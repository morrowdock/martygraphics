// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import MartyGraphics

/// The pane slide of an explainer story (`MGPaneSlide`): a beat whose board pane opens or closes moves its camera and
/// slides the pane boundary instead of cutting; hold frames keep the stills' layouts and cameras exactly; the move's
/// camera keeps its routed positions and is fitted to the current pane; no caption, label or claim of the new beat
/// shows during the move; everything is deterministic. Synthetic gears with neutral names.
final class StoryPaneSlideTests: ExplainerTestCase {
    /// Gears with a label on each; the board has only a text item until beat 2 adds a table (the pane opens), beat 3
    /// keeps it, beat 4 removes it (the pane closes).
    static let doc = XFix.doc(
        board: #"{"v":1,"items":[{"id":"cap","k":"text","at":[6,7],"text":"Gears"}]}"#,
        solid: #"{"v":2,"parts":[{"id":"p","shape":{"gear":{"teeth":15,"module":2,"width":8}},"joint":{"revolute":[0,0,1]},"drive":{"input":1}},{"id":"w","at":[45,0,0],"shape":{"gear":{"teeth":30,"module":2,"width":8}},"joint":{"revolute":[0,0,1]}},{"id":"base","at":[22,0,-30],"shape":{"box":{"size":[160,60,6]}}}],"constraints":[{"gearMesh":{"a":"p","b":"w"}}],"annotations":{"labels":[{"id":"lp","at":"p","text":"Small gear"},{"id":"lw","at":"w","text":"Big gear"}]}}"#,
        beats: """
        [{"say":"The small gear drives.","view":{"focus":["p"],"annotate":["lp"]}},
         {"say":"The big gear follows.","view":{"focus":["w"],"annotate":["lw"]},"ops":[{"op":"add","item":{"id":"t","k":"table","at":[6,4],"header":true,"cells":[["Gear","Teeth"],["small","{p.teeth}"]]}}]},
         {"say":"It turns half as fast.","view":{"annotate":["lp","lw"]}},
         {"say":"Both turn together.","view":{"annotate":["lp","lw"]},"ops":[{"op":"remove","id":"t"}]}]
        """)

    /// One beat as `marty-solid render` lays out its still: its view, solid step, panes and still camera.
    struct Beat {
        var view: MGExplainerBeatView; var step: Int?; var caption: String
        var board: MGFrameRect?; var solid: MGFrameRect; var camera: MGSolidCamera; var clear: MGSolidClearView
    }

    /// The beats at `w` × `h` with the render tool's rules (settled board, adaptive pane, board share, framing).
    func beats(_ w: Int, _ h: Int) throws -> (MGSolidDocument, [Beat]) {
        let clock = MGManualClock()
        var s = try XFix.load(Self.doc, pacing: .speech, clock: clock)
        let d = try XCTUnwrap(s.solid)
        var out: [Beat] = []
        while let k = s.presented.beat, k == out.count {
            clock.advance(by: s.motionRemaining)
            _ = s.tick()
            let pane = s.boardPane
            let share = pane.shown ? MGExplainerFrame.boardShare(scene: s.state?.scene, width: w, height: h, primarySolid: true) : nil
            let rects = MGExplainerFrame.panes(width: w, height: h, board: pane.shown, solid: true, primarySolid: true, boardShare: share)
            let solid = try XCTUnwrap(rects.solid), step = s.solidStep(forBeat: k)
            let clear = MGExplainerFrame.solidClearView(d, view: s.presented, stepIndex: step, pane: solid)
            out.append(Beat(view: s.presented, step: step, caption: "\(k + 1). \(s.caption ?? "")", board: rects.board, solid: solid,
                            camera: clear.camera, clear: clear))
            _ = s.lineEnded(k)
        }
        return (d, out)
    }

    /// The story as the render tool plans it: slides, routed moves (with the hold views and move views), the plan.
    func story(_ d: MGSolidDocument, _ beats: [Beat], fps: Int = 30) throws -> (MGStoryPlan, [Int: MGStoryMove], [Int: MGPaneSlide]) {
        let hold = beats.map { ($0.view.solid ?? d.view(step: nil)).ghosting($0.clear.autoGhost) }
        let shots = beats.indices.map { k in
            MGStoryBeatShot(camera: beats[k].camera, params: MGExplainerFrame.pose(d, view: beats[k].view),
                            view: k == 0 ? hold[0] : hold[k].moving(from: hold[k - 1], d.assembly), step: beats[k].view.step)
        }
        let unrouted = try MGStoryPlan(captions: beats.map(\.caption), spins: beats.map { $0.view.step?.spin ?? 0 }, fps: fps)
        let moves = MGStoryPlan.routes(d, beats: shots, plan: unrouted)
        var slides: [Int: MGPaneSlide] = [:]
        for k in beats.indices.dropFirst() {
            slides[k] = MGPaneSlide(from: (beats[k - 1].board, beats[k - 1].solid), to: (beats[k].board, beats[k].solid))
        }
        return (unrouted.routed(moves), moves, slides)
    }

