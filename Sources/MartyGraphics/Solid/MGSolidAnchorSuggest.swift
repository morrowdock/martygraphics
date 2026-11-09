// SPDX-License-Identifier: Apache-2.0
import Foundation

// Anchor suggestions (docs/SOLID-3D.md, "Anchor suggestions"): for a label or pointer that breaks an anchor rule
// (`annotation.anchor.off.<id>`, `annotation.anchor.hidden.<id>`), the check report gives an anchor that passes both
// rules in every view that shows the annotation, or says why none was found. The search casts rays from each view's
// camera toward sample points of the named part, takes the first hit on that part, and keeps a candidate only when the
// same rule functions as the check (`MGAnchorViewRule.test`, `MGSolidDocument.offPartIssue`) pass it, written exactly as
// the report prints it. Foundation only, deterministic: views in order, samples in a fixed order, a fixed test budget.

/// One framed view of the anchor view rule: the still a step or explainer beat shows (`MGSolidDocument.anchorIssues`).
public struct MGAnnotationAnchorView: Sendable {
    public let view: MGSolidView
    public let params: MGPoseParameters
    public let camera: MGSolidCamera
    public let width: Double, height: Double
    /// The 0-based step and explainer beat; they only label issues and suggestions.
    public let step: Int?, beat: Int?
    public let stage: MGTransform

    public init(view: MGSolidView, params: MGPoseParameters, camera: MGSolidCamera, width: Double, height: Double, step: Int?, beat: Int?,
                stage: MGTransform = MGSolidStage.zUpToYUp) {
        self.view = view; self.params = params; self.camera = camera; self.width = width; self.height = height
        self.step = step; self.beat = beat; self.stage = stage
    }
}

/// The nearer-part budget of one document's off-part rule, with its caches (part runs and poses).
struct MGOffPartState {
    var budget: Int
    var chunks: [String: MGMeshChunks] = [:]
    var poses: [(params: MGPoseParameters, pose: MGPose)] = []
    init(budget: Int) { self.budget = budget }

    mutating func posed(_ doc: MGSolidDocument, _ params: MGPoseParameters) -> MGPose {
        if let hit = poses.first(where: { $0.params == params }) { return hit.pose }
        let p = doc.assembly.pose(params); poses.append((params, p)); return p
    }
}

/// The anchor view rule of one framed view, prepared once (`MGSolidDocument.anchorIssues`): the parts that can block a
/// line of sight, the camera and the projection. `test` checks one anchor.
struct MGAnchorViewRule {
    struct Solid { let id: String; let mesh: MGMesh; let world: MGTransform }
    let doc: MGSolidDocument
    let v: MGAnnotationAnchorView
    let pose: MGPose
    let proj: MGAnnotationProjection
    let eye: MGVec3
    let solids: [Solid]
    let grow: Double
    var ownChunks: [String: MGMeshChunks] = [:]

    init(_ doc: MGSolidDocument, _ v: MGAnnotationAnchorView) {
        self.doc = doc; self.v = v
        pose = doc.assembly.pose(v.params)
        proj = MGAnnotationProjection(camera: v.camera, width: v.width, height: v.height)
        eye = v.stage.inverse.apply(v.camera.position)
        var solids: [Solid] = []
        var whole = MGBounds.empty
        for p in doc.assembly.parts {
            let t = pose.world[p.id] ?? .identity
            let full = MGSolidFrames.worldBounds(p.mesh.bounds, t)
            let pv = v.view.part(p.id)
            guard !pv.hidden else { continue }
            whole = whole.union(full)
            // Drawn coverage: the view opacity (part opacity and ghosts) times the material's own (glass 0.22).
            guard pv.opacity * p.material.coverage >= MGSolidFraming.blockingOpacity else { continue }
            solids.append(Solid(id: p.id, mesh: pv.cut?.mesh ?? p.mesh, world: t))
        }
        self.solids = solids
        grow = 0.005 * (whole.isEmpty ? 0 : whole.size.length)
    }

    /// The cut exception of the view rule for anchor `p` at world point `x`: when the view cuts the anchor's part and the
    /// anchor lies in that part's box on the kept side (or on the cut face), the parts whose box lies inside that part's
    /// box do not hide it. Containment is tested in the cut part's own frame: every corner of another part's mesh box,
    /// posed and taken into that frame (through anchor-relative coordinates), must lie in the cut part's mesh box (grown
    /// by `grow`), so a rotated cut part never exempts a part outside it that only its world-axis box would hold.
    func exemptParts(_ p: MGAnnotationPoint, x: MGVec3) -> Set<String> {
        var exempt = Set<String>()
        let view = v.view, assembly = doc.assembly, eps = mgPrecision(.zero)
        guard let own = p.part, let cut = view.part(own).cut, let box = assembly.part(own)?.mesh.bounds else { return exempt }
        let ownRel = mgAnchorRelative(pose.world[own] ?? .identity, anchor: x)
        let lo = ownRel.toLocal.apply(.zero)
        guard mgBoxDistance(lo, box) <= eps, cut.plane.distance(lo) <= eps else { return exempt }
        for q in assembly.parts where q.id != own && !q.mesh.bounds.isEmpty {
            let qRel = mgAnchorRelative(pose.world[q.id] ?? .identity, anchor: x)
            if q.mesh.bounds.corners.allSatisfy({ c in
                let l = ownRel.toLocal.apply(qRel.toRelative.apply(c))
                return l.x >= box.min.x - grow && l.x <= box.max.x + grow && l.y >= box.min.y - grow && l.y <= box.max.y + grow
                    && l.z >= box.min.z - grow && l.z <= box.max.z + grow
            }) { exempt.insert(q.id) }
        }
        return exempt
    }

