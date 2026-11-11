// SPDX-License-Identifier: Apache-2.0
import Foundation

// Exact motion facts for annotations, and the one check of what a view may show. No sampling: every pose rule is
// decided by the structure of the motion (a centre-of-mass anchor too: `movingCentre`). Direction-bearing annotations (motion arrows, turn arrows, `expect`, and
// any dimension in a moving view) need a linear motion chain: every moving joint above the point is linear in the
// input with a constant rate (input drives, constant-ratio follows, gear meshes, planetary carriers). Crank closed
// forms are used only for exact `over` ranges. Foundation only, deterministic.

enum MGSolidAnnotationMotion {
    /// Parts whose own joint moves, from `part` up its parent chain (nearest first); empty for a world point.
    static func movers(_ doc: MGSolidDocument, _ part: String?) -> [String] {
        var out: [String] = []
        var cur = part, seen = Set<String>()
        while let c = cur, seen.insert(c).inserted {
            if doc.ownMotion(c) { out.append(c) }
            cur = doc.assembly.part(c)?.parent
        }
        return out
    }

    static func isRevolute(_ doc: MGSolidDocument, _ id: String) -> Bool {
        if case .revolute? = doc.assembly.part(id)?.joint { return true }
        return false
    }

    /// `q = offset + rate × input` for a joint whose drive chain is linear (input, follow, gear mesh); nil for a crank
    /// closed form or a cycle.
    static func linear(_ doc: MGSolidDocument, _ id: String, _ seen: Set<String> = []) -> (rate: Double, offset: Double)? {
        guard !seen.contains(id) else { return nil }
        let next = seen.union([id])
        switch doc.assembly.part(id)?.drive {
        case nil: return (0, 0)
        case .input(let s, let o)?: return (s, o)
        case .follow(let src, let k, let o)?:
            guard let a = linear(doc, src, next) else { return nil }
            return (k * a.rate, o + k * a.offset)
        case .gear(let d, let k, let c, let o)?:
            guard let a = linear(doc, d, next) else { return nil }
            let b = c.map { linear(doc, $0, next) } ?? (0, 0)
            guard let cb = b else { return nil }
            return (k * (a.rate - cb.rate), o + k * (a.offset - cb.offset))
        case .crankSlider?, .crankRod?: return nil
        }
    }

    /// True when every moving joint above the point (its own joint included) is linear in the input with a constant
    /// rate, so the motion never reverses or changes speed.
    static func linearChain(_ doc: MGSolidDocument, _ part: String?) -> Bool {
        movers(doc, part).allSatisfy { linear(doc, $0) != nil }
    }

    /// The slider displacement of a crank-slider and its derivative by the crank angle.
    static func slider(_ t: Double, _ r: Double, _ l: Double) -> (x: Double, dx: Double) {
        let s = sin(t), c = cos(t)
        let root = max(1e-300, l * l - r * r * s * s).squareRoot()
        return (r * c + root, -r * s - r * r * s * c / root)
    }

    /// dq/d(input) of a joint at the pose's joint values, from the drive closed forms.
    static func rate(_ doc: MGSolidDocument, _ id: String, _ q: [String: Double], _ seen: Set<String> = []) -> Double {
        guard !seen.contains(id) else { return 0 }
        let next = seen.union([id])
        switch doc.assembly.part(id)?.drive {
        case nil: return 0
        case .input(let s, _)?: return s
        case .follow(let src, let k, _)?: return k * rate(doc, src, q, next)
        case .gear(let d, let k, let c, _)?: return k * (rate(doc, d, q, next) - (c.map { rate(doc, $0, q, next) } ?? 0))
        case .crankSlider(let c, let r, let l, _)?:
            return slider(q[c] ?? 0, r, l).dx * rate(doc, c, q, next)
        case .crankRod(let c, let r, let l)?:
            let t = q[c] ?? 0
            let (x, dx) = slider(t, r, l)
            let X = r * cos(t) - x, Y = r * sin(t), Xp = -r * sin(t) - dx, Yp = r * cos(t)
            let d = X * X + Y * Y
            return d > 0 ? (X * Yp - Y * Xp) / d * rate(doc, c, q, next) : 0
        }
    }

    /// The exact velocity of a point (mm per input radian, kernel world) at a pose: the sum over its moving joints.
    static func velocity(_ doc: MGSolidDocument, _ p: MGAnnotationPoint, _ pose: MGPose) -> MGVec3 {
        let x = p.world(pose)
        var v = MGVec3.zero
        for id in movers(doc, p.part) {
            guard let part = doc.assembly.part(id) else { continue }
            let w = pose.world[id] ?? .identity
            let qd = rate(doc, id, pose.values)
            switch part.joint {
            case .revolute(let axis): v += w.applyVector(axis).normalized.cross(x - w.translation) * qd
            case .prismatic(let axis): v += w.applyVector(axis).normalized * qd
            case .fixed: break
            }
        }
        return v
    }

    /// The motion direction a view shows at a pose (`sense` −1 plays the input backwards); nil when the point does not
    /// move.
    static func direction(_ doc: MGSolidDocument, _ p: MGAnnotationPoint, _ pose: MGPose, sense: Double = 1) -> MGVec3? {
        let v = velocity(doc, p, pose) * (sense < 0 ? -1 : 1)
        guard v.length > 1e-9 * max(1, doc.annotations.diagonal), v.x.isFinite, v.y.isFinite, v.z.isFinite else { return nil }
        return v.normalized
    }

    /// True when every moving joint of the point's chain is a revolute whose axis passes through the point: the point
    /// stays where it is during any motion (a point on a turning shaft's axis).
    static func worldFixed(_ doc: MGSolidDocument, _ p: MGAnnotationPoint, _ pose: MGPose) -> Bool {
        let x = p.world(pose)
        let tol = 1e-9 * max(1, doc.annotations.diagonal)
        for id in movers(doc, p.part) {
            guard case .revolute(let axis)? = doc.assembly.part(id)?.joint else { return false }
            let w = pose.world[id] ?? .identity
            let a = w.applyVector(axis).normalized, d = x - w.translation
            if (d - a * a.dot(d)).length > tol { return false }
        }
        return true
    }

