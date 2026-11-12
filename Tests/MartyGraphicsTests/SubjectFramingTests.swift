// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import MartyGraphics

/// Subject-first framing (docs/SOLID-3D.md, "Subject first"): a step's subject (its `focus`, or its highlighted,
/// section and annotated parts) is framed alone at the closest framing that keeps it whole; context may be cut at the
/// safe window's edges and the renderer clips the model to that window; a subject that misses a floor gives
/// `framing.subject.small.<step|beat>.<n>` with exact repairs. One framing function gives the stills, the story, the
/// render plan and the SwiftUI pane. The fixtures are generic reductions of the r2j jet-suit failures (a head under the
/// title band above a highlighted back pack; arm engines too small to read) and of the PR #51 review (a whole-figure
/// view that shrank the subject; a wall that spans the view with every vertex outside it).
final class SubjectFramingTests: XCTestCase {
    /// A figure (Z up, mm): legs, torso, head, a back pack, two arms and a small engine at each hand. The parts are apart
    /// by 20 mm or more (more than the touch tolerance), except where an arm meets the torso.
    static let parts = """
    [{"id": "legs", "shape": {"box": {"size": [200, 120, 900], "at": [0, 0, 450]}}},
     {"id": "torso", "shape": {"box": {"size": [400, 200, 600], "at": [0, 0, 1220]}}},
     {"id": "head", "shape": {"box": {"size": [180, 180, 220], "at": [0, 0, 1650]}}},
     {"id": "pack", "shape": {"box": {"size": [200, 120, 300], "at": [0, 160, 1350]}}},
     {"id": "armL", "shape": {"box": {"size": [500, 100, 100], "at": [450, 0, 1450]}}},
     {"id": "armR", "shape": {"box": {"size": [500, 100, 100], "at": [-450, 0, 1450]}}},
     {"id": "jetL", "shape": {"box": {"size": [24, 60, 60], "at": [740, 0, 1450]}}},
     {"id": "jetR", "shape": {"box": {"size": [24, 60, 60], "at": [-740, 0, 1450]}}}]
    """
    static let labels = #"{"labels": [{"id": "lFar", "at": {"world": [-3900, 0, 3900]}, "text": "Far note"}, {"id": "lPack", "at": {"part": "pack", "point": "centre"}, "text": "Pack"}]}"#

    /// Step 1: the pack (highlight), the head-under-the-band case. Step 2: both small engines (highlight), far apart.
    /// Step 3: the pack with a far world-point label. Step 4: the whole figure.
    static func assembly(step2: String = #""highlight": ["jetL", "jetR"]"#, far: Bool = true) -> String {
        let step3 = far ? #"["lPack", "lFar"]"# : #"["lPack"]"#
        let annotations = far ? labels : #"{"labels": [{"id": "lPack", "at": {"part": "pack", "point": "centre"}, "text": "Pack"}]}"#
        return """
        {"v": 2, "kind": "assembly", "title": "Figure", "parts": \(parts), "annotations": \(annotations),
         "steps": [{"say": "The pack on the back.", "highlight": ["pack"], "camera": "back", "annotate": ["lPack"]},
                   {"say": "The hand engines.", \(step2), "camera": "front", "annotate": []},
                   {"say": "The pack, with a note.", "highlight": ["pack"], "camera": "back", "annotate": \(step3)},
                   {"say": "The whole figure.", "camera": "front", "annotate": []}]}
        """
    }

    static func explainer() -> String {
        """
        {"v": 1, "kind": "explainer", "title": "Figure", "solid": {"v": 2, "parts": \(parts), "annotations": \(labels)},
         "beats": [{"say": "The pack on the back.", "highlight": ["pack"], "view": {"camera": "back", "annotate": ["lPack"]}},
                   {"say": "The hand engines.", "highlight": ["jetL", "jetR"], "view": {"camera": "front", "annotate": []}},
                   {"say": "The pack, with a note.", "highlight": ["pack"], "view": {"camera": "back", "annotate": ["lPack", "lFar"]}},
                   {"say": "The whole figure.", "view": {"camera": "front", "annotate": []}}]}
        """
    }

    func compile(_ t: String) throws -> MGSolidDocument { try MGSolidParser.document(data: Data(t.utf8)).get() }
    func report(_ t: String) -> [String: MGJSON] {
        guard case .object(let o) = MGSolidReport.check(data: Data(t.utf8), profile: .strict).json else { return [:] }
        return o
    }
    func cut(_ doc: MGSolidDocument, _ f: MGFramedStill, ids: [String]? = nil) -> [String] {
        let v = f.still
        return MGSolidFraming.cutParts(doc, view: v.view, params: v.params, camera: v.camera, aspect: v.width / v.height, window: f.window,
                                       ids: ids)
    }

