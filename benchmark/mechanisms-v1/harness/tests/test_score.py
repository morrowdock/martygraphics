# SPDX-License-Identifier: Apache-2.0
"""Unit tests of the section 10 merge and the section 11 scoring (synthetic data only)."""

from fractions import Fraction as F
import sys
import tempfile
import unittest
from unittest import mock

from support import CHECKS, checks_with, key, preference, reply, score, write_input

ARMS = (1, 2)
ALL_PASS = {c: "PASS" for c in CHECKS}
NO_JUDGED_CJ = {"M1": "N/A", "M2": "N/A", "M3": "CANNOT JUDGE", "M4": "CANNOT JUDGE", "M5": "N/A"}


def memory(runs, scores=(), preferences=(), sides=None, attest=True, k=None):
    """Run the whole analysis in memory. runs: [(q, arm, run, status)]; scores: [(grader, slot, reply)]."""
    k = k or key()
    table = {score.slot_id(q, a, r): {"id": score.slot_id(q, a, r), "question": q, "arm": a, "run": r, "status": s}
             for q, a, r, s in runs}
    sc = {g: {} for g in score.GRADERS}
    for g, sid, body in scores:
        sc[g][sid] = body
    pf = {g: {} for g in score.GRADERS}
    for g, pid, body in preferences:
        pf[g][pid] = body
    return score.analyse(table, sides or {}, sc, pf, [], k, attest_21_days=attest)


def full_runs(status=None, questions=("Q1", "QV")):
    status = status or {}
    return [(q, a, r, status.get((q, a, r), "rendered")) for q in questions for a in ARMS for r in (1, 2, 3)]


def run_record(result, sid):
    return next(r for r in result["runs"] if r["id"] == sid)


def row(result, question, section="primary"):
    return next(r for r in result[section]["rows"] if r["question"] == question)


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
        self.assertIsNone(score.mechanism_score({"M1": score.NA, "M2": score.NA, "M3": score.UNJUDGED,
                                                 "M4": score.UNJUDGED, "M5": score.NA}))

    def test_per_check_merge_not_per_grader_score(self):
        # G1 judges only M1 (PASS); G2 judges only M2 (FAIL). The merge is per check: 1 PASS of 2 judged.
        g1 = reply(checks={"M1": "PASS", "M2": "N/A", "M3": "CANNOT JUDGE", "M4": "CANNOT JUDGE", "M5": "N/A"})
        g2 = reply(checks={"M1": "N/A", "M2": "FAIL", "M3": "CANNOT JUDGE", "M4": "CANNOT JUDGE", "M5": "N/A"})
        merged = score.merge_output({"G1": g1, "G2": g2}, key()["Q1"])
        self.assertEqual(merged["mechanism"], F(5, 2))


class ZeroJudgedChecksBothArmsTest(unittest.TestCase):
    """No judged check (denominator 0): mechanism N/A, reported, left out of M(q, a), never a pass. Both arms."""

    def test_one_run_without_judged_check_leaves_the_mean(self):
        for arm in ARMS:
            with self.subTest(arm=arm):
                scores = []
                for q, a, r, _ in full_runs():
                    sid = score.slot_id(q, a, r)
                    body = reply(q, checks=checks_with(1)) if (a, r) != (arm, 2) else reply(q, checks=NO_JUDGED_CJ)
                    scores += [("G1", sid, body), ("G2", sid, body)]
                result = memory(full_runs(), scores)
                na_id = score.slot_id("Q1", arm, 2)
                self.assertIsNone(run_record(result, na_id)["mechanism"])
                self.assertIn(na_id, result["mechanismNAOutputs"])
                self.assertIn(na_id, result["countsPerArm"]["arm%d" % arm]["mechanismNA"])
                # The mean is over the two other runs (1 each), not three runs with a 0 or a 5.
                self.assertEqual(row(result, "Q1")["M%d" % arm], F(1))
                self.assertEqual(row(result, "Q1")["d"], F(0))

    def test_all_runs_without_judged_check_make_m_undefined(self):
        for arm in ARMS:
            with self.subTest(arm=arm):
                scores = []
                for q, a, r, _ in full_runs():
                    sid = score.slot_id(q, a, r)
                    body = reply(q, checks=NO_JUDGED_CJ) if (q, a) == ("Q1", arm) else reply(q)
                    scores += [("G1", sid, body), ("G2", sid, body)]
                result = memory(full_runs(), scores)
                self.assertIsNone(row(result, "Q1")["M%d" % arm])
                self.assertIsNone(row(result, "Q1")["d"])
                self.assertIn("Q1", result["primary"]["leftOut"])
                self.assertEqual(result["primary"]["definedQuestions"], 1)

    def test_one_grader_judges_nothing_the_other_does(self):
        for arm in ARMS:
            with self.subTest(arm=arm):
                scores = []
                for q, a, r, _ in full_runs():
                    sid = score.slot_id(q, a, r)
                    if a == arm:
                        scores += [("G1", sid, reply(q, checks=NO_JUDGED_CJ)), ("G2", sid, reply(q, checks=checks_with(3)))]
                    else:
                        scores += [("G1", sid, reply(q)), ("G2", sid, reply(q))]
                result = memory(full_runs(), scores)
                self.assertEqual(row(result, "Q1")["M%d" % arm], F(3))


