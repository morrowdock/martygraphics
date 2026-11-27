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

    def test_graph_edits_count_against_the_graph_budget(self):
        # Each graph item counts once and each step edit of one once more (Swift MGLimits.exprItems).
        graph = {"id": "f", "k": "func", "at": [1, 1], "w": 6, "h": 4, "xr": [-3, 3], "yr": [-2, 2], "y": "a*x/10", "a": 1}
        text = {"id": "t", "k": "text", "at": [8, 6], "text": "Slope"}

        def scene(graph_edits, text_edits=0):
            edits = [{"id": "f", "key": "a", "value": k + 2} for k in range(graph_edits)]
            edits += [{"id": "t", "key": "text", "value": f"Slope {k}"} for k in range(text_edits)]
            steps = [{"say": "Start."}] + [{"say": f"Step {k}.", "do": [e]} for k, e in enumerate(edits)]
            return {"v": 1, "items": [graph, text], "steps": steps}

        self.assertTrue(mg_expr.check_scene(scene(mg_expr.EXPR_ITEMS - 1)))
        self.assertTrue(mg_expr.check_scene(scene(mg_expr.EXPR_ITEMS - 1, text_edits=2)))
        with self.assertRaises(mg_expr.Refusal) as raised:
            mg_expr.check_scene(scene(mg_expr.EXPR_ITEMS))
        self.assertEqual(raised.exception.reason, "items.expr")

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

    def test_a_non_finite_midpoint_between_two_samples_splits_the_piece(self):
        # 0 is exactly the midpoint of interval 127: both grid values beside it are finite (for 1/x also inside the
        # y range, so no pole bisection runs); only the midpoint shows the gap. Mirror of GraphKindTests.
        x0, x1 = -0.99609375, 1.00390625
        self.assertEqual(mg_expr.grid_x(127, x0, x1) + mg_expr.grid_x(128, x0, x1), 0)
        for text, (y0, y1) in [("1/x", (-300, 300)), ("x/x", (0, 2))]:
            with self.subTest(text=text):
                expr = mg_expr.compile_expression(text, {"x"}, "func.y")
                curve = mg_expr.curve(lambda x: expr.value(x=x), x0, x1, y0, y1, measure=True, width=6, height=4)
                self.assertEqual(curve.starts, [129])
                self.assertEqual(len(curve.pieces()), 2)
                for lo, hi in curve.pieces():
                    xs = [p[0] for p in curve.samples[lo:hi]]
                    self.assertTrue(all(x < 0 for x in xs) or all(x > 0 for x in xs), "a piece crosses x = 0")
                self.assertFalse(curve.covers(-0.5, 0.5))
                item = {"id": "f", "k": "func", "at": [1, 1], "w": 6, "h": 4, "xr": [x0, x1], "yr": [y0, y1], "y": text}
                self.assertEqual(mg_expr.check_graph_item(item)["starts"], [129])
                with self.assertRaises(mg_expr.Refusal) as raised:
                    mg_expr.check_graph_item(dict(item, shade=[-0.5, 0.5]))
                self.assertEqual(raised.exception.reason, "func.shade")
        # The same rule at every checked instant of a moving graph.
        item = {"id": "f", "k": "func", "at": [1, 1], "w": 6, "h": 4, "xr": [x0, x1], "yr": [-300, 300],
                "y": "1/x + sin(pi*t/2)", "period": 4}
        self.assertEqual(mg_expr.check_graph_item(item)["starts"], [129])
        with self.assertRaises(mg_expr.Refusal) as raised:
            mg_expr.check_graph_item(dict(item, shade=[-0.5, 0.5]))
        self.assertEqual(raised.exception.reason, "func.shade")


class ItemRules(unittest.TestCase):
    BASE = {"func": {"id": "f", "k": "func", "at": [1, 1], "w": 6, "h": 4, "xr": [-3, 3], "yr": [-2, 2], "y": "x"},
            "field": {"id": "v", "k": "field", "at": [1, 1], "w": 6, "h": 4, "xr": [-2, 2], "yr": [-2, 2],
                      "dx": "1", "dy": "x"}}

    def reason(self, scene):
        with self.assertRaises(mg_expr.Refusal) as raised:
            mg_expr.check_scene(scene)
        return raised.exception.reason

    def test_a_three_coordinate_at_matches_swift(self):
        # MGParser.point takes three coordinates only in a 3D scene; the item is then refused as 3d.kind.<kind>.
        for kind, item in self.BASE.items():
            with self.subTest(kind=kind):
                flat = dict(item, at=[1, 1, 0])
                self.assertEqual(self.reason({"v": 1, "items": [flat]}), kind + ".at")
                self.assertEqual(self.reason({"v": 1, "dim": "3d", "items": [flat]}), "3d.kind." + kind)
                self.assertEqual(self.reason({"v": 1, "dim": "3d", "items": [item]}), "3d.kind." + kind)
                self.assertTrue(mg_expr.check_graph_item(flat, is3d=True))
                # z is still range-checked (within the world span), before the 3D refusal.
                self.assertEqual(self.reason({"v": 1, "dim": "3d", "items": [dict(item, at=[1, 1, 13])]}), kind + ".at")

    def test_a_missing_or_malformed_id_is_a_refusal(self):
        for kind, item in self.BASE.items():
            with self.subTest(kind=kind):
                missing = {k: v for k, v in item.items() if k != "id"}
                self.assertEqual(self.reason({"v": 1, "items": [missing]}), "item." + kind + ".missing")
                for bad in [3, ["f"], "", "1f", "a-b"]:
                    self.assertEqual(self.reason({"v": 1, "items": [dict(item, id=bad)]}), "item.id")
                self.assertEqual(self.reason({"v": 1, "items": [dict(item, color="pink")]}), "item.color")

    def test_out_of_range_integers_are_refused_with_the_key_reason(self):
        big = 10 ** 400
        func, field = self.BASE["func"], self.BASE["field"]
        cases = [
            (dict(func, w=big), "func.w"),
            (dict(func, h=-big), "func.h"),
            (dict(func, xr=[0, big]), "func.xr"),
            (dict(func, at=[big, 1]), "func.at"),
            (dict(func, a=big), "func.a"),
            (dict(func, period=big), "func.period"),
            (dict(func, mark=big), "func.mark"),
            (dict(func, shade=[0, big]), "func.shade"),
            (dict(field, n=[big, 3]), "field.n"),
            (dict(field, yr=[-big, 2]), "field.yr"),
        ]
        for item, reason in cases:
            with self.subTest(reason=reason):
                self.assertEqual(self.reason({"v": 1, "items": [item]}), reason)
        self.assertEqual(self.reason({"v": 1, "world": {"w": big, "h": 8}, "items": [func]}), "world.w")
        # An in-range int is still accepted and converted.
        self.assertTrue(mg_expr.check_scene({"v": 1, "world": {"w": 12, "h": 8}, "items": [dict(func, w=6, a=2)]}))


if __name__ == "__main__":
    unittest.main()
