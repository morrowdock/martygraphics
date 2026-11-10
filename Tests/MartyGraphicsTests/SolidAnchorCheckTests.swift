// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import MartyGraphics

/// The anchor rules of labels and pointers (docs/SOLID-3D.md, "Anchor checks"): an anchor off its part
/// (`annotation.anchor.off.<id>`), and an anchor a step or beat still does not show (`annotation.anchor.hidden.<id>`:
/// occluded, hidden, ghosted, off screen), with the repair detail. Fixtures are new synthetic boxes.
final class SolidAnchorCheckTests: XCTestCase {
    /// A closed 200 mm shell box with a 40 mm core box inside it, and a 40 mm box beside them.
    static let parts = #"{"id": "shell", "shape": {"box": {"size": [200, 200, 200]}}}, {"id": "core", "shape": {"box": {"size": [40, 40, 40]}}}, {"id": "side", "at": [400, 0, 0], "shape": {"box": {"size": [40, 40, 40]}}}"#

    func text(_ annotations: String, steps: String = #"[{"say": "Boxes."}]"#) -> String {
        #"{"v": 2, "kind": "assembly", "parts": [\#(Self.parts)], "annotations": \#(annotations), "steps": \#(steps)}"#
    }
    func doc(_ t: String, file: StaticString = #filePath, line: UInt = #line) throws -> MGSolidDocument {
        switch MGSolidParser.document(data: Data(t.utf8)) {
        case .success(let d): return d
        case .failure(let e): XCTFail("refused: \(e)", file: file, line: line); throw e
        }
    }
    func report(_ t: String, _ profile: MGSolidProfile) -> MGSolidReport { MGSolidReport.check(data: Data(t.utf8), profile: profile, engine: nil) }
    func issues(_ r: MGSolidReport) -> [[String: MGJSON]] {
        guard case .array(let a)? = r.json["anchorIssues"] else { return [] }
        return a.compactMap { if case .object(let o) = $0 { return o }; return nil }
    }
    func warnings(_ r: MGSolidReport) -> [String] {
        guard case .array(let a)? = r.json["warnings"] else { return [] }
        return a.compactMap { if case .string(let s)? = $0["reason"] { return s }; return nil }
    }

    // MARK: Off part

