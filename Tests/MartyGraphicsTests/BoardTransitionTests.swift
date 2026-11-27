// SPDX-License-Identifier: Apache-2.0
#if canImport(AppKit)
import AppKit
#endif
import CoreGraphics
import Foundation
import SwiftUI
import XCTest
@testable import MartyGraphics

/// `MGTransitionStyle` on the 2D board (docs/ENGINE.md, "Transitions"): the default `.spring` board is the board as it
/// was at 5e4952e (spring blends and camera moves, spring pops, leaving items vanish, Reduce Motion snaps with no frame
/// loop), and `.bounded` is opt-in. These are the pure decisions `MGSceneHost` and `MGCanvasRenderer` call; the hosted
/// tests (`BoardTransitionHostTests`) drive a real board in a window through its entry points.
final class BoardTransitionTests: XCTestCase {
    func vectors() -> (MGItem, MGItem) {
        var a = MGItem(id: "v", kind: .vector, color: .force)
        a.pts = [MGPoint(0, 0)]; a.num = ["angle": 350, "len": 2]
        var b = a
        b.pts = [MGPoint(4, 2)]; b.num = ["angle": 20, "len": 6]
        return (a, b)
    }

    @MainActor func testTheSpringIsTheDefaultAndBoundedIsOptIn() throws {
        let scene = try MGParser.scene(data: Data(RenderQualityTests.layered.utf8)).get()
        XCTAssertEqual(MGBoardTeaching().transitionStyle, .spring)
        XCTAssertEqual(MartyGraphicsView(scene: scene).teaching.transitionStyle, .spring)
        XCTAssertEqual(MartyGraphicsView(controller: MGSceneController(scene: scene)).teaching.transitionStyle, .spring)
        XCTAssertEqual(MartyGraphicsView(scene: scene).transitionStyle(.bounded).teaching.transitionStyle, .bounded)
        XCTAssertEqual(MartyGraphicsView(scene: scene).transitionStyle(.bounded).transitionStyle(.spring).teaching.transitionStyle, .spring)
        let input = MGRenderInput(scene: scene, items: scene.items,
                                  viewport: MGViewport(size: CGSize(width: 480, height: 320), width: scene.width, height: scene.height, camera: nil))
        XCTAssertEqual(input.transitionStyle, .spring, "every other host of the renderer keeps the spring pops")
        XCTAssertTrue(input.opacity.isEmpty)
    }

    func testTheSpringBlendIsTheLegacyBlend() {
        let (a, b) = vectors()
        let leaving = MGMake.body("old", MGPoint(1, 1)), entering = MGMake.body("new", MGPoint(5, 5))
        for k in 0...130 {
            let t = Double(k) / 100
            let f = MGBoardTransition.items(.spring, from: [a, leaving], to: [b, entering], elapsed: t, reduceMotion: false)
            // What the board did before `MGTransitionStyle`: `blend(spring(t))` inside the 1.2 s window, then the step.
            let legacy = t < 1.2 ? MGTimeline.blend(from: [a, leaving], to: [b, entering], t: MGTimeline.spring(t)) : [b, entering]
            XCTAssertEqual(f.items, legacy, "at \(t) s")
            XCTAssertTrue(f.opacity.isEmpty, "nothing fades on the default board")
            XCTAssertFalse(f.items.contains { $0.id == "old" }, "a leaving item vanishes at once")
            // Reduce Motion: the new state at once, no blend and no dissolve.
            let snap = MGBoardTransition.items(.spring, from: [a, leaving], to: [b, entering], elapsed: t, reduceMotion: true)
            XCTAssertEqual(snap, MGStepTransition.Frame(items: [b, entering], opacity: [:]), "at \(t) s")
        }
        XCTAssertGreaterThan(MGTimeline.spring(0.3), 1, "the default board keeps the spring's overshoot")
        XCTAssertEqual(MGBoardTransition.items(.spring, from: nil, to: [b], elapsed: 0.1, reduceMotion: false).items, [b], "no blend")
    }

