// SPDX-License-Identifier: Apache-2.0
import Foundation

/// Sampling, drawing checks and drawing geometry of the `curve` item (docs/PROTOCOL.md, "Parametric and polar curves"):
/// a parametric curve (x(θ), y(θ)) or a polar curve r(θ), with θ written `theta`. The same rules as a `func` graph
/// (`MGGraph.curve`), carried to the plane: gaps where the curve has no value, breaks where it leaves the window and comes
/// back from elsewhere (a pole), a measured distance between the drawn polyline and the curve, and a seamless loop. Pure
/// functions of their inputs, so a parse, a frame and a test agree; tools/mg_expr.py mirrors them operation for
/// operation.
extension MGGraph {
    /// The drawn data window of a `curve`, with its edges included.
    struct Window: Equatable {
        var x0: Double, x1: Double, y0: Double, y1: Double

        init(x0: Double, x1: Double, y0: Double, y1: Double) { self.x0 = x0; self.x1 = x1; self.y0 = y0; self.y1 = y1 }
        /// The item's drawn window (`x0`…`y1`).
        init(_ item: MGItem) { self.init(x0: item.n("x0"), x1: item.n("x1"), y0: item.n("y0"), y1: item.n("y1")) }

        var isValid: Bool { [x0, x1, y0, y1].allSatisfy(\.isFinite) && x1 > x0 && y1 > y0 }

        func contains(_ p: MGPoint) -> Bool { p.x >= x0 && p.x <= x1 && p.y >= y0 && p.y <= y1 }

        /// The nearest point of the window.
        func clamp(_ p: MGPoint) -> MGPoint { MGPoint(MGGraph.clip(p.x, x0, x1), MGGraph.clip(p.y, y0, y1)) }

        /// The part of the segment from `a` to `b` inside the window, as fractions `lo` ≤ `hi` of the way from `a`, or
        /// nil when the segment misses it (Liang–Barsky; touching an edge or a corner counts as inside) or an end is not
        /// finite (only an item built in code has such a point).
        func segment(_ a: MGPoint, _ b: MGPoint) -> (lo: Double, hi: Double)? {
            guard a.x.isFinite, a.y.isFinite, b.x.isFinite, b.y.isFinite else { return nil }
            let dx = b.x - a.x, dy = b.y - a.y
            var lo = 0.0, hi = 1.0
            // One edge: false when the segment runs parallel to it entirely outside.
            func edge(_ p: Double, _ q: Double) -> Bool {
                if p == 0 { return q >= 0 }
                let r = q / p
                if p < 0 { lo = Swift.max(lo, r) } else { hi = Swift.min(hi, r) }
                return true
            }
            guard edge(-dx, a.x - x0), edge(dx, x1 - a.x), edge(-dy, a.y - y0), edge(dy, y1 - a.y) else { return nil }
            return lo <= hi ? (lo, hi) : nil
        }

        func crosses(_ a: MGPoint, _ b: MGPoint) -> Bool { segment(a, b) != nil }
    }

    /// The drawn window of a `curve` whose given ranges are `xr` and `yr` in a frame `w` × `h` world units: one data unit
    /// is as long across as up, so a circle is drawn round. The range with fewer data units per world unit is widened
    /// about its centre to match the other; neither range is ever narrowed, and both stay as given when they already
    /// match.
    static func curveWindow(_ xr: (Double, Double), _ yr: (Double, Double), w: Double, h: Double) -> Window {
        let kx = (xr.1 - xr.0) / w, ky = (yr.1 - yr.0) / h
        if kx > ky {
            let cy = (yr.0 + yr.1) / 2, half = kx * h / 2
            return Window(x0: xr.0, x1: xr.1, y0: cy - half, y1: cy + half)
        }
        if ky > kx {
            let cx = (xr.0 + xr.1) / 2, half = ky * w / 2
            return Window(x0: cx - half, x1: cx + half, y0: yr.0, y1: yr.1)
        }
        return Window(x0: xr.0, x1: xr.1, y0: yr.0, y1: yr.1)
    }

    /// A finite point scaled toward the origin so that neither coordinate exceeds ±10¹² (its direction is kept). Windows
    /// lie within ±3 × 10⁸, so no visible part changes.
    static func clampPoint(_ p: MGPoint) -> MGPoint {
        let m = Swift.max(abs(p.x), abs(p.y))
        guard m > magnitude else { return p }
        return MGPoint(p.x / m * magnitude, p.y / m * magnitude)
    }