    func testAnAnchorFarFromItsPartWarnsAndStrictRefusesWithTheDistance() throws {
        let t = text(#"{"labels": [{"id": "l1", "at": {"part": "side", "offset": [0, 0, 200]}, "text": "Side box"}]}"#)
        let standard = report(t, .standard)
        XCTAssertTrue(standard.ok)
        XCTAssertTrue(warnings(standard).contains("annotation.anchor.off.l1"))
        let strict = report(t, .strict)
        XCTAssertFalse(strict.ok)
        XCTAssertEqual(strict.reason, "annotation.anchor.off.l1")
        XCTAssertEqual(strict.part, "l1")
        guard case .object(let a)? = strict.json["anchor"] else { return XCTFail("no anchor detail") }
        XCTAssertEqual(a["cause"], .string("offpart"))
        XCTAssertEqual(a["part"], .string("side"))
        XCTAssertEqual(a["distance"], .number(180))
        // Tolerance: max(5 % of the side box's diagonal, 0.5 % of the model's diagonal).
        let d = try doc(t)
        let tol = max(MGAnnotationAnchorRules.partShare * MGVec3(40, 40, 40).length, MGAnnotationAnchorRules.modelShare * d.annotations.diagonal)
        if case .number(let got)? = a["tolerance"] { XCTAssertEqual(got, (tol * 1000).rounded() / 1000, accuracy: 1e-9) } else { XCTFail("tolerance") }
        XCTAssertEqual(a["step"], .null)
        if case .string(let fix)? = a["fix"] { XCTAssertTrue(fix.contains("world"), fix) } else { XCTFail("fix") }
        // The compile's strict profile refuses it too (it needs no camera).
        guard case .failure(let e) = MGSolidParser.document(data: Data(t.utf8), profile: .strict) else { return XCTFail("strict compile") }
        XCTAssertEqual(e.reason, "annotation.anchor.off.l1")
    }

    func testAnchorsOnOrNearTheirPartPass() throws {
        // 2 mm above the top face (inside the tolerance), the centre, the origin and a world point.
        let t = text(#"{"labels": [{"id": "l1", "at": {"part": "side", "offset": [0, 0, 22]}, "text": "Near"}, {"id": "l2", "at": {"part": "side", "point": "centre"}, "text": "Centre"}, {"id": "l3", "at": "side", "text": "Origin"}, {"id": "l4", "at": {"world": [0, 0, 900]}, "text": "Free text"}]}"#)
        XCTAssertEqual(try doc(t).offPartAnchors, [])
        // Just outside the tolerance.
        let d = try doc(t)
        let tol = max(MGAnnotationAnchorRules.partShare * MGVec3(40, 40, 40).length, MGAnnotationAnchorRules.modelShare * d.annotations.diagonal)
        let far = text(#"{"labels": [{"id": "l1", "at": {"part": "side", "offset": [0, 0, \#(20 + tol + 0.5)]}, "text": "Far"}]}"#)
        XCTAssertEqual(try doc(far).offPartAnchors.map(\.id), ["l1"])
    }

    func testAPointerTipMustBeOnItsPartButItsTailIsFree() throws {
        let tipOff = text(#"{"arrows": [{"id": "a1", "meaning": "pointer", "from": {"world": [400, 0, 600]}, "to": {"part": "side", "offset": [0, 0, 60]}, "text": "Side box"}]}"#)
        XCTAssertEqual(report(tipOff, .strict).reason, "annotation.anchor.off.a1")
        let tailOff = text(#"{"arrows": [{"id": "a1", "meaning": "pointer", "from": {"part": "side", "offset": [0, 0, 300]}, "to": "side", "text": "Side box"}]}"#)
        XCTAssertEqual(try doc(tailOff).offPartAnchors, [])
        // Force, flow and motion arrows and dimensions are not tested.
        let flow = text(#"{"arrows": [{"id": "a1", "meaning": "flow", "from": {"part": "side", "offset": [0, 0, 300]}, "to": {"part": "side", "offset": [0, 0, 600]}}]}"#)
        XCTAssertEqual(try doc(flow).offPartAnchors, [])
    }

    // MARK: Hidden in a step

    func testAnAnchorInsideAClosedPartIsOccludedByIt() throws {
        let t = text(#"{"labels": [{"id": "l1", "at": {"part": "core", "point": "centre"}, "text": "Core"}]}"#)
        let standard = report(t, .standard)
        XCTAssertTrue(standard.ok, "the standard profile only warns")
        // The labelled core is wholly inside its shell, so it covers 0 px in every still (`unit.small.core`), and as the
        // step's subject it misses its floors (`framing.subject.small.step.1`, repair: ghost the shell).
        XCTAssertEqual(warnings(standard), ["annotation.anchor.hidden.l1", "framing.subject.small.step.1", "unit.small.core"])
        XCTAssertEqual(issues(standard).first?["cause"], .string("occluded"))
        XCTAssertEqual(issues(standard).first?["by"], .string("shell"))
        XCTAssertEqual(issues(standard).first?["step"], .number(1))
        let strict = report(t, .strict)
        XCTAssertEqual(strict.reason, "annotation.anchor.hidden.l1")
        guard case .object(let a)? = strict.json["anchor"] else { return XCTFail("no anchor detail") }
        XCTAssertEqual(a["by"], .string("shell"))
        if case .string(let fix)? = a["fix"] { XCTAssertTrue(fix.contains("ghost `shell`"), fix) } else { XCTFail("fix") }
        // From every side.
        let d = try doc(t)
        for (yaw, pitch) in [(0.0, 0.0), (90, 10), (200, 24), (32, 28), (0, 88), (0, -80)] {
            let cam = MGSolidCamera(target: .zero, yaw: yaw, pitch: pitch, distance: 1200)
            let r = d.anchorIssues(view: d.view(step: 0), params: d.defaults, camera: cam, width: 1280, height: 800, step: 0, beat: nil)
            XCTAssertEqual(r.issues.map(\.cause), [.occluded], "yaw \(yaw) pitch \(pitch)")
        }
    }

    func testTheAnchorsOwnSurfaceNeverHidesIt() throws {
        // The shell's centre is inside the shell and inside the core: the first surface on the line of sight is the
        // shell's own, so the dot shows on the shell.
        let t = text(#"{"labels": [{"id": "l1", "at": {"part": "shell", "point": "centre"}, "text": "Shell"}, {"id": "l2", "at": {"part": "shell", "offset": [0, 0, 100]}, "text": "Top face"}]}"#)
        XCTAssertEqual(try doc(t).stepAnchorIssues().issues, [])
        XCTAssertTrue(report(t, .strict).ok)
    }

    func testGhostingTheBlockerShowsTheAnchorAndGhostingTheAnchorsPartRefuses() throws {
        let labels = #"{"labels": [{"id": "l1", "at": {"part": "core", "point": "centre"}, "text": "Core"}]}"#
        XCTAssertTrue(report(text(labels, steps: #"[{"say": "Inside.", "ghost": ["shell"]}]"#), .strict).ok)
        let ghosted = report(text(labels, steps: #"[{"say": "Inside.", "ghost": ["shell", "core"]}]"#), .strict)
        XCTAssertEqual(ghosted.reason, "annotation.anchor.hidden.l1")
        XCTAssertEqual(issues(ghosted).first?["cause"], .string("ghosted"))
    }

    func testACutOpenPartShowsItsInside() throws {
        // The hero camera looks from kernel -Y; the section removes y < 0 of the shell. The shell's centre lies on the
        // cut face, inside the core: the core is inside the shell's box, so it does not hide it.
        let labels = #"{"labels": [{"id": "l1", "at": {"part": "shell", "point": "centre"}, "text": "Inside the shell"}]}"#
        let cut = text(labels, steps: #"[{"say": "Cut open.", "section": {"normal": [0, -1, 0], "offset": 0, "parts": ["shell"]}}]"#)
        let d = try doc(cut)
        XCTAssertEqual(d.stepAnchorIssues().issues, [])
        XCTAssertTrue(report(cut, .strict).ok)
        // Without the exception the core would be the first surface: the line of sight crosses it first.
        let cam = MGSolidFraming.clearView(d, shot: MGSolidShot.step(d, 0)!, aspect: 1.6).camera
        let eye = MGSolidStage.zUpToYUp.inverse.apply(cam.position)
        let hits = MGSolidFraming.OcclusionProbe.crossings(eye, .zero, d.assembly.part("core")!.mesh, after: 1e-9, before: 1)
        XCTAssertEqual(hits.count, 1)
        // A part outside the cut part still hides it: the core is seen through the cut, the side box is not inside.
        let core = text(#"{"labels": [{"id": "l1", "at": {"part": "core", "point": "centre"}, "text": "Core"}]}"#,
                        steps: #"[{"say": "Cut open.", "section": {"normal": [0, -1, 0], "offset": 0, "parts": ["shell"]}}]"#)
        XCTAssertEqual(try doc(core).stepAnchorIssues().issues, [], "the core's own surface is first through the cut")
    }

    func testHiddenAndOffScreenCauses() throws {
        let t = text(#"{"labels": [{"id": "l1", "at": {"part": "side", "offset": [0, 0, 20]}, "text": "Side box"}]}"#)
        let d = try doc(t)
        var v = d.view(step: 0)
        let cam = MGSolidCamera(target: MGVec3(400, 0, 0), yaw: 32, pitch: 28, distance: 600)
        XCTAssertEqual(d.anchorIssues(view: v, params: d.defaults, camera: cam, width: 1280, height: 800, step: 0, beat: nil).issues, [])
        // The camera looks far to the right of the anchor.
        let away = MGSolidCamera(target: MGVec3(4000, 0, 0), yaw: 0, pitch: 0, distance: 300)
        XCTAssertEqual(d.anchorIssues(view: v, params: d.defaults, camera: away, width: 1280, height: 800, step: 0, beat: nil).issues.map(\.cause),
                       [.offScreen])
        // A hidden part (a view built in code; the compile refuses a step that hides a part its annotation names).
        v.parts["side"]?.hidden = true
        XCTAssertEqual(d.anchorIssues(view: v, params: d.defaults, camera: cam, width: 1280, height: 800, step: 0, beat: nil).issues.map(\.cause),
                       [.hidden])
    }

    func testOverTheTriangleBudgetAnAnchorIsUntested() throws {
        let t = text(#"{"labels": [{"id": "l1", "at": {"part": "core", "point": "centre"}, "text": "Core"}, {"id": "l2", "at": {"part": "side", "offset": [0, 0, 20]}, "text": "Side box"}]}"#)
        let d = try doc(t)
        let cam = MGSolidCamera(target: MGVec3(200, 0, 0), yaw: 32, pitch: 28, distance: 1500)
        let full = d.anchorIssues(view: d.view(step: 0), params: d.defaults, camera: cam, width: 1280, height: 800, step: 0, beat: nil)
        XCTAssertEqual(full.issues.map(\.id), ["l1"]); XCTAssertTrue(full.untested.isEmpty)
        // Budget 0: no line-of-sight test runs; both anchors are issues with cause `untested`, none is called visible.
        let none = d.anchorIssues(view: d.view(step: 0), params: d.defaults, camera: cam, width: 1280, height: 800, step: 0, beat: nil,
                                  stage: MGSolidStage.zUpToYUp, budget: 0)
        XCTAssertEqual(none.issues.map(\.cause), [.untested, .untested])
        XCTAssertEqual(none.issues.map(\.reason), ["annotation.anchor.untested.l1", "annotation.anchor.untested.l2"])
        XCTAssertEqual(none.untested.map(\.id), ["l1", "l2"])
        XCTAssertEqual(none.untestedJSON, .array([.object(["id": .string("l1"), "step": .number(1), "beat": .null]),
                                                  .object(["id": .string("l2"), "step": .number(1), "beat": .null])]))
    }

    // MARK: Order, determinism, report shape

    func testIssuesFollowStepThenViewOrderAndAreDeterministic() throws {
        let t = text(#"{"labels": [{"id": "lA", "at": {"part": "core", "point": "centre"}, "text": "Core A"}, {"id": "lB", "at": {"part": "core", "offset": [0, 0, 5]}, "text": "Core B"}, {"id": "lFar", "at": {"part": "side", "offset": [0, 0, 300]}, "text": "Far"}]}"#,
                     steps: #"[{"say": "One.", "annotate": ["lB", "lFar"]}, {"say": "Two.", "annotate": ["lA", "lB"]}]"#)
        let r = report(t, .standard)
        let got = issues(r).map { [$0["id"]!, $0["cause"]!, $0["step"]!] }
        XCTAssertEqual(got, [[.string("lFar"), .string("offpart"), .null], [.string("lB"), .string("occluded"), .number(1)],
                             [.string("lA"), .string("occluded"), .number(2)], [.string("lB"), .string("occluded"), .number(2)]])
        // The off-part refusal comes first (a document warning), then the first view issue.
        XCTAssertEqual(report(t, .strict).reason, "annotation.anchor.off.lFar")
        for _ in 0..<3 { XCTAssertEqual(report(t, .standard).json, r.json) }
    }

    func testReportsWithoutAnnotationsKeepTheirKeys() {
        let t = #"{"v": 2, "kind": "assembly", "parts": [{"id": "b", "shape": {"box": {"size": [10, 10, 10]}}}], "steps": [{"say": "A box."}]}"#
        let r = report(t, .strict)
        XCTAssertNil(r.json["anchorIssues"]); XCTAssertNil(r.json["anchorUntested"]); XCTAssertNil(r.json["anchor"])
    }

    func testReasonsAreCatalogued() {
        XCTAssertEqual(MGSolidReasons.lookup("annotation.anchor.hidden.l1")?.strict, true)
        XCTAssertEqual(MGSolidReasons.lookup("annotation.anchor.hidden.l1")?.formats, [.check, .explainer])
        XCTAssertEqual(MGSolidReasons.lookup("annotation.anchor.off.l1")?.strict, true)
        XCTAssertEqual(MGSolidReasons.lookup("annotation.anchor.off.l1")?.kind, .warning)
    }

    // MARK: Explainer beats

    func testAnExplainerBeatGivesTheBeatInTheLocationAndTheDetail() throws {
        let solid = #"{"v": 2, "parts": [\#(Self.parts)], "annotations": {"labels": [{"id": "l1", "at": {"part": "core", "point": "centre"}, "text": "Core"}, {"id": "l2", "at": {"part": "shell", "offset": [0, 0, 100]}, "text": "Shell"}]}}"#
        let t = #"{"v": 1, "kind": "explainer", "solid": \#(solid), "beats": [{"say": "The shell.", "view": {"annotate": ["l2"]}}, {"say": "The core.", "view": {"annotate": ["l1"]}}]}"#
        let standard = MGExplainerReport.check(data: Data(t.utf8), profile: .standard, engine: nil)
        XCTAssertTrue(standard.ok)
        guard case .array(let w)? = standard.json["warnings"] else { return XCTFail("warnings") }
        XCTAssertTrue(w.contains(.object(["reason": .string("annotation.anchor.hidden.l1"), "view": .string("beat"), "id": .string("l1")])))
        let strict = MGExplainerReport.check(data: Data(t.utf8), profile: .strict, engine: nil)
        XCTAssertEqual(strict.reason, "annotation.anchor.hidden.l1")
        XCTAssertEqual(strict.location?.view, .beat)
        XCTAssertEqual(strict.location?.beat, 1)
        XCTAssertEqual(strict.location?.id, "l1")
        XCTAssertEqual(strict.location?.detail, "occluded")
        guard case .object(let a)? = strict.json["anchor"] else { return XCTFail("no anchor detail") }
        XCTAssertEqual(a["beat"], .number(2))
        XCTAssertEqual(a["by"], .string("shell"))
        // The solid view's own report holds no step-still result (the beats are the views).
        if case .object(let views)? = strict.json["views"], case .object(let s)? = views["solid"] { XCTAssertNil(s["anchorIssues"]) }
        // Fixed: the label on the shell's top face only.
        let fixed = #"{"v": 1, "kind": "explainer", "solid": \#(solid), "beats": [{"say": "The shell.", "view": {"annotate": ["l2"]}}, {"say": "The core.", "view": {"annotate": ["l1"], "ghost": ["shell"]}}]}"#
        XCTAssertTrue(MGExplainerReport.check(data: Data(fixed.utf8), profile: .strict, engine: nil).ok)
    }
}

/// The fixtures of the independent review of the anchor checks (rotated cuts, glass, a nearer neighbour, board panes,
/// automatic ghosts, instances and the triangle budget), each as a test, plus the L-shaped-part regression of the
/// shipped winch. All synthetic.
final class SolidAnchorReviewFixtureTests: XCTestCase {
    func strict(_ t: String) -> MGSolidReport { MGSolidReport.check(data: Data(t.utf8), profile: .strict, engine: nil) }
    func standard(_ t: String) -> MGSolidReport { MGSolidReport.check(data: Data(t.utf8), profile: .standard, engine: nil) }
    func explainer(_ t: String, _ profile: MGSolidProfile = .strict) -> MGExplainerReport { MGExplainerReport.check(data: Data(t.utf8), profile: profile, engine: nil) }
    func issues(_ json: MGJSON) -> [[String: MGJSON]] {
        guard case .array(let a)? = json["anchorIssues"] else { return [] }
        return a.compactMap { if case .object(let o) = $0 { return o }; return nil }
    }
    func causes(_ json: MGJSON) -> [String] { issues(json).compactMap { if case .string(let c)? = $0["cause"] { return c }; return nil } }

    static let plateAndExternal = #""parts":[{"id":"plate","shape":{"box":{"size":[200,20,100]}},"rot":[0,0,1,45]},{"id":"external","shape":{"box":{"size":[20,20,20]}},"at":[0,-50,7]}],"annotations":{"labels":[{"id":"label","at":{"part":"plate","point":"centre"},"text":"Named part"}]}"#
    static let rotatedCut = #"{"v":2,"kind":"assembly",\#(plateAndExternal),"steps":[{"say":"Inspect the named part.","camera":"front","section":{"normal":[0,-1,0],"offset":0,"parts":["plate"]}}]}"#
    static let rotatedNoSection = #"{"v":2,"kind":"assembly",\#(plateAndExternal),"steps":[{"say":"Inspect the named part.","camera":"front"}]}"#

    /// A rotated cut part does not exempt a part outside it that only its world-axis box holds.
    func testRotatedCutPartDoesNotExemptAnOutsideBlocker() {
        for t in [Self.rotatedCut, Self.rotatedNoSection] {
            let r = strict(t)
            XCTAssertEqual(r.reason, "annotation.anchor.hidden.label")
            XCTAssertEqual(issues(r.json).first?["by"], .string("external"))
        }
        // In the plate's frame the external box lies outside the plate's box, although the plate's world box holds it.
        let d = try! MGSolidParser.document(data: Data(Self.rotatedCut.utf8)).get()
        let pose = d.assembly.pose(d.defaults)
        let world = MGSolidFrames.worldBounds(d.assembly.part("plate")!.mesh.bounds, pose.world["plate"]!)
        let ext = MGSolidFrames.worldBounds(d.assembly.part("external")!.mesh.bounds, pose.world["external"]!)
        XCTAssertTrue(ext.min.x >= world.min.x && ext.max.x <= world.max.x && ext.min.y >= world.min.y && ext.max.y <= world.max.y)
        let local = (pose.world["plate"]!.inverse * pose.world["external"]!).apply(MGVec3(0, 0, 0))
        XCTAssertLessThan(local.y, -20)
    }

    func testRotatedCutInABoardPaneBeatIsRefusedAtTheFirstBeat() {
        let board = #"{"v":1,"items":[{"id":"table","k":"table","at":[6,4],"header":true,"cells":[["part","status"],["plate","built"]]}]}"#
        let t = #"{"v":1,"kind":"explainer","title":"Rotated cut and a board pane","board":\#(board),"solid":{"v":2,\#(Self.plateAndExternal)},"beats":[{"say":"The plate is named.","view":{"camera":"front","annotate":["label"],"section":{"normal":[0,-1,0],"offset":0,"parts":["plate"]}}},{"say":"The plate is posed.","view":{"camera":"front","annotate":["label"],"section":{"normal":[0,-1,0],"offset":0,"parts":["plate"]},"pose":{"plate":{"rot":[0,0,1,-30]}}}}]}"#
        let r = explainer(t)
        XCTAssertEqual(r.reason, "annotation.anchor.hidden.label")
        XCTAssertEqual(r.location?.beat, 0)
        XCTAssertEqual(issues(r.json).map { $0["beat"] }, [.number(1), .number(2)])
        XCTAssertEqual(issues(r.json).map { $0["by"] }, [.string("external"), .string("external")])
    }

    /// Glass covers 0.22 as the renderer draws it, so it hides no anchor.
    func testGlassDoesNotHideAnAnchor() {
        XCTAssertEqual(MGMaterialPreset.glass.coverage, 0.22)
        XCTAssertEqual(MGMaterialPreset.blackOxide.coverage, 1)
        let panel = #"{"v":2,"kind":"assembly","parts":[{"id":"core","shape":{"box":{"size":[60,60,60]}},"material":"blackOxide"},{"id":"glass","at":[0,-60,0],"shape":{"box":{"size":[200,2,200]}},"material":"glass"}],"annotations":{"labels":[{"id":"coreLabel","at":{"part":"core","point":"centre"},"text":"Core behind glass"}]},"steps":[{"say":"The core is behind transparent glass.","camera":"front"}]}"#
        XCTAssertTrue(strict(panel).ok)
        let box = #"{"v":2,"kind":"assembly","parts":[{"id":"core","shape":{"box":{"size":[20,20,20]}}},{"id":"glass","shape":{"box":{"size":[200,200,200]}},"material":"glass"}],"annotations":{"labels":[{"id":"label","at":{"part":"core","point":"centre"},"text":"Named part"}]},"steps":[{"say":"Inspect the named part.","camera":"front"}]}"#
        XCTAssertTrue(strict(box).ok)
        XCTAssertEqual(causes(strict(box).json), [])
        // The same box in steel hides it.
        let steel = box.replacingOccurrences(of: #""material":"glass""#, with: #""material":"brushedSteel""#)
        XCTAssertEqual(strict(steel).reason, "annotation.anchor.hidden.label")
    }

    static let neighbour = #""parts":[{"id":"plate","shape":{"box":{"size":[200,200,2]}}},{"id":"neighbour","shape":{"box":{"size":[40,40,2]}},"at":[0,0,30]}]"#
    func neighbourDoc(_ offset: String) -> String {
        #"{"v":2,"kind":"assembly",\#(Self.neighbour),"annotations":{"labels":[{"id":"label","at":{"part":"plate","offset":\#(offset)},"text":"Named part"}]},"steps":[{"say":"Inspect the named part.","camera":"front"}]}"#
    }

    /// A dot that lands on a separate neighbour is off its part, and the detail names the neighbour.
    func testADotOnANeighbourIsOffItsPart() {
        for offset in ["[0,-20,30]", "[0,0,30]"] {
            let r = strict(neighbourDoc(offset))
            XCTAssertEqual(r.reason, "annotation.anchor.off.label", offset)
            guard case .object(let a)? = r.json["anchor"] else { XCTFail("anchor"); continue }
            XCTAssertEqual(a["closer"], .string("neighbour"))
            // The distance of the first nearer triangle found: less than the 29 mm to the plate.
            if case .number(let c)? = a["closerDistance"] { XCTAssertLessThan(c, 29) } else { XCTFail("closerDistance") }
            XCTAssertEqual(a["distance"], .number(29))
            if case .string(let fix)? = a["fix"] { XCTAssertTrue(fix.contains("`neighbour` is nearer"), fix) } else { XCTFail("fix") }
        }
        // On the plate's top face, away from the neighbour: no issue.
        XCTAssertEqual(issues(strict(neighbourDoc("[60,60,1]")).json).count, 0)
    }

    /// An L-shaped part whose box holds empty space does not claim an anchor in that space (the shipped winch's drum
    /// label sits 2 mm past its axle, inside the frame's box but 57 mm from the frame; here a pin's label sits 0.5 mm
    /// past the pin).
    func testAnLShapedPartsEmptyBoxDoesNotClaimAnAnchor() throws {
        let t = #"{"v":2,"kind":"assembly","parts":[{"id":"frame","shape":[{"box":{"size":[170,6,150],"at":[0,14,85]}},{"box":{"size":[180,90,8],"at":[0,-25,-4]}}]},{"id":"pin","at":[0,-46,120],"shape":{"box":{"size":[8,8,8]}}}],"annotations":{"labels":[{"id":"l1","at":{"part":"pin","offset":[0,-4.5,0]},"text":"Pin"}]},"steps":[{"say":"A pin."}]}"#
        let d = try MGSolidParser.document(data: Data(t.utf8)).get()
        XCTAssertEqual(d.offPartAnchors, [])
        // The frame's box holds the anchor, its solid does not.
        let x = d.annotations.label("l1")!.at.world(d.assembly.pose(d.defaults))
        XCTAssertEqual(mgBoxDistance(x, d.assembly.part("frame")!.mesh.bounds), 0)
        let frame = MGMeshChunks(d.assembly.part("frame")!.mesh)
        var budget = 1_000_000
        XCTAssertEqual(frame.nearer(x, than: 50, budget: &budget), .notNearer)
        XCTAssertEqual(frame.nearer(MGVec3(0, 14, 85), than: 1, budget: &budget), .nearer(0), "inside the solid")
        // The shipped winch passes strict.
        let winch = try Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Examples/Solid3D/Sources/MartySolid3D/Models/annotated-winch.json"))
        XCTAssertTrue(MGSolidReport.check(data: winch, profile: .strict, engine: nil).ok)
    }

    static let ghostSolid = #""parts":[{"id":"core","shape":{"box":{"size":[40,40,40]}}},{"id":"blocker","at":[0,-60,0],"shape":{"box":{"size":[200,10,200]}}}],"annotations":{"labels":[{"id":"coreLabel","at":{"part":"core","point":"centre"},"text":"Core"},{"id":"blockerLabel","at":{"part":"blocker","point":"centre"},"text":"Blocker"}]}"#
    static let ghostSteps = #"[{"say":"The blocker is ghosted.","camera":"front","focus":["core"],"annotate":["coreLabel"]},{"say":"The ghosted blocker cannot be labelled strictly.","camera":"front","focus":["core"],"annotate":["blockerLabel"]}]"#

    /// The unblocked-focus rule ghosts the blocker: the core's label shows, and a label on the ghost is refused.
    func testAutomaticGhostsInAStepAndInABoardPaneBeat() {
        let a = strict(#"{"v":2,"kind":"assembly",\#(Self.ghostSolid),"steps":\#(Self.ghostSteps)}"#)
        XCTAssertEqual(a.reason, "annotation.anchor.hidden.blockerLabel")
        XCTAssertEqual(issues(a.json).map { [$0["id"]!, $0["cause"]!, $0["step"]!] }, [[.string("blockerLabel"), .string("ghosted"), .number(2)]])
        let board = #"{"v":1,"items":[{"id":"table","k":"table","at":[6,4],"header":true,"cells":[["part","status"],["plate","built"]]}]}"#
        let beats = #"[{"say":"The blocker is ghosted.","view":{"camera":"front","focus":["core"],"annotate":["coreLabel"]}},{"say":"The ghosted blocker cannot be labelled strictly.","view":{"camera":"front","focus":["core"],"annotate":["blockerLabel"]}}]"#
        let e = explainer(#"{"v":1,"kind":"explainer","title":"Automatic ghosts with a board pane","board":\#(board),"solid":{"v":2,\#(Self.ghostSolid)},"beats":\#(beats)}"#)
        XCTAssertEqual(e.reason, "annotation.anchor.hidden.blockerLabel")
        XCTAssertEqual(e.location?.beat, 1)
        XCTAssertEqual(e.location?.detail, "ghosted")
    }

    func testInstanceShowHideAndPosePass() {
        let t = #"{"v":2,"kind":"assembly","parts":[{"id":"pilot","use":"mannequin"}],"annotations":{"labels":[{"id":"bodyLabel","at":{"part":"pilot.body","point":"centre"},"text":"Body"}]},"steps":[{"say":"Shown pilot.","show":["pilot"],"annotate":["bodyLabel"]},{"say":"Hidden pilot.","hide":["pilot"],"annotate":[]},{"say":"Posed pilot.","show":["pilot"],"annotate":["bodyLabel"],"pose":{"pilot":{"with":{"leftShoulder":40}}}}]}"#
        let r = strict(t)
        XCTAssertTrue(r.ok, r.reason ?? "")
        XCTAssertEqual(issues(r.json).count, 0)
    }

    /// A 393,216-triangle shell with 12 labels exhausts the 3,000,000 triangle tests of the view: the anchors after the
    /// budget are `untested`; strict refuses the first, standard warns. With the core label alone, it is tested and
    /// refused as occluded.
    func budgetDoc(coreOnly: Bool) -> String {
        var pts: [String] = []
        for i in 0..<128 { pts.append("[100,\(-100 + 200 * Double(i) / 127)]") }
        for i in 0..<128 { pts.append("[90,\(100 - 200 * Double(i) / 127)]") }
        let profile = #"{"revolvedProfile":{"points":[\#(pts.joined(separator: ","))],"closed":true}}"#
        let shell = #"{"id":"shell","shape":[\#(Array(repeating: profile, count: 8).joined(separator: ","))]}"#
        var labels = (0..<11).map { #"{"id":"shell\#($0)","at":{"part":"shell","offset":[0,-95,0]},"text":"Shell"}"# }
        labels.append(#"{"id":"coreLabel","at":{"part":"core","point":"centre"},"text":"Hidden core"}"#)
        if coreOnly { labels = [labels.last!] }
        return #"{"v":2,"kind":"assembly","parts":[\#(shell),{"id":"core","shape":{"box":{"size":[20,20,20]}}}],"annotations":{"labels":[\#(labels.joined(separator: ","))]},"steps":[{"say":"All twelve anchors.","camera":"front"}]}"#
    }

    func testOverTheBudgetStrictRefusesUntestedAnchors() throws {
        let t = budgetDoc(coreOnly: false)
        let d = try MGSolidParser.document(data: Data(t.utf8)).get()
        XCTAssertEqual(d.assembly.part("shell")?.mesh.triangleCount, 393_216)
        let s = strict(t)
        XCTAssertEqual(s.reason, "annotation.anchor.untested.shell7")
        let untested = issues(s.json).filter { $0["cause"] == .string("untested") }.map { $0["id"]! }
        XCTAssertEqual(untested, ["shell7", "shell8", "shell9", "shell10", "coreLabel"].map(MGJSON.string))
        guard case .array(let u)? = s.json["anchorUntested"] else { return XCTFail("anchorUntested") }
        XCTAssertEqual(u.count, 5)
        let w = standard(t)
        XCTAssertTrue(w.ok, "the standard profile warns")
        guard case .array(let ws)? = w.json["warnings"] else { return XCTFail("warnings") }
        XCTAssertTrue(ws.contains(.object(["reason": .string("annotation.anchor.untested.coreLabel"), "part": .string("coreLabel")])))
        let core = strict(budgetDoc(coreOnly: true))
        XCTAssertEqual(core.reason, "annotation.anchor.hidden.coreLabel")
        XCTAssertEqual(issues(core.json).first?["by"], .string("shell"))
    }

    /// Fresh reports of the review's refused fixtures are identical (no dictionary order in the result).
    func testReviewFixturesAreDeterministic() {
        for t in [Self.rotatedCut, neighbourDoc("[0,-20,30]")] {
            let first = strict(t).json
            for _ in 0..<3 { XCTAssertEqual(strict(t).json, first) }
        }
    }
}

/// The fixtures of the second independent review (nearer-part budget, posed views, touching parts, ordinary layouts),
/// each as a test. All synthetic.
final class SolidAnchorRecheckFixtureTests: XCTestCase {
    func strict(_ t: String) -> MGSolidReport { MGSolidReport.check(data: Data(t.utf8), profile: .strict, engine: nil) }
    func standard(_ t: String) -> MGSolidReport { MGSolidReport.check(data: Data(t.utf8), profile: .standard, engine: nil) }
    func issues(_ r: MGSolidReport) -> [[String: MGJSON]] {
        guard case .array(let a)? = r.json["anchorIssues"] else { return [] }
        return a.compactMap { if case .object(let o) = $0 { return o }; return nil }
    }
    func doc(_ t: String) throws -> MGSolidDocument { try MGSolidParser.document(data: Data(t.utf8)).get() }
    func assembly(_ parts: String, _ labels: String, steps: String = #"[{"say":"Inspect the named part.","camera":"front"}]"#) -> String {
        #"{"v":2,"kind":"assembly","parts":[\#(parts)],"annotations":{"labels":[\#(labels)]},"steps":\#(steps)}"#
    }

    // MARK: Item 1: the nearer-part search never invents a distance

    /// A hollow glass casing of eight sleeves (393,216 triangles; `lowDetail`: four profile points each) and bearings
    /// inside it, each labelled 1 mm outside its bearing (within its tolerance).
    func casing(bearings: Int, oneBearing: Bool = false, lowDetail: Bool = false) -> String {
        var pts: [String] = []
        if lowDetail { pts = ["[100,-10]", "[100,10]", "[90,10]", "[90,-10]"] } else {
            for i in 0..<128 { pts.append("[100,\(-10 + 20 * Double(i) / 127)]") }
            for i in 0..<128 { pts.append("[90,\(10 - 20 * Double(i) / 127)]") }
        }
        let sleeves = stride(from: -70, through: 70, by: 20).map { z in #"{"revolvedProfile":{"points":[\#(pts.joined(separator: ","))],"closed":true,"at":[0,0,\#(z)]}}"# }
        let shell = #"{"id":"shell","material":"glass","shape":[\#(sleeves.joined(separator: ","))]}"#
        var parts: [String] = [], labels: [String] = []
        if oneBearing {
            parts = [#"{"id":"bearing","shape":{"box":{"size":[10,10,10]}}}"#]
            labels = (0..<bearings).map { #"{"id":"bearingLabel\#($0)","text":"Bearing","at":{"part":"bearing","offset":[0,-6,0]}}"# }
        } else {
            for i in 0..<bearings {
                parts.append(#"{"id":"bearing\#(i)","shape":{"box":{"size":[10,10,10]}},"at":[0,0,\#(-66 + 12 * i)]}"#)
                labels.append(#"{"id":"bearingLabel\#(i)","text":"Bearing","at":{"part":"bearing\#(i)","offset":[0,-6,0]}}"#)
            }
        }
        return assembly((parts + [shell]).joined(separator: ","), labels.joined(separator: ","))
    }

    func testTwelveBearingsInAHollowCasingPassWithinTheBudget() throws {
        let t = casing(bearings: 12)
        let d = try doc(t)
        XCTAssertEqual(d.assembly.part("shell")?.mesh.triangleCount, 393_216)
        let r = strict(t)
        XCTAssertTrue(r.ok, r.reason ?? "")
        XCTAssertEqual(issues(r).count, 0)
        // No budget overrun: the whole document's search fits in a third of the budget.
        XCTAssertEqual(d.offPartAnchors(budget: MGAnnotationAnchorRules.surfaceTests / 3), [])
        for v in [casing(bearings: 12, lowDetail: true), casing(bearings: 1), casing(bearings: 12, oneBearing: true), casing(bearings: 1, oneBearing: true)] {
            XCTAssertTrue(strict(v).ok)
        }
    }

    /// Out of budget the answer is unknown: `untested` (strict refuses, standard warns), never `off`.
    func testOutOfBudgetTheNearerPartTestIsUntestedNeverOff() throws {
        let t = casing(bearings: 3)
        let d = try doc(t)
        let small = d.offPartAnchors(budget: 1_000)
        XCTAssertEqual(small.map(\.cause), [.untested, .untested, .untested])
        XCTAssertEqual(small.map(\.reason), ["annotation.anchor.untested.bearingLabel0", "annotation.anchor.untested.bearingLabel1",
                                             "annotation.anchor.untested.bearingLabel2"])
        XCTAssertEqual(small.first?.budget, "nearerPart")
        XCTAssertEqual(small.first?.json["budget"], .string("nearerPart"))
        XCTAssertNil(small.first?.closer)
        // The same anchors with the full budget pass.
        XCTAssertEqual(d.offPartAnchors, [])
        // The search itself: unknown when the budget runs out, never a distance.
        let shell = MGMeshChunks(d.assembly.part("shell")!.mesh)
        var tiny = 10
        XCTAssertEqual(shell.nearer(MGVec3(0, -6, -66), than: 1, budget: &tiny), .unknown)
        var enough = 1_000_000
        XCTAssertEqual(shell.nearer(MGVec3(0, -6, -66), than: 1, budget: &enough), .notNearer)
        XCTAssertEqual(shell.nearer(MGVec3(95, 0, -70), than: 1, budget: &enough), .nearer(0), "inside the sleeve wall")
        XCTAssertGreaterThan(enough, 1_000_000 - 50_000, "far runs are skipped")
    }

    // MARK: Item 2: the nearer-part test runs at the pose of each view that shows the label

    static let arm = #"{"id":"arm","shape":{"box":{"size":[200,2,2]}}}"#
    static let armLabel = #"{"id":"label","text":"Named part","at":{"part":"arm","offset":[80,-2,0]}}"#
    static let armStep = #"[{"say":"Inspect the named part.","camera":"front","annotate":["label"],"pose":{"arm":{"rot":[0,0,1,90]}}}]"#

    func testAPartNearOnlyAtTheUnshownDefaultPoseDoesNotRefuse() {
        for at in ["[80,-2,0]", "[-80,-2,0]"] {
            let t = assembly(Self.arm + #",{"id":"restNeighbour","shape":{"box":{"size":[5,5,5]}},"at":\#(at)}"#, Self.armLabel, steps: Self.armStep)
            XCTAssertTrue(strict(t).ok, at)
        }
    }

    func testAPartNearAtTheShownPoseRefusesWithTheStep() {
        // At the posed step the dot is at [2, 80, 0]; a neighbour there is nearer than the arm.
        let t = assembly(Self.arm + #",{"id":"posedNeighbour","shape":{"box":{"size":[5,5,5]}},"at":[2,80,0]}"#, Self.armLabel, steps: Self.armStep)
        let r = strict(t)
        XCTAssertEqual(r.reason, "annotation.anchor.off.label")
        guard case .object(let a)? = r.json["anchor"] else { return XCTFail("anchor") }
        XCTAssertEqual(a["closer"], .string("posedNeighbour"))
        XCTAssertEqual(a["step"], .number(1))
        // A label shown in the plain view is tested at the default pose there (no step).
        let plain = assembly(Self.arm + #",{"id":"restNeighbour","shape":{"box":{"size":[5,5,5]}},"at":[80,-2,0]}"#, Self.armLabel,
                             steps: #"[{"say":"Inspect the named part.","camera":"front"}]"#)
        let p = strict(plain)
        XCTAssertEqual(p.reason, "annotation.anchor.off.label")
        guard case .object(let b)? = p.json["anchor"] else { return XCTFail("anchor") }
        XCTAssertEqual(b["closer"], .string("restNeighbour"))
        XCTAssertEqual(b["step"], .null)
    }

    func testAnExplainerBeatNamesTheBeatOfANearerPart() {
        let solid = #"{"v":2,"parts":[\#(Self.arm),{"id":"posedNeighbour","shape":{"box":{"size":[5,5,5]}},"at":[2,80,0]}],"annotations":{"labels":[\#(Self.armLabel)]}}"#
        let t = #"{"v":1,"kind":"explainer","solid":\#(solid),"beats":[{"say":"The arm.","view":{"camera":"front","annotate":[]}},{"say":"The arm turns.","view":{"camera":"front","annotate":["label"],"pose":{"arm":{"rot":[0,0,1,90]}}}}]}"#
        let r = MGExplainerReport.check(data: Data(t.utf8), profile: .strict, engine: nil)
        XCTAssertEqual(r.reason, "annotation.anchor.off.label")
        guard case .object(let a)? = r.json["anchor"] else { return XCTFail("anchor") }
        XCTAssertEqual(a["beat"], .number(2))
        XCTAssertEqual(a["closer"], .string("posedNeighbour"))
    }

    // MARK: Item 3: touching parts are symmetric; a real blocker is still caught

    static let touching = #"{"id":"left","shape":{"box":{"size":[10,10,10]}},"at":[-5,0,0]},{"id":"right","shape":{"box":{"size":[10,10,10]}},"at":[\#(5),0,0]}"#
    func touchingDoc(right: String = "5", part: String, offset: String) -> String {
        assembly(#"{"id":"left","shape":{"box":{"size":[10,10,10]}},"at":[-5,0,0]},{"id":"right","shape":{"box":{"size":[10,10,10]}},"at":[\#(right),0,0]}"#,
                 #"{"id":"label","text":"Named part","at":{"part":"\#(part)","offset":\#(offset)}}"#)
    }

    func testTouchingPartsGiveTheSameResultForBothNames() {
        let left = strict(touchingDoc(part: "left", offset: "[5,0,0]")), right = strict(touchingDoc(part: "right", offset: "[-5,0,0]"))
        XCTAssertEqual(left.ok, right.ok)
        XCTAssertTrue(left.ok, left.reason ?? "")
        XCTAssertEqual(issues(left).count, issues(right).count)
        // The shared front edge, and the same point with the right box moved by ±0.00001 mm.
        XCTAssertTrue(strict(touchingDoc(part: "left", offset: "[5,-5,0]")).ok)
        XCTAssertTrue(strict(touchingDoc(part: "right", offset: "[-5,-5,0]")).ok)
        for r in ["5.00001", "4.99999"] { XCTAssertTrue(strict(touchingDoc(right: r, part: "left", offset: "[5,0,0]")).ok, r) }
        for _ in 0..<3 { XCTAssertEqual(strict(touchingDoc(part: "left", offset: "[5,0,0]")).json, left.json) }
    }

    func testARealBlockerOneMillimetreInFrontIsStillCaught() {
        // A 0.5 mm plate whose back face is 1 mm in front of the left box's front face (the camera looks from -Y).
        let t = assembly(#"{"id":"left","shape":{"box":{"size":[10,10,10]}}},{"id":"plate","shape":{"box":{"size":[20,0.5,20]}},"at":[0,-6.25,0]}"#,
                         #"{"id":"label","text":"Named part","at":{"part":"left","offset":[0,-5,0]}}"#)
        let r = strict(t)
        XCTAssertEqual(r.reason, "annotation.anchor.hidden.label")
        XCTAssertEqual(issues(r).first?["by"], .string("plate"))
    }

    // MARK: Ordinary layouts and controls of the review

    func testOrdinaryLayoutsAndControls() {
        let bearing = #"{"id":"bearing","shape":{"box":{"size":[12,12,10]}}}"#, tube = #"{"id":"casing","shape":{"tube":{"inner":10,"outer":30,"length":20,"z0":-10}}}"#
        let label6 = #"{"id":"label","text":"Named part","at":{"part":"bearing","offset":[0,-6,0]}}"#
        XCTAssertTrue(strict(assembly(bearing + "," + tube, label6, steps: #"[{"say":"Inspect the named part.","camera":"front","ghost":["casing"]}]"#)).ok)
        let inCasing = strict(assembly(bearing + "," + tube, label6))
        XCTAssertEqual(inCasing.reason, "annotation.anchor.hidden.label")
        XCTAssertEqual(issues(inCasing).first?["by"], .string("casing"))
        XCTAssertTrue(strict(assembly(#"{"id":"bearing","shape":{"box":{"size":[10,10,10]}}},{"id":"casing","shape":{"box":{"size":[100,40,100]}},"at":[0,25,0]}"#,
                                      #"{"id":"label","text":"Named part","at":{"part":"bearing","offset":[0,5,0]}}"#)).ok)
        // A 10 mm bearing labelled 1 mm out is past its 0.87 mm tolerance; 0.5 mm out passes.
        let small = #"{"id":"bearing","shape":{"box":{"size":[10,10,10]}}}"#
        XCTAssertEqual(strict(assembly(small + "," + tube, #"{"id":"label","text":"Named part","at":{"part":"bearing","offset":[0,-6,0]}}"#)).reason,
                       "annotation.anchor.off.label")
        XCTAssertTrue(strict(assembly(small + "," + tube, #"{"id":"label","text":"Named part","at":{"part":"bearing","offset":[0,-5.5,0]}}"#,
                                      steps: #"[{"say":"Inspect the named part.","camera":"front","ghost":["casing"]}]"#)).ok)
        // Coverage threshold: 0.49 does not block, 0.5 and 0.51 do.
        for (o, ok) in [("0.49", true), ("0.5", false), ("0.51", false)] {
            let t = assembly(#"{"id":"core","shape":{"box":{"size":[20,20,20]}}},{"id":"panel","shape":{"box":{"size":[100,2,100]}},"opacity":\#(o),"at":[0,-30,0]}"#,
                             #"{"id":"label","text":"Named part","at":{"part":"core","point":"centre"}}"#)
            XCTAssertEqual(strict(t).ok, ok, o)
        }
        for (m, ok) in [("darkSteel", false), ("glass", true)] {
            let t = assembly(#"{"id":"core","shape":{"box":{"size":[20,20,20]}}},{"id":"shell","shape":{"box":{"size":[100,100,100]}},"material":"\#(m)"}"#,
                             #"{"id":"label","text":"Named part","at":{"part":"core","point":"centre"}}"#)
            XCTAssertEqual(strict(t).ok, ok, m)
        }
        XCTAssertTrue(strict(assembly(#"{"id":"gear","shape":{"gear":{"teeth":20,"module":2,"width":10,"bore":4,"z0":-5}}},{"id":"shaft","shape":{"shaft":{"radius":4,"length":50,"z0":-25}}}"#,
                                      #"{"id":"label","text":"Named part","at":{"part":"gear","offset":[20,0,0]}}"#)).ok)
        XCTAssertTrue(strict(assembly(#"{"id":"pilot","use":"mannequin","at":[100,200,50],"rot":[0,0,1,45]}"#,
                                      #"{"id":"label","text":"Named part","at":{"part":"pilot.body","point":"centre"}}"#,
                                      steps: #"[{"say":"Inspect the named part.","camera":"front","pose":{"pilot":{"with":{"leftShoulder":40}}}}]"#)).ok)
        let carried = #"{"id":"root","shape":{"box":{"size":[2,2,2]}},"at":[200,0,0]},{"id":"bearing","shape":{"box":{"size":[10,10,10]}},"parent":"root"},{"id":"casing","shape":{"tube":{"inner":10,"outer":30,"length":20,"z0":-10}},"parent":"root"}"#
        let carriedLabel = #"{"id":"label","text":"Named part","at":{"part":"bearing","offset":[0,-5,0]}}"#
        XCTAssertTrue(strict(assembly(carried, carriedLabel, steps: #"[{"say":"Inspect the named part.","camera":"front","pose":{"root":{"rot":[0,0,1,45]}},"ghost":["casing"]}]"#)).ok)
        XCTAssertEqual(strict(assembly(carried, carriedLabel, steps: #"[{"say":"Inspect the named part.","camera":"front","pose":{"root":{"at":[100,0,0],"rot":[0,0,1,45]}}}]"#)).reason,
                       "step.pose.key")
    }
}

/// The fixtures of the third independent review: a large, distant or hidden part never widens a tolerance (precision
/// epsilon only), blockers and neighbours at many gaps and model spreads, exact neighbours and later posed steps. All
/// synthetic.
final class SolidAnchorPrecisionFixtureTests: XCTestCase {
    func strict(_ t: String) -> MGSolidReport { MGSolidReport.check(data: Data(t.utf8), profile: .strict, engine: nil) }
    func anchor(_ r: MGSolidReport) -> [String: MGJSON] { if case .object(let o)? = r.json["anchor"] { return o }; return [:] }
    func box(_ id: String, _ size: [Double], _ at: [Double] = [0, 0, 0], material: String? = nil) -> String {
        let m = material.map { #","material":"\#($0)""# } ?? ""
        return #"{"id":"\#(id)","shape":{"box":{"size":[\#(size.map { "\($0)" }.joined(separator: ","))]}},"at":[\#(at.map { "\($0)" }.joined(separator: ","))]\#(m)}"#
    }
    /// `spread` > 0 adds an unrelated 1 mm part that far along +X, hidden in the step.
    func doc(_ parts: [String], part: String, offset: [Double], spread: Double = 0, steps: String? = nil) -> String {
        var all = parts
        if spread > 0 { all.append(box("distant", [1, 1, 1], [spread, 0, 0])) }
        let hide = spread > 0 ? #","hide":["distant"]"# : ""
        let st = steps ?? #"[{"say":"Inspect the named part.","camera":"front"\#(hide)}]"#
        return #"{"v":2,"kind":"assembly","parts":[\#(all.joined(separator: ","))],"annotations":{"labels":[{"id":"label","text":"Named part","at":{"part":"\#(part)","offset":[\#(offset.map { "\($0)" }.joined(separator: ","))]}}]},"steps":\#(st)}"#
    }

    func testThePrecisionEpsilonDoesNotGrowWithTheModel() {
        // The argument is anchor-relative: the epsilon depends on the distance from the dot only.
        XCTAssertEqual(mgPrecision(.zero), 1e-6 + 1e-4, accuracy: 1e-15)
        XCTAssertEqual(mgPrecision(MGVec3(100, 0, 0)), 2e-4, accuracy: 1e-15)
        XCTAssertEqual(mgPrecision(MGVec3(1000, 0, 0)), 1.1e-3, accuracy: 1e-15)
    }

    /// A real blocker whose hit is 10.6 mm before the dot is caught, with or without a hidden part 2 m away.
    func testASideBlockerIsNotExcusedByAHiddenDistantPart() {
        for spread in [0.0, 2000] {
            let t = doc([box("core", [2, 200, 2], [2, 0, 0]), box("blocker", [1, 1, 20], [0, -10, 0])], part: "core", offset: [-2, 0, 0], spread: spread)
            let r = strict(t)
            XCTAssertEqual(r.reason, "annotation.anchor.hidden.label", "spread \(spread)")
            XCTAssertEqual(anchor(r)["by"], .string("blocker"), "spread \(spread)")
        }
    }

    /// A plate in front of the named face is caught at every gap from 0.01 mm to 5 mm and every model spread.
    func testAPlateInFrontIsCaughtAtEveryGapAndSpread() {
        for spread in [0.0, 100, 1000, 2000, 3900] {
            for gap in [0.01, 0.1, 1, 2, 5] {
                let t = doc([box("core", [10, 10, 10]), box("blocker", [20, 0.5, 20], [0, -5 - gap - 0.25, 0])], part: "core", offset: [0, -5, 0], spread: spread)
                XCTAssertEqual(strict(t).reason, "annotation.anchor.hidden.label", "spread \(spread) gap \(gap)")
            }
        }
        // The same geometry at other scales (blocker 10 % of the core side in front).
        for scale in [0.1, 1, 10, 100] {
            let t = doc([box("core", [10 * scale, 10 * scale, 10 * scale]), box("blocker", [20 * scale, 0.5 * scale, 20 * scale], [0, -6.25 * scale, 0])],
                        part: "core", offset: [0, -5 * scale, 0])
            XCTAssertEqual(strict(t).reason, "annotation.anchor.hidden.label", "scale \(scale)")
        }
    }

    /// A dot on a neighbour's face just outside its named part is off its part at every gap and spread.
    func testADotOnANeighbourIsOffAtEveryGapAndSpread() {
        for spread in [0.0, 2000] {
            let t = doc([box("core", [100, 10, 10]), box("neighbour", [10, 0.5, 10], [0, -5.75, 0])], part: "core", offset: [0, -6, 0], spread: spread)
            let r = strict(t)
            XCTAssertEqual(r.reason, "annotation.anchor.off.label", "spread \(spread)")
            XCTAssertEqual(anchor(r)["closer"], .string("neighbour"))
        }
        for spread in [0.0, 100, 1000, 2000, 3900] {
            for gap in [0.01, 0.1, 0.5, 1, 2] {
                let t = doc([box("core", [10, 10, 10]), box("neighbour", [10, 0.5, 10], [0, -5 - gap - 0.25, 0], material: "glass")],
                            part: "core", offset: [0, -5 - gap, 0], spread: spread)
                XCTAssertEqual(strict(t).reason, "annotation.anchor.off.label", "spread \(spread) gap \(gap)")
            }
        }
    }

    /// `closerDistance` is the distance of the first nearer triangle found, not a guaranteed 0 inside.
    func testExactNeighboursAndTheReportedCloserDistance() {
        for y in [-6.0, -6.5, -6.25] {
            let r = strict(doc([box("core", [100, 10, 10]), box("neighbour", [20, 0.5, 20], [0, -6.25, 0], material: "glass")], part: "core", offset: [0, y, 0]))
            XCTAssertEqual(r.reason, "annotation.anchor.off.label", "\(y)")
            XCTAssertEqual(anchor(r)["closer"], .string("neighbour"))
            if case .number(let c)? = anchor(r)["closerDistance"] { XCTAssertLessThan(c, abs(y) - 5) } else { XCTFail("closerDistance") }
        }
    }

    /// A neighbour at the posed place of the dot is caught in whichever step shows the pose.
    func testAPosedNeighbourIsCaughtInALaterStep() {
        let parts = [#"{"id":"arm","shape":{"box":{"size":[200,2,2]}}}"#, box("restNeighbour", [5, 5, 5], [2, 80, 0])]
        let posed = #"{"say":"Inspect the named part.","camera":"front","annotate":["label"],"pose":{"arm":{"rot":[0,0,1,90]}}}"#
        for (steps, step) in [("[\(posed)]", 1.0), (#"[{"say":"At rest.","camera":"front","annotate":["label"]},\#(posed)]"#, 2.0)] {
            let r = strict(doc(parts, part: "arm", offset: [80, -2, 0], steps: steps))
            XCTAssertEqual(r.reason, "annotation.anchor.off.label")
            XCTAssertEqual(anchor(r)["step"], .number(step))
        }
    }

    /// Touching boxes stay symmetric with a hidden distant part present.
    func testTouchingBoxesStaySymmetricInALargeModel() {
        let parts = [box("left", [10, 10, 10], [-5, 0, 0]), box("right", [10, 10, 10], [5, 0, 0])]
        for spread in [0.0, 2000] {
            XCTAssertTrue(strict(doc(parts, part: "left", offset: [5, 0, 0], spread: spread)).ok)
            XCTAssertTrue(strict(doc(parts, part: "right", offset: [-5, 0, 0], spread: spread)).ok)
        }
    }

    /// A hidden part does not widen the own-part tolerance: it uses the parts the views showing the label draw. The
    /// step lists the label (`annotate`), so the plain view, which draws the distant part, does not show it.
    func testHiddenPartsDoNotWidenTheOwnPartTolerance() throws {
        func t(_ y: Double, _ spread: Double) -> String {
            let hide = spread > 0 ? #","hide":["distant"]"# : ""
            return doc([box("core", [10, 10, 10])], part: "core", offset: [0, y, 0], spread: spread,
                       steps: #"[{"say":"Inspect the named part.","camera":"front","annotate":["label"]\#(hide)}]"#)
        }
        // max(5 % of 17.32, 0.5 % of 17.32) = 0.866 mm: 0.8 mm out passes, 1 mm out is off, with or without the far part.
        for spread in [0.0, 3000] {
            XCTAssertTrue(strict(t(-5.8, spread)).ok, "spread \(spread)")
            XCTAssertEqual(strict(t(-6, spread)).reason, "annotation.anchor.off.label", "spread \(spread)")
        }
        let d = try MGSolidParser.document(data: Data(t(-6, 3000).utf8)).get()
        XCTAssertGreaterThan(d.annotations.diagonal, 2000, "the whole assembly is large")
        if case .number(let tol)? = d.offPartAnchors.first?.json["tolerance"] { XCTAssertEqual(tol, 0.866, accuracy: 0.001) } else { XCTFail("tolerance") }
    }
}

/// The fixtures of the fourth independent review: legal drives and poses that move a model to about 10⁶ mm, or whose
/// rest pose is far from the shown pose. Every test runs in anchor-relative coordinates, so a blocker or neighbour is
/// caught wherever the model is, and every coincident touching face still passes. All synthetic.
final class SolidAnchorWorldPositionFixtureTests: XCTestCase {
    func strict(_ t: String, library: MGSolidLibrary = .builtIn) -> MGSolidReport {
        MGSolidReport.check(data: Data(t.utf8), library: library, profile: .strict, engine: nil)
    }
    func anchor(_ r: MGSolidReport) -> [String: MGJSON] { if case .object(let o)? = r.json["anchor"] { return o }; return [:] }
    func num(_ x: Double) -> String { "\(x)" }
    func part(_ id: String, _ size: [Double], at: [Double] = [0, 0, 0], extra: String = "") -> String {
        #"{"id":"\#(id)","shape":{"box":{"size":[\#(size.map(num).joined(separator: ","))]}},"at":[\#(at.map(num).joined(separator: ","))]\#(extra)}"#
    }
    func doc(_ parts: [String], _ label: String, _ offset: [Double], step: String, params: String = "") -> String {
        #"{"v":2,"kind":"assembly","parts":[\#(parts.joined(separator: ","))],"annotations":{"labels":[{"id":"label","text":"Named part","at":{"part":"\#(label)","offset":[\#(offset.map(num).joined(separator: ","))]}}]},"steps":[\#(step)]\#(params)}"#
    }
    /// Both parts on equal prismatic drives along `axis`, shown at the end of a one-turn spin that ends at
    /// `coordinate` mm along the axis.
    func driven(_ parts: [String], _ label: String, _ offset: [Double], axis: [Double], coordinate: Double) -> String {
        let length = (axis.map { $0 * $0 }.reduce(0, +)).squareRoot()
        let input = coordinate * length / 1000 - 2 * .pi
        return doc(parts, label, offset, step: #"{"say":"Inspect the named part.","camera":"front","annotate":["label"],"spin":1}"#,
                   params: #","params":{"input":\#(input)}"#)
    }
    func drive(_ axis: [Double]) -> String { #","joint":{"prismatic":[\#(axis.map(num).joined(separator: ","))]},"drive":{"input":1000}"# }

    func testAnchorRelativeTransformsKeepTheirPrecisionFarAway() {
        let t = MGTransform(c0: MGVec3(0, 1, 0), c1: MGVec3(-1, 0, 0), c2: MGVec3(0, 0, 1), translation: MGVec3(2e6, 1e6, 0))
        let x = t.apply(MGVec3(0, -5, 0))
        let rel = mgAnchorRelative(t, anchor: x)
        let local = rel.toLocal.apply(.zero)
        XCTAssertEqual(local.x, 0, accuracy: 1e-9); XCTAssertEqual(local.y, -5, accuracy: 1e-9); XCTAssertEqual(local.z, 0, accuracy: 1e-9)
        let back = rel.toRelative.apply(MGVec3(0, -6, 0))
        XCTAssertEqual(back.length, 1, accuracy: 1e-9, "a point 1 mm from the anchor stays 1 mm away")
    }

    /// A plate 0.1, 1 or 2 mm in front of the dot is caught with the model driven to 10⁵, 10⁶ or 2 × 10⁶ mm, along X
    /// or a diagonal.
    func testADrivenFarBlockerIsCaught() {
        for (axis, coordinates) in [([1.0, 0, 0], [1e5, 1e6, 2e6]), ([1, 1, 0], [1e6]), ([1, 1, 1], [1e6])] {
            for c in coordinates {
                for gap in [0.1, 1, 2] {
                    let t = driven([part("core", [10, 10, 10], extra: drive(axis)), part("blocker", [20, 0.05, 20], at: [0, -5 - gap - 0.025, 0], extra: drive(axis))],
                                   "core", [0, -5, 0], axis: axis, coordinate: c)
                    let r = strict(t)
                    XCTAssertEqual(r.reason, "annotation.anchor.hidden.label", "axis \(axis) at \(c) gap \(gap)")
                    XCTAssertEqual(anchor(r)["by"], .string("blocker"), "axis \(axis) at \(c) gap \(gap)")
                }
            }
        }
    }

    /// The side blocker 10.6 mm before the dot is not excused as a tie when the model is driven to 10⁵…2 × 10⁶ mm.
    func testADrivenFarSideBlockerIsNotATie() {
        for c in [1e5, 1e6, 2e6] {
            let t = driven([part("core", [2, 200, 2], at: [2, 0, 0], extra: drive([1, 0, 0])), part("blocker", [1, 1, 20], at: [0, -10, 0], extra: drive([1, 0, 0]))],
                           "core", [-2, 0, 0], axis: [1, 0, 0], coordinate: c)
            XCTAssertEqual(anchor(strict(t))["by"], .string("blocker"), "at \(c)")
        }
    }

    /// A dot on a neighbour's face 0.1, 1 or 2 mm outside its part is off its part far away.
    func testADrivenFarNeighbourIsOff() {
        for c in [1e5, 1e6, 2e6] {
            for gap in [0.1, 1, 2] {
                let t = driven([part("core", [100, 10, 10], extra: drive([1, 0, 0])),
                                part("neighbour", [10, 0.5, 10], at: [0, -5 - gap + 0.25, 0], extra: #","material":"glass""# + drive([1, 0, 0]))],
                               "core", [0, -5 - gap, 0], axis: [1, 0, 0], coordinate: c)
                let r = strict(t)
                XCTAssertEqual(r.reason, "annotation.anchor.off.label", "at \(c) gap \(gap)")
                XCTAssertEqual(anchor(r)["closer"], .string("neighbour"), "at \(c) gap \(gap)")
            }
        }
    }

    /// The shown pose decides, not the rest pose: a child driven to 2 × 10⁶ mm at rest and posed back near the origin,
    /// and a child 3,990 mm out at rest posed to the origin, are refused at their shown pose.
    func testTheShownPoseDecidesNotTheRestPose() {
        for input in [0, 1000] {
            for gap in [0.1, 1, 2, 3] {
                let parts = [part("carrier", [0.05, 0.05, 0.05], extra: drive([1, 0, 0])),
                             part("core", [100, 10, 10], extra: #","parent":"carrier""# + drive([1, 0, 0])),
                             part("neighbour", [10, 0.5, 10], at: [0, 5 + gap - 0.25, 0], extra: #","material":"glass""#)]
                let t = doc(parts, "core", [0, -5 - gap, 0],
                            step: #"{"say":"Inspect the named part.","camera":"front","annotate":["label"],"pose":{"core":{"rot":[0,0,1,180]}},"hide":["carrier"]}"#,
                            params: #","params":{"input":\#(input)}"#)
                XCTAssertEqual(strict(t).reason, "annotation.anchor.off.label", "input \(input) gap \(gap)")
            }
        }
        for coordinate in [0.0, 3990] {
            for gap in [0.001, 0.002, 0.005, 0.01, 1] {
                let parts = [part("carrier", [0.05, 0.05, 0.05], at: [coordinate / 2, 0, 0]),
                             part("core", [100, 10, 10], at: [coordinate / 2, 0, 0], extra: #","parent":"carrier""#),
                             part("neighbour", [10, 0.5, 10], at: [0, 5 + gap - 0.25, 0], extra: #","material":"glass""#)]
                let t = doc(parts, "core", [0, -5 - gap, 0],
                            step: #"{"say":"Inspect the named part.","camera":"front","annotate":["label"],"pose":{"carrier":{"rot":[0,0,1,180]}},"hide":["carrier"]}"#)
                XCTAssertEqual(strict(t).reason, "annotation.anchor.off.label", "rest \(coordinate) gap \(gap)")
            }
        }
    }

    /// Coincident touching faces still pass for both names: rounding-noise offsets, rotations, a posed carrier, and a
    /// custom component placed or posed at each angle.
    func testCoincidentTouchingFacesPassEverywhere() throws {
        for separation in [0, (0.1 + 0.2) - 0.3, 1e-7, -1e-7] {
            for angle in [0.0, 17, 45, 90] {
                let r = angle * .pi / 180
                for named in ["left", "right"] {
                    let parts = [("left", -5.0), ("right", 5 + separation)].map { id, c in
                        part(id, [10, 10, 10], at: [0.1 + 0.2 + c * cos(r), 0.3 + c * sin(r), 0], extra: #","rot":[0,0,1,\#(angle)]"#)
                    }
                    let t = doc(parts, named, [named == "left" ? 5 : -5, 0, 0],
                                step: #"{"say":"Inspect the named part.","camera":"front","annotate":["label"],"orbit":\#(angle)}"#)
                    XCTAssertTrue(strict(t).ok, "separation \(separation) angle \(angle) \(named)")
                }
            }
        }
        for angle in [17.0, 45, 90] {
            for named in ["left", "right"] {
                let parts = [part("carrier", [0.05, 0.05, 0.05], at: [0.1 + 0.2, 0.3, 0]), part("left", [10, 10, 10], at: [-5, 0, 0], extra: #","parent":"carrier""#),
                             part("right", [10, 10, 10], at: [5 + (0.1 + 0.2) - 0.3, 0, 0], extra: #","parent":"carrier""#)]
                let t = doc(parts, named, [named == "left" ? 5 : -5, 0, 0],
                            step: #"{"say":"Inspect the named part.","camera":"front","annotate":["label"],"pose":{"carrier":{"rot":[0,0,1,\#(angle)]}},"hide":["carrier"],"orbit":\#(angle)}"#)
                XCTAssertTrue(strict(t).ok, "posed carrier \(angle) \(named)")
            }
        }
        let component = #"{"v":1,"kind":"component","id":"touchingPair","title":"Two touching boxes","about":"Synthetic precision fixture.","params":{"angle":{"default":0,"min":-180,"max":180}},"parts":[{"id":"carrier","shape":{"box":{"size":[0.05,0.05,0.05]}},"rot":[0,0,1,{"param":"angle"}]},{"id":"left","shape":{"box":{"size":[10,10,10]}},"parent":"carrier","at":[-5,0,0]},{"id":"right","shape":{"box":{"size":[10,10,10]}},"parent":"carrier","at":[5,0,0]}],"anchors":{"leftFace":"left","rightFace":"right"}}"#
        var library = MGSolidLibrary.builtIn
        _ = try library.register(Data(component.utf8)).get()
        for angle in [0.0, 17, 45, 90] {
            for named in ["left", "right"] {
                for posed in [false, true] {
                    let instance = posed ? #"{"id":"pair","use":"touchingPair","at":[0.30000000000000004,0.3,0]}"#
                        : #"{"id":"pair","use":"touchingPair","at":[0.30000000000000004,0.3,0],"rot":[0,0,1,\#(angle)]}"#
                    let pose = posed ? #","pose":{"pair":{"with":{"angle":\#(angle)}}}"# : ""
                    let t = doc([instance], "pair.\(named)", [named == "left" ? 5 : -5, 0, 0],
                                step: #"{"say":"Inspect the named part.","camera":"front","annotate":["label"],"hide":["pair.carrier"],"orbit":\#(angle)\#(pose)}"#)
                    XCTAssertTrue(strict(t, library: library).ok, "component \(angle) \(named) posed \(posed): \(strict(t, library: library).reason ?? "")")
                }
            }
        }
    }
}
