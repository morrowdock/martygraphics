// SPDX-License-Identifier: Apache-2.0
import SwiftUI
import SceneKit
import Combine
import os

// The SwiftUI host of an explainer: two panes (the board and the solid) driven by one beat timeline, one caption and
// one legend. All explainer logic stays in the Foundation-only `MGExplainerSession`.

/// Time marks of one explainer run (session clock). TE1/TE3 are core marks; TE2/TE4 are the first frames each pane drew.
public struct MGExplainerRunTiming: Equatable, Sendable {
    /// When the host started the request (`begin()`).
    public var requestAt: Duration?
    public var core = MGExplainerTiming()
    /// TE2: the first Canvas frame of the board. TE4: the first frame of the solid pane.
    public var boardFrameAt: Duration?
    public var solidFrameAt: Duration?

    /// TE1: board statement complete → `boardPresented`.
    public var boardCore: Duration? { core.boardCore }
    /// TE2: request → first board frame.
    public var boardFrame: Duration? { requestAt.flatMap { r in boardFrameAt.map { $0 - r } } }
    /// TE3: solid statement complete → `solidCompiled`.
    public var solidCore: Duration? { core.solidCore }
    /// TE4: request → first solid frame.
    public var solidFrame: Duration? { requestAt.flatMap { r in solidFrameAt.map { $0 - r } } }
    /// TE5: request → the earlier of TE2 and TE4.
    public var firstVisible: Duration? { [boardFrame, solidFrame].compactMap { $0 }.min() }
    /// TE6: request → `explainerComplete`.
    public var complete: Duration? { requestAt.flatMap { r in core.completeAt.map { $0 - r } } }
}

/// The board pane's render input for a presented explainer beat: the 2D state with the beat's emphasis and table rows.
public enum MGExplainerBoard {
    public static func input(_ scene: MGScene, view: MGExplainerBeatView, size: CGSize, theme: MGTheme = .board) -> MGRenderInput {
        let vp = MGViewport(size: size, width: scene.width, height: scene.height, camera: scene.camera)
        var input = MGRenderInput(scene: scene, items: scene.items, viewport: vp, theme: theme)
        input.emphasis = view.boardEmphasis
        input.tableRows = view.tableRows
        input.tableCells = view.tableCells
        return input
    }
}

/// SwiftUI adapter around `MGExplainerSession`: publishes both views, runs the pacing clock, plays each beat's 3D
/// `spin` over time from the beat's start (frozen while paused), applies the beat's camera preset and orbit, drives
/// the board through an `MGSceneController` (the lesson's blends and keyframes, held while paused), writes signposts
/// (subsystem `MartyGraphics`, category `explainer`: `statement`, `beat`, `solidCompile`) and records TE1–TE6.
@MainActor
public final class MGExplainerController: ObservableObject {
    @Published public private(set) var session: MGExplainerSession
    @Published public private(set) var timing = MGExplainerRunTiming()
    /// The last refusal (developer reason; never show it to the learner).
    @Published public private(set) var lastIssue: MGExplainerIssue?
    /// The pose the solid pane shows now (it changes while a beat's spin plays).
    @Published public private(set) var solidParams = MGPoseParameters()
    /// Every event, in order (speech hook: speak `lineDue` text, then call `lineStarted` / `lineEnded`).
    public var onEvent: ((MGExplainerEvent) -> Void)?
    /// The SceneKit renderer of the solid pane (nil without a solid). It draws highlights with `.strong` emphasis.
    public private(set) var renderer: MGSolidRenderer?
    /// The board pane's scene controller (the presented 2D state with the lesson's transitions).
    public let board = MGSceneController()
    public nonisolated let clock: MGLessonClock

    let boardFrame = MGFirstFrameMark(), solidFrame = MGFirstFrameMark()
    private var ticker: Task<Void, Never>?
    private var animator: Task<Void, Never>?
    private var shownSolid: MGJSON?
    private var shownSerial = 0
    private var shownBeat: Int?
    /// When the presented beat's motion started (moved forward by every pause), and the elapsed time held while paused.
    private var beatStart: Duration?
    private var heldElapsed: Duration?
    /// `finishNow()`: show every remaining beat at its end, without motion.
    private var skipMotion = false
    private var aspect = 1.4
    private let signposter = OSSignposter(subsystem: "MartyGraphics", category: "explainer")
    private var beatInterval: OSSignpostIntervalState?

