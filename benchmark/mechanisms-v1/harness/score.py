# SPDX-License-Identifier: Apache-2.0
"""Primary scoring, grade merge and the analysis plan of mechanisms-v1 (PROTOCOL.md sections 6, 8, 10, 11 and 12).

This is the code that section 11 requires to be reviewed and hash-pinned in RUN-LOCK.json before run 1. It reads
the final run table, the dated grading record with every attempt's exact reply, and the published blinding seed and
mapping. It checks every reply with the one shared validator (rubric_form.py), merges the two primary graders as
section 10 says, scores failed and graded runs as section 11 says, computes M(q, a), d(q), the exact sign test and
the section 12 verdict, and every analysis of sections 10 and 11. The choices that the protocol text left open are
decided in AMENDMENTS.md; each is marked here with its amendment id.

Exact fractions for every score and mean (a tie d(q) = 0 is never lost to rounding). The intervals need NumPy at
the version that RUN-LOCK.json pins (section 11 names `default_rng(20261111)`); without it the report is refused.

Usage (from benchmark/mechanisms-v1):  python3 harness/score.py INPUT_DIR --out RESULT.json
The input folder is described in harness/README.md.
"""

import argparse
import csv
from datetime import datetime, timedelta
from decimal import Decimal, InvalidOperation
from fractions import Fraction
import json
from math import comb
from pathlib import Path
import platform
import random
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
import agreement  # noqa: E402  (sibling modules; harness/ is not a package)
import blinding  # noqa: E402
import rubric_form as form  # noqa: E402

HERE = Path(__file__).resolve().parent
BENCH = HERE.parent

GRADERS = ("G1", "G2")
ARMS = (1, 2)
RUNS_PER_ARM = 3                          # section 6
MAX_TRIES = 4                             # sections 4 and 5: at most 3 repairs
CHECKS = form.CHECKS
JUDGED = form.JUDGED
SEVERITIES = form.SEVERITIES
ALPHA = Fraction(5, 100)                  # section 11
UNGRADED_LIMIT = Fraction(5, 100)         # section 11: "more than 5 %" -> descriptive only
DESIGN_DAYS = 21                          # section 11
RUN_LIMIT = timedelta(minutes=60)         # sections 4 and 5: a run past 60 min is a failure
RUN_ORDER_SEED = 20261111                 # section 6
NEAR_SHIPPED = ("MECH-01", "MECH-03", "MECH-08", "MECH-17", "MECH-18")
BOOTSTRAP_RESAMPLES = 10000
BOOTSTRAP_SEED = 20261111
MAX_SCORE = 5

# Merged check states (A-08: a judged non-PASS merge is NOT PASS; the raw judgments are kept per grader).
PASS, NOT_PASS, UNJUDGED, NA = "PASS", "NOT PASS", "UNJUDGED", "N/A"


class InputError(ValueError):
    """The input folder is not a consistent, verifiable run table, record and grade set."""


# ------------------------------------------------------------------------------------------- NumPy (pinned)

def pinned_numpy_version():
    return json.loads((BENCH / "RUN-LOCK.json").read_text(encoding="utf-8"))["harness"]["numpy"]


def require_numpy():
    """The report needs NumPy at the pinned version (A-05). Never a silent missing interval."""
    try:
        import numpy
    except ImportError:
        raise InputError("NumPy %s is required (RUN-LOCK.json harness.numpy); it is not installed"
                         % pinned_numpy_version())
    if numpy.__version__ != pinned_numpy_version():
        raise InputError("NumPy %s is required (RUN-LOCK.json harness.numpy); this is %s"
                         % (pinned_numpy_version(), numpy.__version__))
    return numpy


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
            "raw": q,
        }
    return key


def resolve_configuration(name, q):
    """RUBRIC.md: 'unclear' grades against the conventional configuration."""
    return name if name in q["variants"] else "conventional"


def applies(fact, configuration):
    return "all" in fact["appliesTo"] or configuration in fact["appliesTo"]


# ------------------------------------------------------------------------------- section 10: the merge rules

def merge_check(values):
    """One check. `values`: the present graders' results (a missing grade leaves the other)."""
    if not values:
        raise ValueError("merge_check needs at least one grade")
    judged = [v for v in values if v in JUDGED]
    if judged:
        return PASS if all(v == "PASS" for v in judged) else NOT_PASS
    if all(v == "N/A" for v in values):
        return NA
    return UNJUDGED


def mechanism_score(merged_checks):
    """(a) 5 x merged PASS / judged checks; None (N/A) when no check is judged."""
    passes = sum(1 for v in merged_checks.values() if v == PASS)
    judged = sum(1 for v in merged_checks.values() if v in (PASS, NOT_PASS))
    return Fraction(MAX_SCORE * passes, judged) if judged else None


def applicable_core_facts(reply, q):
    """A-01: the core facts whose appliesTo holds 'all' or the configuration the grader names."""
    configuration = resolve_configuration(reply["configuration"], q)
    return {f for f, fact in q["facts"].items() if fact["core"] and applies(fact, configuration)}


def grader_coverage(reply, q):
    """One grader's covered applicable core facts / applicable core facts; None when no core fact applies."""
    applicable = applicable_core_facts(reply, q)
    if not applicable:
        return None
    return Fraction(len(applicable & set(reply["coveredFacts"])), len(applicable))


def coverage_warnings(reply, q):
    """Every covered fact that the fraction ignores, and a grader N/A list that differs from the configuration."""
    applicable = applicable_core_facts(reply, q)
    configuration = resolve_configuration(reply["configuration"], q)
    out = ["coveredFacts %s is not applicable to configuration %s and is ignored" % (f, configuration)
           for f in reply["coveredFacts"] if f not in applicable]
    keyed = {f for f, fact in q["facts"].items() if fact["core"] and not applies(fact, configuration)}
    listed = {f for f in reply["notApplicableFacts"] if q["facts"][f]["core"]}
    if keyed != listed:
        out.append("core facts N/A by configuration %s are %s; notApplicableFacts lists %s"
                   % (configuration, sorted(keyed), sorted(listed)))
    return out


def merge_coverage(fractions):
    defined = [f for f in fractions if f is not None]
    return min(defined) if defined else None


