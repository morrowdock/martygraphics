# SPDX-License-Identifier: Apache-2.0
"""Offline reference for the scene v1 `func` and `field` kinds and the `alt` text keys.

Swift is authoritative: `MGExpression`, `MGGraph` and `MGParser` in Sources/MartyGraphics. This module mirrors their
rules operation for operation, so an offline preflight (for example tools/scene_v1_check.py on the schema branch) can
give the same reasons, and so the shared golden cases in docs/fixtures/v1/expressions.cases.json and
docs/fixtures/v1/graphs.cases.json run in Python as well as in XCTest. Standard library only; never imports or
evaluates scene text as Python.

Floating-point note: Python's math functions raise where C returns a value (log(0), sqrt(-1), overflow). The wrappers
below return the IEEE 754 / C99 value instead, so values match Apple's libm up to its last-place rounding.
"""

import math
import unicodedata

EXPR_LENGTH = 80
EXPR_TOKENS = 48
EXPR_DEPTH = 8
NUMBER_LENGTH = 12
EXPR_ITEMS = 6
EXPR_PARAMETER = 1000.0
FUNC_INTERVALS = 256
FUNC_BREAKS = 16
FUNC_TOLERANCE = 0.01
FUNC_PERIOD = (0.5, 20.0)
FIELD_COLS = 16
FIELD_ROWS = 12
BISECTIONS = 8
MAGNITUDE = 1e12
SAY = 200
LABEL = 40

VARIABLES = ("x", "y", "t", "a", "b", "c")
FUNCTIONS = ("sin", "cos", "tan", "asin", "acos", "atan", "sinh", "cosh", "tanh",
             "exp", "ln", "log", "sqrt", "abs", "min", "max")
SYMBOLS = frozenset(" .+-*/^(),")
E = 2.718281828459045


class Refusal(ValueError):
    """A refusal with the Swift reason token."""

    def __init__(self, reason):
        super().__init__(reason)
        self.reason = reason


# MARK: IEEE 754 arithmetic


def _divide(left, right):
    if right == 0:
        if left == 0 or math.isnan(left):
            return math.nan
        return math.copysign(math.inf, left) * math.copysign(1.0, right)
    try:
        return left / right
    except OverflowError:
        return math.copysign(math.inf, left) * math.copysign(1.0, right)


def _odd_integer(value):
    return math.isfinite(value) and value.is_integer() and int(value) % 2 == 1


def _power(left, right):
    try:
        return math.pow(left, right)
    except OverflowError:
        return -math.inf if left < 0 and _odd_integer(right) else math.inf
    except ValueError:
        if left == 0 and right < 0:
            return math.copysign(math.inf, left) if _odd_integer(right) else math.inf
        return math.nan


def _guarded(function, value, overflow=None):
    try:
        return function(value)
    except OverflowError:
        return overflow(value) if overflow else math.inf
    except ValueError:
        return math.nan


def _log(function, value):
    if math.isnan(value) or value < 0:
        return math.nan
    if value == 0:
        return -math.inf
    return function(value)


def _apply(name, v):
    if name == "sin":
        return _guarded(math.sin, v)
    if name == "cos":
        return _guarded(math.cos, v)
    if name == "tan":
        return _guarded(math.tan, v)
    if name == "asin":
        return _guarded(math.asin, v)
    if name == "acos":
        return _guarded(math.acos, v)
    if name == "atan":
        return math.atan(v)
    if name == "sinh":
        return _guarded(math.sinh, v, lambda x: math.copysign(math.inf, x))
    if name == "cosh":
        return _guarded(math.cosh, v)
    if name == "tanh":
        return math.tanh(v)
    if name == "exp":
        return _guarded(math.exp, v)
    if name == "ln":
        return _log(math.log, v)
    if name == "log":
        return _log(math.log10, v)
    if name == "sqrt":
        return math.nan if v < 0 else math.sqrt(v)
    if name == "abs":
        return math.fabs(v)
    return math.nan