    public init(pacing: MGPacing = .estimate(wordsPerSecond: 2.5), clock: MGLessonClock = MGSystemClock(), library: MGSolidLibrary = .builtIn) {
        session = MGExplainerSession(pacing: pacing, clock: clock, library: library); self.clock = clock
        // One clock: the board draws its frames on the session's clock, so a wall-clock jump cannot show an earlier
        // frame while the session says the board has settled.
        board.presentationClock = clock
    }

    /// The learner controls the explainer bound (`bind`), in order.
    public var controls: [MGLessonControl] { session.state?.controls ?? [] }
    public func value(of control: MGLessonControl) -> Double { session.state?.value(of: control) ?? control.min }

    /// Start a new run: clears the session and marks the request time.
    public func begin() {
        ticker?.cancel(); animator?.cancel()
        session = MGExplainerSession(pacing: session.pacing, clock: session.clock, library: session.library)
        timing = MGExplainerRunTiming(requestAt: clock.now)
        lastIssue = nil; renderer = nil; shownSolid = nil; shownSerial = 0; shownBeat = nil; beatStart = nil; heldElapsed = nil
        skipMotion = false
        boardFrame.arm(); solidFrame.arm()
        board.resumeTransitions(); board.show(nil)
    }

    public func feed(_ chunk: String) {
        let interval = signposter.beginInterval("statement", id: signposter.makeSignpostID())
        let events = session.feed(chunk)
        signposter.endInterval("statement", interval)
        sync(events)
    }
    public func feed(_ data: Data) {
        let interval = signposter.beginInterval("statement", id: signposter.makeSignpostID())
        let events = session.feed(data)
        signposter.endInterval("statement", interval)
        sync(events)
    }
    public func endStream() { sync(session.endStream()) }

    /// Load a whole document (all-or-nothing). A refused document changes nothing but `lastIssue`.
    @discardableResult public func load(_ doc: MGExplainer) -> Bool {
        let started = clock.now
        var trial = session
        switch trial.load(doc) {
        case .success(let events):
            ticker?.cancel(); animator?.cancel()
            session = trial; lastIssue = nil; renderer = nil; shownSolid = nil; shownSerial = 0; shownBeat = nil
            beatStart = nil; heldElapsed = nil; skipMotion = false
            if timing.requestAt == nil || timing.core.completeAt != nil { timing = MGExplainerRunTiming(requestAt: started) }
            boardFrame.arm(); solidFrame.arm()
            board.resumeTransitions()
            sync(events); return true
        case .failure(let issue): lastIssue = issue; return false
        }
    }

    /// A learner slider moved: snapped to the control's step (UI only), then the session's learner path. The caption,
    /// the claims and the highlights follow the new state at once.
    @discardableResult public func control(_ id: String, _ value: Double) -> Bool {
        guard let c = session.state?.control(id) else { return false }
        let snapped = min(c.max, max(c.min, c.min + ((value - c.min) / c.step).rounded() * c.step))
        let r = session.control(id, snapped)
        if case .failure(let issue) = r { lastIssue = issue }
        sync([])
        return (try? r.get()) != nil
    }

    public func lineStarted(_ k: Int) { sync(session.lineStarted(k)) }
    public func lineEnded(_ k: Int) { sync(session.lineEnded(k)) }
    public func finishNow() { skipMotion = true; board.resumeTransitions(); sync(session.finishNow()) }
    /// Freeze both panes: the board holds its transition and the solid keeps its current pose.
    public func pause() {
        if heldElapsed == nil, let start = beatStart { heldElapsed = clock.now - start }
        animator?.cancel()
        session.pause(); board.pauseTransitions(); sync([])
    }
    public func resume() {
        if let held = heldElapsed { beatStart = clock.now - held; heldElapsed = nil }
        board.resumeTransitions()
        sync(session.resume())
    }
    public func next() {
        if session.isPaused { resume(); return }
        if let k = session.openLine { lineEnded(k) }
    }

    /// The solid pane's size changed: frame the camera for the new aspect.
    public func setSolidAspect(_ a: Double) {
        guard a.isFinite, a > 0, abs(a - aspect) > 1e-3 else { return }
        aspect = a; frameCamera()
    }

