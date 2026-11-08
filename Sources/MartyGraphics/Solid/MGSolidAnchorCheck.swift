// SPDX-License-Identifier: Apache-2.0
import Foundation

// The anchor rules of labels and pointer arrows (docs/SOLID-3D.md, "Anchor checks"). The anchor of a label (`at`) and
// the tip of a pointer (`to`) must lie on the part they name, with no other part nearer (`annotation.anchor.off.<id>`),
// and in every step or beat that shows them, the point must be visible from the camera of that step's still
// (`annotation.anchor.hidden.<id>`): not on a hidden or ghosted part, not off screen, and not behind another part. An
// anchor the triangle budget left untested is `annotation.anchor.untested.<id>`. The standard profile warns; the strict
// profile refuses. Foundation only, deterministic: annotations in view order, parts in assembly order, a fixed
// triangle-test budget per view.

/// Constants of the anchor rules.
public enum MGAnnotationAnchorRules {
    /// An anchor may lie at most `max(partShare × the part's box diagonal, modelShare × the model's box diagonal)` mm
    /// outside the box of its part's mesh, measured in the part's own frame (an oriented box), before it is off its part.
    public static let partShare = 0.05, modelShare = 0.005
    /// Triangle tests one view may spend on the line-of-sight tests. The anchor whose test would pass the budget, and
    /// every later anchor of the view, is not tested for occlusion (`untested`, `annotation.anchor.untested.<id>`): a
    /// warning in the standard profile, refused by the strict check report. The other causes are still tested.
    public static let tests = 3_000_000
    /// Triangles one document may read for the exact nearer-part distances of `annotation.anchor.off.<id>`
    /// (`MGSolidDocument.offPartAnchors`); after that, other parts are measured by their oriented box.
    public static let surfaceTests = 3_000_000
    /// The still size the check frames an assembly step at (`marty-solid render` default) and the composite frame an
    /// explainer beat's solid pane is laid out in.
    public static let width = 1280, height = 800
}

extension MGMaterialPreset {
    /// The share of the surface the renderer covers with this material: `opacity` for a transmissive material (glass:
    /// 0.22, `MGSolidRenderer` sets it as the material's transparency), else 1. A part's drawn coverage is this times
    /// its view opacity (`MGSolidPartView.opacity`, which holds the part's own `opacity` and any ghost).
    public var coverage: Double {
        let p = parameters
        return p.transmission > 0 ? min(1, max(0, p.opacity)) : 1
    }
}

/// One label or pointer anchor that breaks an anchor rule: what, where, why, and how to repair it.
public struct MGAnnotationAnchorIssue: Equatable, Sendable {
    public enum Cause: String, Equatable, Sendable, CaseIterable {
        /// Another part is the first surface on the line of sight from the camera to the anchor (`by` names it).
        case occluded
        /// The anchor's part is hidden in the view (step `hide`, or a show-only part the step does not `show`).
        case hidden
        /// The anchor's part is ghosted in the view (step `ghost`, or an automatic ghost of the unblocked-focus rule).
        case ghosted
        /// The anchor projects outside the view, or lies behind the camera.
        case offScreen = "offscreen"
        /// The line-of-sight test of the view ran over its triangle budget before this anchor
        /// (`annotation.anchor.untested.<id>`).
        case untested
        /// The anchor lies farther than `tolerance` from its part's oriented box, or another part (`closer`) is nearer
        /// to it (`annotation.anchor.off.<id>`).
        case offPart = "offpart"
    }
    /// The annotation id.
    public let id: String
    /// `label` (its `at`) or `pointer` (its tip, `to`).
    public let kind: String
    public let cause: Cause
    /// The part the anchor rides on; nil for a world anchor.
    public let part: String?
    /// `occluded`: the part in the way.
    public let by: String?
    /// The 0-based step and explainer beat whose view does not show the anchor; nil for `offPart` (a property of the
    /// document) and for a view that is not a step or a beat.
    public let step: Int?
    public let beat: Int?
    /// The anchor point in the posed kernel world (Z up, mm) of the view; for `offPart`, at the default input.
    public let point: MGVec3
    /// `offPart`: the distance (mm) from the anchor to its part's oriented box, and the largest distance allowed.
    public let distance: Double?
    public let tolerance: Double?
    /// `offPart`: the nearest other part when it is nearer to the anchor than `part`, and its distance (mm).
    public var closer: String? = nil
    public var closerDistance: Double? = nil

