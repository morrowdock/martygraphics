# SPDX-License-Identifier: Apache-2.0
"""Check the shared semantic fixtures under docs/fixtures/semantics on a machine without Swift.

Each `*.expected.json` names one input and a list of expectations. An expectation says how far
Python can go: `checked` (the draft preflight in tools/scene_v1_check.py reproduces it),
`model` (a small Python model of one Swift function reproduces it), `observed` (behavior is
undecided; the Python result is recorded, not endorsed) or `none` (needs Swift). This runner
never runs Swift, so every Swift-facing expectation stays `pending-mac`. Agreement here is not
parity evidence.
"""

import argparse
import json
import math
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
import scene_v1_check as preflight  # noqa: E402  (copied from feat/scene-v1-json-schema @ c2269d7)

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "docs/fixtures/semantics"
FORMAT = "mg-semantics-expected/1"
TOP_KEYS = {"format", "input", "entry", "about", "expect"}
ENTRY_KEYS = {"check", "expect", "python", "swift", "note", "observed"}
CHECKS = {"preflight", "outcome", "resolved", "format", "patches", "patches.resolved", "stream.finish",
          "stream.previews", "timeline.items", "timeline.frame", "timeline.cycle", "timeline.blend"}
PYTHON = {"checked", "model", "observed", "none"}
# Python can evaluate these checks; every other check must say python "none".
PYTHON_CAN = {"preflight": {"checked"}, "outcome": {"checked", "observed"}, "format": {"model"},
              "patches": {"model"}, "stream.finish": {"checked", "observed"}}
ENTRIES = {"MGParser.scene(data:)", "MGPhysics.format(_:unit:)", "MGScene.applying(_:)",
           "MGStreamParser.feed(_:)/finish()", "MGTimeline"}
PATCH_OPS = {"params": {"params"}, "add": {"item"}, "remove": {"id"}, "set": {"id", "key", "value"},
             "steps": {"steps"}, "step": {"index"}, "camera": {"camera"}, "title": {"title"}, "dim": {"dim"}}
PATCH_BYTES = 4 * 1024
STEPS = 8


class Mismatch(AssertionError):
    pass


def materialize(spec, base):
    """Input bytes: a sibling file name, or inline {"utf8": text, "padToBytes": n} / {"hex": digits}."""
    if isinstance(spec, str):
        path = (base / spec).resolve()
        if not path.is_relative_to(FIXTURES) or not path.is_file():
            raise Mismatch(f"input {spec!r} is not a fixture file")
        return path.read_bytes(), path
    if not isinstance(spec, dict) or not spec.keys() <= {"utf8", "hex", "padToBytes"} or len(spec.keys() & {"utf8", "hex"}) != 1:
        raise Mismatch("inline input needs exactly one of utf8 or hex, and optional padToBytes")
    data = spec["utf8"].encode("utf-8") if "utf8" in spec else bytes.fromhex(spec["hex"])
    pad = spec.get("padToBytes")
    if pad is not None:
        if type(pad) is not int or pad < len(data):
            raise Mismatch("padToBytes must be an integer at least the input length")
        data += b" " * (pad - len(data))
    return data, None


def run_preflight(data, packs=()):
    try:
        template = preflight.check(data, packs=packs)
    except preflight.Invalid as error:
        return {"result": "fail", "reason": str(error)}
    return {"result": "pass-deferred", "template": template} if template else {"result": "pass"}


def as_outcome(result):
    if result["result"] == "pass":
        return {"result": "accept"}
    if result["result"] == "fail":
        return {"result": "reject", "reason": result["reason"]}
    raise Mismatch("template expansion is deferred to Swift; use a preflight check instead")


# MGPhysics.format(_:unit:): a Python model of the Swift source, not the Swift code.
def model_format(value, unit):
    if not math.isfinite(value):
        return "—"
    magnitude = abs(value)
    digits = 0 if magnitude >= 100 else 1 if magnitude >= 10 else 2
    text = "%.*f" % (digits, value)
    if "." in text:
        text = text.rstrip("0").rstrip(".")
    if text == "-0":
        text = "0"
    return text if not unit else text + unit if unit == "°" else text + " " + unit


# MGPatch.parse + MGScene.applying for literal scenes: a Python model, with the draft preflight
# standing in for the Swift re-parse. Template scenes are out of scope for the model.
class PatchError(Exception):
    pass


def number(value):
    return type(value) in (int, float)


def closed(obj, required, optional, what):
    if not required <= obj.keys():
        raise PatchError(what + ".missing")
    unknown = obj.keys() - required - optional
    if unknown:
        raise PatchError(what + ".unknown." + ",".join(sorted(unknown)))


