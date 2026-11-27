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

/// How a board moves from one step's state to the next (docs/ENGINE.md, "Transitions"): bounded, deterministic, and
/// with a reduced-motion path.
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
