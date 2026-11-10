// SPDX-License-Identifier: Apache-2.0
import SwiftUI

/// Everything one 2D frame needs. Built by `MartyGraphicsView` each tick; pure input, so snapshots are reproducible.
public struct MGRenderInput {
    public var scene: MGScene
    public var items: [MGItem]
    public var viewport: MGViewport
    public var theme: MGTheme = .board
    /// Draw-on progress per item id, 0...1. Missing means fully drawn.
    public var appear: [String: Double] = [:]
    public var focus: String?
    /// Items to point at (selection / "look here"): glow rings.
    public var emphasis: Set<String> = []
    /// Numbered markers (item id → n) matching an object list, so list and picture correspond.
    public var markers: [String: Int] = [:]
    public var time: Double = 0
    /// Emphasised table rows (0-based, header included) and cells (row × columns + column), by table id: an
    /// explainer beat's `highlight` of `t.r2` or `t.r1c0`. Presentation only; empty by default.
    public var tableRows: [String: Set<Int>] = [:]
    public var tableCells: [String: Set<Int>] = [:]
    /// Selection uses the same resolved positions and viewport that are handed to the renderer.
    func hit(_ point: CGPoint, among selectable: Set<String>? = nil) -> MGItem? {
        MGLayout.hit(point, items: items, viewport: viewport, among: selectable)
    }
    public init(scene: MGScene, items: [MGItem], viewport: MGViewport, theme: MGTheme = .board, appear: [String: Double] = [:], focus: String? = nil, time: Double = 0) {
        self.scene = scene; self.items = items; self.viewport = viewport; self.theme = theme; self.appear = appear; self.focus = focus; self.time = time
    }
}

/// SwiftUI Canvas renderer for 2D scenes: neon-on-dark board, glowing vectors drawn on from the body's edge,
/// collision-free labels, pulsing focus. No state; `MartyGraphicsView` owns time and steps.
public enum MGCanvasRenderer {
    static let layer: [MGKind: Int] = [.axes: 0, .plot: 0, .bars: 0, .incline: 1, .line: 1, .orbit: 1, .path: 2, .rope: 2, .spring: 3,
                                       .pulley: 3, .edge: 3, .body: 4, .node: 4, .array: 4, .vector: 5, .highlight: 6, .text: 7, .table: 4, .region: 0]

