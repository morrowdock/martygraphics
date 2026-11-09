// SPDX-License-Identifier: Apache-2.0
import Foundation

// Arrow visibility (docs/SOLID-3D.md, "Arrow visibility"). In every step or beat still that shows an arrow (force,
// flow, motion or pointer), points along the arrow's drawn shaft and head are tested from the still's camera with the
// line-of-sight rule of the anchor checks (`MGAnchorViewRule`): the same blocking coverage, the same cut exception and
// the same anchor-relative precision, with no exception for the parts the arrow is anchored on (an arrow inside its
// own casing is hidden). An arrow with less than half of its samples visible, or its head hidden, is
// `annotation.arrow.hidden.<id>`; one the view's budget left untested is `annotation.arrow.untested.<id>`. The
// standard profile warns; the strict check report refuses. The report suggests a move of the arrow that clears in
// every view that shows it, re-checked once applied. Foundation only, deterministic.

/// Constants of the arrow visibility rule.
public enum MGAnnotationArrowRules {
    /// Sample points along the drawn shaft (evenly by length, at the middle of each of `shaftSamples` equal pieces;
    /// a turn arrow's arc counts its chords) and along the head's axis (at these shares of the head's length from its
    /// base). An arrow that is all head (shorter than its head) has head samples only.
    public static let shaftSamples = 16
    public static let headFractions: [Double] = [1.0 / 6, 0.5, 5.0 / 6]
    /// An arrow passes a view when at least `minVisibleShare` of all its samples are visible there and at least
    /// `minHeadSamples` of its head samples are visible.
    public static let minVisibleShare = 0.5
    public static let minHeadSamples = 2
    /// Run-box and triangle tests one view may spend on the arrow samples (building a part's runs of 64 triangles
    /// costs its triangle count, once per view). The arrow whose test would pass the budget, and every later arrow of
    /// the view, is `untested`.
    public static let tests = 3_000_000
    /// Suggestion search: offsets of `suggestSteps` sizes in each direction, each size a multiple of
    /// `max(the blocker's box diagonal, the arrow's length) / 4`.
    public static let suggestSteps = 8
    /// Tests one search for one arrow may spend, and all searches of one report together (retries included).
    public static let suggestTests = 8_000_000, suggestDocumentTests = 64_000_000
    /// A moved force or flow arrow must keep its drawn vector (end minus start) in every view that shows it: the
    /// moved vector may differ from the authored one by at most the precision epsilon at that vector
    /// (`mgPrecision`, 1e-6 × max(1, |v|) + 1e-4 mm) plus `roundingAllowance`, the most that rounding both moved ends
    /// to 0.001 mm (in their parts' frames) can add (2 × √3 × 0.0005 mm < 0.002 mm).
    public static let roundingAllowance = 0.002
    static func keepsVector(_ authored: MGVec3, _ moved: MGVec3) -> Bool {
        let d = (moved - authored).length
        return d.isFinite && d <= mgPrecision(authored) + roundingAllowance
    }
}

/// What one view shows of one arrow.
public struct MGArrowVisibility: Equatable, Sendable {
    /// Samples tested, and visible.
    public var samples = 0, visible = 0
    /// Head samples, and visible head samples.
    public var head = 0, headVisible = 0
    /// Samples outside the view (or behind the camera).
    public var offScreen = 0
    /// Samples each part hides (the nearest blocking part on the line of sight), by part id.
    public var hiddenBy: [String: Int] = [:]
    /// True when the view's budget ran out before every sample was tested.
    public var over = false

    /// The visible share of the samples (0 when there are none).
    public var share: Double { samples > 0 ? Double(visible) / Double(samples) : 0 }
    /// True when the arrow passes the rule in this view (tested, at least half visible, head visible).
    public var passes: Bool {
        !over && samples > 0 && Double(visible) >= MGAnnotationArrowRules.minVisibleShare * Double(samples)
            && headVisible >= min(head, MGAnnotationArrowRules.minHeadSamples)
    }
    /// True when every sample is visible.
    public var full: Bool { !over && samples > 0 && visible == samples }
}

/// One arrow that a still does not show well enough: what, where, how much is visible, and how to repair it.
public struct MGAnnotationArrowIssue: Equatable, Sendable {
    public enum Cause: String, Equatable, Sendable {
        /// Less than half of the samples, or the head, is visible (`annotation.arrow.hidden.<id>`).
        case hidden
        /// The view's test budget ran out before this arrow (`annotation.arrow.untested.<id>`).
        case untested
    }
    public let id: String
    /// `force`, `flow`, `motion` or `pointer`.
    public let meaning: String
    public let cause: Cause
    /// The 0-based step and explainer beat of the view.
    public let step: Int?, beat: Int?
    public let visibility: MGArrowVisibility
    /// The part that hides the most samples (ties: assembly order); nil when no part hides one (off screen).
    public let by: String?
    /// The move the check report suggests, or why there is none (set by the reports for `hidden`).
    public var suggestion: MGAnnotationArrowSuggestion? = nil

    /// `annotation.arrow.hidden.<id>` or `annotation.arrow.untested.<id>`.
    public var reason: String { cause == .untested ? "annotation.arrow.untested.\(id)" : "annotation.arrow.hidden.\(id)" }

    var viewName: String { beat.map { "beat \($0 + 1)" } ?? step.map { "step \($0 + 1)" } ?? "the plain view" }

    /// The visible share as a whole percent, rounded down (49.9 % prints as 49 %, never 50 %).
    var percent: Int { Int((visibility.share * 100).rounded(.down)) }

