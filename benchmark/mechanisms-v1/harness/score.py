# SPDX-License-Identifier: Apache-2.0
"""Primary scoring and grade merge for mechanisms-v1 (PROTOCOL.md sections 6, 10, 11 and 12).

This is the code that section 11 requires to be reviewed and hash-pinned in RUN-LOCK.json before run 1. It reads
the final run table and the stored grader replies (after unblinding), merges the two primary graders exactly as
section 10 says, scores failed and graded runs as section 11 says, and computes M(q, a), d(q), the exact two-sided
sign test and the verdict of section 12.

All scores are exact fractions (fractions.Fraction), so a tie d(q) = 0 is never lost to floating-point rounding.
Python standard library only. The effect-size bootstrap uses NumPy `default_rng(20261111)` because section 11 names
it; when NumPy is not installed, the interval is reported as not computed and nothing else changes.

Where the protocol text leaves a choice open, the code does not choose silently: every such point is a key of
DECISIONS below and an entry in OPEN-QUESTIONS.md. The values are provisional until the review settles them.

Input folder (see harness/README.md):
  runs.csv                                   question,arm,run,status   (status: rendered or failed)
  pair-sides.csv                             pair,A                    (the arm shown as A: 1 or 2; preferences only)
  grades/<G1|G2>/score/<question>-r<r>-arm<a>.json        the stored final score reply of that grader
  grades/<G1|G2>/preference/<question>-r<r>.json          the stored final preference reply of that grader

Usage (from benchmark/mechanisms-v1):
  python3 harness/score.py INPUT_DIR [--questions QUESTIONS.json] [--out RESULT.json] [--attest-within-21-days]
"""

import argparse
import csv
from fractions import Fraction
import json
from math import comb
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
import agreement  # noqa: E402  (the sibling module; harness/ is not a package)

HERE = Path(__file__).resolve().parent
BENCH = HERE.parent

GRADERS = ("G1", "G2")
ARMS = (1, 2)
RUNS_PER_ARM = 3                                   # section 6: 3 runs per question per arm (primary generator)
CHECKS = ("M1", "M2", "M3", "M4", "M5")
CANNOT_JUDGE_CHECKS = ("M3", "M4")                 # RUBRIC.md: CANNOT JUDGE only for M3 and M4
JUDGED = ("PASS", "FAIL", "NOT SHOWN")             # section 10: the judgments that were made
RESULTS = JUDGED + ("N/A", "CANNOT JUDGE")
ERROR_TYPES = ("K", "N", "L", "O")
DEFECT_TYPES = ("D1", "D2", "D3", "D4", "D5", "D6")
SEVERITIES = ("major", "minor")
PREFERENCES = ("A", "B", "tie")
ALPHA = Fraction(5, 100)                           # section 11: alpha = 0.05
UNGRADED_LIMIT = Fraction(5, 100)                  # section 11: more than 5 % ungraded -> descriptive only
NEAR_SHIPPED = ("MECH-01", "MECH-03", "MECH-08", "MECH-17", "MECH-18")   # section 11 sensitivity analysis
BOOTSTRAP_RESAMPLES = 10000
BOOTSTRAP_SEED = 20261111
MAX_SCORE = 5

# Merged check states. Section 10 needs only PASS against not PASS among judged checks; which of FAIL and NOT SHOWN
# is "stricter" never changes a score, so a judged non-PASS merge is NOT_PASS (OPEN-QUESTIONS.md, OQ-08).
PASS, NOT_PASS, UNJUDGED, NA = "PASS", "NOT PASS", "UNJUDGED", "N/A"

# Provisional answers to the open questions (OPEN-QUESTIONS.md). Each is used in exactly one place, named below.
DECISIONS = {
    # OQ-01: which core facts are "applicable" for one grader's coverage fraction.
    #   "configuration": core facts whose appliesTo holds "all" or the configuration that grader identified
    #   "grader-list":   core facts minus the ones that grader listed in notApplicableFacts
    "applicableCoreFacts": "configuration",
    # OQ-02: E_fail(q) when question q has no graded output in either arm.
    #   1: the largest merged error count over no output is taken as 0;  None: E_fail(q) and those errors undefined
    "efailWithoutGradedOutput": 1,
    # OQ-03: a stored reply that is not valid JSON in the rubric's form counts as a missing grade (section 6), and is
    #   listed under invalidGrades. The alternative is to stop the analysis.
    "invalidStoredReply": "missing",
}


