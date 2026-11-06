// SPDX-License-Identifier: Apache-2.0
import AppKit
import AVFoundation
import CoreText
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct Failure: Error, CustomStringConvertible {
    let description: String
    init(_ s: String) { description = s }
}

// MARK: Files

enum Media {
    static func png(_ image: CGImage, to url: URL) throws {
        guard let d = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { throw Failure("PNG \(url.lastPathComponent)") }
        CGImageDestinationAddImage(d, image, nil)
        guard CGImageDestinationFinalize(d) else { throw Failure("PNG finalize \(url.lastPathComponent)") }
    }

    static func sha256(_ url: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
    }

    static func bytes(_ url: URL) -> Int { (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0 }

    static func scaled(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }

    static func newDirectory(_ path: String) throws -> URL {
        let url = URL(fileURLWithPath: path, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: url.path) else { throw Failure("Output directory already exists; choose a new directory") }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func writeJSON(_ object: Any, to url: URL) throws {
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]).write(to: url)
    }
}

final class MovieWriter {
    let writer: AVAssetWriter
    let input: AVAssetWriterInput
    let adaptor: AVAssetWriterInputPixelBufferAdaptor
    let fps: Int32, width: Int, height: Int
    var frame: Int64 = 0

    init(url: URL, width: Int, height: Int, fps: Int32, bitrate: Int) throws {
        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: bitrate, AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                                              AVVideoMaxKeyFrameIntervalKey: Int(fps) * 2],
            AVVideoColorPropertiesKey: [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                                        AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                                        AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2],
        ])
        input.expectsMediaDataInRealTime = false
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height])
        writer.add(input)
        self.fps = fps; self.width = width; self.height = height
        guard writer.startWriting() else { throw Failure("AVAssetWriter: \(writer.error.map { "\($0)" } ?? "start failed")") }
        writer.startSession(atSourceTime: .zero)
    }

    func append(_ image: CGImage) throws {
        while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.002) }
        var buffer: CVPixelBuffer?
        guard let pool = adaptor.pixelBufferPool, CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let pb = buffer else {
            throw Failure("pixel buffer")
        }
        CVPixelBufferLockBaseAddress(pb, [])
        let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pb), width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: CVPixelBufferGetBytesPerRow(pb), space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        ctx?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        CVPixelBufferUnlockBaseAddress(pb, [])
        guard adaptor.append(pb, withPresentationTime: CMTime(value: frame, timescale: fps)) else { throw Failure("append frame \(frame)") }
        frame += 1
    }

    func finish() throws {
        input.markAsFinished()
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        guard writer.status == .completed else { throw Failure("MP4 writer: \(writer.error.map { "\($0)" } ?? "failed")") }
    }
}

/// Animated GIF. Delays are stored in hundredths of a second, so pass a delay that is a whole number of them.
final class GIFWriter {
    let destination: CGImageDestination
    let delay: Double
    private(set) var frames = 0
    init(url: URL, frames: Int, delay: Double) throws {
        guard let d = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frames, nil) else { throw Failure("GIF") }
        CGImageDestinationSetProperties(d, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        destination = d; self.delay = delay
    }
    func append(_ image: CGImage) {
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay,
                                                                                       kCGImagePropertyGIFUnclampedDelayTime: delay]] as CFDictionary)
        frames += 1
    }
    func finish() throws { guard CGImageDestinationFinalize(destination) else { throw Failure("GIF finalize") } }

    /// Reads back the stored per-frame delays (seconds) of a GIF file.
    static func delays(_ url: URL) -> [Double] {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return [] }
        return (0..<CGImageSourceGetCount(src)).map { i in
            let props = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [CFString: Any]
            let gif = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            return (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double) ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0
        }
    }
}

// MARK: Overlay

struct Label { let text: String; let anchor: CGPoint }

enum Overlay {
    static func font(_ size: CGFloat, _ weight: NSFont.Weight) -> CTFont { NSFont.systemFont(ofSize: size, weight: weight) as CTFont }