    public static func draw(_ input: MGRenderInput, in ctx: GraphicsContext) {
        let vp = input.viewport, theme = input.theme, size = vp.size
        // Board.
        let rect = CGRect(origin: .zero, size: size)
        ctx.fill(Path(roundedRect: rect, cornerRadius: 0),
                 with: .linearGradient(Gradient(colors: [theme.backgroundTop, theme.backgroundBottom]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
        if !input.scene.is3D { grid(ctx, vp, input.scene, theme) }

        let byID = Dictionary(input.items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var labels: [MGLayout.LabelRequest] = []
        var labelStyle: [String: (String, Color, Double)] = [:]
        var obstacles: [CGRect] = []

        // Parallel arrows on one body fan out sideways so they never hide each other.
        var fan: [String: CGFloat] = [:]
        let groups = Dictionary(grouping: input.items.filter { $0.kind == .vector && $0.ref != nil }) { "\($0.ref!)|\(Int((($0.n("angle").truncatingRemainder(dividingBy: 360)) + 360).truncatingRemainder(dividingBy: 360).rounded()))" }
        for (_, g) in groups where g.count > 1 { for (k, v) in g.enumerated() { fan[v.id] = (CGFloat(k) - CGFloat(g.count - 1) / 2) * 11 } }

        for item in input.items.sorted(by: { (layer[$0.kind] ?? 0) < (layer[$1.kind] ?? 0) }) {
            let p = ease(input.appear[item.id] ?? 1)
            let color = theme.color(item.color)
            // A selected/emphasised object's own label takes the emphasis colour (the object keeps its semantic colour),
            // so ring and words read as one.
            let labelColor = input.emphasis.contains(item.id) ? theme.color(.yellow) : color
            func label(_ text: String?, at anchor: CGPoint, dir: CGVector, alpha: Double = 1) {
                guard let text, !text.isEmpty, alpha > 0.01 else { return }
                let s = ctx.resolve(Text(text).font(.system(size: 13, weight: .semibold))).measure(in: CGSize(width: 400, height: 60))
                labels.append(.init(id: item.id + "#" + String(labels.count), anchor: anchor, direction: dir, size: CGSize(width: s.width + 14, height: s.height + 8)))
                labelStyle[labels.last!.id] = (text, labelColor, alpha)
            }
            switch item.kind {
            case .body:
                guard let c = item.pts.first.map(vp.point) else { continue }
                let pop = CGFloat(MGTimeline.spring(p * 0.9) * (p >= 1 ? 1 : 1))
                let side = vp.length(item.n("size", 1)) * max(0.01, pop)
                var body = ctx
                body.translateBy(x: c.x, y: c.y); body.rotate(by: .degrees(-item.n("angle")))
                let r = CGRect(x: -side / 2, y: -side / 2, width: side, height: side)
                let shape = item.has("ball") ? Path(ellipseIn: r) : Path(roundedRect: r, cornerRadius: side * 0.14)
                body.drawLayer { l in
                    l.addFilter(.shadow(color: color.opacity(0.55), radius: 10))
                    l.fill(shape, with: item.has("ball")
                           ? .radialGradient(Gradient(colors: [color.opacity(0.95), color.opacity(0.55)]), center: CGPoint(x: -side * 0.18, y: -side * 0.2), startRadius: 1, endRadius: side * 0.7)
                           : .linearGradient(Gradient(colors: [color.opacity(0.95), color.opacity(0.6)]), startPoint: CGPoint(x: 0, y: -side / 2), endPoint: CGPoint(x: 0, y: side / 2)))
                }
                body.stroke(shape, with: .color(.white.opacity(0.35)), lineWidth: 1.5)
                let box = CGRect(x: c.x - side / 2, y: c.y - side / 2, width: side, height: side)
                obstacles.append(box)
                if let text = item.label {
                    let t = ctx.resolve(Text(text).font(.system(size: 13, weight: .bold)).foregroundColor(.white))
                    let m = t.measure(in: CGSize(width: 300, height: 40))
                    if m.width < side * (item.has("ball") ? 0.72 : 0.9), m.height < side * 0.7 { ctx.draw(t, at: c) } else { label(text, at: CGPoint(x: c.x, y: box.maxY), dir: CGVector(dx: 0, dy: 1)) }
                }
            case .incline:
                guard let o = item.pts.first else { continue }
                let b = item.n("base"), h = b * tan(item.n("angle") * .pi / 180)
                var tri = Path(); tri.move(to: vp.point(o)); tri.addLine(to: vp.point(o + MGPoint(b, 0))); tri.addLine(to: vp.point(o + MGPoint(b, h))); tri.closeSubpath()
                ctx.fill(tri, with: .linearGradient(Gradient(colors: [color.opacity(0.32), color.opacity(0.12)]), startPoint: vp.point(o + MGPoint(b, h)), endPoint: vp.point(o)))
                ctx.stroke(tri, with: .color(color.opacity(0.85)), lineWidth: 2)
                if item.n("angle") > 1 {
                    var arc = Path(); let c = vp.point(o)
                    arc.addArc(center: c, radius: vp.length(min(1.2, b * 0.25)), startAngle: .degrees(0), endAngle: .degrees(-item.n("angle")), clockwise: true)
                    ctx.stroke(arc, with: .color(theme.color(.yellow).opacity(0.8)), lineWidth: 1.5)
                }
                label(item.label, at: vp.point(o + MGPoint(b * 0.55, h * 0.55)), dir: CGVector(dx: -0.6, dy: -1))
                obstacles.append(MGLayout.bounds(item, in: input.items, vp) ?? .null)
            case .line:
                guard item.pts.count == 2 else { continue }
                let a = vp.point(item.pts[0]), b = vp.point(item.pts[1])
                var path = Path(); path.move(to: a); path.addLine(to: b)
                let path2 = path.trimmedPath(from: 0, to: p)
                if item.has("ground") {
                    ctx.stroke(path2, with: .color(color.opacity(0.9)), lineWidth: 3)
                    let n = Int(hypot(b.x - a.x, b.y - a.y) / 14)
                    if n > 0, p >= 1 {
                        var hatch = Path(); let len = hypot(b.x - a.x, b.y - a.y), ux = (b.x - a.x) / len, uy = (b.y - a.y) / len
                        let nx = uy, ny = -ux  // screen normal: below a left-to-right line
                        for k in 0...n { let s = CGFloat(k) * 14; let q = CGPoint(x: a.x + ux * s, y: a.y + uy * s)
                            hatch.move(to: q); hatch.addLine(to: CGPoint(x: q.x - nx * 8 - ux * 6, y: q.y - ny * 8 - uy * 6)) }
                        ctx.stroke(hatch, with: .color(color.opacity(0.35)), lineWidth: 1)
                    }
                } else {
                    ctx.stroke(path2, with: .color(color.opacity(0.85)), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: item.has("dashed") ? [6, 5] : []))
                }
            case .vector:
                guard let from = item.pts.first, item.n("len") > 0 else { continue }
                let angle = item.n("angle"), body = item.ref.flatMap { byID[$0] }
                let center = vp.point(from)
                var start = MGLayout.shaftStart(center: center, angle: angle, body: body, vp)
                let full = vp.length(item.n("len"))
                let len = full * CGFloat(p)
                let dx = CGFloat(cos(angle * .pi / 180)), dy = -CGFloat(sin(angle * .pi / 180))
                if let shift = fan[item.id] { start = CGPoint(x: start.x - dy * shift, y: start.y + dx * shift) }
                let tip = CGPoint(x: start.x + dx * len, y: start.y + dy * len)
                arrow(ctx, from: start, to: tip, color: color, dashed: item.has("dashed"), width: item.has("dashed") ? 2 : 3.2)
                label(item.label, at: tip, dir: CGVector(dx: dx, dy: dy), alpha: p > 0.6 ? (p - 0.6) / 0.4 : 0)
            case .axes:
                guard let o = item.pts.first else { continue }
                let origin = vp.point(o), xEnd = vp.point(o + MGPoint(item.n("w"), 0)), yEnd = vp.point(o + MGPoint(0, item.n("h")))
                arrow(ctx, from: origin, to: xEnd, color: color, dashed: false, width: 1.5, glow: false)
                arrow(ctx, from: origin, to: yEnd, color: color, dashed: false, width: 1.5, glow: false)
                if item.list.count == 2 {
                    small(ctx, item.list[0], at: CGPoint(x: xEnd.x - 4, y: xEnd.y + 14), color: theme.subtleInk, anchor: .trailing)
                    small(ctx, item.list[1], at: CGPoint(x: yEnd.x + 10, y: yEnd.y + 4), color: theme.subtleInk, anchor: .leading)
                }
            case .plot:
                plot(ctx, item, vp, theme, color, p)
                label(item.label, at: vp.point(item.pts[0] + MGPoint(item.n("w") / 2, item.n("h"))), dir: CGVector(dx: 0, dy: -1))
                obstacles.append(MGLayout.bounds(item, in: input.items, vp) ?? .null)
            case .spring:
                guard item.pts.count == 2 else { continue }
                coil(ctx, from: vp.point(item.pts[0]), to: vp.point(item.pts[1]), coils: Int(item.n("coils", 8)), amplitude: vp.length(0.28), color: color)
                obstacles.append((MGLayout.bounds(item, in: input.items, vp) ?? .null).insetBy(dx: 0, dy: -vp.length(0.3)))
                let mid = vp.point(item.pts[0].lerp(item.pts[1], 0.5))
                label(item.label, at: CGPoint(x: mid.x, y: mid.y - vp.length(0.3)), dir: CGVector(dx: 0, dy: -1))
            case .pulley:
                guard let c = item.pts.first.map(vp.point) else { continue }
                let r = vp.length(item.n("r"))
                let disc = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
                ctx.fill(disc, with: .radialGradient(Gradient(colors: [color.opacity(0.5), color.opacity(0.15)]), center: c, startRadius: 0, endRadius: r))
                ctx.stroke(disc, with: .color(color), lineWidth: 2.5)
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8)), with: .color(theme.ink))
            case .rope:
                var path = Path(); path.addLines(item.pts.map(vp.point))
                ctx.stroke(path, with: .color(theme.ink.opacity(0.75)), lineWidth: 2)
            case .orbit:
                guard let c = item.pts.first.map(vp.point) else { continue }
                let r = vp.length(item.n("r"))
                let ring = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
                ctx.stroke(ring.trimmedPath(from: 0, to: p), with: .color(color.opacity(0.7)), style: StrokeStyle(lineWidth: 2, dash: [7, 6]))
                label(item.label, at: CGPoint(x: c.x, y: c.y - r), dir: CGVector(dx: 0.4, dy: -1))
            case .path:
                guard item.pts.count > 1 else { continue }
                var path = Path(); path.addLines(item.pts.map(vp.point))
                ctx.drawLayer { l in
                    l.addFilter(.shadow(color: color.opacity(0.6), radius: 5))
                    l.stroke(path.trimmedPath(from: 0, to: p), with: .color(color.opacity(0.9)),
                             style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round, dash: item.has("dashed") ? [6, 6] : []))
                }
            case .text:
                guard let at = item.pts.first.map(vp.point), let s = item.text else { continue }
                let opacity = p
                if item.has("callout") {
                    let t = ctx.resolve(Text(s).font(.system(size: 15, weight: .semibold)).foregroundColor(theme.ink))
                    let m = t.measure(in: CGSize(width: vp.size.width * 0.8, height: 200))
                    let box = CGRect(x: at.x - m.width / 2 - 12, y: at.y - m.height / 2 - 7, width: m.width + 24, height: m.height + 14)
                    var c = ctx; c.opacity = opacity
                    c.fill(Path(roundedRect: box, cornerRadius: 12), with: .color(theme.labelFill))
                    c.stroke(Path(roundedRect: box, cornerRadius: 12), with: .color(color.opacity(0.9)), lineWidth: 1.5)
                    c.fill(Path(CGRect(x: box.minX + 6, y: box.minY + 7, width: 3, height: box.height - 14)), with: .color(color))
                    c.draw(t, in: CGRect(x: at.x - m.width / 2 + 2, y: at.y - m.height / 2, width: m.width + 2, height: m.height))
                    obstacles.append(box)
                } else if item.has("code") {
                    // Monospaced and left-aligned at `at`, so indented lines stack into a readable listing.
                    let t = ctx.resolve(Text(s).font(.system(size: 14, weight: .medium, design: .monospaced)).foregroundColor(color))
                    var c = ctx; c.opacity = opacity; c.draw(t, at: at, anchor: .leading)
                    let m = t.measure(in: CGSize(width: 600, height: 100))
                    obstacles.append(CGRect(x: at.x, y: at.y - m.height / 2, width: m.width, height: m.height))
                } else {
                    let t = ctx.resolve(Text(s).font(.system(size: item.has("title") ? 20 : 14, weight: item.has("title") ? .bold : .medium)).foregroundColor(color))
                    var c = ctx; c.opacity = opacity; c.draw(t, at: at)
                    let m = t.measure(in: CGSize(width: 600, height: 100))
                    obstacles.append(CGRect(x: at.x - m.width / 2, y: at.y - m.height / 2, width: m.width, height: m.height))
                }
            case .highlight:
                guard let target = item.ref.flatMap({ byID[$0] }), let r = MGLayout.bounds(target, in: input.items, vp) else { continue }
                let pulse = 0.55 + 0.45 * sin(input.time * 4)
                let box = r.insetBy(dx: -10, dy: -10)
                let shape = target.kind == .node || target.has("ball") ? Path(ellipseIn: box) : Path(roundedRect: box, cornerRadius: 12)
                ctx.drawLayer { l in
                    l.opacity = p
                    l.addFilter(.shadow(color: color.opacity(0.9), radius: 12))
                    if target.kind != .node { l.fill(shape, with: .color(color.opacity(0.10))) }
                    l.stroke(shape, with: .color(color.opacity(pulse)), lineWidth: 2.5)
                }
                label(item.label, at: CGPoint(x: box.midX, y: box.minY), dir: CGVector(dx: 0, dy: -1))
            case .bars:
                bars(ctx, item, vp, theme, p)
                obstacles.append(MGLayout.bounds(item, in: input.items, vp) ?? .null)
            case .array:
                array(ctx, item, vp, theme, color, p)
                obstacles.append(MGLayout.bounds(item, in: input.items, vp) ?? .null)
                if let l = item.label, let c = item.pts.first {
                    label(l, at: vp.point(c + MGPoint(0, item.n("cell", 1) / 2)), dir: CGVector(dx: 0, dy: -1))
                }
            case .region:
                guard item.pts.count >= 3 else { continue }
                var shape = Path(); shape.addLines(item.pts.map(vp.point)); shape.closeSubpath()
                var layer = ctx; layer.opacity = p
                layer.fill(shape, with: .color(color.opacity(0.20)))
                layer.stroke(shape, with: .color(color.opacity(0.85)), style: StrokeStyle(lineWidth: 1.8, dash: item.has("dashed") ? [6, 5] : []))
                if let r = MGLayout.bounds(item, in: input.items, vp) { label(item.label, at: CGPoint(x: r.midX, y: r.minY), dir: CGVector(dx: 0, dy: -1)) }
            case .table:
                // A table with no data row is not drawn (`MGItem.isEmptyTable`): no header-only grid before its first fill.
                guard !item.isEmptyTable else { continue }
                table(ctx, item, vp, theme, color, p, rows: input.tableRows[item.id] ?? [], cells: input.tableCells[item.id] ?? [])
                if let r = MGLayout.bounds(item, in: input.items, vp) {
                    obstacles.append(r)
                    if let l = item.label {
                        // The caption fades in with the grid instead of appearing before any row.
                        var caption = ctx; caption.opacity = p
                        caption.draw(Text(l).font(.system(size: 13, weight: .bold)).foregroundColor(theme.ink), at: CGPoint(x: r.minX + 2, y: r.minY - 12), anchor: .leading)
                    }
                }
            case .node:
                guard let c = item.pts.first.map(vp.point) else { continue }
                let r = vp.length(item.n("r", 0.5)) * CGFloat(MGTimeline.spring(p * 0.9))
                let disc = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
                ctx.drawLayer { l in
                    l.addFilter(.shadow(color: color.opacity(0.5), radius: 8))
                    l.fill(disc, with: .radialGradient(Gradient(colors: [color.opacity(0.55), color.opacity(0.22)]), center: c, startRadius: 0, endRadius: r))
                }
                ctx.stroke(disc, with: .color(color), lineWidth: 2)
                if let s = item.text { ctx.draw(Text(s).font(.system(size: max(10, min(18, r * 0.8)), weight: .bold, design: .rounded)).foregroundColor(theme.ink), at: c) }
                obstacles.append(CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
            case .edge:
                guard let a = item.ref.flatMap({ byID[$0] }), let b = item.ref2.flatMap({ byID[$0] }),
                      let pa = a.pts.first.map(vp.point), let pb = b.pts.first.map(vp.point) else { continue }
                let d = hypot(pb.x - pa.x, pb.y - pa.y); guard d > 1 else { continue }
                let ux = (pb.x - pa.x) / d, uy = (pb.y - pa.y) / d
                let ra = vp.length(a.n("r", 0.5)), rb = vp.length(b.n("r", 0.5)) + (item.has("dir") ? 2 : 0)
                let s = CGPoint(x: pa.x + ux * ra, y: pa.y + uy * ra)
                let e = CGPoint(x: s.x + (pb.x - ux * rb - s.x) * CGFloat(p), y: s.y + (pb.y - uy * rb - s.y) * CGFloat(p))
                if item.has("dir") { arrow(ctx, from: s, to: e, color: color, dashed: false, width: 2, glow: false) }
                else { var path = Path(); path.move(to: s); path.addLine(to: e); ctx.stroke(path, with: .color(color), lineWidth: 2) }
                label(item.label, at: CGPoint(x: (s.x + e.x) / 2, y: (s.y + e.y) / 2), dir: CGVector(dx: -uy, dy: ux))
            }
        }

        // Emphasis rings, then numbered markers (object list ↔ board), drawn under labels.
        for id in input.emphasis.sorted() {
            guard let target = byID[id], let r = MGLayout.bounds(target, in: input.items, vp) else { continue }
            let box = r.insetBy(dx: -9, dy: -9), glow = theme.color(.yellow)
            ctx.drawLayer { l in
                l.addFilter(.shadow(color: glow.opacity(0.9), radius: 10))
                l.stroke(Path(roundedRect: box, cornerRadius: 10), with: .color(glow.opacity(0.9)), lineWidth: 2.5)
            }
        }
        for (id, n) in input.markers.sorted(by: { $0.value < $1.value }) {
            guard let target = byID[id], let r = MGLayout.bounds(target, in: input.items, vp) else { continue }
            let c = markerSpot(target, r, vp, body: target.ref.flatMap { byID[$0] })
            obstacles.append(CGRect(x: c.x - 12, y: c.y - 12, width: 24, height: 24))   // labels steer around markers
            let disc = Path(ellipseIn: CGRect(x: c.x - 10, y: c.y - 10, width: 20, height: 20))
            let ring = input.emphasis.contains(id) ? theme.color(.yellow) : theme.subtleInk
            ctx.fill(disc, with: .color(theme.labelFill))
            ctx.stroke(disc, with: .color(ring), lineWidth: 1.5)
            ctx.draw(Text("\(n)").font(.system(size: 11, weight: .bold, design: .rounded)).foregroundColor(theme.ink), at: c)
        }
        // Focus ring (step focus), drawn under labels so text stays readable.
        if let f = input.focus, let target = byID[f], target.kind != .highlight, let r = MGLayout.bounds(target, in: input.items, vp) {
            let pulse = 0.35 + 0.35 * (0.5 + 0.5 * sin(input.time * 3.2))
            let box = r.insetBy(dx: -8, dy: -8)
            ctx.stroke(Path(roundedRect: box, cornerRadius: 10), with: .color(theme.ink.opacity(pulse)), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
        }

        let placed = MGLayout.place(labels, obstacles: obstacles.filter { !$0.isNull }, bounds: rect.insetBy(dx: 4, dy: 4))
        for r in labels {
            guard let box = placed[r.id], let (text, color, alpha) = labelStyle[r.id] else { continue }
            var c = ctx; c.opacity = alpha
            c.fill(Path(roundedRect: box, cornerRadius: 7), with: .color(theme.labelFill))
            c.stroke(Path(roundedRect: box, cornerRadius: 7), with: .color(color.opacity(0.55)), lineWidth: 1)
            c.draw(Text(text).font(.system(size: 13, weight: .semibold)).foregroundColor(theme.ink), at: CGPoint(x: box.midX, y: box.midY))
        }
    }

    // MARK: pieces

    /// Where an object's number sits, always touching its object: arrows beside their midpoint, a slope just above the
    /// middle of its surface, everything else at its top-left corner.
    static func markerSpot(_ item: MGItem, _ r: CGRect, _ vp: MGViewport, body: MGItem? = nil) -> CGPoint {
        if item.kind == .incline, let o = item.pts.first {
            let th = item.n("angle"), b = item.n("base"), len = b / max(cos(th * .pi / 180), 1e-6)
            return vp.point(o + MGPoint.polar(th, len * 0.38) + MGPoint.polar(th + 90, 0.45))
        }
        if item.kind == .vector, let from = item.pts.first {
            // Along the drawn shaft (which starts at the body's edge), 60% of the way, offset to the arrow's left.
            let a = item.n("angle") * .pi / 180, dx = CGFloat(cos(a)), dy = -CGFloat(sin(a))
            let start = MGLayout.shaftStart(center: vp.point(from), angle: item.n("angle"), body: body, vp)
            let along = vp.length(item.n("len")) * 0.6
            return CGPoint(x: start.x + dx * along + dy * 15, y: start.y + dy * along - dx * 15)
        }
        return CGPoint(x: r.minX + 2, y: r.minY + 2)
    }

    static func ease(_ p: Double) -> Double { let x = min(1, max(0, p)); return 1 - pow(1 - x, 3) }

    static func grid(_ ctx: GraphicsContext, _ vp: MGViewport, _ scene: MGScene, _ theme: MGTheme) {
        var dots = Path()
        let stepWorld = max(1, (scene.width / 24).rounded())
        var x = 0.0
        while x <= scene.width {
            var y = 0.0
            while y <= scene.height { let p = vp.point(MGPoint(x, y)); dots.addEllipse(in: CGRect(x: p.x - 1, y: p.y - 1, width: 2, height: 2)); y += stepWorld }
            x += stepWorld
        }
        ctx.fill(dots, with: .color(theme.grid))
    }

    static func arrow(_ ctx: GraphicsContext, from a: CGPoint, to b: CGPoint, color: Color, dashed: Bool, width: CGFloat, glow: Bool = true) {
        let d = hypot(b.x - a.x, b.y - a.y); guard d > 0.5 else { return }
        let ux = (b.x - a.x) / d, uy = (b.y - a.y) / d
        let head = min(14, max(7, d * 0.35)) * (width > 2.5 ? 1 : 0.8)
        let base = CGPoint(x: b.x - ux * head, y: b.y - uy * head)
        var shaft = Path(); shaft.move(to: a); shaft.addLine(to: base)
        var tip = Path()
        tip.move(to: b)
        tip.addLine(to: CGPoint(x: base.x - uy * head * 0.55, y: base.y + ux * head * 0.55))
        tip.addLine(to: CGPoint(x: base.x + uy * head * 0.55, y: base.y - ux * head * 0.55))
        tip.closeSubpath()
        ctx.drawLayer { l in
            if glow { l.addFilter(.shadow(color: color.opacity(0.75), radius: 6)) }
            l.stroke(shaft, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, dash: dashed ? [7, 5] : []))
            l.fill(tip, with: .color(color))
        }
    }

