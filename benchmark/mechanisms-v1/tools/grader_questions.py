# SPDX-License-Identifier: Apache-2.0
"""Make the graders' question file from QUESTIONS.json (mechanisms-v1).

Graders see only: the question id and text, the conventional configuration and the accepted variants, each key
fact's id, fact, core flag, appliesTo and acceptedWordings, and the five mechanism checks. No category, sources, check
labels, designer notes, fact-check records, nearShipped notes, or anything about how the outputs are made.

Usage (from benchmark/mechanisms-v1):
  python3 tools/grader_questions.py            write GRADER-QUESTIONS.json
  python3 tools/grader_questions.py --check    exit 1 if GRADER-QUESTIONS.json is not up to date, leaks a word, or a
                                               configuration has fewer than 2 applicable core facts
"""

import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
SOURCE = HERE / "QUESTIONS.json"
TARGET = HERE / "GRADER-QUESTIONS.json"

# Words that would tell a grader how an output was made. Checked case-insensitively on whole words.
# ("arm" alone is a mechanical word here: steering arm, rocker arm, wiper arm.)
FORBIDDEN = ["marty", "martygraphics", "arm 1", "arm 2", "arm one", "arm two", "three.js", "threejs", "webgl", "scenekit", "claude", "opus",
             "nearshipped", "shipped", "benchmark", "baseline", "engine check", "repair", "provenance"]


def build():
    src = json.loads(SOURCE.read_text(encoding="utf-8"))
    questions = []
    for q in src["questions"]:
        questions.append({
            "id": q["id"],
            "question": q["question"],
            "conventional": q["conventional"],
            "acceptedVariants": q["acceptedVariants"],
            "keyFacts": [{"id": k["id"], "fact": k["fact"], "core": k["core"], "appliesTo": k["appliesTo"],
                          "acceptedWordings": k["acceptedWordings"]}
                         for k in q["keyFacts"]],
            "mechanismChecks": [{"id": m["id"], "kind": m["kind"], "pass": m["pass"]} for m in q["mechanismChecks"]],
        })
    return {"kind": "grader-questions/2", "questions": questions}


def leaks(doc):
    text = json.dumps(doc, ensure_ascii=False).lower()
    return [w for w in FORBIDDEN if re.search(r"(?<![a-z0-9])" + re.escape(w) + r"(?![a-z0-9])", text)]


def configuration_gaps():
    """Every configuration (conventional and each accepted variant) needs at least 2 applicable core facts."""
    src = json.loads(SOURCE.read_text(encoding="utf-8"))
    gaps = []
    for q in src["questions"]:
        for c in ["conventional"] + [v["id"] for v in q["acceptedVariants"]]:
            n = sum(1 for f in q["keyFacts"] if f["core"] and ("all" in f["appliesTo"] or c in f["appliesTo"]))
            if n < 2:
                gaps.append("%s/%s has %d applicable core facts" % (q["id"], c, n))
        known = {"all", "conventional"} | {v["id"] for v in q["acceptedVariants"]}
        for f in q["keyFacts"]:
            if not set(f["appliesTo"]) <= known:
                gaps.append("%s %s names an unknown configuration" % (q["id"], f["id"]))
    return gaps


def main(argv):
    doc = build()
    gaps = configuration_gaps()
    if gaps:
        print("Configuration gaps:", "; ".join(gaps), file=sys.stderr)
        return 1
    bad = leaks(doc)
    if bad:
        print("Forbidden words in the grader view:", ", ".join(bad), file=sys.stderr)
        return 1
    data = json.dumps(doc, indent=2, ensure_ascii=False) + "\n"
    if argv == ["--check"]:
        if not TARGET.exists() or TARGET.read_text(encoding="utf-8") != data:
            print("GRADER-QUESTIONS.json is not up to date", file=sys.stderr)
            return 1
        print("PASS: GRADER-QUESTIONS.json matches QUESTIONS.json, has no forbidden word, and every configuration "
              "has at least 2 applicable core facts")
        return 0
    if argv:
        print(__doc__)
        return 2
    TARGET.write_text(data, encoding="utf-8")
    print("wrote", TARGET.name, len(doc["questions"]), "questions")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
