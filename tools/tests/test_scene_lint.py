# SPDX-License-Identifier: Apache-2.0
"""Authoring lint: each guard fires on its mistake and stays quiet on the guide's worked examples."""

from pathlib import Path
import json
import re
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "evals/dev-authoring/vendor/tools"))

import scene_lint  # noqa: E402
import scene_v1_check  # noqa: E402


def codes(scene):
    return {warning.split(":", 1)[0] for warning in scene_lint.lint(scene)}


class SceneLint(unittest.TestCase):
    def test_guards_fire(self):
        cases = {
            "step0.edits": {"v": 1, "items": [{"id": "a", "k": "array", "at": [6, 4], "vals": [5, 1]}],
                            "steps": [{"say": "Swap.", "do": [{"id": "a", "key": "vals", "value": [1, 5]}]}]},
            "display.rounding": {"v": 1, "items": [{"id": "b", "k": "bars", "at": [1, 1], "w": 8, "h": 5,
                                                    "bars": [{"label": "p", "value": 0.375}]}]},
            "bars.negative": {"v": 1, "items": [{"id": "b", "k": "bars", "at": [1, 1], "w": 8, "h": 5,
                                                 "bars": [{"label": "p", "value": -2}]}]},
            "plot.outside": {"v": 1, "items": [{"id": "p", "k": "plot", "at": [1, 1], "w": 8, "h": 5, "xr": [0, 10],
                                                "yr": [0, 10], "pts": [[0, 0], [12, 3]]}]},
            "layout.outside": {"v": 1, "items": [{"id": "a", "k": "array", "at": [10, 4],
                                                  "vals": [1, 2, 3, 4, 5, 6], "cell": 1}]},
            "line.ground.side": {"v": 1, "items": [{"id": "c", "k": "line", "from": [2, 7], "to": [10, 7], "style": "ground"},
                                                   {"id": "b", "k": "body", "at": [6, 4]}]},
            "vector.zero": {"v": 1, "items": [{"id": "v", "k": "vector", "from": [1, 1], "angle": 0, "len": 0}]},
            "body.move": {"v": 1, "items": [{"id": "b", "k": "body", "at": [2, 4], "move": {"to": [8, 4], "t": 2}}]},
            "focus.highlight": {"v": 1, "items": [{"id": "b", "k": "body", "at": [2, 4]},
                                                  {"id": "h", "k": "highlight", "target": "b"}],
                                "steps": [{"say": "Look.", "focus": "h"}]},
        }
        for code, scene in cases.items():
            with self.subTest(code=code):
                scene_v1_check.check(json.dumps(scene).encode())
                self.assertIn(code, codes(scene))

    def test_quiet_cases(self):
        floor = {"v": 1, "items": [{"id": "g", "k": "line", "from": [1, 1], "to": [11, 1], "style": "ground"},
                                   {"id": "b", "k": "body", "at": [6, 1.5]}]}
        self.assertEqual(codes(floor), set())
        whole = {"v": 1, "items": [{"id": "b", "k": "bars", "at": [1, 1], "w": 8, "h": 5,
                                    "bars": [{"label": "a", "value": 49}, {"label": "b", "value": 2.5}]}]}
        self.assertEqual(codes(whole), set())
        self.assertEqual(scene_lint.lint({"v": 1, "template": "bst", "params": {"values": [1]}}), [])

    def test_review_cues_are_separate_from_warnings(self):
        ceiling = {"v": 1, "items": [{"id": "c", "k": "line", "from": [2, 7], "to": [10, 7], "style": "ground"},
                                     {"id": "b", "k": "body", "at": [6, 4]}]}
        found = scene_lint.report(ceiling)
        self.assertEqual(found["warnings"], [])
        self.assertEqual([cue.split(":", 1)[0] for cue in found["cues"]], ["line.ground.side"])
        self.assertEqual(scene_lint.REVIEW_CUES, {"step0.edits", "line.ground.side", "body.move"})

    def test_rotated_box_extent(self):
        # A size-2 box at x = 1.1 fits unrotated (half side 1) but reaches 1.41 from its centre at 45 degrees.
        upright = {"v": 1, "items": [{"id": "crate", "k": "body", "at": [1.1, 4], "size": 2}]}
        tilted = {"v": 1, "items": [{"id": "crate", "k": "body", "at": [1.1, 4], "size": 2, "angle": 45}]}
        for scene in (upright, tilted):
            scene_v1_check.check(json.dumps(scene).encode())
        self.assertEqual(codes(upright), set())
        self.assertEqual(codes(tilted), {"layout.outside"})
        ball = {"v": 1, "items": [{"id": "ball", "k": "body", "at": [1.1, 4], "size": 2, "shape": "ball", "angle": 45}]}
        self.assertEqual(codes(ball), set())

    def test_layout_follows_the_shown_steps(self):
        # A legal edit moves the block off the board at step 1; the warning names that step.
        slide = {"v": 1, "items": [{"id": "block", "k": "body", "at": [6, 4], "size": 1}],
                 "steps": [{"say": "The block rests."},
                           {"say": "It slides right.", "do": [{"id": "block", "key": "at", "value": [11.8, 4]}]}]}
        scene_v1_check.check(json.dumps(slide).encode())
        self.assertEqual(scene_lint.lint(slide), ["layout.outside: block (body) extends outside the 12 x 8 world at step 1"])
        # Authored off the board but moved on in step 0: never drawn outside, so only the step 0 cue remains.
        placed = {"v": 1, "items": [{"id": "block", "k": "body", "at": [11.8, 4], "size": 1}],
                  "steps": [{"say": "Start.", "do": [{"id": "block", "key": "at", "value": [6, 4]}]}]}
        self.assertEqual(codes(placed), {"step0.edits"})
        # A wide array that is shown only after it shrinks back is never drawn outside.
        grow = {"v": 1, "items": [{"id": "a", "k": "array", "at": [6, 4], "vals": [1, 2, 3], "cell": 1}],
                "steps": [{"say": "Three values."},
                          {"say": "Fourteen values.", "do": [{"id": "a", "key": "vals", "value": list(range(14))}]}]}
        self.assertEqual(codes(grow), {"layout.outside"})
        hidden = {"v": 1, "items": [{"id": "a", "k": "array", "at": [6, 4], "vals": list(range(14)), "cell": 1},
                                    {"id": "b", "k": "body", "at": [6, 2]}],
                  "steps": [{"say": "A body.", "do": [{"id": "a", "key": "vals", "value": [1, 2]}]},
                            {"say": "Two values.", "show": ["a"]}]}
        self.assertEqual(codes(hidden), {"step0.edits"})

    def test_skipped_inputs_are_reported(self):
        template = {"v": 1, "template": "bst", "params": {"values": [5, 3, 8]},
                    "items": [{"id": "note", "k": "text", "at": [2, 1], "text": "Insert 5, 3, 8."}]}
        solid = {"v": 1, "dim": "3d", "items": [{"id": "v", "k": "vector", "from": [1, 1, 0], "dir": [1, 0, 0], "len": 2}]}
        words = {"v": 1, "items": [{"id": "t", "k": "text", "at": [6, 4], "text": "Forces on a block"},
                                   {"id": "b", "k": "body", "at": [6, 2]},
                                   {"id": "W", "k": "vector", "on": "b", "angle": 270, "len": 1}]}
        for scene in (template, solid, words):
            scene_v1_check.check(json.dumps(scene).encode())
        self.assertEqual(scene_lint.lint(template), [])
        self.assertIn("template scene", scene_lint.report(template)["skipped"][0])
        self.assertEqual(scene_lint.lint(solid), [])
        self.assertIn("3D scene", scene_lint.report(solid)["skipped"][0])
        skipped = scene_lint.report(words)["skipped"]
        self.assertEqual(len(skipped), 2)
        self.assertIn("text t", skipped[0])
        self.assertIn("vectors on an item: W", skipped[1])

    def test_authoring_guide_examples_validate_without_warnings(self):
        text = (ROOT / "docs/AUTHORING.md").read_text(encoding="utf-8")
        blocks = re.findall(r"```json\n(.*?)```", text, re.S)
        self.assertGreaterEqual(len(blocks), 4)
        for block in blocks:
            scene_v1_check.check(block.encode("utf-8"))
            self.assertEqual(scene_lint.lint(json.loads(block)), [])


if __name__ == "__main__":
    unittest.main()