    static func small(_ ctx: GraphicsContext, _ s: String, at p: CGPoint, color: Color, anchor: UnitPoint = .center) {
        guard !s.isEmpty else { return }
        ctx.draw(Text(s).font(.system(size: 12, weight: .medium)).foregroundColor(color), at: p, anchor: anchor)
    }

    static func coil(_ ctx: GraphicsContext, from a: CGPoint, to b: CGPoint, coils: Int, amplitude: CGFloat, color: Color) {
        let d = hypot(b.x - a.x, b.y - a.y); guard d > 1 else { return }
        let ux = (b.x - a.x) / d, uy = (b.y - a.y) / d, nx = -uy, ny = ux
        let lead = d * 0.08, body = d - 2 * lead, n = max(3, coils) * 2
        var path = Path(); path.move(to: a)
        path.addLine(to: CGPoint(x: a.x + ux * lead, y: a.y + uy * lead))
        for k in 1...n {
            let s = lead + body * CGFloat(k) / CGFloat(n + 1)
            let side: CGFloat = k % 2 == 0 ? -1 : 1
            path.addLine(to: CGPoint(x: a.x + ux * s + nx * amplitude * side, y: a.y + uy * s + ny * amplitude * side))
        }
        path.addLine(to: CGPoint(x: b.x - ux * lead, y: b.y - uy * lead)); path.addLine(to: b)
        ctx.drawLayer { l in
            l.addFilter(.shadow(color: color.opacity(0.5), radius: 4))
            l.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        }
    }

