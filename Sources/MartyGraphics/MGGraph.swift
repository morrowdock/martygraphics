// SPDX-License-Identifier: Apache-2.0
import Foundation

/// One sampled function graph (a `func` item): its finite samples in increasing x and where a new piece starts.
struct MGCurve: Equatable {
    var samples: [MGPoint] = []
    /// Indices into `samples` where a new piece starts (never 0): after a gap where the function has no value, or at a
    /// pole between two samples.
    var starts: [Int] = []
    /// A sample, or a crossing found between two samples, lies inside the y range.
    var visible = false
    /// Largest distance at an interval midpoint between the drawn polyline and the function, as a fraction of the frame
    /// height (`MGGraph.curve`; 0 when not measured).
    var deviation = 0.0

    /// The sample index ranges of the pieces, in order.
    var pieces: [Range<Int>] { MGGraph.pieces(samples.count, starts: starts) }

    /// True when one piece runs from x = `a` to x = `b` with no gap and no pole in between.
    func covers(_ a: Double, _ b: Double) -> Bool {
        pieces.contains { r in samples[r.lowerBound].x <= a && samples[r.upperBound - 1].x >= b }
    }
}

/// Sampling, drawing checks and drawing geometry of the `func` and `field` items (docs/PROTOCOL.md, "Function graphs,
/// vector fields and text alternatives"). Pure functions of their inputs, so a parse, a frame and a test agree.
enum MGGraph {
    /// Bisection steps when two neighbouring samples lie outside the y range on opposite sides.
    static let bisections = 8
    /// Stored values are clamped to ±10¹². Ranges are within ±10⁶, so no visible part changes.
    static let magnitude = 1e12

    /// Grid x value `i` of `MGLimits.funcIntervals` equal intervals from `x0` to `x1` (exactly `x1` at the end).
    static func gridX(_ i: Int, _ x0: Double, _ x1: Double) -> Double {
        let n = MGLimits.funcIntervals
        return i == n ? x1 : x0 + (x1 - x0) * Double(i) / Double(n)
    }

    static func clampMagnitude(_ y: Double) -> Double { Swift.max(-magnitude, Swift.min(magnitude, y)) }
    static func clip(_ y: Double, _ lo: Double, _ hi: Double) -> Double { Swift.max(lo, Swift.min(hi, y)) }

