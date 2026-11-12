# SPDX-License-Identifier: Apache-2.0
"""Apple-framework acceptance tests, synthetic only; skipped on non-macOS hosts."""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

import support as S
import pack


@unittest.skipUnless(sys.platform == "darwin" and shutil.which("swiftc"), "Apple frameworks and swiftc required")
class NativeMediaTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        cls.addClassCleanup(cls.temp.cleanup)
        cls.root = Path(cls.temp.name)
        cls.binary = cls.root / "media"
        subprocess.run(["swiftc", "-O", str(S.HARNESS / "native" / "media.swift"), "-o", str(cls.binary)],
                       check=True, capture_output=True, timeout=120)

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir=self.root)
        self.addCleanup(self.temp.cleanup)
        self.work = Path(self.temp.name)
        self.media = pack.AppleMedia(self.binary)
        self.addCleanup(self.media.close)

    def test_encode_decode_orientation_thumbnail_and_metadata(self):
        # Four unequal color quadrants detect mirroring, rotation and wrong RGB order.
        row1 = bytes((220, 30, 30)) * 640 + bytes((30, 220, 30)) * 640
        row2 = bytes((30, 30, 220)) * 640 + bytes((220, 220, 30)) * 640
        raw = row1 * 400 + row2 * 400
        source = self.work / "source.png"
        pack.png(source, raw)
        decoded = self.work / "decoded"; decoded.mkdir()
        frames = self.media.prepare({"kind": "captures", "paths": [str(source)] * 6}, 2, decoded)
        self.assertEqual(len(frames), 6)
        pixels = Path(frames[0]).read_bytes()
        self.assertEqual(len(pixels), 1280 * 800 * 3)
        for x, y in ((200, 200), (1000, 200), (200, 600), (1000, 600)):
            i = (y * 1280 + x) * 3
            self.assertTrue(all(abs(pixels[i+c] - raw[i+c]) < 25 for c in range(3)))
        self.assertEqual(len(self.media.thumbnail(Path(frames[0]))), 256 * 160 * 3)
        video = self.work / "normalized.mp4"
        self.media.video([Path(p) for p in frames], video)
        # The scrubber is idempotent and checks fast-start, one H.264 video track.
        before = video.read_bytes(); pack.scrub_mp4(video); self.assertEqual(before, video.read_bytes())
        again = self.work / "again"; again.mkdir()
        self.assertEqual(len(self.media.prepare({"kind": "video", "path": str(video)}, 1, again)), 6)

    def test_vision_matched_range_and_kept_limitation(self):
        # Native system-font fixture: only synthetic branding and a kept label.
        fixture = self.work / "fixture.swift"
        output = self.work / "text.png"
        fixture.write_text('''import AppKit
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1280, pixelsHigh: 800,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 1280, height: 800).fill()
let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 60), .foregroundColor: NSColor.black]
("Schematic Marty" as NSString).draw(at: NSPoint(x: 80, y: 400), withAttributes: attributes)
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
''')
        subprocess.run(["swift", str(fixture), str(output)], check=True, capture_output=True, timeout=120)
        frames_dir = self.work / "frames"; frames_dir.mkdir()
        frames = self.media.prepare({"kind": "captures", "paths": [str(output)] * 3}, 2, frames_dir)
        frame = Path(frames[0])
        lines = self.media.ocr(frame)
        matches = [m for line in lines for m in line["matches"]]
        self.assertTrue(any(m["rule"] == "B1" for m in matches))
        masked = self.work / "masked.rgb"
        masked.write_bytes(pack.mask(frame.read_bytes(), lines, 3))
        text = " ".join(line["text"] for line in self.media.ocr(masked)).lower()
        self.assertIn("schematic", text)
        self.assertNotIn("marty", text)

    def test_native_refusals(self):
        wrong = self.work / "wrong.png"; pack.png(wrong, bytes(3), 1, 1)
        for request in ({"op": "unknown"}, {"op": "encode", "paths": [], "output": str(self.work / "v.mp4"), "raw": True},
                        {"op": "thumbnail", "path": str(wrong)},
                        {"op": "prepare", "kind": "captures", "paths": [str(wrong)], "output": str(self.work)}):
            with self.subTest(request=request), self.assertRaises(ValueError): self.media.invoke(**request)
