// SPDX-License-Identifier: Apache-2.0
import Foundation

/// Engine-computed calculus numbers of a `func` item: its wire `readouts` (docs/PROTOCOL.md, "Readouts: slopes and
/// areas"). Text names them as `{<id>.<readout>}` placeholders, so the model never writes these numbers itself.
///
/// - `value`: f(m) at the marked x `m` (`mark`), the point where the tangent touches.
/// - `slope`: the derivative f′(m), the slope of the tangent there, or a refusal. Proven, never estimated: both
///   one-sided derivatives come from the closed-form rule of every operation (`MGExpression.local`, forward mode in
///   double precision) and must be the same finite number. A corner, a cusp, a vertical tangent, a pole and the edge of
///   a function's domain are refused, and so is a mark one probe or less from any of them (`slope`).
/// - `area`: the signed area ∫ f(x) dx of the analytic curve over the shaded interval (`shade`); parts below y = 0
///   count as negative. Interval arithmetic, rounded outward, first certifies by bounded subdivision that the analytic
///   curve is continuous on the whole interval and stays in the y range (`certify`). Then the composite 5-point Gauss–Legendre rule on
///   `MGLimits.readoutPanels` equal panels; its error estimate is the difference from the same rule on half as many
///   panels (`area`). The drawn band (`MGGraph.shadeBands`) is a clipped, piecewise-linear picture of that region.
///
/// Every readout is shown as every engine number is (`MGPhysics.format`: 2 decimals below 10, 1 below 100, whole
/// numbers above). The slope's only error is double rounding. The area is refused unless its error estimate is at most
/// half of the last shown digit, so the number shown is within one unit of its last digit of the exact value as far as
/// the estimate holds: on a certified continuous curve, two rules that agree can still both miss a feature narrower
/// than a panel.
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
                item.num[r.key] = try area({ expr.value(base.with(x: $0)) }, enclose: { expr.enclosure(base, $0, $1) },
                                           item.n("s0"), item.n("s1"), y0: y0, y1: y1)
            }
        }
    }

    // MARK: slope

    /// f′(m), or `func.readouts.slope` unless it is proven, in this order:
    /// - the marked point lies inside one drawn piece (`MGCurve.covers`);
    /// - every operation has a finite value at m (`MGExpression.Local.sides`);
    /// - no kink, pole or domain edge lies within a probe (1/1024 of a sampling interval, as `MGGraph.curve` probes) of
    ///   m. Interval arithmetic, rounded outward (`MGExpression.intervals`), runs over each half, [m − probe, m] and
    ///   [m, m + probe], and must find an enclosure of every operation there. What each kink, pole or domain edge is
    ///   measured by (an `abs` argument, the difference of a `min`/`max` pair, a divisor, a `sqrt`/`ln`/`log`
    ///   argument, 1 − |u| for `asin`/`acos`, cos u for `tan`, the base of a power) must then stay strictly on its
    ///   side at m over both halves, so two corners that cancel between the probes are refused too
    ///   (`abs((x - 0.000003)*(x - 0.000006))` at 0). One that is exactly at its kink at m must not cross it within
    ///   either half, so m is its only crossing there, and is left to the one-sided rules (`x*abs(x)` at 0);
    /// - both one-sided derivatives (`MGExpression.local`) are the same finite number, at most 10¹² in size. A
    ///   smooth point always gives two equal numbers; a corner (`abs(x)` at 0, `min(x, x^3)` at 1), however small,
    ///   never does; and where only a domain edge is left (`sqrt(x^4)` or `(x^2)^1.5` at 0) no rule applies, so it is
    ///   refused even where the derivative exists.
    /// One forward-mode pass at m and two interval passes.
    static func slope(_ expr: MGExpression, _ base: MGExpression.Inputs, at m: Double, x0: Double, x1: Double,
                      drawn: MGCurve) throws -> Double {
        let refuse = MGError("func.readouts.slope")
        let probe = (x1 - x0) / Double(MGLimits.funcIntervals) / 1024
        guard drawn.covers(m, m) else { throw refuse }
        let at = expr.local(base.with(x: m))
        guard let sides = at.sides,
              let left = expr.intervals(base, MGExpression.sum(m, -probe, up: false), m)?.edges,
              let right = expr.intervals(base, m, MGExpression.sum(m, probe, up: true))?.edges,
              left.count == sides.count, right.count == sides.count else { throw refuse }
        for i in sides.indices {
            guard let l = left[i], let r = right[i] else { continue }
            if sides[i] != 0 {
                guard MGExpression.strictSide(l) == sides[i], MGExpression.strictSide(r) == sides[i] else { throw refuse }
            } else {
                guard l.lo >= 0 || l.hi <= 0, r.lo >= 0 || r.hi <= 0 else { throw refuse }
            }
        }
        let s = at.right
        guard at.left == s, s.isFinite, Swift.abs(s) <= MGGraph.magnitude else { throw refuse }
        return s
    }

    // MARK: area

    /// Gauss–Legendre nodes on [−1, 1] and their weights (5 points: exact for polynomials up to degree 9).
    static let nodes: [Double] = [-0.906179845938664, -0.5384693101056831, 0, 0.5384693101056831, 0.906179845938664]
    static let weights: [Double] = [0.23692688505618908, 0.47862867049936647, 0.5688888888888889, 0.47862867049936647,
                                    0.23692688505618908]

    /// ∫ f over [s0, s1], the integral of the analytic curve, in this order:
    /// - `certify`: interval arithmetic proves, by bounded subdivision, that f is continuous on the whole interval and
    ///   stays in the y range (`func.readouts.area` or `func.readouts.view` when it cannot, within its budget);
    /// - the composite 5-point Gauss–Legendre rule on `MGLimits.readoutPanels` equal panels and on half as many.
    ///   Refused as `func.readouts.area` when f has no finite value at a node of either rule or at an end of the
    ///   interval; when the two results differ by more than half of the last shown digit; when the same two rules
    ///   applied to |f| differ by more than that or 1/1024 of the result, whichever is larger; or when the area is
    ///   above 10¹² in size;
    /// - `func.readouts.view` when y = 0 is outside the y range, or any sampled value (every node of both rules and
    ///   both ends) is, where the drawn band would be clipped.
    /// At most `certifyBudget` enclosures (`enclose`, one interval pass of the expression each), then 962 evaluations
    /// of `f` (640 + 320 nodes and the two ends).
    static func area(_ f: (Double) -> Double, enclose: (Double, Double) -> (lo: Double, hi: Double)?,
                     _ s0: Double, _ s1: Double, y0: Double, y1: Double) throws -> Double {
        let refuse = MGError("func.readouts.area")
        try certify(enclose, s0, s1, y0: y0, y1: y1)
        var fine: [Double] = [], coarse: [Double] = []
        let a = gauss(f, s0, s1, panels: MGLimits.readoutPanels, values: &fine)
        let b = gauss(f, s0, s1, panels: MGLimits.readoutPanels / 2, values: &coarse)
        let samples = fine + coarse + [f(s0), f(s1)]
        guard samples.allSatisfy(\.isFinite) else { throw refuse }
        let tolerance = resolution(a.sum) / 2
        guard Swift.abs(a.sum - b.sum) <= tolerance, Swift.abs(a.abs - b.abs) <= Swift.max(tolerance, a.abs / 1024),
              Swift.abs(a.sum) <= MGGraph.magnitude else { throw refuse }
        guard y0 <= 0, y1 >= 0, samples.allSatisfy({ $0 >= y0 && $0 <= y1 }) else { throw MGError("func.readouts.view") }
        return a.sum
    }

    /// Halvings of the shaded interval `certify` may make: its smallest cell is 1/1024 of the interval.
    static let certifyDepth = 10
    /// Enclosures one area readout may compute in `certify`.
    static let certifyBudget = 256

    /// Proves that f is continuous on [s0, s1] and stays in the y range there, or refuses. `enclose(a, b)` is an
    /// enclosure of the analytic f over [a, b] (`MGExpression.enclosure`, rounded outward), or nil when interval
    /// arithmetic cannot show f continuous there (a divisor range that holds 0, a pole of `tan`, an argument outside a
    /// domain, a bound that is not finite). A cell is certified when
    /// its enclosure lies within [y0 − d, y1 + d], d being `MGLimits.funcTolerance` of the y range: the drawing
    /// tolerance, which also keeps a curve that touches the edge of the range (`1000*x` up to y = 1000) from being
    /// refused for the overestimate of interval arithmetic. Any other cell is halved, depth first and left half first,
    /// down to `certifyDepth` halvings. A cell that is still not certified there is `func.readouts.area` when it has
    /// no enclosure (a singularity, even one between every sample: `0.000001/(x - 0.3)`) and `func.readouts.view`
    /// when its enclosure leaves the range (a spike between samples). More than `certifyBudget` enclosures in all is
    /// `func.readouts.area`. A removable singularity (`sin(x)/x` at 0) is refused too: no enclosure holds 0/0.
    static func certify(_ enclose: (Double, Double) -> (lo: Double, hi: Double)?, _ s0: Double, _ s1: Double,
                        y0: Double, y1: Double) throws {
        let slack = MGLimits.funcTolerance * (y1 - y0)
        var cells: [(a: Double, b: Double, depth: Int)] = [(s0, s1, 0)]
        var used = 0
        while let cell = cells.popLast() {
            used += 1
            guard used <= certifyBudget else { throw MGError("func.readouts.area") }
            let e = enclose(cell.a, cell.b)
            if let e, e.lo >= y0 - slack, e.hi <= y1 + slack { continue }
            guard cell.depth < certifyDepth else { throw MGError(e == nil ? "func.readouts.area" : "func.readouts.view") }
            let mid = cell.a + (cell.b - cell.a) / 2
            cells.append((mid, cell.b, cell.depth + 1))
            cells.append((cell.a, mid, cell.depth + 1))
        }
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
    /// One pass of `local`: the value, the derivatives along +x and along −x, and the side of each operation.
    struct Local: Equatable {
        /// The value, computed by the same operations as `value`, so the two agree exactly.
        var value: Double
        /// The one-sided derivatives with respect to x, from the left and from the right. Not a number where no rule
        /// proves one (see `local`).
        var left: Double, right: Double
        /// For each operation in program order, the side of its kink, pole or domain edge that its operands are on:
        /// −1 or 1, 0 at the kink or edge itself and for an operation that has none (`side`). nil when some operation
        /// has no finite value.
        var sides: [Int8]?
    }

    /// The value and the one-sided derivatives with respect to `x` at `inputs`, by forward-mode differentiation along
    /// +x and along −x (the derivative from the left is minus the one along −x). Every operation applies its exact rule
    /// (d sin u = cos u du, d uᵛ = v uᵛ⁻¹ du when the exponent does not read x, …) where it is smooth; at the kink of
    /// `abs`, `min` or `max` it applies the one-sided rule (|du|; the smaller or larger of the two derivatives),
    /// which is exact for a function made of smooth pieces. No rule applies, so both derivatives are not a number, at
    /// the edge of a domain (`sqrt` at 0, `asin` and `acos` at ±1, a fractional power at base 0, a power whose
    /// exponent reads x at a base ≤ 0) or where some operation has no finite value. Where the expression is smooth at
    /// `inputs` the two derivatives are exactly the same number: each rule is linear in du and IEEE rounding is
    /// symmetric. The exponent counts as constant only when its subexpression does not read x, never because its
    /// derivative happens to be 0 at one point.
    func local(_ inputs: Inputs) -> Local {
        let size = Swift.max(1, program.count)
        // Value, derivative along +x, derivative along −x, and whether the entry reads x.
        var v = [Double](repeating: 0, count: size), p = v, q = v
        var reads = [Bool](repeating: false, count: size)
        var sides: [Int8] = [], finite = true
        var n = 0
        let broken = Local(value: .nan, left: .nan, right: .nan, sides: nil)
        for op in program {
            var side: Int8 = 0
            switch op {
            case .number(let c):
                guard n < size else { return broken }
                (v[n], p[n], q[n], reads[n]) = (c, 0, 0, false); n += 1
            case .variable(let x):
                guard n < size else { return broken }
                (v[n], p[n], q[n], reads[n]) = (inputs[x], x == .x ? 1 : 0, x == .x ? -1 : 0, x == .x); n += 1
            case .negate:
                guard n >= 1 else { return broken }
                (v[n - 1], p[n - 1], q[n - 1]) = (-v[n - 1], -p[n - 1], -q[n - 1])
            case .call(let f) where f.arity == 1:
                guard n >= 1 else { return broken }
                let u = v[n - 1]
                side = Self.side(f, u)
                (v[n - 1], p[n - 1], q[n - 1]) = (Self.apply(f, u), Self.slope(f, u, p[n - 1]),
                                                  Self.slope(f, u, q[n - 1]))
            case .add, .subtract, .multiply, .divide, .power, .call:
                guard n >= 2 else { return broken }
                let l = v[n - 2], r = v[n - 1], constant = !reads[n - 1]
                side = Self.side(op, l, r, constant: constant)
                (v[n - 2], p[n - 2], q[n - 2]) = (Self.combine(op, l, r),
                                                  Self.slope(op, l, p[n - 2], r, p[n - 1], constant: constant),
                                                  Self.slope(op, l, q[n - 2], r, q[n - 1], constant: constant))
                reads[n - 2] = reads[n - 2] || reads[n - 1]
                n -= 1
            }
            if !v[n - 1].isFinite { finite = false }
            sides.append(side)
        }
        guard n == 1 else { return broken }
        guard finite else { return Local(value: v[0], left: .nan, right: .nan, sides: nil) }
        return Local(value: v[0], left: -q[0], right: p[0], sides: sides)
    }

    /// The value and the derivative with respect to `x` at `inputs` (`local`): the derivative where both one-sided
    /// derivatives are the same number, else not a number.
    func valueAndSlope(_ inputs: Inputs) -> (value: Double, slope: Double) {
        let l = local(inputs)
        return (l.value, l.left == l.right ? l.right : .nan)
    }

    static func sign(_ v: Double) -> Int8 { v > 0 ? 1 : v < 0 ? -1 : 0 }

    /// The side of the kink or domain edge of `f` that `u` is on: `abs`, `sqrt`, `ln` and `log` at 0, `asin` and
    /// `acos` at ±1, `tan` at its poles; 0 for the other functions.
    static func side(_ f: Function, _ u: Double) -> Int8 {
        switch f {
        case .abs, .sqrt, .ln, .log: return sign(u)
        case .asin, .acos: return sign(1 - Swift.abs(u))
        case .tan: return sign(cos(u))
        default: return 0
        }
    }

    /// The side of the kink, pole or domain edge of `l op r`: the divisor's sign, the order of a `min`/`max` pair,
    /// and the base's sign for a power, except a power to a constant whole exponent of 0 or more (a polynomial).
    static func side(_ op: Op, _ l: Double, _ r: Double, constant: Bool) -> Int8 {
        switch op {
        case .divide: return sign(r)
        case .power: return constant && r >= 0 && r.rounded() == r ? 0 : sign(l)
        case .call(.min), .call(.max): return sign(l - r)
        default: return 0
        }
    }

    /// The derivative of f(u) along a direction in which u changes by `du` (see `local`).
    static func slope(_ f: Function, _ u: Double, _ du: Double) -> Double {
        switch f {
        case .sin: return cos(u) * du
        case .cos: return -sin(u) * du
        case .tan: return du / (cos(u) * cos(u))
        case .asin: return Swift.abs(u) < 1 ? du / (1 - u * u).squareRoot() : .nan
        case .acos: return Swift.abs(u) < 1 ? -du / (1 - u * u).squareRoot() : .nan
        case .atan: return du / (1 + u * u)
        case .sinh: return cosh(u) * du
        case .cosh: return sinh(u) * du
        case .tanh: let t = tanh(u); return (1 - t * t) * du
        case .exp: return exp(u) * du
        case .ln: return u > 0 ? du / u : .nan
        case .log: return u > 0 ? du / (u * 2.302585092994046) : .nan
        case .sqrt: return u > 0 ? du / (2 * u.squareRoot()) : .nan
        case .abs: return u > 0 ? du : u < 0 ? -du : u == 0 ? Swift.abs(du) : .nan
        case .min, .max: return .nan
        }
    }

    /// The derivative of `l op r` along a direction in which l and r change by `dl` and `dr` (see `local`).
    /// `constant`: the exponent of a power does not read x.
    static func slope(_ op: Op, _ l: Double, _ dl: Double, _ r: Double, _ dr: Double, constant: Bool) -> Double {
        switch op {
        case .add: return dl + dr
        case .subtract: return dl - dr
        case .multiply: return dl * r + l * dr
        case .divide: return (dl - l / r * dr) / r
        case .power:
            if constant {
                // uᵛ for a constant v: 1 when v = 0, a polynomial or rational function for a whole v, and smooth for a
                // positive base; a fractional power at base 0 is at the edge of its domain.
                if r == 0 { return 0 }
                return r.rounded() == r || l > 0 ? r * pow(l, r - 1) * dl : .nan
            }
            // uᵛ = exp(v ln u) needs u > 0 around the point.
            return l > 0 ? pow(l, r) * (dr * log(l) + r * dl / l) : .nan
        case .call(.min), .call(.max):
            if l.isNaN || r.isNaN || dl.isNaN || dr.isNaN { return .nan }
            if l == r { return op == .call(.min) ? (dr < dl ? dr : dl) : (dr > dl ? dr : dl) }
            return (l < r) == (op == .call(.min)) ? dl : dr
        default: return .nan
        }
    }

    // MARK: enclosures

    /// Bounds on a value: every exact value of a subexpression over an interval lies in [lo, hi].
    typealias Bounds = (lo: Double, hi: Double)

    /// An enclosure of the analytic expression over x in [`a`, `b`] (the other inputs fixed), from `intervals`.
    func enclosure(_ inputs: Inputs, _ a: Double, _ b: Double) -> Bounds? {
        intervals(inputs, a, b)?.value
    }

    /// One interval pass over x in [`a`, `b`] (the other inputs fixed): an enclosure of the expression, and for each
    /// operation in program order an enclosure of what its kink, pole or domain edge is measured by (`edge`), nil for
    /// an operation that has none.
    ///
    /// The bounds hold the exact value of every subexpression, the literals, `pi` and `e` being the doubles they parse
    /// to, so an enclosure holds the analytic curve and not only its double-precision evaluation (in which
    /// `(10^20 + x) - 10^20` is 0 for every |x| < 8192). Every operation rounds outward. `+`, `−`, `×`, `÷` and whole
    /// powers move a bound to the next double outward exactly when its rounded result is not exact (`sum`, `product`,
    /// `quotient`, `wholePower`), so an exact bound stays exact: `1 - x^2` is exactly [0, 1] over [−1, 1]. Negation,
    /// `abs`, `min` and `max` are exact. A library function widens its bounds by `libraryUlps` within its range
    /// (`libraryHull`). nil when interval arithmetic cannot show the expression continuous over the interval: a divisor
    /// range that holds 0, a pole of `tan` that may lie inside (`mayHold`), a `sqrt`, `ln`, `log`, `asin` or `acos`
    /// argument that leaves the domain, a power outside its domain (a base range that reaches below 0, or 0 for a
    /// negative or varying exponent), or a bound that is not finite.
    func intervals(_ inputs: Inputs, _ a: Double, _ b: Double) -> (value: Bounds, edges: [Bounds?])? {
        guard a <= b else { return nil }
        let size = Swift.max(1, program.count)
        var lo = [Double](repeating: 0, count: size), hi = lo
        // Whether the entry reads x, as in `local`.
        var reads = [Bool](repeating: false, count: size)
        var edges: [Bounds?] = []
        var n = 0
        for op in program {
            var edge: Bounds? = nil
            switch op {
            case .number(let c):
                guard n < size else { return nil }
                (lo[n], hi[n], reads[n]) = (c, c, false); n += 1
            case .variable(let x):
                guard n < size else { return nil }
                (lo[n], hi[n], reads[n]) = x == .x ? (a, b, true) : (inputs[x], inputs[x], false); n += 1
            case .negate:
                guard n >= 1 else { return nil }
                (lo[n - 1], hi[n - 1]) = (-hi[n - 1], -lo[n - 1])
            case .call(let f) where f.arity == 1:
                guard n >= 1 else { return nil }
                let u = (lo[n - 1], hi[n - 1])
                edge = Self.edge(f, u)
                guard let r = Self.enclose(f, u.0, u.1) else { return nil }
                (lo[n - 1], hi[n - 1]) = r
            case .add, .subtract, .multiply, .divide, .power, .call:
                guard n >= 2 else { return nil }
                let l = (lo[n - 2], hi[n - 2]), r = (lo[n - 1], hi[n - 1])
                edge = Self.edge(op, l, r, constant: !reads[n - 1])
                guard let v = Self.enclose(op, l, r) else { return nil }
                (lo[n - 2], hi[n - 2]) = v
                reads[n - 2] = reads[n - 2] || reads[n - 1]
                n -= 1
            }
            guard lo[n - 1].isFinite, hi[n - 1].isFinite, lo[n - 1] <= hi[n - 1] else { return nil }
            edges.append(edge)
        }
        guard n == 1 else { return nil }
        return (value: (lo: lo[0], hi: hi[0]), edges: edges)
    }

    /// 1 or −1 when every value in `e` is above or below 0, else 0.
    static func strictSide(_ e: Bounds) -> Int8 { e.lo > 0 ? 1 : e.hi < 0 ? -1 : 0 }

    /// What the kink, pole or domain edge of f is measured by over the argument range `u`, the quantity whose sign
    /// `side(_:_:)` takes at a point: the argument of `abs`, `sqrt`, `ln` and `log`, 1 − |u| for `asin` and `acos`,
    /// cos u for `tan`. nil for the other functions, which have none.
    static func edge(_ f: Function, _ u: (Double, Double)) -> Bounds? {
        switch f {
        case .abs, .sqrt, .ln, .log: return (u.0, u.1)
        case .asin, .acos:
            let m = magnitude(u)
            return (sum(1, -m.1, up: false), sum(1, -m.0, up: true))
        case .tan:
            let c = enclose(.cos, u.0, u.1) ?? (-.infinity, .infinity)
            return (c.0, c.1)
        default: return nil
        }
    }

    /// What the kink, pole or domain edge of `l op r` is measured by over the two ranges, the quantity whose sign
    /// `side(_:_:_:constant:)` takes at a point: the divisor, the base of a power (except for a constant whole
    /// exponent of 0 or more, a polynomial, which has none), and l − r for `min` and `max`. nil for the other
    /// operations.
    static func edge(_ op: Op, _ l: (Double, Double), _ r: (Double, Double), constant: Bool) -> Bounds? {
        switch op {
        case .divide: return (r.0, r.1)
        case .power: return constant && r.0 == r.1 && r.0 >= 0 && r.0.rounded() == r.0 ? nil : (l.0, l.1)
        case .call(.min), .call(.max): return (sum(l.0, -r.1, up: false), sum(l.1, -r.0, up: true))
        default: return nil
        }
    }

    // MARK: outward rounding

    /// Doubles by which a library function's bounds are widened to each side (`libraryHull`): a documented margin over
    /// the last-place error of the C library's `sin`, `cos`, `tan`, `asin`, `acos`, `atan`, `sinh`, `cosh`, `tanh`,
    /// `exp`, `log`, `log10` and `pow`, which are accurate to 1 or 2 ulps on the platforms the engine and the Python
    /// mirror run on (`sqrt` is rounded correctly by IEEE 754 and gets the same margin).
    static let libraryUlps = 4

    /// Below this magnitude, except at 0, the rounding error of a product or quotient may not be a double itself, so
    /// `product` and `quotient` move such a result outward without looking at it.
    static let exactLimit = 0x1p-960

    /// `v` as a bound on an exact result whose difference from `v` has the sign of `error`: `v` itself when the exact
    /// result is on the side asked for or equal, else the next double down (`up` false) or up.
    static func outward(_ v: Double, _ error: Double, up: Bool) -> Double {
        up ? (error > 0 ? v.nextUp : v) : (error < 0 ? v.nextDown : v)
    }

    /// `l + r` rounded down (`up` false) or up: Knuth's TwoSum gives the rounding error of the sum exactly. Not finite
    /// when the sum overflows.
    static func sum(_ l: Double, _ r: Double, up: Bool) -> Double {
        let s = l + r
        guard s.isFinite else { return s }
        let t = s - l
        return outward(s, (l - (s - t)) + (r - t), up: up)
    }

    /// `l × r` rounded down or up: a fused multiply-add gives the rounding error of the product exactly.
    static func product(_ l: Double, _ r: Double, up: Bool) -> Double {
        let p = l * r
        guard p.isFinite else { return p }
        if p == 0 { return outward(p, l == 0 || r == 0 ? 0 : (l < 0) == (r < 0) ? 1 : -1, up: up) }
        if Swift.abs(p) < exactLimit { return outward(p, up ? 1 : -1, up: up) }
        return outward(p, (-p).addingProduct(l, r), up: up)
    }

    /// `l ÷ r` rounded down or up, for r ≠ 0: a fused multiply-add gives the remainder l − q × r exactly, whose sign
    /// (times the sign of r) is that of the rounding error.
    static func quotient(_ l: Double, _ r: Double, up: Bool) -> Double {
        let q = l / r
        guard q.isFinite else { return q }
        if q == 0 { return outward(q, l == 0 ? 0 : (l < 0) == (r < 0) ? 1 : -1, up: up) }
        if Swift.abs(q) < exactLimit || Swift.abs(l) < exactLimit { return outward(q, up ? 1 : -1, up: up) }
        let remainder = l.addingProduct(-q, r)
        return outward(q, r > 0 ? remainder : -remainder, up: up)
    }

    /// uⁿ for a finite u ≥ 0 and a whole n ≥ 1, by repeated squaring with every product rounded down (`up` false) or
    /// up: a bound on the exact power, which is the power itself when every product is exact.
    static func wholePower(_ u: Double, _ n: Double, up: Bool) -> Double {
        var result = 1.0, square = u, k = n
        while true {
            if k.truncatingRemainder(dividingBy: 2) == 1 { result = Swift.max(0, product(result, square, up: up)) }
            k = (k / 2).rounded(.down)
            guard k >= 1, result.isFinite else { return result }
            square = Swift.max(0, product(square, square, up: up))
        }
    }

    /// `v` moved `libraryUlps` doubles down (`up` false) or up; not a number when `v` is not finite.
    static func widened(_ v: Double, up: Bool) -> Double {
        guard v.isFinite else { return .nan }
        var w = v
        for _ in 0..<libraryUlps { w = up ? w.nextUp : w.nextDown }
        return w
    }

    /// The smallest and largest of `values` (a library function's values at the corners of a range where it is
    /// monotone), widened by `libraryUlps` and kept within `range`, which the function's exact values never leave; nil
    /// when one is not finite.
    static func libraryHull(_ values: [Double], within range: (Double, Double) = (-.infinity, .infinity)) -> (Double, Double)? {
        guard let h = hull(values), h.0.isFinite, h.1.isFinite else { return nil }
        return (Swift.max(range.0, widened(h.0, up: false)), Swift.min(range.1, widened(h.1, up: true)))
    }

    /// Smallest and largest of `values`, or nil when one is not a number.
    static func hull(_ values: [Double]) -> (Double, Double)? {
        guard let first = values.first, !values.contains(where: \.isNaN) else { return nil }
        return values.dropFirst().reduce((first, first)) { (Swift.min($0.0, $1), Swift.max($0.1, $1)) }
    }

    /// True when some `at` + k × `period` may lie in [`a`, `b`]. `at` and `period` stand for multiples of the real π,
    /// which `Double.pi` misses by about 1.2 × 10⁻¹⁶, and the subtraction and division round, which moves the test by
    /// less than |a| × 1.1 × 10⁻¹⁶ + 10⁻¹⁵ of a period at either end. It is widened by (|a| + |b| + 4) × 10⁻¹⁵ of a
    /// period, so a point that may be inside counts as inside.
    static func mayHold(_ a: Double, _ b: Double, _ at: Double, period: Double) -> Bool {
        let slack = (Swift.abs(a) + Swift.abs(b) + 4) * 1e-15
        return ((a - at) / period - slack).rounded(.up) <= ((b - at) / period + slack).rounded(.down)
    }

    /// |u| over the range `u`, exactly.
    static func magnitude(_ u: (Double, Double)) -> (Double, Double) {
        u.0 >= 0 ? u : u.1 <= 0 ? (-u.1, -u.0) : (0, Swift.max(-u.0, u.1))
    }

    /// f over [`a`, `b`], rounded outward, or nil where f may not be continuous there.
    static func enclose(_ f: Function, _ a: Double, _ b: Double) -> (Double, Double)? {
        let ends = [apply(f, a), apply(f, b)]
        switch f {
        case .sin, .cos:
            // Largest 1 at π/2 + 2kπ (sin) or 2kπ (cos), smallest −1 half a period on, monotone in between: an
            // interval that may hold one of them takes it as its bound.
            if b - a >= 2 * .pi { return (-1, 1) }
            guard let range = libraryHull(ends, within: (-1, 1)) else { return nil }
            let peak = f == .sin ? Double.pi / 2 : 0
            return (mayHold(a, b, peak + .pi, period: 2 * .pi) ? -1 : range.0,
                    mayHold(a, b, peak, period: 2 * .pi) ? 1 : range.1)
        case .tan:
            guard b - a < .pi, !mayHold(a, b, .pi / 2, period: .pi) else { return nil }
            return libraryHull(ends)
        case .asin: return a >= -1 && b <= 1 ? libraryHull(ends) : nil
        case .acos: return a >= -1 && b <= 1 ? libraryHull(ends, within: (0, .infinity)) : nil
        case .atan, .sinh: return libraryHull(ends)
        case .tanh: return libraryHull(ends, within: (-1, 1))
        case .exp: return libraryHull(ends, within: (0, .infinity))
        case .cosh:
            // Smallest 1 at 0.
            guard a < 0, b > 0 else { return libraryHull(ends, within: (1, .infinity)) }
            return (1, widened(Swift.max(ends[0], ends[1]), up: true))
        case .ln, .log: return a > 0 ? libraryHull(ends) : nil
        case .sqrt: return a >= 0 ? libraryHull(ends, within: (0, .infinity)) : nil
        case .abs: return magnitude((a, b))
        case .min, .max: return nil
        }
    }

    /// `l op r` over the two ranges, rounded outward, or nil where it may not be continuous there.
    static func enclose(_ op: Op, _ l: (Double, Double), _ r: (Double, Double)) -> (Double, Double)? {
        switch op {
        case .add: return (sum(l.0, r.0, up: false), sum(l.1, r.1, up: true))
        case .subtract: return (sum(l.0, -r.1, up: false), sum(l.1, -r.0, up: true))
        case .multiply: return corners(l, r, product(_:_:up:))
        case .divide:
            guard r.0 > 0 || r.1 < 0 else { return nil }
            return corners(l, r, quotient(_:_:up:))
        case .power: return power(l, r)
        case .call(.min): return (Swift.min(l.0, r.0), Swift.min(l.1, r.1))
        case .call(.max): return (Swift.max(l.0, r.0), Swift.max(l.1, r.1))
        default: return nil
        }
    }

    /// The smallest of `f` rounded down and the largest of `f` rounded up at the four corners of two ranges: the range
    /// of a product, or of a quotient whose divisor range does not hold 0.
    static func corners(_ l: (Double, Double), _ r: (Double, Double),
                        _ f: (Double, Double, Bool) -> Double) -> (Double, Double)? {
        let pairs = [(l.0, r.0), (l.0, r.1), (l.1, r.0), (l.1, r.1)]
        guard let low = hull(pairs.map { f($0.0, $0.1, false) }),
              let high = hull(pairs.map { f($0.0, $0.1, true) }) else { return nil }
        return (low.0, high.1)
    }

    /// The base range `l` to the power of the exponent range `r`, rounded outward, or nil outside the domain.
    static func power(_ l: (Double, Double), _ r: (Double, Double)) -> (Double, Double)? {
        let p = { (u: Double, w: Double) in Self.combine(.power, u, w) }
        guard r.0 == r.1 else {
            // A varying exponent: uᵛ = exp(v ln u) is monotone in each of u > 0 and v, so the corners bound it.
            guard l.0 > 0 else { return nil }
            return libraryHull([p(l.0, r.0), p(l.0, r.1), p(l.1, r.0), p(l.1, r.1)], within: (0, .infinity))
        }
        let w = r.0
        if w == 0 { return (1, 1) }
        if w.rounded() == w {
            if w < 0, l.0 <= 0, l.1 >= 0 { return nil }  // a pole at 0
            // l^|w| by repeated squaring of the base's magnitude, with the sign of an odd power.
            let n = Swift.abs(w), odd = n.truncatingRemainder(dividingBy: 2) == 1
            let m: (Double, Double)
            if l.0 >= 0 {
                m = (wholePower(l.0, n, up: false), wholePower(l.1, n, up: true))
            } else if l.1 <= 0 {
                m = odd ? (-wholePower(-l.0, n, up: true), -wholePower(-l.1, n, up: false))
                        : (wholePower(-l.1, n, up: false), wholePower(-l.0, n, up: true))
            } else {
                m = odd ? (-wholePower(-l.0, n, up: true), wholePower(l.1, n, up: true))
                        : (0, Swift.max(wholePower(-l.0, n, up: true), wholePower(l.1, n, up: true)))
            }
            guard m.0.isFinite, m.1.isFinite else { return nil }
            return w > 0 ? m : enclose(.divide, (1, 1), m)
        }
        // A fractional power: defined from 0 up (positive exponent) or above 0 (negative), monotone there.
        guard w > 0 ? l.0 >= 0 : l.0 > 0 else { return nil }
        return libraryHull([p(l.0, w), p(l.1, w)], within: (0, .infinity))
    }
}
