# SPDX-License-Identifier: Apache-2.0
"""Offline reference for math text: the `math` style of a scene v1 `text` item.

Swift is authoritative: `MGMathText` in Sources/MartyGraphics/MGMathText.swift. This module mirrors its tokenizer,
parser, refusal order and spoken form rule for rule (not its layout, which only the renderers need), so an offline
preflight (tools/scene_v1_check.py) gives the same reasons, and the shared golden cases in
docs/fixtures/v1/math.cases.json run in Python as well as in XCTest. Standard library only; never imports or evaluates
scene text as Python.

    python3 tools/mg_math.py "x^2 + 2 x"     # prints the spoken form, or the refusal reason
"""

import sys

try:
    from tools import mg_expr
except ImportError:  # run as tools/mg_math.py
    import mg_expr

MATH_LENGTH = 80
MATH_TOKENS = 48
MATH_DEPTH = 4
REASON = "text.math"

GREEK = (
    ("alpha", "α"), ("beta", "β"), ("gamma", "γ"), ("delta", "δ"), ("epsilon", "ε"), ("zeta", "ζ"), ("eta", "η"),
    ("theta", "θ"), ("iota", "ι"), ("kappa", "κ"), ("lambda", "λ"), ("mu", "μ"), ("nu", "ν"), ("xi", "ξ"),
    ("pi", "π"), ("rho", "ρ"), ("sigma", "σ"), ("tau", "τ"), ("upsilon", "υ"), ("phi", "φ"), ("chi", "χ"),
    ("psi", "ψ"), ("omega", "ω"), ("Gamma", "Γ"), ("Delta", "Δ"), ("Theta", "Θ"), ("Lambda", "Λ"), ("Xi", "Ξ"),
    ("Pi", "Π"), ("Sigma", "Σ"), ("Upsilon", "Υ"), ("Phi", "Φ"), ("Psi", "Ψ"), ("Omega", "Ω"),
)
GREEK_LETTER = dict(GREEK)
GREEK_NAME = {letter: name for name, letter in GREEK}

UNITS = (
    ("m", "m", "metre", "metres"), ("cm", "cm", "centimetre", "centimetres"), ("mm", "mm", "millimetre", "millimetres"),
    ("km", "km", "kilometre", "kilometres"), ("nm", "nm", "nanometre", "nanometres"),
    ("s", "s", "second", "seconds"), ("ms", "ms", "millisecond", "milliseconds"), ("min", "min", "minute", "minutes"),
    ("h", "h", "hour", "hours"), ("kg", "kg", "kilogram", "kilograms"), ("g", "g", "gram", "grams"),
    ("mg", "mg", "milligram", "milligrams"), ("N", "N", "newton", "newtons"), ("kN", "kN", "kilonewton", "kilonewtons"),
    ("J", "J", "joule", "joules"), ("kJ", "kJ", "kilojoule", "kilojoules"), ("eV", "eV", "electronvolt", "electronvolts"),
    ("W", "W", "watt", "watts"), ("kW", "kW", "kilowatt", "kilowatts"), ("Pa", "Pa", "pascal", "pascals"),
    ("kPa", "kPa", "kilopascal", "kilopascals"), ("Hz", "Hz", "hertz", "hertz"), ("kHz", "kHz", "kilohertz", "kilohertz"),
    ("V", "V", "volt", "volts"), ("mV", "mV", "millivolt", "millivolts"), ("A", "A", "ampere", "amperes"),
    ("mA", "mA", "milliampere", "milliamperes"), ("C", "C", "coulomb", "coulombs"), ("ohm", "Ω", "ohm", "ohms"),
    ("T", "T", "tesla", "teslas"), ("K", "K", "kelvin", "kelvins"), ("degC", "°C", "degree Celsius", "degrees Celsius"),
    ("deg", "°", "degree", "degrees"), ("rad", "rad", "radian", "radians"), ("mol", "mol", "mole", "moles"),
    ("L", "L", "litre", "litres"), ("mL", "mL", "millilitre", "millilitres"), ("percent", "%", "percent", "percent"),
)
UNIT_INDEX = {unit[0]: index for index, unit in enumerate(UNITS)}

