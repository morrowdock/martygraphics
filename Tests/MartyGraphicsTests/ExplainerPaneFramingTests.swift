// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import MartyGraphics

/// The SwiftUI solid pane (`MGExplainerController`, shown by `MartyGraphicsExplainerView`) frames every beat with the
/// function the beat's still and its `story.mp4` hold frames use (`MGExplainerFrame.solidClearView`): per-step focus
/// framing, the unblocked-focus rule (automatic ghosts, alternate directions) and every camera preset, `backLeft` and
/// `backRight` included (docs/EXPLAINER.md, "The solid pane in SwiftUI").
final class ExplainerPaneFramingTests: XCTestCase {
    /// Shipped explainers with a solid: the examples and the docs fixtures (a figure with engines, a cut engine, a
    /// microTurbojet seen from `back`).
    static let shipped = ["Examples/Explainers/gears-3d.explainer.json", "Examples/Explainers/gears-mixed.explainer.json",
                          "docs/fixtures/anchor-suggest/figure-engines.explainer.json", "docs/fixtures/anchor-suggest/cut-engine.explainer.json",
                          "docs/fixtures/arrow-visibility/arrow-in-casing.explainer.json"]

    static func parse(_ text: String) throws -> MGExplainer { try MGExplainer.parse(data: Data(text.utf8)).get() }
    static func shippedDoc(_ path: String) throws -> MGExplainer {
        try parse(String(contentsOf: XFix.root.appendingPathComponent(path), encoding: .utf8))
    }

    /// The shipped turbofan model (`Examples/Turbofan`) as an explainer: its parts as the solid, one beat per step
    /// with the step's `highlight` and view keys (`camera`, `orbit`, `focus`, `spin`, `explode`).
    static func turbofan() throws -> MGExplainer {
        let url = XFix.root.appendingPathComponent("Examples/Turbofan/Sources/TurbofanKit/Models/turbofan.json")
        guard case .object(let model) = XFix.json(try String(contentsOf: url, encoding: .utf8)),
              let parts = model["parts"], case .array(let steps)? = model["steps"] else { throw MGSolidIssue("fixture") }
        // An explainer's solid is a v2 document; the v1 model's parts and steps are valid v2.
        var solid: [String: MGJSON] = ["v": .number(2), "parts": parts]
        if let units = model["units"] { solid["units"] = units }
        let beats: [MGJSON] = steps.enumerated().map { i, s in
            guard case .object(let o) = s else { return s }
            // The step's text says engine numbers an explainer beat must check; the camera does not read the text.
            var beat: [String: MGJSON] = ["say": .string("Step \(Character(UnicodeScalar(65 + i)!)).")], view: [String: MGJSON] = [:]
            for (k, v) in o {
                if k == "highlight" { beat[k] = v } else if MGExplainer.viewKeys.contains(k) { view[k] = v }
            }
            if !view.isEmpty { beat["view"] = .object(view) }
            return .object(beat)
        }
        let doc: MGJSON = .object(["v": .number(1), "kind": .string("explainer"), "title": .string("Turbofan (pane test)"),
                                   "solid": .object(solid), "beats": .array(beats)])
        return try MGExplainer.parse(json: doc).get()
    }

    /// A tall column with a block beside it and a wall in front of the block, seen from behind (`backLeft`,
    /// `backRight`), with and without a focus.
    static let backTower = """
    {"v": 1, "kind": "explainer", "title": "Tower from behind",
     "solid": {"v": 2, "parts": [
      {"id": "column", "shape": {"shaft": {"radius": 40, "length": 1000}}},
      {"id": "block", "at": [600, 0, 0], "shape": {"box": {"size": [60, 60, 60]}}},
      {"id": "wall", "at": [600, -100, 0], "shape": {"box": {"size": [400, 20, 400]}}}]},
     "beats": [
      {"say": "The whole tower from behind, left.", "view": {"camera": "backLeft"}},
      {"say": "The block alone from behind, right.", "highlight": ["block"], "view": {"focus": ["block"], "camera": "backRight", "orbit": 10}},
      {"say": "The block from behind, left.", "view": {"focus": ["block"], "camera": "backLeft"}},
      {"say": "The block from the front.", "view": {"focus": ["block"], "camera": "front"}}]}
    """

    /// One beat as the SwiftUI pane showed it.
    struct PaneBeat: Equatable {
        var beat: Int
        var camera: MGSolidCamera
        var view: MGSolidView
        var clear: MGSolidClearView
    }

