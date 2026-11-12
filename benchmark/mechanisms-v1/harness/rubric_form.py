# SPDX-License-Identifier: Apache-2.0
"""The one rubric-form validator for mechanisms-v1 grader replies, and the section 6 attempt rule.

The grading runner and score.py both use this module, so "valid JSON in the rubric's form" (PROTOCOL.md section 6)
has exactly one meaning. A reply is the exact text a grader returned. It is valid when:

- the text, without surrounding whitespace, is exactly one JSON object: no code fence, no other text, no duplicate
  key (RUBRIC.md: "Return one JSON object and nothing else");
- it has every key of the rubric's answer format with the right type, and its identity is right: the question id of
  the packet, and the output or pair token of the packet (from the published mapping);
- score replies: `configuration` is `conventional`, `unclear` or an accepted variant id of the question; each of
  `M1`-`M5` is one of the five results; `CANNOT JUDGE` only on `M3` and `M4`; `N/A` only when the configuration is an
  accepted variant (RUBRIC.md, "Configurations and N/A"); evidence for every FAIL (with a still or a time in
  seconds) and for every CANNOT JUDGE (its reason), and for every error and defect a still or a time and one sentence
  (RUBRIC.md, general rule 5); every error has its type, and a `K` error names a key fact of the question;
  `coveredFacts` lists distinct core key facts of the question, `notApplicableFacts` distinct key facts, and no fact
  is in both; `clarity` is an integer from 1 to 5 with a reason; every defect has a type and a severity.

The rubric's own example of a CANNOT JUDGE gives a reason without a time ("only the gear teeth move; no single
feature to follow"), so a CANNOT JUDGE needs a reason, not a time. Python standard library only.
"""

import json
import re
import unicodedata

CHECKS = ("M1", "M2", "M3", "M4", "M5")
CANNOT_JUDGE_CHECKS = ("M3", "M4")
JUDGED = ("PASS", "FAIL", "NOT SHOWN")
RESULTS = JUDGED + ("N/A", "CANNOT JUDGE")
ERROR_TYPES = ("K", "N", "L", "O")
DEFECT_TYPES = ("D1", "D2", "D3", "D4", "D5", "D6")
SEVERITIES = ("major", "minor")
PREFERENCES = ("A", "B", "tie")
GUESS_DIFFERENT = ("yes", "no", "cannot tell")
GUESS_ENGINE = ("A", "B", "cannot tell")
MAX_SESSIONS = 3                 # section 6: the first session and up to 2 new sessions
REPLIES_PER_FAILED_SESSION = 2   # section 6: the reply and one reply to the parse-error message

# "Give the still or the frame time (seconds)": a time such as "10.0 s", "t=6.0 s", "12 s", "3 seconds", or a still
# name such as "still-2" or "still 2".
WHERE = re.compile(r"(?<![\w.])\d+(?:\.\d+)?\s*s(?:ec(?:ond)?s?)?(?![a-z])|still[- ]?[1-5](?!\d)", re.IGNORECASE)


def _text(value):
    return isinstance(value, str) and value.strip() != ""


# Words of evidence (rule 5) are counted after the still, time and file-name references are removed. A word is a
# run of letters and combining marks (so Devanagari vowel signs do not split a word). Scripts that are written
# without spaces between words (Han, kana, Thai, Lao, Khmer, Myanmar) count as a sentence from 3 such characters.
FILE_REF = re.compile(r"\S*\.(?:png|jpe?g|webp|gif|tiff?|bmp|mp4|mov|webm|json|txt)\b", re.IGNORECASE)
NO_SPACE_SCRIPTS = ("CJK", "HIRAGANA", "KATAKANA", "THAI", "LAO", "KHMER", "MYANMAR")


def _words(text):
    words, current, unspaced = [], "", 0
    for char in text + " ":
        category = unicodedata.category(char)
        if category[0] == "L" or (category[0] == "M" and current):
            current += char
            if category[0] == "L" and unicodedata.name(char, "").startswith(NO_SPACE_SCRIPTS):
                unspaced += 1
        else:
            if current:
                words.append(current)
            current = ""
    return words, unspaced


def _evidence(value):
    """A still or time AND a sentence (rule 5: "the still or the frame time and one sentence of evidence"):
    at least two words, or three characters of a script written without spaces, beyond the references."""
    if not (_text(value) and WHERE.search(value)):
        return False
    words, unspaced = _words(WHERE.sub(" ", FILE_REF.sub(" ", value)))
    return len(words) >= 2 or unspaced >= 3