    /// `annotation.anchor.off.<id>`, `annotation.anchor.untested.<id>` or `annotation.anchor.hidden.<id>`.
    public var reason: String {
        switch cause {
        case .offPart: return "annotation.anchor.off.\(id)"
        case .untested: return "annotation.anchor.untested.\(id)"
        default: return "annotation.anchor.hidden.\(id)"
        }
    }

    /// A repair a model can act on.
    public var fix: String {
        let what = kind == "pointer" ? "the pointer tip (`to`)" : "the anchor (`at`)"
        let p = part.map { "`\($0)`" } ?? "the world point"
        func mm(_ x: Double?) -> String { x.map { String(format: "%.1f", $0) } ?? "?" }
        switch cause {
        case .offPart:
            let move = "Move \(what) onto \(p): an offset inside its box or within \(mm(tolerance)) mm of it, or {\"part\": \"\(part ?? "")\", "
                + "\"point\": \"centre\"}. For free text, use a {\"world\": [x, y, z]} anchor."
            guard let c = closer else { return move }
            return "`\(c)` is nearer to the anchor (\(mm(closerDistance)) mm) than \(p) (\(mm(distance)) mm), so the dot lands on `\(c)`. "
                + move + " If the label names `\(c)`, anchor it on `\(c)`."
        case .hidden:
            return "\(p) is hidden in this view: show it, anchor \(id) on a part the view shows, or leave \(id) out of this view's annotate list."
        case .ghosted:
            return "\(p) is ghosted in this view: do not ghost it (or change the camera so it is not an automatic ghost), anchor \(id) on "
                + "a solid part, or leave \(id) out of this view's annotate list."
        case .offScreen:
            return "The anchor is outside the view: change the camera (camera, orbit, focus) or move \(what) onto a framed part."
        case .untested:
            return "This view's line-of-sight test ran over its budget (\(MGAnnotationAnchorRules.tests) triangle tests) before this "
                + "anchor: hide or ghost parts that are not needed in this view, use simpler parts, or show fewer labels in it."
        case .occluded:
            let b = by.map { "`\($0)`" } ?? "another part"
            return "\(b) hides the anchor: move \(what) to a face of \(p) that faces the camera, change the camera (camera, orbit), "
                + "or ghost \(b) in this view."
        }
    }

    /// `{"id", "kind", "reason", "cause", "part", "by", "closer", "closerDistance", "step", "beat", "point", "distance",
    /// "tolerance", "fix"}`; `step` and `beat` are 1-based, absent values are null.
    public var json: MGJSON {
        func n(_ i: Int?) -> MGJSON { i.map { .number(Double($0 + 1)) } ?? .null }
        func d(_ x: Double?) -> MGJSON { x.flatMap { $0.isFinite ? .number(($0 * 1000).rounded() / 1000) : nil } ?? .null }
        let pt: MGJSON = [point.x, point.y, point.z].allSatisfy(\.isFinite)
            ? .array([point.x, point.y, point.z].map { .number(($0 * 1000).rounded() / 1000) }) : .null
        return .object(["id": .string(id), "kind": .string(kind), "reason": .string(reason), "cause": .string(cause.rawValue),
                        "part": part.map(MGJSON.string) ?? .null, "by": by.map(MGJSON.string) ?? .null,
                        "closer": closer.map(MGJSON.string) ?? .null, "closerDistance": d(closerDistance), "step": n(step), "beat": n(beat),
                        "point": pt, "distance": d(distance), "tolerance": d(tolerance), "fix": .string(fix)])
    }
}

