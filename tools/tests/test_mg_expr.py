# SPDX-License-Identifier: Apache-2.0
"""The offline mirror of the func / field / alt rules agrees with the shared golden cases.

The same files are checked against Swift (the authority) by Tests/MartyGraphicsTests/ExpressionTests.swift and
GraphCaseTests.swift; together the two runs show the mirror and the engine give the same values and reasons.
"""

import json
import math
from fractions import Fraction
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
        for name in ["graphs.scene.json", "wave.scene.json", "calculus.scene.json"]:
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


class SliderCases(unittest.TestCase):
    """The `sliders` key against docs/fixtures/v1/sliders.cases.json (Swift: Tests/MartyGraphicsTests/SliderTests.swift)."""

    def test_limits_match_swift(self):
        self.assertEqual((mg_expr.SLIDERS, mg_expr.SLIDER_STEPS, mg_expr.SLIDER_BINDINGS), (3, 100, 6))
        self.assertEqual(sorted(mg_expr.SLIDER_KEYS), ["default", "label", "max", "min", "param", "step"])

    def test_accepted_scenes(self):
        cases = load("sliders.cases.json")["accepted"]
        self.assertGreaterEqual(len(cases), 7)
        for case in cases:
            with self.subTest(case=case["name"]):
                mg_expr.check_scene(case["scene"])
                self.assertEqual(mg_expr.check_sliders(case["scene"]), case["sliders"])

    def test_refused_scenes(self):
        cases = load("sliders.cases.json")["refused"]
        self.assertGreaterEqual(len(cases), 41)
        for case in cases:
            with self.subTest(case=case["name"]):
                with self.assertRaises(mg_expr.Refusal) as raised:
                    mg_expr.check_scene(case["scene"])
                self.assertEqual(raised.exception.reason, case["reason"])

    def test_documentation_scene_passes(self):
        scene = load("sliders.scene.json")
        self.assertEqual(mg_expr.check_scene(scene)["wave"]["samples"], 257)
        self.assertEqual([s["param"] for s in mg_expr.check_sliders(scene)], ["a", "b", "c"])

    def test_a_template_scene_checks_each_slider_alone(self):
        slider = {"param": "a", "min": 0, "max": 1, "step": 0.5, "default": 0, "label": "a"}
        scene = {"v": 1, "template": "bst", "params": {"values": [1]}, "sliders": [slider]}
        self.assertEqual(mg_expr.check_sliders(scene, literal=False),
                         [{"param": "a", "steps": 2, "defaultStop": 0, "items": []}])
        with self.assertRaises(mg_expr.Refusal) as raised:
            mg_expr.check_sliders(dict(scene, sliders=[dict(slider, step=0.3)]), literal=False)
        self.assertEqual(raised.exception.reason, "slider.step")

    def test_huge_and_tiny_numbers_are_refusals(self):
        slider = {"param": "a", "min": 0, "max": 1, "step": 0.5, "default": 0, "label": "a"}
        for change, reason in [({"min": -10 ** 400}, "slider.min"), ({"step": 10 ** 400}, "slider.step"),
                               ({"step": 5e-324}, "slider.step.count"), ({"default": 10 ** 400}, "slider.default"),
                               ({"step": True}, "slider.step"), ({"label": 3}, "slider.label")]:
            with self.subTest(reason=reason, change=str(change)[:40]):
                with self.assertRaises(mg_expr.Refusal) as raised:
                    mg_expr.check_slider(dict(slider, **change))
                self.assertEqual(raised.exception.reason, reason)
        # Unknown keys are named the way Swift names them: sorted, at most four, odd names as `?`.
        with self.assertRaises(mg_expr.Refusal) as raised:
            mg_expr.check_slider(dict(slider, z=1, y=1, x=1, w=1, v=1))
        self.assertEqual(raised.exception.reason, "slider.unknown.v,w,x,y")
        with self.assertRaises(mg_expr.Refusal) as raised:
            mg_expr.check_slider(dict(slider, **{"a-b": 1}))
        self.assertEqual(raised.exception.reason, "slider.unknown.?")

    def test_stops_finer_than_the_doubles_are_refused(self):
        # Four steps from 1 to the third double above it: stops 0 and 1 are both 1 (SliderTests, the same case).
        slider = {"param": "a", "min": 1, "max": 1.0000000000000004, "step": 1.1102230246251565e-16, "default": 1,
                  "label": "a"}
        with self.assertRaises(mg_expr.Refusal) as raised:
            mg_expr.check_slider(slider)
        self.assertEqual(raised.exception.reason, "slider.grid")

    def test_a_nonzero_value_is_never_written_as_zero(self):
        grid = mg_expr.SliderGrid(-1.0, 1.0, 1.0, 2)
        self.assertEqual(grid.text(1e-12), "1e-12")
        self.assertEqual(grid.text(-1e-12), "-1e-12")
        self.assertEqual(grid.text(-0.0), "0")
        # A default within tolerance of the stop 0 but not 0 is refused: it is not written as its stop is.
        slider = {"param": "a", "min": -1, "max": 1, "step": 1, "default": 1e-12, "label": "a"}
        with self.assertRaises(mg_expr.Refusal) as raised:
            mg_expr.check_slider(slider)
        self.assertEqual(raised.exception.reason, "slider.default")
        # A stop meant to be 0 is 0, not the 4.4e-16 that min + (max - min) * 26 / 52 gives.
        wide = mg_expr.SliderGrid(-2.6, 2.6, 0.1, 52)
        self.assertEqual(wide.value_at(26), 0.0)
        self.assertEqual(wide.text(wide.value_at(26)), "0")
        self.assertTrue(wide.is_distinct())

    def test_an_end_the_slider_cannot_show_exactly_is_refused(self):
        # Codex: 0 to 1.0000000002 in one step shows its last stop as `1`, so the engine would get 1.0000000002 under
        # a label of 1. At exactly 1 the graph y = 0.0000000001/(a-1) is refused, at 1.0000000002 it is drawn.
        grid = mg_expr.SliderGrid(0.0, 1.0000000002, 1.0, 1)
        self.assertEqual(grid.text(1.0000000002), "1")
        self.assertEqual(grid.value_at(1), 1.0)
        self.assertFalse(grid.is_distinct())
        graph = {"id": "f", "k": "func", "at": [1, 1], "w": 10, "h": 6, "xr": [-3, 3], "yr": [-4, 4],
                 "y": "0.0000000001/(a-1)", "a": 0}
        self.assertTrue(mg_expr.check_graph_item(dict(graph, a=1.0000000002), (12.0, 8.0), False))
        with self.assertRaises(mg_expr.Refusal) as raised:
            mg_expr.check_graph_item(dict(graph, a=1), (12.0, 8.0), False)
        self.assertEqual(raised.exception.reason, "func.empty")
        # Refused whatever the default: a default of 1 (shown as max) no longer stands in for max.
        for default in (0, 1):
            with self.subTest(default=default):
                with self.assertRaises(mg_expr.Refusal) as raised:
                    mg_expr.check_slider({"param": "a", "min": 0, "max": 1.0000000002, "step": 1, "default": default,
                                          "label": "a"})
                self.assertEqual(raised.exception.reason, "slider.grid")

    def test_the_default_is_exactly_a_stop_and_never_replaces_one(self):
        slider = {"param": "a", "min": 0, "max": 1, "step": 0.1, "default": 0.30000000000000004, "label": "a"}
        with self.assertRaises(mg_expr.Refusal) as raised:
            mg_expr.check_slider(slider)
        self.assertEqual(raised.exception.reason, "slider.default")
        self.assertEqual(mg_expr.check_slider(dict(slider, default=0.3))[5:], (10, 3))
        # value_at never returns the default in place of the stop's own value.
        grid = mg_expr.SliderGrid(0.0, 1.0, 0.1, 10, initial=0.30000000000000004, default_stop=3)
        self.assertEqual(grid.value_at(3), 0.3)
        self.assertEqual(mg_expr.SliderGrid(0.0, 1.0, 1.0, 1, initial=0.9999999999, default_stop=1).value_at(1), 1.0)

    def test_the_engine_gets_exactly_the_shown_value_on_ordinary_grids(self):
        # Every grid an author would write from these mins, steps and step counts (max written to six places):
        # label -> float is the engine value, the stops rise strictly from exactly min to exactly max, and each stop
        # is accepted as the default at its own position.
        checked = 0
        for lo in (-1000, -10, -3, -2.6, -1, -0.5, -0.3, 0, 0.1, 0.25, 1, 2.5, 100):
            for step in (0.001, 0.01, 0.02, 0.05, 0.1, 0.125, 0.2, 0.25, 0.5, 1, 5, 20):
                for n in (2, 3, 4, 5, 7, 10, 13, 30, 64, 100):
                    hi = float("%.6f" % (lo + n * step))
                    if hi > 1000:
                        continue
                    with self.subTest(lo=lo, hi=hi, step=step):
                        slider = {"param": "a", "min": lo, "max": hi, "step": step, "default": lo, "label": "a"}
                        steps = mg_expr.check_slider(slider)[5]
                        self.assertEqual(steps, n)
                        grid = mg_expr.SliderGrid(float(lo), hi, float(step), steps)
                        values = [grid.value_at(i) for i in range(steps + 1)]
                        self.assertEqual((values[0], values[-1]), (lo, hi))
                        self.assertTrue(all(a < b for a, b in zip(values, values[1:])))
                        for i, v in enumerate(values):
                            self.assertEqual(float(grid.text(v)), v)
                            self.assertEqual(grid.text(grid.candidate_at(i)), grid.text(v))
                        for i in (0, n // 2, n):
                            self.assertEqual(mg_expr.check_slider(dict(slider, default=values[i]))[6], i)
                        checked += 1
        self.assertGreater(checked, 1000)


def near(actual, expected, tolerance=1e-12):
    """A closed-form readout: within `tolerance` relative (absolute below 1)."""
    return math.isfinite(actual) and abs(actual - expected) <= tolerance * max(1.0, abs(expected))


class ReadoutCases(unittest.TestCase):
    """The shared readout cases (docs/fixtures/v1/readouts.cases.json); ReadoutCaseTests.swift checks the same file."""

    def test_derivatives_match_the_closed_forms(self):
        cases = load("readouts.cases.json")["derivatives"]
        self.assertGreater(len(cases), 35)
        for case in cases:
            with self.subTest(text=case["text"], x=case["x"]):
                expr = mg_expr.compile_expression(case["text"], set(mg_expr.VARIABLES), "func.y")
                inputs = {k: case[k] for k in mg_expr.VARIABLES if k in case}
                value, slope = expr.value_and_slope(**inputs)
                self.assertTrue(same(value, case["value"]), (value, case["value"]))
                self.assertTrue(same(slope, case["slope"]), (slope, case["slope"]))
                # The value comes from the same operations as `value`.
                plain = expr.value(**inputs)
                self.assertTrue(value == plain or (math.isnan(value) and math.isnan(plain)))

    def test_the_dual_value_is_the_plain_value_for_every_expression_case(self):
        for case in load("expressions.cases.json")["values"]:
            with self.subTest(text=case["text"]):
                expr = mg_expr.compile_expression(case["text"], set(mg_expr.VARIABLES), "func.y")
                inputs = {k: case[k] for k in mg_expr.VARIABLES if k in case}
                value, plain = expr.value_and_slope(**inputs)[0], expr.value(**inputs)
                self.assertTrue(value == plain or (math.isnan(value) and math.isnan(plain)), (value, plain))

    def test_accepted_items_give_the_closed_forms(self):
        cases = load("readouts.cases.json")["accepted"]
        self.assertGreater(len(cases), 15)
        for case in cases:
            with self.subTest(case=case["name"]):
                readouts = mg_expr.check_graph_item(case["item"])["readouts"]
                self.assertEqual(sorted(readouts), sorted(case["readouts"]))
                for name, expected in case["readouts"].items():
                    tolerance = case.get("tolerance", {}).get(name, 1e-12)
                    self.assertTrue(near(readouts[name], expected, tolerance), (name, readouts[name], expected))
                    self.assertEqual(mg_expr.format_number(readouts[name]), case["shown"][name], name)

    def test_refused_scenes(self):
        cases = load("readouts.cases.json")["refused"]
        self.assertGreater(len(cases), 25)
        for case in cases:
            with self.subTest(case=case["name"]):
                with self.assertRaises(mg_expr.Refusal) as raised:
                    mg_expr.check_scene(case["scene"])
                self.assertEqual(raised.exception.reason, case["reason"])

    def test_filled_texts(self):
        limits = {"title": (60, False), "alt": (mg_expr.SAY, False), "say": (mg_expr.SAY, True),
                  "text": (120, True), "label": (mg_expr.LABEL, False)}
        for case in load("readouts.cases.json")["filled"]:
            with self.subTest(case=case["name"]):
                scene = case["scene"]
                summaries = mg_expr.check_scene(scene)
                values = {f"{i}.{name}": v for i, summary in summaries.items()
                          for name, v in summary.get("readouts", {}).items()}
                for path, expected in case["texts"].items():
                    parts = path.split(".")
                    if parts[0] == "items":
                        raw = next(item for item in scene["items"] if item["id"] == parts[1])[parts[2]]
                    elif parts[0] == "steps":
                        raw = scene["steps"][int(parts[1])][parts[2]]
                    else:
                        raw = scene[parts[0]]
                    limit, multiline = limits[parts[-1]]
                    self.assertEqual(mg_expr.text_rules(raw, limit, path, values, multiline), expected, path)

    def test_the_one_sided_rules(self):
        def local(text, x):
            return mg_expr.compile_expression(text, set(mg_expr.VARIABLES), "func.y").local(x=x)
        # Both sides of a smooth composition are the same number; a corner's are not, however small it is.
        self.assertEqual(local("x*abs(x)", 0)[1:3], (0.0, 0.0))
        self.assertEqual(local("abs(x)", 0)[1:3], (-1.0, 1.0))
        self.assertEqual(local("min(x, x^3)", 1)[1:3], (3.0, 1.0))
        for scale in ("1", "0.001", "0.000001", "0.0000000001"):
            with self.subTest(scale=scale):
                _, left, right, _ = local(scale + "*abs(x)", 0)
                self.assertNotEqual(left, right)
        # A power's exponent is constant only when it does not read x, never because its derivative is 0 at a point.
        self.assertEqual(local("(x - 1)^2", 0)[1:3], (-2.0, -2.0))
        self.assertTrue(math.isnan(local("(x - 1)^(2 + x^2)", 0)[2]))
        # The sides of the kinks, poles and domain edges, in program order (x, 1, -, abs: the abs is at its kink).
        self.assertEqual(local("abs(x - 1)", 1)[3], [0, 0, 0, 0])
        self.assertEqual(local("abs(x - 1)", 1.5)[3], [0, 0, 0, 1])
        self.assertIsNone(local("sqrt(x)^0", -1)[3])

    def test_the_view_check_reads_every_sample(self):
        # f leaves the y range only at the first node of the coarser rule: the band would be clipped there.
        node = 1 / 128 + 1 / 128 * mg_expr.GAUSS_NODES[0]
        with self.assertRaises(mg_expr.Refusal) as raised:
            mg_expr.area_readout(lambda x: 1.0 if x == node else 0.0, lambda a, b: (0.0, 0.0), 0.0, 1.0, -0.5, 0.5)
        self.assertEqual(raised.exception.reason, "func.readouts.view")

    def test_the_certification_is_bounded(self):
        def run(enclose):
            used = []

            def counted(a, b):
                used.append(b - a)
                return enclose(a, b)
            try:
                mg_expr.certify_area(counted, 0.0, 1.0, -1.0, 1.0)
            except mg_expr.Refusal as refusal:
                return refusal.reason, len(used)
            return None, len(used)
        # Depth first: a cell that never certifies is refused after CERTIFY_DEPTH halvings (11 enclosures).
        self.assertEqual(run(lambda a, b: None), ("func.readouts.area", 11))
        self.assertEqual(run(lambda a, b: (5.0, 6.0)), ("func.readouts.view", 11))
        # Within the drawing tolerance (1 % of the y range) a cell is certified.
        self.assertEqual(run(lambda a, b: (-1.02, 1.02)), (None, 1))
        self.assertEqual(run(lambda a, b: (-1.03, 1.0)), ("func.readouts.view", 11))
        # Cells of 1/512 and narrower certify: 1,023 cells would be needed, so the budget refuses it after 256.
        self.assertEqual(run(lambda a, b: (0.0, 0.0) if b - a <= 1 / 512 else None),
                         ("func.readouts.area", mg_expr.CERTIFY_BUDGET))
        self.assertEqual(run(lambda a, b: (0.0, 0.0) if b - a <= 1 / 64 else None), (None, 127))

    def test_enclosures_hold_every_value(self):
        cases = [("x^3 - 2*x", -2.0, 2.5), ("sin(x) + cos(3*x)", -4.0, 4.0), ("abs(x - 1)*exp(-x)", -1.0, 3.0),
                 ("tan(x)", -1.5, 1.5), ("min(x, x^2) - max(x, 0.5)", -2.0, 2.0), ("(x + 3)^x", 0.0, 2.0),
                 ("x^4 - x^2", -1.5, 1.5), ("sqrt(x) + ln(x + 1)", 0.0, 4.0), ("cosh(x) - 2", -2.0, 2.0)]
        for text, x0, x1 in cases:
            expr = mg_expr.compile_expression(text, set(mg_expr.VARIABLES), "func.y")
            for k in range(16):
                a, b = x0 + (x1 - x0) * k / 16, x0 + (x1 - x0) * (k + 1) / 16
                lo, hi = expr.enclosure(a, b)
                with self.subTest(text=text, cell=k):
                    for j in range(33):
                        v = expr.value(x=a + (b - a) * j / 32)
                        self.assertTrue(lo <= v <= hi, (v, lo, hi))
        expr = mg_expr.compile_expression("1/(x - 0.3)", {"x"}, "func.y")
        self.assertIsNone(expr.enclosure(0.25, 0.5))
        self.assertIsNotNone(expr.enclosure(0.31, 0.5))

    def test_enclosures_round_outward(self):
        def enclosure(text, a, b):
            return mg_expr.compile_expression(text, {"x"}, "func.y").enclosure(a, b)
        # In double precision (10^20 + x) - 10^20 is 0 for |x| < 8192. The enclosure still holds the analytic x, so the
        # divisor x + 1 below has no enclosure over [-2, 2]: it is 0 at -1.
        lo, hi = enclosure("(10^20 + x) - 10^20", -2.0, 2.0)
        self.assertTrue(lo <= -2 and hi >= 2, (lo, hi))
        self.assertIsNone(enclosure("1/(((10^20+x)-10^20)+1)", -2.0, 2.0))
        # An inexact result is bounded by the doubles on either side of it: 0.1 + 0.2 and 3 * 0.1 are both exactly
        # 0.3000000000000000166..., between 0.3 and 0.30000000000000004.
        for text in ("x + 0.2", "3*x"):
            self.assertEqual(enclosure(text, 0.1, 0.1), (0.3, 0.30000000000000004), text)
        # An exact result stays exact, so a domain edge at an end of the interval is still inside the domain.
        self.assertEqual(enclosure("x - 1", 1.0, 2.0), (0.0, 1.0))
        self.assertEqual(enclosure("1 - x^2", -1.0, 1.0), (0.0, 1.0))
        self.assertEqual(enclosure("sqrt(1 - x^2)", -1.0, 1.0)[0], 0.0)
        self.assertIsNotNone(enclosure("asin(x/2)", -2.0, 2.0))
        # A library function widens by LIBRARY_ULPS to each side.
        v = math.exp(1.0)
        self.assertEqual(enclosure("exp(x)", 1.0, 1.0), (v - 4 * math.ulp(v), v + 4 * math.ulp(v)))

    def test_the_directed_operations_bound_the_exact_result(self):
        values = [0.1, 0.2, 0.3, 1.0, 3.0, -0.7, 1e-300, 1e300, 2.0 ** -1000, 123456.789, -2.5e-8, 7.0]
        operations = [(mg_expr._sum, lambda u, v: Fraction(u) + Fraction(v)),
                      (mg_expr._product, lambda u, v: Fraction(u) * Fraction(v)),
                      (mg_expr._quotient, lambda u, v: Fraction(u) / Fraction(v))]
        for left in values:
            for right in values:
                for function, exact in operations:
                    lo, hi = function(left, right, False), function(left, right, True)
                    if not (math.isfinite(lo) and math.isfinite(hi)):
                        continue
                    with self.subTest(function=function.__name__, left=left, right=right):
                        self.assertTrue(Fraction(lo) <= exact(left, right) <= Fraction(hi), (lo, hi))
                        if abs(lo) >= mg_expr.EXACT_LIMIT and abs(left) >= mg_expr.EXACT_LIMIT:
                            # Tight: the rounded result and its neighbour on the side of the exact result, or one
                            # double when it is exact. Below EXACT_LIMIT both bounds move outward.
                            self.assertIn(hi, (lo, math.nextafter(lo, math.inf)))
        self.assertEqual(mg_expr._whole_power(3.0, 5.0, False), 243.0)
        # 0.1 * 0.1 is exactly 0.0100000000000000011102..., between 0.01 and 0.010000000000000002.
        self.assertEqual(mg_expr._whole_power(0.1, 2.0, False), 0.01)
        self.assertEqual(mg_expr._whole_power(0.1, 2.0, True), 0.010000000000000002)

    def test_poles_and_peaks_count_when_they_may_be_inside(self):
        # tan's pole at 22.5 pi lies between these two adjacent doubles; the plain double-precision test misses it.
        a, b = 70.68583470577035, 70.68583470577036
        self.assertEqual(math.nextafter(a, math.inf), b)
        self.assertFalse(math.ceil((a - math.pi / 2) / math.pi) <= math.floor((b - math.pi / 2) / math.pi))
        self.assertTrue(mg_expr._may_hold(a, b, math.pi / 2, math.pi))
        self.assertIsNone(mg_expr._enclose1("tan", a, b))
        self.assertIsNotNone(mg_expr._enclose1("tan", 70.0, 70.6))
        self.assertFalse(mg_expr._may_hold(0.0, 1.5, math.pi / 2, math.pi))

    def test_the_slope_certifies_both_halves_of_the_probe_interval(self):
        probe = 4 / mg_expr.FUNC_INTERVALS / 1024  # xr [-2, 2]
        expr = mg_expr.compile_expression("abs((x-0.000003)*(x-0.000006))", {"x"}, "func.y")
        # The abs argument is on the same side at the mark and at both probes, where the old three-point check looked...
        for x in (-probe, 0.0, probe):
            self.assertEqual(expr.local(x=x)[3][-1], 1)
        # ...but crosses 0 twice in between: its enclosure over [0, probe] holds both signs.
        self.assertEqual(mg_expr._strict_side(expr.intervals(-probe, 0.0)[1][-1]), 1)
        self.assertEqual(mg_expr._strict_side(expr.intervals(0.0, probe)[1][-1]), 0)
        # x*abs(x) at 0: the abs is at its kink at the mark and on one side of it over each half (x, x, abs, *).
        expr = mg_expr.compile_expression("x*abs(x)", {"x"}, "func.y")
        self.assertEqual(expr.intervals(-probe, 0.0)[1], [None, None, (-probe, 0.0), None])
        self.assertEqual(expr.intervals(0.0, probe)[1], [None, None, (0.0, probe), None])

    def test_the_bounds_are_the_documented_ones(self):
        self.assertEqual((mg_expr.READOUTS, mg_expr.READOUT_PANELS), (("value", "slope", "area"), 128))
        self.assertEqual((mg_expr.CERTIFY_DEPTH, mg_expr.CERTIFY_BUDGET), (10, 256))
        self.assertAlmostEqual(sum(mg_expr.GAUSS_WEIGHTS), 2.0, places=15)
        # 5 points integrate x^8 exactly on [-1, 1].
        self.assertAlmostEqual(sum(w * x ** 8 for x, w in zip(mg_expr.GAUSS_NODES, mg_expr.GAUSS_WEIGHTS)), 2 / 9, places=15)

    def test_the_numbers_are_shown_as_the_engine_shows_them(self):
        for value, shown in [(0.375, "0.38"), (2.0, "2"), (-0.004, "0"), (12.34, "12.3"), (-1000.4, "-1000"),
                             (99.96, "100"), (1e12, "1000000000000"), (math.nan, "\u2014")]:
            with self.subTest(value=value):
                self.assertEqual(mg_expr.format_number(value), shown)

    def test_a_readout_placeholder_needs_an_id_and_a_known_name(self):
        self.assertEqual(mg_expr.readout_placeholder("wave.area"), "wave.area")
        for name in ["wave.areas", "wave", ".area", "1w.area", "a-b.area", "wave.area.x", "w" * 25 + ".area"]:
            with self.subTest(name=name):
                self.assertIsNone(mg_expr.readout_placeholder(name))


if __name__ == "__main__":
    unittest.main()