    /// A conservative bound on how far a centre-of-mass anchor can move during a step's motion (docs/SOLID-3D.md,
    /// "Poses: every claim holds at every pose its view can show"). Exact arithmetic on the structure, no sampling.
    ///
    /// For each part with a share of the mass (`MGAnnotationPoint.mass`) and a moving joint in its chain (`movers`,
    /// nearest first), its centroid's displacement over any motion is bounded by `D`, built joint by joint from the
    /// part upward (the product-of-exponentials form: each joint turns about its axis as it lies at `pose`, the view's
    /// first pose, applied from the leaf up): a revolute joint adds `2 × (d + D)`, with `d` the centroid's distance from
    /// that axis at `pose` and `D` the bound so far (the joints below may already have carried it that far off); a
    /// prismatic joint adds its travel over the step (`travel`). The centre's bound is the share-weighted sum of the
    /// parts' bounds (the centre is their share-weighted mean). Returns that bound, the part that adds the most to it
    /// and, in that part's chain, the joint that adds the most, with the centroid's distance from that joint's axis
    /// (nil for a prismatic joint). A bound of 0 means the centre cannot move.
    static func centreBound(_ doc: MGSolidDocument, _ p: MGAnnotationPoint, _ pose: MGPose, spin: Double)
        -> (bound: Double, part: String?, joint: String?, distance: Double?, top: Double) {
        guard p.isCentreOfMass else { return (0, nil, nil, nil, 0) }
        var total = 0.0
        var worst: (share: Double, part: String, joint: String, distance: Double?)?
        for m in p.mass where m.share > 0 {
            let x = (pose.world[m.part] ?? .identity).apply(m.centroid)
            let b = pointBound(doc, x, on: m.part, pose, spin: spin)
            total += m.share * b.bound
            if let j = b.joint, worst.map({ m.share * b.bound > $0.share }) ?? (b.bound > 0) { worst = (m.share * b.bound, m.part, j, b.distance) }
        }
        return (total.isNaN ? .infinity : total, worst?.part, worst?.joint, worst?.distance, worst?.share ?? 0)
    }

    /// The same recurrence for one point `x` (posed world, at `pose`) that rides on `part`: from the part upward, a
    /// revolute joint adds `2 × (d + E)` (`d` the point's distance from its axis at `pose`, `E` the bound so far), a
    /// prismatic joint its travel (`travel`). 0 when no joint in the chain moves. Returns the bound and the joint that
    /// adds the most, with the point's distance from its axis (nil for a prismatic joint).
    static func pointBound(_ doc: MGSolidDocument, _ x: MGVec3, on part: String, _ pose: MGPose, spin: Double)
        -> (bound: Double, joint: String?, distance: Double?) {
        var bound = 0.0
        var top: (term: Double, joint: String, distance: Double?)?
        for id in movers(doc, part) {
            let term: Double, distance: Double?
            switch doc.assembly.part(id)?.joint {
            case .revolute(let axis)?:
                let w = pose.world[id] ?? .identity
                let a = w.applyVector(axis).normalized, d = x - w.translation
                let off = (d - a * a.dot(d)).length
                term = 2 * (off + bound); distance = off
            case .prismatic?: term = travel(doc, id, spin: spin); distance = nil
            default: term = .infinity; distance = nil
            }
            bound += term.isNaN ? .infinity : term
            if top.map({ term > $0.term }) ?? (term > 0) { top = (term, id, distance) }
        }
        return (bound.isNaN ? .infinity : bound, top?.joint, top?.distance)
    }

    /// The most a prismatic joint's displacement can change during `spin` input turns: `|rate| × |spin| × 2π` for a
    /// linear drive, `2r` (the crank's diameter) for a crank-slider, infinity otherwise.
    static func travel(_ doc: MGSolidDocument, _ id: String, spin: Double) -> Double {
        if let l = linear(doc, id) { return abs(l.rate) * abs(spin) * 2 * .pi }
        if case .crankSlider(_, let r, _, _)? = doc.assembly.part(id)?.drive { return 2 * abs(r) }
        return .infinity
    }

    /// True when the points keep their relative placement during any motion: all world-fixed, or all on the same
    /// moving chain (the same moving joints), and with `translationOnly`, no moving joint turns.
    static func rigid(_ doc: MGSolidDocument, _ points: [MGAnnotationPoint], _ pose: MGPose, translationOnly: Bool) -> Bool {
        if points.allSatisfy({ worldFixed(doc, $0, pose) }) { return true }
        return sameMotion(doc, points, translationOnly: translationOnly)
    }

    /// True when the points ride the same moving joints (the same ordered `movers` list) and, with `translationOnly`,
    /// none of them turns. Then their relative placement is exactly constant during any motion, with no tolerance:
    /// the two paths to the world are disjoint below their lowest common part, so equal lists of moving joints mean
    /// that no joint below it moves; both points take one rigid motion of that part (distances and angles keep), and
    /// without a turning joint that motion is a translation (world components keep too).
    static func sameMotion(_ doc: MGSolidDocument, _ points: [MGAnnotationPoint], translationOnly: Bool) -> Bool {
        let sets = points.map { movers(doc, $0.part) }
        guard let first = sets.first, sets.allSatisfy({ $0 == first }) else { return false }
        return !translationOnly || !first.contains { isRevolute(doc, $0) }
    }

    /// The most a dimension anchor can move during a step's motion (`pointBound` on its posed point; `spin` the step's
    /// turns): 0 for a world anchor (a dimension has no centre-of-mass anchor). With the joint that adds the most and the
    /// point's distance from its axis (nil for a sliding joint).
    static func anchorBound(_ doc: MGSolidDocument, _ p: MGAnnotationPoint, _ pose: MGPose, spin: Double)
        -> (bound: Double, joint: String?, distance: Double?) {
        guard let part = p.part else { return (0, nil, nil) }
        return pointBound(doc, p.world(pose), on: part, pose, spin: spin)
    }

