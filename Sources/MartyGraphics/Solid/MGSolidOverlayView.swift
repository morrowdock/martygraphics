// SPDX-License-Identifier: Apache-2.0
import Foundation
import CoreGraphics
import CoreText
import SwiftUI

// The annotation overlay: labels, leaders, anchor dots, value texts, tier chips, callout markers and rows, and the
// legend, drawn from one `MGAnnotationFrame`. The SwiftUI view and the CoreGraphics drawer (used by `marty-solid
// render`) read the same records, so every host draws the same layout. Text is shrunk until its real width fits its
// box, so it never overflows.

public enum MGSolidOverlay {
    /// Smallest font the fit goes down to (pixels).
    public static let minimumFont = 4.0

    static func font(_ size: Double) -> CTFont {
        CTFontCreateUIFontForLanguage(.system, CGFloat(size), nil) ?? CTFontCreateWithName("Helvetica" as CFString, CGFloat(size), nil)
    }

    /// Real width of one line of text at a font size (CoreText, the system UI font).
    public static func textWidth(_ text: String, fontSize: Double) -> Double {
        let attr = NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font(fontSize)])
        return Double(CTLineGetTypographicBounds(CTLineCreateWithAttributedString(attr), nil, nil, nil))
    }

    /// The largest font size, at most `fontSize`, whose real text width fits `width` (shrinking by 5 % steps), and that
    /// width. Very long words get small; they never overflow.
    public static func fit(_ text: String, width: Double, fontSize: Double) -> (size: Double, width: Double) {
        var size = fontSize.isFinite ? max(minimumFont, fontSize) : minimumFont
        let room = width.isFinite ? max(0, width) : 0
        var w = textWidth(text, fontSize: size)
        while w > room, size > minimumFont {
            size = max(minimumFont, size * 0.95)
            w = textWidth(text, fontSize: size)
        }
        return (size, w)
    }

    /// The tier of an annotation for its chip colour, nil when it makes no claim.
    static func tier(_ doc: MGSolidDocument, _ id: String) -> MGSolidTier? {
        doc.annotations.label(id)?.tier ?? doc.annotations.arrow(id)?.tier ?? doc.annotations.dimension(id)?.tier
    }
    /// Chip colours: solved = good, built = warn, described = muted.
    static func chip(_ t: MGSolidTier?) -> [Double] {
        switch t {
        case .solved?: return MGSolidPalette.srgb(.good)
        case .built?: return MGSolidPalette.srgb(.warn)
        case .described?: return MGSolidPalette.srgb(.muted)
        case nil: return MGSolidPalette.srgb(.muted).map { $0 * 0.6 }
        }
    }
    static let ink = MGSolidPalette.srgb(.white)
    static let fill: [Double] = [10.0 / 255, 15.0 / 255, 31.0 / 255, 0.82]

    /// Pixel geometry of one record in a view of `w` × `h` (origin top-left).
    struct Shape {
        var box: CGRect, leaderEnd: CGPoint?, anchor: CGPoint?, text: String, kind: String, callout: Int?, occluded: Bool?
        init?(_ p: MGAnnotationPlacement, _ w: Double, _ h: Double) {
            guard p.box.count == 4, p.box.allSatisfy(\.isFinite) else { return nil }
            box = CGRect(x: p.box[0] * w, y: p.box[1] * h, width: p.box[2] * w, height: p.box[3] * h)
            func pt(_ v: [Double]?) -> CGPoint? { guard let v, v.count == 2, v.allSatisfy(\.isFinite) else { return nil }; return CGPoint(x: v[0] * w, y: v[1] * h) }
            leaderEnd = pt(p.leader); anchor = pt(p.anchor)
            text = p.callout.map { "\($0 + 1). " + p.text } ?? p.text
            kind = p.kind; callout = p.callout; occluded = p.occluded
        }
    }

    /// Draws only the document legend (its text and notes) in the legend corner, with no labels: for frames that show
    /// no labels but must keep the legend (`story.mp4` during a camera move).
    public static func drawLegend(document doc: MGSolidDocument, in ctx: CGContext, width: Int, height: Int, look: MGSolidLook = .classic) {
        let empty = MGAnnotationFrame(width: Double(width), height: Double(height), fontSize: MGAnnotationLayout.fontSize(height: Double(height)),
                                      placement: [], anchors: [], refusal: nil)
        draw(empty, document: doc, legend: true, in: ctx, width: width, height: height, look: look)
    }

    /// The drawn metrics of the modern overlay, every one a multiple of the font size `f`, so a larger label size
    /// scales plates, strokes and leaders together. The text box itself is the layout's and does not change.
    struct Metrics {
        var radius: Double, hairline: Double, barWidth: Double, barInset: Double, leader: Double, casing: Double, dot: Double, disc: Double
        init(_ f: Double) {
            radius = 0.45 * f; hairline = max(1, 0.06 * f); barWidth = 0.17 * f; barInset = 0.1 * f
            leader = max(1.2, 0.09 * f); casing = max(2.6, 0.22 * f); dot = 0.3 * f; disc = 0.7 * f
        }
    }

    /// Draws a frame's overlay into a CoreGraphics context of `width` × `height` pixels (bottom-left origin, as
    /// `CGContext` bitmaps are). `legend`: also draw the document legend in the legend corner.
    /// `look`: the ink, plate and casing colours; a look with `modernOverlay` draws the plates, leaders and callouts of
    /// docs/VISUAL-STYLE.md in the same boxes, `classic` (the default) draws as before.
    public static func draw(_ frame: MGAnnotationFrame, document doc: MGSolidDocument, legend: Bool, in ctx: CGContext, width: Int, height: Int,
                            look: MGSolidLook = .classic) {
        let w = Double(width), h = Double(height)
        guard w > 0, h > 0 else { return }
        let f = MGAnnotationLayout.fontSize(height: h)
        let ink = look.ink, fill = look.plate, modern = look.modernOverlay, m = Metrics(f)
        ctx.saveGState()
        // Work in top-left coordinates; text is drawn with its own unflipped matrix.
        ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: 1, y: -1)
        func color(_ c: [Double], _ a: Double = 1) -> CGColor { CGColor(srgbRed: c[0], green: c[1], blue: c[2], alpha: a) }
        func text(_ s: String, in box: CGRect, size: Double, alignRight: Bool = false) {
            let fitted = fit(s, width: Double(box.width) - 12, fontSize: size)
            let ft = font(fitted.size)
            let attr = NSAttributedString(string: s, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): ft,
                                                                   NSAttributedString.Key(kCTForegroundColorAttributeName as String): color(ink, 0.96)])
            let line = CTLineCreateWithAttributedString(attr)
            let ascent = CTFontGetAscent(ft), descent = CTFontGetDescent(ft)
            let x = alignRight ? box.maxX - 6 - CGFloat(fitted.width) : box.minX + 6
            let baseline = box.midY + (ascent - descent) / 2
            ctx.saveGState()
            ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
            ctx.textPosition = CGPoint(x: x, y: baseline)
            CTLineDraw(line, ctx)
            ctx.restoreGState()
        }
        /// A placement's text on its lines (`MGAnnotationLayout.lines`), one row each, all at the size that fits them.
        func block(_ s: String, in box: CGRect, size: Double) {
            let ls = MGAnnotationLayout.lines(s)
            guard ls.count > 1 else { return text(s, in: box, size: size) }
            let fs = ls.map { fit($0, width: Double(box.width) - 12, fontSize: size).size }.min() ?? size
            let row = max(0, box.height - 8) / CGFloat(ls.count)
            for (i, l) in ls.enumerated() {
                text(l, in: CGRect(x: box.minX, y: box.minY + 4 + CGFloat(i) * row, width: box.width, height: row), size: fs)
            }
        }
        let shapes = frame.placement.compactMap { Shape($0, w, h) }
        for (p, s) in zip(frame.placement, shapes) {
            let tierColor = chip(tier(doc, p.id))
            if modern {
                let casing = color(look.casing, look.casing.count > 3 ? look.casing[3] : 0.55)
                if s.callout == nil, let a = s.anchor, let e = s.leaderEnd {
                    // A casing under the line, so it reads over a white part and over a black one.
                    let dash: [CGFloat] = s.occluded == true ? [CGFloat(0.35 * f), CGFloat(0.25 * f)] : []
                    ctx.setLineCap(.round)
                    ctx.setStrokeColor(casing); ctx.setLineWidth(CGFloat(m.casing))
                    ctx.move(to: a); ctx.addLine(to: e); ctx.strokePath()
                    ctx.setStrokeColor(color(ink, 0.95)); ctx.setLineWidth(CGFloat(m.leader)); ctx.setLineDash(phase: 0, lengths: dash)
                    ctx.move(to: a); ctx.addLine(to: e); ctx.strokePath()
                    ctx.setLineDash(phase: 0, lengths: []); ctx.setLineCap(.butt)
                    if s.kind == "label" {
                        let d = CGFloat(m.dot), ring = CGFloat(m.casing - m.leader) / 2
                        ctx.setFillColor(casing); ctx.fillEllipse(in: CGRect(x: a.x - d - ring, y: a.y - d - ring, width: 2 * (d + ring), height: 2 * (d + ring)))
                        let dot = CGRect(x: a.x - d, y: a.y - d, width: 2 * d, height: 2 * d)
                        if s.occluded == true { ctx.setStrokeColor(color(ink)); ctx.setLineWidth(CGFloat(m.leader * 1.3)); ctx.strokeEllipse(in: dot.insetBy(dx: 1, dy: 1)) }
                        else { ctx.setFillColor(color(ink)); ctx.fillEllipse(in: dot) }
                    }
                }
                if let n = s.callout, let a = s.anchor {
                    let d = CGFloat(m.disc)
                    let r = CGRect(x: a.x - d, y: a.y - d, width: 2 * d, height: 2 * d)
                    ctx.setFillColor(color(fill, min(1, fill[3] + 0.08))); ctx.fillEllipse(in: r)
                    ctx.setStrokeColor(color(tierColor)); ctx.setLineWidth(CGFloat(max(1.5, 0.1 * f))); ctx.strokeEllipse(in: r)
                    text("\(n + 1)", in: r.insetBy(dx: -6, dy: 0), size: 0.7 * f)
                }
                let radius = CGFloat(min(m.radius, Double(s.box.height) / 2, Double(s.box.width) / 2))
                let path = CGPath(roundedRect: s.box, cornerWidth: radius, cornerHeight: radius, transform: nil)
                ctx.addPath(path); ctx.setFillColor(color(fill, fill[3])); ctx.fillPath()
                ctx.addPath(path); ctx.setStrokeColor(color(ink, 0.16)); ctx.setLineWidth(CGFloat(m.hairline)); ctx.strokePath()
                // The tier mark: a rounded bar inside the leading edge (it ends before the text's 6 px inset).
                let bar = CGRect(x: s.box.minX + CGFloat(m.barInset), y: s.box.minY + CGFloat(0.22 * f), width: CGFloat(m.barWidth),
                                 height: max(0, s.box.height - CGFloat(0.44 * f)))
                ctx.addPath(CGPath(roundedRect: bar, cornerWidth: bar.width / 2, cornerHeight: min(bar.width, bar.height) / 2, transform: nil))
                ctx.setFillColor(color(tierColor)); ctx.fillPath()
                block(s.text, in: s.box, size: f)
                continue
            }
            if s.callout == nil, let a = s.anchor, let e = s.leaderEnd {
                ctx.setStrokeColor(color(ink, 0.8)); ctx.setLineWidth(1.2)
                ctx.setLineDash(phase: 0, lengths: s.occluded == true ? [4, 3] : [])
                ctx.move(to: a); ctx.addLine(to: e); ctx.strokePath()
                ctx.setLineDash(phase: 0, lengths: [])
                if s.kind == "label" {
                    let dot = CGRect(x: a.x - 4, y: a.y - 4, width: 8, height: 8)
                    if s.occluded == true { ctx.setStrokeColor(color(ink)); ctx.setLineWidth(1.5); ctx.strokeEllipse(in: dot) }
                    else { ctx.setFillColor(color(ink)); ctx.fillEllipse(in: dot) }
                }
            }
            if let n = s.callout, let a = s.anchor {
                let r = CGRect(x: a.x - 9, y: a.y - 9, width: 18, height: 18)
                ctx.setFillColor(color(fill, fill[3])); ctx.fillEllipse(in: r)
                ctx.setStrokeColor(color(tierColor)); ctx.setLineWidth(1.5); ctx.strokeEllipse(in: r)
                text("\(n + 1)", in: r.insetBy(dx: -6, dy: 0), size: 0.7 * f)
            }
            let path = CGPath(roundedRect: s.box, cornerWidth: 4, cornerHeight: 4, transform: nil)
            ctx.addPath(path); ctx.setFillColor(color(fill, fill[3])); ctx.fillPath()
            ctx.addPath(path); ctx.setStrokeColor(color(tierColor, 0.9)); ctx.setLineWidth(1); ctx.strokePath()
            // The tier chip: a bar on the box's left edge.
            ctx.setFillColor(color(tierColor)); ctx.fill(CGRect(x: s.box.minX + 1, y: s.box.minY + 3, width: 3, height: max(0, s.box.height - 6)))
            block(s.text, in: s.box, size: f)
        }
        if legend {
            let l = doc.legend
            let lines = [l.text] + l.notes
            let rect = MGAnnotationLayout.legendRect(width: w, height: h)
            let rowH = rect.height / Double(max(lines.count, 2))
            for (i, s) in lines.enumerated() {
                let r = CGRect(x: rect.x, y: rect.y + 6 + Double(i) * rowH, width: rect.width - 6, height: rowH)
                text(s, in: r, size: min(0.8 * f, rowH * 0.75), alignRight: true)
            }
        }
        ctx.restoreGState()
    }
}

