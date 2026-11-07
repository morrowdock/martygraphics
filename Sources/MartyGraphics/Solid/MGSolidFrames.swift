// SPDX-License-Identifier: Apache-2.0
import Foundation

// Honesty lints over a compiled solid document: idle joints and frame errors (a child placed in world coordinates,
// a child far from its parent, a turn axis that misses its own part), `expect` orientation claims, the plain-words
// read-back of every part, and the strict (model harness) profile. Foundation only, deterministic.

/// Which warnings refuse a document. `standard` (the plain API) only warns; `strict` (the model harness, owner D3)
/// refuses only errors that are certain from the document itself: a jointed part that nothing moves, and a turn
/// axis that misses its own jointed part. The child-frame heuristics (`frame.child.absolute`, `frame.child.far`)
/// stay warnings in both profiles: they can flag correct parent-relative layouts (spaced plates, parts on posts),
/// so the read-back of world positions, not a refusal, is the defence against frame errors.
public enum MGSolidProfile: Equatable, Sendable {
    case standard, strict

    /// Warning reason prefixes that the strict profile refuses.
    public static let strictPrefixes = ["joint.idle.", "frame.axis.off."]

    /// The first warning this profile refuses, in document order; nil when the document passes.
    public func refusal(_ doc: MGSolidDocument) -> MGSolidIssue? {
        guard self == .strict else { return nil }
        return doc.warnings.first { w in MGSolidProfile.strictPrefixes.contains { w.reason.hasPrefix($0) } }
    }
}

enum MGSolidFrames {
    /// A child is "far" when its bounds miss the parent's bounds grown by this many parent sizes.
    static let farFactor = 1.5
    /// `expect` directions must match within this angle (degrees).
    static let expectDegrees = 1.0

    /// World bounds of a part's mesh under a transform (transformed bounding-box corners; conservative).
    static func worldBounds(_ local: MGBounds, _ t: MGTransform) -> MGBounds {
        var b = MGBounds.empty
        for c in local.corners { b.include(t.apply(c)) }
        return b
    }

    /// World bounds of a mesh's vertices under a transform (exact for the read-back; slower than `worldBounds`).
    static func vertexBounds(_ mesh: MGMesh, _ t: MGTransform) -> MGBounds {
        var b = MGBounds.empty
        for p in mesh.positions { b.include(t.apply(p)) }
        return b
    }

    /// Distance between two boxes (0 when they touch or overlap).
    static func gap(_ a: MGBounds, _ b: MGBounds) -> Double {
        let dx = max(0, a.min.x - b.max.x, b.min.x - a.max.x)
        let dy = max(0, a.min.y - b.max.y, b.min.y - a.max.y)
        let dz = max(0, a.min.z - b.max.z, b.min.z - a.max.z)
        return (dx * dx + dy * dy + dz * dz).squareRoot()
    }

    static func intersects(_ a: MGBounds, _ b: MGBounds) -> Bool {
        a.min.x <= b.max.x && b.min.x <= a.max.x && a.min.y <= b.max.y && b.min.y <= a.max.y && a.min.z <= b.max.z && b.min.z <= a.max.z
    }

    /// True when the infinite line through the origin along `dir` passes through `box` (slab test).
    static func lineHits(_ dir: MGVec3, _ box: MGBounds) -> Bool {
        var lo = -Double.infinity, hi = Double.infinity
        for (d, mn, mx) in [(dir.x, box.min.x, box.max.x), (dir.y, box.min.y, box.max.y), (dir.z, box.min.z, box.max.z)] {
            if abs(d) < 1e-12 {
                guard mn <= 0, 0 <= mx else { return false }
            } else {
                let t1 = mn / d, t2 = mx / d
                lo = max(lo, min(t1, t2)); hi = min(hi, max(t1, t2))
            }
        }
        return lo <= hi
    }

    /// Placement of every part with every joint at 0 (the authored frames, before any drive acts).
    static func restWorld(_ a: MGAssembly) -> [String: MGTransform] {
        var still = a
        for i in still.parts.indices { still.parts[i].drive = nil }
        return still.pose(MGPoseParameters()).world
    }

