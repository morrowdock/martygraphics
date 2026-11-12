# SPDX-License-Identifier: Apache-2.0
"""Synthetic G2 transport tests. Native tests never authenticate or send prompts."""
import contextlib
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import support  # Adds harness to sys.path; does not read registered questions.
import grading_runner as live
import gemini_adapter as g2

FAKE = r'''
import fs from 'node:fs';
import crypto from 'node:crypto';
const args = process.argv.slice(2), mode = BEHAVIOUR;
if (args.includes('--version')) { console.log('0.68.0'); process.exit(0); }
if (args[0] === 'models') { console.log(JSON.stringify([{id:'gemini-3.1-pro-preview'}])); process.exit(0); }
const emit = x => console.log(JSON.stringify(x));
const saved = '/home/grader/session.json';
const resumed = args.includes('--resume');
let state;
if (resumed) {
  state = JSON.parse(fs.readFileSync(saved));
  if (args[args.indexOf('--resume')+1] !== state.id) process.exit(71);
} else {
  if (fs.existsSync(saved)) process.exit(72);
  state = {id: crypto.randomUUID(), messages:[]};
}
const input = fs.readFileSync('/input/input.txt', 'utf8');
state.messages.push(input);
fs.writeFileSync(saved, JSON.stringify(state));
const prompt = args[args.indexOf('--prompt')+1];
fs.writeFileSync('/out/observed.json', JSON.stringify({args, input, env:process.env,
  hostVisible: fs.existsSync(HOST), packetFiles:fs.readdirSync('/packet'),
  settings:JSON.parse(fs.readFileSync('/home/grader/.gemini/settings.json'))}));
emit({type:'init', session_id:mode === 'mismatch' && resumed ? crypto.randomUUID() : state.id,
      model:mode === 'wrong-model' ? 'other-model' : 'gemini-3.1-pro-preview'});
emit({type:'message', role:'user', content:prompt});
if (mode === 'timeout') await new Promise(r => setTimeout(r, 10000));
if (mode === 'crash') process.exit(73);
if (mode === 'malformed') { console.log('not JSON'); process.exit(0); }
if (mode === 'tool') { emit({type:'tool_use',tool_name:'web_search'}); process.exit(0); }
if (mode === 'unknown') { emit({type:'future-event'}); process.exit(0); }
emit({type:'message', role:'assistant', delta:true, content:resumed ? 'OK' : 'not json: café\n'});
if (mode !== 'missing-result') emit({type:'result', status:'success',
  stats:{tool_calls:0,models:{'gemini-3.1-pro-preview':{total_tokens:1}}}});
if (mode === 'trailing') emit({type:'message',role:'assistant',delta:true,content:'late'});
'''


