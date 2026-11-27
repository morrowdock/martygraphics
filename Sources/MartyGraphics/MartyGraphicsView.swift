// SPDX-License-Identifier: Apache-2.0
import SwiftUI
import Combine

/// Owns the current scene. Patches and streams go through here so every change is validated and blended, never torn.
@MainActor
public final class MGSceneController: ObservableObject {
    @Published public private(set) var scene: MGScene?
    @Published public private(set) var isStreaming = false
    /// Bumps on every accepted change (new scene, patch, stream preview) so views can blend from what was on screen.
    @Published public private(set) var revision = 0
    /// True when the last patch or stream was refused and the previous scene stayed.
    @Published public private(set) var lastUpdateFailed = false
    /// How the board moves to the current scene. `.blend` for every existing entry point; `.direct` (follow a finger)
    /// and `.keyframes` (engine in-betweens) only when a caller asks for them.
    @Published public private(set) var transition: MGTransition = .blend
    /// True while transitions are held (a paused lesson): an in-flight keyframe animation stops where it is and
    /// continues from there on resume. Default false; only callers of `pauseTransitions()` change it.
    @Published public private(set) var transitionsPaused = false
    /// False after `show(_:transition:drawsOn: false)`: the board shows the scene as it is, with no draw-on (also on a
    /// first appearance). Every other entry point sets it back to true (existing behaviour).
    @Published public private(set) var drawsOn = true
    private var stream: MGStreamParser?
    private var beforeStream: MGScene?
    /// Scene revisions handed out by this controller only ever increase, so a replacement scene never reuses the
    /// revision of the scene it replaced and an old patch can never match it.
    public private(set) var nextSceneRevision = 0
    /// The visible items of the steps its boards show, kept between frames (`MGTimelineCache`: the last 4 steps read,
    /// so boards sharing this controller on different steps do not evict each other). Every scene this controller
    /// holds carries a revision it never reuses (`stamped`), so the cache key names one scene.
    let timeline = MGTimelineCache()

    public init(scene: MGScene? = nil) { self.scene = scene.map(stamped) }

    /// `MGTimeline.items(scene, step:)` for a scene this controller holds, computed once per (revision, step) while
    /// that step stays among the last `MGTimelineCache.capacity` steps read.
    func timelineItems(_ scene: MGScene, step: Int) -> [MGItem] { timeline.items(scene, step: step) }

    /// The time base of the board's transitions (keyframes, blends, draw-on, motion). nil (the default) keeps the wall
    /// clock (`Date()`), as before. A lesson or explainer host sets its session's monotonic clock here, so the frame the
    /// board draws and the session's settle time come from ONE clock: a wall-clock jump can never show an earlier
    /// frame while the session already says the board has settled.
    public var presentationClock: MGLessonClock?
    /// The wall clock (tests replace it to model a jump).
    var wallClock: () -> Date = { Date() }

    /// Now on the board's time base: the presentation clock as a date (only differences are used), else the wall clock.
    public func presentationDate() -> Date {
        guard let c = presentationClock else { return wallClock() }
        let d = c.now
        return Date(timeIntervalSinceReferenceDate: Double(d.components.seconds) + Double(d.components.attoseconds) * 1e-18)
    }

    private func stamped(_ s: MGScene) -> MGScene { var s = s; s.revision = nextSceneRevision; nextSceneRevision += 1; return s }

    public func show(_ scene: MGScene?) { show(scene, transition: .blend) }
    /// Show a scene with an explicit transition (lesson sessions: `.direct` for learner controls, `.keyframes` for
    /// `animate`). `show(_:)` is `show(_:transition: .blend)`.
    public func show(_ scene: MGScene?, transition: MGTransition) { show(scene, transition: transition, drawsOn: true) }
    /// `drawsOn: false` shows the scene with no draw-on for any id, also when the board appears for the first time
    /// (a restored lesson: the learner already saw these marks). With `.direct` there is also no blend and no keyframes.
    public func show(_ scene: MGScene?, transition: MGTransition, drawsOn: Bool) {
        self.transition = transition; self.drawsOn = drawsOn; self.scene = scene.map(stamped); lastUpdateFailed = false; revision &+= 1
    }

    /// Applies a follow-up patch to the current scene. Returns false and keeps the scene if it doesn't validate.
    /// `requireRevision`: refuse patches that don't name the revision they were written against (model-sent patches).
    @discardableResult public func apply(patch: MGPatch, requireRevision: Bool = false) -> Bool {
        apply(patch: patch, requireRevision: requireRevision, transition: .blend)
    }
    /// `apply(patch:requireRevision:)` with an explicit transition; `.direct` adopts without blend or draw-on replay.
    @discardableResult public func apply(patch: MGPatch, requireRevision: Bool = false, transition: MGTransition) -> Bool {
        guard let scene, !requireRevision || patch.baseRevision != nil,
              case .success(let next) = scene.applying(patch) else { lastUpdateFailed = true; return false }
        self.transition = transition; drawsOn = true; self.scene = stamped(next); lastUpdateFailed = false; revision &+= 1; return true
    }
    @discardableResult public func apply(patchObject: Any) -> Bool {
        guard case .success(let p) = MGPatch.parse(object: patchObject) else { lastUpdateFailed = true; return false }
        return apply(patch: p)
    }

    /// Hold the current keyframe animation (lesson pause). `resumeTransitions()` continues it from the same frame.
    public func pauseTransitions() { if !transitionsPaused { transitionsPaused = true } }
    public func resumeTransitions() { if transitionsPaused { transitionsPaused = false } }

