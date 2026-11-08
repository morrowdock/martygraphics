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
        XCTAssertEqual(warnings(standard), ["annotation.anchor.hidden.l1"])
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
            XCTAssertEqual(a["closerDistance"], .number(0))
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
        XCTAssertGreaterThan(mgSolidDistance(x, d.assembly.part("frame")!.mesh), 50)
        XCTAssertEqual(mgSolidDistance(MGVec3(0, 14, 85), d.assembly.part("frame")!.mesh), 0, "inside the solid")
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
