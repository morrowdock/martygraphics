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

    public init(scene: MGScene? = nil) { self.scene = scene.map(stamped) }

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

    public func beginStream() { stream = MGStreamParser(); beforeStream = scene; isStreaming = true }
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
public struct MartyGraphicsView: View {
    @StateObject private var own: MGSceneController
    private let external: MGSceneController?
    private let initial: MGScene?
    private let showsControls: Bool
    private let readOnly: Bool
    private var teaching = MGBoardTeaching()

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
    /// VoiceOver value for the board (e.g. a teaching summary); defaults to the current step's narration.
    public func boardAccessibility(_ summary: String?) -> Self { var v = self; v.teaching.summary = summary; return v }
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
    var concealed: Set<String> = []
    /// Non-nil: 3D camera keep/reset key (`preserves3DCamera`).
    var cameraReset: Int?
    /// Opt-in 3D hooks (`inspects3D`); empty keeps the original 3D behaviour.
    var inspection3D: MG3DInspection = []
    /// Motion stays on its first frame while anything is concealed (it can show the answer), then plays from the start.
    var holdsMotion: Bool { !concealed.isEmpty }
}

struct MGSceneHost: View {
    @ObservedObject var controller: MGSceneController
    let showsControls: Bool
    var readOnly = false
    var teaching = MGBoardTeaching()
    @Environment(\.mgTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var step = 0
    @State private var playing = true
    @State private var epoch = Date()
    @State private var pausedAt: Double = 0
    @State private var appearStart: [String: Date] = [:]
    @State private var blendFrom: [MGItem]?
    @State private var blendStart = Date.distantPast
    @State private var cameraFrom: MGCamera?
    @State private var cameraStart = Date.distantPast
    @State private var shownScene: MGScene?
    /// Engine keyframe segments being played, on a clock that a lesson pause can hold.
    @State private var keyframes: [MGAdoption.Segment] = []
    @State private var keyframeClock = MGTransitionClock(start: .distantPast)
    @State private var keyframeDuration: Double = 0
    @State private var heldAt: Date?
    // Render gating: the frame loop runs only for real motion or a short transition on a visible board.
    @Environment(\.scenePhase) private var scenePhase
    @State private var visible = false
    @State private var transientUntil = Date.distantPast
    @State private var transientToken = 0

    private func renderState(_ scene: MGScene) -> MGRenderPolicy.State {
        .init(motionPlaying: playing && scene.animates && !teaching.holdsMotion, transientActive: Date() < transientUntil,
              visible: visible, sceneActive: scenePhase == .active, reduceMotion: reduceMotion)
    }
    /// Keep the 2D loop alive just long enough for a transition, then settle on a final static frame.
    private func bumpTransient(_ seconds: Double = MGRenderPolicy.transientSeconds) {
        transientUntil = max(transientUntil, Date().addingTimeInterval(seconds)); transientToken &+= 1
    }

    var body: some View {
        if let scene = controller.scene {
            VStack(alignment: .leading, spacing: 12) {
                header(scene)
                board(scene)
                if showsControls, !scene.steps.isEmpty { caption(scene) }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(theme.backgroundBottom))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
            .onAppear { visible = true; adopt(scene, animated: false, drawsOn: controller.drawsOn) }
            .onDisappear { visible = false }
            .task(id: transientToken) {
                let wait = max(0, transientUntil.timeIntervalSinceNow)
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                if !Task.isCancelled { transientUntil = .distantPast }   // state change → one settled redraw, loop paused
            }
            .onChange(of: controller.revision) { _, _ in if let s = controller.scene { adopt(s, animated: true, transition: controller.transition, drawsOn: controller.drawsOn) } }
            .onChange(of: controller.transitionsPaused) { _, paused in holdTransitions(paused) }
            .onChange(of: teaching.holdsMotion) { _, held in
                if !held { epoch = Date(); pausedAt = 0; playing = true }   // revealed: play the motion from its start
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
        Group {
            if scene.is3D && teaching.concealed.isEmpty {
                MG3DView(scene: scene, items: MGTimeline.items(scene, step: step), playing: MGRenderPolicy.sceneKitPlaying(renderState(scene)),
                         teaching: teaching, readOnly: readOnly)
                    .overlay(alignment: .bottomTrailing) {
                        Label("Drag to turn", systemImage: "hand.draw").font(.caption2).foregroundStyle(theme.subtleInk).padding(8)
                    }
            } else {
                let running = MGRenderPolicy.continuous(renderState(scene))
                GeometryReader { geo in
                    TimelineView(.animation(minimumInterval: MGRenderPolicy.frameInterval, paused: !running)) { tl in
                        Canvas(rendersAsynchronously: false) { ctx, size in
                            MGCanvasRenderer.draw(input(scene, now: running ? tl.date : Date(), size: size), in: ctx)
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(SpatialTapGesture().onEnded { value in select(scene, at: value.location, size: geo.size) },
                             including: teaching.selection != nil && !readOnly ? .all : .none)
                }
            }
        }
        .aspectRatio(scene.width / scene.height, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement()
        .accessibilityLabel(scene.title.isEmpty ? "Marty's sketch" : scene.title)
        .accessibilityValue(teaching.summary ?? (scene.steps.indices.contains(step) ? scene.steps[step].say : ""))
    }

    // MARK: teaching hooks

    /// Tap → the smallest selectable footprint under the finger (12 pt slop); empty space clears the selection.
    private func select(_ scene: MGScene, at point: CGPoint, size: CGSize) {
        guard let binding = teaching.selection else { return }
        // Use the drawing's frame calculation, including in-flight item and camera blends.
        let frame = input(scene, now: Date(), size: size)
        let selectable = teaching.markers.isEmpty ? nil : Set(teaching.markers.keys)
        binding.wrappedValue = frame.hit(point, among: selectable)?.id
    }

    struct LoopKey: Hashable { let epoch: Date; let playing: Bool; let loops: Int?; let revision: Int }

    /// Finite motion: after `loops` cycles, rest on the end of the last cycle (not snapped back to the start).
    private func finishLoops(_ scene: MGScene) async {
        guard let loops = teaching.loops, playing, !teaching.holdsMotion, scene.animates, let cycle = MGTimeline.cycle(scene) else { return }
        let end = cycle * Double(loops)
        let remaining = end - Date().timeIntervalSince(epoch)
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
                    control("arrow.counterclockwise", "Replay", enabled: true) { epoch = Date(); pausedAt = 0; playing = true; bumpTransient() }
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

    // MARK: state

    private func time(_ now: Date) -> Double { teaching.holdsMotion ? 0 : (playing ? now.timeIntervalSince(epoch) : pausedAt) }

    private func togglePlay() {
        if playing { pausedAt = Date().timeIntervalSince(epoch) } else { epoch = Date().addingTimeInterval(-pausedAt) }
        playing.toggle(); bumpTransient()
    }

    private func go(_ scene: MGScene, _ next: Int) {
        guard scene.steps.indices.contains(next) else { return }
        let before = Set(MGTimeline.items(scene, step: step).map(\.id))
        cameraFrom = scene.steps[step].camera ?? scene.camera; cameraStart = Date()
        blendFrom = MGTimeline.frame(scene, items: MGTimeline.items(scene, step: step), time: time(Date())); blendStart = Date()
        step = next; bumpTransient()
        let now = Date()
        for id in MGTimeline.items(scene, step: next).map(\.id) where !before.contains(id) { appearStart[id] = now }
    }

    /// New scene or patched scene. `.blend`: blend from what is on screen now; new items draw on. `.direct`: no blend
    /// and no draw-on replay for ids already shown (a finger update). `.keyframes`: play engine in-betweens.
    /// A first appearance (not animated) draws everything on. The decision is `MGAdoption.plan` (pure, tested).
    private func adopt(_ scene: MGScene, animated: Bool, transition: MGTransition = .blend, drawsOn: Bool = true) {
        let now = Date()
        let previous = shownScene
        let plan = MGAdoption.plan(previous: animated ? previous?.items : nil, next: scene.items, transition: transition, step: step, drawsOn: drawsOn)
        if !drawsOn { appearStart.removeAll() }   // no draw-on left over from an earlier, interrupted transition
        if plan.blends, let previous {
            blendFrom = MGTimeline.frame(previous, items: MGTimeline.items(previous, step: step), time: time(now)); blendStart = now
        } else {
            blendFrom = nil
        }
        keyframes = plan.segments; keyframeClock = MGTransitionClock(start: now); keyframeDuration = plan.duration
        if controller.transitionsPaused { keyframeClock.pause(at: now); heldAt = now }
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
        if case .direct = transition, animated, plan.appear.isEmpty { bumpTransient(0.1) }   // one settled redraw, no replay
        else { bumpTransient(max(MGRenderPolicy.transientSeconds, max(plan.duration, plan.appear.values.max() ?? 0) + 0.8)) }   // + draw-on 0.55 s
    }

    /// Lesson pause: freeze keyframe time (and pending draw-on starts); resume continues from the same frame.
    private func holdTransitions(_ paused: Bool) {
        let now = Date()
        if paused {
            keyframeClock.pause(at: now); heldAt = now
        } else {
            keyframeClock.resume(at: now)
            if let held = heldAt {
                let gap = now.timeIntervalSince(held)
                for (id, start) in appearStart where start > held { appearStart[id] = start.addingTimeInterval(gap) }
            }
            heldAt = nil
            let left = max(0, keyframeDuration - keyframeClock.elapsed(at: now))
            if left > 0 { bumpTransient(left + 0.8) }
        }
    }

    private func input(_ scene: MGScene, now: Date, size: CGSize) -> MGRenderInput {
        let t = reduceMotion ? 0 : time(now)
        let keyT = keyframeClock.elapsed(at: now)
        let playsKeyframes = !keyframes.isEmpty && keyT < keyframeDuration && !reduceMotion
        var items = MGTimeline.frame(scene, items: playsKeyframes ? MGTween.sample(keyframes, at: keyT)
                                                                  : MGTimeline.items(scene, step: step), time: t)
        if !teaching.concealed.isEmpty { items.removeAll { teaching.concealed.contains($0.id) } }
        let blendT = now.timeIntervalSince(blendStart)
        if let from = blendFrom, blendT < 1.2, !reduceMotion { items = MGTimeline.blend(from: from, to: items, t: MGTimeline.spring(blendT)) }
        let camera = scene.steps.indices.contains(step) ? (scene.steps[step].camera ?? scene.camera) : scene.camera
        var vp = MGViewport(size: size, width: scene.width, height: scene.height, camera: camera)
        let camT = now.timeIntervalSince(cameraStart)
        if camT < 1.0, !reduceMotion {
            let from = MGViewport(size: size, width: scene.width, height: scene.height, camera: cameraFrom)
            vp = from.lerp(vp, CGFloat(MGTimeline.spring(camT)))
        }
        var appear: [String: Double] = [:]
        if !reduceMotion { for (id, start) in appearStart { let p = now.timeIntervalSince(start) / 0.55; if p < 1 { appear[id] = max(0, p) } } }
        let focus = scene.steps.indices.contains(step) ? scene.steps[step].focus : nil
        var out = MGRenderInput(scene: scene, items: items, viewport: vp, theme: theme, appear: appear, focus: focus, time: t)
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