    /// A repair a model can act on: the suggested move, or why there is none and what to do instead.
    public var fix: String {
        if cause == .untested {
            return "This view's arrow test ran over its budget (\(MGAnnotationArrowRules.tests) tests) before \(id): hide or ghost parts "
                + "this view does not need, use simpler parts, or show fewer arrows in it."
        }
        let what = "\(percent) % of \(id) is visible in \(viewName)" + (visibility.headVisible < min(visibility.head, MGAnnotationArrowRules.minHeadSamples) ? ", and its head is hidden" : "")
        let why = by.map { " (`\($0)` hides it)" } ?? (visibility.offScreen > 0 ? " (it is outside the view)" : "")
        if let s = suggestion, let a = s.anchorJSON {
            return "\(what)\(why). Use \(MGAnnotationAnchorIssue.compact(a)): it moves \(s.moveText) and shows \(id) in every view that shows it."
        }
        if let s = suggestion {
            return "\(what)\(why). No move of \(id) shows it in every view (\(s.causeText ?? "")): " + MGAnnotationAnchorIssue.orList(s.alternatives(id: id))
        }
        return "\(what)\(why): move the arrow out of the part in the way, ghost that part in this view, or change the camera."
    }

    /// One line a tool can pass straight to a model (at most `MGAnnotationAnchorIssue.repairScalars` Unicode scalars).
    public var repair: String {
        let who = "Arrow \(id) (\(viewName))"
        let problem: String
        if cause == .untested { problem = "was not tested: the view's arrow test budget ran out" }
        else {
            var p = "is \(percent) % visible"
            if let by { p += ", hidden behind \(by)" } else if visibility.offScreen > 0 { p += ", outside the view" }
            if visibility.headVisible < min(visibility.head, MGAnnotationArrowRules.minHeadSamples) { p += "; its head is hidden" }
            problem = p
        }
        let action: String
        if cause == .untested { action = "Hide or ghost parts this view does not need, or show fewer arrows in it." }
        else if let s = suggestion, let a = s.anchorJSON { action = "Use " + MGAnnotationAnchorIssue.compact(a) + "." }
        else if let s = suggestion { action = "No clear move: \(s.causeText ?? ""). " + MGAnnotationAnchorIssue.orList(s.alternatives(id: id)) }
        else { action = "Move the arrow out of \(by ?? "the part in the way"), ghost that part, or change the camera." }
        return MGAnnotationAnchorIssue.bounded("\(who) \(problem). \(action)", MGAnnotationAnchorIssue.repairScalars)
    }

    /// `{"id", "meaning", "reason", "cause", "step", "beat", "by", "samples", "visible", "share", "head",
    /// "headVisible", "offScreen", "fix", "suggest", "noSuggest", "repair"}`; `step` and `beat` 1-based, absent values
    /// null; `share` rounded down to 0.001.
    public var json: MGJSON {
        func n(_ i: Int?) -> MGJSON { i.map { .number(Double($0 + 1)) } ?? .null }
        let v = visibility
        let s = cause == .untested ? nil : suggestion
        return .object(["id": .string(id), "meaning": .string(meaning), "reason": .string(reason), "cause": .string(cause.rawValue),
                        "step": n(step), "beat": n(beat), "by": by.map(MGJSON.string) ?? .null,
                        "samples": .number(Double(v.samples)), "visible": .number(Double(v.visible)),
                        "share": .number((v.share * 1000).rounded(.down) / 1000), "head": .number(Double(v.head)),
                        "headVisible": .number(Double(v.headVisible)), "offScreen": .number(Double(v.offScreen)),
                        "fix": .string(fix), "suggest": s?.anchorJSON ?? .null,
                        "noSuggest": s.map { $0.anchorJSON == nil ? $0.noneJSON(id: id) : .null } ?? .null, "repair": .string(repair)])
    }
}

/// The move the check report suggests for a hidden arrow, or why there is none.
public struct MGAnnotationArrowSuggestion: Equatable, Sendable {
    public enum Cause: String, Equatable, Sendable {
        /// A motion arrow shows the engine's motion of its anchor; it cannot be moved.
        case motion
        /// Every move tried changes the arrow's direction or length in some view that shows it (its ends ride on parts
        /// that turn differently between those views), so no move keeps what the arrow says.
        case pose
        /// No offset tried shows the arrow in every view that shows it.
        case noClearOffset = "noclearoffset"
        /// The suggestion budget ran out first.
        case budget
        /// The document with the move applied does not compile.
        case form
        /// The move did not hold once applied (the framing changed), within the re-checks.
        case framing
        /// The move gives another annotation (`other`) an issue once applied.
        case conflict
    }
    /// The new anchors: `from` (and `to` for a force or flow arrow, moved by the same offset); nil when none passes. A
    /// pointer keeps its tip (`to`), so only its start moves.
    public let from: MGAnnotationPoint?, to: MGAnnotationPoint?
    /// The world offset (kernel frame, mm) of the move's start from the authored start, at the pose of the first view
    /// that shows the arrow.
    public internal(set) var offset: MGVec3?
    /// True when every sample is visible in every view that shows the arrow.
    public let full: Bool
    public let cause: Cause?
    /// The view at fault for `noClearOffset` (the first view that showed the arrow) and the part in the way there.
    public let step: Int?, beat: Int?
    public let by: String?
    /// Candidates checked.
    public internal(set) var samples = 0
    /// `conflict`: the annotation the move would give an issue.
    public internal(set) var other: String? = nil

    static func point(_ p: MGAnnotationPoint) -> MGJSON {
        func v(_ x: MGVec3) -> MGJSON { .array([x.x, x.y, x.z].map { .number($0) }) }
        switch p.anchor {
        case .world(let w): return .object(["world": v(w)])
        case .part(let id): return .string(id)
        case .centre(let id): return .object(["part": .string(id), "point": .string("centre")])
        case .offset(let id, let o): return .object(["part": .string(id), "offset": v(o)])
        }
    }

