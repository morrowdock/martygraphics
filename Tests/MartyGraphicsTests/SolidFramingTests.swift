// SPDX-License-Identifier: Apache-2.0
import Foundation
import SceneKit
import XCTest
@testable import MartyGraphics

/// The render plan's camera framing (`MGSolidFraming`): focus steps, the whole-model rule, the caption band, the loop
/// factor, loop rates, hostile numbers and the renderer entry point. Foundation math except the last two tests.
final class SolidFramingTests: XCTestCase {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    func model(_ name: String) throws -> (MGSolidDocument, Data) {
        let data = try Data(contentsOf: Self.root.appendingPathComponent("Examples/Solid3D/Sources/MartySolid3D/Models/\(name).json"))
        return (try MGSolidParser.document(data: data).get(), data)
    }
    func compile(_ text: String) throws -> MGSolidDocument { try MGSolidParser.document(data: Data(text.utf8)).get() }

    /// A tall column (1 m) with a small separate block beside it, and steps that highlight, focus and cut.
    static let tower = """
    {"v": 2, "kind": "assembly", "title": "Tower", "parts": [
     {"id": "column", "shape": {"shaft": {"radius": 40, "length": 1000}}},
     {"id": "cap", "shape": {"box": {"size": [120, 120, 20], "at": [0, 0, 1010]}}},
     {"id": "block", "at": [600, 0, 0], "shape": {"box": {"size": [60, 60, 60], "at": [0, 0, 30]}}},
     {"id": "pin", "at": [600, 0, 60], "shape": {"shaft": {"radius": 5, "length": 30}}}],
     "steps": [
      {"say": "The block.", "highlight": ["block"], "camera": "front"},
      {"say": "The block alone.", "highlight": ["block"], "focus": ["block"], "camera": "side", "orbit": 20},
      {"say": "The whole tower.", "camera": "front"},
      {"say": "The column and its cap.", "highlight": ["column"]}]}
    """

    /// Points of the parts at a still's pose (render world).
    func points(_ doc: MGSolidDocument, _ ids: [String]?, _ s: MGSolidShot) -> [MGVec3] {
        MGSolidFraming.Samples(doc.assembly, ids: ids).world(doc.assembly, s.params, stage: MGSolidStage.zUpToYUp)
    }

    func testFocusStepFramesItsPartsFromThePresetDirection() throws {
        let doc = try compile(Self.tower)
        let plan = MGSolidRenderPlan(doc, sourceName: "t.json", source: MGSolidSource(data: Data(Self.tower.utf8)))
        let cams = plan.cameras(doc, width: 1280, height: 800)
        // hero and step 3 cut the tall column with the earlier framing. The exploded still (margin 0.92) kept it, but
        // its earlier framing reaches into the title band, which no still may do now ("Shown parts stay whole").
        XCTAssertEqual(cams.rules, [.modelFitted, .modelFitted, .focus, .focus, .modelFitted, .modelFitted])
        // Step 1: the block and the pin that touches it, inside the safe window, from the front preset.
        let s1 = plan.stills[2], c1 = cams.stills[2]
        XCTAssertEqual(MGSolidFraming.focusParts(doc, step: 0, params: s1.params), ["block", "pin"])
        XCTAssertEqual(c1.yaw, MGSolidCamera.presets["front"]!.yaw)
        XCTAssertEqual(c1.pitch, MGSolidCamera.presets["front"]!.pitch)
        let bands = MGSolidRenderPlan.bands(width: 1280, height: 800)
        let safe = MGSolidFraming.Window(titleBand: bands.title, captionBand: bands.caption)
        XCTAssertTrue(MGSolidFraming.contains(points(doc, ["block", "pin"], s1), camera: c1, aspect: 1.6, window: safe))
        // Much closer than the whole tower, and filling the safe window to `fill` (not more).
        XCTAssertLessThan(c1.distance, cams.stills[0].distance / 3)
        XCTAssertFalse(MGSolidFraming.contains(points(doc, ["block", "pin"], s1), camera: c1, aspect: 1.6, window: safe.scaled(0.8)))
        // Step 2: `focus` is used as written (no touching parts), with the preset yaw plus the orbit.
        XCTAssertEqual(MGSolidFraming.focusParts(doc, step: 1, params: plan.stills[3].params), ["block"])
        XCTAssertEqual(cams.stills[3].yaw, MGSolidCamera.presets["side"]!.yaw + 20)
        // Step 4: the column touches its cap, and both span the model: the whole-model rule.
        XCTAssertEqual(MGSolidFraming.focusParts(doc, step: 3, params: plan.stills[5].params), ["column", "cap"])
    }

