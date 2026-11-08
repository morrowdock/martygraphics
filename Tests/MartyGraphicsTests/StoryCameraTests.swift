// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import MartyGraphics

/// The story video's camera against the stills: during a beat's hold the story camera equals the camera of that beat's
/// still, for the same layout (full frame or split), and the fit uses the solid pane's actual pixels. At the hold
/// camera, the focus parts and the anchors of shown annotations are inside the pane (no "off view").
final class StoryCameraTests: ExplainerTestCase {
    /// Gears with a label on each gear; beat 1 has a text-only board (full-frame solid) and focuses the small gear,
    /// beat 2 adds a table (split layout) and focuses the big gear, beat 3 removes it again (full frame).
    static let doc = XFix.doc(
        board: #"{"v":1,"items":[{"id":"cap","k":"text","at":[6,7],"text":"Gears"}]}"#,
        solid: #"{"v":2,"parts":[{"id":"p","shape":{"gear":{"teeth":15,"module":2,"width":8}},"joint":{"revolute":[0,0,1]},"drive":{"input":1}},{"id":"w","at":[45,0,0],"shape":{"gear":{"teeth":30,"module":2,"width":8}},"joint":{"revolute":[0,0,1]}},{"id":"base","at":[22,0,-30],"shape":{"box":{"size":[160,60,6]}}}],"constraints":[{"gearMesh":{"a":"p","b":"w"}}],"annotations":{"labels":[{"id":"lp","at":"p","text":"Small gear"},{"id":"lw","at":"w","text":"Big gear"}]}}"#,
        beats: """
        [{"say":"The small gear drives.","view":{"focus":["p"],"annotate":["lp"]}},
         {"say":"The big gear follows.","view":{"focus":["w"],"annotate":["lw"],"spin":0.5},"ops":[{"op":"add","item":{"id":"t","k":"table","at":[6,4],"header":true,"cells":[["Gear","Teeth"],["small","{p.teeth}"]]}}]},
         {"say":"Both turn together.","view":{"annotate":["lp","lw"]},"ops":[{"op":"remove","id":"t"}]}]
        """)

    struct Beat { var view: MGExplainerBeatView; var step: Int?; var pane: MGExplainerBoardPane; var caption: String }

    /// The beats as `marty-solid render` steps them (each settled).
    func beats() throws -> (MGExplainerSession, [Beat]) {
        let clock = MGManualClock()
        var s = try XFix.load(Self.doc, pacing: .speech, clock: clock)
        var out: [Beat] = []
        while let k = s.presented.beat, k == out.count {
            clock.advance(by: s.motionRemaining)
            _ = s.tick()
            out.append(Beat(view: s.presented, step: s.solidStep(forBeat: k), pane: s.boardPane, caption: "\(k + 1). \(s.caption ?? "")"))
            _ = s.lineEnded(k)
        }
        return (s, out)
    }

    func testHoldCameraEqualsTheStillCameraInBothLayouts() throws {
        let (s, beats) = try beats()
        let d = try XCTUnwrap(s.solid)
        XCTAssertEqual(beats.map(\.pane.shown), [false, true, false])
        for (w, h) in [(1280, 800), (640, 400), (800, 1000)] {
            // The still of each beat: its own layout, its pane's pixels.
            var stills: [MGSolidCamera?] = [], panes: [MGFrameRect] = []
            for b in beats {
                let pane = try XCTUnwrap(MGExplainerFrame.panes(width: w, height: h, board: b.pane.shown, solid: true, primarySolid: true).solid)
                panes.append(pane)
                stills.append(MGExplainerFrame.solidCamera(d, view: b.view, stepIndex: b.step, pane: pane).camera)
            }
            // The layouts differ (full frame, split, full frame), and the fit depends on the pane: the split pane's
            // camera for beat 2 differs from the camera the full-frame pane would give it.
            XCTAssertEqual(panes[0], panes[2])
            XCTAssertNotEqual(panes[0], panes[1])
            let full = MGExplainerFrame.solidCamera(d, view: beats[1].view, stepIndex: beats[1].step, pane: panes[0]).camera
            XCTAssertNotEqual(full, stills[1])
            let plan = try MGStoryPlan(captions: beats.map(\.caption), spins: beats.map { $0.view.step?.spin ?? 0 }, fps: 30)
            // Without cuts: every hold frame has the still's camera, every move frame lies between two stills.
            var holds = 0
            for i in 0..<plan.frameCount {
                let f = plan.frame(i)
                let c = try XCTUnwrap(plan.camera(frame: i, beatCameras: stills))
                XCTAssertEqual(plan.holds(frame: i), f.camera >= 1)
                if f.camera >= 1 {
                    XCTAssertEqual(c, stills[f.beat], "frame \(i) at \(w)x\(h)"); holds += 1
                } else {
                    XCTAssertNotEqual(c, stills[f.beat], "frame \(i): inside the move")
                }
            }
            XCTAssertEqual(holds, plan.beats.reduce(0) { $0 + $1.frames - $1.transitionFrames })
            // The layout changes at beats 2 and 3 (split, then full frame): those beats cut, so every one of their
            // frames has the still's camera and shows labels.
            let cuts = Set(panes.indices.dropFirst().filter { panes[$0] != panes[$0 - 1] })
            XCTAssertEqual(cuts, [1, 2])
            for i in 0..<plan.frameCount where cuts.contains(plan.frame(i).beat) {
                XCTAssertEqual(plan.camera(frame: i, beatCameras: stills, cuts: cuts), stills[plan.frame(i).beat])
                XCTAssertTrue(plan.holds(frame: i, cuts: cuts))
            }
            // The last frame of every beat is the still's camera and the still's pose.
            for (k, b) in plan.beats.enumerated() {
                let last = b.startFrame + b.frames - 1
                XCTAssertEqual(plan.camera(frame: last, beatCameras: stills), stills[k])
                XCTAssertEqual(plan.frame(last).spin, 1)
            }
        }
    }

