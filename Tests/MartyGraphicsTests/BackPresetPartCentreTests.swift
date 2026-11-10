// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import MartyGraphics

/// The three-quarter back camera presets (`backLeft`, `backRight`) and the part-centre anchor `{"part": id}`
/// (docs/SOLID-3D.md, "Camera presets" and "Anchors"). Synthetic boxes only.
final class BackPresetPartCentreTests: XCTestCase {
    func compile(_ text: String) throws -> MGSolidDocument { try MGSolidParser.document(data: Data(text.utf8)).get() }
    func reason(_ text: String, profile: MGSolidProfile = .standard) -> String? {
        if case .failure(let e) = MGSolidParser.document(data: Data(text.utf8), profile: profile) { return e.reason }
        return nil
    }
    func strict(_ text: String) -> MGSolidReport { MGSolidReport.check(data: Data(text.utf8), profile: .strict, engine: nil) }

    /// A tall column with a small block beside it (as in SolidFramingTests), with steps from behind.
    static let tower = """
    {"v": 2, "kind": "assembly", "title": "Tower from behind", "parts": [
     {"id": "column", "shape": {"shaft": {"radius": 40, "length": 1000}}},
     {"id": "cap", "shape": {"box": {"size": [120, 120, 20], "at": [0, 0, 1010]}}},
     {"id": "block", "at": [600, 0, 0], "shape": {"box": {"size": [60, 60, 60], "at": [0, 0, 30]}}},
     {"id": "pin", "at": [600, 0, 60], "shape": {"shaft": {"radius": 5, "length": 30}}}],
     "steps": [
      {"say": "The block from behind, left.", "highlight": ["block"], "camera": "backLeft"},
      {"say": "The block alone from behind, right.", "focus": ["block"], "camera": "backRight", "orbit": 10},
      {"say": "The whole tower from behind, left.", "camera": "backLeft"},
      {"say": "The whole tower from behind, right.", "camera": "backRight"}]}
    """

    func points(_ doc: MGSolidDocument, _ ids: [String]?, _ s: MGSolidShot) -> [MGVec3] {
        MGSolidFraming.Samples(doc.assembly, ids: ids).world(doc.assembly, s.params, stage: MGSolidStage.zUpToYUp)
    }

    // MARK: Presets

    func testBackPresetsAreMirroredThreeQuarterViewsFromBehind() throws {
        let hero = try XCTUnwrap(MGSolidCamera.presets["hero"])
        let left = try XCTUnwrap(MGSolidCamera.presets["backLeft"]), right = try XCTUnwrap(MGSolidCamera.presets["backRight"])
        XCTAssertEqual(left.yaw, 135)
        XCTAssertEqual(right.yaw, 225)   // −135° from `front`
        XCTAssertEqual(left.pitch, hero.pitch)
        XCTAssertEqual(right.pitch, hero.pitch)
        // The names list is every preset once, in a fixed order, the old names first and unchanged.
        XCTAssertEqual(MGSolidCamera.presetNames, ["hero", "front", "side", "top", "low", "back", "iso", "backLeft", "backRight"])
        XCTAssertEqual(Set(MGSolidCamera.presetNames), Set(MGSolidCamera.presets.keys))
        XCTAssertEqual(MGSolidCamera.presets.count, MGSolidCamera.presetNames.count)
        XCTAssertEqual(MGSolidCamera.presets["back"]?.yaw, 200)
        XCTAssertEqual(MGSolidCamera.presets["hero"]?.yaw, 32)
        // Both look from behind (kernel +Y), mirrored across the X = 0 plane; backLeft is on +X, the hero side.
        func eye(_ p: (yaw: Double, pitch: Double)) -> MGVec3 {
            MGSolidStage.zUpToYUp.inverse.apply(MGSolidCamera(target: .zero, yaw: p.yaw, pitch: p.pitch, distance: 1000).position)
        }
        let l = eye(left), r = eye(right), h = eye(hero)
        XCTAssertGreaterThan(l.y, 0)
        XCTAssertGreaterThan(r.y, 0)
        XCTAssertLessThan(h.y, 0)
        XCTAssertGreaterThan(l.x, 0)
        XCTAssertLessThan(r.x, 0)
        XCTAssertEqual(l.x, -r.x, accuracy: 1e-9)
        XCTAssertEqual(l.y, r.y, accuracy: 1e-9)
        XCTAssertEqual(l.z, r.z, accuracy: 1e-9)
        XCTAssertEqual(l.z, h.z, accuracy: 1e-9)
        // 135° from the front: the horizontal direction is at 45° to both the X and Y axes.
        XCTAssertEqual(abs(l.x), abs(l.y), accuracy: 1e-9)
    }