    // MARK: streaming

    /// Start a stream. Restarting an active stream discards its preview and restores the last committed scene.
    public func beginStream() {
        if stream == nil {
            beforeStream = scene
        } else if scene != beforeStream {
            transition = .blend
            drawsOn = true
            scene = beforeStream
            revision &+= 1
        }
        stream = MGStreamParser()
        isStreaming = true
    }
    public func feed(_ chunk: String) {
        guard var s = stream else { return }
        if let preview = s.feed(chunk) { transition = .blend; drawsOn = true; scene = stamped(preview); revision &+= 1 }
        stream = s
    }
    /// Strict final parse. On failure the scene from before the stream comes back (fail safe).
    @discardableResult public func endStream() -> Bool {
        defer { stream = nil; beforeStream = nil; isStreaming = false }
        guard let s = stream else { return false }
        switch s.finish() {
        case .success(let final): transition = .blend; drawsOn = true; scene = stamped(final); lastUpdateFailed = false; revision &+= 1; return true
        case .failure: transition = .blend; drawsOn = true; scene = beforeStream; lastUpdateFailed = true; revision &+= 1; return false
        }
    }
}

/// Public entry point: `MartyGraphicsView(scene:)` or `MartyGraphicsView(controller:)` for live patches/streams.
/// A scene with learner `sliders` shows them under the board when the view shows its controls and is not read-only
/// (`MGSliderState`; docs/PROTOCOL.md, "Learner sliders").
public struct MartyGraphicsView: View {
    @StateObject private var own: MGSceneController
    private let external: MGSceneController?
    private let initial: MGScene?
    private let showsControls: Bool
    private let readOnly: Bool
    /// The teaching hooks the modifiers set (internal read for tests).
    private(set) var teaching = MGBoardTeaching()

    /// `readOnly`: presentation only (e.g. submitted exam work). The finished walkthrough is shown with no step,
    /// play or replay controls and no element interaction. Animation still plays unless Reduce Motion is on.
    public init(scene: MGScene, showsControls: Bool = true, readOnly: Bool = false) {
        _own = StateObject(wrappedValue: MGSceneController(scene: scene)); external = nil; initial = scene
        self.showsControls = showsControls; self.readOnly = readOnly
    }
    public init(controller: MGSceneController, showsControls: Bool = true, readOnly: Bool = false) {
        _own = StateObject(wrappedValue: MGSceneController()); external = controller; initial = nil
        self.showsControls = showsControls; self.readOnly = readOnly
    }
    /// Tap the board to select a semantic object (only ids in `markers`, when markers are set). Ignored when read-only.
    /// 2D only unless the host opts in with `inspects3D([.selection])`.
    public func selection(_ id: Binding<String?>) -> Self { var v = self; v.teaching.selection = id; return v }
    /// Items to point at with a glow ring (the selection is always included).
    /// 2D only unless the host opts in with `inspects3D([.emphasis])` and/or `[.dimming]`.
    public func emphasis(_ ids: Set<String>) -> Self { var v = self; v.teaching.emphasis = ids; return v }
    /// 2D: emphasise table rows (0-based, header included) and cells (row × columns + column), by table id.
    public func tableEmphasis(rows: [String: Set<Int>], cells: [String: Set<Int>] = [:]) -> Self {
        var v = self; v.teaching.tableRows = rows; v.teaching.tableCells = cells; return v
    }
    /// Numbered markers (item id → n) that match an object list beside the board.
    public func markers(_ markers: [String: Int]) -> Self { var v = self; v.teaching.markers = markers; return v }
    /// Finite motion: play `loops` cycles, then rest on the last frame (Replay plays again). nil keeps looping.
    public func motionLoops(_ loops: Int?) -> Self { var v = self; v.teaching.loops = loops.map { max(1, $0) }; return v }
    /// VoiceOver value for the board (e.g. a teaching summary); defaults to the current step's narration followed by
    /// the step's (or else the scene's) `alt` text when the scene has one.
    public func boardAccessibility(_ summary: String?) -> Self { var v = self; v.teaching.summary = summary; return v }
    /// VoiceOver: when neither the current step nor the scene has `alt` text, read the engine's description of the
    /// visible board (`MGDescribe.board`) after the narration. Concealed items are never described. Off by default.
    public func describesBoard(_ on: Bool = true) -> Self { var v = self; v.teaching.describes = on; return v }
    /// 2D: fit the board's viewport for `size` instead of the view's own size, keeping that scale and centre (the
    /// explainer's narrowed board pane uses its reference pane, `MGExplainerFrame.boardReferenceSize`). Nil: own size.
    public func viewportFit(_ size: CGSize?) -> Self { var v = self; v.teaching.fitSize = size; return v }
    /// Items not drawn and not tappable (values hidden until the host reveals them, e.g. during independent practice).
    public func concealed(_ ids: Set<String>) -> Self { var v = self; v.teaching.concealed = ids; return v }
    /// 3D only: keep the learner's orbit and zoom across updates of the same scene (patches, parameter changes,
    /// streams). The scene camera is applied when the board first appears; when the scene's own camera, world size or
    /// identity (template and title) changes; and whenever `resetKey` changes (e.g. a Reset button increments it).
    /// Applying it also re-centres the built-in camera controller's orbit pivot and stops its inertia.
    /// Without this modifier every 3D rebuild returns to the scene camera, as before.
    public func preserves3DCamera(resetKey: Int) -> Self { var v = self; v.teaching.cameraReset = resetKey; return v }
    /// 3D only, opt-in: let the existing `selection`, `markers` and `emphasis` modifiers act on a 3D board.
    /// Without this modifier a 3D board ignores them exactly as before. See `MG3DInspection` for each option.
    public func inspects3D(_ options: MG3DInspection) -> Self { var v = self; v.teaching.inspection3D = options; return v }
    /// 2D: how the board moves between steps and patches. `.spring` (the default, the board as it always was): blends
    /// and camera moves follow the board's spring, leaving items vanish, and with Reduce Motion the board snaps with
    /// no transition. `.bounded` (opt-in): bounded easing with no overshoot, fading exits, pops that land on their size,
    /// and with Reduce Motion a dissolve with no motion (`MGTransitionStyle`, `MGStepTransition`).
    public func transitionStyle(_ style: MGTransitionStyle) -> Self { var v = self; v.teaching.transitionStyle = style; return v }
    /// Test seam (internal): record what the 2D board decides and draws, and expose its own handlers (`MGBoardProbe`).
    func boardProbe(_ probe: MGBoardProbe?) -> Self { var v = self; v.teaching.probe = probe; return v }
    /// Test seam (internal): use this Reduce Motion setting instead of the system's (nil: the system's).
    func boardReduceMotion(_ on: Bool?) -> Self { var v = self; v.teaching.reduceMotion = on; return v }

