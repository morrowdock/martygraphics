# SPDX-License-Identifier: Apache-2.0
"""Authoring lint for v1 scene JSON: common mistakes that the parser accepts but that draw the wrong thing.

    python3 tools/scene_lint.py FILE...

Run it on scenes that already validate (`marty-scene-validate --hints`). Each finding is `code: message`; the codes
are listed in docs/AUTHORING.md under "Common mistakes". The lint never refuses a scene and always exits 0 for
readable files. Geometry follows the 2D engine's conventions (MGLayout, MGCanvasRenderer, MGTimeline).

Findings come in two classes. A *warning* is a mechanical fact (an item off the board, a number drawn with other
digits). A *review cue* (`REVIEW_CUES`) is a pattern that is often a mistake but can be intended, such as edits in
step 0 or the hatching side of a ground line; read the scene before changing it.

Supported subset: full 2D scenes. Every check except the step 0 and focus checks runs on each step as it is shown,
as MGTimeline.items resolves it: the edits of steps 0..k applied in order, items first shown later left out, and a
vector, highlight or edge whose anchor is hidden left out too. Box rotation and a body's
`move` target count towards its extent. Not checked, and reported under "not checked": template scenes (the
template builds its own items), 3D scenes, the drawn width of text items (only their anchor point is checked) and
the drawn position of vectors anchored with `on` (it depends on the anchor's edge and the renderer's fan-out).
"""

import json
import math
from pathlib import Path
import sys

REVIEW_CUES = {"step0.edits", "line.ground.side", "body.move"}


def fmt(value):
    """MGPhysics.format(v, unit: ""): the text a number cell or bar value is drawn with."""
    a = abs(value)
    digits = 0 if a >= 100 else 1 if a >= 10 else 2
    text = f"{value:.{digits}f}"
    if "." in text:
        text = text.rstrip("0").rstrip(".")
    return "0" if text == "-0" else text


def shortest(value):
    return str(int(value)) if float(value).is_integer() else repr(float(value))


def number(value):
    return type(value) in (int, float)


def box(x, y, half, angle=0.0):
    """Axis-aligned bounds of a square of half side `half` centred at (x, y), rotated by `angle` degrees."""
    a = math.radians(angle)
    reach = half * (abs(math.cos(a)) + abs(math.sin(a)))
    return [(x - reach, y - reach), (x + reach, y + reach)]


def extents(item, span):
    """World-space points an item covers, for the outside-the-world check. Empty when the lint does not place it."""
    kind = item["k"]
    if kind == "body":
        x, y = item["at"][:2]
        half = item.get("size", 1) / 2
        angle = 0 if item.get("shape") == "ball" else item.get("angle", 0)
        pts = box(x, y, half, angle)
        if "move" in item:
            pts += box(item["move"]["to"][0], item["move"]["to"][1], half, angle)
        return pts
    if kind == "node":
        x, y = item["at"][:2]
        r = item.get("r", min(0.5, span / 6))
        return [(x - r, y - r), (x + r, y + r)]
    if kind in ("pulley", "orbit"):
        x, y = item["at"][:2]
        return [(x - item["r"], y - item["r"]), (x + item["r"], y + item["r"])]
    if kind in ("axes", "plot", "bars"):
        x, y = item["at"][:2]
        return [(x, y), (x + item["w"], y + item["h"])]
    if kind == "array":
        x, y = item["at"][:2]
        cell = item.get("cell", min(1, span / 4))
        half = cell * len(item["vals"]) / 2
        return [(x - half, y - cell / 2), (x + half, y + cell / 2)]
    if kind == "table":
        x, y = item["at"][:2]
        rows, cols = len(item["cells"]), len(item["cells"][0])
        w, h = item.get("cw", min(1.6, span / 3)) * cols / 2, item.get("rh", min(0.7, span / 6)) * rows / 2
        return [(x - w, y - h), (x + w, y + h)]
    if kind == "incline":
        x, y = item["at"][:2]
        b = item["base"]
        return [(x, y), (x + b, y + b * math.tan(math.radians(item["angle"])))]
    if kind == "text":
        return [tuple(item["at"][:2])]
    if kind in ("line", "spring"):
        return [tuple(item["from"][:2]), tuple(item["to"][:2])]
    if kind in ("rope", "path", "region"):
        return [tuple(p[:2]) for p in item["pts"]]
    if kind == "vector" and "from" in item:
        x, y = item["from"][:2]
        a = math.radians(item.get("angle", 0))
        return [(x, y), (x + item["len"] * math.cos(a), y + item["len"] * math.sin(a))]
    return []