    /// The most a dimension's value can change at `pose` while its anchors move by at most `ea`, `eb` and `ev` (the
    /// vertex). A distance, also `along` an axis: `ea + eb` (the triangle inequality: `| |x| − |y| | ≤ |x − y|`, and one
    /// world component changes by at most the length of the change). An angle: each arm (vertex to end, length `L`)
    /// turns by at most `asin((e_end + ev) / L)` when that sum is below `L` and `L` minus the sum is at least 0.01 mm (the
    /// arm stays measurable), else 180°; the angle changes by at most the sum over its two arms (degrees). Not finite
    /// when a bound is not.
    static func valueBound(_ d: MGSolidDimension, _ pose: MGPose, ea: Double, eb: Double, ev: Double) -> Double {
        guard d.kind == .angle, let v = d.vertex else { let s = ea + eb; return s.isNaN ? .infinity : s }
        func arm(_ end: MGAnnotationPoint, _ e: Double) -> Double {
            let delta = e + ev, len = (end.world(pose) - v.world(pose)).length
            if delta == 0 { return 0 }
            // The arm must also stay long enough to measure (`dimensionValue`: 0.01 mm) at every pose.
            guard delta < len, len - delta >= MGSolidAnnotationLimits.minDimension else { return 180 }
            return asin(delta / len) * 180 / .pi
        }
        return min(180, arm(d.a, ea) + arm(d.b, eb))
    }

    /// The range of a dimension with `over` over one input turn (`0...2π`) at an explode value, and how far off it can
    /// be. Exactly one anchor may move, by one prismatic joint (a linear drive or a crank-slider) and nothing else; its
    /// motion is exact, from the joint's closed form. The other anchor is world-fixed (`worldFixed`): a world point,
    /// or a point whose moving joints are all revolutes with their axes within the epsilon of it. Such a point can still
    /// move by its `anchorBound` `E` (offsets add up along a chain), so every value over the turn is within `E` of the
    /// value computed with it held still, and the range (largest minus smallest) within `2E`: `bound` is `2E`, `other`
    /// the anchor that can move, with its joint and distance. Distances along an axis and straight distances only.
    /// Otherwise `dimension.over.motion.<id>`.
    static func range(_ d: MGSolidDimension, _ doc: MGSolidDocument, explode: Double,
                      placements: [String: MGTransform] = [:]) throws -> Double {
        try rangeBound(d, doc, explode: explode, placements: placements).value
    }

    static func rangeBound(_ d: MGSolidDimension, _ doc: MGSolidDocument, explode: Double, placements: [String: MGTransform] = [:]) throws
        -> (value: Double, bound: Double, other: MGAnnotationPoint, pose: MGPose, joint: String?, distance: Double?) {
        let fail = MGSolidIssue("dimension.over.motion.\(d.id)", part: d.id)
        guard d.kind == .distance else { throw fail }
        let pose = doc.assembly.pose(MGPoseParameters(input: 0, explode: explode, placements: placements))
        let points = [d.a, d.b]
        let moving = points.filter { !worldFixed(doc, $0, pose) }
        guard moving.count == 1, let p = moving.first, let other = points.first(where: { $0 != p }) else { throw fail }
        let m = movers(doc, p.part)
        guard m.count == 1, let part = doc.assembly.part(m[0]), case .prismatic(let axis) = part.joint else { throw fail }
        // The joint's displacement range over the turn, from its closed form.
        let q0 = pose.values[m[0]] ?? 0
        var qs: [Double]
        if let l = linear(doc, m[0]) {
            qs = [l.offset, l.offset + 2 * .pi * l.rate]
        } else if case .crankSlider(let c, let r, let rod, let off)? = part.drive, let lc = linear(doc, c) {
            let t0 = lc.offset, t1 = lc.offset + 2 * .pi * lc.rate
            var ts = [t0, t1]
            let lo = min(t0, t1), hi = max(t0, t1)
            var k = (lo / .pi).rounded(.up)
            while k * .pi < hi, ts.count < 4_000 { ts.append(k * .pi); k += 1 }
            qs = ts.map { slider($0, r, rod).x - off }
        } else { throw fail }
        let qlo = qs.min()! - q0, qhi = qs.max()! - q0
        let a = pose.world[m[0]].map { $0.applyVector(axis).normalized } ?? axis.normalized
        let w = p.world(pose) - other.world(pose)
        // The other anchor's motion: its moving joints are revolutes, so the bound does not depend on the turns.
        let ob = anchorBound(doc, other, pose, spin: 1)
        let bound = (2 * ob.bound).isNaN ? Double.infinity : 2 * ob.bound
        if let k = d.along {
            let alpha = [w.x, w.y, w.z][k], beta = [a.x, a.y, a.z][k]
            let e0 = alpha + beta * qlo, e1 = alpha + beta * qhi
            let hiV = max(abs(e0), abs(e1)), loV = e0 * e1 <= 0 ? 0 : min(abs(e0), abs(e1))
            return (hiV - loV, bound, other, pose, ob.joint, ob.distance)
        }
        func dist(_ s: Double) -> Double { (w + a * s).length }
        let star = min(max(-w.dot(a), qlo), qhi)
        return (max(dist(qlo), dist(qhi)) - dist(star), bound, other, pose, ob.joint, ob.distance)
    }
}

// MARK: The view rules

extension MGSolidAnnotationEngine {
    /// What a view can show: a step plays its `spin` from the default input at its explode value; the plain view shows
    /// the default pose.
    static func domain(_ doc: MGSolidDocument, step: Int?) -> (input: Double, spin: Double, explode: Double) {
        guard let i = step, doc.steps.indices.contains(i) else { return (doc.defaults.input, 0, doc.defaults.explode) }
        let s = doc.steps[i]
        return (doc.defaults.input, s.spin, s.explode ?? doc.defaults.explode)
    }

    /// The placements a view shows: the step's `pose` (empty for the plain view and a step without one).
    static func placements(_ doc: MGSolidDocument, step: Int?) -> [String: MGTransform] {
        guard let i = step, doc.steps.indices.contains(i) else { return [:] }
        return doc.steps[i].pose
    }