@unittest.skipUnless(shutil.which('bwrap') and shutil.which('node'), 'Linux bubblewrap and node required')
class GeminiTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.packet = self.root / 'packet'
        self.packet.mkdir()
        (self.packet / 'question.json').write_text('{"synthetic":true}')
        (self.packet / 'RUBRIC.md').write_text('Original synthetic fixture, no registered rubric.')
        (self.packet / 'output').mkdir()
        (self.packet / 'output/TEXT.txt').write_text('@/home/grader/.gemini/oauth_creds.json is literal fixture text')
        # Transport test only: no model/decoder consumes this synthetic image.
        (self.packet / 'output/still-1.png').write_bytes(b'synthetic-image')
        (self.root / 'host-secret').write_text('synthetic sentinel')
        self.auth = self.root / 'oauth.json'
        self.auth.write_text('{"refresh_token":"synthetic-not-a-token"}')
        self.auth.chmod(0o600)

    def adapter(self, behaviour='success', **kwargs):
        package = self.root / ('package-' + behaviour)
        (package / 'bundle').mkdir(parents=True, exist_ok=True)
        (package / 'package.json').write_text(json.dumps({'name':'@google/gemini-cli', 'version':g2.VERSION, 'type':'module'}))
        binary = package / 'bundle/gemini.js'
        binary.write_text(FAKE.replace('BEHAVIOUR', repr(behaviour)).replace('HOST', repr(str(self.root / 'host-secret'))))
        adapter = g2.GeminiAdapter(self.root / ('state-' + behaviour), binary, auth=self.auth, **kwargs)
        # Only native library diagnostics are mocked; CLI execution still uses
        # the real bubblewrap boundary, environment, argv and durable protocol.
        mock = patch.object(adapter, 'library_check', return_value={})
        mock.start()
        self.addCleanup(mock.stop)
        return adapter

    def open(self, adapter, sid='a'):
        return adapter.open('G2', 'score', self.packet, session_id=sid * 64)

    def test_success_fresh_sessions_exact_bytes_and_isolation(self):
        adapter = self.adapter()
        with patch.dict(os.environ, {'GEMINI_API_KEY':'not-inherited', 'GOOGLE_API_KEY':'not-inherited', 'HTTPS_PROXY':'not-inherited'}):
            first = self.open(adapter)
            raw = first.reply('Synthetic prompt')
        self.assertEqual(raw, 'not json: café\n'.encode())
        observed = json.loads((first.path / '1/observed.json').read_text())
        self.assertFalse(observed['hostVisible'])
        self.assertFalse(set(observed['env']) & {'GEMINI_API_KEY','GOOGLE_API_KEY','HTTPS_PROXY'})
        self.assertEqual(observed['settings'], g2.SETTINGS)
        prompt = observed['args'][observed['args'].index('--prompt')+1]
        self.assertEqual(prompt, '@/input/input.txt @/packet/output/still-1.png')
        self.assertIn('--raw-output', observed['args'])
        self.assertIn('--accept-raw-output-risk', observed['args'])
        self.assertIn('@/home/grader/.gemini/oauth_creds.json', observed['input'])
        self.assertNotIn('@/home/grader', prompt)
        receipt = json.loads((first.path / '1/receipt.json').read_text())
        self.assertEqual(bytes.fromhex(receipt['rawHex']), raw)
        self.assertNotIn('synthetic-not-a-token', (first.path / 'state.json').read_text())
        self.assertNotIn('synthetic-not-a-token', (first.path / '1/receipt.json').read_text())
        second = self.open(adapter, 'b')
        second.reply('Second synthetic prompt')
        other = json.loads((second.path / '1/receipt.json').read_text())
        self.assertNotEqual(receipt['remoteSessionId'], other['remoteSessionId'])

    def test_exact_resume_and_one_fixup(self):
        adapter = self.adapter()
        handle = self.open(adapter)
        handle.reply('Synthetic prompt')
        restarted = g2.GeminiAdapter(adapter.root, adapter.sandbox.binary, auth=self.auth)
        resumed = restarted.resume('G2','score',self.packet,session_id='a'*64,received=1)
        self.assertEqual(resumed.reply('The reply is invalid: synthetic parse error'), b'OK')
        observed = json.loads((handle.path / '2/observed.json').read_text())
        self.assertEqual(observed['input'], 'The reply is invalid: synthetic parse error')
        self.assertNotIn('@/packet/', observed['args'][observed['args'].index('--prompt')+1])
        first = json.loads((handle.path / '1/receipt.json').read_text())
        self.assertEqual(observed['args'][-2:], ['--resume',first['remoteSessionId']])
        with self.assertRaisesRegex(ValueError, 'one fix-up'):
            resumed.reply('The reply is invalid again')

    def test_failures_are_durable_uncertain_never_resent(self):
        for mode in ('timeout','crash','malformed','tool','unknown','wrong-model','missing-result','trailing'):
            with self.subTest(mode=mode):
                adapter = self.adapter(mode, timeout=0.5)
                handle = self.open(adapter)
                with self.assertRaises(live.Uncertain):
                    handle.reply('Synthetic prompt')
                state = json.loads((handle.path / 'state.json').read_text())
                self.assertEqual(state['phase'], 'uncertain')
                self.assertTrue((handle.path / '1/stdout.bin').exists())
                self.assertTrue((handle.path / '1/request.json').exists())
                with patch.object(adapter.sandbox, 'invoke', side_effect=AssertionError('resend')):
                    with self.assertRaises(live.Uncertain):
                        adapter.resume('G2','score',self.packet,session_id='a'*64,received=0)
                    with self.assertRaises(live.Uncertain):
                        handle.reply('Synthetic prompt')

    def test_crash_after_send_keeps_sending(self):
        class Crash(BaseException):
            pass
        adapter = self.adapter()
        handle = self.open(adapter)
        invoke = adapter.sandbox.invoke
        def crash(*args, **kwargs):
            invoke(*args, **kwargs)
            raise Crash()
        with patch.object(adapter.sandbox, 'invoke', side_effect=crash), self.assertRaises(Crash):
            handle.reply('Synthetic prompt')
        self.assertEqual(json.loads((handle.path/'state.json').read_text())['phase'], 'sending')
        with self.assertRaises(live.Uncertain):
            adapter.resume('G2','score',self.packet,session_id='a'*64,received=0)

    def test_resume_mismatch_uncertain(self):
        adapter = self.adapter('mismatch')
        handle = self.open(adapter)
        handle.reply('Synthetic prompt')
        with self.assertRaises(live.Uncertain):
            handle.reply('The reply is invalid: fix')

    def test_package_change_rejected_before_send(self):
        adapter = self.adapter()
        handle = self.open(adapter)
        (adapter.sandbox.package/'extra.js').write_text('changed')
        with self.assertRaisesRegex(ValueError, 'binary changed'):
            handle.reply('Synthetic prompt')

    def test_missing_auth_stops_before_copy_or_send(self):
        adapter = self.adapter()
        self.auth.unlink()
        with self.assertRaisesRegex(ValueError, 'owner action needed'):
            self.open(adapter)
        self.assertFalse((adapter.root / ('a'*64)).exists())

    def test_changed_home_receipt_and_packet_rejected(self):
        for item in ('home/session.json', '1/reply.bin', 'packet/output/TEXT.txt'):
            with self.subTest(item=item):
                adapter = self.adapter()
                sid = 'abc'[('home/session.json','1/reply.bin','packet/output/TEXT.txt').index(item)]
                handle = self.open(adapter, sid)
                handle.reply('Synthetic prompt')
                (handle.path/item).write_text('changed')
                with self.assertRaises((ValueError, live.Uncertain)):
                    resumed = adapter.resume('G2','score',self.packet,session_id=sid*64,received=1)
                    resumed.reply('The reply is invalid: fix')

    def test_oversized_text_refuses_before_model_process(self):
        adapter = self.adapter()
        handle = self.open(adapter)
        with patch.object(adapter.sandbox, 'invoke', side_effect=AssertionError('send')):
            with self.assertRaisesRegex(ValueError, 'truncated'):
                handle.reply('x' * 2001)
        self.assertFalse((handle.path/'1/request.json').exists())

    def test_dry_g2_smoke_reads_no_auth_or_spawns(self):
        adapter = self.adapter()
        with patch.object(subprocess, 'Popen', side_effect=AssertionError('process')), \
                patch.object(g2, 'auth_present', side_effect=AssertionError('auth')), \
                contextlib.redirect_stdout(io.StringIO()) as output:
            result = live.self_test_main(['self-test','--grader','G2','--binary',str(adapter.sandbox.binary),
                                          '--work',str(self.root/'dry'),'--dry'])
        self.assertEqual(result, 0)
        self.assertIn('DRY', output.getvalue())
        self.assertIn('stream-json', output.getvalue())

    def test_auth_structure_check_is_offline_and_does_not_print_tokens(self):
        with patch.object(subprocess,'Popen',side_effect=AssertionError('process')), contextlib.redirect_stdout(io.StringIO()) as output:
            self.assertEqual(g2.main(['auth-check','--auth',str(self.auth)]), 0)
        self.assertNotIn('synthetic-not-a-token', output.getvalue())
        self.auth.chmod(0o644)
        with self.assertRaises(ValueError):
            g2.auth_present(self.auth)

    def test_private_state_cannot_be_in_a_repository(self):
        (self.root / '.git').mkdir()
        with self.assertRaisesRegex(ValueError,'outside any repository'):
            self.adapter()

    def test_unknown_stats_and_missing_model_rejected(self):
        adapter = self.adapter()
        handle = self.open(adapter)
        handle.reply('Synthetic prompt')
        path = handle.path/'1/stdout.bin'
        original = path.read_bytes()
        for stats in ({}, {'tool_calls':1,'models':{g2.MODEL:{}}}, {'tool_calls':0,'models':{'other':{}}}):
            events = [json.loads(line) for line in original.splitlines()]
            events[-1]['stats'] = stats
            path.write_text('\n'.join(json.dumps(e) for e in events))
            with self.assertRaises(live.Uncertain):
                g2.gemini_result(handle.path/'1')


