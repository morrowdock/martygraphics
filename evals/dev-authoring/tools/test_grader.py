# SPDX-License-Identifier: Apache-2.0
"""Mutation tests for the grader: a known mistake injected into a passing scene must fail the targeted check.

    python -m unittest discover -s tools -p "test_*.py"

Each case loads a frozen baseline output, applies one mutation, and expects the named check type to fail
while the unmutated scene passes it. This guards against a grader that passes everything.
"""

import copy
import json
from pathlib import Path
import sys
import unittest

HERE = Path(__file__).resolve().parent
EVAL = HERE.parent
sys.path.insert(0, str(HERE))

import grade  # noqa: E402

SPECS = json.loads((EVAL / "specs.json").read_text(encoding="utf-8"))["specs"]


def load(identifier):
    return json.loads((EVAL / "runs" / "baseline" / identifier / "attempt-1.json").read_text(encoding="utf-8"))


def item(scene, identifier):
    return next(i for i in scene["items"] if i["id"] == identifier)


def failing(scene, identifier):
    checks, _ = grade.grade_scene(scene, SPECS[identifier])
    return {(c["t"], c["cat"]) for c in checks if not c["pass"]}


def set_field(identifier, field, value):
    def mutate(scene):
        item(scene, identifier)[field] = value
    return mutate


def edit_say(index, text):
    def mutate(scene):
        scene["steps"][index]["say"] = text
    return mutate


def drop_first_step_edits(scene):
    scene["steps"][0].pop("do", None)


def show_all_from_start(scene):
    for step in scene["steps"]:
        step.pop("show", None)


def swap_bfs(scene):
    scene["steps"][1]["focus"], scene["steps"][2]["focus"] = "C", "B"
    scene["steps"][1]["do"] = [{"id": "visit", "key": "target", "value": "C"}, {"id": "C", "key": "color", "value": "good"}]
    scene["steps"][2]["do"] = [{"id": "visit", "key": "target", "value": "B"}, {"id": "B", "key": "color", "value": "good"}]


def stack_wrong_pop(scene):
    scene["steps"][2]["do"] = [{"id": "stack", "key": "vals", "value": [8]}]


CASES = [
    ("P01", set_field("N", "angle", 90), ("dir_rel", "direction")),
    ("P01", set_field("F", "angle", 210), ("dir_rel", "direction")),
    ("P01", set_field("N", "len", 1.225), ("len_ratio", "magnitude")),
    ("P01", set_field("box", "at", [9, 1.5]), ("on_incline", "geometry")),
    ("P01", set_field("N", "label", "N = 24.5 N"), ("num", "numbers")),
    ("P02", lambda s: item(s, "traj")["pts"].__setitem__(4, [20, 12]), ("plot_fn", "data")),
    ("P02", set_field("traj", "xr", [0, 40]), ("plot_box", "data")),
    ("P03", set_field("S", "len", 1.2), ("len_ratio", "magnitude")),
    ("P04", set_field("a3", "angle", 270), ("dir", "direction")),
    ("P05", set_field("v", "angle", 180), ("dir_rel", "direction")),
    ("P05", set_field("a", "angle", 0), ("dir_rel", "direction")),
    ("P09", set_field("light", "at", [9, 4.4]), ("seesaw_dist", "geometry")),
    ("P10", set_field("refracted", "angle", 310), ("snell_angles", "direction")),
    ("P11", lambda s: s["steps"][2]["do"].pop(1), ("pend_string_attached", "geometry")),
    ("P12", lambda s: (edit_say(2, "So the road pushes up with N = 9800 N.")(s), item(s, "N").__setitem__("label", "N")), ("num", "numbers")),
    ("M01", set_field("dropx", "style", "solid"), ("segment", "geometry")),
    ("M02", lambda s: (set_field("peaklabel", "at", [6, 6.85])(s), set_field("peak", "at", [6, 6.33])(s)), ("near_plot_point", "geometry")),
    ("M03", set_field("tri", "pts", [[2, 1.5], [8, 1.5], [2, 7]]), ("triangle", "geometry")),
    ("M04", set_field("rise", "to", [8.7, 4]), ("plot_segment", "geometry")),
    ("M06", set_field("b", "from", [6, 2]), ("head_to_tail", "geometry")),
    ("M07", lambda s: s["steps"][2]["do"].__setitem__(0, {"id": "row", "key": "marked", "value": [0, 1, 2, 3, 4, 5]}), ("marked_final", "data")),
    ("M09", lambda s: item(s, "dist")["bars"][2].__setitem__("value", 0.125), ("bars_values", "data")),
    ("C01", lambda s: s["steps"][1]["do"].__setitem__(0, {"id": "arr", "key": "ptrs", "value": [{"i": 0, "label": "low"}, {"i": 2, "label": "high"}, {"i": 2, "label": "mid"}]}), ("ptr_states", "order")),
    ("C04", stack_wrong_pop, ("stack_states", "order")),
    ("C05", swap_bfs, ("visit_order", "order")),
    ("C07", lambda s: item(s, "tt")["cells"].__setitem__(4, [1, 1, 1]), ("table_rows", "data")),
    ("C08", lambda s: s["steps"][3]["do"].__setitem__(0, {"id": "buckets", "key": "vals", "value": ["-", "22", "-", "10,31", "-", "4", "-"]}), ("hash_final", "data")),
    ("C09", show_all_from_start, ("graph_edges", "data")),
    ("C10", lambda s: item(s, "growth")["bars"][3].__setitem__("value", 128), ("bars_labeled_values", "data")),
]


class GraderMutations(unittest.TestCase):
    def test_unmutated_baselines_pass_targeted_checks(self):
        for identifier, _, target in CASES:
            self.assertNotIn(target, failing(load(identifier), identifier), identifier)

    def test_each_mutation_fails_its_check(self):
        for identifier, mutate, target in CASES:
            scene = copy.deepcopy(load(identifier))
            mutate(scene)
            with self.subTest(identifier=identifier, target=target):
                self.assertIn(target, failing(scene, identifier))

    def test_step_zero_edits_hide_the_authored_state(self):
        scene = load("C06")
        self.assertIn(("array_states", "order"), failing(scene, "C06"))
        scene = copy.deepcopy(scene)
        scene["steps"].insert(0, {"say": "Start: 5, 1, 4, 2, 8.", "focus": "arr"})
        self.assertNotIn(("array_states", "order"), failing(scene, "C06"))

    def test_numbers_reader(self):
        self.assertIn(4800, grade.numbers("N = 4.8 kN"))
        self.assertTrue(any(abs(n - 8 / 3) < 1e-9 for n in grade.numbers("exact area 8/3")))
        self.assertTrue(any(abs(n - 1.5708) < 1e-4 for n in grade.numbers("at x = π/2")))
        self.assertIn(-2.0, grade.numbers("from −2 to 6"))
        self.assertEqual(grade.numbers("buckets 10,31"), [10.0, 31.0])


if __name__ == "__main__":
    unittest.main()