    /// The view rule for one anchor (`MGSolidDocument.anchorIssues` describes it): nil when the view shows the anchor,
    /// else the cause and, for `occluded`, the part in the way. `used` and `over` carry the view's triangle budget.
    mutating func test(_ p: MGAnnotationPoint, used: inout Int, over: inout Bool, budget: Int) -> (MGAnnotationAnchorIssue.Cause, String?)? {
        let view = v.view, assembly = doc.assembly
        let x = p.world(pose)
        if let own = p.part {
            let pv = view.part(own)
            if pv.hidden { return (.hidden, nil) }
            let base = MGSolidView.clamp(opacity: assembly.part(own)?.opacity ?? 1)
            if pv.opacity < base - 1e-9 { return (.ghosted, nil) }
        }
        guard let s = proj.project(v.stage.apply(x)), s.x >= 0, s.x <= v.width, s.y >= 0, s.y <= v.height else { return (.offScreen, nil) }
        if over { return (.untested, nil) }
        // Every test below runs in anchor-relative coordinates (world minus the anchor, `mgAnchorRelative`): the camera,
        // each part's placement and every hit point are taken relative to the dot before any test, so the precision
        // epsilon (`mgPrecision`) depends on the distance from the dot only, never on where the model is.
        let eps = mgPrecision(.zero)
        let eyeRel = eye - x
        let ownRel = p.part.map { mgAnchorRelative(pose.world[$0] ?? .identity, anchor: x) }
        let exempt = exemptParts(p, x: x)
        // The segment from the camera (t = 0) to the dot (t = 1, the origin), less the epsilon at the dot.
        let len = eyeRel.length
        guard len > eps, len.isFinite else { return nil }
        let before = 1 - eps / len
        var first: (t: Double, id: String)?, ownT: Double?
        for sld in solids where !exempt.contains(sld.id) {
            let rel = mgAnchorRelative(sld.world, anchor: x)
            guard MGAnnotationOcclusion.segmentHits(eyeRel, .zero, MGSolidFrames.worldBounds(sld.mesh.bounds, rel.toRelative)) else { continue }
            guard used + sld.mesh.triangleCount <= budget else { over = true; break }
            used += sld.mesh.triangleCount
            guard let t = MGSolidFraming.OcclusionProbe.firstHit(rel.toLocal.apply(eyeRel), rel.toLocal.apply(.zero), sld.mesh,
                                                                 after: 1e-9, before: before) else { continue }
            if sld.id == p.part { ownT = t } else if first.map({ t < $0.t }) ?? true { first = (t, sld.id) }
        }
        if over { return (.untested, nil) }
        guard let f = first, !(ownT.map { $0 <= f.t } ?? false) else { return nil }
        // A coincident surface is a tie, not an occlusion: when the blocker's hit point lies on the anchor's own part
        // (as the view draws it) within the precision epsilon at that point (its distance from the dot), the own
        // part is there too, so it is visible. Two touching parts give the same answer whichever of them the anchor
        // names; a separate part in front is a tie only when it is within that epsilon of the own part
        // (1.01e-4 mm plus 1e-6 per mm from the dot), wherever the model is.
        if let own = p.part, let ownRel, let ownPart = assembly.part(own) {
            let mesh = view.part(own).cut?.mesh ?? ownPart.mesh
            if ownChunks[own] == nil {
                guard used + mesh.triangleCount <= budget else { over = true; return (.untested, nil) }
                used += mesh.triangleCount
                ownChunks[own] = MGMeshChunks(mesh)
            }
            let hRel = eyeRel * (1 - f.t)
            var left = budget - used
            let near = ownChunks[own]!.nearer(ownRel.toLocal.apply(hRel), than: mgPrecision(hRel), budget: &left)
            used = budget - max(0, left)
            switch near {
            case .nearer: return nil
            case .unknown: over = true; return (.untested, nil)
            case .notNearer: break
            }
        }
        return (.occluded, f.id)
    }
}

/// The anchor the check report suggests for a label or pointer with an off or hidden issue, or why it has none.
public struct MGAnnotationAnchorSuggestion: Equatable, Sendable {
    /// Why no anchor was found.
    public enum Cause: String, Equatable, Sendable {
        /// The part is hidden in a view that shows the annotation (`step`/`beat` names it).
        case hidden
        /// The part is ghosted in such a view.
        case ghosted
        /// No sampled point of the part projects inside such a view.
        case offScreen = "offscreen"
        /// Every sampled point of the part is behind another part in such a view (`by`: the part in the way of the
        /// nearest sample).
        case occluded
        /// Each view shows some point of the part, but no sampled point passes in every view together.
        case noCommonPoint = "nocommonpoint"
        /// The suggestion budget ran out before a candidate passed (`MGAnnotationAnchorRules.suggestTests`,
        /// `suggestDocumentTests`).
        case budget
        /// Every visible point needs an offset outside the anchor syntax's ±4000 mm (`MGSolidLimits.coordinate`) and
        /// the part's centre is not visible, or the document with the suggestion applied does not compile.
        case form
        /// The suggestion did not hold once applied: the document with it, framed again, still shows an issue for the
        /// annotation, and a new search in that framing did not settle within the re-checks
        /// (`MGAnnotationAnchorRules.recheckRounds`).
        case framing
        /// Every anchor tried for this annotation conflicts with another annotation (`other`) once applied: it gives
        /// `other`, which had no issue, an issue, or `other`'s suggestion keeps giving this one an issue (the framing
        /// changes).
        case conflict
    }
    /// The named part (the resolved part id; a component anchor name gives its part).
    public let part: String
    /// The anchor offset in the part's own frame (mm, rounded to 0.001 mm, exactly as the report prints it); nil when
    /// no candidate passed.
    public let offset: MGVec3?
    /// True when the offset lies on the cut face of a view that cuts the part.
    public let onCut: Bool
    /// True when the anchor is the part's centre: `anchorJSON` is `{"part", "point": "centre"}` (`offset` holds that
    /// centre in the part's frame, unrounded).
    public internal(set) var centre = false
    /// Why there is no offset (nil when there is one).
    public let cause: Cause?
    /// The 0-based step and beat of the view at fault (`hidden`, `ghosted`, `offScreen`, `occluded`).
    public let step: Int?, beat: Int?
    /// `occluded`: the part in the way.
    public let by: String?
    /// Candidates checked against the rules before the search gave up (0 with an offset).
    public internal(set) var samples = 0
    /// `conflict`: the annotation that the suggestion would give an issue.
    public internal(set) var other: String? = nil