class InputError(ValueError):
    """The input folder is not a consistent run table and grade set."""


# --------------------------------------------------------------------------------------------------- the key

def load_key(path):
    doc = json.loads(Path(path).read_text(encoding="utf-8"))
    key = {}
    for q in doc["questions"]:
        key[q["id"]] = {
            "id": q["id"],
            "category": q.get("category"),
            "variants": [v["id"] for v in q.get("acceptedVariants", [])],
            "facts": {f["id"]: {"core": bool(f["core"]), "appliesTo": list(f["appliesTo"])} for f in q["keyFacts"]},
            "checks": [m["id"] for m in q["mechanismChecks"]],
        }
    return key


def resolve_configuration(name, q):
    """RUBRIC.md: 'unclear' and a configuration that is neither conventional nor an accepted variant use conventional."""
    if isinstance(name, str) and name in q["variants"]:
        return name
    return "conventional"


def applies(fact, configuration):
    return "all" in fact["appliesTo"] or configuration in fact["appliesTo"]


# ---------------------------------------------------------------------------------------- reply validation

def validate_score_reply(reply, q):
    """Problems that make a stored score reply not 'valid JSON in the rubric's form' (an empty list: valid)."""
    if not isinstance(reply, dict):
        return ["the reply is not a JSON object"]
    problems = []
    for name, kind in (("question", str), ("output", str), ("configuration", str), ("mechanism", dict),
                       ("errors", list), ("unsure", list), ("coveredFacts", list), ("notApplicableFacts", list),
                       ("clarity", int), ("clarityReason", str), ("defects", list)):
        if name not in reply:
            problems.append("missing key " + name)
        elif not isinstance(reply[name], kind) or (kind is int and isinstance(reply[name], bool)):
            problems.append("%s is not a %s" % (name, kind.__name__))
    if problems:
        return problems
    if reply["question"] != q["id"]:
        problems.append("question is %r, expected %r" % (reply["question"], q["id"]))
    for check in CHECKS:
        value = reply["mechanism"].get(check)
        if value not in RESULTS:
            problems.append("%s is %r" % (check, value))
        elif value == "CANNOT JUDGE" and check not in CANNOT_JUDGE_CHECKS:
            problems.append("%s cannot be CANNOT JUDGE" % check)
    for item in reply["errors"]:
        if not isinstance(item, dict) or item.get("type") not in ERROR_TYPES:
            problems.append("an error entry has no type K, N, L or O")
    for item in reply["defects"]:
        if not isinstance(item, dict) or item.get("type") not in DEFECT_TYPES or item.get("severity") not in SEVERITIES:
            problems.append("a defect entry has no type D1-D6 or no severity major/minor")
    for name in ("coveredFacts", "notApplicableFacts"):
        if not all(isinstance(x, str) for x in reply[name]):
            problems.append(name + " holds a non-string")
    if not 1 <= reply["clarity"] <= 5:
        problems.append("clarity %r is not 1 to 5" % reply["clarity"])
    return problems


def score_reply_warnings(reply, q):
    """Content oddities that do not make a reply invalid; reported, never used to change a grade."""
    warnings = []
    config = reply["configuration"]
    if config not in ["conventional", "unclear"] + q["variants"]:
        warnings.append("configuration %r is not in the key; graded as conventional" % config)
    for name in ("coveredFacts", "notApplicableFacts"):
        unknown = sorted(set(reply[name]) - set(q["facts"]))
        if unknown:
            warnings.append("%s names facts not in the key: %s" % (name, ", ".join(unknown)))
    both = sorted(set(reply["coveredFacts"]) & set(reply["notApplicableFacts"]))
    if both:
        warnings.append("facts both covered and N/A: " + ", ".join(both))
    resolved = resolve_configuration(config, q)
    na_checks = [c for c in CHECKS if reply["mechanism"][c] == "N/A"]
    if na_checks and resolved == "conventional":
        warnings.append("N/A checks %s with the conventional configuration (OPEN-QUESTIONS OQ-04)" % ", ".join(na_checks))
    keyed_na = {f for f, fact in q["facts"].items() if fact["core"] and not applies(fact, resolved)}
    listed_na = {f for f in reply["notApplicableFacts"] if f in q["facts"] and q["facts"][f]["core"]}
    if keyed_na != listed_na:
        warnings.append("core facts N/A by configuration %s differ from notApplicableFacts" % sorted(keyed_na ^ listed_na))
    return warnings


