# SPDX-License-Identifier: Apache-2.0
"""The offline mirror of math text agrees with the shared golden cases.

The same file is checked against Swift (the authority) by Tests/MartyGraphicsTests/MathTextTests.swift; together the
two runs show the mirror and the engine give the same spoken forms and reasons.
"""

import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))

import mg_math  # noqa: E402
import scene_v1_check  # noqa: E402

CASES = json.loads((ROOT / "docs/fixtures/v1/math.cases.json").read_text(encoding="utf-8"))


def scene(text, **extra):
    item = {"id": "eq", "k": "text", "at": [6, 4], "text": text, "style": "math"}
    return {"v": 1, "items": [item], **extra}


class MathCases(unittest.TestCase):
    def test_spoken_forms(self):
        self.assertGreaterEqual(len(CASES["spoken"]), 40)
        for case in CASES["spoken"]:
            with self.subTest(text=case["text"]):
                self.assertEqual(mg_math.spoken(case["text"]), case["spoken"])

    def test_refusals(self):
        self.assertGreaterEqual(len(CASES["refusals"]), 30)
        for case in CASES["refusals"]:
            with self.subTest(text=case["text"]):
                with self.assertRaises(mg_math.Refusal) as caught:
                    mg_math.spoken(case["text"])
                self.assertEqual(caught.exception.reason, case["reason"])

    def test_every_reason_is_covered(self):
        reasons = {case["reason"] for case in CASES["refusals"]}
        self.assertEqual(reasons, {"text.math", "text.math.syntax", "text.math.tokens", "text.math.depth",
                                   "text.math.name", "text.math.unit"})

    def test_limits(self):
        self.assertEqual((mg_math.MATH_LENGTH, mg_math.MATH_TOKENS, mg_math.MATH_DEPTH), (80, 48, 4))
        texts = {case["text"] for case in CASES["spoken"]}
        self.assertTrue(any(len(t) == mg_math.MATH_LENGTH for t in texts))
        self.assertTrue(any(len(mg_math._tokenize(t)) == mg_math.MATH_TOKENS for t in texts))
        self.assertTrue(any(mg_math.depth(mg_math.parse(t)) == mg_math.MATH_DEPTH for t in texts))

    def test_vocabulary_matches_the_swift_tables(self):
        source = (ROOT / "Sources/MartyGraphics/MGMathText.swift").read_text(encoding="utf-8")
        for name, letter in mg_math.GREEK:
            self.assertIn(f'("{name}", "{letter}")', source)
        for name, symbol, one, many in mg_math.UNITS:
            self.assertIn(f'("{name}", "{symbol}", "{one}", "{many}")', source)
        for name, spoken in mg_math.FUNCTIONS.items():
            self.assertIn(f'case .{name}: return ("', source)
            self.assertIn(f'"{spoken}")', source)
        limits = (ROOT / "Sources/MartyGraphics/MGParser.swift").read_text(encoding="utf-8")
        self.assertIn("public static let mathLength = 80, mathTokens = 48, mathDepth = 4", limits)


class MathInScenes(unittest.TestCase):
    def reason(self, data):
        try:
            scene_v1_check.check(json.dumps(data).encode("utf-8"))
        except scene_v1_check.Invalid as error:
            return str(error)
        return None

    def test_accepted_and_refused_math_text(self):
        self.assertIsNone(self.reason(scene("y = a sin(x)")))
        self.assertIsNone(self.reason(scene("  v = 9.8 [m/s^2]\n")))
        self.assertEqual(self.reason(scene("ma")), "text.math.name")
        self.assertEqual(self.reason(scene("x = {v}")), "text.text.placeholder.v")
        self.assertEqual(self.reason(scene("[kgs]")), "text.math.unit")
        self.assertEqual(self.reason(scene("x < 1")), "text.text")
        self.assertEqual(self.reason(scene("x^2", dim="3d")), "3d.text.math")
        code = scene("i += 1", dim="3d")
        code["items"][0]["style"] = "code"
        self.assertEqual(self.reason(code), "3d.text.code")
        misspelt = scene("x^2")
        misspelt["items"][0]["style"] = "maths"
        self.assertEqual(self.reason(misspelt), "text.style")


if __name__ == "__main__":
    unittest.main()