    static func plot(_ ctx: GraphicsContext, _ item: MGItem, _ vp: MGViewport, _ theme: MGTheme, _ color: Color, _ p: Double) {
        guard let o = item.pts.first else { return }
        let w = item.n("w"), h = item.n("h")
        let frame = CGRect(origin: vp.point(o + MGPoint(0, h)), size: CGSize(width: vp.length(w), height: vp.length(h)))
        ctx.fill(Path(roundedRect: frame, cornerRadius: 6), with: .color(theme.labelFill.opacity(0.5)))
        var g = Path()
        for k in 1..<4 {
            let fx = frame.minX + frame.width * CGFloat(k) / 4, fy = frame.minY + frame.height * CGFloat(k) / 4
            g.move(to: CGPoint(x: fx, y: frame.minY)); g.addLine(to: CGPoint(x: fx, y: frame.maxY))
            g.move(to: CGPoint(x: frame.minX, y: fy)); g.addLine(to: CGPoint(x: frame.maxX, y: fy))
        }
        ctx.stroke(g, with: .color(theme.grid.opacity(1.5)), lineWidth: 1)
        ctx.stroke(Path(roundedRect: frame, cornerRadius: 6), with: .color(theme.subtleInk.opacity(0.5)), lineWidth: 1)
        let x0 = item.n("x0"), x1 = item.n("x1"), y0 = item.n("y0"), y1 = item.n("y1")
        let mapped = item.pts.dropFirst().map { q in
            CGPoint(x: frame.minX + frame.width * CGFloat((q.x - x0) / (x1 - x0)), y: frame.maxY - frame.height * CGFloat((q.y - y0) / (y1 - y0)))
        }
        var line = Path(); line.addLines(mapped)
        var clip = ctx; clip.clip(to: Path(frame.insetBy(dx: -2, dy: -2)))
        clip.drawLayer { l in
            l.addFilter(.shadow(color: color.opacity(0.7), radius: 5))
            l.stroke(line.trimmedPath(from: 0, to: p), with: .color(color), style: StrokeStyle(lineWidth: 2.8, lineCap: .round, lineJoin: .round))
        }
        let f = { (v: Double) in MGPhysics.format(v, unit: "") }
        small(ctx, f(x0), at: CGPoint(x: frame.minX, y: frame.maxY + 9), color: theme.subtleInk, anchor: .leading)
        small(ctx, f(x1), at: CGPoint(x: frame.maxX, y: frame.maxY + 9), color: theme.subtleInk, anchor: .trailing)
        small(ctx, f(y1), at: CGPoint(x: frame.minX - 4, y: frame.minY + 6), color: theme.subtleInk, anchor: .trailing)
        small(ctx, f(y0), at: CGPoint(x: frame.minX - 4, y: frame.maxY - 6), color: theme.subtleInk, anchor: .trailing)
        if item.list.count == 2 {
            small(ctx, item.list[0], at: CGPoint(x: frame.midX, y: frame.maxY + 22), color: theme.subtleInk)
            small(ctx, item.list[1], at: CGPoint(x: frame.minX + 6, y: frame.minY - 10), color: theme.subtleInk, anchor: .leading)
        }
    }