    public var body: some View {
        MGSceneHost(controller: external ?? own, showsControls: showsControls, readOnly: readOnly, teaching: teaching)
            .onChange(of: initial) { _, next in if external == nil, let next { own.show(next) } }
    }
}

/// Opt-in 3D teaching hooks for `MartyGraphicsView.inspects3D(_:)`. Each option reuses an existing modifier;
/// none of them changes 2D boards.
public struct MG3DInspection: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    /// Board taps go to the `selection` binding (ignored when read-only). SceneKit hit tests probe the tap point and
    /// two rings within the same 12-pt slop as 2D; the nearest hit of the earliest probe wins (2D instead picks the
    /// smallest footprint). Only `markers` ids are selectable when markers are set. As in 2D, highlights, axes and
    /// ground lines are never selected. Numbered marker badges are not drawn in 3D.
    public static let selection = MG3DInspection(rawValue: 1 << 0)
    /// `emphasis` items (and the current selection) glow brighter; nothing else changes. A highlight halo glows
    /// with its target.
    public static let emphasis = MG3DInspection(rawValue: 1 << 1)
    /// While something drawn is emphasised, every other item except the axes is dimmed (a highlight dims with its target).
    /// 3D only: 2D emphasis never dims.
    public static let dimming = MG3DInspection(rawValue: 1 << 2)
}

/// Teaching hooks carried from MartyGraphicsView into the host.
struct MGBoardTeaching {
    var selection: Binding<String?>?
    var emphasis: Set<String> = []
    /// Emphasised table rows and cells by table id (`MGRenderInput.tableRows` / `tableCells`).
    var tableRows: [String: Set<Int>] = [:]
    var tableCells: [String: Set<Int>] = [:]
    var markers: [String: Int] = [:]
    var loops: Int?
    var summary: String?
    /// Read `MGDescribe.board` when no `alt` text is authored (`describesBoard`).
    var describes = false
    var concealed: Set<String> = []
    /// 2D: the size the viewport is fitted for (nil: the view's own size); the view keeps that scale and centre.
    var fitSize: CGSize?
    /// Non-nil: 3D camera keep/reset key (`preserves3DCamera`).
    var cameraReset: Int?
    /// Opt-in 3D hooks (`inspects3D`); empty keeps the original 3D behaviour.
    var inspection3D: MG3DInspection = []
    /// 2D step and patch transitions (`transitionStyle`); `.spring` keeps the board as it was.
    var transitionStyle: MGTransitionStyle = .spring
    /// Test seams (internal, never set by a host): a probe of the 2D board, and a Reduce Motion override.
    var probe: MGBoardProbe?
    var reduceMotion: Bool?
    /// Motion stays on its first frame while anything is concealed (it can show the answer), then plays from the start.
    var holdsMotion: Bool { !concealed.isEmpty }
}

/// Test seam (internal; a host never sets one, `MartyGraphicsView.boardProbe(_:)`): what a 2D board decided and drew,
/// and the board's own frame function, tap handler and step handler from its latest evaluation, so a test drives the
/// real board through its entry points in a window. Main thread only.
final class MGBoardProbe {
    struct Draw {
        let input: MGRenderInput
        let layer: MGCanvasLayer
        let size: CGSize
    }
    struct Decision: Equatable {
        /// The frame loop runs (the TimelineView is not paused).
        let running: Bool
        /// The board draws a cached base canvas under a live one.
        let layered: Bool
    }
    /// Every Canvas draw, in order: the one canvas, or a layered board's base and live canvases.
    private(set) var draws: [Draw] = []
    /// The frame-loop decision of every evaluation of the board.
    private(set) var decisions: [Decision] = []
    /// The frame the board's Canvas draws at a time and size (`MGSceneHost.input`).
    var frame: ((Date, CGSize) -> MGRenderInput)?
    /// The board's tap handler (what its `SpatialTapGesture` calls), at a point in a board of a size.
    var tap: ((CGPoint, CGSize) -> Void)?
    /// The board's step handler (what its Previous and Next buttons call).
    var go: ((Int) -> Void)?
    /// The board's learner slider handlers: move a slider to the stop nearest a value (what the slider's binding calls)
    /// and reset every slider (the Reset sliders button). They do nothing on a board that shows no sliders.
    var slide: ((String, Double) -> Void)?
    var resetSliders: (() -> Void)?
    /// The audio graph of every evaluation of the board (`MGAudioGraph.chart` of the items it charts), in order.
    private(set) var charts: [MGAudioGraph.Chart?] = []

