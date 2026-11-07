// SPDX-License-Identifier: Apache-2.0
import Foundation

/// Item-level difference between two item lists, matched by stable id. Order follows the lists (`added`, `changed` and
/// `unchanged` in `to` order, `removed` in `from` order), so equal inputs always give equal diffs.
public struct MGSceneDiff: Equatable, Sendable {
    public let added: [String]
    public let removed: [String]
    /// Ids present in both lists whose item is not `==` (any slot, including the kind).
    public let changed: [String]
    public let unchanged: [String]

    public init(from: [MGItem], to: [MGItem]) {
        let old = Dictionary(from.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let new = Set(to.map(\.id))
        var added: [String] = [], changed: [String] = [], unchanged: [String] = []
        for item in to {
            guard let previous = old[item.id] else { added.append(item.id); continue }
            if previous == item { unchanged.append(item.id) } else { changed.append(item.id) }
        }
        self.added = added; self.changed = changed; self.unchanged = unchanged
        removed = from.map(\.id).filter { !new.contains($0) }
    }

    /// True when nothing was added, removed or changed.
    public var isEmpty: Bool { added.isEmpty && removed.isEmpty && changed.isEmpty }
}

/// One timed run of engine keyframes: `frames[0]` is the start scene, the last frame is that command's committed scene.
/// Neighbouring frames are at most one keyframe step apart (5° for an angle).
public struct MGKeyframeSegment: Equatable, Sendable {
    public let frames: [MGScene]
    public let duration: Double
    public init(frames: [MGScene], duration: Double) { self.frames = frames; self.duration = duration }
}

/// How a board moves from the scene it shows to the next one.
public enum MGTransition: Equatable, Sendable {
    /// Existing behaviour for scripted changes and patches: blend from what is on screen; new ids draw on.
    case blend
    /// Follows a finger: no blend and no draw-on for ids that were already shown. New ids still draw on.
    case direct
    /// Engine keyframes, one segment per `animate`, played one after another, each over its own duration. A view blends
    /// only between neighbouring frames of one segment; between segments it cuts (a change between two `animate`
    /// commands in one beat is not tweened, so no chord is drawn across it). Ids that are new in the final scene and
    /// absent from every keyframe draw on after the last segment.
    case keyframes([MGKeyframeSegment])

    /// Total keyframe time in seconds (0 for `blend` and `direct`).
    public var keyframeDuration: Double {
        if case .keyframes(let segments) = self { return segments.reduce(0) { $0 + $1.duration } }
        return 0
    }
}

/// Pausable elapsed time for a board transition (lesson pause holds an in-flight `animate`). Pure, so tests can sample it.
public struct MGTransitionClock: Equatable, Sendable {
    public private(set) var start: Date
    /// Elapsed seconds frozen at `pause`, or nil while running.
    public private(set) var held: Double?
    public init(start: Date) { self.start = start }
    public func elapsed(at now: Date) -> Double { held ?? now.timeIntervalSince(start) }
    public mutating func pause(at now: Date) { if held == nil { held = now.timeIntervalSince(start) } }
    public mutating func resume(at now: Date) { if let h = held { start = now.addingTimeInterval(-h); held = nil } }
}

/// What a board does when it adopts a new scene. A pure function of the shown items, the next items and the
/// transition, so the SwiftUI host and tests agree (renderer acceptance R1, R2).
public struct MGAdoption: Equatable, Sendable {
    /// One keyframe segment as item lists (sampled with `MGTween.sample(_:at:)`).
    public struct Segment: Equatable, Sendable {
        public let items: [[MGItem]]
        public let duration: Double
    }
    /// Blend from the items on screen.
    public let blends: Bool
    /// Draw-on start delay in seconds per id. Ids not listed are drawn fully at once.
    public let appear: [String: Double]
    /// Keyframe segments to play (empty unless the transition is `.keyframes`).
    public let segments: [Segment]
    /// Total keyframe time in seconds.
    public var duration: Double { segments.reduce(0) { $0 + $1.duration } }

    /// `previous == nil` means the board appears for the first time: every item draws on in layer order (existing
    /// behaviour). Otherwise only ids that are new compared with `previous` draw on. `step` selects the visible items of
    /// stepped keyframe scenes (lesson scenes have no steps). `drawsOn: false` (a restored lesson shown as it was): no
    /// id draws on, also on a first appearance; the transition still decides blend and keyframes.
    public static func plan(previous: [MGItem]?, next: [MGItem], transition: MGTransition, step: Int = 0, drawsOn: Bool = true) -> MGAdoption {
        if !drawsOn {
            let full = plan(previous: previous, next: next, transition: transition, step: step)
            return MGAdoption(blends: full.blends, appear: [:], segments: full.segments)
        }
        guard let previous else {
            var appear: [String: Double] = [:]
            for item in next { appear[item.id] = Double(drawOrder(item)) * 0.05 }
            return MGAdoption(blends: false, appear: appear, segments: [])
        }
        let old = Set(previous.map(\.id))
        let fresh = next.map(\.id).filter { !old.contains($0) }
        switch transition {
        case .blend:
            return MGAdoption(blends: true, appear: Dictionary(uniqueKeysWithValues: fresh.map { ($0, 0) }), segments: [])
        case .direct:
            return MGAdoption(blends: false, appear: Dictionary(uniqueKeysWithValues: fresh.map { ($0, 0) }), segments: [])
        case .keyframes(let list):
            let segments = list.filter { $0.frames.count >= 2 && $0.duration > 0 }
                .map { Segment(items: $0.frames.map { MGTimeline.items($0, step: step) }, duration: $0.duration) }
            let total = segments.reduce(0) { $0 + $1.duration }
            // Ids that exist only after the keyframes (added later in the same beat) draw on once the turn is over.
            let inFrames = Set(segments.flatMap { $0.items.flatMap { $0.map(\.id) } })
            var appear: [String: Double] = [:]
            for id in fresh { appear[id] = inFrames.contains(id) ? 0 : total }
            return MGAdoption(blends: false, appear: appear, segments: segments)
        }
    }

    /// Draw-on order for a first appearance (existing staggering: geometry, then bodies, then arrows, then text).
    public static func drawOrder(_ i: MGItem) -> Int {
        switch i.kind { case .vector, .highlight: return 6; case .text: return 8; case .body, .node, .array: return 3; default: return 0 }
    }
}