    /// `{"part": p, "offset": [x, y, z]}` (or `{"part": p, "point": "centre"}`): the anchor, in the form a document
    /// writes it and the parser accepts (every offset coordinate within ±4000 mm).
    public var anchorJSON: MGJSON? {
        guard let o = offset else { return nil }
        if centre { return .object(["part": .string(part), "point": .string("centre")]) }
        return .object(["part": .string(part), "offset": .array([o.x, o.y, o.z].map { .number($0) })])
    }

    /// The view at fault as the author numbers it: `beat N` in an explainer, else `step N` (1-based).
    var viewName: String? {
        if let b = beat { return "beat \(b + 1)" }
        if let s = step { return "step \(s + 1)" }
        return nil
    }

    /// The cause as a short phrase: `part fully hidden in step 6`, `part hidden in beat 4`, … (nil with an offset).
    public var causeText: String? {
        guard let cause else { return nil }
        let w = viewName.map { " in \($0)" } ?? ""
        switch cause {
        case .hidden: return "part hidden\(w)"
        case .ghosted: return "part ghosted\(w)"
        case .offScreen: return "part off screen\(w)"
        case .occluded: return "part fully hidden\(w)"
        case .noCommonPoint: return "no point of the part is visible in every view that shows it"
        case .budget: return "suggestion budget ran out"
        case .form: return "no visible point of the part can be written as an anchor"
        case .framing: return "no anchor stays visible once the framing changes"
        case .conflict: return "every anchor tried conflicts with \(other ?? "another annotation") once applied"
        }
    }

    /// What the author can do instead when there is no offset, one sentence each.
    public func alternatives(id: String) -> [String] {
        guard let cause else { return [] }
        let w = viewName ?? "that view"
        let list = beat != nil ? "view.annotate" : "annotate"
        let blocker = by.map { "`\($0)`" } ?? "the part in the way"
        switch cause {
        case .hidden:
            return ["Leave \(id) out of \(w)'s \(list) list.", "Show `\(part)` in \(w).", "Anchor \(id) on a part \(w) shows."]
        case .ghosted:
            return ["Leave \(id) out of \(w)'s \(list) list.", "Do not ghost `\(part)` in \(w).", "Change \(w)'s camera."]
        case .offScreen:
            return ["Leave \(id) out of \(w)'s \(list) list.", "Change \(w)'s camera so `\(part)` is framed."]
        case .occluded:
            return ["Leave \(id) out of \(w)'s \(list) list.", "Ghost \(blocker) in \(w).", "Change \(w)'s camera."]
        case .noCommonPoint:
            return ["Show \(id) in fewer views.", "Use one label per view.", "Change a camera."]
        case .budget:
            return ["Use simpler parts near the anchor.", "Use fewer labels and pointers."]
        case .form:
            return ["Anchor \(id) on a part whose frame is near its mesh.", "Use a {\"world\": [x, y, z]} anchor for free text."]
        case .framing:
            return ["Leave \(id) out of the views that hide it.", "Set the camera of those views.", "Ghost the part in the way."]
        case .conflict:
            let o = other ?? "the other annotation"
            return ["Show \(id) and \(o) in different views.", "Move \(o) as well.", "Set the camera of the view that shows both."]
        }
    }

    /// `{"cause", "code", "step", "beat", "by", "other", "samples", "alternatives"}` (step and beat 1-based) for a suggestion
    /// without an offset. `samples` is the number of candidates checked: "fully hidden" means none of them passed.
    func noneJSON(id: String) -> MGJSON {
        func n(_ i: Int?) -> MGJSON { i.map { .number(Double($0 + 1)) } ?? .null }
        return .object(["cause": .string(causeText ?? ""), "code": .string(cause?.rawValue ?? ""), "step": n(step), "beat": n(beat),
                        "by": by.map(MGJSON.string) ?? .null, "other": other.map(MGJSON.string) ?? .null, "samples": .number(Double(samples)),
                        "alternatives": .array(alternatives(id: id).map(MGJSON.string))])
    }
}

extension MGAnnotationAnchorRules {
    /// Tests one search for one annotation may spend (`MGSolidDocument.anchorSuggestions`): each triangle read for the
    /// samples, each ray–triangle test of the casts, and each triangle test the rule checks spend (the view rule's own
    /// count, the nearer-part tests) cost 1. Over it, the suggestion has cause `budget`. An annotation is searched at
    /// most `1 + retries` times in one report.
    public static let suggestTests = 8_000_000
    /// Tests all searches of one report may spend together, retries included (`MGSuggestionBudget`).
    public static let suggestDocumentTests = 64_000_000
    /// Searches again for one annotation after its first search, at most: its suggestion still had an issue in the
    /// re-check, or it gave another annotation an issue.
    public static let retries = 2
    /// Sample points per view: the triangles nearest to the authored anchor, triangles spread over the mesh, cap
    /// triangles of a cut part, and the part's box centre.
    public static let nearSamples = 24, spreadSamples = 24, capSamples = 16
    /// Rays per side of the grid each view casts across its part: a square grid of `grid` × `grid` rays from the camera,
    /// spanning the part's box diagonal in the plane through the box centre facing the camera.
    public static let grid = 12
    /// Triangle centroids the second, denser pass samples per view (all triangles of a smaller mesh).
    public static let denseSpread = 512
    /// How far (mm) a candidate moves past the hit, into its part, before it is rounded and checked.
    public static let inset = 0.05
}

/// The search budget one report shares between its suggestion searches, retries included.
final class MGSuggestionBudget {
    var left: Int
    init(_ tests: Int = MGAnnotationAnchorRules.suggestDocumentTests) { left = tests }
}

