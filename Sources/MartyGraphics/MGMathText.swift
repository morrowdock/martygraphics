// SPDX-License-Identifier: Apache-2.0
import Foundation

/// Math text: the closed markup of a `text` item with `"style": "math"` (docs/PROTOCOL.md, "Math text"). The engine
/// parses it into a small tree, lays it out as typeset runs (`layout`: baseline shifts, smaller scripts, fraction bars
/// and root signs) and writes a deterministic spoken form (`spoken`) that VoiceOver, `MGDescribe` and caption export
/// read. It is not LaTeX and not HTML: nothing is evaluated, nothing reaches the host, and every bound is checked
/// before the tree is built.
///
///     math     := relation
///     relation := sum (("=" | "≠" | "≈" | "≤" | "≥") sum)*
///     sum      := sign? product (("+" | "-" | "±") product)*          sign := "+" | "-" | "±"   ("+-" is ±)
///     product  := factor ((("*" | "·" | "×") sign? factor) | factor)*   a factor after a factor is an implicit product
///     factor   := script ("/" script)?                                  a stacked fraction
///     script   := primary ("_" sub)? ("^" sign? sup)?
///     primary  := number "°"? | name | name "(" list ")" | letter"(" list ")" | "(" list ")" | "[" unit "]"
///     list     := relation ("," relation)*
///
/// Names: a single ASCII letter is a variable; the Greek letter names (`alpha` … `omega`, `Gamma` … `Omega`) or the
/// Greek letters themselves; `inf` (∞); the functions of `MGExpression` (`sin x` or `sin(x)`; `sqrt`, `abs`, `min` and
/// `max` need parentheses, `min` and `max` two arguments). A letter written directly before `(` is a function
/// application (`f(x)`); write a space for a product (`a (b + c)`). A subscript may also be a word (`v_max`). Units go
/// in brackets (`9.8 [m/s^2]`, `[J/(kg K)]`): unit names from `units`, powers 2 and 3, at most one `/`. Parentheses
/// around a fraction's parts or a script are grouping only and are not drawn.
///
/// Refusals, first match wins: `text.math` (empty, more than `MGLimits.mathLength` Unicode scalars, or a character
/// outside the alphabet: braces too, since math text has no placeholders), `text.math.syntax` (a malformed number),
/// `text.math.tokens` (more than `MGLimits.mathTokens`), `text.math.depth` (parentheses nested deeper than
/// `MGLimits.mathDepth`), then left to right while parsing `text.math.syntax`, `text.math.name` (an unknown name) and
/// `text.math.unit` (anything wrong inside `[ ]`), last `text.math.depth` (fractions, scripts, roots and parentheses
/// nested deeper than `MGLimits.mathDepth`). The Python mirror is `tools/mg_math.py`; both check the shared cases in
/// docs/fixtures/v1/math.cases.json.
public struct MGMathText: Equatable, Sendable {
    /// The markup exactly as given.
    public let text: String
    /// The engine's spoken form, for example "x squared plus 2 x" for `x^2 + 2 x`.
    public let spoken: String
    let root: Node

    /// Parses `text` (reasons `text.math…`, see the type's note).
    public static func parse(_ text: String) throws -> MGMathText {
        let scalars = Array(text.unicodeScalars)
        guard scalars.count <= MGLimits.mathLength, scalars.contains(where: { $0 != " " }),
              scalars.allSatisfy(inAlphabet) else { throw MGError(reason) }
        let lexemes = try tokenize(scalars)
        guard lexemes.count <= MGLimits.mathTokens else { throw MGError(reason + ".tokens") }
        var open = 0, deepest = 0
        for l in lexemes {
            if l.token == .symbol("(") { open += 1; deepest = Swift.max(deepest, open) }
            if l.token == .symbol(")") { open -= 1 }
        }
        guard deepest <= MGLimits.mathDepth else { throw MGError(reason + ".depth") }
        var parser = Parser(lexemes: lexemes)
        let root = try parser.relation()
        guard parser.index == lexemes.count else { throw MGError(reason + ".syntax") }
        guard depth(root) <= MGLimits.mathDepth else { throw MGError(reason + ".depth") }
        return MGMathText(text: text, spoken: speak(root), root: root)
    }

    /// The spoken form of `text`, or nil when it is not math text.
    public static func spoken(_ text: String) -> String? { (try? parse(text))?.spoken }

    static let reason = "text.math"

    // MARK: vocabulary

    /// Greek letters: the ASCII name and the letter. Lower-case letters are drawn italic, capitals upright.
    static let greek: [(String, Unicode.Scalar)] = [
        ("alpha", "α"), ("beta", "β"), ("gamma", "γ"), ("delta", "δ"), ("epsilon", "ε"), ("zeta", "ζ"), ("eta", "η"),
        ("theta", "θ"), ("iota", "ι"), ("kappa", "κ"), ("lambda", "λ"), ("mu", "μ"), ("nu", "ν"), ("xi", "ξ"),
        ("pi", "π"), ("rho", "ρ"), ("sigma", "σ"), ("tau", "τ"), ("upsilon", "υ"), ("phi", "φ"), ("chi", "χ"),
        ("psi", "ψ"), ("omega", "ω"), ("Gamma", "Γ"), ("Delta", "Δ"), ("Theta", "Θ"), ("Lambda", "Λ"), ("Xi", "Ξ"),
        ("Pi", "Π"), ("Sigma", "Σ"), ("Upsilon", "Υ"), ("Phi", "Φ"), ("Psi", "Ψ"), ("Omega", "Ω"),
    ]
    static let greekLetter = Dictionary(uniqueKeysWithValues: greek.map { ($0.0, $0.1) })
    static let greekName = Dictionary(uniqueKeysWithValues: greek.map { ($0.1, $0.0) })