    /// Fraction of the presented beat's `spin` played at `now`: 0 at the beat's start, 1 when it has played (or there is
    /// no spin, `.immediate` pacing, `finishNow`). Paused time does not count.
    public func spinProgress(at now: Duration) -> Double {
        guard let spin = session.presented.step?.spin, spin != 0, session.pacing != .immediate, !skipMotion else { return 1 }
        guard let start = beatStart else { return 0 }
        let elapsed = heldElapsed ?? (now - start)
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) * 1e-18
        return min(1, max(0, seconds / (abs(spin) * MGExplainerLimits.spinSecondsPerTurn)))
    }

    /// The solid's pose at `now`: the beat's explode, and its spin played so far.
    public func solidPose(at now: Duration) -> MGPoseParameters {
        guard let d = session.solid else { return MGPoseParameters() }
        let step = session.presented.step
        return MGPoseParameters(input: d.defaults.input + (step?.spin ?? 0) * 2 * .pi * spinProgress(at: now),
                                explode: step?.explode ?? d.defaults.explode)
    }

    nonisolated func markBoardFrame() { boardFrame.hit(clock) }
    nonisolated func markSolidFrame() { solidFrame.hit(clock) }

    private func frameCamera() {
        guard let r = renderer, let d = session.solid else { return }
        let step = session.presented.step
        let p = MGSolidCamera.presets[step?.camera ?? "hero"] ?? MGSolidCamera.presets["hero"]!
        let params = MGPoseParameters(input: d.defaults.input, explode: step?.explode ?? d.defaults.explode)
        r.frame(params, explodeRange: [0, params.explode], yaw: p.yaw + (step?.orbit ?? 0), pitch: p.pitch, aspect: aspect, margin: 0.8)
    }

    private func applyPose() {
        let pose = solidPose(at: clock.now)
        renderer?.apply(pose)
        if pose != solidParams { solidParams = pose }
    }

    /// Plays the beat's spin: one pose about every 1/30 s until it has played or the controller pauses.
    private func animate() {
        animator?.cancel()
        guard !session.isPaused, spinProgress(at: clock.now) < 1 else { return }
        animator = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(33))
                guard let self, !Task.isCancelled else { return }
                self.applyPose()
                if self.spinProgress(at: self.clock.now) >= 1 { return }
            }
        }
    }

    private func sync(_ events: [MGExplainerEvent]) {
        var fresh = false
        if let src = session.solidSource, src != shownSolid, let doc = session.solid {
            let interval = signposter.beginInterval("solidCompile", id: signposter.makeSignpostID())
            let r = MGSolidRenderer(assembly: doc.assembly)
            r.emphasis = .strong
            renderer = r
            signposter.endInterval("solidCompile", interval)
            shownSolid = src; fresh = true
        }
        // The board shows the presented 2D state with the lesson's own transition.
        if session.board != nil, let change = session.lesson.lastChange, change.serial != shownSerial, let s = session.state {
            shownSerial = change.serial
            board.show(s.scene, transition: change.transition)
        }
        // A new beat starts its motion now (held at zero while paused) and sets its own view and camera.
        let beat = session.presented.beat
        let changed = beat != shownBeat
        if changed {
            shownBeat = beat
            beatStart = clock.now
            heldElapsed = session.isPaused ? .zero : nil
        }
        if let r = renderer, let d = session.solid {
            let v = session.presented
            if fresh || changed { r.show(v.solid ?? d.view(step: nil)) }
            // Also after a learner change, which can move the highlight (an id may stop resolving).
            r.highlight(Set(v.solidHighlight), dimOthers: !v.solidHighlight.isEmpty)
            if fresh || changed { frameCamera() }
        }
        applyPose()
        animate()
        for e in events {
            switch e {
            case .refused(let issue): lastIssue = issue
            case .lineDue:
                if let b = beatInterval { signposter.endInterval("beat", b) }
                beatInterval = signposter.beginInterval("beat", id: signposter.makeSignpostID())
            default: break
            }
            onEvent?(e)
        }
        timing.core = session.timing
        if session.isComplete, let b = beatInterval { signposter.endInterval("beat", b); beatInterval = nil }
        if let f = boardFrame.value, timing.boardFrameAt == nil { timing.boardFrameAt = f }
        if let f = solidFrame.value, timing.solidFrameAt == nil { timing.solidFrameAt = f }
        schedule()
    }

    private func schedule() {
        ticker?.cancel()
        guard let wake = session.nextWake else { return }
        let delay = max(.zero, wake - session.clock.now)
        ticker = Task { [weak self] in
            try? await Task.sleep(for: delay + .milliseconds(1))
            guard !Task.isCancelled, let self else { return }
            self.sync(self.session.tick())
        }
    }
}