    /// The pack step is a close-up of the pack, not a whole-figure view: the subject is whole and large, the context
    /// (head, legs) is cut at the safe window and clipped there. Before (PR #51 head), the step zoomed out to the whole
    /// figure and the pack filled a few per cent of the window; at main it was a close-up whose head sat under the band.
    func testTheSubjectIsFramedAloneAndStaysLarge() throws {
        let doc = try compile(Self.assembly())
        let stills = doc.framedStills()
        // Step 3's far label joins the fit (every drawn target is inside), so it spans the model: a whole-model still.
        XCTAssertEqual(stills.map(\.rule), [.focus, .focus, .modelFitted, .modelFitted])
        let pack = stills[0]
        XCTAssertEqual(MGSolidFraming.subjectParts(doc, shot: pack.shot).parts, ["pack"])
        let pts = MGSolidFraming.Samples(doc.assembly, ids: ["pack"]).world(doc.assembly, pack.still.params, stage: MGSolidStage.zUpToYUp)
        XCTAssertEqual(MGSolidFraming.filled(pts, camera: pack.still.camera, aspect: 1.6, window: pack.window), MGSolidFraming.fill, accuracy: 0.01)
        XCTAssertEqual(cut(doc, pack, ids: ["pack"]), [], "the subject is whole")
        XCTAssertTrue(cut(doc, pack).contains("head"), "context is cut at the safe window: \(cut(doc, pack))")
        // The whole-figure step keeps every part whole.
        XCTAssertEqual(cut(doc, stills[3]), [])
        // The pack close-up meets its floors. Step 3's far label makes it a whole-model still, where the pack is small:
        // the floors are measured whatever the framing class.
        let floors = doc.subjectIssues(stills)
        XCTAssertEqual(floors.map(\.reason), ["framing.subject.small.step.2", "framing.subject.small.step.3"])
    }

    /// Rule (b): every target a still draws lies inside its safe window, a far world-point label too. The re-check
    /// found labels left "(off view)" by a close-up; now the label joins the fit and the subject floors warn instead.
    func testEveryDrawnTargetIsInsideTheSafeWindow() throws {
        let doc = try compile(Self.assembly())
        let stills = doc.framedStills()
        let f = stills[2], v = f.still
        let anchors = MGSolidFraming.annotationPoints(doc, view: v.view, params: v.params)
        XCTAssertEqual(anchors.count, 2)
        XCTAssertTrue(MGSolidFraming.contains(anchors, camera: v.camera, aspect: 1.6, window: f.window))
        XCTAssertNotEqual(stills[2].still.camera, stills[0].still.camera, "the far label widens the pack shot")
        let o = report(Self.assembly())
        XCTAssertEqual(o["ok"], .bool(true))
        guard case .array(let issues)? = o["anchorIssues"] else { return XCTFail("anchorIssues") }
        XCTAssertTrue(issues.isEmpty, "\(issues)")
    }

    /// Rule (c): a posed step's inferred subject brings every chain the pose moves. The step highlights only the jet at
    /// the raised hand (the r2j step-5 case); the raised upper arm, forearm and hand join the fit, so the step does not
    /// become a close-up of the jet.
    func testAPosedStepKeepsItsMovedChain() throws {
        let t = #"{"v": 2, "kind": "assembly", "title": "Pose", "parts": [{"id": "pilot", "use": "mannequin"}, {"id": "jet", "parent": "pilot.leftHand", "shape": {"box": {"size": [40, 40, 90]}}}], "annotations": {"labels": [{"id": "lNote", "at": {"world": [0, -350, 1950]}, "text": "Steering by the arms"}]}, "steps": [{"say": "One arm raised.", "highlight": ["jet"], "camera": "front", "annotate": ["lNote"], "pose": {"pilot": {"with": {"leftShoulder": 70}}}}]}"#
        let doc = try compile(t)
        let f = try XCTUnwrap(doc.framedStills().first)
        let subject = MGSolidFraming.subjectParts(doc, shot: f.shot)
        XCTAssertEqual(subject.parts, ["jet"])
        for p in ["pilot.upperArmL", "pilot.lowerArmL", "pilot.handL"] { XCTAssertTrue(subject.moved.contains(p), p) }
        XCTAssertFalse(subject.moved.contains("pilot.legL"))
        let pts = MGSolidFraming.Samples(doc.assembly, ids: subject.parts + subject.moved).world(doc.assembly, f.still.params, stage: MGSolidStage.zUpToYUp)
        XCTAssertTrue(MGSolidFraming.contains(pts, camera: f.still.camera, aspect: 1.6, window: f.window), "the raised arm is whole")
        XCTAssertTrue(MGSolidFraming.contains(MGSolidFraming.annotationPoints(doc, view: f.still.view, params: f.still.params),
                                              camera: f.still.camera, aspect: 1.6, window: f.window), "the label is inside")
    }

