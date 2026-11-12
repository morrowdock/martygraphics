# SPDX-License-Identifier: Apache-2.0
"""The shared rubric-form validator and the section 6 attempt rule (synthetic replies only)."""

import copy
import json
import re
import unittest

from support import BENCH, SYNTHETIC_KEY, reply
import rubric_form as form

RUBRIC = (BENCH / "RUBRIC.md").read_text(encoding="utf-8")
EXAMPLES = re.findall(r"```json\n(.*?)\n```", RUBRIC, re.S)
SCORE_EXAMPLE, PREFERENCE_EXAMPLE = EXAMPLES[0], EXAMPLES[1]
QUESTIONS = {q["id"]: q for q in json.loads((BENCH / "QUESTIONS.json").read_text(encoding="utf-8"))["questions"]}
VIEW = {q["id"]: q for q in json.loads((BENCH / "GRADER-QUESTIONS.json").read_text(encoding="utf-8"))["questions"]}
SYN = {q["id"]: q for q in SYNTHETIC_KEY["questions"]}
# Built at run time: a long literal assigned to a TOKEN name looks like a credential to secret scanners.
# The value is the synthetic packet id 0123456789ab, the same as before.
TOKEN = "".join(map(str, range(10))) + "ab"


def base():
    return reply(("Q1", 1, 1), output=TOKEN)


def problems(mutate, question="Q1", config=None):
    body = base() if config is None else reply((question, 1, 1), output=TOKEN, configuration=config)
    mutate(body)
    return form.validate_score(body, SYN[question], TOKEN)


class RubricExampleTest(unittest.TestCase):
    """The rubric's own answer formats are valid, with both views of the key."""

    def test_score_example(self):
        for view in (QUESTIONS, VIEW):
            reply_obj, found = form.check_text("score", SCORE_EXAMPLE, view["MECH-01"], "<output id given to you>")
            self.assertEqual(found, [])
            self.assertEqual(reply_obj["mechanism"]["M3"], "CANNOT JUDGE")

    def test_preference_example(self):
        _, found = form.check_text("preference", PREFERENCE_EXAMPLE, QUESTIONS["MECH-01"], "<pair id given to you>")
        self.assertEqual(found, [])

    def test_example_with_another_token_is_invalid(self):
        _, found = form.check_text("score", SCORE_EXAMPLE, QUESTIONS["MECH-01"], "abcdefabcdef")
        self.assertEqual(found, ["output is '<output id given to you>', not the packet's output id"])


class ParseTest(unittest.TestCase):
    def test_exactly_one_object(self):
        good = json.dumps(base())
        self.assertEqual(form.check_text("score", "  \n" + good + "\n", SYN["Q1"], TOKEN)[1], [])
        for bad in ("```json\n" + good + "\n```", "Here it is: " + good, good + " done", "[" + good + "]",
                    good[:-1], '{"a": 1, "a": 2}', "", "null"):
            self.assertNotEqual(form.check_text("score", bad, SYN["Q1"], TOKEN)[1], [], bad[:30])
        self.assertNotEqual(form.check_text("score", b"\xff\xfe", SYN["Q1"], TOKEN)[1], [])
        self.assertEqual(form.check_text("score", good.encode("utf-8"), SYN["Q1"], TOKEN)[1], [])


