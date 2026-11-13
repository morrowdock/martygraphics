# SPDX-License-Identifier: Apache-2.0
"""Synthetic G2 tests. Native startup uses stub auth, never credentials or network."""
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
const model = process.env.MARTYGRAPHICS_GEMINI_MODEL;
if (args.includes('--version')) { console.log('0.68.0'); process.exit(0); }
if (args[0] === 'models') { console.log(JSON.stringify([{id:model}])); process.exit(0); }
const {Config} = await import('./chunk-RCB6BI5H.js');
const config = new Config();
await config.refreshAuth();
config.contentGenerator.generateContent({model:model,
  config:{thinkingConfig:{thinkingLevel:'HIGH'},tools:[]}});
const emit = x => console.log(JSON.stringify(x));
if (mode === 'refused') { emit({type:'result',status:'error'}); process.exit(1); }
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
      model:mode === 'wrong-model' ? 'other-model' : model});
emit({type:'message', role:'user', content:prompt});
if (mode === 'timeout') await new Promise(r => setTimeout(r, 10000));
if (mode === 'crash') process.exit(73);
if (mode === 'malformed') { console.log('not JSON'); process.exit(0); }
if (mode === 'tool') { emit({type:'tool_use',tool_name:'web_search'}); process.exit(0); }
if (mode === 'unknown') { emit({type:'future-event'}); process.exit(0); }
emit({type:'message', role:'assistant', delta:true, content:resumed ? 'OK' : 'not json: café\n'});
if (mode !== 'missing-result') emit({type:'result', status:'success',
  stats:{tool_calls:0,models:{[model]:{total_tokens:1}}}});
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
        (package / 'bundle/chunk-RCB6BI5H.js').write_text("""
import fs from 'node:fs';
export class CodeAssistServer {}
export class Config {
  async refreshAuth() {
    this.contentGenerator = {
      generateContent: () => fs.writeFileSync('/out/dispatched.json', '{}'),
      generateContentStream: () => { throw new Error('unused synthetic stream'); },
    };
  }
  isInitialized() { return true; }
  getModel() { return process.env.MARTYGRAPHICS_GEMINI_MODEL; }
  getToolRegistry() { return {
    getAllTools: () => TOOLS, getFunctionDeclarations: () => [],
  }; }
}
""".replace('TOOLS', "[{name:'late_mcp_tool'}]" if behaviour == 'late-tool' else '[]'))
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


    def test_post_startup_tool_refused_before_generation(self):
        adapter = self.adapter('late-tool')
        handle = self.open(adapter)
        with self.assertRaises(live.Uncertain):
            handle.reply('Synthetic prompt')
        self.assertFalse((handle.path / '1/dispatched.json').exists())
        self.assertIn('final tool registry', (handle.path / '1/stderr.bin').read_text())

    def test_model_access_requires_explicit_confirmation_without_reading_auth(self):
        with patch.object(g2, 'auth_present', side_effect=AssertionError('auth read')), \
                patch.object(subprocess, 'Popen', side_effect=AssertionError('process')), \
                contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            g2.main(['model-access-check'])

    def test_fallback_disabled_before_state_auth_or_process(self):
        self.assertIsNone(g2.FALLBACK_OWNER_APPROVAL_AMENDMENT)
        with patch.object(g2, 'auth_present', side_effect=AssertionError('auth read')), \
                patch.object(subprocess, 'Popen', side_effect=AssertionError('process')):
            with self.assertRaisesRegex(ValueError, 'fallback DISABLED'):
                g2.GeminiAdapter(self.root / 'forbidden-state', '/missing', model=g2.PROPOSED_FALLBACK_MODEL)
            self.assertFalse((self.root / 'forbidden-state').exists())
            with self.assertRaisesRegex(ValueError, 'fallback DISABLED'):
                g2.gemini_argv(model=g2.PROPOSED_FALLBACK_MODEL)
            with self.assertRaisesRegex(ValueError, 'fallback DISABLED'):
                g2.write_settings(self.root, g2.PROPOSED_FALLBACK_MODEL)
            with contextlib.redirect_stderr(io.StringIO()) as stderr, self.assertRaises(SystemExit):
                g2.main(['model-access-check', '--model', g2.PROPOSED_FALLBACK_MODEL,
                         '--binary', '/missing', '--work', str(self.root / 'forbidden-state'),
                         '--confirm-model-request'])
            self.assertIn('fallback DISABLED', stderr.getvalue())

    def test_access_cli_model_selection_and_allowlist(self):
        # Synthetic handler only: no actual access-check command or auth.
        for selection in ([], ['--model', g2.REGISTERED_MODEL]):
            with patch.object(g2, 'GeminiAdapter') as factory, \
                    patch.object(g2, 'model_access_check', return_value=0) as check:
                self.assertEqual(g2.main(['model-access-check', '--binary', '/synthetic',
                    '--work', str(self.root / 'synthetic'), '--confirm-model-request', *selection]), 0)
                self.assertEqual(factory.call_args.kwargs['model'], 'gemini-4-argon')
                check.assert_called_once_with(factory.return_value)
        for extra in (['--model', 'arbitrary-model', '--confirm-model-request'],
                      ['--model', g2.REGISTERED_MODEL], ['--model', g2.PROPOSED_FALLBACK_MODEL]):
            with patch.object(g2, 'GeminiAdapter', side_effect=AssertionError('adapter')), \
                    contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
                g2.main(['model-access-check', '--binary', '/missing', '--work', str(self.root), *extra])

    def test_synthetic_approved_fallback_selection_and_recording(self):
        # An in-memory mock exercises the future gate; no approval is recorded
        # in the repo and the production constant remains None.
        with patch.object(g2, 'FALLBACK_OWNER_APPROVAL_AMENDMENT', 'SYNTHETIC-TEST-ONLY'):
            adapter = self.adapter(model=g2.PROPOSED_FALLBACK_MODEL)
            with patch.object(g2, 'GeminiAdapter', return_value=adapter), \
                    contextlib.redirect_stdout(io.StringIO()):
                status = g2.main(['model-access-check', '--model', g2.PROPOSED_FALLBACK_MODEL,
                                 '--binary', str(adapter.sandbox.binary), '--work', str(adapter.root),
                                 '--confirm-model-request'])
            self.assertEqual(status, 0)
            report = json.loads((adapter.root / 'MODEL-ACCESS-CHECK.json').read_text())
            self.assertEqual(report['model'], g2.PROPOSED_FALLBACK_MODEL)
            self.assertEqual(report['ownerApprovalAmendment'], 'SYNTHETIC-TEST-ONLY')
            observed = json.loads((adapter.root / 'model-access/out/observed.json').read_text())
            self.assertEqual(observed['args'][observed['args'].index('--model') + 1], g2.PROPOSED_FALLBACK_MODEL)
            self.assertEqual(observed['settings']['model']['name'], g2.PROPOSED_FALLBACK_MODEL)
            self.assertEqual(observed['env']['MARTYGRAPHICS_GEMINI_MODEL'], g2.PROPOSED_FALLBACK_MODEL)
            with self.assertRaisesRegex(ValueError, 'already attempted'):
                g2.model_access_check(adapter)
        with self.assertRaisesRegex(ValueError, 'fallback DISABLED'):
            g2.model_access_check(adapter)

    def test_model_access_records_accept_refuse_uncertain_once_with_fake_cli(self):
        for mode, outcome in [('success', 'accepted'), ('refused', 'refused'), ('crash', 'uncertain')]:
            with self.subTest(mode=mode):
                adapter = self.adapter(mode)
                with contextlib.redirect_stdout(io.StringIO()):
                    status = g2.model_access_check(adapter)
                report = json.loads((adapter.root / 'MODEL-ACCESS-CHECK.json').read_text())
                self.assertEqual(report['outcome'], outcome)
                self.assertEqual(status, 0 if outcome == 'accepted' else 1)
                self.assertEqual(report['generationAttemptLimit'], 1)
                self.assertEqual(report['model'], 'gemini-4-argon')
                self.assertIsNone(report['ownerApprovalAmendment'])
                observed = adapter.root / 'model-access/out/input.txt'
                self.assertEqual(observed.read_text(), 'Reply OK.')
                self.assertNotIn('synthetic-not-a-token', json.dumps(report))
                with patch.object(adapter.sandbox, 'invoke', side_effect=AssertionError('retry')):
                    with self.assertRaisesRegex(ValueError, 'already attempted'):
                        g2.model_access_check(adapter)


