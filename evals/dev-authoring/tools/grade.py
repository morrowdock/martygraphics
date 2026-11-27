# SPDX-License-Identifier: Apache-2.0
"""Grade a run's final outputs against specs.json, as fixed in SPEC-CONTRACT.md.

    python tools/grade.py RUN            # writes results/RUN.json and prints a summary
    python tools/grade.py RUN --id P01   # one request, with every check

Engine conventions are mirrored from the Swift sources at main 5e4952e: MGTimeline.items (steps and
visibility), MGParser.apply (edits), MGLayout / MGCanvasRenderer (vector, incline, plot, array, table and
bars geometry) and MGPhysics.format (displayed numbers).
"""

from collections import Counter
import itertools
import json
import math
from pathlib import Path
import re
import sys

HERE = Path(__file__).resolve().parent
EVAL = HERE.parent
sys.path.insert(0, str(HERE))

import attempt  # noqa: E402
import ml_check  # noqa: E402

PLACEHOLDERS = {"", "-", "–", "—", "_", ".", "·", "∅", "empty", "null", "nil"}


# ---------- scene model ----------

def fmt(value):
    """MGPhysics.format(v, unit: "")."""
    a = abs(value)
    digits = 0 if a >= 100 else 1 if a >= 10 else 2
    s = f"{value:.{digits}f}"
    if "." in s:
        s = s.rstrip("0").rstrip(".")
    return "0" if s == "-0" else s


def cell_text(value):
    if isinstance(value, bool):
        return str(value)
    if isinstance(value, (int, float)):
        return fmt(float(value))
    return str(value).strip().replace("−", "-")


class Scene:
    def __init__(self, data):
        self.data = data
        self.items = data.get("items", [])
        self.steps = data.get("steps", [])
        world = data.get("world", {"w": 12, "h": 8})
        self.w, self.h = world["w"], world["h"]
        self.span = max(self.w, self.h)
        self.by_id = {item["id"]: item for item in self.items}
        self.states, self.visible = self._timeline()

    def _apply(self, items, edit):
        out = dict(items)
        current = dict(out[edit["id"]])
        current[edit["key"]] = edit["value"]
        if edit["key"] == "on":
            current.pop("from", None)
        if edit["key"] == "from" and current["k"] == "vector":
            current.pop("on", None)
        out[edit["id"]] = current
        return out

    def _timeline(self):
        current = dict(self.by_id)
        if not self.steps:
            return [current], [self._anchor_filter(current, set(current))]
        first = {}
        for index, step in enumerate(self.steps):
            for identifier in step.get("show", []):
                first.setdefault(identifier, index)
        states, visible = [], []
        for index, step in enumerate(self.steps):
            for edit in step.get("do", []):
                if edit["id"] in current:
                    current = self._apply(current, edit)
            states.append(current)
            shown = {i for i in current if first.get(i, 0) <= index}
            visible.append(self._anchor_filter(current, shown))
        return states, visible

    @staticmethod
    def _anchor_filter(items, ids):
        ids = set(ids)
        while True:
            kept = set()
            for identifier in ids:
                item = items[identifier]
                kind = item["k"]
                if kind == "vector" and "on" in item and item["on"] not in ids:
                    continue
                if kind == "highlight" and item.get("target") not in ids:
                    continue
                if kind == "edge" and (item["a"] not in ids or item["b"] not in ids):
                    continue
                kept.add(identifier)
            if kept == ids:
                return ids
            ids = kept

    def first_visible_state(self, identifier):
        for k, ids in enumerate(self.visible):
            if identifier in ids:
                return self.states[k]
        return self.states[0]

    def item(self, identifier, state=None):
        state = state if state is not None else self.first_visible_state(identifier)
        return state.get(identifier)

    # ----- geometry (engine conventions) -----
    def size(self, item):
        return float(item.get("size", 1))

    def radius(self, item):
        kind = item["k"]
        if kind == "body":
            return self.size(item) / 2
        if kind == "node":
            return float(item.get("r", min(0.5, self.span / 6)))
        if kind in ("pulley", "orbit"):
            return float(item["r"])
        return 0.0

    def center(self, item, state=None):
        kind = item["k"]
        if kind in ("body", "node", "pulley", "orbit", "text", "table", "array"):
            return tuple(item["at"][:2])
        if kind in ("line", "spring"):
            return mid(item["from"], item["to"])
        if kind in ("path", "rope", "region"):
            pts = item["pts"]
            return (sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts))
        if kind in ("plot", "axes", "bars"):
            return (item["at"][0] + item["w"] / 2, item["at"][1] + item["h"] / 2)
        if kind == "incline":
            o, b, h = self.incline_geometry(item)
            return ((o[0] * 2 + b) / 2, o[1] + h / 3)
        if kind == "vector":
            return self.vector_tail(item, state)
        return None

    def vector_tail(self, item, state=None):
        if "on" in item:
            state = state if state is not None else self.first_visible_state(item["id"])
            target = state.get(item["on"])
            return tuple(target["at"][:2]) if target else None
        return tuple(item["from"][:2]) if "from" in item else None

    def vector_dir(self, item):
        a = math.radians(float(item.get("angle", 0)))
        return (math.cos(a), math.sin(a))

    def vector_head(self, item, state=None):
        """Drawn tip: a vector `on` a body or node starts at its edge (MGLayout.shaftStart)."""
        tail = self.vector_tail(item, state)
        if tail is None:
            return None
        d = self.vector_dir(item)
        start = 0.0
        if "on" in item:
            state = state if state is not None else self.first_visible_state(item["id"])
            body = state.get(item["on"])
            if body and body["k"] == "node":
                start = self.radius(body)
            elif body and body.get("shape") == "ball":
                start = self.size(body) / 2
            elif body:
                rel = math.radians(float(item.get("angle", 0)) - float(body.get("angle", 0)))
                start = (self.size(body) / 2) / max(abs(math.cos(rel)), abs(math.sin(rel)))
        reach = start + float(item["len"])
        return (tail[0] + d[0] * reach, tail[1] + d[1] * reach)

    def incline_geometry(self, item):
        o = tuple(item["at"][:2])
        b = float(item["base"])
        return o, b, b * math.tan(math.radians(float(item["angle"])))

    def ends(self, item, state=None):
        kind = item["k"]
        if kind in ("line", "spring"):
            return [tuple(item["from"][:2]), tuple(item["to"][:2])]
        if kind in ("path", "rope"):
            return [tuple(item["pts"][0][:2]), tuple(item["pts"][-1][:2])]
        if kind == "vector":
            tail = self.vector_tail(item, state)
            return [tail, self.vector_head(item, state)] if tail else []
        return []

    def anchors(self, item, state=None):
        kind = item["k"]
        if kind in ("body", "node", "pulley", "orbit", "text", "table", "array"):
            return [tuple(item["at"][:2])]
        if kind in ("line", "spring"):
            a, b = tuple(item["from"][:2]), tuple(item["to"][:2])
            return [a, b, mid(a, b)]
        if kind in ("path", "rope", "region"):
            return [tuple(p[:2]) for p in item["pts"]] + [self.center(item)]
        if kind == "vector":
            ends = self.ends(item, state)
            return ends + ([mid(*ends)] if len(ends) == 2 else [])
        if kind in ("plot", "axes", "bars"):
            o = item["at"]
            return [tuple(o[:2]), (o[0] + item["w"], o[1] + item["h"]), self.center(item)]
        if kind == "incline":
            o, b, h = self.incline_geometry(item)
            return [o, (o[0] + b, o[1]), (o[0] + b, o[1] + h)]
        return []

    def plot_world(self, item, xy):
        x0, x1 = item["xr"]
        y0, y1 = item["yr"]
        return (item["at"][0] + item["w"] * (xy[0] - x0) / (x1 - x0),
                item["at"][1] + item["h"] * (xy[1] - y0) / (y1 - y0))

    # ----- text -----
    def label_texts(self):
        out = []
        for state in self.states:
            for item in state.values():
                for key in ("label", "xl", "yl", "unit"):
                    if key in item:
                        out.append(str(item[key]))
                if item["k"] in ("text", "node"):
                    out.append(str(item["text"]))
                if item["k"] == "bars":
                    out += [str(b["label"]) for b in item["bars"]]
                if item["k"] == "array":
                    out += [str(p["label"]) for p in item.get("ptrs", [])]
                    out += [cell_text(v) for v in item["vals"]]
                if item["k"] == "table":
                    out += [cell_text(v) for row in item["cells"] for v in row]
        return out

    def texts(self, scope, bound=None, min_step=0):
        says = [step["say"] for step in self.steps]
        if scope == "say":
            return says[min_step:]
        if scope == "say_last":
            return says[-1:]
        if scope == "title":
            return [self.data.get("title", "")]
        if scope == "labels":
            return self.label_texts()
        if scope == "any":
            return says + [self.data.get("title", "")] + self.label_texts()
        if scope.startswith("label:"):
            if bound is None:
                return []
            out = []
            for state in self.states:
                item = state.get(bound)
                if not item:
                    continue
                if "label" in item:
                    out.append(item["label"])
                points = self.anchors(item, state)
                for other in state.values():
                    if other["k"] == "text" and any(dist(other["at"], p) <= 1.2 for p in points if p):
                        out.append(other["text"])
            return out
        raise ValueError("unknown scope " + scope)


