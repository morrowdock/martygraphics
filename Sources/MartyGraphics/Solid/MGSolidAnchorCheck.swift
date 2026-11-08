// SPDX-License-Identifier: Apache-2.0
import Foundation

// The anchor rules of labels and pointer arrows (docs/SOLID-3D.md, "Anchor checks"). The anchor of a label (`at`) and
// the tip of a pointer (`to`) must lie on the part they name (`annotation.anchor.off.<id>`), and in every step or beat
// that shows them, the point must be visible from the camera of that step's still (`annotation.anchor.hidden.<id>`):
// not on a hidden or ghosted part, not off screen, and not behind another part. The standard profile warns; the strict
// profile refuses. Foundation only, deterministic: annotations in view order, parts in assembly order, a fixed
// triangle-test budget per view.

/// Constants of the anchor rules.
public enum MGAnnotationAnchorRules {
    /// An anchor may lie at most `max(partShare × the part's box diagonal, modelShare × the model's box diagonal)` mm
    /// outside the box of its part's mesh (in the part's own frame) before it is off its part.
    public static let partShare = 0.15, modelShare = 0.01
    /// Triangle tests one view may spend on the line-of-sight tests. The anchor whose test would pass the budget, and
    /// every later anchor of the view, is not tested for occlusion (`untested`), never refused for it; the other causes
    /// are still tested.
    public static let tests = 3_000_000
    /// The still size the check frames an assembly step at (`marty-solid render` default) and the composite frame an
    /// explainer beat's solid pane is laid out in.
    public static let width = 1280, height = 800
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
        /// The anchor lies farther than `tolerance` from the box of its part's mesh (`annotation.anchor.off.<id>`).
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
    /// `offPart`: the distance (mm) from the anchor to its part's box, and the largest distance allowed.
    public let distance: Double?
    public let tolerance: Double?

    /// `annotation.anchor.off.<id>` for `offPart`, else `annotation.anchor.hidden.<id>`.
    public var reason: String { cause == .offPart ? "annotation.anchor.off.\(id)" : "annotation.anchor.hidden.\(id)" }

    /// A repair a model can act on.
    public var fix: String {
        let what = kind == "pointer" ? "the pointer tip (`to`)" : "the anchor (`at`)"
        let p = part.map { "`\($0)`" } ?? "the world point"
        switch cause {
        case .offPart:
            let tol = tolerance.map { String(format: "%.1f", $0) } ?? "?"
            return "Move \(what) onto \(p): an offset inside its box or within \(tol) mm of it, or {\"part\": \"\(part ?? "")\", "
                + "\"point\": \"centre\"}. For free text, use a {\"world\": [x, y, z]} anchor."
        case .hidden:
            return "\(p) is hidden in this view: show it, anchor \(id) on a part the view shows, or leave \(id) out of this view's annotate list."
        case .ghosted:
            return "\(p) is ghosted in this view: do not ghost it (or change the camera so it is not an automatic ghost), anchor \(id) on "
                + "a solid part, or leave \(id) out of this view's annotate list."
        case .offScreen:
            return "The anchor is outside the view: change the camera (camera, orbit, focus) or move \(what) onto a framed part."
        case .occluded:
            let b = by.map { "`\($0)`" } ?? "another part"
            return "\(b) hides the anchor: move \(what) to a face of \(p) that faces the camera, change the camera (camera, orbit), "
                + "or ghost \(b) in this view."
        }
    }

    /// `{"id", "kind", "reason", "cause", "part", "by", "step", "beat", "point", "distance", "tolerance", "fix"}`; `step`
    /// and `beat` are 1-based, absent values are null.
    public var json: MGJSON {
        func n(_ i: Int?) -> MGJSON { i.map { .number(Double($0 + 1)) } ?? .null }
        func d(_ x: Double?) -> MGJSON { x.flatMap { $0.isFinite ? .number(($0 * 1000).rounded() / 1000) : nil } ?? .null }
        let pt: MGJSON = [point.x, point.y, point.z].allSatisfy(\.isFinite)
            ? .array([point.x, point.y, point.z].map { .number(($0 * 1000).rounded() / 1000) }) : .null
        return .object(["id": .string(id), "kind": .string(kind), "reason": .string(reason), "cause": .string(cause.rawValue),
                        "part": part.map(MGJSON.string) ?? .null, "by": by.map(MGJSON.string) ?? .null, "step": n(step), "beat": n(beat),
                        "point": pt, "distance": d(distance), "tolerance": d(tolerance), "fix": .string(fix)])
    }
}

/// The anchor issues of some views, and the anchors not tested because a view's triangle budget ran out.
public struct MGAnnotationAnchorReport: Equatable, Sendable {
    public internal(set) var issues: [MGAnnotationAnchorIssue] = []
    /// `(id, step, beat)` of each anchor a view did not test (0-based step and beat).
    public internal(set) var untested: [(id: String, step: Int?, beat: Int?)] = []
    public init() {}