def parse(text):
    """(object, problems). The reply must be exactly one JSON object with no duplicate key."""
    if isinstance(text, bytes):
        try:
            text = text.decode("utf-8")
        except UnicodeDecodeError:
            return None, ["the reply is not UTF-8 text"]

    def no_duplicates(pairs):
        keys = [k for k, _ in pairs]
        if len(set(keys)) != len(keys):
            raise ValueError("duplicate key")
        return dict(pairs)
    try:
        value = json.loads(text.strip(), object_pairs_hook=no_duplicates)
    except ValueError as error:                   # json.JSONDecodeError is a ValueError
        return None, ["not exactly one JSON object: %s" % error]
    if not isinstance(value, dict):
        return None, ["the reply is not a JSON object"]
    return value, []


def _variants(question):
    return [v["id"] for v in question.get("acceptedVariants", [])]


def validate_score(reply, question, token):
    """Problems of a parsed score reply (an empty list: valid). `question`: its QUESTIONS.json or grader-view entry."""
    if not isinstance(reply, dict):
        return ["the reply is not a JSON object"]
    problems = []
    for name, kind in (("question", str), ("output", str), ("configuration", str), ("mechanism", dict),
                       ("errors", list), ("unsure", list), ("coveredFacts", list), ("notApplicableFacts", list),
                       ("clarity", int), ("clarityReason", str), ("defects", list)):
        if name not in reply:
            problems.append("missing key " + name)
        elif not isinstance(reply[name], kind) or (kind is int and isinstance(reply[name], bool)):
            problems.append("%s is not a %s" % (name, {str: "string", dict: "object", list: "list",
                                                       int: "integer"}[kind]))
    if problems:
        return problems
    facts = {f["id"]: f for f in question["keyFacts"]}
    variants = _variants(question)
    if reply["question"] != question["id"]:
        problems.append("question is %r, not %r" % (reply["question"], question["id"]))
    if reply["output"] != token:
        problems.append("output is %r, not the packet's output id" % reply["output"])
    configuration = reply["configuration"]
    if configuration not in ["conventional", "unclear"] + variants:
        problems.append("configuration %r is not conventional, unclear or an accepted variant" % configuration)
    mechanism = reply["mechanism"]
    evidence = mechanism.get("evidence", {})
    if not isinstance(evidence, dict):
        problems.append("mechanism.evidence is not an object")
        evidence = {}
    for check in CHECKS:
        value = mechanism.get(check)
        if value not in RESULTS:
            problems.append("%s is %r, not one of the five results" % (check, value))
            continue
        if value == "CANNOT JUDGE" and check not in CANNOT_JUDGE_CHECKS:
            problems.append("%s cannot be CANNOT JUDGE (only M3 and M4)" % check)
        if value == "N/A" and configuration not in variants:
            problems.append("%s is N/A, but N/A needs an accepted variant as the configuration" % check)
        if value == "FAIL" and not _evidence(evidence.get(check)):
            problems.append("%s is FAIL without evidence that names a still or a time and says what is wrong" % check)
        if value == "CANNOT JUDGE" and not _text(evidence.get(check)):
            problems.append("%s is CANNOT JUDGE without a reason in the evidence" % check)
    for n, item in enumerate(reply["errors"], 1):
        if not isinstance(item, dict) or item.get("type") not in ERROR_TYPES:
            problems.append("error %d has no type K, N, L or O" % n)
            continue
        if not (_text(item.get("time")) and WHERE.search(item["time"])):
            problems.append("error %d has no still or time" % n)
        for field in ("text", "reason"):
            if not _text(item.get(field)):
                problems.append("error %d has no %s" % (n, field))
        if item["type"] == "K" and not (isinstance(item.get("keyFact"), str) and item["keyFact"] in facts):
            problems.append("error %d is a key-fact error without a key fact of this question" % n)
    for n, item in enumerate(reply["defects"], 1):
        if not isinstance(item, dict) or item.get("type") not in DEFECT_TYPES or item.get("severity") not in SEVERITIES:
            problems.append("defect %d has no type D1-D6 or no severity major or minor" % n)
            continue
        if not (_text(item.get("time")) and WHERE.search(item["time"])):
            problems.append("defect %d has no still or time" % n)
        if not _text(item.get("evidence")):
            problems.append("defect %d has no evidence" % n)
    lists_ok = True
    for name, core_only in (("coveredFacts", True), ("notApplicableFacts", False)):
        ids = reply[name]
        if not all(isinstance(x, str) for x in ids) or len(set(ids)) != len(ids):
            problems.append(name + " must list distinct fact ids")
            lists_ok = False
            continue
        unknown = [x for x in ids if x not in facts]
        if unknown:
            problems.append("%s names facts not in this question: %s" % (name, ", ".join(unknown)))
        if core_only and any(x in facts and not facts[x]["core"] for x in ids):
            problems.append("coveredFacts lists a fact that is not core")
    if lists_ok and not set(reply["coveredFacts"]).isdisjoint(reply["notApplicableFacts"]):
        problems.append("a fact is both covered and N/A")
    if not 1 <= reply["clarity"] <= 5:
        problems.append("clarity %r is not 1 to 5" % reply["clarity"])
    if not _text(reply["clarityReason"]):
        problems.append("clarityReason is empty")
    return problems