def mid(a, b):
    return ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)


def dist(a, b):
    return math.hypot(a[0] - b[0], a[1] - b[1])


def angle_diff(a, b):
    d = (a - b) % 360
    return min(d, 360 - d)


def direction_deg(a, b):
    return math.degrees(math.atan2(b[1] - a[1], b[0] - a[0])) % 360


def point_segment(p, a, b):
    ax, ay, bx, by = a[0], a[1], b[0], b[1]
    length2 = (bx - ax) ** 2 + (by - ay) ** 2
    if length2 == 0:
        return dist(p, a)
    t = max(0.0, min(1.0, ((p[0] - ax) * (bx - ax) + (p[1] - ay) * (by - ay)) / length2))
    return dist(p, (ax + t * (bx - ax), ay + t * (by - ay)))


# ---------- numbers in text ----------

NUMBER = re.compile(r"(?<![\w.])([-−]?(?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d+)?|[-−]?\.\d+)(\s*k[NJ]\b)?")
FRACTION = re.compile(r"(?<![\w.])(\d+(?:\.\d+)?)\s*/\s*(\d+(?:\.\d+)?)")
PI = re.compile(r"(?<![\w.])(\d+(?:\.\d+)?)?\s*(π|\bpi\b)\s*(?:/\s*(\d+(?:\.\d+)?))?")


def numbers(text):
    out = []
    for match in NUMBER.finditer(text):
        value = float(match.group(1).replace("−", "-").replace(",", ""))
        out.append(value)
        if match.group(2):
            out.append(value * 1000)
    for match in FRACTION.finditer(text):
        den = float(match.group(2))
        if den:
            out.append(float(match.group(1)) / den)
    for match in PI.finditer(text):
        coef = float(match.group(1)) if match.group(1) else 1.0
        den = float(match.group(3)) if match.group(3) else 1.0
        out.append(coef * math.pi / den)
    return out


def number_match(found, values, rtol, atol):
    return any(abs(n - v) <= max(atol, rtol * abs(v)) for n in found for v in values)


# ---------- checks ----------

