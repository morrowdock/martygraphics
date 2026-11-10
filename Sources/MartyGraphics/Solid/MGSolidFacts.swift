// SPDX-License-Identifier: Apache-2.0
import Foundation

// The engine facts table, `{placeholder}` fill with closed modifiers, number rule N1 and step claim checks for solid
// assembly documents. Foundation only, deterministic. Text rules apply to assembly v2 only; v1 text is never filled.

/// How far the engine stands behind a claim. The engine computes it; an author can never set it (`tier.key`).
/// Ordered: `described < built < solved`; a claim takes the lowest tier of its inputs.
public enum MGSolidTier: Int, Comparable, Sendable, CaseIterable {
    /// Text or a number the engine does not check (for example a caption marked `unchecked`).
    case described = 0
    /// Exact geometry from the author's numbers, with behaviour from the author: an `input` scale other than ±1, a
    /// `follow` ratio, and everything computed from them (later: scripted motion, stand-ins, cited sizes).
    case built = 1
    /// Computed by the engine, and every named check for it passed.
    case solved = 2

    public static func < (a: MGSolidTier, b: MGSolidTier) -> Bool { a.rawValue < b.rawValue }
    public var name: String {
        switch self {
        case .solved: return "solved"
        case .built: return "built"
        case .described: return "described"
        }
    }
}

/// One engine number: a value with its unit, its tier and what produced it.
public struct MGSolidFact: Equatable, Sendable {
    public internal(set) var value: Double
    /// `""` for pure numbers (tooth counts, turns per input turn, ratios, counts) or `"mm"`.
    public internal(set) var unit: String
    public internal(set) var tier: MGSolidTier
    /// What produced it: `shape`, `input`, `gearMesh`, `follow`, `crankSlider`, `repeat` or `anchors`.
    public internal(set) var source: String
    public init(value: Double, unit: String, tier: MGSolidTier, source: String) {
        self.value = value; self.unit = unit; self.tier = tier; self.source = source
    }
    /// What the learner sees: `MGPhysics.format` (about three significant figures), except that a non-zero value
    /// never shows as "0" (a 1:1000 train shows "0.001", not "0").
    public var text: String { MGSolidFacts.display(value, unit: unit) }
}

/// A step claim the engine proves before the learner sees it: `{"value": "<fact>", "eq" | "lt" | "gt": x, "tol"?: t}`.
/// Same shape and meaning as the lesson `check`: without `tol`, `eq` compares what the learner sees
/// (`MGPhysics.format` text of both numbers), except that a target of 0 then needs exactly 0 (a small speed such as
/// 0.004 prints "0" but is not 0).
public struct MGSolidClaimCheck: Equatable, Sendable {
    public enum Comparison: String, Equatable, Sendable { case eq, lt, gt }
    public let value: String
    public let comparison: Comparison
    public let target: Double
    public let tolerance: Double?

    static func parse(_ json: MGJSON) throws -> MGSolidClaimCheck {
        guard case .object(let o) = json else { throw MGSolidIssue("check.object") }
        try MGSolidParser.closed(o, ["value"], ["eq", "lt", "gt", "tol"], "step.check")
        guard case .string(let name)? = o["value"], MGSolidFacts.isName(name) else { throw MGSolidIssue("check.value") }
        let present = [Comparison.eq, .lt, .gt].filter { o[$0.rawValue] != nil }
        guard present.count == 1, let comparison = present.first else { throw MGSolidIssue("check.comparison") }
        let target = try MGSolidParser.num(o[comparison.rawValue], -1e6...1e6, "check.\(comparison.rawValue)")
        var tolerance: Double?
        if let t = o["tol"] {
            guard comparison == .eq else { throw MGSolidIssue("check.tol") }
            tolerance = try MGSolidParser.num(t, 0...1e6, "check.tol")
        }
        return MGSolidClaimCheck(value: name, comparison: comparison, target: target, tolerance: tolerance)
    }

