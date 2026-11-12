# SPDX-License-Identifier: Apache-2.0
"""Synthetic fixtures for the harness tests. Nothing here is, or is made from, a real benchmark output.

`build(folder, plan)` writes a complete input folder (runs.csv with times in the registered order, the seed, its
commitment, the published mapping, RECORD.json and every reply file) from a compact plan, so most tests run the
same load-and-analyse path as the official report. Expected values in the tests come from fixed numbers or hand
rules, never from score.py.
"""

import csv
from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import random
import sys

HARNESS = Path(__file__).resolve().parents[1]
BENCH = HARNESS.parent
sys.path.insert(0, str(HARNESS))

import blinding  # noqa: E402
import score  # noqa: E402

CHECKS = score.CHECKS
SEED = bytes(range(32))
BASE = datetime(2026, 12, 1, tzinfo=timezone.utc)

# A synthetic key. Q1: no variant, two core facts. QV: variant "v" has no applicable core fact (impossible in the
# real key, which tools/grader_questions.py --check guards; needed for the coverage N/A path); variant "w" has one.
SYNTHETIC_KEY = {"questions": [
    {"id": "Q1", "category": "c1", "acceptedVariants": [],
     "keyFacts": [{"id": "K1", "core": True, "appliesTo": ["all"]},
                  {"id": "K2", "core": True, "appliesTo": ["all"]},
                  {"id": "K3", "core": False, "appliesTo": ["all"]}],
     "mechanismChecks": [{"id": c} for c in CHECKS]},
    {"id": "QV", "category": "c2", "acceptedVariants": [{"id": "v"}, {"id": "w"}],
     "keyFacts": [{"id": "K1", "core": True, "appliesTo": ["conventional"]},
                  {"id": "K2", "core": True, "appliesTo": ["conventional", "w"]},
                  {"id": "K3", "core": False, "appliesTo": ["all"]}],
     "mechanismChecks": [{"id": c} for c in CHECKS]},
]}

NO_JUDGED = {"M1": "N/A", "M2": "N/A", "M3": "CANNOT JUDGE", "M4": "CANNOT JUDGE", "M5": "N/A"}


def many_questions(n):
    return {"questions": [{"id": "Q%02d" % i, "category": "c%d" % (i % 3), "acceptedVariants": [],
                           "keyFacts": [{"id": "K1", "core": True, "appliesTo": ["all"]},
                                        {"id": "K2", "core": True, "appliesTo": ["all"]}],
                           "mechanismChecks": [{"id": c} for c in CHECKS]} for i in range(n)]}


def write_key(folder, doc):
    path = Path(folder) / "KEY.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(doc), encoding="utf-8")
    return path


def prefix(n, judged=5):
    """n PASS among `judged` judged checks (PASS first, then FAIL); M3/M4 CANNOT JUDGE for the unjudged ones."""
    unjudged = ["M3", "M4"][:5 - judged]
    if len(unjudged) != 5 - judged:
        raise ValueError("only M3 and M4 can be CANNOT JUDGE")
    out, made = {}, 0
    for c in CHECKS:
        if c in unjudged:
            out[c] = "CANNOT JUDGE"
        else:
            out[c] = "PASS" if made < n else "FAIL"
            made += 1
    return out


def reply(slot, checks=None, errors=0, covered=(), na=(), clarity=4, major=0, minor=0,
          configuration="conventional", output=None):
    """A valid score reply for slot (question, arm, run)."""
    question, arm, run = slot
    checks = dict(checks or {c: "PASS" for c in CHECKS})
    evidence = {c: ("t=1.0 s: synthetic contradiction" if v == "FAIL" else "synthetic reason")
                for c, v in checks.items() if v in ("FAIL", "CANNOT JUDGE")}
    return {"question": question,
            "output": output if output is not None else blinding.output_token(SEED, question, run, arm),
            "configuration": configuration, "mechanism": dict(checks, evidence=evidence),
            "errors": [{"type": "K", "keyFact": "K1", "time": "%d.0 s" % (i + 1), "text": "claim %d" % i,
                        "reason": "synthetic"} for i in range(errors)],
            "unsure": [], "coveredFacts": list(covered), "notApplicableFacts": list(na),
            "clarity": clarity, "clarityReason": "synthetic",
            "defects": [{"type": "D3", "severity": "major", "time": "still-2", "evidence": "synthetic"}] * major
            + [{"type": "D1", "severity": "minor", "time": "4.0 s", "evidence": "synthetic"}] * minor}