class Grader:
    def __init__(self, scene, bind):
        self.s = scene
        self.bind = bind  # binding name -> item id or None
        self.memo = {}

    def it(self, name, state=None):
        identifier = self.bind.get(name)
        return None if identifier is None else self.s.item(identifier, state)

    def rank(self, identifier):
        for k, step in enumerate(self.s.steps):
            if identifier in step.get("show", []) or step.get("focus") == identifier:
                return k
            for edit in step.get("do", []):
                if edit["id"] == identifier or (edit["key"] == "target" and edit["value"] == identifier):
                    return k
        for k, ids in enumerate(self.s.visible):
            if identifier in ids:
                return k
        return math.inf

    def run(self, check):
        method = getattr(self, "c_" + check["t"])
        try:
            return bool(method(check))
        except (KeyError, TypeError, ValueError, ZeroDivisionError, IndexError):
            return False

    # basic
    def c_field(self, c):
        item = self.it(c["b"])
        value = item.get(c["key"]) if item else None
        if isinstance(c["eq"], (int, float)) and not isinstance(c["eq"], bool):
            return isinstance(value, (int, float)) and abs(value - c["eq"]) <= c.get("tol", 1e-9)
        return value == c["eq"]

    def c_count(self, c):
        return sum(1 for item in self.s.items if item["k"] == c["kind"]) >= c["min"]

    def c_steps(self, c):
        return c.get("min", 0) <= len(self.s.steps) <= c.get("max", 99)

    def c_order(self, c):
        ids = [self.bind.get(name) for name in c["seq"]]
        if None in ids:
            return False
        ranks = [self.rank(i) for i in ids]
        return all(a < b for a, b in zip(ranks, ranks[1:])) and math.inf not in ranks

    def c_num(self, c):
        scope = c["scope"]
        bound = self.bind.get(scope.split(":", 1)[1]) if scope.startswith("label:") else None
        found = [n for text in self.s.texts(scope, bound, c.get("min_step", 0)) for n in numbers(text)]
        atol = c.get("atol", 0.0)
        rtol = c.get("rtol", 0.0 if "atol" in c else 0.01)
        return number_match(found, c["values"], rtol, atol)

    def c_regex(self, c):
        flags = re.I if c.get("i") else 0
        return any(re.search(c["pattern"], text, flags) for text in self.s.texts(c["scope"]))

    # vectors and geometry
    def c_anchored(self, c):
        vec, to = self.it(c["vec"]), self.it(c["to"])
        if not vec or not to:
            return False
        if vec.get("on") == to["id"]:
            return True
        tail = self.s.vector_tail(vec)
        return tail is not None and dist(tail, self.s.center(to)) <= self.s.radius(to) + 0.3

    def c_dir(self, c):
        vec = self.it(c["vec"])
        return vec is not None and angle_diff(float(vec.get("angle", 0)), c["deg"]) <= c["tol"]

    def c_dir_rel(self, c):
        vec, ref = self.it(c["vec"]), self.it(c["ref"])
        if not vec or not ref:
            return False
        angle = float(vec.get("angle", 0))
        rel = c["rel"]
        if rel.startswith("incline"):
            theta = float(ref["angle"])
            target = {"incline_normal": theta + 90, "incline_up": theta, "incline_down": theta + 180}[rel]
            return angle_diff(angle, target) <= c["tol"]
        tail = self.s.vector_tail(vec)
        centre = self.s.center(ref)
        if tail is None or dist(tail, centre) < 1e-9:
            return False
        toward = direction_deg(tail, centre)
        if rel == "toward_center":
            return angle_diff(angle, toward) <= c["tol"]
        if rel == "away_from_center":
            return angle_diff(angle, toward + 180) <= c["tol"]
        if rel == "tangent":
            return min(angle_diff(angle, toward + 90), angle_diff(angle, toward - 90)) <= c["tol"]
        return False

    def c_len_ratio(self, c):
        a, b = self.it(c["a"]), self.it(c["b"])
        if not a or not b or float(b["len"]) == 0:
            return False
        return abs(float(a["len"]) / float(b["len"]) - c["ratio"]) <= c["rtol"] * c["ratio"]

    def c_on_incline(self, c):
        body, incline = self.it(c["body"]), self.it(c["incline"])
        if not body or not incline:
            return False
        o, b, _ = self.s.incline_geometry(incline)
        theta = math.radians(float(incline["angle"]))
        centre = self.s.center(body)
        normal = (-math.sin(theta), math.cos(theta))
        d = (centre[0] - o[0]) * normal[0] + (centre[1] - o[1]) * normal[1]
        size = self.s.size(body)
        return o[0] - 0.1 <= centre[0] <= o[0] + b + 0.1 and 0.25 * size <= d <= 1.25 * size

    def c_on_circle(self, c):
        item, circle = self.it(c["item"]), self.it(c["circle"])
        if not item or not circle:
            return False
        r = float(circle["r"])
        return abs(dist(self.s.center(item), circle["at"]) - r) <= c["rtol"] * r

    def c_left_right(self, c):
        left, middle, right = self.it(c["left"]), self.it(c["mid"]), self.it(c["right"])
        if not left or not middle or not right:
            return False
        return self.s.center(left)[0] < self.s.center(middle)[0] < self.s.center(right)[0]

    def c_below(self, c):
        a, b = self.it(c["a"]), self.it(c["b"])
        return bool(a and b) and self.s.center(a)[1] < self.s.center(b)[1]

    def c_above(self, c):
        a, b = self.it(c["a"]), self.it(c["b"])
        return bool(a and b) and self.s.center(a)[1] > self.s.center(b)[1]

    def c_horizontal(self, c):
        line = self.it(c["b"])
        if not line:
            return False
        d = direction_deg(line["from"], line["to"])
        return min(angle_diff(d, 0), angle_diff(d, 180)) <= c["tol"]

    def c_spring_connects(self, c):
        spring, top, bottom = self.it(c["spring"]), self.it(c["top"]), self.it(c["bottom"])
        if not spring or not top or not bottom:
            return False
        ends = self.s.ends(spring)
        t0, t1 = top["from"], top["to"]
        for a, b in (ends, ends[::-1]):
            if point_segment(a, t0, t1) <= 0.3 and dist(b, self.s.center(bottom)) <= self.s.radius(bottom) + 0.35:
                return True
        return False

    def c_rope_attached(self, c):
        for name in c["to"]:
            item = self.it(name)
            if not item:
                return False
            centre, reach = self.s.center(item), self.s.radius(item) + 0.4
            if not any(other["k"] in c["kinds"] and any(dist(e, centre) <= reach for e in self.s.ends(other))
                       for other in self.s.items):
                return False
        return True

    def c_head_to_tail(self, c):
        first, second = self.it(c["first"]), self.it(c["second"])
        if not first or not second:
            return False
        head, tail = self.s.vector_head(first), self.s.vector_tail(second)
        return head is not None and tail is not None and dist(head, tail) <= c["tol_frac"] * float(first["len"])

    def c_same_tail(self, c):
        a, b = self.it(c["a"]), self.it(c["b"])
        if not a or not b:
            return False
        ta, tb = self.s.vector_tail(a), self.s.vector_tail(b)
        return ta is not None and tb is not None and dist(ta, tb) <= c["tol_frac"] * float(b["len"])

    def c_same_head(self, c):
        a, b = self.it(c["a"]), self.it(c["b"])
        if not a or not b:
            return False
        ha, hb = self.s.vector_head(a), self.s.vector_head(b)
        return ha is not None and hb is not None and dist(ha, hb) <= c["tol_frac"] * float(b["len"])

    # circle constructions (M01)
    def circle_P(self, c):
        circle = self.it(c["circle"])
        if not circle:
            return None
        centre, r = tuple(circle["at"][:2]), float(circle["r"])
        a = math.radians(c.get("deg", 60))
        target = (centre[0] + r * math.cos(a), centre[1] + r * math.sin(a))
        best = None
        for item in self.s.items:
            if item["k"] in c.get("kinds", ["body", "node"]) and dist(item["at"], target) <= c.get("rtol", 0.08) * r:
                if best is None or dist(item["at"], target) < dist(best, target):
                    best = tuple(item["at"][:2])
        return best

    def c_circle_point(self, c):
        point = self.circle_P(c)
        if point is not None:
            self.memo["P"] = point
            self.memo["P_spec"] = c
        return point is not None

    def named_point(self, name, circle):
        centre = tuple(circle["at"][:2])
        point = self.memo.get("P")
        if name == "center":
            return centre
        if point is None:
            return None
        return {"P": point, "projx": (point[0], centre[1]), "projy": (centre[0], point[1])}[name]

    def c_segment(self, c):
        circle = self.it(c["circle"])
        if not circle:
            return False
        a, b = self.named_point(c["a"], circle), self.named_point(c["b"], circle)
        if a is None or b is None:
            return False
        tol = c["dist_frac"] * float(circle["r"])
        for item in self.s.items:
            if item["k"] not in c["kinds"]:
                continue
            if c.get("dashed") and not (item.get("style") == "dashed" or item.get("dashed") is True):
                continue
            ends = self.s.ends(item)
            if len(ends) == 2 and None not in ends and (
                    (dist(ends[0], a) <= tol and dist(ends[1], b) <= tol) or
                    (dist(ends[0], b) <= tol and dist(ends[1], a) <= tol)):
                return True
        return False

    def c_axes_at_center(self, c):
        circle = self.it(c["circle"])
        if not circle:
            return False
        centre, tol = tuple(circle["at"][:2]), c["tol_frac"] * float(circle["r"])
        if any(item["k"] == "axes" and dist(item["at"], centre) <= tol for item in self.s.items):
            return True
        lines = [item for item in self.s.items if item["k"] in ("line", "vector", "path")]
        horizontal, vertical = [], []
        for item in lines:
            ends = self.s.ends(item)
            if len(ends) != 2 or None in ends or dist(*ends) == 0:
                continue
            d = direction_deg(*ends)
            if min(angle_diff(d, 0), angle_diff(d, 180)) <= 3:
                horizontal.append(ends)
            if min(angle_diff(d, 90), angle_diff(d, 270)) <= 3:
                vertical.append(ends)
        for h in horizontal:
            for v in vertical:
                cross = (v[0][0], h[0][1])
                if point_segment(cross, *h) <= 0.05 and point_segment(cross, *v) <= 0.05 and dist(cross, centre) <= tol:
                    return True
        return False

    # triangle (M03)
    def triangle(self, c):
        if "triangle" in self.memo:
            return self.memo["triangle"]
        found = None
        candidates = []
        for item in self.s.items:
            if item["k"] == "region" and len(item["pts"]) == 3:
                candidates.append(([tuple(p[:2]) for p in item["pts"]], {item["id"]}))
            if item["k"] == "path":
                pts = [tuple(p[:2]) for p in item["pts"]]
                if len(pts) == 3 or (len(pts) == 4 and dist(pts[0], pts[3]) <= 0.1):
                    candidates.append((pts[:3], {item["id"]}))
        lines = [i for i in self.s.items if i["k"] == "line"]
        for trio in itertools.combinations(lines, 3):
            points = []
            for line in trio:
                for p in (tuple(line["from"][:2]), tuple(line["to"][:2])):
                    if not any(dist(p, q) <= 0.1 for q in points):
                        points.append(p)
            if len(points) == 3:
                candidates.append((points, {line["id"] for line in trio}))
        expected = sorted(c["sides"])
        for points, ids in candidates:
            sides = [(dist(points[i], points[(i + 1) % 3]), (points[i], points[(i + 1) % 3])) for i in range(3)]
            ordered = sorted(sides, key=lambda s: s[0])
            scale = sum(s[0] for s in ordered) / sum(expected)
            if scale <= 0 or any(abs(s[0] - e * scale) > c["rtol"] * e * scale for s, e in zip(ordered, expected)):
                continue
            longest = ordered[-1][1]
            vertex = next(p for p in points if p not in longest)
            u = (longest[0][0] - vertex[0], longest[0][1] - vertex[1])
            v = (longest[1][0] - vertex[0], longest[1][1] - vertex[1])
            angle = math.degrees(math.acos(max(-1, min(1, (u[0] * v[0] + u[1] * v[1]) / (math.hypot(*u) * math.hypot(*v))))))
            if abs(angle - 90) <= c["right_tol"]:
                found = {"sides": [(e, s[1]) for s, e in zip(ordered, expected)], "vertex": vertex, "ids": ids}
                break
        self.memo["triangle"] = found
        return found

    def c_triangle(self, c):
        return self.triangle(c) is not None

    def c_side_labels(self, c):
        tri = self.memo.get("triangle")
        if not tri:
            return False
        for value, (a, b) in tri["sides"]:
            centre = mid(a, b)
            ok = False
            for item in self.s.items:
                texts = []
                if item["k"] == "text" and dist(item["at"], centre) <= c["dist"]:
                    texts.append(item["text"])
                if item["k"] == "line" and "label" in item and point_segment(mid(item["from"], item["to"]), a, b) <= 0.1:
                    texts.append(item["label"])
                if any(number_match(numbers(t), [value], 0.0, 1e-9) for t in texts):
                    ok = True
            if not ok:
                return False
        return True

    def c_right_angle_mark(self, c):
        tri = self.memo.get("triangle")
        if not tri:
            return False
        for item in self.s.items:
            if item["id"] in tri["ids"] or item["k"] in ("highlight", "edge"):
                continue
            if any(p is not None and dist(p, tri["vertex"]) <= c["dist"] for p in self.s.anchors(item)):
                return True
        return False

    # plots
    def c_plot_fn(self, c):
        plot = self.it(c["b"])
        if not plot:
            return False
        f = make_fn(c["fn"])
        pts = plot["pts"]
        if len(pts) < c["min_pts"]:
            return False
        xs = [p[0] for p in pts]
        lo, hi = c["x_span"]
        if min(xs) > lo + c["span_tol"] or max(xs) < hi - c["span_tol"]:
            return False
        return all(abs(p[1] - f(p[0])) <= c["atol"] for p in pts)

    def c_plot_has_points(self, c):
        plot = self.it(c["b"])
        return bool(plot) and all(any(dist(p, q) <= c["tol"] for q in plot["pts"]) for p in c["points"])

    def c_plot_box(self, c):
        plot = self.it(c["b"])
        if not plot:
            return False
        ok = True
        for key, (lo, hi) in (("xr", c["x"]), ("yr", c["y"])):
            r0, r1 = plot[key]
            slack = 1e-6 + 0.01 * (r1 - r0)
            ok &= r0 <= lo + slack and r1 >= hi - slack
        return ok

    def c_near_plot_point(self, c):
        plot = self.it(c["plot"])
        if not plot:
            return False
        target = self.s.plot_world(plot, c["xy"])
        return any(item["k"] in c["kinds"] and item["id"] != plot["id"] and
                   any(p is not None and dist(p, target) <= c["dist"] for p in self.s.anchors(item))
                   for item in self.s.items)

    def c_plot_segment(self, c):
        plot = self.it(c["plot"])
        if not plot:
            return False
        a, b = self.s.plot_world(plot, c["from"]), self.s.plot_world(plot, c["to"])
        for item in self.s.items:
            if item["k"] not in c["kinds"]:
                continue
            ends = self.s.ends(item)
            if len(ends) == 2 and None not in ends and (
                    (dist(ends[0], a) <= c["dist"] and dist(ends[1], b) <= c["dist"]) or
                    (dist(ends[0], b) <= c["dist"] and dist(ends[1], a) <= c["dist"])):
                return True
        return False

    def c_rects(self, c):
        heights = c["heights"]
        for state in self.s.states:
            for item in state.values():
                if item["k"] == "bars" and len(item["bars"]) == len(heights) and all(
                        abs(b["value"] - h) <= c["rtol"] for b, h in zip(item["bars"], heights)):
                    return True
        rects = []
        for item in self.s.items:
            if item["k"] == "region" and len(item["pts"]) == 4:
                xs = sorted({round(p[0], 6) for p in item["pts"]})
                ys = sorted({round(p[1], 6) for p in item["pts"]})
                if len(xs) == 2 and len(ys) == 2:
                    rects.append((xs[1] - xs[0], ys[1] - ys[0], xs[0]))
        nonzero = [h for h in heights if h > 0]
        if len(rects) < len(nonzero):
            return False
        for combo in itertools.combinations(sorted(rects, key=lambda r: r[2]), len(nonzero)):
            widths = [r[0] for r in combo]
            if max(widths) - min(widths) > 0.02 * max(widths):
                continue
            scale = combo[-1][1] / nonzero[-1]
            if all(abs(r[1] - h * scale) <= c["rtol"] * max(nonzero) * scale for r, h in zip(combo, nonzero)):
                return True
        return False

    # bars
    def bars_states(self):
        out = []
        for k, state in enumerate(self.s.states):
            out.append([state[i] for i in sorted(self.s.visible[k]) if state[i]["k"] == "bars"])
        return out

    def c_bars_values(self, c):
        target = self.bind.get(c["b"])
        for k, state in enumerate(self.s.states):
            item = state.get(target)
            if not item or target not in self.s.visible[k] or len(item["bars"]) != len(c["values"]):
                continue
            values = [b["value"] for b in item["bars"]]
            if c["mode"] == "exact":
                if all(abs(v - e) <= c["rtol"] * max(abs(x) for x in c["values"]) for v, e in zip(values, c["values"])):
                    return True
            else:
                total_e = sum(c["values"])
                scale = sum(values) / total_e if total_e else 0
                if scale > 0 and all(abs(v - e * scale) <= c["rtol"] * scale * max(c["values"]) for v, e in zip(values, c["values"])):
                    return True
        return False

    def c_bars_labels_order(self, c):
        item = self.it(c["b"])
        if not item or len(item["bars"]) != len(c["tokens"]):
            return False
        return all(re.search(r"(?<![\w.])" + re.escape(tok) + r"(?![\w.])", b["label"])
                   for b, tok in zip(item["bars"], c["tokens"]))

    def c_bars_labeled_values(self, c):
        item = self.it(c["b"])
        if not item:
            return False
        for cls in c["classes"]:
            hits = [b for b in item["bars"] if re.search(cls["re"], b["label"], re.I)]
            if len(hits) != 1 or abs(hits[0]["value"] - cls["v"]) > c["rtol"] * cls["v"]:
                return False
        return True

    def c_bars_states(self, c):
        roles = c["roles"]
        expected = c["states"]
        top = max(abs(v) for state in expected for v in state.values()) or 1
        index = 0
        for items in self.bars_states():
            if index == len(expected):
                break
            for item in items:
                mapped = {}
                for role, pattern in roles.items():
                    hits = [b for b in item["bars"] if re.search(pattern, b["label"], re.I)]
                    if len(hits) == 1:
                        mapped[role] = hits[0]["value"]
                if len(mapped) == len(roles) and all(
                        abs(mapped[r] - v) <= c["rtol"] * top for r, v in expected[index].items()):
                    index += 1
                    break
        return index == len(expected)

    # arrays and tables
    def item_states(self, name):
        identifier = self.bind.get(name)
        if identifier is None:
            return []
        return [state[identifier] for k, state in enumerate(self.s.states) if identifier in self.s.visible[k]]

    @staticmethod
    def collapse(seq):
        out = []
        for value in seq:
            if not out or out[-1] != value:
                out.append(value)
        return out

    @staticmethod
    def subsequence(expected, seq):
        index = 0
        for value in seq:
            if index < len(expected) and value == expected[index]:
                index += 1
        return index == len(expected)

    def c_array_vals(self, c):
        want = [cell_text(v) for v in c["vals"]]
        states = [[cell_text(v) for v in item["vals"]] for item in self.item_states(c["b"])]
        if not states:
            return False
        return want == states[-1] if c.get("when") == "final" else want in states

    def c_array_states(self, c):
        strip = c.get("strip")
        seq = []
        for item in self.item_states(c["b"]):
            cells = [cell_text(v) for v in item["vals"]]
            if strip:
                cells = [v for v in cells if v.lower() not in PLACEHOLDERS]
            seq.append(cells)
        seq = self.collapse(seq)
        expected = [[cell_text(v) for v in state] for state in c["states"]]
        if c.get("only"):
            return bool(seq) and all(state in expected for state in seq)
        if not self.subsequence(expected, seq):
            return False
        return not c.get("exact_final") or (seq and seq[-1] == expected[-1])

    def c_stack_states(self, c):
        seq = []
        for item in self.item_states(c["b"]):
            cells = [(i, cell_text(v)) for i, v in enumerate(item["vals"]) if cell_text(v).lower() not in PLACEHOLDERS]
            tops = [p["i"] for p in item.get("ptrs", []) if re.fullmatch(c["top_re"], p["label"].strip(), re.I)]
            if not cells or len(tops) != 1:
                seq.append(None)
                continue
            indices = [i for i, _ in cells]
            if tops[0] == max(indices):
                seq.append([v for _, v in cells])
            elif tops[0] == min(indices):
                seq.append([v for _, v in reversed(cells)])
            else:
                seq.append(None)
        expected = [[cell_text(v) for v in state] for state in c["states"]]
        return self.subsequence(expected, self.collapse(seq))

    def c_ptr_states(self, c):
        seq = []
        for item in self.item_states(c["b"]):
            mapped = {}
            for pointer in item.get("ptrs", []):
                for role, pattern in c["roles"].items():
                    if re.fullmatch(pattern, pointer["label"].strip(), re.I) and role not in mapped:
                        mapped[role] = int(pointer["i"])
            seq.append(mapped)
        index = 0
        for mapped in seq:
            if index < len(c["states"]) and all(mapped.get(r) == v for r, v in c["states"][index].items()):
                index += 1
        return index == len(c["states"])

    def c_marked_states(self, c):
        seq = self.collapse([sorted(set(item.get("marked", []))) for item in self.item_states(c["b"])])
        return self.subsequence([sorted(s) for s in c["sets"]], seq)

    def c_marked_final(self, c):
        states = self.item_states(c["b"])
        return bool(states) and sorted(set(states[-1].get("marked", []))) == sorted(c["set"])

    def c_table_rows(self, c):
        states = self.item_states(c["b"])
        if not states:
            return False
        rows = [[cell_text(v) for v in row] for row in states[-1]["cells"]]
        header = rows[0]
        if len(header) != len(c["header_re"]) or not all(re.search(p, h, re.I) for p, h in zip(c["header_re"], header)):
            return False
        data, want = rows[1:], c["rows"]
        return data == want if c.get("ordered") else Counter(map(tuple, data)) == Counter(map(tuple, want))

    def c_table_marked_rows(self, c):
        states = self.item_states(c["b"])
        if not states:
            return False
        table = states[-1]
        rows = [[cell_text(v) for v in row] for row in table["cells"]]
        marked_rows = {r for r, _ in table.get("marked", [])}
        for r, row in enumerate(rows[1:], start=1):
            if row in c["marked"] and r not in marked_rows:
                return False
            if row in c["unmarked"] and r in marked_rows:
                return False
        return any(row in c["marked"] for row in rows[1:])

    # graphs
    def edges_at(self, k, directed):
        state, ids = self.s.states[k], self.s.visible[k]
        out = set()
        for identifier in ids:
            item = state[identifier]
            if item["k"] != "edge":
                continue
            a, b = state[item["a"]], state[item["b"]]
            ta, tb = str(a.get("text", "")).strip(), str(b.get("text", "")).strip()
            if directed:
                out.add((ta, tb) if item.get("dir") is True else ("undirected", frozenset((ta, tb))))
            else:
                out.add(frozenset((ta, tb)))
        return out

    def c_graph_edges(self, c):
        if not self.s.states or not self.s.items:
            return False
        k = 0 if c["when"] == "first" else len(self.s.states) - 1
        directed = c.get("directed", False)
        got = self.edges_at(k, directed)
        want = {tuple(e) for e in c["edges"]} if directed else {frozenset(e) for e in c["edges"]}
        return got == want if c.get("exact", True) else want <= got

    def c_edge_order(self, c):
        first_seen = {}
        for k in range(len(self.s.states)):
            for edge in self.edges_at(k, True):
                first_seen.setdefault(edge, k)
        a, b = first_seen.get(tuple(c["first"])), first_seen.get(tuple(c["then"]))
        return a is not None and b is not None and a < b

    def c_visit_order(self, c):
        visited, order = set(), []
        previous_targets = {}
        for k, step in enumerate(self.s.steps):
            state, ids = self.s.states[k], self.s.visible[k]
            signals = set()
            focus = step.get("focus")
            if focus in state and state[focus]["k"] == "node":
                signals.add(focus)
            for identifier in ids:
                item = state[identifier]
                if item["k"] == "highlight":
                    target = item.get("target")
                    if target in state and state[target]["k"] == "node" and previous_targets.get(identifier) != target:
                        signals.add(target)
                    previous_targets[identifier] = target
            for edit in step.get("do", []):
                if edit["key"] == "color" and edit["id"] in state and state[edit["id"]]["k"] == "node":
                    signals.add(edit["id"])
            new = [s for s in signals if s not in visited]
            if len(new) > 1:
                return False
            for identifier in new:
                visited.add(identifier)
                order.append(str(state[identifier].get("text", "")).strip())
        return order == c["nodes"]

    # hashing (C08)
    def bucket_states(self, n):
        out = []
        for k, state in enumerate(self.s.states):
            found = None
            for identifier in sorted(self.s.visible[k]):
                item = state[identifier]
                if item["k"] == "array" and len(item["vals"]) == n:
                    found = [ints(cell_text(v)) for v in item["vals"]]
                elif item["k"] == "table":
                    rows = item["cells"]
                    body = rows[1:] if len(rows) == n + 1 else rows if len(rows) == n else None
                    if body is not None and len(body[0]) >= 2:
                        found = [ints(cell_text(row[-1])) for row in body]
                if found is not None:
                    break
            out.append(found)
        return out

    def c_hash_final(self, c):
        states = self.bucket_states(c["n"])
        if not states or states[-1] is None:
            return False
        final = states[-1]
        want = {int(k): sorted(v) for k, v in c["buckets"].items()}
        return all(sorted(final[i]) == want.get(i, []) for i in range(c["n"]))

    def c_hash_order(self, c):
        first = {}
        for k, buckets in enumerate(self.bucket_states(c["n"])):
            if buckets is None:
                continue
            present = {v for cell in buckets for v in cell}
            for key in c["keys"]:
                if key in present:
                    first.setdefault(key, k)
        steps = [first.get(key) for key in c["keys"]]
        return None not in steps and all(a < b for a, b in zip(steps, steps[1:]))

    # pie (M08)
    def c_pie(self, c):
        shares = sorted(s * 3.6 for s in c["shares"])
        regions = [item for item in self.s.items if item["k"] == "region"]
        vertices = Counter()
        for region in regions:
            for p in {(round(p[0], 1), round(p[1], 1)) for p in region["pts"]}:
                vertices[p] += 1
        for centre, count in vertices.items():
            if count < len(shares):
                continue
            spans = []
            for region in regions:
                pts = [tuple(p[:2]) for p in region["pts"]]
                if not any(dist(p, centre) <= 0.15 for p in pts):
                    continue
                angles = sorted(direction_deg(centre, p) for p in pts if dist(p, centre) > 0.15)
                if len(angles) < 2:
                    continue
                gaps = [(angles[(i + 1) % len(angles)] - angles[i]) % 360 for i in range(len(angles))]
                spans.append(360 - max(gaps))
            if len(spans) == len(shares) and all(abs(a - b) <= c["deg_tol"] for a, b in zip(sorted(spans), shares)):
                return True
        disclosed = any(re.search(c["disclosure_re"], t, re.I) for t in self.s.texts("any"))
        if not disclosed:
            return False
        for state in self.s.states:
            for item in state.values():
                if item["k"] == "bars" and len(item["bars"]) == len(shares):
                    values = sorted(b["value"] for b in item["bars"])
                    want = sorted(c["shares"])
                    scale = sum(values) / sum(want)
                    if scale > 0 and all(abs(v - w * scale) <= c["bars_rtol"] * scale * max(want) for v, w in zip(values, want)):
                        return True
        return False

    # momentum (P07)
    def c_vec_states(self, c):
        seen = []
        for k, state in enumerate(self.s.states):
            for identifier in self.s.visible[k]:
                item = state[identifier]
                if item["k"] == "vector" and angle_diff(float(item.get("angle", 0)), c["dir"]) <= c["tol"] and float(item["len"]) > 0:
                    seen.append((k, float(item["len"])))
        if not seen:
            return False
        k1 = min(k for k, _ in seen)
        firsts = [length for k, length in seen if k == k1]
        laters = [length for k, length in seen if k > k1]
        return any(abs(l2 / l1 - c["ratio"]) <= c["rtol"] * c["ratio"] for l1 in firsts for l2 in laters)

    # refraction (P10)
    def snell(self):
        if "snell" in self.memo:
            return self.memo["snell"]
        result = None
        segments = []
        for item in self.s.items:
            if item["k"] in ("line", "vector", "path"):
                ends = self.s.ends(item)
                if len(ends) == 2 and None not in ends and dist(*ends) > 0:
                    segments.append((item, ends))
        horizontal = [(i, e) for i, e in segments if i["k"] == "line" and
                      min(angle_diff(direction_deg(*e), 0), angle_diff(direction_deg(*e), 180)) <= 3]
        vertical = [(i, e) for i, e in segments if
                    min(angle_diff(direction_deg(*e), 90), angle_diff(direction_deg(*e), 270)) <= 3]
        for surface, se in horizontal:
            for normal, ne in vertical:
                entry = (ne[0][0], se[0][1])
                if point_segment(entry, *se) > 0.3 or point_segment(entry, *ne) > 0.3:
                    continue
                above, below = [], []
                for item, ends in segments:
                    if item is surface or item is normal:
                        continue
                    for near, far in (ends, ends[::-1]):
                        if dist(near, entry) <= 0.3:
                            if far[1] > entry[1] + 0.2:
                                above.append(far)
                            elif far[1] < entry[1] - 0.2:
                                below.append(far)
                if above and below:
                    result = {"entry": entry, "above": above, "below": below}
                    break
            if result:
                break
        self.memo["snell"] = result
        return result

    def c_snell_setup(self, c):
        return self.snell() is not None

    def c_snell_angles(self, c):
        geometry = self.snell()
        if not geometry:
            return False
        e = geometry["entry"]
        for a in geometry["above"]:
            ia = math.degrees(math.atan2(abs(a[0] - e[0]), a[1] - e[1]))
            for b in geometry["below"]:
                ib = math.degrees(math.atan2(abs(b[0] - e[0]), e[1] - b[1]))
                opposite = (a[0] - e[0]) * (b[0] - e[0]) < 0
                if opposite and abs(ia - c["incident"]) <= c["tol"] and abs(ib - c["refracted"]) <= c["tol"]:
                    return True
        return False

    # seesaw (P09)
    def c_seesaw_dist(self, c):
        heavy, light = self.it(c["heavy"]), self.it(c["light"])
        if not heavy or not light:
            return False
        xh, xl = self.s.center(heavy)[0], self.s.center(light)[0]
        for beam in self.s.items:
            if beam["k"] != "line":
                continue
            d = direction_deg(beam["from"], beam["to"])
            if min(angle_diff(d, 0), angle_diff(d, 180)) > 5:
                continue
            for pivot in self.s.items:
                if pivot["id"] in (heavy["id"], light["id"], beam["id"]) or pivot["k"] not in ("incline", "body", "node", "region"):
                    continue
                top = self.top_point(pivot)
                if top is None or point_segment(top, beam["from"], beam["to"]) > 0.6:
                    continue
                xp = top[0]
                if (xh - xp) * (xl - xp) >= 0:
                    continue
                if abs(abs(xh - xp) / abs(xl - xp) - c["ratio"]) <= c["rtol"] * c["ratio"]:
                    return True
        return False

    def top_point(self, item):
        if item["k"] == "body":
            return (item["at"][0], item["at"][1] + self.s.size(item) / 2)
        if item["k"] == "node":
            return (item["at"][0], item["at"][1] + self.s.radius(item))
        points = self.s.anchors(item)
        return max(points, key=lambda p: p[1]) if points else None

    # pendulum (P11)
    def pendulum(self):
        if "pendulum" in self.memo:
            return self.memo["pendulum"]
        best = None
        for string in self.s.items:
            if string["k"] not in ("line", "rope", "path"):
                continue
            for bob in self.s.items:
                if bob["k"] != "body":
                    continue
                records = []
                for k, state in enumerate(self.s.states):
                    if string["id"] not in self.s.visible[k] or bob["id"] not in self.s.visible[k]:
                        continue
                    records.append((self.s.ends(state[string["id"]]), tuple(state[bob["id"]]["at"][:2]),
                                    self.s.size(state[bob["id"]])))
                if not records:
                    continue
                for fixed in (0, 1):
                    pivot = records[0][0][fixed]
                    if not all(dist(r[0][fixed], pivot) <= 0.05 for r in records):
                        continue
                    attached = all(dist(r[0][1 - fixed], r[1]) <= 0.35 * r[2] + 0.15 for r in records)
                    candidate = {"pivot": pivot, "bobs": [r[1] for r in records], "attached": attached}
                    if best is None or (attached and not best["attached"]):
                        best = candidate
        self.memo["pendulum"] = best
        return best

    def swing(self, pivot, bob):
        return math.degrees(math.atan2(bob[0] - pivot[0], pivot[1] - bob[1]))

    def c_pend_string_attached(self, c):
        p = self.pendulum()
        return bool(p and p["attached"])

    def c_pend_rest_first(self, c):
        p = self.pendulum()
        return bool(p) and abs(self.swing(p["pivot"], p["bobs"][0])) <= c["tol"]

    def c_pend_extremes(self, c):
        p = self.pendulum()
        if not p:
            return False
        angles = [self.swing(p["pivot"], b) for b in p["bobs"][1:]]
        return any(abs(a + c["deg"]) <= c["tol"] for a in angles) and any(abs(a - c["deg"]) <= c["tol"] for a in angles)

    def c_pend_length_constant(self, c):
        p = self.pendulum()
        if not p:
            return False
        lengths = [dist(p["pivot"], b) for b in p["bobs"]]
        return all(abs(l - lengths[0]) <= c["rtol"] * lengths[0] for l in lengths)

    def c_template(self, c):
        data = self.s.data
        return data.get("template") == c["name"] and deep_equal(data.get("params"), c["params"])