    /// Re-check B3: a core inside an opaque 200 mm shell (an inner 100 mm shell already ghosted) is hidden; a face that
    /// crosses the near plane still hides it on the raster (clipped, not dropped). Before: 88,112 px "visible".
    func testAFaceAcrossTheNearPlaneStillHidesOnTheRaster() throws {
        let t = #"{"v": 2, "kind": "assembly", "parts": [{"id": "core", "shape": {"box": {"size": [20, 20, 20]}}}, {"id": "shellA", "shape": {"box": {"size": [100, 100, 100]}}}, {"id": "shellB", "shape": {"box": {"size": [200, 200, 200]}}}], "steps": [{"say": "The core.", "camera": "front", "focus": ["core"], "ghost": ["shellA"]}]}"#
        let doc = try compile(t)
        let f = try XCTUnwrap(doc.framedStills().first)
        let r = try XCTUnwrap(MGStillRaster(doc, f.still, groups: [["core"]]))
        XCTAssertEqual(r.visible(0).pixels, 0)
        let issues = doc.subjectIssues([f]) { doc.authoredGhost(step: $0.still.step) }
        XCTAssertEqual(issues.map(\.reason), ["framing.subject.small.step.1"])
        XCTAssertEqual(issues.first?.ghost, ["shellA", "shellB"], "the complete list: the existing ghost kept")
    }

