# SPDX-License-Identifier: Apache-2.0
"""The author-independent counts in RESULTS.md must be what `inventory.py` recomputes from checked-in files.

    python -m unittest discover -s tools -p "test_*.py"
"""

import json
from pathlib import Path
import re
import sys
import unittest

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import inventory  # noqa: E402


class AuthorIndependentCounts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.summary = inventory.summary()
        cls.results = (HERE.parent / "RESULTS.md").read_text(encoding="utf-8")

    def test_conventions(self):
        counts = self.summary["conventions"]
        self.assertEqual((counts["total"], counts["current"]), (17, 17))
        data = json.loads(inventory.CONVENTIONS.read_text(encoding="utf-8"))
        recorded = sum(c["baselineProbeMatch"] for c in data["conventions"])
        self.assertEqual(recorded, 1)
        if counts["baseline"] is None:
            self.skipTest("no git history: the baseline prose at the base commit cannot be read")
        base = inventory.baseline_text(data)
        self.assertEqual(inventory.probe_matches(data, base), {c["id"]: c["baselineProbeMatch"] for c in data["conventions"]})
        self.assertIn("| 1 / 17 | 17 / 17 |", self.results)

    def test_reasons(self):
        self.assertEqual(self.summary["sceneReasons"], {"tokens": 218, "baselineDetails": 3, "hinted": 218})
        self.assertEqual(self.summary["mlReasons"], {"total": 58, "baseline": 0, "hinted": 58})
        self.assertIn("[218 sample tokens]", self.results)
        self.assertIn("| 0 / 58 | 58 / 58 |", self.results)
        self.assertNotRegex(self.results, r"\| 148 \|")

    def test_lint(self):
        baseline, improved = self.summary["lint"]["baseline"], self.summary["lint"]["improved"]
        self.assertEqual((baseline["scenes"], baseline["warnings"], baseline["cues"]), (32, 4, 6))
        self.assertEqual(baseline["notChecked"], ["C02", "C03"])
        self.assertEqual(baseline["flagged"], {"C04": ["step0.edits"], "C05": ["step0.edits"], "C06": ["step0.edits"],
                                               "C08": ["step0.edits"], "M09": ["display.rounding"],
                                               "P03": ["line.ground.side"], "P11": ["line.ground.side"]})
        self.assertEqual((improved["warnings"], improved["cues"], improved["flagged"]), (0, 0, {}))
        self.assertIn("10 findings in 7 of 32 scenes: 4 warnings", self.results)

    def test_no_accuracy_gain_wording(self):
        for text in (self.results, (HERE.parents[2] / "CHANGELOG.md").read_text(encoding="utf-8")):
            self.assertIsNone(re.search(r"one-request gain|measured gain|39/40 and 40/40|show the order", text))


if __name__ == "__main__":
    unittest.main()