def ints(text):
    return [int(x) for x in re.findall(r"(?<![\d.])\d+(?![\d.])", text)]


def deep_equal(a, b):
    if isinstance(a, dict) and isinstance(b, dict):
        return a.keys() == b.keys() and all(deep_equal(a[k], b[k]) for k in a)
    if isinstance(a, list) and isinstance(b, list):
        return len(a) == len(b) and all(deep_equal(x, y) for x, y in zip(a, b))
    if isinstance(a, (int, float)) and isinstance(b, (int, float)) and not isinstance(a, bool) and not isinstance(b, bool):
        return abs(a - b) <= 1e-9
    return a == b


SAFE = {"sin": math.sin, "cos": math.cos, "sqrt": math.sqrt, "pi": math.pi, "min": min, "max": max, "abs": abs}


def make_fn(expression):
    if not re.fullmatch(r"[\sx0-9.+\-*/(),a-z]*", expression) or re.search(r"[a-z]{2,}", re.sub(r"\b(sin|cos|sqrt|pi|min|max|abs)\b", "", expression)):
        raise ValueError("unsafe expression")
    code = compile(expression, "<fn>", "eval")
    return lambda x: eval(code, {"__builtins__": {}}, dict(SAFE, x=x))


# ---------- ML checks ----------

def grade_ml(doc, facts, checks):
    item, item_facts = None, None
    results = []
    for check in checks:
        t = check["t"]
        ok = False
        try:
            if t == "ml_kind":
                for raw, fact in zip(doc["items"], facts):
                    if raw["kind"] == check["kind"]:
                        item, item_facts = raw, fact["facts"]
                        break
                ok = item is not None
            elif item is None:
                ok = False
            elif t == "ml_field":
                ok = check["key"] in item and deep_equal(item[check["key"]], check["eq"])
            elif t == "ml_absent":
                ok = not any(key in item for key in check["keys"])
            elif t == "ml_optional_eq":
                ok = check["key"] not in item or deep_equal(item[check["key"]], check["eq"])
            elif t == "ml_candidates":
                got = {cand["token"]: cand["logit"] for cand in item["candidates"]}
                ok = got.keys() == check["map"].keys() and all(abs(got[k] - v) <= 1e-9 for k, v in check["map"].items())
            elif t == "ml_points_labels":
                labels = [p["label"] for p in item.get("points", [])]
                ok = sorted(labels) == sorted(check["eq"])
            elif t == "ml_cluster":
                ok = sorted(item.get("cluster", [])) == sorted(check["eq"])
            elif t == "ml_states":
                ok = sorted(item.get("states", [])) == sorted(check["eq"])
            elif t == "ml_steps_candidates":
                ok = all(len(step["candidates"]) == check["count"] for step in item["steps"])
            elif t == "ml_map_groups":
                group = {label: g for g, labels in enumerate(check["groups"]) for label in labels}
                pts = {p["label"]: p["position"] for p in item["points"]}
                ok = True
                for label, pos in pts.items():
                    nearest = min((other for other in pts if other != label), key=lambda o: dist(pos, pts[o]))
                    ok &= group.get(label) is not None and group.get(label) == group.get(nearest)
            elif t == "ml_fact":
                ok = deep_equal(item_facts.get(check["key"]), check["eq"])
        except (KeyError, TypeError, ValueError):
            ok = False
        results.append({"t": t, "cat": check["cat"], "pass": bool(ok)})
    return results


