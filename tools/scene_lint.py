# SPDX-License-Identifier: Apache-2.0
"""Authoring lint for v1 scene JSON: common mistakes that the parser accepts but that draw the wrong thing.

    python3 tools/scene_lint.py FILE...

Run it on scenes that already validate (`marty-scene-validate --hints`). Each warning is `code: message`; the codes
are listed in docs/AUTHORING.md under "Common mistakes". The lint never refuses a scene and always exits 0 for
readable files. Geometry follows the engine's conventions (MGLayout, MGCanvasRenderer, MGTimeline).
"""

import json
import math
from pathlib import Path
import sys


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


def extents(item, span):
    """World-space points an item covers, for the outside-the-world check."""
    kind = item["k"]
    if kind == "body":
        x, y = item["at"][:2]
        half = item.get("size", 1) / 2
        return [(x - half, y - half), (x + half, y + half)]
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


def lint(scene):
    """Return a list of `code: message` warnings for one parsed scene."""
    if "items" not in scene or "template" in scene:
        return []
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
                   "make step 0 edit-free to show the starting state")

    states = [items]
    current = dict(by_id)
    for step in steps:
        for edit in step.get("do", []):
            if edit["id"] in current:
                current = {**current, edit["id"]: {**current[edit["id"]], edit["key"]: edit["value"]}}
        states.append(list(current.values()))

    seen = set()
    for state in states:
        for item in state:
            values = []
            if item["k"] == "bars":
                values = [(b["value"], f"bar {b['label']!r}") for b in item["bars"]]
                for b in item["bars"]:
                    if number(b["value"]) and b["value"] < 0 and (item["id"], "neg") not in seen:
                        seen.add((item["id"], "neg"))
                        out.append(f"bars.negative: {item['id']} has a negative value, drawn as a positive height")
            elif item["k"] == "array":
                values = [(v, f"cell {i}") for i, v in enumerate(item["vals"])]
            elif item["k"] == "table":
                values = [(v, f"cell [{r}, {c}]") for r, row in enumerate(item["cells"]) for c, v in enumerate(row)]
            for value, where in values:
                if number(value) and not isinstance(value, bool) and fmt(value) != shortest(value):
                    key = (item["id"], where, value)
                    if key not in seen:
                        seen.add(key)
                        out.append(f"display.rounding: {item['id']} {where} {shortest(value)} is drawn as {fmt(value)}")

    for item in items:
        kind = item["k"]
        if kind == "plot":
            (x0, x1), (y0, y1) = item["xr"], item["yr"]
            outside = [p for p in item["pts"] if not (x0 <= p[0] <= x1 and y0 <= p[1] <= y1)]
            if outside:
                out.append(f"plot.outside: {item['id']} has {len(outside)} point(s) outside xr/yr; they are clipped "
                           "(pts are data coordinates)")
        pts = extents(item, span)
        if any(not (-1e-9 <= x <= w + 1e-9 and -1e-9 <= y <= h + 1e-9) for x, y in pts):
            out.append(f"layout.outside: {item['id']} ({kind}) extends outside the {w:g} x {h:g} world")
        if kind == "line" and item.get("style") == "ground":
            (ax, ay), (bx, by) = item["from"][:2], item["to"][:2]
            length = math.hypot(bx - ax, by - ay) or 1
            side = ((by - ay) / length, -(bx - ax) / length)
            others = [c for c in (centre(o) for o in items if o is not item and o["k"] not in ("highlight", "edge")) if c]
            facing = [c for c in others if (c[0] - ax) * side[0] + (c[1] - ay) * side[1] > 0.05]
            if others and len(facing) > len(others) / 2:
                out.append(f"line.ground.side: {item['id']} hatches toward most of the scene; swap from and to so the "
                           "hatching faces away (draw a ceiling right to left)")
        if kind == "vector" and item.get("len", 0) == 0:
            out.append(f"vector.zero: {item['id']} has len 0 and is not drawn")
        if kind == "body" and "move" in item:
            out.append(f"body.move: {item['id']} glides in a straight line to move.to and back, forever; "
                       "say so if the request implies real motion")

    for index, step in enumerate(steps):
        focus = step.get("focus")
        if focus in by_id and by_id[focus]["k"] == "highlight":
            out.append(f"focus.highlight: step {index} focuses highlight {focus}, which draws no focus ring; "
                       "focus its target instead")
    return out


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
        warnings = lint(scene)
        print(f"{name}: " + ("no warnings" if not warnings else f"{len(warnings)} warning(s)"))
        for warning in warnings:
            print("  " + warning)
    return status


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
