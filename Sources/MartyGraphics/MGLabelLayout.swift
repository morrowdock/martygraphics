// SPDX-License-Identifier: Apache-2.0
import CoreGraphics
import Foundation

/// Deterministic 2D label placement with leader lines (docs/ENGINE.md, "Labels"). The 2D board's labels use it; the
/// solid overlay has its own rule (`MGAnnotationLayout`).
///
/// Labels are placed in the order given. Each label tries the three rings of twelve positions around its anchor that
/// `MGLayout.place` tries (its own direction first), then three farther rings. The first position that is clean wins:
/// inside the bounds, at least `spacing` clear of every label placed before and of their leaders, clear of every
/// obstacle, not covering its own anchor, and, for a far position, with a leader that crosses no placed label, no other
/// leader and no obstacle except the one its anchor sits on. A box farther than `leaderDistance` from its anchor gets a leader from the
/// anchor to the nearest point of the box, so a pushed-away label still points at what it names. When no position is
/// clean the cheapest one is taken (overlap area, then leader length and crossings), as `MGLayout.place` does. Boxes
/// snap to whole points, so text and borders sit on the pixel grid.
public enum MGLabelLayout {
    public struct Leader: Equatable {
        public var from: CGPoint
        public var to: CGPoint
        public var length: CGFloat { hypot(to.x - from.x, to.y - from.y) }
    }

    public struct Placement: Equatable {
        public var box: CGRect
        public var leader: Leader?
    }

    public struct Options: Equatable {
        /// Gap between the anchor and the nearest ring (as `MGLayout.place`).
        public var gap: CGFloat = 8
        /// Clear space kept between two labels.
        public var spacing: CGFloat = 2
        /// Rings tried: the first three are `MGLayout.place`'s, the rest are farther out and usually need a leader.
        public var rings = 6
        /// A box farther than this from its anchor gets a leader.
        public var leaderDistance: CGFloat = 14
        /// Grid the box origin snaps to (points); 0 keeps it unsnapped.
        public var snap: CGFloat = 1
        public init() {}
    }

    /// Placements by request id. Every request is placed (a crowded board may overlap, never drop a label).
    public static func place(_ requests: [MGLayout.LabelRequest], obstacles: [CGRect], bounds: CGRect,
                             options: Options = Options()) -> [String: Placement] {
        let obstacles = obstacles.filter { !$0.isNull && !$0.isInfinite }
        var placed: [CGRect] = [], leaders: [Leader] = [], out: [String: Placement] = [:]
        let turns = [0, 1, -1, 2, -2, 3, -3, 4, -4, 5, -5, 6]
        for r in requests {
            let len = max(0.001, hypot(r.direction.dx, r.direction.dy))
            let base = atan2(r.direction.dy / len, r.direction.dx / len)
            // The obstacles the anchor sits on: a leader may leave them.
            let home = obstacles.filter { $0.insetBy(dx: -1, dy: -1).contains(r.anchor) }
            var best: (placement: Placement, cost: CGFloat)?
            var chosen: Placement?
            search: for ring in 0..<max(1, options.rings) {
                for (k, turn) in turns.enumerated() {
                    let a = base + CGFloat(turn) * .pi / 6
                    let gap = options.gap + CGFloat(ring) * (r.size.height + 6)
                    let cx = r.anchor.x + cos(a) * (r.size.width / 2 + gap), cy = r.anchor.y + sin(a) * (r.size.height / 2 + gap)
                    let box = snapped(CGRect(x: cx - r.size.width / 2, y: cy - r.size.height / 2, width: r.size.width, height: r.size.height),
                                      options.snap)
                    let leader = leaderFor(r.anchor, box, options.leaderDistance)
                    let p = Placement(box: box, leader: leader)
                    var cost = CGFloat(ring * 30 + k * 2)
                    var clean = bounds.contains(box) && !box.insetBy(dx: -2, dy: -2).contains(r.anchor)
                    if !bounds.contains(box) {
                        let i = bounds.intersection(box)
                        cost += box.width * box.height - (i.isNull ? 0 : i.width * i.height) + 300
                    }
                    for q in placed {
                        let near = q.insetBy(dx: -options.spacing, dy: -options.spacing)
                        guard near.intersects(box) else { continue }
                        clean = false
                        let i = q.intersection(box)
                        cost += (i.isNull ? 0 : i.width * i.height) + 400
                    }
                    for o in obstacles where o.intersects(box) {
                        clean = false
                        let i = o.intersection(box)
                        cost += i.width * i.height * 0.6 + 150
                    }
                    // A box never covers the leader of a label placed before it.
                    for other in leaders where crosses(other, box) { clean = false; cost += 200 }
                    if let l = leader {
                        cost += l.length / 4
                        for q in placed where crosses(l, q) { clean = false; cost += 200 }
                        for other in leaders where crosses(l, other) { clean = false; cost += 120 }
                        for o in obstacles where !home.contains(o) && crosses(l, o) { clean = false; cost += 60 }
                    }
                    if clean { chosen = p; break search }
                    if best == nil || cost < best!.cost { best = (p, cost) }
                }
            }
            guard let p = chosen ?? best?.placement else { continue }
            placed.append(p.box)
            if let l = p.leader { leaders.append(l) }
            out[r.id] = p
        }
        return out
    }