# ---------- driver ----------

def candidates(scene, rule):
    out = []
    for item in scene.items:
        if item["k"] not in rule["kind"]:
            continue
        if "label_re" in rule:
            texts = [state[item["id"]].get("label", "") for state in scene.states if item["id"] in state]
            centre = scene.center(item)
            texts += [other["text"] for other in scene.items if other["k"] == "text" and centre and dist(other["at"], centre) <= 1.2]
            if not any(re.search(rule["label_re"], t, re.I) for t in texts):
                continue
        if "text_re" in rule and not re.search(rule["text_re"], str(item.get("text", "")), re.I):
            continue
        out.append(item["id"])
    return out


def grade_scene(data, spec):
    scene = Scene(data)
    names = list(spec.get("bind", {}))
    pools = [candidates(scene, spec["bind"][name]) or [None] for name in names]
    best = None
    count = 0
    for combo in itertools.product(*pools):
        ids = [c for c in combo if c is not None]
        if len(ids) != len(set(ids)):
            continue
        count += 1
        if count > 20000:
            break
        grader = Grader(scene, dict(zip(names, combo)))
        results = [{"t": c["t"], "cat": c["cat"], "pass": grader.run(c)} for c in spec["checks"]]
        score = sum(r["pass"] for r in results)
        if best is None or score > best[0]:
            best = (score, results, dict(zip(names, combo)))
    if best is None:
        grader = Grader(scene, {name: None for name in names})
        best = (0, [{"t": c["t"], "cat": c["cat"], "pass": grader.run(c)} for c in spec["checks"]], {})
    return best[1], best[2]