class CoverageTest(unittest.TestCase):
    def test_smaller_fraction(self):
        q = key()["Q1"]
        merged = score.merge_output({"G1": reply(covered=["K1", "K2"]), "G2": reply(covered=["K1"])}, q)
        self.assertEqual(merged["coverage"], F(1, 2))

    def test_only_applicable_core_facts_count(self):
        q = key()["Q1"]
        # K3 is not core; K9 is not in the key: neither enters the numerator.
        self.assertEqual(score.grader_coverage(reply(covered=["K1", "K3", "K9"]), q), F(1, 2))

    def test_configuration_selects_applicable_facts(self):
        q = key()["QV"]
        self.assertEqual(score.grader_coverage(reply("QV", covered=["K1"]), q), F(1, 2))
        self.assertEqual(score.grader_coverage(reply("QV", covered=["K1"], configuration="unclear"), q), F(1, 2))
        self.assertEqual(score.grader_coverage(reply("QV", covered=["K1"], configuration="nonsense"), q), F(1, 2))
        self.assertIsNone(score.grader_coverage(reply("QV", covered=["K1"], configuration="v"), q))

    def test_grader_list_decision(self):
        q = key()["Q1"]
        with mock.patch.dict(score.DECISIONS, applicableCoreFacts="grader-list"):
            self.assertEqual(score.grader_coverage(reply(covered=["K1"], na=["K2"]), q), F(1))
            self.assertIsNone(score.grader_coverage(reply(na=["K1", "K2"]), q))

    def test_merge_coverage_rules(self):
        self.assertEqual(score.merge_coverage([F(1, 2), F(1, 3)]), F(1, 3))
        self.assertEqual(score.merge_coverage([None, F(1, 3)]), F(1, 3))
        self.assertEqual(score.merge_coverage([F(1, 2), None]), F(1, 2))
        self.assertIsNone(score.merge_coverage([None, None]))
        self.assertIsNone(score.merge_coverage([None]))
        self.assertEqual(score.merge_coverage([F(0)]), F(0))

    def test_zero_denominator_both_arms(self):
        """One grader undefined -> the other's; both undefined -> N/A, reported, never full coverage. Both arms."""
        for arm in ARMS:
            for case in ("one", "both", "single-grader"):
                with self.subTest(arm=arm, case=case):
                    scores = []
                    for q, a, r, _ in full_runs():
                        sid = score.slot_id(q, a, r)
                        conv = reply(q, covered=["K1"])
                        var = reply(q, covered=["K1", "K2"], configuration="v")
                        if (q, a, r) == ("QV", arm, 1):
                            if case == "one":
                                scores += [("G1", sid, var), ("G2", sid, conv)]
                            elif case == "both":
                                scores += [("G1", sid, var), ("G2", sid, var)]
                            else:
                                scores += [("G1", sid, var)]
                        else:
                            scores += [("G1", sid, conv), ("G2", sid, conv)]
                    result = memory(full_runs(), scores)
                    sid = score.slot_id("QV", arm, 1)
                    record = run_record(result, sid)
                    if case == "one":
                        self.assertEqual(record["coverage"], F(1, 2))
                    else:
                        self.assertIsNone(record["coverage"])
                        self.assertIn(sid, result["countsPerArm"]["arm%d" % arm]["coverageNA"])
                        # Left out of the coverage mean, not counted as 1: the other two runs are 1/2 each.
                        cov = next(x for x in result["exploratory"]["coverageQuestionLevel"]["rows"]
                                   if x["question"] == "QV")
                        self.assertEqual(cov["M%d" % arm], F(1, 2))
                    # Coverage N/A never touches the mechanism score of that run.
                    self.assertEqual(record["mechanism"], F(5))