    func drew(_ input: MGRenderInput, _ layer: MGCanvasLayer, _ size: CGSize) { draws.append(Draw(input: input, layer: layer, size: size)) }
    func decided(_ d: Decision) { decisions.append(d) }
    func charted(_ chart: MGAudioGraph.Chart?) { charts.append(chart) }
    /// Draws of the cached base canvas.
    var baseDraws: Int { draws.filter { if case .base = $0.layer { return true }; return false }.count }
    /// Draws of the one canvas or of the live canvas (one per frame-loop tick while the loop runs).
    var liveDraws: Int { draws.count - baseDraws }
}

struct MGSceneHost: View {
    @ObservedObject var controller: MGSceneController
    let showsControls: Bool
    var readOnly = false
    var teaching = MGBoardTeaching()
    @Environment(\.mgTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    /// The system's Reduce Motion setting (a test may override it, `MGBoardTeaching.reduceMotion`).
    private var reduceMotion: Bool { teaching.reduceMotion ?? systemReduceMotion }
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var step = 0
    /// Learner sliders (wire `sliders`): their positions and the items they give. Nil for a scene without sliders and
    /// whenever the host hides the controls or the board is read-only, so such a board draws exactly as before.
    @State private var sliderState: MGSliderState?
    @State private var playing = true
    @State private var epoch = Date()   // replaced on appear (`adopt`) by the board's time base
    @State private var pausedAt: Double = 0
    @State private var appearStart: [String: Date] = [:]
    /// Engine keyframe segments being played (on a clock that a lesson pause can hold) and the blend from what was on
    /// screen. A slider change settles both (`changeSliders`).
    @State private var motion = MGBoardMotion()
    @State private var cameraFrom: MGCamera?
    @State private var cameraStart = Date.distantPast
    @State private var shownScene: MGScene?
    @State private var heldAt: Date?
    // Render gating: the frame loop runs only for real motion or a short transition on a visible board.
    @Environment(\.scenePhase) private var scenePhase
    @State private var visible = false
    @State private var transientUntil = Date.distantPast
    @State private var transientToken = 0
    /// Bumped by the live canvas when a tick finds the board's transitions past the phase it was split for
    /// (`MGBoardTransition.phase`), so the board is evaluated once more and splits for the new phase.
    @State private var repartitions = 0

    private func renderState(_ scene: MGScene) -> MGRenderPolicy.State {
        .init(motionPlaying: playing && scene.animates && !teaching.holdsMotion, transientActive: controller.presentationDate() < transientUntil,
              visible: visible, sceneActive: scenePhase == .active, reduceMotion: reduceMotion)
    }
    /// Keep the 2D loop alive just long enough for a transition, then settle on a final static frame.
    private func bumpTransient(_ seconds: Double = MGRenderPolicy.transientSeconds) {
        transientUntil = max(transientUntil, controller.presentationDate().addingTimeInterval(seconds)); transientToken &+= 1
    }
    /// End the transition window at `end` (board clock) when that is earlier, and wait for the new end instead of the
    /// old one (the window's task restarts), so the board is evaluated again as soon as the window ends.
    private func endTransient(by end: Date) {
        guard end < transientUntil else { return }
        transientUntil = end; transientToken &+= 1
    }

    var body: some View {
        if let scene = controller.scene {
            VStack(alignment: .leading, spacing: 12) {
                header(scene)
                board(scene)
                if let state = sliders(scene), !state.sliders(hiding: teaching.concealed).isEmpty { sliderPanel(state) }
                if showsControls, !scene.steps.isEmpty { caption(scene) }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(theme.backgroundBottom))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
            .onAppear { visible = true; adopt(scene, animated: false, drawsOn: controller.drawsOn) }
            .onDisappear { visible = false }
            .task(id: transientToken) {
                let wait = max(0, transientUntil.timeIntervalSince(controller.presentationDate()))
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                if !Task.isCancelled { transientUntil = .distantPast }   // state change → one settled redraw, loop paused
            }
            .onChange(of: controller.revision) { _, _ in if let s = controller.scene { adopt(s, animated: true, transition: controller.transition, drawsOn: controller.drawsOn) } }
            .onChange(of: controller.transitionsPaused) { _, paused in holdTransitions(paused) }
            .onChange(of: teaching.holdsMotion) { _, held in
                if !held { epoch = controller.presentationDate(); pausedAt = 0; playing = true }   // revealed: play the motion from its start
                bumpTransient()
            }
            .onChange(of: teaching.emphasis.union(teaching.selection?.wrappedValue.map { [$0] } ?? [])) { _, _ in bumpTransient() }
            .onChange(of: teaching.tableRows) { _, _ in bumpTransient() }
            .onChange(of: teaching.tableCells) { _, _ in bumpTransient() }
            .task(id: LoopKey(epoch: epoch, playing: playing && !teaching.holdsMotion, loops: teaching.loops, revision: controller.revision)) { await finishLoops(scene) }
        }
    }

    // MARK: pieces

    private func header(_ scene: MGScene) -> some View {
        HStack(spacing: 8) {
            Image(systemName: scene.is3D ? "cube.transparent" : "sparkles").foregroundStyle(theme.color(.accent))
            Text(scene.title.isEmpty ? "Marty's sketch" : scene.title).font(.headline).foregroundStyle(theme.ink)
            Spacer(minLength: 0)
            if controller.isStreaming { ProgressView().controlSize(.small).tint(theme.ink) }
        }
    }

    private func board(_ scene: MGScene) -> some View {
        // VoiceOver audio graph of the visible plot, func or bars items (none otherwise; concealed items never count),
        // built from the items the board draws now: with the learner's slider values when the scene shows sliders.
        let chart = MGAudioGraph.chart(scene, items: boardItems(scene, step: step), hiding: teaching.concealed)
        teaching.probe?.charted(chart)
        return Group {
            if scene.is3D && teaching.concealed.isEmpty {
                MG3DView(scene: scene, items: controller.timelineItems(scene, step: step), playing: MGRenderPolicy.sceneKitPlaying(renderState(scene)),
                         teaching: teaching, readOnly: readOnly)
                    .overlay(alignment: .bottomTrailing) {
                        Label("Drag to turn", systemImage: "hand.draw").font(.caption2).foregroundStyle(theme.subtleInk).padding(8)
                    }
            } else {
                board2D(scene)
            }
        }
        .aspectRatio(scene.width / scene.height, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement()
        .accessibilityLabel(scene.title.isEmpty ? "Marty's sketch" : scene.title)
        // At the slider defaults the value is the authored one, read from the cached step items like the board.
        .accessibilityValue(teaching.summary
                            ?? sliders(scene).flatMap { $0.isAtDefaults ? nil : $0.accessibilityValue(describing: teaching.describes, hiding: teaching.concealed) }
                            ?? MGDescribe.accessibilityValue(scene, step: step, describing: teaching.describes,
                                                       hiding: teaching.concealed) { controller.timelineItems(scene, step: step) })
        .modifier(MGAudioGraphModifier(chart: chart))
    }

    /// The 2D board: one Canvas in a TimelineView, or, while motion plays and no transition runs, a cached base Canvas
    /// under a live one (`MGRenderPolicy.layered`, `MGCanvasLayers`). The two layers composite to the frame one Canvas
    /// draws; the base (board, grid and the static items below every moving item) is drawn once, outside the timeline.
    /// The split also follows the board's own clock (`MGBoardTransition.phase`): while a blend, a camera move or
    /// keyframes still change the frame there is one canvas, and the base is chosen for the phase now. When a tick
    /// finds that phase over (the blend or the last draw-on has ended), the board splits once more for the new one.
    private func board2D(_ scene: MGScene) -> some View {
        let state = renderState(scene)
        // Reduce Motion: a `.spring` board snaps (no loop); a `.bounded` board dissolves, so the loop runs for that
        // transition only (`MGBoardTransition.runsLoop`).
        let running = MGBoardTransition.runsLoop(teaching.transitionStyle, state)
        _ = repartitions   // read, so that a repartition asked for by the live canvas evaluates the board again
        let now = controller.presentationDate()
        let splits = MGRenderPolicy.layered(state) && scene.layer2d == nil
        let phase = transitionPhase(at: now)
        let layered = splits && phase != .moving
        if let probe = teaching.probe {
            probe.decided(MGBoardProbe.Decision(running: running, layered: layered))
            probe.frame = { now, size in input(scene, now: now, size: size) }
            probe.tap = { point, size in select(scene, at: point, size: size) }
            probe.go = { next in go(scene, next) }
            probe.slide = { param, value in changeSliders { $0.set(param, nearest: value) } }
            probe.resetSliders = { changeSliders { $0.reset(); return true } }
        }
        return GeometryReader { geo in
            ZStack {
                if layered {
                    layeredCanvases(scene, size: geo.size, running: running, now: now, phase: phase)
                } else {
                    liveCanvas(scene, running: running, layer: nil, watching: splits ? phase : nil)
                }
            }
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture().onEnded { value in select(scene, at: value.location, size: geo.size) },
                     including: teaching.selection != nil && !readOnly ? .all : .none)
        }
    }

    @ViewBuilder private func layeredCanvases(_ scene: MGScene, size: CGSize, running: Bool, now: Date, phase: MGBoardTransition.Phase) -> some View {
        let still = input(scene, now: now, size: size)
        // Items still drawing on or fading are live too: ticks never redraw the base (`MGCanvasLayers.settling`).
        let live = MGCanvasLayers.live(scene, items: still.items).union(MGCanvasLayers.settling(appear: still.appear, opacity: still.opacity))
        let base = MGCanvasLayers.base(still.items, live: live)
        Canvas(rendersAsynchronously: false) { ctx, size in
            // The base frame at this evaluation's time for the canvas's own size, as the live canvas draws for its own
            // size, so both layers always draw with one viewport (the reader's size is used only to choose the items).
            let frame = input(scene, now: now, size: size)
            MGCanvasRenderer.draw(frame, in: ctx, layer: .base(base))
            teaching.probe?.drew(frame, .base(base), size)
        }
        liveCanvas(scene, running: running, layer: .live(base), watching: phase)
    }

    /// `watching`: the phase of the board's transitions that the board was split for, or would have been but for a
    /// blend or camera move (nil: the board cannot split now). When a tick finds another phase on the board's clock,
    /// the canvas asks for one more evaluation of the board (`repartitions`), so it splits for the new phase: one base
    /// redraw when the last draw-on ends, and the first split once a blend or camera move has ended.
    private func liveCanvas(_ scene: MGScene, running: Bool, layer: MGCanvasLayer?, watching: MGBoardTransition.Phase?) -> some View {
        TimelineView(.animation(minimumInterval: MGRenderPolicy.frameInterval, paused: !running)) { tl in
            Canvas(rendersAsynchronously: false) { ctx, size in
                let frame = input(scene, now: running && controller.presentationClock == nil ? tl.date : controller.presentationDate(), size: size)
                MGCanvasRenderer.draw(frame, in: ctx, layer: layer ?? .all)
                teaching.probe?.drew(frame, layer ?? .all, size)
            }
            .onChange(of: watching.map { _ in transitionPhase(at: controller.presentationDate()) }, initial: true) { _, current in
                if let watching, let current, current != watching { repartitions &+= 1 }
            }
        }
    }

    // MARK: teaching hooks

    /// Tap → the smallest selectable footprint under the finger (12 pt slop); empty space clears the selection.
    private func select(_ scene: MGScene, at point: CGPoint, size: CGSize) {
        guard let binding = teaching.selection else { return }
        // Use the drawing's frame calculation, including in-flight item and camera blends.
        let frame = input(scene, now: controller.presentationDate(), size: size)
        let selectable = teaching.markers.isEmpty ? nil : Set(teaching.markers.keys)
        binding.wrappedValue = frame.hit(point, among: selectable)?.id
    }

    struct LoopKey: Hashable { let epoch: Date; let playing: Bool; let loops: Int?; let revision: Int }

    /// Finite motion: after `loops` cycles, rest on the end of the last cycle (not snapped back to the start).
    private func finishLoops(_ scene: MGScene) async {
        guard let loops = scene.layer2d == nil ? teaching.loops : 1, playing, !teaching.holdsMotion, scene.animates, let cycle = MGTimeline.cycle(scene) else { return }
        let end = cycle * Double(loops)
        let remaining = end - controller.presentationDate().timeIntervalSince(epoch)
        if remaining > 0 { try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000)) }
        guard !Task.isCancelled, playing else { return }
        pausedAt = MGTimeline.restTime(scene, loops: loops) ?? end; playing = false; bumpTransient()
    }

    private func caption(_ scene: MGScene) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(scene.steps[min(step, scene.steps.count - 1)].say)
                .font(.body).foregroundStyle(theme.ink).fixedSize(horizontal: false, vertical: true)
                .id(step).transition(.opacity.combined(with: .move(edge: .bottom)))
            HStack(spacing: 6) {
                ForEach(scene.steps.indices, id: \.self) { i in
                    Capsule().fill(i == step ? theme.color(.accent) : theme.subtleInk.opacity(0.35))
                        .frame(width: i == step ? 22 : 8, height: 8)
                }
                Spacer(minLength: 8)
                if !readOnly {
                control("chevron.left", "Previous step", enabled: step > 0) { go(scene, step - 1) }
                if scene.animates && !reduceMotion && !teaching.holdsMotion {
                    control(playing ? "pause.fill" : "play.fill", playing ? "Pause" : "Play", enabled: true) { togglePlay() }
                    control("arrow.counterclockwise", "Replay", enabled: true) { epoch = controller.presentationDate(); pausedAt = 0; playing = true; bumpTransient() }
                }
                control("chevron.right", "Next step", enabled: step < scene.steps.count - 1) { go(scene, step + 1) }
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: step)
    }

    private func control(_ icon: String, _ label: String, enabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.body.weight(.semibold)).frame(width: 44, height: 44)
                .background(Circle().fill(Color.white.opacity(enabled ? 0.10 : 0.04)))
                .foregroundStyle(enabled ? theme.ink : theme.subtleInk.opacity(0.5))
        }
        .buttonStyle(.plain).disabled(!enabled).accessibilityLabel(label)
    }

    // MARK: learner sliders

    /// The slider state for `scene` at the current step, or nil when the scene shows no sliders.
    private func sliders(_ scene: MGScene) -> MGSliderState? {
        guard let s = sliderState, s.scene.revision == scene.revision, s.step == step else { return nil }
        return s
    }

    /// The items at `step`, for the canvas and the audio graph alike: the learner's items once a slider sits at an
    /// accepted non-default value, else `MGTimeline.items` through the controller's cache (also at the defaults), so a
    /// frame never recomputes them (`MGSliderState.boardItems`).
    private func boardItems(_ scene: MGScene, step: Int) -> [MGItem] {
        MGSliderState.boardItems(scene, step: step, sliders: sliderState, cache: controller.timeline)
    }

    /// One row per slider that drives a graph on the board now, the engine's readout of the driven graphs, a note when
    /// the engine refused a position, and a reset button. Text uses Dynamic Type styles and wraps.
    private func sliderPanel(_ state: MGSliderState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(state.sliders(hiding: teaching.concealed)) { s in sliderRow(s, state) }
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(state.caption(hiding: teaching.concealed).enumerated()), id: \.offset) { _, line in
                        Text(line).font(.callout.monospacedDigit()).foregroundStyle(theme.subtleInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let note = state.refusal?.text {
                        Text(note).font(.callout).foregroundStyle(theme.color(.warn))
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("board.slider.note")
                    }
                }
                Spacer(minLength: 0)
                control("arrow.uturn.backward", "Reset sliders", enabled: !state.isAtDefaults) { changeSliders { $0.reset(); return true } }
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// The label and the current value above a native slider. VoiceOver reads the slider itself (label, value, hint)
    /// and adjusts it one step per swipe, past any position the engine refuses; the text above it is not read twice.
    private func sliderRow(_ s: MGSlider, _ state: MGSliderState) -> some View {
        let a11y = state.accessibility(s.param)
        let name = Text(s.label).font(.subheadline.weight(.semibold)).foregroundStyle(theme.ink)
        let shown = Text(a11y?.value ?? "").font(.subheadline.monospacedDigit()).foregroundStyle(theme.color(.accent))
        return VStack(alignment: .leading, spacing: 4) {
            Group {
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 2) { name; shown }
                } else {
                    HStack { name; Spacer(minLength: 8); shown }
                }
            }
            .accessibilityHidden(true)
            Slider(value: Binding(get: { sliderState?.value(s.param) ?? s.defaultValue },
                                  set: { v in changeSliders { $0.set(s.param, nearest: v) } }),
                   in: s.min...s.max, step: s.step)
                .tint(theme.color(.accent))
                .accessibilityLabel(a11y?.label ?? s.label)
                .accessibilityValue(a11y?.value ?? "")
                .accessibilityHint(a11y?.hint ?? "")
                .accessibilityIdentifier(a11y?.identifier ?? "board.slider." + s.param)
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: changeSliders { $0.increment(s.param) }
                    case .decrement: changeSliders { $0.decrement(s.param) }
                    @unknown default: break
                    }
                }
        }
    }

    /// Apply a slider change: the board follows at once (no blend, no draw-on), and a newly refused position is
    /// announced to VoiceOver with the note the board shows. A change of the board's items settles any in-flight step,
    /// scene or keyframe transition (`MGBoardMotion.settle`): from the next frame on the canvas draws the items the
    /// audio graph charts, instead of finishing a blend or keyframes toward items the sliders have replaced.
    /// A slider change is not a transition, so while motion plays it opens no transition window: a split board stays
    /// split (`MGRenderPolicy.layered`) and draws its base once against the new items. A window still open for the
    /// transitions it settled (a step's 1.6 s) now ends with the step's camera move (`MGBoardTransition.windowEnd`), so
    /// the board splits as soon as that move ends (`MGBoardTransition.phase`). A board with no motion playing keeps its
    /// window and runs its paused frame loop for one settled redraw, as before.
    private func changeSliders(_ change: (inout MGSliderState) -> Bool) {
        guard var state = sliderState else { return }
        let before = state.refusal
        let shown = state.items
        _ = change(&state)
        sliderState = state
        let motionPlays = renderState(state.scene).motionPlaying
        if state.items != shown {
            motion.settle()
            if motionPlays {
                let now = controller.presentationDate()
                endTransient(by: MGBoardTransition.windowEnd(transientUntil, settledAt: now, cameraStart: cameraStart, reduceMotion: reduceMotion))
            }
        }
        if !motionPlays { bumpTransient(0.1) }
        if let refusal = state.refusal, refusal != before { AccessibilityNotification.Announcement(refusal.text).post() }
    }

    // MARK: state

    private func time(_ now: Date) -> Double { teaching.holdsMotion ? 0 : (playing ? now.timeIntervalSince(epoch) : pausedAt) }

    private func togglePlay() {
        if playing { pausedAt = controller.presentationDate().timeIntervalSince(epoch) } else { epoch = controller.presentationDate().addingTimeInterval(-pausedAt) }
        playing.toggle(); bumpTransient()
    }

    private func go(_ scene: MGScene, _ next: Int) {
        guard scene.steps.indices.contains(next) else { return }
        let before = Set(controller.timelineItems(scene, step: step).map(\.id))
        cameraFrom = scene.steps[step].camera ?? scene.camera; cameraStart = controller.presentationDate()
        motion.blend(from: MGTimeline.frame(scene, items: boardItems(scene, step: step), time: time(controller.presentationDate())), at: controller.presentationDate())
        step = next; sliderState?.show(step: next); bumpTransient()
        let now = controller.presentationDate()
        for id in controller.timelineItems(scene, step: next).map(\.id) where !before.contains(id) { appearStart[id] = now }
    }

    /// New scene or patched scene. `.blend`: blend from what is on screen now; new items draw on. `.direct`: no blend
    /// and no draw-on replay for ids already shown (a finger update). `.keyframes`: play engine in-betweens.
    /// A first appearance (not animated) draws everything on. The decision is `MGAdoption.plan` (pure, tested).
    private func adopt(_ scene: MGScene, animated: Bool, transition: MGTransition = .blend, drawsOn: Bool = true) {
        let now = controller.presentationDate()
        let previous = shownScene
        let plan = MGAdoption.plan(previous: animated ? previous?.items : nil, next: scene.items, transition: transition, step: step, drawsOn: drawsOn)
        if !drawsOn { appearStart.removeAll() }   // no draw-on left over from an earlier, interrupted transition
        if plan.blends, let previous {
            // What the board showed: the learner's items, or the outgoing step items read without filling the cache,
            // which may already hold the incoming revision (`MGSliderState.leavingItems`).
            let shown = MGSliderState.leavingItems(previous, step: step, sliders: sliderState, cache: controller.timeline)
            motion.blend(from: MGTimeline.frame(previous, items: shown, time: time(now)), at: now)
        } else {
            motion.blend(from: nil, at: now)
        }
        motion.play(plan.segments, duration: plan.duration, at: now)
        if controller.transitionsPaused { motion.pause(at: now); heldAt = now }
        for (id, delay) in plan.appear { appearStart[id] = now.addingTimeInterval(delay) }
        let sameScene = previous.map { $0.template == scene.template && $0.title == scene.title } ?? false
        if !sameScene { step = 0; epoch = now; pausedAt = 0 }
        // Finite (teaching) motion: a changed parameter replays the new motion from the start for its loops, so the
        // learner sees the consequence of their change; it never resumes mid-way through a different motion.
        else if teaching.loops != nil, previous != scene { epoch = now; pausedAt = 0; playing = scene.animates }
        step = min(scene.startStep > 0 ? scene.startStep : step, max(0, scene.steps.count - 1))
        if readOnly { step = max(0, scene.steps.count - 1) }
        if scene.startStep > 0, let previous { cameraFrom = previous.steps.indices.contains(step) ? previous.steps[step].camera : previous.camera; cameraStart = now }
        shownScene = scene
        // Sliders keep the learner's positions across updates of the same scene while they stay valid.
        sliderState = showsControls && !readOnly && !scene.sliders.isEmpty
            ? MGSliderState(scene: scene, step: step, keeping: sameScene ? sliderState?.values ?? [:] : [:]) : nil
        if case .direct = transition, animated, plan.appear.isEmpty { bumpTransient(0.1) }   // one settled redraw, no replay
        else { bumpTransient(max(MGRenderPolicy.transientSeconds, max(plan.duration, plan.appear.values.max() ?? 0) + 0.8)) }   // + draw-on 0.55 s
    }

    /// Lesson pause: freeze keyframe time (and pending draw-on starts); resume continues from the same frame.
    private func holdTransitions(_ paused: Bool) {
        let now = controller.presentationDate()
        if paused {
            motion.pause(at: now); heldAt = now
        } else {
            motion.resume(at: now)
            if let held = heldAt {
                let gap = now.timeIntervalSince(held)
                for (id, start) in appearStart where start > held { appearStart[id] = start.addingTimeInterval(gap) }
            }
            heldAt = nil
            let left = motion.keyframesLeft(at: now)
            if left > 0 { bumpTransient(left + 0.8) }
        }
    }

    /// Where the board's step and patch transitions stand at `now` on its own clock (`MGBoardTransition.phase`), from
    /// the same state `input` draws with: the blend and the keyframes in `motion`, the camera move and the draw-on.
    private func transitionPhase(at now: Date) -> MGBoardTransition.Phase {
        motion.phase(teaching.transitionStyle, at: now, cameraElapsed: now.timeIntervalSince(cameraStart),
                     drawingOn: !MGBoardTransition.appear(appearStart, at: now, reduceMotion: reduceMotion).isEmpty, reduceMotion: reduceMotion)
    }

    private func input(_ scene: MGScene, now: Date, size: CGSize) -> MGRenderInput {
        let t = reduceMotion ? 0 : time(now)
        // Step and patch transitions (`MGBoardMotion.frame`, `MGBoardTransition`): by default the board's spring within
        // the 1.2 s window and nothing with Reduce Motion, exactly as before; a `.bounded` board eases with no overshoot,
        // fades leaving items out and dissolves with Reduce Motion (`MGStepTransition`). The live items are the
        // learner's once a slider sits at a non-default value, else the cached step items (`boardItems`), read only
        // when no keyframes supply the frame.
        let style = teaching.transitionStyle
        let blend = motion.frame(scene, live: boardItems(scene, step: step), style: style, now: now, time: t,
                                 hiding: teaching.concealed, reduceMotion: reduceMotion)
        let items = blend.items
        let camera = scene.steps.indices.contains(step) ? (scene.steps[step].camera ?? scene.camera) : scene.camera
        let fit = teaching.fitSize ?? size
        var vp = MGViewport(size: fit, width: scene.width, height: scene.height, camera: camera).resized(to: size)
        if let progress = MGBoardTransition.cameraProgress(style, elapsed: now.timeIntervalSince(cameraStart), reduceMotion: reduceMotion) {
            let from = MGViewport(size: fit, width: scene.width, height: scene.height, camera: cameraFrom).resized(to: size)
            vp = from.lerp(vp, CGFloat(progress))
        }
        let appear = MGBoardTransition.appear(appearStart, at: now, reduceMotion: reduceMotion)
        let focus = scene.steps.indices.contains(step) ? scene.steps[step].focus : nil
        var out = MGRenderInput(scene: scene, items: items, viewport: vp, theme: theme, appear: appear, focus: focus, time: t)
        out.opacity = blend.opacity
        out.transitionStyle = style
        out.emphasis = teaching.emphasis.union(teaching.selection?.wrappedValue.map { [$0] } ?? [])
        out.markers = teaching.markers
        out.tableRows = teaching.tableRows
        out.tableCells = teaching.tableCells
        return out
    }
}

extension MG3DView {
    /// The host board's 3D wiring: derives the hooks from the teaching modifiers (`MG3DInteraction.Hooks.derive`)
    /// and writes taps to the current selection binding. Kept out of `MGSceneHost.body` so tests can build it.
    init(scene: MGScene, items: [MGItem], playing: Bool, teaching: MGBoardTeaching, readOnly: Bool) {
        let hooks = MG3DInteraction.Hooks.derive(hasSelection: teaching.selection != nil, selected: teaching.selection?.wrappedValue,
                                                 emphasis: teaching.emphasis, markers: teaching.markers,
                                                 inspection: teaching.inspection3D, cameraReset: teaching.cameraReset, readOnly: readOnly)
        self.init(scene: scene, items: items, playing: playing, selectable: hooks.selectable,
                  onSelect: hooks.selects ? { [selection = teaching.selection] in selection?.wrappedValue = $0 } : nil,
                  emphasis: hooks.emphasis, glowsEmphasis: hooks.glows, dimsOthers: hooks.dims, cameraReset: hooks.cameraReset)
    }
}
