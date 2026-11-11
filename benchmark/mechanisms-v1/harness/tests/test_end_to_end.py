# SPDX-License-Identifier: Apache-2.0
"""End to end on SYNTHETIC grader files: the real key's 20 question ids x 3 runs x 2 arms, then the verdict.

No real output is read or made. The grades are generated from a plan, and the expected M(q, a), d(q), sign test and
verdict are computed here from that plan by hand rules, not by score.py:
  a run graded by both graders with n1 and n2 PASS (all five checks judged, PASS on a prefix) merges to min(n1, n2);
  a failed run is 0; an ungraded run and a run with no judged check leave the mean.
"""

import contextlib
from fractions import Fraction as F
import io
from itertools import product
import json
from math import comb
import tempfile
import unittest

from support import BENCH, CHECKS, preference, reply, score, write_input

QUESTIONS = json.loads((BENCH / "QUESTIONS.json").read_text(encoding="utf-8"))
IDS = [q["id"] for q in QUESTIONS["questions"]]
CORE = {q["id"]: [f["id"] for f in q["keyFacts"] if f["core"] and "all" in f["appliesTo"]] for q in QUESTIONS["questions"]}


def prefix(n):
    return {c: "PASS" if i < n else "FAIL" for i, c in enumerate(CHECKS)}


NO_JUDGED = {"M1": "N/A", "M2": "N/A", "M3": "CANNOT JUDGE", "M4": "CANNOT JUDGE", "M5": "N/A"}


def make_plan(flip_q14_to_tie=False):
    """plan[(question, arm, run)] = ("both", n1, n2) | ("g1", n) | ("failed",) | ("ungraded",) | ("noJudged",)."""
    plan = {}
    for i, q in enumerate(IDS):
        for arm, run in product((1, 2), (1, 2, 3)):
            if i < 15:
                n = (4, 5, 3)[run - 1] if arm == 1 else (2, 1, 3)[run - 1]          # arm 1 better
            else:
                n = (1, 2, 1)[run - 1] if arm == 1 else (3, 4, 2)[run - 1]          # arm 2 better
            if flip_q14_to_tie and i == 14:
                n = 3
            plan[(q, arm, run)] = ("both", n, min(5, n + run % 2))                 # G2 is sometimes kinder
    plan[(IDS[0], 2, 3)] = ("failed",)
    plan[(IDS[1], 1, 2)] = ("ungraded",)
    plan[(IDS[2], 1, 1)] = ("noJudged",)
    plan[(IDS[3], 2, 1)] = ("g1", 2)
    plan[(IDS[4], 1, 3)] = ("both", 5, 1)                                          # strong disagreement
    plan[(IDS[15], 1, 1)] = ("failed",)
    plan[(IDS[19], 1, 2)] = ("failed",)
    return plan


def expected_m(plan, q, arm):
    values = []
    for run in (1, 2, 3):
        entry = plan[(q, arm, run)]
        if entry[0] == "both":
            values.append(F(min(entry[1], entry[2])))
        elif entry[0] == "g1":
            values.append(F(entry[1]))
        elif entry[0] == "failed":
            values.append(F(0))
    return sum(values, F(0)) / len(values) if values else None


def build(folder, plan, invalid_g2=None):
    runs, scores, prefs, sides = [], {}, {}, {}
    for (q, arm, run), entry in sorted(plan.items()):
        runs.append((q, arm, run, "failed" if entry[0] == "failed" else "rendered"))
        sid = score.slot_id(q, arm, run)
        covered = CORE[q][:1 + run % 2]
        if entry[0] == "both":
            scores[("G1", sid)] = reply(q, prefix(entry[1]), errors=run - 1, covered=covered, clarity=2 + entry[1] % 4)
            scores[("G2", sid)] = reply(q, prefix(entry[2]), errors=run % 2, covered=covered, clarity=1 + entry[2] % 5,
                                        minor=1)
        elif entry[0] == "g1":
            scores[("G1", sid)] = reply(q, prefix(entry[1]), covered=covered)
        elif entry[0] == "noJudged":
            scores[("G1", sid)] = reply(q, NO_JUDGED, covered=covered)
            scores[("G2", sid)] = reply(q, NO_JUDGED)
    if invalid_g2:
        scores[("G2", invalid_g2)] = '{"question": "truncated'
    for q, run in product(IDS, (1, 2, 3)):
        pid = score.pair_id(q, run)
        if all(plan[(q, a, run)][0] != "failed" for a in (1, 2)):
            sides[pid] = 1 if run != 2 else 2
            better_arm = 1 if IDS.index(q) < 15 else 2
            letter = "A" if sides[pid] == better_arm else "B"
            prefs[("G1", pid)] = preference(q, "tok", letter)
            prefs[("G2", pid)] = preference(q, "tok", letter if run != 3 else "tie")
    return write_input(folder, runs, scores, prefs, sides)


def sign_p(pos, neg):
    n = pos + neg
    return min(F(1), F(2 * sum(comb(n, i) for i in range(min(pos, neg) + 1)), 2 ** n))


class EndToEndTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.key = score.load_key(BENCH / "QUESTIONS.json")

    def run_folder(self, plan, attest=True, invalid_g2=None):
        folder = build(self.tmp.name + "/in", plan, invalid_g2)
        out = self.tmp.name + "/result.json"
        argv = [str(folder), "--out", out] + (["--attest-within-21-days"] if attest else [])
        printed = io.StringIO()
        with contextlib.redirect_stdout(printed):
            self.assertEqual(score.main(argv), 0)
        self.assertIn("verdict:", printed.getvalue())
        with open(out, encoding="utf-8") as stream:
            return json.load(stream)

    def check_primary(self, result, plan):
        ds = []
        for row in result["primary"]["rows"]:
            m1, m2 = expected_m(plan, row["question"], 1), expected_m(plan, row["question"], 2)
            self.assertEqual(row["M1"]["exact"], str(m1), row["question"])
            self.assertEqual(row["M2"]["exact"], str(m2), row["question"])
            ds.append(m1 - m2)
            self.assertEqual(row["d"]["exact"], str(m1 - m2))
        pos, neg = sum(d > 0 for d in ds), sum(d < 0 for d in ds)
        test = result["primary"]["signTest"]
        self.assertEqual((test["positive"], test["negative"], test["ties"]), (pos, neg, 20 - pos - neg))
        self.assertEqual(test["p"]["exact"], str(sign_p(pos, neg)))
        self.assertEqual(result["primary"]["meanD"]["exact"], str(sum(ds, F(0)) / len(ds)))
        return pos, neg

    def test_win_at_fifteen_of_twenty(self):
        plan = make_plan()
        result = self.run_folder(plan, invalid_g2=score.slot_id(IDS[5], 2, 2))
        self.assertEqual(self.check_primary(result, plan), (15, 5))
        self.assertEqual(result["verdict"]["verdict"], "win")
        self.assertEqual(result["verdict"]["status"], "registered verdict (completed design)")
        self.assertFalse(result["primary"]["oppositeSignedEffect"])
        self.assertEqual(result["ungradedOutputs"], [score.slot_id(IDS[1], 1, 2)])
        self.assertEqual(result["mechanismNAOutputs"], [score.slot_id(IDS[2], 1, 1)])
        self.assertEqual([(i["grader"], i["id"]) for i in result["invalidGrades"]], [("G2", score.slot_id(IDS[5], 2, 2))])
        arm1, arm2 = result["countsPerArm"]["arm1"], result["countsPerArm"]["arm2"]
        self.assertEqual(sorted(arm1["failed"]), sorted([score.slot_id(IDS[15], 1, 1), score.slot_id(IDS[19], 1, 2)]))
        self.assertEqual(arm2["failed"], [score.slot_id(IDS[0], 2, 3)])
        self.assertEqual(arm2["oneGradeMissing"], sorted([score.slot_id(IDS[3], 2, 1), score.slot_id(IDS[5], 2, 2)]))
        self.assertEqual(arm1["successRate"]["value"]["exact"], "29/30")
        self.assertEqual(result["design"]["ungradedShare"]["value"]["exact"], "1/117")
        # E_fail for IDS[0] (arm 2, run 3): 1 + the largest merged error count of IDS[0] (runs 3 -> G1 2 errors).
        failed = next(r for r in result["runs"] if r["id"] == score.slot_id(IDS[0], 2, 3))
        self.assertEqual((failed["errors"], failed["clarity"], failed["coverage"]["exact"]), (3, 0, "0"))
        # Sensitivity without the 5 nearShipped questions (MECH-01, -03, -08 favour arm 1; MECH-17, -18 arm 2).
        sens = result["sensitivityWithoutNearShipped"]
        self.assertEqual((sens["signTest"]["positive"], sens["signTest"]["negative"]), (12, 3))
        self.assertEqual(sens["signTest"]["p"]["exact"], str(sign_p(12, 3)))
        self.assertEqual(sorted(score.NEAR_SHIPPED), sorted(q["id"] for q in QUESTIONS["questions"] if q.get("nearShipped")))
        # Preferences: 60 pairs, 3 with a failed run are automatic and won by the rendered arm 1 or 2.
        pref = result["exploratory"]["preference"]
        kinds = [p["kind"] for p in pref["pairs"]]
        self.assertEqual((kinds.count("graded"), kinds.count("automatic"), kinds.count("unjudged")), (57, 3, 0))
        self.assertEqual(pref["arm1WinRateGraded"]["numerator"], 15 * 2)          # runs 1 and 2 of the arm-1 questions
        self.assertEqual(pref["arm1WinRateGraded"]["ties"], 19)                    # run 3: G2 says tie
        # Agreement statistics exist and are numbers or undefined, never errors.
        agree = result["exploratory"]["agreement"]
        self.assertEqual(agree["outputsBothGraded"], 117 - 3)            # less: ungraded, G1 only, invalid G2
        self.assertIsNotNone(agree["mechanismScore"]["krippendorffAlphaInterval"])
        self.assertIsNotNone(agree["mechanismScore"]["spearmanRho"])
        self.assertEqual(agree["preference"]["pairsBothGraded"], 57)

    def test_fourteen_of_twenty_with_a_tie_is_no_conclusion(self):
        plan = make_plan(flip_q14_to_tie=True)
        result = self.run_folder(plan)
        self.assertEqual(self.check_primary(result, plan), (14, 5))
        self.assertEqual(result["primary"]["signTest"]["ties"], 1)
        self.assertEqual(result["verdict"]["verdict"], "no conclusion")

    def test_without_attestation_there_is_no_registered_verdict(self):
        result = self.run_folder(make_plan(), attest=False)
        self.assertIsNone(result["verdict"]["verdict"])
        self.assertEqual(result["verdict"]["primaryTestWouldBe"], "win")

    def test_mirror_is_a_loss(self):
        plan = {(q, 3 - a, r): v for (q, a, r), v in make_plan().items()}
        result = self.run_folder(plan)
        self.assertEqual(self.check_primary(result, plan), (5, 15))
        self.assertEqual(result["verdict"]["verdict"], "loss")


if __name__ == "__main__":
    unittest.main()