class NativeGeminiTest(unittest.TestCase):
    def native_adapter(self, root):
        binary = os.environ.get('GEMINI_NATIVE_BINARY') or shutil.which('gemini')
        if not binary:
            self.skipTest('Gemini CLI absent; set GEMINI_NATIVE_BINARY to the pinned installed bundle')
        return g2.GeminiAdapter(root / 'state', binary)

    def test_full_startup_trust_is_scoped_to_sandbox_packet(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            adapter = self.native_adapter(root)
            for trusted in (False, True):
                with self.subTest(trusted=trusted):
                    folder = root / str(trusted)
                    for name in ('home', 'packet', 'out'):
                        (folder / name).mkdir(parents=True)
                    home, packet, output = (folder / name for name in ('home', 'packet', 'out'))
                    g2.write_settings(home)
                    trust_file = home / '.gemini/trustedFolders.json'
                    self.assertEqual(json.loads(trust_file.read_text()), {'/packet': 'TRUST_FOLDER'})
                    if not trusted:
                        trust_file.unlink()
                    command, message = adapter.transport(b'Synthetic offline startup fixture', [], None, output)
                    self.assertEqual(command, g2.gemini_argv())
                    self.assertEqual(message, b'')
                    shutil.copyfile(Path(__file__).with_name('gemini_startup_stub.mjs'), output / 'startup.mjs')
                    guard = Path(g2.__file__).parent / 'native/gemini_guard.mjs'
                    shutil.copyfile(guard, output / 'guard.mjs')
                    original = adapter.sandbox.command
                    def with_stub(home, packet, output, args, *, network=True):
                        self.assertFalse(network)
                        argv = original(home, packet, output, args, network=network)
                        self.assertEqual(argv.count(str(guard)), 1)
                        argv[argv.index(str(guard))] = str(output / 'startup.mjs')
                        return argv
                    with patch.object(adapter.sandbox, 'command', side_effect=with_stub), \
                            patch.object(g2, 'auth_present', side_effect=AssertionError('auth read')):
                        with self.assertRaises(live.Uncertain):
                            adapter.sandbox.invoke(home, packet, output, command, message, 30, network=False)
                    stderr = (output / 'stderr.bin').read_text()
                    if trusted:
                        self.assertTrue((output / 'initialized.json').exists(), stderr)
                        self.assertEqual(json.loads((output / 'initialized.json').read_text()),
                                         {'initialized': True, 'trusted': True, 'tools': 0})
                        self.assertTrue((output / 'synthetic-auth.json').exists())
                        events = [json.loads(line) for line in (output / 'stdout.bin').read_bytes().splitlines()]
                        self.assertTrue(any(event.get('type') == 'init' for event in events))
                        self.assertEqual(json.loads((output / 'generation-refused.json').read_text()),
                                         {'outcome': 'refused'})
                        self.assertNotIn('not running in a trusted directory', stderr)
                    else:
                        self.assertIn('not running in a trusted directory', stderr)
                        self.assertFalse((output / 'initialized.json').exists())
                    self.assertFalse((home / '.gemini/oauth_creds.json').exists())

    def transport_probe(self, adapter, folder, method, status, mode):
        for name in ('home', 'packet', 'out'):
            (folder / name).mkdir(parents=True)
        home, packet, output = (folder / name for name in ('home', 'packet', 'out'))
        g2.write_settings(home)
        shutil.copyfile(Path(__file__).with_name('gemini_transport_probe.mjs'), output / 'transport.mjs')
        shutil.copyfile(Path(g2.__file__).parent / 'native/gemini_guard.mjs', output / 'guard.mjs')
        with patch.object(g2, 'auth_present', side_effect=AssertionError('auth read')):
            with self.assertRaises(live.Uncertain):
                adapter.sandbox.invoke(home, packet, output,
                                       ['/node', '/out/transport.mjs', method, str(status), mode],
                                       b'', 30, network=False)
        report = json.loads((output / 'transport-result.json').read_text())
        self.assertEqual(report['outcome'], 'refused')
        self.assertFalse((home / '.gemini/oauth_creds.json').exists())
        return report

    def test_native_oauth_transport_refuses_401_403_generation_replays(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            adapter = self.native_adapter(root)
            for method in ('generateContent', 'generateContentStream'):
                for status in (401, 403):
                    with self.subTest(method=method, status=status):
                        baseline = self.transport_probe(adapter, root / f'{method}-{status}-baseline',
                                                        method, status, 'baseline')
                        self.assertEqual(baseline['generationPosts'], 2)
                        self.assertEqual(baseline['refreshes'], 1)
                        self.assertEqual(baseline['posts'][0]['body'], baseline['posts'][1]['body'])
                        guarded = self.transport_probe(adapter, root / f'{method}-{status}-guarded',
                                                       method, status, 'guarded')
                        self.assertEqual(guarded['generationPosts'], 1)
                        self.assertEqual(guarded['refreshes'], 1)
                        self.assertIn('second generation POST', guarded['reason'])

    def test_native_oauth_transport_allows_refresh_before_first_post(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            adapter = self.native_adapter(root)
            for method in ('generateContent', 'generateContentStream'):
                with self.subTest(method=method):
                    report = self.transport_probe(adapter, root / method, method, 401, 'expired')
                    self.assertEqual(report['generationPosts'], 1)
                    self.assertEqual(report['refreshes'], 1)
                    self.assertEqual(report['posts'][0]['refreshesBeforeDispatch'], 1)

    def test_native_oauth_transport_budget_spans_clients_and_methods(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            adapter = self.native_adapter(root)
            for method in ('generateContent', 'generateContentStream'):
                with self.subTest(method=method):
                    report = self.transport_probe(adapter, root / method, method, 503, 'second-client')
                    self.assertEqual(report['generationPosts'], 1)
                    self.assertEqual(report['refreshes'], 0)
                    self.assertIn('second generation POST', report['secondRefusal'])

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
            self.assertIsNone(library['bundledModel'])
            self.assertEqual(report['selectedModel'], 'gemini-4-argon')
            self.assertEqual(g2.MODEL, 'gemini-4-argon')
            self.assertEqual(live.MODELS['G2'], 'gemini-4-argon')
            self.assertEqual(library['thinking']['thinkingLevel'], 'HIGH')
            self.assertFalse(report['registeredModelListed'])
            self.assertEqual(len(library['modelConditions']), 8)
            self.assertTrue(all(item['resolved'] == 'gemini-4-argon' for item in library['modelConditions']))
            self.assertEqual(library['registeredModelThinking']['thinkingLevel'], 'HIGH')
            for name in ('mcp', 'extensions', 'skills'):
                self.assertTrue(library['mergedAdmin'][name]['enabled'])
            self.assertTrue(all(library['dispatchGuard'].values()))
            self.assertIn('unavailable',report['effectiveToolContextDiagnostic'])

    def test_native_rejects_tool_memory_and_model_policy_regressions(self):
        binary = os.environ.get('GEMINI_NATIVE_BINARY') or shutil.which('gemini')
        if not binary:
            self.skipTest('Gemini CLI absent; set GEMINI_NATIVE_BINARY')
        with tempfile.TemporaryDirectory() as temp:
            adapter = g2.GeminiAdapter(Path(temp)/'state', binary)
            for target, replacement in ((g2.SETTINGS['tools'], {'core':['run_shell_command']}),
                                        (g2.SETTINGS['modelConfigs'], {'modelIdResolutions':{g2.MODEL:{'default':'other-model', 'contexts':[]}}}),
                                        (g2.SETTINGS['modelConfigs'], {'customOverrides':[]})):
                with self.subTest(replacement=replacement), patch.dict(target, replacement):
                    with self.assertRaisesRegex(ValueError, 'native library policy/input check failed'):
                        adapter.library_check()

            original = g2.write_settings
            def contaminated(home, model=g2.MODEL):
                original(home, model)
                (home/'.gemini/GEMINI.md').write_text('SYNTHETIC unwanted memory')
            with patch.object(g2, 'write_settings', side_effect=contaminated):
                with self.assertRaisesRegex(ValueError, 'native library policy/input check failed'):
                    adapter.library_check()
