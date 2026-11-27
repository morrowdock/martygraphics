# SPDX-License-Identifier: Apache-2.0
"""Seamless loops in the Blender render path (tools/render-blender/mgrender/loop.py), without Blender.

The manifest records here are built by hand and the expectations are analytic: these tests do not read output of
the Swift exporter, so they are not a parity check of `MGSolidGLTF.seamlessLoop`. docs/ENGINE.md ("Verify on a Mac")
generates the Swift vectors (the robot joint's seamless `loop` record) for a later parity test.
"""
import math
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "render-blender"))

from mgrender import loop as loops  # noqa: E402
from mgrender import manifest as mf  # noqa: E402
from test_render_blender import ExportFixture  # noqa: E402


def record(frames=4, closing=True, **extra):
    """A hand-built manifest `loop` record in the shape the Swift exporter writes (not Swift output)."""
    loop = {"seamless": True, "frames": frames, "inputTurns": "49/6"}
    if closing:
        loop["closingFrame"] = frames
    loop.update(extra)
    return {"loop": loop}


class LoopRecordTests(unittest.TestCase):
    def test_no_record_keeps_the_old_behaviour(self):
        self.assertIsNone(loops.loop_info({}, 10))
        self.assertEqual(loops.render_range(None, 10), (0, 9))
        self.assertEqual(loops.blur_position(None), "CENTER")
        self.assertEqual(loops.camera_end_frame(None, 10), 9)
        self.assertIsNone(loops.sway_frames(None))

    def test_seamless_record_with_a_closing_frame(self):
        info = loops.loop_info(record(4), 5)
        self.assertEqual(info, {"seamless": True, "frames": 4, "closing": True, "input_turns": "49/6"})
        # Frames 0..3 are the loop; frame 4 (the closing key) is frame 0 again and is not rendered.
        self.assertEqual(loops.render_range(info, 5), (0, 3))
        # The last loop frame blurs toward the closing key, as frame 0 blurs toward frame 1.
        self.assertEqual(loops.blur_position(info), "START")
        # The turntable completes its turn at frame 4 (= the period), the sway spans 4 frames.
        self.assertEqual(loops.camera_end_frame(info, 5), 3)
        self.assertEqual(loops.sway_frames(info), 4)

    def test_a_record_that_is_not_seamless_renders_every_frame(self):
        info = loops.loop_info({"loop": {"seamless": False, "frames": 5}}, 5)
        self.assertEqual(loops.render_range(info, 5), (0, 4))
        self.assertEqual(loops.blur_position(info), "CENTER")

    def test_malformed_records_are_refused(self):
        bad = [
            ({"loop": []}, 5),
            ({"loop": {"seamless": "yes", "frames": 4}}, 5),
            ({"loop": {"seamless": True, "frames": True}}, 5),
            ({"loop": {"seamless": True, "frames": 0}}, 5),
            (record(4, closingFrame=3), 5),
            (record(4), 4),                          # a closing frame needs frameCount = frames + 1
            ({"loop": {"seamless": True, "frames": 6}}, 5),
            (record(4, inputTurns=8.1666), 5),
        ]
        for manifest, count in bad:
            with self.assertRaises(loops.LoopError, msg=repr(manifest)):
                loops.loop_info(manifest, count)

    def test_sway_is_periodic_and_bounded(self):
        n, start, sweep = 120, -0.6, math.radians(40)
        keys = loops.sway(start, sweep, n)
        self.assertEqual([f for f, _ in keys], list(range(n + 1)))
        self.assertAlmostEqual(keys[0][1], start, places=12)
        self.assertAlmostEqual(keys[n][1], keys[0][1], places=12)
        self.assertAlmostEqual(keys[n // 2][1], start + sweep, places=12)
        steps = [b - a for (_, a), (_, b) in zip(keys, keys[1:])]
        # Rest at both turns (the steps at the wrap are the smallest) and never faster than the cosine's peak speed.
        self.assertAlmostEqual(abs(steps[0]), abs(steps[-1]), places=12)
        self.assertLessEqual(max(abs(s) for s in steps), sweep * math.pi / n + 1e-12)
        with self.assertRaises(loops.LoopError):
            loops.sway(0, 1, 0)


class ManifestLoopTests(unittest.TestCase):
    def test_verify_returns_the_loop(self):
        with tempfile.TemporaryDirectory() as tmp:
            fx = ExportFixture(tmp, frames=5)
            fx.manifest.update(record(4))
            checked = mf.verify(fx.write())
            self.assertEqual(checked["loop"]["frames"], 4)
            self.assertTrue(checked["loop"]["closing"])

    def test_verify_refuses_a_loop_that_does_not_fit_the_frames(self):
        with tempfile.TemporaryDirectory() as tmp:
            fx = ExportFixture(tmp, frames=5)
            fx.manifest.update(record(5))
            with self.assertRaises(mf.ExportError):
                mf.verify(fx.write())

    def test_verify_without_a_loop_is_unchanged(self):
        with tempfile.TemporaryDirectory() as tmp:
            fx = ExportFixture(tmp, frames=5)
            self.assertIsNone(mf.verify(fx.write())["loop"])


if __name__ == "__main__":
    unittest.main()