def final_attempt(run, identifier):
    _, found = attempt.attempts(run, identifier)
    return found[-1] if found else None


def grade_request(run, identifier, spec):
    path = final_attempt(run, identifier)
    if path is None:
        return {"id": identifier, "missing": True, "valid": False, "attempts": 0,
                "checks": [{"t": c["t"], "cat": c["cat"], "pass": False} for c in spec["checks"]]}
    data = path.read_bytes()
    valid, message, reason = attempt.validate(data, "baseline")
    attempts_used = int(path.stem.split("-")[1])
    first_valid = None
    log_path = path.parent / "log.json"
    if log_path.exists():
        log = json.loads(log_path.read_text(encoding="utf-8"))
        first_valid = bool(log and log[0]["valid"])
    result = {"id": identifier, "valid": valid, "attempts": attempts_used, "firstTryValid": first_valid,
              "reason": reason, "bindings": {}}
    if not valid:
        result["checks"] = [{"t": c["t"], "cat": c["cat"], "pass": False} for c in spec["checks"]]
    elif attempt.is_ml(data):
        doc, facts = ml_check.check(data)
        result["checks"] = grade_ml(doc, facts, spec["checks"])
    else:
        checks, bindings = grade_scene(json.loads(data.decode("utf-8")), spec)
        result["checks"], result["bindings"] = checks, bindings
    result["passed"] = sum(c["pass"] for c in result["checks"])
    result["total"] = len(result["checks"])
    result["correct"] = valid and result["passed"] == result["total"]
    return result