/// The anchor issues of some views, in view order. Anchors a view's triangle budget left untested are issues with cause
/// `untested`.
public struct MGAnnotationAnchorReport: Equatable, Sendable {
    public internal(set) var issues: [MGAnnotationAnchorIssue] = []
    public init() {}

    mutating func append(_ o: MGAnnotationAnchorReport) { issues += o.issues }

    /// `(id, step, beat)` of each anchor a view did not test (0-based step and beat).
    public var untested: [(id: String, step: Int?, beat: Int?)] {
        issues.filter { $0.cause == .untested }.map { ($0.id, $0.step, $0.beat) }
    }

    /// `[{"id", "step", "beat"}]` with 1-based step and beat.
    public var untestedJSON: MGJSON {
        .array(untested.map { u in
            .object(["id": .string(u.id), "step": u.step.map { .number(Double($0 + 1)) } ?? .null,
                     "beat": u.beat.map { .number(Double($0 + 1)) } ?? .null])
        })
    }
}

extension MGSolidAnnotations {
    /// The anchor the anchor rules test for an annotation: a label's `at` or a pointer arrow's tip (`to`); nil for every
    /// other annotation (force, flow and motion arrows, dimensions).
    func checkedAnchor(_ id: String) -> (kind: String, point: MGAnnotationPoint)? {
        if let l = label(id) { return ("label", l.at) }
        if let r = arrow(id), r.meaning == .pointer, let to = r.to { return ("pointer", to) }
        return nil
    }
}

/// The distance (mm) from a point to a box (0 inside).
func mgBoxDistance(_ q: MGVec3, _ b: MGBounds) -> Double {
    let dx = max(0, b.min.x - q.x, q.x - b.max.x), dy = max(0, b.min.y - q.y, q.y - b.max.y), dz = max(0, b.min.z - q.z, q.z - b.max.z)
    return (dx * dx + dy * dy + dz * dz).squareRoot()
}

/// The closest point of triangle `abc` to `p` (Ericson, "Real-Time Collision Detection", 5.1.5).
func mgClosestOnTriangle(_ p: MGVec3, _ a: MGVec3, _ b: MGVec3, _ c: MGVec3) -> MGVec3 {
    let ab = b - a, ac = c - a, ap = p - a
    let d1 = ab.dot(ap), d2 = ac.dot(ap)
    if d1 <= 0 && d2 <= 0 { return a }
    let bp = p - b, d3 = ab.dot(bp), d4 = ac.dot(bp)
    if d3 >= 0 && d4 <= d3 { return b }
    let vc = d1 * d4 - d3 * d2
    if vc <= 0 && d1 >= 0 && d3 <= 0 { let v = d1 / (d1 - d3); return a + ab * v }
    let cp = p - c, d5 = ab.dot(cp), d6 = ac.dot(cp)
    if d6 >= 0 && d5 <= d6 { return c }
    let vb = d5 * d2 - d1 * d6
    if vb <= 0 && d2 >= 0 && d6 <= 0 { let w = d2 / (d2 - d6); return a + ac * w }
    let va = d3 * d6 - d5 * d4
    if va <= 0 && (d4 - d3) >= 0 && (d5 - d6) >= 0 { let w = (d4 - d3) / ((d4 - d3) + (d5 - d6)); return b + (c - b) * w }
    let den = va + vb + vc
    guard den != 0, den.isFinite else { return a }
    let v = vb / den, w = vc / den
    return a + ab * v + ac * w
}