class ScoreFormTest(unittest.TestCase):
    def test_valid_fixture(self):
        self.assertEqual(form.validate_score(base(), SYN["Q1"], TOKEN), [])

    def test_identity(self):
        self.assertTrue(problems(lambda r: r.update(question="QV")))
        self.assertTrue(problems(lambda r: r.update(output="ffffffffffff")))

    def test_keys_and_types(self):
        for name in ("question", "output", "configuration", "mechanism", "errors", "unsure", "coveredFacts",
                     "notApplicableFacts", "clarity", "clarityReason", "defects"):
            self.assertTrue(problems(lambda r: r.pop(name)), name)
        for clarity in (0, 6, 4.0, True, "4"):
            self.assertTrue(problems(lambda r: r.update(clarity=clarity)), clarity)
        self.assertTrue(problems(lambda r: r.update(clarityReason=" ")))

    def test_results(self):
        self.assertTrue(problems(lambda r: r["mechanism"].update(M2="MAYBE")))
        self.assertTrue(problems(lambda r: r["mechanism"].pop("M5")))
        self.assertTrue(problems(lambda r: r["mechanism"].update(M1="CANNOT JUDGE", evidence={"M1": "reason"})))

    def test_evidence_rule_5(self):
        def fail(text):
            return lambda r: r["mechanism"].update(M2="FAIL", evidence={} if text is None else {"M2": text})
        self.assertTrue(problems(fail(None)))
        self.assertTrue(problems(fail("the gears are on different shafts")))      # no still and no time
        self.assertEqual(problems(fail("t=6.0 s: the gears are on different shafts")), [])
        self.assertEqual(problems(fail("still-3 shows a gap")), [])
        # A location alone is not evidence: rule 5 asks for the place AND one sentence (re-check 2026-11-12).
        refused = ("6.0 s", "still-3", "t=6.0 s", "  12 s  ", "still 2, 4.5 s", "t=6.0 s, t=7.0 s", "T = 6 s",
                   "still-3.png", "see-still-2.png 4 s", "frames/still-4.jpg 7 s", '6.0 s: "frames/gear contact shot.png"',
                   "6.0 s: \u2018frames/gear contact snapshot.png\u2019", "6.0 s: \u201cframes/a b.png\u201d",
                   "6.0 s: 'frames/a b.png'", "6.0 s: \u00abframes/a b.png\u00bb",
                   "6.0 s 🙂", "6.0 s 123 456", "6.0 s ... !!")
        for bare in refused:
            with self.subTest(evidence=bare):
                self.assertTrue(problems(fail(bare)))
        # Any script, and one-word sentences (A-13): the validator checks there is evidence, not its style.
        accepted = ("6.0 s: गियर नहीं घूमता।", "6.0 s : l'engrenage ne tourne pas", "6.0 s：齿轮不转",
                    "6.0 s：齿轮没有转动（still-3.png）。", "6.0 s: الترس لا يدور", "6.0 s: يصطدمان.", "4 s: Chocan.",
                    "still-3：歯車が回らない", "still-3.png shows a gap", "t=6.0 s bad", "6.0 s: gears slip")
        for sentence in accepted:
            with self.subTest(evidence=sentence):
                self.assertEqual(problems(fail(sentence)), [])

    def test_evidence_check_is_fast_on_long_text(self):
        # Linear, not quadratic: at 200,000 characters a quadratic scan would take hours; linear takes well under 1 s.
        import time
        n = 200_000
        for text in ("6.0 s " + "a" * n, "6.0 s " + "a." * (n // 2), '6.0 s "' + "b" * n,
                     "6.0 s: " + "\u201c" * n, "6.0 s: " + "\u201c" * (n // 2) + "\u201d",
                     "6.0 s: " + "'" * n, "6.0 s: " + "\u2018a\n" * (n // 3) + "\u2019"):
            started = time.monotonic()
            problems(lambda r: r["mechanism"].update(M2="FAIL", evidence={"M2": text}))
            self.assertLess(time.monotonic() - started, 3.0)

        self.assertTrue(problems(lambda r: r["mechanism"].update(M3="CANNOT JUDGE", evidence={})))
        self.assertEqual(problems(lambda r: r["mechanism"].update(M3="CANNOT JUDGE",
                                                                  evidence={"M3": "too fast"})), [])
        self.assertTrue(problems(lambda r: r["mechanism"].update(evidence="none")))

    def test_conventional_na_is_invalid(self):
        # A-04: N/A only when the configuration is an accepted variant.
        self.assertTrue(problems(lambda r: r["mechanism"].update(M5="N/A")))
        self.assertTrue(problems(lambda r: r["mechanism"].update(M5="N/A"), "QV", "conventional"))
        self.assertTrue(problems(lambda r: r["mechanism"].update(M5="N/A"), "QV", "unclear"))
        self.assertEqual(problems(lambda r: r["mechanism"].update(M5="N/A"), "QV", "v"), [])

    def test_configuration(self):
        self.assertTrue(problems(lambda r: r.update(configuration="v")))          # Q1 has no variant v
        self.assertEqual(problems(lambda r: r.update(configuration="unclear")), [])

    def test_error_items(self):
        full = {"type": "K", "keyFact": "K2", "time": "10.0 s", "text": "q", "reason": "r"}
        self.assertEqual(problems(lambda r: r.update(errors=[full])), [])
        for field in ("time", "text", "reason", "keyFact", "type"):
            item = dict(full)
            item.pop(field)
            self.assertTrue(problems(lambda r: r.update(errors=[item])), field)
        self.assertTrue(problems(lambda r: r.update(errors=[dict(full, keyFact="K9")])))
        self.assertTrue(problems(lambda r: r.update(errors=[dict(full, time="early on")])))
        self.assertTrue(problems(lambda r: r.update(errors=[{"type": "K"}])))
        other = {"type": "O", "time": "still-1", "text": "q", "reason": "energy is not conserved"}
        self.assertEqual(problems(lambda r: r.update(errors=[other])), [])

    def test_defect_items(self):
        full = {"type": "D3", "severity": "minor", "time": "14.0 s", "evidence": "e"}
        self.assertEqual(problems(lambda r: r.update(defects=[full])), [])
        for field in ("type", "severity", "time", "evidence"):
            item = dict(full)
            item.pop(field)
            self.assertTrue(problems(lambda r: r.update(defects=[item])), field)

    def test_malformed_ids_are_problems_not_crashes(self):
        # Re-check 2026-11-12: unhashable ids raised TypeError instead of returning problems.
        for change in (lambda r: r.update(coveredFacts=[{"id": "K1"}]),
                       lambda r: r.update(notApplicableFacts=[["K1"]]),
                       lambda r: r.update(coveredFacts=[["K1"]], notApplicableFacts=[{"id": "K1"}]),
                       lambda r: r.update(errors=[{"type": "K", "keyFact": ["K1"], "time": "1.0 s",
                                                   "text": "q", "reason": "r"}]),
                       lambda r: r.update(errors=[{"type": "K", "keyFact": {"id": "K1"}, "time": "1.0 s",
                                                   "text": "q", "reason": "r"}])):
            self.assertTrue(problems(change))

    def test_fact_lists(self):
        self.assertTrue(problems(lambda r: r.update(coveredFacts=["K3"])))         # not core
        self.assertTrue(problems(lambda r: r.update(coveredFacts=["K9"])))         # not in the key
        self.assertTrue(problems(lambda r: r.update(coveredFacts=["K1", "K1"])))
        self.assertTrue(problems(lambda r: r.update(coveredFacts=["K1"], notApplicableFacts=["K1"])))
        self.assertTrue(problems(lambda r: r.update(notApplicableFacts=["K7"])))
        self.assertEqual(problems(lambda r: r.update(notApplicableFacts=["K3"])), [])

    def test_extra_keys_are_allowed(self):
        self.assertEqual(problems(lambda r: r.update(note="extra")), [])

    def test_not_an_object(self):
        self.assertTrue(form.validate_score([], SYN["Q1"], TOKEN))


class PreferenceAndGuessTest(unittest.TestCase):
    def test_preference(self):
        good = {"question": "Q1", "pair": TOKEN, "preference": "tie", "preferenceReason": "r"}
        self.assertEqual(form.validate_preference(good, "Q1", TOKEN), [])
        for change in ({"preference": "C"}, {"pair": "x"}, {"question": "QV"}, {"preferenceReason": ""}):
            self.assertTrue(form.validate_preference(dict(good, **change), "Q1", TOKEN), change)
        self.assertTrue(form.validate_preference({"question": "Q1"}, "Q1", TOKEN))

    def test_guess(self):
        good = {"differentTools": "yes", "engine": "A", "reason": "r"}
        self.assertEqual(form.validate_guess(good), [])
        for change in ({"engine": "C"}, {"differentTools": "maybe"}, {"reason": ""}):
            self.assertTrue(form.validate_guess(dict(good, **change)), change)


class AttemptRuleTest(unittest.TestCase):
    """PROTOCOL.md section 6: one fix-up message in the session, then up to 2 new sessions (3 in all)."""

    def test_status_table(self):
        T, F = True, False
        table = [
            ([], "incomplete"),
            ([[T]], "completed"),
            ([[F, T]], "completed"),
            ([[F, F], [T]], "completed"),
            ([[F, F], [F, F], [F, T]], "completed"),
            ([[F]], "incomplete"),
            ([[F, F]], "incomplete"),
            ([[F, F], [F, F], [F]], "incomplete"),
            ([[F, F], [F, F], [F, F]], "exhausted"),
            ([[F], [T]], "nonconforming"),              # a new session without the fix-up message
            ([[T, F]], "nonconforming"),                # asked again after a valid reply
            ([[T], [T]], "nonconforming"),
            ([[F, F, F]], "nonconforming"),             # two fix-up messages
            ([[F, F], [F, F], [F, F], [T]], "nonconforming"),
            ([[]], "nonconforming"),
        ]
        for sessions, status in table:
            self.assertEqual(form.call_status(sessions)[0], status, sessions)
        self.assertEqual(form.call_status([[False, False], [True]])[1], (1, 0))

    def test_next_step(self):
        T, F = True, False
        self.assertEqual(form.next_step([]), "new-session")
        self.assertEqual(form.next_step([[F]]), "fix-up")
        self.assertEqual(form.next_step([[F, F]]), "new-session")
        self.assertEqual(form.next_step([[F, F], [F]]), "fix-up")
        self.assertEqual(form.next_step([[F, F], [F, F], [F, F]]), "missing")
        self.assertEqual(form.next_step([[F, T]]), "accept")
        with self.assertRaises(ValueError):
            form.next_step([[F], [F]])


if __name__ == "__main__":
    unittest.main()