def validate_preference_reply(reply, qid):
    if not isinstance(reply, dict):
        return ["the reply is not a JSON object"]
    problems = []
    for name in ("question", "pair", "preference", "preferenceReason"):
        if not isinstance(reply.get(name), str):
            problems.append("missing or non-string key " + name)
    if not problems:
        if reply["question"] != qid:
            problems.append("question is %r, expected %r" % (reply["question"], qid))
        if reply["preference"] not in PREFERENCES:
            problems.append("preference %r is not A, B or tie" % reply["preference"])
    return problems


# ------------------------------------------------------------------------------- section 10: the merge rules

def merge_check(values):
    """One check M1-M5. `values`: the present graders' results (a missing grade leaves the other)."""
    if not values:
        raise ValueError("merge_check needs at least one grade")
    judged = [v for v in values if v in JUDGED]
    if judged:
        # Both judged: PASS only if both PASS. One judged, the other CANNOT JUDGE or N/A: the judgment.
        return PASS if all(v == "PASS" for v in judged) else NOT_PASS
    if all(v == "N/A" for v in values):
        return NA                                  # both N/A (or the only grade is N/A): N/A
    return UNJUDGED                                # neither judged


def mechanism_score(merged_checks):
    """(a) 5 x merged PASS / judged checks; None (N/A) when no check is judged. Never counted as a pass."""
    passes = sum(1 for v in merged_checks.values() if v == PASS)
    judged = sum(1 for v in merged_checks.values() if v in (PASS, NOT_PASS))
    if judged == 0:
        return None
    return Fraction(MAX_SCORE * passes, judged)


def grader_coverage(reply, q):
    """One grader's covered applicable core facts / applicable core facts; None when no core fact applies."""
    if DECISIONS["applicableCoreFacts"] == "configuration":
        configuration = resolve_configuration(reply["configuration"], q)
        applicable = {f for f, fact in q["facts"].items() if fact["core"] and applies(fact, configuration)}
    elif DECISIONS["applicableCoreFacts"] == "grader-list":
        applicable = {f for f, fact in q["facts"].items() if fact["core"]} - set(reply["notApplicableFacts"])
    else:
        raise ValueError("unknown applicableCoreFacts decision")
    if not applicable:
        return None
    return Fraction(len(applicable & set(reply["coveredFacts"])), len(applicable))


def merge_coverage(fractions):
    """(b) The smaller defined fraction; one undefined -> the other; both undefined -> None (N/A)."""
    defined = [f for f in fractions if f is not None]
    return min(defined) if defined else None


def merge_errors(replies):
    return max(len(r["errors"]) for r in replies)              # (b) the larger count


def merge_clarity(replies):
    return min(r["clarity"] for r in replies)                  # (c) the lower score


def merge_defects(replies):
    """(d) The larger count, for major and for minor apart."""
    return {s: max(sum(1 for d in r["defects"] if d["severity"] == s) for r in replies) for s in SEVERITIES}


def merge_preference(values):
    """(e) values: present graders' answers in arm terms ('arm1', 'arm2', 'tie'). None if both are missing."""
    if not values:
        return None                                            # unjudged
    if len(set(values)) == 1:
        return values[0]                                       # same answer (or the only answer)
    return "tie"                                               # one tie and one side, or arm 1 against arm 2


def merge_output(replies, q):
    """Merge the present graders' valid score replies of one rendered output (dict grader -> reply)."""
    present = [replies[g] for g in GRADERS if g in replies]
    if not present:
        raise ValueError("an ungraded output has no merge")
    checks = {c: merge_check([r["mechanism"][c] for r in present]) for c in CHECKS}
    return {
        "checks": checks,
        "mechanism": mechanism_score(checks),
        "errors": merge_errors(present),
        "coverage": merge_coverage([grader_coverage(r, q) for r in present]),
        "clarity": merge_clarity(present),
        "defects": merge_defects(present),
    }


# ----------------------------------------------------------------------------------------------- statistics