/// The distance (mm) from `q` (in the mesh's frame) to the solid of a closed mesh: 0 when `q` lies inside it (an odd
/// number of watertight crossings on a segment from `q` past the mesh box along +X), else the distance to its nearest
/// triangle. Reads every triangle once, plus one segment test.
func mgSolidDistance(_ q: MGVec3, _ mesh: MGMesh) -> Double {
    let b = mesh.bounds
    guard !b.isEmpty else { return .infinity }
    if q.x <= b.max.x {
        let far = MGVec3(b.max.x + 1 + (b.max.x - q.x), q.y, q.z)
        if MGSolidFraming.OcclusionProbe.crossings(q, far, mesh, after: 0, before: 1).count % 2 == 1 { return 0 }
    }
    var best = Double.infinity
    for i in 0..<mesh.triangleCount {
        let (i0, i1, i2) = mesh.triangle(i)
        guard i0 < mesh.positions.count, i1 < mesh.positions.count, i2 < mesh.positions.count else { continue }
        let d = (mgClosestOnTriangle(q, mesh.positions[i0], mesh.positions[i1], mesh.positions[i2]) - q).length
        if d < best { best = d }
    }
    return best
}

extension MGSolidDocument {
    /// Labels and pointers whose anchor lies off the part it names (`annotation.anchor.off.<id>`), in authored order, at
    /// the default input with explode 0. Two tests, each on oriented boxes (a part's mesh box in its own frame):
    ///
    /// 1. The distance from the anchor to its part's box is at most `max(partShare × that box's diagonal, modelShare ×
    ///    the model's diagonal)` (in the part's frame, so it holds in every pose).
    /// 2. No other part is nearer to the anchor than its own part's box by more than the annotation tolerance (0.1 % of
    ///    the model's diagonal); the nearest such part is `closer`. Another part's distance is to its solid (0 inside
    ///    it, else to its nearest triangle, `mgSolidDistance`), so an L-shaped part whose box holds empty space does not
    ///    claim an anchor in that space. A part whose oriented box is not nearer is skipped. The exact tests of one
    ///    document read at most `MGAnnotationAnchorRules.surfaceTests` triangles; after that, other parts are measured
    ///    by their oriented box (stricter: an anchor may be refused, never passed, for lack of budget).
    ///
    /// A world anchor names no part and is not tested.
    public var offPartAnchors: [MGAnnotationAnchorIssue] {
        let a = annotations
        guard !a.isEmpty else { return [] }
        let rest = assembly.pose(MGPoseParameters(input: defaults.input, explode: 0))
        let eps = Swift.max(1e-6, 1e-3 * a.diagonal)
        var out: [MGAnnotationAnchorIssue] = []
        var used = 0
        for id in a.ids {
            guard let (kind, p) = a.checkedAnchor(id), let partID = p.part, let part = assembly.part(partID) else { continue }
            let b = part.mesh.bounds
            guard !b.isEmpty else { continue }
            let dist = mgBoxDistance(p.local, b)
            let tol = Swift.max(MGAnnotationAnchorRules.partShare * b.size.length, MGAnnotationAnchorRules.modelShare * a.diagonal)
            let x = p.world(rest)
            var closer: (id: String, d: Double)?
            for q in assembly.parts where q.id != partID {
                let qb = q.mesh.bounds
                guard !qb.isEmpty else { continue }
                let lq = (rest.world[q.id] ?? .identity).inverse.apply(x)
                var dq = mgBoxDistance(lq, qb)
                guard dq < dist - eps else { continue }
                if used + q.mesh.triangleCount <= MGAnnotationAnchorRules.surfaceTests {
                    used += q.mesh.triangleCount
                    dq = mgSolidDistance(lq, q.mesh)
                }
                if dq < dist - eps, closer.map({ dq < $0.d }) ?? true { closer = (q.id, dq) }
            }
            guard !(dist <= tol) || closer != nil else { continue }
            var issue = MGAnnotationAnchorIssue(id: id, kind: kind, cause: .offPart, part: partID, by: nil, step: nil, beat: nil,
                                                point: x, distance: dist, tolerance: tol)
            issue.closer = closer?.id; issue.closerDistance = closer?.d
            out.append(issue)
        }
        return out
    }