def summarize(run, results, requests):
    domain = {r["id"]: r["domain"] for r in requests}
    out = {"run": run, "requests": len(results),
           "valid": sum(r["valid"] for r in results),
           "firstTryValid": sum(bool(r.get("firstTryValid")) for r in results),
           "correct": sum(r["correct"] for r in results),
           "checksPassed": sum(r["passed"] for r in results), "checksTotal": sum(r["total"] for r in results),
           "byDomain": {}, "byCategory": {}, "byCheckType": {}}
    for d in ("physics", "math", "cs", "ml"):
        rs = [r for r in results if domain[r["id"]] == d]
        out["byDomain"][d] = {"requests": len(rs), "correct": sum(r["correct"] for r in rs),
                              "checksPassed": sum(r["passed"] for r in rs), "checksTotal": sum(r["total"] for r in rs)}
    for r in results:
        failed_cats = set()
        for c in r["checks"]:
            cat = out["byCategory"].setdefault(c["cat"], {"passed": 0, "total": 0, "requestsWithFailure": 0})
            cat["passed"] += c["pass"]
            cat["total"] += 1
            if not c["pass"]:
                failed_cats.add(c["cat"])
            typ = out["byCheckType"].setdefault(c["t"], {"passed": 0, "total": 0})
            typ["passed"] += c["pass"]
            typ["total"] += 1
        for cat in failed_cats:
            out["byCategory"][cat]["requestsWithFailure"] += 1
    return out