def sign_test(ds):
    """Exact two-sided sign test over the d(q) that are not 0 (binomial, p = 0.5). All ties (or none): p = 1."""
    pos = sum(1 for d in ds if d > 0)
    neg = sum(1 for d in ds if d < 0)
    n = pos + neg
    if n == 0:
        return {"n": 0, "positive": 0, "negative": 0, "ties": len(ds), "p": Fraction(1)}
    tail = sum(comb(n, i) for i in range(min(pos, neg) + 1))
    p = min(Fraction(1), Fraction(2 * tail, 2 ** n))
    return {"n": n, "positive": pos, "negative": neg, "ties": len(ds) - n, "p": p}


def test_result(test):
    """Section 12 from the primary test alone (the completed-design condition is applied separately)."""
    if test["p"] < ALPHA and test["positive"] > test["negative"]:
        return "win"
    if test["p"] < ALPHA and test["negative"] > test["positive"]:
        return "loss"
    return "no conclusion"


def mean(values):
    values = list(values)
    return sum(values, Fraction(0)) / len(values) if values else None


def bootstrap_interval(values):
    """95 % percentile bootstrap of the mean (resample with replacement, 10 000, NumPy default_rng(20261111))."""
    if not values:
        return {"status": "undefined: no values", "low": None, "high": None}
    try:
        import numpy as np
    except ImportError:
        return {"status": "not computed: NumPy is not installed", "low": None, "high": None}
    data = np.array([float(v) for v in values])
    rng = np.random.default_rng(BOOTSTRAP_SEED)
    idx = rng.integers(0, len(data), size=(BOOTSTRAP_RESAMPLES, len(data)))
    low, high = np.percentile(data[idx].mean(axis=1), [2.5, 97.5])
    return {"status": "computed", "numpy": np.__version__, "low": float(low), "high": float(high),
            "method": "rng.integers(0, n, size=(10000, n)); np.percentile(means, [2.5, 97.5]) (OPEN-QUESTIONS OQ-05)"}


def rate(numerator, denominator):
    """A summary with a zero denominator is undefined, reported with its counts (section 11)."""
    out = {"numerator": numerator, "denominator": denominator}
    out["value"] = Fraction(numerator, denominator) if denominator else None
    return out


# -------------------------------------------------------------------------------------------- input loading

def slot_id(question, arm, run):
    return "%s-r%d-arm%d" % (question, run, arm)


def pair_id(question, run):
    return "%s-r%d" % (question, run)


def read_runs(path, key):
    runs = {}
    with open(path, newline="", encoding="utf-8") as stream:
        for row in csv.DictReader(stream):
            try:
                question, arm, run, status = row["question"], int(row["arm"]), int(row["run"]), row["status"]
            except (KeyError, TypeError, ValueError):
                raise InputError("runs.csv needs the columns question,arm,run,status with integer arm and run")
            if question not in key:
                raise InputError("runs.csv names an unknown question " + question)
            if arm not in ARMS or not 1 <= run <= RUNS_PER_ARM:
                raise InputError("runs.csv has arm %r run %r" % (arm, run))
            if status not in ("rendered", "failed"):
                raise InputError("runs.csv status must be rendered or failed, not %r" % status)
            sid = slot_id(question, arm, run)
            if sid in runs:
                raise InputError("runs.csv lists %s twice" % sid)
            runs[sid] = {"id": sid, "question": question, "arm": arm, "run": run, "status": status}
    return runs


def read_reply(path):
    try:
        return json.loads(Path(path).read_text(encoding="utf-8")), None
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        return None, "not valid JSON: %s" % error


