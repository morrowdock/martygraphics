// SPDX-License-Identifier: Apache-2.0
import Foundation

/// Bounded easing curves (docs/ENGINE.md, "Transitions"). Every curve maps 0 to 0 and 1 to 1, never leaves 0...1 and
/// never turns back (monotone), so a blended value always lies between its two step values: a vector never grows past
/// its new length on the way, an angle never swings past its target. Inputs outside 0...1 (and NaN) are clamped.
/// Pure and deterministic.
public enum MGEasing {
    public enum Curve: String, CaseIterable, Sendable {
        /// Constant speed.
        case linear
        /// Cubic smoothstep 3t² − 2t³: starts and ends at rest.
        case smooth
        /// Quintic smootherstep 6t⁵ − 15t⁴ + 10t³: also starts and ends with zero acceleration (the step default).
        case smoother
        /// Cubic ease-out 1 − (1 − t)³: starts at speed, settles gently (draw-on).
        case easeOut
        /// A critically damped approach, scaled to land exactly on 1 at t = 1: the feel of a spring with no overshoot.
        case settle

        public func callAsFunction(_ t: Double) -> Double { at(t) }

        /// The curve at `t` (clamped to 0...1; NaN counts as 0).
        public func at(_ t: Double) -> Double {
            let x = t.isNaN ? 0 : min(1, max(0, t))
            switch self {
            case .linear: return x
            case .smooth: return x * x * (3 - 2 * x)
            case .smoother: return x * x * x * (x * (6 * x - 15) + 10)
            case .easeOut: return 1 - pow(1 - x, 3)
            case .settle:
                let w = MGEasing.settleRate
                return min(1, (1 - (1 + w * x) * exp(-w * x)) / (1 - (1 + w) * exp(-w)))
            }
        }
    }

    /// Rate of `Curve.settle` (per unit time): at 8 the curve covers 90 % of the way by t ≈ 0.48.
    public static let settleRate = 8.0
}

/// How a 2D board moves between steps and patches (`MartyGraphicsView.transitionStyle(_:)`, docs/ENGINE.md,
/// "Transitions"). `.bounded` is the default. Select `.spring` for the original board motion.
public enum MGTransitionStyle: String, CaseIterable, Sendable {
    /// Original motion: step and patch blends and camera moves follow `MGTimeline.spring` (it overshoots by
    /// about 12 % and settles at 1.2 s), body and node pops use the same spring, items that leave a step vanish at
    /// once, and with Reduce Motion the board snaps to the new state with no transition and no frame loop.
    case spring
    /// Opt-in: `MGStepTransition` (bounded easing over 0.6 s, no value past either step), leaving items fade out, a
    /// step's camera moves over 0.8 s, pops land exactly on their size (`MGEasing.Curve.settle`), and with Reduce
    /// Motion the board dissolves (nothing moves; the frame loop runs for the dissolve only, `MGRenderPolicy.dissolving`).
    case bounded
}

/// The 2D board's transition decisions for one `MGTransitionStyle`. `MGSceneHost` and `MGCanvasRenderer` call these
/// on every frame; pure, so tests check both styles without a window.
enum MGBoardTransition {
    /// Seconds after a step or patch change in which the board blends (both styles; `.bounded` settles at 0.6 s).
    static let blendWindow = 1.2
    /// Seconds after a step change in which the board's camera moves (both styles; `.bounded` settles at 0.8 s).
    static let cameraWindow = 1.0

