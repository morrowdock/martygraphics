# SPDX-License-Identifier: Apache-2.0
"""Offline reference for the scene v1 `func` and `field` kinds, the `func` readouts, the `alt` text keys and the
`sliders` key.

Swift is authoritative: `MGExpression`, `MGGraph`, `MGReadout`, `MGParser` and `MGParser.sliders` (MGSliders.swift) in
Sources/MartyGraphics. This module mirrors their rules operation for operation, so an offline preflight (for example
tools/scene_v1_check.py) can give the same reasons, and so the shared golden cases in
docs/fixtures/v1/expressions.cases.json, docs/fixtures/v1/graphs.cases.json, docs/fixtures/v1/readouts.cases.json and
docs/fixtures/v1/sliders.cases.json run in Python as well as in XCTest. Standard library only; never imports or
evaluates scene text as Python.

Floating-point note: Python's math functions raise where C returns a value (log(0), sqrt(-1), overflow). The wrappers
below return the IEEE 754 / C99 value instead, so values match Apple's libm up to its last-place rounding.
"""

import math
import unicodedata
from fractions import Fraction

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
SLIDERS = 3
SLIDER_STEPS = 100
SLIDER_BINDINGS = 6
SLIDER_KEYS = ("param", "min", "max", "step", "default", "label")
READOUTS = ("value", "slope", "area")
READOUT_PANELS = 128
# `MGReadout.certifyDepth` and `certifyBudget`: the bounded subdivision of an area readout.
CERTIFY_DEPTH = 10
CERTIFY_BUDGET = 256
# Gauss-Legendre nodes on [-1, 1] and their weights (5 points), as in `MGReadout`.
GAUSS_NODES = (-0.906179845938664, -0.5384693101056831, 0.0, 0.5384693101056831, 0.906179845938664)
GAUSS_WEIGHTS = (0.23692688505618908, 0.47862867049936647, 0.5688888888888889, 0.47862867049936647,
                 0.23692688505618908)
LN10 = 2.302585092994046

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


def _sign(value):
    return 1 if value > 0 else -1 if value < 0 else 0


def _whole(value):
    """Swift's `v.rounded() == v`: true for a whole number and for an infinity."""
    return math.isinf(value) or (math.isfinite(value) and value.is_integer())


def _side1(name, u):
    """Mirror of `MGExpression.side(_:_:)`: the side of the kink or domain edge of a function that u is on."""
    if name in ("abs", "sqrt", "ln", "log"):
        return _sign(u)
    if name in ("asin", "acos"):
        return _sign(1 - abs(u))
    if name == "tan":
        return _sign(_apply("cos", u))
    return 0


def _side2(op, left, right, constant):
    """Mirror of `MGExpression.side(_:_:_:constant:)`: the divisor's sign, a min/max pair's order, a power's base."""
    if op == "/":
        return _sign(right)
    if op == "^":
        return 0 if constant and right >= 0 and _whole(right) else _sign(left)
    if op in ("min", "max"):
        return _sign(left - right)
    return 0


def _slope1(name, u, du):
    """Mirror of `MGExpression.slope(_:_:_:)`: the derivative of name(u) along a direction in which u changes by du."""
    if name == "sin":
        return _apply("cos", u) * du
    if name == "cos":
        return -_apply("sin", u) * du
    if name == "tan":
        c = _apply("cos", u)
        return _divide(du, c * c)
    if name == "asin":
        return _divide(du, _apply("sqrt", 1 - u * u)) if abs(u) < 1 else math.nan
    if name == "acos":
        return _divide(-du, _apply("sqrt", 1 - u * u)) if abs(u) < 1 else math.nan
    if name == "atan":
        return _divide(du, 1 + u * u)
    if name == "sinh":
        return _apply("cosh", u) * du
    if name == "cosh":
        return _apply("sinh", u) * du
    if name == "tanh":
        t = _apply("tanh", u)
        return (1 - t * t) * du
    if name == "exp":
        return _apply("exp", u) * du
    if name == "ln":
        return _divide(du, u) if u > 0 else math.nan
    if name == "log":
        return _divide(du, u * LN10) if u > 0 else math.nan
    if name == "sqrt":
        return _divide(du, 2 * _apply("sqrt", u)) if u > 0 else math.nan
    if name == "abs":
        if u > 0:
            return du
        if u < 0:
            return -du
        # The kink: the one-sided rule |du|.
        return abs(du) if u == 0 else math.nan
    return math.nan


def _slope2(op, left, dl, right, dr, constant):
    """Mirror of `MGExpression.slope(_:_:_:_:_:constant:)`: the derivative of `left op right` along a direction.
    `constant`: the exponent of a power does not read x."""
    if op == "+":
        return dl + dr
    if op == "-":
        return dl - dr
    if op == "*":
        return dl * right + left * dr
    if op == "/":
        return _divide(dl - _divide(left, right) * dr, right)
    if op == "^":
        if constant:
            if right == 0:
                return 0.0
            return right * _power(left, right - 1) * dl if _whole(right) or left > 0 else math.nan
        if not left > 0:
            return math.nan
        return _power(left, right) * (dr * _log(math.log, left) + _divide(right * dl, left))
    if op in ("min", "max"):
        if any(math.isnan(v) for v in (left, right, dl, dr)):
            return math.nan
        if left == right:
            # The kink: the smaller (larger) of the two derivatives.
            return (dr if dr < dl else dl) if op == "min" else (dr if dr > dl else dl)
        return dl if (left < right) == (op == "min") else dr
    return math.nan


