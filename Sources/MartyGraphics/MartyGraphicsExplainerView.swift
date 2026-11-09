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
    /// `fit`: the size the viewport is fitted for (the reference board pane, `MGExplainerFrame.boardReferenceSize`);
    /// the board then keeps that scale and centre in a pane of `size`. Nil fits `size` itself.
    public static func input(_ scene: MGScene, view: MGExplainerBeatView, size: CGSize, fit: CGSize? = nil, theme: MGTheme = .board) -> MGRenderInput {
        let vp = MGViewport(size: fit ?? size, width: scene.width, height: scene.height, camera: scene.camera).resized(to: size)
        var input = MGRenderInput(scene: scene, items: scene.items, viewport: vp, theme: theme)
        input.emphasis = view.boardEmphasis
        input.tableRows = view.tableRows
        input.tableCells = view.tableCells
        return input
    }
}

/// SwiftUI adapter around `MGExplainerSession`: publishes both views, runs the pacing clock, plays each beat's 3D
/// `spin` over time from the beat's start (frozen while paused), frames the solid pane with the beat's framed camera
/// and automatic ghosts (`MGExplainerFrame.solidClearView`, the camera of the beat's still and story hold), drives
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
    /// The SceneKit renderer of the solid pane (nil without a solid). It is loaded from the compiled solid
    /// (`MGSolidRenderer(document:)`, `setDocument(_:)`), shows each beat with `show(document:view:)` (so annotations
    /// pass #31's one gate) and draws highlights with `.strong` emphasis.
    public private(set) var renderer: MGSolidRenderer?
    /// The annotation overlay record (labels, leaders, value texts, callouts) of the solid pane at the pose shown now;
    /// nil without annotations or before the pane has a size. It comes from `MGSolidAnnotations.frame`, through
    /// `checkedAnnotations`.
    @Published public private(set) var annotationFrame: MGAnnotationFrame?
    /// The framing of the solid pane for the presented beat: `MGExplainerFrame.solidClearView` for the beat's step
    /// (`MGExplainerSession.solidStep(forBeat:)`) at the pane's aspect, the same function the beat's still and its
    /// `story.mp4` hold frames use (per-step focus framing, the unblocked-focus rule with its automatic ghosts and
    /// alternate directions, every camera preset). The pane draws `paneView` from `clear.camera`. Nil without a solid.
    public private(set) var paneClear: MGSolidClearView?
    /// The view the solid pane draws: the beat's solid view with `paneClear`'s automatic ghosts, as in its still.
    public private(set) var paneView: MGSolidView?
    /// Grows by one each time the pane goes back to its framed camera: a new beat, a new solid, or a new pane aspect.
    /// The framed camera is the start pose of each beat; the learner may orbit and zoom from it (a document without
    /// annotations), and the next framing discards that orbit (`MartyGraphicsExplainerView` rebuilds its scene view
    /// for each key, which also drops a camera SceneKit's camera control switched to and its orbit pivot).
    @Published public private(set) var cameraReset = 0
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
    private var solidSize = CGSize.zero
    private var shownFingerprint: String?
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
        skipMotion = false; paneClear = nil; paneView = nil
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
            beatStart = nil; heldElapsed = nil; skipMotion = false; paneClear = nil; paneView = nil
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

    /// The solid pane's size changed: frame the camera for the new aspect (the framing reads only the aspect).
    public func setSolidAspect(_ a: Double) {
        guard a.isFinite, a > 0, abs(a - aspect) > 1e-3 else { return }
        aspect = a; frameCamera()
    }

    /// The solid pane's size in points: frames the camera and lays out the annotation overlay for it.
    public func setSolidSize(_ size: CGSize) {
        guard size.width > 0, size.height > 0, size != solidSize else { return }
        solidSize = size
        setSolidAspect(Double(size.width / size.height))
        applyPose()
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
        return session.presented.step?.poseParameters(defaults: d.defaults, spin: spinProgress(at: now)) ?? d.defaults
    }

    nonisolated func markBoardFrame() { boardFrame.hit(clock) }
    nonisolated func markSolidFrame() { solidFrame.hit(clock) }

    /// The framing of the presented beat in a pane of width over height `aspect`: `MGExplainerFrame.solidClearView`
    /// for the beat's step, and the view the pane draws (the beat's solid view with the automatic ghosts). The one
    /// function the beat's still and story hold frames use; nothing here computes a camera of its own.
    static func paneFraming(_ session: MGExplainerSession, aspect: Double) -> (clear: MGSolidClearView, view: MGSolidView)? {
        guard let d = session.solid else { return nil }
        let v = session.presented
        let clear = MGExplainerFrame.solidClearView(d, view: v, stepIndex: v.beat.flatMap { session.solidStep(forBeat: $0) }, aspect: aspect)
        return (clear, (v.solid ?? d.view(step: nil)).ghosting(clear.autoGhost))
    }

    /// Frames the pane for the presented beat at the pane's aspect: the beat's framed camera (a cut, as before; the
    /// story's camera moves are not played here) and its automatic ghosts. Each call is a camera reset.
    private func frameCamera() {
        guard let r = renderer, let d = session.solid, let f = Self.paneFraming(session, aspect: aspect) else { return }
        paneClear = f.clear
        if paneView != f.view || r.view != f.view {
            paneView = f.view
            r.show(document: d, view: f.view)
            // `show` restyles every part: the highlight goes back on.
            let v = session.presented
            r.highlight(Set(v.solidHighlight), dimOthers: !v.solidHighlight.isEmpty)
        }
        r.setCamera(f.clear.camera)
        cameraReset &+= 1
    }

    private func applyPose() {
        let pose = solidPose(at: clock.now)
        renderer?.apply(pose)
        if pose != solidParams { solidParams = pose }
        // The overlay is laid out at the pose shown, through the one gate (a view or pose not checked shows nothing).
        if let r = renderer, let d = session.solid, !d.annotations.isEmpty, solidSize.width > 0 {
            let v = session.presented
            annotationFrame = MGSolidAnnotations.frame(document: d, view: paneView ?? v.solid ?? d.view(step: nil), params: pose, camera: r.camera,
                                                       width: Double(solidSize.width), height: Double(solidSize.height),
                                                       previous: annotationFrame, highlight: v.solidHighlight)
        } else if annotationFrame != nil {
            annotationFrame = nil
        }
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
            let r = MGSolidRenderer(document: doc)
            r.emphasis = .strong
            renderer = r
            signposter.endInterval("solidCompile", interval)
            shownSolid = src; shownFingerprint = doc.checkedFingerprint; fresh = true
        } else if let r = renderer, let doc = session.solid, doc.checkedFingerprint != shownFingerprint {
            // The solid compiled again (a beat view added or dropped): the renderer loads that exact document, so its
            // views pass the one gate.
            r.setDocument(doc)
            shownFingerprint = doc.checkedFingerprint; fresh = true
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
        if let r = renderer, session.solid != nil {
            let v = session.presented
            if fresh || changed {
                r.apply(solidPose(at: clock.now))
                // The beat's view with its automatic ghosts and its framed camera (`frameCamera`).
                paneView = nil
                frameCamera()
            }
            // Also after a learner change, which can move the highlight (an id may stop resolving).
            r.highlight(Set(v.solidHighlight), dimOthers: !v.solidHighlight.isEmpty)
            r.highlightAnnotations(Set(v.annotations))
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
/// controls and the legend with its notes. The board pane follows the adaptive rule (`MGExplainerSession.boardPane`):
/// while the shown board has only text, the solid takes both panes' room and the board's text shows under the title.
/// The pane slides in and out (0.35 s); with Reduce Motion it changes at once. The solid pane shows each beat with
/// its still's framed camera and automatic ghosts (`MGExplainerController.paneClear`) and cuts to the next beat's
/// camera (no camera move, so no camera timing of its own).
public struct MartyGraphicsExplainerView: View {
    @ObservedObject private var controller: MGExplainerController
    @ObservedObject private var board: MGSceneController
    @Environment(\.mgTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let frameDelegate: MGExplainerSolidFrameDelegate

    /// How long the board pane takes to slide in or out (instant with Reduce Motion).
    public static let paneAnimationSeconds = 0.35

    public init(controller: MGExplainerController) {
        self.controller = controller; board = controller.board
        frameDelegate = MGExplainerSolidFrameDelegate(mark: controller.solidFrame, clock: controller.clock)
    }

    public var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width >= geo.size.height
            VStack(alignment: .leading, spacing: 12) {
                if let t = controller.session.title { Text(t).font(.title3.bold()).foregroundStyle(theme.ink) }
                if let line = controller.session.boardPane.line {
                    // The board's text while its pane is not drawn (the adaptive rule): it is not lost, it moves here.
                    Text(line).font(.subheadline.weight(.medium)).foregroundStyle(theme.subtleInk).lineLimit(1).truncationMode(.tail)
                        .transition(.opacity).accessibilityIdentifier("explainer.boardText")
                }
                panes(wide: wide)
                Text(controller.session.caption ?? " ").font(.title3).foregroundStyle(theme.ink)
                    .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("explainer.caption")
                ForEach(controller.controls) { c in slider(c) }
                legend
            }
            .padding(16)
            .animation(reduceMotion ? nil : .easeInOut(duration: Self.paneAnimationSeconds), value: controller.session.boardPane)
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
        // The adaptive rule: with a solid, the board pane shows only while the shown board has a non-text item.
        let showsBoard = s.board != nil && board.scene != nil && s.boardPane.shown
        let both = showsBoard && s.solid != nil
        let layout = wide ? AnyLayout(HStackLayout(spacing: Self.paneSpacing)) : AnyLayout(VStackLayout(spacing: Self.paneSpacing))
        GeometryReader { area in
        // Side by side with both panes, the board width fits its content (`MGExplainerFrame.boardShare`, the rule the
        // stills and story video use), drawn at its reference pane's scale; stacked, the primary view gets more room.
        let share = MGExplainerFrame.boardShare(scene: board.scene, areaWidth: area.size.width, areaHeight: area.size.height,
                                                gap: Self.paneSpacing, primarySolid: primaryIsSolid)
        let boardWidth = max(1, (area.size.width - Self.paneSpacing) * share)
        let fit = MGExplainerFrame.boardReferenceSize(areaWidth: area.size.width, areaHeight: area.size.height, gap: Self.paneSpacing,
                                                      primarySolid: primaryIsSolid)
        layout {
            if showsBoard {
                Group {
                    if wide && both {
                        boardPane(fit: fit).frame(width: boardWidth).frame(maxHeight: .infinity)
                    } else {
                        boardPane().frame(maxWidth: .infinity, maxHeight: .infinity).layoutPriority(both && !primaryIsSolid ? 1.2 : 1)
                    }
                }
                .transition(.move(edge: wide ? .leading : .top).combined(with: .opacity))
            }
            if s.solid != nil, let r = controller.renderer {
                GeometryReader { g in
                    // With annotations the camera stays the engine's, so the overlay's placement matches the picture.
                    // Without them the learner may orbit and zoom from the beat's framed camera; each new framing
                    // (`cameraReset`: a new beat, solid or pane aspect) builds a fresh scene view on the framed
                    // camera, so the learner's orbit, a camera SceneKit switched to and its orbit pivot are dropped.
                    let annotated = !(s.solid?.annotations.isEmpty ?? true)
                    SceneView(scene: r.scene, pointOfView: r.cameraNode, options: annotated ? [] : [.allowsCameraControl], delegate: frameDelegate)
                        .id(annotated ? 0 : controller.cameraReset)
                        .overlay {
                            if let f = controller.annotationFrame, let d = s.solid { MGSolidOverlayView(frame: f, document: d, legend: false).allowsHitTesting(false) }
                        }
                        .onAppear { controller.setSolidSize(g.size) }
                        .onChange(of: g.size) { _, size in controller.setSolidSize(size) }
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .frame(maxWidth: .infinity, maxHeight: .infinity).layoutPriority(both && primaryIsSolid ? 1.2 : 1)
                .accessibilityIdentifier("explainer.solid")
            }
        }
        }
    }

    /// Space between the board and solid panes (points).
    static let paneSpacing: CGFloat = 12

    private func boardPane(fit: CGSize? = nil) -> some View {
        let v = controller.session.presented
        return MartyGraphicsView(controller: board, showsControls: false, readOnly: true)
            .viewportFit(fit)
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
