// SPDX-License-Identifier: Apache-2.0
import Foundation

/// Which part of a frame `MGCanvasRenderer.draw(_:in:layer:)` draws (docs/ENGINE.md, "Layers and caches").
public enum MGCanvasLayer: Equatable, Sendable {
    /// The whole frame (`MGCanvasRenderer.draw(_:in:)`).
    case all
    /// The cached base: the board, the grid and these items (`MGCanvasLayers.base`), with no ring, marker or label.
    case base(Set<String>)
    /// The rest over a transparent background: every item not in this base set, then the emphasis rings, markers, focus
    /// ring and every label (the labels of base items too, placed around every item as in one frame).
    case live(Set<String>)

    /// True when this layer draws the item's own marks.
    func draws(_ id: String) -> Bool {
        switch self {
        case .all: return true
        case .base(let ids): return ids.contains(id)
        case .live(let ids): return !ids.contains(id)
        }
    }

    /// True when this layer fills the board and its grid.
    var drawsBoard: Bool { if case .live = self { return false }; return true }
    /// True when this layer draws rings, markers, the focus ring and labels.
    var drawsOverlays: Bool { if case .base = self { return false }; return true }
}

/// The split of a 2D frame into a cached base and a live layer while motion plays (`MGRenderPolicy.layered`).
/// Pure and deterministic.
public enum MGCanvasLayers {
    /// Ids of the items that change while the scene's motion plays: what the motion moves (its body, its vectors and
    /// bars), bodies with `move`, items attached to a moving body, vectors on a moving body or node, edges of a moving
    /// node, every highlight (it pulses with time) and every moving function graph (a `func` with `period`, sampled
    /// again at each tick by `MGTimeline.frame`). The closure over vectors and edges repeats until it is stable.
    /// `items` may be a scene's or step's items or a frame of them: a body with `move` has its target as a second
    /// point, and `MGTimeline.frame` drops that point but keeps the body's `moveT`, so either one marks it live.
    public static func live(_ scene: MGScene, items: [MGItem]) -> Set<String> {
        var live = Set<String>()
        switch scene.motion {
        case .none: break
        case .slide(let entries, _, _): live.formUnion(entries.map(\.id))
        case .orbit(let id, _, _, let rotating): live.insert(id); live.formUnion(rotating)
        case .projectile(let id, _, _, _, _, _, _, let vx, let vy, _):
            live.insert(id)
            if let vx { live.insert(vx) }
            if let vy { live.insert(vy) }
        case .oscillate(let id, _, _, _, let bars, let vector, _):
            live.insert(id)
            if let bars { live.insert(bars) }
            if let vector { live.insert(vector) }
        }
        for i in items where i.kind == .body && (i.pts.count > 1 || i.num["moveT"] != nil) { live.insert(i.id) }
        for i in items where i.kind == .function && i.num["period"] != nil { live.insert(i.id) }
        while true {
            let before = live.count
            for (item, body) in scene.attachments where live.contains(body) { live.insert(item) }
            for i in items {
                switch i.kind {
                case .highlight: live.insert(i.id)
                case .vector: if let r = i.ref, live.contains(r) { live.insert(i.id) }
                case .edge:
                    if let a = i.ref, live.contains(a) { live.insert(i.id) }
                    if let b = i.ref2, live.contains(b) { live.insert(i.id) }
                default: break
                }
            }
            if live.count == before { return live }
        }
    }

    /// Ids whose marks still change on the board's own time base outside the motion: an item still drawing on
    /// (`MGRenderInput.appear` below 1) or fading in or out (`MGRenderInput.opacity` below 1, a `.bounded`
    /// transition). The base canvas is not redrawn on ticks, so the board adds these ids to the live set and the base
    /// caches only items drawn in full. Blends and camera moves are not covered here (a `.bounded` exit starts at
    /// opacity 1): the board draws one canvas until they end on its own clock (`MGBoardTransition.phase`), and splits
    /// once more when the last draw-on ends, so these items then move into the base.
    public static func settling(appear: [String: Double], opacity: [String: Double]) -> Set<String> {
        Set(appear.filter { $0.value < 1 }.keys).union(opacity.filter { $0.value < 1 }.keys)
    }

    /// The base: the items that are not live and are drawn before every live item (a lower layer rank than the
    /// lowest live rank, `MGCanvasRenderer.layer`), so drawing the base under the rest keeps the order of one frame.
    /// No live item: every item.
    public static func base(_ items: [MGItem], live: Set<String>) -> Set<String> {
        let lowest = items.filter { live.contains($0.id) }.map { MGCanvasRenderer.rank($0) }.min() ?? Int.max
        return Set(items.filter { !live.contains($0.id) && MGCanvasRenderer.rank($0) < lowest }.map(\.id))
    }
}

/// The items of a scene at one step (`MGTimeline.items`), kept until the scene or the step changes: a live 2D board
/// otherwise re-applies every step's edits to the scene on every frame. Keyed by the controller that stamped the scene,
/// its revision and the step; a controller's revisions only increase, so one key never names two scenes. Main thread
/// only (the board's Canvas draws synchronously).
final class MGStepItemsCache {
    private struct Key: Equatable { let controller: ObjectIdentifier; let revision: Int; let step: Int }
    private var key: Key?
    private var cached: [MGItem] = []

    func items(_ scene: MGScene, step: Int, controller: AnyObject) -> [MGItem] {
        let k = Key(controller: ObjectIdentifier(controller), revision: scene.revision, step: step)
        if k == key { return cached }
        cached = MGTimeline.items(scene, step: step)
        key = k
        return cached
    }
}