def load_input(folder, key):
    folder = Path(folder)
    runs = read_runs(folder / "runs.csv", key)
    sides = {}
    sides_path = folder / "pair-sides.csv"
    if sides_path.exists():
        with open(sides_path, newline="", encoding="utf-8") as stream:
            for row in csv.DictReader(stream):
                if row.get("A") not in ("1", "2"):
                    raise InputError("pair-sides.csv: A must be 1 or 2 for " + str(row.get("pair")))
                sides[row["pair"]] = int(row["A"])
    scores = {g: {} for g in GRADERS}
    preferences = {g: {} for g in GRADERS}
    invalid = []
    for grader in GRADERS:
        for path in sorted((folder / "grades" / grader / "score").glob("*.json")):
            sid = path.stem
            if sid not in runs:
                raise InputError("a score grade for %s, which is not in runs.csv" % sid)
            if runs[sid]["status"] != "rendered":
                raise InputError("a score grade for the failed run %s (failed runs get no score call)" % sid)
            reply, problem = read_reply(path)
            problems = [problem] if problem else validate_score_reply(reply, key[runs[sid]["question"]])
            if problems:
                if DECISIONS["invalidStoredReply"] != "missing":
                    raise InputError("invalid score reply %s %s: %s" % (grader, sid, "; ".join(problems)))
                invalid.append({"grader": grader, "kind": "score", "id": sid, "problems": problems})
                continue
            scores[grader][sid] = reply
        for path in sorted((folder / "grades" / grader / "preference").glob("*.json")):
            pid = path.stem
            q, _, r = pid.rpartition("-r")
            ids = [slot_id(q, a, int(r)) if r.isdigit() else None for a in ARMS]
            if not all(i in runs and runs[i]["status"] == "rendered" for i in ids):
                raise InputError("a preference grade for %s, which is not a pair of two rendered runs" % pid)
            if pid not in sides:
                raise InputError("pair-sides.csv has no side for " + pid)
            reply, problem = read_reply(path)
            problems = [problem] if problem else validate_preference_reply(reply, q)
            if problems:
                if DECISIONS["invalidStoredReply"] != "missing":
                    raise InputError("invalid preference reply %s %s: %s" % (grader, pid, "; ".join(problems)))
                invalid.append({"grader": grader, "kind": "preference", "id": pid, "problems": problems})
                continue
            preferences[grader][pid] = reply
    return runs, sides, scores, preferences, invalid


# ------------------------------------------------------------------------------------------------- analysis

def score_runs(runs, scores, key, graders=GRADERS):
    """Section 11 run scores. Returns the per-run records (every slot in runs, ordered by id)."""
    records = {}
    for sid in sorted(runs):
        run = runs[sid]
        q = key[run["question"]]
        record = dict(run)
        if run["status"] == "failed":
            record.update(state="failed", graders=[])
        else:
            replies = {g: scores[g][sid] for g in graders if sid in scores[g]}
            record["graders"] = sorted(replies)
            if not replies:
                record["state"] = "ungraded"          # never dropped, never scored 0
            else:
                record["state"] = "graded"
                record.update(merge_output(replies, q))
                record["perGrader"] = {g: {"configuration": r["configuration"],
                                           "resolvedConfiguration": resolve_configuration(r["configuration"], q),
                                           "checks": dict((c, r["mechanism"][c]) for c in CHECKS),
                                           "coverage": grader_coverage(r, q),
                                           "errors": len(r["errors"]),
                                           "clarity": r["clarity"],
                                           "defects": {s: sum(1 for d in r["defects"] if d["severity"] == s)
                                                       for s in SEVERITIES},
                                           "warnings": score_reply_warnings(r, q)}
                                       for g, r in replies.items()}
        records[sid] = record
    # E_fail(q) = 1 + the largest merged error count of any graded output of q in either arm.
    for question in key:
        graded = [r["errors"] for r in records.values() if r["question"] == question and r["state"] == "graded"]
        if graded:
            efail = 1 + max(graded)
        else:
            efail = DECISIONS["efailWithoutGradedOutput"]
        for r in records.values():
            if r["question"] == question and r["state"] == "failed":
                r.update(checks=None, mechanism=Fraction(0), clarity=0, coverage=Fraction(0), errors=efail,
                         defects=None)                # defects are not defined for a failed run
    return records


def counted(record, field):
    """The value that enters a mean of `field`, or None: ungraded outputs and N/A values are left out."""
    if record["state"] == "ungraded":
        return None
    return record[field]


def question_level(records, key, field, questions=None):
    """M(q, a) means over failed and graded runs with a defined value, d(q) = M(q, 1) - M(q, 2), and the test."""
    rows = []
    for question in (questions if questions is not None else sorted(key)):
        means = {}
        for arm in ARMS:
            values = [counted(r, field) for r in records.values() if r["question"] == question and r["arm"] == arm]
            means[arm] = mean(v for v in values if v is not None)
        d = means[1] - means[2] if means[1] is not None and means[2] is not None else None
        rows.append({"question": question, "M1": means[1], "M2": means[2], "d": d})
    defined = [row["d"] for row in rows if row["d"] is not None]
    test = sign_test(defined)
    effect = mean(defined)
    out = {"rows": rows, "definedQuestions": len(defined),
           "leftOut": [row["question"] for row in rows if row["d"] is None],
           "signTest": test, "testResult": test_result(test),
           "meanD": effect, "interval": bootstrap_interval(defined)}
    majority = (test["positive"] > test["negative"]) - (test["positive"] < test["negative"])
    sign = (effect > 0) - (effect < 0) if effect is not None else 0
    out["oppositeSignedEffect"] = bool(majority and sign and majority != sign)
    return out


