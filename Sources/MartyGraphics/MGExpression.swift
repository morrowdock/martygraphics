// SPDX-License-Identifier: Apache-2.0
import Foundation

/// A small, closed arithmetic grammar for the `func`, `field` and `curve` items (docs/PROTOCOL.md, "Function graphs,
/// vector fields and text alternatives" and "Parametric and polar curves"):
///
///     expr    := term (("+" | "-") term)*
///     term    := unary (("*" | "/") unary)*
///     unary   := ("+" | "-") unary | power
///     power   := primary ("^" unary)?
///     primary := number | name | name "(" expr ("," expr)* ")" | "(" expr ")"
///
/// `^` is right-associative and binds tighter than a leading minus: `2^3^2` is 2^9 and `-x^2` is -(x^2). Numbers are
/// decimal (`2`, `0.5`, `.5`; no exponent; at most 12 characters). Names are the constants `pi` and `e`, the variables
/// `x y t a b c theta` (each item kind allows its own subset; `theta` is the parameter of a `curve`) and the functions
/// `sin cos tan asin acos atan sinh cosh tanh exp ln log sqrt abs` (one argument; `ln` is natural, `log` is base 10) and
/// `min max` (two arguments). Multiplication is always written: `2x` and `x(x+1)` are refused.
///
/// Compiling turns the text into a flat postfix program that a stack machine with a fixed set of operations evaluates.
/// Nothing reaches the host: no `NSExpression` (whose `FUNCTION` form can invoke arbitrary methods), no JavaScriptCore,
/// no key paths, selectors or format strings. Every bound is checked before any value is computed: at most
/// `MGLimits.exprLength` Unicode scalars, `MGLimits.exprTokens` tokens and `MGLimits.exprDepth` nested parentheses, so
/// one evaluation runs at most 48 operations. Values follow IEEE 754: outside a function's domain (`sqrt(-1)`, `ln(0)`,
/// `1/0`) a value is not finite, and the items draw a gap there, never a number.
public struct MGExpression: Equatable, Sendable {
    /// `theta` is last, so the order in which `compile` reports a variable that is not allowed is unchanged for the
    /// others.
    public enum Variable: String, CaseIterable, Sendable { case x, y, t, a, b, c, theta }

    public enum Function: String, CaseIterable, Sendable {
        case sin, cos, tan, asin, acos, atan, sinh, cosh, tanh, exp, ln, log, sqrt, abs, min, max
        /// Number of arguments: two for `min` and `max`, one for every other function.
        public var arity: Int { self == .min || self == .max ? 2 : 1 }
    }

    /// The variable values of one evaluation. A variable the expression does not read is ignored.
    public struct Inputs: Equatable, Sendable {
        public var x: Double, y: Double, t: Double, a: Double, b: Double, c: Double, theta: Double
        public init(x: Double = 0, y: Double = 0, t: Double = 0, a: Double = 0, b: Double = 0, c: Double = 0, theta: Double = 0) {
            self.x = x; self.y = y; self.t = t; self.a = a; self.b = b; self.c = c; self.theta = theta
        }
        public subscript(_ v: Variable) -> Double {
            switch v {
            case .x: return x
            case .y: return y
            case .t: return t
            case .a: return a
            case .b: return b
            case .c: return c
            case .theta: return theta
            }
        }
        func with(x: Double) -> Inputs { var copy = self; copy.x = x; return copy }
        func with(x: Double, y: Double) -> Inputs { var copy = self; copy.x = x; copy.y = y; return copy }
        func with(theta: Double) -> Inputs { var copy = self; copy.theta = theta; return copy }
    }

    enum Op: Equatable, Sendable {
        case number(Double), variable(Variable), negate, add, subtract, multiply, divide, power, call(Function)
    }

    enum Token: Equatable { case number(Double), name(String), symbol(Unicode.Scalar) }

    /// The text exactly as written.
    public let text: String
    /// The variables the text reads.
    public let variables: Set<Variable>
    /// Postfix operations; at most `MGLimits.exprTokens` long.
    let program: [Op]