    /// The board opens at beat 2 and closes at beat 4: both beats move (no cut), the pane slides, every hold frame has
    /// the still's camera and layout, and no caption, label or claim of the new beat shows during a move.
    func testBoardOpensAndClosesWithoutACut() throws {
        for (w, h) in [(1280, 800), (640, 400), (800, 1000)] {
            let (d, beats) = try beats(w, h)
            XCTAssertEqual(beats.map { $0.board != nil }, [false, true, true, false])
            let (plan, moves, slides) = try story(d, beats)
            XCTAssertEqual(plan.cuts, [], "\(w)x\(h): no cut")
            XCTAssertEqual(slides.keys.sorted(), [1, 3])
            XCTAssertEqual(slides[1]?.change, .open); XCTAssertEqual(slides[3]?.change, .close)
            for k in 1...3 { XCTAssertNotEqual(moves[k]?.path, .cut) }
            let stills = beats.map { Optional($0.camera) }
            var moveFrames = 0
            for i in 0..<plan.frameCount {
                let f = plan.frame(i)
                let c = try XCTUnwrap(plan.camera(frame: i, beatCameras: stills))
                let holding = plan.holds(frame: i)
                XCTAssertEqual(holding, f.camera >= 1, "frame \(i)")
                guard !holding, let slide = slides[f.beat] else {
                    if holding { XCTAssertEqual(c, beats[f.beat].camera, "hold frame \(i) at \(w)x\(h)") }
                    continue
                }
                moveFrames += 1
                // During the move: no caption (and so no label or claim of the new beat: they follow `holds`).
                XCTAssertNil(plan.caption(frame: i))
                let p = slide.panes(f.camera), fitted = slide.camera(c, f.camera)
                // The fitted camera keeps the routed position; only the field of view may widen.
                XCTAssertEqual(fitted.targetVector, c.targetVector); XCTAssertEqual(fitted.yaw, c.yaw)
                XCTAssertEqual(fitted.pitch, c.pitch); XCTAssertEqual(fitted.distance, c.distance)
                XCTAssertGreaterThanOrEqual(fitted.fieldOfView, c.fieldOfView)
                // The solid pane lies between the two layouts' solid panes (side by side: its left edge and width).
                let a = beats[f.beat - 1].solid, b = beats[f.beat].solid
                XCTAssertGreaterThanOrEqual(p.solid.x, min(a.x, b.x)); XCTAssertLessThanOrEqual(p.solid.x, max(a.x, b.x))
                XCTAssertGreaterThanOrEqual(p.solid.width, min(a.width, b.width)); XCTAssertLessThanOrEqual(p.solid.width, max(a.width, b.width))
                XCTAssertGreaterThanOrEqual(p.solid.height, min(a.height, b.height)); XCTAssertLessThanOrEqual(p.solid.height, max(a.height, b.height))
            }
            XCTAssertEqual(moveFrames, plan.beats[1].transitionFrames + plan.beats[3].transitionFrames)
            // The last frame of every beat: the still's camera, and the slide's panes at share 1 are the still's panes.
            for (k, b) in plan.beats.enumerated() {
                XCTAssertEqual(plan.camera(frame: b.startFrame + b.frames - 1, beatCameras: stills), beats[k].camera)
                if let s = slides[k] {
                    XCTAssertEqual(s.panes(1).solid, beats[k].solid); XCTAssertEqual(s.panes(1).board, beats[k].board)
                    XCTAssertEqual(s.panes(0).solid, beats[k - 1].solid); XCTAssertEqual(s.panes(0).board, beats[k - 1].board)
                    XCTAssertEqual(s.camera(beats[k].camera, 1), beats[k].camera)
                }
            }
        }
    }