class OtherMergesTest(unittest.TestCase):
    def test_errors_clarity_defects(self):
        q = key()["Q1"]
        merged = score.merge_output({"G1": reply(errors=1, clarity=5, major=2, minor=0),
                                     "G2": reply(errors=3, clarity=2, major=0, minor=3)}, q)
        self.assertEqual(merged["errors"], 3)
        self.assertEqual(merged["clarity"], 2)
        self.assertEqual(merged["defects"], {"major": 2, "minor": 3})

    def test_unsure_is_not_an_error(self):
        body = reply(errors=0)
        body["unsure"] = [{"text": "maybe"}]
        self.assertEqual(score.merge_output({"G1": body}, key()["Q1"])["errors"], 0)

    def test_one_grade_missing_uses_the_other(self):
        q = key()["Q1"]
        merged = score.merge_output({"G2": reply(checks=checks_with(2), errors=4, clarity=3, covered=["K1"])}, q)
        self.assertEqual((merged["mechanism"], merged["errors"], merged["clarity"], merged["coverage"]),
                         (F(2), 4, 3, F(1, 2)))


class FailedRunTest(unittest.TestCase):
    def test_failed_run_scores(self):
        for arm in ARMS:
            with self.subTest(arm=arm):
                status = {("Q1", arm, 3): "failed"}
                scores = []
                for q, a, r, s in full_runs(status):
                    if s == "failed":
                        continue
                    sid = score.slot_id(q, a, r)
                    # The largest merged error count of Q1 (4) is in the OTHER arm: E_fail uses either arm.
                    n = 4 if (q, a, r) == ("Q1", 3 - arm, 1) else 1
                    scores += [("G1", sid, reply(q, errors=n, covered=["K1", "K2"])), ("G2", sid, reply(q))]
                result = memory(full_runs(status), scores)
                record = run_record(result, score.slot_id("Q1", arm, 3))
                self.assertEqual(record["state"], "failed")
                self.assertEqual(record["mechanism"], F(0))
                self.assertEqual(record["clarity"], 0)
                self.assertEqual(record["coverage"], F(0))
                self.assertEqual(record["errors"], 5)
                self.assertIsNone(record["defects"])
                # The failure enters M(q, a) as 0: (5 + 5 + 0) / 3.
                self.assertEqual(row(result, "Q1")["M%d" % arm], F(10, 3))
                self.assertIn(record["id"], result["countsPerArm"]["arm%d" % arm]["failed"])
                # A failed run is never ungraded and never mechanism N/A.
                self.assertNotIn(record["id"], result["ungradedOutputs"] + result["mechanismNAOutputs"])

    def test_all_runs_of_an_arm_failed(self):
        status = {("Q1", 1, r): "failed" for r in (1, 2, 3)}
        scores = [(g, score.slot_id(q, a, r), reply(q)) for q, a, r, s in full_runs(status) if s == "rendered"
                  for g in ("G1", "G2")]
        result = memory(full_runs(status), scores)
        self.assertEqual(row(result, "Q1")["M1"], F(0))
        self.assertEqual(row(result, "Q1")["d"], F(-5))

    def test_efail_without_any_graded_output(self):
        status = {("Q1", a, r): "failed" for a in ARMS for r in (1, 2, 3)}
        scores = [(g, score.slot_id(q, a, r), reply(q)) for q, a, r, s in full_runs(status) if s == "rendered"
                  for g in ("G1", "G2")]
        result = memory(full_runs(status), scores)
        self.assertEqual(run_record(result, "Q1-r1-arm1")["errors"], score.DECISIONS["efailWithoutGradedOutput"])
        self.assertEqual(row(result, "Q1")["d"], F(0))
        with mock.patch.dict(score.DECISIONS, efailWithoutGradedOutput=None):
            result = memory(full_runs(status), scores)
            self.assertIsNone(run_record(result, "Q1-r1-arm1")["errors"])

    def test_efail_ignores_ungraded_outputs(self):
        status = {("Q1", 1, 1): "failed"}
        scores = [(g, score.slot_id(q, a, r), reply(q, errors=2)) for q, a, r, s in full_runs(status)
                  if s == "rendered" and (q, a, r) != ("Q1", 2, 2) for g in ("G1", "G2")]
        result = memory(full_runs(status), scores)
        self.assertEqual(run_record(result, "Q1-r1-arm1")["errors"], 3)