    /// Characters of the grammar besides ASCII letters and digits.
    static let symbols: Set<Unicode.Scalar> = [" ", ".", "+", "-", "*", "/", "^", "(", ")", ","]
    /// Longest number literal, in characters.
    static let numberLength = 12

    /// Compiles `text`. `allowed` lists the variables the context provides; `reason` is the key's reason (`func.y`).
    /// Refusals, first match wins: `reason` (empty or only spaces, more than `MGLimits.exprLength` Unicode scalars, or a
    /// character outside the grammar), `reason.syntax` (a malformed number), `reason.tokens`, `reason.depth`, then
    /// left to right while parsing: `reason.syntax`, `reason.name` (not a constant, variable or function) and
    /// `reason.arity`; last, `reason.var.<v>` for the first variable in `Variable` order that `allowed` does not hold.
    public static func compile(_ text: String, allowed: Set<Variable>, reason: String) throws -> MGExpression {
        let scalars = Array(text.unicodeScalars)
        guard scalars.count <= MGLimits.exprLength, scalars.contains(where: { $0 != " " }),
              scalars.allSatisfy({ isLetter($0) || isDigit($0) || symbols.contains($0) }) else { throw MGError(reason) }
        let tokens = try tokenize(scalars, reason)
        guard tokens.count <= MGLimits.exprTokens else { throw MGError(reason + ".tokens") }
        var depth = 0, deepest = 0
        for token in tokens {
            if token == .symbol("(") { depth += 1; deepest = Swift.max(deepest, depth) }
            if token == .symbol(")") { depth -= 1 }
        }
        guard deepest <= MGLimits.exprDepth else { throw MGError(reason + ".depth") }
        var parser = Parser(tokens: tokens, reason: reason)
        try parser.expression()
        guard parser.index == tokens.count else { throw MGError(reason + ".syntax") }
        for v in Variable.allCases where parser.used.contains(v) && !allowed.contains(v) {
            throw MGError(reason + ".var." + v.rawValue)
        }
        return MGExpression(text: text, variables: parser.used, program: parser.program)
    }

    /// The value at `inputs`. Not finite outside the expression's domain.
    public func value(_ inputs: Inputs) -> Double {
        var stack = [Double](repeating: 0, count: Swift.max(1, program.count))
        var n = 0
        for op in program {
            switch op {
            case .number(let d):
                guard n < stack.count else { return .nan }
                stack[n] = d; n += 1
            case .variable(let v):
                guard n < stack.count else { return .nan }
                stack[n] = inputs[v]; n += 1
            case .negate:
                guard n >= 1 else { return .nan }
                stack[n - 1] = -stack[n - 1]
            case .call(let f) where f.arity == 1:
                guard n >= 1 else { return .nan }
                stack[n - 1] = Self.apply(f, stack[n - 1])
            case .add, .subtract, .multiply, .divide, .power, .call:
                guard n >= 2 else { return .nan }
                stack[n - 2] = Self.combine(op, stack[n - 2], stack[n - 1]); n -= 1
            }
        }
        return n == 1 ? stack[0] : .nan
    }

    // MARK: internals

    static func isLetter(_ s: Unicode.Scalar) -> Bool { (s >= "a" && s <= "z") || (s >= "A" && s <= "Z") }
    static func isDigit(_ s: Unicode.Scalar) -> Bool { s >= "0" && s <= "9" }

    static func tokenize(_ s: [Unicode.Scalar], _ reason: String) throws -> [Token] {
        var tokens: [Token] = []
        var i = 0
        while i < s.count {
            let ch = s[i]
            if ch == " " { i += 1; continue }
            if isDigit(ch) || ch == "." {
                var j = i
                while j < s.count, isDigit(s[j]) { j += 1 }
                if j < s.count, s[j] == "." {
                    j += 1
                    let fraction = j
                    while j < s.count, isDigit(s[j]) { j += 1 }
                    guard j > fraction else { throw MGError(reason + ".syntax") }   // `1.` or a lone `.`
                }
                guard j - i <= numberLength else { throw MGError(reason + ".syntax") }
                var literal = ch == "." ? "0" : ""
                literal.unicodeScalars.append(contentsOf: s[i..<j])
                guard let value = Double(literal), value.isFinite else { throw MGError(reason + ".syntax") }
                tokens.append(.number(value)); i = j
                continue
            }
            if isLetter(ch) {
                var j = i
                while j < s.count, isLetter(s[j]) { j += 1 }
                var name = ""
                name.unicodeScalars.append(contentsOf: s[i..<j])
                tokens.append(.name(name)); i = j
                continue
            }
            tokens.append(.symbol(ch)); i += 1
        }
        return tokens
    }