def _combine(op, left, right):
    if op == "+":
        return left + right
    if op == "-":
        return left - right
    if op == "*":
        return left * right
    if op == "/":
        return _divide(left, right)
    if op == "^":
        return _power(left, right)
    if op == "min":
        return math.nan if math.isnan(left) or math.isnan(right) else (right if right < left else left)
    if op == "max":
        return math.nan if math.isnan(left) or math.isnan(right) else (right if right > left else left)
    return math.nan


# MARK: grammar


def _letter(ch):
    return "a" <= ch <= "z" or "A" <= ch <= "Z"


def _digit(ch):
    return "0" <= ch <= "9"


def _tokenize(text, reason):
    tokens = []
    i = 0
    while i < len(text):
        ch = text[i]
        if ch == " ":
            i += 1
            continue
        if _digit(ch) or ch == ".":
            j = i
            while j < len(text) and _digit(text[j]):
                j += 1
            if j < len(text) and text[j] == ".":
                j += 1
                fraction = j
                while j < len(text) and _digit(text[j]):
                    j += 1
                if j == fraction:
                    raise Refusal(reason + ".syntax")
            if j - i > NUMBER_LENGTH:
                raise Refusal(reason + ".syntax")
            literal = ("0" if ch == "." else "") + text[i:j]
            tokens.append(("number", float(literal)))
            i = j
            continue
        if _letter(ch):
            j = i
            while j < len(text) and _letter(text[j]):
                j += 1
            tokens.append(("name", text[i:j]))
            i = j
            continue
        tokens.append(("symbol", ch))
        i += 1
    return tokens


class _Parser:
    def __init__(self, tokens, reason):
        self.tokens = tokens
        self.reason = reason
        self.index = 0
        self.program = []
        self.used = set()

    def next(self):
        return self.tokens[self.index] if self.index < len(self.tokens) else None

    def symbol(self, ch):
        return self.next() == ("symbol", ch)

    def syntax(self):
        return Refusal(self.reason + ".syntax")

    def expression(self):
        self.term()
        while self.symbol("+") or self.symbol("-"):
            op = self.next()[1]
            self.index += 1
            self.term()
            self.program.append(("op", op))

    def term(self):
        self.unary()
        while self.symbol("*") or self.symbol("/"):
            op = self.next()[1]
            self.index += 1
            self.unary()
            self.program.append(("op", op))

    def unary(self):
        if self.symbol("+") or self.symbol("-"):
            op = self.next()[1]
            self.index += 1
            self.unary()
            if op == "-":
                self.program.append(("negate", None))
            return
        self.power()

    def power(self):
        self.primary()
        if self.symbol("^"):
            self.index += 1
            self.unary()
            self.program.append(("op", "^"))

    def primary(self):
        token = self.next()
        if token is None:
            raise self.syntax()
        self.index += 1
        kind, value = token
        if kind == "number":
            self.program.append(("number", value))
        elif token == ("symbol", "("):
            self.expression()
            if not self.symbol(")"):
                raise self.syntax()
            self.index += 1
        elif kind == "name":
            if value in FUNCTIONS:
                if not self.symbol("("):
                    raise self.syntax()
                self.index += 1
                count = 0
                if not self.symbol(")"):
                    self.expression()
                    count = 1
                    while self.symbol(","):
                        self.index += 1
                        self.expression()
                        count += 1
                if not self.symbol(")"):
                    raise self.syntax()
                self.index += 1
                if count != (2 if value in ("min", "max") else 1):
                    raise Refusal(self.reason + ".arity")
                self.program.append(("call", value))
            elif value == "pi":
                self.program.append(("number", math.pi))
            elif value == "e":
                self.program.append(("number", E))
            elif value in VARIABLES:
                self.used.add(value)
                self.program.append(("variable", value))
            else:
                raise Refusal(self.reason + ".name")
        else:
            raise self.syntax()


class Expression:
    """A compiled expression: `value(**inputs)` evaluates it."""

    def __init__(self, text, variables, program):
        self.text = text
        self.variables = frozenset(variables)
        self.program = program

    def value(self, x=0.0, y=0.0, t=0.0, a=0.0, b=0.0, c=0.0):
        inputs = {"x": x, "y": y, "t": t, "a": a, "b": b, "c": c}
        stack = []
        for kind, value in self.program:
            if kind == "number":
                stack.append(value)
            elif kind == "variable":
                stack.append(float(inputs[value]))
            elif kind == "negate":
                if not stack:
                    return math.nan
                stack[-1] = -stack[-1]
            elif kind == "call" and value not in ("min", "max"):
                if not stack:
                    return math.nan
                stack[-1] = _apply(value, stack[-1])
            else:
                if len(stack) < 2:
                    return math.nan
                right = stack.pop()
                stack[-1] = _combine(value, stack[-1], right)
        return stack[0] if len(stack) == 1 else math.nan