# MARK: outward rounding (mirror of the `MGExpression` enclosure helpers)

# `MGExpression.libraryUlps`: doubles by which a library function's bounds are widened to each side.
LIBRARY_ULPS = 4
# `MGExpression.exactLimit`: below it, except at 0, a product or quotient is moved outward without looking at it.
EXACT_LIMIT = 2.0 ** -960


def _outward(v, error, up):
    """Mirror of `MGExpression.outward`: v as a bound on an exact result whose difference from v has the sign of
    `error`, moved to the next double down (up False) or up when the exact result is on the other side."""
    if up:
        return math.nextafter(v, math.inf) if error > 0 else v
    return math.nextafter(v, -math.inf) if error < 0 else v


def _sum(left, right, up):
    """Mirror of `MGExpression.sum`: left + right rounded down or up (Knuth's TwoSum gives the error exactly)."""
    s = left + right
    if not math.isfinite(s):
        return s
    t = s - left
    return _outward(s, (left - (s - t)) + (right - t), up)


def _product(left, right, up):
    """Mirror of `MGExpression.product`: left * right rounded down or up. Swift finds the sign of the rounding error
    with a fused multiply-add; this computes it exactly with fractions (the same sign above EXACT_LIMIT)."""
    p = left * right
    if not math.isfinite(p):
        return p
    if p == 0:
        return _outward(p, 0 if left == 0 or right == 0 else 1 if (left < 0) == (right < 0) else -1, up)
    if abs(p) < EXACT_LIMIT:
        return _outward(p, 1 if up else -1, up)
    return _outward(p, _sign(Fraction(left) * Fraction(right) - Fraction(p)), up)


def _quotient(left, right, up):
    """Mirror of `MGExpression.quotient`: left / right rounded down or up, for right != 0."""
    q = _divide(left, right)
    if not math.isfinite(q):
        return q
    if q == 0:
        return _outward(q, 0 if left == 0 else 1 if (left < 0) == (right < 0) else -1, up)
    if abs(q) < EXACT_LIMIT or abs(left) < EXACT_LIMIT:
        return _outward(q, 1 if up else -1, up)
    return _outward(q, _sign(Fraction(left) / Fraction(right) - Fraction(q)), up)


def _whole_power(u, n, up):
    """Mirror of `MGExpression.wholePower`: u ** n for a finite u >= 0 and a whole n >= 1, by repeated squaring with
    every product rounded down or up."""
    result, square, k = 1.0, u, n
    while True:
        if math.fmod(k, 2) == 1:
            result = max(0.0, _product(result, square, up))
        k = float(math.floor(k / 2))
        if not (k >= 1 and math.isfinite(result)):
            return result
        square = max(0.0, _product(square, square, up))


def _widened(v, up):
    """Mirror of `MGExpression.widened`: v moved LIBRARY_ULPS doubles down or up; nan when v is not finite."""
    if not math.isfinite(v):
        return math.nan
    for _ in range(LIBRARY_ULPS):
        v = math.nextafter(v, math.inf if up else -math.inf)
    return v


def _library_hull(values, lo=-math.inf, hi=math.inf):
    """Mirror of `MGExpression.libraryHull`: the hull of a library function's values, widened by LIBRARY_ULPS and kept
    within [lo, hi]; None when one is not finite."""
    span = _hull(values)
    if span is None or not (math.isfinite(span[0]) and math.isfinite(span[1])):
        return None
    return max(lo, _widened(span[0], False)), min(hi, _widened(span[1], True))


def _hull(values):
    """Mirror of `MGExpression.hull`: the smallest and largest of `values`, or None when one is not a number."""
    if any(math.isnan(v) for v in values):
        return None
    return min(values), max(values)


def _may_hold(a, b, at, period):
    """Mirror of `MGExpression.mayHold`: some at + k * period (multiples of the real pi) may lie in [a, b]."""
    slack = (abs(a) + abs(b) + 4) * 1e-15
    return math.ceil((a - at) / period - slack) <= math.floor((b - at) / period + slack)


def _magnitude(a, b):
    """Mirror of `MGExpression.magnitude`: |u| over [a, b], exactly."""
    if a >= 0:
        return a, b
    return (-b, -a) if b <= 0 else (0.0, max(-a, b))


def _enclose1(name, a, b):
    """Mirror of `MGExpression.enclose(_:_:_:)`: name over [a, b], rounded outward, or None where it may not be
    continuous there."""
    ends = [_apply(name, a), _apply(name, b)]
    if name in ("sin", "cos"):
        if b - a >= 2 * math.pi:
            return -1.0, 1.0
        span = _library_hull(ends, -1.0, 1.0)
        if span is None:
            return None
        peak = math.pi / 2 if name == "sin" else 0.0
        return (-1.0 if _may_hold(a, b, peak + math.pi, 2 * math.pi) else span[0],
                1.0 if _may_hold(a, b, peak, 2 * math.pi) else span[1])
    if name == "tan":
        if not b - a < math.pi or _may_hold(a, b, math.pi / 2, math.pi):
            return None
        return _library_hull(ends)
    if name == "asin":
        return _library_hull(ends) if a >= -1 and b <= 1 else None
    if name == "acos":
        return _library_hull(ends, 0.0) if a >= -1 and b <= 1 else None
    if name in ("atan", "sinh"):
        return _library_hull(ends)
    if name == "tanh":
        return _library_hull(ends, -1.0, 1.0)
    if name == "exp":
        return _library_hull(ends, 0.0)
    if name == "cosh":
        if not (a < 0 and b > 0):
            return _library_hull(ends, 1.0)
        return 1.0, _widened(max(ends), True)
    if name in ("ln", "log"):
        return _library_hull(ends) if a > 0 else None
    if name == "sqrt":
        return _library_hull(ends, 0.0) if a >= 0 else None
    if name == "abs":
        return _magnitude(a, b)
    return None


