// SPDX-License-Identifier: Apache-2.0
import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation

/// Delivery presets for exported video (docs/ENGINE.md, "Export presets"): the frame, rate, codec, bit rate, key-frame
/// interval, colour handling and alpha of one destination, and the part of the frame its own interface covers.
/// `MGMovieWriter(url:preset:)` writes with one; `MGVideoExportOptions.preset` uses one for a 2D video.
public struct MGExportPreset: Equatable, Sendable {
    public enum Codec: String, Sendable {
        case h264, hevc
        /// Apple ProRes 4444 in a QuickTime file: the compositing master (alpha), constant quality, every frame a key.
        case proRes4444
    }

    /// The colour space frames are drawn in and the tags the file asks for (docs/ENGINE.md, "Export presets"). The
    /// writer tags every source pixel buffer with the space it was drawn in. The decoded check is pending: until the
    /// Mac test that decodes colour patches has run, these are the tags requested, not tags proven on decoded frames.
    public enum ColorSpace: String, Sendable {
        /// Drawn in sRGB; the file asks for BT.709 primaries and matrix and the sRGB transfer function, so an Apple
        /// player can show it as the stills look (the engine's own loop and story MP4s).
        case srgb
        /// Drawn in sRGB; the file asks for BT.709 throughout (primaries, transfer function and matrix, "1-1-1"), the
        /// tags upload transcoders (YouTube, X) read. The source buffers say sRGB, so an encoder that colour-matches
        /// converts the transfer function on the way; whether it does is part of the pending decoded check. If that
        /// check finds sRGB samples under the BT.709 tags, the planned resolution is to draw these frames in
        /// `CGColorSpace.itur_709`, so the samples match the tags.
        case rec709
        /// Drawn in Display P3 (an sRGB image is converted when drawn); the file asks for P3-D65 primaries, the sRGB
        /// transfer function and the BT.709 matrix. sRGB content keeps its look; only content drawn in P3 gains colours.
        case displayP3
    }

    /// The alpha a frame carries.
    public enum Alpha: String, Sendable {
        /// Opaque: the frame is drawn over `MGExportPreset.letterbox` black.
        case none
        /// Colour not multiplied by alpha, as most editors read ProRes 4444 and as PNG stores it.
        case straight
        /// Colour multiplied by alpha (Core Graphics' own buffers).
        case premultiplied
    }

    /// Fractions of the frame (0...0.5) that a destination's own interface covers.
    public struct Insets: Equatable, Sendable {
        public var top: Double, left: Double, bottom: Double, right: Double
        public init(top: Double, left: Double, bottom: Double, right: Double) {
            self.top = top; self.left = left; self.bottom = bottom; self.right = right
        }
        public static let zero = Insets(top: 0, left: 0, bottom: 0, right: 0)
    }

    public var name: String
    public var width: Int
    public var height: Int
    public var fps: Int
    public var codec: Codec
    public var colorSpace: ColorSpace
    public var alpha: Alpha
    /// Average bit rate in bits per second (H.264 and HEVC; ProRes is constant quality and ignores it).
    public var bitrate: Int
    /// Longest time between key frames (seconds).
    public var keyframeSeconds: Double
    /// Longest video the destination accepts (seconds); nil for no limit.
    public var maxSeconds: Double?
    /// The part of the frame the destination's own interface covers: keep titles, captions and labels outside it.
    public var safeArea: Insets

    public init(name: String, width: Int, height: Int, fps: Int, codec: Codec, colorSpace: ColorSpace, alpha: Alpha = .none,
                bitrate: Int, keyframeSeconds: Double, maxSeconds: Double? = nil, safeArea: Insets = .zero) {
        self.name = name; self.width = width; self.height = height; self.fps = fps; self.codec = codec
        self.colorSpace = colorSpace; self.alpha = alpha; self.bitrate = bitrate; self.keyframeSeconds = keyframeSeconds
        self.maxSeconds = maxSeconds; self.safeArea = safeArea
    }

