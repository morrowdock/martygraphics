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
/// "Transitions"). `.spring` is the default and keeps the board exactly as it was; `.bounded` is opt-in.
public enum MGTransitionStyle: String, CaseIterable, Sendable {
    /// The default, unchanged: step and patch blends and camera moves follow `MGTimeline.spring` (it overshoots by
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
}

/// How a board that opts in (`MGTransitionStyle.bounded`) moves from one step's state to the next (docs/ENGINE.md,
/// "Transitions"): bounded, deterministic, and with a reduced-motion path. The default board keeps its spring.
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