FUNCTIONS = {
    "sin": "sine", "cos": "cosine", "tan": "tangent", "asin": "arc sine", "acos": "arc cosine",
    "atan": "arc tangent", "sinh": "hyperbolic sine", "cosh": "hyperbolic cosine", "tanh": "hyperbolic tangent",
    "exp": "the exponential", "ln": "the natural log", "log": "the log", "sqrt": "the square root",
    "abs": "the absolute value", "min": "the minimum", "max": "the maximum",
}
assert tuple(FUNCTIONS) == mg_expr.FUNCTIONS
PARENS_REQUIRED = ("sqrt", "abs", "min", "max")
SYMBOLS = frozenset(" .+-*/^_()[],=±·×−≤≥≠≈°")

SIGNS = {"+": "plus", "-": "minus", "±": "plusMinus"}
PRODUCTS = {"*": "dot", "·": "dot", "×": "cross"}
RELATIONS = {"=": "equals", "≠": "notEqual", "≈": "approx", "≤": "lessEqual", "≥": "greaterEqual"}
SPOKEN_OPS = {
    "plus": "plus", "minus": "minus", "plusMinus": "plus or minus", "dot": "times", "cross": "times",
    "equals": "equals", "notEqual": "is not equal to", "approx": "is approximately equal to",
    "lessEqual": "is less than or equal to", "greaterEqual": "is greater than or equal to",
}


class Refusal(ValueError):
    """A refusal with the Swift reason token."""

    def __init__(self, reason):
        super().__init__(reason)
        self.reason = reason


def _in_alphabet(ch):
    return mg_expr._letter(ch) or mg_expr._digit(ch) or ch in SYMBOLS or ch in GREEK_NAME


def _tokenize(text):
    """Lexemes `(kind, value, spaced)`; kinds number (as written), name, greek (by name) and symbol."""
    out = []
    i = 0
    spaced = False
    while i < len(text):
        ch = text[i]
        if ch == " ":
            spaced = True
            i += 1
            continue
        if mg_expr._digit(ch) or ch == ".":
            j = i
            while j < len(text) and mg_expr._digit(text[j]):
                j += 1
            if j < len(text) and text[j] == ".":
                j += 1
                fraction = j
                while j < len(text) and mg_expr._digit(text[j]):
                    j += 1
                if j == fraction:
                    raise Refusal(REASON + ".syntax")
            if j - i > mg_expr.NUMBER_LENGTH:
                raise Refusal(REASON + ".syntax")
            token = ("number", text[i:j])
            i = j
        elif mg_expr._letter(ch):
            j = i
            while j < len(text) and mg_expr._letter(text[j]):
                j += 1
            token = ("name", text[i:j])
            i = j
        elif ch in GREEK_NAME:
            token = ("greek", GREEK_NAME[ch])
            i += 1
        elif ch == "+" and i + 1 < len(text) and text[i + 1] == "-":
            token = ("symbol", "±")
            i += 2
        else:
            token = ("symbol", "-" if ch == "−" else ch)
            i += 1
        out.append((token[0], token[1], spaced))
        spaced = False
    return out


def depth(node):
    kind = node[0]
    if kind in ("number", "degree", "variable", "greek", "infinity", "word", "unit"):
        return 0
    if kind == "group":
        return 1 + max(depth(p) for p in node[1])
    if kind == "apply":
        return 1 + max(depth(p) for p in node[2])
    if kind == "function":
        return 1 + max(depth(p) for p in node[2])
    if kind == "script":
        _, base, sub, sup = node
        return max(depth(base), 1 + depth(sub) if sub else 0, 1 + depth(sup) if sup else 0)
    if kind == "fraction":
        return 1 + max(depth(node[1]), depth(node[2]))
    if kind == "sign":
        return depth(node[2])
    if kind == "row":
        return max(depth(n) for n in (node[1],) + tuple(link[1] for link in node[2]))
    raise AssertionError(kind)


def _stripped(node):
    if node[0] == "group" and len(node[1]) == 1:
        return node[1][0]
    return node