def op_shape(op):
    if not isinstance(op, dict) or not isinstance(op.get("op"), str):
        raise PatchError("patch.op")
    name = op["op"]
    if name not in PATCH_OPS:
        raise PatchError("patch.op." + name)
    closed(op, PATCH_OPS[name] | {"op"}, set(), "patch." + name)
    if name == "step":
        index = op["index"]
        if not number(index) or not 0 <= index <= STEPS - 1 or index != int(index):
            raise PatchError("patch.step")


def refuse_constant(name):
    raise ValueError("non-finite JSON constant " + name)


def parse_patch(entry):
    if isinstance(entry, dict) and entry.keys() == {"utf8"}:
        data = entry["utf8"].encode("utf-8")
        if len(data) > 2 * PATCH_BYTES:
            raise PatchError("patch.json")
        try:
            preflight.check_depth(data.decode("utf-8"))
            obj = json.loads(data, parse_constant=refuse_constant)
        except preflight.Invalid as error:
            raise PatchError("patch.depth" if str(error) == "scene.depth" else "patch.json") from error
        except ValueError as error:
            raise PatchError("patch.json") from error
    else:
        obj = entry
    canonical = json.dumps(obj, ensure_ascii=False, separators=(",", ":"), sort_keys=True).encode("utf-8")
    if len(canonical) > PATCH_BYTES or not isinstance(obj, dict):
        raise PatchError("patch.object")
    closed(obj, {"v", "ops"}, {"rev"}, "patch")
    ops = obj["ops"]
    if not (number(obj["v"]) and obj["v"] == 1) or not isinstance(ops, list) or not 1 <= len(ops) <= 12:
        raise PatchError("patch.ops")
    for op in ops:
        op_shape(op)
    base = None
    if "rev" in obj:
        rev = obj["rev"]
        if not number(rev) or not 0 <= rev <= 1_000_000 or rev != int(rev):
            raise PatchError("patch.rev")
        base = int(rev)
    return ops, base