    /// `{"from": anchor, "to": anchor}` (a pointer: `{"from": anchor}`), in the form a document writes them.
    public var anchorJSON: MGJSON? {
        guard let from else { return nil }
        var o: [String: MGJSON] = ["from": MGAnnotationArrowSuggestion.point(from)]
        if let to { o["to"] = MGAnnotationArrowSuggestion.point(to) }
        return .object(o)
    }

    /// "the whole arrow 120 mm" or "its start 40 mm".
    var moveText: String {
        let mm = MGAnnotationAnchorIssue.number(offset?.length ?? 0)
        return (to != nil ? "the whole arrow " : "its start ") + "\(mm) mm"
    }

    var viewName: String? { beat.map { "beat \($0 + 1)" } ?? step.map { "step \($0 + 1)" } }

    /// The cause as a short phrase (nil with a move).
    public var causeText: String? {
        guard let cause else { return nil }
        switch cause {
        case .motion: return "a motion arrow shows its anchor's motion and cannot move"
        case .pose: return "no move keeps the arrow's direction and length in every view that shows it"
        case .noClearOffset: return "no offset tried is clear" + (viewName.map { " in \($0)" } ?? "")
        case .budget: return "suggestion budget ran out"
        case .form: return "the moved arrow cannot be written or does not compile"
        case .framing: return "no move stays clear once the framing changes"
        case .conflict: return "every move tried conflicts with \(other ?? "another annotation") once applied"
        }
    }

    /// What the author can do instead when there is no move, one sentence each.
    public func alternatives(id: String) -> [String] {
        guard cause != nil else { return [] }
        let w = viewName ?? "that view"
        let list = beat != nil ? "view.annotate" : "annotate"
        let blocker = by.map { "`\($0)`" } ?? "the part in the way"
        return ["Leave \(id) out of \(w)'s \(list) list.", "Ghost \(blocker) in \(w).", "Change \(w)'s camera."]
    }

    /// `{"cause", "code", "step", "beat", "by", "other", "samples", "alternatives"}` for a suggestion without a move.
    func noneJSON(id: String) -> MGJSON {
        func n(_ i: Int?) -> MGJSON { i.map { .number(Double($0 + 1)) } ?? .null }
        return .object(["cause": .string(causeText ?? ""), "code": .string(cause?.rawValue ?? ""), "step": n(step), "beat": n(beat),
                        "by": by.map(MGJSON.string) ?? .null, "other": other.map(MGJSON.string) ?? .null, "samples": .number(Double(samples)),
                        "alternatives": .array(alternatives(id: id).map(MGJSON.string))])
    }
}

/// The arrow sample points of one drawn arrow (posed kernel world).
struct MGArrowSamples: Equatable {
    let shaft: [MGVec3]
    let head: [MGVec3]

    /// The samples of an arrow's pieces (`MGSolidAnnotations.primitives`): nil when the arrow draws nothing.
    init?(_ prims: [MGAnnotationPrimitive], turn: Bool) {
        let n = MGSolidAnnotations.arcChords
        let shaftPieces: [MGAnnotationPrimitive], headPiece: MGAnnotationPrimitive
        if turn {
            guard prims.count == n + 1 else { return nil }
            shaftPieces = Array(prims[0..<n]); headPiece = prims[n]
        } else {
            guard prims.count == 2 else { return nil }
            shaftPieces = [prims[0]]; headPiece = prims[1]
        }
        guard !headPiece.hidden else { return nil }
        let pieces = shaftPieces.filter { !$0.hidden && ($0.end - $0.start).length > 1e-9 }
        let lengths = pieces.map { ($0.end - $0.start).length }
        let total = lengths.reduce(0, +)
        var shaft: [MGVec3] = []
        if total > 1e-9, total.isFinite {
            let m = MGAnnotationArrowRules.shaftSamples
            var k = 0, acc = 0.0
            for i in 0..<m {
                let s = (Double(i) + 0.5) / Double(m) * total
                while k < pieces.count - 1 && acc + lengths[k] < s { acc += lengths[k]; k += 1 }
                let u = lengths[k] > 0 ? min(1, max(0, (s - acc) / lengths[k])) : 0
                shaft.append(pieces[k].start + (pieces[k].end - pieces[k].start) * u)
            }
        }
        self.shaft = shaft
        head = MGAnnotationArrowRules.headFractions.map { headPiece.start + (headPiece.end - headPiece.start) * $0 }
        guard (shaft + head).allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }) else { return nil }
    }
}

/// The arrow rule of one framed view: the anchor view rule's blocking parts, camera and projection, with each part's
/// runs of 64 triangles built once.
struct MGArrowViewRule {
    var base: MGAnchorViewRule
    var runs: [Int: MGMeshChunks] = [:]
    let order: [String: Int]

    init(_ doc: MGSolidDocument, _ v: MGAnnotationAnchorView) {
        base = MGAnchorViewRule(doc, v)
        var o: [String: Int] = [:]
        for (k, p) in doc.assembly.parts.enumerated() { o[p.id] = k }
        order = o
    }

    enum Sample: Equatable { case visible, offScreen, hidden(String), over }

