// SPDX-License-Identifier: Apache-2.0
import CoreGraphics
import CoreText
import Foundation
import MartyGraphics
import SwiftUI

public enum MGMLSize: String, CaseIterable, Sendable {
    case landscape = "1920x1080"
    case square = "1080x1080"
    case portrait = "1080x1920"

    public var width: Int { self == .landscape ? 1920 : 1080 }
    public var height: Int { self == .portrait ? 1920 : 1080 }
}

extension MGMLDocument {
    public static let framesPerSecond = 30

    public var frameCount: Int { items.reduce(0) { $0 + $1.content.frameCount } }

    /// Draws a checked frame. The alpha option keeps the canvas clear for compositing.
    public func frame(_ index: Int, size: MGMLSize, theme: MGTheme = .board, transparent: Bool = false) throws -> CGImage {
        let frame = try locate(index)
        return try draw(frame.item, at: frame.offset, size: size, theme: theme, transparent: transparent)
    }

    func locate(_ index: Int) throws -> (item: MLItem, offset: Int) {
        guard index >= 0 else { throw MGMLReason.frame }
        var offset = index
        for item in items {
            if offset < item.content.frameCount { return (item, offset) }
            offset -= item.content.frameCount
        }
        throw MGMLReason.frame
    }

    func draw(_ item: MLItem, at frame: Int, size: MGMLSize, theme: MGTheme, transparent: Bool) throws -> CGImage {
        let board = try MLBoard(size: size, theme: theme, transparent: transparent)
        board.text(title, x: board.panel.midX, y: board.panel.minY + MLStyle.titleOffset,
                   size: MLStyle.title, maxWidth: board.panel.width)
        switch item.content {
        case .vision(let vision): board.vision(vision)
        case .probabilities(let probabilities): board.probabilities(probabilities, frame: frame)
        case .agent(let agent): board.agent(agent)
        }
        guard let image = board.context.makeImage() else { throw MGMLReason.raster }
        return image
    }
}

extension MLItem.Content {
    var frameCount: Int {
        switch self {
        case .vision, .agent: return 90
        case .probabilities(let probabilities): return probabilities.frameCount
        }
    }

    /// A key for consecutive frames with identical pixels, to avoid redrawing static holds.
    func imageKey(_ offset: Int) -> Int {
        guard case .probabilities(let probabilities) = self else { return 0 }
        return probabilities.imageKey(offset)
    }
}

extension MLProbabilities {
    static let introFrames = 30
    static let stageFrames = 42
    static let transitionFrames = 15

    var frameCount: Int { Self.introFrames + Self.stageFrames * distributions.count }

    func imageKey(_ frame: Int) -> Int {
        guard frame >= Self.introFrames else { return 0 }
        let start = frame - (frame - Self.introFrames) % Self.stageFrames
        return min(frame, start + Self.transitionFrames)
    }

    func displayed(at frame: Int) -> (stage: Distribution, values: [Double], selection: Bool)? {
        guard frame >= Self.introFrames else { return nil }
        let index = (frame - Self.introFrames) / Self.stageFrames
        let stage = distributions[index]
        let offset = (frame - Self.introFrames) % Self.stageFrames
        let previous = index > 0 ? distributions[index - 1].probabilities : stage.probabilities
        let unit = min(1, Double(offset + 1) / Double(Self.transitionFrames))
        let progress = unit * unit * (3 - 2 * unit)
        let values = unit == 1 ? stage.probabilities : zip(previous, stage.probabilities).map { start, end in
            (1 - progress) * start + progress * end
        }
        return (stage, values, index == distributions.count - 1 && unit == 1)
    }
}

final class MLBoard {
    let context: CGContext
    let panel: CGRect
    private let theme: MGTheme
    let ink: CGColor
    let subtle: CGColor
    private var colors: [MGColorRole: CGColor] = [:]