def apply_patch(root, revision, ops, base):
    if "template" in root:
        raise Mismatch("the Python patch model covers literal scenes only")
    if base is not None and base != revision:
        raise PatchError("patch.stale")
    root = json.loads(json.dumps(root))
    jump = None
    for op in ops:
        name = op["op"]
        items = root.get("items") if isinstance(root.get("items"), list) else []
        if name == "params":
            raise PatchError("patch.params")
        if name == "add":
            root["items"] = items + [op["item"]]
        elif name == "remove":
            if not isinstance(op["id"], str):
                raise PatchError("patch.remove")
            index = next((i for i, item in enumerate(items) if isinstance(item, dict) and item.get("id") == op["id"]), None)
            if index is None:
                raise PatchError("patch.remove.ref")
            root["items"] = items[:index] + items[index + 1:]
        elif name == "set":
            if not (isinstance(op["id"], str) and isinstance(op["key"], str)):
                raise PatchError("patch.set")
            index = next((i for i, item in enumerate(items) if isinstance(item, dict) and item.get("id") == op["id"]), None)
            if index is None:
                raise PatchError("patch.set.ref")
            if op["key"] in ("id", "k"):
                raise PatchError("patch.set.key")
            item = dict(items[index])
            item[op["key"]] = op["value"]
            if op["key"] == "on":
                item.pop("from", None)
            if op["key"] == "from" and item.get("k") == "vector":
                item.pop("on", None)
            root["items"] = items[:index] + [item] + items[index + 1:]
        elif name == "step":
            jump = int(op["index"])
        else:
            root[name] = op[name]
    data = json.dumps(root, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    try:
        preflight.check(data)
    except preflight.Invalid as error:
        raise PatchError(str(error)) from error
    if jump is not None and jump >= max(len(root.get("steps", [])), 1):
        raise PatchError("patch.step.range")
    return root, revision + 1, jump or 0


def model_patches(scene_bytes, patches):
    root = json.loads(scene_bytes)
    preflight.check(scene_bytes)
    revision, start, out = 0, 0, []
    for index, entry in enumerate(patches):
        row = {"patch": index}
        try:
            ops, base = parse_patch(entry)
            root, revision, start = apply_patch(root, revision, ops, base)
            row["result"] = "accept"
        except PatchError as error:
            row.update(result="reject", reason=str(error))
        row.update(revision=revision, title=root.get("title", ""), itemIds=[i["id"] for i in root["items"]], startStep=start)
        out.append(row)
    return out


def check_entry(entry, data, path):
    kind, python = entry["check"], entry["python"]
    if python == "none":
        return "pending"
    if kind == "preflight":
        got = run_preflight(data)
    elif kind == "outcome":
        got = as_outcome(run_preflight(data))
    elif kind == "format":
        got = [model_format(case["value"], case["unit"]) for case in json.loads(data)["cases"]]
    elif kind == "patches":
        patches = json.loads(path.with_name(path.name.replace(".scene.json", ".patches.json")).read_text(encoding="utf-8"))
        got = model_patches(data, patches["patches"])
    elif kind == "stream.finish":
        chunks = json.loads(data)["chunks"]
        got = as_outcome(run_preflight("".join(chunks).encode("utf-8")))
    else:
        raise Mismatch(f"python cannot evaluate {kind}")
    want = entry["observed"] if python == "observed" else entry["expect"]
    if got != want:
        raise Mismatch(f"{kind}: expected {json.dumps(want, ensure_ascii=False)}, Python gave {json.dumps(got, ensure_ascii=False)}")
    return python


def validate_shape(doc):
    if not isinstance(doc, dict) or doc.keys() - TOP_KEYS or not {"format", "input", "entry", "expect"} <= doc.keys():
        raise Mismatch("closed keys: format, input, entry, expect and optional about")
    if doc["format"] != FORMAT or doc["entry"] not in ENTRIES:
        raise Mismatch("unknown format or entry point")
    if not isinstance(doc["expect"], list) or not doc["expect"]:
        raise Mismatch("expect must be a non-empty list")
    for entry in doc["expect"]:
        if not isinstance(entry, dict) or entry.keys() - ENTRY_KEYS or not {"check", "expect", "python", "swift"} <= entry.keys():
            raise Mismatch("expectation keys: check, expect, python, swift and optional note, observed")
        kind, python = entry["check"], entry["python"]
        if kind not in CHECKS or python not in PYTHON:
            raise Mismatch(f"unknown check {kind!r} or python status {python!r}")
        if python != "none" and python not in PYTHON_CAN.get(kind, ()):
            raise Mismatch(f"python cannot be {python!r} for {kind}")
        # Fail closed on parity claims: no Swift run is recorded in this corpus yet.
        swift = "not-applicable" if kind == "preflight" else "pending-mac"
        if entry["swift"] != swift:
            raise Mismatch(f"{kind}: swift must be {swift!r} until a Mac run is recorded")
        if (python == "observed") != ("observed" in entry) or (python == "observed") != (entry["expect"] == "undetermined"):
            raise Mismatch("observed is required exactly when python is 'observed' and expect is 'undetermined'")


def run(verbose=False):
    totals = {"fixtures": 0, "checked": 0, "model": 0, "observed": 0, "pending": 0, "swift-pending": 0}
    failures, referenced = [], set()
    expected_files = sorted(FIXTURES.rglob("*.expected.json"))
    if not expected_files:
        return totals, ["no expected-result files found"]
    for path in expected_files:
        name = path.relative_to(FIXTURES).as_posix()
        try:
            doc = json.loads(path.read_text(encoding="utf-8"))
            validate_shape(doc)
            data, source = materialize(doc["input"], path.parent)
            if source:
                referenced.add(source)
                if source.name.endswith(".scene.json"):
                    sibling = source.with_name(source.name.replace(".scene.json", ".patches.json"))
                    if sibling.exists():
                        referenced.add(sibling)
            for entry in doc["expect"]:
                status = check_entry(entry, data, source or path)
                totals[status] += 1
                totals["swift-pending"] += entry["swift"] == "pending-mac"
            totals["fixtures"] += 1
            if verbose:
                print("ok  ", name)
        except (Mismatch, ValueError, KeyError, TypeError) as error:
            failures.append(f"{name}: {error}")
    inputs = {p.resolve() for p in FIXTURES.rglob("*") if p.is_file() and p.suffix == ".json" and not p.name.endswith(".expected.json")}
    for orphan in sorted(inputs - referenced):
        failures.append(f"{orphan.relative_to(FIXTURES).as_posix()}: input without an expected-result file")
    return totals, failures


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("-v", "--verbose", action="store_true")
    args = parser.parse_args()
    totals, failures = run(args.verbose)
    for failure in failures:
        print("FAIL", failure)
    print(f"{totals['fixtures']} fixtures; expectations: {totals['checked']} reproduced by the Python preflight, "
          f"{totals['model']} by a Python model, {totals['observed']} undecided (Python result recorded), "
          f"{totals['pending']} need Swift. Swift-facing expectations pending a Mac run: {totals['swift-pending']}.")
    print("No Swift was run; this is not parity evidence.")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
