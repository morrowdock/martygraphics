// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import MartyGraphics

/// The framing rule "shown parts stay whole" (docs/SOLID-3D.md, "Shown parts stay whole"): every part a still draws
/// solid (not hidden, not a ghost) that the still shows at all lies inside the safe window, clear of the title and
/// caption bands. A focus close-up widens until that holds; an explicit `focus` stops at the minimum zoom and the check
/// warns with the exact `ghost` repair. One framing function gives the stills, the story, the render plan and the
/// SwiftUI pane, so one fix covers all four. The fixtures are generic reductions of the r2j jet-suit failures: a figure
/// whose head sat under the title band and whose legs were cut (a highlighted back pack), and a hand engine close-up
/// that cut the body at the pane edge.
final class ShownPartsFramingTests: XCTestCase {
    /// A figure (Z up, mm): legs, torso, head, a pack on the back, an arm and a small engine at the hand. The parts are
    /// apart by 20 mm (more than the touch tolerance), except the pack, the arm and the engine, which touch.
    static let parts = """
    [{"id": "legs", "shape": {"box": {"size": [200, 120, 900], "at": [0, 0, 450]}}},
     {"id": "torso", "shape": {"box": {"size": [400, 200, 600], "at": [0, 0, 1220]}}},
     {"id": "head", "shape": {"box": {"size": [180, 180, 220], "at": [0, 0, 1650]}}},
     {"id": "pack", "shape": {"box": {"size": [200, 120, 300], "at": [0, 160, 1350]}}},
     {"id": "arm", "shape": {"box": {"size": [500, 100, 100], "at": [450, 0, 1450]}}},
     {"id": "jet", "shape": {"box": {"size": [60, 60, 120], "at": [730, 0, 1450]}}}]
    """
    static let label = #"{"labels": [{"id": "lJet", "at": {"world": [-600, 0, 1900]}, "text": "Hand engine (example)"}]}"#