    /// Plays `doc` in a controller beat by beat, as `MGExplainerFrame.beatPanes` plays it for the stills, giving the pane
    /// each beat's still pane size; checks that the pane shows the still's camera and view, and returns what it showed.
    @MainActor func playPane(_ doc: MGExplainer, _ name: String, file: StaticString = #filePath, line: UInt = #line) throws -> [PaneBeat] {
        let stills = MGExplainerFrame.beatPanes(doc)
        if stills.solid == nil {
            var probe = MGExplainerSession(pacing: .speech, clock: MGManualClock())
            if case .failure(let issue) = probe.load(doc) { XCTFail("\(name): load: \(issue)", file: file, line: line) }
        }
        let solid = try XCTUnwrap(stills.solid, "\(name): the explainer has a solid", file: file, line: line)
        XCTAssertFalse(stills.beats.isEmpty, "\(name): beats with a solid pane", file: file, line: line)
        let clock = MGManualClock()
        let c = MGExplainerController(pacing: .speech, clock: clock)
        // The host lays the pane out before the document arrives (as SwiftUI does), so the first beat frames once.
        if let first = stills.beats.first { c.setSolidSize(CGSize(width: first.pane.width, height: first.pane.height)) }
        XCTAssertTrue(c.load(doc), "\(name): loads", file: file, line: line)
        var out: [PaneBeat] = []
        for b in stills.beats {
            XCTAssertEqual(c.session.presented.beat, b.beat, "\(name): beat \(b.beat + 1) presented", file: file, line: line)
            clock.advance(by: c.session.motionRemaining)
            c.setSolidSize(CGSize(width: b.pane.width, height: b.pane.height))
            let d = try XCTUnwrap(c.session.solid, file: file, line: line)
            XCTAssertEqual(d.checkedFingerprint, solid.checkedFingerprint, "\(name): the same compiled solid", file: file, line: line)
            XCTAssertEqual(c.session.solidStep(forBeat: b.beat), b.stepIndex, file: file, line: line)
            XCTAssertEqual(c.session.presented.step, b.view.step, file: file, line: line)
            // The still's camera and view (`marty-solid render`, `beatViews`): one function, the same result.
            let still = MGExplainerFrame.solidClearView(solid, view: b.view, stepIndex: b.stepIndex, pane: b.pane)
            let stillView = (b.view.solid ?? solid.view(step: nil)).ghosting(still.autoGhost)
            let r = try XCTUnwrap(c.renderer, file: file, line: line)
            XCTAssertEqual(r.camera, still.camera, "\(name): beat \(b.beat + 1) camera", file: file, line: line)
            XCTAssertEqual(c.paneClear, still, "\(name): beat \(b.beat + 1) unblocked-focus result", file: file, line: line)
            XCTAssertEqual(c.paneView, stillView, "\(name): beat \(b.beat + 1) view with automatic ghosts", file: file, line: line)
            XCTAssertEqual(r.view, stillView, "\(name): beat \(b.beat + 1) drawn view", file: file, line: line)
            out.append(PaneBeat(beat: b.beat, camera: r.camera, view: r.view, clear: still))
            c.lineEnded(b.beat)
        }
        return out
    }

    /// Every beat of every shipped explainer with a solid (`MGExplainerFrame.solidCamera` is this camera too).
    @MainActor func testShippedExplainersShowTheStillCameraInEveryBeat() throws {
        var beats = 0
        for path in Self.shipped { beats += try playPane(try Self.shippedDoc(path), path).count }
        XCTAssertGreaterThanOrEqual(beats, 10)
    }

    /// The shipped turbofan model: every step as a beat. Its blades hide the compressor and combustor from the authored
    /// views, so beats there show automatic ghosts, in the pane as in the still.
    @MainActor func testTurbofanStepsShowTheStillCameraAndGhosts() throws {
        let doc = try Self.turbofan()
        let shown = try playPane(doc, "turbofan")
        XCTAssertEqual(shown.count, doc.beats.count, "every step is a beat with a solid pane")
        XCTAssertTrue(shown.contains { !$0.clear.autoGhost.isEmpty }, "a turbofan beat ghosts the parts in the way")
        for b in shown where !b.clear.autoGhost.isEmpty {
            for id in b.clear.autoGhost { XCTAssertLessThanOrEqual(b.view.part(id).opacity, MGSolidView.ghostOpacity + 1e-12, "beat \(b.beat + 1): \(id)") }
        }
    }