    /// Units in brackets: the ASCII name, the symbol drawn, and the spoken singular and plural.
    static let units: [(name: String, symbol: String, one: String, many: String)] = [
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
    ]
    static let unitIndex = Dictionary(uniqueKeysWithValues: units.enumerated().map { ($0.element.name, $0.offset) })

    /// How each `MGExpression` function is drawn and spoken (`sqrt` and `abs` draw a root sign and bars).
    static func function(_ f: MGExpression.Function) -> (drawn: String, spoken: String) {
        switch f {
        case .sin: return ("sin", "sine")
        case .cos: return ("cos", "cosine")
        case .tan: return ("tan", "tangent")
        case .asin: return ("arcsin", "arc sine")
        case .acos: return ("arccos", "arc cosine")
        case .atan: return ("arctan", "arc tangent")
        case .sinh: return ("sinh", "hyperbolic sine")
        case .cosh: return ("cosh", "hyperbolic cosine")
        case .tanh: return ("tanh", "hyperbolic tangent")
        case .exp: return ("exp", "the exponential")
        case .ln: return ("ln", "the natural log")
        case .log: return ("log", "the log")
        case .sqrt: return ("√", "the square root")
        case .abs: return ("|", "the absolute value")
        case .min: return ("min", "the minimum")
        case .max: return ("max", "the maximum")
        }
    }

    /// Characters of the alphabet besides ASCII letters, digits and the Greek letters.
    static let symbols: Set<Unicode.Scalar> = [" ", ".", "+", "-", "*", "/", "^", "_", "(", ")", "[", "]", ",", "=",
                                               "±", "·", "×", "−", "≤", "≥", "≠", "≈", "°"]

    /// Refused in a scene's math text before the plain-text rules run (`MGParser`, reason `text.math`): a placeholder
    /// brace or a line break (LF, VT, FF, CR, NEL, U+2028, U+2029), wherever it is.
    static func refusedInScene(_ s: Unicode.Scalar) -> Bool {
        s == "{" || s == "}" || (0x0A...0x0D).contains(s.value) || s.value == 0x85 || s.value == 0x2028 || s.value == 0x2029
    }

    static func inAlphabet(_ s: Unicode.Scalar) -> Bool {
        MGExpression.isLetter(s) || MGExpression.isDigit(s) || symbols.contains(s) || greekName[s] != nil
    }

    // MARK: tokens

    enum Token: Equatable {
        /// A decimal number exactly as written.
        case number(String)
        /// A run of ASCII letters.
        case name(String)
        /// A Greek letter written as itself, by its ASCII name.
        case greek(String)
        /// A symbol; `−` reads as `-` and `+-` as `±`.
        case symbol(Unicode.Scalar)
    }

    struct Lexeme: Equatable {
        let token: Token
        /// White space comes before it.
        let spaced: Bool
    }

    /// Numbers follow `MGExpression`: digits with at most one `.` and a digit after it (`2`, `0.5`, `.5`), at most
    /// `MGExpression.numberLength` characters.
    static func tokenize(_ s: [Unicode.Scalar]) throws -> [Lexeme] {
        var out: [Lexeme] = []
        var i = 0, spaced = false
        while i < s.count {
            let ch = s[i]
            if ch == " " { spaced = true; i += 1; continue }
            let token: Token
            if MGExpression.isDigit(ch) || ch == "." {
                var j = i
                while j < s.count, MGExpression.isDigit(s[j]) { j += 1 }
                if j < s.count, s[j] == "." {
                    j += 1
                    let fraction = j
                    while j < s.count, MGExpression.isDigit(s[j]) { j += 1 }
                    guard j > fraction else { throw MGError(reason + ".syntax") }
                }
                guard j - i <= MGExpression.numberLength else { throw MGError(reason + ".syntax") }
                var literal = ""
                literal.unicodeScalars.append(contentsOf: s[i..<j])
                token = .number(literal); i = j
            } else if MGExpression.isLetter(ch) {
                var j = i
                while j < s.count, MGExpression.isLetter(s[j]) { j += 1 }
                var name = ""
                name.unicodeScalars.append(contentsOf: s[i..<j])
                token = .name(name); i = j
            } else if let name = greekName[ch] {
                token = .greek(name); i += 1
            } else if ch == "+", i + 1 < s.count, s[i + 1] == "-" {
                token = .symbol("±"); i += 2
            } else {
                token = .symbol(ch == "−" ? "-" : ch); i += 1
            }
            out.append(Lexeme(token: token, spaced: spaced))
            spaced = false
        }
        return out
    }

    // MARK: tree

    enum Op: Equatable, Sendable {
        case plus, minus, plusMinus, dot, cross, implicit, equals, notEqual, approx, lessEqual, greaterEqual