def letter(question, run, arm):
    """The packet letter (A or B) under which `arm` was shown in this pair."""
    return "A" if blinding.arm_shown_as_a(SEED, question, run) == arm else "B"


def preference(question, run, answer):
    return {"question": question, "pair": blinding.pair_token(SEED, question, run), "preference": answer,
            "preferenceReason": "synthetic"}


def guess(engine):
    return {"differentTools": "yes" if engine != "cannot tell" else "cannot tell", "engine": engine,
            "reason": "synthetic"}


EXHAUSTED = [["not json", '{"still": "not the form"}']] * 3
INCOMPLETE = [["not json"]]
NONCONFORMING = [["not json"], ["not json", "not json"]]


def sessions_of(entry):
    """A plan entry -> sessions of reply texts. A dict is one valid first reply; 'exhausted', 'incomplete' and
    'nonconforming' are attempt patterns; a list is the sessions themselves (texts or dicts)."""
    if entry is None:
        return None
    if isinstance(entry, dict):
        return [[entry]]
    if entry == "exhausted":
        return EXHAUSTED
    if entry == "incomplete":
        return INCOMPLETE
    if entry == "nonconforming":
        return NONCONFORMING
    return entry


class Plan:
    """What to write. Defaults: every slot rendered; both graders give each rendered output an all-PASS reply,
    each two-rendered pair a 'tie' and each stored preference a 'cannot tell' guess; everything on time."""

    def __init__(self, key_doc=SYNTHETIC_KEY):
        self.key_doc = key_doc
        self.questions = [q["id"] for q in key_doc["questions"]]
        self.status = {}          # (q, arm, run) -> "failed"
        self.missing = set()      # slots left out of runs.csv
        self.scores = {}          # (grader, (q, arm, run)) -> reply dict | pattern | None (not recorded)
        self.preferences = {}     # (grader, (q, run)) -> "A"/"B"/"tie" | pattern | None
        self.guesses = {}         # (grader, (q, run)) -> "A"/"B"/"cannot tell" | None
        self.withdrawn = []
        self.extra_days = 0       # pushes every grading reply this many days later
        self.commit_before_end = False
        self.reply_before_commit = False
        self.swap_order = False
        self.overlap = False
        self.long_run = None      # slot that takes 61 min
        self.costs = {}           # slot -> (tries, costUsd)

    def slots(self):
        return sorted((q, a, r) for q in self.questions for a in (1, 2) for r in (1, 2, 3))

    def rendered(self, slot):
        return self.status.get(slot, "rendered") == "rendered"


