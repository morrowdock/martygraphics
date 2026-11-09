// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import MartyGraphics

/// The arrow visibility rule (docs/SOLID-3D.md, "Arrow visibility"): samples along a drawn arrow's shaft and head,
/// tested from each still's camera with the anchor checks' line-of-sight rule; `annotation.arrow.hidden.<id>` and
/// `annotation.arrow.untested.<id>`; the suggested move and its re-check. Fixtures are new synthetic boxes and the
/// synthetic explainer in docs/fixtures/arrow-visibility (neutral names, no real-world claims).
final class ArrowVisibilityTests: XCTestCase {
    /// A closed 200 mm shell box with a 40 mm core box inside it, and a 40 mm box beside them.
    static let parts = #"{"id": "shell", "shape": {"box": {"size": [200, 200, 200]}}}, {"id": "core", "shape": {"box": {"size": [40, 40, 40]}}}, {"id": "side", "at": [400, 0, 0], "shape": {"box": {"size": [40, 40, 40]}}}"#

    func text(_ arrows: String, steps: String = #"[{"say": "Boxes."}]"#, parts: String = ArrowVisibilityTests.parts) -> String {
        #"{"v": 2, "kind": "assembly", "parts": [\#(parts)], "annotations": {"arrows": \#(arrows)}, "steps": \#(steps)}"#
    }
    func doc(_ t: String) throws -> MGSolidDocument { try MGSolidParser.document(data: Data(t.utf8)).get() }
    func report(_ t: String, _ profile: MGSolidProfile) -> MGSolidReport { MGSolidReport.check(data: Data(t.utf8), profile: profile, engine: nil) }
    func arrows(_ json: MGJSON) -> [[String: MGJSON]] {
        guard case .array(let a)? = json["arrowIssues"] else { return [] }
        return a.compactMap { if case .object(let o) = $0 { return o }; return nil }
    }
    func warnings(_ json: MGJSON) -> [String] {
        guard case .array(let a)? = json["warnings"] else { return [] }
        return a.compactMap { if case .string(let s)? = $0["reason"] { return s }; return nil }
    }

    // MARK: The rule

