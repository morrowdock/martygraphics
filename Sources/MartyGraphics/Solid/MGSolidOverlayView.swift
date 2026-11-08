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
    public static func drawLegend(document doc: MGSolidDocument, in ctx: CGContext, width: Int, height: Int) {
        let empty = MGAnnotationFrame(width: Double(width), height: Double(height), fontSize: MGAnnotationLayout.fontSize(height: Double(height)),
                                      placement: [], anchors: [], refusal: nil)
        draw(empty, document: doc, legend: true, in: ctx, width: width, height: height)
    }

    /// Draws a frame's overlay into a CoreGraphics context of `width` × `height` pixels (bottom-left origin, as
    /// `CGContext` bitmaps are). `legend`: also draw the document legend in the legend corner.
    public static func draw(_ frame: MGAnnotationFrame, document doc: MGSolidDocument, legend: Bool, in ctx: CGContext, width: Int, height: Int) {
        let w = Double(width), h = Double(height)
        guard w > 0, h > 0 else { return }
        let f = MGAnnotationLayout.fontSize(height: h)
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
        let shapes = frame.placement.compactMap { Shape($0, w, h) }
        for (p, s) in zip(frame.placement, shapes) {
            let tierColor = chip(tier(doc, p.id))
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
            text(s.text, in: s.box, size: f)
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

    public init(frame: MGAnnotationFrame, document: MGSolidDocument, legend: Bool = true) {
        self.frame = frame; self.document = document; self.legend = legend
    }

    public var body: some View {
        Canvas { ctx, size in
            let w = Double(size.width), h = Double(size.height)
            guard w > 0, h > 0 else { return }
            let f = MGAnnotationLayout.fontSize(height: h)
            func color(_ c: [Double], _ a: Double = 1) -> Color { Color(.sRGB, red: c[0], green: c[1], blue: c[2], opacity: a) }
            /// Draws text inside a box: starts from the CoreText fit, then shrinks until the resolved text fits.
            func text(_ s: String, in box: CGRect, size: Double, alignRight: Bool = false) {
                let room = Double(box.width) - 12
                var fs = MGSolidOverlay.fit(s, width: room, fontSize: size).size
                var resolved = ctx.resolve(Text(s).font(.system(size: CGFloat(fs))).foregroundColor(color(MGSolidOverlay.ink, 0.96)))
                var measured = Double(resolved.measure(in: CGSize(width: 10_000, height: 1_000)).width)
                while measured > room, fs > MGSolidOverlay.minimumFont {
                    fs = max(MGSolidOverlay.minimumFont, fs * 0.95)
                    resolved = ctx.resolve(Text(s).font(.system(size: CGFloat(fs))).foregroundColor(color(MGSolidOverlay.ink, 0.96)))
                    measured = Double(resolved.measure(in: CGSize(width: 10_000, height: 1_000)).width)
                }
                let x = alignRight ? box.maxX - 6 : box.minX + 6
                ctx.draw(resolved, at: CGPoint(x: x, y: box.midY), anchor: alignRight ? .trailing : .leading)
            }
            for p in frame.placement {
                guard let s = MGSolidOverlay.Shape(p, w, h) else { continue }
                let tierColor = MGSolidOverlay.chip(MGSolidOverlay.tier(document, p.id))
                if s.callout == nil, let a = s.anchor, let e = s.leaderEnd {
                    var line = Path(); line.move(to: a); line.addLine(to: e)
                    ctx.stroke(line, with: .color(color(MGSolidOverlay.ink, 0.8)),
                               style: StrokeStyle(lineWidth: 1.2, dash: s.occluded == true ? [4, 3] : []))
                    if s.kind == "label" {
                        let dot = Path(ellipseIn: CGRect(x: a.x - 4, y: a.y - 4, width: 8, height: 8))
                        if s.occluded == true { ctx.stroke(dot, with: .color(color(MGSolidOverlay.ink)), lineWidth: 1.5) }
                        else { ctx.fill(dot, with: .color(color(MGSolidOverlay.ink))) }
                    }
                }
                if let n = s.callout, let a = s.anchor {
                    let r = CGRect(x: a.x - 9, y: a.y - 9, width: 18, height: 18)
                    ctx.fill(Path(ellipseIn: r), with: .color(color(MGSolidOverlay.fill, MGSolidOverlay.fill[3])))
                    ctx.stroke(Path(ellipseIn: r), with: .color(color(tierColor)), lineWidth: 1.5)
                    text("\(n + 1)", in: r.insetBy(dx: -6, dy: 0), size: 0.7 * f)
                }
                let box = Path(roundedRect: s.box, cornerRadius: 4)
                ctx.fill(box, with: .color(color(MGSolidOverlay.fill, MGSolidOverlay.fill[3])))
                ctx.stroke(box, with: .color(color(tierColor, 0.9)), lineWidth: 1)
                ctx.fill(Path(CGRect(x: s.box.minX + 1, y: s.box.minY + 3, width: 3, height: max(0, s.box.height - 6))), with: .color(color(tierColor)))
                text(s.text, in: s.box, size: f)
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