    /// True when the claim holds for this fact value.
    public func holds(_ v: Double) -> Bool {
        switch comparison {
        case .eq:
            if let t = tolerance { return abs(v - target) <= t }
            if target == 0 { return v == 0 }
            return MGPhysics.format(v, unit: "") == MGPhysics.format(target, unit: "")
        case .lt: return v < target
        case .gt: return v > target
        }
    }

    /// True when the check proves the sign of the fact: only a strict inequality against a bound on one side of zero
    /// (`lt` t with t ≤ 0, `gt` t with t ≥ 0). An equality never does: without `tol` it compares displayed text, and
    /// -0.001 and +0.001 both display as "0".
    var provesSign: Bool {
        switch comparison {
        case .eq: return false
        case .lt: return target <= 0
        case .gt: return target >= 0
        }
    }

    /// The claim as text with the exact numbers that were checked, for example "stage.sun.teeth > 0",
    /// "stage.output.speed = 0.2857142857142857 ± 1e-09", or "stage.output.speed shows as 0.29 (target 0.286)".
    public var text: String {
        let x = MGSolidFacts.exact(target)
        switch comparison {
        case .eq:
            if let t = tolerance { return "\(value) = \(x) ± \(MGSolidFacts.exact(t))" }
            return target == 0 ? "\(value) = 0" : "\(value) shows as \(MGPhysics.format(target, unit: "")) (target \(x))"
        case .lt: return "\(value) < \(x)"
        case .gt: return "\(value) > \(x)"
        }
    }
}

/// A filled text: what the learner sees, the canonical facts it used (in order) with their modifiers, and whether it
/// has a number character outside the placeholders.
struct MGSolidFilledText {
    var text: String
    var facts: [String]
    var modifiers: [[String]] = []
    var typedNumbers = false
}

/// Facts table, placeholder grammar and modifiers.
public enum MGSolidFacts {
    /// Placeholder and fact names: ASCII letters, digits, `_` and `.`, at most this many characters.
    public static let nameLength = 64
    /// Modifiers per placeholder (`{name|abs|frac}`).
    public static let modifiers = 3
    /// Largest denominator `frac` prints.
    public static let fractionDenominator = 100_000
    /// Relative error `frac` accepts. Engine ratios from tooth counts are exact to about 1e-15.
    public static let fractionTolerance = 1e-12
    /// Input samples over one input turn for `<part>.travel`.
    public static let travelSamples = 720
    /// Closed modifier set. `pct`, `deg` and `frac` end a chain; `inv`, `pct`, `deg` and `frac` need a pure number;
    /// `pct` and `deg` apply to speeds and ratios only; `abs` needs a check in the same step that proves the sign.
    public static let modifierNames: Set<String> = ["abs", "inv", "pct", "deg", "frac"]

    /// A learner-facing number: `MGPhysics.format`, but a non-zero value that would show as "0" gets enough decimals
    /// to show its first three significant figures (scientific notation below 1e-9).
    public static func display(_ v: Double, unit: String) -> String {
        let s = MGPhysics.format(v, unit: unit)
        guard v != 0, v.isFinite, s.filter(\.isNumber).allSatisfy({ $0 == "0" }) else { return s }
        let a = abs(v)
        var t: String
        if a >= 1e-9 {
            let decimals = min(12, 2 - Int(log10(a).rounded(.down)))
            t = String(format: "%.\(decimals)f", v)
            while t.hasSuffix("0") { t.removeLast() }
            if t.hasSuffix(".") { t.removeLast() }
        } else {
            t = String(format: "%.2e", v)
        }
        return unit.isEmpty ? t : unit == "°" ? t + unit : t + " " + unit
    }

    /// A number as written for a proof condition: whole numbers without a decimal point, otherwise the shortest text
    /// that reads back as the same Double ("0.2857142857142857", "1e-09").
    public static func exact(_ v: Double) -> String {
        if v == v.rounded(), abs(v) < 1e15 { return String(Int64(v)) }
        return "\(v)"
    }