    func testStepAndViewCameraAcceptTheNewNamesAndNoAliases() throws {
        func step(_ camera: String) -> String {
            #"{"v": 1, "kind": "assembly", "parts": [{"id": "a", "shape": {"box": {"size": [10, 10, 10]}}}], "steps": [{"say": "A.", "camera": "\#(camera)"}]}"#
        }
        for name in MGSolidCamera.presetNames { XCTAssertNil(reason(step(name)), name) }
        for alias in ["three-quarter-back", "threeQuarterBack", "back-left", "backleft", "BackLeft", "back_right", "rearLeft", " backLeft", "backLeft "] {
            XCTAssertEqual(reason(step(alias)), "step.camera", alias)
        }
        // The refusal meaning (and so the report's repair line) lists every valid name.
        for p in ["step.camera", "view.camera"] {
            let meaning = try XCTUnwrap(MGSolidReasons.lookup(p)?.meaning)
            for name in MGSolidCamera.presetNames { XCTAssertTrue(meaning.contains("`\(name)`"), "\(p): \(name)") }
            XCTAssertTrue(meaning.hasSuffix("`backLeft` or `backRight`)."), meaning)
        }
        let r = strict(step("three-quarter-back"))
        XCTAssertEqual(r.reason, "step.camera")
        guard case .string(let repair)? = r.json["repair"] else { return XCTFail("repair") }
        for name in MGSolidCamera.presetNames { XCTAssertTrue(repair.contains(name), repair) }
    }