    /// Idle joints and frame lints, in part order (for each part: idle, absolute child, far child, axis off). A
    /// `repeat` copy reports its base id once.
    static func lints(_ doc: MGSolidDocument) -> [MGSolidIssue] {
        let a = doc.assembly
        let byID = Dictionary(a.parts.map { ($0.id, $0) }, uniquingKeysWith: { x, _ in x })
        let rest = restWorld(a)
        let posed = a.pose(MGPoseParameters()).world
        var localBounds: [String: MGBounds] = [:]
        for p in a.parts { localBounds[p.id] = p.mesh.bounds }
        func world(_ id: String) -> MGBounds { worldBounds(localBounds[id] ?? .empty, posed[id] ?? .identity) }
        var out: [MGSolidIssue] = []
        var reported = Set<String>()
        func report(_ kind: String, _ base: String) {
            let reason = "\(kind).\(MGSolidParser.token(base))"
            if reported.insert(reason).inserted { out.append(MGSolidIssue(reason, part: base)) }
        }
        for p in a.parts {
            let base = doc.copies[p.id] ?? p.id
            // A joint that nothing drives never moves; the learner would see a still part that looks jointed.
            if p.joint != .fixed && p.drive == nil { report("joint.idle", base) }
            if let parent = p.parent, byID[parent] != nil {
                // World coordinates written into a parent-relative `at` / `rot` move the child by the parent's
                // placement again (the double offset). Confirmed by geometry, with every joint at 0: the child misses
                // its parent as placed, but read as world values its `at` / `rot` put it nearer, within one parent
                // size. A child that touches its parent as placed (an arm link, a chain, a stack) never warns, and
                // neither does a child of a parent at the world origin: only rotation differs there (a turbofan
                // spinner on a shaft laid along X), so there is no offset to double.
                let pr = worldBounds(localBounds[parent] ?? .empty, rest[parent] ?? .identity)
                let lb = localBounds[p.id] ?? .empty
                let placed = gap(pr, worldBounds(lb, rest[p.id] ?? .identity)), asWorld = gap(pr, worldBounds(lb, p.placement))
                let touch = max(0.01, 1e-6 * max(pr.size.x, pr.size.y, pr.size.z))
                if !pr.isEmpty, !lb.isEmpty, (rest[parent] ?? .identity).translation.length > touch, placed > touch, asWorld < placed,
                   asWorld <= max(pr.size.x, pr.size.y, pr.size.z) {
                    report("frame.child.absolute", base)
                }
                let pb = world(parent), cb = world(p.id)
                if !pb.isEmpty, !cb.isEmpty {
                    let grow = farFactor * max(pb.size.x, pb.size.y, pb.size.z)
                    let g = MGVec3(grow, grow, grow)
                    if !intersects(MGBounds(min: pb.min - g, max: pb.max + g), cb) { report("frame.child.far", base) }
                }
            }
            // A turn axis must pass through its own part, unless the author says it is off axis on purpose.
            if case .revolute(let axis) = p.joint, !doc.offAxis.contains(base), let lb = localBounds[p.id], !lb.isEmpty {
                let tol = max(0.01, 0.01 * max(lb.size.x, lb.size.y, lb.size.z))
                let t = MGVec3(tol, tol, tol)
                if !lineHits(axis, MGBounds(min: lb.min - t, max: lb.max + t)) { report("frame.axis.off", base) }
            }
        }
        return out
    }

    /// Checks `expect` claims at input 0: `axisWorld` against the joint axis in world space, `upWorld` against the
    /// part's local +Z in world space. Refuses `expect.axis.<id>` / `expect.up.<id>` (base id for copies).
    static func checkExpectations(_ a: MGAssembly, _ expects: [String: (axis: MGVec3?, up: MGVec3?)], copies: [String: String]) throws {
        guard !expects.isEmpty else { return }
        let w = a.pose(MGPoseParameters()).world
        let cosTol = cos(expectDegrees * .pi / 180)
        for p in a.parts {
            let base = copies[p.id] ?? p.id
            guard let e = expects[base] else { continue }
            let t = w[p.id] ?? .identity
            if let want = e.axis {
                let axis: MGVec3?
                switch p.joint {
                case .revolute(let x), .prismatic(let x): axis = t.applyVector(x).normalized
                case .fixed: axis = nil
                }
                guard let got = axis, got.dot(want.normalized) >= cosTol else { throw MGSolidIssue("expect.axis.\(MGSolidParser.token(base))", part: base) }
            }
            if let want = e.up {
                guard t.applyVector(.unitZ).normalized.dot(want.normalized) >= cosTol else {
                    throw MGSolidIssue("expect.up.\(MGSolidParser.token(base))", part: base)
                }
            }
        }
    }

    // MARK: Read-back

    static func num(_ v: Double) -> String { MGPhysics.format(abs(v) < 5e-7 ? 0 : v, unit: "") }
    static func point(_ v: MGVec3) -> String { "(\(num(v.x)), \(num(v.y)), \(num(v.z)))" }
    static func list(_ v: MGVec3) -> String { "[\(num(v.x)), \(num(v.y)), \(num(v.z))]" }

