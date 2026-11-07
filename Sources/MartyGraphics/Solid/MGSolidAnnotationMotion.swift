// SPDX-License-Identifier: Apache-2.0
import Foundation

// Exact motion facts for annotations, and the one check of what a view may show. No sampling: joint rates come from
// the drive closed forms (input, follow, gear mesh, crank-slider, crank-rod), point velocities from the joint chain,
// and every pose rule is decided by the structure of the motion (which joints move during a view), so a claim that
// passes holds at every pose the view can show. Foundation only, deterministic.

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

    /// The motion direction a view shows at a pose (`sense` −1 plays the input backwards): the velocity direction; at a
    /// crank-slider dead centre (the point's only moving joint is the slider and the velocity is 0), the direction the
    /// slider moves next, which is exact: away from either end of its stroke. Nil when the point does not move.
    static func direction(_ doc: MGSolidDocument, _ p: MGAnnotationPoint, _ pose: MGPose, sense: Double = 1) -> MGVec3? {
        let v = velocity(doc, p, pose) * (sense < 0 ? -1 : 1)
        if v.length > 1e-9 * max(1, doc.annotations.diagonal), v.x.isFinite, v.y.isFinite, v.z.isFinite { return v.normalized }
        let m = movers(doc, p.part)
        guard m.count == 1, let part = doc.assembly.part(m[0]), case .prismatic(let axis) = part.joint,
              case .crankSlider(let c, _, _, _)? = part.drive else { return nil }
        let t = pose.values[c] ?? 0
        return (pose.world[m[0]] ?? .identity).applyVector(axis).normalized * (-cos(t) >= 0 ? 1 : -1)
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

    /// True when the points keep their relative placement during any motion: all world-fixed, or all on the same
    /// moving chain (the same moving joints), and with `translationOnly`, no moving joint turns.
    static func rigid(_ doc: MGSolidDocument, _ points: [MGAnnotationPoint], _ pose: MGPose, translationOnly: Bool) -> Bool {
        if points.allSatisfy({ worldFixed(doc, $0, pose) }) { return true }
        let sets = points.map { movers(doc, $0.part) }
        guard let first = sets.first, sets.allSatisfy({ $0 == first }) else { return false }
        return !translationOnly || !first.contains { isRevolute(doc, $0) }
    }

    /// The exact range of a dimension with `over` over one input turn (`0...2π`) at an explode value. Exactly one anchor
    /// may move, by one prismatic joint (a linear drive or a crank-slider) and nothing else; the other anchors are
    /// world-fixed. Distances along an axis and straight distances only. Otherwise `dimension.over.motion.<id>`.
    static func range(_ d: MGSolidDimension, _ doc: MGSolidDocument, explode: Double) throws -> Double {
        let fail = MGSolidIssue("dimension.over.motion.\(d.id)", part: d.id)
        guard d.kind == .distance else { throw fail }
        let pose = doc.assembly.pose(MGPoseParameters(input: 0, explode: explode))
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
        if let k = d.along {
            let alpha = [w.x, w.y, w.z][k], beta = [a.x, a.y, a.z][k]
            let e0 = alpha + beta * qlo, e1 = alpha + beta * qhi
            let hiV = max(abs(e0), abs(e1)), loV = e0 * e1 <= 0 ? 0 : min(abs(e0), abs(e1))
            return hiV - loV
        }
        func dist(_ s: Double) -> Double { (w + a * s).length }
        let star = min(max(-w.dot(a), qlo), qhi)
        return max(dist(qlo), dist(qhi)) - dist(star)
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

    /// A dimension's value holds over a view: with `over`, its exact range at the view's explode value equals the
    /// fact; without, it is constant during the view (no motion, or rigid anchors) and equals the fact at the view's
    /// pose.
    static func dimensionHolds(_ d: MGSolidDimension, _ doc: MGSolidDocument, step: Int?) -> Bool {
        let (u0, spin, e) = domain(doc, step: step)
        let tol = 1e-9 * max(1, abs(d.value), doc.annotations.diagonal)
        if d.over { return (try? MGSolidAnnotationMotion.range(d, doc, explode: e)).map { abs($0 - d.value) <= tol } ?? false }
        let pose = doc.assembly.pose(MGPoseParameters(input: u0, explode: e))
        if spin != 0 {
            let pts = [d.a, d.b, d.vertex].compactMap { $0 }
            guard MGSolidAnnotationMotion.rigid(doc, pts, pose, translationOnly: d.along != nil) else { return false }
        }
        guard let v = dimensionValue(d, pose) else { return false }
        return abs(v - d.value) <= tol
    }

    /// Every displayed annotation claim holds at every pose its view can show, decided exactly (no sampling):
    /// - a shown dimension, and every `dim.<id>` fact that shown text (a label, an arrow or dimension text, the step's
    ///   caption, the title) displays, holds over the view (`dimensionHolds`);
    /// - a gravity force arrow does not turn during the view and points within 10° of −Z at the view's pose;
    /// - a motion line arrow does not ride a turning joint during a moving view; a stated `expect` holds at every pose
    ///   (a constant velocity, or a crank-slider that does not reverse inside the view);
    /// - a turn arrow's stated `sense` matches the way the view plays.
    /// Failures: `annotation.pose.<id>`, `text.pose.step.<n>` (a caption), `text.pose.title`.
    static func checkViews(_ doc: MGSolidDocument) throws {
        let a = doc.annotations
        guard !a.isEmpty else { return }
        func dims(_ facts: [String]) -> [MGSolidDimension] { a.dimensions.filter { facts.contains($0.factName) } }
        for step in [nil] + doc.steps.indices.map({ Optional($0) }) {
            let (u0, spin, e) = domain(doc, step: step)
            let sense: Double = spin < 0 ? -1 : 1
            let pose = doc.assembly.pose(MGPoseParameters(input: u0, explode: e))
            let shown = doc.visibleAnnotations(step: step)
            func fail(_ id: String) -> MGSolidIssue { MGSolidIssue("annotation.pose.\(id)", part: id) }
            for id in a.ids where shown.contains(id) {
                if let l = a.label(id) {
                    if !dims(l.facts).allSatisfy({ dimensionHolds($0, doc, step: step) }) { throw fail(id) }
                }
                if let d = a.dimension(id) {
                    if !dimensionHolds(d, doc, step: step) || !dims(d.facts).allSatisfy({ dimensionHolds($0, doc, step: step) }) { throw fail(id) }
                }
                guard let r = a.arrow(id) else { continue }
                if !dims(r.facts).allSatisfy({ dimensionHolds($0, doc, step: step) }) { throw fail(id) }
                switch (r.meaning, r.style) {
                case (.motion, .turn):
                    if let stated = r.sense, ((r.turnSign ?? 1) * sense > 0) != (stated == "ccw") { throw fail(id) }
                case (.motion, .line):
                    guard let from = r.from else { continue }
                    let m = MGSolidAnnotationMotion.movers(doc, from.part)
                    if spin != 0, m.contains(where: { MGSolidAnnotationMotion.isRevolute(doc, $0) }) { throw fail(id) }
                    guard let expect = r.expect else { continue }
                    guard let dir = MGSolidAnnotationMotion.direction(doc, from, pose, sense: sense), angle(expect, dir) <= L.expectDegrees else { throw fail(id) }
                    guard spin != 0 else { continue }
                    // Only translations move the anchor: linear drives give one constant velocity; a crank-slider must
                    // not pass a dead centre inside the view.
                    let crank = m.contains { id in
                        if case .crankSlider? = doc.assembly.part(id)?.drive { return true }
                        return false
                    }
                    if !crank { continue }
                    guard m.count == 1, case .crankSlider(let c, _, _, _)? = doc.assembly.part(m[0])?.drive,
                          let lc = MGSolidAnnotationMotion.linear(doc, c) else { throw fail(id) }
                    let t0 = lc.offset + lc.rate * u0, t1 = t0 + lc.rate * 2 * .pi * spin
                    let lo = min(t0, t1), hi = max(t0, t1)
                    let k = (lo / .pi).rounded(.down) + 1
                    if k * .pi < hi { throw fail(id) }
                case (.force, _) where r.cause == "gravity":
                    guard let from = r.from, let to = r.to else { continue }
                    if spin != 0, !MGSolidAnnotationMotion.rigid(doc, [from, to], pose, translationOnly: true) { throw fail(id) }
                    let dv = to.world(pose) - from.world(pose)
                    if dv.length < L.minAuthorLength || angle(dv, MGVec3(0, 0, -1)) > L.gravityDegrees { throw fail(id) }
                default: continue
                }
            }
            if let i = step, !dims(doc.steps[i].facts).allSatisfy({ dimensionHolds($0, doc, step: step) }) {
                throw MGSolidIssue("text.pose.step.\(i + 1)")
            }
            if !dims(doc.titleFacts).allSatisfy({ dimensionHolds($0, doc, step: step) }) { throw MGSolidIssue("text.pose.title") }
        }
    }
}

// MARK: The one gate every output path uses

extension MGSolidDocument {
    /// The annotations a renderer may draw for `view` at `params`, or nil when the view or the pose is not one the
    /// engine checked; then a renderer draws none. A view checks only when it came from `view(step:)` of this document,
    /// lists only annotations that step shows (a host may remove some, never add), and `params` lies in the view's
    /// poses: the step's explode value and an input between the default input and the default input + `spin` turns
    /// (the plain view: the default pose). An empty list is `[]`. `MGSolidAnnotations.frame`, `MGSolidRenderer` and
    /// `MGSolidSnapshot.make` all call this.
    public func checkedAnnotations(_ view: MGSolidView, params: MGPoseParameters) -> [String]? {
        if view.annotations.isEmpty { return [] }
        guard view.checked else { return nil }
        let allowed = Set(visibleAnnotations(step: view.step))
        guard view.annotations.allSatisfy({ allowed.contains($0) }) else { return nil }
        let (u0, spin, e) = MGSolidAnnotationEngine.domain(self, step: view.step)
        guard params.explode == e, params.input.isFinite else { return nil }
        let tol = 1e-9 * max(1, abs(u0), abs(params.input))
        let u1 = u0 + 2 * .pi * spin
        guard params.input >= min(u0, u1) - tol, params.input <= max(u0, u1) + tol else { return nil }
        return view.annotations
    }
}

extension MGSolidShot {
    /// `marty-solid render` draws annotations on `hero.png` and on the step stills only.
    public var showsAnnotations: Bool { step != nil || file == "hero.png" }
}
