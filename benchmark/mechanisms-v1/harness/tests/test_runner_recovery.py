# SPDX-License-Identifier: Apache-2.0
"""Crash/restart tests using only original synthetic fixtures and offline adapters."""
import contextlib
from datetime import timedelta
import io
import os
from pathlib import Path
import subprocess
import tempfile
import json
import shutil
import unittest
from unittest.mock import Mock, patch

import support as S
import grading_runner as runner
import grading_runner as live
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


FAKE = r'''#!/usr/bin/python3
import json, os, pathlib, sys, time, uuid
behaviour = BEHAVIOUR
if "--version" in sys.argv:
    print("codex-cli 0.167.2")
    sys.exit(0)
if sys.argv[1:3] == ["debug", "models"]:
    print(json.dumps({"models": [{"slug": "gpt-6.1-sol", "tool_mode": "code_mode_only",
          "multi_agent_version": "v2", "experimental_supported_tools": ["clock"],
          "apply_patch_tool_type": "freeform"}]}))
    sys.exit(0)
if sys.argv[1:3] == ["debug", "prompt-input"]:
    if behaviour == "exposed_tools":
        print(json.dumps([{"type": "additional_tools", "tools": [
              {"type": "function", "name": "unexpected_tool"}]}]))
    else:
        print(json.dumps([{"type": "message", "role": "developer", "content": []}]))
    sys.exit(0)
home = pathlib.Path(os.environ["HOME"])
packet = pathlib.Path("/packet")
output = pathlib.Path("/out")
previous = home / "conversation.json"
resumed = "resume" in sys.argv
if resumed:
    conversation = json.loads(previous.read_text())
    assert sys.argv[-2] == conversation["id"]
else:
    assert not previous.exists()
    conversation = {"id": str(uuid.uuid4()), "messages": []}
    if behaviour == "duplicate":
        conversation["id"] = "11111111-1111-1111-1111-111111111111"
message = sys.stdin.read()
conversation["messages"].append(message)
previous.write_text(json.dumps(conversation))
print(json.dumps({"type": "thread.started", "thread_id": conversation["id"]}), flush=True)
print(json.dumps({"type": "turn.started"}), flush=True)
observed = {"argv": sys.argv, "env": dict(os.environ), "message": message,
            "repositoryVisible": pathlib.Path(HOST_SENTINEL).exists(),
            "hostConfigVisible": pathlib.Path("/etc/codex").exists()}
(output / "observed.json").write_text(json.dumps(observed))
if behaviour == "timeout":
    time.sleep(10)
if behaviour == "crash":
    os._exit(73)
if behaviour == "malformed":
    print("not an event", flush=True)
    sys.exit(0)
if behaviour == "tool":
    print(json.dumps({"type": "item.completed", "item": {"type": "web_search"}}), flush=True)
    sys.exit(0)
if behaviour == "mismatch" and resumed:
    conversation["id"] = str(uuid.uuid4())
    print(json.dumps({"type": "thread.started", "thread_id": conversation["id"]}), flush=True)
    sys.exit(0)
if behaviour == "invalid" or behaviour == "invalid_first" and not resumed:
    raw = b"not json\n"
elif behaviour in ("pipeline", "invalid_first"):
    question = json.loads((packet / "question.json").read_text())["id"]
    initial = conversation["messages"][0].splitlines()[0].split()
    kind = initial[1]
    if kind == "score":
        result = {"question": question, "output": initial[2], "configuration": "conventional",
                  "mechanism": dict({"M%d" % n: "PASS" for n in range(1, 6)}, evidence={}),
                  "errors": [], "unsure": [], "coveredFacts": [], "notApplicableFacts": [],
                  "clarity": 4, "clarityReason": "Synthetic", "defects": []}
    elif kind == "preference":
        result = {"question": question, "pair": initial[2], "preference": "tie", "preferenceReason": "Synthetic"}
    else:
        result = {"differentTools": "cannot tell", "engine": "cannot tell", "reason": "Synthetic"}
    raw = json.dumps(result).encode()
elif behaviour == "ok":
    raw = b"OK"
else:
    raw = '{"synthetic":"caf\u00e9"}\n'.encode()
if behaviour == "bytes_mismatch":
    (output / "reply.bin").write_bytes(b"changed")
else:
    (output / "reply.bin").write_bytes(raw)
print(json.dumps({"type": "item.completed", "item": {"type": "agent_message", "text": raw.decode()}}), flush=True)
print(json.dumps({"type": "turn.completed", "usage": {}}), flush=True)
'''