class _Parser:
    def __init__(self, lexemes):
        self.lexemes = lexemes
        self.index = 0

    def next(self):
        return self.lexemes[self.index] if self.index < len(self.lexemes) else None

    def symbol(self):
        lexeme = self.next()
        return lexeme[1] if lexeme and lexeme[0] == "symbol" else None

    def spaced(self):
        lexeme = self.next()
        return lexeme[2] if lexeme else False

    @staticmethod
    def syntax():
        return Refusal(REASON + ".syntax")

    @staticmethod
    def unit_error():
        return Refusal(REASON + ".unit")

    def relation(self):
        first = self.sum()
        links = []
        while self.symbol() in RELATIONS:
            op = RELATIONS[self.symbol()]
            self.index += 1
            links.append((op, self.sum()))
        return ("row", first, tuple(links)) if links else first

    def sum(self):
        if self.symbol() in SIGNS:
            op = SIGNS[self.symbol()]
            self.index += 1
            first = ("sign", op, self.product())
        else:
            first = self.product()
        links = []
        while self.symbol() in SIGNS:
            op = SIGNS[self.symbol()]
            self.index += 1
            links.append((op, self.product()))
        return ("row", first, tuple(links)) if links else first

    def product(self):
        first = self.factor()
        links = []
        while True:
            if self.symbol() in PRODUCTS:
                op = PRODUCTS[self.symbol()]
                self.index += 1
                if self.symbol() in SIGNS:
                    sign = SIGNS[self.symbol()]
                    self.index += 1
                    links.append((op, ("sign", sign, self.factor())))
                else:
                    links.append((op, self.factor()))
            elif self.starts_factor():
                links.append(("implicit", self.factor()))
            else:
                break
        return ("row", first, tuple(links)) if links else first

    def starts_factor(self):
        lexeme = self.next()
        if lexeme is None:
            return False
        if lexeme[0] in ("number", "name", "greek"):
            return True
        return lexeme[1] in ("(", "[")

    def factor(self):
        top = self.script()
        if self.symbol() != "/":
            return top
        self.index += 1
        bottom = self.script()
        if self.symbol() == "/":
            raise self.syntax()
        return ("fraction", _stripped(top), _stripped(bottom))

    def script(self):
        base = self.primary()
        sub = sup = None
        if self.symbol() == "_":
            self.index += 1
            sub = _stripped(self.subscript_part())
        if self.symbol() == "^":
            self.index += 1
            if self.symbol() in SIGNS:
                op = SIGNS[self.symbol()]
                self.index += 1
                sup = ("sign", op, _stripped(self.atom()))
            else:
                sup = _stripped(self.atom())
        if sub is None and sup is None:
            return base
        return ("script", base, sub, sup)

    def subscript_part(self):
        lexeme = self.next()
        if lexeme is None:
            raise self.syntax()
        kind, value, _ = lexeme
        if kind == "number":
            self.index += 1
            return ("number", value)
        if kind == "greek":
            self.index += 1
            return ("greek", value)
        if kind == "name":
            self.index += 1
            if value in GREEK_LETTER:
                return ("greek", value)
            return ("variable", value) if len(value) == 1 else ("word", value)
        if value == "(":
            return self.parenthesised()
        raise self.syntax()

    def atom(self):
        lexeme = self.next()
        if lexeme is None:
            raise self.syntax()
        kind, value, _ = lexeme
        if kind == "number":
            self.index += 1
            return ("number", value)
        if kind == "greek":
            self.index += 1
            return ("greek", value)
        if kind == "name":
            return self.named(True)
        if value == "(":
            return self.parenthesised()
        raise self.syntax()

    def primary(self):
        lexeme = self.next()
        if lexeme is None:
            raise self.syntax()
        kind, value, _ = lexeme
        if kind == "number":
            self.index += 1
            if self.symbol() == "°" and not self.spaced():
                self.index += 1
                return ("degree", value)
            return ("number", value)
        if kind == "greek":
            self.index += 1
            return ("greek", value)
        if kind == "name":
            return self.named(False)
        if value == "(":
            return self.parenthesised()
        if value == "[":
            self.index += 1
            return self.unit()
        raise self.syntax()

    def named(self, parens_required):
        lexeme = self.next()
        if lexeme is None or lexeme[0] != "name":
            raise self.syntax()
        name = lexeme[1]
        self.index += 1
        if name in FUNCTIONS:
            if self.symbol() == "(":
                args = self.arguments()
                if len(args) != (2 if name in ("min", "max") else 1):
                    raise self.syntax()
                return ("function", name, args, True)
            if parens_required or name in PARENS_REQUIRED:
                raise self.syntax()
            return ("function", name, (self.script(),), False)
        if name in GREEK_LETTER:
            return ("greek", name)
        if name == "inf":
            return ("infinity",)
        if len(name) != 1:
            raise Refusal(REASON + ".name")
        if self.symbol() == "(" and not self.spaced():
            return ("apply", name, self.arguments())
        return ("variable", name)

    def parenthesised(self):
        return ("group", self.arguments())

    def arguments(self):
        if self.symbol() != "(":
            raise self.syntax()
        self.index += 1
        parts = [self.relation()]
        while self.symbol() == ",":
            self.index += 1
            parts.append(self.relation())
        if self.symbol() != ")":
            raise self.syntax()
        self.index += 1
        return tuple(parts)

    def unit(self):
        top = self.unit_product()
        bottom = ()
        if self.symbol() == "/":
            self.index += 1
            if self.symbol() == "(":
                self.index += 1
                bottom = self.unit_product()
                if self.symbol() != ")":
                    raise self.unit_error()
                self.index += 1
            else:
                bottom = (self.unit_term(),)
        if self.symbol() != "]":
            raise self.unit_error()
        self.index += 1
        return ("unit", top, bottom)

    def unit_product(self):
        terms = [self.unit_term()]
        while True:
            lexeme = self.next()
            if self.symbol() in ("*", "·"):
                self.index += 1
                terms.append(self.unit_term())
            elif lexeme is not None and lexeme[0] == "name":
                terms.append(self.unit_term())
            else:
                return tuple(terms)

    def unit_term(self):
        lexeme = self.next()
        if lexeme is None or lexeme[0] != "name" or lexeme[1] not in UNIT_INDEX:
            raise self.unit_error()
        unit = UNIT_INDEX[lexeme[1]]
        self.index += 1
        if self.symbol() != "^":
            return (unit, 1)
        self.index += 1
        lexeme = self.next()
        if lexeme is None or lexeme[0] != "number" or lexeme[1] not in ("2", "3"):
            raise self.unit_error()
        self.index += 1
        return (unit, int(lexeme[1]))