def compile_expression(text, allowed, reason):
    """Mirror of `MGExpression.compile`: the same refusals in the same order."""
    if not isinstance(text, str):
        raise Refusal(reason)
    if len(text) > EXPR_LENGTH or not text.strip(" ") or \
            any(not (_letter(ch) or _digit(ch) or ch in SYMBOLS) for ch in text):
        raise Refusal(reason)
    tokens = _tokenize(text, reason)
    if len(tokens) > EXPR_TOKENS:
        raise Refusal(reason + ".tokens")
    depth = deepest = 0
    for token in tokens:
        if token == ("symbol", "("):
            depth += 1
            deepest = max(deepest, depth)
        if token == ("symbol", ")"):
            depth -= 1
    if deepest > EXPR_DEPTH:
        raise Refusal(reason + ".depth")
    parser = _Parser(tokens, reason)
    parser.expression()
    if parser.index != len(tokens):
        raise Refusal(reason + ".syntax")
    for name in VARIABLES:
        if name in parser.used and name not in allowed:
            raise Refusal(reason + ".var." + name)
    return Expression(text, parser.used, parser.program)


# MARK: sampling (MGGraph)


def grid_x(i, x0, x1):
    n = FUNC_INTERVALS
    return x1 if i == n else x0 + (x1 - x0) * i / n


def _clamp_magnitude(y):
    return max(-MAGNITUDE, min(MAGNITUDE, y))


def _clip(y, lo, hi):
    return max(lo, min(hi, y))


class Curve:
    def __init__(self):
        self.samples = []
        self.starts = []
        self.visible = False
        self.deviation = 0.0

    def pieces(self):
        return pieces(len(self.samples), self.starts)

    def covers(self, a, b):
        return any(self.samples[lo][0] <= a and self.samples[hi - 1][0] >= b for lo, hi in self.pieces())


def pieces(count, starts):
    bounds = [0]
    for s in sorted(starts):
        if s > bounds[-1] and s < count:
            bounds.append(s)
    bounds.append(max(0, count))
    return [(lo, hi) for lo, hi in zip(bounds, bounds[1:]) if lo < hi]


def _distance(p, a, b):
    """Mirror of `MGGraph.distance`: from p to the segment a-b."""
    dx, dy = b[0] - a[0], b[1] - a[1]
    length2 = dx * dx + dy * dy
    t = max(0.0, min(1.0, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / length2)) if length2 > 0 else 0.0
    qx, qy = a[0] + t * dx - p[0], a[1] + t * dy - p[1]
    return math.sqrt(qx * qx + qy * qy)


