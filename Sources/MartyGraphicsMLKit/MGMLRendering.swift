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

public enum MGMLComposition: Sendable {
    case fullFrame
    /// On a landscape canvas, reserve the left 45% for an editor's camera.
    case rightColumn
}

extension MGMLDocument {
    public static let framesPerSecond = 30

    public var frameCount: Int { items.reduce(0) { $0 + $1.content.frameCount } }

    /// Draws a checked frame. The alpha option keeps the canvas clear for compositing.
    public func frame(_ index: Int, size: MGMLSize, theme: MGTheme = .mlBoard, transparent: Bool = false) throws -> CGImage {
        try frame(index, size: size, theme: theme, transparent: transparent, composition: .fullFrame)
    }

    public func frame(_ index: Int, size: MGMLSize, theme: MGTheme = .mlBoard, transparent: Bool = false,
                      composition: MGMLComposition) throws -> CGImage {
        let frame = try locate(index)
        return try draw(frame.item, at: frame.offset, size: size, theme: theme, transparent: transparent,
                        composition: composition)
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

    func draw(_ item: MLItem, at frame: Int, size: MGMLSize, theme: MGTheme, transparent: Bool,
              composition: MGMLComposition) throws -> CGImage {
        let board = try MLBoard(size: size, theme: theme, transparent: transparent, composition: composition)
        board.text(title, x: board.panel.midX, y: board.panel.minY + MLStyle.titleOffset,
                   size: MLStyle.title, maxWidth: board.panel.width)
        switch item.content {
        case .vision(let vision): board.vision(vision)
        case .probabilities(let probabilities): board.probabilities(probabilities, frame: frame)
        case .agent(let agent): board.agent(agent)
        case .picture(let picture): board.picture(picture, frame: frame)
        case .meaningMap(let map): board.meaningMap(map, frame: frame)
        case .generation(let generation): board.generation(generation, frame: frame)
        case .attention(let attention): board.attention(attention, frame: frame)
        }
        guard let image = board.context.makeImage() else { throw MGMLReason.raster }
        return image
    }
}

extension MLItem.Content {
    var frameCount: Int {
        switch self {
        case .vision, .agent: return 90
        case .meaningMap: return 150
        case .generation(let generation): return generation.frameCount
        case .attention: return MLAttention.frameCount
        case .picture(let picture): return picture.frameCount
        case .probabilities(let probabilities): return probabilities.frameCount
        }
    }

    /// A key for consecutive frames with identical pixels, to avoid redrawing static holds.
    func imageKey(_ offset: Int) -> Int {
        switch self {
        case .probabilities(let probabilities): return probabilities.imageKey(offset)
        case .picture(let picture): return picture.imageKey(offset)
        case .meaningMap: return offset >= 63 ? 99 : max(0, offset - 12) / 4
        case .generation(let generation): return generation.imageKey(offset)
        case .attention: return min(max(offset, MLAttention.revealFrame),
                                    MLAttention.revealFrame + MLAttention.transitionFrames)
        default: return 0
        }
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
        let previous = distributions[max(0, index - 1)]
        let unit = min(1, Double(offset + 1) / Double(Self.transitionFrames))
        let progress = unit * unit * (3 - 2 * unit)
        let values = unit == 1 ? stage.probabilities : zip(previous.probabilities, stage.probabilities).map { start, end in
            (1 - progress) * start + progress * end
        }
        return (unit == 1 ? stage : previous, values, index == distributions.count - 1 && unit == 1)
    }
}

extension MGTheme {
    /// The ML explainer palette uses the portfolio's dark stage colors.
    public static let mlBoard: MGTheme = {
        func rgb(_ value: UInt32) -> Color {
            Color(red: Double(value >> 16) / 255, green: Double((value >> 8) & 255) / 255,
                  blue: Double(value & 255) / 255)
        }
        var theme = MGTheme.board
        theme.backgroundTop = rgb(0x1A1312)
        theme.backgroundBottom = rgb(0x07080C)
        theme.ink = rgb(0xFBEFE8)
        theme.subtleInk = rgb(0xCFB1A7)
        theme.palette[.accent] = rgb(0xFFD9CB)
        theme.palette[.muted] = rgb(0xCFB1A7)
        return theme
    }()
}

enum MLTextFace {
    case label, heading, mono

