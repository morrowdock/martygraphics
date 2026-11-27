# SPDX-License-Identifier: Apache-2.0
"""The Python repair-hint mirror must match the Swift tables, and every parser reason should have a hint."""

import importlib.util
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
STRING = r'"((?:[^"\\]|\\.)*)"'


def load_hints():
    spec = importlib.util.spec_from_file_location("hints", ROOT / "evals/dev-authoring/tools/hints.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def swift_scene_table():
    source = (ROOT / "Sources/MartyGraphics/MGRepairHint.swift").read_text(encoding="utf-8")
    consts = dict(re.findall(r"static let (plainText|pointShape) = " + STRING, source))

    def plain(text):
        text = text.replace('\\"', '"')
        return re.sub(r"\\\((plainText|pointShape)\)", lambda m: plain(consts[m.group(1)]), text)

    rows = re.findall(r"^\s*\(" + STRING + r", " + STRING + r"\),?$", source, re.M)
    return source, [(plain(a), plain(b)) for a, b in rows]


def swift_ml_hints():
    source = (ROOT / "Sources/MartyGraphicsMLKit/MGMLKit.swift").read_text(encoding="utf-8")
    enum = source[source.index("public enum MGMLReason"):source.index("extension MGMLReason")]
    raw = dict(re.findall(r'case (\w+) = "([^"]+)"', enum))
    body = source[source.index("public var hint: String"):source.index("public struct MGMLIssue")]
    cases = re.findall(r"case \.(\w+): return " + STRING, body)
    return raw, {raw[name]: text.replace('\\"', '"') for name, text in cases}


class RepairHintMirror(unittest.TestCase):
    def setUp(self):
        self.hints = load_hints()

    def test_scene_table_matches_swift(self):
        source, table = swift_scene_table()
        self.assertEqual(self.hints.SCENE_HINTS, table)
        # The two computed hints use the same wording on both sides.
        self.assertIn('"a \\(kind.rawValue) needs "', source)
        self.assertIn('"remove unknown keys; a \\(kind.rawValue) allows "', source)
        self.assertEqual(self.hints.scene_hint("item.body.missing"), "a body needs at, id, k")
        self.assertTrue(self.hints.scene_hint("item.edge.unknown.c").startswith("remove unknown keys; a edge allows a, b, "))

    def test_ml_table_matches_swift_and_covers_every_reason(self):
        raw, swift = swift_ml_hints()
        self.assertEqual(self.hints.ML_HINTS, swift)
        self.assertEqual(sorted(swift), sorted(raw.values()))
        self.assertTrue(all(text.isascii() for text in swift.values()))

    def test_every_static_parser_reason_has_a_hint(self):
        parser = (ROOT / "Sources/MartyGraphics/MGParser.swift").read_text(encoding="utf-8")
        reasons = set(re.findall(r'MGError\("([a-z0-9.\-]+)"\)', parser)) | {"json", "input.too-large", "scene.missing"}
        grammar = load_hints().KINDS
        for name, extra, _ in grammar:
            reasons |= {f"item.{name}.missing", f"item.{name}.unknown.zz"}
            reasons |= {f"{name}.{key}" for key in extra if key not in ("label",)}
        reasons |= {"title.placeholder.n", "step.say.brace", "item.label.placeholder", "edit.key.zz", "id.duplicate.a",
                    "scene.unknown.zz", "world.unknown.zz", "step.unknown.zz", "camera.unknown.zz", "3d.kind.table"}
        missing = sorted(r for r in reasons if not self.hints.scene_hint(r))
        self.assertEqual(missing, [])

    def test_wildcards(self):
        match = self.hints.matches
        self.assertTrue(match("item.*.unknown.*", "item.body.unknown.a,b"))
        self.assertTrue(match("*.at", "body.at"))
        self.assertFalse(match("*.at", "body.atx"))
        self.assertTrue(match("step*", "steps"))
        self.assertFalse(match("items", "items.count"))


if __name__ == "__main__":
    unittest.main()