    /// A dimension's value holds over a view: with `over`, its range at the view's explode value equals the fact; without,
    /// it is constant during the view (no motion, or rigid anchors) and equals the fact at the view's pose
    /// (`dimensionCheck`).
    static func dimensionHolds(_ d: MGSolidDimension, _ doc: MGSolidDocument, step: Int?) -> Bool {
        dimensionCheck(d, doc, step: step).holds
    }

    /// `dimensionHolds` with the detail of a refusal that the motion bound decides (nil for every other cause), with the
    /// dimension tolerance `tol` = 1e-9 × max(1, |value|, model diagonal):
    /// - with `over`: the range `R` at the view's explode value (`rangeBound`) and its bound `B` (`2E` of the anchor that
    ///   is held still) must give `|R − value| + B ≤ tol`;
    /// - without, in a step with `spin`: the anchors' chains are linear and the anchors are rigid (`rigid`: all
    ///   world-fixed, or the same moving joints). The same moving joints keep the value exactly (`sameMotion`). Anchors
    ///   that are only world-fixed get the motion bound: each anchor's `anchorBound` (`E1`, `E2`, the vertex's `Ev`), and
    ///   from them the most the value can change, `C` (`valueBound`: `E1 + E2` for a distance);
    /// - the value `v` at the view's first pose must give `|v − value| + C ≤ tol` (`C` is 0 for a still view or exact
    ///   rigid anchors).
    static func dimensionCheck(_ d: MGSolidDimension, _ doc: MGSolidDocument, step: Int?) -> (holds: Bool, motion: MGDimensionMotion?) {
        let (u0, spin, e) = domain(doc, step: step)
        let placed = placements(doc, step: step)
        let tol = 1e-9 * max(1, abs(d.value), doc.annotations.diagonal)
        if d.over {
            guard let r = try? MGSolidAnnotationMotion.rangeBound(d, doc, explode: e, placements: placed) else { return (false, nil) }
            let off = abs(r.value - d.value)
            if off + r.bound <= tol { return (true, nil) }
            guard r.bound > 0, off <= tol else { return (false, nil) }
            return (false, MGDimensionMotion.over(d, doc, step: step, r, tolerance: tol))
        }
        let pose = doc.assembly.pose(MGPoseParameters(input: u0, explode: e, placements: placed))
        let pts = [d.a, d.b, d.vertex].compactMap { $0 }
        var change = 0.0
        var ends: [(name: String, point: MGAnnotationPoint, bound: Double, joint: String?, distance: Double?)] = []
        if spin != 0 {
            guard pts.allSatisfy({ MGSolidAnnotationMotion.linearChain(doc, $0.part) }),
                  MGSolidAnnotationMotion.rigid(doc, pts, pose, translationOnly: d.along != nil) else { return (false, nil) }
            if !MGSolidAnnotationMotion.sameMotion(doc, pts, translationOnly: d.along != nil) {
                for (name, p) in [("a", d.a), ("b", d.b)] + (d.vertex.map { [("vertex", $0)] } ?? []) {
                    let b = MGSolidAnnotationMotion.anchorBound(doc, p, pose, spin: spin)
                    ends.append((name, p, b.bound, b.joint, b.distance))
                }
                func e(_ n: String) -> Double { ends.first { $0.name == n }?.bound ?? 0 }
                change = MGSolidAnnotationMotion.valueBound(d, pose, ea: e("a"), eb: e("b"), ev: e("vertex"))
            }
        }
        guard let v = dimensionValue(d, pose) else { return (false, nil) }
        let off = abs(v - d.value)
        if off + change <= tol { return (true, nil) }
        guard change > 0, off <= tol, let i = step else { return (false, nil) }
        return (false, MGDimensionMotion(d, doc, step: i, ends: ends, change: change, offset: off, tolerance: tol, pose: pose))
    }

    /// The first of `ds` that does not hold over the view, with its motion detail (`dimensionCheck`); nil when all hold.
    static func firstBroken(_ ds: [MGSolidDimension], _ doc: MGSolidDocument, step: Int?) -> (dimension: MGSolidDimension, motion: MGDimensionMotion?)? {
        for d in ds {
            let c = dimensionCheck(d, doc, step: step)
            if !c.holds { return (d, c.motion) }
        }
        return nil
    }

