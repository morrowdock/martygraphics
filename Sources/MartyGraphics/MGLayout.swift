// SPDX-License-Identifier: Apache-2.0
import CoreGraphics
import Foundation

/// World → screen mapping with one uniform scale (no distortion), y flipped, camera centre and zoom.
public struct MGViewport: Equatable {
    public let size: CGSize
    public let scale: CGFloat
    let center: MGPoint
    public init(size: CGSize, width: Double, height: Double, camera: MGCamera?, padding: CGFloat = 18) {
        self.size = size
        let fit = min((size.width - 2 * padding) / CGFloat(width), (size.height - 2 * padding) / CGFloat(height))
        scale = max(1, fit) * CGFloat(camera?.zoom ?? 1)
        center = MGPoint(camera?.x ?? width / 2, camera?.y ?? height / 2)
    }
    public func point(_ p: MGPoint) -> CGPoint {
        CGPoint(x: size.width / 2 + CGFloat(p.x - center.x) * scale, y: size.height / 2 - CGFloat(p.y - center.y) * scale)
    }
    public func length(_ d: Double) -> CGFloat { CGFloat(d) * scale }
    /// Blend two viewports for camera moves between steps.
    public func lerp(_ other: MGViewport, _ t: CGFloat) -> MGViewport {
        var v = self
        v = MGViewport(size: size, scale: scale + (other.scale - scale) * t, center: center.lerp(other.center, Double(t)))
        return v
    }
    init(size: CGSize, scale: CGFloat, center: MGPoint) { self.size = size; self.scale = scale; self.center = center }
    /// This viewport (same scale and centre) for a view of another size: a narrower view crops the sides.
    public func resized(to size: CGSize) -> MGViewport { MGViewport(size: size, scale: scale, center: center) }
}

public enum MGLayout {
    /// Screen-space footprint of an item (for focus rings, highlights and label obstacles).
    public static func bounds(_ item: MGItem, in items: [MGItem], _ vp: MGViewport) -> CGRect? {
        // Public-API callers can bypass parsing. Resolve chains iteratively so
        // cyclic or arbitrarily deep highlight graphs cannot exhaust the stack.
        var resolved = item
        var visited = Set<String>()
        while resolved.kind == .highlight {
            guard visited.insert(resolved.id).inserted,
                  let target = items.first(where: { $0.id == resolved.ref }) else { return nil }
            resolved = target
        }
        let item = resolved
        func around(_ p: MGPoint, _ r: Double) -> CGRect { let c = vp.point(p), s = vp.length(r); return CGRect(x: c.x - s, y: c.y - s, width: 2 * s, height: 2 * s) }
        func box(_ pts: [MGPoint]) -> CGRect? {
            guard let f = pts.first else { return nil }
            return pts.dropFirst().reduce(CGRect(origin: vp.point(f), size: .zero)) { $0.union(CGRect(origin: vp.point($1), size: .zero)) }
        }
        switch item.kind {
        case .body: return item.pts.first.map { around($0, item.n("size", 1) / (item.has("ball") ? 2 : 1.6)) }
        case .node: return item.pts.first.map { around($0, item.n("r", 0.5)) }
        case .pulley, .orbit: return item.pts.first.map { around($0, item.n("r")) }
        case .incline:
            guard let o = item.pts.first else { return nil }
            let b = item.n("base"), h = b * tan(item.n("angle") * .pi / 180)
            return box([o, o + MGPoint(b, 0), o + MGPoint(b, h)])
        case .vector:
            guard let from = item.pts.first else { return nil }
            return box([from, from + MGPoint.polar(item.n("angle"), item.n("len"))])?.insetBy(dx: -6, dy: -6)
        case .axes, .plot, .bars:
            guard let o = item.pts.first else { return nil }
            return box([o, o + MGPoint(item.n("w"), item.n("h"))])
        case .array:
            guard let c = item.pts.first else { return nil }
            let w = item.n("cell", 1) * Double(item.list.count)
            return box([c - MGPoint(w / 2, item.n("cell", 1) / 2), c + MGPoint(w / 2, item.n("cell", 1) / 2)])?.insetBy(dx: 0, dy: -vp.length(0.5))
        case .table:
            guard let c = item.pts.first else { return nil }
            let w = item.n("cw", 1.6) * item.n("cols", 1), h = item.n("rh", 0.7) * item.n("rows", 1)
            return box([c - MGPoint(w / 2, h / 2), c + MGPoint(w / 2, h / 2)])
        case .text:
            guard let p = item.pts.first else { return nil }
            if item.has("code") {
                // Code text is drawn left-aligned at `at` in a monospaced font.
                let c = vp.point(p), text = item.text ?? ""
                let s = CGSize(width: CGFloat(text.count) * 14 * 0.6 + 4, height: 14 * 1.35 + 4)
                return CGRect(x: c.x, y: c.y - s.height / 2, width: s.width, height: s.height)
            }
            let s = textSize(item.text ?? "", font: item.has("title") ? 20 : 14)
            let c = vp.point(p); return CGRect(x: c.x - s.width / 2, y: c.y - s.height / 2, width: s.width, height: s.height)
        case .highlight:
            return nil // Already resolved above; fail closed if this case changes.
        case .edge:
            let a = items.first { $0.id == item.ref }?.pts.first, b = items.first { $0.id == item.ref2 }?.pts.first
            guard let a, let b else { return nil }; return box([a, b])
        case .line, .spring, .rope, .path, .region: return box(item.pts)
        }
    }