    public static func == (a: MGAnnotationAnchorReport, b: MGAnnotationAnchorReport) -> Bool {
        a.issues == b.issues && a.untested.map { "\($0.id)|\($0.step ?? -1)|\($0.beat ?? -1)" } == b.untested.map { "\($0.id)|\($0.step ?? -1)|\($0.beat ?? -1)" }
    }

    mutating func append(_ o: MGAnnotationAnchorReport) { issues += o.issues; untested += o.untested }

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

extension MGSolidDocument {
    /// Labels and pointers whose anchor lies off the part it names (`annotation.anchor.off.<id>`), in authored order. The
    /// test is in the part's own frame, so it holds in every pose: the distance from the anchor to the box of the part's
    /// mesh must be at most `max(partShare × that box's diagonal, modelShare × the model's diagonal)`. A world anchor
    /// names no part and is not tested.
    public var offPartAnchors: [MGAnnotationAnchorIssue] {
        let a = annotations
        guard !a.isEmpty else { return [] }
        let rest = assembly.pose(MGPoseParameters(input: defaults.input, explode: 0))
        var out: [MGAnnotationAnchorIssue] = []
        for id in a.ids {
            guard let (kind, p) = a.checkedAnchor(id), let partID = p.part, let part = assembly.part(partID) else { continue }
            let b = part.mesh.bounds
            guard !b.isEmpty else { continue }
            let q = p.local
            let dx = Swift.max(0, b.min.x - q.x, q.x - b.max.x), dy = Swift.max(0, b.min.y - q.y, q.y - b.max.y)
            let dz = Swift.max(0, b.min.z - q.z, q.z - b.max.z)
            let dist = (dx * dx + dy * dy + dz * dz).squareRoot()
            let tol = Swift.max(MGAnnotationAnchorRules.partShare * b.size.length, MGAnnotationAnchorRules.modelShare * a.diagonal)
            guard !(dist <= tol) else { continue }
            out.append(MGAnnotationAnchorIssue(id: id, kind: kind, cause: .offPart, part: partID, by: nil, step: nil, beat: nil,
                                               point: p.world(rest), distance: dist, tolerance: tol))
        }
        return out
    }

    /// The anchor rules of one framed view: for each label and pointer the view shows (`checkedAnnotations`, view order),
    /// in this order: its part is hidden (`hidden`), its part is ghosted (`ghosted`: the view draws it fainter than the
    /// part's own opacity), the anchor projects outside a `width` × `height` view of `camera` (`offScreen`), or another
    /// part is the first surface on the segment from the camera to the anchor (`occluded`). The segment test is the
    /// watertight ray test of the unblocked-focus rule against every part the view shows at
    /// `MGSolidFraming.blockingOpacity` or more (a cut part tests its cut mesh): a part blocks when it crosses the segment
    /// before the anchor (less the annotation tolerance) and before the first crossing of the anchor's own part. So an
    /// anchor at the centre of its part, seen through its part's own surface, is visible, and an anchor in the air in
    /// front of a part is not hidden by it. Exception: when the view cuts the anchor's part and the anchor lies in that
    /// part's box on the kept side of the cut (or on the cut face), the parts inside that part's box (grown by 0.5 % of
    /// the model's diagonal) do not hide it; parts outside still do. `step` and `beat` only label the issues.
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
        var boxes: [String: MGBounds] = [:]
        var whole = MGBounds.empty
        for p in assembly.parts {
            let t = pose.world[p.id] ?? .identity
            let full = MGSolidFrames.worldBounds(p.mesh.bounds, t)
            boxes[p.id] = full
            let pv = view.part(p.id)
            guard !pv.hidden else { continue }
            whole = whole.union(full)
            guard pv.opacity >= MGSolidFraming.blockingOpacity else { continue }
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
            if over { out.untested.append((id, step, beat)); continue }
            // The cut exception: the inside of the anchor's own cut part does not hide it.
            var exempt = Set<String>()
            if let own = p.part, let cut = view.part(own).cut, let box = assembly.part(own)?.mesh.bounds,
               p.local.x >= box.min.x - tol, p.local.x <= box.max.x + tol, p.local.y >= box.min.y - tol, p.local.y <= box.max.y + tol,
               p.local.z >= box.min.z - tol, p.local.z <= box.max.z + tol, cut.plane.distance(p.local) <= tol, let ob = boxes[own] {
                for q in assembly.parts where q.id != own {
                    guard let b = boxes[q.id], !b.isEmpty else { continue }
                    if b.min.x >= ob.min.x - grow, b.max.x <= ob.max.x + grow, b.min.y >= ob.min.y - grow, b.max.y <= ob.max.y + grow,
                       b.min.z >= ob.min.z - grow, b.max.z <= ob.max.z + grow { exempt.insert(q.id) }
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
            if over { out.untested.append((id, step, beat)); continue }
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