def fake_cli(root, behaviour):
    binary_dir = root / "bin"
    binary_dir.mkdir(exist_ok=True)
    binary = binary_dir / "codex"
    binary.write_text(FAKE.replace("BEHAVIOUR", repr(behaviour)).replace(
        "HOST_SENTINEL", repr(str(root / "operator-secret"))))
    binary.chmod(0o755)
    (root / "operator-secret").write_text("synthetic host-only sentinel")
    return binary


@unittest.skipUnless(shutil.which("bwrap"), "Linux bubblewrap required for isolated fake CLI tests")
class AdapterTest(PipelineFixture):
    def adapter(self, behaviour="success", **kwargs):
        binary = fake_cli(self.root, behaviour)
        with patch.dict(os.environ, {"PATH": str(binary.parent) + os.pathsep + os.environ["PATH"]}):
            return live.CodexAdapter(self.root / "state", "codex", **kwargs)

    def packet(self):
        out, doc = self.build()
        return out / "packets" / doc["calls"][0]["token"]

    def test_preflight_rejects_tools_before_session_or_auth(self):
        adapter = self.adapter("exposed_tools")
        with self.assertRaisesRegex(ValueError, "model-visible tools must be empty"):
            adapter.open("G1", "score", self.packet(), session_id="a" * 64)
        self.assertFalse((adapter.root / ("a" * 64)).exists())

    def test_bytes_receipt_isolation_and_fresh_session(self):
        packet = self.packet()
        adapter = self.adapter()
        with patch.dict(os.environ, {"OPENAI_API_KEY": "must-not-pass", "HTTP_PROXY": "must-not-pass"}):
            first = adapter.open("G1", "score", packet, session_id="a" * 64)
            raw = first.reply("Synthetic score")
        receipt = json.loads((first.path / "1/receipt.json").read_text())
        self.assertEqual(bytes.fromhex(receipt["rawHex"]), raw)
        self.assertEqual(raw, '{"synthetic":"caf\u00e9"}\n'.encode())
        self.assertEqual(receipt["toolVersion"], live.VERSIONS["G1"])
        self.assertLessEqual(receipt["startedUTC"], receipt["receivedUTC"])
        observed = json.loads((first.path / "1/observed.json").read_text())
        self.assertFalse(observed["repositoryVisible"])
        self.assertFalse(observed["hostConfigVisible"])
        self.assertNotIn("OPENAI_API_KEY", observed["env"])
        self.assertNotIn("HTTP_PROXY", observed["env"])
        self.assertIn("Synthetic rubric", observed["message"])
        self.assertIn("What does the synthetic shape do?", observed["message"])
        self.assertEqual(observed["argv"].count("--image"), len(list(packet.rglob("*.png"))))
        for option in live.CODEX_CONFIG:
            self.assertIn(option, observed["argv"])
        second = adapter.open("G1", "score", packet, session_id="b" * 64)
        second.reply("Synthetic score")
        other = json.loads((second.path / "1/receipt.json").read_text())
        self.assertNotEqual(receipt["remoteSessionId"], other["remoteSessionId"])
        self.assertEqual(len(json.loads((second.path / "home/conversation.json").read_text())["messages"]), 1)

    def test_exact_resume_fixup_sends_no_packet_again(self):
        packet = self.packet()
        adapter = self.adapter("invalid_first")
        first = adapter.open("G1", "score", packet, session_id="a" * 64)
        token = packet.name
        self.assertEqual(first.reply("Synthetic score " + token), b"not json\n")
        first.close()
        restarted = live.CodexAdapter(adapter.root, adapter.sandbox.binary)
        resumed = restarted.resume("G1", "score", packet, session_id="a" * 64, received=1)
        result = resumed.reply("The reply is invalid:\nsynthetic parse error")
        self.assertEqual(json.loads(result)["output"], token)
        first_receipt = json.loads((first.path / "1/receipt.json").read_text())
        second_receipt = json.loads((first.path / "2/receipt.json").read_text())
        self.assertEqual(first_receipt["remoteSessionId"], second_receipt["remoteSessionId"])
        observed = json.loads((first.path / "2/observed.json").read_text())
        self.assertEqual(observed["message"], "The reply is invalid:\nsynthetic parse error")
        self.assertIn("resume", observed["argv"])
        self.assertNotIn("--image", observed["argv"])
        with self.assertRaisesRegex(ValueError, "one fix-up"):
            resumed.reply("The reply is invalid again")

    def test_timeout_malformed_crash_and_tool_use_are_uncertain(self):
        packet = self.packet()
        for index, behaviour in enumerate(("timeout", "malformed", "crash", "tool", "bytes_mismatch")):
            with self.subTest(behaviour=behaviour):
                adapter = self.adapter(behaviour, timeout=0.3)
                session_id = str(index) * 64
                handle = adapter.open("G1", "score", packet, session_id=session_id)
                with self.assertRaises(live.Uncertain):
                    handle.reply("Synthetic score")
                state = json.loads((handle.path / "state.json").read_text())
                self.assertEqual(state["phase"], "uncertain")
                failure = json.loads((handle.path / "1/uncertain.json").read_text())
                self.assertIsNone(failure["receivedUTC"])
                self.assertEqual(failure["sessionId"], session_id)
                self.assertIn(b"thread.started", (handle.path / "1/stdout.bin").read_bytes())
                with self.assertRaises(live.Uncertain):
                    handle.reply("Synthetic score")
                with self.assertRaises(live.Uncertain):
                    adapter.resume("G1", "score", packet, session_id=session_id, received=0)
                self.assertFalse((handle.path / "2").exists())

    def test_resume_mismatch_never_accepts_different_session(self):
        packet = self.packet()
        adapter = self.adapter("mismatch")
        handle = adapter.open("G1", "score", packet, session_id="a" * 64)
        handle.reply("Synthetic score")
        with self.assertRaises(live.Uncertain):
            handle.reply("The reply is invalid")

    def test_new_call_rejects_reused_remote_id(self):
        packet = self.packet()
        adapter = self.adapter("duplicate")
        first = adapter.open("G1", "score", packet, session_id="a" * 64)
        first.reply("Synthetic score")
        second = adapter.open("G1", "score", packet, session_id="b" * 64)
        with self.assertRaises(live.Uncertain):
            second.reply("Synthetic score")

    def test_interrupted_adapter_send_retains_intent_and_refuses_resume(self):
        packet = self.packet()
        adapter = self.adapter()
        handle = adapter.open("G1", "score", packet, session_id="a" * 64)
        invoke = adapter.sandbox.invoke
        def interrupt(*args):
            invoke(*args)
            raise Interrupted()
        with patch.object(adapter.sandbox, "invoke", side_effect=interrupt), self.assertRaises(Interrupted):
            handle.reply("Synthetic score")
        self.assertEqual(json.loads((handle.path / "state.json").read_text())["phase"], "sending")
        self.assertTrue((handle.path / "1/stdout.bin").exists())
        with self.assertRaises(live.Uncertain):
            adapter.resume("G1", "score", packet, session_id="a" * 64, received=0)

    def test_resume_checks_reply_count_receipts_and_home(self):
        packet = self.packet()
        adapter = self.adapter()
        handle = adapter.open("G1", "score", packet, session_id="a" * 64)
        handle.reply("Synthetic score")
        with self.assertRaisesRegex(live.Uncertain, "reply count"):
            adapter.resume("G1", "score", packet, session_id="a" * 64, received=0)
        (handle.path / "1/reply.bin").write_bytes(b"altered")
        with self.assertRaisesRegex(live.Uncertain, "receipt changed"):
            adapter.resume("G1", "score", packet, session_id="a" * 64, received=1)
        (handle.path / "home/conversation.json").write_text("{}")
        with self.assertRaisesRegex(live.Uncertain, "storage changed"):
            adapter.resume("G1", "score", packet, session_id="a" * 64, received=1)

    def test_restart_before_first_send_is_safe(self):
        packet = self.packet()
        adapter = self.adapter()
        handle = adapter.open("G1", "score", packet, session_id="a" * 64)
        resumed = adapter.resume("G1", "score", packet, session_id="a" * 64, received=0)
        self.assertTrue(resumed.reply("Synthetic score"))
        with self.assertRaises(FileExistsError):
            adapter.open("G1", "score", packet, session_id="a" * 64)
        self.assertFalse((handle.path / "2").exists())

    def test_packet_link_extra_file_and_changed_packet_refused(self):
        packet = self.packet()
        adapter = self.adapter()
        extra = packet / "AGENTS.md"
        extra.write_text("Never load this")
        with self.assertRaisesRegex(ValueError, "unexpected packet"):
            adapter.open("G1", "score", packet, session_id="a" * 64)
        extra.unlink()
        extra.symlink_to(self.root / "operator-secret")
        with self.assertRaisesRegex(ValueError, "symlinks"):
            adapter.open("G1", "score", packet, session_id="a" * 64)
        extra.unlink()
        handle = adapter.open("G1", "score", packet, session_id="a" * 64)
        changed = handle.path / "packet/RUBRIC.md"
        changed.chmod(0o600)
        changed.write_text("changed")
        with self.assertRaisesRegex(ValueError, "packet changed"):
            handle.reply("Synthetic score")

    def test_runner_fixup_integration_with_fake_provider_for_both_labels(self):
        out, doc = self.build()
        adapter = self.adapter("invalid_first")
        class Both:
            def open(inner, grader, kind, packet, *, session_id):
                return adapter.open("G1", kind, packet, session_id=session_id)
            def resume(inner, grader, kind, packet, *, session_id, received):
                return adapter.resume("G1", kind, packet, session_id=session_id, received=received)
        result = runner.run(out, Both(), Publication(), PROMPTS, self.clock)
        self.assertEqual(len(result["calls"]), 24)
        for call in result["calls"]:
            self.assertEqual(len(call["sessions"]), 1)
            self.assertEqual(len(call["sessions"][0]["replies"]), 2)
        self.assertTrue((out / "BLINDING-SEED.txt").exists())
        self.assertEqual(len(list((adapter.root / "remote-ids").iterdir())), 24)

    def test_runner_crash_after_send_does_not_resend_retained_reply(self):
        out, doc = self.build()
        adapter = self.adapter("pipeline")
        def stop(stage):
            if stage == "after-send":
                raise Interrupted()
        with self.assertRaises(Interrupted):
            runner.run(out, adapter, Publication(), PROMPTS, self.clock, _checkpoint=stop)
        self.assertEqual(len(list(adapter.root.glob("*/1/receipt.json"))), 1)
        with self.assertRaisesRegex(ValueError, "uncertain request"):
            runner.run(out, adapter, Publication(), PROMPTS, self.clock)
        self.assertEqual(len(list(adapter.root.glob("*/1/receipt.json"))), 1)
        self.assertFalse((out / "BLINDING-SEED.txt").exists())

    def test_runner_timeout_does_not_allocate_replacement_attempt(self):
        out, doc = self.build()
        adapter = self.adapter("timeout", timeout=0.3)
        with self.assertRaises(live.Uncertain):
            runner.run(out, adapter, Publication(), PROMPTS, self.clock)
        with self.assertRaisesRegex(ValueError, "uncertain request"):
            runner.run(out, adapter, Publication(), PROMPTS, self.clock)
        record = json.loads((out / "RECORD.json").read_text())
        self.assertEqual(len(record["calls"][0]["sessions"]), 1)

    def test_self_test_fake_only_and_dry_no_process(self):
        binary = fake_cli(self.root, "ok")
        base = ["self-test", "--grader", "G1", "--binary", str(binary)]
        with patch.object(subprocess, "Popen", side_effect=AssertionError("dry executed a process")):
            with contextlib.redirect_stdout(io.StringIO()) as printed:
                self.assertEqual(live.self_test_main(base + ["--work", str(self.root / "dry"), "--dry"]), 0)
        plans = json.loads(printed.getvalue())["plans"]
        self.assertEqual(len(plans), 2)
        self.assertEqual(plans[0]["stdin"], "reply with the word OK")
        self.assertEqual(plans[0]["env"], live.ENV)
        auth = self.root / "fake-auth.json"
        auth.write_text('{}')
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(live.self_test_main(base + ["--work", str(self.root / "fake-smoke"),
                                               "--run", "--auth", str(auth)]), 0)
        proof = json.loads((self.root / "fake-smoke/SELF-TEST.json").read_text())
        self.assertEqual(len(set(proof["remoteSessionIds"])), 2)