    func testABeatViewTakesTheBackPresets() throws {
        func beat(_ camera: String) -> (MGExplainerSession, [MGExplainerEvent]) {
            XFix.stream([XFix.header(), #"{"solid":\#(XFix.wheelGears)}"#, #"{"say":"One."}"#,
                         #"{"view":{"camera":"\#(camera)"}}"#])
        }
        for name in ["backLeft", "backRight"] {
            let (s, ev) = beat(name)
            XCTAssertEqual(XFix.reasons(ev), [], name)
            XCTAssertEqual(s.presented.step?.camera ?? nil, name)
        }
        XCTAssertEqual(XFix.reasons(beat("three-quarter-back").1), ["view.camera"])
    }

    func testBackPresetStepsFrameTheirFocusAndKeepTheBandsFree() throws {
        let doc = try compile(Self.tower)
        let plan = MGSolidRenderPlan(doc, sourceName: "t.json", source: MGSolidSource(data: Data(Self.tower.utf8)))
        let cams = plan.cameras(doc, width: 1280, height: 800)
        XCTAssertEqual(plan.stills.map(\.preset).suffix(4), ["backLeft", "backRight", "backLeft", "backRight"])
        // Stills: hero, exploded, then the four steps. Steps 1–2 are framed on their focus.
        XCTAssertEqual(Array(cams.rules[2...3]), [.focus, .focus])
        let bands = MGSolidRenderPlan.bands(width: 1280, height: 800)
        let safe = MGSolidFraming.Window(titleBand: bands.title, captionBand: bands.caption)
        let s1 = plan.stills[2], c1 = cams.stills[2]
        XCTAssertEqual(MGSolidFraming.focusParts(doc, step: 0, params: s1.params), ["block", "pin"])
        // Subject first: the highlighted block alone is framed; the touching pin is context.
        XCTAssertEqual(MGSolidFraming.subjectParts(doc, shot: s1).parts, ["block"])
        XCTAssertEqual(c1.yaw, 135)
        XCTAssertEqual(c1.pitch, 28)
        XCTAssertTrue(MGSolidFraming.contains(points(doc, ["block"], s1), camera: c1, aspect: 1.6, window: safe))
        XCTAssertFalse(MGSolidFraming.contains(points(doc, ["block"], s1), camera: c1, aspect: 1.6, window: safe.scaled(0.8)))
        XCTAssertLessThan(c1.distance, cams.stills[0].distance / 3)
        // Step 2: the `focus` list as written, the preset yaw plus the orbit.
        XCTAssertEqual(MGSolidFraming.focusParts(doc, step: 1, params: plan.stills[3].params), ["block"])
        XCTAssertEqual(cams.stills[3].yaw, 235)
        XCTAssertTrue(MGSolidFraming.contains(points(doc, ["block"], plan.stills[3]), camera: cams.stills[3], aspect: 1.6, window: safe))
        // Steps 3–4: the whole tall tower, fitted inside the safe window (title band and caption band free).
        for k in [4, 5] {
            XCTAssertNotEqual(cams.rules[k], .focus)
            XCTAssertTrue(MGSolidFraming.contains(points(doc, nil, plan.stills[k]), camera: cams.stills[k], aspect: 1.6, window: safe), "still \(k)")
        }
        XCTAssertEqual(cams.stills[4].yaw, 135)
        XCTAssertEqual(cams.stills[5].yaw, 225)
        // The two whole-model views are mirrored: the same distance (the model is not symmetric in X, so only close).
        XCTAssertEqual(cams.stills[4].pitch, cams.stills[5].pitch)
    }

    /// A 60 mm block with a wall behind it (kernel +Y), the side the back presets look from.
    func blocked(_ wallY: Double, camera: String) -> String {
        """
        {"v": 2, "kind": "assembly", "title": "Blocked from behind", "parts": [
         {"id": "target", "shape": {"box": {"size": [60, 60, 60]}}},
         {"id": "wall", "at": [0, \(wallY), 0], "shape": {"box": {"size": [400, 20, 400]}}}],
         "steps": [{"say": "The block.", "focus": ["target"], "camera": "\(camera)"}]}
        """
    }

    func testBackPresetsUseTheUnblockedFocusRule() throws {
        for (camera, yaw) in [("backLeft", 135.0), ("backRight", 225.0)] {
            // A wall between the camera and the focus, not touching it: an automatic ghost, the preset stays.
            let free = try compile(blocked(100, camera: camera))
            let c = MGSolidFraming.clearView(free, shot: try XCTUnwrap(MGSolidShot.step(free, 0)), aspect: 1.6)
            XCTAssertTrue(c.tested, camera)
            XCTAssertEqual(c.direction, .preset, camera)
            XCTAssertEqual(c.autoGhost, ["wall"], camera)
            XCTAssertEqual(c.camera.yaw, yaw, camera)
            XCTAssertTrue(c.clear, camera)
            // The same wall on the front side is not in the way of a back view.
            let front = try compile(blocked(-100, camera: camera))
            let f = MGSolidFraming.clearView(front, shot: try XCTUnwrap(MGSolidShot.step(front, 0)), aspect: 1.6)
            XCTAssertEqual(f.autoGhost, [], camera)
            XCTAssertEqual(f.direction, .preset, camera)
            // A wall that touches the focus is its context: the camera turns to the first clear other direction.
            let context = try compile(blocked(40, camera: camera))
            let t = MGSolidFraming.clearView(context, shot: try XCTUnwrap(MGSolidShot.step(context, 0)), aspect: 1.6)
            XCTAssertEqual(t.autoGhost, [], camera)
            XCTAssertNotEqual(t.direction, .preset, camera)
            XCTAssertTrue(t.clear, camera)
        }
    }

    func testBackPresetsRenderWithTheFramedCamera() throws {
        let doc = try compile(Self.tower)
        for k in 0..<doc.steps.count {
            let shot = try XCTUnwrap(MGSolidShot.step(doc, k))
            let r = MGSolidRenderer(document: doc)
            r.apply(shot.params)
            r.frame(shot, document: doc, aspect: 1.6)
            XCTAssertEqual(r.camera, MGSolidFraming.camera(doc, shot: shot, aspect: 1.6), "step \(k + 1)")
            let far = try XCTUnwrap(r.cameraNode.camera?.zFar)
            XCTAssertGreaterThanOrEqual(Double(far), r.worldBounds(shot.params).corners.map { ($0 - r.camera.position).length }.max()!)
            // An image needs a Metal device; the camera checks above run without one.
            guard let image = r.render(width: 160, height: 100) else { continue }
            XCTAssertEqual(image.width, 160)
            XCTAssertEqual(image.height, 100)
        }
    }

    func testBackPresetFramingIsDeterministic() throws {
        let a = try compile(Self.tower), b = try compile(Self.tower)
        let plan = MGSolidRenderPlan(a, sourceName: "t.json", source: MGSolidSource(data: Data(Self.tower.utf8)))
        let first = plan.cameras(a, width: 1280, height: 800)
        for _ in 0..<3 { XCTAssertEqual(plan.cameras(b, width: 1280, height: 800), first) }
        let r1 = strict(Self.tower), r2 = strict(Self.tower)
        XCTAssertEqual(r1.text, r2.text)
        XCTAssertTrue(r1.ok, r1.reason ?? "")
    }

    // MARK: Part-centre anchors

    static let boxes = #"{"id": "shell", "shape": {"box": {"size": [200, 200, 200]}}}, {"id": "core", "shape": {"box": {"size": [40, 40, 40]}}}, {"id": "side", "at": [400, 0, 0], "shape": {"box": {"size": [40, 40, 40], "at": [0, 0, 20]}}}"#
    func boxes(_ annotations: String, steps: String = #"[{"say": "Boxes."}]"#) -> String {
        #"{"v": 2, "kind": "assembly", "parts": [\#(Self.boxes)], "annotations": \#(annotations), "steps": \#(steps)}"#
    }

    func testAPartOnlyAnchorIsThePartsCentre() throws {
        let short = try compile(boxes(#"{"labels": [{"id": "l1", "at": {"part": "side"}, "text": "Side"}], "arrows": [{"id": "p1", "meaning": "pointer", "from": {"world": [600, -300, 300]}, "to": {"part": "side"}, "text": "Here"}], "dimensions": [{"id": "d1", "a": {"part": "side"}, "b": {"world": [0, 0, 0]}}]}"#))
        let long = try compile(boxes(#"{"labels": [{"id": "l1", "at": {"part": "side", "point": "centre"}, "text": "Side"}], "arrows": [{"id": "p1", "meaning": "pointer", "from": {"world": [600, -300, 300]}, "to": {"part": "side", "point": "centre"}, "text": "Here"}], "dimensions": [{"id": "d1", "a": {"part": "side", "point": "centre"}, "b": {"world": [0, 0, 0]}}]}"#))
        let l = try XCTUnwrap(short.annotations.label("l1"))
        XCTAssertEqual(l.at.anchor, .centre(part: "side"))
        XCTAssertEqual(short.annotations, long.annotations)
        // The centre of the mesh bounds, not the frame origin the bare id gives.
        let pose = short.assembly.pose(MGPoseParameters(input: short.defaults.input, explode: 0))
        let p = l.at.world(pose)
        XCTAssertEqual(p.x, 400, accuracy: 1e-9)
        XCTAssertEqual(p.z, 20, accuracy: 1e-9)
        let bare = try compile(boxes(#"{"labels": [{"id": "l1", "at": "side", "text": "Side"}]}"#))
        XCTAssertEqual(try XCTUnwrap(bare.annotations.label("l1")).at.world(pose).z, 0, accuracy: 1e-9)
        // Other part forms are still refused as before.
        XCTAssertEqual(reason(boxes(#"{"labels": [{"id": "l1", "at": {"part": 5}, "text": "P"}]}"#)), "anchor.form")
        XCTAssertEqual(reason(boxes(#"{"labels": [{"id": "l1", "at": {"part": "side", "point": "centre", "offset": [0, 0, 1]}, "text": "P"}]}"#)), "anchor.form")
        XCTAssertEqual(reason(boxes(#"{"labels": [{"id": "l1", "at": {"part": "side", "world": [0, 0, 1]}, "text": "P"}]}"#)), "anchor.form")
        XCTAssertEqual(reason(boxes(#"{"labels": [{"id": "l1", "at": {}, "text": "P"}]}"#)), "anchor.form")
        XCTAssertEqual(reason(boxes(#"{"labels": [{"id": "l1", "at": {"part": "nope"}, "text": "P"}]}"#)), "anchor.ref.nope")
        // A part-only anchor is checked against the final names: a hidden part is refused like the centre form.
        let hidden = #"[{"say": "No side.", "hide": ["side"]}]"#
        XCTAssertEqual(reason(boxes(#"{"labels": [{"id": "l1", "at": {"part": "side"}, "text": "Side"}]}"#, steps: hidden)),
                       reason(boxes(#"{"labels": [{"id": "l1", "at": {"part": "side", "point": "centre"}, "text": "Side"}]}"#, steps: hidden)))
    }

    func testAHiddenPartOnlyCentreIsRefusedInStrictModeWithTheSameReportAsTheCentreForm() throws {
        // The core's centre is inside the closed shell: hidden, no suggestion (as for `{"point": "centre"}`).
        let short = strict(boxes(#"{"labels": [{"id": "l1", "at": {"part": "core"}, "text": "Core"}]}"#))
        let long = strict(boxes(#"{"labels": [{"id": "l1", "at": {"part": "core", "point": "centre"}, "text": "Core"}]}"#))
        XCTAssertEqual(short.reason, "annotation.anchor.hidden.l1")
        XCTAssertEqual(short.reason, long.reason)
        XCTAssertEqual(short.json["anchor"], long.json["anchor"])
        XCTAssertEqual(short.json["anchorIssues"], long.json["anchorIssues"])
        XCTAssertEqual(short.json["repair"], long.json["repair"])
    }

    /// A small block between the camera and the side box's centre: the centre is hidden, the box's faces are not.
    func testAPartlyHiddenPartOnlyCentreGetsASuggestionThatPasses() throws {
        let blocker = #", {"id": "blocker", "at": [428, -45, 48], "shape": {"box": {"size": [24, 24, 24]}}}"#
        func doc(_ at: String) -> String {
            #"{"v": 2, "kind": "assembly", "parts": [\#(Self.boxes)\#(blocker)], "annotations": {"labels": [{"id": "l1", "at": \#(at), "text": "Side"}]}, "steps": [{"say": "Boxes."}]}"#
        }
        let t = doc(#"{"part": "side"}"#)
        let short = strict(t), long = strict(doc(#"{"part": "side", "point": "centre"}"#))
        XCTAssertFalse(short.ok)
        XCTAssertEqual(short.reason, "annotation.anchor.hidden.l1")
        XCTAssertEqual(short.json["anchorIssues"], long.json["anchorIssues"])
        guard case .object(let a)? = short.json["anchor"] else { return XCTFail("anchor") }
        XCTAssertEqual(a["by"], .string("blocker"))
        guard case .object(let s)? = a["suggest"] else { return XCTFail("no suggest: \(short.text)") }
        XCTAssertEqual(s["part"], .string("side"))
        let fixed = SolidAnchorSuggestTests.applying(["l1": .object(s)], to: t)
        let after = strict(fixed)
        XCTAssertTrue(after.ok, after.reason ?? "")
        // Deterministic: the same report text every time.
        XCTAssertEqual(strict(t).text, short.text)
    }
}
