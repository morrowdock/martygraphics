# SPDX-License-Identifier: Apache-2.0
"""Make the graders' question file from QUESTIONS.json (mechanisms-v1).

Graders see only: the question id and text, each key fact's id, fact, core flag and acceptedVariants, and the five
mechanism checks. No category, sources, check labels, designer notes, nearShipped notes, or anything about how the
outputs are made.

Usage (from benchmark/mechanisms-v1):
  python3 tools/grader_questions.py            write GRADER-QUESTIONS.json
  python3 tools/grader_questions.py --check    exit 1 if GRADER-QUESTIONS.json is not up to date or leaks a word
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
            "keyFacts": [{"id": k["id"], "fact": k["fact"], "core": k["core"], "acceptedVariants": k["acceptedVariants"]}
                         for k in q["keyFacts"]],
            "mechanismChecks": [{"id": m["id"], "kind": m["kind"], "pass": m["pass"]} for m in q["mechanismChecks"]],
        })
    return {"kind": "grader-questions/1", "questions": questions}


def leaks(doc):
    text = json.dumps(doc, ensure_ascii=False).lower()
    return [w for w in FORBIDDEN if re.search(r"(?<![a-z0-9])" + re.escape(w) + r"(?![a-z0-9])", text)]


def main(argv):
    doc = build()
    bad = leaks(doc)
    if bad:
        print("Forbidden words in the grader view:", ", ".join(bad), file=sys.stderr)
        return 1
    data = json.dumps(doc, indent=2, ensure_ascii=False) + "\n"
    if argv == ["--check"]:
        if not TARGET.exists() or TARGET.read_text(encoding="utf-8") != data:
            print("GRADER-QUESTIONS.json is not up to date", file=sys.stderr)
            return 1
        print("PASS: GRADER-QUESTIONS.json matches QUESTIONS.json and has no forbidden word")
        return 0
    if argv:
        print(__doc__)
        return 2
    TARGET.write_text(data, encoding="utf-8")
    print("wrote", TARGET.name, len(doc["questions"]), "questions")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
