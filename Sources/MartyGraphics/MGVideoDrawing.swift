// SPDX-License-Identifier: Apache-2.0
import Foundation
import CoreGraphics
import CoreText

enum MGVideoDrawing {
    static func font(_ size: Double, code: Bool = false) -> CTFont {
        CTFontCreateWithName((code ? "Menlo-Regular" : "Helvetica") as CFString, size, nil)
    }

    static func line(_ text: String, size: Double, color: CGColor = CGColor(gray: 1, alpha: 1), code: Bool = false) -> CTLine {
        CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font(size, code: code),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ]))
    }

    static func textSize(_ text: String, size: Double, code: Bool = false) -> CGSize {
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        let width = CTLineGetTypographicBounds(line(text, size: size, code: code), &ascent, &descent, &leading)
        return CGSize(width: ceil(width), height: ceil(ascent + descent + leading))
    }

    static func captionSetter(_ text: String) -> CTFramesetter {
        CTFramesetterCreateWithAttributedString(NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font(18),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1),
        ]))
    }

    static func captionHeight(_ text: String, width: Double) -> Double {
        ceil(CTFramesetterSuggestFrameSizeWithConstraints(captionSetter(text), CFRange(), nil, CGSize(width: width, height: 10000), nil).height)
    }

    static func tick(_ value: Double) -> String {
        let normalized: Double = value == 0 ? 0.0 : value
        return String(format: "%.4g", locale: Locale(identifier: "en_US_POSIX"), normalized)
    }

    static func ticks(_ element: MGVideoElement) -> [(String, CGPoint)] {
        guard let count = element.ticks else { return [] }
        let origin = CGPoint(x: element.at[0], y: element.at[1])
        let horizontal = element.range ?? element.xRange!
        let width = element.length ?? element.size![0]
        var output: [(String, CGPoint)] = []
        for index in 0..<count {
            let fraction = Double(index) / Double(count - 1)
            output.append((tick(horizontal[0] + (horizontal[1] - horizontal[0]) * fraction), CGPoint(x: origin.x + width * fraction, y: origin.y - 24)))
            if let vertical = element.yRange, let size = element.size {
                output.append((tick(vertical[0] + (vertical[1] - vertical[0]) * fraction), CGPoint(x: origin.x - 32, y: origin.y + size[1] * fraction)))
            }
        }
        return output
    }

    struct TextLayout {
        let line: CTLine
        let baseline: CGPoint
        let bounds: CGRect
    }

    static func textLayout(_ string: String, at point: CGPoint, size: Double, color: CGColor = CGColor(gray: 1, alpha: 1), code: Bool = false, centered: Bool = true) -> TextLayout {
        let measured = textSize(string, size: size, code: code)
        let rendered = line(string, size: size, color: color, code: code)
        var ascent: CGFloat = 0, descent: CGFloat = 0
        _ = CTLineGetTypographicBounds(rendered, &ascent, &descent, nil)
        let baseline = CGPoint(x: point.x - (centered ? measured.width / 2 : 0), y: point.y - (ascent - descent) / 2)
        let measuredBounds = CGRect(x: baseline.x, y: point.y - measured.height / 2, width: measured.width, height: measured.height)
        let glyphBounds = CTLineGetBoundsWithOptions(rendered, .useGlyphPathBounds).offsetBy(dx: baseline.x, dy: baseline.y)
        return TextLayout(line: rendered, baseline: baseline, bounds: measuredBounds.union(glyphBounds))
    }

    static func codeLayout(_ element: MGVideoElement, color: CGColor = CGColor(gray: 1, alpha: 1)) -> (bounds: CGRect, lines: [TextLayout], highlight: CGRect?) {
        let origin = CGPoint(x: element.at[0], y: element.at[1])
        let size = element.fontSize!
        let lines = element.lines!.enumerated().map { index, string in
            textLayout(string, at: CGPoint(x: origin.x, y: origin.y - Double(index + 1) * size * 1.4 + size * 0.4), size: size, color: color, code: true, centered: false)
        }
        var bounds = CGRect(x: origin.x, y: origin.y - Double(lines.count) * size * 1.4, width: 0, height: Double(lines.count) * size * 1.4 + 4)
        for layout in lines { bounds = bounds.union(layout.bounds) }
        bounds = bounds.insetBy(dx: -4, dy: 0)
        let highlight = element.highlightLine.map { index in
            CGRect(x: bounds.minX, y: origin.y - Double(index) * size * 1.4 - size * 0.1, width: bounds.width, height: size * 1.4)
        }
        if let highlight { bounds = bounds.union(highlight) }
        return (bounds, lines, highlight)
    }

    static func bounds(_ element: MGVideoElement) -> CGRect {
        let origin = CGPoint(x: element.at[0], y: element.at[1])
        switch element.kind {
        case "shape":
            let size = element.size!
            return CGRect(x: origin.x - size[0] / 2, y: origin.y - size[1] / 2, width: size[0], height: size[1])
        case "arrow":
            let end = element.to!
            return CGRect(x: min(origin.x, end[0]), y: min(origin.y, end[1]), width: abs(origin.x - end[0]), height: abs(origin.y - end[1])).insetBy(dx: -12, dy: -12)
        case "label":
            let size = textSize(element.text!, size: element.fontSize!)
            return CGRect(x: origin.x - size.width / 2, y: origin.y - size.height / 2, width: size.width, height: size.height)
        case "code":
            return codeLayout(element).bounds
        default:
            let width = element.length ?? element.size![0], height = element.size?[1] ?? 0
            var rect = CGRect(x: origin.x, y: origin.y, width: width, height: max(1, height)).insetBy(dx: -4, dy: -4)
            for (text, point) in ticks(element) {
                let size = textSize(text, size: 14)
                rect = rect.union(CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height))
            }
            return rect
        }
    }

    static func textBounds(_ element: MGVideoElement) -> [CGRect] {
        if ["label", "code"].contains(element.kind) { return [bounds(element)] }
        return ticks(element).map { string, point in
            let size = textSize(string, size: 14)
            return CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height)
        }
    }

    static func draw(_ elements: [MGVideoElement], plan: MGCheckedVideoPlan, frame: Int, burnCaptions: Bool) throws -> CGImage {
        guard let context = CGContext(data: nil, width: plan.canvas.width, height: plan.canvas.height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw MGError("video2d.budget.raster") }
        let background = CGColor(red: 0.035, green: 0.05, blue: 0.09, alpha: 1)
        context.setFillColor(background)
        context.fill(CGRect(x: 0, y: 0, width: plan.canvas.width, height: plan.canvas.height))
        func text(_ string: String, at point: CGPoint, size: Double, color: CGColor, code: Bool = false, centered: Bool = true, backdrop: Bool = true) {
            let layout = textLayout(string, at: point, size: size, color: color, code: code, centered: centered)
            if backdrop {
                context.setFillColor(background)
                context.fill(layout.bounds.insetBy(dx: -2, dy: 0))
            }
            context.textPosition = layout.baseline
            CTLineDraw(layout.line, context)
        }
        func segment(_ start: CGPoint, _ end: CGPoint) {
            context.move(to: start); context.addLine(to: end); context.strokePath()
        }
        let geometry = elements.filter { ["shape", "arrow"].contains($0.kind) }
        let axes = elements.filter { ["axes", "numberLine"].contains($0.kind) }
        let labels = elements.filter { ["label", "code"].contains($0.kind) }
        for element in geometry + axes + labels {
            context.saveGState()
            context.setAlpha(element.opacity ?? 1)
            let rgb = UInt32(element.color.dropFirst(), radix: 16)!
            let color = CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [Double((rgb >> 16) & 255) / 255, Double((rgb >> 8) & 255) / 255, Double(rgb & 255) / 255, 1])!
            context.setFillColor(color); context.setStrokeColor(color); context.setLineWidth(element.strokeWidth ?? 2)
            let origin = CGPoint(x: element.at[0], y: element.at[1])
            switch element.kind {
            case "shape":
                if element.shape == "rect" { context.fill(bounds(element)) } else { context.fillEllipse(in: bounds(element)) }
            case "arrow":
                let end = CGPoint(x: element.to![0], y: element.to![1])
                let angle = atan2(end.y - origin.y, end.x - origin.x)
                // The shaft stops just inside the head's base (12 · cos 0.4 back from the tip), so its square end never
                // shows past the head's flanks at the sharp tip.
                let back = min(hypot(end.x - origin.x, end.y - origin.y), 12 * cos(0.4) - min(1, (element.strokeWidth ?? 2) / 2))
                segment(origin, CGPoint(x: end.x - back * cos(angle), y: end.y - back * sin(angle)))
                context.move(to: end)
                context.addLine(to: CGPoint(x: end.x - 12 * cos(angle - 0.4), y: end.y - 12 * sin(angle - 0.4)))
                context.addLine(to: CGPoint(x: end.x - 12 * cos(angle + 0.4), y: end.y - 12 * sin(angle + 0.4)))
                context.closePath(); context.fillPath()
            case "label": text(element.text!, at: origin, size: element.fontSize!, color: color)
            case "code":
                let layout = codeLayout(element, color: color)
                context.setFillColor(background); context.fill(layout.bounds)
                if let highlight = layout.highlight {
                    context.setFillColor(CGColor(red: 0.9, green: 0.7, blue: 0.1, alpha: 0.3))
                    context.fill(highlight)
                }
                for line in layout.lines {
                    context.textPosition = line.baseline
                    CTLineDraw(line.line, context)
                }
            default:
                let width = element.length ?? element.size![0]
                segment(origin, CGPoint(x: origin.x + width, y: origin.y))
                if let size = element.size { segment(origin, CGPoint(x: origin.x, y: origin.y + size[1])) }
                for (string, point) in ticks(element) {
                    if point.y < origin.y { segment(CGPoint(x: point.x, y: origin.y - 4), CGPoint(x: point.x, y: origin.y + 4)) }
                    else { segment(CGPoint(x: origin.x - 4, y: point.y), CGPoint(x: origin.x + 4, y: point.y)) }
                    text(string, at: point, size: 14, color: color)
                }
            }
            context.restoreGState()
        }
        if burnCaptions, let caption = plan.captions.first(where: { $0.startFrame <= frame && frame < $0.endFrame }) {
            let rect = CGRect(x: 16, y: 28, width: plan.canvas.width - 32, height: 52)
            CTFrameDraw(CTFramesetterCreateFrame(captionSetter(caption.text), CFRange(), CGPath(rect: rect, transform: nil), nil), context)
        }
        text(plan.generatedMediaLabel, at: CGPoint(x: Double(plan.canvas.width) / 2, y: 14), size: 12, color: CGColor(gray: 1, alpha: 1))
        guard let image = context.makeImage() else { throw MGError("video2d.budget.raster") }
        return image
    }
}
