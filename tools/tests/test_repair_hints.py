# SPDX-License-Identifier: Apache-2.0
"""The Python repair-hint mirror must match the Swift tables, by source and by output.

The source comparison parses the Swift tables. The output comparison uses the shared corpus
(docs/fixtures/repair-hints/corpus.json): Python asserts it here, and `RepairHintCorpusTests` and
`MLRepairHintCorpusTests` assert the same file against Swift on a Mac.
"""

import importlib.util
import json
from pathlib import Path
import re
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
TOOLS = ROOT / "evals/dev-authoring/tools"
STRING = r'"((?:[^"\\]|\\.)*)"'
CORPUS = ROOT / "docs/fixtures/repair-hints/corpus.json"


def load(name):
    sys.path.insert(0, str(TOOLS))
    spec = importlib.util.spec_from_file_location(name, TOOLS / f"{name}.py")
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


def swift_kind_tables():
    """MGParser.allowedKeys(_:) extras and MGParser.required(_:), parsed from the Swift source."""
    source = (ROOT / "Sources/MartyGraphics/MGParser.swift").read_text(encoding="utf-8")
    allowed = source[source.index("static func allowedKeys"):source.index("static func required")]
    required = source[source.index("static func required"):source.index("static func defaultColor")]
    keys = lambda text: re.findall(r'"(\w+)"', text)  # noqa: E731
    extra = {kind: keys(body) for kind, body in re.findall(r"case \.(\w+): extra = \[([^\]]*)\]", allowed)}
    needed = {}
    for kinds, body in re.findall(r"case ((?:\.\w+(?:, )?)+): return \[([^\]]*)\]", required):
        for kind in re.findall(r"\.(\w+)", kinds):
            needed[kind] = keys(body)
    return extra, needed