    /// Samples `f` at the `MGLimits.funcIntervals + 1` grid values.
    ///
    /// - A grid value where `f` is not finite is a gap. The piece before it ends at x − Δ and the next starts at x + Δ
    ///   (Δ = interval / 1024) when `f` has a value there, so a hole is drawn as narrow as it is (`sin(x)/x` at 0) and a
    ///   curve runs up to an asymptote (`ln(x)` near 0).
    /// - The midpoint of every interval between two finite grid values is evaluated. Where `f` is not finite there
    ///   (`1/x` or `x/x` when 0 falls exactly between two grid values) it is a gap like a grid gap: the piece ends at
    ///   midpoint − Δ and the next starts at midpoint + Δ, so no chord crosses it and no shade can cover it.
    /// - Two neighbouring samples outside the y range on opposite sides are bisected up to `bisections` times: a value
    ///   inside the range means the curve passes through the view (no break); otherwise it is a pole and the piece ends.
    /// - `measure`: also record how far the drawn chord is from the function at every interval midpoint inside one
    ///   piece, in the frame's own units (`width` × `height`, world units) as a fraction of `height`: the
    ///   smaller of the vertical gap (both values clipped to the y range) and the distance from the true point to the
    ///   chord. A steep chord beside a steep curve is close even where their heights differ; intervals wholly above
    ///   or below the range cannot be seen and are skipped.
    ///
    /// At most 257 grid values, 256 midpoints, 2 probes per gap (grid value or midpoint) and `bisections` evaluations
    /// per pair of samples; `measure` reuses the midpoint values. The same rule runs at parse time and in every animated
    /// frame. `stopAfter`: return as soon as there are more piece starts than this.
    static func curve(_ f: @escaping (Double) -> Double, x0: Double, x1: Double, y0: Double, y1: Double,
                      measure: Bool, width: Double = 1, height: Double = 1, stopAfter maxStarts: Int = .max) -> MGCurve {
        let n = MGLimits.funcIntervals
        let probe = (x1 - x0) / Double(n) / 1024
        var c = MGCurve()
        var values = [Double](repeating: .nan, count: n + 1)
        // f at the midpoint of interval i, evaluated only when both of its ends are finite.
        var mids = [Double](repeating: .nan, count: n)
        var piece = [Int](repeating: -1, count: n + 1)
        var open = false
        var last = MGPoint.zero
        func inside(_ y: Double) -> Bool { y >= y0 && y <= y1 }
        func pole(_ a: MGPoint, _ b: MGPoint) -> Bool {
            guard (a.y > y1 && b.y < y0) || (a.y < y0 && b.y > y1) else { return false }
            var lo = a, hi = b
            for _ in 0..<bisections {
                let xm = (lo.x + hi.x) / 2, ym = f(xm)
                guard ym.isFinite else { return true }
                if inside(ym) { c.visible = true; return false }
                if (ym > y1) == (lo.y > y1) { lo = MGPoint(xm, ym) } else { hi = MGPoint(xm, ym) }
            }
            return true
        }
        func add(_ p: MGPoint) {
            if open, pole(last, p) { open = false }
            if !open {
                if !c.samples.isEmpty { c.starts.append(c.samples.count) }
                open = true
            }
            if inside(p.y) { c.visible = true }
            c.samples.append(MGPoint(p.x, clampMagnitude(p.y)))
            last = p
        }
        for i in 0...n {
            let xi = gridX(i, x0, x1), yi = f(xi)
            values[i] = yi
            if yi.isFinite {
                if i > 0, values[i - 1].isFinite {
                    let xm = (gridX(i - 1, x0, x1) + xi) / 2, ym = f(xm)
                    mids[i - 1] = ym
                    if !ym.isFinite {
                        // A gap between two finite samples: split the piece there (pole checks run on each side).
                        let left = f(xm - probe)
                        if left.isFinite { add(MGPoint(xm - probe, left)) }
                        open = false
                        let right = f(xm + probe)
                        if right.isFinite { add(MGPoint(xm + probe, right)) }
                    }
                }
                add(MGPoint(xi, yi))
                piece[i] = c.starts.count
            } else {
                if i > 0, open {
                    let left = f(xi - probe)
                    if left.isFinite { add(MGPoint(xi - probe, left)) }
                }
                open = false
                if i < n {
                    let right = f(xi + probe)
                    if right.isFinite { add(MGPoint(xi + probe, right)) }
                }
            }
            if c.starts.count > maxStarts { return c }
        }
        guard measure else { return c }
        let sx = width / (x1 - x0), sy = height / (y1 - y0)
        for i in 0..<n where piece[i] >= 0 && piece[i] == piece[i + 1] {
            let xa = gridX(i, x0, x1), xb = gridX(i + 1, x0, x1), xm = (xa + xb) / 2, ym = mids[i]
            guard ym.isFinite else { continue }  // never: a non-finite midpoint splits the piece above
            let ya = clampMagnitude(values[i]), yb = clampMagnitude(values[i + 1]), yt = clampMagnitude(ym)
            guard Swift.max(ya, yb, yt) >= y0, Swift.min(ya, yb, yt) <= y1 else { continue }
            let vertical = abs(clip(yt, y0, y1) - clip((ya + yb) / 2, y0, y1)) * sy
            let chord = distance(MGPoint((xm - x0) * sx, (yt - y0) * sy), MGPoint((xa - x0) * sx, (ya - y0) * sy),
                                 MGPoint((xb - x0) * sx, (yb - y0) * sy))
            c.deviation = Swift.max(c.deviation, Swift.min(vertical, chord) / height)
        }
        return c
    }

