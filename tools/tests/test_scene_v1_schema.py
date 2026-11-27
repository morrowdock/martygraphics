# SPDX-License-Identifier: Apache-2.0
"""Exercise the draft schema and preflight against documented scene inputs."""

import json
import os
import subprocess
import sys
import unittest
from unittest.mock import patch

from tools import scene_v1_check as checker


FIXTURES = checker.ROOT / "docs/fixtures/v1"
SHOWCASE = checker.ROOT / "Examples/Showcase/Sources/MartyShowcase/Scenes"
PROTOCOL_NEGATIVES = {
    "highlight-cycle.scene.json": "highlight.cycle",
    "unknown-key.scene.json": "scene.unknown.unknown",
}


class SceneV1Tests(unittest.TestCase):
    def assert_invalid(self, data, reason, **options):
        with self.assertRaises(checker.Invalid) as failure:
            checker.check(data, **options)
        self.assertEqual(str(failure.exception), reason)

    def test_valid_protocol_and_showcase_scenes(self):
        scenes = [
            FIXTURES / "scene.json",
            *(path for path in sorted(FIXTURES.glob("*.scene.json")) if path.name not in PROTOCOL_NEGATIVES),
            *sorted(SHOWCASE.glob("*.json")),
        ]
        self.assertTrue(any(path.parent == SHOWCASE for path in scenes))
        for path in scenes:
            with self.subTest(path=path.name, directory=path.parent.name):
                data = path.read_bytes()
                scene = json.loads(data)
                checker.shape(scene, checker.SCHEMA)
                if scene.get("template") == "shortest_path":
                    self.assert_invalid(data, "template.unknown")
                    self.assertEqual(checker.check(data, packs=("graphs",)), "shortest_path")
                else:
                    self.assertEqual(checker.check(data), scene.get("template"))

    def test_graph_pack_cli_accepts_showcase_scene(self):
        command = [sys.executable, str(checker.ROOT / "tools/scene_v1_check.py")]
        scene = str(SHOWCASE / "shortest-path.json")
        default = subprocess.run([*command, scene], capture_output=True, text=True)
        self.assertEqual(default.returncode, 1)
        self.assertIn("template.unknown", default.stdout)
        graphs = subprocess.run([*command, "--pack", "graphs", scene], capture_output=True, text=True)
        self.assertEqual(graphs.returncode, 0, graphs.stderr)
        self.assertIn("shortest_path expansion requires Swift", graphs.stdout)

    def test_literal_swift_reason_codes(self):
        body = {"id": "dot", "k": "body", "at": [3, 4]}
        base = {"v": 1, "items": [body]}
        array = {**body, "k": "array", "vals": [0]}
        bars = {**body, "k": "bars", "w": 2, "h": 2}
        cases = [
            ({"items": [{**array, "vals": [True]}]}, "array.val"),  # MGParser.swift:503
            ({"items": [{**body, "k": "table", "cells": [[True]]}]}, "table.cell"),  # MGParser.swift:551
            ({"items": [{**bars, "bars": [{"label": 1, "value": 2}]}]}, "bars.label"),  # MGParser.swift:487
            # MGParser.swift:484 and :582
            ({"items": [{**bars, "bars": [{"label": "A", "value": 2, "extra": 0}]}]}, "bars.bar.unknown.extra"),
            ({"items": [{**array, "ptrs": [{"i": .5, "label": "i"}]}]}, "array.ptr.i"),  # MGParser.swift:514
            ({"items": [{"id": "v", "k": "vector", "from": [3, 4], "len": 1}]}, "vector.angle"),  # MGParser.swift:434
            ({"title": "{x}"}, "title.placeholder.x"),  # MGParser.swift:200 and :656
            ({"steps": [{"say": "Edit", "do": [{"id": "dot", "key": "id", "value": "x"}]}]}, "edit.key"),  # MGParser.swift:306
            ({"world": {"w": 5}}, "world.missing"),  # MGParser.swift:154 and :581
            ({"params": []}, "scene.params.without.template"),  # MGParser.swift:142
        ]
        for scene, reason in cases:
            with self.subTest(reason=reason):
                self.assert_invalid(json.dumps({**base, **scene}).encode(), reason)

    def test_swift_template_reason_codes(self):
        # MGParser.swift:133 resolves the registry before validation, then :135–136 calls MGTemplate.validate.
        cases = [
            ({"template": "unknown", "params": []}, "template.unknown", ()),
            ({"template": None}, "template.unknown", ()),
            ({"template": "bst", "params": {"values": [.5]}}, "template.values.integer", ()),  # MGTemplates.swift:232
            ({"template": "bst", "params": {"values": [True]}}, "template.values", ()),  # MGTemplates.swift:231
            ({"template": "bst", "params": {}}, "template.values", ()),  # MGTemplates.swift:229
            ({"template": "shortest_path", "params": {"edges": [[0, 1, 2]]}}, "template.n.missing", ("graphs",)),  # MGTemplates.swift:240
            ({"template": "shortest_path", "params": {"n": 2}}, "template.edges.missing", ("graphs",)),  # MGTemplates.swift:255
        ]
        for edge in ([0, 1], [0, 1, 2, 3], 0):
            # MGTemplates.swift:260
            cases.append(({"template": "shortest_path", "params": {"n": 2, "edges": [edge]}},
                          "template.edges.arity", ("graphs",)))
        for scene, reason, packs in cases:
            with self.subTest(scene=scene):
                self.assert_invalid(json.dumps({"v": 1, **scene}).encode(), reason, packs=packs)

    def test_swift_textual_nesting_limit(self):
        # MGParser.swift:84 and MGModel.swift:257–275
        self.assert_invalid(b"[" * 64 + b"]" * 64, "scene.object")
        for depth in (65, 1200):
            with self.subTest(depth=depth):
                self.assert_invalid(b"[" * depth + b"]" * depth, "scene.depth")
        data = json.dumps({"v": 1, "items": [{"id": "dot", "k": "body", "at": [3, 4]}],
                           "ignored": '"\\' + "[" * 1200}).encode()
        self.assert_invalid(data, "scene.unknown.ignored")

    def test_protocol_negative_fixtures(self):
        for name, reason in PROTOCOL_NEGATIVES.items():
            with self.subTest(name=name):
                self.assert_invalid((FIXTURES / name).read_bytes(), reason)

    def test_swift_validator_negative_fixtures(self):
        directory = FIXTURES / "invalid"
        cases = json.loads((directory / "swift-cases.json").read_bytes())
        self.assertEqual(
            {path.name for path in directory.glob("*.json")} - {"swift-cases.json"},
            {name for name, case in cases.items() if "raw" not in case},
        )
        for name, case in cases.items():
            with self.subTest(name=name):
                if "raw" in case:
                    data = case["raw"].encode("utf-8")
                    data = data.ljust(case.get("padToBytes", len(data)), b" ")
                else:
                    data = (directory / name).read_bytes()
                self.assert_invalid(data, case["reason"])

    def test_input_limit_allows_padding_up_to_boundary(self):
        scene = b'{"v":1,"title":"Synthetic dot","items":[{"id":"dot","k":"body","at":[3,4]}]}'
        self.assertIsNone(checker.check(scene.ljust(checker.INPUT_BYTES, b" ")))

    def test_plot_minimum_span_on_both_axes(self):
        plot = {"id": "curve", "k": "plot", "at": [2, 2], "w": 4, "h": 3,
                "xr": [0, 1e-6], "yr": [0, 1e-6], "pts": [[0, 0], [1e-6, 1e-6]]}
        self.assertEqual(checker.MIN_PLOT_SPAN, 1e-6)
        self.assertIsNone(checker.check(json.dumps({"v": 1, "items": [plot]}).encode()))

    def test_unknown_and_edit_reasons_use_short_names(self):
        names = ("color", "height", "label", "width", "angle")
        self.assertEqual(checker.reason_keys(names), "color,height,label,width")
        self.assertEqual(checker.reason_keys(("extraConfigurationSetting",)), "?")
        self.assertEqual(checker.reason_keys(("line_width",)), "line_width")

    def test_math_label_scalar_parity(self):
        data = (FIXTURES / "math-label.scene.json").read_bytes()
        self.assertIsNone(checker.check(data))
        self.assertEqual(json.loads(data)["items"][0]["text"], "x \u226e y")

    def test_text_and_narration_accept_line_breaks(self):
        item = {"id": "caption", "k": "text", "at": [2, 2], "text": "First line\nSecond line"}
        base = {"v": 1, "title": "Line breaks", "items": [item], "steps": [{"say": "First line\nSecond line"}]}
        self.assertIsNone(checker.check(json.dumps(base).encode()))

    def test_scene_number_spelling_and_unique_fields(self):
        self.assertIs(type(checker.scene_float("3.0")), int)
        self.assertEqual(checker.scene_float("-0.0"), 0)
        self.assertEqual(checker.scene_float("3.25"), 3.25)
        self.assertEqual(checker.unique_object([("v", 1), ("title", "Plot")]), {"v": 1, "title": "Plot"})

    def test_cli_checks_open_file_descriptor(self):
        with patch.object(sys, "argv", ["scene_v1_check.py", str(FIXTURES / "scene.json")]), \
                patch.object(os, "fstat", wraps=os.fstat) as fstat, patch("builtins.print"):
            self.assertEqual(checker.main(), 0)
        fstat.assert_called_once()
        self.assertIsInstance(fstat.call_args.args[0], int)

    def test_schema_rejects_wrong_type_count_dimension_and_item_keys(self):
        base = {"v": 1, "items": [{"id": "dot", "k": "body", "at": [3, 4]}]}
        variants = [
            {"v": True},
            {"items": base["items"] * 25},
            {"steps": [{"say": "A dot"}] * 9},
            {"items": [{"id": "dot", "k": "body", "at": [3, 4, 0]}]},
            {"items": [{"id": "dot", "k": "body", "at": [3, 4], "header": False}]},
            {"items": [{"id": "dot\n", "k": "body", "at": [3, 4]}]},
        ]
        for update in variants:
            with self.subTest(update=update), self.assertRaises(checker.ShapeError):
                checker.shape({**base, **update}, checker.SCHEMA)

    def test_semantic_rules_check_focus_world_cycles_and_canonical_budget(self):
        body = {"id": "dot", "k": "body", "at": [3, 4]}
        base = {"v": 1, "items": [body]}
        variants = [
            ({"steps": [{"say": "A dot", "focus": "missing"}]}, "step.focus"),
            ({"world": {"w": 2, "h": 8}}, "body.at"),
            ({
                "items": [body, {"id": "a", "k": "highlight", "target": "b"},
                          {"id": "b", "k": "highlight", "target": "dot"}],
                "steps": [{"say": "A dot", "do": [{"id": "b", "key": "target", "value": "a"}]}],
            }, "highlight.cycle"),
            ({"items": [{"id": f"grid{i}", "k": "table", "at": [1, 1],
                         "cells": [["abcdefghij"] * 6] * 8} for i in range(14)]}, "scene.bytes"),
        ]
        for update, reason in variants:
            with self.subTest(reason=reason):
                data = json.dumps({**base, **update}, separators=(",", ":")).encode("utf-8")
                self.assert_invalid(data, reason)

    def test_graph_kinds_and_text_alternatives(self):
        graph = {"id": "g", "k": "func", "at": [1, 1], "w": 5, "h": 4, "xr": [-3, 3], "yr": [-2, 2], "y": "sin(x)"}
        field = {"id": "v", "k": "field", "at": [6, 1], "w": 4, "h": 4, "xr": [-2, 2], "yr": [-2, 2],
                 "dx": "-y", "dy": "x"}
        self.assertIsNone(checker.check(json.dumps({"v": 1, "alt": "A curve and a field.", "items": [graph, field],
                                                    "steps": [{"say": "Look.", "alt": "A sine curve."}]}).encode()))
        # One graph and five edits of it: six graph checks, the limit (one more is `items.expr` below).
        self.assertIsNone(checker.check(json.dumps({"v": 1, "items": [{**graph, "y": "a*sin(x)", "a": 1}], "steps": [
            {"say": "Go.", "do": [{"id": "g", "key": "a", "value": k} for k in range(2, 7)]}]}).encode()))
        variants = [
            ({"items": [{**graph, "y": "sin(x"}]}, "func.y.syntax"),
            ({"items": [{**graph, "y": "a*x"}]}, "func.y.var.a"),
            ({"items": [{**graph, "period": 4}]}, "func.period"),
            ({"items": [{**graph, "w": 20}]}, "func.w"),
            ({"items": [{**graph, "id": f"g{i}"} for i in range(7)]}, "items.expr"),
            ({"items": [{**graph, "y": "a*sin(x)", "a": 1}],
              "steps": [{"say": "Go.", "do": [{"id": "g", "key": "a", "value": k} for k in range(2, 8)]}]}, "items.expr"),
            ({"items": [{**field, "n": [1, 4]}]}, "field.n"),
            ({"items": [{**field, "style": "wavy"}]}, "field.style"),
            ({"items": [graph], "alt": "a <b>"}, "alt"),
            ({"items": [graph], "alt": "Two\nlines"}, "alt"),
            ({"items": [{**graph, "xl": "x\ny"}]}, "func.xl"),
            ({"items": [graph], "steps": [{"say": "Look.", "alt": ""}]}, "step.alt"),
            ({"items": [graph], "dim": "3d"}, "3d.kind.func"),
            ({"items": [{**graph, "y": "a*sin(x)", "a": 1}],
              "steps": [{"say": "Go.", "do": [{"id": "g", "key": "a", "value": 5000}]}]}, "func.a"),
        ]
        for update, reason in variants:
            with self.subTest(reason=reason):
                self.assert_invalid(json.dumps({"v": 1, **update}).encode("utf-8"), reason)


if __name__ == "__main__":
    unittest.main()