def validate_preference(reply, question_id, token):
    if not isinstance(reply, dict):
        return ["the reply is not a JSON object"]
    problems = ["missing or non-string key " + k for k in ("question", "pair", "preference", "preferenceReason")
                if not isinstance(reply.get(k), str)]
    if problems:
        return problems
    if reply["question"] != question_id:
        problems.append("question is %r, not %r" % (reply["question"], question_id))
    if reply["pair"] != token:
        problems.append("pair is %r, not the packet's pair id" % reply["pair"])
    if reply["preference"] not in PREFERENCES:
        problems.append("preference %r is not A, B or tie" % reply["preference"])
    if not _text(reply["preferenceReason"]):
        problems.append("preferenceReason is empty")
    return problems


def validate_guess(reply):
    if not isinstance(reply, dict):
        return ["the reply is not a JSON object"]
    problems = []
    if reply.get("differentTools") not in GUESS_DIFFERENT:
        problems.append("differentTools is not yes, no or cannot tell")
    if reply.get("engine") not in GUESS_ENGINE:
        problems.append("engine is not A, B or cannot tell")
    if not _text(reply.get("reason")):
        problems.append("reason is missing or empty")
    return problems


def check_text(kind, text, question=None, token=None):
    """Parse and validate one reply text: (object or None, problems)."""
    reply, problems = parse(text)
    if problems:
        return None, problems
    if kind == "score":
        problems = validate_score(reply, question, token)
    elif kind == "preference":
        problems = validate_preference(reply, question["id"], token)
    elif kind == "guess":
        problems = validate_guess(reply)
    else:
        raise ValueError("kind must be score, preference or guess")
    return (reply if not problems else None), problems


# ------------------------------------------------------------------------------------ section 6 attempt rule

def call_status(sessions):
    """Status of one grading call. `sessions`: one list per session of the replies' validity (True/False), in order.

    completed      the last reply is valid and is the only valid one (nothing was asked after it)
    exhausted      3 sessions, each a reply and one reply to the parse-error message, all invalid: the grade is missing
    incomplete     the prescribed attempts are not all made yet (or none was made)
    nonconforming  the attempts break the rule (a new session without the fix-up message, more than 3 sessions,
                   more than 2 replies in a session, an attempt after a valid reply)
    Returns (status, (session index, reply index) of the accepted reply or None).
    """
    if not sessions:
        return "incomplete", None
    if len(sessions) > MAX_SESSIONS:
        return "nonconforming", None
    for s, replies in enumerate(sessions):
        last_session = s == len(sessions) - 1
        if not replies or len(replies) > REPLIES_PER_FAILED_SESSION:
            return "nonconforming", None
        for i, ok in enumerate(replies):
            if ok:
                if not last_session or i != len(replies) - 1:
                    return "nonconforming", None
                return "completed", (s, i)
        if len(replies) < REPLIES_PER_FAILED_SESSION and not last_session:
            return "nonconforming", None
    if len(sessions) == MAX_SESSIONS and all(len(r) == REPLIES_PER_FAILED_SESSION for r in sessions):
        return "exhausted", None
    return "incomplete", None


def next_step(sessions):
    """What the grading runner does next: accept, fix-up (send the parse error in the same session), new-session or
    missing (record the grade as missing). Raises ValueError for nonconforming attempts."""
    status, _ = call_status(sessions)
    if status == "completed":
        return "accept"
    if status == "exhausted":
        return "missing"
    if status == "nonconforming":
        raise ValueError("the recorded attempts break PROTOCOL.md section 6")
    if not sessions or len(sessions[-1]) == REPLIES_PER_FAILED_SESSION:
        return "new-session"
    return "fix-up"
