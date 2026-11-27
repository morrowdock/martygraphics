# SPDX-License-Identifier: Apache-2.0
"""The portability map stays current and the semantic fixtures keep their Python-checkable meaning."""

import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import unittest
from unittest.mock import patch

TOOLS = Path(__file__).resolve().parents[1]


def load(name):
    spec = importlib.util.spec_from_file_location(name, TOOLS / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


sys.path.insert(0, str(TOOLS))
portability_map = load("portability_map")
semantic = load("semantic_fixtures")


class PortabilityMapTests(unittest.TestCase):
    def test_python_import_inventory_ignores_embedded_swift(self):
        rows = dict(portability_map.python_rows())
        imports = rows["tools/verify_release_install.py"]
        self.assertIn("subprocess", imports)
        self.assertNotIn("Foundation", imports)
        self.assertNotIn("MartyGraphics", imports)

    def test_generated_block_is_current(self):
        result = subprocess.run([sys.executable, str(TOOLS / "portability_map.py"), "--check"],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_strip_hides_comments_and_strings(self):
        code = portability_map.strip_swift('let a = "CGFloat" // CGPoint\n/* SCNNode */ let b: CGSize\n')
        self.assertNotIn("CGFloat", code)
        self.assertNotIn("CGPoint", code)
        self.assertNotIn("SCNNode", code)
        self.assertIn("CGSize", code)
        self.assertEqual(code.count("\n"), 2)

    def test_local_names_are_not_platform_symbols(self):
        files = {f["path"]: f for f in portability_map.scan()}
        explainer = files["Sources/MartyGraphics/Explainer/MGExplainer.swift"]
        self.assertNotIn("SwiftUI", explainer["symbols"])   # its nested `enum View` is not SwiftUI
        self.assertIn("CoreGraphics", files["Sources/MartyGraphics/MGLayout.swift"]["symbols"])

    def test_core_candidates_exist(self):
        for path in portability_map.CORE:
            self.assertTrue((portability_map.ROOT / path).is_file(), path)


class SemanticFixtureTests(unittest.TestCase):
    def test_missing_corpus_fails(self):
        with patch.object(semantic, "FIXTURES", TOOLS / "missing_semantic_fixtures"):
            totals, failures = semantic.run()
        self.assertEqual(totals["fixtures"], 0)
        self.assertTrue(failures)

    def test_corpus_passes(self):
        totals, failures = semantic.run()
        self.assertEqual(failures, [])
        self.assertGreater(totals["fixtures"], 50)
        self.assertGreater(totals["pending"], 0)

    def doc(self):
        return {"format": semantic.FORMAT, "input": {"utf8": '{"v":1,"items":[{"id":"a","k":"body","at":[1,1]}]}'},
                "entry": "MGParser.scene(data:)",
                "expect": [{"check": "outcome", "expect": {"result": "accept"}, "python": "checked", "swift": "pending-mac"}]}

    def test_parity_claims_fail_closed(self):
        semantic.validate_shape(self.doc())
        for swift in ("confirmed", "pass", "not-applicable"):
            doc = self.doc()
            doc["expect"][0]["swift"] = swift
            with self.assertRaises(semantic.Mismatch):
                semantic.validate_shape(doc)

    def test_closed_keys(self):
        doc = self.doc()
        doc["parity"] = True
        with self.assertRaises(semantic.Mismatch):
            semantic.validate_shape(doc)
        doc = self.doc()
        doc["expect"][0]["verified"] = True
        with self.assertRaises(semantic.Mismatch):
            semantic.validate_shape(doc)

    def test_python_cannot_claim_swift_only_checks(self):
        doc = self.doc()
        doc["expect"][0] = {"check": "resolved", "expect": {}, "python": "checked", "swift": "pending-mac"}
        with self.assertRaises(semantic.Mismatch):
            semantic.validate_shape(doc)

    def test_wrong_reason_is_reported(self):
        doc = self.doc()
        doc["input"] = {"utf8": '{"v":2,"items":[{"id":"a","k":"body","at":[1,1]}]}'}
        doc["expect"][0]["expect"] = {"result": "reject", "reason": "scene.dim"}
        data, _ = semantic.materialize(doc["input"], semantic.FIXTURES)
        with self.assertRaises(semantic.Mismatch):
            semantic.check_entry(doc["expect"][0], data, None)

    def test_format_model(self):
        cases = {0.004: "0", -0.004: "0", 12.25: "12.2", 99999.5: "100000", 1234.5: "1234", 9.999: "10"}
        for value, text in cases.items():
            self.assertEqual(semantic.model_format(value, ""), text, value)
        self.assertEqual(semantic.model_format(30, "°"), "30°")
        self.assertEqual(semantic.model_format(float("nan"), "N"), "—")

    def test_failed_patch_keeps_scene(self):
        scene = b'{"v":1,"items":[{"id":"dot","k":"body","at":[3,4]}]}'
        rows = semantic.model_patches(scene, [
            {"v": 1, "ops": [{"op": "title", "title": "Kept"}]},
            {"v": 1, "rev": 1, "ops": [{"op": "title", "title": "Lost"}, {"op": "set", "id": "dot", "key": "at", "value": [99, 4]}]},
        ])
        self.assertEqual([r["result"] for r in rows], ["accept", "reject"])
        self.assertEqual(rows[1]["reason"], "body.at")
        self.assertEqual((rows[1]["revision"], rows[1]["title"]), (1, "Kept"))

    def test_patch_model_does_not_mutate_input(self):
        root = {"v": 1, "items": [{"id": "dot", "k": "body", "at": [3, 4]}]}
        before = copy.deepcopy(root)
        with self.assertRaises(semantic.PatchError):
            semantic.apply_patch(root, 0, [{"op": "set", "id": "dot", "key": "at", "value": [99, 4]}], None)
        self.assertEqual(root, before)

    def test_inline_padding(self):
        data, _ = semantic.materialize({"utf8": "{}", "padToBytes": 5}, semantic.FIXTURES)
        self.assertEqual(data, b"{}   ")
        with self.assertRaises(semantic.Mismatch):
            semantic.materialize({"utf8": "{}", "hex": "00"}, semantic.FIXTURES)
        with self.assertRaises(semantic.Mismatch):
            semantic.materialize("../../../README.md", semantic.FIXTURES)

    def test_expected_files_are_json(self):
        for path in semantic.FIXTURES.rglob("*.json"):
            json.loads(path.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