def design_status(runs, records, key, attest_21_days):
    """Section 11 'Stopping rule and incomplete data': the registered verdict needs the completed design."""
    expected = {slot_id(q, a, r) for q in key for a in ARMS for r in range(1, RUNS_PER_ARM + 1)}
    missing = sorted(expected - set(runs))
    rendered = [r for r in records.values() if r["status"] == "rendered"]
    ungraded = [r["id"] for r in rendered if r["state"] == "ungraded"]
    share = rate(len(ungraded), len(rendered))
    reasons = []
    if missing:
        reasons.append("%d run slots are not generated" % len(missing))
    if share["value"] is not None and share["value"] > UNGRADED_LIMIT:
        reasons.append("more than 5 %% of the rendered outputs are ungraded (%d of %d)" % (len(ungraded), len(rendered)))
    if not attest_21_days:
        reasons.append("the operator has not attested that the design completed within 21 days after run 1")
    return {"missingSlots": missing, "ungradedShare": share, "complete": not reasons, "reasons": reasons}


def preference_analysis(runs, sides, preferences, graders=GRADERS):
    pairs = []
    questions = sorted({r["question"] for r in runs.values()})
    for question in questions:
        for run in range(1, RUNS_PER_ARM + 1):
            pid = pair_id(question, run)
            slots = [runs.get(slot_id(question, a, run)) for a in ARMS]
            if None in slots:
                pairs.append({"pair": pid, "kind": "incomplete", "result": None})
                continue
            rendered = [s["status"] == "rendered" for s in slots]
            if rendered == [True, True]:
                answers = []
                for g in graders:
                    if pid in preferences[g]:
                        p = preferences[g][pid]["preference"]
                        answers.append("tie" if p == "tie" else
                                       "arm%d" % (sides[pid] if p == "A" else 3 - sides[pid]))
                result = merge_preference(answers)
                pairs.append({"pair": pid, "kind": "graded" if result else "unjudged", "result": result})
            elif rendered == [False, False]:
                pairs.append({"pair": pid, "kind": "automatic", "result": "tie"})
            else:
                pairs.append({"pair": pid, "kind": "automatic", "result": "arm1" if rendered[0] else "arm2"})

    def win_rate(kinds):
        chosen = [p["result"] for p in pairs if p["kind"] in kinds]
        wins, losses = chosen.count("arm1"), chosen.count("arm2")
        out = rate(wins, wins + losses)
        out["ties"] = chosen.count("tie")
        return out
    return {"pairs": pairs,
            "unjudged": [p["pair"] for p in pairs if p["kind"] == "unjudged"],
            "arm1WinRateGraded": win_rate(("graded",)),
            "arm1WinRateWithAutomatic": win_rate(("graded", "automatic"))}


def counts_per_arm(records):
    out = {}
    for arm in ARMS:
        mine = [r for r in records.values() if r["arm"] == arm]
        graded = [r for r in mine if r["state"] == "graded"]
        per_check = {}
        for c in CHECKS:
            per_check[c] = {
                "merged": {s: sum(1 for r in graded if r["checks"][c] == s) for s in (PASS, NOT_PASS, UNJUDGED, NA)},
                "cannotJudge": {g: sum(1 for r in graded if r["perGrader"].get(g, {}).get("checks", {}).get(c)
                                       == "CANNOT JUDGE") for g in GRADERS},
                "notApplicable": {g: sum(1 for r in graded if r["perGrader"].get(g, {}).get("checks", {}).get(c)
                                         == "N/A") for g in GRADERS},
            }
        configurations = {}
        for g in GRADERS:
            names = [r["perGrader"][g]["resolvedConfiguration"] for r in graded if g in r["perGrader"]]
            configurations[g] = {n: names.count(n) for n in sorted(set(names))}
        both = [r for r in graded if all(g in r["perGrader"] for g in GRADERS)]
        same = sum(1 for r in both if len({r["perGrader"][g]["resolvedConfiguration"] for g in GRADERS}) == 1)
        out["arm%d" % arm] = {
            "runs": len(mine),
            "rendered": sum(1 for r in mine if r["status"] == "rendered"),
            "failed": [r["id"] for r in mine if r["state"] == "failed"],
            "ungraded": [r["id"] for r in mine if r["state"] == "ungraded"],
            "oneGradeMissing": [r["id"] for r in graded if len(r["graders"]) == 1],
            "mechanismNA": [r["id"] for r in graded if r["mechanism"] is None],
            "coverageNA": [r["id"] for r in graded if r["coverage"] is None],
            "successRate": rate(sum(1 for r in mine if r["status"] == "rendered"), len(mine)),
            "checks": per_check,
            "configurations": configurations,
            "configurationAgreement": rate(same, len(both)),
        }
    return out


