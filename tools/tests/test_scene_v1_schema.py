# SPDX-License-Identifier: Apache-2.0
"""Exercise the draft schema and preflight against documented scene inputs."""

import json
import unittest

from tools import scene_v1_check as checker


FIXTURES = checker.ROOT / "docs/fixtures/v1"
SHOWCASE = checker.ROOT / "Examples/Showcase/Sources/MartyShowcase/Scenes"
PROTOCOL_NEGATIVES = {
    "highlight-cycle.scene.json": "highlight.cycle",
    "unknown-key.scene.json": "scene.unknown.unknown",
}


class SceneV1Tests(unittest.TestCase):
    def assert_invalid(self, data, reason):
        with self.assertRaises(checker.Invalid) as failure:
            checker.check(data)
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
                self.assertEqual(checker.check(data), scene.get("template"))

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