    /// `rect` with its origin on the `grid` (whole points for 1); its size is kept.
    public static func snapped(_ rect: CGRect, _ grid: CGFloat) -> CGRect {
        guard grid > 0, rect.minX.isFinite, rect.minY.isFinite else { return rect }
        return CGRect(x: (rect.minX / grid).rounded() * grid, y: (rect.minY / grid).rounded() * grid, width: rect.width, height: rect.height)
    }

    /// The nearest point of `box` to `p` (p itself when inside).
    public static func nearest(_ p: CGPoint, on box: CGRect) -> CGPoint {
        CGPoint(x: min(max(p.x, box.minX), box.maxX), y: min(max(p.y, box.minY), box.maxY))
    }

    static func leaderFor(_ anchor: CGPoint, _ box: CGRect, _ distance: CGFloat) -> Leader? {
        let to = nearest(anchor, on: box)
        let l = Leader(from: anchor, to: to)
        return l.length > distance ? l : nil
    }

    /// True when the segment `l` passes through the inside of `rect` (touching its edge does not count).
    static func crosses(_ l: Leader, _ rect: CGRect) -> Bool {
        let r = rect.insetBy(dx: 0.5, dy: 0.5)
        guard !r.isNull, r.width > 0, r.height > 0 else { return false }
        // Liang-Barsky clipping of the segment against the rectangle.
        let dx = l.to.x - l.from.x, dy = l.to.y - l.from.y
        var t0: CGFloat = 0, t1: CGFloat = 1
        for (p, q) in [(-dx, l.from.x - r.minX), (dx, r.maxX - l.from.x), (-dy, l.from.y - r.minY), (dy, r.maxY - l.from.y)] {
            if p == 0 {
                if q < 0 { return false }
            } else {
                let t = q / p
                if p < 0 { t0 = max(t0, t) } else { t1 = min(t1, t) }
                if t0 > t1 { return false }
            }
        }
        return t1 - t0 > 1e-6
    }

    /// True when two leaders cross (sharing an end point does not count).
    static func crosses(_ a: Leader, _ b: Leader) -> Bool {
        func side(_ p: CGPoint, _ q: CGPoint, _ r: CGPoint) -> CGFloat { (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x) }
        let d1 = side(b.from, b.to, a.from), d2 = side(b.from, b.to, a.to)
        let d3 = side(a.from, a.to, b.from), d4 = side(a.from, a.to, b.to)
        return ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) && ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0))
    }
}
