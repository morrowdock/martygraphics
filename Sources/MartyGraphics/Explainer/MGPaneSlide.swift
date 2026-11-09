// SPDX-License-Identifier: Apache-2.0
import Foundation

// The pane slide of an explainer's story video (docs/EXPLAINER.md, "Pane slide in the story video"): when the board
// pane opens, closes or changes width between two beats, the pane boundary slides between the two layouts during the
// camera move into the beat, instead of a cut. Foundation only, deterministic.

/// A change of the pane layout between two beats of an explainer story, played over the camera move into the beat.
///
/// At share `s` of the move (the move's eased camera blend, 0...1) every pane edge lies `s` of the way between its two
/// layouts, rounded to whole pixels: the solid pane eases from its rect in the previous beat's layout to its rect in
/// this beat's layout. A board pane that opens grows from zero size at its outer edge (the frame edge away from the
/// solid pane) and fades in; one that closes shrinks to that edge and fades out. At `s` 0 the panes are exactly the
/// previous beat's, at `s` 1 exactly this beat's, so every hold frame keeps its still's layout.
public struct MGPaneSlide: Equatable, Sendable {
    /// How the layout changes: the board pane `open`s, `close`s, or both layouts have it at another width (`resize`).
    public enum Change: String, Equatable, Sendable, CaseIterable { case open, close, resize }

    public let change: Change
    /// The panes of the previous beat's layout and of this beat's layout (nil: the pane is not drawn).
    public let fromBoard: MGFrameRect?, fromSolid: MGFrameRect
    public let toBoard: MGFrameRect?, toSolid: MGFrameRect

    /// The slide between two layouts, or nil when there is nothing to slide: the layouts are equal, or a layout has
    /// no solid pane or a solid pane of no size (only the solid pane has a camera to move).
    public init?(from: (board: MGFrameRect?, solid: MGFrameRect?), to: (board: MGFrameRect?, solid: MGFrameRect?)) {
        guard let fs = from.solid, let ts = to.solid, fs.width > 0, fs.height > 0, ts.width > 0, ts.height > 0 else { return nil }
        guard fs != ts || from.board != to.board else { return nil }
        switch (from.board, to.board) {
        case (nil, .some): change = .open
        case (.some, nil): change = .close
        default: change = .resize
        }
        fromBoard = from.board; fromSolid = fs; toBoard = to.board; toSolid = ts
    }

    /// The panes at share `s` of the move. `s` ≤ 0 (or not finite) gives the previous layout exactly, `s` ≥ 1 this
    /// layout exactly; in between each rect edge moves linearly with `s` and is rounded to the nearest whole pixel. A
    /// board pane of zero width or height is not drawn (nil).
    public func panes(_ s: Double) -> (board: MGFrameRect?, solid: MGFrameRect) {
        guard s.isFinite, s > 0 else { return (fromBoard, fromSolid) }
        guard s < 1 else { return (toBoard, toSolid) }
        let solid = Self.blend(fromSolid, toSolid, s)
        let board: MGFrameRect?
        switch change {
        case .open: board = toBoard.map { Self.blend(Self.collapsed($0, beside: toSolid), $0, s) }
        case .close: board = fromBoard.map { Self.blend($0, Self.collapsed($0, beside: fromSolid), s) }
        case .resize: board = fromBoard.flatMap { a in toBoard.map { Self.blend(a, $0, s) } }
        }
        return (board.flatMap { $0.width > 0 && $0.height > 0 ? $0 : nil }, solid)
    }

    /// The board pane's opacity at share `s`: an opening pane fades in (`s`), a closing one fades out (1 − `s`), a
    /// resized one stays opaque. 0...1; exactly the end value at `s` ≤ 0 and `s` ≥ 1.
    public func boardOpacity(_ s: Double) -> Double {
        let t = s.isFinite ? min(1, max(0, s)) : 0
        switch change {
        case .open: return t
        case .close: return 1 - t
        case .resize: return 1
        }
    }

