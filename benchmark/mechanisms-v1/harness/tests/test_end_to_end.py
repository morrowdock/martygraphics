# SPDX-License-Identifier: Apache-2.0
"""End to end on SYNTHETIC grader replies: the real key's 20 question ids x 3 runs x 2 arms, then the verdict.

No real output is read or made. The input folder (runs, seed, mapping, dated record, every reply) is generated from
a plan, run through the command line, and the expected M(q, a), d(q), sign test and verdict are computed here from
the plan by hand rules, not by score.py:
  a run graded by both graders with n1 and n2 PASS (all five checks judged, PASS first) merges to min(n1, n2);
  a run graded by one grader with n PASS scores n; a failed run is 0;
  an ungraded run and a run with no judged check leave the mean.
"""

import contextlib
from fractions import Fraction as F
import io
import json
from math import comb
import tempfile
import unittest

import support as S
from support import BENCH, NO_JUDGED, Plan, prefix, reply, score

QUESTIONS = json.loads((BENCH / "QUESTIONS.json").read_text(encoding="utf-8"))
IDS = [q["id"] for q in QUESTIONS["questions"]]
CORE_ALL = {q["id"]: [f["id"] for f in q["keyFacts"] if f["core"] and "all" in f["appliesTo"]]
            for q in QUESTIONS["questions"]}


def make(flip_q14_to_tie=False, mirror=False):
    """(plan, table): table[(q, arm, run)] = ("both", n1, n2) | ("one", n) | ("failed",) | ("ungraded",) | ("none",)."""
    table = {}
    for i, q in enumerate(IDS):
        for arm in (1, 2):
            for run in (1, 2, 3):
                if i < 15:
                    n = (4, 5, 3)[run - 1] if arm == 1 else (2, 1, 3)[run - 1]          # arm 1 better
                else:
                    n = (1, 2, 1)[run - 1] if arm == 1 else (3, 4, 2)[run - 1]          # arm 2 better
                if flip_q14_to_tie and i == 14:
                    n = 3
                table[(q, arm, run)] = ("both", n, min(5, n + run % 2))                 # G2 is sometimes kinder
    table[(IDS[0], 2, 3)] = ("failed",)
    table[(IDS[1], 1, 2)] = ("ungraded",)
    table[(IDS[5], 1, 1)] = ("none",)                 # MECH-06, variant reversing-motor: no judged check
    table[(IDS[3], 2, 1)] = ("one", 2)                # G2's call is exhausted
    table[(IDS[4], 1, 3)] = ("both", 5, 1)            # strong disagreement
    table[(IDS[15], 1, 1)] = ("failed",)
    table[(IDS[19], 1, 2)] = ("failed",)
    if mirror:
        table = {(q, 3 - a, r): v for (q, a, r), v in table.items()}
    plan = Plan(QUESTIONS)
    better = {q: (1 if i < 15 else 2) if not mirror else (2 if i < 15 else 1) for i, q in enumerate(IDS)}
    for (q, arm, run), entry in table.items():
        slot = (q, arm, run)
        covered = CORE_ALL[q][:1 + run % 2]
        if entry[0] == "failed":
            plan.status[slot] = "failed"
        elif entry[0] == "ungraded":
            plan.scores[("G1", slot)] = plan.scores[("G2", slot)] = "exhausted"
        elif entry[0] == "none":
            for g in score.GRADERS:
                plan.scores[(g, slot)] = reply(slot, NO_JUDGED, configuration="reversing-motor", covered=covered)
        elif entry[0] == "one":
            plan.scores[("G1", slot)] = reply(slot, prefix(entry[1]), covered=covered)
            plan.scores[("G2", slot)] = "exhausted"
        else:
            plan.scores[("G1", slot)] = reply(slot, prefix(entry[1]), errors=run - 1, covered=covered,
                                              clarity=2 + entry[1] % 4)
            plan.scores[("G2", slot)] = reply(slot, prefix(entry[2]), errors=run % 2, covered=covered,
                                              clarity=1 + entry[2] % 5, minor=1)
    # One G2 reply is valid only after the parse-error message (section 6): it still counts.
    fixed = (IDS[6], 2, 2) if not mirror else (IDS[6], 1, 2)
    plan.scores[("G2", fixed)] = [["```json\n{}\n```", plan.scores[("G2", fixed)]]]
    for q in IDS:
        for run in (1, 2, 3):
            plan.preferences[("G1", (q, run))] = S.letter(q, run, better[q])
            plan.preferences[("G2", (q, run))] = S.letter(q, run, better[q]) if run != 3 else "tie"
            plan.guesses[("G1", (q, run))] = S.letter(q, run, 1)
    return plan, table