    /// Grid value `i` of `MGLimits.curveIntervals` equal steps from `t0` to `t1` (exactly `t1` at the end).
    static func gridT(_ i: Int, _ t0: Double, _ t1: Double) -> Double {
        let n = MGLimits.curveIntervals
        return i == n ? t1 : t0 + (t1 - t0) * Double(i) / Double(n)
    }

    /// The point of a curve at `inputs` (θ in `inputs.theta`): (x, y) from two expressions, or (r cos θ, r sin θ) from
    /// one. Not finite where the curve has no value.
    static func curvePoint(_ expressions: [MGExpression], _ inputs: MGExpression.Inputs) -> MGPoint {
        if expressions.count == 1 {
            let r = expressions[0].value(inputs), theta = inputs.theta
            guard r.isFinite else { return MGPoint(.nan, .nan) }
            return MGPoint(r * cos(theta), r * sin(theta))
        }
        guard expressions.count == 2 else { return MGPoint(.nan, .nan) }
        return MGPoint(expressions[0].value(inputs), expressions[1].value(inputs))
    }

    static func length(_ dx: Double, _ dy: Double) -> Double { (dx * dx + dy * dy).squareRoot() }

    /// Samples `raw` (a point for each θ) at the `MGLimits.curveIntervals + 1` grid values from `t0` to `t1`, in θ
    /// order. Points are kept within ±10¹² by `clampPoint`; a point is finite when both coordinates are.
    ///
    /// - A grid value where the curve has no point is a gap. The piece before it ends at θ − Δ and the next starts at
    ///   θ + Δ (Δ = step / 1024) when the curve has a point there.
    /// - The midpoint of every step between two finite grid points is evaluated. Where the curve has no point there,
    ///   it is a gap like a grid gap: the piece ends at midpoint − Δ and the next starts at midpoint + Δ.
    /// - Two neighbouring points both outside the window whose chord crosses it are bisected up to `bisections` times:
    ///   a point inside the window means the curve passes through the view (no break). Otherwise the curve goes around
    ///   the view or to infinity (a pole) and the piece ends, so no false chord crosses the view: the half whose chord
    ///   still crosses the window is followed, and when neither half crosses it the curve stays outside there.
    /// - `measure`: also record how far the drawn chord is from the curve at every step midpoint inside one piece, as a
    ///   fraction of the frame's shorter side `side` (`scale`: world units per data unit): the smaller of the distance
    ///   from the true point to the chord and the same distance with all three points clamped into the window. Steps
    ///   whose three points all lie beyond one edge of the window cannot be seen and are skipped.
    ///
    /// At most 257 grid points, 256 midpoints, 2 probes per gap and `bisections` points per pair of samples (7,169
    /// points, as `MGGraph.curve`). The same rule runs at parse time and in every animated frame. `stopAfter`: return as
    /// soon as there are more piece starts than this.
    static func planar(_ raw: @escaping (Double) -> MGPoint, t0: Double, t1: Double, window v: Window, measure: Bool,
                       scale: Double = 1, side: Double = 1, stopAfter maxStarts: Int = .max) -> MGCurve {
        let n = MGLimits.curveIntervals
        let probe = (t1 - t0) / Double(n) / 1024
        func f(_ t: Double) -> MGPoint? {
            let p = raw(t)
            return p.x.isFinite && p.y.isFinite ? clampPoint(p) : nil
        }
        var c = MGCurve()
        var values = [MGPoint?](repeating: nil, count: n + 1)
        var mids = [MGPoint?](repeating: nil, count: n)
        var piece = [Int](repeating: -1, count: n + 1)
        var open = false
        var last = (t: 0.0, p: MGPoint.zero)
        func jump(_ a: (t: Double, p: MGPoint), _ b: (t: Double, p: MGPoint)) -> Bool {
            guard !v.contains(a.p), !v.contains(b.p), v.crosses(a.p, b.p) else { return false }
            var lo = a, hi = b
            for _ in 0..<bisections {
                let tm = (lo.t + hi.t) / 2
                guard let pm = f(tm) else { return true }
                if v.contains(pm) { c.visible = true; return false }
                if v.crosses(lo.p, pm) { hi = (tm, pm) } else if v.crosses(pm, hi.p) { lo = (tm, pm) } else { return true }
            }
            return true
        }
        func add(_ t: Double, _ p: MGPoint) {
            if open, jump(last, (t, p)) { open = false }
            if !open {
                if !c.samples.isEmpty { c.starts.append(c.samples.count) }
                open = true
            }
            if v.contains(p) { c.visible = true }
            c.samples.append(p)
            last = (t, p)
        }
        for i in 0...n {
            let ti = gridT(i, t0, t1), pi = f(ti)
            values[i] = pi
            if let pi {
                if i > 0, values[i - 1] != nil {
                    let tm = (gridT(i - 1, t0, t1) + ti) / 2, pm = f(tm)
                    mids[i - 1] = pm
                    if pm == nil {
                        // A gap between two finite points: split the piece there (jump checks run on each side).
                        if let left = f(tm - probe) { add(tm - probe, left) }
                        open = false
                        if let right = f(tm + probe) { add(tm + probe, right) }
                    }
                }
                add(ti, pi)
                piece[i] = c.starts.count
            } else {
                if i > 0, open, let left = f(ti - probe) { add(ti - probe, left) }
                open = false
                if i < n, let right = f(ti + probe) { add(ti + probe, right) }
            }
            if c.starts.count > maxStarts { return c }
        }
        guard measure else { return c }
        for i in 0..<n where piece[i] >= 0 && piece[i] == piece[i + 1] {
            guard let a = values[i], let b = values[i + 1], let m = mids[i] else { continue }
            guard Swift.max(a.x, b.x, m.x) >= v.x0, Swift.min(a.x, b.x, m.x) <= v.x1,
                  Swift.max(a.y, b.y, m.y) >= v.y0, Swift.min(a.y, b.y, m.y) <= v.y1 else { continue }
            let d = Swift.min(distance(m, a, b), distance(v.clamp(m), v.clamp(a), v.clamp(b)))
            c.deviation = Swift.max(c.deviation, d * scale / side)
        }
        return c
    }