extension MGSolidDocument {
    /// The suggestion for every annotation that `issues` names with an off or hidden issue (`offPart`, `hidden`,
    /// `ghosted`, `offScreen`, `occluded`), by annotation id. `views` are the framed views the view rule tested (every
    /// step still, or every explainer beat still); the off-part rule uses the document's own views (`shownPoses`).
    ///
    /// For each such annotation, in issue order:
    /// 1. The views that show it (`checkedAnnotations`), in order. For each, sample points of its part's mesh as that
    ///    view draws it (a cut part's cut mesh): the `nearSamples` triangles nearest to the authored anchor (their
    ///    nearest points), `spreadSamples` triangle centroids spread evenly over the mesh, `capSamples` centroids of a
    ///    cut's cap triangles, and the box centre; and a `grid` × `grid` square of rays across the part as the camera
    ///    sees it (spanning its box diagonal, in the plane through the box centre that faces the camera). A ray from the
    ///    view's camera through each sample (to just past it) gives the first hit on the part; the candidate is that hit
    ///    moved `inset` mm further along the ray, into the part. A cap sample is also a candidate itself (moved `inset`
    ///    mm to the kept side). An annotation no view shows
    ///    takes the samples' nearest points, moved `inset` mm inward toward the box centre.
    /// 2. Candidates are rounded to 0.001 mm in the part's frame and sorted: on a cut face first when a view cuts the
    ///    part, then by distance to the authored anchor, then by generation order.
    /// 3. The first candidate that passes the view rule (`MGAnchorViewRule.test`) in every view that shows the
    ///    annotation, and then the off-part rule (`offPartIssue`), is the suggestion. A screen with the rule's own
    ///    segment test through runs of 64 triangles runs first; it can only drop a candidate, never pass one.
    /// 4. When none passes, a second pass adds denser samples (twice the nearest triangles and cap centroids, up to
    ///    `denseSpread` centroids, a grid twice as fine) and checks only the new candidates.
    /// 5. Else the first view where no candidate passes on its own names the cause (the most frequent cause there,
    ///    ties in the order hidden, ghosted, off screen, occluded); when every view passes some candidate, the cause is
    ///    `noCommonPoint`. When the budget runs out first, the cause is `budget`.
    /// A world anchor has no part and gets no suggestion.
    public func anchorSuggestions(for issues: [MGAnnotationAnchorIssue], views: [MGAnnotationAnchorView]) -> [String: MGAnnotationAnchorSuggestion] {
        anchorSuggestions(for: issues, views: views, scale: 1)
    }

    /// `anchorSuggestions` with `scale` times the samples and the budgets (tests: a denser search).
    func anchorSuggestions(for issues: [MGAnnotationAnchorIssue], views: [MGAnnotationAnchorView], scale: Int,
                           shared: MGSuggestionBudget? = nil) -> [String: MGAnnotationAnchorSuggestion] {
        let wanted: Set<MGAnnotationAnchorIssue.Cause> = [.offPart, .hidden, .ghosted, .offScreen, .occluded]
        var ids: [String] = []
        for i in issues where wanted.contains(i.cause) && !ids.contains(i.id) { ids.append(i.id) }
        return anchorSuggestions(ids: ids, views: views, scale: scale, shared: shared ?? MGSuggestionBudget(MGAnnotationAnchorRules.suggestDocumentTests * max(1, scale)))
    }

    /// The suggestion for each annotation `ids` names, in that order, from `shared`. `excluding` gives, per annotation,
    /// anchors (in its part's frame) already found to give another annotation an issue: no candidate within
    /// `max(1 mm, 10 % of the part's box diagonal)` of one is used.
    func anchorSuggestions(ids: [String], views: [MGAnnotationAnchorView], scale: Int = 1, shared: MGSuggestionBudget,
                           excluding: [String: [MGVec3]] = [:]) -> [String: MGAnnotationAnchorSuggestion] {
        let k = max(1, scale)
        guard !ids.isEmpty else { return [:] }
        var rules = views.map { MGAnchorViewRule(self, $0) }
        var shownBy: [[String]] = views.map { checkedAnnotations($0.view, params: $0.params) ?? [] }
        if shownBy.count != rules.count { shownBy = Array(repeating: [], count: rules.count) }
        var out: [String: MGAnnotationAnchorSuggestion] = [:]
        for id in ids {
            guard let (kind, p) = annotations.checkedAnchor(id), let partID = p.part else { continue }
            let mine = rules.indices.filter { shownBy[$0].contains(id) }
            var budget = min(shared.left, MGAnnotationAnchorRules.suggestTests * k)
            let start = budget
            out[id] = suggestion(id: id, kind: kind, p, partID: partID, rules: &rules, views: mine, budget: &budget, scale: k,
                                 excluding: excluding[id] ?? [])
            shared.left -= start - max(0, budget)
        }
        return out
    }