    func testTheBoundedBlendIsTheStepTransition() {
        let (a, b) = vectors()
        let leaving = MGMake.body("old", MGPoint(1, 1)), entering = MGMake.body("new", MGPoint(5, 5))
        for reduce in [false, true] {
            for k in 0...130 {
                let t = Double(k) / 100
                let f = MGBoardTransition.items(.bounded, from: [a, leaving], to: [b, entering], elapsed: t, reduceMotion: reduce)
                let want = t < 1.2 ? MGStepTransition(reduceMotion: reduce).frame(from: [a, leaving], to: [b, entering], elapsed: t)
                                   : MGStepTransition.Frame(items: [b, entering], opacity: [:])
                XCTAssertEqual(f, want, "at \(t) s, Reduce Motion \(reduce)")
            }
        }
        let mid = MGBoardTransition.items(.bounded, from: [a, leaving], to: [b, entering], elapsed: 0.3, reduceMotion: false)
        XCTAssertEqual(mid.opacity["old"] ?? -1, 1 - MGStepTransition().progress(0.3), accuracy: 1e-12, "the leaving item fades out")
        let dissolve = MGBoardTransition.items(.bounded, from: [a, leaving], to: [b, entering], elapsed: 0.3, reduceMotion: true)
        XCTAssertEqual(dissolve.items.first { $0.id == "v" }, b, "nothing moves in the dissolve")
        XCTAssertEqual(dissolve.opacity["new"] ?? -1, MGStepTransition().progress(0.3), accuracy: 1e-12)
    }

    func testCameraMovesAndPopsFollowTheStyle() {
        for k in 0...110 {
            let t = Double(k) / 100
            XCTAssertEqual(MGBoardTransition.cameraProgress(.spring, elapsed: t, reduceMotion: false), t < 1 ? MGTimeline.spring(t) : nil, "at \(t) s")
            XCTAssertEqual(MGBoardTransition.cameraProgress(.bounded, elapsed: t, reduceMotion: false),
                           t < 1 ? MGStepTransition(duration: MGStepTransition.cameraSeconds).progress(t) : nil, "at \(t) s")
            XCTAssertNil(MGBoardTransition.cameraProgress(.spring, elapsed: t, reduceMotion: true))
            XCTAssertNil(MGBoardTransition.cameraProgress(.bounded, elapsed: t, reduceMotion: true))
        }
        for k in 0...100 {
            let p = Double(k) / 100
            XCTAssertEqual(MGBoardTransition.pop(.spring, p), MGTimeline.spring(p * 0.9), "the legacy pop at \(p)")
            XCTAssertEqual(MGBoardTransition.pop(.bounded, p), MGEasing.Curve.settle.at(p))
        }
        XCTAssertLessThan(MGBoardTransition.pop(.spring, 1), 1, "the default pop rests just under the size, as before")
        XCTAssertGreaterThan((0...100).map { MGBoardTransition.pop(.spring, Double($0) / 100) }.max() ?? 0, 1, "and overshoots on the way")
        XCTAssertEqual(MGBoardTransition.pop(.bounded, 1), 1)
    }

    func testOnlyABoundedBoardRunsTheLoopForAReduceMotionDissolve() {
        for motion in [false, true] { for transient in [false, true] { for visible in [false, true] { for active in [false, true] { for reduce in [false, true] {
            let s = MGRenderPolicy.State(motionPlaying: motion, transientActive: transient, visible: visible, sceneActive: active, reduceMotion: reduce)
            XCTAssertEqual(MGBoardTransition.runsLoop(.spring, s), MGRenderPolicy.continuous(s), "the default loop is unchanged")
            XCTAssertEqual(MGBoardTransition.runsLoop(.bounded, s), MGRenderPolicy.continuous(s) || MGRenderPolicy.dissolving(s))
            if reduce {
                XCTAssertFalse(MGBoardTransition.runsLoop(.spring, s), "Reduce Motion: the default board never ticks")
                XCTAssertEqual(MGBoardTransition.runsLoop(.bounded, s), visible && active && transient, "only during the dissolve")
            }
        } } } } }
    }
}