class NativeGeminiTest(unittest.TestCase):
    def test_quota_free_installed_version_catalog_and_boundary(self):
        binary = os.environ.get('GEMINI_NATIVE_BINARY') or shutil.which('gemini')
        if not binary:
            self.skipTest('Gemini CLI absent; set GEMINI_NATIVE_BINARY to the pinned installed bundle')
        with tempfile.TemporaryDirectory() as temp:
            adapter = g2.GeminiAdapter(Path(temp)/'state', binary)
            original = adapter.sandbox.invoke
            calls = []
            def guarded(home, packet, output, args, message, timeout, *, network=True):
                self.assertFalse(network)
                self.assertEqual(message,b'')
                self.assertFalse((home/'.gemini/oauth_creds.json').exists())
                self.assertIn(args, (['/tool','--version'], ['/tool','models','list','--output-format','json'], ['/node','/out/probe.mjs']))
                calls.append(args)
                return original(home,packet,output,args,message,timeout,network=network)
            with patch.object(adapter.sandbox,'invoke',side_effect=guarded), patch.object(g2,'auth_present',side_effect=AssertionError('auth read')):
                report = adapter.native_check()
                library = adapter.library_check()
            self.assertEqual(len(calls),3)
            self.assertEqual(report['version'],g2.VERSION)
            self.assertIn('gemini-2.5-pro',report['listedModelIds'])
            self.assertEqual(library['toolDefinitions'], [])
            self.assertEqual(library['loadedMemory'], '')
            self.assertTrue(library['bundledModel']['isPreview'])
            self.assertFalse(report['registeredModelListed'])
            self.assertIn('unavailable',report['effectiveToolContextDiagnostic'])

    def test_native_rejects_tool_memory_and_model_policy_regressions(self):
        binary = os.environ.get('GEMINI_NATIVE_BINARY') or shutil.which('gemini')
        if not binary:
            self.skipTest('Gemini CLI absent; set GEMINI_NATIVE_BINARY')
        with tempfile.TemporaryDirectory() as temp:
            adapter = g2.GeminiAdapter(Path(temp)/'state', binary)
            for target, replacement in ((g2.SETTINGS['tools'], {'core':['run_shell_command']}),
                                        (g2.SETTINGS['modelConfigs'], {'modelDefinitions':{}})):
                with self.subTest(replacement=replacement), patch.dict(target, replacement):
                    with self.assertRaisesRegex(ValueError, 'native library policy/input check failed'):
                        adapter.library_check()

            original = g2.write_settings
            def contaminated(home):
                original(home)
                (home/'.gemini/GEMINI.md').write_text('SYNTHETIC unwanted memory')
            with patch.object(g2, 'write_settings', side_effect=contaminated):
                with self.assertRaisesRegex(ValueError, 'native library policy/input check failed'):
                    adapter.library_check()