    /// The slide's panes: exact at both ends, monotone in between, a board pane that grows from its outer edge and
    /// fades in (and the reverse), whole pixels inside the frame, never overlapping the solid pane.
    func testSlidePanesAndOpacity() throws {
        for (w, h) in [(1280, 800), (800, 1000)] {
            let full = MGExplainerFrame.panes(width: w, height: h, board: false, solid: true, primarySolid: true)
            let split = MGExplainerFrame.panes(width: w, height: h, board: true, solid: true, primarySolid: true, boardShare: 0.3)
            let open = try XCTUnwrap(MGPaneSlide(from: full, to: split)), close = try XCTUnwrap(MGPaneSlide(from: split, to: full))
            XCTAssertNil(MGPaneSlide(from: split, to: split))
            XCTAssertNil(MGPaneSlide(from: (split.board, nil), to: split))
            // A wider board pane side by side resizes; stacked layouts ignore the share, so nothing changes there.
            let wider = MGExplainerFrame.panes(width: w, height: h, board: true, solid: true, primarySolid: true, boardShare: 0.45)
            if w >= h {
                let wide = try XCTUnwrap(MGPaneSlide(from: split, to: wider))
                XCTAssertEqual(wide.change, .resize); XCTAssertEqual(wide.boardOpacity(0.5), 1)
                let mid = wide.panes(0.5)
                XCTAssertGreaterThan(try XCTUnwrap(mid.board).width, split.board!.width); XCTAssertLessThan(mid.board!.width, wider.board!.width)
            } else {
                XCTAssertNil(MGPaneSlide(from: split, to: wider))
            }
            XCTAssertEqual(open.boardOpacity(0), 0); XCTAssertEqual(open.boardOpacity(1), 1); XCTAssertEqual(open.boardOpacity(0.25), 0.25)
            XCTAssertEqual(close.boardOpacity(0), 1); XCTAssertEqual(close.boardOpacity(1), 0)
            XCTAssertEqual(open.boardOpacity(.nan), 0)
            XCTAssertEqual(open.panes(0).board, nil); XCTAssertEqual(open.panes(.nan).solid, full.solid)
            var last = open.panes(0)
            for j in 1...60 {
                let s = Double(j) / 60
                let p = open.panes(s), q = close.panes(1 - s)
                XCTAssertEqual(p.solid, q.solid, "open and close are mirror images")
                XCTAssertEqual(p.board, q.board)
                if w >= h {
                    XCTAssertGreaterThanOrEqual(p.solid.x, last.solid.x); XCTAssertLessThanOrEqual(p.solid.width, last.solid.width)
                } else {
                    XCTAssertLessThanOrEqual(p.solid.height, last.solid.height)
                }
                if let b = p.board {
                    XCTAssertGreaterThan(b.width, 0); XCTAssertGreaterThan(b.height, 0)
                    XCTAssertGreaterThanOrEqual(b.x, 0); XCTAssertGreaterThanOrEqual(b.y, 0)
                    XCTAssertLessThanOrEqual(b.x + b.width, w); XCTAssertLessThanOrEqual(b.y + b.height, h)
                    XCTAssertTrue(b.x + b.width <= p.solid.x || b.y >= p.solid.y + p.solid.height, "no overlap at \(s)")
                    // The board grows from its outer edge: the left edge (side by side), the top edge (stacked).
                    if w >= h { XCTAssertEqual(b.x, split.board!.x) } else { XCTAssertEqual(b.y + b.height, split.board!.y + split.board!.height) }
                }
                last = p
            }
            XCTAssertEqual(last.solid, split.solid); XCTAssertEqual(last.board, split.board)
        }
    }

    /// The camera fit: the field of view widens only when the current pane is narrower than the nominal (blended)
    /// aspect, by exactly that ratio; the position never changes; the ends are exact.
    func testCameraFitsTheCurrentPane() throws {
        let c = MGSolidCamera(target: MGVec3(1, 2, 3), yaw: 30, pitch: 20, distance: 400, fieldOfView: 30)
        // Stacked (taller than wide): the solid pane's height blends linearly, so its aspect lies below the blend.
        let full = MGExplainerFrame.panes(width: 800, height: 1000, board: false, solid: true, primarySolid: true)
        let split = MGExplainerFrame.panes(width: 800, height: 1000, board: true, solid: true, primarySolid: true)
        let open = try XCTUnwrap(MGPaneSlide(from: full, to: split))
        XCTAssertEqual(open.camera(c, 0), c); XCTAssertEqual(open.camera(c, 1), c); XCTAssertEqual(open.camera(c, .nan), c)
        var widened = 0
        for j in 1..<30 {
            let s = Double(j) / 30
            let f = open.camera(c, s)
            XCTAssertEqual(f.targetVector, c.targetVector); XCTAssertEqual(f.distance, c.distance)
            XCTAssertEqual(f.yaw, c.yaw); XCTAssertEqual(f.pitch, c.pitch)
            let nominal = full.solid!.aspect + (split.solid!.aspect - full.solid!.aspect) * s
            let current = open.panes(s).solid.aspect
            if nominal > current {
                widened += 1
                // tan(fov'/2) = tan(fov/2) × nominal / current.
                XCTAssertEqual(tan(f.fieldOfView * .pi / 360), tan(c.fieldOfView * .pi / 360) * nominal / current, accuracy: 1e-12)
            } else {
                XCTAssertEqual(f, c)
            }
        }
        XCTAssertGreaterThan(widened, 20)
        // A camera already at the widest field of view is not changed.
        let wideCam = MGSolidCamera(target: .zero, yaw: 0, pitch: 0, distance: 10, fieldOfView: MGPaneSlide.maxFieldOfView)
        XCTAssertEqual(open.camera(wideCam, 0.5), wideCam)
    }