class UngradedTest(unittest.TestCase):
    def test_ungraded_is_listed_not_dropped_not_zero(self):
        for arm in ARMS:
            with self.subTest(arm=arm):
                missing = score.slot_id("Q1", arm, 2)
                scores = [(g, score.slot_id(q, a, r), reply(q)) for q, a, r, _ in full_runs()
                          if score.slot_id(q, a, r) != missing for g in ("G1", "G2")]
                result = memory(full_runs(), scores)
                record = run_record(result, missing)
                self.assertEqual(record["state"], "ungraded")
                self.assertNotIn("mechanism", record)
                self.assertIn(missing, result["ungradedOutputs"])
                self.assertEqual(result["countsPerArm"]["arm%d" % arm]["ungraded"], [missing])
                self.assertEqual(row(result, "Q1")["M%d" % arm], F(5))      # not (5 + 5 + 0) / 3
                self.assertEqual(len(result["runs"]), 12)                      # the run is still in the table

    def test_all_runs_ungraded_make_m_undefined(self):
        scores = [(g, score.slot_id(q, a, r), reply(q)) for q, a, r, _ in full_runs()
                  if (q, a) != ("QV", 2) for g in ("G1", "G2")]
        result = memory(full_runs(), scores)
        self.assertIsNone(row(result, "QV")["M2"])
        self.assertEqual(result["primary"]["leftOut"], ["QV"])

    def test_one_grade_missing_is_graded(self):
        scores = [(g, score.slot_id(q, a, r), reply(q)) for q, a, r, _ in full_runs() for g in ("G1", "G2")
                  if not (g == "G2" and (q, a, r) == ("Q1", 1, 1))]
        result = memory(full_runs(), scores)
        self.assertEqual(run_record(result, "Q1-r1-arm1")["graders"], ["G1"])
        self.assertEqual(result["countsPerArm"]["arm1"]["oneGradeMissing"], ["Q1-r1-arm1"])
        self.assertEqual(result["ungradedOutputs"], [])

    def test_ungraded_share_boundary(self):
        # 20 questions x 2 arms x 3 runs = 120 rendered outputs: 6 ungraded (5 %) keeps the verdict, 7 does not.
        k = key({"questions": [dict(key_question(i)) for i in range(20)]})
        runs = full_runs(questions=sorted(k))
        for n_ungraded, complete in ((6, True), (7, False)):
            with self.subTest(ungraded=n_ungraded):
                skip = {score.slot_id(q, a, r) for q, a, r, _ in runs[:n_ungraded]}
                scores = [(g, score.slot_id(q, a, r), reply(q)) for q, a, r, _ in runs
                          if score.slot_id(q, a, r) not in skip for g in ("G1", "G2")]
                result = memory(runs, scores, k=k)
                self.assertEqual(result["design"]["complete"], complete)
                self.assertEqual(result["design"]["ungradedShare"]["value"], F(n_ungraded, 120))
                if not complete:
                    self.assertIsNone(result["verdict"]["verdict"])


def key_question(i):
    return {"id": "Q%02d" % i, "category": "synthetic", "acceptedVariants": [],
            "keyFacts": [{"id": "K1", "core": True, "appliesTo": ["all"]}, {"id": "K2", "core": True, "appliesTo": ["all"]}],
            "mechanismChecks": [{"id": c} for c in CHECKS]}


