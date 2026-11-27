// SPDX-License-Identifier: Apache-2.0
import Foundation

/// Engine-computed calculus numbers of a `func` item: its wire `readouts` (docs/PROTOCOL.md, "Readouts: slopes and
/// areas"). Text names them as `{<id>.<readout>}` placeholders, so the model never writes these numbers itself.
///
/// - `value`: f(m) at the marked x `m` (`mark`), the point where the tangent touches.
/// - `slope`: the derivative f′(m), the slope of the tangent there. Exact: forward-mode differentiation applies the
///   closed-form rule of every operation of the expression (`MGExpression.valueAndSlope`) in double precision. Where a
///   rule has no value at that point (0/0, as `sqrt(x^4)` at 0, or a corner of `abs`, `min` or `max`), one-sided
///   differences are used instead (`fallbackSlope`). An infinite derivative (a vertical tangent) is refused.
/// - `area`: the signed area ∫ f(x) dx over the shaded interval (`shade`); parts below y = 0 count as negative. The
///   composite 5-point Gauss–Legendre rule on `MGLimits.readoutPanels` equal panels; its error estimate is the
///   difference from the same rule on half as many panels (`area`).
///
/// Every readout is shown as every engine number is (`MGPhysics.format`: 2 decimals below 10, 1 below 100, whole
/// numbers above) and is refused unless its error, or its error estimate, is at most half of the last shown digit.
/// The exact slope's error is only double rounding. So the number shown is within one unit of its last digit of the
/// exact value, as far as the estimate holds: a rule that agrees with itself at two resolutions can still miss detail
/// narrower than a panel, which the sampler's own checks (`MGGraph.checkFunction`) bound at the scale of the frame.
enum MGReadout: String, CaseIterable, Sendable {
    case value, slope, area

    /// The flag that marks this readout requested, and the `num` key of its value, in a parsed `func` item.
    var key: String { "readout." + rawValue }

    /// The keys of a `func` item that hold text. They are checked after the readouts of the scene are known.
    static let textKeys: Set<String> = ["label", "xl", "yl"]

    /// The readouts that `raw` (the wire `readouts` key) lists: 1 to `MGLimits.readouts` distinct names
    /// (`func.readouts`).
    static func parse(_ raw: MGJSON) throws -> [MGReadout] {
        guard case .array(let list) = raw, (1...MGLimits.readouts).contains(list.count) else { throw MGError("func.readouts") }
        var out: [MGReadout] = []
        for entry in list {
            guard case .string(let name) = entry, let r = MGReadout(rawValue: name), !out.contains(r) else { throw MGError("func.readouts") }
            out.append(r)
        }
        return out
    }

    /// What each readout needs, checked before anything is sampled, first match wins: a moving graph has none
    /// (`func.readouts.period`: its numbers would change while the text stays), `value` and `slope` need a `mark`
    /// (`func.readouts.mark`) and `area` a `shade` (`func.readouts.shade`).
    static func checkKeys(_ list: [MGReadout], _ item: MGItem) throws {
        if item.num["period"] != nil { throw MGError("func.readouts.period") }
        if list.contains(where: { $0 != .area }), item.num["mark"] == nil { throw MGError("func.readouts.mark") }
        if list.contains(.area), item.num["s0"] == nil || item.num["s1"] == nil { throw MGError("func.readouts.shade") }
    }

    /// The readouts a parsed item requested, in `allCases` order.
    static func requested(_ item: MGItem) -> [MGReadout] { allCases.filter { item.has($0.key) } }

    /// Computes the requested readouts of a checked `func` item (after `MGGraph.checkFunction`, which stores the
    /// samples, the piece starts and the marked value) into `num`.
    static func compute(_ item: inout MGItem, _ expr: MGExpression) throws {
        let list = requested(item)
        guard !list.isEmpty else { return }
        let x0 = item.n("x0"), x1 = item.n("x1"), y0 = item.n("y0"), y1 = item.n("y1")
        let base = MGGraph.inputs(item)
        let drawn = MGCurve(samples: Array(item.pts.dropFirst()), starts: item.marked)
        for r in list {
            switch r {
            case .value:
                item.num[r.key] = item.num["my"]
            case .slope:
                item.num[r.key] = try slope(expr, base, at: item.n("mark"), x0: x0, x1: x1, drawn: drawn)
            case .area:
                item.num[r.key] = try area({ expr.value(base.with(x: $0)) }, item.n("s0"), item.n("s1"), y0: y0, y1: y1)
            }
        }
    }

