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

/// How a board moves from the scene it shows to the next one.
public enum MGTransition: Equatable, Sendable {
    /// Existing behaviour for scripted changes and patches: blend from what is on screen; new ids draw on.
    case blend
    /// Follows a finger: no blend and no draw-on for ids that were already shown. New ids still draw on.
    case direct
    /// Engine keyframes (each a fully validated scene, first = start, last = committed state) shown over `duration`
    /// seconds, blending only between neighbours. Ids that are new in the final scene draw on after the keyframes.
    case keyframes([MGScene], duration: Double)
}

/// What a board does when it adopts a new scene. A pure function of the shown items, the next items and the
/// transition, so the SwiftUI host and tests agree (renderer acceptance R1, R2).
public struct MGAdoption: Equatable, Sendable {
    /// Blend from the items on screen.
    public let blends: Bool
    /// Draw-on start delay in seconds per id. Ids not listed are drawn fully at once.
    public let appear: [String: Double]
    /// Keyframe item lists to sample over `duration` (empty unless the transition is `.keyframes`).
    public let keyframes: [[MGItem]]
    public let duration: Double

    /// `previous == nil` means the board appears for the first time: every item draws on in layer order (existing
    /// behaviour). Otherwise only ids that are new compared with `previous` draw on. `step` selects the visible items of
    /// stepped keyframe scenes (lesson scenes have no steps).
    public static func plan(previous: [MGItem]?, next: [MGItem], transition: MGTransition, step: Int = 0) -> MGAdoption {
        guard let previous else {
            var appear: [String: Double] = [:]
            for item in next { appear[item.id] = Double(drawOrder(item)) * 0.05 }
            return MGAdoption(blends: false, appear: appear, keyframes: [], duration: 0)
        }
        let old = Set(previous.map(\.id))
        let fresh = next.map(\.id).filter { !old.contains($0) }
        switch transition {
        case .blend:
            return MGAdoption(blends: true, appear: Dictionary(uniqueKeysWithValues: fresh.map { ($0, 0) }), keyframes: [], duration: 0)
        case .direct:
            return MGAdoption(blends: false, appear: Dictionary(uniqueKeysWithValues: fresh.map { ($0, 0) }), keyframes: [], duration: 0)
        case .keyframes(let frames, let duration):
            let lists = frames.map { MGTimeline.items($0, step: step) }
            // Ids that exist only after the keyframes (added later in the same beat) draw on once the turn is over.
            let inFrames = Set(lists.flatMap { $0.map(\.id) })
            var appear: [String: Double] = [:]
            for id in fresh { appear[id] = inFrames.contains(id) ? 0 : duration }
            return MGAdoption(blends: false, appear: appear, keyframes: lists.count >= 2 ? lists : [], duration: lists.count >= 2 ? duration : 0)
        }
    }

    /// Draw-on order for a first appearance (existing staggering: geometry, then bodies, then arrows, then text).
    public static func drawOrder(_ i: MGItem) -> Int {
        switch i.kind { case .vector, .highlight: return 6; case .text: return 8; case .body, .node, .array: return 3; default: return 0 }
    }
}