    static func draw(_ ctx: CGContext, _ s: String, at p: CGPoint, size: CGFloat, weight: NSFont.Weight, color: CGColor, tracking: CGFloat = 0) {
        let attrs: [NSAttributedString.Key: Any] = [.init(kCTFontAttributeName as String): font(size, weight), .init(kCTForegroundColorAttributeName as String): color,
                                                    .init(kCTKernAttributeName as String): tracking]
        ctx.textPosition = p
        CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: attrs)), ctx)
    }

    static func width(_ s: String, size: CGFloat, weight: NSFont.Weight) -> CGFloat {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: [.init(kCTFontAttributeName as String): font(size, weight)]))
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    /// Greedy word wrap to `maxWidth`.
    static func wrap(_ s: String, size: CGFloat, weight: NSFont.Weight, maxWidth: CGFloat) -> [String] {
        var lines: [String] = [], cur = ""
        for w in s.split(separator: " ").map(String.init) {
            let t = cur.isEmpty ? w : cur + " " + w
            if width(t, size: size, weight: weight) > maxWidth && !cur.isEmpty { lines.append(cur); cur = w } else { cur = t }
        }
        if !cur.isEmpty { lines.append(cur) }
        return lines
    }

    /// Title block, caption, footer and leader-line labels over a frame. Label anchors are top-left pixel space;
    /// labels go in a row above or below the subject, alternating along the engine axis.
    static func apply(_ image: CGImage, title: String? = nil, subtitle: String? = nil, footer: String? = nil, labels: [Label] = [],
                      labelAlpha: Double = 1, caption: String? = nil, kicker: String = "MARTYGRAPHICS · SOLID ENGINE",
                      corner: String? = nil, labelBand: (top: CGFloat, bottom: CGFloat) = (0.17, 0.86)) -> CGImage {
        let w = image.width, h = image.height
        let scale = CGFloat(w) / 1280
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let H = CGFloat(h), W = CGFloat(w)
        let white = CGColor(srgbRed: 0.95, green: 0.96, blue: 1, alpha: 1)
        let soft = CGColor(srgbRed: 0.70, green: 0.76, blue: 0.90, alpha: 1)
        let accent = CGColor(srgbRed: 0.49, green: 0.61, blue: 1.0, alpha: 1)
        if let t = title {
            draw(ctx, kicker, at: CGPoint(x: 40 * scale, y: H - 50 * scale), size: 12 * scale, weight: .bold, color: accent, tracking: 2 * scale)
            draw(ctx, t, at: CGPoint(x: 40 * scale, y: H - 84 * scale), size: 28 * scale, weight: .semibold, color: white)
            if let s = subtitle { draw(ctx, s, at: CGPoint(x: 40 * scale, y: H - 110 * scale), size: 15 * scale, weight: .regular, color: soft) }
        }
        if let c = corner {
            let size = 13 * scale, tw = width(c, size: size, weight: .medium)
            draw(ctx, c, at: CGPoint(x: W - tw - 36 * scale, y: H - 50 * scale), size: size, weight: .medium, color: soft)
        }
        if let c = caption {
            let size = 18 * scale
            let lines = wrap(c, size: size, weight: .medium, maxWidth: W - 200 * scale)
            let lw = lines.map { width($0, size: size, weight: .medium) }.max() ?? 0
            let lineH = 26 * scale
            let boxH = CGFloat(lines.count) * lineH + 22 * scale
            let box = CGRect(x: (W - lw) / 2 - 22 * scale, y: 40 * scale, width: lw + 44 * scale, height: boxH)
            ctx.setFillColor(CGColor(srgbRed: 0.02, green: 0.03, blue: 0.06, alpha: 0.74))
            ctx.addPath(CGPath(roundedRect: box, cornerWidth: 12 * scale, cornerHeight: 12 * scale, transform: nil)); ctx.fillPath()
            for (i, l) in lines.enumerated() {
                let lwi = width(l, size: size, weight: .medium)
                draw(ctx, l, at: CGPoint(x: (W - lwi) / 2, y: box.maxY - 11 * scale - CGFloat(i + 1) * lineH + 7 * scale), size: size, weight: .medium, color: white)
            }
        }
        if let f = footer {
            let size = 11 * scale, tw = width(f, size: size, weight: .regular)
            draw(ctx, f, at: CGPoint(x: W - tw - 24 * scale, y: 16 * scale), size: size, weight: .regular,
                 color: CGColor(srgbRed: 0.6, green: 0.65, blue: 0.78, alpha: 0.9))
        }
        guard labelAlpha > 0.01, !labels.isEmpty else { return ctx.makeImage() ?? image }
        let size = 13.5 * scale, pad = 8 * scale, gapX = 10 * scale
        // The upper half of the anchors (by height) label in the top row, the rest in the bottom row; each row runs
        // left to right by anchor position so leader lines do not cross.
        let byHeight = labels.sorted { $0.anchor.y < $1.anchor.y }
        let upper = Array(byHeight.prefix((labels.count + 1) / 2)), lower = Array(byHeight.dropFirst((labels.count + 1) / 2))
        let rowY: [CGFloat] = [H * labelBand.top, H * labelBand.bottom]
        var rows: [[(Label, CGFloat, CGFloat)]] = [[], []]   // label, box width, box x
        for (r, list) in [upper, lower].enumerated() {
            for l in list.sorted(by: { $0.anchor.x < $1.anchor.x }) {
                let bw = width(l.text, size: size, weight: .semibold) + 2 * pad
                rows[r].append((l, bw, l.anchor.x - bw / 2))
            }
        }
        for r in 0..<2 {
            // Push boxes right to remove overlaps, then shift the row back inside the frame.
            for i in rows[r].indices.dropFirst() {
                let prev = rows[r][i - 1]
                rows[r][i].2 = max(rows[r][i].2, prev.2 + prev.1 + gapX)
            }
            if let last = rows[r].last, last.2 + last.1 > W - 24 * scale {
                let shift = last.2 + last.1 - (W - 24 * scale)
                for i in rows[r].indices { rows[r][i].2 -= shift }
                for i in rows[r].indices.reversed().dropFirst() {
                    let next = rows[r][i + 1]
                    rows[r][i].2 = min(rows[r][i].2, next.2 - rows[r][i].1 - gapX)
                }
            }
            if let first = rows[r].first, first.2 < 24 * scale {
                let shift = 24 * scale - first.2
                for i in rows[r].indices { rows[r][i].2 += shift }
            }
        }
        let a = CGFloat(labelAlpha)
        for r in 0..<2 {
            for (l, bw, bx) in rows[r] {
                let anchor = CGPoint(x: l.anchor.x, y: H - l.anchor.y)
                let boxH = 26 * scale
                let by = H - rowY[r] - boxH / 2
                let attach = CGPoint(x: min(max(anchor.x, bx + 10 * scale), bx + bw - 10 * scale), y: r == 0 ? by : by + boxH)
                ctx.setStrokeColor(CGColor(srgbRed: 0.92, green: 0.94, blue: 1, alpha: 0.8 * a)); ctx.setLineWidth(1.3 * scale)
                ctx.move(to: anchor); ctx.addLine(to: CGPoint(x: attach.x, y: attach.y)); ctx.strokePath()
                ctx.setFillColor(CGColor(srgbRed: 1, green: 0.72, blue: 0.35, alpha: a))
                ctx.fillEllipse(in: CGRect(x: anchor.x - 3.5 * scale, y: anchor.y - 3.5 * scale, width: 7 * scale, height: 7 * scale))
                let box = CGRect(x: bx, y: by, width: bw, height: boxH)
                ctx.setFillColor(CGColor(srgbRed: 0.03, green: 0.04, blue: 0.08, alpha: 0.80 * a))
                ctx.addPath(CGPath(roundedRect: box, cornerWidth: 7 * scale, cornerHeight: 7 * scale, transform: nil)); ctx.fillPath()
                draw(ctx, l.text, at: CGPoint(x: box.minX + pad, y: box.minY + 8.5 * scale), size: size, weight: .semibold,
                     color: CGColor(srgbRed: 0.96, green: 0.97, blue: 1, alpha: a))
            }
        }
        return ctx.makeImage() ?? image
    }
}