    /// The items to draw `elapsed` seconds after a change from `from` (nil: no blend) to `to`, and the opacity of
    /// every item that is not opaque. `.spring` is the board before `MGTransitionStyle` existed: `MGTimeline.blend` at
    /// `MGTimeline.spring(elapsed)`, nothing fades, and no blend at all with Reduce Motion. `.bounded`:
    /// `MGStepTransition`, a dissolve with Reduce Motion.
    static func items(_ style: MGTransitionStyle, from: [MGItem]?, to: [MGItem], elapsed: Double, reduceMotion: Bool) -> MGStepTransition.Frame {
        guard let from, elapsed < blendWindow else { return MGStepTransition.Frame(items: to, opacity: [:]) }
        switch style {
        case .spring:
            guard !reduceMotion else { return MGStepTransition.Frame(items: to, opacity: [:]) }
            return MGStepTransition.Frame(items: MGTimeline.blend(from: from, to: to, t: MGTimeline.spring(elapsed)), opacity: [:])
        case .bounded:
            return MGStepTransition(reduceMotion: reduceMotion).frame(from: from, to: to, elapsed: elapsed)
        }
    }

    /// How far a step's camera move has gone `elapsed` seconds after the step changed; nil when the board shows the
    /// step's camera as it is (after the window, and always with Reduce Motion). `.spring`: `MGTimeline.spring`, as
    /// before; `.bounded`: 0.8 s on `MGStepTransition`'s curve.
    static func cameraProgress(_ style: MGTransitionStyle, elapsed: Double, reduceMotion: Bool) -> Double? {
        guard elapsed < cameraWindow, !reduceMotion else { return nil }
        switch style {
        case .spring: return MGTimeline.spring(elapsed)
        case .bounded: return MGStepTransition(duration: MGStepTransition.cameraSeconds).progress(elapsed)
        }
    }

    /// The size factor of a body or the radius factor of a node at eased draw-on progress `p` (1 once drawn).
    /// `.spring`: `MGTimeline.spring(p · 0.9)` as before (it overshoots while it draws on and rests just under the
    /// size); `.bounded`: `MGEasing.Curve.settle` (no overshoot, exactly the size at 1).
    static func pop(_ style: MGTransitionStyle, _ p: Double) -> Double {
        switch style {
        case .spring: return MGTimeline.spring(p * 0.9)
        case .bounded: return MGEasing.Curve.settle.at(p)
        }
    }

    /// True while the 2D frame loop runs: `MGRenderPolicy.continuous`, and for `.bounded` also the Reduce Motion
    /// dissolve (`MGRenderPolicy.dissolving`). With Reduce Motion a `.spring` board never runs the loop: it snaps.
    static func runsLoop(_ style: MGTransitionStyle, _ s: MGRenderPolicy.State) -> Bool {
        MGRenderPolicy.continuous(s) || (style == .bounded && MGRenderPolicy.dissolving(s))
    }

    /// Seconds an item takes to draw on: `MGRenderInput.appear` runs from 0 to 1 over this.
    static let drawOnSeconds = 0.55

    /// The draw-on progress at `now` of every item still drawing on, from the start of each draw-on in `starts` (a
    /// start still to come counts as 0). Items drawn in full are left out; with Reduce Motion nothing draws on.
    static func appear(_ starts: [String: Date], at now: Date, reduceMotion: Bool) -> [String: Double] {
        guard !reduceMotion else { return [:] }
        var appear: [String: Double] = [:]
        for (id, start) in starts { let p = now.timeIntervalSince(start) / drawOnSeconds; if p < 1 { appear[id] = max(0, p) } }
        return appear
    }

    /// Where a 2D board's own step and patch transitions stand at one time on the board's clock. The board's split
    /// (`MGRenderPolicy.layered`, `MGCanvasLayers`) follows this, not the transition window, whose end is a wall-clock
    /// wait: the base canvas is not redrawn on ticks, so it may only cache what no transition still changes.
    enum Phase: Equatable, Sendable {
        /// A blend, a camera move or keyframes still change the frame: the board draws one canvas.
        case moving
        /// Only draw-ons remain: the board may split, with the items still drawing on in the live layer
        /// (`MGCanvasLayers.settling`), and splits once more when the last one ends.
        case drawingOn
        /// Nothing changes but the motion: the base caches every static item below the lowest live item.
        case settled
    }