    /// Samples a parsed `curve` item at t = 0 and, for a moving curve, also at a quarter, a half and three quarters of
    /// its period, and applies the drawing checks. At each instant, in this order: `curve.breaks` (more than
    /// `MGLimits.curveBreaks` breaks), `curve.empty` (first instant only: no point inside the window), `curve.detail`
    /// (the drawn chord is farther than `MGLimits.curveTolerance` of the frame's shorter side from the curve at some
    /// step midpoint; see `planar`) and `curve.mark` (the marked point has no value or leaves the window). Then
    /// `curve.loop`: at t = period every grid point must match t = 0 (same gaps; points within the tolerance, both
    /// clamped into the window). Stores the t = 0 samples (`pts` after `at`), the piece starts (`marked`) and the
    /// marked point (`num["mx"]`, `num["my"]`).
    static func checkCurve(_ item: inout MGItem, _ expressions: [MGExpression]) throws {
        let v = Window(item)
        let t0 = item.n("th0"), t1 = item.n("th1"), w = item.n("w"), h = item.n("h")
        let scale = Swift.min(w / (v.x1 - v.x0), h / (v.y1 - v.y0)), side = Swift.min(w, h)
        let period = item.num["period"]
        let instants: [Double] = period.map { [0, $0 / 4, $0 / 2, 3 * $0 / 4] } ?? [0]
        let mark = item.num["mark"]
        var first = MGCurve()
        var marked: MGPoint?
        for (k, tau) in instants.enumerated() {
            let base = inputs(item, t: tau)
            let c = planar({ curvePoint(expressions, base.with(theta: $0)) }, t0: t0, t1: t1, window: v, measure: true,
                           scale: scale, side: side, stopAfter: MGLimits.curveBreaks)
            guard c.starts.count <= MGLimits.curveBreaks else { throw MGError("curve.breaks") }
            if k == 0, !c.visible { throw MGError("curve.empty") }
            guard c.deviation <= MGLimits.curveTolerance else { throw MGError("curve.detail") }
            if let m = mark {
                let p = curvePoint(expressions, base.with(theta: m))
                guard p.x.isFinite, p.y.isFinite, v.contains(p) else { throw MGError("curve.mark") }
                if k == 0 { marked = p }
            }
            if k == 0 { first = c }
        }
        if let p = period {
            let start = inputs(item, t: 0), end = inputs(item, t: p)
            let tolerance = MGLimits.curveTolerance * Swift.min(v.x1 - v.x0, v.y1 - v.y0)
            for i in 0...MGLimits.curveIntervals {
                let theta = gridT(i, t0, t1)
                let u = curvePoint(expressions, start.with(theta: theta)), q = curvePoint(expressions, end.with(theta: theta))
                let finite = u.x.isFinite && u.y.isFinite
                guard finite == (q.x.isFinite && q.y.isFinite) else { throw MGError("curve.loop") }
                guard finite else { continue }
                let a = v.clamp(clampPoint(u)), b = v.clamp(clampPoint(q))
                if length(a.x - b.x, a.y - b.y) > tolerance { throw MGError("curve.loop") }
            }
        }
        item.pts = Array(item.pts.prefix(1)) + first.samples
        item.marked = first.starts
        if let marked { item.num["mx"] = marked.x; item.num["my"] = marked.y }
    }