class TiesTest(unittest.TestCase):
    def test_exact_tie_that_floats_would_break(self):
        # Arm 1 runs: 1, 10/3, 5/3; Arm 2 runs: 0, 1, 5. Both means are exactly 2, so d(q) = 0 (a tie). A plain
        # left-to-right float sum gives 2.0000000000000004 against 2.0 and would turn the tie into a "win".
        def float_mean(values):
            total = 0.0
            for v in values:
                total = total + v
            return total / len(values)
        self.assertNotEqual(float_mean([1.0, 10 / 3, 5 / 3]), float_mean([0.0, 1.0, 5.0]))
        plan = {("Q1", 1, 1): checks_with(1), ("Q1", 1, 2): checks_with(2, 3), ("Q1", 1, 3): checks_with(1, 3),
                ("Q1", 2, 1): checks_with(0), ("Q1", 2, 2): checks_with(1), ("Q1", 2, 3): checks_with(5)}
        scores = [(g, score.slot_id(q, a, r), reply(q, checks=plan.get((q, a, r)))) for q, a, r, _ in full_runs()
                  for g in ("G1", "G2")]
        result = memory(full_runs(), scores)
        self.assertEqual(row(result, "Q1")["M1"], F(2))
        self.assertEqual(row(result, "Q1")["d"], F(0))
        self.assertEqual(result["primary"]["signTest"]["ties"], 2)
        self.assertEqual(result["primary"]["signTest"]["n"], 0)

    def test_all_ties_p_is_one(self):
        test = score.sign_test([F(0)] * 20)
        self.assertEqual((test["n"], test["ties"], test["p"]), (0, 20, F(1)))
        self.assertEqual(score.test_result(test), "no conclusion")
        self.assertEqual(score.sign_test([])["p"], F(1))

    def test_ties_leave_the_test(self):
        test = score.sign_test([F(1)] * 6 + [F(0)] * 14)
        self.assertEqual((test["n"], test["positive"], test["p"]), (6, 6, F(2, 64)))
        self.assertEqual(score.test_result(test), "win")

    def test_balanced_p_is_capped_at_one(self):
        self.assertEqual(score.sign_test([F(1), F(-1)])["p"], F(1))
        self.assertEqual(score.sign_test([F(1)] * 10 + [F(-1)] * 10)["p"], F(1))


class SignTestBoundaryTest(unittest.TestCase):
    def test_fifteen_of_twenty(self):
        test = score.sign_test([F(1, 3)] * 15 + [F(-2)] * 5)
        self.assertEqual(test["p"], F(2 * (1 + 20 + 190 + 1140 + 4845 + 15504), 2 ** 20))
        self.assertAlmostEqual(float(test["p"]), 0.0414, places=4)
        self.assertEqual(score.test_result(test), "win")

    def test_fourteen_of_twenty(self):
        test = score.sign_test([F(1)] * 14 + [F(-1)] * 6)
        self.assertAlmostEqual(float(test["p"]), 0.1153, places=4)
        self.assertEqual(score.test_result(test), "no conclusion")

    def test_loss_mirror(self):
        self.assertEqual(score.test_result(score.sign_test([F(1)] * 5 + [F(-1)] * 15)), "loss")
        self.assertEqual(score.test_result(score.sign_test([F(1)] * 6 + [F(-1)] * 14)), "no conclusion")

    def test_small_n(self):
        self.assertEqual(score.sign_test([F(1)] * 5)["p"], F(2, 32))
        self.assertEqual(score.test_result(score.sign_test([F(1)] * 5)), "no conclusion")

    def test_p_exactly_alpha_is_not_significant(self):
        with mock.patch.object(score, "ALPHA", F(2, 64)):
            self.assertEqual(score.test_result(score.sign_test([F(1)] * 6)), "no conclusion")

    def test_opposite_signed_effect(self):
        k = key({"questions": [key_question(i) for i in range(20)]})
        runs = full_runs(questions=sorted(k))
        scores = []
        for i, q in enumerate(sorted(k)):
            for a in ARMS:
                for r in (1, 2, 3):
                    if i < 15:        # arm 1 a little better: 5 against 4
                        checks = checks_with(5 if a == 1 else 4)
                    else:             # arm 2 much better: 0 against 5
                        checks = checks_with(0 if a == 1 else 5)
                    scores += [(g, score.slot_id(q, a, r), reply(q, checks=checks)) for g in ("G1", "G2")]
        result = memory(runs, scores, k=k)
        self.assertEqual(result["primary"]["testResult"], "win")
        self.assertEqual(result["primary"]["meanD"], F(15 * 1 - 5 * 5, 20))
        self.assertTrue(result["primary"]["oppositeSignedEffect"])