def merge_output(replies, q):
    """Merge the present graders' valid score replies of one rendered output (dict grader -> reply)."""
    present = [replies[g] for g in GRADERS if g in replies]
    if not present:
        raise ValueError("an ungraded output has no merge")
    checks = {c: merge_check([r["mechanism"][c] for r in present]) for c in CHECKS}
    return {
        "checks": checks,
        "mechanism": mechanism_score(checks),
        "errors": max(len(r["errors"]) for r in present),
        "coverage": merge_coverage([grader_coverage(r, q) for r in present]),
        "clarity": min(r["clarity"] for r in present),
        "defects": {s: max(sum(1 for d in r["defects"] if d["severity"] == s) for r in present) for s in SEVERITIES},
    }


def merge_preference(values):
    """(e) Present graders' answers in arm terms ('arm1', 'arm2', 'tie'); None if both are missing (unjudged)."""
    if not values:
        return None
    return values[0] if len(set(values)) == 1 else "tie"


# ----------------------------------------------------------------------------------------------- statistics

def binomial_two_sided(k, n):
    """Exact two-sided binomial test with p = 0.5 (k successes of n); None when n = 0."""
    if n == 0:
        return None
    tail = sum(comb(n, i) for i in range(min(k, n - k) + 1))
    return min(Fraction(1), Fraction(2 * tail, 2 ** n))


def sign_test(ds):
    """Exact two-sided sign test over the d(q) that are not 0. All ties, or no defined d(q): p = 1 (A-12)."""
    pos = sum(1 for d in ds if d > 0)
    neg = sum(1 for d in ds if d < 0)
    p = binomial_two_sided(pos, pos + neg)
    return {"definedQuestions": len(ds), "n": pos + neg, "positive": pos, "negative": neg, "ties": len(ds) - pos - neg,
            "p": Fraction(1) if p is None else p,
            "emptySample": "no defined d(q)" if not ds else ("every defined d(q) is 0" if pos + neg == 0 else None)}


def test_result(test):
    if test["p"] < ALPHA and test["positive"] > test["negative"]:
        return "win"
    if test["p"] < ALPHA and test["negative"] > test["positive"]:
        return "loss"
    return "no conclusion"


def mean(values):
    values = list(values)
    return sum(values, Fraction(0)) / len(values) if values else None


def rate(numerator, denominator):
    """A summary with a zero denominator is undefined, with its counts (section 11)."""
    return {"numerator": numerator, "denominator": denominator,
            "value": Fraction(numerator, denominator) if denominator else None}


def _interval(np, stats, method):
    stats = np.asarray(stats, dtype=float)
    defined = stats[~np.isnan(stats)]
    out = {"resamples": BOOTSTRAP_RESAMPLES, "undefinedResamples": int(stats.size - defined.size), "method": method}
    if defined.size == 0:
        out.update(low=None, high=None)
    else:
        low, high = np.percentile(defined, [2.5, 97.5])
        out.update(low=float(low), high=float(high))
    return out


def bootstrap_mean(values):
    """A-05: the section 11 interval of a question-level mean (rng.integers draw, np.percentile linear)."""
    np = require_numpy()
    if not values:
        return {"resamples": 0, "undefinedResamples": 0, "low": None, "high": None, "method": "no values"}
    data = np.array([float(v) for v in values])
    rng = np.random.default_rng(BOOTSTRAP_SEED)
    idx = rng.integers(0, len(data), size=(BOOTSTRAP_RESAMPLES, len(data)))
    return _interval(np, data[idx].mean(axis=1), "resample the values with replacement; mean")


def resample_weights(n):
    """(10000, n) counts of each item in each resample, from a fresh default_rng(20261111) (A-05, A-06)."""
    np = require_numpy()
    idx = np.random.default_rng(BOOTSTRAP_SEED).integers(0, n, size=(BOOTSTRAP_RESAMPLES, n))
    weights = np.zeros((BOOTSTRAP_RESAMPLES, n))
    np.add.at(weights, (np.arange(BOOTSTRAP_RESAMPLES)[:, None], idx), 1)
    return weights


def bootstrap_ratio(numerators, denominators):
    """Interval of sum(numerators) / sum(denominators), resampling the items (questions) with replacement."""
    np = require_numpy()
    if not numerators:
        return {"resamples": 0, "undefinedResamples": 0, "low": None, "high": None, "method": "no items"}
    weights = resample_weights(len(numerators))
    num = weights @ np.array([float(x) for x in numerators])
    den = weights @ np.array([float(x) for x in denominators])
    with np.errstate(divide="ignore", invalid="ignore"):
        stats = np.where(den > 0, num / np.where(den > 0, den, 1), np.nan)
    return _interval(np, stats, "resample the questions with replacement; pooled ratio")


# ---------------------------------------------------------------------------------------------- input files

def slot_id(question, arm, run):
    return "%s-r%d-arm%d" % (question, run, arm)


def pair_id(question, run):
    return "%s-r%d" % (question, run)


def parse_time(value, where):
    try:
        moment = datetime.fromisoformat(value)
    except (TypeError, ValueError):
        raise InputError("%s: %r is not an ISO 8601 time" % (where, value))
    if moment.tzinfo is None:
        raise InputError("%s: %r has no time zone (use Z)" % (where, value))
    return moment


def read_csv(path, columns):
    if not path.exists():
        raise InputError("%s is missing" % path.name)
    with open(path, newline="", encoding="utf-8") as stream:
        reader = csv.DictReader(stream)
        if reader.fieldnames != columns:
            raise InputError("%s must have exactly the columns %s" % (path.name, ",".join(columns)))
        return list(reader)


