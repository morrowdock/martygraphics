// SPDX-License-Identifier: Apache-2.0
import SwiftUI
import Combine
import os

/// Time marks of one lesson run on the session clock. Time to first visible and time to complete are separate numbers.
public struct MGLessonTiming: Equatable, Sendable {
    /// When the host started the request (`MGLessonController.begin()`).
    public var requestAt: Duration?
    /// Core: the first scene statement was presented (`firstPresented`).
    public var firstPresentedAt: Duration?
    /// View: the first Canvas frame that drew a lesson scene.
    public var firstFrameAt: Duration?
    public var streamEndedAt: Duration?
    public var lessonCompleteAt: Duration?

    public var timeToFirstVisible: Duration? { requestAt.flatMap { r in (firstFrameAt ?? firstPresentedAt).map { $0 - r } } }
    public var timeToStreamEnded: Duration? { requestAt.flatMap { r in streamEndedAt.map { $0 - r } } }
    public var timeToComplete: Duration? { requestAt.flatMap { r in lessonCompleteAt.map { $0 - r } } }
}

/// First-frame mark written from inside the Canvas draw closure (no SwiftUI state change during drawing).
final class MGFirstFrameMark: @unchecked Sendable {
    private let lock = NSLock()
    private var armed = false
    private var at: Duration?
    func arm() { lock.lock(); armed = true; at = nil; lock.unlock() }
    func hit(_ clock: MGLessonClock) { lock.lock(); if armed, at == nil { at = clock.now; armed = false }; lock.unlock() }
    var value: Duration? { lock.lock(); defer { lock.unlock() }; return at }
}

/// SwiftUI adapter around `MGLessonSession`: publishes the presented state to a board, runs the pacing clock, and turns
/// slider drags into learner commands. All lesson logic stays in the Foundation-only session.
@MainActor
public final class MGLessonController: ObservableObject {
    @Published public private(set) var session: MGLessonSession
    /// The board's scene controller (pass it to `MartyGraphicsView(controller:)` or use `MartyGraphicsLessonView`).
    public let board = MGSceneController()
    @Published public private(set) var timing = MGLessonTiming()
    /// The last refusal (developer reason; never show it to the learner).
    @Published public private(set) var lastIssue: MGLessonIssue?
    @Published public var selection: String?
    /// Every event, in order, as it happens (speech hook: speak `lineDue` text, then call `lineStarted` / `lineEnded`).
    public var onEvent: ((MGLessonEvent) -> Void)?

    let firstFrame = MGFirstFrameMark()
    /// The session clock (shared by every session this controller starts).
    public nonisolated let clock: MGLessonClock
    private var ticker: Task<Void, Never>?
    private var shownSerial = 0
    private let signposter = OSSignposter(subsystem: "MartyGraphics", category: "lesson")
    private var beatInterval: OSSignpostIntervalState?

    public init(pacing: MGPacing = .estimate(wordsPerSecond: 2.5), clock: MGLessonClock = MGSystemClock()) {
        session = MGLessonSession(pacing: pacing, clock: clock); self.clock = clock
    }

    public var state: MGLessonState? { session.state }
    public var caption: String? { session.caption }
    public var controls: [MGLessonControl] { session.state?.controls ?? [] }

    /// Start a new run: clears the session and marks the request time (time-to-first-visible starts here).
    public func begin() {
        ticker?.cancel()
        session = MGLessonSession(pacing: session.pacing, clock: session.clock)
        timing = MGLessonTiming(requestAt: session.clock.now)
        lastIssue = nil; shownSerial = 0; selection = nil
        firstFrame.arm()
        board.resumeTransitions()
        board.show(nil)
    }

    /// Feed streamed statement text (partial text is held until a statement completes).
    public func feed(_ chunk: String) {
        let id = signposter.makeSignpostID()
        let interval = signposter.beginInterval("statement", id: id)
        let events = session.feed(chunk)
        signposter.endInterval("statement", interval)
        sync(events)
    }

    public func endStream() { sync(session.endStream()) }