class VerdictConditionTest(unittest.TestCase):
    def test_missing_slot_and_attestation(self):
        scores = [(g, score.slot_id(q, a, r), reply(q)) for q, a, r, _ in full_runs() for g in ("G1", "G2")]
        result = memory(full_runs(), scores)
        self.assertTrue(result["design"]["complete"])
        self.assertEqual(result["verdict"]["verdict"], "no conclusion")
        result = memory(full_runs(), scores, attest=False)
        self.assertIsNone(result["verdict"]["verdict"])
        result = memory(full_runs()[1:], scores[2:])
        self.assertEqual(result["design"]["missingSlots"], ["Q1-r1-arm1"])
        self.assertIsNone(result["verdict"]["verdict"])


class PreferenceTest(unittest.TestCase):
    def test_merge(self):
        self.assertEqual(score.merge_preference(["arm1", "arm1"]), "arm1")
        self.assertEqual(score.merge_preference(["tie", "arm2"]), "tie")
        self.assertEqual(score.merge_preference(["arm1", "arm2"]), "tie")
        self.assertEqual(score.merge_preference(["arm2"]), "arm2")
        self.assertIsNone(score.merge_preference([]))

    def test_pairs_sides_automatic_and_unjudged(self):
        status = {("Q1", 2, 2): "failed", ("QV", 1, 3): "failed", ("QV", 2, 3): "failed"}
        runs = full_runs(status)
        scores = [(g, score.slot_id(q, a, r), reply(q)) for q, a, r, s in runs if s == "rendered" for g in ("G1", "G2")]
        sides = {"Q1-r1": 1, "Q1-r3": 2, "QV-r1": 2, "QV-r2": 1}
        prefs = [("G1", "Q1-r1", preference("Q1", "t", "A")), ("G2", "Q1-r1", preference("Q1", "t", "A")),
                 ("G1", "Q1-r3", preference("Q1", "t", "A")), ("G2", "Q1-r3", preference("Q1", "t", "tie")),
                 ("G1", "QV-r1", preference("QV", "t", "A"))]
        result = memory(runs, scores, prefs, sides)
        pairs = {p["pair"]: p for p in result["exploratory"]["preference"]["pairs"]}
        self.assertEqual(pairs["Q1-r1"], {"pair": "Q1-r1", "kind": "graded", "result": "arm1"})
        self.assertEqual(pairs["Q1-r2"], {"pair": "Q1-r2", "kind": "automatic", "result": "arm1"})
        self.assertEqual(pairs["Q1-r3"]["result"], "tie")
        self.assertEqual(pairs["QV-r1"]["result"], "arm2")             # A is arm 2 in this pair
        self.assertEqual(pairs["QV-r2"], {"pair": "QV-r2", "kind": "unjudged", "result": None})
        self.assertEqual(pairs["QV-r3"], {"pair": "QV-r3", "kind": "automatic", "result": "tie"})
        pref = result["exploratory"]["preference"]
        self.assertEqual(pref["unjudged"], ["QV-r2"])
        self.assertEqual(pref["arm1WinRateGraded"], {"numerator": 1, "denominator": 2, "value": F(1, 2), "ties": 1})
        self.assertEqual(pref["arm1WinRateWithAutomatic"]["value"], F(2, 3))

    def test_win_rate_zero_denominator_is_undefined(self):
        runs = full_runs()
        scores = [(g, score.slot_id(q, a, r), reply(q)) for q, a, r, _ in runs for g in ("G1", "G2")]
        prefs = [("G1", "Q1-r1", preference("Q1", "t", "tie"))]
        result = memory(runs, scores, prefs, {"Q1-r1": 1})
        rate = result["exploratory"]["preference"]["arm1WinRateGraded"]
        self.assertEqual((rate["numerator"], rate["denominator"], rate["value"], rate["ties"]), (0, 0, None, 1))


class InputTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.key = key()

    def test_invalid_stored_reply_is_missing_and_listed(self):
        bad = reply()
        bad["mechanism"]["M1"] = "CANNOT JUDGE"           # only M3 and M4 may be CANNOT JUDGE
        folder = write_input(self.tmp.name, [("Q1", 1, 1, "rendered")],
                             {("G1", "Q1-r1-arm1"): "not json", ("G2", "Q1-r1-arm1"): bad})
        runs, sides, scores, prefs, invalid = score.load_input(folder, self.key)
        self.assertEqual(scores, {"G1": {}, "G2": {}})
        self.assertEqual([(i["grader"], i["id"]) for i in invalid], [("G1", "Q1-r1-arm1"), ("G2", "Q1-r1-arm1")])
        result = score.analyse(runs, sides, scores, prefs, invalid, self.key)
        self.assertEqual(result["ungradedOutputs"], ["Q1-r1-arm1"])

    def test_grade_for_failed_run_is_refused(self):
        folder = write_input(self.tmp.name, [("Q1", 1, 1, "failed")], {("G1", "Q1-r1-arm1"): reply()})
        with self.assertRaises(score.InputError):
            score.load_input(folder, self.key)

    def test_grade_for_unknown_slot_and_duplicate_slot_are_refused(self):
        folder = write_input(self.tmp.name, [("Q1", 1, 1, "rendered")], {("G1", "Q1-r2-arm1"): reply()})
        with self.assertRaises(score.InputError):
            score.load_input(folder, self.key)
        folder = write_input(self.tmp.name + "/b", [("Q1", 1, 1, "rendered"), ("Q1", 1, 1, "failed")])
        with self.assertRaises(score.InputError):
            score.load_input(folder, self.key)

    def test_bad_status_is_refused(self):
        folder = write_input(self.tmp.name, [("Q1", 1, 1, "void")])
        with self.assertRaises(score.InputError):
            score.load_input(folder, self.key)

    def test_validation(self):
        q = self.key["Q1"]
        self.assertEqual(score.validate_score_reply(reply(), q), [])
        for mutate in (lambda r: r.pop("clarity"), lambda r: r.update(clarity=6), lambda r: r.update(clarity=True),
                       lambda r: r.update(clarity=4.0), lambda r: r.update(question="QV"),
                       lambda r: r["mechanism"].update(M2="MAYBE"), lambda r: r["mechanism"].pop("M5"),
                       lambda r: r.update(errors=[{"type": "X"}]), lambda r: r.update(defects=[{"type": "D1"}])):
            body = reply()
            mutate(body)
            self.assertNotEqual(score.validate_score_reply(body, q), [])
        self.assertNotEqual(score.validate_score_reply([], q), [])
        self.assertEqual(score.validate_preference_reply(preference("Q1", "t", "tie"), "Q1"), [])
        self.assertNotEqual(score.validate_preference_reply(preference("Q1", "t", "C"), "Q1"), [])

    def test_warnings_do_not_change_grades(self):
        q = self.key["QV"]
        body = reply("QV", covered=["K1", "K9"], na=["K1"], configuration="other")
        warnings = score.score_reply_warnings(body, q)
        self.assertEqual(len(warnings), 4)         # unknown configuration, unknown fact, both lists, N/A list
        self.assertEqual(score.grader_coverage(body, q), F(1, 2))
        na = reply("Q1", checks=dict(ALL_PASS, M5="N/A"))
        self.assertEqual(len(score.score_reply_warnings(na, self.key["Q1"])), 1)
        self.assertEqual(score.mechanism_score({c: score.merge_check([na["mechanism"][c]]) for c in CHECKS}), F(5))


class BootstrapTest(unittest.TestCase):
    def test_without_numpy(self):
        with mock.patch.dict(sys.modules, {"numpy": None}):
            out = score.bootstrap_interval([F(1), F(2)])
        self.assertEqual(out["status"], "not computed: NumPy is not installed")
        self.assertEqual(score.bootstrap_interval([])["status"], "undefined: no values")

    def test_with_numpy(self):
        try:
            import numpy as np
        except ImportError:
            self.skipTest("NumPy is not installed")
        values = [F(i - 7, 3) for i in range(20)]
        out = score.bootstrap_interval(values)
        rng = np.random.default_rng(20261111)
        data = np.array([float(v) for v in values])
        means = data[rng.integers(0, 20, size=(10000, 20))].mean(axis=1)
        self.assertEqual((out["low"], out["high"]), tuple(float(x) for x in np.percentile(means, [2.5, 97.5])))
        self.assertEqual(score.bootstrap_interval([F(2)] * 5)["low"], 2.0)


if __name__ == "__main__":
    unittest.main()