def build(folder, plan):
    folder = Path(folder)
    folder.mkdir(parents=True, exist_ok=True)
    order = plan.slots()
    random.Random(20261111).shuffle(order)
    if plan.swap_order:
        order[0], order[1] = order[1], order[0]
    present = [s for s in order if s not in plan.missing]
    with open(folder / "runs.csv", "w", newline="", encoding="utf-8") as stream:
        writer = csv.writer(stream)
        writer.writerow(["question", "arm", "run", "status", "startedUTC", "endedUTC", "tries", "costUsd"])
        end = BASE
        for i, slot in enumerate(present):
            start = BASE + timedelta(minutes=15 * i)
            length = timedelta(minutes=61 if slot == plan.long_run else 10)
            if plan.overlap and i == 1:
                start -= timedelta(minutes=10)
            tries, cost = plan.costs.get(slot, (1 + (i % 4), "0.%02d" % (i % 100)))
            writer.writerow([slot[0], slot[1], slot[2], "rendered" if plan.rendered(slot) else "failed",
                             start.isoformat(), (start + length).isoformat(), tries, cost])
            end = max(end, start + length)
    seed_hex = SEED.hex()
    (folder / "BLINDING-SEED.txt").write_text(seed_hex + "\n", encoding="ascii")
    (folder / "BLINDING-COMMITMENT.txt").write_text(blinding.commitment(SEED) + "\n", encoding="ascii")
    rendered = [s for s in present if plan.rendered(s)]
    with open(folder / "output-tokens.csv", "w", newline="", encoding="utf-8") as stream:
        writer = csv.writer(stream)
        writer.writerow(["output", "token"])
        for q, a, r in sorted(rendered):
            writer.writerow([score.slot_id(q, a, r), blinding.output_token(SEED, q, r, a)])
    pairs = sorted({(q, r) for q, a, r in rendered if (q, 3 - a, r) in rendered})
    with open(folder / "pair-sides.csv", "w", newline="", encoding="utf-8") as stream:
        writer = csv.writer(stream)
        writer.writerow(["pair", "token", "A"])
        for q, r in pairs:
            writer.writerow([score.pair_id(q, r), blinding.pair_token(SEED, q, r), blinding.arm_shown_as_a(SEED, q, r)])
    commitment = end - timedelta(minutes=5) if plan.commit_before_end else end + timedelta(hours=1)
    clock = [commitment + timedelta(days=plan.extra_days, minutes=1)]
    if plan.reply_before_commit:
        clock[0] = commitment - timedelta(minutes=1)

    def tick():
        clock[0] += timedelta(seconds=1)
        return clock[0].isoformat()

    calls = []

    def record(grader, kind, cid, sessions):
        entry = {"grader": grader, "kind": kind, "id": cid, "sessions": []}
        for s, texts in enumerate(sessions, 1):
            session = {"startedUTC": tick(), "replies": []}
            for n, text in enumerate(texts, 1):
                rel = "replies/%s/%s/%s/%d-%d.txt" % (grader, kind, cid, s, n)
                path = folder / rel
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(text if isinstance(text, str) else json.dumps(text), encoding="utf-8")
                session["replies"].append({"file": rel, "receivedUTC": tick()})
            entry["sessions"].append(session)
        calls.append(entry)
        status, _ = score.form.call_status([[isinstance(t, dict) for t in texts] for texts in sessions])
        return status

    for slot in sorted(rendered):
        for g in score.GRADERS:
            entry = plan.scores.get((g, slot), "default")
            if entry == "default":
                entry = reply(slot)
            sessions = sessions_of(entry)
            if sessions is not None:
                record(g, "score", score.slot_id(*slot), sessions)
    for q, r in pairs:
        for g in score.GRADERS:
            entry = plan.preferences.get((g, (q, r)), "tie")
            if isinstance(entry, str) and entry in ("A", "B", "tie"):
                entry = preference(q, r, entry)
            sessions = sessions_of(entry)
            if sessions is None:
                continue
            if record(g, "preference", score.pair_id(q, r), sessions) == "completed":
                engine = plan.guesses.get((g, (q, r)), "cannot tell")
                if engine is not None:
                    record(g, "guess", score.pair_id(q, r), [[guess(engine)]])
    doc = {"kind": "mechanisms-v1.record/1", "commitmentPushedUTC": commitment.isoformat(),
           "withdrawnModels": plan.withdrawn, "humanGraders": [], "calls": calls}
    (folder / "RECORD.json").write_text(json.dumps(doc, indent=1), encoding="utf-8")
    return folder


def run(tmp, plan, name="in"):
    """Build the plan in tmp/name and return (result, key) through the official load-and-analyse path."""
    folder = build(Path(tmp) / name, plan)
    key = score.load_key(write_key(Path(tmp) / name, plan.key_doc))
    return score.analyse(score.load_input(folder, key), key), key