def curve(f, x0, x1, y0, y1, measure, width=1.0, height=1.0, stop_after=None):
    """Mirror of `MGGraph.curve`, including the midpoint rule: a non-finite value at the midpoint of an interval
    between two finite grid values splits the piece there (probes at midpoint +/- one probe), as at parse time and in
    every animated frame."""
    n = FUNC_INTERVALS
    probe = (x1 - x0) / n / 1024
    c = Curve()
    values = [math.nan] * (n + 1)
    mids = [math.nan] * n
    piece = [-1] * (n + 1)
    state = {"open": False, "last": (0.0, 0.0)}

    def inside(y):
        return y0 <= y <= y1

    def pole(a, b):
        if not ((a[1] > y1 and b[1] < y0) or (a[1] < y0 and b[1] > y1)):
            return False
        lo, hi = a, b
        for _ in range(BISECTIONS):
            xm = (lo[0] + hi[0]) / 2
            ym = f(xm)
            if not math.isfinite(ym):
                return True
            if inside(ym):
                c.visible = True
                return False
            if (ym > y1) == (lo[1] > y1):
                lo = (xm, ym)
            else:
                hi = (xm, ym)
        return True

    def add(p):
        if state["open"] and pole(state["last"], p):
            state["open"] = False
        if not state["open"]:
            if c.samples:
                c.starts.append(len(c.samples))
            state["open"] = True
        if inside(p[1]):
            c.visible = True
        c.samples.append((p[0], _clamp_magnitude(p[1])))
        state["last"] = p

    for i in range(n + 1):
        xi = grid_x(i, x0, x1)
        yi = f(xi)
        values[i] = yi
        if math.isfinite(yi):
            if i > 0 and math.isfinite(values[i - 1]):
                xm = (grid_x(i - 1, x0, x1) + xi) / 2
                ym = f(xm)
                mids[i - 1] = ym
                if not math.isfinite(ym):
                    # A gap between two finite samples: split the piece there (pole checks run on each side).
                    left = f(xm - probe)
                    if math.isfinite(left):
                        add((xm - probe, left))
                    state["open"] = False
                    right = f(xm + probe)
                    if math.isfinite(right):
                        add((xm + probe, right))
            add((xi, yi))
            piece[i] = len(c.starts)
        else:
            if i > 0 and state["open"]:
                left = f(xi - probe)
                if math.isfinite(left):
                    add((xi - probe, left))
            state["open"] = False
            if i < n:
                right = f(xi + probe)
                if math.isfinite(right):
                    add((xi + probe, right))
        if stop_after is not None and len(c.starts) > stop_after:
            return c
    if not measure:
        return c
    sx, sy = width / (x1 - x0), height / (y1 - y0)
    for i in range(n):
        if piece[i] < 0 or piece[i] != piece[i + 1]:
            continue
        xa, xb = grid_x(i, x0, x1), grid_x(i + 1, x0, x1)
        xm = (xa + xb) / 2
        ym = mids[i]
        if not math.isfinite(ym):
            continue  # never: a non-finite midpoint splits the piece above
        ya, yb, yt = _clamp_magnitude(values[i]), _clamp_magnitude(values[i + 1]), _clamp_magnitude(ym)
        if max(ya, yb, yt) < y0 or min(ya, yb, yt) > y1:
            continue
        vertical = abs(_clip(yt, y0, y1) - _clip((ya + yb) / 2, y0, y1)) * sy
        chord = _distance(((xm - x0) * sx, (yt - y0) * sy), ((xa - x0) * sx, (ya - y0) * sy), ((xb - x0) * sx, (yb - y0) * sy))
        c.deviation = max(c.deviation, min(vertical, chord) / height)
    return c


def grid_values(f, x0, x1):
    return [f(grid_x(i, x0, x1)) for i in range(FUNC_INTERVALS + 1)]


def check_function(expr, x0, x1, y0, y1, params=None, period=None, shade=None, mark=None, width=1.0, height=1.0):
    """Mirror of `MGGraph.checkFunction`. Returns (curve at t = 0, marked value or None); raises Refusal."""
    params = params or {}
    instants = [0, period / 4, period / 2, 3 * period / 4] if period is not None else [0]
    first, marked = None, None
    for k, tau in enumerate(instants):
        def f(x, tau=tau):
            return expr.value(x=x, t=tau, **params)
        c = curve(f, x0, x1, y0, y1, measure=True, width=width, height=height, stop_after=FUNC_BREAKS)
        if len(c.starts) > FUNC_BREAKS:
            raise Refusal("func.breaks")
        if k == 0 and not c.visible:
            raise Refusal("func.empty")
        if c.deviation > FUNC_TOLERANCE:
            raise Refusal("func.detail")
        if shade is not None and not c.covers(shade[0], shade[1]):
            raise Refusal("func.shade")
        if mark is not None:
            v = expr.value(x=mark, t=tau, **params)
            if not (math.isfinite(v) and y0 <= v <= y1):
                raise Refusal("func.mark")
            if k == 0:
                marked = v
        if k == 0:
            first = c
    if period is not None:
        start = grid_values(lambda x: expr.value(x=x, t=0, **params), x0, x1)
        end = grid_values(lambda x: expr.value(x=x, t=period, **params), x0, x1)
        tolerance = FUNC_TOLERANCE * (y1 - y0)
        for u, v in zip(start, end):
            if math.isfinite(u) != math.isfinite(v):
                raise Refusal("func.loop")
            if math.isfinite(u) and abs(_clip(u, y0, y1) - _clip(v, y0, y1)) > tolerance:
                raise Refusal("func.loop")
    return first, marked