    /// Distance from `p` to the segment from `a` to `b`.
    static func distance(_ p: MGPoint, _ a: MGPoint, _ b: MGPoint) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y, length2 = dx * dx + dy * dy
        let t = length2 > 0 ? Swift.max(0, Swift.min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / length2)) : 0
        let qx = a.x + t * dx - p.x, qy = a.y + t * dy - p.y
        return (qx * qx + qy * qy).squareRoot()
    }

    /// `f` at the grid values.
    static func gridValues(_ f: (Double) -> Double, x0: Double, x1: Double) -> [Double] {
        (0...MGLimits.funcIntervals).map { f(gridX($0, x0, x1)) }
    }

    /// Sample index ranges for `count` samples split at `starts` (out-of-order or out-of-range starts are ignored, so
    /// an item built in code cannot trap the renderer).
    static func pieces(_ count: Int, starts: [Int]) -> [Range<Int>] {
        var bounds = [0]
        for s in starts.sorted() where s > bounds[bounds.count - 1] && s < count { bounds.append(s) }
        bounds.append(Swift.max(0, count))
        return zip(bounds, bounds.dropFirst()).compactMap { $0 < $1 ? $0..<$1 : nil }
    }

    /// The polyline with each value clamped to `lo`…`hi` and a vertex added wherever a segment crosses `lo` or `hi`:
    /// wherever the original lies between the two levels, the result is exactly the original line.
    static func clamped(_ pts: [MGPoint], lo: Double, hi: Double) -> [MGPoint] {
        guard var previous = pts.first else { return [] }
        func level(_ p: MGPoint) -> MGPoint { MGPoint(p.x, Swift.max(lo, Swift.min(hi, p.y))) }
        var out = [level(previous)]
        for q in pts.dropFirst() {
            var crossings: [Double] = []
            for edge in [lo, hi] where (previous.y - edge) * (q.y - edge) < 0 {
                crossings.append((edge - previous.y) / (q.y - previous.y))
            }
            for t in crossings.sorted() {
                out.append(level(MGPoint(previous.x + (q.x - previous.x) * t, previous.y + (q.y - previous.y) * t)))
            }
            out.append(level(q))
            previous = q
        }
        return out
    }

    /// The polyline's value at `px` (linear between its vertices), or nil outside its x span.
    static func value(on pts: [MGPoint], at px: Double) -> Double? {
        guard let first = pts.first, let last = pts.last, px >= first.x, px <= last.x else { return nil }
        var lo = 0, hi = pts.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if pts[mid].x <= px { lo = mid } else { hi = mid }
        }
        let p = pts[lo], q = pts[hi]
        return q.x > p.x ? p.y + (q.y - p.y) * (px - p.x) / (q.x - p.x) : p.y
    }

    /// The drawn curve's value at `px`: the polyline of the piece that holds `px`, or nil in a gap.
    static func drawnValue(_ samples: [MGPoint], starts: [Int], at px: Double) -> Double? {
        for r in pieces(samples.count, starts: starts) {
            if let v = value(on: Array(samples[r]), at: px) { return v }
        }
        return nil
    }

    /// Closed fill polygons (data coordinates) between the drawn curve and y = 0 (clamped to the y range) from `s0` to
    /// `s1`, one per piece that overlaps the interval; curve values are clamped to the y range.
    static func shadeBands(_ samples: [MGPoint], starts: [Int], _ s0: Double, _ s1: Double, y0: Double, y1: Double) -> [[MGPoint]] {
        let base = clip(0, y0, y1)
        var out: [[MGPoint]] = []
        for r in pieces(samples.count, starts: starts) where r.count >= 2 {
            let pts = Array(samples[r])
            guard let first = pts.first, let last = pts.last else { continue }
            let a = Swift.max(s0, first.x), b = Swift.min(s1, last.x)
            guard a < b, let ya = value(on: pts, at: a), let yb = value(on: pts, at: b) else { continue }
            let top = clamped([MGPoint(a, ya)] + pts.filter { $0.x > a && $0.x < b } + [MGPoint(b, yb)], lo: y0, hi: y1)
            out.append([MGPoint(a, base)] + top + [MGPoint(b, base)])
        }
        return out
    }

    /// The parameter values of an item (`a`, `b`, `c`; 0 when not set) at loop time `t`.
    static func inputs(_ item: MGItem, t: Double = 0) -> MGExpression.Inputs {
        MGExpression.Inputs(t: t, a: item.n("a"), b: item.n("b"), c: item.n("c"))
    }

    // MARK: func

    /// Samples a parsed `func` item at t = 0 and, for a moving graph, also at a quarter, a half and three quarters of
    /// its period, and applies the drawing checks. At each instant, in this order: `func.breaks` (more than
    /// `MGLimits.funcBreaks` breaks), `func.empty` (first instant only: nothing inside the y range), `func.detail` (the
    /// drawn chord is farther than `MGLimits.funcTolerance` of the frame height from the function at some interval
    /// midpoint; see `curve`), `func.shade` (the shaded interval is not inside one
    /// piece) and `func.mark` (the marked point has no value or leaves the y range). Then `func.loop`: at t = period
    /// the graph must match t = 0 (same gaps; values within the tolerance, both clipped to the y range).
    /// Stores the t = 0 samples (`pts` after `at`), the piece starts (`marked`) and the marked value (`num["my"]`).
    static func checkFunction(_ item: inout MGItem, _ expr: MGExpression) throws {
        let x0 = item.n("x0"), x1 = item.n("x1"), y0 = item.n("y0"), y1 = item.n("y1")
        let period = item.num["period"]
        let instants: [Double] = period.map { [0, $0 / 4, $0 / 2, 3 * $0 / 4] } ?? [0]
        let s0 = item.num["s0"], s1 = item.num["s1"]
        let mark = item.num["mark"]
        var first = MGCurve()
        var marked: Double?
        for (k, tau) in instants.enumerated() {
            let base = inputs(item, t: tau)
            let c = curve({ expr.value(base.with(x: $0)) }, x0: x0, x1: x1, y0: y0, y1: y1, measure: true,
                          width: item.n("w"), height: item.n("h"), stopAfter: MGLimits.funcBreaks)
            guard c.starts.count <= MGLimits.funcBreaks else { throw MGError("func.breaks") }
            if k == 0, !c.visible { throw MGError("func.empty") }
            guard c.deviation <= MGLimits.funcTolerance else { throw MGError("func.detail") }
            if let s0, let s1, !c.covers(s0, s1) { throw MGError("func.shade") }
            if let m = mark {
                let v = expr.value(base.with(x: m))
                guard v.isFinite, v >= y0, v <= y1 else { throw MGError("func.mark") }
                if k == 0 { marked = v }
            }
            if k == 0 { first = c }
        }
        if let p = period {
            let start = inputs(item, t: 0), end = inputs(item, t: p)
            let a = gridValues({ expr.value(start.with(x: $0)) }, x0: x0, x1: x1)
            let b = gridValues({ expr.value(end.with(x: $0)) }, x0: x0, x1: x1)
            let tolerance = MGLimits.funcTolerance * (y1 - y0)
            for (u, v) in zip(a, b) {
                guard u.isFinite == v.isFinite else { throw MGError("func.loop") }
                if u.isFinite, abs(clip(u, y0, y1) - clip(v, y0, y1)) > tolerance { throw MGError("func.loop") }
            }
        }
        item.pts = Array(item.pts.prefix(1)) + first.samples
        item.marked = first.starts
        if let marked { item.num["my"] = marked }
    }

    /// A moving `func` item at loop time `tau` (seconds into its period): its samples, pieces and marked value then
    /// (`num["my"]` is removed when the marked point has no value or is outside the y range at `tau`).
    /// An item whose expression does not compile (one built in code, not parsed) is returned unchanged.
    static func animated(_ item: MGItem, at tau: Double) -> MGItem {
        guard let text = item.text,
              let expr = try? MGExpression.compile(text, allowed: Set(MGExpression.Variable.allCases), reason: "func.y") else { return item }
        let x0 = item.n("x0"), x1 = item.n("x1"), y0 = item.n("y0"), y1 = item.n("y1")
        guard [x0, x1, y0, y1].allSatisfy(\.isFinite), x1 > x0, y1 > y0, tau.isFinite else { return item }
        let base = inputs(item, t: tau)
        let c = curve({ expr.value(base.with(x: $0)) }, x0: x0, x1: x1, y0: y0, y1: y1, measure: false)
        var out = item
        out.pts = Array(item.pts.prefix(1)) + c.samples
        out.marked = c.starts
        // The marked value is the one at this instant or none: never the parsed (t = 0) value of another instant.
        out.num["my"] = nil
        if let m = item.num["mark"] {
            let v = expr.value(base.with(x: m))
            if v.isFinite, v >= y0, v <= y1 { out.num["my"] = v }
        }
        return out
    }

    // MARK: field

    /// The vector of each cell of a parsed `field` item (row by row from the bottom left, at cell centres; components
    /// clamped to ±10¹²) and the cells without a finite vector (stored as zero).
    static func fieldVectors(_ item: MGItem, _ dx: MGExpression, _ dy: MGExpression) -> (vectors: [MGPoint], missing: [Int]) {
        let x0 = item.n("x0"), x1 = item.n("x1"), y0 = item.n("y0"), y1 = item.n("y1")
        let rawCols = item.n("cols"), rawRows = item.n("rows")
        guard (1...Double(MGLimits.fieldCols)).contains(rawCols), (1...Double(MGLimits.fieldRows)).contains(rawRows),
              rawCols.rounded() == rawCols, rawRows.rounded() == rawRows else { return ([], []) }
        let cols = Int(rawCols), rows = Int(rawRows)
        let base = inputs(item)
        var vectors: [MGPoint] = [], missing: [Int] = []
        for j in 0..<rows {
            for i in 0..<cols {
                let px = x0 + (x1 - x0) * (Double(i) + 0.5) / Double(cols)
                let py = y0 + (y1 - y0) * (Double(j) + 0.5) / Double(rows)
                let at = base.with(x: px, y: py)
                let u = dx.value(at), v = dy.value(at)
                if u.isFinite, v.isFinite {
                    vectors.append(MGPoint(clampMagnitude(u), clampMagnitude(v)))
                } else {
                    missing.append(vectors.count)
                    vectors.append(.zero)
                }
            }
        }
        return (vectors, missing)
    }
}