#if canImport(AppKit)
/// A real board (`MartyGraphicsView(controller:)`) in a window, on a manual presentation clock, with a probe
/// (`MGBoardProbe`): the frames it draws, its frame-loop decisions, and its own frame function, tap and step handlers.
/// Real time passes only in `settle`; the board's time (motion, blends, camera moves) moves only with `advance`.
@MainActor final class BoardRig {
    let clock = MGManualClock()
    let controller: MGSceneController
    let probe = MGBoardProbe()
    let window: NSWindow
    let host: NSHostingView<AnyView>
    var style: MGTransitionStyle?
    var reduceMotion: Bool?
    var theme = MGTheme.board
    var markers: [String: Int] = [:]
    var selection: String?

    init(_ scene: MGScene, style: MGTransitionStyle? = nil, reduceMotion: Bool? = false) {
        controller = MGSceneController(scene: scene)
        controller.presentationClock = clock
        self.style = style
        self.reduceMotion = reduceMotion
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 520), styleMask: [.titled], backing: .buffered, defer: false)
        host = NSHostingView(rootView: AnyView(EmptyView()))
        host.frame = window.contentLayoutRect
        window.contentView = host
        rebuild()
        window.orderFront(nil)
    }

    /// The board with the rig's current modifiers and environment (what a host changing them does).
    func rebuild() {
        var board = MartyGraphicsView(controller: controller).boardProbe(probe).boardReduceMotion(reduceMotion).markers(markers)
            .selection(Binding(get: { [unowned self] in self.selection }, set: { [unowned self] in self.selection = $0 }))
        if let style { board = board.transitionStyle(style) }
        host.rootView = AnyView(board.environment(\.mgTheme, theme))
    }

    /// Lets SwiftUI apply updates and run the board's tasks and frame loop for `seconds` of real time.
    func settle(_ seconds: Double = 0.3) {
        let end = Date().addingTimeInterval(seconds)
        repeat {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        } while Date() < end
    }

    /// Moves the board's own time base on.
    func advance(_ seconds: Double) { clock.advance(by: .nanoseconds(Int64((seconds * 1e9).rounded()))) }
    var now: Date { controller.presentationDate() }

    /// The frame the board draws now for a board of `size` (its own frame function).
    func frame(_ size: CGSize) throws -> MGRenderInput { try XCTUnwrap(probe.frame, "the board was never evaluated")(now, size) }

    func patch(_ json: String) throws {
        let p = try MGPatch.parse(data: Data(json.utf8)).get()
        XCTAssertTrue(controller.apply(patch: p), json)
    }

    func resize(_ size: CGSize) {
        window.setContentSize(size)
        host.frame = window.contentLayoutRect
    }

    func close() { window.orderOut(nil) }
}

/// The real 2D board through its entry points: `MartyGraphicsView(controller:)` with and without
/// `transitionStyle(.bounded)`, `MGSceneController.apply(patch:)`, the board's own step handler (its Next button) and
/// tap handler (its tap gesture), the theme environment, a resized window and the teaching modifiers. A probe records
/// what the board decided and drew; pixels are re-rendered from the inputs it drew with, at 1x and 2x.
final class BoardTransitionHostTests: XCTestCase {
    /// A moving body (so the board splits while motion plays), static base items, a static vector, a text item that
    /// a patch removes, and two steps (the second zooms the camera).
    static let json = #"{"v":1,"title":"Layer check","world":{"w":12,"h":8},"items":[{"id":"zone","k":"region","pts":[[1,1],[5,1],[5,4],[1,4]]},{"id":"floor","k":"line","from":[0,1],"to":[12,1]},{"id":"dot","k":"body","at":[3,5.5],"shape":"ball","size":1,"move":{"to":[7,5.5],"t":2}},{"id":"arrow","k":"vector","from":[9,2],"angle":90,"len":2,"label":"Lift"},{"id":"note","k":"text","at":[6,7],"text":"Synthetic motion"}],"steps":[{"say":"First step."},{"say":"Second step.","cam":{"zoom":1.5}}]}"#
    static let size = CGSize(width: 480, height: 320)

    func scene() throws -> MGScene { try MGParser.scene(data: Data(Self.json.utf8)).get() }