    /// Load a whole lesson document (all-or-nothing). Returns false and keeps the current lesson on refusal.
    @discardableResult public func load(_ lesson: MGLesson) -> Bool {
        if timing.requestAt == nil { begin() }
        let started = clock.now
        switch session.load(lesson) {
        case .success(let events):
            // A new session counts its changes from zero: always show its scene, and time this run on its own.
            shownSerial = -1
            board.resumeTransitions()
            if timing.firstPresentedAt != nil { timing = MGLessonTiming(requestAt: started); firstFrame.arm() }
            sync(events); return true
        case .failure(let issue): lastIssue = issue; return false
        }
    }

    /// A learner moved a bound control. The value is snapped to the control's step (UI quantisation only) and sent
    /// as the same `params` command a scripted beat would send.
    @discardableResult public func control(_ id: String, _ value: Double) -> Bool {
        guard let c = session.state?.control(id) else { return false }
        let snapped = min(c.max, max(c.min, c.min + ((value - c.min) / c.step).rounded() * c.step))
        if let current = session.state?.value(of: c), current == snapped { return true }
        let result = session.control(id, snapped)
        if case .failure(let issue) = result { lastIssue = issue }
        sync([])
        return (try? result.get()) != nil
    }

    /// Current value of a bound control (read from the scene source; there is no separate slider state).
    public func value(of control: MGLessonControl) -> Double { session.state?.value(of: control) ?? control.min }

    /// Apply a scripted command (debug field, host tools). Same path as a beat command.
    @discardableResult public func apply(_ command: MGJSON) -> Bool {
        switch session.apply(command, origin: .script) {
        case .success: sync([]); return true
        case .failure(let issue): lastIssue = issue; sync([]); return false
        }
    }

    public func lineStarted(_ k: Int) { sync(session.lineStarted(k)) }
    public func lineEnded(_ k: Int) { sync(session.lineEnded(k)) }
    public func finishNow() { board.resumeTransitions(); sync(session.finishNow()) }
    /// Pause the beat clock and hold an in-flight keyframe animation on the board.
    public func pause() { session.pause(); board.pauseTransitions(); sync([]) }
    public func resume() { board.resumeTransitions(); sync(session.resume()) }
    /// "Play beats" control: resume when paused, otherwise end the line being shown so the next beat comes.
    public func next() {
        if session.isPaused { resume(); return }
        if let k = session.openLine { lineEnded(k) }
    }

    public func describe(_ id: String) -> MGJSON? { session.describe(id) }

    /// Called from the board's draw closure through `MartyGraphicsLessonView`; records the first frame only.
    nonisolated func markFrame(_ clock: MGLessonClock) { firstFrame.hit(clock) }

    // MARK: private

    private func sync(_ events: [MGLessonEvent]) {
        if let change = session.lastChange, change.serial != shownSerial, let s = session.state {
            shownSerial = change.serial
            board.show(s.scene, transition: change.transition)
        }
        for e in events {
            switch e {
            case .firstPresented: if timing.firstPresentedAt == nil { timing.firstPresentedAt = session.history.last { $0.event == .firstPresented }?.at }
            case .streamEnded: timing.streamEndedAt = session.history.last { $0.event == .streamEnded }?.at
            case .lessonComplete: timing.lessonCompleteAt = session.history.last { $0.event == .lessonComplete }?.at
            case .refused(let issue): lastIssue = issue
            case .lineDue:
                if let b = beatInterval { signposter.endInterval("beat", b) }
                beatInterval = signposter.beginInterval("beat", id: signposter.makeSignpostID())
            default: break
            }
            onEvent?(e)
        }
        if session.isComplete, let b = beatInterval { signposter.endInterval("beat", b); beatInterval = nil }
        if let f = firstFrame.value, timing.firstFrameAt == nil { timing.firstFrameAt = f }
        schedule()
    }