    private static let fonts: (display: CTFontDescriptor?, mono: CTFontDescriptor?) = {
        guard let path = ProcessInfo.processInfo.environment["MARTY_ML_FONT_DIR"] else { return (nil, nil) }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        func descriptor(_ name: String) -> CTFontDescriptor? {
            (CTFontManagerCreateFontDescriptorsFromURL(directory.appendingPathComponent(name) as CFURL)
                as? [CTFontDescriptor])?.first
        }
        return (descriptor("BricolageGrotesque.ttf"), descriptor("DMMono-Regular.ttf"))
    }()

    func font(size: Double) -> CTFont {
        if self == .mono, let descriptor = Self.fonts.mono {
            return CTFontCreateWithFontDescriptor(descriptor, size, nil)
        }
        if self != .mono, let descriptor = Self.fonts.display {
            // OpenType variation axis tag 'wght'.
            let styled = CTFontDescriptorCreateCopyWithVariation(descriptor, NSNumber(value: 0x77676874) as CFNumber,
                                                                 self == .heading ? 600 : 500)
            return CTFontCreateWithFontDescriptor(styled, size, nil)
        }
        let fallback = self == .mono ? "Menlo-Regular" : self == .heading ? "Helvetica-Bold" : "Helvetica"
        return CTFontCreateWithName(fallback as CFString, size, nil)
    }
}

enum MLTextAlignment { case left, center, right }

final class MLBoard {
    let context: CGContext
    let panel: CGRect
    let size: MGMLSize
    private let theme: MGTheme
    let ink: CGColor
    let subtle: CGColor
    private var colors: [MGColorRole: CGColor] = [:]

    init(size: MGMLSize, theme: MGTheme, transparent: Bool, composition: MGMLComposition = .fullFrame) throws {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: size.width, height: size.height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw MGMLReason.raster }
        self.context = context
        self.size = size
        self.theme = theme
        ink = Self.color(theme.ink)
        subtle = Self.color(theme.subtleInk)
        let scale = Double(min(size.width, size.height)) / MLStyle.shortSide
        let width = Double(size.width) / scale, height = Double(size.height) / scale
        let inset = size == .portrait ? 64.0 / scale : MLStyle.inset
        let top = size == .portrait ? 220.0 / scale : 0
        let bottom = size == .portrait ? 1500.0 / scale : height
        let left = size == .landscape && composition == .rightColumn ? width * 0.45 + inset : inset
        panel = CGRect(x: left, y: top, width: width - inset - left, height: bottom - top)
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

