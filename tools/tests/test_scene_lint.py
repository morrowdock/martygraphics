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

    def test_authoring_guide_examples_validate_without_warnings(self):
        text = (ROOT / "docs/AUTHORING.md").read_text(encoding="utf-8")
        blocks = re.findall(r"```json\n(.*?)```", text, re.S)
        self.assertGreaterEqual(len(blocks), 4)
        for block in blocks:
            scene_v1_check.check(block.encode("utf-8"))
            self.assertEqual(scene_lint.lint(json.loads(block)), [])


if __name__ == "__main__":
    unittest.main()