# MARK: spoken form

def _atom(node):
    return node[0] in ("number", "degree", "variable", "greek", "infinity", "word")


def _simple(node):
    if _atom(node):
        return True
    return node[0] == "script" and node[3] is None and node[2] is not None and _atom(node[1]) and _atom(node[2])


NUMERATORS = ("one", "two", "three", "four", "five", "six", "seven", "eight", "nine")
DENOMINATORS = (("half", "halves"), ("third", "thirds"), ("quarter", "quarters"), ("fifth", "fifths"),
                ("sixth", "sixths"), ("seventh", "sevenths"), ("eighth", "eighths"), ("ninth", "ninths"),
                ("tenth", "tenths"))


def _whole(literal, low, high):
    return literal.isdigit() and literal.isascii() and str(int(literal)) == literal and low <= int(literal) <= high


def _fraction_words(top, bottom):
    if top[0] != "number" or bottom[0] != "number" or not _whole(top[1], 1, 9) or not _whole(bottom[1], 2, 10):
        return None
    t, d = int(top[1]), int(bottom[1])
    names = DENOMINATORS[d - 2]
    return NUMERATORS[t - 1] + " " + (names[0] if t == 1 else names[1])


def _unit_words(top, bottom, plural):
    words = []
    for k, (unit, power) in enumerate(top):
        name = UNITS[unit][3] if k == len(top) - 1 and plural else UNITS[unit][2]
        words.append({2: "square ", 3: "cubic "}.get(power, "") + name)
    text = " ".join(words)
    if bottom:
        text += " per " + " ".join(UNITS[unit][2] + {2: " squared", 3: " cubed"}.get(power, "") for unit, power in bottom)
    return text


def _arguments(parts):
    if len(parts) == 1 and _simple(parts[0]):
        return speak(parts[0])
    return "open paren " + " comma ".join(speak(p) for p in parts) + " close paren"