    /// An arrow inside a closed part is hidden by it, also when the arrow is anchored on that part (no own-part
    /// exception for arrows). Strict refuses with the view, the part in the way and the visible share; standard warns.
    func testAnArrowInsideAClosedPartIsRefused() throws {
        let t = text(#"[{"id": "f1", "meaning": "force", "from": {"part": "shell", "offset": [0, 0, -18]}, "to": {"part": "shell", "offset": [0, 0, 18]}}]"#)
        let strict = report(t, .strict)
        XCTAssertFalse(strict.ok)
        XCTAssertEqual(strict.reason, "annotation.arrow.hidden.f1")
        XCTAssertEqual(strict.part, "f1")
        guard case .object(let a)? = strict.json["arrow"] else { return XCTFail("no arrow detail") }
        XCTAssertEqual(a["by"], .string("shell"))
        XCTAssertEqual(a["step"], .number(1))
        XCTAssertEqual(a["visible"], .number(0))
        XCTAssertEqual(a["share"], .number(0))
        XCTAssertEqual(a["samples"], .number(Double(MGAnnotationArrowRules.shaftSamples + MGAnnotationArrowRules.headFractions.count)))
        XCTAssertEqual(a["meaning"], .string("force"))
        if case .string(let r)? = strict.json["repair"] { XCTAssertTrue(r.hasPrefix("Arrow f1 (step 1) is 0 % visible, hidden behind shell"), r) } else { XCTFail("repair") }
        let standard = report(t, .standard)
        XCTAssertTrue(standard.ok)
        XCTAssertEqual(warnings(standard.json), ["annotation.arrow.hidden.f1"])
        XCTAssertEqual(arrows(standard.json).count, 1)
        XCTAssertNil(standard.json["arrow"])
        // The compile does not refuse it (the rule needs each still's camera).
        guard case .success = MGSolidParser.document(data: Data(t.utf8), profile: .strict) else { return XCTFail("the strict compile refused it") }
    }

    /// Arrows in the open pass; an arrow that starts inside a part (a weight arrow from a body's centre) passes while at
    /// least half of it and its head show; an arrow whose head is inside a part is refused although most of it shows.
    func testHalfVisibleArrowsPassAndAHiddenHeadRefuses() throws {
        let open = text(#"[{"id": "f1", "meaning": "force", "from": {"part": "side", "offset": [0, 0, 30]}, "to": {"part": "side", "offset": [0, 0, 230]}}, {"id": "f2", "meaning": "flow", "from": {"part": "side", "point": "centre"}, "to": {"part": "side", "offset": [0, 0, -200]}}, {"id": "p1", "meaning": "pointer", "from": {"world": [250, -150, 200]}, "to": {"part": "side", "offset": [0, 0, 20]}, "text": "Side"}]"#)
        let ok = report(open, .strict)
        XCTAssertTrue(ok.ok, ok.reason ?? "")
        XCTAssertEqual(arrows(ok.json).count, 0)
        let head = text(#"[{"id": "f1", "meaning": "force", "from": {"world": [400, 0, 200]}, "to": {"part": "side", "point": "centre"}}]"#)
        let r = report(head, .strict)
        XCTAssertEqual(r.reason, "annotation.arrow.hidden.f1")
        guard case .object(let a)? = r.json["arrow"] else { return XCTFail("arrow") }
        XCTAssertEqual(a["headVisible"], .number(0))
        if case .number(let s)? = a["share"] { XCTAssertGreaterThanOrEqual(s, MGAnnotationArrowRules.minVisibleShare) } else { XCTFail("share") }
        XCTAssertEqual(a["by"], .string("side"))
        // The suggestion slides the arrow back along itself (world anchors move in the world) and passes once applied.
        guard case .object(let s)? = a["suggest"] else { return XCTFail("suggest") }
        guard case .object(let from)? = s["from"], case .object(let to)? = s["to"] else { return XCTFail("anchors") }
        XCTAssertNotNil(from["world"]); XCTAssertEqual(to["part"], .string("side"))
        let fixed = Self.applying(["f1": .object(s)], to: head)
        let after = report(fixed, .strict)
        XCTAssertTrue(after.ok, after.reason ?? "")
        XCTAssertEqual(arrows(after.json).count, 0)
    }

    /// The cut exception of the anchor checks: a view that cuts the arrow's part open shows the arrow inside it, and
    /// the parts inside the cut part's box do not hide it. Closed, the part hides it.
    func testACutOpenPartShowsTheArrowInside() throws {
        let arrow = #"[{"id": "f1", "meaning": "force", "from": {"part": "shell", "offset": [0, 0, -18]}, "to": {"part": "shell", "offset": [0, 0, 18]}}]"#
        let cut = text(arrow, steps: #"[{"say": "Cut open.", "section": {"normal": [0, -1, 0], "offset": 0, "parts": ["shell"]}}]"#)
        let d = try doc(cut)
        XCTAssertEqual(d.stepArrowIssues(), [])
        XCTAssertTrue(report(cut, .strict).ok)
        // Without the exception the core would hide the samples inside it: the line of sight crosses the core first.
        let cam = MGSolidFraming.clearView(d, shot: MGSolidShot.step(d, 0)!, aspect: 1.6).camera
        let eye = MGSolidStage.zUpToYUp.inverse.apply(cam.position)
        XCTAssertEqual(MGSolidFraming.OcclusionProbe.crossings(eye, .zero, d.assembly.part("core")!.mesh, after: 1e-9, before: 1).count, 1)
        // A ghosted shell (coverage 0.2) does not block; glass does not either.
        XCTAssertTrue(report(text(arrow, steps: #"[{"say": "Ghost.", "ghost": ["shell", "core"]}]"#), .strict).ok)
        let glass = ArrowVisibilityTests.parts.replacingOccurrences(of: #"{"id": "shell", "#, with: #"{"id": "shell", "material": "glass", "#)
        let g = report(text(arrow, parts: glass), .strict)
        XCTAssertEqual(g.reason, "annotation.arrow.hidden.f1", "the core still hides the samples inside it")
        XCTAssertEqual({ () -> MGJSON? in if case .object(let a)? = g.json["arrow"] { return a["by"] }; return nil }(), .string("core"))
    }

    /// A motion arrow shows its anchor's motion: it gets no move, and the report says why and what to do instead.
    func testAHiddenMotionArrowGetsNoMove() throws {
        let parts = #"{"id": "shell", "shape": {"box": {"size": [200, 200, 200]}}}, {"id": "wheel", "shape": {"shaft": {"radius": 30, "length": 10}}, "joint": {"revolute": [0, 0, 1]}, "drive": {"input": 1}}"#
        let t = text(#"[{"id": "m1", "meaning": "motion", "from": {"part": "wheel", "offset": [30, 0, 5]}}]"#, parts: parts)
        let r = report(t, .strict)
        XCTAssertEqual(r.reason, "annotation.arrow.hidden.m1")
        guard case .object(let a)? = r.json["arrow"] else { return XCTFail("arrow") }
        XCTAssertEqual(a["suggest"], .null)
        guard case .object(let n)? = a["noSuggest"] else { return XCTFail("noSuggest") }
        XCTAssertEqual(n["code"], .string("motion"))
        guard case .array(let alts)? = n["alternatives"] else { return XCTFail("alternatives") }
        XCTAssertEqual(alts.first, .string("Leave m1 out of step 1's annotate list."))
        XCTAssertEqual(alts.dropFirst().first, .string("Ghost `shell` in step 1."))
    }

    /// Over the view's budget an arrow is untested (and every later arrow of the view); strict refuses it. A sample
    /// whose line of sight meets no part box needs no test.
    func testOverTheBudgetAnArrowIsUntested() throws {
        let t = text(#"[{"id": "f1", "meaning": "force", "from": {"part": "shell", "offset": [0, 0, -18]}, "to": {"part": "shell", "offset": [0, 0, 18]}}, {"id": "f2", "meaning": "force", "from": {"part": "side", "offset": [0, 30, 30]}, "to": {"part": "side", "offset": [0, 30, 230]}}]"#)
        let d = try doc(t)
        let v = try XCTUnwrap(d.stepCheckViews().first)
        XCTAssertEqual(d.arrowIssues(v).map(\.id), ["f1"])
        XCTAssertEqual(d.arrowIssues(v).map(\.cause), [.hidden])
        let open = try doc(text(#"[{"id": "f2", "meaning": "force", "from": {"part": "side", "offset": [0, 30, 30]}, "to": {"part": "side", "offset": [0, 30, 230]}}]"#))
        XCTAssertEqual(open.arrowIssues(try XCTUnwrap(open.stepCheckViews().first), budget: 0), [])
        let none = d.arrowIssues(v, budget: 0)
        guard none.count == 2 else { return XCTFail("\(none)") }
        XCTAssertEqual(none.map(\.id), ["f1", "f2"])
        XCTAssertEqual(none.map(\.cause), [.untested, .untested])
        XCTAssertEqual(none.first?.reason, "annotation.arrow.untested.f1")
        XCTAssertTrue(none.first?.visibility.over ?? false)
        XCTAssertTrue(none.first?.fix.contains("budget") ?? false)
        if case .object(let o) = none[0].json { XCTAssertEqual(o["suggest"], .null); XCTAssertEqual(o["noSuggest"], .null) }
    }

    /// The samples: 16 along the shaft (a turn arrow's arc counts its chords), 3 along the head; none for an arrow the
    /// view does not draw.
    func testSamplesFollowTheDrawnPieces() throws {
        let line = MGSolidAnnotations.lineArrow(.zero, MGVec3(0, 0, 100), radius: 1)
        let s = try XCTUnwrap(MGArrowSamples(line, turn: false))
        XCTAssertEqual(s.shaft.count, MGAnnotationArrowRules.shaftSamples)
        XCTAssertEqual(s.head.count, 3)
        XCTAssertEqual(s.shaft.first!.z, 96.0 / 32, accuracy: 1e-9)   // the shaft ends at the head's base, 4 radii short
        XCTAssertEqual(s.head[1].z, 98, accuracy: 1e-9)
        // All head: a shaft shorter than its head has no shaft samples.
        XCTAssertEqual(MGArrowSamples(MGSolidAnnotations.lineArrow(.zero, MGVec3(0, 0, 2), radius: 1), turn: false)?.shaft.count, 0)
        XCTAssertNil(MGArrowSamples(MGSolidAnnotations.lineArrow(.zero, .zero, radius: 1), turn: false))
        XCTAssertNil(MGArrowSamples(MGSolidAnnotations.lineArrow(.zero, MGVec3(0, 0, 100), radius: 1, hidden: true), turn: false))
        // A turn arrow's arc.
        let n = MGSolidAnnotations.arcChords
        var pieces: [MGAnnotationPrimitive] = (0..<n).map { k in
            let a = Double(k) / Double(n) * 1.5 * .pi, b = Double(k + 1) / Double(n) * 1.5 * .pi
            return MGSolidAnnotations.segment(MGVec3(cos(a), sin(a), 0) * 50, MGVec3(cos(b), sin(b), 0) * 50, 1)
        }
        pieces.append(MGAnnotationPrimitive(shape: .cone, start: MGVec3(0, -50, 0), end: MGVec3(4, -50, 0), radius: 2.5, hidden: false))
        let arc = try XCTUnwrap(MGArrowSamples(pieces, turn: true))
        XCTAssertEqual(arc.shaft.count, MGAnnotationArrowRules.shaftSamples)
        for p in arc.shaft { XCTAssertEqual((p - MGVec3(0, 0, 0)).length, 50, accuracy: 1) }
        XCTAssertNil(MGArrowSamples(Array(pieces.dropLast()), turn: true))
    }

    // MARK: The re-check of suggested moves

    /// The fixed-point re-check: a move that still fails in the copy is searched again and then dropped (`framing`);
    /// a move that gives another annotation an issue is dropped as a `conflict` naming it; a copy that does not compile
    /// drops the set (`form`); a clean copy keeps every move.
    func testTheRecheckKeepsOnlyMovesThatHold() throws {
        let t = text(#"[{"id": "f1", "meaning": "force", "from": {"world": [400, 0, 200]}, "to": {"part": "side", "point": "centre"}}]"#)
        let d = try doc(t)
        let views = d.stepCheckViews()
        var base = MGAnnotationArrowReport()
        base.issues = views.flatMap { d.arrowIssues($0) }
        XCTAssertEqual(base.issues.map(\.id), ["f1"])
        base.suggest(d, views: views, budget: MGSuggestionBudget())
        XCTAssertNotNil(base.issues[0].suggestion?.from)
        let issue = base.issues[0]
        func run(_ recheck: @escaping ([String: MGJSON]) -> MGArrowRecheck?) -> MGAnnotationArrowSuggestion? {
            var r = base
            r.verify(anchorIssues: [], recheck)
            return r.issues[0].suggestion
        }
        let clean = run { _ in MGArrowRecheck(arrows: [], anchors: [], search: { _, _ in [:] }) }
        XCTAssertEqual(clean, issue.suggestion)
        XCTAssertEqual(run { _ in nil }?.cause, .form)
        var calls = 0
        let stuck = run { _ in
            calls += 1
            return MGArrowRecheck(arrows: [issue], anchors: [], search: { list, _ in Dictionary(uniqueKeysWithValues: list.map { ($0.id, issue.suggestion!) }) })
        }
        XCTAssertEqual(stuck?.cause, .framing)
        XCTAssertLessThanOrEqual(calls, MGAnnotationAnchorRules.recheckRounds)
        let other = MGAnnotationAnchorIssue(id: "l9", kind: "label", cause: .occluded, part: "side", by: "shell", step: 0, beat: nil,
                                            point: .zero, distance: nil, tolerance: nil)
        let conflict = run { _ in
            MGArrowRecheck(arrows: [], anchors: [other], shown: [(0, nil, ["f1", "l9"])], search: { _, _ in [:] })
        }
        XCTAssertEqual(conflict?.cause, .conflict)
        XCTAssertEqual(conflict?.other, "l9")
        // An annotation that already had an issue does not count against a move.
        var known = base
        known.verify(anchorIssues: ["l9"]) { _ in MGArrowRecheck(arrows: [], anchors: [other], search: { _, _ in [:] }) }
        XCTAssertEqual(known.issues[0].suggestion, issue.suggestion)
    }

    // MARK: Review fixes (PR #44)

    /// Review repro: the arrow's ends ride on parts that turn differently between the two steps that show it. An
    /// offset taken into each end's frame at step 1 moves the ends by different world offsets at step 2, so the moved
    /// arrow would point another way there (25.456 mm became 380.791 mm). A force or flow move must keep the authored
    /// vector in every view; here none does, so `suggest` is null with code `pose`.
    func testAMoveMustKeepTheArrowVectorInEveryView() throws {
        let t = #"{"v":2,"kind":"assembly","parts":[{"id":"shell","shape":{"box":{"size":[200,200,200]}}},{"id":"end","at":[0,0,0],"shape":{"box":{"size":[1,1,1]}}}],"annotations":{"arrows":[{"id":"push","meaning":"force","from":{"part":"shell","offset":[0,0,-18]},"to":{"part":"end","offset":[0,0,18]}}]},"steps":[{"say":"Start."},{"say":"Turn.","pose":{"end":{"rot":[1,1,1,120]}}}]}"#
        let r = report(t, .strict)
        XCTAssertEqual(r.reason, "annotation.arrow.hidden.push")
        let issues = arrows(r.json)
        XCTAssertFalse(issues.isEmpty)
        for i in issues {
            if let s = i["suggest"], s != .null {
                // Any move printed keeps the vector in both steps.
                let d = try doc(t), fixed = try doc(Self.applying(["push": s], to: t))
                for k in d.steps.indices {
                    let pose = d.assembly.pose(MGSolidShot.step(d, k)!.params)
                    let a = d.annotations.arrow("push")!, m = fixed.annotations.arrow("push")!
                    XCTAssertTrue(MGAnnotationArrowRules.keepsVector(a.to!.world(pose) - a.from!.world(pose), m.to!.world(pose) - m.from!.world(pose)), "step \(k + 1)")
                }
            } else {
                guard case .object(let n)? = i["noSuggest"] else { return XCTFail("noSuggest") }
                XCTAssertEqual(n["code"], .string("pose"))
                guard case .array(let alts)? = n["alternatives"] else { return XCTFail("alternatives") }
                XCTAssertEqual(alts.count, 3)
            }
        }
        guard case .object(let a)? = r.json["arrow"] else { return XCTFail("arrow") }
        XCTAssertEqual(a["suggest"], .null)
        // The final check also drops a move that does not keep the vector (one made by hand here): cause `pose`.
        let d = try doc(t)
        let views = d.stepCheckViews().filter { d.showsArrow($0.view) }
        var rep = MGAnnotationArrowReport()
        rep.issues = views.flatMap { d.arrowIssues($0) }
        let o = MGVec3(-259.808, 0, 0)
        let from = MGAnnotationPoint(anchor: .offset(part: "shell", MGVec3(0, 0, -18) + o), local: MGVec3(0, 0, -18) + o)
        let to = MGAnnotationPoint(anchor: .offset(part: "end", MGVec3(0, 0, 18) + o), local: MGVec3(0, 0, 18) + o)
        rep.issues[0].suggestion = MGAnnotationArrowSuggestion(from: from, to: to, offset: o, full: true, cause: nil, step: nil, beat: nil, by: nil)
        rep.measure(d, views: views)
        XCTAssertEqual(rep.issues[0].suggestion?.cause, .pose)
        XCTAssertNil(rep.issues[0].suggestion?.anchorJSON)
        // The tolerance: the precision epsilon at the vector plus the rounding of both ends.
        XCTAssertTrue(MGAnnotationArrowRules.keepsVector(MGVec3(18, 0, 18), MGVec3(18.0017, 0, 18)))
        XCTAssertFalse(MGAnnotationArrowRules.keepsVector(MGVec3(18, 0, 18), MGVec3(18.003, 0, 18)))
    }

    /// One search budget per report: the first searches and the re-check's searches draw from the same object, so a
    /// report spends at most `suggestDocumentTests` on them together. With an empty budget nothing is searched, and the
    /// re-check gets that same budget.
    func testTheReportSharesOneSearchBudget() throws {
        let t = text(#"[{"id": "f1", "meaning": "force", "from": {"world": [400, 0, 200]}, "to": {"part": "side", "point": "centre"}}]"#)
        let d = try doc(t)
        let views = d.stepCheckViews().filter { d.showsArrow($0.view) }
        var empty = MGAnnotationArrowReport()
        empty.issues = views.flatMap { d.arrowIssues($0) }
        let none = MGSuggestionBudget(0)
        var seen: [MGSuggestionBudget] = []
        empty.repair(d, views: views, anchorIssues: [], budget: none) { _, b in seen.append(b); return nil }
        XCTAssertEqual(empty.issues[0].suggestion?.cause, .budget)
        XCTAssertTrue(seen.isEmpty, "nothing to re-check without a move")
        var full = MGAnnotationArrowReport()
        full.issues = empty.issues.map { var i = $0; i.suggestion = nil; return i }
        let budget = MGSuggestionBudget(MGAnnotationArrowRules.suggestDocumentTests)
        full.repair(d, views: views, anchorIssues: [], budget: budget) { moves, b in
            seen.append(b)
            guard case .success(let c) = MGSolidParser.document(json: MGSolidDocument.replacingArrows(d.source, moves), library: d.library) else { return nil }
            return MGSolidReport.arrowRecheck(c, budget: b)
        }
        XCTAssertFalse(seen.isEmpty)
        XCTAssertTrue(seen.allSatisfy { $0 === budget })
        XCTAssertLessThan(budget.left, MGAnnotationArrowRules.suggestDocumentTests)
        XCTAssertNotNil(full.issues[0].suggestion?.anchorJSON)
    }

    // MARK: Joint check of every printed suggestion (anchors and arrows together)

    /// One anchor suggestion and one arrow move that each pass alone but interfere together: the union check keeps
    /// both when the joint copy is clean, drops the one that still fails (`conflict`, `other` the suggestion of the other
    /// family shown with it), drops the suggestions shown with an annotation that gets a new issue (`other` naming it),
    /// and drops all on a refused copy (`form`). After a drop the remaining set is checked again; a union of one family
    /// is checked too.
    func testAnchorAndArrowSuggestionsAreCheckedTogether() throws {
        let t = text(#"[{"id": "f1", "meaning": "force", "from": {"world": [400, 0, 200]}, "to": {"part": "side", "point": "centre"}}]"#)
        let d = try doc(t)
        let views = d.stepCheckViews()
        var arrowsBase = MGAnnotationArrowReport()
        arrowsBase.issues = views.flatMap { d.arrowIssues($0) }
        arrowsBase.suggest(d, views: views, budget: MGSuggestionBudget())
        let move = try XCTUnwrap(arrowsBase.issues[0].suggestion)
        XCTAssertNotNil(move.anchorJSON)
        var label = MGAnnotationAnchorIssue(id: "l1", kind: "label", cause: .occluded, part: "side", by: "shell", step: 0, beat: nil,
                                            point: .zero, distance: nil, tolerance: nil)
        label.suggestion = MGAnnotationAnchorSuggestion(part: "side", offset: MGVec3(0, 0, 20), onCut: false, cause: nil, step: nil, beat: nil, by: nil)
        var anchorsBase = MGAnnotationAnchorReport()
        anchorsBase.issues = [label]
        func run(_ recheck: @escaping ([String: MGJSON], [String: MGJSON]) -> MGArrowRecheck?) -> (MGAnnotationAnchorSuggestion?, MGAnnotationArrowSuggestion?, Int) {
            var a = anchorsBase, r = arrowsBase, calls = 0
            MGSuggestionUnion.verifyTogether(anchors: &a, arrows: &r) { am, rm in
                calls += 1
                XCTAssertEqual(am.keys.sorted() + rm.keys.sorted(), (am.isEmpty ? [] : ["l1"]) + (rm.isEmpty ? [] : ["f1"]))
                return recheck(am, rm)
            }
            return (a.issues[0].suggestion, r.issues[0].suggestion, calls)
        }
        // Clean union: both kept, one check.
        let clean = run { _, _ in MGArrowRecheck(arrows: [], anchors: [], search: { _, _ in [:] }) }
        XCTAssertEqual(clean.0, label.suggestion); XCTAssertEqual(clean.1, move); XCTAssertEqual(clean.2, 1)
        // The arrow move hides the label in the union (the framing changes): the label's suggestion is the conflict.
        var stillHidden = label; stillHidden.suggestion = nil
        let hidden = run { am, _ in
            MGArrowRecheck(arrows: [], anchors: am.isEmpty ? [] : [stillHidden], shown: [(0, nil, ["l1", "f1"])], search: { _, _ in [:] })
        }
        XCTAssertNil(hidden.0?.anchorJSON); XCTAssertEqual(hidden.0?.cause, .conflict); XCTAssertEqual(hidden.0?.other, "f1")
        XCTAssertEqual(hidden.1, move, "the arrow move stays: alone it was checked")
        XCTAssertEqual(hidden.2, 2, "the remaining arrow move is checked again on its own")
        // An annotation without an issue gets one in the union: the suggestions shown with it are dropped.
        let fresh = MGAnnotationAnchorIssue(id: "l9", kind: "label", cause: .occluded, part: "side", by: "shell", step: 0, beat: nil,
                                            point: .zero, distance: nil, tolerance: nil)
        let both = run { _, _ in MGArrowRecheck(arrows: [], anchors: [fresh], shown: [(0, nil, ["l1", "f1", "l9"])], search: { _, _ in [:] }) }
        XCTAssertEqual(both.0?.cause, .conflict); XCTAssertEqual(both.0?.other, "l9")
        XCTAssertEqual(both.1?.cause, .conflict); XCTAssertEqual(both.1?.other, "l9")
        // A refused copy.
        let refused = run { _, _ in nil }
        XCTAssertEqual(refused.0?.cause, .form); XCTAssertEqual(refused.1?.cause, .form)
        // One family only: still checked with every rule; a clean copy keeps the move.
        var a = MGAnnotationAnchorReport(), r = arrowsBase, calls = 0
        MGSuggestionUnion.verifyTogether(anchors: &a, arrows: &r) { am, rm in
            calls += 1
            XCTAssertTrue(am.isEmpty); XCTAssertEqual(rm.keys.sorted(), ["f1"])
            return MGArrowRecheck(arrows: [], anchors: [], search: { _, _ in [:] })
        }
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(r.issues[0].suggestion, move)
        // A suggestion that still fails with no other family in the union: `framing`.
        var a2 = MGAnnotationAnchorReport(), r2 = arrowsBase
        MGSuggestionUnion.verifyTogether(anchors: &a2, arrows: &r2) { _, rm in
            MGArrowRecheck(arrows: rm.isEmpty ? [] : arrowsBase.issues, anchors: [], search: { _, _ in [:] })
        }
        XCTAssertEqual(r2.issues[0].suggestion?.cause, .framing)
        XCTAssertNil(r2.issues[0].suggestion?.other)
    }

    /// Re-check repro (PR #44): a 128 mm core box, a blocker beside it, an off-part label and a clean force arrow. The
    /// label's anchor suggestion passes the anchor rules, but in the framing it causes the clean arrow is 0 % visible.
    /// The report prints only anchor suggestions, and the joint check still runs every rule on the union: the label's
    /// suggestion is dropped (`conflict`, `other` the arrow), so applying every printed suggestion breaks nothing.
    func testAnAnchorOnlyUnionIsCheckedAgainstTheArrows() throws {
        let t = #"{"v":2,"kind":"assembly","parts":[{"id":"core","shape":{"box":{"size":[128,128,128]}}},{"id":"blocker","at":[-56,7,-37],"shape":{"box":{"size":[88,72,82]}}}],"annotations":{"arrows":[{"id":"good","meaning":"force","from":{"world":[-66,-60,-65]},"to":{"world":[-66,-60,-61]}}],"labels":[{"id":"label","text":"Core","at":{"part":"core","offset":[495,-956,-910]}}]},"steps":[{"say":"Core.","orbit":-158}]}"#
        let r = report(t, .strict)
        XCTAssertEqual(r.reason, "annotation.anchor.off.label")
        XCTAssertEqual(arrows(r.json).count, 0, "the arrow is clean before")
        // The anchor family's own suggestion, applied, hides the clean arrow.
        let stale: MGJSON = .object(["part": .string("core"), "offset": .array([.number(-63.969), .number(-63.996), .number(-59.794)])])
        let staleCopy = report(SolidAnchorSuggestTests.applying(["label": stale], to: t), .strict)
        XCTAssertEqual(staleCopy.reason, "annotation.arrow.hidden.good")
        // The report does not print it: dropped in the joint check.
        guard case .object(let a)? = r.json["anchor"] else { return XCTFail("anchor") }
        XCTAssertEqual(a["suggest"], .null)
        guard case .object(let n)? = a["noSuggest"] else { return XCTFail("noSuggest") }
        XCTAssertEqual(n["code"], .string("conflict")); XCTAssertEqual(n["other"], .string("good"))
        XCTAssertEqual(report(t, .strict).json, r.json, "deterministic")
    }

    /// The opposite case: only arrow moves are printed candidates, and the move hides a clean label in the framing it
    /// causes. The move is not printed (`conflict`, `other` the label).
    func testAnArrowOnlyUnionIsCheckedAgainstTheLabels() throws {
        let t = #"{"v":2,"kind":"assembly","parts":[{"id":"core","shape":{"box":{"size":[128,128,128]}}},{"id":"blocker","at":[-56,7,-37],"shape":{"box":{"size":[88,72,82]}}}],"annotations":{"labels":[{"id":"label","text":"Core","at":{"part":"core","offset":[-63.969,-63.996,-59.794]}}],"arrows":[{"id":"far","meaning":"force","from":{"world":[-900,300,600]},"to":{"world":[-56,7,-37]}}]},"steps":[{"say":"Core.","orbit":-158}]}"#
        let r = report(t, .strict)
        XCTAssertEqual(r.reason, "annotation.arrow.hidden.far")
        if case .array(let ai)? = r.json["anchorIssues"] { XCTAssertEqual(ai.count, 0, "the label is clean before") } else { XCTFail("anchorIssues") }
        // The arrow family's first move, applied, hides the clean label.
        let d = try doc(t)
        let views = d.stepCheckViews()
        var first = MGAnnotationArrowReport()
        first.issues = views.flatMap { d.arrowIssues($0) }
        first.suggest(d, views: views, budget: MGSuggestionBudget())
        let move = try XCTUnwrap(first.issues[0].suggestion?.anchorJSON)
        let moved = report(Self.applying(["far": move], to: t), .strict)
        if case .array(let ai)? = moved.json["anchorIssues"] { XCTAssertEqual(ai.count, 1, "the move hides the label") } else { XCTFail("anchorIssues") }
        guard case .object(let a)? = r.json["arrow"] else { return XCTFail("arrow") }
        XCTAssertEqual(a["suggest"], .null)
        guard case .object(let n)? = a["noSuggest"] else { return XCTFail("noSuggest") }
        XCTAssertEqual(n["code"], .string("conflict")); XCTAssertEqual(n["other"], .string("label"))
    }

    /// The round-2f synthetic explainer holds anchor suggestions and a pointer move in one report: every printed
    /// suggestion applied at once clears every suggested annotation and gives no other annotation an issue.
    func testEveryPrintedSuggestionAppliesAtOnce() throws {
        let url = XFix.root.appendingPathComponent("docs/fixtures/anchor-suggest/figure-engines.explainer.json")
        let source = try String(contentsOf: url, encoding: .utf8)
        let before = MGExplainerReport.check(data: Data(source.utf8), profile: .strict, engine: nil)
        func list(_ json: MGJSON, _ key: String) -> [[String: MGJSON]] {
            guard case .array(let a)? = json[key] else { return [] }
            return a.compactMap { if case .object(let o) = $0 { return o }; return nil }
        }
        var anchorMoves: [String: MGJSON] = [:], arrowMoves: [String: MGJSON] = [:]
        for i in list(before.json, "anchorIssues") { if case .string(let id)? = i["id"], let s = i["suggest"], s != .null { anchorMoves[id] = s } }
        for i in list(before.json, "arrowIssues") { if case .string(let id)? = i["id"], let s = i["suggest"], s != .null { arrowMoves[id] = s } }
        XCTAssertFalse(anchorMoves.isEmpty)
        let hadIssue = Set((list(before.json, "anchorIssues") + list(before.json, "arrowIssues")).compactMap { i -> String? in
            if case .string(let id)? = i["id"] { return id }; return nil })
        guard case .object(var root)? = Self.json(source), let solid = root["solid"] else { return XCTFail("json") }
        root["solid"] = MGSolidDocument.replacingAnchors(MGSolidDocument.replacingArrows(solid, arrowMoves), anchorMoves)
        let after = MGExplainerReport.check(data: Data(MGJSON.object(root).canonicalString.utf8), profile: .strict, engine: nil, suggest: false)
        let left = Set((list(after.json, "anchorIssues") + list(after.json, "arrowIssues")).compactMap { i -> String? in
            if case .string(let id)? = i["id"] { return id }; return nil })
        XCTAssertTrue(left.isDisjoint(with: Set(anchorMoves.keys).union(arrowMoves.keys)), "\(left.sorted())")
        XCTAssertTrue(left.isSubset(of: hadIssue), "new issues: \(left.subtracting(hadIssue).sorted())")
    }

    // MARK: The synthetic explainer (an arrow from a nozzle to its intake lip, inside the casing)

    static var fixture: URL {
        XFix.root.appendingPathComponent("docs/fixtures/arrow-visibility/arrow-in-casing.explainer.json")
    }

    /// The thrust arrow of an engine on a figure's back runs inside the engine casing: strict refuses it in the beat
    /// that shows it, names the casing and the visible share, and suggests a move; applied, the copy passes strict with
    /// no arrow or anchor issue. Standard warns. The report is the same on every run.
    func testAnArrowInsideAnEngineCasingIsRefusedAndTheMoveClearsIt() throws {
        let source = try String(contentsOf: Self.fixture, encoding: .utf8)
        let strict = MGExplainerReport.check(data: Data(source.utf8), profile: .strict, engine: nil)
        XCTAssertFalse(strict.ok)
        XCTAssertEqual(strict.reason, "annotation.arrow.hidden.push")
        XCTAssertEqual(strict.location?.beat, 1)
        XCTAssertEqual(strict.location?.id, "push")
        guard case .object(let a)? = strict.json["arrow"] else { return XCTFail("arrow") }
        XCTAssertEqual(a["beat"], .number(2))
        XCTAssertEqual(a["by"], .string("engine.casing"))
        if case .number(let s)? = a["share"] { XCTAssertLessThan(s, MGAnnotationArrowRules.minVisibleShare) } else { XCTFail("share") }
        guard case .object(let s)? = a["suggest"] else { return XCTFail("suggest") }
        XCTAssertEqual(MGExplainerReport.check(data: Data(source.utf8), profile: .strict, engine: nil).json, strict.json, "deterministic")
        let standard = MGExplainerReport.check(data: Data(source.utf8), profile: .standard, engine: nil)
        XCTAssertTrue(standard.ok)
        XCTAssertEqual(warnings(standard.json), ["annotation.arrow.hidden.push"])
        // Applied to a copy of the solid: strict passes, with no arrow or anchor issue.
        guard case .object(var root)? = Self.json(source), let solid = root["solid"] else { return XCTFail("json") }
        root["solid"] = MGSolidDocument.replacingArrows(solid, ["push": .object(s)])
        let fixed = MGJSON.object(root).canonicalString
        let after = MGExplainerReport.check(data: Data(fixed.utf8), profile: .strict, engine: nil)
        XCTAssertTrue(after.ok, after.reason ?? "")
        XCTAssertEqual(arrows(after.json).count, 0)
        if case .array(let anchors)? = after.json["anchorIssues"] { XCTAssertEqual(anchors.count, 0) } else { XCTFail("anchorIssues") }
    }

    /// Replaces each arrow's anchors in an assembly's text with its `suggest`.
    static func applying(_ moves: [String: MGJSON], to text: String) -> String {
        guard let json = json(text) else { return text }
        return MGSolidDocument.replacingArrows(json, moves).canonicalString
    }

    static func json(_ text: String) -> MGJSON? {
        guard let o = try? JSONSerialization.jsonObject(with: Data(text.utf8)) else { return nil }
        return MGJSON(any: o)
    }
}