    /// The phase `blendElapsed` seconds after the last blend began (nil: no blend), `cameraElapsed` seconds after the
    /// last camera move began, with keyframes playing or not and items drawing on or not. A blend moves for as long as
    /// `items` can still give anything but the new items: for `.spring` its whole window (its blend gives the new items
    /// whenever the spring is past 1, and leaves them again while the window lasts), none with Reduce Motion; for
    /// `.bounded` until the progress of `MGStepTransition` reaches 1, whose leaving items start at opacity 1 (so
    /// `MGCanvasLayers.settling` alone would cache them in full). A camera move moves while `cameraProgress` is non-nil.
    static func phase(_ style: MGTransitionStyle, blendElapsed: Double?, cameraElapsed: Double, keyframes: Bool,
                      drawingOn: Bool, reduceMotion: Bool) -> Phase {
        if keyframes || cameraProgress(style, elapsed: cameraElapsed, reduceMotion: reduceMotion) != nil { return .moving }
        if let e = blendElapsed, e < blendWindow {
            switch style {
            case .spring: if !reduceMotion { return .moving }
            case .bounded: if MGStepTransition(reduceMotion: reduceMotion).progress(e) < 1 { return .moving }
            }
        }
        return drawingOn ? .drawingOn : .settled
    }

    /// When the board's transition window (`MGRenderPolicy.State.transientActive`, on the board's clock) ends once a
    /// learner change has settled the board's blend and keyframes at `now` (`MGBoardMotion.settle`) while motion plays:
    /// what is left of the window ending at `until`, but no later than the end of the camera move that began at
    /// `cameraStart`, the one step transition a settle leaves running (`cameraProgress` is nil from `cameraWindow` on,
    /// and always with Reduce Motion). The split (`MGRenderPolicy.layered`) waits for that window, so the board then
    /// splits as soon as the camera move ends instead of when a step's 1.6 s window would have. Draw-ons need no window
    /// while motion plays: the board splits with them in its live layer (`Phase.drawingOn`).
    static func windowEnd(_ until: Date, settledAt now: Date, cameraStart: Date, reduceMotion: Bool) -> Date {
        let cameraEnd = reduceMotion ? now : max(now, cameraStart.addingTimeInterval(cameraWindow))
        return min(until, cameraEnd)
    }
}

/// The 2D board's transition window (`MGRenderPolicy.State.transientActive`): open until `until` on the board's clock.
/// Every change that opens or ends it early gives it a new `token`, which restarts the host's task that waits for it
/// (`.task(id:)`). SwiftUI cancels the old task only at its next update, so the old task can wake after a change and
/// before that update. A task keeps the token it was started for: it reads the deadline only while that token is
/// current (`deadline(for:)`) and closes the window only if nothing changed it since (`close(_:)`), so a stale task
/// never closes a window that a later step or patch opened.
struct MGTransientWindow: Equatable, Sendable {
    /// When the window ends on the board's clock; `Date.distantPast` while it is closed.
    private(set) var until = Date.distantPast
    private(set) var token = 0

    func active(at now: Date) -> Bool { now < until }
    /// Keep the window open at least `seconds` past `now` (an open window never ends earlier for it), with a new token.
    mutating func keepOpen(from now: Date, for seconds: Double) {
        until = max(until, now.addingTimeInterval(seconds)); token &+= 1
    }
    /// End the window at `end` when that is earlier, with a new token. False, and nothing changes, when it already
    /// ends by then.
    @discardableResult mutating func end(by end: Date) -> Bool {
        guard end < until else { return false }
        until = end; token &+= 1
        return true
    }
    /// The deadline that the task started for `token` waits for; nil once a later change has given the window a new
    /// token.
    func deadline(for token: Int) -> Date? { token == self.token ? until : nil }
    /// The task started for `token` has waited out its deadline: close the window, unless a change since gave it a new
    /// token. Returns whether it closed.
    @discardableResult mutating func close(_ token: Int) -> Bool {
        guard token == self.token else { return false }
        until = .distantPast
        return true
    }
}