def per_arm_means(records):
    """Pooled descriptive means per arm (exploratory; failed runs enter with their section 11 scores)."""
    out = {}
    for arm in ARMS:
        mine = [r for r in records.values() if r["arm"] == arm]
        row = {}
        for field in ("mechanism", "errors", "coverage", "clarity"):
            values = [counted(r, field) for r in mine]
            values = [v for v in values if v is not None]
            row[field] = {"mean": mean(values), "n": len(values)}
        graded = [r for r in mine if r["state"] == "graded"]
        for s in SEVERITIES:
            values = [r["defects"][s] for r in graded]
            row["defects_" + s] = {"mean": mean(values), "n": len(values)}
        out["arm%d" % arm] = row
    return out


def agreement_analysis(records, preferences):
    """Section 10 agreement statistics (G1 against G2, on the outputs and pairs that both graded). Exploratory."""
    both = [r for r in records.values() if r["state"] == "graded" and all(g in r["perGrader"] for g in GRADERS)]
    g1, g2 = GRADERS

    def alone_score(r, g):
        return mechanism_score({c: merge_check([r["perGrader"][g]["checks"][c]]) for c in CHECKS})

    def numeric(get):
        x = [get(r, g1) for r in both]
        y = [get(r, g2) for r in both]
        return {"items": len(both),
                "pairable": sum(1 for a, b in zip(x, y) if a is not None and b is not None),
                "krippendorffAlphaInterval": agreement.krippendorff_alpha(list(zip(x, y)), "interval"),
                "spearmanRho": agreement.spearman_rho(x, y)}

    out = {"note": "exploratory; 95 % bootstrap intervals not computed (OPEN-QUESTIONS OQ-06)",
           "outputsBothGraded": len(both),
           "mechanismScore": numeric(alone_score),
           "errors": numeric(lambda r, g: r["perGrader"][g]["errors"]),
           "coverage": numeric(lambda r, g: r["perGrader"][g]["coverage"]),
           "defectsMajor": numeric(lambda r, g: r["perGrader"][g]["defects"]["major"]),
           "defectsMinor": numeric(lambda r, g: r["perGrader"][g]["defects"]["minor"])}
    out["clarity"] = {"items": len(both), "cohenKappaQuadratic": agreement.cohen_kappa(
        [r["perGrader"][g1]["clarity"] for r in both], [r["perGrader"][g2]["clarity"] for r in both],
        [1, 2, 3, 4, 5], weights="quadratic")}
    checks = {}
    pooled_x, pooled_y, pooled_one, pooled_all = [], [], 0, 0
    for c in CHECKS:
        values = [(r["perGrader"][g1]["checks"][c], r["perGrader"][g2]["checks"][c]) for r in both]
        judged = [(a == "PASS", b == "PASS") for a, b in values if a in JUDGED and b in JUDGED]
        one = sum(1 for a, b in values if (a in JUDGED) != (b in JUDGED))
        x, y = [a for a, _ in judged], [b for _, b in judged]
        checks[c] = {"bothJudged": len(judged), "percentAgreement": agreement.percent_agreement(x, y),
                     "cohenKappa": agreement.cohen_kappa(x, y, [True, False]),
                     "oneJudgedOtherNot": rate(one, len(values))}
        pooled_x += x
        pooled_y += y
        pooled_one += one
        pooled_all += len(values)
    checks["pooled"] = {"bothJudged": len(pooled_x), "percentAgreement": agreement.percent_agreement(pooled_x, pooled_y),
                        "cohenKappa": agreement.cohen_kappa(pooled_x, pooled_y, [True, False]),
                        "oneJudgedOtherNot": rate(pooled_one, pooled_all)}
    out["checks"] = checks
    pairs = sorted(set(preferences[g1]) & set(preferences[g2]))
    out["preference"] = {"pairsBothGraded": len(pairs), "cohenKappa": agreement.cohen_kappa(
        [preferences[g1][p]["preference"] for p in pairs], [preferences[g2][p]["preference"] for p in pairs],
        list(PREFERENCES))}
    return out