    func item(_ id: String, _ f: MGRenderInput) throws -> MGItem { try XCTUnwrap(f.items.first { $0.id == id }, "\(id) is not drawn") }

    /// The camera move `elapsed` into a step change from step `a` to step `b` at `progress`.
    func viewport(_ s: MGScene, from a: Int, to b: Int, progress: Double) -> MGViewport {
        let from = MGViewport(size: Self.size, width: s.width, height: s.height, camera: s.steps[a].camera ?? s.camera).resized(to: Self.size)
        let to = MGViewport(size: Self.size, width: s.width, height: s.height, camera: s.steps[b].camera ?? s.camera).resized(to: Self.size)
        return from.lerp(to, CGFloat(progress))
    }

    func assertViewport(_ v: MGViewport, _ want: MGViewport, _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(Double(v.scale), Double(want.scale), accuracy: 1e-9, "\(what): scale", file: file, line: line)
        XCTAssertEqual(v.center.x, want.center.x, accuracy: 1e-9, "\(what): centre x", file: file, line: line)
        XCTAssertEqual(v.center.y, want.center.y, accuracy: 1e-9, "\(what): centre y", file: file, line: line)
    }

    static let grow = #"{"v":1,"ops":[{"op":"set","id":"arrow","key":"len","value":6},{"op":"remove","id":"note"}]}"#

    // MARK: Item 1: the default board keeps its spring, `.bounded` opts in

    @MainActor func testTheDefaultBoardKeepsTheSpringThroughItsEntryPoints() throws {
        let rig = BoardRig(try scene())                      // no transitionStyle modifier
        defer { rig.close() }
        rig.settle()
        XCTAssertEqual(try rig.frame(Self.size).transitionStyle, .spring)
        let before = try item("arrow", try rig.frame(Self.size))

        // A patch: the arrow grows from 2 to 6 and the note leaves.
        try rig.patch(Self.grow)
        rig.settle()
        let start = rig.now
        rig.advance(0.1)
        var f = try rig.frame(Self.size)
        let after = try XCTUnwrap(MGTimeline.items(try XCTUnwrap(rig.controller.scene), step: 0).first { $0.id == "arrow" })
        let legacy = try XCTUnwrap(MGTimeline.blend(from: [before], to: [after], t: MGTimeline.spring(rig.now.timeIntervalSince(start))).first)
        XCTAssertEqual(try item("arrow", f).n("len"), legacy.n("len"), accuracy: 1e-9, "the spring blend")
        XCTAssertNotEqual(legacy.n("len"), 6, accuracy: 0.1, "0.1 s into the blend")
        XCTAssertNil(f.items.first { $0.id == "note" }, "a leaving item vanishes at once")
        XCTAssertTrue(f.opacity.isEmpty, "nothing fades")
        XCTAssertEqual(f.transitionStyle, .spring, "spring pops")

        // The board's step handler (its Next button): the camera follows the spring.
        try XCTUnwrap(rig.probe.go)(1)
        rig.settle()
        let stepped = rig.now
        rig.advance(0.1)
        f = try rig.frame(Self.size)
        let s = try XCTUnwrap(rig.controller.scene)
        assertViewport(f.viewport, viewport(s, from: 0, to: 1, progress: MGTimeline.spring(rig.now.timeIntervalSince(stepped))), "spring camera")
    }