    // MARK: slope

    /// f′(m), or `func.readouts.slope` when the marked point is not inside one drawn piece with a value on both sides
    /// of it (one probe width of `MGGraph.curve` away), when the derivative is infinite or above 10¹² in size, or
    /// when the exact rule has no value there and the one-sided differences do not agree (`fallbackSlope`).
    static func slope(_ expr: MGExpression, _ base: MGExpression.Inputs, at m: Double, x0: Double, x1: Double,
                      drawn: MGCurve) throws -> Double {
        let refuse = MGError("func.readouts.slope")
        let f = { (x: Double) in expr.value(base.with(x: x)) }
        let probe = (x1 - x0) / Double(MGLimits.funcIntervals) / 1024
        guard drawn.covers(m, m), f(m - probe).isFinite, f(m + probe).isFinite else { throw refuse }
        var s = expr.valueAndSlope(base.with(x: m)).slope
        if s.isNaN { s = try fallbackSlope(f, at: m, step: (x1 - x0) / Double(MGLimits.funcIntervals * 64)) }
        guard s.isFinite, Swift.abs(s) <= MGGraph.magnitude else { throw refuse }
        return s
    }

    /// The slope at `m` from second-order one-sided differences, used only where the exact rule has no value.
    /// D₊(k) = (−3f(m) + 4f(m + k) − f(m + 2k)) / 2k and D₋(k) = (3f(m) − 4f(m − k) + f(m − 2k)) / 2k at k = `h` and
    /// k = `h` / 2 (`h` is 1/64 of a sampling interval; 7 evaluations). The slope is the mean of D₊(h/2) and D₋(h/2).
    /// Refused (`func.readouts.slope`) when a value is not finite; when the two sides do not approach each other as
    /// the step halves (a corner: |D₊(h/2) − D₋(h/2)| is above both half of |D₊(h) − D₋(h)| and the rounding level
    /// 2⁻⁴⁰ × max |f| / h); or when the error estimate, the largest of |D₊(h/2) − D₊(h)|, |D₋(h/2) − D₋(h)| and
    /// |D₊(h/2) − D₋(h/2)|, is above half of the last shown digit.
    static func fallbackSlope(_ f: (Double) -> Double, at m: Double, step h: Double) throws -> Double {
        let refuse = MGError("func.readouts.slope")
        let f0 = f(m)
        let p1 = f(m + h / 2), p2 = f(m + h), p4 = f(m + 2 * h)
        let m1 = f(m - h / 2), m2 = f(m - h), m4 = f(m - 2 * h)
        let values = [f0, p1, p2, p4, m1, m2, m4]
        guard values.allSatisfy(\.isFinite) else { throw refuse }
        let rightFine = (-3 * f0 + 4 * p1 - p2) / h, rightCoarse = (-3 * f0 + 4 * p2 - p4) / (2 * h)
        let leftFine = (3 * f0 - 4 * m1 + m2) / h, leftCoarse = (3 * f0 - 4 * m2 + m4) / (2 * h)
        let s = (rightFine + leftFine) / 2
        let gap = Swift.abs(rightFine - leftFine), coarseGap = Swift.abs(rightCoarse - leftCoarse)
        let noise = values.map { Swift.abs($0) }.reduce(0, Swift.max) / h * 0x1p-40
        guard gap <= noise || gap <= coarseGap / 2 else { throw refuse }
        let error = Swift.max(Swift.abs(rightFine - rightCoarse), Swift.abs(leftFine - leftCoarse), gap)
        guard error <= resolution(s) / 2 else { throw refuse }
        return s
    }

    // MARK: area

    /// Gauss–Legendre nodes on [−1, 1] and their weights (5 points: exact for polynomials up to degree 9).
    static let nodes: [Double] = [-0.906179845938664, -0.5384693101056831, 0, 0.5384693101056831, 0.906179845938664]
    static let weights: [Double] = [0.23692688505618908, 0.47862867049936647, 0.5688888888888889, 0.47862867049936647,
                                    0.23692688505618908]