def analyse(runs, sides, scores, preferences, invalid, key, attest_21_days=False):
    records = score_runs(runs, scores, key)
    primary = question_level(records, key, "mechanism")
    design = design_status(runs, records, key, attest_21_days)
    if design["complete"]:
        verdict = {"verdict": primary["testResult"], "status": "registered verdict (completed design)"}
    else:
        verdict = {"verdict": None, "status": "descriptive results only: " + "; ".join(design["reasons"]),
                   "primaryTestWouldBe": primary["testResult"]}
    kept = [q for q in sorted(key) if q not in NEAR_SHIPPED]
    single = {}
    for g in GRADERS:
        alone = score_runs(runs, scores, key, graders=(g,))
        single[g] = question_level(alone, key, "mechanism")
    return {
        "kind": "mechanisms-v1.score/1",
        "decisions": dict(DECISIONS),
        "verdict": verdict,
        "design": design,
        "primary": primary,
        "sensitivityWithoutNearShipped": dict(question_level(records, key, "mechanism", kept),
                                              note="descriptive; does not change the verdict"),
        "ungradedOutputs": [r["id"] for r in records.values() if r["state"] == "ungraded"],
        "mechanismNAOutputs": [r["id"] for r in records.values() if r["state"] == "graded" and r["mechanism"] is None],
        "invalidGrades": invalid,
        "countsPerArm": counts_per_arm(records),
        "exploratory": {
            "note": "exploratory and unadjusted; never a route to a win, a loss or a claim of superiority",
            "perArmMeans": per_arm_means(records),
            "errorsQuestionLevel": question_level(records, key, "errors"),
            "clarityQuestionLevel": question_level(records, key, "clarity"),
            "coverageQuestionLevel": question_level(records, key, "coverage"),
            "preference": preference_analysis(runs, sides, preferences),
            "primaryPerGraderAlone": single,
            "agreement": agreement_analysis(records, preferences),
        },
        "runs": [records[s] for s in sorted(records)],
    }


# --------------------------------------------------------------------------------------------------- output

def to_json(value):
    """Fractions become {"exact": "p/q", "float": x}; everything else is plain JSON."""
    if isinstance(value, Fraction):
        return {"exact": str(value), "float": float(value)}
    if isinstance(value, dict):
        return {k: to_json(v) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [to_json(v) for v in value]
    return value


def summary(result):
    p = result["primary"]
    t = p["signTest"]
    lines = [
        "verdict: %s (%s)" % (result["verdict"]["verdict"], result["verdict"]["status"]),
        "primary test: %s; %d questions with defined d(q): %d positive, %d negative, %d ties; p = %s (%.4f)"
        % (p["testResult"], p["definedQuestions"], t["positive"], t["negative"], t["ties"], t["p"], float(t["p"])),
        "mean d(q): %s; interval: %s" % (None if p["meanD"] is None else "%.4f" % p["meanD"], p["interval"]["status"]),
        "ungraded outputs: %d; mechanism N/A outputs: %d; invalid stored replies: %d"
        % (len(result["ungradedOutputs"]), len(result["mechanismNAOutputs"]), len(result["invalidGrades"])),
    ]
    if p["oppositeSignedEffect"]:
        lines.insert(1, "opposite-signed effect: the mean of d(q) has the opposite sign of the sign-test majority")
    return "\n".join(lines)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("input", type=Path, help="input folder (runs.csv, pair-sides.csv, grades/)")
    parser.add_argument("--questions", type=Path, default=BENCH / "QUESTIONS.json")
    parser.add_argument("--out", type=Path, help="write the full result JSON here")
    parser.add_argument("--attest-within-21-days", action="store_true",
                        help="the operator attests that the design completed within 21 days after run 1")
    args = parser.parse_args(argv)
    key = load_key(args.questions)
    try:
        loaded = load_input(args.input, key)
    except InputError as error:
        print("input error:", error, file=sys.stderr)
        return 2
    result = analyse(*loaded, key, attest_21_days=args.attest_within_21_days)
    if args.out:
        args.out.write_text(json.dumps(to_json(result), indent=2) + "\n", encoding="utf-8")
    print(summary(result))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
