# SPDX-License-Identifier: Apache-2.0
"""The offline mirror of the func / field / alt rules agrees with the shared golden cases.

The same files are checked against Swift (the authority) by Tests/MartyGraphicsTests/ExpressionTests.swift and
GraphCaseTests.swift; together the two runs show the mirror and the engine give the same values and reasons.
"""

import json
import math
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))

import mg_expr  # noqa: E402

CASES = ROOT / "docs" / "fixtures" / "v1"


def load(name):
    return json.loads((CASES / name).read_text(encoding="utf-8"))


def same(actual, expected):
    if expected == "nan":
        return math.isnan(actual)
    if expected == "inf":
        return actual == math.inf
    if expected == "-inf":
        return actual == -math.inf
    return math.isfinite(actual) and abs(actual - expected) <= 1e-12 * max(1.0, abs(expected))


class ExpressionCases(unittest.TestCase):
    def test_values(self):
        cases = load("expressions.cases.json")["values"]
        self.assertGreater(len(cases), 40)
        for case in cases:
            with self.subTest(text=case["text"]):
                expr = mg_expr.compile_expression(case["text"], set(mg_expr.VARIABLES), "func.y")
                inputs = {k: case[k] for k in mg_expr.VARIABLES if k in case}
                self.assertTrue(same(expr.value(**inputs), case["value"]), (expr.value(**inputs), case["value"]))

    def test_refusals(self):
        cases = load("expressions.cases.json")["refusals"]
        self.assertGreater(len(cases), 30)
        for case in cases:
            with self.subTest(text=case["text"]):
                allowed = set(case.get("allowed", "x"))
                if case["reason"] is None:
                    mg_expr.compile_expression(case["text"], allowed, "func.y")
                    continue
                with self.assertRaises(mg_expr.Refusal) as raised:
                    mg_expr.compile_expression(case["text"], allowed, "func.y")
                self.assertEqual(raised.exception.reason, case["reason"])

    def test_bounds_are_the_documented_ones(self):
        self.assertEqual((mg_expr.EXPR_LENGTH, mg_expr.EXPR_TOKENS, mg_expr.EXPR_DEPTH), (80, 48, 8))
        self.assertEqual((mg_expr.FUNC_INTERVALS, mg_expr.FUNC_BREAKS, mg_expr.FUNC_TOLERANCE), (256, 16, 0.01))
        self.assertEqual((mg_expr.EXPR_ITEMS, mg_expr.FIELD_COLS, mg_expr.FIELD_ROWS), (6, 16, 12))

    def test_the_grammar_never_evaluates_python(self):
        # Names outside the closed vocabulary are refused before anything is evaluated.
        for text in ["__import__", "open(x)", "eval(x)", "x.real", "lambda", "exec(x)"]:
            with self.subTest(text=text), self.assertRaises(mg_expr.Refusal):
                mg_expr.compile_expression(text, {"x"}, "func.y")


class GraphCases(unittest.TestCase):
    def test_accepted_items(self):
        cases = load("graphs.cases.json")["accepted"]
        self.assertGreater(len(cases), 15)
        for case in cases:
            with self.subTest(case=case["name"]):
                summary = mg_expr.check_graph_item(case["item"])
                if case["item"]["k"] == "func":
                    self.assertEqual(summary["samples"], case["samples"])
                    self.assertEqual(summary["starts"], case["starts"])
                    if "mark" in case:
                        self.assertTrue(same(summary["mark"], case["mark"]))
                else:
                    self.assertEqual((summary["cols"], summary["rows"]), (case["cols"], case["rows"]))
                    self.assertEqual(summary["missing"], case["missing"])
                    if "vectors" in case:
                        self.assertEqual([list(v) for v in summary["vectors"]], case["vectors"])

    def test_refused_scenes(self):
        cases = load("graphs.cases.json")["refused"]
        self.assertGreater(len(cases), 40)
        for case in cases:
            with self.subTest(case=case["name"]):
                with self.assertRaises(mg_expr.Refusal) as raised:
                    mg_expr.check_scene(case["scene"])
                self.assertEqual(raised.exception.reason, case["reason"])

    def test_documentation_scenes_pass(self):
        for name in ["graphs.scene.json", "wave.scene.json"]:
            with self.subTest(name=name):
                summaries = mg_expr.check_scene(load(name))
                self.assertTrue(summaries)

    def test_a_pole_is_never_joined(self):
        expr = mg_expr.compile_expression("1/x", {"x"}, "func.y")
        curve = mg_expr.curve(lambda x: expr.value(x=x), -2, 3, -5, 5, measure=True, width=6, height=4)
        for lo, hi in curve.pieces():
            xs = [p[0] for p in curve.samples[lo:hi]]
            self.assertTrue(all(x < 0 for x in xs) or all(x > 0 for x in xs), "a piece crosses x = 0")

    def test_a_removable_hole_is_one_probe_wide(self):
        expr = mg_expr.compile_expression("sin(x)/x", {"x"}, "func.y")
        curve = mg_expr.curve(lambda x: expr.value(x=x), -10, 10, -0.5, 1.2, measure=True, width=6, height=4)
        (_, end), (start, _) = curve.pieces()
        gap = curve.samples[start][0] - curve.samples[end - 1][0]
        self.assertAlmostEqual(gap, 2 * 20 / 256 / 1024)


if __name__ == "__main__":
    unittest.main()