        static func sign(_ s: Unicode.Scalar) -> Op? {
            switch s { case "+": return .plus; case "-": return .minus; case "±": return .plusMinus; default: return nil }
        }
        static func product(_ s: Unicode.Scalar) -> Op? {
            switch s { case "*", "·": return .dot; case "×": return .cross; default: return nil }
        }
        static func relation(_ s: Unicode.Scalar) -> Op? {
            switch s {
            case "=": return .equals
            case "≠": return .notEqual
            case "≈": return .approx
            case "≤": return .lessEqual
            case "≥": return .greaterEqual
            default: return nil
            }
        }
        var drawn: String {
            switch self {
            case .plus: return "+"
            case .minus: return "−"
            case .plusMinus: return "±"
            case .dot: return "·"
            case .cross: return "×"
            case .implicit: return ""
            case .equals: return "="
            case .notEqual: return "≠"
            case .approx: return "≈"
            case .lessEqual: return "≤"
            case .greaterEqual: return "≥"
            }
        }
        var spoken: String {
            switch self {
            case .plus: return "plus"
            case .minus: return "minus"
            case .plusMinus: return "plus or minus"
            case .dot, .cross: return "times"
            case .implicit: return ""
            case .equals: return "equals"
            case .notEqual: return "is not equal to"
            case .approx: return "is approximately equal to"
            case .lessEqual: return "is less than or equal to"
            case .greaterEqual: return "is greater than or equal to"
            }
        }
    }

    struct UnitTerm: Equatable, Sendable {
        /// Index into `units`.
        let unit: Int
        /// 1, 2 or 3.
        let power: Int
    }

    struct Link: Equatable, Sendable {
        let op: Op
        let node: Node
    }

    indirect enum Node: Equatable, Sendable {
        case number(String)
        /// A number with a degree sign: `30°`.
        case degree(String)
        case variable(String)
        /// By ASCII name.
        case greek(String)
        case infinity
        /// A subscript written as a word (`max` in `v_max`).
        case word(String)
        case unit(top: [UnitTerm], bottom: [UnitTerm])
        /// Parentheses around one or more comma-separated parts.
        case group([Node])
        case function(MGExpression.Function, [Node], parens: Bool)
        /// A letter applied to arguments: `f(x)`.
        case apply(String, [Node])
        case script(Node, sub: Node?, sup: Node?)
        case fraction(Node, Node)
        case sign(Op, Node)
        /// A sum, product or relation: the first part, then each operator and part.
        case row(Node, [Link])
    }

    /// Nesting of fractions, scripts, roots, function arguments and parentheses (`text.math.depth`).
    static func depth(_ n: Node) -> Int {
        switch n {
        case .number, .degree, .variable, .greek, .infinity, .word, .unit: return 0
        case .group(let parts), .apply(_, let parts), .function(_, let parts, _): return 1 + (parts.map(depth).max() ?? 0)
        case .script(let base, let sub, let sup):
            return Swift.max(depth(base), sub.map { 1 + depth($0) } ?? 0, sup.map { 1 + depth($0) } ?? 0)
        case .fraction(let a, let b): return 1 + Swift.max(depth(a), depth(b))
        case .sign(_, let x): return depth(x)
        case .row(let first, let links): return ([first] + links.map(\.node)).map(depth).max() ?? 0
        }
    }

    /// Parentheses around a fraction's part or a script group only: they are not drawn or spoken.
    static func stripped(_ n: Node) -> Node {
        if case .group(let parts) = n, parts.count == 1 { return parts[0] }
        return n
    }

    // MARK: parsing

    /// Recursive descent over at most `MGLimits.mathTokens` tokens: every call level consumes a token or ends, so the
    /// recursion is bounded by the token count.
    struct Parser {
        let lexemes: [Lexeme]
        var index = 0

        init(lexemes: [Lexeme]) { self.lexemes = lexemes }

        var next: Token? { index < lexemes.count ? lexemes[index].token : nil }
        var nextSpaced: Bool { index < lexemes.count ? lexemes[index].spaced : false }
        var nextSymbol: Unicode.Scalar? { if case .symbol(let s)? = next { return s }; return nil }
        func syntax() -> MGError { MGError(reason + ".syntax") }
        func unitError() -> MGError { MGError(reason + ".unit") }

        mutating func relation() throws -> Node {
            let first = try sum()
            var links: [Link] = []
            while let s = nextSymbol, let op = Op.relation(s) {
                index += 1
                links.append(Link(op: op, node: try sum()))
            }
            return links.isEmpty ? first : .row(first, links)
        }

        mutating func sum() throws -> Node {
            var first: Node
            if let s = nextSymbol, let op = Op.sign(s) {
                index += 1
                first = .sign(op, try product())
            } else {
                first = try product()
            }
            var links: [Link] = []
            while let s = nextSymbol, let op = Op.sign(s) {
                index += 1
                links.append(Link(op: op, node: try product()))
            }
            if !links.isEmpty { first = .row(first, links) }
            return first
        }

        mutating func product() throws -> Node {
            let first = try factor()
            var links: [Link] = []
            while true {
                if let s = nextSymbol, let op = Op.product(s) {
                    index += 1
                    if let t = nextSymbol, let sign = Op.sign(t) {
                        index += 1
                        links.append(Link(op: op, node: .sign(sign, try factor())))
                    } else {
                        links.append(Link(op: op, node: try factor()))
                    }
                } else if startsFactor {
                    links.append(Link(op: .implicit, node: try factor()))
                } else {
                    break
                }
            }
            return links.isEmpty ? first : .row(first, links)
        }