def _corners(left, right, function):
    """Mirror of `MGExpression.corners`: the smallest of `function` rounded down and the largest rounded up at the four
    corners of two ranges."""
    (l0, l1), (r0, r1) = left, right
    pairs = [(l0, r0), (l0, r1), (l1, r0), (l1, r1)]
    low = _hull([function(u, v, False) for u, v in pairs])
    high = _hull([function(u, v, True) for u, v in pairs])
    if low is None or high is None:
        return None
    return low[0], high[1]


def _enclose_power(left, right):
    """Mirror of `MGExpression.power`: the base range to the power of the exponent range, rounded outward, or None
    outside the domain."""
    (l0, l1), (r0, r1) = left, right
    if r0 != r1:
        # A varying exponent: the corners bound u^v for u > 0.
        if not l0 > 0:
            return None
        return _library_hull([_power(l0, r0), _power(l0, r1), _power(l1, r0), _power(l1, r1)], 0.0)
    w = r0
    if w == 0:
        return 1.0, 1.0
    if _whole(w):
        if w < 0 and l0 <= 0 <= l1:
            return None
        n = abs(w)
        odd = math.fmod(n, 2) == 1
        if l0 >= 0:
            m = (_whole_power(l0, n, False), _whole_power(l1, n, True))
        elif l1 <= 0:
            m = ((-_whole_power(-l0, n, True), -_whole_power(-l1, n, False)) if odd
                 else (_whole_power(-l1, n, False), _whole_power(-l0, n, True)))
        else:
            m = ((-_whole_power(-l0, n, True), _whole_power(l1, n, True)) if odd
                 else (0.0, max(_whole_power(-l0, n, True), _whole_power(l1, n, True))))
        if not (math.isfinite(m[0]) and math.isfinite(m[1])):
            return None
        return m if w > 0 else _enclose2("/", (1.0, 1.0), m)
    if not (l0 >= 0 if w > 0 else l0 > 0):
        return None
    return _library_hull([_power(l0, w), _power(l1, w)], 0.0)


def _enclose2(op, left, right):
    """Mirror of `MGExpression.enclose(_:_:_:)` for `left op right` over two ranges, rounded outward, or None where it
    may not be continuous there."""
    (l0, l1), (r0, r1) = left, right
    if op == "+":
        return _sum(l0, r0, False), _sum(l1, r1, True)
    if op == "-":
        return _sum(l0, -r1, False), _sum(l1, -r0, True)
    if op == "*":
        return _corners(left, right, _product)
    if op == "/":
        if not (r0 > 0 or r1 < 0):
            return None
        return _corners(left, right, _quotient)
    if op == "^":
        return _enclose_power(left, right)
    if op == "min":
        return min(l0, r0), min(l1, r1)
    if op == "max":
        return max(l0, r0), max(l1, r1)
    return None


def _edge1(name, u):
    """Mirror of `MGExpression.edge(_:_:)`: what the kink, pole or domain edge of a function is measured by over the
    argument range u, or None for a function that has none."""
    if name in ("abs", "sqrt", "ln", "log"):
        return u
    if name in ("asin", "acos"):
        m0, m1 = _magnitude(*u)
        return _sum(1.0, -m1, False), _sum(1.0, -m0, True)
    if name == "tan":
        return _enclose1("cos", *u) or (-math.inf, math.inf)
    return None


def _edge2(op, left, right, constant):
    """Mirror of `MGExpression.edge(_:_:_:constant:)`: the divisor, a power's base (none for a constant whole exponent
    of 0 or more) and l - r for min and max; None for the other operations."""
    if op == "/":
        return right
    if op == "^":
        r0, r1 = right
        return None if constant and r0 == r1 and r0 >= 0 and _whole(r0) else left
    if op in ("min", "max"):
        return _sum(left[0], -right[1], False), _sum(left[1], -right[0], True)
    return None