def centre(item):
    pts = extents(item, 12)
    if not pts:
        return None
    return (sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts))


def apply_edit(item, key, value):
    """MGParser.applying: the value replaces the whole field; a vector's `on` and `from` exclude each other."""
    out = {**item, key: value}
    if item["k"] == "vector" and key == "on":
        out.pop("from", None)
    if item["k"] == "vector" and key == "from":
        out.pop("on", None)
    return out


def anchors(item):
    """The ids an item needs visible to be drawn (MGTimeline.items: vector `on`, highlight target, edge ends)."""
    if item["k"] == "vector":
        return [item["on"]] if "on" in item else []
    if item["k"] == "highlight":
        return [item.get("target")]
    if item["k"] == "edge":
        return [item.get("a"), item.get("b")]
    return []


def visible(items):
    """Drop, transitively, every vector, highlight or edge whose anchor is not visible (MGTimeline.items)."""
    while True:
        ids = {item["id"] for item in items}
        kept = [item for item in items if all(a in ids for a in anchors(item))]
        if len(kept) == len(items):
            return kept
        items = kept


def shown_states(scene):
    """(step index, visible items) for each frame the viewer sees; (None, items) for a scene without steps.

    Mirrors MGTimeline.items(_:step:): the edits of steps 0...k applied in order, items first listed in a later
    `show` removed, then items whose anchor is hidden removed too.
    """
    items = scene["items"]
    steps = scene.get("steps", [])
    if not steps:
        return [(None, visible(list(items)))]
    first = {}
    for index, step in enumerate(steps):
        for identifier in step.get("show", []):
            first.setdefault(identifier, index)
    current = {item["id"]: item for item in items}
    states = []
    for index, step in enumerate(steps):
        for edit in step.get("do", []):
            if edit["id"] in current:
                current[edit["id"]] = apply_edit(current[edit["id"]], edit["key"], edit["value"])
        states.append((index, visible([item for item in current.values() if first.get(item["id"], 0) <= index])))
    return states


def at_step(index):
    return "" if index is None else f" at step {index}"