/// Records the first frame SceneKit actually rendered in the solid pane (TE4).
final class MGExplainerSolidFrameDelegate: NSObject, SCNSceneRendererDelegate, @unchecked Sendable {
    let mark: MGFirstFrameMark, clock: MGLessonClock
    init(mark: MGFirstFrameMark, clock: MGLessonClock) { self.mark = mark; self.clock = clock }
    func renderer(_ renderer: SCNSceneRenderer, didRenderScene scene: SCNScene, atTime time: TimeInterval) { mark.hit(clock) }
}

/// Two panes (the `primary` view larger: side by side when wide, stacked when narrow), the caption, the learner
/// controls and the legend with its notes.
public struct MartyGraphicsExplainerView: View {
    @ObservedObject private var controller: MGExplainerController
    @ObservedObject private var board: MGSceneController
    @Environment(\.mgTheme) private var theme
    private let frameDelegate: MGExplainerSolidFrameDelegate

    public init(controller: MGExplainerController) {
        self.controller = controller; board = controller.board
        frameDelegate = MGExplainerSolidFrameDelegate(mark: controller.solidFrame, clock: controller.clock)
    }

    public var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width >= geo.size.height
            VStack(alignment: .leading, spacing: 12) {
                if let t = controller.session.title { Text(t).font(.title3.bold()).foregroundStyle(theme.ink) }
                panes(wide: wide)
                Text(controller.session.caption ?? " ").font(.title3).foregroundStyle(theme.ink)
                    .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("explainer.caption")
                ForEach(controller.controls) { c in slider(c) }
                legend
            }
            .padding(16)
        }
        .background(theme.backgroundBottom)
    }

    private var legend: some View {
        let l = controller.session.legend
        return VStack(alignment: .leading, spacing: 2) {
            Text(l.text).font(.footnote.weight(.semibold)).foregroundStyle(theme.ink)
            ForEach(l.notes, id: \.self) { Text($0).font(.caption).foregroundStyle(theme.subtleInk) }
        }
        .accessibilityElement(children: .combine).accessibilityIdentifier("explainer.legend")
    }

    private func slider(_ c: MGLessonControl) -> some View {
        let value = controller.value(of: c)
        let shown = MGPhysics.format(value, unit: c.unit)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(c.label).font(.headline).foregroundStyle(theme.ink)
                Spacer()
                Text(shown).font(.headline.monospacedDigit()).foregroundStyle(theme.color(.accent))
            }
            Slider(value: Binding(get: { controller.value(of: c) }, set: { controller.control(c.id, $0) }), in: c.min...c.max)
                .tint(theme.color(.accent)).accessibilityLabel(c.label).accessibilityValue(shown)
                .accessibilityIdentifier("explainer.slider.\(c.id)")
        }
    }

    @ViewBuilder private func panes(wide: Bool) -> some View {
        let s = controller.session
        let primaryIsSolid = (s.primary ?? (s.solid != nil ? "solid" : "board")) == "solid"
        let both = s.board != nil && s.solid != nil
        let layout = wide ? AnyLayout(HStackLayout(spacing: 12)) : AnyLayout(VStackLayout(spacing: 12))
        layout {
            if s.board != nil, board.scene != nil {
                boardPane.frame(maxWidth: .infinity, maxHeight: .infinity).layoutPriority(both && !primaryIsSolid ? 1.2 : 1)
            }
            if s.solid != nil, let r = controller.renderer {
                GeometryReader { g in
                    SceneView(scene: r.scene, pointOfView: r.cameraNode, options: [.allowsCameraControl], delegate: frameDelegate)
                        .onAppear { controller.setSolidAspect(Double(g.size.width / max(1, g.size.height))) }
                        .onChange(of: g.size) { _, size in controller.setSolidAspect(Double(size.width / max(1, size.height))) }
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .frame(maxWidth: .infinity, maxHeight: .infinity).layoutPriority(both && primaryIsSolid ? 1.2 : 1)
                .accessibilityIdentifier("explainer.solid")
            }
        }
    }

    private var boardPane: some View {
        let v = controller.session.presented
        return MartyGraphicsView(controller: board, showsControls: false, readOnly: true)
            .emphasis(v.boardEmphasis)
            .tableEmphasis(rows: v.tableRows, cells: v.tableCells)
            .boardAccessibility(controller.session.caption)
            .background(MGExplainerBoardProbe(controller: controller, revision: board.revision))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .accessibilityIdentifier("explainer.board")
    }
}

private struct MGExplainerBoardProbe: View {
    let controller: MGExplainerController
    let revision: Int
    var body: some View {
        let c = controller
        let _ = revision
        Canvas { _, _ in c.markBoardFrame() }.allowsHitTesting(false).accessibilityHidden(true)
    }
}
