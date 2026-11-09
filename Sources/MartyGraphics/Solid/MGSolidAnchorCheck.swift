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
    /// An anchor may lie at most `max(partShare × the part's box diagonal, modelShare × the drawn model's box diagonal)`
    /// mm outside the box of its part's mesh, measured in the part's own frame (an oriented box), before it is off its
    /// part. The drawn model is the parts that the views showing the annotation draw (hidden parts left out), at those
    /// views' poses.
    public static let partShare = 0.05, modelShare = 0.005
    /// Triangle tests one view may spend on the line-of-sight tests. The anchor whose test would pass the budget, and
    /// every later anchor of the view, is not tested for occlusion (`untested`, `annotation.anchor.untested.<id>`): a
    /// warning in the standard profile, refused by the strict check report. The other causes are still tested.
    public static let tests = 3_000_000
    /// Tests one document may spend on the exact nearer-part search of `annotation.anchor.off.<id>`
    /// (`MGSolidDocument.offPartAnchors`): every candidate box test, every triangle read to build a part's runs, every
    /// run-box test and every triangle test costs 1. When it runs out, the anchor is `untested` (`"budget":
    /// "nearerPart"`), never off.
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
    /// The 0-based step and explainer beat of the view the issue concerns: the view that does not show the anchor, or
    /// for `offPart` and the nearer-part `untested` the view where another part is nearer (or the budget ran out). Nil
    /// for the plain view and for an `offPart` found only by the distance test (it holds in every pose).
    public let step: Int?
    public let beat: Int?
    /// The anchor point in the posed kernel world (Z up, mm) at the pose of that view; for an `offPart` found only by the
    /// distance test, at the pose of the first view that shows it (the default input with explode 0 when none does).
    public let point: MGVec3
    /// `offPart`: the distance (mm) from the anchor to its part's oriented box, and the largest distance allowed.
    public let distance: Double?
    public let tolerance: Double?
    /// `offPart`: the first other part (assembly order) found nearer to the anchor than `part`'s box, and the distance
    /// (mm) to the first of its triangles found nearer (run order). That distance is 0 when the anchor lies on that
    /// triangle (a dot on the part's face), and also 0 when no triangle is nearer and the anchor lies inside that part
    /// (watertight parity); an anchor inside a part can also report a positive distance to a face found first. Not
    /// necessarily the nearest part or distance: the search stops at the first.
    public var closer: String? = nil
    public var closerDistance: Double? = nil
    /// `untested`: the budget that ran out, `lineOfSight` (the view's, `MGAnnotationAnchorRules.tests`) or `nearerPart`
    /// (the document's, `MGAnnotationAnchorRules.surfaceTests`).
    public var budget: String? = nil
    /// The anchor the check report suggests instead (`MGSolidDocument.anchorSuggestions`), or why there is none. Set by
    /// the check reports for `offPart`, `hidden`, `ghosted`, `offScreen` and `occluded`; nil elsewhere.
    public var suggestion: MGAnnotationAnchorSuggestion? = nil

    /// The same issue for explainer beat `beat` (0-based).
    func at(beat: Int?) -> MGAnnotationAnchorIssue {
        var i = MGAnnotationAnchorIssue(id: id, kind: kind, cause: cause, part: part, by: by, step: step, beat: beat, point: point,
                                        distance: distance, tolerance: tolerance)
        i.closer = closer; i.closerDistance = closerDistance; i.budget = budget; i.suggestion = suggestion
        return i
    }

    /// `annotation.anchor.off.<id>`, `annotation.anchor.untested.<id>` or `annotation.anchor.hidden.<id>`.
    public var reason: String {
        switch cause {
        case .offPart: return "annotation.anchor.off.\(id)"
        case .untested: return "annotation.anchor.untested.\(id)"
        default: return "annotation.anchor.hidden.\(id)"
        }
    }

    /// `at` for a label, `to` for a pointer.
    var key: String { kind == "pointer" ? "to" : "at" }

    /// A repair a model can act on. With a suggestion it names the suggested anchor (or why there is none); it never
    /// proposes a point the rules were not checked to pass.
    public var fix: String {
        let what = kind == "pointer" ? "the pointer tip (`to`)" : "the anchor (`at`)"
        let p = part.map { "`\($0)`" } ?? "the world point"
        func mm(_ x: Double?) -> String { x.map { String(format: "%.1f", $0) } ?? "?" }
        if let s = suggestion, cause != .untested {
            // What is wrong in one sentence, then the suggested anchor (checked to pass) or why there is none.
            var lead = ""
            switch cause {
            case .offPart: lead = closer.map { "`\($0)` is nearer to the anchor (\(mm(closerDistance)) mm) than \(p) (\(mm(distance)) mm), so the dot lands on `\($0)`. " }
                ?? "The anchor is \(mm(distance)) mm off \(p) (at most \(mm(tolerance)) mm). "
            case .occluded: lead = "\(by.map { "`\($0)`" } ?? "Another part") hides the anchor. "
            case .hidden: lead = "\(p) is hidden in this view. "
            case .ghosted: lead = "\(p) is ghosted in this view. "
            case .offScreen: lead = "The anchor is outside the view. "
            case .untested: break
            }
            var tail = ""
            if cause == .offPart {
                tail = " For free text, use a {\"world\": [x, y, z]} anchor."
                if let c = closer { tail += " If the label names `\(c)`, anchor it on `\(c)`." }
            }
            if let a = s.anchorJSON {
                return lead + "Use \(MGAnnotationAnchorIssue.compact(a)) for \(what): it lies on \(p) and passes the anchor rules in every view that shows "
                    + "\(id)." + tail
            }
            return lead + "No point of \(p) passes in every view that shows \(id) (\(s.causeText ?? "")): "
                + MGAnnotationAnchorIssue.orList(s.alternatives(id: id)) + tail
        }
        switch cause {
        case .offPart:
            let move = "Move \(what) onto a face of \(p) that the views showing \(id) can see (an offset inside its box or within "
                + "\(mm(tolerance)) mm of it). For free text, use a {\"world\": [x, y, z]} anchor."
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
        case .untested where budget == "nearerPart":
            return "The nearer-part test ran over its budget (\(MGAnnotationAnchorRules.surfaceTests) tests per document) before this "
                + "anchor: use simpler parts near the anchors, or fewer labels and pointers."
        case .untested:
            return "This view's line-of-sight test ran over its budget (\(MGAnnotationAnchorRules.tests) triangle tests) before this "
                + "anchor: hide or ghost parts that are not needed in this view, use simpler parts, or show fewer labels in it."
        case .occluded:
            let b = by.map { "`\($0)`" } ?? "another part"
            return "\(b) hides the anchor: move \(what) to a face of \(p) that faces the camera, change the camera (camera, orbit), "
                + "or ghost \(b) in this view."
        }
    }

    /// Longest `repair` text, in Unicode scalars.
    public static let repairScalars = 400

    /// One line a tool can pass straight to a model, built from the fields above: what is wrong, where, and the anchor to
    /// use (or why there is none and what to do instead). At most `repairScalars` Unicode scalars; deterministic.
    public var repair: String {
        let who = (kind == "pointer" ? "Pointer " : "Label ") + id
        let at = beat.map { " (beat \($0 + 1))" } ?? step.map { " (step \($0 + 1))" } ?? ""
        let p = part ?? "the world point"
        func mm(_ x: Double?) -> String { x.map { String(format: "%.1f", $0) } ?? "?" }
        let problem: String
        switch cause {
        case .offPart:
            if let c = closer { problem = "lands on \(c), which is nearer than \(p)" }
            else { problem = "is \(mm(distance)) mm off \(p) (at most \(mm(tolerance)) mm)" }
        case .occluded: problem = "is hidden behind \(by ?? "another part")"
        case .hidden: problem = "is on \(p), which this view hides"
        case .ghosted: problem = "is on \(p), which this view ghosts"
        case .offScreen: problem = "is outside the view"
        case .untested: problem = budget == "nearerPart" ? "was not tested: the nearer-part budget ran out" : "was not tested: the view's triangle budget ran out"
        }
        var action: String
        if let s = suggestion, cause != .untested {
            if let a = s.anchorJSON {
                action = (kind == "pointer" ? "Use tip (`to`) " : "Use anchor ") + MGAnnotationAnchorIssue.compact(a) + "."
            } else {
                action = "No visible point: \(s.causeText ?? ""). " + MGAnnotationAnchorIssue.orList(s.alternatives(id: id))
            }
        } else {
            switch cause {
            case .untested: action = budget == "nearerPart" ? "Use simpler parts near the anchors, or fewer labels." : "Hide or ghost parts this view does not need, or show fewer labels in it."
            case .offPart: action = "Move `\(key)` onto a visible face of \(p), or use a {\"world\": [x, y, z]} anchor for free text."
            case .occluded: action = "Move `\(key)` to a face of \(p) that faces the camera, ghost \(by ?? "the part in the way"), or change the camera."
            case .hidden: action = "Show \(p) in this view, or leave \(id) out of its annotate list."
            case .ghosted: action = "Do not ghost \(p) in this view, or leave \(id) out of its annotate list."
            case .offScreen: action = "Change the camera, or move `\(key)` onto a framed part."
            }
        }
        let line = "\(who)\(at) \(problem). \(action)"
        return MGAnnotationAnchorIssue.bounded(line, MGAnnotationAnchorIssue.repairScalars)
    }

    /// `"a, b or c"` from sentences ending in a period: the first kept, the rest lower-cased after "or".
    static func orList(_ items: [String]) -> String {
        guard let first = items.first else { return "" }
        if items.count == 1 { return first }
        func bare(_ s: String) -> String { s.hasSuffix(".") ? String(s.dropLast()) : s }
        func lower(_ s: String) -> String { s.prefix(1).lowercased() + s.dropFirst() }
        var parts = [bare(first)] + items.dropFirst().dropLast().map { lower(bare($0)) }
        let last = "or " + lower(bare(items.last!))
        parts.append(last)
        return parts.joined(separator: ", ") + "."
    }

    /// `text` cut to `max` Unicode scalars (the last kept scalar becomes `…` when it is cut).
    static func bounded(_ text: String, _ max: Int) -> String {
        let one = text.replacingOccurrences(of: "\n", with: " ")
        guard one.unicodeScalars.count > max else { return one }
        var u = String.UnicodeScalarView()
        u.append(contentsOf: one.unicodeScalars.prefix(max - 1))
        u.append("…")
        return String(u)
    }

    /// A number as the repair text writes it: rounded to 0.001, without trailing zeros (`-30`, `148.25`).
    static func number(_ x: Double) -> String {
        guard x.isFinite else { return "null" }
        var s = String(format: "%.3f", (x * 1000).rounded() / 1000)
        while s.contains("."), s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s == "-0" ? "0" : s
    }

    /// One-line JSON for an anchor (`{"part": "p", "offset": [x, y, z]}`), keys in a fixed order.
    static func compact(_ v: MGJSON) -> String {
        switch v {
        case .object(let o):
            let order = ["part", "offset", "point", "world"]
            let keys = order.filter { o[$0] != nil } + o.keys.filter { !order.contains($0) }.sorted()
            return "{" + keys.map { "\"\($0)\": " + compact(o[$0]!) }.joined(separator: ", ") + "}"
        case .array(let a): return "[" + a.map(compact).joined(separator: ", ") + "]"
        case .string(let s): return "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
        case .number(let d): return number(d)
        case .bool(let b): return b ? "true" : "false"
        case .null: return "null"
        }
    }

    /// `{"id", "kind", "reason", "cause", "part", "by", "closer", "closerDistance", "budget", "step", "beat", "point",
    /// "distance", "tolerance", "fix", "suggest", "noSuggest", "repair"}`; `step` and `beat` are 1-based, absent values are
    /// null. `suggest` is the suggested anchor (`{"part", "offset"}`) and `noSuggest` says why there is none
    /// (`MGAnnotationAnchorSuggestion.noneJSON`); both are null when no suggestion was computed.
    public var json: MGJSON {
        func n(_ i: Int?) -> MGJSON { i.map { .number(Double($0 + 1)) } ?? .null }
        func d(_ x: Double?) -> MGJSON { x.flatMap { $0.isFinite ? .number(($0 * 1000).rounded() / 1000) : nil } ?? .null }
        let pt: MGJSON = [point.x, point.y, point.z].allSatisfy(\.isFinite)
            ? .array([point.x, point.y, point.z].map { .number(($0 * 1000).rounded() / 1000) }) : .null
        let s = cause == .untested ? nil : suggestion
        return .object(["id": .string(id), "kind": .string(kind), "reason": .string(reason), "cause": .string(cause.rawValue),
                        "part": part.map(MGJSON.string) ?? .null, "by": by.map(MGJSON.string) ?? .null,
                        "closer": closer.map(MGJSON.string) ?? .null, "closerDistance": d(closerDistance), "budget": budget.map(MGJSON.string) ?? .null,
                        "step": n(step), "beat": n(beat),
                        "point": pt, "distance": d(distance), "tolerance": d(tolerance), "fix": .string(fix),
                        "suggest": s?.anchorJSON ?? .null, "noSuggest": s.map { $0.offset == nil ? $0.noneJSON(id: id) : .null } ?? .null,
                        "repair": .string(repair)])
    }
}