    func suggestion(id: String, kind: String, _ p: MGAnnotationPoint, partID: String, rules: inout [MGAnchorViewRule], views mine: [Int],
                    budget: inout Int, scale: Int = 1, excluding: [MGVec3] = []) -> MGAnnotationAnchorSuggestion {
        var tested = 0
        func none(_ c: MGAnnotationAnchorSuggestion.Cause, _ k: Int? = nil, by: String? = nil) -> MGAnnotationAnchorSuggestion {
            var s = MGAnnotationAnchorSuggestion(part: partID, offset: nil, onCut: false, cause: c, step: k.flatMap { rules[$0].v.step },
                                                 beat: k.flatMap { rules[$0].v.beat }, by: by)
            s.samples = tested
            return s
        }
        guard let part = assembly.part(partID), !part.mesh.bounds.isEmpty else { return none(.budget) }
        let authored = p.local
        let R = MGAnnotationAnchorRules.self
        struct Candidate { let local: MGVec3; let onCut: Bool; let order: Int; var centre = false }
        var cands: [Candidate] = []
        var seen = Set<[Double]>()
        func spend(_ n: Int) -> Bool { budget -= n; return budget >= 0 }
        // Runs of 64 triangles per mesh as a view draws it (built once, `n` tests), for the search's own ray tests.
        var runs: [String: MGMeshChunks] = [:]
        func chunks(_ key: String, _ mesh: MGMesh) -> MGMeshChunks? {
            if let c = runs[key] { return c }
            guard spend(mesh.triangleCount) else { return nil }
            let c = MGMeshChunks(mesh); runs[key] = c; return c
        }
        /// The first hit on a mesh along `a → b`, through its runs; nil `ok` when the budget ran out.
        func hit(_ key: String, _ mesh: MGMesh, _ a: MGVec3, _ b: MGVec3, before: Double) -> (t: Double?, ok: Bool) {
            guard let c = chunks(key, mesh) else { return (nil, false) }
            return c.firstHit(a, b, after: 1e-9, before: before, budget: &budget)
        }
        func rounded(_ v: MGVec3) -> MGVec3 { MGVec3((v.x * 1000).rounded() / 1000, (v.y * 1000).rounded() / 1000, (v.z * 1000).rounded() / 1000) }
        // Only a point the anchor syntax can write is a candidate: every offset coordinate within ±4000 mm.
        var far: [MGVec3] = []
        // Anchors that gave another annotation an issue, and the points near them, are not used again.
        let keepOff = max(1, 0.1 * part.mesh.bounds.size.length)
        func excluded(_ v: MGVec3) -> Bool { excluding.contains { ($0 - v).length < keepOff } }
        func add(_ v: MGVec3, onCut: Bool) {
            let r = rounded(v)
            guard [r.x, r.y, r.z].allSatisfy(\.isFinite), !excluded(r) else { return }
            guard [r.x, r.y, r.z].allSatisfy({ MGSolidLimits.coordinate.contains($0) }) else { if far.count < 64 { far.append(r) }; return }
            guard seen.insert([r.x, r.y, r.z]).inserted else { return }
            cands.append(Candidate(local: r, onCut: onCut, order: cands.count))
        }
        // The part's centre is always writable (`{"point": "centre"}`), whatever its coordinates.
        if !excluded(part.mesh.bounds.center) { cands.append(Candidate(local: part.mesh.bounds.center, onCut: false, order: 0, centre: true)) }
        // The sample points of one mesh (in the part's frame): nearest points of the `near` triangles nearest to the
        // authored anchor, `spread` centroids spread evenly over the triangles, `caps` cap centroids, the box centre.
        func samples(_ mesh: MGMesh, cut: MGSectionCut?, near nearCount: Int, spread spreadCount: Int, caps capCount: Int) -> [(point: MGVec3, cap: Bool)]? {
            let n = mesh.triangleCount, pos = mesh.positions
            guard n > 0 else { return [] }
            guard spend(n) else { return nil }
            var near: [(d: Double, i: Int, q: MGVec3)] = []
            near.reserveCapacity(n)
            for i in 0..<n {
                let (i0, i1, i2) = mesh.triangle(i)
                guard i0 < pos.count, i1 < pos.count, i2 < pos.count else { continue }
                let q = mgClosestOnTriangle(authored, pos[i0], pos[i1], pos[i2])
                let d = (q - authored).length
                guard d.isFinite else { continue }
                near.append((d, i, q))
            }
            near.sort { $0.d != $1.d ? $0.d < $1.d : $0.i < $1.i }
            var out: [(MGVec3, Bool)] = near.prefix(nearCount).map { ($0.q, false) }
            func centroid(_ i: Int) -> MGVec3? {
                let (i0, i1, i2) = mesh.triangle(i)
                guard i0 < pos.count, i1 < pos.count, i2 < pos.count else { return nil }
                return (pos[i0] + pos[i1] + pos[i2]) * (1.0 / 3)
            }
            let spread = min(n, spreadCount)
            for k in 0..<spread { if let c = centroid(k * n / spread) { out.append((c, false)) } }
            if let cut, cut.capTriangleCount > 0 {
                let first = max(0, min(cut.capFirstTriangle, n)), count = max(0, min(cut.capTriangleCount, n - first))
                let m = min(count, capCount)
                for k in 0..<m { if let c = centroid(first + k * count / m) { out.append((c, true)) } }
            }
            out.append((mesh.bounds.center, false))
            return out
        }
        /// Adds the candidates of every view that shows the annotation; false when the budget ran out.
        func generate(near: Int, spread: Int, caps: Int, grid g: Int) -> Bool {
            if mine.isEmpty {
                // An annotation no view shows: only the off-part rule applies; take points of its own mesh, moved inward.
                guard let s = samples(part.mesh, cut: nil, near: near, spread: spread, caps: 0) else { return false }
                let c = part.mesh.bounds.center
                for q in s {
                    let d = c - q.point, l = d.length
                    add(l > R.inset ? q.point + d * (R.inset / l) : q.point, onCut: false)
                }
                return true
            }
            for k in mine {
                let rule = rules[k]
                let pv = rule.v.view.part(partID)
                if pv.hidden { continue }
                let mesh = pv.cut?.mesh ?? part.mesh
                let t = rule.pose.world[partID] ?? .identity
                let eyeL = t.inverse.apply(rule.eye)
                func cast(_ far: MGVec3) -> Bool {
                    let r = hit("\(k)", mesh, eyeL, far, before: 1)
                    guard r.ok else { return false }
                    guard let t = r.t else { return true }
                    let h = eyeL + (far - eyeL) * t + (far - eyeL).normalized * R.inset
                    add(h, onCut: pv.cut.map { abs($0.plane.distance(h)) <= R.inset + 0.01 } ?? false)
                    return true
                }
                // A grid of rays across the part as the camera sees it: it finds slivers that object-space samples miss.
                let c = mesh.bounds.center, toC = c - eyeL, dl = toC.length
                if g > 0, dl > 1e-9, dl.isFinite {
                    let fwd = toC * (1 / dl)
                    var right = fwd.cross(t.inverse.applyVector(MGVec3(0, 0, 1)))
                    if right.length < 1e-6 { right = fwd.cross(t.inverse.applyVector(MGVec3(1, 0, 0))) }
                    right = right.normalized
                    let up = right.cross(fwd), ext = mesh.bounds.size.length / 2
                    for i in 0..<g {
                        for j in 0..<g {
                            let u = -1 + (2 * Double(i) + 1) / Double(g), w = -1 + (2 * Double(j) + 1) / Double(g)
                            let dir = c + right * (u * ext) + up * (w * ext) - eyeL, along = dir.dot(fwd)
                            guard along > 1e-9 else { continue }
                            guard cast(eyeL + dir * ((dl + ext + 1) / along)) else { return false }
                        }
                    }
                }
                guard let s = samples(mesh, cut: pv.cut, near: near, spread: spread, caps: caps) else { return false }
                for q in s {
                    let dir = q.point - eyeL
                    let len = dir.length
                    guard len > 1e-9, len.isFinite else { continue }
                    guard cast(eyeL + dir * (1 + 1e-5) + dir * (1e-3 / len)) else { return false }
                    if q.cap, let cut = pv.cut {
                        let nrm = cut.plane.normal, l = nrm.length
                        add(l > 0 ? q.point - nrm * (R.inset / l) : q.point, onCut: true)
                    }
                }
            }
            return true
        }
        let cutPreferred = mine.contains { rules[$0].v.view.part(partID).cut != nil }
        func ordered(_ list: ArraySlice<Candidate>) -> [Int] {
            return list.indices.sorted { ia, ib in
                let a = cands[ia], b = cands[ib]
                if cutPreferred, a.onCut != b.onCut { return a.onCut }
                let da = (a.local - authored).length, db = (b.local - authored).length
                return da != db ? da < db : a.order < b.order
            }
        }
        func point(_ c: Candidate) -> MGAnnotationPoint {
            MGAnnotationPoint(anchor: c.centre ? .centre(part: partID) : .offset(part: partID, c.local), local: c.local)
        }
        // Each (candidate, view) is tested once: the diagnosis reuses the results. Before the full rule, a candidate is
        // screened with the rule's own segment test through runs of 64 triangles (`MGMeshChunks.firstHit`, the same
        // crossings): when another part is crossed before the own part, it is occluded (a coincident-surface tie is
        // left out, so the screen can only miss a candidate, never pass one). Only a candidate that passes the screen
        // goes to the full rule, which decides.
        enum Outcome { case pass, fail(MGAnnotationAnchorIssue.Cause, String?) }
        var memo: [Int: Outcome] = [:]
        // Per view, once: each blocking part's world box and inverse placement, and the parts the cut exception would
        // exempt (the containment test does not depend on the anchor; only the condition that the anchor lies in its cut
        // part's box on the kept side does).
        struct Screen { let boxes: [MGBounds]; let inverses: [MGTransform]; let exempt: Set<String> }
        var screens: [Int: Screen] = [:]
        func screen(_ k: Int) -> Screen {
            if let s = screens[k] { return s }
            let rule = rules[k]
            var exempt = Set<String>()
            if rule.v.view.part(partID).cut != nil, let box = assembly.part(partID)?.mesh.bounds {
                let ownInv = (rule.pose.world[partID] ?? .identity).inverse, g = rule.grow
                for q in assembly.parts where q.id != partID && !q.mesh.bounds.isEmpty {
                    let tq = rule.pose.world[q.id] ?? .identity
                    if q.mesh.bounds.corners.allSatisfy({ c in
                        let l = ownInv.apply(tq.apply(c))
                        return l.x >= box.min.x - g && l.x <= box.max.x + g && l.y >= box.min.y - g && l.y <= box.max.y + g
                            && l.z >= box.min.z - g && l.z <= box.max.z + g
                    }) { exempt.insert(q.id) }
                }
            }
            let s = Screen(boxes: rule.solids.map { MGSolidFrames.worldBounds($0.mesh.bounds, $0.world) }, inverses: rule.solids.map { $0.world.inverse },
                           exempt: exempt)
            screens[k] = s
            return s
        }
        func screened(_ ci: Int, _ k: Int) -> String? {
            let rule = rules[k]
            guard let ownPart = assembly.part(partID) else { return nil }
            let q = point(cands[ci]), x = q.world(rule.pose)
            // Only an occlusion is screened: a hidden, ghosted or off-screen candidate goes to the full rule.
            let pv = rule.v.view.part(partID)
            guard !pv.hidden, pv.opacity >= MGSolidView.clamp(opacity: ownPart.opacity) - 1e-9,
                  let sp = rule.proj.project(rule.v.stage.apply(x)), sp.x >= 0, sp.x <= rule.v.width, sp.y >= 0, sp.y <= rule.v.height else { return nil }
            let eye = rule.eye, d = x - eye, len = d.length
            guard len > 1e-6, len.isFinite else { return nil }
            let before = 1 - mgPrecision(.zero) / len
            let sc = screen(k)
            var exempt = Set<String>()
            if let cut = pv.cut {
                let lo = q.local
                if mgBoxDistance(lo, ownPart.mesh.bounds) <= mgPrecision(.zero), cut.plane.distance(lo) <= mgPrecision(.zero) { exempt = sc.exempt }
            }
            // The rule's segment test, through runs of 64 triangles: the own part's first crossing, then the first other
            // part that crosses before it.
            var tOwn: Double?
            if let i = rule.solids.firstIndex(where: { $0.id == partID }), mgSegmentMeetsBox(eye, d, sc.boxes[i]) {
                let inv = sc.inverses[i]
                let o = hit("\(k):\(partID)", rule.solids[i].mesh, inv.apply(eye), inv.apply(x), before: before)
                guard o.ok else { return nil }
                tOwn = o.t
            }
            for (i, sld) in rule.solids.enumerated() where sld.id != partID && !exempt.contains(sld.id) {
                budget -= 1
                guard budget >= 0 else { return nil }
                guard mgSegmentMeetsBox(eye, d, sc.boxes[i]) else { continue }
                let inv = sc.inverses[i]
                let r = hit("\(k):\(sld.id)", sld.mesh, inv.apply(eye), inv.apply(x), before: min(before, tOwn ?? before))
                guard r.ok else { return nil }
                if let tb = r.t, tb < (tOwn ?? 2) { return sld.id }
            }
            return nil
        }
        func viewTest(_ ci: Int, _ k: Int) -> (MGAnnotationAnchorIssue.Cause, String?)? {
            let key = ci * max(1, rules.count) + k
            if let m = memo[key] { if case .fail(let c, let b) = m { return (c, b) }; return nil }
            if let b = screened(ci, k) { memo[key] = .fail(.occluded, b); return (.occluded, b) }
            var used = 0, over = false
            let cap = max(0, min(budget, R.tests))
            let r = rules[k].test(point(cands[ci]), used: &used, over: &over, budget: cap)
            budget -= used
            memo[key] = r.map { .fail($0.0, $0.1) } ?? .pass
            return r
        }
        var off = MGOffPartState(budget: 0)
        // Views are tried hardest first (most failures so far, then view order), so a candidate fails fast where most fail.
        var fails: [Int: Int] = [:]
        /// The first candidate in `range` (in order) that passes everywhere, or a refusal cause (`budget`).
        func search(_ range: Range<Int>) -> MGAnnotationAnchorSuggestion? {
            for ci in ordered(cands[range]) {
                guard budget > 0 else { return none(.budget) }
                tested += 1
                let c = cands[ci], q = point(c)
                var ok = true
                for k in mine.sorted(by: { (fails[$0] ?? 0, -$0) > (fails[$1] ?? 0, -$1) }) {
                    if let r = viewTest(ci, k) {
                        ok = false
                        fails[k, default: 0] += 1
                        if r.0 == .untested { return none(.budget) }
                        break
                    }
                }
                guard ok else { continue }
                // The off-part rule, for a candidate every view shows (a point inside its part's box always passes it).
                off.budget = max(0, min(budget, R.surfaceTests))
                let before = off.budget
                let offIssue = offPartIssue(id: id, kind: kind, q, state: &off)
                budget -= before - max(0, off.budget)
                if offIssue != nil { continue }
                var found = MGAnnotationAnchorSuggestion(part: partID, offset: c.local, onCut: c.onCut, cause: nil, step: nil, beat: nil, by: nil)
                found.centre = c.centre
                return found
            }
            return nil
        }
        // Pass 1: the samples above. Pass 2, only when pass 1 finds none: denser samples (twice the nearest triangles and
        // cap centroids, up to `denseSpread` centroids, a grid twice as fine); only the new candidates are checked.
        guard generate(near: R.nearSamples * scale, spread: R.spreadSamples * scale, caps: R.capSamples * scale, grid: R.grid * min(scale, 3)) else {
            return none(.budget)
        }
        if let found = search(0..<cands.count) { return found }
        let first = cands.count
        guard generate(near: 2 * R.nearSamples * scale, spread: R.denseSpread * scale, caps: 2 * R.capSamples * scale, grid: 2 * R.grid * min(scale, 3)) else {
            return none(.budget)
        }
        if let found = search(first..<cands.count) { return found }
        // Points the syntax cannot write: when one of them would pass, the cause is the form, not the views.
        for x in far {
            guard budget > 0 else { return none(.budget) }
            let q = MGAnnotationPoint(anchor: .offset(part: partID, x), local: x)
            var passes = true
            for k in mine {
                var used = 0, over = false
                let r = rules[k].test(q, used: &used, over: &over, budget: max(0, min(budget, R.tests)))
                budget -= used
                if r != nil { passes = false; break }
            }
            if passes { return none(.form) }
        }
        // No candidate passes everywhere: find the first view where none passes on its own.
        for k in mine {
            if rules[k].v.view.part(partID).hidden { return none(.hidden, k) }
            var counts: [MGAnnotationAnchorIssue.Cause: Int] = [:]
            var firstBy: String?
            var passed = false
            for ci in cands.indices {
                guard budget > 0 else { return none(.budget) }
                guard let r = viewTest(ci, k) else { passed = true; break }
                if r.0 == .untested { return none(.budget) }
                counts[r.0, default: 0] += 1
                if r.0 == .occluded, firstBy == nil { firstBy = r.1 }
            }
            if passed { continue }
            let order: [(MGAnnotationAnchorIssue.Cause, MGAnnotationAnchorSuggestion.Cause)] = [(.hidden, .hidden), (.ghosted, .ghosted),
                                                                                                 (.offScreen, .offScreen), (.occluded, .occluded)]
            var best = order[3], most = -1
            for o in order where counts[o.0, default: 0] > most { best = o; most = counts[o.0, default: 0] }
            return none(best.1, k, by: best.1 == .occluded ? firstBy : nil)
        }
        return none(cands.isEmpty ? .occluded : .noCommonPoint, cands.isEmpty ? mine.first : nil)
    }