        var startsFactor: Bool {
            switch next {
            case .number?, .name?, .greek?: return true
            case .symbol(let s)?: return s == "(" || s == "["
            case nil: return false
            }
        }

        mutating func factor() throws -> Node {
            let top = try script()
            guard nextSymbol == "/" else { return top }
            index += 1
            let bottom = try script()
            guard nextSymbol != "/" else { throw syntax() }   // write (a/b)/c
            return .fraction(stripped(top), stripped(bottom))
        }

        mutating func script() throws -> Node {
            let base = try primary()
            var sub: Node?, sup: Node?
            if nextSymbol == "_" { index += 1; sub = stripped(try subscriptPart()) }
            if nextSymbol == "^" {
                index += 1
                if let s = nextSymbol, let op = Op.sign(s) {
                    index += 1
                    sup = .sign(op, stripped(try atom()))
                } else {
                    sup = stripped(try atom())
                }
            }
            return sub == nil && sup == nil ? base : .script(base, sub: sub, sup: sup)
        }

        /// A subscript: a number, a letter, a Greek letter, a word or a parenthesised list.
        mutating func subscriptPart() throws -> Node {
            guard let t = next else { throw syntax() }
            switch t {
            case .number(let s): index += 1; return .number(s)
            case .greek(let g): index += 1; return .greek(g)
            case .name(let n):
                index += 1
                if greekLetter[n] != nil { return .greek(n) }
                return n.unicodeScalars.count == 1 ? .variable(n) : .word(n)
            case .symbol("("): return try parenthesised()
            case .symbol: throw syntax()
            }
        }

        /// A primary without a function written without parentheses or a unit: a superscript.
        mutating func atom() throws -> Node {
            guard let t = next else { throw syntax() }
            switch t {
            case .number(let s): index += 1; return .number(s)
            case .greek(let g): index += 1; return .greek(g)
            case .name: return try named(parensRequired: true)
            case .symbol("("): return try parenthesised()
            case .symbol: throw syntax()
            }
        }

        mutating func primary() throws -> Node {
            guard let t = next else { throw syntax() }
            switch t {
            case .number(let s):
                index += 1
                if nextSymbol == "°", !nextSpaced { index += 1; return .degree(s) }
                return .number(s)
            case .greek(let g): index += 1; return .greek(g)
            case .name: return try named(parensRequired: false)
            case .symbol("("): return try parenthesised()
            case .symbol("["): index += 1; return try unit()
            case .symbol: throw syntax()
            }
        }

        mutating func named(parensRequired: Bool) throws -> Node {
            guard case .name(let n)? = next else { throw syntax() }
            index += 1
            if let f = MGExpression.Function(rawValue: n) {
                if nextSymbol == "(" {
                    let args = try arguments()
                    guard args.count == f.arity else { throw syntax() }
                    return .function(f, args, parens: true)
                }
                guard !parensRequired, ![.sqrt, .abs, .min, .max].contains(f) else { throw syntax() }
                return .function(f, [try script()], parens: false)
            }
            if greekLetter[n] != nil { return .greek(n) }
            if n == "inf" { return .infinity }
            guard n.unicodeScalars.count == 1 else { throw MGError(reason + ".name") }
            if nextSymbol == "(", !nextSpaced { return .apply(n, try arguments()) }
            return .variable(n)
        }

        /// `(` list `)`, as a group.
        mutating func parenthesised() throws -> Node { .group(try arguments()) }

        mutating func arguments() throws -> [Node] {
            guard nextSymbol == "(" else { throw syntax() }
            index += 1
            var parts = [try relation()]
            while nextSymbol == "," { index += 1; parts.append(try relation()) }
            guard nextSymbol == ")" else { throw syntax() }
            index += 1
            return parts
        }

        /// After `[`: terms, optionally `/` and one term or a parenthesised product, then `]`. Any fault is
        /// `text.math.unit`.
        mutating func unit() throws -> Node {
            let top = try unitProduct()
            var bottom: [UnitTerm] = []
            if nextSymbol == "/" {
                index += 1
                if nextSymbol == "(" {
                    index += 1
                    bottom = try unitProduct()
                    guard nextSymbol == ")" else { throw unitError() }
                    index += 1
                } else {
                    bottom = [try unitTerm()]
                }
            }
            guard nextSymbol == "]" else { throw unitError() }
            index += 1
            return .unit(top: top, bottom: bottom)
        }

        mutating func unitProduct() throws -> [UnitTerm] {
            var terms = [try unitTerm()]
            while true {
                if nextSymbol == "*" || nextSymbol == "·" { index += 1; terms.append(try unitTerm()) }
                else if case .name? = next { terms.append(try unitTerm()) }
                else { return terms }
            }
        }

        mutating func unitTerm() throws -> UnitTerm {
            guard case .name(let n)? = next, let u = unitIndex[n] else { throw unitError() }
            index += 1
            guard nextSymbol == "^" else { return UnitTerm(unit: u, power: 1) }
            index += 1
            guard case .number(let p)? = next, p == "2" || p == "3" else { throw unitError() }
            index += 1
            return UnitTerm(unit: u, power: p == "2" ? 2 : 3)
        }
    }

    // MARK: spoken form