def field_vectors(dx, dy, x0, x1, y0, y1, cols, rows, params=None):
    """Mirror of `MGGraph.fieldVectors`: (vectors row by row from the bottom left, cells without a finite vector)."""
    params = params or {}
    vectors, missing = [], []
    for j in range(rows):
        for i in range(cols):
            px = x0 + (x1 - x0) * (i + 0.5) / cols
            py = y0 + (y1 - y0) * (j + 0.5) / rows
            u = dx.value(x=px, y=py, **params)
            v = dy.value(x=px, y=py, **params)
            if math.isfinite(u) and math.isfinite(v):
                vectors.append((_clamp_magnitude(u), _clamp_magnitude(v)))
            else:
                missing.append(len(vectors))
                vectors.append((0.0, 0.0))
    return vectors, missing


# MARK: item and scene rules (the new keys only)


def _number(value):
    """A JSON number: a finite float, or an int. Python ints are unbounded, so an int is never passed to
    math.isfinite (which raises OverflowError past the float range); `_num` range-checks it exactly instead."""
    return type(value) is int or (type(value) is float and math.isfinite(value))


def _num(value, lo, hi, reason):
    # An int is compared with the bounds exactly before it is converted, so an out-of-range one (10**400) is this
    # key's refusal, never an OverflowError.
    if not _number(value) or not lo <= value <= hi:
        raise Refusal(reason)
    return float(value)


def _space(ch):
    """Swift's `CharacterSet.whitespacesAndNewlines`: general category Z*, U+0009...U+000D and U+0085."""
    return unicodedata.category(ch).startswith("Z") or ch in "\t\n\x0b\x0c\r\x85"


def _trim(value):
    start, end = 0, len(value)
    while start < end and _space(value[start]):
        start += 1
    while end > start and _space(value[end - 1]):
        end -= 1
    return value[start:end]


def text_rules(value, limit, reason):
    """The plain-text rules of `MGParser.text` for a scene without template values."""
    if not isinstance(value, str):
        raise Refusal(reason)
    trimmed = _trim(value)
    if not trimmed or len(value) > limit or "<" in value or ">" in value or "```" in value or "://" in value:
        raise Refusal(reason)
    # Swift's `CharacterSet.controlCharacters` (general categories Cc and Cf) and U+2028 / U+2029 (Zl, Zp). Labels and
    # `alt` are single-line text, so a line feed is refused too; only text items and narration may break lines.
    if any(unicodedata.category(ch) in ("Cc", "Cf", "Zl", "Zp") for ch in value):
        raise Refusal(reason)
    name = None
    for ch in trimmed:
        if name is not None:
            if ch == "}":
                raise Refusal(reason + ".placeholder." + name)
            if not (ch.isascii() and ch.isalnum() and len(name) < 16):
                raise Refusal(reason + ".placeholder")
            name += ch
        elif ch == "{":
            name = ""
        elif ch == "}":
            raise Refusal(reason + ".brace")
    if name is not None:
        raise Refusal(reason + ".brace")
    return trimmed


def _range(value, reason):
    if not isinstance(value, list) or len(value) != 2:
        raise Refusal(reason)
    lo = _num(value[0], -1e6, 1e6, reason)
    hi = _num(value[1], -1e6, 1e6, reason)
    if not lo < hi or hi - lo < 1e-6:
        raise Refusal(reason)
    return lo, hi


def _point(value, world, reason, is3d=False):
    """Mirror of `MGParser.point`: two coordinates, or three in a 3D scene (z within +/- the world span)."""
    width, height = world
    if not isinstance(value, list) or not (len(value) == 2 or (len(value) == 3 and is3d)):
        raise Refusal(reason)
    x = _num(value[0], -0.25 * width, 1.25 * width, reason)
    y = _num(value[1], -0.25 * height, 1.25 * height, reason)
    z = _num(value[2], -max(world), max(world), reason) if len(value) == 3 else 0.0
    return x, y, z