    /// "+X", "-Z" when within 1° of a principal axis; otherwise the rounded unit vector.
    static func direction(_ d: MGVec3) -> String {
        let u = d.normalized, c = cos(expectDegrees * .pi / 180)
        for (name, e) in [("X", MGVec3.unitX), ("Y", .unitY), ("Z", .unitZ)] {
            if u.dot(e) >= c { return "+" + name }
            if u.dot(e) <= -c { return "-" + name }
        }
        return point(u)
    }

    /// "a vertical axis (+Z)", "a horizontal axis (+X)", "a horizontal axis along (0.71, 0.71, 0)" or
    /// "an axis tilted 30° from vertical, along (0.5, 0, 0.87)".
    static func axisWords(_ d: MGVec3) -> String {
        let u = d.normalized, tilt = acos(min(1, abs(u.z))) * 180 / .pi
        let dir = direction(u), along = dir.hasPrefix("(") ? " along \(dir)" : " (\(dir))"
        if tilt <= expectDegrees { return "a vertical axis" + along }
        if tilt >= 90 - expectDegrees { return "a horizontal axis" + along }
        return "an axis tilted \(num(tilt))° from vertical, along \(dir)"
    }

    /// One plain-words line per part at input 0 (world position, motion with its tier and source, parent frame,
    /// the part's up), so an author that cannot see the render can compare the model with its intent.
    static func readBack(_ doc: MGSolidDocument) -> [String] {
        let a = doc.assembly
        let byID = Dictionary(a.parts.map { ($0.id, $0) }, uniquingKeysWith: { x, _ in x })
        let w = a.pose(MGPoseParameters()).world
        return a.parts.map { p in
            let t = w[p.id] ?? .identity
            let b = vertexBounds(p.mesh, t)
            var s = "\(p.id): world centre \(point(b.center)) mm, size \(num(b.size.x)) x \(num(b.size.y)) x \(num(b.size.z)) mm"
            switch p.joint {
            case .revolute(let axis):
                let wa = t.applyVector(axis)
                if let tier = doc.motionTier(p.id), let src = doc.motionSources[p.id] {
                    var speed = doc.facts[p.id + ".speed"].map { "\($0.text) \(abs($0.value) == 1 ? "turn" : "turns") per input turn" } ?? "angle from \(src)"
                    if let parent = p.parent, doc.ownMotion(parent) || doc.movingAncestor(parent) != nil { speed += " relative to \(parent)" }
                    s += "; turns about \(axisWords(wa)) through \(point(t.translation)); \(speed) (\(tier.name.capitalized), \(src))"
                } else {
                    s += "; joint about \(axisWords(wa)) " + (p.drive == nil ? "with no drive: never moves (joint.idle)" : "held still")
                }
            case .prismatic(let axis):
                let wa = t.applyVector(axis)
                if let tier = doc.motionTier(p.id), let src = doc.motionSources[p.id] {
                    let travel = doc.facts[p.id + ".travel"].map { "travel \($0.text) per input turn" } ?? "moved by \(src)"
                    s += "; slides along \(direction(wa)); \(travel) (\(tier.name.capitalized), \(src))"
                } else {
                    s += "; slide along \(direction(wa)) " + (p.drive == nil ? "with no drive: never moves (joint.idle)" : "held still")
                }
            case .fixed:
                s += doc.movingAncestor(p.id).map { "; fixed to its parent, moves with \($0)" } ?? "; static"
            }
            if let base = doc.copies[p.id] {
                let n = doc.copies.values.filter { $0 == base }.count
                s += "; copy \(p.id.dropFirst(base.count)) of \(n) (repeat of \(base))"
            }
            if let parent = p.parent, let pp = byID[parent] {
                s += "; child of \(parent) (at \(list(p.placement.translation)) in the \(parent) frame)"
                if case .revolute(let pa) = pp.joint {
                    // Distance of this part's origin from the parent's turn axis, both in world space at input 0.
                    let pw = w[parent] ?? .identity, axis = pw.applyVector(pa).normalized
                    let d = t.translation - pw.translation
                    s += "; its origin is \(num((d - axis * axis.dot(d)).length)) mm from the \(parent) axis"
                }
            } else {
                s += "; root (at \(list(p.placement.translation)) in the world frame)"
            }
            s += "; local +Z points \(direction(t.applyVector(.unitZ)))"
            return s
        }
    }
}

extension MGSolidDocument {
    /// The plain-words read-back of every part at input 0 (see docs/SOLID-3D.md, "Check report").
    public var readBack: [String] { MGSolidFrames.readBack(self) }
}
