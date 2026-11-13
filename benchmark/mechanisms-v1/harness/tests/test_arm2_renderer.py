# SPDX-License-Identifier: Apache-2.0
"""Native synthetic acceptance. Supply the pinned tarball; never download in a test."""

import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import shutil
import socket
import struct
import subprocess
import sys
import tempfile
import threading
import unittest
import zlib

import support as S
from arm2_tokenizer_cases import tokenizer_cases


def image_payload(path):
    data = path.read_bytes()
    offset, payload = 8, bytearray()
    while offset < len(data):
        size = struct.unpack_from(">I", data, offset)[0]
        if data[offset + 4:offset + 8] == b"IDAT":
            payload.extend(data[offset + 8:offset + 8 + size])
        offset += 12 + size
    return zlib.decompress(payload)


@unittest.skipUnless(sys.platform == "darwin" and shutil.which("swiftc") and os.environ.get("ARM2_THREE_TARBALL"),
                     "macOS, swiftc and ARM2_THREE_TARBALL required")
class WKRendererTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        cls.addClassCleanup(cls.temp.cleanup)
        cls.root = Path(os.environ.get("ARM2_TEST_ARTIFACTS", cls.temp.name))
        if os.environ.get("ARM2_TEST_ARTIFACTS"):
            cls.root.mkdir(parents=True, exist_ok=False)
        cls.binary = Path(os.environ.get("ARM2_RWK_BINARY", str(cls.root / "r-wk")))
        if not os.environ.get("ARM2_RWK_BINARY"):
            subprocess.run(["swiftc", "-O", str(S.HARNESS / "arm2" / "render.swift"), "-o", str(cls.binary)],
                           check=True, capture_output=True, timeout=180)
        cls.tarball = Path(os.environ["ARM2_THREE_TARBALL"])
        cls.fixtures = S.HARNESS / "tests" / "fixtures" / "arm2"

    def render(self, name, source=None, tarball=None, binary=None):
        page = self.fixtures / (name + ".html")
        if source is not None:
            page = self.root / (name + ".html")
            page.write_text(source)
        output = self.root / name
        result = subprocess.run([str(binary or self.binary), "--html", str(page), "--out", str(output),
                                 "--three-tarball", str(tarball or self.tarball), "--lock", str(S.BENCH / "LOCK.json")],
                                capture_output=True, timeout=310)
        (self.root / (name + ".stderr")).write_bytes(result.stderr)
        report = json.loads((output / "report.json").read_bytes()) if (output / "report.json").exists() else None
        return result, report, output

    def test_webgl_cube_full_sequence(self):
        result, report, output = self.render("cube")
        self.assertEqual(result.returncode, 0, result.stderr.decode(errors="replace"))
        self.assertTrue(report["complete"], report)
        self.assertEqual(len(report["frames"]), 300)
        self.assertEqual(report["observedViewport"], {"width": 1280, "height": 800, "scale": 1})
        self.assertFalse(report["allBlank"], "R-WK cannot capture WebGL: synthetic cube is blank")
        self.assertGreater(min(report["nonModalPixelFractions"]), 0.05)
        self.assertNotEqual(image_payload(output / report["frames"][0]), image_payload(output / report["frames"][30]),
                            "R-WK cannot capture WebGL motion: frame 0 and frame 30 are identical")
        self.assertEqual(report["stillIndices"], [30, 90, 150, 210, 270])
        self.assertIn("warn: synthetic cube ready", report["console"])
        self.assertTrue(all((output / name).exists() for name in report["frames"]))
        evidence = {"result": "works", "frames": 300, "frame0Sha256": hashlib.sha256((output / report["frames"][0]).read_bytes()).hexdigest(),
                    "frame30Sha256": hashlib.sha256((output / report["frames"][30]).read_bytes()).hexdigest(),
                    "nonModalPixelFractions": report["nonModalPixelFractions"], "seconds": report["seconds"]}
        (self.root / "webgl-evidence.json").write_text(json.dumps(evidence, indent=2) + "\n")

    def test_never_ready_times_out(self):
        result, report, output = self.render("never-ready")
        self.assertEqual(result.returncode, 1)
        self.assertFalse(report["complete"])
        self.assertTrue(any("benchReady timeout" in error for error in report["harnessErrors"]))
        self.assertGreaterEqual(report["seconds"], 30)
        self.assertLess(report["seconds"], 40)
        self.assertIn("error: synthetic readiness error", report["console"])
        self.assertEqual(len(report["stills"]), 5)

    def test_network_probes_blocked_without_request_reaching_server(self):
        hits = []
        connections = []

        class Server(ThreadingHTTPServer):
            def get_request(self):
                connection, address = super().get_request()
                connections.append(address)
                return connection, address

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                hits.append(self.path)
                self.send_response(200)
                self.end_headers()

            def log_message(self, *args):
                pass

        server = Server(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            source = (self.fixtures / "network.html").read_text().replace("NETWORK_URL", "http://127.0.0.1:%d/denied" % server.server_port)
            result, report, output = self.render("network", source)
        finally:
            server.shutdown()
            server.server_close()
            thread.join()
        self.assertEqual(result.returncode, 0, result.stderr.decode(errors="replace"))
        self.assertEqual(hits, [])
        self.assertEqual(connections, [], "offline probes opened a TCP connection")
        (self.root / "network-evidence.json").write_text(json.dumps({"tcpConnections": len(connections), "httpRequests": len(hits)}) + "\n")
        for probe in ("fetch", "XHR", "WebSocket", "image", "dynamic-import"):
            self.assertIn("warn: synthetic " + probe + " blocked", report["console"])
        self.assertFalse(report["allBlank"])
        self.assertEqual(len(report["frames"]), 300)

    def test_webrtc_main_and_iframe_send_no_udp(self):
        datagrams = []
        stopped = threading.Event()
        listener = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        listener.bind(("127.0.0.1", 0))
        listener.settimeout(0.1)

        def listen():
            while not stopped.is_set():
                try:
                    datagrams.append(listener.recvfrom(65535))
                except socket.timeout:
                    pass

        thread = threading.Thread(target=listen, daemon=True)
        thread.start()
        probe = """
        async function probe(scope, label) {
          console.warn('synthetic WebRTC attempted: ' + label);
          for (const name of ['RTCPeerConnection', 'webkitRTCPeerConnection']) {
            if (typeof scope[name] !== 'function') continue;
            console.error('WebRTC exposed: ' + label + ' ' + name);
            try {
              const peer = new scope[name]({iceServers: [{urls: 'stun:127.0.0.1:UDP_PORT'}]});
              scope.syntheticPeer = peer;
              peer.createDataChannel('synthetic');
              await peer.setLocalDescription(await peer.createOffer());
            } catch (error) { console.warn('synthetic WebRTC error: ' + error); }
          }
        }
        """.replace("UDP_PORT", str(listener.getsockname()[1]))
        srcdoc = "<script>" + probe + "probe(window, 'srcdoc-execution');</script>"
        source = """<!doctype html><html><head></head><body>
        <div style="background:black;color:white;font:40px system-ui">Synthetic offline WebRTC</div>
        <script>""" + probe + """
        (async () => {
          await probe(window, 'main');
          for (const name of ['RTCPeerConnection', 'webkitRTCPeerConnection', 'RTCDataChannel', 'RTCIceCandidate']) {
            try { Object.defineProperty(window, name, {value: function restored() {}}); } catch {}
            const descriptor = Object.getOwnPropertyDescriptor(window, name);
            if (!descriptor || descriptor.value !== undefined || descriptor.writable || descriptor.configurable)
              console.error('WebRTC binding not locked: ' + name);
          }
          const blank = document.createElement('iframe');
          document.body.appendChild(blank);
          await probe(blank.contentWindow, 'iframe');
          const frame = document.createElement('iframe');
          frame.srcdoc = SRCDOC;
          document.body.appendChild(frame);
          await probe(frame.contentWindow, 'iframe/srcdoc');
          window.benchDuration = 10;
          window.benchFrame = async () => {};
          window.benchReady = true;
        })();
        </script></body></html>""".replace("SRCDOC", json.dumps(srcdoc).replace("</", "<\\/"))
        try:
            result, report, output = self.render("webrtc", source)
        finally:
            stopped.set()
            thread.join()
            listener.close()
        self.assertEqual(result.returncode, 0, result.stderr.decode(errors="replace"))
        self.assertTrue(report["complete"], report)
        self.assertEqual(len(report["frames"]), 300)
        self.assertEqual(datagrams, [], "WebRTC sent UDP despite offline policy")
        (self.root / "webrtc-evidence.json").write_text(json.dumps({"udpDatagrams": len(datagrams)}) + "\n")
        for label in ("main", "iframe", "iframe/srcdoc"):
            self.assertIn("warn: synthetic WebRTC attempted: " + label, report["console"])
        self.assertFalse(any("WebRTC exposed:" in line or "WebRTC binding not locked:" in line
                             for line in report["console"]), report["console"])
        self.assertTrue(any("srcdoc" in line and ("blocked" in line or "srcdoc-execution" in line)
                            for line in report["console"]), report["console"])

    def assert_head_injection(self, name, prefix, expect_timeout=False):
        source = prefix + """<body><div style="background:black;color:white;font:40px system-ui">Synthetic head</div>
        <script type="module">
        import {REVISION} from 'three';
        if (REVISION !== '170') throw Error('wrong module');
        const map = document.querySelector('script[data-bench-importmap]');
        if (!map || map.type !== 'importmap') throw Error('missing import map');
        console.warn('synthetic head and import map ready');
        window.benchDuration = 10; window.benchFrame = async () => {}; window.benchReady = true;
        </script></body></html>"""
        result, report, output = self.render(name, source)
        if expect_timeout:
            self.assertEqual(result.returncode, 1)
            self.assertEqual(report["frames"], [])
            self.assertIn("benchReady timeout (30 s)", report["harnessErrors"])
            self.assertTrue(report["headInvariantAtStart"], report)
            self.assertTrue(report["headInvariantAfterLoad"], report)
            return
        self.assertEqual(result.returncode, 0, result.stderr.decode(errors="replace"))
        self.assertTrue(report["complete"], report)
        self.assertEqual(len(report["frames"]), 300)
        self.assertIn("warn: synthetic head and import map ready", report["console"])
        if "EARLY-AUTHOR" in prefix:
            self.assertIn("warn: EARLY-AUTHOR map=true", report["console"])
        self.assertFalse(report["allBlank"])
        self.assertTrue(report["headInvariantAtStart"], report)
        self.assertTrue(report["headInvariantAfterLoad"], report)
        events = [json.loads(line) for line in (output / "events.ndjson").read_text().splitlines()]
        self.assertIn({"kind": "head-invariant", "value": "verified"}, events)
        self.assertEqual(report["htmlLoadedSha256"], report["htmlSourceSha256"])

    def test_comment_before_head(self):
        self.assert_head_injection("comment-head", '<!doctype html><!-- mentions <head> --><html><head></head>')

    def test_head_in_script_string(self):
        self.assert_head_injection("script-head", '<!doctype html><html><script>const marker = "<head>";</script><head></head>')

    def test_head_in_style_text(self):
        self.assert_head_injection("style-head", '<!doctype html><html><style>body::before {content:"<head>"}</style><head></head>')

    def test_missing_head(self):
        self.assert_head_injection("no-head", '<!doctype html><html>')

    def test_uppercase_head_with_attributes(self):
        self.assert_head_injection("uppercase-head", '<!DOCTYPE html><HTML lang="en"><HEAD data-note="quoted > <head>"></HEAD>')

    def test_additional_head_baseline_cases(self):
        cases = {
            "head-tab": '<!doctype html><html><head\tdata-note="tab"></head>',
            "head-lf": '<!doctype html><html><head\ndata-note="lf"></head>',
            "head-ff": '<!doctype html><html><head\fdata-note="ff"></head>',
            "head-cr": '<!doctype html><html><head\rdata-note="cr"></head>',
            "head-space": '<!doctype html><html><head data-note="space"></head>',
            "head-bom": '\ufeff \t\r\n<!doctype html><html><head></head>',
            "head-no-html": '<!doctype html><head></head>',
            "head-self-closing": '<!doctype html><html><head/></head>',
            "head-html-attributes": '<!doctype html><html data-note="quoted > <head>"><head></head>',
            "head-comment-bang": '<!doctype html><!-- <head> --!><html><head></head>',
        }
        for name, prefix in cases.items():
            with self.subTest(name=name):
                self.assert_head_injection(name, prefix)

    def test_nbsp_head_is_not_a_head_tag(self):
        self.assert_head_injection("head-nbsp", '<!doctype html><html><head\u00a0data-note="nbsp"></head>')

    def test_vertical_tab_head_is_not_a_head_tag(self):
        self.assert_head_injection("head-vt", '<!doctype html><html><head\vdata-note="vt"></head>')

    def test_doctype_quoted_head_ends_at_first_greater_than(self):
        for keyword in ("PUBLIC", "SYSTEM"):
            for quote in ('"', "'"):
                name = "doctype-" + keyword.lower() + ("-double" if quote == '"' else "-single")
                with self.subTest(name=name):
                    self.assert_head_injection(name, '<!doctype html ' + keyword + ' ' + quote + '<head>' + quote + ' "about:legacy-compat"><html><head></head>')

    def test_unquoted_attribute_quote_first_script_has_policy(self):
        source = (self.fixtures / "unquoted-attribute-quote.html").read_text()
        result, report, output = self.render("unquoted-attribute-quote", source)
        self.assertEqual(result.returncode, 0, result.stderr.decode(errors="replace"))
        self.assertTrue(report["complete"], report)
        self.assertEqual(len(report["frames"]), 300)
        self.assertTrue(report["headInvariantAtStart"], report)
        self.assertTrue(report["headInvariantAfterLoad"], report)
        self.assertIn("warn: first authored script: CSP blocked fetch", report["console"])
        self.assertIn("warn: first authored module: three 170", report["console"])
        self.assertFalse(any("POLICY BYPASS" in line for line in report["console"]), report)

    def test_head_invariant_refuses_removed_import_map(self):
        source = '''<!doctype html><html><head></head><body><script>
        window.__benchVerifyHead = () => true;
        document.querySelector('script[data-bench-importmap]').remove();
        window.benchDuration=10; window.benchFrame=async () => {}; window.benchReady=true;
        </script></body></html>'''
        result, report, output = self.render("head-invariant-removed", source)
        self.assertEqual(result.returncode, 1, result.stderr.decode(errors="replace"))
        self.assertFalse(report["complete"])
        self.assertEqual(report["frames"], [])
        self.assertTrue(any("head invariant" in error for error in report["harnessErrors"]), report)
        self.assertFalse(report["headInvariantAfterLoad"])

    def test_reviewer_tokenizer_matrix(self):
        hits, connections = [], []

        class Server(ThreadingHTTPServer):
            def get_request(self):
                connection, address = super().get_request()
                connections.append(address)
                return connection, address

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                hits.append(self.path)
                self.send_response(200)
                self.end_headers()

            def log_message(self, *arguments):
                pass

        server = Server(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        early = '''<script>
        console.warn('EARLY-AUTHOR map=' + !!document.querySelector('[data-bench-importmap]'));
        try { window.earlySocket = new WebSocket('ws://127.0.0.1:PORT/early-socket'); } catch(error) {}
        fetch('http://127.0.0.1:PORT/early-fetch').catch(() => {});
        </script>'''.replace("PORT", str(server.server_port))
        cases = tokenizer_cases(early)
        self.assertEqual(len(cases), 39)
        try:
            for name, prefix in cases.items():
                with self.subTest(name=name):
                    self.assert_head_injection("matrix-" + name, prefix,
                                               expect_timeout=name in {"unterminated-comment", "unterminated-comment-dashes"})
        finally:
            server.shutdown()
            server.server_close()
            thread.join()
        self.assertEqual(connections, [])
        self.assertEqual(hits, [])
        (self.root / "matrix-network-evidence.json").write_text(json.dumps({
            "cases": len(cases), "tcpConnections": len(connections), "httpRequests": len(hits)}) + "\n")

    def assert_configuration_fault_refused(self, name, original, replacement):
        source = (S.HARNESS / "arm2" / "render.swift").read_text()
        self.assertEqual(source.count(original), 1)
        policy = source.split('let policy = "', 1)[1].split('"', 1)[0]
        swift = self.root / (name + ".swift")
        swift.write_text(source.replace(original, replacement))
        binary = self.root / (name + "-r-wk")
        subprocess.run(["swiftc", "-O", str(swift), "-o", str(binary)],
                       check=True, capture_output=True, timeout=180)
        page = '''<!doctype html><html><script>
        window.__benchVerifyHead = () => true;
        document.dispatchEvent(new SecurityPolicyViolationEvent('securitypolicyviolation', {
          originalPolicy: POLICY, disposition: 'enforce', blockedURI: 'data', effectiveDirective: 'script-src-elem'
        }));
        window.benchDuration=10; window.benchFrame=async () => {}; window.benchReady=true;
        </script></html>'''.replace("POLICY", json.dumps(policy))
        result, report, output = self.render(name, page, binary=binary)
        self.assertEqual(result.returncode, 1, result.stderr.decode(errors="replace"))
        self.assertFalse(report["complete"], report)
        self.assertEqual(report["frames"], [])
        self.assertTrue(any("head invariant" in error for error in report["harnessErrors"]), report)
        self.assertFalse(report["headInvariantAfterLoad"], report)

    def test_missing_response_policy_refused(self):
        self.assert_configuration_fault_refused("missing-response-policy",
                                               'headers["Content-Security-Policy"] = policy',
                                               'headers["X-Synthetic-Omitted-Policy"] = policy')

    def test_missing_document_start_map_refused(self):
        self.assert_configuration_fault_refused("missing-document-start-map",
                                               'document.documentElement.appendChild(map);',
                                               'void map;')

    def test_bad_archive_hash_is_refused(self):
        archive = self.root / "bad.tgz"
        archive.write_bytes(b"synthetic invalid archive")
        result, report, output = self.render("bad-archive", "<html><head></head></html>", archive)
        self.assertEqual(result.returncode, 2)
        self.assertIn(b"tarball SHA-256 mismatch", result.stderr)
        self.assertIsNone(report)

    def test_missing_duration_is_harness_error(self):
        source = "<html><head></head><body><script>window.benchReady=true</script></body></html>"
        result, report, output = self.render("missing-duration", source)
        self.assertEqual(result.returncode, 1)
        self.assertTrue(any("benchDuration" in error for error in report["harnessErrors"]))

    def test_frame_exception_is_recorded(self):
        source = """<html><head></head><body><script>
        window.benchDuration=10;
        window.benchFrame=async () => { throw Error('synthetic benchFrame failure'); };
        window.benchReady=true;
        </script></body></html>"""
        result, report, output = self.render("frame-error", source)
        self.assertEqual(result.returncode, 1)
        self.assertFalse(report["complete"])
        self.assertEqual(report["frames"], [])
        self.assertTrue(any("synthetic benchFrame failure" in error for error in report["harnessErrors"]))


if __name__ == "__main__":
    unittest.main()