class NativeCodexToolsTest(unittest.TestCase):
    """Real Codex only; no credentials, model requests or network namespace."""

    def setUp(self):
        binary = os.environ.get("CODEX_NATIVE_BINARY") or shutil.which("codex")
        if binary is None:
            self.skipTest("Codex is not installed; native offline tool diagnostic unavailable")
        if Path(binary).resolve().name == "mise":
            binary = subprocess.check_output(["mise", "which", "codex"], text=True).strip()
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.adapter = live.CodexAdapter(self.root / "state", binary)
        invoke = self.adapter.sandbox.invoke
        def offline_only(home, packet, output, args, message, timeout, *, network=True):
            self.assertFalse(network, "native regression must never enable network")
            self.assertEqual(message, b"", "native regression must not submit a prompt")
            self.assertTrue(args == ["/tool", "--version"] or args[1:3] in (
                ["debug", "models"], ["debug", "prompt-input"]), args)
            return invoke(home, packet, output, args, message, timeout, network=False)
        self.guard = patch.object(self.adapter.sandbox, "invoke", side_effect=offline_only)
        self.guard.start()
        self.addCleanup(self.guard.stop)
        for name in ("home/codex", "packet", "out"):
            (self.root / name).mkdir(parents=True)

    def diagnostic(self, name, args):
        output = self.root / name
        output.mkdir()
        sandbox = self.adapter.sandbox
        command = sandbox.command(self.root / "home", self.root / "packet", output, args,
                                  network=False)
        self.assertNotIn("--share-net", command)
        for key, value in live.ENV.items():
            self.assertIn(["--setenv", key, value], [command[index:index + 3]
                          for index in range(len(command) - 2)])
        sandbox.invoke(self.root / "home", self.root / "packet", output, args, b"", 30,
                       network=False)
        return (output / "stdout.bin").read_bytes()

    def test_native_exact_fresh_and_fixup_configuration_has_no_tools(self):
        self.assertEqual(self.adapter.preflight(), live.VERSIONS["G1"])
        live.durable_json(self.root / "home/codex/grader-model.json", self.adapter.catalog)
        (self.root / "packet/output").mkdir()
        live.pack.png(self.root / "packet/output/still-1.png", bytes((80, 90, 100)) * 4,
                      width=2, height=2)
        for remote_id in (None, "11111111-1111-1111-1111-111111111111"):
            with self.subTest(remote_id=remote_id):
                images = ["output/still-1.png"] if remote_id is None else []
                argv = live.codex_argv(images, remote_id)
                diagnostic = live.codex_diagnostic_argv(argv)
                config = [argv[index + 1] for index, arg in enumerate(argv) if arg == "-c"]
                self.assertEqual(config, live.CODEX_CONFIG)
                self.assertEqual(diagnostic, ["/tool", "debug", "prompt-input"] +
                                 [part for value in config for part in ("-c", value)] +
                                 [part for image in images for part in ("--image", "/packet/" + image)])
                raw = self.diagnostic("fresh" if remote_id is None else "fixup", diagnostic)
                self.assertEqual(live.codex_tool_definitions(raw), [])
                self.assertFalse(any(item.get("tools") for item in json.loads(raw)))

    def test_native_metadata_override_is_removed_not_just_feature_disabled(self):
        raw = self.diagnostic("bundled", ["/tool", "debug", "models"])
        original = next(model for model in json.loads(raw)["models"]
                        if model["slug"] == live.MODELS["G1"])
        self.assertEqual(original["tool_mode"], "code_mode_only")
        self.assertEqual(original["multi_agent_version"], "v2")
        self.assertIn("clock", original["experimental_supported_tools"])
        home = self.root / "home"
        live.durable_json(home / "codex/grader-model.json", {"models": [original]})
        diagnostic = live.codex_diagnostic_argv(live.codex_argv())
        exposed = live.codex_tool_definitions(self.diagnostic("exposed", diagnostic))
        self.assertIn("functions.exec", exposed)
        sanitized = live.prepare_codex_policy(self.adapter.sandbox, home,
                                             self.root / "packet", self.root / "out")
        expected = dict(original)
        expected.update(live.CODEX_MODEL_POLICY)
        self.assertEqual(sanitized, {"models": [expected]})
        self.assertEqual(live.codex_tool_definitions(self.diagnostic("sanitized", diagnostic)), [])
        effective = json.loads(self.diagnostic("static", ["/tool", "debug", "models", "-c",
                              'model_catalog_json="/home/grader/codex/grader-model.json"']))
        for field, value in live.CODEX_MODEL_POLICY.items():
            self.assertEqual(effective["models"][0].get(field), value)
            if value is None and field not in effective["models"][0]:
                del expected[field]
        self.assertEqual(effective, {"models": [expected]})

    def test_native_preflight_fails_closed_if_metadata_sanitizer_regresses(self):
        with patch.object(live, "CODEX_MODEL_POLICY", {}):
            with self.assertRaisesRegex(ValueError, "model-visible tools must be empty"):
                self.adapter.preflight()