    /// Rough text box for label placement (system font, regular). Good enough to keep labels apart.
    public static func textSize(_ s: String, font: CGFloat) -> CGSize {
        CGSize(width: CGFloat(s.count) * font * 0.56 + 14, height: font * 1.35 + 6)
    }

    /// Where a vector should start so its shaft leaves the body's EDGE instead of being buried in it.
    public static func shaftStart(center: CGPoint, angle: Double, body: MGItem?, _ vp: MGViewport) -> CGPoint {
        guard let body, body.kind == .body || body.kind == .node else { return center }
        let dx = cos(angle * .pi / 180), dy = -sin(angle * .pi / 180)
        let distance: CGFloat
        if body.kind == .node || body.has("ball") {
            distance = vp.length(body.kind == .node ? body.n("r", 0.5) : body.n("size", 1) / 2)
        } else {
            // Ray from the centre of a rotated square: distance to its edge along the arrow.
            let half = vp.length(body.n("size", 1) / 2)
            let rel = (angle - body.n("angle")) * .pi / 180
            distance = half / max(abs(CGFloat(cos(rel))), abs(CGFloat(sin(rel))))
        }
        return CGPoint(x: center.x + CGFloat(dx) * distance, y: center.y + CGFloat(dy) * distance)
    }

    public struct LabelRequest {
        public let id: String
        public let anchor: CGPoint
        /// Preferred push-out direction (screen space), e.g. along an arrow.
        public let direction: CGVector
        public let size: CGSize
    }

    /// Greedy collision-free label placement. Tries eight positions around each anchor, preferring its own direction,
    /// and picks the first that overlaps nothing placed, no obstacle and stays on screen; otherwise the least-overlap spot.
    /// Deterministic: the same scene always lays out the same way.
    public static func place(_ requests: [LabelRequest], obstacles: [CGRect], bounds: CGRect) -> [String: CGRect] {
        var placed: [CGRect] = [], out: [String: CGRect] = [:]
        for r in requests {
            let len = max(0.001, hypot(r.direction.dx, r.direction.dy))
            let base = atan2(r.direction.dy / len, r.direction.dx / len)
            var best: (rect: CGRect, cost: CGFloat)?
            // Three rings of twelve angles, nearest ring and the label's own direction first.
            search: for ring in 0..<3 {
                for (k, turn) in [0, 1, -1, 2, -2, 3, -3, 4, -4, 5, -5, 6].enumerated() {
                    let a = base + CGFloat(turn) * .pi / 6
                    let gap: CGFloat = 8 + CGFloat(ring) * (r.size.height + 6)
                    let cx = r.anchor.x + cos(a) * (r.size.width / 2 + gap), cy = r.anchor.y + sin(a) * (r.size.height / 2 + gap)
                    let rect = CGRect(x: cx - r.size.width / 2, y: cy - r.size.height / 2, width: r.size.width, height: r.size.height)
                    let preference = CGFloat(ring * 30 + k * 2)
                    var cost = preference
                    for p in placed where p.intersects(rect) { let i = p.intersection(rect); cost += i.width * i.height + 400 }
                    for o in obstacles where o.intersects(rect) { let i = o.intersection(rect); cost += (i.width * i.height) * 0.6 + 150 }
                    if !bounds.contains(rect) { let i = bounds.intersection(rect); cost += (rect.width * rect.height - (i.isNull ? 0 : i.width * i.height)) + 300 }
                    if best == nil || cost < best!.cost { best = (rect, cost) }
                    if cost <= preference { break search }
                }
            }
            if let b = best { placed.append(b.rect); out[r.id] = b.rect }
        }
        return out
    }
}

extension MGLayout {
    /// The item under a tap, or nil: the smallest footprint containing the point with a 12 pt touch slop. Ground lines,
    /// axes and highlights are never targets; `among` limits hits to semantic objects (e.g. an object list's ids).
    public static func hit(_ point: CGPoint, items: [MGItem], viewport: MGViewport, among: Set<String>? = nil) -> MGItem? {
        var best: (item: MGItem, area: CGFloat)?
        for item in items where ![.highlight, .axes].contains(item.kind) && !item.has("ground") && (among?.contains(item.id) ?? true) {
            guard let r = bounds(item, in: items, viewport), !r.isNull, r.insetBy(dx: -12, dy: -12).contains(point) else { continue }
            let area = max(r.width, 1) * max(r.height, 1)
            if best == nil || area < best!.area { best = (item, area) }
        }
        return best?.item
    }
}