    /// The anchor source of `id` with `anchor` in place: the label's `at` or the pointer's `to`, in a copy of
    /// `source` (an assembly, or an explainer's solid object). Unchanged when `source` has no such annotation.
    static func replacingAnchors(_ source: MGJSON, _ anchors: [String: MGJSON]) -> MGJSON {
        guard case .object(var o) = source, case .object(var ann)? = o["annotations"] else { return source }
        for (key, field) in [("labels", "at"), ("arrows", "to")] {
            guard case .array(let list)? = ann[key] else { continue }
            ann[key] = .array(list.map { e in
                guard case .object(var eo) = e, case .string(let id)? = eo["id"], let a = anchors[id] else { return e }
                eo[field] = a
                return .object(eo)
            })
        }
        o["annotations"] = .object(ann)
        return .object(o)
    }
}

/// One full re-check of a document with suggested anchors applied (`MGSolidReport`, `MGExplainerReport`): the copy's
/// anchor issues (off part and every framed view, with the copy's own framing), the annotations each framed view shows,
/// and a search in that framing.
struct MGAnchorRecheck {
    let issues: [MGAnnotationAnchorIssue]
    /// Per framed view: its step and beat (0-based) and the annotations it shows.
    var shown: [(step: Int?, beat: Int?, ids: Set<String>)] = []
    /// A search for these annotations in the copy's framing, avoiding the given anchors.
    let search: (_ ids: [String], _ excluding: [String: [MGVec3]]) -> [String: MGAnnotationAnchorSuggestion]
}