    /// One sample point `x` (posed kernel world): off screen, hidden by the nearest blocking part on the segment from
    /// the camera (watertight crossings strictly before the point less the precision epsilon at it, in sample-relative
    /// coordinates), or visible. `parts`: the parts the arrow is anchored on; when the view cuts one of them and `x`
    /// lies in its box on the kept side, the parts inside that box do not hide `x` (the cut exception). Each run-box
    /// test and triangle test costs 1 from `budget`, and building a part's runs costs its triangle count.
    mutating func sample(_ x: MGVec3, parts: [String], budget: inout Int) -> Sample {
        let v = base.v
        guard let s = base.proj.project(v.stage.apply(x)), s.x >= 0, s.x <= v.width, s.y >= 0, s.y <= v.height else { return .offScreen }
        let eps = mgPrecision(.zero)
        let eyeRel = base.eye - x
        let len = eyeRel.length
        guard len > eps, len.isFinite else { return .visible }
        let before = 1 - eps / len
        var exempt = Set<String>()
        for p in parts { exempt.formUnion(base.exemptParts(MGAnnotationPoint(anchor: .part(p), local: .zero), x: x)) }
        var first: (t: Double, i: Int)?
        for (i, sld) in base.solids.enumerated() where !exempt.contains(sld.id) {
            let rel = mgAnchorRelative(sld.world, anchor: x)
            guard MGAnnotationOcclusion.segmentHits(eyeRel, .zero, MGSolidFrames.worldBounds(sld.mesh.bounds, rel.toRelative)) else { continue }
            if runs[i] == nil {
                budget -= sld.mesh.triangleCount
                guard budget >= 0 else { return .over }
                runs[i] = MGMeshChunks(sld.mesh)
            }
            let r = runs[i]!.firstHit(rel.toLocal.apply(eyeRel), rel.toLocal.apply(.zero), after: 1e-9,
                                      before: first.map { min(before, $0.t) } ?? before, budget: &budget)
            guard r.ok else { return .over }
            if let t = r.t, first.map({ t < $0.t }) ?? true { first = (t, i) }
        }
        return first.map { .hidden(base.solids[$0.i].id) } ?? .visible
    }

    /// Every sample of an arrow. Stops at the first sample over the budget (`over`).
    mutating func visibility(_ s: MGArrowSamples, parts: [String], budget: inout Int) -> MGArrowVisibility {
        var out = MGArrowVisibility()
        for (k, x) in (s.shaft + s.head).enumerated() {
            let isHead = k >= s.shaft.count
            switch sample(x, parts: parts, budget: &budget) {
            case .over: out.over = true; return out
            case .visible:
                out.visible += 1
                if isHead { out.headVisible += 1 }
            case .offScreen: out.offScreen += 1
            case .hidden(let id): out.hiddenBy[id, default: 0] += 1
            }
            out.samples += 1
            if isHead { out.head += 1 }
        }
        return out
    }

    /// The part that hides the most samples (ties: assembly order).
    func mainBlocker(_ v: MGArrowVisibility) -> String? {
        v.hiddenBy.sorted { a, b in a.value != b.value ? a.value > b.value : (order[a.key] ?? .max, a.key) < (order[b.key] ?? .max, b.key) }.first?.key
    }
}

extension MGSolidDocument {
    /// True when `view` shows a label or a pointer (the anchor checks test it).
    func showsCheckedAnchor(_ view: MGSolidView) -> Bool { view.annotations.contains { annotations.checkedAnchor($0) != nil } }
    /// True when `view` shows an arrow (the arrow visibility rule tests it).
    func showsArrow(_ view: MGSolidView) -> Bool { view.annotations.contains { annotations.arrow($0) != nil } }

    /// The parts an arrow is anchored on (`from`, `to`, `on`), without repeats.
    func arrowParts(_ r: MGSolidArrow) -> [String] {
        var out: [String] = []
        for p in [r.from?.part, r.to?.part, r.on].compactMap({ $0 }) where !out.contains(p) { out.append(p) }
        return out
    }

    /// The arrow visibility rule of one framed view: for each arrow the view shows (`checkedAnnotations`, view order),
    /// sample points along its drawn shaft and head (`MGAnnotationArrowRules`, the pieces the renderer draws at the
    /// view's pose, motion sense and step) are tested from the view's camera (`MGArrowViewRule.sample`). The arrow is
    /// `hidden` when less than `minVisibleShare` of its samples, or fewer than `minHeadSamples` of its head samples,
    /// are visible; `untested` when the view's budget (`MGAnnotationArrowRules.tests`) ran out before or during it
    /// (every later arrow of the view too). An arrow that draws nothing in the view (a motion arrow on a still anchor)
    /// is not tested.
    func arrowIssues(_ v: MGAnnotationAnchorView, budget initial: Int = MGAnnotationArrowRules.tests) -> [MGAnnotationArrowIssue] {
        let a = annotations
        let ids = (checkedAnnotations(v.view, params: v.params) ?? []).filter { a.arrow($0) != nil }
        guard !ids.isEmpty else { return [] }
        var rule = MGArrowViewRule(self, v)
        var budget = initial, over = false
        var out: [MGAnnotationArrowIssue] = []
        for id in ids {
            guard let r = a.arrow(id) else { continue }
            let prims = MGSolidAnnotations.primitives(self, id, params: v.params, sense: v.view.motionSense, step: v.view.step)
            guard let s = MGArrowSamples(prims, turn: r.style == .turn) else { continue }
            var vis = MGArrowVisibility()
            if !over { vis = rule.visibility(s, parts: arrowParts(r), budget: &budget) }
            if over || vis.over {
                over = true
                vis.over = true
                out.append(MGAnnotationArrowIssue(id: id, meaning: r.meaning.rawValue, cause: .untested, step: v.step, beat: v.beat,
                                                  visibility: vis, by: nil))
                continue
            }
            guard !vis.passes else { continue }
            out.append(MGAnnotationArrowIssue(id: id, meaning: r.meaning.rawValue, cause: .hidden, step: v.step, beat: v.beat,
                                              visibility: vis, by: rule.mainBlocker(vis)))
        }
        return out
    }

    /// The framed view of every step still as `marty-solid render` frames it (see `stepAnchorViews`) whose view shows
    /// a label, a pointer or an arrow: the views both the anchor checks and the arrow rule test.
    public func stepCheckViews(width: Int = MGAnnotationAnchorRules.width, height: Int = MGAnnotationAnchorRules.height) -> [MGAnnotationAnchorView] {
        stepViews(width: width, height: height) { showsCheckedAnchor($0) || showsArrow($0) }
    }