    /// Every displayed annotation claim holds at every pose its view can show, decided exactly (no sampling):
    /// - a shown dimension, and every `dim.<id>` fact that shown text (a label, an arrow or dimension text, the step's
    ///   caption, the title) displays, holds over the view (`dimensionHolds`);
    /// - a gravity force arrow does not turn during the view and points within 10° of −Z at the view's pose;
    /// - a motion line arrow does not ride a turning joint during a moving view (its linear chain then gives one
    ///   constant velocity); a stated `expect` holds at the view's pose;
    /// - a dimension shown in a moving view has linear chains above its anchors (`annotation.motion.nonlinear.<id>`);
    /// - a turn arrow's stated `sense` matches the way the view plays.
    /// Failures: `annotation.pose.<id>`, `text.pose.step.<n>` (a caption), `text.pose.title`.
    static func checkViews(_ doc: MGSolidDocument) throws {
        let a = doc.annotations
        guard !a.isEmpty else { return }
        func dims(_ facts: [String]) -> [MGSolidDimension] { a.dimensions.filter { facts.contains($0.factName) } }
        for step in [nil] + doc.steps.indices.map({ Optional($0) }) {
            let (u0, spin, e) = domain(doc, step: step)
            let sense: Double = spin < 0 ? -1 : 1
            // A posed step is checked at its pose (`MGSolidStep.pose`): gravity arrows, `expect` and dimensions.
            let pose = doc.assembly.pose(MGPoseParameters(input: u0, explode: e, placements: placements(doc, step: step)))
            let shown = doc.visibleAnnotations(step: step)
            func fail(_ id: String) -> MGSolidIssue { MGSolidIssue("annotation.pose.\(id)", part: id) }
            // A dimension refused by the motion bound adds its detail (`MGSolidIssue.dimensionMotion`).
            func broken(_ issue: MGSolidIssue, _ ds: [MGSolidDimension]) -> MGSolidIssue? {
                guard let b = firstBroken(ds, doc, step: step) else { return nil }
                var out = issue
                out.dimensionMotion = b.motion
                return out
            }
            for id in a.ids where shown.contains(id) {
                if let l = a.label(id), let issue = broken(fail(id), dims(l.facts)) { throw issue }
                if let d = a.dimension(id) {
                    if spin != 0, ![d.a, d.b, d.vertex].compactMap({ $0 }).allSatisfy({ MGSolidAnnotationMotion.linearChain(doc, $0.part) }) {
                        throw MGSolidIssue("annotation.motion.nonlinear.\(id)", part: id)
                    }
                    if let issue = broken(fail(id), [d] + dims(d.facts)) { throw issue }
                }
                guard let r = a.arrow(id) else { continue }
                if let issue = broken(fail(id), dims(r.facts)) { throw issue }
                switch (r.meaning, r.style) {
                case (.motion, .turn):
                    if let stated = r.sense, ((r.turnSign ?? 1) * sense > 0) != (stated == "ccw") { throw fail(id) }
                case (.motion, .line):
                    // The chain is linear (checked when the document compiled): a moving step may not turn the anchor,
                    // so its velocity is constant; a still step shows one pose.
                    guard let from = r.from else { continue }
                    let m = MGSolidAnnotationMotion.movers(doc, from.part)
                    if spin != 0, m.contains(where: { MGSolidAnnotationMotion.isRevolute(doc, $0) }) { throw fail(id) }
                    guard let expect = r.expect else { continue }
                    guard let dir = MGSolidAnnotationMotion.direction(doc, from, pose, sense: sense), angle(expect, dir) <= L.expectDegrees else { throw fail(id) }
                case (.force, _) where r.cause == "gravity":
                    guard let from = r.from, let to = r.to else { continue }
                    // Both ends are bounded with the same recurrence: `D` for a centre-of-mass end (`centreBound`), `E` for a
                    // part-mounted end (`pointBound` on its anchor point); a world end does not move. The sum must be at
                    // most the world-fixed epsilon, and the angle from down plus the most `D + E` can turn the arrow must
                    // stay within the gravity limit. Two ends that translate together on one chain keep the vector
                    // exactly (`rigid`) and need no bound. A moving centre is never a Solved direction.
                    if spin != 0, let i = step {
                        let ends = [from, to]
                        let sameTranslation = !ends.contains { $0.isCentreOfMass } && ends.allSatisfy { $0.part != nil }
                            && MGSolidAnnotationMotion.movers(doc, from.part) == MGSolidAnnotationMotion.movers(doc, to.part)
                            && !MGSolidAnnotationMotion.movers(doc, from.part).contains { MGSolidAnnotationMotion.isRevolute(doc, $0) }
                        if !sameTranslation {
                            let c = ends.first(where: { $0.isCentreOfMass }).map { MGSolidAnnotationMotion.centreBound(doc, $0, pose, spin: spin) }
                            var e = 0.0
                            var endTop: (bound: Double, part: String, joint: String, distance: Double?)?
                            for end in ends where !end.isCentreOfMass {
                                guard let part = end.part else { continue }
                                let b = MGSolidAnnotationMotion.pointBound(doc, end.world(pose), on: part, pose, spin: spin)
                                e += b.bound
                                if let j = b.joint, endTop.map({ b.bound > $0.bound }) ?? (b.bound > 0) { endTop = (b.bound, part, j, b.distance) }
                            }
                            let d = c?.bound ?? 0
                            if d + e > 0 {
                                let dv = to.world(pose) - from.world(pose)
                                let both = from.isCentreOfMass && to.isCentreOfMass
                                let len = dv.length
                                let extra = both ? 0 : (len > 0 ? asin(min(1, (d + e) / len)) * 180 / .pi : 90)
                                let now = angle(dv, MGVec3(0, 0, -1))
                                let tol = 1e-9 * max(1, doc.annotations.diagonal)
                                if !(d + e <= tol) || !(now + extra <= L.gravityDegrees) {
                                    // The top contributor: the centre's largest single (volume-weighted) part term or the end's part,
                                    // whichever is larger. Compared per contributor, not against the total `D`.
                                    let useEnd = endTop.map { $0.bound > (c?.top ?? 0) } ?? false
                                    var issue = fail(id)
                                    issue.centreOfMass = MGCentreOfMassMotion(
                                        arrow: id, step: i, part: useEnd ? endTop!.part : (c?.part ?? ""), joint: useEnd ? endTop!.joint : (c?.joint ?? ""),
                                        distance: useEnd ? endTop!.distance : c?.distance, bound: d, endBound: e, tolerance: tol, angle: now, extra: extra,
                                        from: from.world(pose), to: to.world(pose))
                                    throw issue
                                }
                            }
                        }
                    }
                    if spin != 0, !MGSolidAnnotationMotion.rigid(doc, [from, to], pose, translationOnly: true) { throw fail(id) }
                    let dv = to.world(pose) - from.world(pose)
                    if dv.length < L.minAuthorLength || angle(dv, MGVec3(0, 0, -1)) > L.gravityDegrees { throw fail(id) }
                default: continue
                }
            }
            if let i = step, let issue = broken(MGSolidIssue("text.pose.step.\(i + 1)"), dims(doc.steps[i].facts)) { throw issue }
            if let issue = broken(MGSolidIssue("text.pose.title"), dims(doc.titleFacts)) { throw issue }
        }
    }
}

// MARK: The one gate every output path uses