    /// YouTube Shorts: 1080 × 1920 at 30 fps, H.264 High at 12 Mbit/s (above YouTube's 8 Mbit/s for 1080p30, for
    /// thin lines and small text on dark boards), a key frame every half second (YouTube asks for a closed GOP of half
    /// the frame rate), BT.709 tags, at most 3 minutes. The safe area keeps clear of the search bar (top), the title
    /// and channel rows (bottom) and the action buttons (right).
    public static let shorts = MGExportPreset(name: "shorts", width: 1080, height: 1920, fps: 30, codec: .h264, colorSpace: .rec709,
                                              bitrate: 12_000_000, keyframeSeconds: 0.5, maxSeconds: 180,
                                              safeArea: Insets(top: 0.10, left: 0.06, bottom: 0.22, right: 0.18))
    /// X (Twitter): 1920 × 1080 at 30 fps, H.264 High at 16 Mbit/s, a key frame every second, BT.709 tags, at most
    /// 2 min 20 s (the standard account limit). The safe area keeps clear of the player's controls (bottom).
    public static let x = MGExportPreset(name: "x", width: 1920, height: 1080, fps: 30, codec: .h264, colorSpace: .rec709,
                                         bitrate: 16_000_000, keyframeSeconds: 1, maxSeconds: 140,
                                         safeArea: Insets(top: 0.05, left: 0.05, bottom: 0.12, right: 0.05))
    /// Lessons in an Apple app: 1920 × 1200 (the 16:10 of the engine's stills and stories) at 30 fps, H.264 High at
    /// 14 Mbit/s, a key frame every 2 seconds (the engine's MP4s), sRGB tags so the video matches the stills.
    public static let lesson = MGExportPreset(name: "lesson", width: 1920, height: 1200, fps: 30, codec: .h264, colorSpace: .srgb,
                                              bitrate: 14_000_000, keyframeSeconds: 2)
    /// The lesson frame as a transparent compositing master: ProRes 4444 with straight alpha in a QuickTime file.
    public static let lessonAlpha = MGExportPreset(name: "lesson-alpha", width: 1920, height: 1200, fps: 30, codec: .proRes4444,
                                                   colorSpace: .srgb, alpha: .straight, bitrate: 0, keyframeSeconds: 1 / 30)
    /// The Shorts frame as a transparent compositing master: ProRes 4444 with straight alpha.
    public static let shortsAlpha = MGExportPreset(name: "shorts-alpha", width: 1080, height: 1920, fps: 30, codec: .proRes4444,
                                                   colorSpace: .rec709, alpha: .straight, bitrate: 0, keyframeSeconds: 1 / 30,
                                                   safeArea: MGExportPreset.shorts.safeArea)

    public static let all: [MGExportPreset] = [.shorts, .x, .lesson, .lessonAlpha, .shortsAlpha]

    /// A preset by name ("shorts", "x", "lesson", "lesson-alpha", "shorts-alpha").
    public static func named(_ name: String) -> MGExportPreset? { all.first { $0.name == name } }

    /// The file extension the preset writes: "mov" for ProRes, else "mp4".
    public var fileExtension: String { codec == .proRes4444 ? "mov" : "mp4" }

    /// Key-frame interval in frames (at least 1).
    public var keyframeInterval: Int { max(1, Int((keyframeSeconds * Double(fps)).rounded())) }