    /// ∫ f over [s0, s1] with the composite 5-point Gauss–Legendre rule on `MGLimits.readoutPanels` equal panels.
    /// Refused as `func.readouts.area` when f has no finite value at a node of either rule or at an end of the
    /// interval; when the result differs from the same rule on half as many panels by more than half of its last
    /// shown digit; when the same two rules applied to |f| differ by more than that or 1/1024 of the result, whichever
    /// is larger (a pole whose two sides cancel, as `1/x` over [−1, 1], converges for f but not for |f|); or when
    /// the area is above 10¹² in size. Then `func.readouts.view` when the shaded band is not the region measured:
    /// y = 0 or f at an end or a node of the finer rule is outside the y range, where the band is clipped.
    /// 962 evaluations (640 + 320 nodes and the two ends).
    static func area(_ f: (Double) -> Double, _ s0: Double, _ s1: Double, y0: Double, y1: Double) throws -> Double {
        let refuse = MGError("func.readouts.area")
        var fine: [Double] = [], coarse: [Double] = []
        let a = gauss(f, s0, s1, panels: MGLimits.readoutPanels, values: &fine)
        let b = gauss(f, s0, s1, panels: MGLimits.readoutPanels / 2, values: &coarse)
        let ends = [f(s0), f(s1)]
        guard (fine + coarse + ends).allSatisfy(\.isFinite) else { throw refuse }
        let tolerance = resolution(a.sum) / 2
        guard Swift.abs(a.sum - b.sum) <= tolerance, Swift.abs(a.abs - b.abs) <= Swift.max(tolerance, a.abs / 1024),
              Swift.abs(a.sum) <= MGGraph.magnitude else { throw refuse }
        guard y0 <= 0, y1 >= 0, (ends + fine).allSatisfy({ $0 >= y0 && $0 <= y1 }) else { throw MGError("func.readouts.view") }
        return a.sum
    }

    /// The composite rule for f and |f| on `panels` equal panels of [a, b] (the last ends exactly at `b`); appends each
    /// node value to `values`, panel by panel from the left, nodes in order.
    static func gauss(_ f: (Double) -> Double, _ a: Double, _ b: Double, panels: Int,
                      values: inout [Double]) -> (sum: Double, abs: Double) {
        var sum = 0.0, total = 0.0
        for k in 0..<panels {
            let lo = a + (b - a) * Double(k) / Double(panels)
            let hi = k == panels - 1 ? b : a + (b - a) * Double(k + 1) / Double(panels)
            let mid = (lo + hi) / 2, half = (hi - lo) / 2
            var s = 0.0, t = 0.0
            for j in 0..<nodes.count {
                let y = f(mid + half * nodes[j])
                values.append(y)
                s += weights[j] * y
                t += weights[j] * Swift.abs(y)
            }
            sum += half * s
            total += half * t
        }
        return (sum, total)
    }

    /// The step between two numbers as `MGPhysics.format` shows `v`: 1 from 100 up, 0.1 from 10 up, else 0.01.
    static func resolution(_ v: Double) -> Double {
        let a = Swift.abs(v)
        return a >= 100 ? 1 : a >= 10 ? 0.1 : 0.01
    }

    // MARK: scene

    /// The scene values of the readouts of `items`, in order (the first item with an id wins; a repeated id refuses
    /// the scene later): `<id>.<readout>` without a unit.
    static func values(_ items: [MGItem]) -> [String: MGValue] {
        var out: [String: MGValue] = [:]
        for item in items where item.kind == .function {
            for r in requested(item) {
                let name = item.id + "." + r.rawValue
                if out[name] == nil, let v = item.num[r.key] { out[name] = MGValue(value: v, unit: "") }
            }
        }
        return out
    }

    /// The readout placeholder that `scalars` spells (an item id as `MGParser.identifier` takes it, a dot and a
    /// readout name), or nil.
    static func placeholder(_ scalars: ArraySlice<Unicode.Scalar>) -> String? {
        guard let dot = scalars.firstIndex(of: ".") else { return nil }
        var id = "", name = ""
        id.unicodeScalars.append(contentsOf: scalars[scalars.startIndex..<dot])
        name.unicodeScalars.append(contentsOf: scalars[(dot + 1)...])
        guard let r = MGReadout(rawValue: name), (try? MGParser.identifier(.string(id), "id")) != nil else { return nil }
        return id + "." + r.rawValue
    }