def _strict_side(e):
    """Mirror of `MGExpression.strictSide`: 1 or -1 when every value in e is above or below 0, else 0."""
    return 1 if e[0] > 0 else -1 if e[1] < 0 else 0


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

    def local(self, x=0.0, y=0.0, t=0.0, a=0.0, b=0.0, c=0.0):
        """Mirror of `MGExpression.local`: (value, slope from the left, slope from the right, sides), by forward mode
        along +x and along -x. `sides` lists the side of each operation's kink, pole or domain edge (-1, 0 or 1), or is
        None when some operation has no finite value; the slopes are then not numbers."""
        inputs = {"x": x, "y": y, "t": t, "a": a, "b": b, "c": c}
        broken = (math.nan, math.nan, math.nan, None)
        stack = []  # (value, derivative along +x, derivative along -x, reads x)
        sides, finite = [], True
        for kind, value in self.program:
            side = 0
            if kind == "number":
                stack.append((value, 0.0, 0.0, False))
            elif kind == "variable":
                is_x = value == "x"
                stack.append((float(inputs[value]), 1.0 if is_x else 0.0, -1.0 if is_x else 0.0, is_x))
            elif kind == "negate":
                if not stack:
                    return broken
                v, p, q, reads = stack[-1]
                stack[-1] = (-v, -p, -q, reads)
            elif kind == "call" and value not in ("min", "max"):
                if not stack:
                    return broken
                u, p, q, reads = stack[-1]
                side = _side1(value, u)
                stack[-1] = (_apply(value, u), _slope1(value, u, p), _slope1(value, u, q), reads)
            else:
                if len(stack) < 2:
                    return broken
                right, rp, rq, right_reads = stack.pop()
                left, lp, lq, left_reads = stack[-1]
                constant = not right_reads
                side = _side2(value, left, right, constant)
                stack[-1] = (_combine(value, left, right), _slope2(value, left, lp, right, rp, constant),
                             _slope2(value, left, lq, right, rq, constant), left_reads or right_reads)
            if not math.isfinite(stack[-1][0]):
                finite = False
            sides.append(side)
        if len(stack) != 1:
            return broken
        v, p, q, _ = stack[0]
        if not finite:
            return v, math.nan, math.nan, None
        return v, -q, p, sides

    def value_and_slope(self, x=0.0, y=0.0, t=0.0, a=0.0, b=0.0, c=0.0):
        """Mirror of `MGExpression.valueAndSlope`: the value, and the derivative where both one-sided ones agree."""
        v, left, right, _ = self.local(x, y, t, a, b, c)
        return v, (right if left == right else math.nan)

    def enclosure(self, lo, hi, y=0.0, t=0.0, a=0.0, b=0.0, c=0.0):
        """Mirror of `MGExpression.enclosure`: (low, high) bounds of the analytic value over x in [lo, hi], or None
        where interval arithmetic cannot show the expression continuous there."""
        result = self.intervals(lo, hi, y, t, a, b, c)
        return None if result is None else result[0]

    def intervals(self, lo, hi, y=0.0, t=0.0, a=0.0, b=0.0, c=0.0):
        """Mirror of `MGExpression.intervals`: one interval pass over x in [lo, hi], rounded outward. Returns the
        enclosure and, per operation in program order, the enclosure of what its kink, pole or domain edge is measured
        by (None for an operation that has none); None when some operation has no enclosure."""
        if not lo <= hi:
            return None
        inputs = {"y": y, "t": t, "a": a, "b": b, "c": c}
        stack = []  # (low, high, reads x)
        edges = []
        for kind, value in self.program:
            edge = None
            if kind == "number":
                stack.append((value, value, False))
            elif kind == "variable":
                stack.append((lo, hi, True) if value == "x" else (float(inputs[value]), float(inputs[value]), False))
            elif kind == "negate":
                if not stack:
                    return None
                low, high, reads = stack[-1]
                stack[-1] = (-high, -low, reads)
            elif kind == "call" and value not in ("min", "max"):
                if not stack:
                    return None
                low, high, reads = stack[-1]
                edge = _edge1(value, (low, high))
                result = _enclose1(value, low, high)
                if result is None:
                    return None
                stack[-1] = (result[0], result[1], reads)
            else:
                if len(stack) < 2:
                    return None
                r0, r1, right_reads = stack.pop()
                l0, l1, left_reads = stack[-1]
                edge = _edge2(value, (l0, l1), (r0, r1), not right_reads)
                result = _enclose2(value, (l0, l1), (r0, r1))
                if result is None:
                    return None
                stack[-1] = (result[0], result[1], left_reads or right_reads)
            low, high, _ = stack[-1]
            if not (math.isfinite(low) and math.isfinite(high) and low <= high):
                return None
            edges.append(edge)
        if len(stack) != 1:
            return None
        return (stack[0][0], stack[0][1]), edges


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


# MARK: readouts (MGReadout)


def resolution(value):
    """Mirror of `MGReadout.resolution`: the step between two numbers as the engine shows `value`."""
    magnitude = abs(value)
    return 1.0 if magnitude >= 100 else 0.1 if magnitude >= 10 else 0.01


def format_number(value):
    """Mirror of `MGPhysics.format(value, unit: "")`: 2 decimals below 10, 1 below 100, whole numbers above, no
    trailing zeros, never "-0"."""
    if not math.isfinite(value):
        return "\u2014"
    magnitude = abs(value)
    digits = 0 if magnitude >= 100 else 1 if magnitude >= 10 else 2
    shown = "%.*f" % (digits, value)
    if "." in shown:
        shown = shown.rstrip("0")
        if shown.endswith("."):
            shown = shown[:-1]
    return "0" if shown == "-0" else shown