    /// Recursive descent over at most `MGLimits.exprTokens` tokens: every call level consumes a token, so the
    /// recursion is at most that deep.
    struct Parser {
        let tokens: [Token]
        let reason: String
        var index = 0
        var program: [Op] = []
        var used: Set<Variable> = []

        init(tokens: [Token], reason: String) { self.tokens = tokens; self.reason = reason }

        var next: Token? { index < tokens.count ? tokens[index] : nil }
        func syntax() -> MGError { MGError(reason + ".syntax") }

        mutating func expression() throws {
            try term()
            while let t = next, t == .symbol("+") || t == .symbol("-") {
                index += 1
                try term()
                program.append(t == .symbol("+") ? .add : .subtract)
            }
        }

        mutating func term() throws {
            try unary()
            while let t = next, t == .symbol("*") || t == .symbol("/") {
                index += 1
                try unary()
                program.append(t == .symbol("*") ? .multiply : .divide)
            }
        }

        mutating func unary() throws {
            if let t = next, t == .symbol("+") || t == .symbol("-") {
                index += 1
                try unary()
                if t == .symbol("-") { program.append(.negate) }
                return
            }
            try power()
        }

        mutating func power() throws {
            try primary()
            if next == .symbol("^") {
                index += 1
                try unary()
                program.append(.power)
            }
        }

        mutating func primary() throws {
            guard let t = next else { throw syntax() }
            index += 1
            switch t {
            case .number(let d):
                program.append(.number(d))
            case .symbol("("):
                try expression()
                guard next == .symbol(")") else { throw syntax() }
                index += 1
            case .name(let name):
                if let f = Function(rawValue: name) {
                    guard next == .symbol("(") else { throw syntax() }
                    index += 1
                    var count = 0
                    if next != .symbol(")") {
                        try expression(); count = 1
                        while next == .symbol(",") { index += 1; try expression(); count += 1 }
                    }
                    guard next == .symbol(")") else { throw syntax() }
                    index += 1
                    guard count == f.arity else { throw MGError(reason + ".arity") }
                    program.append(.call(f))
                } else if name == "pi" {
                    program.append(.number(Double.pi))
                } else if name == "e" {
                    program.append(.number(2.718281828459045))
                } else if let v = Variable(rawValue: name) {
                    used.insert(v)
                    program.append(.variable(v))
                } else {
                    throw MGError(reason + ".name")
                }
            case .symbol:
                throw syntax()
            }
        }
    }

    static func combine(_ op: Op, _ l: Double, _ r: Double) -> Double {
        switch op {
        case .add: return l + r
        case .subtract: return l - r
        case .multiply: return l * r
        case .divide: return l / r
        case .power: return pow(l, r)
        case .call(.min): return l.isNaN || r.isNaN ? .nan : Swift.min(l, r)
        case .call(.max): return l.isNaN || r.isNaN ? .nan : Swift.max(l, r)
        default: return .nan
        }
    }

    static func apply(_ f: Function, _ v: Double) -> Double {
        switch f {
        case .sin: return sin(v)
        case .cos: return cos(v)
        case .tan: return tan(v)
        case .asin: return asin(v)
        case .acos: return acos(v)
        case .atan: return atan(v)
        case .sinh: return sinh(v)
        case .cosh: return cosh(v)
        case .tanh: return tanh(v)
        case .exp: return exp(v)
        case .ln: return log(v)
        case .log: return log10(v)
        case .sqrt: return v.squareRoot()
        case .abs: return Swift.abs(v)
        case .min, .max: return .nan
        }
    }
}