    @MainActor func testTheBoundedBoardOptsInThroughItsEntryPoints() throws {
        let rig = BoardRig(try scene(), style: .bounded)
        defer { rig.close() }
        rig.settle()
        XCTAssertEqual(try rig.frame(Self.size).transitionStyle, .bounded)
        let before = try item("arrow", try rig.frame(Self.size))

        try rig.patch(Self.grow)
        rig.settle()
        let start = rig.now
        rig.advance(0.1)
        var f = try rig.frame(Self.size)
        let elapsed = rig.now.timeIntervalSince(start)
        let after = try XCTUnwrap(MGTimeline.items(try XCTUnwrap(rig.controller.scene), step: 0).first { $0.id == "arrow" })
        let want = try XCTUnwrap(MGStepTransition().frame(from: [before], to: [after], elapsed: elapsed).items.first)
        XCTAssertEqual(try item("arrow", f).n("len"), want.n("len"), accuracy: 1e-9, "the bounded blend")
        XCTAssertEqual(f.opacity["note"] ?? -1, 1 - MGStepTransition().progress(elapsed), accuracy: 1e-9, "the note fades out")
        XCTAssertNotNil(f.items.first { $0.id == "note" })

        try XCTUnwrap(rig.probe.go)(1)
        rig.settle()
        let stepped = rig.now
        rig.advance(0.1)
        f = try rig.frame(Self.size)
        let s = try XCTUnwrap(rig.controller.scene)
        let progress = MGStepTransition(duration: MGStepTransition.cameraSeconds).progress(rig.now.timeIntervalSince(stepped))
        assertViewport(f.viewport, viewport(s, from: 0, to: 1, progress: progress), "bounded camera")
    }

    /// Reduce Motion on the default board: the new state at once, no dissolve, and the frame loop never runs.
    @MainActor func testWithReduceMotionTheDefaultBoardSnapsAndNeverTicks() throws {
        let rig = BoardRig(try scene(), reduceMotion: true)
        defer { rig.close() }
        rig.settle()
        let draws = rig.probe.liveDraws
        try rig.patch(Self.grow)
        rig.settle()
        rig.advance(0.1)
        var f = try rig.frame(Self.size)
        XCTAssertEqual(try item("arrow", f).n("len"), 6, "no blend")
        XCTAssertNil(f.items.first { $0.id == "note" })
        XCTAssertTrue(f.opacity.isEmpty, "no dissolve")
        try XCTUnwrap(rig.probe.go)(1)
        rig.settle()
        rig.advance(0.1)
        f = try rig.frame(Self.size)
        let s = try XCTUnwrap(rig.controller.scene)
        assertViewport(f.viewport, viewport(s, from: 0, to: 1, progress: 1), "no camera move")
        rig.settle(0.5)
        XCTAssertFalse(rig.probe.decisions.isEmpty)
        XCTAssertTrue(rig.probe.decisions.allSatisfy { !$0.running }, "Reduce Motion: no tick for motion, a patch or a step")
        XCTAssertLessThan(rig.probe.liveDraws - draws, 10, "one draw per change, not a frame loop")
    }

    /// Reduce Motion on a `.bounded` board: a dissolve with no motion, and ticks only while it runs.
    @MainActor func testWithReduceMotionTheBoundedBoardTicksOnlyDuringTheDissolve() throws {
        let rig = BoardRig(try scene(), style: .bounded, reduceMotion: true)
        defer { rig.close() }
        rig.settle(2.4)                                       // the first appearance's transition ends
        XCTAssertEqual(rig.probe.decisions.last?.running, false, "no loop for motion under Reduce Motion")
        let decided = rig.probe.decisions.count, draws = rig.probe.liveDraws
        try rig.patch(Self.grow)
        rig.settle(0.4)
        XCTAssertTrue(rig.probe.decisions.dropFirst(decided).contains { $0.running }, "the dissolve runs the loop")
        XCTAssertGreaterThan(rig.probe.liveDraws - draws, 3, "and the board ticks while it runs")
        let start = rig.now
        rig.advance(0.1)
        let f = try rig.frame(Self.size)
        XCTAssertEqual(try item("arrow", f).n("len"), 6, "nothing moves")
        XCTAssertEqual(f.opacity["note"] ?? -1, 1 - MGStepTransition(reduceMotion: true).progress(rig.now.timeIntervalSince(start)), accuracy: 1e-9)
        rig.settle(2.4)                                       // the dissolve's transition window ends
        XCTAssertEqual(rig.probe.decisions.last?.running, false, "no tick after the dissolve")
        let settled = rig.probe.liveDraws
        rig.settle(0.5)
        XCTAssertLessThan(rig.probe.liveDraws - settled, 3, "the loop stays paused")
    }

    // MARK: Item 4: the split board across ticks and changes