    /// The expressions of a parsed `curve` item: [r] (polar) or [x, y]; nil when they do not compile (an item built in
    /// code, not parsed).
    static func curveExpressions(_ item: MGItem) -> [MGExpression]? {
        let all = Set(MGExpression.Variable.allCases)
        let texts = item.has("polar") ? (item.list.count == 3 ? [item.list[2]] : []) : (item.list.count == 4 ? [item.list[2], item.list[3]] : [])
        guard !texts.isEmpty else { return nil }
        return try? texts.map { try MGExpression.compile($0, allowed: all, reason: "curve") }
    }

    /// A moving `curve` item at loop time `tau` (seconds into its period): its samples, pieces and marked point then (the
    /// marked point is removed when it has no value or is outside the window at `tau`). An item whose expressions do not
    /// compile or whose window or `theta` range is not valid (one built in code, not parsed) is returned unchanged.
    static func animatedCurve(_ item: MGItem, at tau: Double) -> MGItem {
        guard let expressions = curveExpressions(item) else { return item }
        let v = Window(item), t0 = item.n("th0"), t1 = item.n("th1")
        guard v.isValid, t0.isFinite, t1.isFinite, t1 > t0, tau.isFinite else { return item }
        let base = inputs(item, t: tau)
        let c = planar({ curvePoint(expressions, base.with(theta: $0)) }, t0: t0, t1: t1, window: v, measure: false)
        var out = item
        out.pts = Array(item.pts.prefix(1)) + c.samples
        out.marked = c.starts
        // The marked point is the one at this instant or none: never the parsed (t = 0) point of another instant.
        out.num["mx"] = nil; out.num["my"] = nil
        if let m = item.num["mark"] {
            let p = curvePoint(expressions, base.with(theta: m))
            if p.x.isFinite, p.y.isFinite, v.contains(p) { out.num["mx"] = p.x; out.num["my"] = p.y }
        }
        return out
    }

    /// The visible runs of a polyline inside `window`: each segment cut to the window, consecutive cut segments joined.
    /// Wherever the polyline lies inside the window the runs are exactly the polyline, and no point of a run is outside
    /// it, so a renderer never draws a huge coordinate.
    static func clipped(_ pts: [MGPoint], to window: Window) -> [[MGPoint]] {
        var runs: [[MGPoint]] = [], current: [MGPoint] = []
        func close() { if current.count >= 2 { runs.append(current) }; current = [] }
        for (a, b) in zip(pts, pts.dropFirst()) {
            guard let s = window.segment(a, b), s.lo < s.hi else { close(); continue }
            if current.isEmpty || s.lo > 0 { close(); current = [s.lo > 0 ? a.lerp(b, s.lo) : a] }
            current.append(s.hi < 1 ? a.lerp(b, s.hi) : b)
            if s.hi < 1 { close() }
        }
        close()
        return runs
    }

    /// True when a curve's drawn samples form one closed piece: one piece whose first and last samples coincide to
    /// within `MGLimits.curveTolerance` of the window's shorter side (a circle, a cardioid, a full rose).
    static func isClosed(_ item: MGItem) -> Bool {
        let samples = Array(item.pts.dropFirst()), v = Window(item)
        guard v.isValid, samples.count >= 3, pieces(samples.count, starts: item.marked).count == 1,
              let first = samples.first, let last = samples.last else { return false }
        return length(first.x - last.x, first.y - last.y) <= MGLimits.curveTolerance * Swift.min(v.x1 - v.x0, v.y1 - v.y0)
    }
}