    func testTallModelIsFittedAboveTheCaptionBand() throws {
        let doc = try compile(Self.tower)
        let plan = MGSolidRenderPlan(doc, sourceName: "t.json", source: MGSolidSource(data: Data(Self.tower.utf8)))
        let cams = plan.cameras(doc, width: 1280, height: 800)
        let bands = MGSolidRenderPlan.bands(width: 1280, height: 800)
        let s = plan.stills[4], all = points(doc, nil, s)
        // The earlier bounding-sphere framing cut the tower or put it under the caption band; the fit does neither.
        let p = MGSolidCamera.presets["front"]!
        let old = MGSolidFraming.legacy(doc.assembly, s, yaw: p.yaw, pitch: p.pitch, aspect: 1.6, fieldOfView: 30, stage: MGSolidStage.zUpToYUp)
        let captionOnly = MGSolidFraming.Window(titleBand: 0, captionBand: bands.caption)
        XCTAssertFalse(MGSolidFraming.contains(all, camera: old, aspect: 1.6, window: captionOnly))
        XCTAssertTrue(MGSolidFraming.contains(all, camera: cams.stills[4], aspect: 1.6,
                                              window: MGSolidFraming.Window(titleBand: bands.title, captionBand: bands.caption)))
        // The loop moves back by one factor for every frame, and then every frame holds the whole model.
        XCTAssertGreaterThan(cams.loopScale, 1)
        for (k, shot) in plan.loop.enumerated() where k % 7 == 0 {
            let q = MGSolidCamera.presets["hero"]!
            let o = MGSolidFraming.legacy(doc.assembly, shot, yaw: q.yaw + shot.orbit, pitch: q.pitch, aspect: 1.6, fieldOfView: 30,
                                          stage: MGSolidStage.zUpToYUp)
            XCTAssertEqual(cams.loop[k].distance, o.distance * cams.loopScale, accuracy: 1e-9 * o.distance)
            XCTAssertEqual(cams.loop[k].target, o.target)
            XCTAssertTrue(MGSolidFraming.contains(points(doc, nil, shot), camera: cams.loop[k], aspect: 1.6,
                                                  window: MGSolidFraming.Window(titleBand: 0, captionBand: 0)), "loop frame \(k)")
        }
    }

    /// A model the earlier framing showed whole keeps it exactly: the propeller's stills and loop are unchanged.
    func testUncutModelKeepsTheEarlierFraming() throws {
        let (doc, data) = try model("propeller")
        let plan = MGSolidRenderPlan(doc, sourceName: "propeller.json", source: MGSolidSource(data: data))
        let cams = plan.cameras(doc, width: 1280, height: 800)
        XCTAssertEqual(cams.loopScale, 1)
        for (k, s) in plan.stills.enumerated() {
            let p = MGSolidCamera.presets[s.preset]!
            XCTAssertEqual(cams.stills[k], MGSolidFraming.legacy(doc.assembly, s, yaw: p.yaw + s.orbit, pitch: p.pitch, aspect: 1.6,
                                                                 fieldOfView: 30, stage: MGSolidStage.zUpToYUp), s.file)
            XCTAssertEqual(cams.rules[k], .model, s.file)
        }
    }

    /// A gear inside a housing brings its neighbours: the planetary steps keep the whole mechanism in view.
    func testHighlightedInnerPartKeepsItsMechanism() throws {
        let (doc, data) = try model("planetary")
        let plan = MGSolidRenderPlan(doc, sourceName: "planetary.json", source: MGSolidSource(data: data))
        let cams = plan.cameras(doc, width: 1280, height: 800)
        let sun = try XCTUnwrap(doc.steps.firstIndex { $0.highlight == ["sun"] })
        XCTAssertNotEqual(cams.rules[sun + 2], .focus)
        let focus = MGSolidFraming.focusParts(doc, step: sun, params: plan.stills[sun + 2].params)
        XCTAssertTrue(focus.contains("sun") && focus.contains("planet1") && focus.count >= 4, "\(focus)")
    }

    func testFramingIsDeterministic() throws {
        let doc = try compile(Self.tower), doc2 = try compile(Self.tower)
        let plan = MGSolidRenderPlan(doc, sourceName: "t.json", source: MGSolidSource(data: Data(Self.tower.utf8)))
        let a = plan.cameras(doc, width: 1280, height: 800)
        for _ in 0..<3 { XCTAssertEqual(plan.cameras(doc2, width: 1280, height: 800), a) }
        // Other sizes keep the rule and reserve their own drawn bands.
        let square = plan.cameras(doc, width: 1200, height: 1200)
        XCTAssertEqual(square.rules, a.rules)
        XCTAssertEqual(MGSolidRenderPlan.bands(width: 1280, height: 800).caption, MGAnnotationLayout.captionBand)
        XCTAssertEqual(MGSolidRenderPlan.bands(width: 3840, height: 1000).caption, 0.36, accuracy: 1e-12)
        XCTAssertEqual(MGSolidRenderPlan.bands(width: 3840, height: 1000).title, 0.3, accuracy: 1e-12)
    }

