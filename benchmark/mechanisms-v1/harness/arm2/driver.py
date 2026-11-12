# SPDX-License-Identifier: Apache-2.0
"""Protocol section 5 driver; questions are supplied at run time, never discovered."""

import argparse
import base64
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time

HARNESS = Path(__file__).resolve().parents[1]
BENCH = HARNESS.parent
sys.path.insert(0, str(HARNESS / "shim"))
from record import record


def locked_prompt(lock, name):
    pin = lock["arm2"][name]
    data = (BENCH / pin["path"]).read_bytes()
    if hashlib.sha256(data).hexdigest() != pin["sha256"]:
        raise ValueError("locked prompt hash mismatch: " + name)
    return data.decode("utf-8")


def reply_text(data):
    events = [json.loads(line) for line in data.decode("utf-8").splitlines() if line.strip()]
    results = [event for event in events if event.get("type") == "result"]
    if len(results) != 1 or results[0].get("is_error") or not isinstance(results[0].get("result"), str):
        raise ValueError("Claude stream must contain one successful text result")
    return results[0]["result"]


class Author:
    def __init__(self, executable, root, system, model):
        self.executable, self.root, self.system, self.model = executable, root, system, model

    def __call__(self, blocks, timeout):
        with tempfile.TemporaryDirectory(prefix="arm2-empty-") as work, \
                tempfile.TemporaryDirectory(prefix="arm2-prompt-") as context:
            prompt = Path(context) / "system.txt"
            prompt.write_bytes(self.system.encode("utf-8"))
            arguments = ["-p", "--model", self.model, "--tools", "", "--strict-mcp-config",
                         "--disable-slash-commands", "--setting-sources", "", "--no-session-persistence",
                         "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
                         "--system-prompt-file", str(prompt)]
            request = (json.dumps({"type": "user", "message": {"role": "user", "content": blocks}},
                                  ensure_ascii=False) + "\n").encode("utf-8")
            with tempfile.TemporaryFile() as incoming, tempfile.TemporaryFile() as outgoing, \
                    tempfile.TemporaryFile() as errors:
                incoming.write(request)
                incoming.seek(0)
                code = record(self.executable, arguments, self.root, timeout,
                              stdin=incoming, stdout=outgoing, stderr=errors, cwd=work)
                if code:
                    raise ValueError("recorded author process failed: exit " + str(code))
                outgoing.seek(0)
                return reply_text(outgoing.read())


class Renderer:
    def __init__(self, binary, tarball):
        self.binary, self.tarball = str(Path(binary).resolve()), str(Path(tarball).resolve())

    def __call__(self, html, output, timeout):
        result = subprocess.run([self.binary, "--html", str(html), "--out", str(output),
                                 "--three-tarball", self.tarball, "--lock", str(BENCH / "LOCK.json")],
                                capture_output=True, timeout=timeout)
        (output.parent / "renderer.stdout").write_bytes(result.stdout)
        (output.parent / "renderer.stderr").write_bytes(result.stderr)
        if result.returncode == 124:
            return error_report("300 s render timeout", output)
        report = json.loads((output / "report.json").read_bytes())
        if result.returncode and not report["harnessErrors"]:
            report["harnessErrors"].append("renderer exited " + str(result.returncode))
        return report


def repair_blocks(template, question, html, number, report, output):
    indices = report.get("stillIndices", [30, 90, 150, 210, 270])
    fields = {"question": question, "html": html, "n": number, "left": 4 - number,
              "harness_errors": json.dumps(report["harnessErrors"], ensure_ascii=False),
              "exceptions": json.dumps(report.get("exceptions", []), ensure_ascii=False),
              "console": json.dumps(report.get("console", [])[:50], ensure_ascii=False)}
    fields.update({"t" + str(index + 1): format(frame / 30, ".12g") for index, frame in enumerate(indices)})
    blocks = [{"type": "text", "text": template.format(**fields)}]
    for path in report["stills"]:
        blocks.append({"type": "image", "source": {"type": "base64", "media_type": "image/png",
                       "data": base64.b64encode((output / path).read_bytes()).decode("ascii")}})
    if len(blocks) != 6:
        raise ValueError("repair requires exactly five image blocks")
    return blocks