extension MGSolidDocument {
    /// The annotations a renderer may draw for `view` at `params`, or nil when the view or the pose is not one the
    /// engine checked; then a renderer draws none. A view checks only when it came from `view(step:)` of this exact
    /// compiled document (the view carries the document's fingerprint, and the document must be unchanged since it
    /// compiled), keeps its step's playback sense, lists each annotation at most once and only annotations that step
    /// shows (a host may remove some, never add), and `params` lies in the view's poses: the step's explode value and
    /// an input between the default input and the default input + `spin` turns (the plain view: the default pose). An
    /// empty list is `[]`. A framed still's arrow drops (`MGSolidView.arrowDrops`) are left out of the list.
    /// `MGSolidAnnotations.frame`, `MGSolidRenderer` and `MGSolidSnapshot.make` all call this.
    public func checkedAnnotations(_ view: MGSolidView, params: MGPoseParameters) -> [String]? {
        if view.annotations.isEmpty { return [] }
        // The view is bound to this compiled document (hosts cannot change a compiled document) and to its step's
        // playback sense.
        guard let checked = checkedFingerprint, view.fingerprint == checked else { return nil }
        let (u0, spin, e) = MGSolidAnnotationEngine.domain(self, step: view.step)
        guard view.motionSense == (spin < 0 ? -1 : 1) else { return nil }
        // Exactly the list the engine checked for that step (a view is read-only to hosts).
        guard view.annotations == visibleAnnotations(step: view.step) else { return nil }
        // Exact poses, no tolerance: the step's explode value, and the default input (a still step) or an input from
        // the default input to its end, `defaults.input + spin * 2 * .pi` (the same expression as the render plan).
        guard params.explode == e, params.input.isFinite else { return nil }
        // The step's pose exactly (no placement for any other step's pose or a pose between two steps).
        guard params.placements == MGSolidAnnotationEngine.placements(self, step: view.step) else { return nil }
        // The framing's arrow drops (`MGSolidView.arrowDrops`) are left out; they only ever remove.
        let shown = view.arrowDrops.isEmpty ? view.annotations : view.annotations.filter { id in !view.arrowDrops.contains { $0.id == id } }
        if spin == 0 { return params.input == u0 ? shown : nil }
        let u1 = u0 + spin * 2 * .pi
        guard params.input >= min(u0, u1), params.input <= max(u0, u1) else { return nil }
        return shown
    }

    /// The identity of a compiled document for its views: SHA-256 of its source (canonical JSON), the library's
    /// component ids, the default pose, the compiled motion (placements, joints, drives, motion sources), the steps,
    /// the annotations and the facts. Computed once when the document compiles; a compiled document is read-only to
    /// hosts, so the gate only compares a view's fingerprint with its document's.
    var annotationFingerprint: String {
        var t = "source \(source.canonicalString)\nlibrary \(library.components.keys.sorted())\n"
        t += "defaults \(defaults.input) \(defaults.explode)\n"
        for k in motionSources.keys.sorted() { t += "motion \(k) \(motionSources[k]!)\n" }
        for p in assembly.parts {
            t += "part \(p.id) \(p.parent ?? "-") \(p.placement) \(p.joint) \(String(describing: p.drive)) \(p.explode) \(p.explodeWindow)\n"
        }
        for s in steps {
            t += "step \(s.spin) \(String(describing: s.explode)) \(String(describing: s.annotate)) \(s.say)\n"
            for id in s.pose.keys.sorted() { t += "pose \(id) \(s.pose[id]!)\n" }
            if !s.hide.isEmpty || !s.show.isEmpty { t += "hide \(s.hide) show \(s.show)\n" }
        }
        t += "annotations \(annotations)\n"
        for name in facts.keys.sorted() { let f = facts[name]!; t += "fact \(name) \(f.value) \(f.unit) \(f.tier)\n" }
        for k in aliases.keys.sorted() { t += "alias \(k) \(aliases[k]!)\n" }
        for k in copies.keys.sorted() { t += "copy \(k) \(copies[k]!)\n" }
        t += "title \(title) \(titleFacts)\n"
        return MGSHA256.hex(Data(t.utf8))
    }
}

extension MGSolidShot {
    /// `marty-solid render` draws annotations on `hero.png` and on the step stills only.
    public var showsAnnotations: Bool { step != nil || file == "hero.png" }
}

/// Why a gravity arrow was refused in a moving step (`annotation.pose.<id>`): its centre-of-mass end
/// (`MGSolidAnnotationMotion.centreBound`) or its part-mounted ends (`pointBound`) can move there, so its direction is not
/// one Solved claim.
public struct MGCentreOfMassMotion: Equatable, Sendable {
    public let arrow: String
    /// The 0-based step whose `spin` moves the centre.
    public let step: Int
    /// The part that adds the most to the bound, and the joint (a part id) in its chain that adds the most.
    public let part: String, joint: String
    /// The centroid's distance (mm) from that joint's axis at the step's first pose; nil for a prismatic joint.
    public let distance: Double?
    /// The centre's displacement bound `D` (mm; 0 without a centre-of-mass end), the part-mounted ends' bound `E` (mm),
    /// and the most `D + E` may be (the world-fixed epsilon).
    public let bound: Double, endBound: Double, tolerance: Double
    /// The arrow's angle from down at the step's first pose, and the most `D` can add to it (degrees; 0 for two
    /// centre-of-mass ends).
    public let angle: Double, extra: Double
    /// The arrow's ends at the step's first pose (kernel world, mm): the fixed points of the repair.
    public let from: MGVec3, to: MGVec3

    /// `{"from": {"world": from}, "to": {"world": to}}` at full precision: the arrow at fixed points, exactly as it stands
    /// at the step's first pose, so the applied repair has the same vector (and the same angle from down). A candidate:
    /// the report and the repair line give it only when a copy with it applied compiles (`fixedVerified`).
    public var fixed: MGJSON {
        func w(_ x: MGVec3) -> MGJSON { .object(["world": .array([x.x, x.y, x.z].map { .number($0) })]) }
        return .object(["from": w(from), "to": w(to)])
    }
    /// True when a copy of the document with `fixed` applied compiles (`MGRepairCheck`); else `fixedNote` says why
    /// (a world point outside ±4000 mm is `anchor.world`).
    public internal(set) var fixedVerified = false
    public internal(set) var fixedNote: String? = nil

    /// A measure for the text (not an executable value): six significant digits.
    static func g(_ x: Double) -> String { x.isFinite ? String(format: "%.6g", x) : "infinite" }

