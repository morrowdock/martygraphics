# SPDX-License-Identifier: Apache-2.0
"""Exercise the draft schema and preflight against documented scene inputs."""

import json
import subprocess
import sys
import unittest

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


if __name__ == "__main__":
    unittest.main()