def report(scene):
    """Return {"warnings", "cues", "skipped"}: lists of `code: message` findings and of inputs not checked."""
    found = {"warnings": [], "cues": [], "skipped": []}
    if "template" in scene:
        found["skipped"].append("template scene: the template builds its own items and steps, so neither they nor "
                                "any extra items are checked")
        return found
    if scene.get("dim") == "3d":
        found["skipped"].append("3D scene: the lint checks 2D geometry only")
        return found
    if not isinstance(scene.get("items"), list):
        found["skipped"].append("no items list: not a full scene")
        return found

    out = []
    world = scene.get("world", {"w": 12, "h": 8})
    w, h = world["w"], world["h"]
    span = max(w, h)
    items = scene["items"]
    by_id = {item["id"]: item for item in items}
    steps = scene.get("steps", [])

    if steps and steps[0].get("do"):
        edited = sorted({edit["id"] for edit in steps[0]["do"]})
        out.append(f"step0.edits: step 0 edits {', '.join(edited)}, so their authored state is never shown; "
                   "make step 0 edit-free if the starting state should be seen")

    seen = set()
    texts, anchored = {}, {}  # ordered sets of ids drawn at some step
    for index, state in shown_states(scene):
        for item in state:
            kind = item["k"]
            values = []
            if kind == "bars":
                values = [(b["value"], f"bar {b['label']!r}") for b in item["bars"]]
                for b in item["bars"]:
                    if number(b["value"]) and b["value"] < 0 and (item["id"], "neg") not in seen:
                        seen.add((item["id"], "neg"))
                        out.append(f"bars.negative: {item['id']} has a negative value{at_step(index)}, "
                                   "drawn as a positive height")
            elif kind == "array":
                values = [(v, f"cell {i}") for i, v in enumerate(item["vals"])]
            elif kind == "table":
                values = [(v, f"cell [{r}, {c}]") for r, row in enumerate(item["cells"]) for c, v in enumerate(row)]
            for value, where in values:
                if number(value) and not isinstance(value, bool) and fmt(value) != shortest(value):
                    key = (item["id"], where, value)
                    if key not in seen:
                        seen.add(key)
                        out.append(f"display.rounding: {item['id']} {where} {shortest(value)} is drawn as {fmt(value)}")
            if kind == "plot" and (item["id"], "plot") not in seen:
                (x0, x1), (y0, y1) = item["xr"], item["yr"]
                outside = [p for p in item["pts"] if not (x0 <= p[0] <= x1 and y0 <= p[1] <= y1)]
                if outside:
                    seen.add((item["id"], "plot"))
                    out.append(f"plot.outside: {item['id']} has {len(outside)} point(s) outside xr/yr{at_step(index)}; "
                               "they are clipped (pts are data coordinates)")
            pts = extents(item, span)
            if (item["id"], "layout") not in seen and any(
                    not (-1e-9 <= x <= w + 1e-9 and -1e-9 <= y <= h + 1e-9) for x, y in pts):
                seen.add((item["id"], "layout"))
                out.append(f"layout.outside: {item['id']} ({kind}) extends outside the {w:g} x {h:g} world{at_step(index)}")

            if kind == "line" and item.get("style") == "ground" and (item["id"], "ground") not in seen:
                (ax, ay), (bx, by) = item["from"][:2], item["to"][:2]
                length = math.hypot(bx - ax, by - ay) or 1
                side = ((by - ay) / length, -(bx - ax) / length)
                others = [c for c in (centre(o) for o in state if o is not item and o["k"] not in ("highlight", "edge"))
                          if c]
                facing = [c for c in others if (c[0] - ax) * side[0] + (c[1] - ay) * side[1] > 0.05]
                if others and len(facing) > len(others) / 2:
                    seen.add((item["id"], "ground"))
                    out.append(f"line.ground.side: {item['id']} hatches toward most of the scene{at_step(index)}; if it "
                               "is a ceiling, swap from and to so the hatching faces away (draw a ceiling right to left)")
            if kind == "vector" and item.get("len", 0) == 0 and (item["id"], "zero") not in seen:
                seen.add((item["id"], "zero"))
                out.append(f"vector.zero: {item['id']} has len 0{at_step(index)} and is not drawn")
            if kind == "body" and "move" in item and (item["id"], "move") not in seen:
                seen.add((item["id"], "move"))
                out.append(f"body.move: {item['id']} glides in a straight line to move.to and back, forever; "
                           "say so if the request implies real motion")
            if kind == "text":
                texts.setdefault(item["id"])
            if kind == "vector" and "on" in item:
                anchored.setdefault(item["id"])

    for index, step in enumerate(steps):
        focus = step.get("focus")
        if focus in by_id and by_id[focus]["k"] == "highlight":
            out.append(f"focus.highlight: step {index} focuses highlight {focus}, which draws no focus ring; "
                       "focus its target instead")

    for finding in out:
        found["cues" if finding.split(":", 1)[0] in REVIEW_CUES else "warnings"].append(finding)
    if texts:
        found["skipped"].append(f"the drawn width of text {', '.join(texts)} (only the anchor point is checked)")
    if anchored:
        found["skipped"].append(f"the drawn position of vectors on an item: {', '.join(anchored)}")
    return found


def lint(scene):
    """All findings (warnings, then review cues) as `code: message` strings, for one parsed scene."""
    found = report(scene)
    return found["warnings"] + found["cues"]


def main(argv):
    sys.stdout.reconfigure(encoding="utf-8")
    if len(argv) < 2:
        print(__doc__.strip().splitlines()[2].strip(), file=sys.stderr)
        return 2
    status = 0
    for name in argv[1:]:
        try:
            scene = json.loads(Path(name).read_text(encoding="utf-8"))
        except (OSError, ValueError) as error:
            print(f"{name}: unreadable: {error}")
            status = 3
            continue
        found = report(scene)
        counts = [f"{len(found['warnings'])} warning(s)", f"{len(found['cues'])} review cue(s)"]
        if found["skipped"]:
            counts.append(f"{len(found['skipped'])} not checked")
        print(f"{name}: " + ", ".join(counts))
        for warning in found["warnings"]:
            print("  warning: " + warning)
        for cue in found["cues"]:
            print("  review cue: " + cue)
        for skipped in found["skipped"]:
            print("  not checked: " + skipped)
    return status


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