    init(size: MGMLSize, theme: MGTheme, transparent: Bool) throws {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: size.width, height: size.height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw MGMLReason.raster }
        self.context = context
        self.theme = theme
        ink = Self.color(theme.ink)
        subtle = Self.color(theme.subtleInk)
        let scale = Double(min(size.width, size.height)) / MLStyle.shortSide
        let width = Double(size.width) / scale, height = Double(size.height) / scale
        let panelHeight = min(height, MLStyle.boardHeight)
        panel = CGRect(x: MLStyle.inset, y: (height - panelHeight) / 2,
                       width: width - MLStyle.inset * 2, height: panelHeight)
        let canvas = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        if transparent {
            context.clear(canvas)
        } else if let gradient = CGGradient(colorsSpace: space, colors: [
            Self.color(theme.backgroundTop), Self.color(theme.backgroundBottom)
        ] as CFArray, locations: [0, 1]) {
            context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size.height), end: .zero, options: [])
        }
        context.translateBy(x: 0, y: CGFloat(size.height))
        context.scaleBy(x: scale, y: -scale)
    }

    private static func color(_ color: Color) -> CGColor {
        let resolved = color.resolve(in: EnvironmentValues())
        return CGColor(srgbRed: CGFloat(resolved.red), green: CGFloat(resolved.green),
                       blue: CGFloat(resolved.blue), alpha: CGFloat(resolved.opacity))
    }

    func color(_ role: MGColorRole) -> CGColor {
        if let color = colors[role] { return color }
        let color = Self.color(theme.color(role))
        colors[role] = color
        return color
    }

    func text(_ label: String, x: Double, y: Double, size: Double, maxWidth: Double, color: CGColor? = nil) {
        let font = CTFontCreateWithName(MLStyle.font as CFString, size, nil)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: label, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color ?? ink
        ]))
        var ascent: CGFloat = 0, descent: CGFloat = 0
        let width = CTLineGetTypographicBounds(line, &ascent, &descent, nil)
        let factor = min(1, maxWidth / max(1, width))
        context.saveGState()
        context.translateBy(x: x - width * factor / 2, y: y + (ascent - descent) * factor / 2)
        context.scaleBy(x: factor, y: -factor)
        context.textMatrix = .identity
        context.textPosition = .zero
        CTLineDraw(line, context)
        context.restoreGState()
    }

    func fill(_ rect: CGRect, color: CGColor, radius: Double = 0) {
        context.setFillColor(color)
        if radius > 0 {
            context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
            context.fillPath()
        } else {
            context.fill(rect)
        }
    }

    func card(_ rect: CGRect, role: MGColorRole = .accent, emphasized: Bool = false) {
        let tint = color(role)
        let opacity = emphasized ? MLStyle.emphasisOpacity : MLStyle.cardOpacity
        fill(rect, color: tint.copy(alpha: opacity) ?? tint, radius: MLStyle.radius)
        context.setStrokeColor(tint.copy(alpha: emphasized ? 0.9 : opacity * 3) ?? tint)
        context.setLineWidth(1)
        context.addPath(CGPath(roundedRect: rect, cornerWidth: MLStyle.radius, cornerHeight: MLStyle.radius, transform: nil))
        context.strokePath()
    }

    func line(_ points: [CGPoint], color: CGColor, width: Double = MLStyle.stroke) {
        guard let first = points.first else { return }
        context.setStrokeColor(color)
        context.setLineWidth(width)
        context.setLineJoin(.round)
        context.move(to: first)
        context.addLines(between: points)
        context.strokePath()
    }

    func arrow(_ points: [CGPoint], role: MGColorRole = .muted) {
        guard points.count >= 2, let end = points.last else { return }
        let tint = color(role)
        line(points, color: tint)
        let before = points[points.count - 2]
        let angle = atan2(end.y - before.y, end.x - before.x)
        let wing = MLStyle.arrowhead
        line([CGPoint(x: end.x - wing * cos(angle - .pi / 6), y: end.y - wing * sin(angle - .pi / 6)),
              end,
              CGPoint(x: end.x - wing * cos(angle + .pi / 6), y: end.y - wing * sin(angle + .pi / 6))], color: tint)
    }

    func tokens(_ tokens: [String], in rect: CGRect, columns: Int, role: MGColorRole) {
        let gap = 4.0
        let width = (rect.width - Double(columns - 1) * gap) / Double(columns)
        for (index, token) in tokens.enumerated() {
            let chip = CGRect(x: rect.minX + Double(index % columns) * (width + gap),
                              y: rect.minY + Double(index / columns) * (MLStyle.tokenHeight + gap),
                              width: width, height: MLStyle.tokenHeight)
            card(chip, role: role)
            text(token, x: chip.midX, y: chip.midY, size: MLStyle.detail, maxWidth: chip.width - 6)
        }
    }

    func number(_ value: Double, precision: String = "%.4g") -> String {
        String(format: precision, locale: Locale(identifier: "en_US_POSIX"), value == 0 ? 0 : value)
    }
}
