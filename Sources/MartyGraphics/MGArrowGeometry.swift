// SPDX-License-Identifier: Apache-2.0
import CoreGraphics
import Foundation

/// Arrow geometry for the 2D renderers (docs/ENGINE.md, "Arrows"). Pure and deterministic.
///
/// The head is a triangle whose length follows the line width (3.5 widths + 3 points, 7...16) but never exceeds 45 % of
/// the arrow, so a short arrow (and every arrow while it draws on from length 0) keeps its proportions: the head never
/// reaches behind the tail and the shaft never points backwards. The shaft stops inside the head (by half the line
/// width, at most half the head), so its cap is covered by the head and no seam shows where the two meet.
public struct MGArrowGeometry: Equatable {
    public var tail: CGPoint
    /// Where the stroked shaft ends.
    public var shaftEnd: CGPoint
    public var tip: CGPoint
    /// The two corners of the head's base, on either side of the shaft (`headLength` back from the tip).
    public var left: CGPoint
    public var right: CGPoint
    public var headLength: CGFloat
    /// False when the arrow is too short for a shaft: the head alone shows it.
    public var drawsShaft: Bool

    /// Head length for a line `width` wide on an arrow `length` long.
    public static func headLength(width: CGFloat, length: CGFloat) -> CGFloat {
        let w = width.isFinite ? max(0, width) : 0
        return max(0, min(length * 0.45, min(16, max(7, 3 + 3.5 * w))))
    }

    /// The arrow from `a` to `b` for a line `width` wide; nil when it is shorter than half a point (nothing to draw).
    public static func make(from a: CGPoint, to b: CGPoint, width: CGFloat) -> MGArrowGeometry? {
        let dx = b.x - a.x, dy = b.y - a.y
        let d = (dx * dx + dy * dy).squareRoot()
        guard d.isFinite, d > 0.5 else { return nil }
        let ux = dx / d, uy = dy / d
        let head = headLength(width: width, length: d)
        let half = max(head * 0.55, min(width, head) * 0.6)
        let base = CGPoint(x: b.x - ux * head, y: b.y - uy * head)
        let overlap = min(max(0, width) / 2, head / 2)
        let end = CGPoint(x: base.x + ux * overlap, y: base.y + uy * overlap)
        return MGArrowGeometry(tail: a, shaftEnd: end, tip: b,
                               left: CGPoint(x: base.x - uy * half, y: base.y + ux * half),
                               right: CGPoint(x: base.x + uy * half, y: base.y - ux * half),
                               headLength: head, drawsShaft: d - head > 0.5)
    }

    /// Length of the stroked shaft.
    public var shaftLength: CGFloat { hypot(shaftEnd.x - tail.x, shaftEnd.y - tail.y) }

    /// The dash phase that ends a dashed shaft `length` long on the end of a whole dash, so the head never floats
    /// after a gap: (length + phase) mod (dash + gap) == dash.
    public static func dashPhase(length: CGFloat, dash: CGFloat, gap: CGFloat) -> CGFloat {
        let period = dash + gap
        guard period > 0, length.isFinite else { return 0 }
        let r = (dash - length).truncatingRemainder(dividingBy: period)
        return r < 0 ? r + period : r
    }
}