    static func bars(_ ctx: GraphicsContext, _ item: MGItem, _ vp: MGViewport, _ theme: MGTheme, _ p: Double) {
        guard let o = item.pts.first, !item.bars.isEmpty else { return }
        let w = vp.length(item.n("w")), h = vp.length(item.n("h"))
        let origin = vp.point(o)  // bottom-left
        let frame = CGRect(x: origin.x, y: origin.y - h, width: w, height: h)
        ctx.fill(Path(roundedRect: frame.insetBy(dx: -8, dy: -8), cornerRadius: 12), with: .color(theme.labelFill.opacity(0.6)))
        let top = max(item.bars.map { abs($0.value) }.max() ?? 1, 1e-9)
        let labelBand: CGFloat = 18, valueBand: CGFloat = 18
        let usable = h - labelBand - valueBand - (item.label == nil ? 0 : 18)
        let baseline = frame.maxY - labelBand
        let slot = w / CGFloat(item.bars.count), bw = slot * 0.56
        var axis = Path(); axis.move(to: CGPoint(x: frame.minX, y: baseline)); axis.addLine(to: CGPoint(x: frame.maxX, y: baseline))
        ctx.stroke(axis, with: .color(theme.subtleInk.opacity(0.6)), lineWidth: 1)
        for (k, b) in item.bars.enumerated() {
            let c = theme.color(b.color)
            let x = frame.minX + slot * CGFloat(k) + (slot - bw) / 2
            let bh = max(0, usable * CGFloat(abs(b.value) / top) * CGFloat(p))
            let r = CGRect(x: x, y: baseline - bh, width: bw, height: bh)
            ctx.drawLayer { l in
                l.addFilter(.shadow(color: c.opacity(0.55), radius: 6))
                l.fill(Path(roundedRect: r, cornerRadius: min(6, bw / 3)), with: .linearGradient(Gradient(colors: [c, c.opacity(0.55)]), startPoint: CGPoint(x: 0, y: r.minY), endPoint: CGPoint(x: 0, y: r.maxY)))
            }
            small(ctx, b.label, at: CGPoint(x: x + bw / 2, y: baseline + 10), color: theme.subtleInk)
            small(ctx, MGPhysics.format(b.value, unit: item.text ?? ""), at: CGPoint(x: x + bw / 2, y: baseline - bh - 9), color: theme.ink)
        }
        if let l = item.label {
            ctx.draw(Text(l).font(.system(size: 13, weight: .bold)).foregroundColor(theme.ink), at: CGPoint(x: frame.minX + 2, y: frame.minY + 6), anchor: .leading)
        }
    }