    /// The move's camera `camera` at share `s`, fitted to the current solid pane (`panes(s).solid`). The key cameras
    /// of a move were each fitted to their own beat's pane; the move's camera blends between them with the same share
    /// `s` as the pane, so its nominal pane aspect is the previous pane's aspect blended linearly to this pane's. When
    /// the current pane is narrower than that nominal aspect (pixel rounding; a stacked layout, whose height blends
    /// linearly, so its aspect does not), the vertical field of view widens by nominal / current aspect, so the view
    /// the camera was fitted for stays inside the pane horizontally; vertically it already does. Otherwise the camera
    /// is returned unchanged. The camera's position never changes, so the routed path and the swept-box test of
    /// `MGStoryPlan.routes` hold as tested. At `s` ≤ 0 and `s` ≥ 1 the camera is returned exactly.
    public func camera(_ camera: MGSolidCamera, _ s: Double) -> MGSolidCamera {
        guard s.isFinite, s > 0, s < 1 else { return camera }
        let nominal = fromSolid.aspect + (toSolid.aspect - fromSolid.aspect) * s
        let current = panes(s).solid.aspect
        let factor = nominal / current
        guard factor.isFinite, factor > 1, camera.fieldOfView.isFinite, camera.fieldOfView < Self.maxFieldOfView else { return camera }
        let half = camera.fieldOfView * .pi / 360
        let widened = 2 * atan(tan(half) * factor) * 180 / .pi
        guard widened.isFinite, widened > camera.fieldOfView else { return camera }
        return MGSolidCamera(target: camera.targetVector, yaw: camera.yaw, pitch: camera.pitch, distance: camera.distance,
                             fieldOfView: min(Self.maxFieldOfView, widened))
    }

    /// The widest field of view a pane slide gives a camera (degrees).
    public static let maxFieldOfView = 120.0

    /// `{"path": "slide" | "cut", "change": "open" | "close" | "resize", "seconds"}` for the story manifest's beat
    /// record (`layout`): how the layout changed into the beat, and how long the slide took (0 for a cut).
    public func manifestJSON(cut: Bool, seconds: Double) -> MGJSON {
        .object(["path": .string(cut ? "cut" : "slide"), "change": .string(change.rawValue), "seconds": .number(cut ? 0 : seconds)])
    }

    /// `a` moved `s` of the way to `b`, each edge rounded to the nearest whole pixel. Edges are computed in `Double`
    /// and bounded, so hostile rects (edges near `Int.max`) never overflow or trap.
    static func blend(_ a: MGFrameRect, _ b: MGFrameRect, _ s: Double) -> MGFrameRect {
        func lerp(_ x: Double, _ y: Double) -> Int { int(x + (y - x) * s) }
        let x0 = lerp(Double(a.x), Double(b.x)), y0 = lerp(Double(a.y), Double(b.y))
        let x1 = lerp(Double(a.x) + Double(a.width), Double(b.x) + Double(b.width))
        let y1 = lerp(Double(a.y) + Double(a.height), Double(b.y) + Double(b.height))
        return MGFrameRect(x: x0, y: y0, width: max(0, x1 - x0), height: max(0, y1 - y0))
    }

    /// `board` with zero size at its outer edge: the edge away from `solid` (left of a board beside it on the left, top
    /// of a board above it in a bottom-left frame, and so on); its left edge when the two overlap.
    static func collapsed(_ board: MGFrameRect, beside solid: MGFrameRect) -> MGFrameRect {
        let bx = Double(board.x), by = Double(board.y), bw = Double(board.width), bh = Double(board.height)
        let sx = Double(solid.x), sy = Double(solid.y), sw = Double(solid.width), sh = Double(solid.height)
        if bx + bw <= sx { return MGFrameRect(x: board.x, y: board.y, width: 0, height: board.height) }
        if bx >= sx + sw { return MGFrameRect(x: int(bx + bw), y: board.y, width: 0, height: board.height) }
        if by >= sy + sh { return MGFrameRect(x: board.x, y: int(by + bh), width: board.width, height: 0) }
        if by + bh <= sy { return MGFrameRect(x: board.x, y: board.y, width: board.width, height: 0) }
        return MGFrameRect(x: board.x, y: board.y, width: 0, height: board.height)
    }

    /// `x` rounded to the nearest integer and bounded to ±2^52 (every such value is exact in `Double` and fits `Int`).
    static func int(_ x: Double) -> Int {
        let r = x.isFinite ? x.rounded() : 0
        return Int(max(-4_503_599_627_370_496, min(4_503_599_627_370_496, r)))
    }
}