/// The 2D board's in-flight item transitions: engine keyframes (on a clock a lesson pause can hold) and the blend from
/// the items that were on screen, in the board's `MGTransitionStyle` (`MGBoardTransition`). `frame` gives what a frame
/// draws and `phase` where the transitions stand (the board's split, `MGBoardTransition.phase`), both from this state,
/// so the SwiftUI host's canvases, its split and the tests agree. `settle()` ends both at once: the next frame draws
/// the board's items exactly (a learner slider change), and the board may split against them once its camera allows
/// (the host ends its transition window with the camera move, `MGBoardTransition.windowEnd`).
struct MGBoardMotion: Equatable, Sendable {
    private(set) var keyframes: [MGAdoption.Segment] = []
    private(set) var clock = MGTransitionClock(start: .distantPast)
    private(set) var keyframeDuration: Double = 0
    private(set) var blendFrom: [MGItem]?
    private(set) var blendStart = Date.distantPast

    /// Blend from `items` (the frame on screen), starting `now`; nil: no blend.
    mutating func blend(from items: [MGItem]?, at now: Date) {
        blendFrom = items
        if items != nil { blendStart = now }
    }

    /// Play `segments` (an `MGAdoption` plan's), starting `now`.
    mutating func play(_ segments: [MGAdoption.Segment], duration: Double, at now: Date) {
        keyframes = segments; clock = MGTransitionClock(start: now); keyframeDuration = duration
    }

    mutating func pause(at now: Date) { clock.pause(at: now) }
    mutating func resume(at now: Date) { clock.resume(at: now) }
    /// Keyframe seconds still to play.
    func keyframesLeft(at now: Date) -> Double { max(0, keyframeDuration - clock.elapsed(at: now)) }

    /// End every in-flight transition: no keyframes and no blend, so `frame` returns the board's items' frame with
    /// nothing fading, and `phase` no longer reports `.moving` for either.
    mutating func settle() { keyframes = []; keyframeDuration = 0; blendFrom = nil }

    /// True while engine keyframes play at `now` (a lesson pause holds their clock); never with Reduce Motion.
    func keyframesPlay(at now: Date, reduceMotion: Bool) -> Bool {
        !keyframes.isEmpty && clock.elapsed(at: now) < keyframeDuration && !reduceMotion
    }

    /// Seconds since the last blend began at `now`; nil when there is no blend.
    func blendElapsed(at now: Date) -> Double? { blendFrom == nil ? nil : now.timeIntervalSince(blendStart) }

    /// The frame drawn at `now` from `board`, the items one evaluation of the board read (`MGBoardFrames`: the step's
    /// items or the learner's slider items): the keyframes while they play, else those items, with motion at `time`
    /// (`MGBoardFrames.frame`), without `hiding`, then the step or patch blend of `style` (`MGBoardTransition.items`):
    /// with the original spring within the 1.2 s window and nothing with Reduce Motion; a `.bounded` board eases
    /// with no overshoot, fades leaving items out and dissolves with Reduce Motion (`MGStepTransition`). `opacity`
    /// holds the items that are not opaque. `board` holds its items by value, so no frame asks the controller's cache
    /// for them (`MGTimelineCache`), with or without keyframes.
    func frame(_ board: MGBoardFrames, style: MGTransitionStyle, now: Date, time: Double,
               hiding: Set<String>, reduceMotion: Bool) -> MGStepTransition.Frame {
        var items = board.frame(time: time, keyframes: keyframesPlay(at: now, reduceMotion: reduceMotion)
                                ? MGTween.sample(keyframes, at: clock.elapsed(at: now)) : nil)
        if !hiding.isEmpty { items.removeAll { hiding.contains($0.id) } }
        var blend = MGBoardTransition.items(style, from: blendFrom, to: items, elapsed: now.timeIntervalSince(blendStart), reduceMotion: reduceMotion)
        // Leaving items come from the previous frame (`.bounded` only): a concealed id stays hidden while it fades.
        if style == .bounded, !hiding.isEmpty { blend.items.removeAll { hiding.contains($0.id) } }
        return blend
    }