    /// The arrow rule of every step still as `marty-solid render` frames it at `width` × `height`, in step order.
    public func stepArrowIssues(width: Int = MGAnnotationAnchorRules.width, height: Int = MGAnnotationAnchorRules.height) -> [MGAnnotationArrowIssue] {
        stepCheckViews(width: width, height: height).filter { showsArrow($0.view) }.flatMap { arrowIssues($0) }
    }
}

extension MGAnnotationArrowSuggestion {
    /// A suggestion without a move.
    static func none(_ c: Cause, step: Int? = nil, beat: Int? = nil, by: String? = nil, samples: Int = 0) -> MGAnnotationArrowSuggestion {
        var s = MGAnnotationArrowSuggestion(from: nil, to: nil, offset: nil, full: false, cause: c, step: step, beat: beat, by: by)
        s.samples = samples
        return s
    }
}

extension MGSolidDocument {
    /// The suggestion for every arrow `issues` names with a `hidden` issue (issue order), by arrow id, from the shared
    /// budget. `views` are the framed views the rule tested.
    ///
    /// For each such arrow: a motion arrow gets none (`motion`). Else, at the pose of the first view that shows it,
    /// with `p`, `q` its drawn ends, `u` their unit direction, `c` the direction toward that view's camera with its
    /// `u` part removed and `e1`, `e2` a basis perpendicular to `u`, the directions are `u, −u, c, −c, e1, −e1, e2,
    /// −e2` (a pointer, which keeps its tip: `c, −c, e1, −e1, e2, −e2, −u`), and the sizes are `k × S`, `k = 1 ...
    /// suggestSteps`, with `S = max(the blocker's box diagonal, |q − p|) / 4` (at least 0.5 mm). Candidates are tried
    /// smallest size first, then in direction order. A force or flow arrow moves both ends by the offset; a pointer
    /// moves its start only. Each end on a part moves in that part's frame (the offset taken into the frame at that
    /// pose), rounded to 0.001 mm; a world end moves in the world. A candidate whose coordinates leave ±4000 mm, or a
    /// pointer start within 4 shaft radii of its tip, is skipped. Each candidate is drawn as the renderer draws it in
    /// every view that shows the arrow and tested with the view rule; the first candidate that shows every sample in
    /// every view is the suggestion, else the first that passes the rule in every view, else none
    /// (`noClearOffset`, or `budget`). `excluding` gives start anchors (`from`, in its part's frame or the world)
    /// already found to conflict: no candidate whose start lies within `max(1 mm, S / 4)` of one is used.
    /// Deterministic.
    func arrowSuggestions(for issues: [MGAnnotationArrowIssue], views: [MGAnnotationAnchorView], shared: MGSuggestionBudget,
                          excluding: [String: [MGVec3]] = [:]) -> [String: MGAnnotationArrowSuggestion] {
        var rules = views.map { MGArrowViewRule(self, $0) }
        let shownBy: [[String]] = views.map { checkedAnnotations($0.view, params: $0.params) ?? [] }
        var out: [String: MGAnnotationArrowSuggestion] = [:]
        for issue in issues where issue.cause == .hidden && out[issue.id] == nil {
            guard let r = annotations.arrow(issue.id) else { continue }
            let mine = rules.indices.filter { shownBy[$0].contains(issue.id) }
            var budget = min(shared.left, MGAnnotationArrowRules.suggestTests)
            let start = budget
            out[issue.id] = arrowSuggestion(r, issue: issue, rules: &rules, views: mine, budget: &budget, excluding: excluding[issue.id] ?? [])
            shared.left -= start - max(0, budget)
        }
        return out
    }