    func testHostileNumbersGiveAFiniteCamera() throws {
        let doc = try compile(Self.tower)
        let shot = try XCTUnwrap(MGSolidShot.step(doc, 0))
        XCTAssertNil(MGSolidShot.step(doc, -1)); XCTAssertNil(MGSolidShot.step(doc, 99))
        XCTAssertEqual(MGSolidFraming.focusParts(doc, step: 99, params: MGPoseParameters()), [])
        for aspect in [Double.nan, .infinity, -1, 0, 1e-300] {
            for band in [Double.nan, -5, 0.9, .infinity] {
                let c = MGSolidFraming.camera(doc, shot: shot, aspect: aspect, titleBand: band, captionBand: band)
                XCTAssertTrue(c.distance.isFinite && c.distance > 0 && c.target.allSatisfy(\.isFinite), "\(aspect) \(band)")
            }
        }
        // Windows, fields of view, fills and poses built in code with unusable numbers still give a finite camera.
        let bad = MGSolidFraming.Window(left: 0, right: 0, bottom: .nan, top: 2)
        let pts = [MGVec3(1, 2, 3), MGVec3(40, 50, 60)]
        for fov in [Double.nan, 0, 180, -30] {
            let c = MGSolidFraming.fit(pts, yaw: .nan, pitch: 400, aspect: 1.6, fieldOfView: fov, window: bad, fill: .nan)
            XCTAssertTrue(c.distance.isFinite && c.distance > 0 && c.target.allSatisfy(\.isFinite), "\(fov)")
            XCTAssertTrue(MGSolidFraming.camera(doc, shot: shot, aspect: 1.6, fieldOfView: fov).distance.isFinite)
        }
        var nanShot = shot
        nanShot.params = MGPoseParameters(input: .nan, explode: .infinity)
        nanShot.orbit = .nan
        let n = MGSolidFraming.camera(doc, shot: nanShot, aspect: 1.6)
        XCTAssertTrue(n.distance.isFinite && n.distance > 0 && n.target.allSatisfy(\.isFinite))
        XCTAssertFalse(MGSolidFraming.contains(pts, camera: MGSolidCamera(target: .zero, yaw: 0, pitch: 0, distance: .nan), aspect: 1.6, window: bad))
        let w = MGSolidFraming.Window(titleBand: .nan, captionBand: 7)
        XCTAssertEqual(w.top, 1); XCTAssertEqual(w.bottom, -0.1, accuracy: 1e-12)
        for pts in [[], [MGVec3(.nan, 0, 0)], [MGVec3(1, 2, 3)], [MGVec3(1, 2, 3), MGVec3(1, 2, 3)]] {
            let c = MGSolidFraming.fit(pts, yaw: 30, pitch: 20, aspect: 1.6, window: w)
            XCTAssertTrue(c.distance.isFinite && c.distance > 0 && c.target.allSatisfy(\.isFinite), "\(pts)")
        }
    }

    func testLoopRates() throws {
        let (doc, data) = try model("propeller")
        let ten = MGSolidRenderPlan(doc, sourceName: "p", source: MGSolidSource(data: data))
        let thirty = MGSolidRenderPlan(doc, sourceName: "p", source: MGSolidSource(data: data), loopRate: 30)
        XCTAssertEqual(ten.loopRate, 10); XCTAssertEqual(ten.loop.count, MGSolidRenderPlan.loopFrames)
        XCTAssertEqual(ten.gifFrameIndices, Array(0..<120))
        XCTAssertEqual(thirty.loop.count, 360)
        XCTAssertEqual(thirty.gifFrameIndices.count, 120)
        // Every GIF frame of the 30 fps plan is the pose of the 10 fps plan: no in-between is shown in the GIF.
        for (k, i) in thirty.gifFrameIndices.enumerated() {
            XCTAssertEqual(thirty.loop[i].params.input, ten.loop[k].params.input, accuracy: 1e-12)
            XCTAssertEqual(thirty.loop[i].params.explode, ten.loop[k].params.explode, accuracy: 1e-12)
            XCTAssertEqual(thirty.loop[i].orbit, ten.loop[k].orbit, accuracy: 1e-9)
        }
        XCTAssertEqual(MGSolidRenderPlan(doc, sourceName: "p", source: MGSolidSource(data: data), loopRate: 25).loopRate, 10)
        XCTAssertEqual(MGSolidRenderPlan(doc, sourceName: "p", source: MGSolidSource(data: data), loop: false, loopRate: 30).loop, [])
    }

