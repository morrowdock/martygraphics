# SPDX-License-Identifier: Apache-2.0
"""Synthetic fixtures for the harness tests. Nothing here is, or is made from, a real benchmark output."""

import csv
import json
from pathlib import Path
import sys

HARNESS = Path(__file__).resolve().parents[1]
BENCH = HARNESS.parent
sys.path.insert(0, str(HARNESS))

import score  # noqa: E402

CHECKS = score.CHECKS

# A synthetic key. Q1: two core facts for every configuration. QV: the accepted variant "v" has no applicable
# core fact (impossible in the real key, which tools/grader_questions.py --check guards; needed for the N/A path).
SYNTHETIC_KEY = {"questions": [
    {"id": "Q1", "category": "synthetic", "acceptedVariants": [],
     "keyFacts": [{"id": "K1", "core": True, "appliesTo": ["all"]},
                  {"id": "K2", "core": True, "appliesTo": ["all"]},
                  {"id": "K3", "core": False, "appliesTo": ["all"]}],
     "mechanismChecks": [{"id": c} for c in CHECKS]},
    {"id": "QV", "category": "synthetic", "acceptedVariants": [{"id": "v"}],
     "keyFacts": [{"id": "K1", "core": True, "appliesTo": ["conventional"]},
                  {"id": "K2", "core": True, "appliesTo": ["conventional"]},
                  {"id": "K3", "core": False, "appliesTo": ["all"]}],
     "mechanismChecks": [{"id": c} for c in CHECKS]},
]}


def write_key(folder, doc=SYNTHETIC_KEY):
    path = Path(folder) / "KEY.json"
    path.write_text(json.dumps(doc), encoding="utf-8")
    return path


def key(doc=SYNTHETIC_KEY, folder=None):
    import tempfile
    with tempfile.TemporaryDirectory() as tmp:
        return score.load_key(write_key(tmp, doc))


def checks_with(passes, judged=5, rest="CANNOT JUDGE"):
    """Checks with `passes` PASS among `judged` judged checks; the other judged ones FAIL; the remainder `rest`.

    Unjudged checks are put on M3/M4 first (the only checks that may be CANNOT JUDGE)."""
    order = ["M3", "M4", "M1", "M2", "M5"] if rest == "CANNOT JUDGE" else list(CHECKS)
    unjudged = order[:5 - judged]
    if rest == "CANNOT JUDGE" and len(unjudged) > 2:
        raise ValueError("only M3 and M4 can be CANNOT JUDGE")
    out, made = {}, 0
    for c in CHECKS:
        if c in unjudged:
            out[c] = rest
        else:
            out[c] = "PASS" if made < passes else "FAIL"
            made += 1
    return out


def reply(question="Q1", checks=None, errors=0, covered=(), na=(), clarity=4, major=0, minor=0,
          configuration="conventional", output="000000000000"):
    checks = dict(checks or {c: "PASS" for c in CHECKS})
    return {"question": question, "output": output, "configuration": configuration,
            "mechanism": dict(checks, evidence={}),
            "errors": [{"type": "K", "keyFact": "K1", "time": "1.0 s", "text": "t", "reason": "r"}] * errors,
            "unsure": [], "coveredFacts": list(covered), "notApplicableFacts": list(na),
            "clarity": clarity, "clarityReason": "synthetic",
            "defects": [{"type": "D3", "severity": "major", "time": "1.0 s", "evidence": "e"}] * major
            + [{"type": "D1", "severity": "minor", "time": "1.0 s", "evidence": "e"}] * minor}


def preference(question, pair, answer):
    return {"question": question, "pair": pair, "preference": answer, "preferenceReason": "synthetic"}


def write_input(folder, runs, scores=None, preferences=None, sides=None):
    """runs: [(question, arm, run, status)]; scores: {(grader, slot id): reply or raw str}; preferences likewise."""
    folder = Path(folder)
    folder.mkdir(parents=True, exist_ok=True)
    with open(folder / "runs.csv", "w", newline="", encoding="utf-8") as stream:
        writer = csv.writer(stream)
        writer.writerow(["question", "arm", "run", "status"])
        writer.writerows(runs)
    if sides is not None:
        with open(folder / "pair-sides.csv", "w", newline="", encoding="utf-8") as stream:
            writer = csv.writer(stream)
            writer.writerow(["pair", "A"])
            writer.writerows(sorted(sides.items()))
    for kind, table in (("score", scores or {}), ("preference", preferences or {})):
        for (grader, name), body in table.items():
            path = folder / "grades" / grader / kind / (name + ".json")
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(body if isinstance(body, str) else json.dumps(body), encoding="utf-8")
    return folder