/// The anchor issues of some views, in view order. Anchors a view's triangle budget left untested are issues with cause
/// `untested`.
public struct MGAnnotationAnchorReport: Equatable, Sendable {
    public internal(set) var issues: [MGAnnotationAnchorIssue] = []
    public init() {}

    mutating func append(_ o: MGAnnotationAnchorReport) { issues += o.issues }

    /// Sets `suggestion` on every off and hidden issue (`MGSolidDocument.anchorSuggestions` with `views`), from the
    /// report's shared search budget.
    mutating func suggest(_ doc: MGSolidDocument, views: [MGAnnotationAnchorView], budget: MGSuggestionBudget) {
        let found = doc.anchorSuggestions(for: issues, views: views, scale: 1, shared: budget)
        guard !found.isEmpty else { return }
        for i in issues.indices where issues[i].cause != .untested { issues[i].suggestion = found[issues[i].id] }
    }

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

/// Slab test of the segment `a + t d`, 0 ≤ t ≤ 1, against a box (the test of `MGAnnotationOcclusion.segmentHits`, without
/// building arrays).
@inline(__always) func mgSegmentMeetsBox(_ a: MGVec3, _ d: MGVec3, _ box: MGBounds) -> Bool {
    guard !box.isEmpty else { return false }
    var lo = 0.0, hi = 1.0
    @inline(__always) func axis(_ o: Double, _ v: Double, _ mn: Double, _ mx: Double) -> Bool {
        if abs(v) < 1e-12 { return o >= mn && o <= mx }
        let t1 = (mn - o) / v, t2 = (mx - o) / v
        lo = max(lo, min(t1, t2)); hi = min(hi, max(t1, t2))
        return lo <= hi
    }
    return axis(a.x, d.x, box.min.x, box.max.x) && axis(a.y, d.y, box.min.y, box.max.y) && axis(a.z, d.z, box.min.z, box.max.z)
}

/// The distance (mm) from a point to a box (0 inside).
func mgBoxDistance(_ q: MGVec3, _ b: MGBounds) -> Double {
    let dx = max(0, b.min.x - q.x, q.x - b.max.x), dy = max(0, b.min.y - q.y, q.y - b.max.y), dz = max(0, b.min.z - q.z, q.z - b.max.z)
    return (dx * dx + dy * dy + dz * dz).squareRoot()
}

/// The numeric-precision epsilon (mm) at an anchor-relative point `v` (the point minus the anchor):
/// `1e-6 × max(1, |v|) + 1e-4`. Every anchor test runs in anchor-relative coordinates (`mgAnchorRelative`), so the
/// epsilon grows only with the distance from the dot, never with the world position or the size of the model: 1.01e-4
/// mm at the dot, at most 2e-4 mm within 100 mm of it, 1.1e-3 mm 1 m from it.
func mgPrecision(_ v: MGVec3) -> Double {
    let m = v.length
    return 1e-6 * max(1, m.isFinite ? m : 0) + 1e-4
}

/// For a part placed by `t` (its posed world transform) and an anchor at world point `x`: the transform from
/// anchor-relative coordinates (world minus `x`) to the part's own frame, and the transform from the part's frame to
/// anchor-relative coordinates. The anchor is subtracted from the part's translation in double precision first, so
/// both stay exact to the size of the offsets, not the world position (a model driven to 1e6 mm keeps the same
/// precision as one at the origin).
func mgAnchorRelative(_ t: MGTransform, anchor x: MGVec3) -> (toLocal: MGTransform, toRelative: MGTransform) {
    let toRelative = MGTransform(c0: t.c0, c1: t.c1, c2: t.c2, translation: t.translation - x)
    let inv = t.inverse
    let toLocal = MGTransform(c0: inv.c0, c1: inv.c1, c2: inv.c2, translation: inv.applyVector(x - t.translation))
    return (toLocal, toRelative)
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

/// A mesh split into runs of `size` consecutive triangles, each with its bounds, for exact searches that skip far runs.
/// Building it reads every triangle once.
struct MGMeshChunks {
    static let size = 64
    let mesh: MGMesh
    let bounds: [MGBounds]

    init(_ mesh: MGMesh) {
        self.mesh = mesh
        var out: [MGBounds] = []
        out.reserveCapacity(mesh.triangleCount / MGMeshChunks.size + 1)
        var start = 0
        while start < mesh.triangleCount {
            var b = MGBounds.empty
            for i in start..<min(start + MGMeshChunks.size, mesh.triangleCount) {
                let (i0, i1, i2) = mesh.triangle(i)
                for k in [i0, i1, i2] where k < mesh.positions.count { b.include(mesh.positions[k]) }
            }
            out.append(b)
            start += MGMeshChunks.size
        }
        bounds = out
    }

    /// The smallest `t` with `after < t < before` at which a triangle crosses `a + t (b − a)` (the watertight test of
    /// `MGSolidFraming.OcclusionProbe.firstHit`, the same answer), reading only runs whose box the segment meets. Each
    /// run-box test and each triangle test costs 1 from `budget`; `ok` is false when it would go below 0.
    func firstHit(_ a: MGVec3, _ b: MGVec3, after: Double, before: Double, budget: inout Int) -> (t: Double?, ok: Bool) {
        guard let ray = WatertightRay(a, b - a) else { return (nil, true) }
        let n = mesh.triangleCount, pos = mesh.positions, d = b - a
        var best: Double?
        for c in bounds.indices {
            budget -= 1
            guard budget >= 0 else { return (nil, false) }
            guard mgSegmentMeetsBox(a, d, bounds[c]) else { continue }
            for i in (c * MGMeshChunks.size)..<min((c + 1) * MGMeshChunks.size, n) {
                budget -= 1
                guard budget >= 0 else { return (nil, false) }
                let (i0, i1, i2) = mesh.triangle(i)
                guard i0 < pos.count, i1 < pos.count, i2 < pos.count else { continue }
                if let t = ray.hit(pos[i0], pos[i1], pos[i2]), t > after, t < before { best = min(best ?? t, t) }
            }
        }
        return (best, true)
    }

    /// The result of `nearer`.
    enum Near: Equatable { case nearer(Double), notNearer, unknown }

    /// Exact and budgeted: does the solid of this closed mesh come nearer than `r` to `q` (in the mesh's frame)?
    /// 1. Every run whose box is nearer than `r` is searched triangle by triangle; the first triangle nearer than `r`
    ///    answers `.nearer(its distance)`.
    /// 2. Else `q` is inside the solid when a segment from `q` along +X past the mesh box crosses its surface an odd
    ///    number of times (watertight crossings; only runs whose box the segment meets are read): `.nearer(0)`.
    /// 3. Else `.notNearer`.
    /// Every run-box test and every triangle test costs 1 from `budget`; when it would go below 0 the answer is
    /// `.unknown`, never a distance.
    func nearer(_ q: MGVec3, than r: Double, budget: inout Int) -> Near {
        guard r > 0, r.isFinite, q.x.isFinite, q.y.isFinite, q.z.isFinite, !mesh.bounds.isEmpty else { return .notNearer }
        func spend() -> Bool { budget -= 1; return budget >= 0 }
        let n = mesh.triangleCount, pos = mesh.positions
        for (c, box) in bounds.enumerated() {
            guard spend() else { return .unknown }
            guard mgBoxDistance(q, box) < r else { continue }
            for i in (c * MGMeshChunks.size)..<min((c + 1) * MGMeshChunks.size, n) {
                guard spend() else { return .unknown }
                let (i0, i1, i2) = mesh.triangle(i)
                guard i0 < pos.count, i1 < pos.count, i2 < pos.count else { continue }
                let d = (mgClosestOnTriangle(q, pos[i0], pos[i1], pos[i2]) - q).length
                if d < r { return .nearer(d) }
            }
        }
        let b = mesh.bounds
        guard q.x <= b.max.x, q.y >= b.min.y, q.y <= b.max.y, q.z >= b.min.z, q.z <= b.max.z else { return .notNearer }
        let far = MGVec3(b.max.x + 1 + (b.max.x - q.x), q.y, q.z)
        guard let ray = WatertightRay(q, far - q) else { return .notNearer }
        var crossings = 0
        for (c, box) in bounds.enumerated() {
            guard spend() else { return .unknown }
            guard MGAnnotationOcclusion.segmentHits(q, far, box) else { continue }
            for i in (c * MGMeshChunks.size)..<min((c + 1) * MGMeshChunks.size, n) {
                guard spend() else { return .unknown }
                let (i0, i1, i2) = mesh.triangle(i)
                guard i0 < pos.count, i1 < pos.count, i2 < pos.count else { continue }
                if let t = ray.hit(pos[i0], pos[i1], pos[i2]), t > 0, t < 1 { crossings += 1 }
            }
        }
        return crossings % 2 == 1 ? .nearer(0) : .notNearer
    }
}

extension MGSolidDocument {
    /// The views that show an annotation and their poses: the plain view (`nil`, at `defaults`) when it shows it, then
    /// every step that shows it (0-based, at the step still's pose, `MGSolidStep.poseParameters`). An explainer beat's
    /// view is its solid step.
    func shownPoses(_ id: String) -> [(step: Int?, params: MGPoseParameters)] {
        var out: [(step: Int?, params: MGPoseParameters)] = []
        if visibleAnnotations(step: nil).contains(id) { out.append((nil, defaults)) }
        for i in steps.indices where visibleAnnotations(step: i).contains(id) { out.append((i, steps[i].poseParameters(defaults: defaults))) }
        return out
    }

    /// Labels and pointers whose anchor lies off the part it names (`annotation.anchor.off.<id>`), or whose nearer-part
    /// test ran out of budget (`annotation.anchor.untested.<id>`), in authored order. Two tests:
    ///
    /// 1. The distance `d` from the anchor to its part's oriented box (the part's mesh box in its own frame) is at most
    ///    `max(partShare × that box's diagonal, modelShare × the drawn model's diagonal)` (the parts the views showing
    ///    the annotation draw, at their poses; all parts when no view shows it). It holds in every pose; the issue has
    ///    no step unless test 2 also found a nearer part (then its view and part are given too).
    /// 2. At the pose of each view that shows the annotation (`shownPoses`: the plain view at the default pose when it
    ///    shows it, and each step or beat still), and in that view's own geometry, no other part's solid comes nearer to
    ///    the anchor than the anchor's distance `d'` to its own part's box (measured in that view) less the precision
    ///    epsilon at the dot (`mgPrecision(.zero)`, 1.01e-4 mm). All distances are taken in anchor-relative coordinates
    ///    (`mgAnchorRelative`). A view is skipped only when `d'` is within that epsilon (the anchor is on or in its own
    ///    part's box in that view). The first such view and part (assembly order) are the issue's `step` and `closer`;
    ///    `closerDistance` is described at `MGAnnotationAnchorIssue.closer`. The search is exact (`MGMeshChunks.nearer`): a part whose oriented box is not nearer is skipped
    ///    with one box test, far runs of 64 triangles are skipped, and it stops at the first nearer triangle. Every
    ///    triangle read (building a part's runs once), every run-box test and every triangle test of one document costs
    ///    1 from `MGAnnotationAnchorRules.surfaceTests`. When the budget runs out, the anchor is `untested` (with the
    ///    view), never off.
    ///
    /// A world anchor names no part and is not tested.
    public var offPartAnchors: [MGAnnotationAnchorIssue] { offPartAnchors(budget: MGAnnotationAnchorRules.surfaceTests) }

    /// `offPartAnchors` with another nearer-part budget (tests).
    func offPartAnchors(budget initial: Int) -> [MGAnnotationAnchorIssue] {
        let a = annotations
        guard !a.isEmpty else { return [] }
        var out: [MGAnnotationAnchorIssue] = []
        var state = MGOffPartState(budget: initial)
        for id in a.ids {
            guard let (kind, p) = a.checkedAnchor(id), let issue = offPartIssue(id: id, kind: kind, p, state: &state) else { continue }
            out.append(issue)
        }
        return out
    }

    /// The off-part rule (`offPartAnchors`) for one anchor `p` of annotation `id`: the issue, or nil when it passes (or
    /// names no part). `state` carries the document's nearer-part budget and its caches.
    func offPartIssue(id: String, kind: String, _ p: MGAnnotationPoint, state: inout MGOffPartState) -> MGAnnotationAnchorIssue? {
        let a = annotations
        guard let partID = p.part, let part = assembly.part(partID) else { return nil }
        let b = part.mesh.bounds
        guard !b.isEmpty else { return nil }
        let dist = mgBoxDistance(p.local, b)
        // The drawn model: the parts the views showing the annotation draw, at their poses (hidden parts left out).
        let shown = shownPoses(id)
        var drawn = MGBounds.empty
        for (step, params) in shown {
            let pose = state.posed(self, params), hidden = hiddenParts(step: step)
            for q in assembly.parts where !hidden.contains(q.id) {
                drawn = drawn.union(MGSolidFrames.worldBounds(q.mesh.bounds, pose.world[q.id] ?? .identity))
            }
        }
        let model = shown.isEmpty || drawn.isEmpty ? a.diagonal : drawn.size.length
        let tol = Swift.max(MGAnnotationAnchorRules.partShare * b.size.length, MGAnnotationAnchorRules.modelShare * model)
        // The nearer-part search, view by view, in each shown view's own geometry and in anchor-relative coordinates
        // (`mgAnchorRelative`): the anchor's distance to its own part's box and to each other part are measured in
        // those parts' frames from the anchor, and the epsilon is the one at the anchor (1.01e-4 mm). A view is
        // skipped only when, in that view, the anchor is within that epsilon of its own part's box.
        let eps = mgPrecision(.zero)
        var closer: (step: Int?, x: MGVec3, part: String, d: Double)?, unknownAt: (step: Int?, x: MGVec3)?
        views: for (step, params) in shown {
            let pose = state.posed(self, params)
            let x = p.world(pose)
            let own = mgAnchorRelative(pose.world[partID] ?? .identity, anchor: x).toLocal.apply(.zero)
            let r = mgBoxDistance(own, b) - eps
            guard r > 0 else { continue }
            for q in assembly.parts where q.id != partID && !q.mesh.bounds.isEmpty {
                    let lq = mgAnchorRelative(pose.world[q.id] ?? .identity, anchor: x).toLocal.apply(.zero)
                    state.budget -= 1
                    guard state.budget >= 0 else { unknownAt = (step, x); break views }
                    guard mgBoxDistance(lq, q.mesh.bounds) < r else { continue }
                    if state.chunks[q.id] == nil {
                        state.budget -= q.mesh.triangleCount
                        guard state.budget >= 0 else { unknownAt = (step, x); break views }
                        state.chunks[q.id] = MGMeshChunks(q.mesh)
                    }
                    switch state.chunks[q.id]!.nearer(lq, than: r, budget: &state.budget) {
                    case .notNearer: continue
                    case .unknown: unknownAt = (step, x)
                    case .nearer(let dq): closer = (step, x, q.id, dq)
                    }
                    break views
            }
        }
        if !(dist <= tol) || closer != nil {
            // Off its part: too far from its own box (in every pose), or another part is nearer in a shown view.
            let rest = state.posed(self, MGPoseParameters(input: defaults.input, explode: 0))
            var issue = MGAnnotationAnchorIssue(id: id, kind: kind, cause: .offPart, part: partID, by: nil, step: closer?.step, beat: nil,
                                                point: closer?.x ?? shown.first.map { p.world(state.posed(self, $0.params)) } ?? p.world(rest),
                                                distance: dist, tolerance: tol)
            issue.closer = closer?.part; issue.closerDistance = closer?.d
            return issue
        } else if let u = unknownAt {
            // Within its tolerance, but the nearer-part search ran out of budget: unknown, never off.
            return MGAnnotationAnchorIssue(id: id, kind: kind, cause: .untested, part: partID, by: nil, step: u.step, beat: nil,
                                           point: u.x, distance: nil, tolerance: nil, budget: "nearerPart")
        }
        return nil
    }

    /// The anchor rules of one framed view: for each label and pointer the view shows (`checkedAnnotations`, view order),
    /// in this order: its part is hidden (`hidden`), its part is ghosted (`ghosted`: the view draws it fainter than the
    /// part's own opacity), the anchor projects outside a `width` × `height` view of `camera` (`offScreen`), or another
    /// part is the first surface on the segment from the camera to the anchor (`occluded`), or the view's triangle budget
    /// ran out before its test (`untested`). The segment test is the watertight ray test of the unblocked-focus rule
    /// against every part the view draws with a coverage of `MGSolidFraming.blockingOpacity` or more (view opacity times
    /// `MGMaterialPreset.coverage`, so glass does not block; a cut part tests its cut mesh): a part blocks when it
    /// crosses the segment before the anchor (less the precision epsilon at the dot, `mgPrecision`; every test runs in
    /// anchor-relative coordinates, `mgAnchorRelative`) and before the first crossing of the
    /// anchor's own part. So an anchor at the centre of its part, seen through its part's own surface, is visible, and an
    /// anchor in the air in front of a part is not hidden by it. A blocker hit that lies on the anchor's own part within
    /// the precision epsilon at the hit point (by its distance from the dot; a coincident face or edge of touching parts)
    /// is a tie: the own part is
    /// there too, so the anchor is visible; this test also costs from the view's budget. Exception: when the view cuts the anchor's part and the
    /// anchor lies in that part's box on the kept side of the cut (or on the cut face), the parts whose box lies inside
    /// that part's box, both taken in the cut part's own frame (grown by 0.5 % of the diagonal of the parts the view
    /// draws), do not hide it;
    /// parts outside still do. `step` and `beat` only label the issues.
    public func anchorIssues(view: MGSolidView, params: MGPoseParameters, camera: MGSolidCamera, width: Double, height: Double,
                             step: Int?, beat: Int?, stage: MGTransform = MGSolidStage.zUpToYUp) -> MGAnnotationAnchorReport {
        anchorIssues(view: view, params: params, camera: camera, width: width, height: height, step: step, beat: beat, stage: stage,
                     budget: MGAnnotationAnchorRules.tests)
    }

    /// `anchorIssues` with another triangle-test budget (tests).
    func anchorIssues(view: MGSolidView, params: MGPoseParameters, camera: MGSolidCamera, width: Double, height: Double,
                      step: Int?, beat: Int?, stage: MGTransform, budget: Int) -> MGAnnotationAnchorReport {
        anchorIssues(MGAnnotationAnchorView(view: view, params: params, camera: camera, width: width, height: height, step: step, beat: beat,
                                            stage: stage), budget: budget)
    }

    /// `anchorIssues` of one framed view.
    func anchorIssues(_ v: MGAnnotationAnchorView, budget: Int = MGAnnotationAnchorRules.tests) -> MGAnnotationAnchorReport {
        var out = MGAnnotationAnchorReport()
        let a = annotations
        let ids = (checkedAnnotations(v.view, params: v.params) ?? []).filter { a.checkedAnchor($0) != nil }
        guard !ids.isEmpty else { return out }
        var rule = MGAnchorViewRule(self, v)
        var used = 0, over = false
        for id in ids {
            guard let (kind, p) = a.checkedAnchor(id) else { continue }
            guard let (c, by) = rule.test(p, used: &used, over: &over, budget: budget) else { continue }
            out.issues.append(MGAnnotationAnchorIssue(id: id, kind: kind, cause: c, part: p.part, by: by, step: v.step, beat: v.beat,
                                                      point: p.world(rule.pose), distance: nil, tolerance: nil,
                                                      budget: c == .untested ? "lineOfSight" : nil))
        }
        return out
    }

    /// The framed view of every step still as `marty-solid render` frames it at `width` × `height` whose view shows a
    /// label or pointer (see `stepAnchorIssues`).
    public func stepAnchorViews(width: Int = MGAnnotationAnchorRules.width, height: Int = MGAnnotationAnchorRules.height) -> [MGAnnotationAnchorView] {
        var out: [MGAnnotationAnchorView] = []
        guard !annotations.isEmpty else { return out }
        let w = Double(width), h = Double(height)
        let aspect = w > 0 && h > 0 ? w / h : 1.6
        let bands = MGSolidRenderPlan.bands(width: w, height: h)
        for i in steps.indices {
            let base = view(step: i)
            guard base.annotations.contains(where: { annotations.checkedAnchor($0) != nil }), let shot = MGSolidShot.step(self, i) else { continue }
            let clear = MGSolidFraming.clearView(self, shot: shot, aspect: aspect, titleBand: shot.title != nil ? bands.title : 0,
                                                 captionBand: shot.caption != nil ? bands.caption : 0)
            out.append(MGAnnotationAnchorView(view: base.ghosting(clear.autoGhost), params: shot.params, camera: clear.camera, width: w, height: h,
                                              step: i, beat: nil))
        }
        return out
    }

    /// The anchor rules of every step still as `marty-solid render` frames it at `width` × `height`
    /// (`MGSolidRenderPlan.cameras`: the step's shot, its title and caption bands, the unblocked-focus rule and its
    /// automatic ghosts), at the still's pose. Steps whose view shows no label or pointer are skipped. The plain view
    /// (`hero.png`) and the poses during a step's spin are not tested.
    public func stepAnchorIssues(width: Int = MGAnnotationAnchorRules.width, height: Int = MGAnnotationAnchorRules.height) -> MGAnnotationAnchorReport {
        var out = MGAnnotationAnchorReport()
        for v in stepAnchorViews(width: width, height: height) { out.append(anchorIssues(v)) }
        return out
    }
}