def error_report(message, output):
    sys.path.insert(0, str(HARNESS))
    from pack import png
    output.mkdir(exist_ok=True)
    paths = ["still-" + str(number) + ".png" for number in range(1, 6)]
    for name in paths:
        png(output / name, bytes((255, 255, 255)) * (1280 * 800))
    report = {"complete": False, "harnessErrors": [message], "exceptions": [], "console": [],
              "stills": paths, "stillIndices": [30, 90, 150, 210, 270], "allBlank": True,
              "placeholderStills": True, "frames": []}
    events = output / "events.ndjson"
    if events.exists():
        for line in events.read_bytes().splitlines():
            try:
                event = json.loads(line)
                report["exceptions" if event["kind"] == "exception" else "console"].append(event["value"])
            except (ValueError, KeyError, TypeError):
                report["harnessErrors"].append("incomplete console event")
    (output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    return report


def run(question, root, author, renderer, repair, clock=time.monotonic):
    root.mkdir(parents=True, exist_ok=False)
    deadline = clock() + 3600
    state = {"kind": "mechanisms-v1.arm2-run/1", "status": "failed", "calls": 0, "tries": [],
             "accepted": False, "questionSha256": hashlib.sha256(question.encode("utf-8")).hexdigest(),
             "startedUTC": datetime.now(timezone.utc).isoformat()}
    blocks = [{"type": "text", "text": question}]
    final = None

    def remaining(limit):
        budget = deadline - clock()
        if budget <= 0:
            raise TimeoutError("60-minute whole-run limit")
        return min(limit, budget)

    try:
        for number in range(1, 5):
            state["calls"] += 1
            text = author(blocks, remaining(900))
            remaining(900)
            (root / ("reply-" + str(number) + ".txt")).write_bytes(text.encode("utf-8"))
            if number > 1 and text == "ACCEPT":
                state["accepted"] = True
                break
            attempt = root / ("try-" + str(number))
            attempt.mkdir()
            output = attempt / "render"
            matches = re.findall(r"```html\s*\n(.*?)```", text, flags=re.S)
            html = matches[0] if matches else ""
            source = attempt / "page.html"
            source.write_bytes(html.encode("utf-8"))
            if not matches:
                final = error_report("No ```html code block found.", output)
            else:
                try:
                    final = renderer(source, output, remaining(300))
                except subprocess.TimeoutExpired:
                    final = error_report("300 s render timeout or whole-run deadline", output)
                except (OSError, ValueError) as error:
                    final = error_report("Renderer error: " + str(error), output)
            state["tries"].append({"number": number, "html": str(source.relative_to(root)),
                                   "report": str((output / "report.json").relative_to(root))})
            state["finalHTML"] = str(source.relative_to(root))
            state["source"] = {"kind": "captures", "paths": [str((output / path).resolve())
                                                               for path in final.get("frames", [])]}
            remaining(300)
            if number < 4:
                blocks = repair_blocks(repair, question, html, number, final, output)
        if final and final["complete"] and not final["harnessErrors"] and not final["allBlank"]:
            state["status"] = "rendered"
    except (OSError, ValueError, TimeoutError, subprocess.SubprocessError) as error:
        state["error"] = str(error)
    state["seconds"] = 3600 - (deadline - clock())
    state["endedUTC"] = datetime.now(timezone.utc).isoformat()
    if state["seconds"] >= 3600:
        state["status"] = "failed"
        state["error"] = "60-minute whole-run limit"
    (root / "run.json").write_text(json.dumps(state, indent=2) + "\n")
    return state


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--question-file", type=Path, required=True, help="UTF-8 text, used without stripping")
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--renderer", type=Path, required=True)
    parser.add_argument("--three-tarball", type=Path, required=True)
    parser.add_argument("--claude", default="claude")
    args = parser.parse_args(argv)
    lock = json.loads((BENCH / "LOCK.json").read_bytes())
    if lock["generator"]["cli"] != "Claude Code 2.1.322" or lock["generator"]["model"] != "claude-opus-5-5":
        parser.error("generator pin mismatch")
    system, repair = locked_prompt(lock, "systemPrompt"), locked_prompt(lock, "repairPrompt")
    root = args.out.resolve()
    author = Author(args.claude, root / "calls", system, lock["generator"]["model"])
    state = run(args.question_file.read_bytes().decode("utf-8"), root, author,
                Renderer(args.renderer, args.three_tarball), repair)
    return 0 if state["status"] == "rendered" else 1


if __name__ == "__main__":
    raise SystemExit(main())