    static func isName(_ s: String) -> Bool {
        (1...nameLength).contains(s.count)
            && s.unicodeScalars.allSatisfy { $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "_" || $0 == ".") }
    }

    /// True for a character with any number scalar in it, before or after Unicode NFKC normalization (`nfkc`): digits
    /// of any script (ASCII, full-width "２", Arabic-Indic "٢", Devanagari "२"), superscripts and subscripts ("²",
    /// "₂"), fractions ("½"), circled and parenthesized numbers ("②"), Roman numerals ("Ⅻ"), CJK numerals ("二"), a
    /// compatibility symbol whose NFKC form holds a digit ("㋀" is "1月"), and a digit inside a grapheme cluster that
    /// starts with a letter (an Indic prepended sign followed by "5"). Every scalar is tested against the toolchain's
    /// Unicode properties and the pinned Unicode 18.0.0 Numeric_Type table (`MGSolidNumericScalars`): Numeric_Type
    /// Decimal, Digit or Numeric counts. Rule N1 counts all of these as numbers: each can state a quantity.
    static func isNumber(_ ch: Character) -> Bool {
        if hasNumberScalar(ch) { return true }
        let plain = nfkc(String(ch))
        return plain != String(ch) && plain.contains(where: hasNumberScalar)
    }

    static func hasNumberScalar(_ ch: Character) -> Bool {
        ch.isNumber || ch.unicodeScalars.contains { $0.properties.numericType != nil || MGSolidNumericScalars.contains($0) }
    }

    /// Unicode NFKC (compatibility decomposition, then canonical composition): full-width and other compatibility
    /// forms become their plain form ("Ｍａｃｈ２" is "Mach2"). Rule N1 and the declared names read text in this form.
    static func nfkc(_ s: String) -> String { s.precomposedStringWithCompatibilityMapping }

    // MARK: Rule N1: declared names

    /// Most entries of a document's `names` list, and the most characters of one name.
    public static let namesCount = 24, nameText = 24

    /// The tokens of `chars` (docs/SOLID-3D.md, "Declared names"): maximal runs of characters that are letters (any
    /// script), number characters (`isNumber`) or the hyphen-minus "-". Every other character (a space, punctuation,
    /// an apostrophe, a brace) ends a token.
    static func tokens(_ chars: [Character]) -> [Range<Int>] {
        func joins(_ c: Character) -> Bool { c == "-" || c.isLetter || isNumber(c) }
        var out: [Range<Int>] = [], i = 0
        while i < chars.count {
            guard joins(chars[i]) else { i += 1; continue }
            var j = i
            while j < chars.count, joins(chars[j]) { j += 1 }
            out.append(i..<j)
            i = j
        }
        return out
    }

    /// Rule N1 on one text (docs/SOLID-3D.md, "Declared names" and "Which characters are numbers"): the offsets in
    /// `chars` of the typed number characters. The text is first put in NFKC form, one grapheme at a time, with a map
    /// from each normalized character back to its original one; the tokens (`tokens`) are found in the normalized text.
    /// A token that exactly equals a declared name (case-sensitive; names are kept in NFKC form) types no number. In
    /// every other token, each original character that is a number (`isNumber`: it, or its NFKC form, holds a numeric
    /// scalar) is a typed number; so a token types a number when its normalized form holds a digit, or when any of its
    /// original characters has a numeric value (the "Ⅻ", "²", "½" and Arabic-Indic digits included). A number
    /// character outside every token is a typed number too.
    static func typedNumberOffsets(_ chars: [Character], names: Set<String>) -> Set<Int> {
        var norm: [Character] = [], from: [Int] = []
        for (k, ch) in chars.enumerated() {
            for c in nfkc(String(ch)) { norm.append(c); from.append(k) }
        }
        var typed = Set<Int>(), inToken = Set<Int>()
        for r in tokens(norm) {
            let originals = Set(from[r])
            inToken.formUnion(originals)
            guard !names.contains(String(norm[r])) else { continue }
            for k in originals where isNumber(chars[k]) { typed.insert(k) }
        }
        for (k, ch) in chars.enumerated() where !inToken.contains(k) && isNumber(ch) { typed.insert(k) }
        return typed
    }

    /// Unit and quantity words a declared name may not join to a number (`names.number.<n>`), lowercase. Matched
    /// without case, except the one-letter units, which match only in lowercase (so "A320" and "V8" stay names).
    static let quantityWords: Set<String> = [
        "mach", "rpm", "rps", "mph", "kph", "kmh", "kmph", "fps", "knots", "kt", "kts",
        "km", "cm", "mm", "nm", "um", "mi", "ft", "yd", "in", "inch", "nmi", "ly", "au",
        "kg", "mg", "lb", "lbs", "oz", "ton", "tons", "tonne",
        "kn", "kw", "mw", "gw", "hp", "bhp", "ps", "kj", "mj", "kwh", "wh", "mah", "kv", "mv", "ma",
        "hz", "khz", "mhz", "ghz", "ms", "us", "sec", "secs", "min", "mins", "hr", "hrs", "yr", "yrs", "day", "days",
        "ml", "cl", "dl", "gal", "cc", "psi", "bar", "mbar", "pa", "kpa", "mpa", "gpa", "atm",
        "deg", "rad", "db", "dba", "lux", "lm", "kb", "mb", "gb", "tb", "kib", "mib", "gib", "bit", "bits",
        "pct", "percent", "pc", "pcs", "usd", "eur", "gbp", "jpy", "cny", "aud", "cad", "chf", "inr", "krw", "rub", "btc",
    ]
    static let quantityLetters: Set<Character> = ["m", "g", "s", "h", "l", "t", "x", "k", "n", "w", "v", "a", "j", "c", "f", "b"]

    /// The number literals rule N1 finds in `chars`: the maximal runs of number characters (`isNumber`, the test the N1
    /// scan in `fill` and `MGExplainerHonesty.typedNumber` applies to each character).
    static func numberLiterals(_ chars: [Character]) -> [Range<Int>] {
        var out: [Range<Int>] = [], i = 0
        while i < chars.count {
            guard isNumber(chars[i]) else { i += 1; continue }
            var j = i
            while j < chars.count, isNumber(chars[j]) { j += 1 }
            out.append(i..<j)
            i = j
        }
        return out
    }

    /// True when a declared name is a number or a quantity (`names.number.<n>`), that is when any of these fails:
    /// (a) it starts with a letter (so "2e3", "1e-3", "120N", "100W", "0x1F", "3D" and "4th" fail);
    /// (b) no number literal that rule N1's scan finds (`numberLiterals`) covers the whole name (a letter that is also
    ///     a number character, such as the Roman numeral "Ⅻ", fails);
    /// (c) its leading letters (the letters before its first non-letter) are not a unit or quantity word
    ///     (`quantityWords`, matched without case, or a one-letter unit of `quantityLetters`, matched in lowercase only,
    ///     so "Mach2", "USD120", "RPM120", "kmh-90" and "x2" fail, and "A320", "V8" and "M6" pass).
    static func isQuantityName(_ name: String) -> Bool {
        let chars = Array(name)
        guard let first = chars.first, first.isLetter else { return true }
        if numberLiterals(chars).contains(0..<chars.count) { return true }
        let lead = String(chars.prefix { $0.isLetter && !isNumber($0) })
        if lead.count == 1, let c = lead.first { return quantityLetters.contains(c) }
        return quantityWords.contains(lead.lowercased())
    }

    /// A document's `names` list (docs/SOLID-3D.md, "Declared names"): 1–`namesCount` strings, each one token
    /// (`tokens`) of 1–`nameText` characters with (d) at least one number character, and not a number or a quantity
    /// (`isQuantityName`, rules (a)–(c)). A name whose original form has a number character other than an ASCII digit
    /// ("Ⅻ2", "Mk²", "Ａ３２０") is `names.number.<n>`. Each name is then put in Unicode NFKC form (`nfkc`), and every rule
    /// reads that form, so "Ｍａｃｈ２" is "Mach2" (a quantity); the list keeps the NFKC forms, and a token of the
    /// normalized text matches a name exactly (`typedNumberOffsets`). Reasons: `names.count` (not an array of strings,
    /// or a count out of range, with `limit`), `names.text.<n>` (length as written, or in NFKC form, with `limit`),
    /// `names.token.<n>` (not one token, or (d): no number character, so it needs no declaration), `names.number.<n>`
    /// (`<n>` 1-based). Repeats (in NFKC form) are kept once.
    static func names(_ v: MGJSON) throws -> [String] {
        guard case .array(let list) = v else { throw MGSolidIssue("names.count") }
        if let d = MGSolidParser.countDetail("names", list.count, 1...namesCount, unit: "names") { throw MGSolidIssue("names.count", limit: d) }
        var out: [String] = []
        for (k, e) in list.enumerated() {
            guard case .string(let raw) = e else { throw MGSolidIssue("names.count") }
            if let d = MGSolidParser.countDetail("names[\(k)]", raw.unicodeScalars.count, 1...nameText, unit: "characters") {
                throw MGSolidIssue("names.text.\(k + 1)", limit: d)
            }
            // A number character other than an ASCII digit ("Ⅻ", "²", "½", "٢", "２") is refused before the normalization
            // could turn it into letters or ASCII digits: declare names in plain form; text may use other forms.
            guard !raw.contains(where: { isNumber($0) && !($0.isASCII && $0.isNumber) }) else { throw MGSolidIssue("names.number.\(k + 1)") }
            let n = nfkc(raw)
            if let d = MGSolidParser.countDetail("names[\(k)]", n.unicodeScalars.count, 1...nameText, unit: "characters") {
                throw MGSolidIssue("names.text.\(k + 1)", limit: d)
            }
            let chars = Array(n)
            guard tokens(chars) == [0..<chars.count], chars.contains(where: isNumber) else { throw MGSolidIssue("names.token.\(k + 1)") }
            guard !isQuantityName(n) else { throw MGSolidIssue("names.number.\(k + 1)") }
            if !out.contains(n) { out.append(n) }
        }
        return out
    }

    // MARK: Table

    /// Builds the facts table from a compiled assembly and the tier of every drive. `sources`: what moves each driven
    /// part; `ownTiers`: the tier of each part's own drive before propagation (an `input` scale other than ±1 and a
    /// `follow` ratio are author behaviour, so Built; gear-mesh solves take the lowest input tier they depend on);
    /// `copies`: `repeat` copy id → base id; `aliases`: component anchor → part id.
    static func table(_ assembly: MGAssembly, gears: [String: MGSolidGear], sources: [String: String],
                      ownTiers: [String: MGSolidTier], copies: [String: String],
                      aliases: [String: String]) -> (facts: [String: MGSolidFact], driveTiers: [String: MGSolidTier]) {
        let byID = Dictionary(assembly.parts.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var facts: [String: MGSolidFact] = [:]
        func put(_ name: String, _ v: Double, _ unit: String, _ tier: MGSolidTier, _ source: String) {
            guard v.isFinite, facts[name] == nil else { return }
            facts[name] = MGSolidFact(value: v, unit: unit, tier: tier, source: source)
        }
        // Tier of each drive: its own tier and every drive it reads (drive cycles are refused before this runs).
        var tierMemo: [String: MGSolidTier] = [:], visiting = Set<String>()
        func driveTier(_ id: String) -> MGSolidTier {
            if let t = tierMemo[id] { return t }
            guard visiting.insert(id).inserted else { return .solved }
            defer { visiting.remove(id) }
            var t = ownTiers[id] ?? .solved
            switch byID[id]?.drive {
            case .follow(let src, _, _)?: t = min(t, driveTier(src))
            case .gear(let d, _, let c, _)?: t = min(t, driveTier(d), c.map(driveTier) ?? .solved)
            case .crankSlider(let c, _, _, _)?, .crankRod(let c, _, _)?: t = min(t, driveTier(c))
            default: break
            }
            tierMemo[id] = t
            return t
        }
        // Joint rate per input radian for linear drives (radians or mm); nil for the crank closed forms.
        var memo: [String: Double?] = [:]
        func rate(_ id: String) -> Double? {
            if let m = memo[id] { return m }
            memo[id] = .some(nil)
            var r: Double?
            switch byID[id]?.drive {
            case .input(let s, _)?: r = s
            case .follow(let src, let k, _)?: r = rate(src).map { k * $0 }
            case .gear(let d, let k, let c, _)?:
                if let rd = rate(d) { r = k * (rd - (c.map { rate($0) ?? 0 } ?? 0)) }
            default: r = nil
            }
            memo[id] = .some(r)
            return r
        }
        var driveTiers: [String: MGSolidTier] = [:]
        for p in assembly.parts where p.drive != nil { driveTiers[p.id] = driveTier(p.id) }
        let rest = MGSolidFrames.restWorld(assembly)
        func axisWorld(_ id: String) -> MGVec3? {
            guard case .revolute(let a)? = byID[id]?.joint else { return nil }
            return (rest[id] ?? .identity).applyVector(a).normalized
        }
        /// World turn rate about the part's own axis: its joint rate plus every turning revolute ancestor, when all
        /// of their axes are parallel to its own (prismatic ancestors do not change a turn rate). nil otherwise.
        func worldSpeed(_ id: String) -> (Double, MGSolidTier)? {
            guard let n = axisWorld(id), var total = rate(id) else { return nil }
            var tier = driveTier(id)
            var cur = byID[id]?.parent, seen: Set<String> = [id]
            while let c = cur, seen.insert(c).inserted, let pp = byID[c] {
                if case .revolute = pp.joint, pp.drive != nil {
                    guard let r = rate(c) else { return nil }
                    if r != 0 {
                        guard let a = axisWorld(c), abs(abs(a.dot(n)) - 1) < 1e-9 else { return nil }
                        total += (a.dot(n) >= 0 ? 1 : -1) * r
                        tier = min(tier, driveTier(c))
                    }
                }
                cur = pp.parent
            }
            return (total, tier)
        }
        // Travel of every driven prismatic joint over one input turn (sampled, endpoints included).
        let sliders = assembly.parts.filter { if case .prismatic = $0.joint, $0.drive != nil { return true }; return false }.map(\.id)
        var lo: [String: Double] = [:], hi: [String: Double] = [:]
        if !sliders.isEmpty {
            for k in 0...travelSamples {
                let q = assembly.jointValues(MGPoseParameters(input: 2 * .pi * Double(k) / Double(travelSamples)))
                for id in sliders { let v = q[id] ?? 0; lo[id] = min(lo[id] ?? v, v); hi[id] = max(hi[id] ?? v, v) }
            }
        }
        for p in assembly.parts {
            if let g = gears[p.id] {
                put(p.id + ".teeth", Double(g.teeth), "", .solved, "shape")
                put(p.id + ".module", g.module, "mm", .solved, "shape")
            }
            let source = sources[p.id] ?? "input"
            switch p.joint {
            case .revolute:
                if p.drive != nil, let r = rate(p.id) {
                    put(p.id + ".speed", r, "", driveTier(p.id), source)
                    if let (w, t) = worldSpeed(p.id) { put(p.id + ".worldSpeed", w, "", t, source) }
                }
            case .prismatic:
                if let a = lo[p.id], let b = hi[p.id] { put(p.id + ".travel", b - a, "mm", driveTier(p.id), source) }
            case .fixed: break
            }
            if case .crankSlider(_, let r, let l, _)? = p.drive {
                put(p.id + ".crankRadius", r, "mm", .solved, "crankSlider")
                put(p.id + ".rodLength", l, "mm", .solved, "crankSlider")
            }
        }
        // `repeat`: the copy count, and every fact all copies share, under the base id.
        var groups: [String: [String]] = [:]
        for p in assembly.parts { if let b = copies[p.id] { groups[b, default: []].append(p.id) } }
        for (base, ids) in groups.sorted(by: { $0.key < $1.key }) {
            put("count." + base, Double(ids.count), "", .solved, "repeat")
            let first = ids[0]
            for (name, f) in facts.sorted(by: { $0.key < $1.key }) where name.hasPrefix(first + ".") {
                let suffix = String(name.dropFirst(first.count))
                let same = ids.allSatisfy { id in
                    guard let o = facts[id + suffix] else { return false }
                    // Same unit, tier and sign, and equal within a relative 1e-9 with no absolute floor: tiny rates of
                    // opposite sign (+1e-10 and -1e-10) are not one shared value.
                    guard o.unit == f.unit, o.tier == f.tier, (o.value > 0) == (f.value > 0), (o.value < 0) == (f.value < 0) else { return false }
                    return o.value == f.value || abs(o.value - f.value) <= 1e-9 * max(abs(o.value), abs(f.value))
                }
                if same { put(base + suffix, f.value, f.unit, f.tier, f.source) }
            }
        }
        // `<instance>.ratio`: output anchor speed over input anchor speed (the lower tier of the two).
        for (key, inTarget) in aliases.sorted(by: { $0.key < $1.key }) where key.hasSuffix(".input") {
            let inst = String(key.dropLast(".input".count))
            guard let outTarget = aliases[inst + ".output"],
                  let a = facts[inTarget + ".speed"], let b = facts[outTarget + ".speed"], a.value != 0 else { continue }
            put(inst + ".ratio", b.value / a.value, "", min(a.tier, b.tier), "anchors")
        }
        return (facts, driveTiers)
    }

    /// Finds a fact by name. Component anchors resolve (`stage.output.speed` → `stage.carrier.speed`).
    static func lookup(_ name: String, _ facts: [String: MGSolidFact], _ aliases: [String: String]) -> (name: String, fact: MGSolidFact)? {
        if let f = facts[name] { return (name, f) }
        var cut = name.endIndex
        while let dot = name[..<cut].lastIndex(of: ".") {
            if let target = aliases[String(name[..<dot])] {
                let resolved = target + name[dot...]
                if let f = facts[resolved] { return (resolved, f) }
            }
            cut = dot
        }
        return nil
    }

    // MARK: Text

    /// Fills `{name}` / `{name|mod|…}` placeholders. With `n1`, every number character outside a placeholder is
    /// refused (`text.number.<where>`); without it, `typedNumbers` reports one. Reasons: `text.brace`,
    /// `text.placeholder` (bad grammar), `text.placeholder.<name>` (unknown fact), `text.modifier.<mod>` (unknown
    /// modifier), `text.modifier.<mod>.<name>` (a modifier that does not apply to this fact) and
    /// `text.rounding.<name>` (a non-zero value that would print as "0").
    static func fill(_ s: String, where w: String, n1: Bool, _ facts: [String: MGSolidFact],
                     _ aliases: [String: String], names: Set<String>) throws -> MGSolidFilledText {
        var out = MGSolidFilledText(text: "", facts: [])
        var body = "", inside = false
        let chars = Array(s), typed = typedNumberOffsets(chars, names: names)
        for (k, ch) in chars.enumerated() {
            if inside {
                if ch == "}" {
                    let (text, name, mods) = try placeholder(body, facts, aliases)
                    out.text += text; out.facts.append(name); out.modifiers.append(mods); body = ""; inside = false
                } else {
                    guard ch != "{", body.count < nameLength + 8 * modifiers else { throw MGSolidIssue(ch == "{" ? "text.brace" : "text.placeholder") }
                    body.append(ch)
                }
            } else if ch == "{" { inside = true }
            else if ch == "}" { throw MGSolidIssue("text.brace") }
            else {
                if typed.contains(k) {
                    if n1 { throw MGSolidIssue("text.number.\(w)") }
                    out.typedNumbers = true
                }
                out.text.append(ch)
            }
        }
        guard !inside else { throw MGSolidIssue("text.brace") }
        return out
    }

    static func placeholder(_ body: String, _ facts: [String: MGSolidFact], _ aliases: [String: String]) throws -> (String, String, [String]) {
        let pieces = body.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard let name = pieces.first, isName(name), pieces.count - 1 <= modifiers else { throw MGSolidIssue("text.placeholder") }
        let t = MGSolidParser.token(name)
        let mods = Array(pieces.dropFirst())
        for m in mods where !modifierNames.contains(m) {
            // A dot would make `text.modifier.<mod>` read like `text.modifier.<mod>.<name>`.
            throw MGSolidIssue(m.contains(".") ? "text.placeholder" : "text.modifier.\(MGSolidParser.token(m))")
        }
        guard let (canonical, fact) = lookup(name, facts, aliases) else { throw MGSolidIssue("text.placeholder.\(t)") }
        let turnRate = canonical.hasSuffix(".speed") || canonical.hasSuffix(".worldSpeed") || canonical.hasSuffix(".ratio")
        var v = fact.value
        var terminal: String?
        /// Every modifier result must be a finite, normal number (or exactly 0 from exactly 0): `inv` of 1e-309
        /// overflows to infinity, and a second `inv` would turn that into a false 0 (`text.range.<name>`).
        func inRange(_ x: Double) throws -> Double {
            guard x.isFinite, !x.isSubnormal, x != 0 || fact.value == 0 else { throw MGSolidIssue("text.range.\(t)") }
            return x
        }
        guard fact.value.isFinite else { throw MGSolidIssue("text.range.\(t)") }
        for m in mods {
            func bad() -> MGSolidIssue { MGSolidIssue("text.modifier.\(m).\(t)") }
            guard terminal == nil else { throw bad() }
            if m != "abs" { guard fact.unit.isEmpty else { throw bad() } }
            if m == "pct" || m == "deg" { guard turnRate else { throw bad() } }
            switch m {
            case "abs": v = abs(v)
            case "inv": guard v != 0 else { throw bad() }; v = try inRange(1 / v)
            case "pct": v = try inRange(v * 100); terminal = MGPhysics.format(v, unit: "") + "%"
            case "deg": v = try inRange(v * 360); terminal = MGPhysics.format(v, unit: "°")
            default:
                guard let f = fraction(v) else { throw bad() }
                terminal = f
            }
        }
        let text = terminal ?? MGPhysics.format(v, unit: fact.unit)
        // A non-zero number shown as "0" (for example a 1:300 reduction, 0.0033) is a false number; `frac` or `inv`
        // shows it honestly.
        let digits = text.filter(\.isNumber)
        if v != 0 || fact.value != 0, !digits.isEmpty, digits.allSatisfy({ $0 == "0" }) {
            throw MGSolidIssue("text.rounding.\(t)")
        }
        return (text, canonical, mods)
    }

    /// The exact fraction p/q (q ≤ 100 000) within 1e-12 × max(1, |x|) of `x`, as "p/q" ("2/7", "-1/3"); whole
    /// numbers print without a denominator. nil when no such fraction exists (for example π: 103993/33102 is only
    /// within 6e-10, so a looser tolerance would print an irrational number as a fraction).
    public static func fraction(_ x: Double) -> String? {
        guard x.isFinite, abs(x) <= 1e6 else { return nil }
        let a = abs(x)
        // Continued-fraction convergents h/k of a.
        var h0 = 0.0, h1 = 1.0, k0 = 1.0, k1 = 0.0, r = a
        for _ in 0..<64 {
            let f = r.rounded(.down)
            let h2 = f * h1 + h0, k2 = f * k1 + k0
            guard k2 <= Double(fractionDenominator) else { break }
            h0 = h1; h1 = h2; k0 = k1; k1 = k2
            if abs(h1 / k1 - a) <= fractionTolerance * max(1, a) {
                let p = Int(h1), q = Int(k1)
                let sign = x < 0 && p != 0 ? "-" : ""
                return q == 1 ? "\(sign)\(p)" : "\(sign)\(p)/\(q)"
            }
            let rest = r - f
            guard rest > 1e-15 else { break }
            r = 1 / rest
        }
        return nil
    }
}