    /// Draws a table item: equal-size cells laid out from the top-left corner, each row fading in after the one above.
    /// Row 0 gets a stronger fill when `header` is set, and marked cell indices use the `.good` colour.
    static func table(_ ctx: GraphicsContext, _ item: MGItem, _ vp: MGViewport, _ theme: MGTheme, _ color: Color, _ p: Double,
                      rows emphasisRows: Set<Int> = [], cells emphasisCells: Set<Int> = []) {
        guard let c = item.pts.first else { return }
        // Items built directly through the public API skip the parser, so never convert an unchecked count.
        let rawRows = item.n("rows", 1), rawCols = item.n("cols", 1)
        guard (1...Double(MGLimits.tableRows)).contains(rawRows), (1...Double(MGLimits.tableCols)).contains(rawCols) else { return }
        let rows = Int(rawRows), cols = Int(rawCols)
        let cw = item.n("cw", 1.6), rh = item.n("rh", 0.7)
        let topLeft = vp.point(c + MGPoint(-cw * Double(cols) / 2, rh * Double(rows) / 2))
        let w = vp.length(cw), h = vp.length(rh), marked = Set(item.marked)
        for r in 0..<rows {
            let appear = min(1, max(0, p * Double(rows) - Double(r) * 0.6)); guard appear > 0 else { continue }
            var l = ctx; l.opacity = appear
            let header = r == 0 && item.has("header")
            for k in 0..<cols {
                let i = r * cols + k; guard i < item.list.count else { continue }
                let cell = CGRect(x: topLeft.x + w * CGFloat(k), y: topLeft.y + h * CGFloat(r), width: w, height: h)
                let fill = marked.contains(i) ? theme.color(.good).opacity(0.40) : header ? color.opacity(0.28) : color.opacity(0.07)
                l.fill(Path(cell.insetBy(dx: 1, dy: 1)), with: .color(fill))
                l.stroke(Path(cell), with: .color(theme.subtleInk.opacity(0.45)), lineWidth: 1)
                let size = max(10, min(16, h * 0.42))
                l.draw(Text(item.list[i]).font(.system(size: size, weight: header ? .bold : .medium, design: .rounded)).foregroundColor(theme.ink),
                       at: CGPoint(x: cell.midX, y: cell.midY))
            }
        }
        // One rounded border around the whole grid, faded with the draw-on progress.
        ctx.stroke(Path(roundedRect: CGRect(x: topLeft.x, y: topLeft.y, width: w * CGFloat(cols), height: h * CGFloat(rows)), cornerRadius: 4),
                   with: .color(color.opacity(0.8 * p)), lineWidth: 1.5)
        // Emphasised rows and cells: a glowing ring in the emphasis colour (the same colour as item emphasis).
        let glow = theme.color(.yellow)
        var boxes: [CGRect] = emphasisRows.sorted().filter { $0 < rows }.map {
            CGRect(x: topLeft.x, y: topLeft.y + h * CGFloat($0), width: w * CGFloat(cols), height: h)
        }
        boxes += emphasisCells.sorted().filter { $0 < rows * cols }.map {
            CGRect(x: topLeft.x + w * CGFloat($0 % cols), y: topLeft.y + h * CGFloat($0 / cols), width: w, height: h)
        }
        for box in boxes {
            ctx.drawLayer { l in
                l.addFilter(.shadow(color: glow.opacity(0.9), radius: 8))
                l.stroke(Path(roundedRect: box.insetBy(dx: -2, dy: -2), cornerRadius: 5), with: .color(glow.opacity(0.95 * p)), lineWidth: 2.5)
            }
        }
    }

