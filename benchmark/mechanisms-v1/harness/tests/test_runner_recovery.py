# SPDX-License-Identifier: Apache-2.0
"""Crash/restart tests using only original synthetic fixtures and offline adapters."""
from datetime import timedelta
import json
import shutil
import unittest
from unittest.mock import Mock, patch

import support as S
import grading_runner as runner
from test_pack_runner import PipelineFixture, Publication, PROMPTS, entries


class Interrupted(BaseException):
    """Simulate abrupt process exit, including outside Exception handlers."""


class RecoveryTest(PipelineFixture):
    def setup_recovery(self):
        out, doc = self.build()
        first = runner.pack.call_order(S.SEED, 'G1', doc['calls'])[0]
        normal = entries(doc)
        good = normal[0]['replies'][0]
        overrides = {('G1', first['kind'], first['id']): [['{}', '{}'], ['{}', good]]}
        self.script = entries(doc, overrides)
        # Identical event times make RECORD byte comparisons meaningful. Real
        # downtime advances later timestamps; it must never rewrite old ones.
        self.now = self.clock.time + timedelta(seconds=10)
        self.fixed = lambda: self.now
        baseline = self.root / 'baseline'
        shutil.copytree(out, baseline)
        adapter = runner.RecordedAdapter(self.script)
        self.expected = runner.run(baseline, adapter, Publication(), PROMPTS, self.fixed)
        self.expected_bytes = (baseline / 'RECORD.json').read_bytes()
        self.expected_messages = adapter.messages
        key = S.score.load_key(S.write_key(self.root, self.key))
        self.expected_score = S.score.analyse(S.score.load_input(baseline, key), key)
        self.key_loaded = key
        return out

    def stop_at(self, stage, occurrence=1):
        count = 0
        def checkpoint(actual):
            nonlocal count
            if actual == stage:
                count += 1
                if count == occurrence:
                    raise Interrupted(stage)
        return checkpoint

    def assert_complete(self, out, messages):
        self.assertEqual((out / 'RECORD.json').read_bytes(), self.expected_bytes)
        self.assertEqual(messages, self.expected_messages)
        self.assertEqual(S.score.analyse(S.score.load_input(out, self.key_loaded), self.key_loaded),
                         self.expected_score)
        files = [r['file'] for c in self.expected['calls'] for s in c['sessions'] for r in s['replies']]
        self.assertEqual(sorted(files), sorted(p.relative_to(out).as_posix() for p in (out / 'replies').rglob('*.txt')))
        self.assertTrue(json.loads((out / 'RUNNER-STATE.json').read_text())['completed'])

    def test_each_safe_boundary_resumes_without_duplicate_or_lost_attempt(self):
        pristine = self.setup_recovery()
        boundaries = [('before-claim', 1), ('after-claim', 1), ('before-open', 1),
                      ('before-send', 1), ('after-receipt', 1), ('after-reply-file', 1),
                      ('after-record', 1), ('after-record', 2), ('after-record', 4)]
        for i, (stage, occurrence) in enumerate(boundaries):
            with self.subTest(stage=stage, occurrence=occurrence):
                out = self.root / f'restart-{i}'
                shutil.copytree(pristine, out)
                first = runner.RecordedAdapter(self.script)
                with self.assertRaises(Interrupted):
                    runner.run(out, first, Publication(), PROMPTS, self.fixed,
                               _checkpoint=self.stop_at(stage, occurrence))
                second = runner.RecordedAdapter(self.script)  # new process/adapter state
                runner.run(out, second, Publication(), PROMPTS, self.fixed)
                self.assert_complete(out, first.messages + second.messages)

    def test_uncertain_send_requires_evidence_then_reconciles_without_resend(self):
        out = self.setup_recovery()
        first = runner.RecordedAdapter(self.script)
        with self.assertRaises(Interrupted):
            runner.run(out, first, Publication(), PROMPTS, self.fixed,
                       _checkpoint=self.stop_at('after-send'))
        second = runner.RecordedAdapter(self.script)
        with self.assertRaisesRegex(ValueError, 'uncertain request.*operator recovery'):
            runner.run(out, second, Publication(), PROMPTS, self.fixed)
        self.assertFalse(second.messages)
        self.assertFalse((out / 'BLINDING-SEED.txt').exists())
        # Explicit operator recovery, ONLY with independently retained exact
        # bytes and receipt time. Here the offline fixture is that evidence.
        state = json.loads((out / 'RUNNER-STATE.json').read_text())
        active = state['active']
        receipt = {'sessionId': active['sessionId'], 'file': active['file'],
                   'receivedUTC': self.now.isoformat(), 'rawHex': b'{}'.hex()}
        runner.durable_json((out / active['file']).with_suffix('.receipt.json'), receipt)
        runner.run(out, second, Publication(), PROMPTS, self.fixed)
        self.assert_complete(out, first.messages + second.messages)

    def test_resume_keeps_real_receipt_time_and_guess_gate(self):
        out = self.setup_recovery()
        first = runner.RecordedAdapter(self.script)
        with self.assertRaises(Interrupted):
            runner.run(out, first, Publication(), PROMPTS, self.fixed,
                       _checkpoint=self.stop_at('after-receipt'))
        receipt = json.loads(next((out / 'replies').rglob('*.receipt.json')).read_text())
        self.now += timedelta(hours=1)
        runner.run(out, runner.RecordedAdapter(self.script), Publication(), PROMPTS, self.fixed)
        record = json.loads((out / 'RECORD.json').read_text())
        self.assertEqual(record['calls'][0]['sessions'][0]['replies'][0]['receivedUTC'], receipt['receivedUTC'])
        for i, call in enumerate(record['calls']):
            if call['kind'] == 'guess':
                stored = record['calls'][i-1]['sessions'][-1]['replies'][-1]['receivedUTC']
                self.assertTrue(all(s['startedUTC'] >= stored for s in call['sessions']))
        self.assertFalse(S.score.load_input(out, self.key_loaded)['record']['timing'])

    def test_resume_rejects_backward_clock_before_adapter(self):
        out = self.setup_recovery()
        with self.assertRaises(Interrupted):
            runner.run(out, runner.RecordedAdapter(self.script), Publication(), PROMPTS, self.fixed,
                       _checkpoint=self.stop_at('after-record'))
        self.now -= timedelta(seconds=1)
        adapter = Mock()
        with self.assertRaisesRegex(ValueError, 'backwards'):
            runner.run(out, adapter, Publication(), PROMPTS, self.fixed)
        adapter.open.assert_not_called()
        adapter.resume.assert_not_called()

    def test_changed_prompts_and_proof_refused_on_resume(self):
        out = self.setup_recovery()
        with self.assertRaises(Interrupted):
            runner.run(out, runner.RecordedAdapter(self.script), Publication(), PROMPTS, self.fixed,
                       _checkpoint=self.stop_at('after-record'))
        for change in ('prompt', 'proof'):
            with self.subTest(change=change):
                prompts = dict(PROMPTS)
                if change == 'prompt':
                    prompts['score'] += ' changed'
                else:
                    proof = json.loads((out / 'PUBLICATION.json').read_text())
                    proof['observedUTC'] = (self.now + timedelta(seconds=1)).isoformat()
                    runner.durable_json(out / 'PUBLICATION.json', proof)
                adapter = Mock()
                with self.assertRaisesRegex(ValueError, 'changed across resume'):
                    runner.run(out, adapter, Publication(), prompts, self.fixed)
                adapter.open.assert_not_called()
                adapter.resume.assert_not_called()

    def test_completed_is_idempotent_even_without_seed_release(self):
        out = self.setup_recovery()
        runner.run(out, runner.RecordedAdapter(self.script), Publication(), PROMPTS, self.fixed)
        for absent in (False, True):
            if absent:
                (out / 'BLINDING-SEED.txt').unlink()
            adapter, pub = Mock(), Mock()
            self.assertEqual(runner.run(out, adapter, pub, PROMPTS, self.fixed), self.expected)
            adapter.open.assert_not_called()
            adapter.resume.assert_not_called()
            pub.verify.assert_not_called()
            self.assertEqual((out / 'BLINDING-SEED.txt').read_text().strip(), S.SEED.hex())

    def test_open_failure_is_uncertain_and_never_reopens(self):
        out = self.setup_recovery()
        adapter = Mock()
        adapter.open.side_effect = RuntimeError('lost open response')
        with self.assertRaises(RuntimeError):
            runner.run(out, adapter, Publication(), PROMPTS, self.fixed)
        with self.assertRaisesRegex(ValueError, 'uncertain session open'):
            runner.run(out, adapter, Publication(), PROMPTS, self.fixed)
        adapter.open.assert_called_once()

    def test_record_replacement_failure_reconciles_write_ahead_state(self):
        out = self.setup_recovery()
        original = runner.durable_json
        def write(path, value):
            if path.name == 'RECORD.json' and value['calls'] and value['calls'][0]['sessions'][0]['replies']:
                raise Interrupted('record replacement')
            return original(path, value)
        first = runner.RecordedAdapter(self.script)
        with patch.object(runner, 'durable_json', side_effect=write), self.assertRaises(Interrupted):
            runner.run(out, first, Publication(), PROMPTS, self.fixed)
        second = runner.RecordedAdapter(self.script)
        runner.run(out, second, Publication(), PROMPTS, self.fixed)
        self.assert_complete(out, first.messages + second.messages)

    def test_partial_receipt_write_is_flagged_never_retried(self):
        out = self.setup_recovery()
        original = runner.durable_json
        def write(path, value):
            if path.name.endswith('.receipt.json'):
                path.with_suffix('.abandoned.tmp').write_text('{"rawHex":')
                raise Interrupted('receipt write')
            return original(path, value)
        first = runner.RecordedAdapter(self.script)
        with patch.object(runner, 'durable_json', side_effect=write), self.assertRaises(Interrupted):
            runner.run(out, first, Publication(), PROMPTS, self.fixed)
        second = runner.RecordedAdapter(self.script)
        with self.assertRaisesRegex(ValueError, 'uncertain request'):
            runner.run(out, second, Publication(), PROMPTS, self.fixed)
        self.assertEqual(len(first.messages), 1)
        self.assertFalse(second.messages)

    def test_concurrent_driver_cannot_open_or_send(self):
        out = self.setup_recovery()
        base = runner.RecordedAdapter(self.script)
        blocked = Mock()
        class Contender:
            def open(inner, grader, kind, packet, *, session_id):
                with self.assertRaisesRegex(ValueError, 'active in another process'):
                    runner.run(out, blocked, Publication(), PROMPTS, self.fixed)
                return base.open(grader, kind, packet, session_id=session_id)
        runner.run(out, Contender(), Publication(), PROMPTS, self.fixed)
        blocked.open.assert_not_called()
        blocked.resume.assert_not_called()
        self.assert_complete(out, base.messages)

    def test_changed_saved_reply_is_flagged_before_resume(self):
        out = self.setup_recovery()
        with self.assertRaises(Interrupted):
            runner.run(out, runner.RecordedAdapter(self.script), Publication(), PROMPTS, self.fixed,
                       _checkpoint=self.stop_at('after-record'))
        next((out / 'replies').rglob('*.txt')).write_bytes(b'changed')
        adapter = Mock()
        with self.assertRaisesRegex(ValueError, 'differs from receipt'):
            runner.run(out, adapter, Publication(), PROMPTS, self.fixed)
        adapter.open.assert_not_called()
        adapter.resume.assert_not_called()

    def test_process_exit_releases_lock_and_reconciles_reply(self):
        import os
        out = self.setup_recovery()
        pid = os.fork()
        if pid == 0:
            def exit_after_reply(stage):
                if stage == 'after-reply-file':
                    os._exit(71)
            try:
                runner.run(out, runner.RecordedAdapter(self.script), Publication(), PROMPTS, self.fixed,
                           _checkpoint=exit_after_reply)
            finally:
                os._exit(72)
        _, status = os.waitpid(pid, 0)
        self.assertEqual(os.waitstatus_to_exitcode(status), 71)
        second = runner.RecordedAdapter(self.script)
        runner.run(out, second, Publication(), PROMPTS, self.fixed)
        self.assert_complete(out, self.expected_messages[:1] + second.messages)

    def test_resume_before_guess_enforces_stored_preference_time(self):
        out = self.setup_recovery()
        attempts = 0
        for call in self.expected['calls']:
            attempts += sum(len(s['replies']) for s in call['sessions'])
            if call['kind'] == 'preference':
                break
        first = runner.RecordedAdapter(self.script)
        with self.assertRaises(Interrupted):
            runner.run(out, first, Publication(), PROMPTS, self.fixed,
                       _checkpoint=self.stop_at('after-record', attempts))
        stored_time = self.now
        self.now -= timedelta(seconds=1)
        blocked = Mock()
        with self.assertRaisesRegex(ValueError, 'backwards'):
            runner.run(out, blocked, Publication(), PROMPTS, self.fixed)
        blocked.open.assert_not_called()
        blocked.resume.assert_not_called()
        self.now = stored_time
        second = runner.RecordedAdapter(self.script)
        runner.run(out, second, Publication(), PROMPTS, self.fixed)
        self.assert_complete(out, first.messages + second.messages)