    static func isAtom(_ n: Node) -> Bool {
        switch n {
        case .number, .degree, .variable, .greek, .infinity, .word: return true
        default: return false
        }
    }

    /// Short enough to speak without an end marker: an atom, or an atom with an atom subscript.
    static func simple(_ n: Node) -> Bool {
        if isAtom(n) { return true }
        if case .script(let base, let sub?, nil) = n { return isAtom(base) && isAtom(sub) }
        return false
    }

    static let numerators = ["one", "two", "three", "four", "five", "six", "seven", "eight", "nine"]
    static let denominators = [("half", "halves"), ("third", "thirds"), ("quarter", "quarters"), ("fifth", "fifths"),
                               ("sixth", "sixths"), ("seventh", "sevenths"), ("eighth", "eighths"), ("ninth", "ninths"),
                               ("tenth", "tenths")]

    /// "one half", "three quarters": a whole-number numerator 1–9 over a whole-number denominator 2–10.
    static func fractionWords(_ a: Node, _ b: Node) -> String? {
        guard case .number(let top) = a, case .number(let bottom) = b,
              let t = Int(top), String(t) == top, (1...9).contains(t),
              let d = Int(bottom), String(d) == bottom, (2...10).contains(d) else { return nil }
        let names = denominators[d - 2]
        return numerators[t - 1] + " " + (t == 1 ? names.0 : names.1)
    }

    /// "metres per second squared": the last unit above the bar plural unless `plural` is false; powers above the bar
    /// are "square" and "cubic", below it "squared" and "cubed".
    static func unitWords(_ top: [UnitTerm], _ bottom: [UnitTerm], plural: Bool) -> String {
        var words = top.enumerated().map { k, term -> String in
            let u = units[term.unit]
            let name = k == top.count - 1 && plural ? u.many : u.one
            return (term.power == 2 ? "square " : term.power == 3 ? "cubic " : "") + name
        }.joined(separator: " ")
        if !bottom.isEmpty {
            words += " per " + bottom.map { term in
                units[term.unit].one + (term.power == 2 ? " squared" : term.power == 3 ? " cubed" : "")
            }.joined(separator: " ")
        }
        return words
    }

    /// A spoken phrase, and whether it ends on a part that a pause began: an end word (", end fraction", ", end root",
    /// ", end absolute value", ", end power", ", end sub") or a script read after a pause ("sine of x, squared").
    /// Whatever follows a closed phrase is read after a pause too ("…, end fraction, plus z").
    struct Phrase {
        var text: String
        var closed = false
    }

    /// `p`, then `words`: after a pause when `p` is closed.
    static func then(_ p: Phrase, _ words: String) -> String { p.text + (p.closed ? ", " : " ") + words }

    /// "open paren a comma b close paren".
    static func parenthesised(_ parts: [Node]) -> String {
        var p = speech(parts[0])
        p.text = "open paren " + p.text
        for part in parts.dropFirst() {
            let q = speech(part)
            p = Phrase(text: then(p, "comma " + q.text), closed: q.closed)
        }
        return then(p, "close paren")
    }

    /// Function arguments: one simple argument as itself, otherwise in spoken parentheses.
    static func arguments(_ parts: [Node]) -> String {
        if parts.count == 1, simple(parts[0]) { return speak(parts[0]) }
        return parenthesised(parts)
    }

    static func speak(_ n: Node) -> String { speech(n).text }

    /// The spoken form. Every compound part that could otherwise run into what follows ends with an end word, so the
    /// listener hears where it stops: a fraction in the long form ("the fraction with numerator … and denominator …,
    /// end fraction"), a root or absolute value of more than one symbol, a power or subscript of more than one symbol.
    /// A power or subscript of a function is read after a pause ("sine of x, squared" for `sin(x)^2`, against "sine of
    /// x squared" for `sin x^2`), and `min` and `max` of anything longer than one symbol read their arguments in spoken
    /// parentheses.
    static func speech(_ n: Node) -> Phrase {
        switch n {
        case .number(let s): return Phrase(text: s)
        case .degree(let s): return Phrase(text: s + (s == "1" ? " degree" : " degrees"))
        case .variable(let v): return Phrase(text: v)
        case .greek(let g):
            guard let first = g.unicodeScalars.first, first.properties.isUppercase else { return Phrase(text: g) }
            return Phrase(text: "capital " + g.lowercased())
        case .infinity: return Phrase(text: "infinity")
        case .word(let w): return Phrase(text: w)
        case .unit(let top, let bottom): return Phrase(text: unitWords(top, bottom, plural: true))
        case .group(let parts):
            if parts.count == 1, simple(parts[0]) { return speech(parts[0]) }
            return Phrase(text: parenthesised(parts))
        case .function(let f, let parts, let parens):
            let name = function(f).spoken
            switch f {
            case .sqrt, .abs:
                let x = speech(parts[0])
                if simple(parts[0]) { return Phrase(text: name + " of " + x.text) }
                return Phrase(text: name + " of " + x.text + (f == .sqrt ? ", end root" : ", end absolute value"), closed: true)
            case .min, .max:
                if simple(parts[0]), simple(parts[1]) { return Phrase(text: name + " of " + speak(parts[0]) + " and " + speak(parts[1])) }
                return Phrase(text: name + " of " + parenthesised(parts))
            default:
                if parens { return Phrase(text: name + " of " + arguments(parts)) }
                let x = speech(parts[0])
                return Phrase(text: name + " of " + x.text, closed: x.closed)
            }
        case .apply(let f, let parts): return Phrase(text: f + " of " + arguments(parts))
        case .script(let base, let sub, let sup):
            var p = speech(base)
            switch base {
            case .function, .apply: p.closed = true
            default: break
            }
            if let sub {
                p = Phrase(text: then(p, "sub " + speak(sub)) + (simple(sub) ? "" : ", end sub"), closed: p.closed || !simple(sub))
            }
            if let sup {
                if sup == .number("2") { p.text = then(p, "squared") }
                else if sup == .number("3") { p.text = then(p, "cubed") }
                else {
                    var plain = simple(sup)
                    if case .sign(_, let x) = sup, simple(x) { plain = true }
                    p = Phrase(text: then(p, "to the power " + speak(sup)) + (plain ? "" : ", end power"), closed: p.closed || !plain)
                }
            }
            return p
        case .fraction(let a, let b):
            if let words = fractionWords(a, b) { return Phrase(text: words) }
            if simple(a), simple(b) { return Phrase(text: speak(a) + " over " + speak(b)) }
            return Phrase(text: "the fraction with numerator " + then(speech(a), "and denominator " + speak(b)) + ", end fraction",
                          closed: true)
        case .sign(let op, let x):
            let q = speech(x)
            return Phrase(text: op.spoken + " " + q.text, closed: q.closed)
        case .row(let first, let links):
            var p = speech(first)
            var previous = first
            for link in links {
                let q: Phrase
                if link.op == .implicit, case .unit(let top, let bottom) = link.node {
                    q = Phrase(text: unitWords(top, bottom, plural: previous != .number("1")))
                } else {
                    q = speech(link.node)
                }
                p = Phrase(text: then(p, link.op == .implicit ? q.text : link.op.spoken + " " + q.text), closed: q.closed)
                previous = link.node
            }
            return p
        }
    }
}