FUNC_KEYS = {"id", "k", "color", "at", "w", "h", "xr", "yr", "y", "a", "b", "c", "period", "shade", "mark", "xl", "yl", "label"}
FUNC_REQUIRED = {"id", "k", "at", "w", "h", "xr", "yr", "y"}
FIELD_KEYS = {"id", "k", "color", "at", "w", "h", "xr", "yr", "dx", "dy", "a", "b", "c", "n", "style", "xl", "yl", "label"}
FIELD_REQUIRED = {"id", "k", "at", "w", "h", "xr", "yr", "dx", "dy"}
COLORS = {"force", "normal", "friction", "gravity", "tension", "velocity", "accel", "energy", "kinetic", "potential",
          "accent", "muted", "good", "warn", "blue", "red", "green", "orange", "purple", "yellow", "teal", "white"}
WORLD = (2.0, 100.0)


def _identifier(value, reason):
    """Mirror of `MGParser.identifier`: 1 to 24 ASCII letters, digits or `_`, starting with a letter."""
    if not isinstance(value, str) or not 1 <= len(value) <= 24 or not value.isascii() or not _letter(value[0]) or \
            any(not (_letter(ch) or _digit(ch) or ch == "_") for ch in value):
        raise Refusal(reason)
    return value


def _parameters(item, kind):
    allowed, params = {"x"}, {}
    for name in ("a", "b", "c"):
        if name in item:
            params[name] = _num(item[name], -EXPR_PARAMETER, EXPR_PARAMETER, kind + "." + name)
            allowed.add(name)
    return allowed, params


def check_graph_item(item, world=(12, 8), is3d=False):
    """The `func` / `field` rules of `MGParser.item` in Swift's order: closed keys, id, color, label, then the kind's
    keys. `is3d`: the scene is 3D, so `at` may have three coordinates, as `MGParser.point` allows; the item is then
    refused as `3d.kind.<kind>` by `check_scene` after every item has been checked, as in Swift.

    Returns a summary dict; raises Refusal with the Swift reason.
    """
    kind = item["k"]
    keys, required = (FUNC_KEYS, FUNC_REQUIRED) if kind == "func" else (FIELD_KEYS, FIELD_REQUIRED)
    if not required <= set(item):
        raise Refusal("item." + kind + ".missing")
    extra = set(item) - keys
    if extra:
        raise Refusal("item." + kind + ".unknown." + ",".join(sorted(extra)))
    _identifier(item["id"], "item.id")
    if "color" in item and (not isinstance(item["color"], str) or item["color"] not in COLORS):
        raise Refusal("item.color")
    if "label" in item:
        text_rules(item["label"], LABEL, "item.label")
    span = max(world)
    _point(item["at"], world, kind + ".at", is3d)
    w = _num(item["w"], 0.5, span * 1.25, kind + ".w")
    h = _num(item["h"], 0.5, span * 1.25, kind + ".h")
    x0, x1 = _range(item["xr"], kind + ".xr")
    y0, y1 = _range(item["yr"], kind + ".yr")
    allowed, params = _parameters(item, kind)
    if kind == "func":
        period = None
        if "period" in item:
            period = _num(item["period"], FUNC_PERIOD[0], FUNC_PERIOD[1], "func.period")
            allowed.add("t")
        expr = compile_expression(item["y"], allowed, "func.y")
        if period is not None and "t" not in expr.variables:
            raise Refusal("func.period")
        shade = None
        if "shade" in item:
            raw = item["shade"]
            if not isinstance(raw, list) or len(raw) != 2:
                raise Refusal("func.shade")
            shade = (_num(raw[0], x0, x1, "func.shade"), _num(raw[1], x0, x1, "func.shade"))
            if not shade[0] < shade[1]:
                raise Refusal("func.shade")
        mark = _num(item["mark"], x0, x1, "func.mark") if "mark" in item else None
        first, marked = check_function(expr, x0, x1, y0, y1, params, period, shade, mark, width=w, height=h)
        for key in ("xl", "yl"):
            if key in item:
                text_rules(item[key], LABEL, "func." + key)
        return {"samples": len(first.samples), "starts": list(first.starts), "mark": marked}
    allowed.add("y")
    if "n" in item:
        grid = item["n"]
        if not isinstance(grid, list) or len(grid) != 2:
            raise Refusal("field.n")
        cols = _num(grid[0], 2, FIELD_COLS, "field.n")
        rows = _num(grid[1], 2, FIELD_ROWS, "field.n")
        if not (cols.is_integer() and rows.is_integer()):
            raise Refusal("field.n")
    else:
        cols = 12.0 if w >= h else max(3.0, float(round_half_away(12 * w / h)))
        rows = max(3.0, float(round_half_away(12 * h / w))) if w >= h else 12.0
    if item.get("style", "arrows") not in ("arrows", "unit", "slope"):
        raise Refusal("field.style")
    dx = compile_expression(item["dx"], allowed, "field.dx")
    dy = compile_expression(item["dy"], allowed, "field.dy")
    for key in ("xl", "yl"):
        if key in item:
            text_rules(item[key], LABEL, "field." + key)
    vectors, missing = field_vectors(dx, dy, x0, x1, y0, y1, int(cols), int(rows), params)
    if not any(u != 0 or v != 0 for u, v in vectors):
        raise Refusal("field.empty")
    return {"cols": int(cols), "rows": int(rows), "missing": missing, "vectors": vectors}