def main(argv):
    run = argv[1]
    specs = json.loads((EVAL / "specs.json").read_text(encoding="utf-8"))["specs"]
    requests = json.loads((EVAL / "requests.json").read_text(encoding="utf-8"))["requests"]
    if "--id" in argv:
        identifier = argv[argv.index("--id") + 1]
        result = grade_request(run, identifier, specs[identifier])
        print(json.dumps(result, indent=1, ensure_ascii=False))
        return 0
    results = [grade_request(run, r["id"], specs[r["id"]]) for r in requests]
    summary = summarize(run, results, requests)
    folder = EVAL / "results"
    folder.mkdir(exist_ok=True)
    (folder / f"{run}.json").write_bytes(
        (json.dumps({"summary": summary, "results": results}, indent=1, ensure_ascii=False) + "\n").encode("utf-8"))
    print(f"{run}: {summary['correct']}/{summary['requests']} mechanically correct, {summary['valid']} valid, "
          f"{summary['firstTryValid']} valid on the first try, checks {summary['checksPassed']}/{summary['checksTotal']}")
    for d, v in summary["byDomain"].items():
        print(f"  {d}: {v['correct']}/{v['requests']} correct, checks {v['checksPassed']}/{v['checksTotal']}")
    for cat, v in sorted(summary["byCategory"].items()):
        print(f"  [{cat}] checks {v['passed']}/{v['total']}, requests with a failure: {v['requestsWithFailure']}")
    for r in results:
        if not r["correct"]:
            failed = [f"{c['t']}({c['cat']})" for c in r["checks"] if not c["pass"]]
            print(f"  FAIL {r['id']}: " + ("invalid: " + str(r.get("reason")) if not r["valid"] else ", ".join(failed)))
    return 0


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    raise SystemExit(main(sys.argv))