    /// Where the transitions stand at `now` (`MGBoardTransition.phase`): the blend and the keyframes are this state's,
    /// the camera move (`cameraElapsed` seconds after it began) and the draw-on are the board's.
    func phase(_ style: MGTransitionStyle, at now: Date, cameraElapsed: Double, drawingOn: Bool, reduceMotion: Bool) -> MGBoardTransition.Phase {
        MGBoardTransition.phase(style, blendElapsed: blendElapsed(at: now), cameraElapsed: cameraElapsed,
                                keyframes: keyframesPlay(at: now, reduceMotion: reduceMotion), drawingOn: drawingOn, reduceMotion: reduceMotion)
    }
}

/// How a board using `MGTransitionStyle.bounded` moves from one step's state to the next (docs/ENGINE.md,
/// "Transitions"): bounded, deterministic, and with a reduced-motion path.
///
/// Shared items (same id and kind) move with `MGTimeline.blend` at the eased progress, so every coordinate stays
/// between its two step values and an angle takes the short way round. Items only in the new step enter; items only in
/// the old step leave, fading out from where they were. With Reduce Motion nothing moves: the new geometry shows at
/// once, entering items fade in and leaving items fade out (a dissolve), over the same duration.
public struct MGStepTransition: Equatable, Sendable {
    /// Seconds the transition moves for (it rests on the new state afterwards).
    public var duration: Double
    public var curve: MGEasing.Curve
    public var reduceMotion: Bool

    public init(duration: Double = MGStepTransition.standardSeconds, curve: MGEasing.Curve = .smoother, reduceMotion: Bool = false) {
        self.duration = duration; self.curve = curve; self.reduceMotion = reduceMotion
    }

    /// The step default: 0.6 s, inside the 1.2 s that a lesson waits for a blend to settle (`MGLessonSession`).
    public static let standardSeconds = 0.6
    /// A step's camera move (inside the 1.0 s camera window of the 2D board).
    public static let cameraSeconds = 0.8

    /// Eased progress at `elapsed` seconds: 0 before the start (or for NaN), exactly 1 from `duration` on.
    public func progress(_ elapsed: Double) -> Double {
        guard elapsed.isFinite, elapsed > 0 else { return elapsed == .infinity ? 1 : 0 }
        guard duration.isFinite, duration > 0, elapsed < duration else { return 1 }
        return curve.at(elapsed / duration)
    }

    /// One frame of the transition: the items to draw (leaving items first, so new items draw over them within a
    /// layer) and the opacity of every item that is not fully opaque (missing ids are opaque).
    public struct Frame: Equatable {
        public var items: [MGItem]
        public var opacity: [String: Double]
        public init(items: [MGItem], opacity: [String: Double]) { self.items = items; self.opacity = opacity }
    }

    /// The frame `elapsed` seconds after the transition from `from` to `to` started.
    public func frame(from: [MGItem], to: [MGItem], elapsed: Double) -> Frame {
        let p = progress(elapsed)
        guard p < 1 else { return Frame(items: to, opacity: [:]) }
        let next = Set(to.map(\.id))
        var before: [String: MGItem] = [:]
        for item in from where before[item.id] == nil { before[item.id] = item }
        let leaving = from.filter { !next.contains($0.id) }
        var opacity: [String: Double] = [:]
        for item in leaving { opacity[item.id] = 1 - p }
        if reduceMotion {
            for item in to where before[item.id] == nil { opacity[item.id] = p }
            return Frame(items: leaving + to, opacity: opacity)
        }
        return Frame(items: leaving + MGTimeline.blend(from: from, to: to, t: p), opacity: opacity)
    }
}