def expected_m(table, q, arm):
    values = []
    for run in (1, 2, 3):
        entry = table[(q, arm, run)]
        if entry[0] == "both":
            values.append(F(min(entry[1], entry[2])))
        elif entry[0] == "one":
            values.append(F(entry[1]))
        elif entry[0] == "failed":
            values.append(F(0))
    return sum(values, F(0)) / len(values) if values else None


def sign_p(pos, neg):
    n = pos + neg
    return min(F(1), F(2 * sum(comb(n, i) for i in range(min(pos, neg) + 1)), 2 ** n))


class EndToEndTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)

    def cli(self, plan, edit=None):
        folder = S.build(self.tmp.name + "/in", plan)
        if edit:
            edit(folder)
        out = self.tmp.name + "/result.json"
        printed = io.StringIO()
        with contextlib.redirect_stdout(printed), contextlib.redirect_stderr(printed):
            code = score.main([str(folder), "--out", out])
        if code != 0:
            return code, printed.getvalue(), None
        with open(out, encoding="utf-8") as stream:
            return code, printed.getvalue(), json.load(stream)

    def check_primary(self, result, table):
        ds = []
        for row in result["primary"]["rows"]:
            m1, m2 = expected_m(table, row["question"], 1), expected_m(table, row["question"], 2)
            self.assertEqual((row["M1"]["exact"], row["M2"]["exact"]), (str(m1), str(m2)), row["question"])
            ds.append(m1 - m2)
            self.assertEqual(row["d"]["exact"], str(m1 - m2))
        pos, neg = sum(d > 0 for d in ds), sum(d < 0 for d in ds)
        test = result["primary"]["signTest"]
        self.assertEqual((test["positive"], test["negative"], test["ties"]), (pos, neg, 20 - pos - neg))
        self.assertEqual(test["p"]["exact"], str(sign_p(pos, neg)))
        self.assertEqual(result["primary"]["meanD"]["exact"], str(sum(ds, F(0)) / len(ds)))
        self.assertIsNotNone(result["primary"]["interval"]["low"])
        return pos, neg

    def test_win_at_fifteen_of_twenty(self):
        plan, table = make()
        code, printed, result = self.cli(plan)
        self.assertEqual(code, 0, printed)
        self.assertEqual(self.check_primary(result, table), (15, 5))
        self.assertEqual(result["verdict"], {"verdict": "win", "status": "registered verdict (completed design)"})
        self.assertIn("verdict: win", printed)
        self.assertEqual(result["primary"]["signTest"]["p"]["exact"], "5425/131072")
        self.assertFalse(result["primary"]["oppositeSignedEffect"])
        self.assertEqual(result["ungradedOutputs"], [score.slot_id(IDS[1], 1, 2)])
        self.assertEqual(result["mechanismNAOutputs"], [score.slot_id(IDS[5], 1, 1)])
        # 117 rendered outputs x 2 score calls (3 exhausted), 57 pairs x 2 preference calls, and a guess call after
        # each stored preference: 231 + 114 + 114 completed.
        self.assertEqual(result["design"]["callStatus"], {"completed": 231 + 114 + 114, "exhausted": 3})
        arm1, arm2 = result["countsPerArm"]["arm1"], result["countsPerArm"]["arm2"]
        self.assertEqual(sorted(arm1["failed"]), sorted([score.slot_id(IDS[15], 1, 1), score.slot_id(IDS[19], 1, 2)]))
        self.assertEqual(arm2["failed"], [score.slot_id(IDS[0], 2, 3)])
        self.assertEqual(arm2["oneGradeMissing"], [score.slot_id(IDS[3], 2, 1)])
        self.assertEqual(result["design"]["ungradedShare"]["value"]["exact"], "1/117")
        # E_fail for IDS[0] arm 2 run 3: 1 + the largest merged error count of IDS[0] (run 3: G1 has 2 errors).
        failed = next(r for r in result["runs"] if r["id"] == score.slot_id(IDS[0], 2, 3))
        self.assertEqual((failed["errors"], failed["clarity"], failed["coverage"]["exact"]), (3, 0, "0"))
        # Sensitivity without the 5 nearShipped questions (MECH-01, -03, -08 favour arm 1; MECH-17, -18 arm 2).
        sens = result["sensitivityWithoutNearShipped"]
        self.assertEqual((sens["signTest"]["positive"], sens["signTest"]["negative"]), (12, 3))
        self.assertEqual(sens["signTest"]["p"]["exact"], str(sign_p(12, 3)))
        self.assertEqual(sorted(score.NEAR_SHIPPED), sorted(q["id"] for q in QUESTIONS["questions"]
                                                            if q.get("nearShipped")))
        # Preferences: 57 graded pairs and 3 automatic ones.
        pref = result["exploratory"]["preference"]
        kinds = [p["kind"] for p in pref["pairs"]]
        self.assertEqual((kinds.count("graded"), kinds.count("automatic"), kinds.count("unjudged")), (57, 3, 0))
        self.assertEqual(pref["arm1WinRateGraded"]["numerator"], 15 * 2)         # runs 1 and 2 of 15 questions
        self.assertEqual(pref["questionWinnersGraded"]["arm1Questions"], 15)
        self.assertEqual(pref["questionWinnersGraded"]["arm2Questions"], 5)
        # Blinding: G1 always names arm 1 (57 of 57 correct); G2 always cannot tell.
        blind = result["exploratory"]["blinding"]
        self.assertEqual((blind["G1"]["correct"], blind["G1"]["wrong"]), (57, 0))
        self.assertEqual(blind["G1"]["binomialP"]["exact"], str(F(2, 2 ** 57)))
        self.assertEqual(blind["G2"]["cannotTell"], 57)
        self.assertIsNone(blind["G2"]["binomialP"])
        # Agreement: 117 rendered, less the ungraded, the G1-only output: 115 both graded.
        agree = result["exploratory"]["agreement"]
        self.assertEqual(agree["outputsBothGraded"], 115)
        self.assertIsNotNone(agree["mechanismScore"]["alphaInterval"]["low"])
        self.assertEqual(agree["preference"]["pairsBothGraded"], 57)
        self.assertEqual([i["attempt"] for i in result["invalidReplies"] if i["id"] == score.slot_id(IDS[6], 2, 2)],
                         ["1.1"])
        self.assertEqual(len(result["exploratory"]["perCategory"]), len({q["category"] for q in QUESTIONS["questions"]}))

    def test_fourteen_of_twenty_with_a_tie_is_no_conclusion(self):
        plan, table = make(flip_q14_to_tie=True)
        code, printed, result = self.cli(plan)
        self.assertEqual(self.check_primary(result, table), (14, 5))
        self.assertEqual(result["primary"]["signTest"]["ties"], 1)
        self.assertEqual(result["verdict"]["verdict"], "no conclusion")

    def test_mirror_is_a_loss(self):
        plan, table = make(mirror=True)
        code, printed, result = self.cli(plan)
        self.assertEqual(self.check_primary(result, table), (5, 15))
        self.assertEqual(result["verdict"]["verdict"], "loss")

    def test_probe_without_complete_record_no_verdict(self):
        # Missing G2 score replies and missing preference replies: descriptive results only, never a verdict.
        plan, table = make()
        for slot in [s for s in plan.slots() if table[s][0] == "both"][:4]:
            plan.scores[("G2", slot)] = None
        for q in IDS:
            plan.preferences[("G2", (q, 1))] = None
        code, printed, result = self.cli(plan)
        self.assertIsNone(result["verdict"]["verdict"])
        self.assertEqual(result["verdict"]["primaryTestWouldBe"], "win")
        # 4 G2 score calls, and G2's preference call for run 1 of the 19 questions whose run-1 pair rendered twice
        # (IDS[15] arm 1 run 1 failed). No guess is due without a stored preference.
        self.assertEqual(result["design"]["callStatus"]["not recorded"], 4 + 19)
        code, printed, _ = self.cli(make()[0], lambda folder: (folder / "RECORD.json").unlink())
        self.assertEqual(code, 2)
        self.assertIn("RECORD.json", printed)


if __name__ == "__main__":
    unittest.main()