    /// The actions first, each complete (`MGRepairLine`): `"spin": 0`, then the fixed points when they validate; then
    /// the explanation, cut to fit.
    public var repair: String {
        let g = MGCentreOfMassMotion.g
        let why = distance.map { "its centroid lies \(g($0)) mm off the axis of joint `\(joint)`" } ?? "joint `\(joint)` slides it"
        var prose = "Arrow \(arrow) (step \(step + 1)) can turn during the spin: its ends can move \(g(bound + endBound)) mm (at most \(g(tolerance))), "
            + "mostly because part `\(part)` moves and \(why)."
        if let note = fixedNote { prose += " No fixed points: \(note)." }
        return MGRepairLine.compose(#"Set "spin": 0 in step \#(step + 1)."#, fixed: fixedVerified ? ("Or anchor it at fixed points: ", fixed) : nil, prose: prose)
    }

    /// `{"arrow", "step" (1-based), "part", "joint", "distance", "bound", "endBound", "tolerance", "angle", "extraAngle",
    /// "fixed", "fixedNote", "repair"}` (numbers at full precision; null when not finite; `fixed` null and `fixedNote`
    /// set when the fixed points do not validate).
    public var json: MGJSON {
        func n(_ x: Double?) -> MGJSON { x.flatMap { $0.isFinite ? MGJSON.number($0) : nil } ?? .null }
        return .object(["arrow": .string(arrow), "step": .number(Double(step + 1)), "part": .string(part), "joint": .string(joint),
                        "distance": n(distance), "bound": n(bound), "endBound": n(endBound), "tolerance": n(tolerance), "angle": n(angle), "extraAngle": n(extra),
                        "fixed": fixedVerified ? fixed : .null, "fixedNote": fixedNote.map { .string($0) } ?? .null, "repair": .string(repair)])
    }
}

/// Why a dimension claim was refused for the motion (`annotation.pose.<id>`, `text.pose.step.<n>`, `text.pose.title`,
/// `step.pose.fact`, `dimension.over.motion.<id>`): an anchor that is world-fixed only within the epsilon of its axes can
/// still move during the motion (`MGSolidAnnotationMotion.anchorBound`; such offsets add up along a chain), so the value
/// (or, with `over`, the range) is not provably within its tolerance at every pose.
public struct MGDimensionMotion: Equatable, Sendable {
    public let dimension: String
    /// The 0-based step whose `spin` moves the anchors; nil when the range was measured (`over`, at the default pose).
    public let step: Int?
    /// True for a dimension with `over` (the bound is on its range).
    public let over: Bool
    /// The most each anchor can move (mm): `a`, `b` and, for an angle, `vertex`. With `over`, the sliding anchor's
    /// motion is exact (0 here).
    public let boundA: Double, boundB: Double, boundVertex: Double?
    /// The most the value can change during the motion (`mm` or `°`; with `over`, the most the range can be off: 2 × the
    /// held anchor's bound), the value's distance from its fact at the first pose, and the tolerance their sum must keep.
    public let change: Double, offset: Double, tolerance: Double
    /// `mm` or `°`.
    public let unit: String
    /// The anchor that can move the most (`a`, `b` or `vertex`), its part, the joint in its chain that adds the most, and
    /// the anchor's distance from that joint's axis (nil for a sliding joint).
    public let anchor: String, part: String, joint: String, distance: Double?
    /// The replacement anchors that validate (`MGRepairCheck`: a copy of the document with them applied compiles): the
    /// anchors that can move, as world points at the first pose at full precision, or, when that copy is refused (a world
    /// point outside ±4000 mm is `anchor.world`), as offsets on the nearest part above each that does not move. Nil when
    /// neither validates; `fixedNote` then says why.
    public internal(set) var fixed: MGJSON? = nil
    public internal(set) var fixedNote: String? = nil
    /// The replacements to try, in order (world points, then static-part offsets when every moving anchor has such a
    /// part).
    let candidates: [MGJSON]

    init(_ d: MGSolidDimension, _ doc: MGSolidDocument, step: Int?, over: Bool = false,
         ends: [(name: String, point: MGAnnotationPoint, bound: Double, joint: String?, distance: Double?)],
         change: Double, offset: Double, tolerance: Double, pose: MGPose) {
        dimension = d.id; self.step = step; self.over = over
        func b(_ n: String) -> Double? { ends.first { $0.name == n }?.bound }
        boundA = b("a") ?? 0; boundB = b("b") ?? 0; boundVertex = d.vertex == nil ? nil : (b("vertex") ?? 0)
        self.change = change; self.offset = offset; self.tolerance = tolerance; unit = d.unit
        let top = ends.filter { $0.bound > 0 }.max { $0.bound < $1.bound }
        anchor = top?.name ?? ""; part = top?.point.part ?? ""; joint = top?.joint ?? ""; distance = top?.distance
        func v(_ x: MGVec3) -> MGJSON { .array([x.x, x.y, x.z].map { .number($0) }) }
        var world: [String: MGJSON] = [:], still: [String: MGJSON] = [:]
        var allStill = true
        for e in ends where e.bound > 0 {
            let x = e.point.world(pose)
            world[e.name] = .object(["world": v(x)])
            // The nearest part at or above the anchor's part whose own chain does not move.
            var cur = e.point.part, found: String?
            while let c = cur, found == nil {
                if MGSolidAnnotationMotion.movers(doc, c).isEmpty { found = c }
                cur = doc.assembly.part(c)?.parent
            }
            if let f = found { still[e.name] = .object(["part": .string(f), "offset": v((pose.world[f] ?? .identity).inverse.apply(x))]) }
            else { allStill = false }
        }
        candidates = world.isEmpty ? [] : [.object(world)] + (allStill ? [.object(still)] : [])
    }

    /// The detail of an `over` range whose held anchor can move (`MGSolidAnnotationMotion.rangeBound`).
    static func over(_ d: MGSolidDimension, _ doc: MGSolidDocument, step: Int?,
                     _ r: (value: Double, bound: Double, other: MGAnnotationPoint, pose: MGPose, joint: String?, distance: Double?),
                     tolerance: Double) -> MGDimensionMotion {
        let name = r.other == d.a ? "a" : "b", slider = name == "a" ? "b" : "a"
        return MGDimensionMotion(d, doc, step: step, over: true,
                                 ends: [(name, r.other, r.bound / 2, r.joint, r.distance), (slider, name == "a" ? d.b : d.a, 0, nil, nil)],
                                 change: r.bound, offset: abs(r.value - d.value), tolerance: tolerance, pose: r.pose)
    }