def round_half_away(value):
    """Swift's `rounded()` (to nearest, ties away from zero)."""
    return math.floor(value + 0.5) if value >= 0 else math.ceil(value - 0.5)


def graph_edits(scene, graph_ids):
    """Step edits that check a graph item again (Swift `MGParser.graphEdits`; malformed entries are not counted).

    A template's own items and steps, and `over` (which may only name template items), stay with Swift: no Python
    template builds a `func` or `field` item.
    """
    count = 0
    steps = scene.get("steps")
    for step in steps if isinstance(steps, list) else ():
        edits = step.get("do") if isinstance(step, dict) else None
        for edit in edits if isinstance(edits, list) else ():
            if isinstance(edit, dict) and isinstance(edit.get("id"), str) and edit["id"] in graph_ids:
                count += 1
    return count


def check_scene(scene):
    """The new rules on a scene object: the `alt` keys, the `items.expr` count and every `func` / `field` item.

    Other kinds and keys are not checked here (Swift and tools/scene_v1_check.py check them). Raises Refusal.
    """
    is3d = scene.get("dim") == "3d"
    world = (12.0, 8.0)
    if "world" in scene:
        # The `world` rules of `MGParser.parseScene`, so a malformed world is a refusal, never a KeyError.
        raw = scene["world"]
        if not isinstance(raw, dict):
            raise Refusal("world")
        if not {"w", "h"} <= set(raw):
            raise Refusal("world.missing")
        if set(raw) - {"w", "h"}:
            raise Refusal("world.unknown." + ",".join(sorted(set(raw) - {"w", "h"})))
        world = (_num(raw["w"], WORLD[0], WORLD[1], "world.w"), _num(raw["h"], WORLD[0], WORLD[1], "world.h"))
    items = scene.get("items", [])
    graphs = [item for item in items if isinstance(item, dict) and item.get("k") in ("func", "field")]
    # Each graph item counts once and each step edit of one once more: an edit checks the whole item again.
    graph_ids = {item["id"] for item in graphs if isinstance(item.get("id"), str)}
    if len(graphs) + graph_edits(scene, graph_ids) > EXPR_ITEMS:
        raise Refusal("items.expr")
    summaries = {}
    for item in graphs:
        # check_graph_item refuses a missing id (`item.<kind>.missing`) or a malformed one (`item.id`) first, so the
        # summary key is always a valid id.
        summary = check_graph_item(item, world, is3d)
        summaries[item["id"]] = summary
    for step in scene.get("steps", []):
        if isinstance(step, dict) and "alt" in step:
            text_rules(step["alt"], SAY, "step.alt")
    if "alt" in scene:
        text_rules(scene["alt"], SAY, "alt")
    if is3d and graphs:
        raise Refusal("3d.kind." + graphs[0]["k"])
    return summaries