    func arrowSuggestion(_ r: MGSolidArrow, issue: MGAnnotationArrowIssue, rules: inout [MGArrowViewRule], views mine: [Int],
                         budget: inout Int, excluding: [MGVec3]) -> MGAnnotationArrowSuggestion {
        func none(_ c: MGAnnotationArrowSuggestion.Cause, tried: Int = 0) -> MGAnnotationArrowSuggestion {
            .none(c, step: issue.step, beat: issue.beat, by: issue.by, samples: tried)
        }
        guard r.meaning != .motion else { return none(.motion) }
        guard let from = r.from, let to = r.to, let k0 = mine.first else { return none(.noClearOffset) }
        let pose0 = rules[k0].base.pose
        let p = from.world(pose0), q = to.world(pose0)
        let len = (q - p).length
        let u = len > 1e-9 && len.isFinite ? (q - p) * (1 / len) : MGVec3.unitZ
        let blockerSize = issue.by.flatMap { assembly.part($0)?.mesh.bounds }.map { $0.isEmpty ? 0 : $0.size.length } ?? 0
        let step = max(0.5, max(blockerSize, len.isFinite ? len : 0) / 4)
        var c = rules[k0].base.eye - (p + q) * 0.5
        c = c - u * c.dot(u)
        let (e1, e2) = MGSolidAnnotations.basis(u)
        var dirs: [MGVec3] = []
        let hasC = c.length > 1e-9 && c.length.isFinite
        if r.meaning == .pointer {
            dirs = (hasC ? [c.normalized, c.normalized * -1] : []) + [e1, e1 * -1, e2, e2 * -1, u * -1]
        } else {
            dirs = [u, u * -1] + (hasC ? [c.normalized, c.normalized * -1] : []) + [e1, e1 * -1, e2, e2 * -1]
        }
        let sr = annotations.diagonal * MGSolidAnnotationLimits.shaftRadius
        let keepOff = max(1, step / 4)
        func rounded(_ v: MGVec3) -> MGVec3 { MGVec3((v.x * 1000).rounded() / 1000, (v.y * 1000).rounded() / 1000, (v.z * 1000).rounded() / 1000) }
        func moved(_ pt: MGAnnotationPoint, _ o: MGVec3) -> MGAnnotationPoint? {
            let local: MGVec3
            if let part = pt.part { local = rounded(pt.local + (pose0.world[part] ?? .identity).inverse.applyVector(o)) }
            else { local = rounded(pt.local + o) }
            guard [local.x, local.y, local.z].allSatisfy({ $0.isFinite && MGSolidLimits.coordinate.contains($0) }) else { return nil }
            if let part = pt.part { return MGAnnotationPoint(anchor: .offset(part: part, local), local: local) }
            return MGAnnotationPoint(anchor: .world(local), local: local)
        }
        let parts = [from.part, to.part].compactMap { $0 }.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        var tried = 0, keptVector = 0
        var firstPass: MGAnnotationArrowSuggestion?
        var seen = Set<[Double]>()
        for k in 1...MGAnnotationArrowRules.suggestSteps {
            for d in dirs {
                let o = d * (Double(k) * step)
                guard let f2 = moved(from, o), !excluding.contains(where: { ($0 - f2.local).length < keepOff }) else { continue }
                let t2 = r.meaning == .pointer ? to : moved(to, o)
                guard let t2 else { continue }
                guard seen.insert([f2.local.x, f2.local.y, f2.local.z, t2.local.x, t2.local.y, t2.local.z]).inserted else { continue }
                guard budget > 0 else { return firstPass ?? none(.budget, tried: tried) }
                tried += 1
                // A force or flow arrow says something with its vector: the move must keep it in every view.
                if r.meaning != .pointer {
                    let keeps = mine.allSatisfy { kv in
                        let pose = rules[kv].base.pose
                        return MGAnnotationArrowRules.keepsVector(to.world(pose) - from.world(pose), t2.world(pose) - f2.world(pose))
                    }
                    guard keeps else { continue }
                }
                keptVector += 1
                var passes = true, full = true
                for kv in mine {
                    let pose = rules[kv].base.pose
                    let a = f2.world(pose), b = t2.world(pose)
                    if r.meaning == .pointer, (b - a).length < 4 * sr { passes = false; break }
                    guard let s = MGArrowSamples(MGSolidAnnotations.lineArrow(a, b, radius: sr), turn: false) else { passes = false; break }
                    let vis = rules[kv].visibility(s, parts: parts, budget: &budget)
                    if vis.over { return firstPass ?? none(.budget, tried: tried) }
                    if !vis.passes { passes = false; break }
                    if !vis.full { full = false }
                }
                guard passes else { continue }
                var found = MGAnnotationArrowSuggestion(from: f2, to: r.meaning == .pointer ? nil : t2, offset: rounded(o), full: full,
                                                        cause: nil, step: nil, beat: nil, by: nil)
                found.samples = tried
                if full { return found }
                if firstPass == nil { firstPass = found }
            }
        }
        return firstPass ?? none(tried > 0 && keptVector == 0 ? .pose : .noClearOffset, tried: tried)
    }

    /// `source` (an assembly, or an explainer's solid object) with each arrow in `moves` given the anchors of its
    /// suggestion (`{"from"}` and, unless a pointer, `{"to"}`). Unchanged when `source` has no such arrow.
    static func replacingArrows(_ source: MGJSON, _ moves: [String: MGJSON]) -> MGJSON {
        guard case .object(var o) = source, case .object(var ann)? = o["annotations"], case .array(let list)? = ann["arrows"] else { return source }
        ann["arrows"] = .array(list.map { e in
            guard case .object(var eo) = e, case .string(let id)? = eo["id"], case .object(let m)? = moves[id] else { return e }
            if let f = m["from"] { eo["from"] = f }
            if let t = m["to"] { eo["to"] = t }
            return .object(eo)
        })
        o["annotations"] = .object(ann)
        return .object(o)
    }
}

/// One full re-check of a document with suggested arrow moves applied: its arrow and anchor issues (with the copy's own
/// framing), the annotations each framed view shows, and a search in that framing.
struct MGArrowRecheck {
    let arrows: [MGAnnotationArrowIssue]
    let anchors: [MGAnnotationAnchorIssue]
    var shown: [(step: Int?, beat: Int?, ids: Set<String>)] = []
    let search: (_ issues: [MGAnnotationArrowIssue], _ excluding: [String: [MGVec3]]) -> [String: MGAnnotationArrowSuggestion]
}

/// The arrow issues of a report, with the shared suggestion pass and its re-check.
struct MGAnnotationArrowReport {
    var issues: [MGAnnotationArrowIssue] = []

    /// The whole suggestion pass of a report, from ONE search budget: `suggest`, then `verify` (its re-searches get
    /// the same `budget` through `recheck`), then `measure`. So all searches of a report, retries included, spend at
    /// most what `budget` holds (`MGAnnotationArrowRules.suggestDocumentTests` in the reports). Nothing runs when no
    /// issue is `hidden`.
    mutating func repair(_ doc: MGSolidDocument, views: [MGAnnotationAnchorView], anchorIssues: Set<String>, budget: MGSuggestionBudget,
                         recheck: ([String: MGJSON], MGSuggestionBudget) -> MGArrowRecheck?) {
        guard issues.contains(where: { $0.cause == .hidden }) else { return }
        suggest(doc, views: views, budget: budget)
        verify(anchorIssues: anchorIssues) { recheck($0, budget) }
        measure(doc, views: views)
    }

    /// Sets `suggestion` on every hidden issue (`arrowSuggestions`).
    mutating func suggest(_ doc: MGSolidDocument, views: [MGAnnotationAnchorView], budget: MGSuggestionBudget) {
        let found = doc.arrowSuggestions(for: issues, views: views, shared: budget)
        for i in issues.indices where issues[i].cause == .hidden { issues[i].suggestion = found[issues[i].id] }
    }