    /// An explicit `focus` is framed exactly even when it spans most of the model: the column is framed on its own,
    /// not with the block 600 mm beside it.
    func testExplicitFocusIsAlwaysFramedExactly() throws {
        let text = Self.tower.replacingOccurrences(of: #"{"say": "The whole tower.", "camera": "front"}"#,
                                                  with: #"{"say": "The column.", "camera": "front", "focus": ["column"]}"#)
        let doc = try compile(text)
        let shot = try XCTUnwrap(MGSolidShot.step(doc, 2))
        let f = MGSolidFraming.framing(doc, shot: shot, aspect: 1.6)
        XCTAssertEqual(f.rule, .focus)
        XCTAssertEqual(f.camera.target[0], 0, accuracy: 1)           // centred on the column (x = 0), not toward the block
        let bands = MGSolidRenderPlan.bands(width: 1280, height: 800)
        XCTAssertTrue(MGSolidFraming.contains(points(doc, ["column"], shot), camera: f.camera, aspect: 1.6,
                                              window: MGSolidFraming.Window(titleBand: bands.title, captionBand: bands.caption)))
        // Exactly the fit of the column alone (before the fix, the whole model was fitted and the target moved ~291 mm).
        let p = MGSolidCamera.presets["front"]!
        XCTAssertEqual(f.camera, MGSolidFraming.fit(points(doc, ["column"], shot), yaw: p.yaw, pitch: p.pitch, aspect: 1.6,
                                                    window: MGSolidFraming.Window(titleBand: bands.title, captionBand: bands.caption)))
    }

    /// A focus far smaller than the renderer's 0.5 mm minimum near plane stays in front of it, and in the window.
    func testSubMillimetreFocusIsNotCutByTheNearPlane() throws {
        let text = #"{"v": 2, "kind": "assembly", "title": "Tiny", "parts": [{"id": "base", "shape": {"box": {"size": [200, 200, 10]}}}, {"id": "dot", "at": [50, 0, 5], "shape": {"box": {"size": [0.1, 0.1, 0.1], "at": [0, 0, 0.05]}}}], "steps": [{"say": "A tiny part.", "focus": ["dot"], "camera": "front"}]}"#
        let doc = try compile(text)
        let shot = try XCTUnwrap(MGSolidShot.step(doc, 0))
        let c = MGSolidFraming.camera(doc, shot: shot, aspect: 1.6)
        let pts = points(doc, ["dot"], shot)
        let b = MGSolidFraming.Basis(yaw: c.yaw, pitch: c.pitch)
        let near = MGSolidFraming.nearPlane(distance: c.distance)
        XCTAssertEqual(near, MGSolidFraming.nearMinimum)
        for p in pts { XCTAssertGreaterThanOrEqual(c.distance + (p - c.targetVector).dot(b.fwd), 1.1 * near - 1e-9) }
        XCTAssertTrue(MGSolidFraming.contains(pts, camera: c, aspect: 1.6, window: MGSolidFraming.Window(titleBand: 0.14, captionBand: 0.2)))
        // The renderer uses the same near plane.
        let r = MGSolidRenderer(document: doc)
        r.apply(shot.params)
        r.frame(shot, document: doc, aspect: 1.6)
        XCTAssertEqual(Double(try XCTUnwrap(r.cameraNode.camera?.zNear)), near, accuracy: 1e-6)
    }

    // MARK: Renderer

    func testRendererFramesAShotAndReachesTheWholeModel() throws {
        let doc = try compile(Self.tower)
        let r = MGSolidRenderer(document: doc)
        let shot = try XCTUnwrap(MGSolidShot.step(doc, 1))
        r.apply(shot.params)
        r.frame(shot, document: doc, aspect: 1.6)
        XCTAssertEqual(r.camera, MGSolidFraming.camera(doc, shot: shot, aspect: 1.6))
        // The close focus keeps the far column in front of the far plane.
        let far = try XCTUnwrap(r.cameraNode.camera?.zFar)
        let b = r.worldBounds(shot.params)
        XCTAssertGreaterThanOrEqual(Double(far), b.corners.map { ($0 - r.camera.position).length }.max()!)
    }
}