class RepairHintMirror(unittest.TestCase):
    def setUp(self):
        self.hints = load("hints")
        self.inventory = load("inventory")
        self.corpus = json.loads(CORPUS.read_text(encoding="utf-8"))

    def test_scene_table_matches_swift(self):
        source, table = swift_scene_table()
        self.assertEqual(self.hints.SCENE_HINTS, table)
        # The two computed hints use the same wording on both sides.
        self.assertIn('"a \\(kind.rawValue) needs "', source)
        self.assertIn('"remove unknown keys; a \\(kind.rawValue) allows "', source)

    def test_kind_tables_match_the_parser(self):
        extra, needed = swift_kind_tables()
        self.assertEqual({name: sorted(keys) for name, keys, _ in self.hints.KINDS},
                         {name: sorted(keys) for name, keys in extra.items()})
        self.assertEqual({name: sorted(keys) for name, _, keys in self.hints.KINDS},
                         {name: sorted(keys) for name, keys in needed.items()})
        self.assertEqual(self.hints.COMMON, ["id", "k", "color"])

    def test_ml_table_matches_swift_and_covers_every_reason(self):
        raw, swift = swift_ml_hints()
        self.assertEqual(self.hints.ML_HINTS, swift)
        self.assertEqual(sorted(swift), sorted(raw.values()))
        self.assertTrue(all(text.isascii() for text in swift.values()))

    def test_corpus_is_current_and_matches_python_outputs(self):
        corpus_tool = load("hint_corpus")
        self.assertEqual(self.corpus, corpus_tool.build(), "run hint_corpus.py --write")
        for entry in self.corpus["scene"]:
            self.assertEqual(self.hints.scene_hint(entry["reason"]), entry["hint"], entry["reason"])
        for entry in self.corpus["ml"]:
            self.assertEqual(self.hints.ml_hint(entry["reason"]) or None, entry["hint"], entry["reason"])

    def test_corpus_covers_computed_hints_patterns_and_unknowns(self):
        scene = {entry["reason"]: entry["hint"] for entry in self.corpus["scene"]}
        for name, _, _ in self.hints.KINDS:
            name = self.hints.wire(name)
            self.assertTrue(scene[f"item.{name}.missing"].startswith(f"a {name} needs "))
            self.assertTrue(scene[f"item.{name}.unknown.zz"].startswith(f"remove unknown keys; a {name} allows "))
        self.assertEqual(scene["item.func.missing"], "a func needs at, h, id, k, w, xr, y, yr")
        self.assertEqual(scene["item.body.missing"], "a body needs at, id, k")
        self.assertEqual(scene["item.edge.unknown.c"], "remove unknown keys; a edge allows a, b, color, dir, id, k, label")
        # Every table row is the first match of at least one corpus reason, so precedence is exercised row by row.
        first = set()
        for reason in scene:
            for pattern, _ in self.hints.SCENE_HINTS:
                if self.hints.matches(pattern, reason):
                    first.add(pattern)
                    break
        self.assertEqual([p for p, _ in self.hints.SCENE_HINTS if p not in first], [])
        self.assertEqual(scene["edge.dir"], "dir is true or false")
        self.assertTrue(scene["vector.dir"].startswith("dir is the 3D direction"))
        self.assertTrue(scene["template.params.depth"].startswith("params must be an object"))
        self.assertGreaterEqual(sum(hint is None for hint in scene.values()), 5)
        ml = {entry["reason"]: entry["hint"] for entry in self.corpus["ml"]}
        raw, _ = swift_ml_hints()
        self.assertTrue(set(raw.values()) <= {r for r, h in ml.items() if h})
        self.assertIsNone(ml["ml.not.a.reason"])

    def test_fixed_hints_state_the_parser_rules(self):
        hint = self.hints.scene_hint
        self.assertNotIn("1e-6", hint("plot.xr") + hint("plot.yr"))
        self.assertIn("lo < hi", hint("plot.xr"))
        self.assertIn("-1e6 to 1e6", hint("plot.pts"))
        self.assertIn("outside xr and yr are accepted", hint("plot.pts"))
        self.assertIn("remove angle", hint("vector.dir"))
        self.assertIn("three numbers from -1 to 1 with length above 0.01", hint("vector.dir"))

    def test_motion_hint_states_the_parser_motion_bounds(self):
        # MGParser.validateMotion: travel, period and visual in MGLimits.bodyMoveTime (0.3...10), hold in 0...10,
        # flight > 0, every other motion number finite. It must not fall back to the template parameter hint.
        hint = self.hints.scene_hint("template.motion")
        parser = (ROOT / "Sources/MartyGraphics/MGParser.swift").read_text(encoding="utf-8")
        self.assertIn("static let bodyMoveTime: ClosedRange<Double> = 0.3...10", parser)
        self.assertIn("let holdDuration = 0...duration.upperBound", parser)
        self.assertIn("flight > 0", parser)
        self.assertNotEqual(hint, self.hints.scene_hint("template.values"))
        self.assertEqual(hint, "the template built invalid motion; fix the template: slide travel, orbit and oscillate "
                               "period and projectile visual are 0.3 to 10 seconds, hold is 0 to 10 seconds, projectile "
                               "flight is above 0, and every other motion number is finite")

    def test_every_sample_reason_has_a_hint(self):
        sample = self.inventory.scene_reason_sample()
        checked_in = json.loads((ROOT / "evals/dev-authoring/inventories/scene-reasons.json").read_text(encoding="utf-8"))
        self.assertEqual(checked_in["tokens"], sample, "run inventory.py --write")
        self.assertEqual(len(sample), 195)
        self.assertEqual([r for r in sample if not self.hints.scene_hint(r)], [])

    def test_wildcards(self):
        match = self.hints.matches
        self.assertTrue(match("item.*.unknown.*", "item.body.unknown.a,b"))
        self.assertTrue(match("*.at", "body.at"))
        self.assertFalse(match("*.at", "body.atx"))
        self.assertTrue(match("step*", "steps"))
        self.assertFalse(match("items", "items.count"))


if __name__ == "__main__":
    unittest.main()
