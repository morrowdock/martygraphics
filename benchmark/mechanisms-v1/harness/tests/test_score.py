# SPDX-License-Identifier: Apache-2.0
"""Unit tests of the section 10 merge, the section 11 scoring and the verdict conditions (synthetic data only).

Every expected value is a fixed number or follows from a hand rule stated next to it; no test reads score.py's
choices back. Every reply passes the shared validator (the fixtures are built by support.build)."""

from fractions import Fraction as F
import json
import random
import sys
import tempfile
import unittest
from unittest import mock

import support as S
from support import CHECKS, NO_JUDGED, Plan, prefix, reply, score

ARMS = (1, 2)
# The first five slots of random.Random(20261111).shuffle over the real key's 120 sorted slots (fixed values).
FIRST_FIVE = ["MECH-18-r3-arm2", "MECH-15-r3-arm2", "MECH-01-r1-arm2", "MECH-19-r3-arm1", "MECH-20-r2-arm1"]


def rows(result, section=("primary",)):
    node = result
    for name in section:
        node = node[name]
    return {r["question"]: r for r in node["rows"]}


def record(result, sid):
    return next(r for r in result["runs"] if r["id"] == sid)


class Case(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.count = 0

    def run_plan(self, plan):
        self.count += 1
        return S.run(self.tmp.name, plan, "in%d" % self.count)[0]

    def load_error(self, plan, edit=None):
        self.count += 1
        folder = S.build(self.tmp.name + "/in%d" % self.count, plan)
        if edit:
            edit(folder)
        key = score.load_key(S.write_key(folder, plan.key_doc))
        with self.assertRaises(score.InputError) as caught:
            score.load_input(folder, key)
        return str(caught.exception)


# --------------------------------------------------------------------------------------------- pure merges

class MergeCheckTest(unittest.TestCase):
    def test_both_judged_pass_only_if_both_pass(self):
        self.assertEqual(score.merge_check(["PASS", "PASS"]), score.PASS)
        for other in ("FAIL", "NOT SHOWN"):
            self.assertEqual(score.merge_check(["PASS", other]), score.NOT_PASS)
            self.assertEqual(score.merge_check([other, "PASS"]), score.NOT_PASS)
        self.assertEqual(score.merge_check(["FAIL", "NOT SHOWN"]), score.NOT_PASS)

    def test_one_judged_gives_the_judgment(self):
        for unjudged in ("CANNOT JUDGE", "N/A"):
            self.assertEqual(score.merge_check(["PASS", unjudged]), score.PASS)
            self.assertEqual(score.merge_check([unjudged, "PASS"]), score.PASS)
            self.assertEqual(score.merge_check(["FAIL", unjudged]), score.NOT_PASS)
            self.assertEqual(score.merge_check([unjudged, "NOT SHOWN"]), score.NOT_PASS)

    def test_neither_judged(self):
        self.assertEqual(score.merge_check(["CANNOT JUDGE", "CANNOT JUDGE"]), score.UNJUDGED)
        self.assertEqual(score.merge_check(["CANNOT JUDGE", "N/A"]), score.UNJUDGED)
        self.assertEqual(score.merge_check(["N/A", "CANNOT JUDGE"]), score.UNJUDGED)
        self.assertEqual(score.merge_check(["N/A", "N/A"]), score.NA)

    def test_a_missing_grade_leaves_the_other(self):
        self.assertEqual(score.merge_check(["PASS"]), score.PASS)
        self.assertEqual(score.merge_check(["NOT SHOWN"]), score.NOT_PASS)
        self.assertEqual(score.merge_check(["CANNOT JUDGE"]), score.UNJUDGED)
        self.assertEqual(score.merge_check(["N/A"]), score.NA)
        with self.assertRaises(ValueError):
            score.merge_check([])


class MechanismScoreTest(unittest.TestCase):
    def test_five_times_pass_over_judged(self):
        merged = {"M1": score.PASS, "M2": score.PASS, "M3": score.PASS, "M4": score.NOT_PASS, "M5": score.NOT_PASS}
        self.assertEqual(score.mechanism_score(merged), F(3))

    def test_unjudged_and_na_leave_numerator_and_denominator(self):
        merged = {"M1": score.PASS, "M2": score.PASS, "M3": score.UNJUDGED, "M4": score.NA, "M5": score.NOT_PASS}
        self.assertEqual(score.mechanism_score(merged), F(10, 3))

    def test_no_judged_check_is_na(self):
        self.assertIsNone(score.mechanism_score({c: score.UNJUDGED for c in CHECKS}))
        self.assertIsNone(score.mechanism_score({c: score.NA for c in CHECKS}))


class OtherMergesTest(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.key = score.load_key(S.write_key(tmp.name, S.SYNTHETIC_KEY))

    def test_errors_clarity_defects(self):
        merged = score.merge_output({"G1": reply(("Q1", 1, 1), errors=1, clarity=5, major=2),
                                     "G2": reply(("Q1", 1, 1), errors=3, clarity=2, minor=3)}, self.key["Q1"])
        self.assertEqual((merged["errors"], merged["clarity"], merged["defects"]), (3, 2, {"major": 2, "minor": 3}))

    def test_per_check_merge_not_per_grader_score(self):
        # QV, variant w: G1 judges only M1 (PASS); G2 judges only M2 (FAIL). Per check: 1 PASS of 2 judged.
        g1 = reply(("QV", 1, 1), {"M1": "PASS", "M2": "N/A", "M3": "CANNOT JUDGE", "M4": "CANNOT JUDGE", "M5": "N/A"},
                   configuration="w")
        g2 = reply(("QV", 1, 1), {"M1": "N/A", "M2": "FAIL", "M3": "CANNOT JUDGE", "M4": "CANNOT JUDGE", "M5": "N/A"},
                   configuration="w")
        self.assertEqual(score.merge_output({"G1": g1, "G2": g2}, self.key["QV"])["mechanism"], F(5, 2))

    def test_coverage_rules(self):
        self.assertEqual(score.merge_coverage([F(1, 2), F(1, 3)]), F(1, 3))
        self.assertEqual(score.merge_coverage([None, F(1, 3)]), F(1, 3))
        self.assertEqual(score.merge_coverage([F(1, 2), None]), F(1, 2))
        self.assertIsNone(score.merge_coverage([None, None]))
        self.assertIsNone(score.merge_coverage([None]))
        self.assertEqual(score.merge_coverage([F(0)]), F(0))

    def test_coverage_uses_the_named_configuration(self):
        q = self.key["QV"]
        self.assertEqual(score.grader_coverage(reply(("QV", 1, 1), covered=["K1"]), q), F(1, 2))
        self.assertEqual(score.grader_coverage(reply(("QV", 1, 1), covered=["K1"], configuration="unclear"), q),
                         F(1, 2))
        self.assertEqual(score.grader_coverage(reply(("QV", 1, 1), covered=["K2"], configuration="w"), q), F(1))
        self.assertIsNone(score.grader_coverage(reply(("QV", 1, 1), covered=["K1"], configuration="v"), q))

    def test_every_ignored_covered_fact_is_warned(self):
        q = self.key["QV"]
        body = reply(("QV", 1, 1), covered=["K1", "K2"], configuration="w", na=["K1"])
        self.assertEqual(score.grader_coverage(body, q), F(1))                 # K1 is ignored under w
        self.assertEqual(score.coverage_warnings(body, q),
                         ["coveredFacts K1 is not applicable to configuration w and is ignored"])
        body = reply(("QV", 1, 1), covered=["K1"], configuration="v")
        self.assertEqual(score.coverage_warnings(body, q),
                         ["coveredFacts K1 is not applicable to configuration v and is ignored",
                          "core facts N/A by configuration v are ['K1', 'K2']; notApplicableFacts lists []"])


# ---------------------------------------------------------------------------------- zero denominators

class ZeroJudgedChecksBothArmsTest(Case):
    """No judged check: mechanism N/A, reported, left out of M(q, a), never a pass. Both arms; valid replies only
    (N/A needs an accepted variant, so these runs show QV's variant v)."""

    def test_one_run_without_judged_check(self):
        for arm in ARMS:
            with self.subTest(arm=arm):
                plan = Plan()
                for s in plan.slots():
                    for g in score.GRADERS:
                        plan.scores[(g, s)] = (reply(s, NO_JUDGED, configuration="v") if s == ("QV", arm, 2)
                                               else reply(s, prefix(1)))
                result = self.run_plan(plan)
                sid = score.slot_id("QV", arm, 2)
                self.assertIsNone(record(result, sid)["mechanism"])
                self.assertEqual(result["mechanismNAOutputs"], [sid])
                self.assertEqual(result["countsPerArm"]["arm%d" % arm]["mechanismNA"], [sid])
                self.assertEqual(rows(result)["QV"]["M%d" % arm], F(1))        # (1 + 1) / 2, not (1 + 0 + 1) / 3
                self.assertEqual(rows(result)["QV"]["d"], F(0))

    def test_all_runs_without_judged_check(self):
        for arm in ARMS:
            with self.subTest(arm=arm):
                plan = Plan()
                for r in (1, 2, 3):
                    for g in score.GRADERS:
                        plan.scores[(g, ("QV", arm, r))] = reply(("QV", arm, r), NO_JUDGED, configuration="v")
                result = self.run_plan(plan)
                self.assertIsNone(rows(result)["QV"]["M%d" % arm])
                self.assertIsNone(rows(result)["QV"]["d"])
                self.assertEqual(result["primary"]["leftOut"], ["QV"])
                self.assertEqual(result["primary"]["signTest"]["definedQuestions"], 1)

    def test_one_grader_judges_nothing(self):
        for arm in ARMS:
            for silent in score.GRADERS:
                with self.subTest(arm=arm, silent=silent):
                    plan = Plan()
                    for r in (1, 2, 3):
                        s = ("QV", arm, r)
                        plan.scores[(silent, s)] = reply(s, NO_JUDGED, configuration="v")
                        other = "G2" if silent == "G1" else "G1"
                        plan.scores[(other, s)] = reply(s, prefix(3))
                    self.assertEqual(rows(self.run_plan(plan))["QV"]["M%d" % arm], F(3))


class CoverageZeroDenominatorTest(Case):
    """No applicable core fact for one grader (either one), for both, or for the only grader; and for every run
    of an arm. Both arms. Variant v of QV has no applicable core fact; K1 is covered by the conventional replies."""

    def plan(self, arm, case):
        plan = Plan()
        for s in plan.slots():
            for g in score.GRADERS:
                plan.scores[(g, s)] = reply(s, covered=["K1"])

        def conv(s):
            return reply(s, covered=["K1"])

        def var(s):
            return reply(s, configuration="v")
        target = [("QV", arm, r) for r in ((1, 2, 3) if case == "all-runs" else (1,))]
        for s in target:
            if case == "G1-undefined":
                plan.scores[("G1", s)], plan.scores[("G2", s)] = var(s), conv(s)
            elif case == "G2-undefined":
                plan.scores[("G1", s)], plan.scores[("G2", s)] = conv(s), var(s)
            elif case in ("both", "all-runs"):
                plan.scores[("G1", s)], plan.scores[("G2", s)] = var(s), var(s)
            elif case == "only-grader":
                plan.scores[("G1", s)], plan.scores[("G2", s)] = var(s), "exhausted"
        return plan

    def test_matrix(self):
        for arm in ARMS:
            for case in ("G1-undefined", "G2-undefined", "both", "only-grader", "all-runs"):
                with self.subTest(arm=arm, case=case):
                    result = self.run_plan(self.plan(arm, case))
                    sid = score.slot_id("QV", arm, 1)
                    coverage = rows(result, ("exploratory", "coverage", "questionLevel"))["QV"]
                    if case.endswith("undefined"):
                        self.assertEqual(record(result, sid)["coverage"], F(1, 2))   # the other grader's 1/2
                        continue
                    self.assertIsNone(record(result, sid)["coverage"])
                    self.assertIn(sid, result["countsPerArm"]["arm%d" % arm]["coverageNA"])
                    if case == "all-runs":
                        self.assertIsNone(coverage["M%d" % arm])                   # undefined, not full
                        self.assertEqual(coverage["counts"][arm]["counted"], 0)
                    else:
                        self.assertEqual(coverage["M%d" % arm], F(1, 2))           # the two other runs, not 1
                    self.assertEqual(record(result, sid)["mechanism"], F(5))       # coverage N/A only


# ---------------------------------------------------------------------------------- failed and ungraded

class FailedRunTest(Case):
    def test_failed_run_scores(self):
        for arm in ARMS:
            with self.subTest(arm=arm):
                plan = Plan()
                plan.status[("Q1", arm, 3)] = "failed"
                # The largest merged error count of Q1 is 4, in the OTHER arm: E_fail(Q1) = 5.
                plan.scores[("G1", ("Q1", 3 - arm, 1))] = reply(("Q1", 3 - arm, 1), errors=4)
                result = self.run_plan(plan)
                r = record(result, score.slot_id("Q1", arm, 3))
                self.assertEqual((r["state"], r["mechanism"], r["clarity"], r["coverage"], r["errors"], r["defects"]),
                                 ("failed", F(0), 0, F(0), 5, None))
                self.assertEqual(rows(result)["Q1"]["M%d" % arm], F(10, 3))     # (5 + 5 + 0) / 3
                self.assertEqual(result["countsPerArm"]["arm%d" % arm]["failed"], [r["id"]])

    def test_every_run_of_an_arm_failed(self):
        for arm in ARMS:
            with self.subTest(arm=arm):
                plan = Plan()
                for r in (1, 2, 3):
                    plan.status[("Q1", arm, r)] = "failed"
                result = self.run_plan(plan)
                self.assertEqual(rows(result)["Q1"]["M%d" % arm], F(0))
                self.assertEqual(rows(result)["Q1"]["d"], F(-5) if arm == 1 else F(5))

    def test_efail_undefined_without_graded_output(self):
        # A-02: no graded output of Q1 in either arm -> E_fail(Q1) undefined; those runs leave the error means.
        plan = Plan()
        for s in plan.slots():
            if s[0] == "Q1":
                plan.status[s] = "failed"
        result = self.run_plan(plan)
        self.assertIsNone(record(result, "Q1-r1-arm1")["errors"])
        errors = rows(result, ("exploratory", "errors", "questionLevel"))["Q1"]
        self.assertIsNone(errors["M1"])
        self.assertEqual(errors["counts"][1]["leftOut"], ["Q1-r1-arm1", "Q1-r2-arm1", "Q1-r3-arm1"])
        self.assertEqual(result["exploratory"]["errors"]["efailContributions"],
                         {"arm1": {"failedRuns": 3, "withDefinedEfail": 0},
                          "arm2": {"failedRuns": 3, "withDefinedEfail": 0}})
        self.assertEqual(result["countsPerArm"]["arm1"]["failedWithUndefinedEfail"],
                         ["Q1-r1-arm1", "Q1-r2-arm1", "Q1-r3-arm1"])
        self.assertEqual(rows(result)["Q1"]["d"], F(0))                         # mechanism 0 against 0

    def test_efail_ignores_ungraded_outputs(self):
        plan = Plan()
        plan.status[("Q1", 1, 1)] = "failed"
        for s in plan.slots():
            if s[0] == "Q1" and s != ("Q1", 1, 1):
                for g in score.GRADERS:
                    plan.scores[(g, s)] = reply(s, errors=2)
        plan.scores[("G1", ("Q1", 2, 2))] = plan.scores[("G2", ("Q1", 2, 2))] = reply(("Q1", 2, 2), errors=7)
        plan.scores[("G1", ("Q1", 2, 3))] = plan.scores[("G2", ("Q1", 2, 3))] = "exhausted"
        result = self.run_plan(plan)
        self.assertEqual(record(result, "Q1-r1-arm1")["errors"], 8)
        self.assertEqual(record(result, "Q1-r3-arm2")["state"], "ungraded")

    def test_all_runs_failed_zero_rendered(self):
        plan = Plan()
        for s in plan.slots():
            plan.status[s] = "failed"
        result = self.run_plan(plan)
        self.assertEqual([(r["M1"], r["M2"], r["d"]) for r in result["primary"]["rows"]], [(F(0), F(0), F(0))] * 2)
        test = result["primary"]["signTest"]
        self.assertEqual((test["n"], test["ties"], test["p"], test["emptySample"]),
                         (0, 2, F(1), "every defined d(q) is 0"))
        self.assertEqual(result["verdict"]["verdict"], "no conclusion")
        self.assertEqual(result["design"]["ungradedShare"], {"numerator": 0, "denominator": 0, "value": None})
        self.assertEqual(result["design"]["callStatus"], {})
        self.assertEqual(result["exploratory"]["success"]["arm1"]["value"], F(0))
        self.assertEqual({p["kind"] for p in result["exploratory"]["preference"]["pairs"]}, {"automatic"})
        self.assertEqual(result["exploratory"]["preference"]["arm1WinRateWithAutomatic"]["value"], None)
        self.assertEqual(result["exploratory"]["agreement"]["outputsBothGraded"], 0)
        self.assertIsNone(result["exploratory"]["agreement"]["mechanismScore"]["krippendorffAlphaInterval"])
        self.assertIsNone(result["exploratory"]["errors"]["perArm"]["arm1"]["mean"])
        json.dumps(score.to_json(result))


class UngradedTest(Case):
    def test_ungraded_is_listed_not_dropped_not_zero(self):
        for arm in ARMS:
            with self.subTest(arm=arm):
                plan = Plan()
                s = ("Q1", arm, 2)
                plan.scores[("G1", s)] = plan.scores[("G2", s)] = "exhausted"
                result = self.run_plan(plan)
                r = record(result, score.slot_id(*s))
                self.assertEqual(r["state"], "ungraded")
                self.assertNotIn("mechanism", r)
                self.assertEqual(result["countsPerArm"]["arm%d" % arm]["ungraded"], [r["id"]])
                self.assertEqual(rows(result)["Q1"]["M%d" % arm], F(5))        # not (5 + 5 + 0) / 3
                self.assertEqual(len(result["runs"]), 12)

    def test_every_run_of_an_arm_ungraded(self):
        for arm in ARMS:
            with self.subTest(arm=arm):
                plan = Plan()
                for r in (1, 2, 3):
                    for g in score.GRADERS:
                        plan.scores[(g, ("QV", arm, r))] = "exhausted"
                result = self.run_plan(plan)
                self.assertIsNone(rows(result)["QV"]["M%d" % arm])
                self.assertEqual(result["primary"]["leftOut"], ["QV"])

    def test_one_grade_missing_is_graded(self):
        for g in score.GRADERS:
            with self.subTest(missing=g):
                plan = Plan()
                plan.scores[(g, ("Q1", 1, 1))] = "exhausted"
                plan.scores[("G2" if g == "G1" else "G1", ("Q1", 1, 1))] = reply(("Q1", 1, 1), prefix(2))
                result = self.run_plan(plan)
                self.assertEqual(record(result, "Q1-r1-arm1")["mechanism"], F(2))
                self.assertEqual(result["countsPerArm"]["arm1"]["oneGradeMissing"], ["Q1-r1-arm1"])
                self.assertEqual(result["verdict"]["verdict"], "no conclusion")    # exhausted is a finished call

    def test_ungraded_share_boundary(self):
        # 20 questions x 2 arms x 3 runs = 120 rendered outputs: 6 ungraded (5 %) keeps the verdict, 7 do not.
        for n_ungraded, complete in ((6, True), (7, False)):
            with self.subTest(ungraded=n_ungraded):
                plan = Plan(S.many_questions(20))
                for s in plan.slots()[:n_ungraded]:
                    plan.scores[("G1", s)] = plan.scores[("G2", s)] = "exhausted"
                result = self.run_plan(plan)
                self.assertEqual(result["design"]["complete"], complete)
                self.assertEqual(result["design"]["ungradedShare"]["value"], F(n_ungraded, 120))
                self.assertEqual(result["verdict"]["verdict"], "no conclusion" if complete else None)


# ------------------------------------------------------------------------------------- ties and the test

class TiesTest(Case):
    def test_exact_tie_that_floats_would_break(self):
        # Arm 1 runs: 1, 10/3, 5/3; Arm 2 runs: 0, 1, 5. Both means are exactly 2: d(q) = 0. A plain left-to-right
        # float sum gives 2.0000000000000004 against 2.0.
        total = 0.0
        for v in (1.0, 10 / 3, 5 / 3):
            total = total + v
        self.assertNotEqual(total / 3, (0.0 + 1.0 + 5.0) / 3)
        plan = Plan()
        checks = {("Q1", 1, 1): prefix(1), ("Q1", 1, 2): prefix(2, 3), ("Q1", 1, 3): prefix(1, 3),
                  ("Q1", 2, 1): prefix(0), ("Q1", 2, 2): prefix(1), ("Q1", 2, 3): prefix(5)}
        for s, c in checks.items():
            plan.scores[("G1", s)] = plan.scores[("G2", s)] = reply(s, c)
        result = self.run_plan(plan)
        self.assertEqual((rows(result)["Q1"]["M1"], rows(result)["Q1"]["d"]), (F(2), F(0)))
        self.assertEqual(result["primary"]["signTest"]["ties"], 2)

    def test_all_ties_and_no_defined_d(self):
        self.assertEqual(score.sign_test([F(0)] * 20)["p"], F(1))
        self.assertEqual(score.sign_test([F(0)] * 20)["emptySample"], "every defined d(q) is 0")
        self.assertEqual(score.sign_test([])["p"], F(1))
        self.assertEqual(score.sign_test([])["emptySample"], "no defined d(q)")
        self.assertEqual(score.test_result(score.sign_test([])), "no conclusion")

    def test_ties_leave_the_test(self):
        test = score.sign_test([F(1)] * 6 + [F(0)] * 14)
        self.assertEqual((test["n"], test["positive"], test["p"]), (6, 6, F(2, 64)))
        self.assertEqual(score.test_result(test), "win")

    def test_balanced_p_is_one(self):
        self.assertEqual(score.sign_test([F(1), F(-1)])["p"], F(1))
        self.assertEqual(score.sign_test([F(1)] * 10 + [F(-1)] * 10)["p"], F(1))


class SignTestBoundaryTest(Case):
    def test_fifteen_of_twenty(self):
        test = score.sign_test([F(1, 3)] * 15 + [F(-2)] * 5)
        self.assertEqual(test["p"], F(5425, 131072))                   # 2 x 21700 / 2^20
        self.assertEqual(score.test_result(test), "win")

    def test_fourteen_of_twenty(self):
        test = score.sign_test([F(1)] * 14 + [F(-1)] * 6)
        self.assertEqual(test["p"], F(15115, 131072))                  # 2 x 60460 / 2^20 = 0.1153
        self.assertEqual(score.test_result(test), "no conclusion")

    def test_loss_mirror_and_small_n(self):
        self.assertEqual(score.test_result(score.sign_test([F(1)] * 5 + [F(-1)] * 15)), "loss")
        self.assertEqual(score.test_result(score.sign_test([F(1)] * 6 + [F(-1)] * 14)), "no conclusion")
        self.assertEqual(score.sign_test([F(1)] * 5)["p"], F(1, 16))
        self.assertEqual(score.test_result(score.sign_test([F(1)] * 5)), "no conclusion")

    def test_p_exactly_alpha_is_not_significant(self):
        with mock.patch.object(score, "ALPHA", F(1, 32)):
            self.assertEqual(score.test_result(score.sign_test([F(1)] * 6)), "no conclusion")

    def test_opposite_signed_effect(self):
        plan = Plan(S.many_questions(20))
        for s in plan.slots():
            i = int(s[0][1:])
            n = (5 if s[1] == 1 else 4) if i < 15 else (0 if s[1] == 1 else 5)
            plan.scores[("G1", s)] = plan.scores[("G2", s)] = reply(s, prefix(n))
        result = self.run_plan(plan)
        self.assertEqual(result["primary"]["testResult"], "win")
        self.assertEqual(result["primary"]["meanD"], F(-1, 2))           # (15 x 1 - 5 x 5) / 20
        self.assertTrue(result["primary"]["oppositeSignedEffect"])
        self.assertIn("opposite-signed effect", score.summary(result))


# --------------------------------------------------------------------------------- the verdict conditions

class DesignRecordTest(Case):
    def reasons(self, plan):
        result = self.run_plan(plan)
        if result["design"]["complete"]:
            self.assertEqual(result["verdict"]["verdict"], "no conclusion")
        else:
            self.assertIsNone(result["verdict"]["verdict"])
        return result["design"]["reasons"]

    def test_complete_design_gives_the_verdict(self):
        self.assertEqual(self.reasons(Plan()), [])

    def test_probe_missing_g2_and_preference_replies(self):
        # Sol's probe: G2 never replied to some score calls and no preference call was recorded.
        plan = Plan()
        for s in plan.slots()[:3]:
            plan.scores[("G2", s)] = None
        for q in plan.questions:
            for r in (1, 2, 3):
                for g in score.GRADERS:
                    plan.preferences[(g, (q, r))] = None
        self.assertEqual(self.reasons(plan),
                         ["grading calls are not completed or exhausted under section 6: 15 not recorded"])

    def test_no_record_no_scoring(self):
        self.assertIn("RECORD.json", self.load_error(Plan(), lambda folder: (folder / "RECORD.json").unlink()))

    def test_incomplete_and_nonconforming_calls(self):
        plan = Plan()
        plan.scores[("G1", ("Q1", 1, 1))] = "incomplete"
        plan.scores[("G2", ("Q1", 1, 1))] = "nonconforming"
        # The output has no grade, so 1 of the 12 rendered outputs is ungraded (more than 5 %) as well.
        self.assertEqual(self.reasons(plan),
                         ["grading calls are not completed or exhausted under section 6: 1 incomplete, 1 nonconforming",
                          "more than 5 % of the rendered outputs are ungraded (1 of 12)"])

    def test_completed_after_fix_up_and_new_session(self):
        plan = Plan()
        plan.scores[("G1", ("Q1", 1, 1))] = [["not json", "still not json"], [reply(("Q1", 1, 1))]]
        result = self.run_plan(plan)
        self.assertEqual(result["design"]["reasons"], [])
        self.assertEqual([i["attempt"] for i in result["invalidReplies"]], ["1.1", "1.2"])

    def test_timing(self):
        for name, setup, expected in (
                ("late", lambda p: setattr(p, "extra_days", 22), "the design did not complete within 21 days"),
                ("withdrawn", lambda p: setattr(p, "withdrawn", ["gemini-4-argon"]),
                 "a model was withdrawn: gemini-4-argon"),
                ("commit", lambda p: setattr(p, "commit_before_end", True), "timing"),
                ("reply", lambda p: setattr(p, "reply_before_commit", True), "timing"),
                ("order", lambda p: setattr(p, "swap_order", True), "timing"),
                ("overlap", lambda p: setattr(p, "overlap", True), "timing"),
                ("long", lambda p: setattr(p, "long_run", ("Q1", 1, 1)), "timing"),
                # Re-check 2026-11-12: a guess that STARTED before the preference was stored, even though its
                # reply came later, must block the registered verdict.
                ("guess", lambda p: setattr(p, "guess_early", True), "timing")):
            with self.subTest(name):
                plan = Plan()
                setup(plan)
                reasons = self.reasons(plan)
                self.assertEqual(len(reasons), 1, reasons)
                self.assertIn(expected, reasons[0])

    def test_within_21_days(self):
        plan = Plan()
        plan.extra_days = 19                     # run 1 to the last reply is about 19 days -> complete
        self.assertEqual(self.reasons(plan), [])

    def test_missing_slot(self):
        plan = Plan()
        plan.missing.add(("Q1", 1, 1))
        self.assertEqual(self.reasons(plan), ["1 run slots are not generated"])

    def test_registered_order(self):
        plan = Plan(S.registered_shape_key())
        order = [score.slot_id(*s) for s in plan.slots()]
        random.Random(20261111).shuffle(order)
        self.assertEqual(order[:5], FIRST_FIVE)


# ---------------------------------------------------------------------------------------- preferences

class PreferenceTest(Case):
    def test_merge(self):
        self.assertEqual(score.merge_preference(["arm1", "arm1"]), "arm1")
        self.assertEqual(score.merge_preference(["tie", "arm2"]), "tie")
        self.assertEqual(score.merge_preference(["arm1", "arm2"]), "tie")
        self.assertEqual(score.merge_preference(["arm2"]), "arm2")
        self.assertIsNone(score.merge_preference([]))

    def test_pairs_automatic_unjudged_and_rates(self):
        plan = Plan()
        plan.status[("Q1", 2, 2)] = "failed"
        plan.status[("QV", 1, 3)] = plan.status[("QV", 2, 3)] = "failed"
        L = S.letter
        plan.preferences[("G1", ("Q1", 1))] = L("Q1", 1, 1)
        plan.preferences[("G2", ("Q1", 1))] = L("Q1", 1, 1)
        plan.preferences[("G1", ("Q1", 3))] = L("Q1", 3, 2)
        plan.preferences[("G2", ("Q1", 3))] = "tie"
        plan.preferences[("G1", ("QV", 1))] = L("QV", 1, 2)
        plan.preferences[("G2", ("QV", 1))] = "exhausted"
        plan.preferences[("G1", ("QV", 2))] = plan.preferences[("G2", ("QV", 2))] = "exhausted"
        result = self.run_plan(plan)
        pref = result["exploratory"]["preference"]
        got = {p["pair"]: (p["kind"], p["result"]) for p in pref["pairs"]}
        self.assertEqual(got, {"Q1-r1": ("graded", "arm1"), "Q1-r2": ("automatic", "arm1"), "Q1-r3": ("graded", "tie"),
                               "QV-r1": ("graded", "arm2"), "QV-r2": ("unjudged", None),
                               "QV-r3": ("automatic", "tie")})
        self.assertEqual(pref["unjudged"], ["QV-r2"])
        self.assertEqual(pref["arm1WinRateGraded"]["value"], F(1, 2))
        self.assertEqual(pref["arm1WinRateWithAutomatic"]["value"], F(2, 3))
        winners = {r["question"]: r["winner"] for r in pref["questionWinnersGraded"]["rows"]}
        self.assertEqual(winners, {"Q1": "arm1", "QV": "arm2"})
        self.assertEqual(pref["questionWinnersGraded"]["meanSign"], F(0))
        self.assertEqual(result["design"]["reasons"], [])

    def test_win_rate_zero_denominator(self):
        result = self.run_plan(Plan())                           # every preference is a tie
        rate = result["exploratory"]["preference"]["arm1WinRateGraded"]
        self.assertEqual((rate["numerator"], rate["denominator"], rate["value"], rate["ties"]), (0, 0, None, 6))
        self.assertEqual(rate["interval"]["undefinedResamples"], 10000)


class BlindingResultTest(Case):
    def test_counts_and_binomial(self):
        plan = Plan()
        pairs = [(q, r) for q in plan.questions for r in (1, 2, 3)]
        for q, r in pairs:
            plan.guesses[("G1", (q, r))] = S.letter(q, r, 1)                 # always right
        for n, (q, r) in enumerate(pairs):
            plan.guesses[("G2", (q, r))] = S.letter(q, r, 2) if n < 2 else "cannot tell"
        out = self.run_plan(plan)["exploratory"]["blinding"]
        self.assertEqual((out["G1"]["correct"], out["G1"]["wrong"], out["G1"]["cannotTell"]), (6, 0, 0))
        self.assertEqual(out["G1"]["binomialP"], F(1, 32))                   # 2 x (1/2)^6
        self.assertEqual((out["G2"]["correct"], out["G2"]["wrong"], out["G2"]["cannotTell"]), (0, 2, 4))
        self.assertEqual(out["G2"]["binomialP"], F(1, 2))

    def test_no_guess_is_undefined(self):
        self.assertIsNone(self.run_plan(Plan())["exploratory"]["blinding"]["G1"]["binomialP"])


class OtherExploratoryTest(Case):
    def test_cost_success_category_and_rendered_pairs(self):
        plan = Plan()
        for s in plan.slots():
            plan.costs[s] = (2, "0.25") if s[1] == 1 else (4, "1.50")
        plan.status[("Q1", 2, 1)] = "failed"
        plan.scores[("G1", ("Q1", 1, 1))] = reply(("Q1", 1, 1), errors=3)
        result = self.run_plan(plan)["exploratory"]
        self.assertEqual(result["cost"]["arm1"]["tries"]["mean"], F(2))
        self.assertEqual(result["cost"]["arm2"]["costUsd"]["sum"], F(9))       # 6 runs x 1.50
        self.assertEqual(result["cost"]["arm1"]["wallSeconds"]["mean"], F(600))
        self.assertEqual(result["success"]["arm2"]["value"], F(5, 6))
        self.assertEqual(result["success"]["perQuestion"][0]["arm2"]["value"], F(2, 3))
        # Errors: all runs (Q1 arm 1 = 3, 0, 0 -> 1) against rendered pairs only (pair r1 has a failure -> 0).
        self.assertEqual(rows(result, ("errors", "questionLevel"))["Q1"]["M1"], F(1))
        self.assertEqual(rows(result, ("errors", "renderedPairsOnly", "questionLevel"))["Q1"]["M1"], F(0))
        self.assertEqual([c["category"] for c in result["perCategory"]], ["c1", "c2"])
        self.assertEqual(result["perCategory"][0]["arm2"]["mean"], F(10, 3))   # Q1 arm 2: 0, 5, 5
        self.assertEqual(result["optionalSecondGenerator"][:11], "not enabled")


# ------------------------------------------------------------------------------------------ input checks

class InputTest(Case):
    def test_score_call_for_a_failed_run(self):
        plan = Plan()
        plan.status[("Q1", 1, 1)] = "failed"

        def add_call(folder):
            doc = json.loads((folder / "RECORD.json").read_text())
            doc["calls"].append({"grader": "G1", "kind": "score", "id": "Q1-r1-arm1", "sessions": []})
            (folder / "RECORD.json").write_text(json.dumps(doc))
        self.assertIn("not a rendered output", self.load_error(plan, add_call))

    def test_pair_sides_duplicates_and_conflicts(self):
        import blinding
        t, a = blinding.pair_token(S.SEED, "Q1", 1), blinding.arm_shown_as_a(S.SEED, "Q1", 1)
        for extra in ("Q1-r1,%s,%d\n" % (t, a), "Q1-r1,%s,%d\n" % (t, 3 - a)):
            with self.subTest(extra=extra):
                def edit(folder):
                    with open(folder / "pair-sides.csv", "a") as stream:
                        stream.write(extra)
                self.assertIn("pair-sides.csv lists Q1-r1 twice", self.load_error(Plan(), edit))

    def test_mapping_must_match_the_seed(self):
        def token(folder):
            text = (folder / "output-tokens.csv").read_text().splitlines()
            text[1] = text[1].split(",")[0] + ",000000000000"
            (folder / "output-tokens.csv").write_text("\n".join(text) + "\n")
        self.assertIn("output-tokens.csv", self.load_error(Plan(), token))

        def flip(folder):
            text = (folder / "pair-sides.csv").read_text().splitlines()
            pair, tok, a = text[1].split(",")
            text[1] = ",".join([pair, tok, str(3 - int(a))])
            (folder / "pair-sides.csv").write_text("\n".join(text) + "\n")
        self.assertIn("pair-sides.csv", self.load_error(Plan(), flip))

    def test_commitment(self):
        self.assertIn("COMMITMENT", self.load_error(
            Plan(), lambda folder: (folder / "BLINDING-COMMITMENT.txt").write_text("0" * 64)))

    def test_reply_with_another_token_is_invalid(self):
        plan = Plan()
        plan.scores[("G1", ("Q1", 1, 1))] = [[reply(("Q1", 1, 1), output="ffffffffffff")] * 2] * 3
        result = self.run_plan(plan)
        self.assertEqual(record(result, "Q1-r1-arm1")["graders"], ["G2"])
        self.assertEqual(len(result["invalidReplies"]), 6)
        self.assertEqual(result["design"]["reasons"], [])

    def test_runs_csv(self):
        def duplicate(folder):
            lines = (folder / "runs.csv").read_text().splitlines()
            (folder / "runs.csv").write_text("\n".join(lines + [lines[1]]) + "\n")
        self.assertIn("twice", self.load_error(Plan(), duplicate))

        def void(folder):
            lines = (folder / "runs.csv").read_text().splitlines()
            lines[1] = lines[1].replace("rendered", "void")
            (folder / "runs.csv").write_text("\n".join(lines) + "\n")
        self.assertIn("status", self.load_error(Plan(), void))


class NumpyAndBootstrapTest(unittest.TestCase):
    def test_numpy_is_required_at_the_pin(self):
        import numpy
        self.assertEqual(numpy.__version__, json.loads((S.BENCH / "RUN-LOCK.json").read_text())["harness"]["numpy"])
        with mock.patch.dict(sys.modules, {"numpy": None}):
            with self.assertRaises(score.InputError):
                score.require_numpy()
        with mock.patch.object(numpy, "__version__", "0.0.0"):
            with self.assertRaises(score.InputError):
                score.require_numpy()

    def test_fixed_values(self):
        # Fixed outputs of NumPy 2.5.4 default_rng(20261111) (A-05); they change only with the algorithm or NumPy.
        out = score.bootstrap_mean([F(i - 7, 3) for i in range(20)])
        self.assertAlmostEqual(out["low"], 0.0, places=12)
        self.assertAlmostEqual(out["high"], 1.6833333333333331, places=12)
        out = score.bootstrap_ratio([1, 2, 0, 3, 5], [2, 2, 1, 4, 5])
        self.assertEqual((out["low"], out["undefinedResamples"]), (0.5, 0))
        self.assertAlmostEqual(out["high"], 18 / 19, places=12)
        out = score.bootstrap_ratio([1, 0], [1, 0])                      # item 2 alone has a 0 denominator
        self.assertEqual((out["undefinedResamples"], out["low"], out["high"]), (2575, 1.0, 1.0))
        self.assertIsNone(score.bootstrap_mean([])["low"])


if __name__ == "__main__":
    unittest.main()