    /// A step edit of item `id` may not change a readout the scene's text was filled with (`func.readouts.edit`):
    /// the text is filled once, so its numbers must stay true at every step.
    static func checkEdit(_ id: String, _ items: [MGItem], _ values: [String: MGValue]) throws {
        for r in allCases {
            guard let published = values[id + "." + r.rawValue] else { continue }
            guard let item = items.first(where: { $0.id == id }), item.kind == .function,
                  item.num[r.key] == published.value else { throw MGError("func.readouts.edit") }
        }
    }
}

extension MGExpression {
    /// The value and the derivative with respect to `x` at `inputs`, by forward-mode differentiation: each operation
    /// carries its exact derivative rule (d sin u = cos u du, d uᵛ = v uᵛ⁻¹ du for a constant v, …). The value is
    /// computed by the same operations as `value`, so the two agree exactly. The derivative is not a number where a
    /// rule has no value at that point (0/0 or 0 × ∞, as `sqrt(x^2)` at 0, or a corner of `abs`, `min` or `max`) and
    /// infinite where the derivative is (a vertical tangent, as `sqrt(x)` at 0).
    func valueAndSlope(_ inputs: Inputs) -> (value: Double, slope: Double) {
        var v = [Double](repeating: 0, count: Swift.max(1, program.count)), d = v
        var n = 0
        for op in program {
            switch op {
            case .number(let c):
                guard n < v.count else { return (.nan, .nan) }
                v[n] = c; d[n] = 0; n += 1
            case .variable(let x):
                guard n < v.count else { return (.nan, .nan) }
                v[n] = inputs[x]; d[n] = x == .x ? 1 : 0; n += 1
            case .negate:
                guard n >= 1 else { return (.nan, .nan) }
                v[n - 1] = -v[n - 1]; d[n - 1] = -d[n - 1]
            case .call(let f) where f.arity == 1:
                guard n >= 1 else { return (.nan, .nan) }
                (v[n - 1], d[n - 1]) = (Self.apply(f, v[n - 1]), Self.slope(f, v[n - 1], d[n - 1]))
            case .add, .subtract, .multiply, .divide, .power, .call:
                guard n >= 2 else { return (.nan, .nan) }
                (v[n - 2], d[n - 2]) = (Self.combine(op, v[n - 2], v[n - 1]), Self.slope(op, v[n - 2], d[n - 2], v[n - 1], d[n - 1]))
                n -= 1
            }
        }
        return n == 1 ? (v[0], d[0]) : (.nan, .nan)
    }

    /// The derivative of f(u) for u′ = `du`.
    static func slope(_ f: Function, _ u: Double, _ du: Double) -> Double {
        switch f {
        case .sin: return cos(u) * du
        case .cos: return -sin(u) * du
        case .tan: return du / (cos(u) * cos(u))
        case .asin: return du / (1 - u * u).squareRoot()
        case .acos: return -du / (1 - u * u).squareRoot()
        case .atan: return du / (1 + u * u)
        case .sinh: return cosh(u) * du
        case .cosh: return sinh(u) * du
        case .tanh: let t = tanh(u); return (1 - t * t) * du
        case .exp: return exp(u) * du
        case .ln: return du / u
        case .log: return du / (u * 2.302585092994046)
        case .sqrt: return du / (2 * u.squareRoot())
        case .abs:
            if u.isNaN { return .nan }
            return u > 0 ? du : u < 0 ? -du : du == 0 ? 0 : .nan
        case .min, .max: return .nan
        }
    }

    /// The derivative of `l op r` for l′ = `dl` and r′ = `dr`.
    static func slope(_ op: Op, _ l: Double, _ dl: Double, _ r: Double, _ dr: Double) -> Double {
        switch op {
        case .add: return dl + dr
        case .subtract: return dl - dr
        case .multiply: return dl * r + l * dr
        case .divide: return (dl - l / r * dr) / r
        case .power:
            let p = pow(l, r)
            if dr == 0 { return r * pow(l, r - 1) * dl }
            if dl == 0 { return p * log(l) * dr }
            return p * (dr * log(l) + r * dl / l)
        case .call(.min), .call(.max):
            if l.isNaN || r.isNaN { return .nan }
            // The smaller (larger) side's derivative; a tie is a corner unless both sides have the same slope.
            if l == r { return dl == dr ? dl : .nan }
            return (l < r) == (op == .call(.min)) ? dl : dr
        default: return .nan
        }
    }
}
