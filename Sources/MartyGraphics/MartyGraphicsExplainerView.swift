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

/// SwiftUI adapter around `MGExplainerSession`: publishes both views, runs the pacing clock, writes signposts
/// (subsystem `MartyGraphics`, category `explainer`: `statement`, `beat`, `solidCompile`) and records TE1–TE6.
@MainActor
public final class MGExplainerController: ObservableObject {
    @Published public private(set) var session: MGExplainerSession
    @Published public private(set) var timing = MGExplainerRunTiming()
    /// The last refusal (developer reason; never show it to the learner).
    @Published public private(set) var lastIssue: MGExplainerIssue?
    /// Every event, in order (speech hook: speak `lineDue` text, then call `lineStarted` / `lineEnded`).
    public var onEvent: ((MGExplainerEvent) -> Void)?
    /// The SceneKit renderer of the solid pane (nil without a solid).
    public private(set) var renderer: MGSolidRenderer?
    public nonisolated let clock: MGLessonClock

    let boardFrame = MGFirstFrameMark(), solidFrame = MGFirstFrameMark()
    private var ticker: Task<Void, Never>?
    private var shownSolid: MGJSON?
    private let signposter = OSSignposter(subsystem: "MartyGraphics", category: "explainer")
    private var beatInterval: OSSignpostIntervalState?

    public init(pacing: MGPacing = .estimate(wordsPerSecond: 2.5), clock: MGLessonClock = MGSystemClock(), library: MGSolidLibrary = .builtIn) {
        session = MGExplainerSession(pacing: pacing, clock: clock, library: library); self.clock = clock
    }

    /// Start a new run: clears the session and marks the request time.
    public func begin() {
        ticker?.cancel()
        session = MGExplainerSession(pacing: session.pacing, clock: session.clock, library: session.library)
        timing = MGExplainerRunTiming(requestAt: clock.now)
        lastIssue = nil; renderer = nil; shownSolid = nil
        boardFrame.arm(); solidFrame.arm()
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
            ticker?.cancel()
            session = trial; lastIssue = nil; renderer = nil; shownSolid = nil
            if timing.requestAt == nil || timing.core.completeAt != nil { timing = MGExplainerRunTiming(requestAt: started) }
            boardFrame.arm(); solidFrame.arm()
            sync(events); return true
        case .failure(let issue): lastIssue = issue; return false
        }
    }

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
    public func finishNow() { sync(session.finishNow()) }
    public func pause() { session.pause(); sync([]) }
    public func resume() { sync(session.resume()) }
    public func next() {
        if session.isPaused { resume(); return }
        if let k = session.openLine { lineEnded(k) }
    }

    nonisolated func markBoardFrame() { boardFrame.hit(clock) }
    nonisolated func markSolidFrame() { solidFrame.hit(clock) }

    private func sync(_ events: [MGExplainerEvent]) {
        if let src = session.solidSource, src != shownSolid, let doc = session.solid {
            let interval = signposter.beginInterval("solidCompile", id: signposter.makeSignpostID())
            renderer = MGSolidRenderer(assembly: doc.assembly)
            signposter.endInterval("solidCompile", interval)
            shownSolid = src
        }
        if let r = renderer, let doc = session.solid {
            let v = session.presented
            r.show(v.solid ?? doc.view(step: nil))
            r.highlight(Set(v.solidHighlight), dimOthers: !v.solidHighlight.isEmpty)
            let spin = session.isPaused || session.pacing == .immediate ? 0 : (v.step?.spin ?? 0)
            r.apply(MGPoseParameters(input: doc.defaults.input + spin * 2 * .pi, explode: v.step?.explode ?? doc.defaults.explode))
        }
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

/// Two panes (the `primary` view larger: side by side when wide, stacked when narrow), the caption and the legend.
public struct MartyGraphicsExplainerView: View {
    @ObservedObject private var controller: MGExplainerController
    @Environment(\.mgTheme) private var theme

    public init(controller: MGExplainerController) { self.controller = controller }

    public var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width >= geo.size.height
            VStack(alignment: .leading, spacing: 12) {
                if let t = controller.session.title { Text(t).font(.title3.bold()).foregroundStyle(theme.ink) }
                panes(wide: wide, size: geo.size)
                Text(controller.session.caption ?? " ").font(.title3).foregroundStyle(theme.ink)
                    .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("explainer.caption")
                Text(controller.session.legend.text).font(.footnote.weight(.semibold)).foregroundStyle(theme.subtleInk)
                    .accessibilityIdentifier("explainer.legend")
            }
            .padding(16)
        }
        .background(theme.backgroundBottom)
    }

    @ViewBuilder private func panes(wide: Bool, size: CGSize) -> some View {
        let s = controller.session
        let primaryIsSolid = (s.primary ?? (s.solid != nil ? "solid" : "board")) == "solid"
        let both = s.board != nil && s.solid != nil
        let layout = wide ? AnyLayout(HStackLayout(spacing: 12)) : AnyLayout(VStackLayout(spacing: 12))
        layout {
            if s.board != nil, let scene = s.state?.scene {
                boardPane(scene).frame(maxWidth: .infinity, maxHeight: .infinity).layoutPriority(both && !primaryIsSolid ? 1.2 : 1)
            }
            if s.solid != nil, let r = controller.renderer {
                SceneView(scene: r.scene, pointOfView: r.cameraNode, options: [.allowsCameraControl])
                    .background(MGExplainerSolidProbe(controller: controller))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .frame(maxWidth: .infinity, maxHeight: .infinity).layoutPriority(both && primaryIsSolid ? 1.2 : 1)
                    .accessibilityIdentifier("explainer.solid")
            }
        }
    }

    private func boardPane(_ scene: MGScene) -> some View {
        let view = controller.session.presented
        let c = controller
        return Canvas { ctx, size in
            MGCanvasRenderer.draw(MGExplainerBoard.input(scene, view: view, size: size, theme: theme), in: ctx)
            c.markBoardFrame()
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityLabel(controller.session.caption ?? "Board")
        .accessibilityIdentifier("explainer.board")
    }
}

private struct MGExplainerSolidProbe: View {
    let controller: MGExplainerController
    var body: some View {
        let c = controller
        Canvas { _, _ in c.markSolidFrame() }.allowsHitTesting(false).accessibilityHidden(true)
    }
}