def speak(node):
    kind = node[0]
    if kind == "number":
        return node[1]
    if kind == "degree":
        return node[1] + (" degree" if node[1] == "1" else " degrees")
    if kind == "variable":
        return node[1]
    if kind == "greek":
        name = node[1]
        return "capital " + name.lower() if name[0].isupper() else name
    if kind == "infinity":
        return "infinity"
    if kind == "word":
        return node[1]
    if kind == "unit":
        return _unit_words(node[1], node[2], True)
    if kind == "group":
        parts = node[1]
        if len(parts) == 1 and _simple(parts[0]):
            return speak(parts[0])
        return "open paren " + " comma ".join(speak(p) for p in parts) + " close paren"
    if kind == "function":
        _, name, parts, parens = node
        word = FUNCTIONS[name]
        if name == "sqrt":
            return word + " of " + speak(parts[0]) + ("" if _simple(parts[0]) else " end root")
        if name == "abs":
            return word + " of " + speak(parts[0]) + ("" if _simple(parts[0]) else " end absolute value")
        if name in ("min", "max"):
            return word + " of " + speak(parts[0]) + " and " + speak(parts[1])
        return word + " of " + (_arguments(parts) if parens else speak(parts[0]))
    if kind == "apply":
        return node[1] + " of " + _arguments(node[2])
    if kind == "script":
        _, base, sub, sup = node
        text = speak(base)
        if sub is not None:
            text += " sub " + speak(sub) + ("" if _simple(sub) else " end sub")
        if sup is not None:
            if sup == ("number", "2"):
                text += " squared"
            elif sup == ("number", "3"):
                text += " cubed"
            else:
                plain = _simple(sup) or (sup[0] == "sign" and _simple(sup[2]))
                text += " to the power " + speak(sup) + ("" if plain else " end power")
        return text
    if kind == "fraction":
        _, top, bottom = node
        words = _fraction_words(top, bottom)
        if words is not None:
            return words
        if _simple(top) and _simple(bottom):
            return speak(top) + " over " + speak(bottom)
        return "the fraction with numerator " + speak(top) + " and denominator " + speak(bottom)
    if kind == "sign":
        return SPOKEN_OPS[node[1]] + " " + speak(node[2])
    if kind == "row":
        _, first, links = node
        text = speak(first)
        previous = first
        for op, part in links:
            if op == "implicit" and part[0] == "unit":
                spoken = _unit_words(part[1], part[2], previous != ("number", "1"))
            else:
                spoken = speak(part)
            text += " " + spoken if op == "implicit" else " " + SPOKEN_OPS[op] + " " + spoken
            previous = part
        return text
    raise AssertionError(kind)


def parse(text):
    """The parsed tree of `text` (`MGMathText.parse`); raises `Refusal` with the Swift reason."""
    if not isinstance(text, str) or len(text) > MATH_LENGTH or not any(ch != " " for ch in text) \
            or not all(_in_alphabet(ch) for ch in text):
        raise Refusal(REASON)
    lexemes = _tokenize(text)
    if len(lexemes) > MATH_TOKENS:
        raise Refusal(REASON + ".tokens")
    open_count = deepest = 0
    for kind, value, _ in lexemes:
        if kind == "symbol" and value == "(":
            open_count += 1
            deepest = max(deepest, open_count)
        if kind == "symbol" and value == ")":
            open_count -= 1
    if deepest > MATH_DEPTH:
        raise Refusal(REASON + ".depth")
    parser = _Parser(lexemes)
    root = parser.relation()
    if parser.index != len(lexemes):
        raise Refusal(REASON + ".syntax")
    if depth(root) > MATH_DEPTH:
        raise Refusal(REASON + ".depth")
    return root


def spoken(text):
    """The spoken form of `text` (`MGMathText.spoken`); raises `Refusal`."""
    return speak(parse(text))


def check_text_item(item, is3d=False):
    """The `math` style rules of `MGParser.item` for a text item, after the plain-text rules: `3d.text.math`, then
    the markup of the trimmed raw text (a placeholder brace is outside the alphabet)."""
    if is3d:
        raise Refusal("3d.text.math")
    return spoken(mg_expr._trim(item["text"]))


def main(argv):
    status = 0
    for text in argv[1:]:
        try:
            print(spoken(text))
        except Refusal as refusal:
            print(refusal.reason)
            status = 1
    return status


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