    /// What is wrong with the preset, in a fixed order; empty when it can be written. H.264 and HEVC need even sizes
    /// (4:2:0) and a positive bit rate and carry no alpha; every preset needs 2...16384 pixels a side, 1...240 fps, a
    /// positive key-frame interval and insets in 0...0.5 that leave part of the frame.
    public var problems: [String] {
        var out: [String] = []
        if !(2...16384).contains(width) || !(2...16384).contains(height) { out.append("size") }
        if codec != .proRes4444 && (width % 2 != 0 || height % 2 != 0) { out.append("evenSize") }
        if !(1...240).contains(fps) { out.append("fps") }
        if codec != .proRes4444 && bitrate <= 0 { out.append("bitrate") }
        if !(keyframeSeconds.isFinite && keyframeSeconds > 0) { out.append("keyframes") }
        if alpha != .none && codec != .proRes4444 { out.append("alpha") }
        if let m = maxSeconds, !(m.isFinite && m > 0) { out.append("maxSeconds") }
        let s = safeArea, sides = [s.top, s.left, s.bottom, s.right]
        if !sides.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 0.5 }) || s.top + s.bottom >= 1 || s.left + s.right >= 1 { out.append("safeArea") }
        return out
    }

    /// The safe area in pixels (Core Graphics coordinates, origin bottom left), on whole pixels.
    public var safeRect: CGRect {
        let w = Double(width), h = Double(height)
        let x0 = (safeArea.left * w).rounded(.up), x1 = (w - safeArea.right * w).rounded(.down)
        let y0 = (safeArea.bottom * h).rounded(.up), y1 = (h - safeArea.top * h).rounded(.down)
        return CGRect(x: x0, y: y0, width: max(0, x1 - x0), height: max(0, y1 - y0))
    }

    /// Where a `source`-sized frame goes in this preset's frame: scaled to fit, centred, on whole pixels.
    public func fit(_ source: CGSize) -> CGRect { MGExportPreset.fit(source, into: CGSize(width: width, height: height)) }

    public static func fit(_ source: CGSize, into frame: CGSize) -> CGRect {
        guard source.width > 0, source.height > 0, source.width.isFinite, source.height.isFinite else { return CGRect(origin: .zero, size: frame) }
        let s = min(frame.width / source.width, frame.height / source.height)
        let w = min(frame.width, (source.width * s).rounded()), h = min(frame.height, (source.height * s).rounded())
        return CGRect(x: ((frame.width - w) / 2).rounded(.down), y: ((frame.height - h) / 2).rounded(.down), width: w, height: h)
    }

    /// The Core Graphics colour space the frames are drawn in (a drawn sRGB image is converted to it).
    public var drawingSpace: CGColorSpace {
        CGColorSpace(name: colorSpace == .displayP3 ? CGColorSpace.displayP3 : CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    }

    /// The sRGB transfer function tag: AVFoundation's documented `AVVideoTransferFunction_IEC_sRGB` where the OS has
    /// it (macOS 15, iOS 18), else Core Video's `kCVImageBufferTransferFunction_sRGB` (macOS 10.13, iOS 11), the same
    /// "IEC_sRGB" tag that the engine's own MP4s have always used.
    static var srgbTransferFunction: String {
        if #available(macOS 15.0, iOS 18.0, *) { return AVVideoTransferFunction_IEC_sRGB }
        return kCVImageBufferTransferFunction_sRGB as String
    }

    /// The AVFoundation colour tags the file asks for (tags requested; decoded check pending, see `ColorSpace`). The
    /// sRGB transfer function is `srgbTransferFunction`.
    public var colorProperties: [String: Any] {
        switch colorSpace {
        case .srgb:
            return [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                    AVVideoTransferFunctionKey: MGExportPreset.srgbTransferFunction,
                    AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2]
        case .rec709:
            return [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                    AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                    AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2]
        case .displayP3:
            return [AVVideoColorPrimariesKey: AVVideoColorPrimaries_P3_D65,
                    AVVideoTransferFunctionKey: MGExportPreset.srgbTransferFunction,
                    AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2]
        }
    }

    /// The Core Video attachments of every source pixel buffer: the space the frame was actually drawn in
    /// (`drawingSpace`: sRGB, or Display P3 for `displayP3`) as primaries, transfer function and colour space, and for
    /// an alpha preset how the alpha is stored (straight or premultiplied, `kCVImageBufferAlphaChannelModeKey`).
    var sourceAttachments: [String: Any] {
        var a: [String: Any] = [
            kCVImageBufferColorPrimariesKey as String: (colorSpace == .displayP3 ? kCVImageBufferColorPrimaries_P3_D65 : kCVImageBufferColorPrimaries_ITU_R_709_2) as String,
            kCVImageBufferTransferFunctionKey as String: kCVImageBufferTransferFunction_sRGB as String,
            kCVImageBufferCGColorSpaceKey as String: drawingSpace,
        ]
        switch alpha {
        case .none: break
        case .straight: a[kCVImageBufferAlphaChannelModeKey as String] = kCVImageBufferAlphaChannelMode_StraightAlpha as String
        case .premultiplied: a[kCVImageBufferAlphaChannelModeKey as String] = kCVImageBufferAlphaChannelMode_PremultipliedAlpha as String
        }
        return a
    }

    /// The `AVAssetWriterInput` output settings. H.264 and HEVC: the bit rate, the key-frame interval and no frame
    /// reordering (no B-frames: frame k is presented at k / fps, the engine's frame-exact rule); H.264 at High profile.
    /// ProRes: no compression properties (constant quality, intra only).
    public var outputSettings: [String: Any] {
        var o: [String: Any] = [AVVideoWidthKey: width, AVVideoHeightKey: height, AVVideoColorPropertiesKey: colorProperties]
        switch codec {
        case .h264:
            o[AVVideoCodecKey] = AVVideoCodecType.h264
            o[AVVideoCompressionPropertiesKey] = [AVVideoAverageBitRateKey: bitrate, AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                                                  AVVideoMaxKeyFrameIntervalKey: keyframeInterval, AVVideoAllowFrameReorderingKey: false,
                                                  AVVideoExpectedSourceFrameRateKey: fps] as [String: Any]
        case .hevc:
            o[AVVideoCodecKey] = AVVideoCodecType.hevc
            o[AVVideoCompressionPropertiesKey] = [AVVideoAverageBitRateKey: bitrate, AVVideoMaxKeyFrameIntervalKey: keyframeInterval,
                                                  AVVideoAllowFrameReorderingKey: false, AVVideoExpectedSourceFrameRateKey: fps] as [String: Any]
        case .proRes4444:
            o[AVVideoCodecKey] = AVVideoCodecType.proRes4444
        }
        return o
    }
}

/// Pixel helpers for the video writers. Pure.
enum MGVideoPixels {
    /// Divides each colour by its alpha in place: premultiplied 4-byte pixels with alpha last in memory (BGRA from a
    /// `premultipliedFirst | byteOrder32Little` context, or RGBA from `premultipliedLast`) become straight alpha.
    /// A transparent pixel becomes 0, 0, 0, 0; an opaque one is unchanged.
    static func unpremultiply(_ bytes: UnsafeMutablePointer<UInt8>, width: Int, height: Int, bytesPerRow: Int) {
        for y in 0..<height {
            let row = bytes + y * bytesPerRow
            for x in 0..<width {
                let p = row + 4 * x
                let a = Int(p[3])
                if a == 255 { continue }
                if a == 0 { p[0] = 0; p[1] = 0; p[2] = 0; continue }
                for k in 0..<3 { p[k] = UInt8(min(255, (Int(p[k]) * 255 + a / 2) / a)) }
            }
        }
    }
}