def read_runs(path, key):
    runs = {}
    columns = ["question", "arm", "run", "status", "startedUTC", "endedUTC", "tries", "costUsd"]
    for row in read_csv(path, columns):
        try:
            question, arm, run, status = row["question"], int(row["arm"]), int(row["run"]), row["status"]
            tries = int(row["tries"])
            cost = Decimal(row["costUsd"])
        except (TypeError, ValueError, InvalidOperation):
            raise InputError("runs.csv: arm, run and tries must be integers and costUsd a decimal number")
        if question not in key or arm not in ARMS or not 1 <= run <= RUNS_PER_ARM:
            raise InputError("runs.csv names an unknown slot %s arm %r run %r" % (question, arm, run))
        if status not in ("rendered", "failed"):
            raise InputError("runs.csv status must be rendered or failed, not %r" % status)
        if not 1 <= tries <= MAX_TRIES or not cost.is_finite() or cost < 0:
            raise InputError("runs.csv: tries must be 1 to 4 and costUsd a number >= 0")
        sid = slot_id(question, arm, run)
        if sid in runs:
            raise InputError("runs.csv lists %s twice" % sid)
        started, ended = parse_time(row["startedUTC"], sid), parse_time(row["endedUTC"], sid)
        runs[sid] = {"id": sid, "question": question, "arm": arm, "run": run, "status": status,
                     "started": started, "ended": ended, "tries": tries, "costUsd": Fraction(cost),
                     "wallSeconds": Fraction((ended - started) // timedelta(microseconds=1), 10 ** 6)}
    return runs


def both_rendered(runs, question, run):
    slots = [runs.get(slot_id(question, a, run)) for a in ARMS]
    return all(s is not None and s["status"] == "rendered" for s in slots)


def read_blinding(folder, runs):
    """The seed, its commitment, and the published mapping, each checked against the others (A-09)."""
    try:
        seed = blinding.parse_seed((folder / "BLINDING-SEED.txt").read_text(encoding="ascii"))
        committed = (folder / "BLINDING-COMMITMENT.txt").read_text(encoding="ascii").strip()
    except FileNotFoundError as error:
        raise InputError("%s is missing" % Path(error.filename).name)
    except (UnicodeDecodeError, ValueError) as error:
        raise InputError("BLINDING-SEED.txt: %s" % error)
    if blinding.commitment(seed) != committed:
        raise InputError("BLINDING-COMMITMENT.txt does not match the seed")
    tokens = {}
    for row in read_csv(folder / "output-tokens.csv", ["output", "token"]):
        if row["output"] in tokens:
            raise InputError("output-tokens.csv lists %s twice" % row["output"])
        tokens[row["output"]] = row["token"]
    sides = {}
    for row in read_csv(folder / "pair-sides.csv", ["pair", "token", "A"]):
        if row["pair"] in sides:
            raise InputError("pair-sides.csv lists %s twice" % row["pair"])
        sides[row["pair"]] = (row["token"], row["A"])
    expected_tokens, expected_sides = {}, {}
    for run in runs.values():
        if run["status"] == "rendered":
            expected_tokens[run["id"]] = blinding.output_token(seed, run["question"], run["run"], run["arm"])
        pid = pair_id(run["question"], run["run"])
        if both_rendered(runs, run["question"], run["run"]):
            expected_sides[pid] = (blinding.pair_token(seed, run["question"], run["run"]),
                                   str(blinding.arm_shown_as_a(seed, run["question"], run["run"])))
    if tokens != expected_tokens:
        raise InputError("output-tokens.csv is not the mapping of the seed for the rendered outputs")
    if sides != expected_sides:
        raise InputError("pair-sides.csv is not the mapping of the seed for the pairs with two rendered outputs")
    return seed, {sid: t for sid, t in tokens.items()}, {pid: (t, int(a)) for pid, (t, a) in sides.items()}


def read_record(folder, runs, key, tokens, sides):
    """The dated completion and call record (A-07) and every recorded reply, checked with rubric_form."""
    path = folder / "RECORD.json"
    if not path.exists():
        raise InputError("RECORD.json (the dated completion and call record) is missing")
    record = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(record, dict) or record.get("kind") != "mechanisms-v1.record/1":
        raise InputError("RECORD.json is not a mechanisms-v1.record/1")
    for name in ("withdrawnModels", "humanGraders", "calls"):
        if not isinstance(record.get(name), list):
            raise InputError("RECORD.json needs the list %s" % name)
    commitment_time = parse_time(record.get("commitmentPushedUTC"), "RECORD.json commitmentPushedUTC")
    calls = {}
    grades = {kind: {g: {} for g in GRADERS} for kind in ("score", "preference", "guess")}
    invalid, timing = [], []
    reply_times = []
    for call in record["calls"]:
        grader, kind, cid = call.get("grader"), call.get("kind"), call.get("id")
        if grader not in GRADERS or kind not in grades:
            raise InputError("RECORD.json: unknown grader or kind in %r" % ((grader, kind, cid),))
        if (grader, kind, cid) in calls:
            raise InputError("RECORD.json lists the call %s %s %s twice" % (grader, kind, cid))
        if kind == "score":
            if cid not in tokens:
                raise InputError("RECORD.json: a score call for %s, which is not a rendered output" % cid)
            question, token = key[runs[cid]["question"]]["raw"], tokens[cid]
        else:
            if cid not in sides:
                raise InputError("RECORD.json: a %s call for %s, which is not a pair of two rendered outputs"
                                 % (kind, cid))
            question, token = key[cid.rpartition("-r")[0]]["raw"], sides[cid][0]
        sessions, validity, texts, previous = call.get("sessions"), [], [], None
        if not isinstance(sessions, list):
            raise InputError("RECORD.json: call %s %s %s has no sessions list" % (grader, kind, cid))
        for s, session in enumerate(sessions, 1):
            started = parse_time(session.get("startedUTC"), "%s %s %s session %d" % (grader, kind, cid, s))
            if previous is not None and started < previous:
                timing.append("%s %s %s: session %d starts before the previous reply" % (grader, kind, cid, s))
            previous = started
            if started < commitment_time:
                timing.append("%s %s %s: session %d starts before the commitment was pushed" % (grader, kind, cid, s))
            row = []
            for n, item in enumerate(session.get("replies", []), 1):
                received = parse_time(item.get("receivedUTC"), "%s %s %s reply %d.%d" % (grader, kind, cid, s, n))
                if received < previous:
                    timing.append("%s %s %s: reply %d.%d is earlier than what came before it" % (grader, kind, cid, s, n))
                previous = received
                reply_times.append(received)
                file = (folder / str(item.get("file", ""))).resolve()
                if not file.is_relative_to(folder.resolve()) or not file.is_file():
                    raise InputError("RECORD.json: reply file %r is missing or outside the input" % item.get("file"))
                reply, problems = form.check_text(kind, file.read_bytes(), question, token)
                row.append(not problems)
                texts.append(reply)
                if problems:
                    invalid.append({"grader": grader, "kind": kind, "id": cid, "attempt": "%d.%d" % (s, n),
                                    "problems": problems})
            validity.append(row)
        status, accepted = form.call_status(validity)
        calls[(grader, kind, cid)] = {"grader": grader, "kind": kind, "id": cid, "status": status,
                                      "attempts": sum(len(r) for r in validity), "acceptedUTC": previous
                                      if status == "completed" else None}
        if status == "completed":
            grades[kind][grader][cid] = [t for t in texts if t is not None][-1]
    for (grader, kind, cid), call in calls.items():
        if kind == "guess":
            pref = calls.get((grader, "preference", cid))
            if pref is None or pref["status"] != "completed":
                raise InputError("RECORD.json: a guess call %s %s without a stored preference" % (grader, cid))
            if call["status"] == "completed" and call["acceptedUTC"] < pref["acceptedUTC"]:
                timing.append("%s guess %s: before the preference was stored" % (grader, cid))
    return {"commitment": commitment_time, "withdrawnModels": record["withdrawnModels"],
            "humanGraders": record["humanGraders"], "calls": calls, "grades": grades, "invalidReplies": invalid,
            "timing": timing, "lastReply": max(reply_times) if reply_times else None}


def load_input(folder, key):
    folder = Path(folder)
    runs = read_runs(folder / "runs.csv", key)
    _, tokens, sides = read_blinding(folder, runs)
    record = read_record(folder, runs, key, tokens, sides)
    lock = json.loads((BENCH / "LOCK.json").read_text(encoding="utf-8"))
    return {"runs": runs, "sides": {pid: armA for pid, (_, armA) in sides.items()}, "record": record,
            "secondGenerator": bool(lock["generator"]["optionalSecondModel"]["runs"])}


# ------------------------------------------------------------------------------------------------ run scores

def score_runs(runs, scores, key, graders=GRADERS):
    """Section 11 run scores for every slot (dict id -> record)."""
    records = {}
    for sid in sorted(runs):
        run = runs[sid]
        q = key[run["question"]]
        record = {k: run[k] for k in ("id", "question", "arm", "run", "status")}
        if run["status"] == "failed":
            record.update(state="failed", graders=[])
        else:
            replies = {g: scores[g][sid] for g in graders if sid in scores[g]}
            record["graders"] = sorted(replies)
            if not replies:
                record["state"] = "ungraded"
            else:
                record["state"] = "graded"
                record.update(merge_output(replies, q))
                record["perGrader"] = {g: {
                    "configuration": r["configuration"],
                    "resolvedConfiguration": resolve_configuration(r["configuration"], q),
                    "checks": {c: r["mechanism"][c] for c in CHECKS},
                    "mechanism": mechanism_score({c: merge_check([r["mechanism"][c]]) for c in CHECKS}),
                    "coverage": grader_coverage(r, q),
                    "errors": len(r["errors"]),
                    "clarity": r["clarity"],
                    "defects": {s: sum(1 for d in r["defects"] if d["severity"] == s) for s in SEVERITIES},
                    "warnings": coverage_warnings(r, q)} for g, r in replies.items()}
        records[sid] = record
    # E_fail(q) = 1 + the largest merged error count of any graded output of q in either arm; undefined (None) when
    # q has no graded output (A-02).
    for question in key:
        graded = [r["errors"] for r in records.values() if r["question"] == question and r["state"] == "graded"]
        for r in records.values():
            if r["question"] == question and r["state"] == "failed":
                r.update(checks=None, mechanism=Fraction(0), clarity=0, coverage=Fraction(0),
                         errors=1 + max(graded) if graded else None, defects=None)
    return records


def value(record, field):
    """The value of a run in a mean of `field`, or None (left out): ungraded outputs and undefined values."""
    if record["state"] == "ungraded":
        return None
    if field in ("defectsMajor", "defectsMinor"):
        return None if record["defects"] is None else record["defects"]["major" if field == "defectsMajor" else "minor"]
    return record[field]


def question_level(records, key, field, questions=None, runs=None):
    """M(q, a) over failed and graded runs with a defined value, d(q) = M(q, 1) - M(q, 2), the test and the interval.

    With `runs`, only runs whose pair has two rendered outputs count (the rendered-pair variant of section 11, 1)."""
    rows = []
    for question in (questions if questions is not None else sorted(key)):
        means, counts = {}, {}
        for arm in ARMS:
            mine = [r for r in records.values() if r["question"] == question and r["arm"] == arm
                    and (runs is None or both_rendered(runs, question, r["run"]))]
            values = [value(r, field) for r in mine]
            counts[arm] = {"runs": len(mine), "counted": sum(1 for v in values if v is not None),
                           "leftOut": [r["id"] for r, v in zip(mine, values) if v is None]}
            means[arm] = mean(v for v in values if v is not None)
        d = means[1] - means[2] if means[1] is not None and means[2] is not None else None
        rows.append({"question": question, "M1": means[1], "M2": means[2], "d": d, "counts": counts})
    defined = [row["d"] for row in rows if row["d"] is not None]
    test = sign_test(defined)
    effect = mean(defined)
    majority = (test["positive"] > test["negative"]) - (test["positive"] < test["negative"])
    sign = (effect > 0) - (effect < 0) if effect is not None else 0
    return {"field": field, "rows": rows, "leftOut": [row["question"] for row in rows if row["d"] is None],
            "signTest": test, "testResult": test_result(test), "meanD": effect, "interval": bootstrap_mean(defined),
            "oppositeSignedEffect": bool(majority and sign and majority != sign)}


def pooled(records, key, field, arm, questions=None, runs=None):
    """The mean of `field` over the counted runs of one arm, with a question-level ratio interval."""
    nums, dens, total, count = [], [], Fraction(0), 0
    for question in (questions if questions is not None else sorted(key)):
        values = [value(r, field) for r in records.values() if r["question"] == question and r["arm"] == arm
                  and (runs is None or both_rendered(runs, question, r["run"]))]
        values = [v for v in values if v is not None]
        nums.append(sum(values, Fraction(0)))
        dens.append(len(values))
        total += nums[-1]
        count += len(values)
    return {"mean": total / count if count else None, "n": count, "interval": bootstrap_ratio(nums, dens)}


# -------------------------------------------------------------------------------------------- design status

def required_calls(runs, record):
    required = []
    for run in sorted(runs.values(), key=lambda r: r["id"]):
        if run["status"] == "rendered":
            required += [(g, "score", run["id"]) for g in GRADERS]
    for question, run in sorted({(r["question"], r["run"]) for r in runs.values()}):
        if both_rendered(runs, question, run):
            pid = pair_id(question, run)
            for g in GRADERS:
                required.append((g, "preference", pid))
                pref = record["calls"].get((g, "preference", pid))
                if pref is not None and pref["status"] == "completed":
                    required.append((g, "guess", pid))
    return required


def design_status(data, key, records):
    """Section 11 'Stopping rule and incomplete data', checked from the run table and the dated record (A-07)."""
    runs, record = data["runs"], data["record"]
    reasons = []
    expected = sorted((q, a, r) for q in key for a in ARMS for r in range(1, RUNS_PER_ARM + 1))
    missing = [slot_id(*s) for s in expected if slot_id(*s) not in runs]
    if missing:
        reasons.append("%d run slots are not generated" % len(missing))
    timing = []
    for run in runs.values():
        if run["ended"] < run["started"]:
            timing.append("%s ends before it starts" % run["id"])
        if run["status"] == "rendered" and run["ended"] - run["started"] > RUN_LIMIT:
            timing.append("%s is rendered but took longer than 60 min (a failure, sections 4 and 5)" % run["id"])
    by_start = sorted(runs.values(), key=lambda r: r["started"])
    for before, after in zip(by_start, by_start[1:]):
        if after["started"] < before["ended"]:
            timing.append("%s starts before %s ends (runs are one at a time)" % (after["id"], before["id"]))
    if not missing:
        order = list(expected)
        random.Random(RUN_ORDER_SEED).shuffle(order)
        if [slot_id(*s) for s in order] != [r["id"] for r in by_start] or \
                len({r["started"] for r in by_start}) != len(by_start):
            timing.append("the runs did not start in the registered order (random.Random(20261111).shuffle)")
    generation_end = max((r["ended"] for r in runs.values()), default=None)
    if generation_end is not None and record["commitment"] < generation_end:
        timing.append("the commitment was pushed before generation ended")
    timing += record["timing"]
    if timing:
        reasons.append("the run or grading timing does not follow the protocol (%d findings)" % len(timing))
    statuses = {}
    for call in required_calls(runs, record):
        status = record["calls"][call]["status"] if call in record["calls"] else "not recorded"
        statuses.setdefault(status, []).append("%s %s %s" % call)
    open_calls = {s: ids for s, ids in statuses.items() if s not in ("completed", "exhausted")}
    if open_calls:
        reasons.append("grading calls are not completed or exhausted under section 6: %s"
                       % ", ".join("%d %s" % (len(v), k) for k, v in sorted(open_calls.items())))
    run1 = min((r["started"] for r in runs.values()), default=None)
    completion = max([t for t in (generation_end, record["lastReply"]) if t is not None], default=None)
    within = run1 is not None and completion is not None and completion <= run1 + timedelta(days=DESIGN_DAYS)
    if not within:
        reasons.append("the design did not complete within 21 days after run 1")
    if record["withdrawnModels"]:
        reasons.append("a model was withdrawn: %s" % ", ".join(map(str, record["withdrawnModels"])))
    rendered = [r for r in records.values() if r["status"] == "rendered"]
    ungraded = [r["id"] for r in rendered if r["state"] == "ungraded"]
    share = rate(len(ungraded), len(rendered))
    if share["value"] is not None and share["value"] > UNGRADED_LIMIT:
        reasons.append("more than 5 %% of the rendered outputs are ungraded (%d of %d)" % (len(ungraded), len(rendered)))
    return {"complete": not reasons, "reasons": reasons, "missingSlots": missing, "timingFindings": timing,
            "callStatus": {k: len(v) for k, v in sorted(statuses.items())},
            "openCalls": {k: v for k, v in sorted(open_calls.items())},
            "run1StartedUTC": run1.isoformat() if run1 else None,
            "completedUTC": completion.isoformat() if completion else None,
            "withinDays": DESIGN_DAYS, "ungradedShare": share, "withdrawnModels": record["withdrawnModels"]}


# ------------------------------------------------------------------------------------- exploratory analyses

def preference_pairs(runs, sides, preferences, key):
    pairs = []
    for question in sorted(key):
        for run in range(1, RUNS_PER_ARM + 1):
            pid = pair_id(question, run)
            slots = [runs.get(slot_id(question, a, run)) for a in ARMS]
            if None in slots:
                pairs.append({"pair": pid, "question": question, "kind": "incomplete", "result": None})
                continue
            rendered = [s["status"] == "rendered" for s in slots]
            if all(rendered):
                answers = []
                for g in GRADERS:
                    if pid in preferences[g]:
                        p = preferences[g][pid]["preference"]
                        answers.append("tie" if p == "tie" else "arm%d" % (sides[pid] if p == "A" else 3 - sides[pid]))
                result = merge_preference(answers)
                pairs.append({"pair": pid, "question": question, "kind": "graded" if result else "unjudged",
                              "result": result})
            elif not any(rendered):
                pairs.append({"pair": pid, "question": question, "kind": "automatic", "result": "tie"})
            else:
                pairs.append({"pair": pid, "question": question, "kind": "automatic",
                              "result": "arm1" if rendered[0] else "arm2"})
    return pairs


def preference_analysis(runs, sides, preferences, key):
    pairs = preference_pairs(runs, sides, preferences, key)

    def win_rate(kinds):
        chosen = [p for p in pairs if p["kind"] in kinds]
        wins = sum(p["result"] == "arm1" for p in chosen)
        losses = sum(p["result"] == "arm2" for p in chosen)
        out = rate(wins, wins + losses)
        out["ties"] = sum(p["result"] == "tie" for p in chosen)
        per_q = [(sum(p["result"] == "arm1" for p in chosen if p["question"] == q),
                  sum(p["result"] == "arm2" for p in chosen if p["question"] == q)) for q in sorted(key)]
        out["interval"] = bootstrap_ratio([w for w, _ in per_q], [w + l for w, l in per_q])
        return out

    def winners(kinds):
        # A-11: the question-level winner by pair wins; the estimate is the mean of +1 (arm 1), 0 (tie), -1 (arm 2)
        # over the questions with at least one judged pair.
        rows, signs = [], []
        for q in sorted(key):
            chosen = [p for p in pairs if p["question"] == q and p["kind"] in kinds]
            w = sum(p["result"] == "arm1" for p in chosen)
            l = sum(p["result"] == "arm2" for p in chosen)
            t = sum(p["result"] == "tie" for p in chosen)
            winner = None if not chosen else ("arm1" if w > l else "arm2" if l > w else "tie")
            rows.append({"question": q, "wins": w, "losses": l, "ties": t, "winner": winner})
            if winner is not None:
                signs.append(Fraction((w > l) - (l > w)))
        return {"rows": rows, "arm1Questions": sum(r["winner"] == "arm1" for r in rows),
                "arm2Questions": sum(r["winner"] == "arm2" for r in rows),
                "tiedQuestions": sum(r["winner"] == "tie" for r in rows),
                "undefinedQuestions": sum(r["winner"] is None for r in rows),
                "meanSign": mean(signs), "interval": bootstrap_mean(signs)}
    return {"pairs": pairs,
            "unjudged": [p["pair"] for p in pairs if p["kind"] == "unjudged"],
            "arm1WinRateGraded": win_rate(("graded",)),
            "arm1WinRateWithAutomatic": win_rate(("graded", "automatic")),
            "questionWinnersGraded": winners(("graded",)),
            "questionWinnersWithAutomatic": winners(("graded", "automatic"))}


def counts_per_arm(records):
    out = {}
    for arm in ARMS:
        mine = [r for r in records.values() if r["arm"] == arm]
        graded = [r for r in mine if r["state"] == "graded"]
        failed = [r for r in mine if r["state"] == "failed"]
        per_check = {c: {
            "merged": {s: sum(1 for r in graded if r["checks"][c] == s) for s in (PASS, NOT_PASS, UNJUDGED, NA)},
            "cannotJudge": {g: sum(1 for r in graded if r["perGrader"].get(g, {}).get("checks", {}).get(c)
                                   == "CANNOT JUDGE") for g in GRADERS},
            "notApplicable": {g: sum(1 for r in graded if r["perGrader"].get(g, {}).get("checks", {}).get(c)
                                     == "N/A") for g in GRADERS}} for c in CHECKS}
        configurations = {}
        for g in GRADERS:
            names = [r["perGrader"][g]["resolvedConfiguration"] for r in graded if g in r["perGrader"]]
            configurations[g] = {n: names.count(n) for n in sorted(set(names))}
        both = [r for r in graded if all(g in r["perGrader"] for g in GRADERS)]
        same = sum(1 for r in both if len({r["perGrader"][g]["resolvedConfiguration"] for g in GRADERS}) == 1)
        out["arm%d" % arm] = {
            "runs": len(mine),
            "rendered": sum(1 for r in mine if r["status"] == "rendered"),
            "failed": [r["id"] for r in failed],
            "failedWithUndefinedEfail": [r["id"] for r in failed if r["errors"] is None],
            "ungraded": [r["id"] for r in mine if r["state"] == "ungraded"],
            "oneGradeMissing": [r["id"] for r in graded if len(r["graders"]) == 1],
            "mechanismNA": [r["id"] for r in graded if r["mechanism"] is None],
            "coverageNA": [r["id"] for r in graded if r["coverage"] is None],
            "checks": per_check,
            "configurations": configurations,
            "configurationAgreement": rate(same, len(both)),
        }
    return out


def success_analysis(runs, key):
    out = {"perQuestion": []}
    for q in sorted(key):
        row = {"question": q}
        for arm in ARMS:
            mine = [r for r in runs.values() if r["question"] == q and r["arm"] == arm]
            row["arm%d" % arm] = rate(sum(r["status"] == "rendered" for r in mine), len(mine))
        out["perQuestion"].append(row)
    for arm in ARMS:
        nums = [row["arm%d" % arm]["numerator"] for row in out["perQuestion"]]
        dens = [row["arm%d" % arm]["denominator"] for row in out["perQuestion"]]
        out["arm%d" % arm] = dict(rate(sum(nums), sum(dens)), interval=bootstrap_ratio(nums, dens))
    return out


def cost_analysis(runs, key):
    """Section 11, 8: tries used, wall time and the CLI's total_cost_usd sum, per arm (runs.csv)."""
    out = {}
    for arm in ARMS:
        row = {}
        for field in ("tries", "wallSeconds", "costUsd"):
            per_q = [[r[field] for r in runs.values() if r["question"] == q and r["arm"] == arm] for q in sorted(key)]
            nums, dens = [sum(v, Fraction(0)) for v in per_q], [len(v) for v in per_q]
            row[field] = {"mean": sum(nums, Fraction(0)) / sum(dens) if sum(dens) else None, "n": sum(dens),
                          "meanInterval": bootstrap_ratio(nums, dens)}
            if field == "costUsd":
                row[field]["sum"] = sum(nums, Fraction(0))
                # Each resample holds as many questions as the key, so a denominator of 1/Q per question makes the
                # pooled ratio the resampled sum.
                row[field]["sumInterval"] = bootstrap_ratio(nums, [Fraction(1, len(nums))] * len(nums))
                row[field]["note"] = "a subscription equivalent, not a bill"
        out["arm%d" % arm] = row
    return out


def category_analysis(records, key, primary):
    out = []
    for category in sorted({q["category"] for q in key.values()}):
        questions = [q for q in sorted(key) if key[q]["category"] == category]
        ds = [row["d"] for row in primary["rows"] if row["question"] in questions and row["d"] is not None]
        test = sign_test(ds)
        out.append({"category": category, "questions": questions,
                    "arm1": pooled(records, key, "mechanism", 1, questions),
                    "arm2": pooled(records, key, "mechanism", 2, questions),
                    "meanD": mean(ds), "interval": bootstrap_mean(ds), "positive": test["positive"],
                    "negative": test["negative"], "ties": test["ties"], "definedQuestions": len(ds)})
    return out


def blinding_analysis(sides, guesses, key):
    """Section 8 'Measure of the residual risk': per grader, correct, wrong and cannot-tell guesses of which side
    used a dedicated 3D engine (Arm 1), and an exact binomial test of correct against wrong (null 50 %)."""
    out = {}
    for g in GRADERS:
        counts = {"correct": 0, "wrong": 0, "cannotTell": 0}
        per_q = {q: [0, 0] for q in key}
        different = {v: 0 for v in form.GUESS_DIFFERENT}
        for pid, reply in sorted(guesses[g].items()):
            different[reply["differentTools"]] += 1
            if reply["engine"] == "cannot tell":
                counts["cannotTell"] += 1
                continue
            arm = sides[pid] if reply["engine"] == "A" else 3 - sides[pid]
            name = "correct" if arm == 1 else "wrong"
            counts[name] += 1
            per_q[pid.rpartition("-r")[0]][0 if arm == 1 else 1] += 1
        n = counts["correct"] + counts["wrong"]
        out[g] = dict(counts, guesses=len(guesses[g]), differentTools=different,
                      binomialP=binomial_two_sided(counts["correct"], n),
                      correctShare=rate(counts["correct"], n),
                      interval=bootstrap_ratio([c for c, _ in per_q.values()], [c + w for c, w in per_q.values()]))
    return out


def agreement_analysis(records, preferences):
    """Section 10 agreement statistics (G1 against G2, on the outputs and pairs both graded), with 95 % bootstrap
    intervals: the section 11 settings, outputs (or pairs) resampled with replacement (A-06)."""
    np = require_numpy()
    g1, g2 = GRADERS
    both = [r for r in records.values() if r["state"] == "graded" and all(g in r["perGrader"] for g in GRADERS)]
    n = len(both)
    weights = resample_weights(n) if n else None

    def interval(stats):
        return _interval(np, stats, "resample the outputs with replacement") if n else None

    def numeric(get):
        x = [get(r["perGrader"][g1]) for r in both]
        y = [get(r["perGrader"][g2]) for r in both]
        fx = np.array([np.nan if v is None else float(v) for v in x])
        fy = np.array([np.nan if v is None else float(v) for v in y])
        return {"items": n, "pairable": sum(1 for a, b in zip(x, y) if a is not None and b is not None),
                "krippendorffAlphaInterval": agreement.krippendorff_alpha(list(zip(x, y)), "interval"),
                "alphaInterval": interval(agreement.alpha_interval_weighted(fx, fy, weights)) if n else None,
                "spearmanRho": agreement.spearman_rho(x, y),
                "rhoInterval": interval(agreement.spearman_weighted(fx, fy, weights)) if n else None}

    out = {"outputsBothGraded": n,
           "mechanismScore": numeric(lambda p: p["mechanism"]),
           "errors": numeric(lambda p: p["errors"]),
           "coverage": numeric(lambda p: p["coverage"]),
           "defectsMajor": numeric(lambda p: p["defects"]["major"]),
           "defectsMinor": numeric(lambda p: p["defects"]["minor"])}
    cx = [r["perGrader"][g1]["clarity"] for r in both]
    cy = [r["perGrader"][g2]["clarity"] for r in both]
    scale = [1, 2, 3, 4, 5]
    cells = agreement.cells([[(scale.index(a), scale.index(b))] for a, b in zip(cx, cy)], 5)
    out["clarity"] = {"items": n, "cohenKappaQuadratic": agreement.cohen_kappa(cx, cy, scale, weights="quadratic"),
                      "interval": interval(agreement.kappa_weighted(cells, weights, "quadratic")) if n else None}
    checks = {}
    for kinds in [[c] for c in CHECKS] + [list(CHECKS)]:
        judged_pairs, one_judged = [], []
        for r in both:
            row, ones = [], 0
            for c in kinds:
                a, b = r["perGrader"][g1]["checks"][c], r["perGrader"][g2]["checks"][c]
                if a in JUDGED and b in JUDGED:
                    row.append((int(a != "PASS"), int(b != "PASS")))
                elif (a in JUDGED) != (b in JUDGED):
                    ones += 1
            judged_pairs.append(row)
            one_judged.append(ones)
        x = [a == 0 for row in judged_pairs for a, _ in row]
        y = [b == 0 for row in judged_pairs for _, b in row]
        cell = agreement.cells(judged_pairs, 2)
        entry = {"bothJudged": len(x), "percentAgreement": agreement.percent_agreement(x, y),
                 "cohenKappa": agreement.cohen_kappa(x, y, [True, False]),
                 "oneJudgedOtherNot": rate(sum(one_judged), n * len(kinds))}
        if n:
            entry["percentAgreementInterval"] = interval(agreement.agreement_weighted(cell, weights))
            entry["kappaInterval"] = interval(agreement.kappa_weighted(cell, weights))
            share = (weights @ np.array(one_judged, dtype=float)) / (len(kinds) * weights.sum(axis=1))
            entry["oneJudgedOtherNotInterval"] = interval(share)
        checks["pooled" if len(kinds) > 1 else kinds[0]] = entry
    out["checks"] = checks
    pairs = sorted(set(preferences[g1]) & set(preferences[g2]))
    labels = list(form.PREFERENCES)
    px = [preferences[g1][p]["preference"] for p in pairs]
    py = [preferences[g2][p]["preference"] for p in pairs]
    pcells = agreement.cells([[(labels.index(a), labels.index(b))] for a, b in zip(px, py)], 3)
    out["preference"] = {"pairsBothGraded": len(pairs), "cohenKappa": agreement.cohen_kappa(px, py, labels),
                         "interval": _interval(np, agreement.kappa_weighted(pcells, resample_weights(len(pairs))),
                                               "resample the pairs with replacement") if pairs else None}
    return out


# ------------------------------------------------------------------------------------------------- analysis

def analyse(data, key):
    np = require_numpy()
    runs, record = data["runs"], data["record"]
    grades = record["grades"]
    if data["secondGenerator"] or record["humanGraders"]:
        raise InputError("the optional second generator and human graders need their separate analysis, which is "
                         "not enabled in this harness")
    records = score_runs(runs, grades["score"], key)
    primary = question_level(records, key, "mechanism")
    design = design_status(data, key, records)
    if design["complete"]:
        verdict = {"verdict": primary["testResult"], "status": "registered verdict (completed design)"}
    else:
        verdict = {"verdict": None, "status": "descriptive results only: " + "; ".join(design["reasons"]),
                   "primaryTestWouldBe": primary["testResult"]}
    kept = [q for q in sorted(key) if q not in NEAR_SHIPPED]
    efail = {"arm%d" % a: {"failedRuns": sum(1 for r in records.values() if r["arm"] == a and r["state"] == "failed"),
                           "withDefinedEfail": sum(1 for r in records.values() if r["arm"] == a
                                                   and r["state"] == "failed" and r["errors"] is not None)}
             for a in ARMS}
    return {
        "kind": "mechanisms-v1.score/2",
        "software": {"python": platform.python_version(), "numpy": np.__version__},
        "verdict": verdict,
        "design": design,
        "primary": primary,
        "sensitivityWithoutNearShipped": dict(question_level(records, key, "mechanism", kept),
                                              note="descriptive; does not change the verdict"),
        "ungradedOutputs": [r["id"] for r in records.values() if r["state"] == "ungraded"],
        "mechanismNAOutputs": [r["id"] for r in records.values() if r["state"] == "graded" and r["mechanism"] is None],
        "invalidReplies": record["invalidReplies"],
        "countsPerArm": counts_per_arm(records),
        "exploratory": {
            "note": "exploratory and unadjusted; never a route to a win, a loss or a claim of superiority",
            "errors": {"questionLevel": question_level(records, key, "errors"),
                       "perArm": {"arm%d" % a: pooled(records, key, "errors", a) for a in ARMS},
                       "efailContributions": efail,
                       "renderedPairsOnly": {"questionLevel": question_level(records, key, "errors", runs=runs),
                                             "perArm": {"arm%d" % a: pooled(records, key, "errors", a, runs=runs)
                                                        for a in ARMS}}},
            "preference": preference_analysis(runs, data["sides"], grades["preference"], key),
            "clarity": {"questionLevel": question_level(records, key, "clarity"),
                        "perArm": {"arm%d" % a: pooled(records, key, "clarity", a) for a in ARMS}},
            "defects": {s: {"questionLevel": question_level(records, key, s),
                            "perArm": {"arm%d" % a: pooled(records, key, s, a) for a in ARMS}}
                        for s in ("defectsMajor", "defectsMinor")},
            "success": success_analysis(runs, key),
            "coverage": {"aggregate": "mean of per-run fractions (A-11)",
                         "questionLevel": question_level(records, key, "coverage"),
                         "perArm": {"arm%d" % a: pooled(records, key, "coverage", a) for a in ARMS}},
            "cost": cost_analysis(runs, key),
            "perCategory": category_analysis(records, key, primary),
            "agreement": agreement_analysis(records, grades["preference"]),
            "primaryPerGraderAlone": {g: question_level(score_runs(runs, grades["score"], key, graders=(g,)), key,
                                                        "mechanism") for g in GRADERS},
            "blinding": blinding_analysis(data["sides"], grades["guess"], key),
            "optionalSecondGenerator": "not enabled (LOCK.json generator.optionalSecondModel.runs is false)",
            "humanGraders": "not enabled (RECORD.json humanGraders is empty)",
        },
        "runs": [records[s] for s in sorted(records)],
    }


# --------------------------------------------------------------------------------------------------- output

def to_json(value):
    """Fractions become {"exact": "p/q", "float": x}; times become ISO strings; the rest is plain JSON."""
    if isinstance(value, Fraction):
        return {"exact": str(value), "float": float(value)}
    if isinstance(value, datetime):
        return value.isoformat()
    if isinstance(value, dict):
        return {str(k): to_json(v) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [to_json(v) for v in value]
    return value


def summary(result):
    p = result["primary"]
    t = p["signTest"]
    lines = ["verdict: %s (%s)" % (result["verdict"]["verdict"], result["verdict"]["status"]),
             "primary test: %s; %d questions with defined d(q): %d positive, %d negative, %d ties; p = %s (%.4f)"
             % (p["testResult"], t["definedQuestions"], t["positive"], t["negative"], t["ties"], t["p"], float(t["p"])),
             "mean d(q): %s; 95 %% interval: %s to %s"
             % (None if p["meanD"] is None else "%.4f" % float(p["meanD"]), p["interval"]["low"], p["interval"]["high"]),
             "ungraded outputs: %d; mechanism N/A outputs: %d; invalid reply attempts: %d"
             % (len(result["ungradedOutputs"]), len(result["mechanismNAOutputs"]), len(result["invalidReplies"]))]
    if p["oppositeSignedEffect"]:
        lines.insert(1, "opposite-signed effect: the mean of d(q) (%.4f) has the opposite sign of the sign-test "
                        "majority (%d positive, %d negative)" % (float(p["meanD"]), t["positive"], t["negative"]))
    return "\n".join(lines)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("input", type=Path, help="input folder (see harness/README.md)")
    parser.add_argument("--questions", type=Path, default=BENCH / "QUESTIONS.json")
    parser.add_argument("--out", type=Path, required=True, help="write the full result JSON here")
    args = parser.parse_args(argv)
    try:
        require_numpy()
        key = load_key(args.questions)
        result = analyse(load_input(args.input, key), key)
    except InputError as error:
        print("input error:", error, file=sys.stderr)
        return 2
    args.out.write_text(json.dumps(to_json(result), indent=2) + "\n", encoding="utf-8")
    print(summary(result))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