    /// The actions first, each complete (`MGRepairLine`): `"spin": 0` (not for `over`, whose range covers a whole input
    /// turn whatever the step plays), then the replacement anchors when they validate; then the explanation, cut to fit.
    public var repair: String {
        let g = MGCentreOfMassMotion.g
        let top = [("a", boundA), ("b", boundB), ("vertex", boundVertex ?? 0)].first { $0.0 == anchor }?.1 ?? 0
        let why = distance.map { "joint `\(joint)` turns it \(g($0)) mm off its axis" } ?? "joint `\(joint)` slides it"
        let at = step.map { " (step \($0 + 1))" } ?? ""
        var prose = (over ? "Dimension \(dimension)\(at): its range over one input turn can be off by \(g(change)) \(unit)"
            : "Dimension \(dimension)\(at) can change during the spin by \(g(change)) \(unit)")
            + " (at most \(g(tolerance - offset)) \(unit)): anchor \(anchor) on part `\(part)` can move \(g(top)) mm, mostly because \(why)."
        if let note = fixedNote { prose += " No fixed anchor: \(note)." + (over ? " Hold that end on a part that does not move." : "") }
        let head = over ? "" : #"Set "spin": 0 in step \#((step ?? 0) + 1)."#
        return MGRepairLine.compose(head, fixed: fixed.map { (head.isEmpty ? "Replace its anchors with " : "Or replace its anchors with ", $0) }, prose: prose)
    }

    /// `{"dimension", "step" (1-based; null when measured), "over", "boundA", "boundB", "boundVertex", "change", "offset",
    /// "tolerance", "unit", "anchor", "part", "joint", "distance", "fixed", "fixedNote", "repair"}` (numbers at full
    /// precision; null when not finite or absent).
    public var json: MGJSON {
        func n(_ x: Double?) -> MGJSON { x.flatMap { $0.isFinite ? MGJSON.number($0) : nil } ?? .null }
        return .object(["dimension": .string(dimension), "step": step.map { .number(Double($0 + 1)) } ?? .null, "over": .bool(over),
                        "boundA": n(boundA), "boundB": n(boundB), "boundVertex": n(boundVertex), "change": n(change), "offset": n(offset),
                        "tolerance": n(tolerance), "unit": .string(unit), "anchor": .string(anchor), "part": .string(part), "joint": .string(joint),
                        "distance": n(distance), "fixed": fixed ?? .null, "fixedNote": fixedNote.map { .string($0) } ?? .null, "repair": .string(repair)])
    }
}

/// One repair line that a tool can pass to a model (at most `MGAnnotationAnchorIssue.repairScalars` Unicode scalars):
/// every executable action complete and first, then the explanation, which alone is cut to fit.
enum MGRepairLine {
    /// `head` (a short action, or empty), then `lead` + the replacement JSON + "." when it fits whole (else `lead` + "the
    /// report's `fixed` (see fixed)."), then `prose`, cut with "…" to the rest of the limit.
    static func compose(_ head: String, fixed: (lead: String, json: MGJSON)?, prose: String,
                        max: Int = MGAnnotationAnchorIssue.repairScalars) -> String {
        func join(_ a: String, _ b: String) -> String { a.isEmpty ? b : b.isEmpty ? a : a + " " + b }
        var actions = head
        if let f = fixed {
            let whole = join(actions, f.lead + MGAnnotationAnchorIssue.compactExact(f.json) + ".")
            // Room for at least a short explanation after the actions.
            actions = whole.unicodeScalars.count <= max - 40 ? whole : join(actions, f.lead + "the report's `fixed` (see fixed).")
        }
        let rest = max - actions.unicodeScalars.count - (actions.isEmpty ? 0 : 1)
        guard rest > 1 else { return actions }
        return join(actions, MGAnnotationAnchorIssue.bounded(prose, rest))
    }
}

/// Every executable fixed-point repair is checked before a report gives it (`MGSolidParser.document`): a copy of the
/// source with the repair applied must compile, as the weight suggestions are checked (`verified`). The copy's own
/// refusals are not checked again (`nested`).
enum MGRepairCheck {
    @TaskLocal static var nested = false

    static func verify(_ issue: MGSolidIssue, _ json: MGJSON, compile: (MGJSON) -> Result<MGSolidDocument, MGSolidIssue>) -> MGSolidIssue {
        guard !nested, issue.dimensionMotion != nil || issue.centreOfMass != nil else { return issue }
        func refusal(_ src: MGJSON) -> String? {
            guard case .failure(let e) = $nested.withValue(true, operation: { compile(src) }) else { return nil }
            return e.reason
        }
        var out = issue
        if var m = out.dimensionMotion {
            var notes: [String] = []
            for (k, c) in m.candidates.enumerated() {
                guard let r = refusal(replacingDimension(json, m.dimension, c)) else { m.fixed = c; break }
                notes.append((k == 0 ? "world points" : "part offsets") + " are refused (`\(r)`)")
            }
            if m.fixed == nil { m.fixedNote = notes.isEmpty ? "no part above it stays still" : notes.joined(separator: "; ") }
            out.dimensionMotion = m
        }
        if var c = out.centreOfMass {
            let r = refusal(MGSolidDocument.replacingArrows(json, [c.arrow: c.fixed]))
            c.fixedVerified = r == nil
            c.fixedNote = r.map { "they are refused (`\($0)`)" }
            out.centreOfMass = c
        }
        return out
    }

    /// `source` with the fields of `anchors` (`{"a"}`, `{"b"}`, `{"vertex"}`) set on dimension `id`.
    static func replacingDimension(_ source: MGJSON, _ id: String, _ anchors: MGJSON) -> MGJSON {
        guard case .object(var o) = source, case .object(var ann)? = o["annotations"], case .array(let list)? = ann["dimensions"],
              case .object(let fields) = anchors else { return source }
        ann["dimensions"] = .array(list.map { e in
            guard case .object(var eo) = e, eo["id"] == .string(id) else { return e }
            for (k, v) in fields { eo[k] = v }
            return .object(eo)
        })
        o["annotations"] = .object(ann)
        return .object(o)
    }
}