    /// Keeps only moves that hold once applied (the fixed-point re-check of the anchor suggestions,
    /// `MGAnnotationAnchorReport.verify`). With every move applied to a copy, `recheck` compiles and frames it again. A
    /// set is accepted when no moved arrow has an arrow issue and no annotation that had no issue in this report (arrow
    /// or anchor, `clean` lists the anchor ids with an issue) has one. Otherwise, at most
    /// `MGAnnotationAnchorRules.recheckRounds` re-checks: a moved arrow that still has an issue is searched again in the
    /// copy's framing (at most `MGAnnotationAnchorRules.retries` times), then dropped (`framing`); the moves shown in
    /// the same view as a newly failing annotation are searched again away from their current offset (at most
    /// `retries` times), then dropped (`conflict`, naming it); a refused copy drops the whole set (`form`). When the
    /// re-checks run out, every remaining move is dropped (`framing`). So a printed set of moves, applied together,
    /// compiles, clears every moved arrow and adds no issue.
    mutating func verify(anchorIssues: Set<String>, _ recheck: ([String: MGJSON]) -> MGArrowRecheck?) {
        let before = Set(issues.map(\.id)).union(anchorIssues)
        var current: [String: MGAnnotationArrowSuggestion] = [:]
        for i in issues { if let s = i.suggestion, current[i.id] == nil { current[i.id] = s } }
        let original = Dictionary(issues.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var retries: [String: Int] = [:], excluding: [String: [MGVec3]] = [:], blamedBy: [String: String] = [:]
        func applied() -> [String: MGJSON] { current.compactMapValues { $0.anchorJSON } }
        func drop(_ ids: [String], _ cause: MGAnnotationArrowSuggestion.Cause) {
            for id in ids {
                guard let s = current[id], s.from != nil else { continue }
                let other = cause == .form ? nil : blamedBy[id]
                var n = MGAnnotationArrowSuggestion.none(other != nil ? .conflict : cause, step: original[id]?.step, beat: original[id]?.beat,
                                                         by: original[id]?.by, samples: s.samples)
                n.other = other
                current[id] = n
            }
        }
        var accepted = false
        for _ in 0..<MGAnnotationAnchorRules.recheckRounds {
            let set = applied()
            if set.isEmpty { accepted = true; break }
            guard let r = recheck(set) else { drop(set.keys.sorted(), .form); continue }
            let moved = set.keys.sorted()
            let bad = moved.filter { id in r.arrows.contains { $0.id == id } }
            var fresh: [(id: String, step: Int?, beat: Int?)] = []
            for i in r.arrows where !before.contains(i.id) && !set.keys.contains(i.id) && !fresh.contains(where: { $0.id == i.id }) {
                fresh.append((i.id, i.step, i.beat))
            }
            for i in r.anchors where !before.contains(i.id) && !fresh.contains(where: { $0.id == i.id }) { fresh.append((i.id, i.step, i.beat)) }
            if bad.isEmpty && fresh.isEmpty { accepted = true; break }
            var again = bad
            for f in fresh.sorted(by: { $0.id < $1.id }) {
                let inView = Set(r.shown.filter { $0.step == f.step && $0.beat == f.beat }.flatMap(\.ids))
                var suspects = moved.filter { inView.contains($0) }
                if suspects.isEmpty { suspects = moved }
                for id in suspects {
                    if blamedBy[id] == nil { blamedBy[id] = f.id }
                    if let f = current[id]?.from { excluding[id, default: []].append(f.local) }
                    if !again.contains(id) { again.append(id) }
                }
            }
            var search: [MGAnnotationArrowIssue] = []
            for id in again {
                if retries[id, default: 0] >= MGAnnotationAnchorRules.retries { drop([id], .framing); continue }
                retries[id, default: 0] += 1
                if let i = r.arrows.first(where: { $0.id == id && $0.cause == .hidden }) ?? original[id] { search.append(i) }
            }
            guard !search.isEmpty else { continue }
            let found = r.search(search, excluding)
            for i in search {
                if let s = found[i.id], s.from != nil { current[i.id] = s } else { drop([i.id], .framing) }
            }
        }
        if !accepted { drop(applied().keys.sorted(), .framing) }
        for k in issues.indices where issues[k].suggestion != nil { issues[k].suggestion = current[issues[k].id] }
    }

    /// Checks each move against the authored arrow of `doc` and sets its `offset`. A force or flow move must keep the
    /// authored vector in every view of `views` that shows the arrow (`MGAnnotationArrowRules.keepsVector`; a re-check
    /// may have searched from an already moved arrow); otherwise it is dropped with cause `pose`. `offset` is the moved
    /// start minus the authored start at the pose of the first such view.
    mutating func measure(_ doc: MGSolidDocument, views: [MGAnnotationAnchorView]) {
        for k in issues.indices {
            guard var s = issues[k].suggestion, let f = s.from, let r = doc.annotations.arrow(issues[k].id), let from = r.from else { continue }
            let shown = views.filter { (doc.checkedAnnotations($0.view, params: $0.params) ?? []).contains(r.id) }
            if r.meaning != .pointer, let to = r.to, let t = s.to {
                let keeps = shown.allSatisfy { v in
                    let pose = doc.assembly.pose(v.params)
                    return MGAnnotationArrowRules.keepsVector(to.world(pose) - from.world(pose), t.world(pose) - f.world(pose))
                }
                if !keeps {
                    issues[k].suggestion = .none(.pose, step: issues[k].step, beat: issues[k].beat, by: issues[k].by, samples: s.samples)
                    continue
                }
            }
            let v = shown.first
            let pose = doc.assembly.pose(v?.params ?? doc.defaults)
            let o = f.world(pose) - from.world(pose)
            s.offset = MGVec3((o.x * 1000).rounded() / 1000, (o.y * 1000).rounded() / 1000, (o.z * 1000).rounded() / 1000)
            issues[k].suggestion = s
        }
    }
}

/// The joint fixed-point check of every printed suggestion of a report, anchors and arrows together
/// (`verifyTogether`). Each family was already checked on its own (`MGAnnotationAnchorReport.verify`,
/// `MGAnnotationArrowReport.verify`); this check applies the union to one copy, so a model can apply every printed
/// suggestion at once.
enum MGSuggestionUnion {
    /// With every printed anchor suggestion and arrow move applied to one copy, `recheck` compiles, frames and checks it
    /// (its `anchors` and `arrows` issues and the annotations each framed view shows; nil when the copy is refused). The
    /// union is accepted, as in `MGAnnotationAnchorReport.verify`, only when no suggested annotation has an issue and
    /// no annotation that had none in the report (`anchors` and `arrows` before the suggestions) has one. Otherwise,
    /// with no new search (each family's own re-check already searched):
    /// - a suggestion whose annotation still has an issue only conflicts in the union (it passed its own family's
    ///   check), so it is dropped with cause `conflict`, `other` naming the first suggestion of the other family (sorted
    ///   ids) shown in the same view (of all of them when none is);
    /// - an annotation that had no issue and now has one drops the suggestions shown in the same view (all of them when
    ///   none is), each with cause `conflict` and `other` naming that annotation;
    /// - a refused copy drops every suggestion (`form`).
    /// The smaller union is checked again, at most `MGAnnotationAnchorRules.recheckRounds` times; when they run out, every
    /// remaining suggestion is dropped (`conflict`). A report whose suggestions are all in one family needs no joint
    /// check: that family's own check is the check of the union. Deterministic (sorted ids).
    static func verifyTogether(anchors: inout MGAnnotationAnchorReport, arrows: inout MGAnnotationArrowReport,
                               recheck: (_ anchors: [String: MGJSON], _ arrows: [String: MGJSON]) -> MGArrowRecheck?) {
        let before = Set(anchors.issues.map(\.id)).union(arrows.issues.map(\.id))
        var a: [String: MGAnnotationAnchorSuggestion] = [:], r: [String: MGAnnotationArrowSuggestion] = [:]
        for i in anchors.issues where a[i.id] == nil && i.suggestion?.anchorJSON != nil { a[i.id] = i.suggestion }
        for i in arrows.issues where r[i.id] == nil && i.suggestion?.anchorJSON != nil { r[i.id] = i.suggestion }
        func dropAnchor(_ id: String, other: String?) {
            guard let s = a[id] else { return }
            var n = MGAnnotationAnchorSuggestion(part: s.part, offset: nil, onCut: false, cause: other == nil ? .form : .conflict,
                                                 step: nil, beat: nil, by: nil)
            n.other = other; n.samples = s.samples
            a[id] = nil
            for k in anchors.issues.indices where anchors.issues[k].id == id { anchors.issues[k].suggestion = n }
        }
        func dropArrow(_ id: String, other: String?) {
            guard let s = r[id] else { return }
            for k in arrows.issues.indices where arrows.issues[k].id == id {
                var n = MGAnnotationArrowSuggestion.none(other == nil ? .form : .conflict, step: arrows.issues[k].step, beat: arrows.issues[k].beat,
                                                         by: arrows.issues[k].by, samples: s.samples)
                n.other = other
                arrows.issues[k].suggestion = n
            }
            r[id] = nil
        }
        func drop(_ id: String, other: String?) { if a[id] != nil { dropAnchor(id, other: other) } else { dropArrow(id, other: other) } }
        for _ in 0..<MGAnnotationAnchorRules.recheckRounds {
            guard !a.isEmpty, !r.isEmpty else { return }
            let aSet = a.compactMapValues { $0.anchorJSON }, rSet = r.compactMapValues { $0.anchorJSON }
            guard let c = recheck(aSet, rSet) else {
                for id in a.keys.sorted() { dropAnchor(id, other: nil) }
                for id in r.keys.sorted() { dropArrow(id, other: nil) }
                return
            }
            // Where each failing annotation's issue is: its step and beat.
            var at: [String: (step: Int?, beat: Int?)] = [:]
            for i in c.anchors where at[i.id] == nil { at[i.id] = (i.step, i.beat) }
            for i in c.arrows where at[i.id] == nil { at[i.id] = (i.step, i.beat) }
            func shownWith(_ id: String) -> Set<String> {
                guard let w = at[id] else { return [] }
                return Set(c.shown.filter { $0.step == w.step && $0.beat == w.beat }.flatMap(\.ids))
            }
            let suggested = Set(a.keys).union(r.keys)
            let bad = suggested.filter { at[$0] != nil }.sorted()
            let fresh = Set(at.keys).subtracting(before).subtracting(suggested).sorted()
            if bad.isEmpty && fresh.isEmpty { return }
            var drops: [(String, String)] = []
            for id in bad {
                let others = (a[id] != nil ? Set(r.keys) : Set(a.keys))
                let near = others.intersection(shownWith(id))
                if let o = (near.isEmpty ? others : near).sorted().first { drops.append((id, o)) }
                else { drops.append((id, id)) }
            }
            for f in fresh {
                let inView = suggested.intersection(shownWith(f))
                for id in (inView.isEmpty ? suggested : inView).sorted() { drops.append((id, f)) }
            }
            for (id, other) in drops where a[id] != nil || r[id] != nil { drop(id, other: other) }
        }
        for id in a.keys.sorted() { dropAnchor(id, other: r.keys.sorted().first ?? id) }
        for id in r.keys.sorted() { dropArrow(id, other: a.keys.sorted().first ?? id) }
    }
}