    private func attributed(_ label: String, size: Double, face: MLTextFace, color: CGColor,
                            tracking: Double = 0) -> NSAttributedString {
        NSAttributedString(string: label, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): face.font(size: size),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
            NSAttributedString.Key(kCTKernAttributeName as String): tracking
        ])
    }

    func textWidth(_ label: String, size: Double, face: MLTextFace, tracking: Double = 0) -> Double {
        let content = attributed(label, size: size, face: face, color: ink, tracking: tracking)
        return CTLineGetTypographicBounds(CTLineCreateWithAttributedString(content), nil, nil, nil)
    }

    func text(_ label: String, x: Double, y: Double, size: Double, maxWidth: Double, color: CGColor? = nil,
              face: MLTextFace? = nil, alignment: MLTextAlignment = .center, tracking: Double = 0,
              lineSpacing: Double = 1.12) {
        let face = face ?? (size >= MLStyle.heading ? .heading : .label)
        let naturalWidth = textWidth(label, size: size, face: face, tracking: tracking)
        let fittedSize = max(MLStyle.minimumText, size * min(1, maxWidth / max(1, naturalWidth)))
        let content = attributed(label, size: fittedSize, face: face, color: color ?? ink, tracking: tracking)
        let typesetter = CTTypesetterCreateWithAttributedString(content)
        var lines: [CTLine] = []
        var offset = 0
        while offset < content.length {
            let count = max(1, CTTypesetterSuggestLineBreak(typesetter, offset, maxWidth + 0.01))
            lines.append(CTTypesetterCreateLine(typesetter, CFRange(location: offset, length: count)))
            offset += count
        }
        let pitch = fittedSize * lineSpacing
        for (index, line) in lines.enumerated() {
            var ascent: CGFloat = 0, descent: CGFloat = 0
            let width = CTLineGetTypographicBounds(line, &ascent, &descent, nil) - CTLineGetTrailingWhitespaceWidth(line)
            let left = x - (alignment == .left ? 0 : alignment == .right ? width : width / 2)
            let center = y + (Double(index) - Double(lines.count - 1) / 2) * pitch
            context.saveGState()
            context.translateBy(x: left, y: center + (ascent - descent) / 2)
            context.scaleBy(x: 1, y: -1)
            context.textMatrix = .identity
            context.textPosition = .zero
            CTLineDraw(line, context)
            context.restoreGState()
        }
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

    func card(_ rect: CGRect, role: MGColorRole = .accent, emphasized: Bool = false, radius: Double = MLStyle.radius, review: Bool = false) {
        let tint = color(role)
        let opacity = review ? 0.22 : emphasized ? MLStyle.emphasisOpacity : MLStyle.cardOpacity
        fill(rect, color: tint.copy(alpha: opacity) ?? tint, radius: radius)
        context.setStrokeColor(tint.copy(alpha: review ? 1 : emphasized ? 0.9 : opacity * 3) ?? tint)
        context.setLineWidth(review ? 2 : 1)
        context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
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
        let dx = cos(angle), dy = sin(angle)
        let base = CGPoint(x: end.x - 12 * dx, y: end.y - 12 * dy)
        let halfWidth = 7.0 / 1.5
        context.setFillColor(tint)
        context.move(to: end)
        context.addLine(to: CGPoint(x: base.x - halfWidth * dy, y: base.y + halfWidth * dx))
        context.addLine(to: CGPoint(x: base.x + halfWidth * dy, y: base.y - halfWidth * dx))
        context.closePath()
        context.fillPath()
    }

    private static let chipGap = 8.0
    private static let chipPadding = 22.0 / 1.5

    func chipWidth(_ token: String) -> Double {
        ceil(textWidth(token, size: MLStyle.detail, face: .label)) + 2 * Self.chipPadding
    }

    func tokenGroupWidth(_ tokens: [String]) -> Double {
        tokens.reduce(0) { $0 + chipWidth($1) } + Double(tokens.count - 1) * Self.chipGap
    }

    @discardableResult
    func tokens(_ tokens: [String], in rect: CGRect, role: MGColorRole) -> Double {
        let gap = Self.chipGap, padding = Self.chipPadding
        var rows: [[(label: String, width: Double)]] = [[]]
        var used = 0.0
        for token in tokens {
            let width = min(rect.width, chipWidth(token))
            if used + gap + width > rect.width, used > 0 {
                rows.append([])
                used = 0
            }
            rows[rows.count - 1].append((token, width))
            used += used == 0 ? width : gap + width
        }
        for (index, row) in rows.enumerated() {
            let width = row.reduce(0) { $0 + $1.width } + Double(row.count - 1) * gap
            var x = rect.midX - width / 2
            for (token, width) in row {
                let chip = CGRect(x: x, y: rect.minY + Double(index) * (MLStyle.tokenHeight + gap),
                                  width: width, height: MLStyle.tokenHeight)
                card(chip, role: role)
                text(token, x: chip.midX, y: chip.midY, size: MLStyle.detail, maxWidth: width - 2 * padding)
                x += width + gap
            }
        }
        return Double(rows.count) * (MLStyle.tokenHeight + gap) - gap
    }

    static func number(_ value: Double, precision: String = "%.4g") -> String {
        String(format: precision, locale: Locale(identifier: "en_US_POSIX"), value == 0 ? 0 : value)
    }
}