// MARK: layout

/// Typeset runs of one math text, in points, relative to the left end of its baseline (y grows downward, as on
/// screen). A renderer draws each run with its baseline at (`x`, `y`) in an italic or upright face of `size`, and
/// strokes each `strokes` polyline (fraction bars, root signs, tall parentheses and absolute-value bars).
public struct MGMathLayout: Equatable, Sendable {
    public struct Run: Equatable, Sendable {
        public var text: String
        public var x: Double, y: Double
        public var size: Double
        public var italic: Bool
    }
    public struct Stroke: Equatable, Sendable {
        public var points: [MGPoint]
        public var width: Double
    }
    public var runs: [Run] = []
    public var strokes: [Stroke] = []
    /// Width, and the extent above (ascent) and below (descent) the baseline.
    public var width = 0.0, ascent = 0.0, descent = 0.0
}

/// Where a formula goes across the canvas (`MGMathText.fit`), in canvas points.
public struct MGMathFit: Equatable, Sendable {
    /// The factor applied to the layout at `MGMathText.boardSize`: 1 when it fits, never below
    /// `minimumSize / boardSize`.
    public var scale: Double
    /// The x of the left end of the baseline.
    public var left: Double
    /// The drawn width: the scaled layout width, or the room left between the margins when `clipped`.
    public var width: Double
    /// True when the formula is wider than the canvas even at `minimumSize`, so its right end is cut off.
    public var clipped: Bool
}

extension MGMathText {
    /// A text run's height above and below the baseline, as fractions of its size.
    static let ascentRatio = 0.72, descentRatio = 0.22
    /// Height of the fraction bar above the baseline, as a fraction of the size.
    static let axis = 0.27

    /// The base size, in points, at which the 2D canvas draws math text (plain text labels are 14).
    public static let boardSize = 17.0

    /// The smallest base size a formula is scaled down to so that it fits across the canvas (`fit`).
    public static let minimumSize = 11.0
    /// The margin kept clear at each side of the canvas when a formula is fitted (`fit`).
    public static let fitMargin = 8.0

    /// Fits a formula across a canvas `canvas` points wide, for the renderer and `MGLayout.bounds` alike. `width` is the
    /// layout width at `boardSize` and `centre` the x of the item's `at`. A formula that fits in the canvas less
    /// `fitMargin` at each side keeps its size and is centred on `at`, moved inward only as far as it must be to stay
    /// inside. A wider one is scaled down uniformly (runs, gaps and strokes alike) until it fits, but never below
    /// `minimumSize`. Wider than the room even at that size, it is drawn at `minimumSize` from the left margin and
    /// clipped at the right margin: `clipped` is true and `width` is the clipped width, so the drawn box never claims
    /// more than is shown. The spoken form is the whole formula either way.
    public static func fit(width: Double, centre: Double, canvas: Double) -> MGMathFit {
        let natural = width.isFinite ? Swift.max(0, width) : 0
        let room = canvas.isFinite ? Swift.max(0, canvas - 2 * fitMargin) : 0
        let lowest = minimumSize / boardSize
        let scale = natural <= room ? 1 : Swift.max(lowest, room / natural)
        let drawn = natural * scale
        guard drawn <= room + 1e-9 else { return MGMathFit(scale: scale, left: fitMargin, width: room, clipped: true) }
        let middle = centre.isFinite ? centre : canvas / 2
        let left = Swift.min(Swift.max(middle - drawn / 2, fitMargin), Swift.max(fitMargin, canvas - fitMargin - drawn))
        return MGMathFit(scale: scale, left: left, width: drawn, clipped: false)
    }