extension MGAnnotationAnchorRules {
    /// Full re-checks of the document with the suggestions applied, at most (`MGAnnotationAnchorReport.verify`).
    public static let recheckRounds = 6
}

extension MGAnnotationAnchorReport {
    /// Keeps only suggestions that hold once applied. Framing depends on the anchors a view shows, so a suggestion found
    /// with the authored framing can be hidden in the framing it causes, or can hide another annotation. With every
    /// suggestion applied to a copy of the document, `recheck` compiles and frames it again and returns its anchor
    /// issues (nil when the copy is refused). A set is accepted only when that check shows no issue for any suggested
    /// annotation and no issue for any annotation that had none in this report (`issues`). Otherwise, at most
    /// `MGAnnotationAnchorRules.recheckRounds` re-checks in all:
    /// - a suggestion whose annotation still has an issue is searched again in the copy's framing, at most
    ///   `MGAnnotationAnchorRules.retries` times, then dropped (`framing`);
    /// - an annotation that had no issue and now has one names the suggestions shown in the same view (all of them when
    ///   none is): each is searched again away from its current anchor, at most `retries` times, then dropped
    ///   (`conflict`, `other` naming that annotation);
    /// - a suggested annotation that passed an earlier check with the same anchor and fails now was broken by another
    ///   suggestion: the first, in sorted order, of those that changed since and are shown in the same view (of those
    ///   shown with it when none changed). When it is dropped, the cause is `conflict` with `other` naming that one;
    /// - a refused copy drops every suggestion of that set (`form`).
    /// When the re-checks run out before a set is accepted, every remaining suggestion is dropped (`framing`). So a
    /// printed set of suggestions, applied together, parses, clears every suggested annotation and adds no issue.
    mutating func verify(_ recheck: ([String: MGJSON]) -> MGAnchorRecheck?) {
        let before = Set(issues.map(\.id))
        var current: [String: MGAnnotationAnchorSuggestion] = [:]
        for i in issues { if let s = i.suggestion, current[i.id] == nil { current[i.id] = s } }
        var retries: [String: Int] = [:]
        var excluding: [String: [MGVec3]] = [:]
        // The other suggestion an annotation's issue was first attributed to (fixed order: sorted ids), kept across
        // re-checks; and the applied set of the last check each suggested annotation passed.
        var conflictWith: [String: String] = [:]
        var passedIn: [String: [String: MGJSON]] = [:]
        func applied() -> [String: MGJSON] { current.compactMapValues { $0.anchorJSON } }
        func drop(_ ids: [String], _ cause: MGAnnotationAnchorSuggestion.Cause) {
            for id in ids {
                guard let s = current[id], s.offset != nil else { continue }
                // Dropped for its issue: a conflict when another suggestion caused it, else the framing.
                let other = cause == .form ? nil : conflictWith[id]
                var n = MGAnnotationAnchorSuggestion(part: s.part, offset: nil, onCut: false, cause: other != nil ? .conflict : cause,
                                                     step: nil, beat: nil, by: nil)
                n.other = other
                current[id] = n
            }
        }
        var accepted = false
        for _ in 0..<MGAnnotationAnchorRules.recheckRounds {
            let set = applied()
            if set.isEmpty { accepted = true; break }
            guard let r = recheck(set) else { drop(set.keys.sorted(), .form); continue }
            let suggested = set.keys.sorted()
            let bad = suggested.filter { id in r.issues.contains { $0.id == id } }
            for id in suggested where !bad.contains(id) { passedIn[id] = set }
            var fresh: [(id: String, issue: MGAnnotationAnchorIssue)] = []
            for i in r.issues where !before.contains(i.id) && !set.keys.contains(i.id) && !fresh.contains(where: { $0.id == i.id }) {
                fresh.append((i.id, i))
            }
            if bad.isEmpty && fresh.isEmpty { accepted = true; break }
            func shownWith(_ i: MGAnnotationAnchorIssue) -> Set<String> {
                Set(r.shown.filter { $0.step == i.step && $0.beat == i.beat }.flatMap(\.ids))
            }
            // The suggestions to search again: those still failing, and those shown with a newly failing annotation.
            var again: [String] = []
            for id in bad where !again.contains(id) {
                again.append(id)
                // A suggested annotation that passed with this same anchor, and fails now, was broken by the other
                // suggestions that changed since (those shown in the same view; all others shown with it when none
                // changed): the first of them in sorted order is the conflict.
                guard conflictWith[id] == nil, let last = passedIn[id], last[id] == set[id],
                      let i = r.issues.first(where: { $0.id == id }) else { continue }
                let inView = shownWith(i)
                let others = suggested.filter { $0 != id && (inView.isEmpty || inView.contains($0)) }
                let changed = others.filter { last[$0] != set[$0] }
                if let o = (changed.isEmpty ? others : changed).first { conflictWith[id] = o }
            }
            var blamed = Set<String>()
            for (other, i) in fresh.sorted(by: { $0.id < $1.id }) {
                let inView = shownWith(i)
                var suspects = suggested.filter { inView.contains($0) }
                if suspects.isEmpty { suspects = suggested }
                for id in suspects where blamed.insert(id).inserted {
                    if conflictWith[id] == nil { conflictWith[id] = other }
                    if let x = current[id]?.offset { excluding[id, default: []].append(x) }
                    if !again.contains(id) { again.append(id) }
                }
            }
            var search: [String] = []
            for id in again {
                if retries[id, default: 0] >= MGAnnotationAnchorRules.retries {
                    drop([id], .framing)
                } else {
                    retries[id, default: 0] += 1
                    search.append(id)
                }
            }
            guard !search.isEmpty else { continue }
            let found = r.search(search, excluding)
            for id in search {
                if let s = found[id], s.offset != nil { current[id] = s } else { drop([id], .framing) }
            }
        }
        if !accepted { drop(applied().keys.sorted(), .framing) }
        for k in issues.indices where issues[k].suggestion != nil { issues[k].suggestion = current[issues[k].id] }
    }
}