    @MainActor func testBackPresetsFrameThePaneAsTheStill() throws {
        let shown = try playPane(try Self.parse(Self.backTower), "back tower")
        XCTAssertEqual(shown.count, 4)
        // Whole model from `backLeft` (yaw 135°) and the focus from `backRight` (225° + 10° orbit), in the preset direction.
        XCTAssertEqual(shown[0].clear.direction, .preset)
        XCTAssertEqual(shown[0].camera.yaw, 135, accuracy: 1e-9)
        XCTAssertEqual(shown[1].clear.direction, .preset)
        XCTAssertEqual(shown[1].camera.yaw, 235, accuracy: 1e-9)
        XCTAssertEqual(shown[2].camera.yaw, 135, accuracy: 1e-9)
        // The focus framing differs from the whole-model framing from the same preset.
        XCTAssertNotEqual(shown[0].camera.target, shown[2].camera.target)
        XCTAssertLessThan(shown[2].camera.distance, shown[0].camera.distance)
        // From the front the wall stands between the camera and the block: the pane ghosts it, as the still does.
        XCTAssertEqual(shown[3].clear.autoGhost, ["wall"], "\(shown[3].clear)")
        XCTAssertEqual(shown[3].view.part("wall").opacity, MGSolidView.ghostOpacity, accuracy: 1e-12)
    }

    /// The same document and pane sizes give the same cameras and views, in a fresh controller and after a reload.
    @MainActor func testPaneFramingIsDeterministic() throws {
        for doc in [try Self.parse(Self.backTower), try Self.shippedDoc(Self.shipped[2]), try Self.shippedDoc(Self.shipped[4])] {
            let a = try playPane(doc, doc.title ?? "doc"), b = try playPane(doc, doc.title ?? "doc")
            XCTAssertEqual(a, b)
        }
    }

    /// The framed camera is each beat's start pose: a camera moved away from it (as the learner's orbit moves the
    /// pane's camera) goes back to the framed camera at the next beat and at a new pane aspect; every framing is a new
    /// reset key, and a same-size layout pass is not.
    @MainActor func testEachFramingIsACameraReset() throws {
        let doc = try Self.parse(Self.backTower)
        let clock = MGManualClock()
        let c = MGExplainerController(pacing: .speech, clock: clock)
        XCTAssertTrue(c.load(doc))
        let solid = try XCTUnwrap(c.session.solid)
        c.setSolidSize(CGSize(width: 800, height: 500))
        let r = try XCTUnwrap(c.renderer)
        let key = c.cameraReset
        c.setSolidSize(CGSize(width: 800, height: 500))
        XCTAssertEqual(c.cameraReset, key, "the same size does not reframe")
        func framed(_ beat: Int, _ aspect: Double) -> MGSolidCamera {
            MGExplainerFrame.solidClearView(solid, view: c.session.presented, stepIndex: c.session.solidStep(forBeat: beat), aspect: aspect).camera
        }
        XCTAssertEqual(r.camera, framed(0, 1.6))
        // The learner moves the camera; the next beat starts at its own framed camera again.
        r.setCamera(MGSolidCamera(target: MGVec3(1, 2, 3), yaw: 10, pitch: 5, distance: 9000))
        c.lineEnded(0)
        XCTAssertEqual(c.session.presented.beat, 1)
        XCTAssertGreaterThan(c.cameraReset, key)
        XCTAssertEqual(r.camera, framed(1, 1.6))
        // A new pane aspect reframes the same beat for that aspect.
        let before = c.cameraReset
        r.setCamera(MGSolidCamera(target: .zero, yaw: 300, pitch: -10, distance: 50))
        c.setSolidSize(CGSize(width: 400, height: 600))
        XCTAssertGreaterThan(c.cameraReset, before)
        XCTAssertEqual(r.camera, framed(1, 400.0 / 600))
        // A broken aspect frames as an empty pane does.
        XCTAssertEqual(MGExplainerFrame.solidClearView(solid, view: c.session.presented, stepIndex: 1, aspect: .nan),
                       MGExplainerFrame.solidClearView(solid, view: c.session.presented, stepIndex: 1, pane: MGFrameRect(x: 0, y: 0, width: 0, height: 0)))
    }
}