    static func array(_ ctx: GraphicsContext, _ item: MGItem, _ vp: MGViewport, _ theme: MGTheme, _ color: Color, _ p: Double) {
        guard let c = item.pts.first else { return }
        let cell = item.n("cell", 1), n = item.list.count
        let side = vp.length(cell)
        let left = vp.point(c - MGPoint(cell * Double(n) / 2, 0))
        let marked = Set(item.marked)
        for (k, v) in item.list.enumerated() {
            let appear = min(1, max(0, p * Double(n) - Double(k) * 0.6))
            guard appear > 0 else { continue }
            let r = CGRect(x: left.x + side * CGFloat(k) + 2, y: left.y - side / 2 + 2, width: side - 4, height: side - 4)
            let fill = marked.contains(k) ? theme.color(.good) : color
            var l = ctx; l.opacity = appear
            l.fill(Path(roundedRect: r, cornerRadius: 8), with: .color(fill.opacity(marked.contains(k) ? 0.45 : 0.18)))
            l.stroke(Path(roundedRect: r, cornerRadius: 8), with: .color(fill.opacity(0.9)), lineWidth: 1.8)
            l.draw(Text(v).font(.system(size: max(11, min(20, side * 0.38)), weight: .bold, design: .rounded)).foregroundColor(theme.ink), at: CGPoint(x: r.midX, y: r.midY))
            small(l, String(k), at: CGPoint(x: r.midX, y: r.minY - 9), color: theme.subtleInk.opacity(0.8))
        }
        // Pointers below their cell; several on one cell stack downward.
        var stack: [Int: Int] = [:]
        let accent = theme.color(.yellow)
        for ptr in item.pointers {
            let slot = Int(ptr.index.rounded()), level = stack[slot, default: 0]; stack[slot] = level + 1
            let x = left.x + side * (CGFloat(ptr.index) + 0.5), y = left.y + side / 2 + 6 + CGFloat(level) * 22
            var tri = Path(); tri.move(to: CGPoint(x: x, y: y)); tri.addLine(to: CGPoint(x: x - 7, y: y + 10)); tri.addLine(to: CGPoint(x: x + 7, y: y + 10)); tri.closeSubpath()
            ctx.drawLayer { l in l.addFilter(.shadow(color: accent.opacity(0.8), radius: 5)); l.fill(tri, with: .color(accent)) }
            ctx.draw(Text(ptr.label).font(.system(size: 12, weight: .heavy, design: .rounded)).foregroundColor(accent), at: CGPoint(x: x + 14, y: y + 6), anchor: .leading)
        }
    }
}