    /// At each beat's hold camera, in its own layout, the focus parts are inside the pane and every shown annotation's
    /// anchor is in view (no callout marked "off view").
    func testFocusAndAnnotationAnchorsAreInViewAtTheHoldCamera() throws {
        let (s, beats) = try beats()
        let d = try XCTUnwrap(s.solid)
        let stage = MGSolidStage.zUpToYUp
        for (w, h) in [(1280, 800), (640, 400)] {
            for (k, b) in beats.enumerated() {
                let pane = try XCTUnwrap(MGExplainerFrame.panes(width: w, height: h, board: b.pane.shown, solid: true, primarySolid: true).solid)
                let camera = MGExplainerFrame.solidCamera(d, view: b.view, stepIndex: b.step, pane: pane).camera
                let shown = try XCTUnwrap(b.view.solid)
                XCTAssertFalse(shown.annotations.isEmpty)
                // Every pose of the hold (the spin plays during it): start, middle and end.
                for spin in [0.0, 0.5, 1.0] {
                    let params = MGExplainerFrame.pose(d, view: b.view, spin: spin)
                    let frame = MGSolidAnnotations.frame(document: d, view: shown, params: params, camera: camera,
                                                         width: Double(pane.width), height: Double(pane.height), highlight: b.view.solidHighlight)
                    XCTAssertNil(frame.refusal, "beat \(k + 1)")
                    XCTAssertEqual(frame.placement.count, shown.annotations.count, "beat \(k + 1)")
                    XCTAssertEqual(frame.placement.filter(\.offView).map(\.id), [], "beat \(k + 1) at \(w)x\(h), spin \(spin)")
                    let pose = d.assembly.pose(params)
                    let focus = b.view.step?.focus ?? []
                    let pts = focus.flatMap { id -> [MGVec3] in
                        let t = pose.world[id] ?? .identity
                        return (d.assembly.part(id)?.mesh.positions ?? []).map { stage.apply(t.apply($0)) }
                    }
                    XCTAssertTrue(MGSolidFraming.contains(pts, camera: camera, aspect: pane.aspect,
                                                          window: MGSolidFraming.Window(left: -1, right: 1, bottom: -1, top: 1)),
                                  "beat \(k + 1) focus at \(w)x\(h)")
                }
            }
        }
    }

    /// Pane rects are whole pixels inside the frame, so the still and the story render the pane at the size its camera
    /// was fitted for.
    func testPaneRectsAreWholePixelsInsideTheFrame() {
        for (w, h) in [(1280, 800), (641, 401), (320, 200), (800, 1000), (3840, 2160)] {
            for board in [false, true] {
                let p = MGExplainerFrame.panes(width: w, height: h, board: board, solid: true, primarySolid: true)
                for r in [p.board, p.solid].compactMap({ $0 }) {
                    XCTAssertGreaterThan(r.width, 0); XCTAssertGreaterThan(r.height, 0)
                    XCTAssertGreaterThanOrEqual(r.x, 0); XCTAssertGreaterThanOrEqual(r.y, 0)
                    XCTAssertLessThanOrEqual(r.x + r.width, w); XCTAssertLessThanOrEqual(r.y + r.height, h)
                }
                if let b = p.board, let s = p.solid {
                    XCTAssertGreaterThan(s.width * s.height, b.width * b.height)   // the primary (solid) pane is larger
                    XCTAssertTrue(b.x + b.width <= s.x || b.y >= s.y + s.height)  // no overlap
                }
            }
        }
    }

    /// The pane decision reads the presented state the legend records: every item the rule looked at is in the
    /// legend's record of shown items.
    func testPaneReadsTheStateTheLegendRecords() throws {
        let clock = MGManualClock()
        var s = try XFix.load(Self.doc, pacing: .speech, clock: clock)
        var k = 0
        while let beat = s.presented.beat, beat == k {
            clock.advance(by: s.motionRemaining)
            _ = s.tick()
            let ids = s.state?.scene.items.map(\.id) ?? []
            XCTAssertFalse(ids.isEmpty)
            XCTAssertTrue(Set(ids).isSubset(of: Set(s.recordedShown.ids)), "beat \(k + 1)")
            XCTAssertEqual(s.boardPane, MGExplainerBoardPane.rule(scene: s.state?.scene, hasSolid: true))
            _ = s.lineEnded(k)
            k += 1
        }
        XCTAssertEqual(k, 3)
    }
}