    /// A rough width for a run (`MGLayout.textSize` uses the same 0.56 em per character): bounds without a font.
    public static func roughWidth(_ text: String, _ size: Double, _ italic: Bool) -> Double {
        Double(text.unicodeScalars.count) * size * 0.56
    }

    /// The typeset layout at base `size`; `measure(text, size, italic)` is the advance width of one run.
    public func layout(size: Double, measure: (String, Double, Bool) -> Double) -> MGMathLayout {
        withoutActuallyEscaping(measure) { measure in
            let box = Typesetter(base: size, measure: measure).node(root, size)
            return MGMathLayout(runs: box.runs, strokes: box.strokes, width: box.width, ascent: box.ascent, descent: box.descent)
        }
    }

    struct Box {
        var width = 0.0, ascent = 0.0, descent = 0.0
        var runs: [MGMathLayout.Run] = []
        var strokes: [MGMathLayout.Stroke] = []

        /// Adds `b` with its baseline origin at (`dx`, `dy`).
        mutating func place(_ b: Box, _ dx: Double, _ dy: Double) {
            runs += b.runs.map { var r = $0; r.x += dx; r.y += dy; return r }
            strokes += b.strokes.map { s in .init(points: s.points.map { MGPoint($0.x + dx, $0.y + dy) }, width: s.width) }
            ascent = Swift.max(ascent, b.ascent - dy)
            descent = Swift.max(descent, b.descent + dy)
            width = Swift.max(width, dx + b.width)
        }

        mutating func stroke(_ points: [MGPoint], _ w: Double) { strokes.append(.init(points: points, width: w)) }
    }

    struct Typesetter {
        let base: Double
        let measure: (String, Double, Bool) -> Double

        func scriptSize(_ size: Double) -> Double { Swift.max(base * 0.5, size * 0.7) }
        func partSize(_ size: Double) -> Double { Swift.max(base * 0.5, size * 0.85) }

        func text(_ s: String, _ size: Double, italic: Bool = false) -> Box {
            let w = measure(s, size, italic)
            return Box(width: w.isFinite ? Swift.max(0, w) : 0, ascent: ascentRatio * size, descent: descentRatio * size,
                       runs: [.init(text: s, x: 0, y: 0, size: size, italic: italic)])
        }

        /// Boxes side by side, each after its gap.
        func line(_ parts: [(Box, Double)]) -> Box {
            var out = Box(), x = 0.0
            for (b, gap) in parts { x += gap; out.place(b, x, 0); x += b.width }
            out.width = x
            return out
        }

        func list(_ parts: [Node], _ size: Double) -> Box {
            var pieces: [(Box, Double)] = []
            for (k, p) in parts.enumerated() {
                if k > 0 { pieces.append((text(",", size), 0)) }
                pieces.append((node(p, size), k > 0 ? 0.25 * size : 0))
            }
            return line(pieces)
        }

        /// Parentheses: glyphs around one-line content, strokes around taller content (a fraction inside).
        func parens(_ content: Box, _ size: Double) -> Box {
            let normal = (ascentRatio + descentRatio) * size
            guard content.ascent + content.descent > 1.2 * normal else {
                return line([(text("(", size), 0), (content, 0.04 * size), (text(")", size), 0.04 * size)])
            }
            let top = -(content.ascent + 0.06 * size), bottom = content.descent + 0.06 * size, w = 0.3 * size
            func curve(_ left: Bool) -> [MGPoint] {
                (0...8).map { k -> MGPoint in
                    let t = Double(k) / 8, bulge = 0.19 * size * (1 - sin(Double.pi * t))
                    return MGPoint(left ? 0.06 * size + bulge : w - 0.06 * size - bulge, top + (bottom - top) * t)
                }
            }
            var out = Box()
            var l = Box(width: w, ascent: -top, descent: bottom); l.stroke(curve(true), 0.07 * size)
            var r = Box(width: w, ascent: -top, descent: bottom); r.stroke(curve(false), 0.07 * size)
            out.place(l, 0, 0); out.place(content, w, 0); out.place(r, w + content.width, 0)
            return out
        }

        func unit(_ top: [UnitTerm], _ bottom: [UnitTerm], _ size: Double) -> Box {
            func terms(_ list: [UnitTerm]) -> [(Box, Double)] {
                var pieces: [(Box, Double)] = []
                for (k, term) in list.enumerated() {
                    if k > 0 { pieces.append((text("·", size), 0.06 * size)) }
                    pieces.append((text(units[term.unit].symbol, size), k > 0 ? 0.06 * size : 0))
                    if term.power > 1 {
                        var raised = Box()
                        raised.place(text(String(term.power), scriptSize(size)), 0, -0.42 * size)
                        pieces.append((raised, 0.03 * size))
                    }
                }
                return pieces
            }
            var pieces = terms(top)
            if !bottom.isEmpty {
                pieces.append((text("/", size), 0.02 * size))
                if bottom.count > 1 {
                    pieces.append((text("(", size), 0.02 * size))
                    pieces += terms(bottom)
                    pieces.append((text(")", size), 0))
                } else {
                    var rest = terms(bottom)
                    if !rest.isEmpty { rest[0].1 = 0.02 * size }
                    pieces += rest
                }
            }
            return line(pieces)
        }