    /// Step 1: a highlighted pack (inferred focus: the pack and the torso it touches), the r2j head-under-the-band
    /// case. Step 2: an explicit `focus` on the small engine with a label at a world point far away, the r2j
    /// cut-at-the-edge case. Step 3: the whole figure.
    static func assembly(ghost: String? = nil) -> String {
        let g = ghost.map { #", "ghost": \#($0)"# } ?? ""
        return """
        {"v": 2, "kind": "assembly", "title": "Figure", "parts": \(parts), "annotations": \(label),
         "steps": [{"say": "The pack on the back.", "highlight": ["pack"], "camera": "front", "annotate": []},
                   {"say": "The hand engine.", "focus": ["jet"], "camera": "front", "annotate": ["lJet"]\(g)},
                   {"say": "The whole figure.", "camera": "front", "annotate": []}]}
        """
    }

    static func explainer(ghost: String? = nil) -> String {
        let g = ghost.map { #", "ghost": \#($0)"# } ?? ""
        return """
        {"v": 1, "kind": "explainer", "title": "Figure", "solid": {"v": 2, "parts": \(parts), "annotations": \(label)},
         "beats": [{"say": "The pack on the back.", "highlight": ["pack"], "view": {"camera": "front", "annotate": []}},
                   {"say": "The hand engine.", "view": {"focus": ["jet"], "camera": "front", "annotate": ["lJet"]\(g)}},
                   {"say": "The whole figure.", "view": {"camera": "front", "annotate": []}}]}
        """
    }

    func compile(_ t: String) throws -> MGSolidDocument { try MGSolidParser.document(data: Data(t.utf8)).get() }

    /// Every solid part's points at a still's pose (the parts its view draws solid).
    func solidPoints(_ doc: MGSolidDocument, _ v: MGAnnotationAnchorView) -> [MGVec3] {
        let ids = doc.assembly.parts.map(\.id).filter { !v.view.part($0).hidden && v.view.part($0).opacity >= MGSolidFraming.blockingOpacity }
        return MGSolidFraming.Samples(doc.assembly, ids: ids).world(doc.assembly, v.params, stage: MGSolidStage.zUpToYUp)
    }

    /// The pack step and the whole figure: before, the pack close-up put the head under the title band and cut the
    /// legs, and the whole-model rule let the earlier framing reach into the title band. Now every solid part is inside
    /// the safe window.
    func testStillsKeepEveryShownPartInsideTheSafeWindow() throws {
        let doc = try compile(Self.assembly())
        let plan = MGSolidRenderPlan(doc, sourceName: "figure.json", source: MGSolidSource(data: Data(Self.assembly().utf8)))
        let cams = plan.cameras(doc, width: 1280, height: 800)
        let bands = MGSolidRenderPlan.bands(width: 1280, height: 800)
        for (k, s) in plan.stills.enumerated() where s.step != 1 {
            let window = MGSolidFraming.Window(titleBand: s.title != nil ? bands.title : 0, captionBand: s.caption != nil ? bands.caption : 0)
            let view = cams.clear[k].view(doc.view(step: s.step))
            let v = MGAnnotationAnchorView(view: view, params: s.params, camera: cams.stills[k], width: 1280, height: 800, step: s.step, beat: nil)
            XCTAssertTrue(MGSolidFraming.contains(solidPoints(doc, v), camera: cams.stills[k], aspect: 1.6, window: window), s.file)
            XCTAssertEqual(MGSolidFraming.cutParts(doc, view: view, params: s.params, camera: cams.stills[k], aspect: 1.6, window: window), [], s.file)
        }
        // The pack step is still framed on its focus (the occlusion rule runs), widened to the whole figure.
        let pack = try XCTUnwrap(plan.stills.firstIndex { $0.step == 0 })
        XCTAssertEqual(cams.rules[pack], .focus)
        // The explicit close-up keeps its zoom: widening would make the engine fill less than the minimum.
        let jet = try XCTUnwrap(plan.stills.firstIndex { $0.step == 1 })
        XCTAssertEqual(cams.rules[jet], .focus)
        XCTAssertLessThan(cams.stills[jet].distance, cams.stills[pack].distance / 3)
    }

    /// The explicit close-up that cannot keep the figure whole is a warning with an exact repair: the report names the
    /// parts it cuts and the `ghost` list; with that list applied, the still cuts nothing and the warning is gone.
    func testAnExplicitCloseUpThatCutsPartsWarnsWithAnExactGhostRepair() throws {
        let r = MGSolidReport.check(data: Data(Self.assembly().utf8), profile: .strict)
        XCTAssertTrue(r.ok, "a warning, not a refusal: \(r.reason ?? "")")
        guard case .object(let o) = r.json, case .array(let cuts)? = o["framingCuts"], case .array(let warnings)? = o["warnings"] else {
            return XCTFail("framingCuts")
        }
        XCTAssertEqual(cuts.count, 1)
        guard case .object(let c) = cuts[0], case .array(let ghost)? = c["ghost"], case .string(let repair)? = c["repair"] else { return XCTFail("cut") }
        XCTAssertEqual(c["step"], .number(2))
        XCTAssertEqual(ghost, [.string("torso"), .string("pack")])
        XCTAssertEqual(repair, "Step 2 cuts torso, pack at the frame edge or under a band, and widening its close-up would make the focus fill less than 25 % of the safe window. Set \"ghost\": [\"torso\", \"pack\"] in the step (see-through context may leave the frame), or remove its \"focus\" so the whole model is framed.")
        XCTAssertTrue(warnings.contains(.object(["reason": .string("framing.cut.step.2"), "part": .string("torso")])))
        XCTAssertEqual(MGSolidReasons.lookup("framing.cut.step.2")?.kind, .warning)
        XCTAssertEqual(MGSolidReasons.lookup("framing.cut.step.2")?.strict, false)
        // The repair, applied as printed.
        let fixed = Self.assembly(ghost: #"["torso", "pack"]"#)
        let r2 = MGSolidReport.check(data: Data(fixed.utf8), profile: .strict)
        XCTAssertTrue(r2.ok)
        guard case .object(let o2) = r2.json else { return XCTFail("report") }
        XCTAssertNil(o2["framingCuts"])
        let doc = try compile(fixed)
        for f in doc.framedStills() {
            XCTAssertEqual(MGSolidFraming.cutParts(doc, view: f.still.view, params: f.still.params, camera: f.still.camera, aspect: 1.6,
                                                   window: f.window), [], "step \((f.still.step ?? 0) + 1)")
        }
        // The removed `focus` repair frames the whole figure.
        let unfocused = Self.assembly().replacingOccurrences(of: #""focus": ["jet"], "#, with: "")
        guard case .object(let o3) = MGSolidReport.check(data: Data(unfocused.utf8), profile: .strict).json else { return XCTFail("report") }
        XCTAssertNil(o3["framingCuts"])
    }

    /// One framing function, four hosts: the beat stills (`marty-solid render`), the story's hold frames (they take the
    /// still cameras), the render plan's step stills and the SwiftUI solid pane frame each beat or step the same way, and
    /// none of them cuts a solid part except the explicit close-up that the report warns about.
    @MainActor func testStillsStoryRenderPlanAndPaneShareTheRule() throws {
        // Render plan and step stills: `framedStills` (the check report) is the render plan's camera for every step.
        let doc = try compile(Self.assembly())
        let plan = MGSolidRenderPlan(doc, sourceName: "figure.json", source: MGSolidSource(data: Data(Self.assembly().utf8)))
        let cams = plan.cameras(doc, width: 1280, height: 800)
        let stills = doc.framedStills()
        var stepCameras: [MGSolidCamera] = []
        for f in stills {
            let k = try XCTUnwrap(plan.stills.firstIndex { $0.step == f.still.step })
            XCTAssertEqual(f.still.camera, cams.stills[k], "step \((f.still.step ?? 0) + 1)")
            stepCameras.append(f.still.camera)
        }
        // The story holds each beat on its still's camera, so its hold frames show what the stills show.
        let story = try MGStoryPlan(captions: doc.steps.map(\.say), spins: doc.steps.map(\.spin))
        for k in doc.steps.indices {
            XCTAssertEqual(story.camera(frame: story.holdStartFrame(k), beatCameras: stepCameras), stepCameras[k], "story beat \(k + 1)")
        }
        // The explainer: beat stills, and the SwiftUI pane at each beat's pane size (`playPane` checks that the pane
        // shows the still's camera, ghosts and drops).
        let ex = try MGExplainer.parse(data: Data(Self.explainer().utf8)).get()
        let beats = MGExplainerFrame.beatStills(ex)
        let solid = try XCTUnwrap(beats.solid)
        XCTAssertEqual(beats.stills.count, 3)
        for f in beats.stills {
            let v = f.still
            let cut = MGSolidFraming.cutParts(solid, view: v.view, params: v.params, camera: v.camera, aspect: v.width / v.height, window: f.window)
            XCTAssertEqual(cut, v.beat == 1 ? ["torso", "pack"] : [], "beat \((v.beat ?? 0) + 1)")
        }
        let pane = try ExplainerPaneFramingTests().playPane(ex, "figure")
        XCTAssertEqual(pane.map(\.camera), beats.stills.map(\.still.camera))
        // The explainer report warns for the beat, with the `view` repair.
        let r = MGExplainerReport.check(data: Data(Self.explainer().utf8), profile: .strict)
        XCTAssertTrue(r.ok, r.reason ?? "")
        guard case .object(let o) = r.json, case .array(let cuts)? = o["framingCuts"], case .object(let c)? = cuts.first,
              case .string(let repair)? = c["repair"] else { return XCTFail("framingCuts") }
        XCTAssertEqual(c["beat"], .number(2))
        XCTAssertTrue(repair.contains(#"Set "ghost": ["torso", "pack"] in its "view""#), repair)
        let fixed = MGExplainerReport.check(data: Data(Self.explainer(ghost: #"["torso", "pack"]"#).utf8), profile: .strict)
        guard case .object(let o2) = fixed.json else { return XCTFail("report") }
        XCTAssertNil(o2["framingCuts"])
    }

    /// The widening is bounded and deterministic: the same document frames to the same cameras, and a figure whose
    /// close-up cuts nothing keeps its close-up exactly (no widening).
    func testWideningIsDeterministicAndOnlyWhenACloseUpCuts() throws {
        let a = try compile(Self.assembly()), b = try compile(Self.assembly())
        XCTAssertEqual(a.framedStills().map(\.still.camera), b.framedStills().map(\.still.camera))
        // A lone block far from a column: its close-up shows no part of the column, so it is not widened.
        let doc = try compile(SolidFramingTests.tower)
        let plan = MGSolidRenderPlan(doc, sourceName: "t.json", source: MGSolidSource(data: Data(SolidFramingTests.tower.utf8)))
        let cams = plan.cameras(doc, width: 1280, height: 800)
        XCTAssertEqual(cams.rules, [.modelFitted, .modelFitted, .focus, .focus, .modelFitted, .modelFitted])
        XCTAssertLessThan(cams.stills[2].distance, cams.stills[0].distance / 3)
    }
}
