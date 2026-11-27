# SPDX-License-Identifier: Apache-2.0
"""Validate an author's latest attempt for one request and log the validator message.

    python tools/attempt.py RUN ID        # check runs/RUN/ID/attempt-N.json (highest N) and log it
    python tools/attempt.py RUN --status  # one line per request

A RUN whose name starts with `baseline` prints only what the existing tools print: `invalid: <reason>` (plus the two existing
details) for scenes, and the strict report's reason and location for ML documents. Any other RUN
adds the fix hint for the reason and the authoring lint warnings. At most 4 attempts (1 + 3 repairs).
"""

import json
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
EVAL = HERE.parent
sys.path.insert(0, str(EVAL / "vendor" / "tools"))
sys.path.insert(0, str(HERE))

import ml_check  # noqa: E402
import scene_v1_check  # noqa: E402

MAX_ATTEMPTS = 4
BASELINE_DETAILS = {  # SceneValidator.detail(for:) at main 5e4952e
    "template.unknown": "not a built-in template; app-registered packs are not loaded by this tool",
    "input.too-large": "larger than 16384 bytes",
}


def is_ml(data):
    try:
        value = json.loads(data.decode("utf-8"))
    except (UnicodeError, ValueError):
        return False
    return isinstance(value, dict) and value.get("kind") == "ml-explainer"


def validate(data, run):
    """Return (valid, message, reason)."""
    improved = not run.startswith("baseline")
    if is_ml(data):
        try:
            ml_check.check(data)
        except ml_check.Issue as issue:
            report = {"ok": False, "reason": issue.reason, "location": issue.path or None}
            if improved:  # marty-scene-validate --ml-kit --strict --hints adds the reason's hint to the report
                import hints
                report["hint"] = hints.ml_hint(issue.reason)
            return False, json.dumps(report, sort_keys=True, ensure_ascii=False), issue.reason
        except ml_check.Unsupported as error:
            return False, "unsupported by the Python mirror: " + str(error), "mirror.unsupported"
        return True, '{"ok": true}', None
    try:
        template = scene_v1_check.check(data)
    except scene_v1_check.Invalid as error:
        reason = str(error)
        detail = BASELINE_DETAILS.get(reason)
        if reason == "json":
            try:
                json.loads(data.decode("utf-8"))
                detail = "JSON contains a value the scene format cannot hold"
            except (UnicodeError, ValueError):
                detail = "not valid JSON with an object or array at the top level"
        if improved:  # SceneValidator.withHint: the existing detail and the hint, joined with "; "
            import hints
            hint = hints.scene_hint(reason)
            if hint:
                detail = detail + "; " + hint if detail else hint
        return False, "invalid: " + reason + (f" ({detail})" if detail else ""), reason
    scene = json.loads(data.decode("utf-8"))
    facts = [scene.get("dim", "2d"), f"{len(scene.get('items', []))} items", f"{len(scene.get('steps', []))} steps"]
    if template:
        facts.append("template " + template)
    return True, "valid (" + ", ".join(facts) + ")", None


def attempts(run, identifier):
    folder = EVAL / "runs" / run / identifier
    found = sorted(folder.glob("attempt-*.json"), key=lambda p: int(p.stem.split("-")[1]))
    return folder, found


def check_latest(run, identifier):
    folder, found = attempts(run, identifier)
    if not found:
        raise SystemExit(f"no attempt for {identifier} in {folder}")
    latest = found[-1]
    number = int(latest.stem.split("-")[1])
    if number > MAX_ATTEMPTS:
        raise SystemExit(f"{identifier}: attempt {number} exceeds the limit of {MAX_ATTEMPTS}")
    data = latest.read_bytes()
    valid, message, reason = validate(data, run)
    lint = []
    if not run.startswith("baseline") and valid and not is_ml(data):
        sys.path.insert(0, str(EVAL.parents[1] / "tools"))
        import scene_lint
        lint = scene_lint.lint(json.loads(data.decode("utf-8")))
    log_path = folder / "log.json"
    log = json.loads(log_path.read_text(encoding="utf-8")) if log_path.exists() else []
    log = [entry for entry in log if entry["attempt"] != number]
    log.append({"attempt": number, "valid": valid, "reason": reason, "message": message, "lint": lint})
    log.sort(key=lambda entry: entry["attempt"])
    log_path.write_bytes((json.dumps(log, indent=1, ensure_ascii=False) + "\n").encode("utf-8"))
    print(f"{identifier} attempt {number}: {message}")
    for warning in lint:
        print("  lint: " + warning)
    return valid


def status(run):
    requests = json.loads((EVAL / "requests.json").read_text(encoding="utf-8"))["requests"]
    for request in requests:
        folder, found = attempts(run, request["id"])
        log_path = folder / "log.json"
        log = json.loads(log_path.read_text(encoding="utf-8")) if log_path.exists() else []
        last = log[-1] if log else None
        state = "none" if not last else ("valid" if last["valid"] else "invalid: " + str(last["reason"]))
        print(f"{request['id']}: {len(found)} attempt(s), {state}")


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    if len(sys.argv) == 3 and sys.argv[2] == "--status":
        status(sys.argv[1])
    elif len(sys.argv) == 3:
        check_latest(sys.argv[1], sys.argv[2])
    else:
        raise SystemExit(__doc__)
