# SPDX-License-Identifier: Apache-2.0
"""Build the shared repair-hint corpus: reason tokens with the exact hint both implementations must return.

    python3 evals/dev-authoring/tools/hint_corpus.py           # check docs/fixtures/repair-hints/corpus.json
    python3 evals/dev-authoring/tools/hint_corpus.py --write   # rewrite it from the Python mirror

The corpus holds every scene reason sample token (every kind's computed missing/unknown hints included), the graph
and expression reasons outside MGParser.swift, cases where several patterns match and the first one must win,
reasons with no hint, and every ML reason. Python asserts it in tools/tests/test_repair_hints.py;
`RepairHintCorpusTests` (MartyGraphicsTests) and `MLRepairHintCorpusTests` (MartyGraphicsMLKitTests) assert the same
file against Swift on a Mac.
"""

import json
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(HERE))

import hints  # noqa: E402
import inventory  # noqa: E402

CORPUS = ROOT / "docs/fixtures/repair-hints/corpus.json"

# Reasons that more than one pattern matches (or that look like a computed hint): the first matching row wins.
PRECEDENCE = [
    "item.body.unknown.radius", "item.edge.unknown.c", "item.table.unknown.a,b", "item.body.missing",
    "template.bst.values.missing", "template.two_pointers.target.integer", "template.params.depth",
    "template.bst.values", "scene.params.without.template", "scene.unknown.layer2d", "title.placeholder.n",
    "item.label.placeholder", "text.text.placeholder.n", "step.say.brace", "body.move.t", "body.move.to",
    "edit.key.radius", "edit.key", "edit.value", "steps", "step.show", "step.cam", "world.w", "world.unknown.d",
    "camera.zoom", "camera.yaw", "edge.dir", "vector.dir", "plot.pts", "rope.pts", "path.pts", "line.pts",
    "body.at", "line.to", "vector.from", "id.duplicate.dot", "3d.kind.table", "3d.text.code", "video2d.schema",
    "hide.ref", "over.ref",
]
# Reasons built by helpers (MGModel bounds, identifier and text checks, templates, camera) rather than MGError literals.
HELPER_REASONS = ["scene.number", "scene.depth", "scene.bytes", "template.check", "item.id", "item.label", "title",
                  "bars.label", "bars.value", "array.ptr.label", "step.say", "camera.x", "camera.y", "alt", "step.alt"]
# Graph reasons outside MGParser.swift: the drawing checks (MGGraph.checkFunction) and the expression compiler's
# suffixes (MGExpression.compile), one sample per pattern for each of the func and field keys.
GRAPH_REASONS = ["func.detail", "func.breaks", "func.empty", "func.loop", "func.y.var.t", "field.dx.var.t",
                 "func.y.syntax", "field.dy.syntax", "func.y.tokens", "field.dx.tokens", "func.y.depth", "field.dy.depth",
                 "func.y.name", "field.dx.name", "func.y.arity", "field.dy.arity"]
# Reasons without a hint: neither a computed hint nor any pattern applies.
UNKNOWN = ["not.a.reason", "", "body.atx", "item.nokind.missing", "item.body", "lesson.op.add", "mp4: writer failed",
           "patch.stale", "items.count.extra"]
ML_UNKNOWN = ["ml.not.a.reason", "ml", "json"]


def build():
    scene = []
    reasons = set(inventory.scene_reason_sample()) | set(PRECEDENCE) | set(HELPER_REASONS) | set(GRAPH_REASONS)
    for reason in sorted(reasons) + UNKNOWN:
        scene.append({"reason": reason, "hint": hints.scene_hint(reason)})
    ml = [{"reason": reason, "hint": hints.ml_hint(reason) or None} for reason in inventory.ml_reasons() + ML_UNKNOWN]
    return {
        "about": "Shared repair-hint corpus: MGRepairHint.text(for:) and the Python mirror must return hint for "
                 "reason (null: no hint); MGMLReason(rawValue: reason)?.hint likewise. Rebuilt by "
                 "evals/dev-authoring/tools/hint_corpus.py --write.",
        "scene": scene,
        "ml": ml,
    }


def encoded(data):
    return (json.dumps(data, indent=1, ensure_ascii=False) + "\n").encode("utf-8")


def main(argv):
    data = build()
    if "--write" in argv:
        CORPUS.parent.mkdir(parents=True, exist_ok=True)
        CORPUS.write_bytes(encoded(data))
        return 0
    if CORPUS.read_bytes() != encoded(data):
        print(f"{CORPUS} is stale; run with --write", file=sys.stderr)
        return 1
    print(f"{CORPUS}: {len(data['scene'])} scene and {len(data['ml'])} ML reasons match")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