    /// Wake the session at its next pacing time (estimate line ends, settle time).
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

/// Board + caption + bound sliders + a minimal "play beats" bar. iPad-first (side panel in regular width, stacked in
/// compact width); also macOS. Slider drags send the same `params` command as a scripted beat.
public struct MartyGraphicsLessonView: View {
    @ObservedObject private var controller: MGLessonController
    @ObservedObject private var board: MGSceneController
    @Environment(\.mgTheme) private var theme
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    @Environment(\.scenePhase) private var scenePhase
    private var showsPlayback = true

    public init(controller: MGLessonController) {
        self.controller = controller; board = controller.board
    }

    /// Hide the play / next / finish bar (for example when a host drives beats with its own voice).
    public func showsPlayback(_ on: Bool) -> Self { var v = self; v.showsPlayback = on; return v }

    private var wide: Bool {
        #if os(iOS)
        return sizeClass == .regular
        #else
        return true
        #endif
    }

    public var body: some View {
        Group {
            if wide {
                HStack(alignment: .top, spacing: 16) {
                    boardView.frame(maxWidth: .infinity)
                    panel.frame(width: 320)
                }
            } else {
                VStack(alignment: .leading, spacing: 12) { boardView; panel }
            }
        }
        .padding(16)
        .background(theme.backgroundBottom)
        .onChange(of: scenePhase) { _, phase in if phase != .active { controller.pause() } }
    }

    private var boardView: some View {
        ZStack {
            if board.scene != nil {
                MartyGraphicsView(controller: board, showsControls: false)
                    .selection($controller.selection)
                    .boardAccessibility(controller.caption)
                    .background(MGFrameProbe(controller: controller, revision: board.revision))
            } else {
                RoundedRectangle(cornerRadius: 22, style: .continuous).fill(theme.backgroundTop)
                    .aspectRatio(1.4, contentMode: .fit)
                    .overlay(ProgressView().tint(theme.ink))
            }
        }
        .accessibilityIdentifier("lesson.board")
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title = controller.session.title ?? board.scene?.title {
                Text(title).font(.title3.bold()).foregroundStyle(theme.ink)
            }
            Text(controller.caption ?? " ")
                .font(.title3).foregroundStyle(theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("lesson.caption")
                .animation(.easeInOut(duration: 0.25), value: controller.caption)
            ForEach(controller.controls) { c in slider(c) }
            if showsPlayback { playback }
            Spacer(minLength: 0)
        }
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
                .tint(theme.color(.accent))
                .accessibilityLabel(c.label)
                .accessibilityValue(c.unit == "°" ? "\(MGPhysics.format(value, unit: "")) degrees" : shown)
                .accessibilityIdentifier("lesson.slider.\(c.id)")
        }
    }

    private var playback: some View {
        HStack(spacing: 10) {
            button(controller.session.isPaused ? "play.fill" : "pause.fill", controller.session.isPaused ? "Play" : "Pause", id: "lesson.play") {
                controller.session.isPaused ? controller.resume() : controller.pause()
            }
            button("forward.fill", "Next beat", id: "lesson.next") { controller.next() }
                .disabled(controller.session.openLine == nil && !controller.session.isPaused)
            button("forward.end.fill", "Show all beats", id: "lesson.finish") { controller.finishNow() }
                .disabled(controller.session.isComplete)
        }
    }

    private func button(_ icon: String, _ label: String, id: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.body.weight(.semibold)).frame(width: 44, height: 44)
                .background(Circle().fill(Color.white.opacity(0.10))).foregroundStyle(theme.ink)
        }
        .buttonStyle(.plain).accessibilityLabel(label).accessibilityIdentifier(id)
    }
}

/// An invisible Canvas behind the board: its first draw after `begin()` is the first-frame mark (the board's own Canvas
/// draws in the same render pass).
private struct MGFrameProbe: View {
    let controller: MGLessonController
    /// Redraws on every board change, so a later run's first frame is also marked.
    let revision: Int
    var body: some View {
        let clock = controller.clock
        let _ = revision
        Canvas { _, _ in controller.markFrame(clock) }
            .allowsHitTesting(false).accessibilityHidden(true)
    }
}