def slope_readout(expr, params, m, x0, x1, drawn):
    """Mirror of `MGReadout.slope`: f'(m) at the marked x when it is proven, else func.readouts.slope."""
    refuse = Refusal("func.readouts.slope")
    probe = (x1 - x0) / FUNC_INTERVALS / 1024
    if not drawn.covers(m, m):
        raise refuse
    _, left, right, sides = expr.local(x=m, **params)
    if sides is None:
        raise refuse
    # Interval passes over each half, [m - probe, m] and [m, m + probe], rounded outward.
    before = expr.intervals(_sum(m, -probe, False), m, **params)
    after = expr.intervals(m, _sum(m, probe, True), **params)
    if before is None or after is None or len(before[1]) != len(sides) or len(after[1]) != len(sides):
        raise refuse
    for side, l, r in zip(sides, before[1], after[1]):
        if l is None or r is None:
            continue
        if side != 0:
            # Off its kink or edge at m: strictly on the same side over both halves.
            if _strict_side(l) != side or _strict_side(r) != side:
                raise refuse
        elif not ((l[0] >= 0 or l[1] <= 0) and (r[0] >= 0 or r[1] <= 0)):
            # At its kink at m: never across it within either half, so m is its only crossing.
            raise refuse
    if not (left == right and math.isfinite(right) and abs(right) <= MAGNITUDE):
        raise refuse
    return right


def gauss(f, a, b, panels, values):
    """Mirror of `MGReadout.gauss`: the composite 5-point Gauss-Legendre rule for f and |f|."""
    total, total_abs = 0.0, 0.0
    for k in range(panels):
        lo = a + (b - a) * k / panels
        hi = b if k == panels - 1 else a + (b - a) * (k + 1) / panels
        mid, half = (lo + hi) / 2, (hi - lo) / 2
        s, t = 0.0, 0.0
        for node, weight in zip(GAUSS_NODES, GAUSS_WEIGHTS):
            y = f(mid + half * node)
            values.append(y)
            s += weight * y
            t += weight * abs(y)
        total += half * s
        total_abs += half * t
    return total, total_abs


