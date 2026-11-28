// SPDX-License-Identifier: Apache-2.0
#if canImport(AppKit)
import AppKit
#endif
import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import XCTest
@testable import MartyGraphics

/// `MGTransitionStyle` on the 2D board (docs/ENGINE.md, "Transitions"): the explicit `.spring` board is the board as it
/// was at 5e4952e (spring blends and camera moves, spring pops, leaving items vanish, Reduce Motion snaps with no frame
/// loop). Bounded motion is the default. These are the pure decisions `MGSceneHost` and `MGCanvasRenderer` call; the hosted
/// tests (`BoardTransitionHostTests`) drive a real board in a window through its entry points.
final class BoardTransitionTests: XCTestCase {
    func vectors() -> (MGItem, MGItem) {
        var a = MGItem(id: "v", kind: .vector, color: .force)
        a.pts = [MGPoint(0, 0)]; a.num = ["angle": 350, "len": 2]
        var b = a
        b.pts = [MGPoint(4, 2)]; b.num = ["angle": 20, "len": 6]
        return (a, b)
    }

    @MainActor func testBoundedIsTheDefaultAndSpringIsAvailable() throws {
        let scene = try MGParser.scene(data: Data(RenderQualityTests.layered.utf8)).get()
        XCTAssertEqual(MGBoardTeaching().transitionStyle, .bounded)
        XCTAssertEqual(MartyGraphicsView(scene: scene).teaching.transitionStyle, .bounded)
        XCTAssertEqual(MartyGraphicsView(controller: MGSceneController(scene: scene)).teaching.transitionStyle, .bounded)
        XCTAssertEqual(MartyGraphicsView(scene: scene).transitionStyle(.bounded).teaching.transitionStyle, .bounded)
        XCTAssertEqual(MartyGraphicsView(scene: scene).transitionStyle(.bounded).transitionStyle(.spring).teaching.transitionStyle, .spring)
        let input = MGRenderInput(scene: scene, items: scene.items,
                                  viewport: MGViewport(size: CGSize(width: 480, height: 320), width: scene.width, height: scene.height, camera: nil))
        XCTAssertEqual(input.transitionStyle, .bounded)
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
        XCTAssertGreaterThan(MGTimeline.spring(0.3), 1, "the spring retains its overshoot")
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

    // MARK: The split follows the board's own clock

    /// `MGBoardTransition.phase`: a blend moves until `items` gives the new items with nothing fading for good (the
    /// whole window for the spring, exactly that for `.bounded`), a camera move exactly while `cameraProgress` is
    /// non-nil and keyframes while they play; draw-on is what is left once those are over. While the phase is `.moving`
    /// the board draws one canvas: a base cached at the start of a blend or a camera move would stay there while the
    /// live layer moved on.
    func testTheSplitWaitsForBlendsAndCameraMovesOnTheBoardsClock() throws {
        let (a, b) = vectors()
        let leaving = MGMake.body("old", MGPoint(1, 1)), entering = MGMake.body("new", MGPoint(5, 5))
        let from = [a, leaving], to = [b, entering]
        let rest = MGStepTransition.Frame(items: to, opacity: [:])
        func phase(_ style: MGTransitionStyle, blend: Double? = nil, camera: Double = .infinity, keyframes: Bool = false,
                   drawingOn: Bool = false, reduce: Bool = false) -> MGBoardTransition.Phase {
            MGBoardTransition.phase(style, blendElapsed: blend, cameraElapsed: camera, keyframes: keyframes, drawingOn: drawingOn,
                                    reduceMotion: reduce)
        }
        for style in MGTransitionStyle.allCases {
            for reduce in [false, true] {
                let what = "\(style.rawValue), Reduce Motion \(reduce)"
                for k in -10...150 {
                    let t = Double(k) / 100
                    let atRest = MGBoardTransition.items(style, from: from, to: to, elapsed: t, reduceMotion: reduce) == rest
                    // Never split during a blend: once the phase is over, the frame is the new items with nothing fading.
                    if phase(style, blend: t, reduce: reduce) != .moving { XCTAssertTrue(atRest, "\(what): split mid-blend at \(t) s") }
                    let moving = style == .bounded ? !atRest : !reduce && t < MGBoardTransition.blendWindow
                    XCTAssertEqual(phase(style, blend: t, reduce: reduce), moving ? .moving : .settled, "\(what): blend at \(t) s")
                    XCTAssertEqual(phase(style, blend: t, drawingOn: true, reduce: reduce), moving ? .moving : .drawingOn,
                                   "\(what): blend and draw-on at \(t) s")
                    let still = MGBoardTransition.cameraProgress(style, elapsed: t, reduceMotion: reduce) == nil
                    XCTAssertEqual(phase(style, camera: t, reduce: reduce), still ? .settled : .moving, "\(what): camera at \(t) s")
                }
                XCTAssertEqual(phase(style, reduce: reduce), .settled, "\(what): no transition")
                XCTAssertEqual(phase(style, drawingOn: true, reduce: reduce), .drawingOn, what)
                XCTAssertEqual(phase(style, keyframes: true, reduce: reduce), .moving, "\(what): keyframes")
            }
        }
        // Why the spring's whole window: its blend gives the new items whenever the spring is past 1 (first at about
        // 0.19 s) and leaves them again inside the window, so reaching them once does not end it.
        let springAtRest = (0..<120).map { MGBoardTransition.items(.spring, from: from, to: to, elapsed: Double($0) / 100, reduceMotion: false) == rest }
        let firstAtRest = try XCTUnwrap(springAtRest.firstIndex(of: true))
        XCTAssertTrue(springAtRest[firstAtRest...].contains(false), "the spring's blend leaves the new items again")
        // The default blend moves for its whole 1.2 s window, a `.bounded` one until 0.6 s; a camera move for the whole
        // 1.0 s window, in which the viewport is a lerp.
        XCTAssertEqual(phase(.spring, blend: 1.19), .moving)
        XCTAssertEqual(phase(.spring, blend: 1.2), .settled)
        XCTAssertEqual(phase(.bounded, blend: 0.59), .moving)
        XCTAssertEqual(phase(.bounded, blend: 0.6), .settled)
        XCTAssertEqual(phase(.bounded, camera: 0.99), .moving)
        XCTAssertEqual(phase(.spring, blend: 0, reduce: true), .settled, "the spring board snaps")
        XCTAssertEqual(phase(.bounded, blend: 0, reduce: true), .moving, "a bounded board dissolves")
        // What `MGCanvasLayers.settling` cannot see: a `.bounded` exit starts opaque, so only the phase keeps it out of
        // the base.
        let start = MGBoardTransition.items(.bounded, from: from, to: to, elapsed: 0, reduceMotion: false)
        XCTAssertEqual(start.opacity["old"], 1)
        XCTAssertTrue(start.items.contains { $0.id == "old" })
        XCTAssertFalse(MGCanvasLayers.settling(appear: [:], opacity: start.opacity).contains("old"))
        XCTAssertEqual(phase(.bounded, blend: 0), .moving)
    }

    /// The draw-on map the board draws with (`MGBoardTransition.appear`), and the cost of its end: over the first
    /// appearance of `RenderQualityTests.layered`, ticked on the board's clock, the phase changes once, when the last
    /// item (the text, 0.4 s late) is drawn in full. The board splits once for the phase it starts in and once more for
    /// that change, so the base is drawn twice in all: first with no item, then with the static prefix.
    func testTheLastDrawOnEndsThePhaseOnce() throws {
        let t0 = Date(timeIntervalSinceReferenceDate: 1000)
        let starts = ["a": t0, "b": t0.addingTimeInterval(0.4)]
        XCTAssertEqual(MGBoardTransition.appear(starts, at: t0, reduceMotion: false), ["a": 0, "b": 0], "b has not started")
        let mid = MGBoardTransition.appear(starts, at: t0.addingTimeInterval(0.6), reduceMotion: false)
        XCTAssertNil(mid["a"], "a is drawn in full")
        XCTAssertEqual(mid["b"] ?? -1, 0.2 / MGBoardTransition.drawOnSeconds, accuracy: 1e-9)
        XCTAssertEqual(MGBoardTransition.appear(starts, at: t0.addingTimeInterval(0.96), reduceMotion: false), [:])
        XCTAssertEqual(MGBoardTransition.appear(starts, at: t0.addingTimeInterval(0.3), reduceMotion: true), [:], "Reduce Motion")

        let scene = try MGParser.scene(data: Data(RenderQualityTests.layered.utf8)).get()
        let plan = MGAdoption.plan(previous: nil, next: scene.items, transition: .blend)
        let appearStart = plan.appear.mapValues { t0.addingTimeInterval($0) }
        let last = (plan.appear.values.max() ?? 0) + MGBoardTransition.drawOnSeconds
        XCTAssertEqual(last, 0.95, accuracy: 1e-12)
        var phases: [MGBoardTransition.Phase] = [], bases: [Set<String>] = []
        for k in 0...96 {
            let t = Double(k) / 64
            let appear = MGBoardTransition.appear(appearStart, at: t0.addingTimeInterval(t), reduceMotion: false)
            let phase = MGBoardTransition.phase(.spring, blendElapsed: nil, cameraElapsed: .infinity, keyframes: false,
                                                drawingOn: !appear.isEmpty, reduceMotion: false)
            XCTAssertEqual(phase, t < last ? .drawingOn : .settled, "at \(k)/64 s")
            guard phases.last != phase else { continue }
            phases.append(phase)
            let items = MGTimeline.frame(scene, items: scene.items, time: t)
            bases.append(MGCanvasLayers.base(items, live: MGCanvasLayers.live(scene, items: items)
                .union(MGCanvasLayers.settling(appear: appear, opacity: [:]))))
        }
        XCTAssertEqual(phases, [.drawingOn, .settled], "one change of phase, so one repartition")
        XCTAssertEqual(bases, [[], ["zone", "floor"]], "from no item cached to the static prefix")
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
    /// The accessibility label of a plain SwiftUI `Text` hosted below the board, when set: an accessibility control
    /// that shows whether the host exposes an accessibility tree at all.
    let control: String?

    init(_ scene: MGScene, style: MGTransitionStyle? = nil, reduceMotion: Bool? = false, control: String? = nil) {
        controller = MGSceneController(scene: scene)
        controller.presentationClock = clock
        self.style = style
        self.reduceMotion = reduceMotion
        self.control = control
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
        // Hosted in this test process, the board did not read the `.active` scene phase (Mac run #23: it never ran its
        // frame loop, `MGRenderPolicy.continuous`), so the rig sets the phase a foreground app's scene gives it.
        let hosted = board.environment(\.mgTheme, theme).environment(\.scenePhase, .active)
        if let control {
            host.rootView = AnyView(VStack(spacing: 0) { hosted; Text(control).accessibilityLabel(control) })
        } else {
            host.rootView = AnyView(hosted)
        }
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

    // MARK: Item 1: the explicit spring and default bounded motion

    @MainActor func testExplicitSpringThroughBoardEntryPoints() throws {
        let rig = BoardRig(try scene(), style: .spring)
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
        let rig = BoardRig(try scene())
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

    /// Reduce Motion on an explicit spring board: the new state at once, no dissolve, and the frame loop never runs.
    @MainActor func testWithReduceMotionSpringSnapsAndNeverTicks() throws {
        let rig = BoardRig(try scene(), style: .spring, reduceMotion: true)
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
        let rig = BoardRig(try scene(), reduceMotion: true)
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
            let oneImage = try render(liveDraw.input, .all)
            let liveImage = try render(liveDraw.input, .live(liveBase)), baseImage = try render(baseDraw.input, .base(baseIDs))
            let one = try Self.rgba(oneImage)
            let split = try Self.rgba(liveImage, over: baseImage)
            XCTAssertEqual(one.count, split.count, file: file, line: line)
            var worst = 0, total = 0
            for (x, y) in zip(one, split) { let d = abs(Int(x) - Int(y)); worst = max(worst, d); total += d }
            XCTAssertLessThanOrEqual(worst, 6, "\(what) at \(scale)x: the split differs from the one-canvas frame", file: file, line: line)
            XCTAssertLessThan(Double(total) / Double(max(1, one.count)), 0.5, "\(what) at \(scale)x", file: file, line: line)
            // Diagnostics only (printed after the checks above; they assert nothing): where a failing split differs.
            if worst > 6 || Double(total) / Double(max(1, one.count)) >= 0.5 {
                Self.reportSplit(what, scale: scale, base: baseDraw, live: liveDraw, baseIDs: baseIDs,
                                 images: (one: oneImage, base: baseImage, live: liveImage), one: one, split: split)
            }
        }
    }

    /// The items the last base draw cached (nil: the board never drew a base).
    @MainActor func lastBase(_ rig: BoardRig) -> Set<String>? {
        guard case .base(let ids)? = rig.probe.draws.last(where: { if case .base = $0.layer { return true }; return false })?.layer else { return nil }
        return ids
    }

    /// Diagnostics for a split that differs from the one-canvas frame, printed on lines that start with `SPLIT-DIFF`
    /// (nothing here asserts): how many pixels differ by more than 6 and where (bounding box, and how many on each
    /// outer row and column), the first and the worst of them with the RGBA of the one-canvas frame, the composite,
    /// the base alone and the live layer alone, the items whose footprint (`MGLayout.bounds` widened by 14 points for
    /// glows and shadows) covers that point in each draw's viewport, and both draws' sizes, viewports, times, draw-on
    /// and fade maps. With `MG_STILLS_DIR` set, the four images are also written there as PNGs.
    static func reportSplit(_ what: String, scale: Double, base: MGBoardProbe.Draw, live: MGBoardProbe.Draw, baseIDs: Set<String>,
                            images: (one: CGImage, base: CGImage, live: CGImage), one: [UInt8], split: [UInt8]) {
        let w = images.one.width, h = images.one.height, tag = "SPLIT-DIFF \(what) at \(scale)x"
        guard w > 0, h > 0, one.count == w * h * 4, split.count == one.count,
              let baseBytes = try? rgba(images.base), let liveBytes = try? rgba(images.live),
              baseBytes.count == one.count, liveBytes.count == one.count else {
            return print("\(tag): no pixel report (the images have different sizes)")
        }
        var count = 0, first: Int?, worstAt = 0, worst = -1
        var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1, top = 0, bottom = 0, left = 0, right = 0
        for p in 0..<(w * h) {
            var d = 0
            for c in 0..<4 { d = max(d, abs(Int(one[4 * p + c]) - Int(split[4 * p + c]))) }
            if d > worst { worst = d; worstAt = p }
            guard d > 6 else { continue }
            let x = p % w, y = p / w
            count += 1
            if first == nil { first = p }
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            if y == 0 { top += 1 }
            if y == h - 1 { bottom += 1 }
            if x == 0 { left += 1 }
            if x == w - 1 { right += 1 }
        }
        func n(_ v: Double) -> String { String(format: "%.3f", v) }
        func bytes(_ b: [UInt8], _ p: Int) -> String { "\(b[4 * p]) \(b[4 * p + 1]) \(b[4 * p + 2]) \(b[4 * p + 3])" }
        func rect(_ r: CGRect) -> String { "x \(n(Double(r.minX)))...\(n(Double(r.maxX))) y \(n(Double(r.minY)))...\(n(Double(r.maxY)))" }
        func map(_ m: [String: Double]) -> String { m.isEmpty ? "none" : m.sorted { $0.key < $1.key }.map { "\($0.key) \(n($0.value))" }.joined(separator: ", ") }
        func covering(_ point: CGPoint) -> String {
            [("live draw", live), ("base draw", base)].map { name, draw in
                let vp = draw.input.viewport
                let hits = draw.input.items.compactMap { item -> String? in
                    guard let r = MGLayout.bounds(item, in: draw.input.items, vp), r.insetBy(dx: -14, dy: -14).contains(point) else { return nil }
                    return "\(item.id) (\(item.kind.rawValue), \(baseIDs.contains(item.id) ? "base" : "live") layer, \(rect(r)))"
                }
                let board = CGRect(origin: .zero, size: vp.size)
                let edge = board.insetBy(dx: 1, dy: 1).contains(point) ? "" : board.contains(point) ? ", within 1 pt of the board's edge" : ", outside the board"
                return "\(name): \(hits.isEmpty ? "no item" : hits.joined(separator: ", "))\(edge)"
            }.joined(separator: " | ")
        }
        func pixel(_ label: String, _ p: Int) -> String {
            let x = p % w, y = p / w, point = CGPoint(x: (Double(x) + 0.5) / scale, y: (Double(y) + 0.5) / scale)
            return "\(tag):   \(label) pixel (\(x), \(y)) = point (\(n(Double(point.x))), \(n(Double(point.y)))): one \(bytes(one, p)), "
                + "split \(bytes(split, p)), base alone \(bytes(baseBytes, p)), live alone \(bytes(liveBytes, p)); covering it: \(covering(point))"
        }
        func drawText(_ name: String, _ d: MGBoardProbe.Draw) -> String {
            let vp = d.input.viewport
            return "\(tag):   \(name) draw: canvas \(n(Double(d.size.width))) x \(n(Double(d.size.height))), viewport \(n(Double(vp.size.width))) x "
                + "\(n(Double(vp.size.height))) scale \(n(Double(vp.scale))) centre (\(n(vp.center.x)), \(n(vp.center.y))), time \(n(d.input.time)), "
                + "draw-on \(map(d.input.appear)), fades \(map(d.input.opacity))"
        }
        print("\(tag): \(count) of \(w * h) pixels (image \(w) x \(h)) differ by more than 6, worst \(worst); "
              + (count > 0 ? "box x \(minX)...\(maxX) y \(minY)...\(maxY); on the top row \(top), bottom row \(bottom), left column \(left), right column \(right)" : "none over 6"))
        if let first { print(pixel("first", first)) }
        print(pixel("worst", worstAt))
        print(drawText("live", live))
        print(drawText("base", base))
        print("\(tag):   base items \(baseIDs.sorted()), live draw items \(live.input.items.map(\.id))")
        guard let dir = ProcessInfo.processInfo.environment["MG_STILLS_DIR"], !dir.isEmpty else { return }
        let stem = "split-" + what.replacingOccurrences(of: " ", with: "-") + "@\(Int(scale))x"
        let composite = CGDataProvider(data: Data(split) as CFData).flatMap {
            CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: $0, decode: nil,
                    shouldInterpolate: false, intent: .defaultIntent)
        }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let outputs: [(String, CGImage?)] = [("one", images.one), ("base", images.base), ("live", images.live), ("split", composite)]
        for (name, image) in outputs {
            guard let image, let out = CGImageDestinationCreateWithURL(URL(fileURLWithPath: dir).appendingPathComponent("\(stem)-\(name).png") as CFURL,
                                                                       "public.png" as CFString, 1, nil) else { continue }
            CGImageDestinationAddImage(out, image, nil)
            _ = CGImageDestinationFinalize(out)
        }
        print("\(tag):   PNGs: \(dir)/\(stem)-{one,base,live,split}.png")
    }

    /// The last base draw is the frame as it now is on the board's clock: every item it cached is drawn now exactly as
    /// it was cached, and its viewport is the current one. A base drawn during a blend or a camera move fails here.
    @MainActor func assertBaseIsCurrent(_ rig: BoardRig, _ what: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let (draw, ids) = try lastBaseDraw(rig)
        let now = try rig.frame(draw.size)
        for id in ids.sorted() {
            XCTAssertEqual(draw.input.items.first { $0.id == id }, now.items.first { $0.id == id }, "\(what): the base cached \(id) as it was",
                           file: file, line: line)
        }
        assertViewport(draw.input.viewport, now.viewport, "\(what): the base viewport", file: file, line: line)
    }

    /// The last base draw, with the items it cached.
    @MainActor func lastBaseDraw(_ rig: BoardRig) throws -> (draw: MGBoardProbe.Draw, ids: Set<String>) {
        let found = rig.probe.draws.reversed().lazy.compactMap { d -> (draw: MGBoardProbe.Draw, ids: Set<String>)? in
            if case .base(let ids) = d.layer { return (d, ids) }
            return nil
        }.first
        return try XCTUnwrap(found, "the board never drew a base")
    }

    /// Ticks the board's own clock on by `seconds`, 0.1 s at a time, letting the frame loop draw between steps.
    @MainActor func tick(_ rig: BoardRig, _ seconds: Double) {
        for _ in 0..<Int((seconds * 10).rounded()) { rig.advance(0.1); rig.settle(0.05) }
    }

    /// After a change whose transition the board's clock has not run yet: the wall-clock transition window ends (real
    /// time only), and the board still draws one canvas, because on its own clock the blend or the camera move is at
    /// its start (`MGBoardTransition.phase`).
    @MainActor func assertOneCanvasUntilTheBoardsClockMoves(_ rig: BoardRig, _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        rig.settle(2.4)
        XCTAssertEqual(rig.probe.decisions.last, MGBoardProbe.Decision(running: true, layered: false),
                       "\(what): the board split before its transition ran on its own clock", file: file, line: line)
    }

    /// After a change: tick the board's own clock through its transitions (`advance` seconds), wait `wait` seconds of
    /// real time, then the board is split again, its base was redrawn (when the change touches the base), base plus live
    /// is the one-canvas frame, and the base is the current frame (`assertBaseIsCurrent`).
    @MainActor func settleSplit(_ rig: BoardRig, _ what: String, baseDraws: inout Int, advance: Double = 0, wait: Double = 0.6,
                                redrawsBase: Bool = true, file: StaticString = #filePath, line: UInt = #line) throws {
        tick(rig, advance)
        rig.settle(wait)
        XCTAssertEqual(rig.probe.decisions.last, MGBoardProbe.Decision(running: true, layered: true), "\(what): split again", file: file, line: line)
        if redrawsBase { XCTAssertGreaterThan(rig.probe.baseDraws, baseDraws, "\(what): the base was not redrawn", file: file, line: line) }
        try assertSplit(rig, what, file: file, line: line)
        try assertBaseIsCurrent(rig, what, file: file, line: line)
        baseDraws = rig.probe.baseDraws
    }

    @MainActor func testTheSplitBoardStaysExactAcrossTicksAndChanges() throws {
        let rig = BoardRig(try scene())                      // the default board: motion plays, so it splits
        defer { rig.close() }
        rig.settle(2.4)
        XCTAssertEqual(rig.probe.decisions.last, MGBoardProbe.Decision(running: true, layered: true))
        var base = rig.probe.baseDraws
        XCTAssertGreaterThan(base, 0)
        // Real time passes in `settle`, the board's own time does not: every item is still at the start of its
        // draw-on, so the base caches no item yet (`MGCanvasLayers.settling`), only the board and the grid.
        XCTAssertEqual(try XCTUnwrap(lastBase(rig)), [], "first frame: an item still drawing on is in the base")
        try assertSplit(rig, "first frame")

        // Ticks: the live layer redraws with the motion and the draw-on, the base never does. (Mac run #25: a base that
        // had cached the zone and the floor mid-draw-on differed here by 3 levels on average.) Both canvases draw the
        // step's items the board's evaluation read from the controller (`MGSceneController.boardFrames`,
        // `MGTimelineCache`): no tick, repartition or base redraw computes them again.
        let live = rig.probe.liveDraws
        let computed = rig.controller.timeline.computed
        for _ in 0..<12 { rig.advance(1.0 / 30); rig.settle(0.05) }
        XCTAssertEqual(rig.probe.baseDraws, base, "a tick redrew the base")
        XCTAssertGreaterThan(rig.probe.liveDraws, live + 3, "the live layer ticks")
        try assertSplit(rig, "after ticks")
        // Ticks past the end of the first appearance's draw-on (the last item ends 0.95 s in). When it ends, the board
        // splits once more: exactly one base redraw, after which the base caches the static prefix drawn in full. (Before,
        // every item stayed in the live layer, redrawn on every tick, for the rest of the playback.)
        for _ in 0..<18 { rig.advance(1.0 / 30); rig.settle(0.05) }
        XCTAssertEqual(rig.probe.baseDraws, base + 1, "the end of the draw-on repartitions the board exactly once")
        XCTAssertEqual(try XCTUnwrap(lastBase(rig)), ["zone", "floor"], "after the draw-on: the static prefix is in the base")
        base = rig.probe.baseDraws
        try assertSplit(rig, "after the draw-on")
        try assertBaseIsCurrent(rig, "after the draw-on")
        // The cost after the repartition: ticks redraw only the live layer, which leaves the static prefix out.
        let afterDrawOn = rig.probe.liveDraws
        for _ in 0..<12 { rig.advance(1.0 / 30); rig.settle(0.05) }
        XCTAssertEqual(rig.probe.baseDraws, base, "a tick after the repartition redrew the base")
        XCTAssertGreaterThan(rig.probe.liveDraws, afterDrawOn + 3, "the live layer ticks")
        XCTAssertEqual(rig.probe.draws.last?.layer, .live(["zone", "floor"]), "each tick draws the live layer without the static prefix")
        try assertSplit(rig, "ticks after the draw-on")
        XCTAssertEqual(rig.controller.timeline.computed, computed, "a tick or the repartition computed the step's items again")

        // A new revision that moves a base item. Until the board's clock runs the blend, the board draws one canvas;
        // then the base is drawn again with the floor where the revision put it.
        try rig.patch(#"{"v":1,"ops":[{"op":"set","id":"floor","key":"to","value":[11,2]}]}"#)
        assertOneCanvasUntilTheBoardsClockMoves(rig, "revision")
        let afterRevision = rig.controller.timeline.computed
        XCTAssertGreaterThan(afterRevision, computed, "revision: the new revision's items were never computed")
        try settleSplit(rig, "revision", baseDraws: &base, advance: 1.5)
        XCTAssertEqual(rig.controller.timeline.computed, afterRevision, "revision: a tick or the split computed the step's items again")
        let revised = try lastBaseDraw(rig)
        XCTAssertEqual(revised.ids, ["zone", "floor"], "revision: the static prefix is in the base")
        XCTAssertEqual(try item("floor", revised.draw.input).pts.last, MGPoint(11, 2), "revision: the base has the revised floor")
        // A step (the board's Next button), which zooms the camera: one canvas until the board's clock runs the move,
        // then a base drawn with the step's camera.
        try XCTUnwrap(rig.probe.go)(1)
        assertOneCanvasUntilTheBoardsClockMoves(rig, "step")
        let afterStep = rig.controller.timeline.computed
        XCTAssertGreaterThan(afterStep, afterRevision, "step: the step's items were never computed")
        try settleSplit(rig, "step", baseDraws: &base, advance: 1.5)
        XCTAssertEqual(rig.controller.timeline.computed, afterStep, "step: a tick or the split computed the step's items again")
        let stepped = try lastBaseDraw(rig)
        let s = try XCTUnwrap(rig.controller.scene)
        let size = stepped.draw.size
        assertViewport(stepped.draw.input.viewport, MGViewport(size: size, width: s.width, height: s.height, camera: s.steps[1].camera).resized(to: size),
                       "step: the base has the step's camera")
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

        // Taps across the split, through the board's own tap handler: a base item and a live item.
        let tapSize = try XCTUnwrap(rig.probe.draws.last?.size)
        let f = try rig.frame(tapSize)
        let tap = try XCTUnwrap(rig.probe.tap)
        tap(f.viewport.point(MGPoint(3, 2.5)), tapSize)
        XCTAssertEqual(rig.selection, "zone", "a base-layer item is selected through the split")
        let dot = try XCTUnwrap(try item("dot", f).pts.first)
        tap(f.viewport.point(dot), tapSize)
        XCTAssertEqual(rig.selection, "dot", "a live-layer item is selected through the split")
    }

    /// The rig's scene with four more steps, so other views can read 4 steps the board does not show, and a static
    /// `func` with readouts, so the board has an audio graph whose summary speaks them.
    static func evictionScene() throws -> MGScene {
        let json = Self.json.replacingOccurrences(of: #"{"say":"Second step.","cam":{"zoom":1.5}}]"#,
                                                  with: #"{"say":"Second step.","cam":{"zoom":1.5}},{"say":"Three."},{"say":"Four."},"#
                                                    + #"{"say":"Five."},{"say":"Six."}]"#)
            .replacingOccurrences(of: #"{"id":"note","#,
                                  with: #"{"id":"g","k":"func","at":[8,4.6],"w":3.5,"h":2.6,"xr":[-1,1],"yr":[-1,1],"y":"x^2","mark":0.5,"#
                                    + #""readouts":["value","slope"]},{"id":"note","#)
        return try MGParser.scene(data: Data(json.utf8)).get()
    }

    /// The board draws from the step items its evaluation read (`MGSceneController.boardFrames`), never from the
    /// controller's cache: after other views on the controller push the board's step out of the cache, its ticks, its
    /// frame function and its tap handler fill nothing, and the taps still hit what the board draws. Its audio graph
    /// comes from the same read: each evaluation of the board reads the cache exactly once and attaches the step's
    /// chart, so VoiceOver reads a value and no cache. A new revision fills the board's step exactly once, and nothing
    /// after it fills the step again.
    @MainActor func testTheBoardsDrawsNeverFillTheCacheAfterItsStepIsEvicted() throws {
        let scene = try Self.evictionScene()
        XCTAssertEqual(scene.steps.count, 6)
        XCTAssertTrue(try XCTUnwrap(MGAudioGraph.chart(scene)).summary.contains("slope is 1"), "the chart speaks the readouts")
        let rig = BoardRig(scene)
        defer { rig.close() }
        rig.settle(2.4)
        for _ in 0..<30 { rig.advance(1.0 / 30); rig.settle(0.05) }   // past the first appearance's draw-on (0.95 s)
        rig.settle(0.6)
        XCTAssertEqual(rig.probe.decisions.last, MGBoardProbe.Decision(running: true, layered: true))
        try assertOneReadPerEvaluation(rig, since: BoardCounts(), "first revision")
        try evictAndTick(rig, "first revision")
        // A new revision that moves a base item: the board's evaluation for it fills its step once (the blend looks the
        // step it leaves up with `MGTimelineCache.peek`, which neither fills the cache nor counts as a read).
        let before = rig.controller.timeline.computed, counts = BoardCounts(rig)
        try rig.patch(#"{"v":1,"ops":[{"op":"set","id":"floor","key":"to","value":[11,2]}]}"#)
        rig.settle(2.4)
        tick(rig, 1.5)
        rig.settle(0.6)
        XCTAssertEqual(rig.probe.decisions.last, MGBoardProbe.Decision(running: true, layered: true), "split again after the revision")
        XCTAssertEqual(rig.controller.timeline.computed, before + 1, "the new revision's step is filled exactly once")
        try assertOneReadPerEvaluation(rig, since: counts, "new revision")
        try evictAndTick(rig, "new revision")
    }

    /// The rig's cache reads (`MGTimelineCache.reads`), evaluations of the board (one frame-loop decision each) and
    /// audio graphs the board attached (`MGBoardProbe.charts`).
    struct BoardCounts {
        var reads = 0, evaluations = 0, charts = 0
        init() {}
        @MainActor init(_ rig: BoardRig) {
            reads = rig.controller.timeline.reads; evaluations = rig.probe.decisions.count; charts = rig.probe.charts.count
        }
    }

    /// Since `start`, the board was evaluated, and each evaluation read the step from the cache exactly once (its draws,
    /// taps, description and audio graph share that read; nothing else on the rig reads the cache) and attached one
    /// audio graph. The last is the chart of the step's items, computed here outside the cache.
    @MainActor func assertOneReadPerEvaluation(_ rig: BoardRig, since start: BoardCounts, _ what: String,
                                              file: StaticString = #filePath, line: UInt = #line) throws {
        let now = BoardCounts(rig), evaluations = now.evaluations - start.evaluations
        XCTAssertGreaterThan(evaluations, 0, "\(what): the board was not evaluated", file: file, line: line)
        XCTAssertEqual(now.reads - start.reads, evaluations,
                       "\(what): the board read the cache more often than it was evaluated (a second read in an evaluation, or a draw)",
                       file: file, line: line)
        XCTAssertEqual(now.charts - start.charts, evaluations, "\(what): one audio graph per evaluation", file: file, line: line)
        let scene = try XCTUnwrap(rig.controller.scene, file: file, line: line)
        let chart = try XCTUnwrap(rig.probe.charts.last.flatMap { $0 }, "\(what): the board has no audio graph", file: file, line: line)
        XCTAssertEqual(chart, MGAudioGraph.chart(scene, step: 0), "\(what): the audio graph is the step's chart", file: file, line: line)
    }

    /// Other views on the controller read steps 1–4 of the board's scene, which pushes the board's step 0 out of the
    /// cache, then the board ticks: the live layer draws, the board is not evaluated again (no base redraw), and no
    /// draw fills the cache. Then the board's own frame function and tap handler (what its tap gesture calls), from
    /// the same evaluation: they fill nothing either, and a tap on a base item and on the moving body selects each.
    /// Nothing read the cache at all (no hit either), and the board kept the audio graph of its last evaluation.
    @MainActor func evictAndTick(_ rig: BoardRig, _ what: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let scene = try XCTUnwrap(rig.controller.scene, file: file, line: line)
        for step in 1...4 { _ = rig.controller.timelineItems(scene, step: step) }
        let computed = rig.controller.timeline.computed, base = rig.probe.baseDraws, live = rig.probe.liveDraws
        let counts = BoardCounts(rig)
        for _ in 0..<12 { rig.advance(1.0 / 30); rig.settle(0.05) }
        XCTAssertGreaterThan(rig.probe.liveDraws, live + 3, "\(what): the live layer ticks", file: file, line: line)
        XCTAssertEqual(rig.probe.baseDraws, base, "\(what): a tick evaluated the board again", file: file, line: line)
        XCTAssertEqual(rig.controller.timeline.computed, computed, "\(what): a draw read the evicted step from the cache", file: file, line: line)
        // The frame function and the tap handler, at the board's last drawn size and its current (manual) time.
        let size = try XCTUnwrap(rig.probe.draws.last?.size, "\(what): nothing was drawn", file: file, line: line)
        let f = try rig.frame(size)
        XCTAssertEqual(rig.controller.timeline.computed, computed, "\(what): the frame function read the evicted step from the cache", file: file, line: line)
        let tap = try XCTUnwrap(rig.probe.tap, "\(what): the board has no tap handler", file: file, line: line)
        rig.selection = nil
        tap(f.viewport.point(MGPoint(3, 2.5)), size)
        XCTAssertEqual(rig.selection, "zone", "\(what): a tap on the zone (a base item) after the eviction", file: file, line: line)
        let dot = try XCTUnwrap(try item("dot", f).pts.first, file: file, line: line)
        tap(f.viewport.point(dot), size)
        XCTAssertEqual(rig.selection, "dot", "\(what): a tap on the moving dot (a live item) after the eviction", file: file, line: line)
        XCTAssertEqual(rig.controller.timeline.computed, computed, "\(what): a tap read the evicted step from the cache", file: file, line: line)
        XCTAssertEqual(rig.controller.timeline.reads, counts.reads, "\(what): a draw, the frame function or a tap read the cache",
                       file: file, line: line)
        XCTAssertEqual(rig.probe.charts.count, counts.charts, "\(what): the board built an audio graph during the ticks", file: file, line: line)
        XCTAssertEqual(rig.probe.charts.last.flatMap { $0 }, MGAudioGraph.chart(scene, step: 0), "\(what): the board's audio graph",
                       file: file, line: line)
        // The board has not been evaluated since the taps, so it never saw the selection: clear it, so the rest of the
        // test runs with no selection change.
        rig.selection = nil
    }

    /// A `.bounded` board: a leaving item fades out from opacity 1, which `MGCanvasLayers.settling` does not count, so
    /// the board draws one canvas until the fade has ended on its own clock, then splits with the item gone.
    @MainActor func testTheBoundedSplitBoardWaitsForAFadingExit() throws {
        let rig = BoardRig(try scene(), style: .bounded)
        defer { rig.close() }
        rig.settle(2.4)
        tick(rig, 1.2)                                        // past the first appearance's draw-on
        XCTAssertEqual(rig.probe.decisions.last, MGBoardProbe.Decision(running: true, layered: true))
        XCTAssertEqual(try XCTUnwrap(lastBase(rig)), ["zone", "floor"], "drawn in full: the static prefix is in the base")
        var base = rig.probe.baseDraws

        // The zone leaves: on the board's clock its fade has not started, so it is still opaque.
        try rig.patch(#"{"v":1,"ops":[{"op":"remove","id":"zone"}]}"#)
        assertOneCanvasUntilTheBoardsClockMoves(rig, "fading exit")
        XCTAssertEqual(try rig.frame(Self.size).opacity["zone"], 1, "the leaving zone starts opaque")
        tick(rig, 0.3)
        XCTAssertEqual(rig.probe.decisions.last?.layered, false, "halfway through the fade: one canvas")
        let mid = try XCTUnwrap(rig.probe.draws.last)
        XCTAssertEqual(mid.layer, .all, "halfway through the fade: one canvas")
        XCTAssertTrue((0.01...0.99).contains(mid.input.opacity["zone"] ?? -1), "the zone is fading: \(mid.input.opacity)")

        // The fade ends at 0.6 s: the board splits, and the base no longer holds the zone.
        try settleSplit(rig, "after the fade", baseDraws: &base, advance: 0.5)
        let after = try lastBaseDraw(rig)
        XCTAssertEqual(after.ids, ["floor"], "after the fade: the zone is gone from the base")
        XCTAssertNil(after.draw.input.items.first { $0.id == "zone" }, "after the fade: the zone is not drawn")
    }

    // MARK: Accessibility (properties only; no VoiceOver run)

    /// The accessibility label of the control `Text` the rig hosts below the board in the accessibility test.
    static let control = "Accessibility control"

    /// The split board is one accessibility element over both canvases, and its value follows the step and survives a
    /// rebuild with new markers. This reads the accessibility properties SwiftUI vends under the host. Mac run #23 found
    /// no element under the host at all, so the rig also hosts a plain SwiftUI `Text` with an accessibility label as a
    /// control. Only a missing control skips the test (the host then exposes no accessibility tree at all); once the
    /// control is found, the board's element count and value are asserted on their own, with no skip, at the first
    /// step, after a step and after a rebuild with markers. The split itself is checked by
    /// `testTheSplitBoardStaysExactAcrossTicksAndChanges`.
    @MainActor func testTheSplitBoardIsOneAccessibilityElement() throws {
        let rig = BoardRig(try scene(), control: Self.control)
        defer { rig.close() }
        rig.settle(2.4)
        XCTAssertEqual(rig.probe.decisions.last, MGBoardProbe.Decision(running: true, layered: true), "the board is split")
        let all = accessibilityElements(rig)
        guard all.contains(where: isControl) else {
            throw XCTSkip("the host exposes no accessibility tree in this process: the control Text was not found (found \(describe(all)))")
        }
        assertBoardElement(rig, value: "First step.", "first step")

        // The board's step handler (its Next button). The board splits again once its own clock has run the camera move.
        try XCTUnwrap(rig.probe.go)(1)
        tick(rig, 1.5)
        rig.settle(2.4)
        XCTAssertEqual(rig.probe.decisions.last, MGBoardProbe.Decision(running: true, layered: true), "the board is split again")
        assertBoardElement(rig, value: "Second step.", "after the step")

        // A rebuild with numbered markers: the host gets a new root view.
        rig.markers = ["zone": 1, "dot": 2]
        rig.rebuild()
        rig.settle(0.6)
        assertBoardElement(rig, value: "Second step.", "after the marker rebuild")
    }

    /// The control is under the host, the board (label: its title) is exactly one element there, and its value is `value`.
    @MainActor func assertBoardElement(_ rig: BoardRig, value: String, _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        let all = accessibilityElements(rig)
        XCTAssertEqual(all.filter(isControl).count, 1, "\(what): the control Text; found \(describe(all))",
                       file: file, line: line)
        let boards = all.filter { axLabel($0) == "Layer check" }
        XCTAssertEqual(boards.count, 1, "\(what): VoiceOver: one board element over both canvases; found \(describe(all))",
                       file: file, line: line)
        XCTAssertEqual(boards.first.flatMap { axValue($0) }, value, "\(what): the board's value; found \(describe(all))",
                       file: file, line: line)
    }

    /// The control `Text` (macOS may vend a static text's string as its value rather than its label).
    @MainActor func isControl(_ o: NSObject) -> Bool { axLabel(o) == Self.control || axValue(o) == Self.control }

    /// Every accessibility element under the host (not the host itself).
    @MainActor func accessibilityElements(_ rig: BoardRig) -> [NSObject] {
        var out: [NSObject] = [], queue: [Any] = axChildren(rig.host), seen = Set<ObjectIdentifier>()
        while let next = queue.popLast(), seen.count < 20_000 {
            guard let o = next as? NSObject, seen.insert(ObjectIdentifier(o)).inserted else { continue }
            out.append(o)
            queue.append(contentsOf: axChildren(o))
        }
        return out
    }

    /// The first elements' labels and values, for a failure message.
    @MainActor func describe(_ elements: [NSObject]) -> String {
        "\(elements.count): " + elements.prefix(12).map { "\(axLabel($0) ?? "-") = \(axValue($0) ?? "-")" }.joined(separator: "; ")
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
