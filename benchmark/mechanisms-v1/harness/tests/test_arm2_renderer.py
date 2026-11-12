# SPDX-License-Identifier: Apache-2.0
"""Native synthetic acceptance. Supply the pinned tarball; never download in a test."""

import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile
import threading
import unittest
import zlib

import support as S


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

    def render(self, name, source=None, tarball=None):
        page = self.fixtures / (name + ".html")
        if source is not None:
            page = self.root / (name + ".html")
            page.write_text(source)
        output = self.root / name
        result = subprocess.run([str(self.binary), "--html", str(page), "--out", str(output),
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

    def test_fetch_blocked_without_request_reaching_server(self):
        hits = []

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                hits.append(self.path)
                self.send_response(200)
                self.end_headers()

            def log_message(self, *args):
                pass

        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
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
        self.assertIn("warn: synthetic fetch blocked", report["console"])
        self.assertFalse(report["allBlank"])
        self.assertEqual(len(report["frames"]), 300)

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