    /// The same document gives the same slides, moves, panes and cameras on every run, and in a fresh session.
    func testDeterministic() throws {
        let (d, beats) = try beats(1280, 800)
        let (plan, moves, slides) = try story(d, beats)
        func trace(_ plan: MGStoryPlan, _ slides: [Int: MGPaneSlide], _ beats: [Beat]) -> [String] {
            (0..<plan.frameCount).map { i in
                let f = plan.frame(i)
                var c = plan.camera(frame: i, beatCameras: beats.map { Optional($0.camera) })!
                var p = "\(beats[f.beat].solid)"
                if !plan.holds(frame: i), let s = slides[f.beat] { c = s.camera(c, f.camera); p = "\(s.panes(f.camera))" }
                return "\(i) \(c) \(p)"
            }
        }
        let first = trace(plan, slides, beats)
        for _ in 0..<2 {
            let (d2, b2) = try self.beats(1280, 800)
            let (p2, m2, s2) = try story(d2, b2)
            XCTAssertEqual(p2, plan); XCTAssertEqual(m2, moves); XCTAssertEqual(s2, slides)
            XCTAssertEqual(trace(p2, s2, b2), first)
        }
    }

    /// Public initialisers with hostile rects (edges near `Int.max`, negative sizes) never trap.
    func testHostileRectsDoNotTrap() throws {
        let big = MGFrameRect(x: Int.max - 1, y: Int.min + 1, width: Int.max, height: Int.max)
        let neg = MGFrameRect(x: -5, y: -5, width: -10, height: -10)
        let ok = MGFrameRect(x: 0, y: 0, width: 100, height: 100)
        for (fb, fs, tb, ts) in [(nil, ok, big, big), (big, big, nil, ok), (neg, ok, big, ok), (big, ok, neg, big)] as [(MGFrameRect?, MGFrameRect, MGFrameRect?, MGFrameRect)] {
            guard let slide = MGPaneSlide(from: (fb, fs), to: (tb, ts)) else { continue }
            for s in [0, 0.25, 0.5, 1, .nan, .infinity, -1] as [Double] {
                let p = slide.panes(s)
                // At shares 0 and 1 the input rects come back exactly (the hold layouts); in between no size is negative.
                if s > 0, s < 1 { XCTAssertGreaterThanOrEqual(p.solid.width, 0); XCTAssertGreaterThan(p.board?.width ?? 1, 0) }
                _ = slide.camera(MGSolidCamera(target: .zero, yaw: 0, pitch: 0, distance: 10), s)
                _ = slide.boardOpacity(s)
            }
        }
        XCTAssertNil(MGPaneSlide(from: (nil, neg), to: (ok, ok)))
    }

    /// The manifest record of a slide: path, change and seconds (0 for a cut).
    func testManifestJSON() throws {
        let full = MGExplainerFrame.panes(width: 1280, height: 800, board: false, solid: true, primarySolid: true)
        let split = MGExplainerFrame.panes(width: 1280, height: 800, board: true, solid: true, primarySolid: true)
        let s = try XCTUnwrap(MGPaneSlide(from: split, to: full))
        XCTAssertEqual(s.manifestJSON(cut: false, seconds: 0.6), .object(["path": .string("slide"), "change": .string("close"), "seconds": .number(0.6)]))
        XCTAssertEqual(s.manifestJSON(cut: true, seconds: 0.6), .object(["path": .string("cut"), "change": .string("close"), "seconds": .number(0)]))
    }
}
