# SPDX-License-Identifier: Apache-2.0
"""Recompute the eval's author-independent counts from checked-in files.

    python3 evals/dev-authoring/tools/inventory.py           # print the counts
    python3 evals/dev-authoring/tools/inventory.py --write   # rewrite inventories/scene-reasons.json

The counts do not depend on who authored the runs:

- conventions: matches of the 17 text probes in `inventories/conventions.json` against the baseline prose (read
  with `git show` at the recorded base and checked against `guidance/baseline/MANIFEST.json`) and against the
  current prose. A probe miss does not prove that a convention is absent;
- scene reasons: the sample tokens in `inventories/scene-reasons.json` (every static `MGParser` reason, those of its
  `sliders` extension in `MGSliders.swift` included, the item missing/unknown families of every kind, every
  kind-field family, ten dynamic forms and the slider reasons built from a key, an id or a func reason), how many
  the baseline validator gave extra text, and how many have a fix hint now;
- ML reasons: every `MGMLReason` case, and how many have a hint;
- lint: `tools/scene_lint.py` on the final scene of every run.
"""

import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

HERE = Path(__file__).resolve().parent
EVAL = HERE.parent
ROOT = EVAL.parents[1]
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(ROOT / "tools"))

import hints  # noqa: E402
import scene_lint  # noqa: E402

CONVENTIONS = EVAL / "inventories" / "conventions.json"
SCENE_REASONS = EVAL / "inventories" / "scene-reasons.json"
# Reasons the baseline validator (tools/SceneValidator at 5e4952e, SceneValidator.swift:153, :167 and :172) printed
# with extra detail text. None of them is a fix hint; they are counted as the baseline's only extra wording.
BASELINE_DETAILS = ["input.too-large", "json", "template.unknown"]
DYNAMIC_SAMPLES = ["title.placeholder.n", "step.say.brace", "item.label.placeholder", "edit.key.zz", "id.duplicate.a",
                   "scene.unknown.zz", "world.unknown.zz", "step.unknown.zz", "camera.unknown.zz", "3d.kind.table"]
# Slider reasons that are not `MGError` literals in MGSliders.swift: the closed-key, number and text helpers'
# reasons, and the forms built from a parameter, a func id or a func reason (one sample each).
SLIDER_SAMPLES = ["slider.missing", "slider.unknown.zz", "slider.duplicate.a", "slider.min", "slider.max", "slider.label",
                  "slider.default.f", "slider.a.min.func.detail", "slider.b.max.func.mark"]


def scene_reason_sample():
    """The sample tokens: static parser reasons (MGParser.swift and its sliders extension), per-kind families and
    dynamic forms (one sample each)."""
    parser = "".join((ROOT / "Sources/MartyGraphics" / name).read_text(encoding="utf-8")
                     for name in ("MGParser.swift", "MGSliders.swift"))
    reasons = set(re.findall(r'MGError\("([a-z0-9.\-]+)"\)', parser)) | {"json", "input.too-large", "scene.missing"}
    for name, extra, _ in hints.KINDS:
        name = hints.wire(name)
        reasons |= {f"item.{name}.missing", f"item.{name}.unknown.zz"}
        reasons |= {f"{name}.{key}" for key in extra if key != "label"}
    return sorted(reasons | set(DYNAMIC_SAMPLES) | set(SLIDER_SAMPLES))


def ml_reasons():
    source = (ROOT / "Sources/MartyGraphicsMLKit/MGMLKit.swift").read_text(encoding="utf-8")
    enum = source[source.index("public enum MGMLReason"):source.index("extension MGMLReason")]
    return re.findall(r'case \w+ = "([^"]+)"', enum)


def normalise(text):
    return re.sub(r"\s+", " ", text.lower().replace("`", "").replace("*", ""))


def baseline_text(inventory):
    """Baseline prose at the recorded base, hash-checked against the baseline manifest. None without git history."""
    manifest = json.loads((EVAL / "guidance/baseline/MANIFEST.json").read_text(encoding="utf-8"))
    hashes = {entry["path"]: entry["sha256"] for entry in manifest["files"]}
    parts = []
    for path in inventory["baselineDocs"]:
        try:
            blob = subprocess.run(["git", "-C", str(ROOT), "show", f"{inventory['baselineBase']}:{path}"],
                                  check=True, capture_output=True).stdout
        except (OSError, subprocess.CalledProcessError):
            return None
        if hashlib.sha256(blob).hexdigest() != hashes[path]:
            raise SystemExit(f"{path} at the base does not match guidance/baseline/MANIFEST.json")
        parts.append(blob.decode("utf-8"))
    return normalise("\n".join(parts))


def current_text(inventory):
    return normalise("\n".join((ROOT / path).read_text(encoding="utf-8") for path in inventory["currentDocs"]))


def probe_matches(inventory, text):
    return {c["id"]: any(re.search(p, text) for p in c["probes"]) for c in inventory["conventions"]}


def final_scenes(run):
    for directory in sorted((EVAL / "runs" / run).iterdir()):
        attempts = sorted(directory.glob("attempt-*.json"), key=lambda p: int(p.stem.split("-")[1]))
        if directory.is_dir() and attempts:
            scene = json.loads(attempts[-1].read_text(encoding="utf-8"))
            if "kind" not in scene:  # ML documents are not scenes
                yield directory.name, scene


def lint_counts(run):
    counts = {"scenes": 0, "notChecked": [], "warnings": 0, "cues": 0, "flagged": {}}
    for name, scene in final_scenes(run):
        counts["scenes"] += 1
        found = scene_lint.report(scene)
        if any(s.startswith(("template scene", "3D scene", "no items")) for s in found["skipped"]):
            counts["notChecked"].append(name)
        counts["warnings"] += len(found["warnings"])
        counts["cues"] += len(found["cues"])
        codes = sorted({f.split(":", 1)[0] for f in found["warnings"] + found["cues"]})
        if codes:
            counts["flagged"][name] = codes
    return counts


def summary():
    inventory = json.loads(CONVENTIONS.read_text(encoding="utf-8"))
    base = baseline_text(inventory)
    sample = json.loads(SCENE_REASONS.read_text(encoding="utf-8"))["tokens"]
    ml = ml_reasons()
    return {
        "conventions": {
            "total": len(inventory["conventions"]),
            "baseline": None if base is None else sum(probe_matches(inventory, base).values()),
            "current": sum(probe_matches(inventory, current_text(inventory)).values()),
        },
        "sceneReasons": {
            "tokens": len(sample),
            "baselineDetails": sum(1 for token in sample if token in BASELINE_DETAILS),
            "hinted": sum(1 for token in sample if hints.scene_hint(token)),
        },
        "mlReasons": {"total": len(ml), "baseline": 0, "hinted": sum(1 for r in ml if hints.ml_hint(r))},
        "lint": {run: lint_counts(run) for run in ("baseline", "improved")},
    }


def main(argv):
    if "--write" in argv:
        data = {"about": "Scene refusal reason sample tokens, rebuilt by tools/inventory.py --write from MGParser.swift "
                         "and the kind tables. A family such as item.<kind>.unknown.<keys> has one sample token (zz).",
                "baselineDetails": BASELINE_DETAILS,
                "tokens": scene_reason_sample()}
        SCENE_REASONS.write_bytes((json.dumps(data, indent=1) + "\n").encode("utf-8"))
    json.dump(summary(), sys.stdout, indent=1, sort_keys=True)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main(sys.argv[1:])