    /// Re-check S1: separately named parts of one instance are measured on their own. A foot named beside the body
    /// misses the floor although the body is large.
    func testSeparatelyNamedPartsMeetTheFloorEachOnTheirOwn() throws {
        let t = #"{"v": 2, "kind": "assembly", "parts": [{"id": "pilot", "use": "mannequin"}], "steps": [{"say": "Body and foot.", "camera": "front", "focus": ["pilot.body", "pilot.footL"]}]}"#
        let doc = try compile(t)
        let stills = doc.framedStills()
        XCTAssertEqual(MGSolidFraming.subjectGroups(doc, ["pilot.body", "pilot.footL"]).map(\.unit), ["pilot.body", "pilot.footL"])
        let issues = doc.subjectIssues(stills)
        let small = issues.first.map { i in i.small.map { i.groups[$0].unit } } ?? []
        XCTAssertEqual(small, ["pilot.footL"])
        // A whole instance is one group.
        let whole = try compile(#"{"v": 2, "kind": "assembly", "parts": [{"id": "pilot", "use": "mannequin"}], "steps": [{"say": "All.", "camera": "front", "highlight": ["pilot"]}]}"#)
        XCTAssertEqual(MGSolidFraming.subjectGroups(whole, whole.assembly.parts.map(\.id), whole: ["pilot"]).map(\.unit), ["pilot"])
        XCTAssertEqual(whole.framedStills().first?.wholeInstances, ["pilot"])
    }

    /// Re-check S2: the ghost repair returns the complete list. A core inside two shells (enclosing context is never an
    /// automatic ghost, and no direction sees past it), shell A already ghosted: the repair is ["shellA", "shellB"]
    /// (before: ["shellB"], which made A opaque again), and applying it clears the floor warning. With a label on the
    /// core, the main-rule camera of main keeps the document accepted (its camera sees the core).
    func testTheGhostRepairKeepsTheExistingGhosts() throws {
        func doc(_ ghost: String, label: Bool = false) -> String {
            let l = label ? #", "annotations": {"labels": [{"id": "lCore", "at": {"part": "core", "point": "centre"}, "text": "Core"}]}"# : ""
            let a = label ? #", "annotate": ["lCore"]"# : ""
            return #"{"v": 2, "kind": "assembly", "parts": [{"id": "core", "shape": {"box": {"size": [20, 20, 20]}}}, {"id": "shellA", "shape": {"box": {"size": [100, 100, 100]}}}, {"id": "shellB", "shape": {"box": {"size": [200, 200, 200]}}}]\#(l), "steps": [{"say": "The core.", "camera": "front", "focus": ["core"], "ghost": \#(ghost)\#(a)}]}"#
        }
        let o = report(doc(#"["shellA"]"#))
        guard case .array(let floors)? = o["subjectFloors"], case .object(let f)? = floors.first, case .string(let repair)? = f["repair"]
        else { return XCTFail("subjectFloors: \(o["reason"] ?? .null)") }
        XCTAssertEqual(f["ghost"], .array([.string("shellA"), .string("shellB")]))
        XCTAssertTrue(repair.contains(#""ghost": ["shellA", "shellB"]"#), repair)
        let fixed = report(doc(#"["shellA", "shellB"]"#))
        XCTAssertEqual(fixed["ok"], .bool(true))
        XCTAssertNil(fixed["subjectFloors"])
        XCTAssertEqual(report(doc(#"["shellA"]"#, label: true))["ok"], .bool(true))
        XCTAssertEqual(report(doc(#"["shellA", "shellB"]"#, label: true))["ok"], .bool(true))
    }

    // MARK: Re-check of 36f5d21

    static let farLabelTwoSteps = #"{"v":2,"kind":"assembly","title":"Far label","parts":[{"id":"detail","shape":{"box":{"size":[20,20,20]}}},{"id":"body","shape":{"box":{"size":[200,100,300],"at":[0,100,0]}}}],"annotations":{"labels":[{"id":"far","at":{"world":[3900,0,3900]},"text":"A remote note"}]},"steps":[{"say":"The readable detail.","focus":["detail"],"camera":"front","annotate":[]},{"say":"A detail with a remote note.","highlight":["detail"],"camera":"front","annotate":["far"]}]}"#
    static let wholeAcceptance = #"{"v":2,"kind":"assembly","title":"Whole model","parts":[{"id":"lower","shape":{"box":{"size":[800,20,20],"at":[0,400,0]}}},{"id":"upper","shape":{"box":{"size":[800,20,20],"at":[0,-400,1000]}}},{"id":"blocker","at":[72.0,-291.3935875760057,543.3813304927515],"shape":{"box":{"size":[4,4,4]}}}],"annotations":{"labels":[{"id":"note","at":{"world":[80,0,500]},"text":"A note"}]},"steps":[{"say":"The model.","camera":"front","annotate":["note"]}]}"#

    /// B2: the floors are measured on every still with a subject, whatever its framing class. Step 2's far label makes it
    /// a whole-model still; its 20 mm detail still warns (before: no warning at all).
    func testTheFloorsApplyWhateverTheFramingClass() throws {
        let doc = try compile(Self.farLabelTwoSteps)
        let stills = doc.framedStills()
        XCTAssertEqual(stills[1].rule, .modelFitted)
        let o = report(Self.farLabelTwoSteps)
        XCTAssertEqual(o["ok"], .bool(true))
        guard case .array(let floors)? = o["subjectFloors"] else { return XCTFail("subjectFloors") }
        let steps: [MGJSON] = floors.compactMap { j -> MGJSON? in
            guard case .object(let f) = j else { return nil }
            return f["step"]
        }
        XCTAssertEqual(steps, [MGJSON.number(2)])
    }

    /// B3: the main-rule fallback covers whole-model stills too. This document passes `check --strict` at main; the
    /// subject-first whole-model fit would hide its label behind a 4 mm blocker, so the still keeps main's camera.
    func testAWholeModelDocumentAcceptedAtMainStaysAccepted() throws {
        let o = report(Self.wholeAcceptance)
        XCTAssertEqual(o["ok"], .bool(true), "\(o["reason"] ?? .null)")
        let doc = try compile(Self.wholeAcceptance)
        let shot = try XCTUnwrap(MGSolidShot.step(doc, 0))
        let bands = MGSolidRenderPlan.bands(width: 1280, height: 800)
        let clear = MGSolidFraming.clearView(doc, shot: shot, aspect: 1.6, titleBand: bands.title, captionBand: bands.caption)
        XCTAssertTrue(clear.mainRule)
        XCTAssertEqual(clear.camera.distance, MGSolidFraming.mainRule(doc, shot: shot, aspect: 1.6, fieldOfView: 30, titleBand: bands.title,
                                                                       captionBand: bands.caption, stage: MGSolidStage.zUpToYUp).camera.distance,
                       accuracy: 1e-9)
    }

    /// S1: every camera consumer gets the one effective camera. The renderer's `frame` (a host's entry point) takes the
    /// still's camera with the fallback, so the label is visible there; the report's `stillPlacements` places a far
    /// label at the still's camera (inside the frame, not "off view"), where the legacy `placements` used a default camera.
    func testEveryCameraConsumerGetsTheEffectiveCamera() throws {
        let doc = try compile(Self.wholeAcceptance)
        let f = try XCTUnwrap(doc.framedStills().first)
        let r = MGSolidRenderer(document: doc)
        let shot = try XCTUnwrap(MGSolidShot.step(doc, 0))
        r.apply(shot.params)
        r.frame(shot, document: doc, aspect: 1.6)
        XCTAssertEqual(r.camera, f.still.camera)
        XCTAssertEqual(MGSolidFraming.camera(doc, shot: shot, aspect: 1.6), f.still.camera)
        let v = MGAnnotationAnchorView(view: f.still.view, params: f.still.params, camera: r.camera, width: 1280, height: 800, step: 0, beat: nil)
        XCTAssertEqual(doc.anchorIssues(v).issues.count, 0, "the label is visible in the render")
        let o = report(Self.farLabelTwoSteps)
        guard case .array(let placed)? = o["stillPlacements"], case .object(let step2)? = placed.last,
              case .array(let items)? = step2["placement"], case .object(let item)? = items.first else { return XCTFail("stillPlacements") }
        XCTAssertEqual(step2["step"], .number(2))
        XCTAssertEqual(item["id"], .string("far"))
        XCTAssertEqual(item["offView"], .bool(false), "the still shows the far label")
    }

    /// S2: each explicitly named part is measured alone, also when the named parts together cover an instance; only an
    /// instance named by its id is one group. Naming all 11 engine parts: the hidden bearings and shaft warn.
    func testEveryExplicitlyNamedPartIsMeasuredAlone() throws {
        let names = ["jet.intakeLip", "jet.impeller", "jet.diffuser", "jet.combustor", "jet.nozzleGuideVanes", "jet.turbineWheel", "jet.nozzle",
                     "jet.shaft", "jet.frontBearing", "jet.rearBearing", "jet.casing"]
        let t = #"{"v":2,"kind":"assembly","parts":[{"id":"jet","use":"microTurbojet","with":{"cutaway":0}}],"steps":[{"say":"Every named engine part.","camera":"side","focus":[\#(names.map { "\"\($0)\"" }.joined(separator: ","))]}]}"#
        let o = report(t)
        guard case .array(let floors)? = o["subjectFloors"], case .object(let f)? = floors.first, case .array(let groups)? = f["groups"]
        else { return XCTFail("subjectFloors") }
        XCTAssertEqual(groups.count, 11)
        let small = groups.compactMap { g -> String? in
            guard case .object(let o) = g, o["small"] == .bool(true), case .string(let u)? = o["unit"] else { return nil }
            return u
        }
        XCTAssertTrue(small.contains("jet.frontBearing") && small.contains("jet.rearBearing") && small.contains("jet.shaft"), "\(small)")
        // The instance named by its id is one group.
        let whole = report(#"{"v":2,"kind":"assembly","parts":[{"id":"jet","use":"microTurbojet","with":{"cutaway":0}}],"steps":[{"say":"The engine.","camera":"side","focus":["jet"]}]}"#)
        XCTAssertNil(whole["subjectFloors"])
    }

    /// A sub-part named explicitly is always measured alone, also when its instance is named too: the instance stays one
    /// group for its other parts, and the hidden front bearing warns (re-check of 2452f2d: it was pooled into the
    /// instance and measured 0 px with no warning). Both a focus list and a highlight name it.
    func testANamedSubPartIsMeasuredAloneBesideItsNamedInstance() throws {
        for keys in [#""focus":["jet","jet.frontBearing"]"#, #""focus":["jet"],"highlight":["jet.frontBearing"]"#] {
            let t = #"{"v":2,"kind":"assembly","parts":[{"id":"jet","use":"microTurbojet","with":{"cutaway":0}}],"steps":[{"say":"The engine and its bearing.","camera":"side",\#(keys)}]}"#
            let o = report(t)
            guard case .array(let floors)? = o["subjectFloors"], case .object(let f)? = floors.first, case .array(let groups)? = f["groups"]
            else { return XCTFail("\(keys): subjectFloors") }
            let units = groups.compactMap { g -> String? in if case .object(let x) = g, case .string(let u)? = x["unit"] { return u }; return nil }
            XCTAssertEqual(units, ["jet", "jet.frontBearing"], keys)
            let bearing = groups.compactMap { g -> [String: MGJSON]? in if case .object(let x) = g, x["unit"] == .string("jet.frontBearing") { return x }; return nil }.first
            XCTAssertEqual(bearing?["pixels"], .number(0), keys)
            XCTAssertEqual(bearing?["small"], .bool(true), keys)
            guard case .object(let jet)? = groups.first, case .array(let parts)? = jet["parts"] else { return XCTFail("jet group") }
            XCTAssertFalse(parts.contains(.string("jet.frontBearing")), "the instance group keeps its other parts only")
            XCTAssertEqual(parts.count, 10)
        }
    }

    /// S3: the public API's default returns the complete ghost list (the step's own ghosts kept), as the CLI does.
    func testThePublicAPIReturnsTheCompleteGhostList() throws {
        let doc = try compile(#"{"v": 2, "kind": "assembly", "parts": [{"id": "core", "shape": {"box": {"size": [20, 20, 20]}}}, {"id": "shellA", "shape": {"box": {"size": [100, 100, 100]}}}, {"id": "shellB", "shape": {"box": {"size": [200, 200, 200]}}}], "steps": [{"say": "The core.", "camera": "front", "focus": ["core"], "ghost": ["shellA"]}]}"#)
        XCTAssertEqual(doc.subjectIssues(doc.framedStills()).first?.ghost, ["shellA", "shellB"])
        XCTAssertEqual(doc.stillMeasures(doc.framedStills()).subjects.first?.ghost, ["shellA", "shellB"])
    }

    /// S4: an explicit focus that a far label pushes below its floors gets an exact repair: the step's `annotate` list
    /// without the far label, which moves to a view of its own.
    func testAFarLabelGetsAnExactAnnotateRepair() throws {
        let t = Self.farLabelTwoSteps.replacingOccurrences(of: #""highlight":["detail"],"camera":"front","annotate":["far"]"#,
                                                           with: #""focus":["detail"],"camera":"front","annotate":["far"]"#)
        let o = report(t)
        guard case .array(let floors)? = o["subjectFloors"], case .object(let f)? = floors.first, case .string(let repair)? = f["repair"]
        else { return XCTFail("subjectFloors") }
        XCTAssertEqual(f["annotate"], .object(["keep": .array([]), "move": .array([.string("far")])]))
        XCTAssertTrue(repair.contains(#"set "annotate": [] in the step, and show ["far"] in a view of their own"#), repair)
        // The repair, applied: the far label in a step of its own.
        let fixed = t.replacingOccurrences(of: #""focus":["detail"],"camera":"front","annotate":["far"]}]"#,
                                           with: #""focus":["detail"],"camera":"front","annotate":[]},{"say":"A remote note.","camera":"front","annotate":["far"]}]"#)
        XCTAssertNotEqual(fixed, t)
        guard case .array(let after)? = report(fixed)["subjectFloors"] ?? .array([]) else { return XCTFail("report") }
        XCTAssertFalse(after.contains { if case .object(let x) = $0 { return x["step"] == .number(2) && x["annotate"] != .null } else { return false } })
    }

    /// Two small engines far apart: the closest whole framing shows each one too small. The report warns with the
    /// measure and exact repairs; applying the split repair (one step per engine) clears it.
    func testASubjectThatMissesAFloorWarnsWithExactRepairs() throws {
        let o = report(Self.assembly(far: false))
        XCTAssertEqual(o["ok"], .bool(true), "a warning, not a refusal: \(o["reason"] ?? .null)")
        guard case .array(let floors)? = o["subjectFloors"], case .object(let f)? = floors.first, case .array(let warnings)? = o["warnings"],
              case .string(let repair)? = f["repair"] else { return XCTFail("subjectFloors") }
        XCTAssertEqual(floors.count, 1)
        XCTAssertEqual(f["step"], .number(2))
        XCTAssertEqual(f["split"], .array([.array([.string("jetL")]), .array([.string("jetR")])]))
        XCTAssertEqual(f["subset"], .array([.string("jetL")]))
        XCTAssertTrue(repair.contains(#""focus": ["jetL"] then "focus": ["jetR"]"#), repair)
        XCTAssertTrue(repair.contains(#"focus a subset in the step: "focus": ["jetL"]"#), repair)
        XCTAssertTrue(warnings.contains(.object(["reason": .string("framing.subject.small.step.2"), "part": .string("jetL")])))
        XCTAssertEqual(MGSolidReasons.lookup("framing.subject.small.step.2")?.kind, .warning)
        XCTAssertEqual(MGSolidReasons.lookup("framing.subject.small.beat.2")?.strict, false)
        // The repair, applied: one engine per step.
        XCTAssertNil(report(Self.assembly(step2: #""focus": ["jetL"]"#, far: false))["subjectFloors"])
    }

    /// The review's adversarial fixture: a 2000 mm wall spans the whole view behind a 20 mm detail and every wall vertex
    /// lies outside the view. The crop test reads triangles, so the wall counts as shown and cut; the detail (the
    /// subject) is whole. With the wall as the subject, the wall is framed whole.
    func testAFaceThatSpansTheViewWithEveryVertexOutsideIsCut() throws {
        let spanning = #"{"v":2,"kind":"assembly","title":"Spanning surface","parts":[{"id":"wall","shape":{"box":{"size":[2000,20,2000],"at":[0,100,0]}}},{"id":"detail","shape":{"box":{"size":[20,20,20],"at":[0,0,0]}}}],"steps":[{"say":"The detail.","camera":"front","focus":["detail"]}]}"#
        let doc = try compile(spanning)
        let f = try XCTUnwrap(doc.framedStills().first)
        let v = f.still
        // Every wall vertex projects outside the view: the vertex test would call the wall unshown.
        let wall = MGSolidFraming.Samples(doc.assembly, ids: ["wall"]).world(doc.assembly, v.params, stage: MGSolidStage.zUpToYUp)
        let full = MGSolidFraming.Window(left: -1, right: 1, bottom: -1, top: 1)
        let b = MGSolidFraming.Basis(yaw: v.camera.yaw, pitch: v.camera.pitch), fo = MGSolidFraming.focal(v.camera.fieldOfView)
        for p in wall {
            let r = p - v.camera.targetVector, z = v.camera.distance + r.dot(b.fwd)
            XCTAssertFalse(abs(r.dot(b.right) * fo / 1.6 / z) <= 1 && abs(r.dot(b.up) * fo / z) <= 1)
        }
        XCTAssertEqual(cut(doc, f), ["wall"])
        XCTAssertEqual(cut(doc, f, ids: ["detail"]), [])
        XCTAssertGreaterThan(doc.unitPixels(v, units: ["wall"])?["wall"] ?? 0, 400_000, "the wall fills the view")
        XCTAssertEqual(MGSolidFraming.cutParts(doc, view: v.view, params: v.params, camera: v.camera, aspect: 1.6, window: full), ["wall"])
        // The wall as the subject: framed whole.
        let wallDoc = try compile(spanning.replacingOccurrences(of: #""focus":["detail"]"#, with: #""focus":["wall"]"#))
        let g = try XCTUnwrap(wallDoc.framedStills().first)
        XCTAssertEqual(cut(wallDoc, g), [])
    }

    /// A face that straddles the near plane (a floor under the camera) is in view: the test needs no division by depth.
    func testAFaceAcrossTheNearPlaneCounts() throws {
        let doc = try compile(#"{"v":2,"kind":"assembly","parts":[{"id":"floor","shape":{"box":{"size":[4000,4000,10],"at":[0,0,-200]}}},{"id":"detail","shape":{"box":{"size":[20,20,20]}}}],"steps":[{"say":"The detail.","camera":"low","focus":["detail"]}]}"#)
        let f = try XCTUnwrap(doc.framedStills().first)
        XCTAssertEqual(cut(doc, f), ["floor"])
    }

    /// One framing function, four hosts: the render plan's step stills, the story's hold frames (they take the still
    /// cameras), the beat stills and the SwiftUI solid pane frame each step or beat the same way; no subject part is cut
    /// in any of them; and the renderer clips the model to each still's safe window.
    @MainActor func testStillsStoryRenderPlanAndPaneShareTheSubjectRule() throws {
        let doc = try compile(Self.assembly())
        let plan = MGSolidRenderPlan(doc, sourceName: "figure.json", source: MGSolidSource(data: Data(Self.assembly().utf8)))
        let cams = plan.cameras(doc, width: 1280, height: 800)
        let stills = doc.framedStills()
        var stepCameras: [MGSolidCamera] = []
        for f in stills {
            let k = try XCTUnwrap(plan.stills.firstIndex { $0.step == f.still.step })
            XCTAssertEqual(f.still.camera, cams.stills[k], "step \((f.still.step ?? 0) + 1)")
            XCTAssertEqual(cut(doc, f, ids: MGSolidFraming.subjectParts(doc, shot: f.shot).parts), [], "step \((f.still.step ?? 0) + 1)")
            stepCameras.append(f.still.camera)
        }
        let story = try MGStoryPlan(captions: doc.steps.map(\.say), spins: doc.steps.map(\.spin))
        for k in doc.steps.indices {
            XCTAssertEqual(story.camera(frame: story.holdStartFrame(k), beatCameras: stepCameras), stepCameras[k], "story beat \(k + 1)")
        }
        let ex = try MGExplainer.parse(data: Data(Self.explainer().utf8)).get()
        let beats = MGExplainerFrame.beatStills(ex)
        let solid = try XCTUnwrap(beats.solid)
        // The whole-figure beat keeps the earlier framing: a pane has no band, and nothing leaves it.
        XCTAssertEqual(beats.stills.map(\.rule), [.focus, .focus, .modelFitted, .model])
        for f in beats.stills {
            XCTAssertEqual(cut(solid, f, ids: MGSolidFraming.subjectParts(solid, shot: f.shot).parts), [], "beat \((f.still.beat ?? 0) + 1)")
        }
        XCTAssertEqual(MGSolidFraming.subjectParts(solid, shot: beats.stills[0].shot).parts, ["pack"])
        let pane = try ExplainerPaneFramingTests().playPane(ex, "figure")
        XCTAssertEqual(pane.map(\.camera), beats.stills.map(\.still.camera))
        // The explainer report warns for the engines beat, with the beat's `view` repair.
        guard case .object(let o) = MGExplainerReport.check(data: Data(Self.explainer().utf8), profile: .strict).json,
              case .array(let floors)? = o["subjectFloors"], case .object(let f)? = floors.first, case .string(let repair)? = f["repair"]
        else { return XCTFail("subjectFloors") }
        XCTAssertEqual(f["beat"], .number(2))
        XCTAssertTrue(repair.contains(#"focus a subset in its "view": "focus": ["jetL"]"#), repair)
    }

    /// The renderer's clip: the safe window's pixel rectangle, and a real render whose title and caption bands hold only
    /// the studio backdrop although the pack close-up cuts the head there.
    func testTheRendererClipsTheModelToTheSafeWindow() throws {
        let bands = MGSolidRenderPlan.bands(width: 1280, height: 800)
        let w = MGSolidFraming.Window(titleBand: bands.title, captionBand: bands.caption)
        let r = try XCTUnwrap(MGSolidRenderer.clipRect(w, width: 1280, height: 800))
        XCTAssertEqual(r.minY, 160, accuracy: 0.5, "above the 160 px caption band (0.2 of 800)")
        XCTAssertEqual(r.maxY, 688, accuracy: 0.5, "below the 112 px title band (0.14 of 800)")
        XCTAssertEqual(r.width, 1280, accuracy: 0.5)
        XCTAssertNil(MGSolidRenderer.clipRect(MGSolidFraming.Window(titleBand: 0, captionBand: 0), width: 1280, height: 800))
        let doc = try compile(Self.assembly())
        let f = try XCTUnwrap(doc.framedStills().first)
        // The classic backdrop (the look this test's backdrop comparison was written for).
        let renderer = MGSolidRenderer(document: doc, look: .classic)
        renderer.show(document: doc, view: f.still.view)
        renderer.apply(f.still.params)
        renderer.setCamera(f.still.camera)
        guard let clipped = renderer.render(width: 320, height: 200, clip: w), let open = renderer.render(width: 320, height: 200) else {
            throw XCTSkip("no Metal device")
        }
        guard let backdrop = MGSolidRenderer.composite(Self.clear(320, 200), width: 320, height: 200, background: renderer.lighting.background)
        else { return XCTFail("backdrop") }
        try studioBandsHoldOnlyTheBackdrop(doc, f.still, w, bands)
        let c = Self.rgba(clipped), o = Self.rgba(open), bg = Self.rgba(backdrop)
        let bandRows = Array(0..<Int(200 * bands.title)) + Array(Int(200 * (1 - bands.caption)) + 1..<200)
        var differsOpen = 0
        for y in bandRows { for x in 0..<320 {
            let i = (y * 320 + x) * 4
            XCTAssertEqual(Array(c[i..<i + 3]), Array(bg[i..<i + 3]), "row \(y)")
            if Array(o[i..<i + 3]) != Array(bg[i..<i + 3]) { differsOpen += 1 }
        } }
        XCTAssertGreaterThan(differsOpen, 100, "without the clip, the cut head is drawn in the title band")
    }

    /// The default look (`studio`): the bands of a clipped render hold exactly the look's backdrop (the cut's fade lies
    /// inside the safe window), and without the clip the cut head is drawn there.
    func studioBandsHoldOnlyTheBackdrop(_ doc: MGSolidDocument, _ still: MGAnnotationAnchorView, _ w: MGSolidFraming.Window,
                                        _ bands: (title: Double, caption: Double)) throws {
        let renderer = MGSolidRenderer(document: doc)
        XCTAssertEqual(renderer.look, .studio)
        renderer.show(document: doc, view: still.view)
        renderer.apply(still.params)
        renderer.setCamera(still.camera)
        guard let clipped = renderer.render(width: 320, height: 200, clip: w), let open = renderer.render(width: 320, height: 200) else {
            throw XCTSkip("no Metal device")
        }
        let p = renderer.backdropPool(width: 320, height: 200)
        let bg = renderer.look.backdrop(width: 320, height: 200, pool: MGSolidLook.Pool(x: p.x.rounded(), y: p.y.rounded(), rx: p.rx.rounded(), ry: p.ry.rounded()))
        let c = Self.rgba(clipped), o = Self.rgba(open)
        let bandRows = Array(0..<Int(200 * bands.title)) + Array(Int(200 * (1 - bands.caption)) + 1..<200)
        var differsOpen = 0, differsClipped = 0
        for y in bandRows { for x in 0..<320 {
            let i = (y * 320 + x) * 4
            if Array(c[i..<i + 3]) != Array(bg[i..<i + 3]) { differsClipped += 1 }
            if Array(o[i..<i + 3]) != Array(bg[i..<i + 3]) { differsOpen += 1 }
        } }
        XCTAssertEqual(differsClipped, 0, "studio: the bands hold only the backdrop")
        XCTAssertGreaterThan(differsOpen, 100, "studio: without the clip, the cut head is drawn in the title band")
    }

    static func clear(_ w: Int, _ h: Int) -> CGImage {
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return ctx.makeImage()!
    }

    /// RGBA bytes, rows from the top.
    static func rgba(_ img: CGImage) -> [UInt8] {
        let w = img.width, h = img.height
        var out = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &out, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        return out
    }

    /// Exact repairs (review S2): a 37-character resolved id is printed whole, and a fragment too long for the line is
    /// never cut: the repair names the structured field instead.
    func testRepairsAreExact() {
        let long = "abcdefghijklmnopqrstuvwx.turbineWheel"
        let g = MGSubjectSmall.Group(unit: "abcdefghijklmnopqrstuvwx", parts: [long], pixels: 10, extent: 3, hiddenBy: [], whole: false)
        let other = MGSubjectSmall.Group(unit: "b", parts: ["b"], pixels: 9000, extent: 90, hiddenBy: [], whole: true)
        let one = MGSubjectSmall(step: 0, beat: nil, groups: [g, other], small: [0], cut: [], fill: 0.88, minimumPixels: 3379, minimumExtent: 24)
        XCTAssertTrue(one.repair.contains(#""focus": ["abcdefghijklmnopqrstuvwx.turbineWheel"]"#), one.repair)
        XCTAssertFalse(one.repair.contains("…"))
        // Eight 24-character units: the split fragment is longer than the line, so the repair points at `split`.
        let units = (0..<8).map { "unit\($0)" + String(repeating: "x", count: 19) }
        let many = MGSubjectSmall(step: 3, beat: nil, groups: units.map { .init(unit: $0, parts: [$0 + ".a"], pixels: 5, extent: 2, hiddenBy: [units[0]], whole: true) },
                                  small: Array(0..<8), cut: [], fill: 0.88, minimumPixels: 3379, minimumExtent: 24)
        XCTAssertLessThanOrEqual(many.repair.unicodeScalars.count, MGAnnotationAnchorIssue.repairScalars)
        if many.repair.contains("[") {
            // Any JSON in the line is complete.
            XCTAssertEqual(many.repair.filter { $0 == "[" }.count, many.repair.filter { $0 == "]" }.count, many.repair)
        }
        XCTAssertTrue(many.repair.contains("`split`"), many.repair)
        XCTAssertEqual(many.split, units.map { [$0] })
        XCTAssertEqual(MGExactRepair.json("a\"b\\c"), #""a\"b\\c""#)
        let unit = MGSmallUnit(unit: long, pixels: 10, step: 1, beat: nil, stills: 2, minimum: 512, width: 1280, height: 800)
        XCTAssertTrue(unit.repair.contains(#""focus": ["abcdefghijklmnopqrstuvwx.turbineWheel"]"#), unit.repair)
    }
}