    /// RGBA bytes of an image drawn into an sRGB context of its size, with `over` drawn first when given.
    static func rgba(_ image: CGImage, over: CGImage? = nil) throws -> [UInt8] {
        let w = image.width, h = image.height
        var out = [UInt8](repeating: 0, count: w * h * 4)
        try out.withUnsafeMutableBytes { buf in
            let ctx = try XCTUnwrap(CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            if let over { ctx.draw(over, in: CGRect(x: 0, y: 0, width: w, height: h)) }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return out
    }

    /// The last base draw and the last live draw re-rendered at 1x and 2x: base under live must be the one-canvas frame
    /// of the live draw's input, so a base that missed a change shows up as a pixel difference.
    @MainActor func assertSplit(_ rig: BoardRig, _ what: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let draws = rig.probe.draws
        guard let baseDraw = draws.last(where: { if case .base = $0.layer { return true }; return false }),
              let liveDraw = draws.last(where: { if case .live = $0.layer { return true }; return false }),
              case .base(let baseIDs) = baseDraw.layer, case .live(let liveBase) = liveDraw.layer else {
            return XCTFail("\(what): the board is not split", file: file, line: line)
        }
        XCTAssertEqual(liveBase, baseIDs, "\(what): the live layer leaves out exactly what the base drew", file: file, line: line)
        XCTAssertEqual(baseDraw.size, liveDraw.size, "\(what): both canvases have one size", file: file, line: line)
        for scale in [1.0, 2.0] {
            func render(_ input: MGRenderInput, _ layer: MGCanvasLayer) throws -> CGImage {
                let r = ImageRenderer(content: Canvas { ctx, _ in MGCanvasRenderer.draw(input, in: ctx, layer: layer) }
                    .frame(width: liveDraw.size.width, height: liveDraw.size.height))
                r.scale = scale
                return try XCTUnwrap(r.cgImage)
            }
            let one = try Self.rgba(try render(liveDraw.input, .all))
            let split = try Self.rgba(try render(liveDraw.input, .live(liveBase)), over: try render(baseDraw.input, .base(baseIDs)))
            XCTAssertEqual(one.count, split.count, file: file, line: line)
            var worst = 0, total = 0
            for (x, y) in zip(one, split) { let d = abs(Int(x) - Int(y)); worst = max(worst, d); total += d }
            XCTAssertLessThanOrEqual(worst, 6, "\(what) at \(scale)x: the split differs from the one-canvas frame", file: file, line: line)
            XCTAssertLessThan(Double(total) / Double(max(1, one.count)), 0.5, "\(what) at \(scale)x", file: file, line: line)
        }
    }

    /// After a change: wait for its transition (if any) to end, then the board is split again, its base was redrawn
    /// (when the change touches the base) and base plus live is the one-canvas frame.
    @MainActor func settleSplit(_ rig: BoardRig, _ what: String, baseDraws: inout Int, wait: Double = 2.4, redrawsBase: Bool = true,
                                file: StaticString = #filePath, line: UInt = #line) throws {
        rig.settle(wait)
        XCTAssertEqual(rig.probe.decisions.last, MGBoardProbe.Decision(running: true, layered: true), "\(what): split again", file: file, line: line)
        if redrawsBase { XCTAssertGreaterThan(rig.probe.baseDraws, baseDraws, "\(what): the base was not redrawn", file: file, line: line) }
        try assertSplit(rig, what, file: file, line: line)
        baseDraws = rig.probe.baseDraws
    }

    @MainActor func testTheSplitBoardStaysExactAcrossTicksAndChanges() throws {
        let rig = BoardRig(try scene())                      // the default board: motion plays, so it splits
        defer { rig.close() }
        rig.settle(2.4)
        XCTAssertEqual(rig.probe.decisions.last, MGBoardProbe.Decision(running: true, layered: true))
        var base = rig.probe.baseDraws
        XCTAssertGreaterThan(base, 0)
        try assertSplit(rig, "first frame")
        XCTAssertEqual(boardElements(rig, value: "First step.").count, 1, "VoiceOver: one board element over both canvases")

        // Ticks: the live layer redraws with the motion, the base never does.
        let live = rig.probe.liveDraws
        for _ in 0..<12 { rig.advance(1.0 / 30); rig.settle(0.05) }
        XCTAssertEqual(rig.probe.baseDraws, base, "a tick redrew the base")
        XCTAssertGreaterThan(rig.probe.liveDraws, live + 3, "the live layer ticks")
        try assertSplit(rig, "after ticks")

        // A new revision that moves a base item.
        try rig.patch(#"{"v":1,"ops":[{"op":"set","id":"floor","key":"to","value":[11,2]}]}"#)
        try settleSplit(rig, "revision", baseDraws: &base)
        // A step (the board's Next button), which zooms the camera.
        try XCTUnwrap(rig.probe.go)(1)
        try settleSplit(rig, "step", baseDraws: &base)
        XCTAssertEqual(boardElements(rig, value: "Second step.").count, 1, "VoiceOver: the board's value follows the step across the split")
        // The viewport: a larger window.
        rig.resize(CGSize(width: 700, height: 640))
        try settleSplit(rig, "viewport", baseDraws: &base, wait: 0.6)
        // The theme.
        var light = MGTheme.board
        light.backgroundTop = Color(red: 0.95, green: 0.96, blue: 0.99)
        light.backgroundBottom = Color(red: 0.84, green: 0.87, blue: 0.94)
        light.grid = Color.black.opacity(0.12)
        rig.theme = light
        rig.rebuild()
        try settleSplit(rig, "theme", baseDraws: &base, wait: 0.6)
        // Teaching state: numbered markers (drawn in the live layer; the base may or may not be redrawn).
        rig.markers = ["zone": 1, "dot": 2]
        rig.rebuild()
        try settleSplit(rig, "markers", baseDraws: &base, wait: 0.6, redrawsBase: false)
        XCTAssertEqual(rig.probe.draws.last(where: { if case .live = $0.layer { return true }; return false })?.input.markers, ["zone": 1, "dot": 2])
        XCTAssertEqual(boardElements(rig, value: "Second step.").count, 1)

        // Taps across the split, through the board's own tap handler: a base item and a live item.
        let size = try XCTUnwrap(rig.probe.draws.last?.size)
        let f = try rig.frame(size)
        let tap = try XCTUnwrap(rig.probe.tap)
        tap(f.viewport.point(MGPoint(3, 2.5)), size)
        XCTAssertEqual(rig.selection, "zone", "a base-layer item is selected through the split")
        let dot = try XCTUnwrap(try item("dot", f).pts.first)
        tap(f.viewport.point(dot), size)
        XCTAssertEqual(rig.selection, "dot", "a live-layer item is selected through the split")
    }

    // MARK: Accessibility (properties only; no VoiceOver run)

    /// Accessibility elements under the host whose label is the board's title and whose value is `value`.
    @MainActor func boardElements(_ rig: BoardRig, value: String) -> [NSObject] {
        var out: [NSObject] = [], queue: [Any] = [rig.host], seen = Set<ObjectIdentifier>()
        while let next = queue.popLast(), seen.count < 20_000 {
            guard let o = next as? NSObject, seen.insert(ObjectIdentifier(o)).inserted else { continue }
            if axLabel(o) == "Layer check", axValue(o) == value { out.append(o) }
            queue.append(contentsOf: axChildren(o))
        }
        return out
    }

    @MainActor func axChildren(_ o: NSObject) -> [Any] {
        if let e = o as? NSAccessibilityProtocol { return e.accessibilityChildren() ?? [] }
        return o.accessibilityAttributeValue(.children) as? [Any] ?? []
    }

    @MainActor func axLabel(_ o: NSObject) -> String? {
        if let e = o as? NSAccessibilityProtocol { return e.accessibilityLabel() }
        return o.accessibilityAttributeValue(.description) as? String
    }

    @MainActor func axValue(_ o: NSObject) -> String? {
        if let e = o as? NSAccessibilityProtocol { return e.accessibilityValue() as? String }
        return o.accessibilityAttributeValue(.value) as? String
    }
}
#endif