        func gap(_ left: Node, _ right: Node, _ size: Double) -> Double {
            if case .unit = right { return 0.2 * size }
            if case .function = right { return 0.14 * size }
            if case .number = left { return 0.03 * size }
            return 0.08 * size
        }

        func node(_ n: Node, _ size: Double) -> Box {
            switch n {
            case .number(let s): return text(s, size)
            case .degree(let s): return text(s + "°", size)
            case .variable(let v): return text(v, size, italic: true)
            case .greek(let g):
                let letter = greekLetter[g].map { String(Character($0)) } ?? g
                return text(letter, size, italic: !(g.unicodeScalars.first?.properties.isUppercase ?? false))
            case .infinity: return text("∞", size)
            case .word(let w): return text(w, size)
            case .unit(let top, let bottom): return unit(top, bottom, size)
            case .group(let parts): return parens(list(parts, size), size)
            case .apply(let f, let parts): return line([(text(f, size, italic: true), 0), (parens(list(parts, size), size), 0.02 * size)])
            case .function(let f, let parts, let hasParens):
                switch f {
                case .sqrt: return root(node(parts[0], size), size)
                case .abs: return bars(node(parts[0], size), size)
                default:
                    let name = text(MGMathText.function(f).drawn, size)
                    if hasParens { return line([(name, 0), (parens(list(parts, size), size), 0.02 * size)]) }
                    return line([(name, 0), (node(parts[0], size), 0.12 * size)])
                }
            case .script(let b, let sub, let sup):
                let body = node(b, size)
                var out = Box()
                out.place(body, 0, 0)
                let small = scriptSize(size)
                let x = body.width + 0.04 * size
                var right = x
                if let sub {
                    let s = node(sub, small)
                    out.place(s, x, Swift.max(sup == nil ? 0.18 * size : 0.26 * size, s.ascent - 0.45 * size))
                    right = Swift.max(right, x + s.width)
                }
                if let sup {
                    let s = node(sup, small)
                    out.place(s, x, -Swift.max(0.42 * size, body.ascent - 0.38 * size))
                    right = Swift.max(right, x + s.width)
                }
                out.width = right + 0.02 * size
                return out
            case .fraction(let a, let b):
                let small = partSize(size)
                let top = node(a, small), bottom = node(b, small)
                let rule = 0.06 * size, gap = 0.12 * size, bar = -axis * size, pad = 0.12 * size
                let w = Swift.max(top.width, bottom.width) + 2 * pad
                var out = Box()
                out.place(top, (w - top.width) / 2, bar - rule / 2 - gap - top.descent)
                out.place(bottom, (w - bottom.width) / 2, bar + rule / 2 + gap + bottom.ascent)
                out.stroke([MGPoint(0.5 * pad, bar), MGPoint(w - 0.5 * pad, bar)], rule)
                out.width = w
                return out
            case .sign(let op, let x): return line([(text(op.drawn, size), 0), (node(x, size), 0.04 * size)])
            case .row(let first, let links):
                var pieces: [(Box, Double)] = [(node(first, size), 0)]
                var previous = first
                for link in links {
                    switch link.op {
                    case .implicit:
                        pieces.append((node(link.node, size), gap(previous, link.node, size)))
                    case .dot, .cross:
                        pieces.append((text(link.op.drawn, size), 0.16 * size)); pieces.append((node(link.node, size), 0.16 * size))
                    case .plus, .minus, .plusMinus:
                        pieces.append((text(link.op.drawn, size), 0.22 * size)); pieces.append((node(link.node, size), 0.22 * size))
                    case .equals, .notEqual, .approx, .lessEqual, .greaterEqual:
                        pieces.append((text(link.op.drawn, size), 0.28 * size)); pieces.append((node(link.node, size), 0.28 * size))
                    }
                    previous = link.node
                }
                return line(pieces)
            }
        }

        /// A root sign drawn as a stroke (tick, down, up), with a bar over the radicand.
        func root(_ r: Box, _ size: Double) -> Box {
            let rule = 0.06 * size, top = -(r.ascent + 0.12 * size), bottom = Swift.max(r.descent, 0.1 * size)
            var out = Box(width: 0, ascent: -top + rule, descent: bottom)
            out.place(r, 0.6 * size, 0)
            out.stroke([MGPoint(0, -0.3 * size), MGPoint(0.12 * size, -0.36 * size), MGPoint(0.32 * size, bottom),
                        MGPoint(0.55 * size, top), MGPoint(0.6 * size + r.width + 0.08 * size, top)], rule)
            out.width = 0.6 * size + r.width + 0.12 * size
            return out
        }

        /// Absolute-value bars drawn as strokes as tall as the content.
        func bars(_ c: Box, _ size: Double) -> Box {
            let rule = 0.06 * size, top = -(c.ascent + 0.05 * size), bottom = c.descent + 0.05 * size
            var out = Box(width: 0, ascent: -top, descent: bottom)
            out.place(c, 0.2 * size, 0)
            let right = 0.2 * size + c.width + 0.1 * size
            out.stroke([MGPoint(0.08 * size, top), MGPoint(0.08 * size, bottom)], rule)
            out.stroke([MGPoint(right, top), MGPoint(right, bottom)], rule)
            out.width = right + 0.08 * size
            return out
        }
    }
}