    /// The anchor rules of one framed view: for each label and pointer the view shows (`checkedAnnotations`, view order),
    /// in this order: its part is hidden (`hidden`), its part is ghosted (`ghosted`: the view draws it fainter than the
    /// part's own opacity), the anchor projects outside a `width` × `height` view of `camera` (`offScreen`), or another
    /// part is the first surface on the segment from the camera to the anchor (`occluded`), or the view's triangle budget
    /// ran out before its test (`untested`). The segment test is the watertight ray test of the unblocked-focus rule
    /// against every part the view draws with a coverage of `MGSolidFraming.blockingOpacity` or more (view opacity times
    /// `MGMaterialPreset.coverage`, so glass does not block; a cut part tests its cut mesh): a part blocks when it
    /// crosses the segment before the anchor (less the annotation tolerance) and before the first crossing of the
    /// anchor's own part. So an anchor at the centre of its part, seen through its part's own surface, is visible, and an
    /// anchor in the air in front of a part is not hidden by it. Exception: when the view cuts the anchor's part and the
    /// anchor lies in that part's box on the kept side of the cut (or on the cut face), the parts whose box lies inside
    /// that part's box, both taken in the cut part's own frame (grown by 0.5 % of the model's diagonal), do not hide it;
    /// parts outside still do. `step` and `beat` only label the issues.
    public func anchorIssues(view: MGSolidView, params: MGPoseParameters, camera: MGSolidCamera, width: Double, height: Double,
                             step: Int?, beat: Int?, stage: MGTransform = MGSolidStage.zUpToYUp) -> MGAnnotationAnchorReport {
        anchorIssues(view: view, params: params, camera: camera, width: width, height: height, step: step, beat: beat, stage: stage,
                     budget: MGAnnotationAnchorRules.tests)
    }