def area_readout(f, enclose, s0, s1, y0, y1):
    """Mirror of `MGReadout.area`: certify, then the signed area over [s0, s1] with its error estimate and the view
    checks on every sampled value."""
    refuse = Refusal("func.readouts.area")
    certify_area(enclose, s0, s1, y0, y1)
    fine, coarse = [], []
    a_sum, a_abs = gauss(f, s0, s1, READOUT_PANELS, fine)
    b_sum, b_abs = gauss(f, s0, s1, READOUT_PANELS // 2, coarse)
    samples = fine + coarse + [f(s0), f(s1)]
    if not all(math.isfinite(v) for v in samples):
        raise refuse
    tolerance = resolution(a_sum) / 2
    if not (abs(a_sum - b_sum) <= tolerance and abs(a_abs - b_abs) <= max(tolerance, a_abs / 1024)
            and abs(a_sum) <= MAGNITUDE):
        raise refuse
    if not (y0 <= 0 and y1 >= 0 and all(y0 <= v <= y1 for v in samples)):
        raise Refusal("func.readouts.view")
    return a_sum


def certify_area(enclose, s0, s1, y0, y1):
    """Mirror of `MGReadout.certify`: bounded subdivision (CERTIFY_DEPTH halvings, CERTIFY_BUDGET enclosures) that
    proves f continuous on [s0, s1] and inside the y range, to the drawing tolerance."""
    slack = FUNC_TOLERANCE * (y1 - y0)
    cells = [(s0, s1, 0)]
    used = 0
    while cells:
        a, b, depth = cells.pop()
        used += 1
        if used > CERTIFY_BUDGET:
            raise Refusal("func.readouts.area")
        e = enclose(a, b)
        if e is not None and e[0] >= y0 - slack and e[1] <= y1 + slack:
            continue
        if depth >= CERTIFY_DEPTH:
            raise Refusal("func.readouts.area" if e is None else "func.readouts.view")
        mid = a + (b - a) / 2
        cells.append((mid, b, depth + 1))
        cells.append((a, mid, depth + 1))


def parse_readouts(raw):
    """Mirror of `MGReadout.parse`: 1 to 3 distinct readout names."""
    if not isinstance(raw, list) or not 1 <= len(raw) <= len(READOUTS):
        raise Refusal("func.readouts")
    out = []
    for entry in raw:
        if not isinstance(entry, str) or entry not in READOUTS or entry in out:
            raise Refusal("func.readouts")
        out.append(entry)
    return out


def readout_placeholder(name):
    """Mirror of `MGReadout.placeholder`: `<id>.<readout>` with an id `MGParser.identifier` takes, else None."""
    if "." not in name:
        return None
    identifier, readout = name.split(".", 1)
    if readout not in READOUTS:
        return None
    try:
        _identifier(identifier, "id")
    except Refusal:
        return None
    return name


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


def text_rules(value, limit, reason, values=None, multiline=False):
    """The plain-text rules of `MGParser.text` for a scene without template values. `values` maps the scene's readout
    placeholders (`<id>.<readout>`) to their numbers; returns the filled text."""
    if not isinstance(value, str):
        raise Refusal(reason)
    trimmed = _trim(value)
    if not trimmed or len(value) > limit or "<" in value or ">" in value or "```" in value or "://" in value:
        raise Refusal(reason)
    # Swift's `CharacterSet.controlCharacters` (general categories Cc and Cf) and U+2028 / U+2029 (Zl, Zp). Labels and
    # `alt` are single-line text, so a line feed is refused too; only text items and narration may break lines.
    if any(unicodedata.category(ch) in ("Cc", "Cf", "Zl", "Zp") and not (multiline and ch == "\n") for ch in value):
        raise Refusal(reason)
    values = values or {}
    out, name, i = [], None, 0
    while i < len(trimmed):
        ch = trimmed[i]
        i += 1
        if name is None and ch == "{":
            end = trimmed.find("}", i)
            readout = readout_placeholder(trimmed[i:end]) if end >= 0 else None
            if readout is not None:
                # A `func` readout (`MGReadout`): filled from the engine's value, else refused.
                if readout not in values:
                    raise Refusal(reason + ".placeholder.readout")
                out.append(format_number(values[readout]))
                i = end + 1
                continue
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
        else:
            out.append(ch)
    if name is not None:
        raise Refusal(reason + ".brace")
    filled = "".join(out)
    if len(filled) > limit:
        raise Refusal(reason)
    return filled


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


FUNC_KEYS = {"id", "k", "color", "at", "w", "h", "xr", "yr", "y", "a", "b", "c", "period", "shade", "mark", "readouts",
             "xl", "yl", "label"}
TEXT_KEYS = ("label", "xl", "yl")
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


def check_graph_item(item, world=(12, 8), is3d=False, values=None, texts=True):
    """The `func` / `field` rules of `MGParser.item` in Swift's order: closed keys, id, color, label, then the kind's
    keys. `is3d`: the scene is 3D, so `at` may have three coordinates, as `MGParser.point` allows; the item is then
    refused as `3d.kind.<kind>` by `check_scene` after every item has been checked, as in Swift. `values`: the scene's
    readout values for the texts. `texts=False` skips `label`, `xl` and `yl`, as Swift's readout pass does.

    Returns a summary dict (a `func` also lists its `readouts` by name); raises Refusal with the Swift reason.
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
    if texts and "label" in item:
        text_rules(item["label"], LABEL, "item.label", values)
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
        requested = []
        if "readouts" in item:
            # Mirror of `MGReadout.parse` and `checkKeys`, before anything is sampled.
            requested = parse_readouts(item["readouts"])
            if period is not None:
                raise Refusal("func.readouts.period")
            if any(r != "area" for r in requested) and mark is None:
                raise Refusal("func.readouts.mark")
            if "area" in requested and shade is None:
                raise Refusal("func.readouts.shade")
        first, marked = check_function(expr, x0, x1, y0, y1, params, period, shade, mark, width=w, height=h)
        readouts = {}
        for name in READOUTS:
            if name not in requested:
                continue
            if name == "value":
                readouts[name] = marked
            elif name == "slope":
                readouts[name] = slope_readout(expr, params, mark, x0, x1, first)
            else:
                readouts[name] = area_readout(lambda x: expr.value(x=x, **params),
                                              lambda lo, hi: expr.enclosure(lo, hi, **params),
                                              shade[0], shade[1], y0, y1)
        if texts:
            graph_texts(item, values)
        return {"samples": len(first.samples), "starts": list(first.starts), "mark": marked, "readouts": readouts}
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
    if texts:
        graph_texts(item, values)
    vectors, missing = field_vectors(dx, dy, x0, x1, y0, y1, int(cols), int(rows), params)
    if not any(u != 0 or v != 0 for u, v in vectors):
        raise Refusal("field.empty")
    return {"cols": int(cols), "rows": int(rows), "missing": missing, "vectors": vectors}


def _reason_keys(keys):
    """Mirror of `MGParser.reasonKeys`: at most four names, and a name that is not 1-24 ASCII letters, digits or `_`
    becomes `?`. `keys` must already be in Swift's order (sorted by Unicode scalar)."""
    return ",".join(key if 1 <= len(key) <= 24 and key.isascii() and all(_letter(ch) or _digit(ch) or ch == "_" for ch in key)
                    else "?" for key in keys[:4])


class SliderGrid:
    """Mirror of `MGSlider`'s grid and number form: `value(at:)`, `stop(nearest:)`, `text`, `gridIsDistinct`.

    Swift's `String(format: "%.Nf")` / `"%.Ne"` and `Double(text)` are C's printf and a correctly rounded parse, as are
    Python's `%` formatting and `float`.
    """

    def __init__(self, lo, hi, step, steps, initial=None, default_stop=0):
        self.lo, self.hi, self.step, self.steps = lo, hi, step, steps
        self.initial = lo if initial is None else initial
        self.default_stop = default_stop
        self.decimals = slider_decimals([lo, step])

    def candidate_at(self, stop):
        """Mirror of `MGSlider.candidate(at:)`: min, max, else the interpolated stop snapped to `decimals` places."""
        i = min(max(stop, 0), self.steps)
        if i == 0:
            return self.lo
        if i == self.steps:
            return self.hi
        raw = self.lo + (self.hi - self.lo) * i / self.steps
        snapped = float(_trimmed("%.*f" % (self.decimals, raw)))
        return snapped if abs(snapped - raw) <= self.step * 1e-6 else raw

    def value_at(self, stop):
        """Mirror of `MGSlider.value(at:)`: the number the stop's label reads as, so the engine gets what is shown.
        The default never stands in for a stop (the parser requires it to equal one exactly)."""
        return float(self.text(self.candidate_at(stop)))

    def stop_nearest(self, value):
        if not math.isfinite(value):
            return self.default_stop
        q = round_half_away((value - self.lo) / self.step)
        return int(min(max(q, 0), self.steps))

    def names(self, text, value):
        try:
            read = float(text)
        except ValueError:
            return False
        if read == 0 or value == 0:
            return read == value
        return abs(read - value) <= self.step * 1e-6

    def text(self, value):
        if not math.isfinite(value):
            return "\u2014"
        compact = _trimmed("%.*f" % (self.decimals, value))
        if self.names(compact, value):
            return compact
        for digits in range(1, 18):
            s = _significant(value, digits)
            if self.names(s, value):
                return s
        return _significant(value, 17)

    def is_distinct(self):
        """Mirror of `MGSlider.gridIsDistinct`: each end reads back as exactly that end, and every stop's value is
        exactly the number its label reads as, within min...max, above the stop before, with a label of its own."""
        if self.value_at(0) != self.lo or self.value_at(self.steps) != self.hi:
            return False
        previous, labels = -math.inf, set()
        for i in range(self.steps + 1):
            v = self.value_at(i)
            if not (v > previous and self.lo <= v <= self.hi):
                return False
            previous = v
            label = self.text(v)
            if float(label) != v or self.stop_nearest(v) != i or label in labels:
                return False
            labels.add(label)
        return True

    def stop_of(self, value):
        """Mirror of `MGSlider.stop(exactly:)`: the stop whose value is exactly `value`, or None."""
        return next((i for i in range(self.steps + 1) if self.value_at(i) == value), None)


def _trimmed(text):
    if "." in text:
        text = text.rstrip("0")
        if text.endswith("."):
            text = text[:-1]
    return "0" if text == "-0" else text


def _significant(value, digits):
    e = "%.*e" % (digits - 1, value)
    mantissa, exponent = e.split("e")
    rounded = float(e)
    if rounded == 0:
        return "0"
    exponent = int(exponent)
    if exponent >= -9:
        return _trimmed("%.*f" % (max(0, digits - 1 - exponent), rounded))
    return _trimmed(mantissa) + "e" + str(exponent)


def slider_decimals(values):
    """Mirror of `MGSlider.decimals`: the fewest places (0-6) that write every value exactly."""
    out = 0
    for v in values:
        places = 0
        while places < 6:
            scaled = v * 10.0 ** places
            if abs(scaled - round_half_away(scaled)) <= 1e-9 * max(1, abs(scaled)):
                break
            places += 1
        out = max(out, places)
    return out


def check_slider(entry, seen=()):
    """The rules of one slider that need no scene (`MGParser.sliders` up to the label), in Swift's order.

    Returns (param, min, max, step, default, steps, default_stop); raises Refusal.
    """
    if not isinstance(entry, dict):
        raise Refusal("slider")
    if not set(SLIDER_KEYS) <= set(entry):
        raise Refusal("slider.missing")
    extra = set(entry) - set(SLIDER_KEYS)
    if extra:
        raise Refusal("slider.unknown." + _reason_keys(sorted(extra)))
    param = entry["param"]
    if not isinstance(param, str) or param not in ("a", "b", "c"):
        raise Refusal("slider.param")
    if param in seen:
        raise Refusal("slider.duplicate." + param)
    lo = _num(entry["min"], -EXPR_PARAMETER, EXPR_PARAMETER, "slider.min")
    hi = _num(entry["max"], -EXPR_PARAMETER, EXPR_PARAMETER, "slider.max")
    if not lo < hi:
        raise Refusal("slider.range")
    step = entry["step"]
    # Swift: a number from the least positive double to max - min. An int is compared exactly before conversion.
    if not _number(step) or not 0 < step <= hi - lo:
        raise Refusal("slider.step")
    step = float(step)
    q = _divide(hi - lo, step)
    if not q < SLIDER_STEPS + 0.5:
        raise Refusal("slider.step.count")
    count = round_half_away(q)
    if not abs(q - count) <= 1e-9 * count:
        raise Refusal("slider.step")
    # The bare grid: every stop its own value and label.
    grid = SliderGrid(lo, hi, step, int(count))
    if not grid.is_distinct():
        raise Refusal("slider.grid")
    initial = _num(entry["default"], lo, hi, "slider.default")
    # The default is a stop: exactly the number some stop's label reads as.
    at = grid.stop_of(initial)
    if at is None:
        raise Refusal("slider.default")
    label = entry["label"]
    # A label is fixed text: an engine number filled in once would go stale when the slider moves.
    if isinstance(label, str) and ("{" in label or "}" in label):
        raise Refusal("slider.label.placeholder")
    text_rules(label, LABEL, "slider.label")
    return param, lo, hi, step, initial, int(count), int(at)


def check_sliders(scene, world=(12.0, 8.0), is3d=False, literal=True, values=None):
    """Mirror of `MGParser.sliders` on a scene whose items and steps passed their own rules.

    `literal`: the scene lists its own items. A template scene's items are known only after Swift expands it, so then
    only each slider's own rules run (the binding rules need the items). `values`: the scene's readout values, for
    the texts of a driven item checked at the ends of the range (Swift checks the item with its texts filled). Returns
    one summary dict per slider (param, steps, defaultStop, items); raises Refusal with the Swift reason.
    """
    raw = scene["sliders"]
    if not isinstance(raw, list) or not 1 <= len(raw) <= SLIDERS:
        raise Refusal("sliders")
    listed = scene.get("items")
    items = [item for item in listed if isinstance(item, dict)] if isinstance(listed, list) else []
    graphs = {item.get("id") for item in items if item.get("k") in ("func", "field")}
    seen, out, bindings = [], [], 0
    for entry in raw:
        param, lo, hi, _, initial, steps, default_stop = check_slider(entry, seen)
        seen.append(param)
        summary = {"param": param, "steps": steps, "defaultStop": default_stop, "items": []}
        out.append(summary)
        if not literal:
            continue
        driven = [item for item in items if item.get("k") == "func" and param in item]
        if not driven:
            raise Refusal("slider.unbound")
        if any(item.get("k") == "field" and param in item for item in items):
            raise Refusal("slider.field")
        for item in driven:
            if float(item[param]) != initial:
                raise Refusal("slider.default." + item["id"])
        bindings += len(driven)
        if bindings > SLIDER_BINDINGS:
            raise Refusal("sliders.bindings")
        steps = scene.get("steps")
        for step in steps if isinstance(steps, list) else []:
            edits = step.get("do") if isinstance(step, dict) else None
            for edit in edits if isinstance(edits, list) else []:
                if isinstance(edit, dict) and edit.get("key") == param and edit.get("id") in graphs:
                    raise Refusal("slider.edit")
        # Both ends of the range, with every other parameter at its default, through the item rules.
        for item in driven:
            for end, value in (("min", lo), ("max", hi)):
                if value == initial:
                    continue
                try:
                    check_graph_item({**item, param: value}, world, is3d, values)
                except Refusal as refusal:
                    raise Refusal(f"slider.{param}.{end}.{refusal.reason}") from refusal
        summary["items"] = [item["id"] for item in driven]
    return out


def graph_texts(item, values=None):
    """The axis labels of a graph item (and, for `func` checked without texts, its label too: `MGParser.functionTexts`
    sets the label first). Returns nothing; raises Refusal."""
    for key in ("xl", "yl"):
        if key in item:
            text_rules(item[key], LABEL, item["k"] + "." + key, values)


def _reason_key(key):
    """Mirror of `MGParser.reasonKeys` for one key."""
    if isinstance(key, str) and 1 <= len(key) <= 24 and key.isascii() and all(ch.isalnum() or ch == "_" for ch in key):
        return key
    return "?"


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
    """The new rules on a scene object: the `alt` keys, the `items.expr` count, every `func` / `field` item and the
    `sliders` key.

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
    # Readouts first, as `MGParser.parseScene` computes them: each `func` that lists them is checked without its
    # texts, in order, and every text of the scene can then name them.
    early = {}
    for index, item in enumerate(items):
        if isinstance(item, dict) and item.get("k") == "func" and "readouts" in item:
            early[index] = check_graph_item(item, world, is3d, texts=False)
    values = readout_values(items, early)
    summaries = {}
    for index, item in enumerate(items):
        if not (isinstance(item, dict) and item.get("k") in ("func", "field")):
            continue
        if index in early:
            # `MGParser.functionTexts`: the label, then the axis labels.
            summary = early[index]
            if "label" in item:
                text_rules(item["label"], LABEL, "item.label", values)
            graph_texts(item, values)
        else:
            # check_graph_item refuses a missing id (`item.<kind>.missing`) or a malformed one (`item.id`) first, so
            # the summary key is always a valid id.
            summary = check_graph_item(item, world, is3d, values)
        summaries[item["id"]] = summary
    for step in scene.get("steps", []):
        if isinstance(step, dict) and "alt" in step:
            text_rules(step["alt"], SAY, "step.alt", values)
    if "alt" in scene:
        text_rules(scene["alt"], SAY, "alt", values)
    if is3d and graphs:
        raise Refusal("3d.kind." + graphs[0]["k"])
    check_graph_edits(scene, world, is3d, values)
    if "sliders" in scene:
        check_sliders(scene, world, is3d, values=values)
    return summaries


def readout_values(items, summaries):
    """Mirror of `MGReadout.values`: `<id>.<readout>` for the readouts of the checked items (`summaries` by index), in
    order; the first item with an id wins."""
    values = {}
    for index in sorted(summaries):
        for name, value in summaries[index].get("readouts", {}).items():
            values.setdefault(items[index]["id"] + "." + name, value)
    return values


def check_graph_edits(scene, world, is3d, values):
    """The step edits of graph items, cumulatively, as `MGParser.checkReferences` applies them: the key must be one
    the kind allows (`edit.key.<key>`), the edited item must pass, and an edit may not change a readout the scene's
    text names (`func.readouts.edit`). Edits of other kinds are left to Swift."""
    current = {item["id"]: item for item in scene.get("items", []) if isinstance(item, dict) and "id" in item}
    for step in scene.get("steps", []):
        if not isinstance(step, dict):
            continue
        for edit in step.get("do", []):
            if not isinstance(edit, dict):
                continue
            item = current.get(edit.get("id"))
            if not isinstance(item, dict) or item.get("k") not in ("func", "field"):
                continue
            key = edit.get("key")
            if not isinstance(key, str) or key in ("id", "k"):
                continue  # `edit.key`, refused when Swift parses the step
            if key not in (FUNC_KEYS if item["k"] == "func" else FIELD_KEYS):
                raise Refusal("edit.key." + _reason_key(key))
            updated = dict(item)
            updated[key] = edit.get("value")
            summary = check_graph_item(updated, world, is3d, values)
            for name in READOUTS:
                published = values.get(item["id"] + "." + name)
                if published is not None and summary.get("readouts", {}).get(name) != published:
                    raise Refusal("func.readouts.edit")
            current[item["id"]] = updated