/// SwiftUI overlay of one annotation frame over a solid view of the same size (place it in a `ZStack` above the
/// SceneKit view). Hosts re-compute the frame at most every 100 ms while the camera or pose changes, passing the
/// previous frame so labels keep their places.
public struct MGSolidOverlayView: View {
    public let frame: MGAnnotationFrame
    public let document: MGSolidDocument
    public let legend: Bool
    /// The ink, plate and casing colours and the overlay style (`MGSolidOverlay.draw(_:document:legend:in:width:height:look:)`).
    public let look: MGSolidLook

    public init(frame: MGAnnotationFrame, document: MGSolidDocument, legend: Bool = true, look: MGSolidLook = .studio) {
        self.frame = frame; self.document = document; self.legend = legend; self.look = look
    }

    public var body: some View {
        Canvas { ctx, size in
            let w = Double(size.width), h = Double(size.height)
            guard w > 0, h > 0 else { return }
            let f = MGAnnotationLayout.fontSize(height: h)
            let ink = look.ink, fill = look.plate, m = MGSolidOverlay.Metrics(f)
            func color(_ c: [Double], _ a: Double = 1) -> Color { Color(.sRGB, red: c[0], green: c[1], blue: c[2], opacity: a) }
            /// Draws text inside a box: starts from the CoreText fit, then shrinks until the resolved text fits.
            func text(_ s: String, in box: CGRect, size: Double, alignRight: Bool = false) {
                let room = Double(box.width) - 12
                var fs = MGSolidOverlay.fit(s, width: room, fontSize: size).size
                var resolved = ctx.resolve(Text(s).font(.system(size: CGFloat(fs))).foregroundColor(color(ink, 0.96)))
                var measured = Double(resolved.measure(in: CGSize(width: 10_000, height: 1_000)).width)
                while measured > room, fs > MGSolidOverlay.minimumFont {
                    fs = max(MGSolidOverlay.minimumFont, fs * 0.95)
                    resolved = ctx.resolve(Text(s).font(.system(size: CGFloat(fs))).foregroundColor(color(ink, 0.96)))
                    measured = Double(resolved.measure(in: CGSize(width: 10_000, height: 1_000)).width)
                }
                let x = alignRight ? box.maxX - 6 : box.minX + 6
                ctx.draw(resolved, at: CGPoint(x: x, y: box.midY), anchor: alignRight ? .trailing : .leading)
            }
            /// A placement's text on its lines (`MGAnnotationLayout.lines`), one row each, at the size that fits them.
            func block(_ s: String, in box: CGRect, size: Double) {
                let ls = MGAnnotationLayout.lines(s)
                guard ls.count > 1 else { return text(s, in: box, size: size) }
                let fs = ls.map { MGSolidOverlay.fit($0, width: Double(box.width) - 12, fontSize: size).size }.min() ?? size
                let row = max(0, box.height - 8) / CGFloat(ls.count)
                for (i, l) in ls.enumerated() {
                    text(l, in: CGRect(x: box.minX, y: box.minY + 4 + CGFloat(i) * row, width: box.width, height: row), size: fs)
                }
            }
            for p in frame.placement {
                guard let s = MGSolidOverlay.Shape(p, w, h) else { continue }
                let tierColor = MGSolidOverlay.chip(MGSolidOverlay.tier(document, p.id))
                if look.modernOverlay {
                    let casing = color(look.casing, look.casing.count > 3 ? look.casing[3] : 0.55)
                    let cf = CGFloat(f), leader = CGFloat(m.leader), casingWidth = CGFloat(m.casing)
                    if s.callout == nil, let a = s.anchor, let e = s.leaderEnd {
                        var line = Path(); line.move(to: a); line.addLine(to: e)
                        let dash: [CGFloat] = s.occluded == true ? [0.35 * cf, 0.25 * cf] : []
                        ctx.stroke(line, with: .color(casing), style: StrokeStyle(lineWidth: casingWidth, lineCap: .round))
                        ctx.stroke(line, with: .color(color(ink, 0.95)), style: StrokeStyle(lineWidth: leader, lineCap: .round, dash: dash))
                        if s.kind == "label" {
                            let d = CGFloat(m.dot), ring = (casingWidth - leader) / 2
                            let outer = CGRect(x: a.x - d - ring, y: a.y - d - ring, width: 2 * (d + ring), height: 2 * (d + ring))
                            ctx.fill(Path(ellipseIn: outer), with: .color(casing))
                            let dot = CGRect(x: a.x - d, y: a.y - d, width: 2 * d, height: 2 * d)
                            if s.occluded == true { ctx.stroke(Path(ellipseIn: dot.insetBy(dx: 1, dy: 1)), with: .color(color(ink)), lineWidth: leader * 1.3) }
                            else { ctx.fill(Path(ellipseIn: dot), with: .color(color(ink))) }
                        }
                    }
                    if let n = s.callout, let a = s.anchor {
                        let d = CGFloat(m.disc)
                        let r = CGRect(x: a.x - d, y: a.y - d, width: 2 * d, height: 2 * d)
                        ctx.fill(Path(ellipseIn: r), with: .color(color(fill, min(1, fill[3] + 0.08))))
                        ctx.stroke(Path(ellipseIn: r), with: .color(color(tierColor)), lineWidth: max(1.5, 0.1 * cf))
                        text("\(n + 1)", in: r.insetBy(dx: -6, dy: 0), size: 0.7 * f)
                    }
                    let radius = min(CGFloat(m.radius), s.box.height / 2, s.box.width / 2)
                    let box = Path(roundedRect: s.box, cornerRadius: radius)
                    ctx.fill(box, with: .color(color(fill, fill[3])))
                    ctx.stroke(box, with: .color(color(ink, 0.16)), lineWidth: CGFloat(m.hairline))
                    let bar = CGRect(x: s.box.minX + CGFloat(m.barInset), y: s.box.minY + 0.22 * cf, width: CGFloat(m.barWidth),
                                     height: max(0, s.box.height - 0.44 * cf))
                    ctx.fill(Path(roundedRect: bar, cornerRadius: min(bar.width, bar.height) / 2), with: .color(color(tierColor)))
                    block(s.text, in: s.box, size: f)
                    continue
                }
                if s.callout == nil, let a = s.anchor, let e = s.leaderEnd {
                    var line = Path(); line.move(to: a); line.addLine(to: e)
                    ctx.stroke(line, with: .color(color(ink, 0.8)),
                               style: StrokeStyle(lineWidth: 1.2, dash: s.occluded == true ? [4, 3] : []))
                    if s.kind == "label" {
                        let dot = Path(ellipseIn: CGRect(x: a.x - 4, y: a.y - 4, width: 8, height: 8))
                        if s.occluded == true { ctx.stroke(dot, with: .color(color(ink)), lineWidth: 1.5) }
                        else { ctx.fill(dot, with: .color(color(ink))) }
                    }
                }
                if let n = s.callout, let a = s.anchor {
                    let r = CGRect(x: a.x - 9, y: a.y - 9, width: 18, height: 18)
                    ctx.fill(Path(ellipseIn: r), with: .color(color(fill, fill[3])))
                    ctx.stroke(Path(ellipseIn: r), with: .color(color(tierColor)), lineWidth: 1.5)
                    text("\(n + 1)", in: r.insetBy(dx: -6, dy: 0), size: 0.7 * f)
                }
                let box = Path(roundedRect: s.box, cornerRadius: 4)
                ctx.fill(box, with: .color(color(fill, fill[3])))
                ctx.stroke(box, with: .color(color(tierColor, 0.9)), lineWidth: 1)
                ctx.fill(Path(CGRect(x: s.box.minX + 1, y: s.box.minY + 3, width: 3, height: max(0, s.box.height - 6))), with: .color(color(tierColor)))
                block(s.text, in: s.box, size: f)
            }
            if legend {
                let l = document.legend
                let lines = [l.text] + l.notes
                let rect = MGAnnotationLayout.legendRect(width: w, height: h)
                let rowH = rect.height / Double(max(lines.count, 2))
                for (i, s) in lines.enumerated() {
                    let r = CGRect(x: rect.x, y: rect.y + 6 + Double(i) * rowH, width: rect.width - 6, height: rowH)
                    text(s, in: r, size: min(0.8 * f, rowH * 0.75), alignRight: true)
                }
            }
        }
        .allowsHitTesting(false)
    }
}