class BlockedTest(unittest.TestCase):
    def test_tool_diagnostic_rejects_unknown_and_empty_output(self):
        for raw in (b"[]", b"{}", b'[{"type":"unknown"}]', b'[{"type":"additional_tools"}]'):
            with self.subTest(raw=raw), self.assertRaises((ValueError, KeyError)):
                live.codex_tool_definitions(raw)
        self.assertEqual(live.codex_tool_definitions(json.dumps([
            {"type": "additional_tools", "tools": [{"type": "namespace", "name": "outer",
             "tools": [{"type": "function", "name": "spawn"}]}]}])), ["outer.spawn"])

    def test_antigravity_proposal_never_spawns(self):
        adapter = live.AntigravityAdapter()
        with patch.object(subprocess, "Popen", side_effect=AssertionError("unsafe G2 dispatch")):
            with self.assertRaisesRegex(ValueError, "UNVERIFIED G2"):
                adapter.open("G2", "score", Path("not-read"), session_id="a" * 64)
            with self.assertRaises(live.Uncertain):
                adapter.resume("G2", "score", Path("not-read"), session_id="a" * 64, received=1)
        args = live.antigravity_argv("exact-id")
        self.assertIn("gemini-4-argon", args)
        self.assertEqual(args[-2:], ["--conversation", "exact-id"])
        self.assertNotIn("--continue", args)

    def test_live_cli_blocks_before_reading_pack_or_prompts(self):
        with patch.object(live.LiveAdapter, "__init__", return_value=None), \
                patch.object(live.LiveAdapter, "preflight", side_effect=ValueError(live.G2_BLOCKER)), \
                patch.object(runner, "load_pack", side_effect=AssertionError("pack was read")), \
                contextlib.redirect_stderr(io.StringIO()) as errors:
            with self.assertRaises(SystemExit) as result:
                runner.main(["not-read", "--live", "--adapter-state", "not-created", "--codex-bin", "not-run",
                             "--public-branch", "main"])
        self.assertEqual(result.exception.code, 2)
        self.assertIn("UNVERIFIED G2", errors.getvalue())

    def test_no_sandbox_fallback(self):
        with patch.object(shutil, "which", return_value=None), tempfile.TemporaryDirectory() as temp:
            binary = Path(temp) / "fake"
            binary.touch()
            with self.assertRaisesRegex(ValueError, "no unsandboxed fallback"):
                live.Bubblewrap(binary)