    /// `anchorIssues` with another triangle-test budget (tests).
    func anchorIssues(view: MGSolidView, params: MGPoseParameters, camera: MGSolidCamera, width: Double, height: Double,
                      step: Int?, beat: Int?, stage: MGTransform, budget: Int) -> MGAnnotationAnchorReport {
        var out = MGAnnotationAnchorReport()
        let a = annotations
        let ids = (checkedAnnotations(view, params: params) ?? []).filter { a.checkedAnchor($0) != nil }
        guard !ids.isEmpty else { return out }
        let pose = assembly.pose(params)
        let proj = MGAnnotationProjection(camera: camera, width: width, height: height)
        let eye = stage.inverse.apply(camera.position)
        let tol = Swift.max(1e-6, 1e-3 * a.diagonal)
        struct Solid { let id: String; let mesh: MGMesh; let inverse: MGTransform; let bounds: MGBounds }
        var solids: [Solid] = []
        var whole = MGBounds.empty
        for p in assembly.parts {
            let t = pose.world[p.id] ?? .identity
            let full = MGSolidFrames.worldBounds(p.mesh.bounds, t)
            let pv = view.part(p.id)
            guard !pv.hidden else { continue }
            whole = whole.union(full)
            // Drawn coverage: the view opacity (part opacity and ghosts) times the material's own (glass 0.22).
            guard pv.opacity * p.material.coverage >= MGSolidFraming.blockingOpacity else { continue }
            let mesh = pv.cut?.mesh ?? p.mesh
            solids.append(Solid(id: p.id, mesh: mesh, inverse: t.inverse, bounds: MGSolidFrames.worldBounds(mesh.bounds, t)))
        }
        let grow = 0.005 * (whole.isEmpty ? 0 : whole.size.length)
        var used = 0, over = false
        for id in ids {
            guard let (kind, p) = a.checkedAnchor(id) else { continue }
            let x = p.world(pose)
            func issue(_ c: MGAnnotationAnchorIssue.Cause, by: String? = nil) {
                out.issues.append(MGAnnotationAnchorIssue(id: id, kind: kind, cause: c, part: p.part, by: by, step: step, beat: beat, point: x,
                                                          distance: nil, tolerance: nil))
            }
            if let own = p.part {
                let pv = view.part(own)
                if pv.hidden { issue(.hidden); continue }
                let base = MGSolidView.clamp(opacity: assembly.part(own)?.opacity ?? 1)
                if pv.opacity < base - 1e-9 { issue(.ghosted); continue }
            }
            guard let s = proj.project(stage.apply(x)), s.x >= 0, s.x <= width, s.y >= 0, s.y <= height else { issue(.offScreen); continue }
            if over { issue(.untested); continue }
            // The cut exception: the inside of the anchor's own cut part does not hide it.
            var exempt = Set<String>()
            // Containment is tested in the cut part's own frame: every corner of another part's mesh box, posed and
            // taken into that frame, must lie in the cut part's mesh box (grown by `grow`), so a rotated cut part never
            // exempts a part outside it that only its world-axis box would hold.
            if let own = p.part, let cut = view.part(own).cut, let box = assembly.part(own)?.mesh.bounds,
               mgBoxDistance(p.local, box) <= tol, cut.plane.distance(p.local) <= tol {
                let toOwn = (pose.world[own] ?? .identity).inverse
                for q in assembly.parts where q.id != own && !q.mesh.bounds.isEmpty {
                    let t = toOwn * (pose.world[q.id] ?? .identity)
                    if q.mesh.bounds.corners.allSatisfy({ c in
                        let l = t.apply(c)
                        return l.x >= box.min.x - grow && l.x <= box.max.x + grow && l.y >= box.min.y - grow && l.y <= box.max.y + grow
                            && l.z >= box.min.z - grow && l.z <= box.max.z + grow
                    }) { exempt.insert(q.id) }
                }
            }
            let d = x - eye, len = d.length
            guard len > tol, len.isFinite else { continue }
            let before = 1 - tol / len
            var first: (t: Double, id: String)?, ownT: Double?
            for sld in solids where !exempt.contains(sld.id) && MGAnnotationOcclusion.segmentHits(eye, x, sld.bounds) {
                guard used + sld.mesh.triangleCount <= budget else { over = true; break }
                used += sld.mesh.triangleCount
                guard let t = MGSolidFraming.OcclusionProbe.firstHit(sld.inverse.apply(eye), sld.inverse.apply(x), sld.mesh,
                                                                     after: 1e-9, before: before) else { continue }
                if sld.id == p.part { ownT = t } else if first.map({ t < $0.t }) ?? true { first = (t, sld.id) }
            }
            if over { issue(.untested); continue }
            if let f = first, !(ownT.map { $0 <= f.t } ?? false) { issue(.occluded, by: f.id) }
        }
        return out
    }

    /// The anchor rules of every step still as `marty-solid render` frames it at `width` × `height`
    /// (`MGSolidRenderPlan.cameras`: the step's shot, its title and caption bands, the unblocked-focus rule and its
    /// automatic ghosts), at the still's pose. Steps whose view shows no label or pointer are skipped. The plain view
    /// (`hero.png`) and the poses during a step's spin are not tested.
    public func stepAnchorIssues(width: Int = MGAnnotationAnchorRules.width, height: Int = MGAnnotationAnchorRules.height) -> MGAnnotationAnchorReport {
        var out = MGAnnotationAnchorReport()
        guard !annotations.isEmpty else { return out }
        let w = Double(width), h = Double(height)
        let aspect = w > 0 && h > 0 ? w / h : 1.6
        let bands = MGSolidRenderPlan.bands(width: w, height: h)
        for i in steps.indices {
            let base = view(step: i)
            guard base.annotations.contains(where: { annotations.checkedAnchor($0) != nil }), let shot = MGSolidShot.step(self, i) else { continue }
            let clear = MGSolidFraming.clearView(self, shot: shot, aspect: aspect, titleBand: shot.title != nil ? bands.title : 0,
                                                 captionBand: shot.caption != nil ? bands.caption : 0)
            out.append(anchorIssues(view: base.ghosting(clear.autoGhost), params: shot.params, camera: clear.camera, width: w, height: h,
                                    step: i, beat: nil))
        }
        return out
    }
}
