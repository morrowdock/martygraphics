// SPDX-License-Identifier: Apache-2.0
import AVFoundation
import Foundation

/// H.264 MP4 writer (AVFoundation, no installs): frames at a fixed rate, presentation time = frame index / rate.
/// `init(url:preset:)` writes with an export preset instead (`MGExportPreset`: H.264, HEVC or ProRes 4444, its bit
/// rate, key frames, colour handling and alpha; frames of another size are fitted, centred, into its frame).
/// Experimental SPI: import with `@_spi(Experimental) import MartyGraphics`. Use from one serial caller only.
@_spi(Experimental)
public final class MGMovieWriter {
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    public let width: Int, height: Int, fps: Int32
    private let maxBufferedFrames: Int?
    /// The space frames are drawn in, how their alpha is stored, and whether another size is fitted (else stretched).
    private let space: CGColorSpace
    private let alpha: MGExportPreset.Alpha
    private let fits: Bool
    /// Preset writers: the Core Video attachments each source buffer gets (`MGExportPreset.sourceAttachments`, the
    /// space the frame was drawn in). nil for the engine's own H.264 writer, which is unchanged.
    private let sourceAttachments: [String: Any]?
    public private(set) var frames: Int64 = 0

    /// H.264 4:2:0 needs even sizes: an odd width or height is written one pixel smaller (the frame is scaled).
    public static func evenSize(_ w: Int, _ h: Int) -> (width: Int, height: Int) { (w - w % 2, h - h % 2) }

    public convenience init(url: URL, width: Int, height: Int, fps: Int32, maxBufferedFrames: Int? = nil) throws {
        guard (2...16384).contains(width), (2...16384).contains(height), (1...240).contains(fps) else { throw MGError("mp4: dimensions or fps") }
        guard maxBufferedFrames.map({ (1...8).contains($0) }) ?? true else { throw MGError("mp4: buffer limit") }
        let (w, h) = MGMovieWriter.evenSize(width, height)
        // About 0.2 bits per pixel per frame, at least 2 Mbit/s: sharp edges on dark studio backgrounds.
        let bitrate = max(2_000_000, min(40_000_000, Int(Double(w * h) * Double(fps) * 0.2)))
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: w, AVVideoHeightKey: h,
            // The frames are sRGB pixels: say so, with BT.709 primaries and matrix. An untagged file leaves a player to
            // guess the transfer function; one that assumes BT.709 and converts to the display shows the middle tones
            // several levels off the stills.
            AVVideoColorPropertiesKey: [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                                        AVVideoTransferFunctionKey: kCVImageBufferTransferFunction_sRGB as String,
                                        AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2],
            // No frame reordering (no B-frames): every sample's presentation time is its decode time, frame k at k / fps.
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: bitrate, AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                                              AVVideoMaxKeyFrameIntervalKey: Int(fps) * 2, AVVideoAllowFrameReorderingKey: false],
        ]
        try self.init(url: url, fileType: .mp4, settings: settings, width: w, height: h, fps: fps, maxBufferedFrames: maxBufferedFrames,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!, alpha: .none, fits: false, sourceAttachments: nil)
    }

    /// A writer for an export preset: its frame size, rate, codec, bit rate, key frames, colour tags and alpha
    /// (`MGExportPreset.outputSettings`), in an MP4 (H.264, HEVC) or a QuickTime file (ProRes 4444). Frames are drawn
    /// in the preset's colour space (an sRGB image is converted to Display P3 for `displayP3`), a frame of another
    /// size is fitted into the preset's frame (centred, over black, or clear with alpha), and `alpha: .straight` divides
    /// the colours by alpha before encoding. Every source buffer is tagged with the space it was drawn in and, with
    /// alpha, how its alpha is stored (`MGExportPreset.sourceAttachments`). Throws `mp4: preset <problems>` for a preset
    /// that cannot be written, `mp4: preset alphaMode` for a preset with alpha before macOS 15 and iOS 18 (Core Video
    /// cannot state the alpha mode there, `MGExportPreset.problems(on:)`).
    public convenience init(url: URL, preset: MGExportPreset, maxBufferedFrames: Int? = nil) throws {
        try self.init(url: url, preset: preset, maxBufferedFrames: maxBufferedFrames, system: .current)
    }

    /// `init(url:preset:maxBufferedFrames:)` on `system` (tests pass an older system to check its refusal).
    convenience init(url: URL, preset: MGExportPreset, maxBufferedFrames: Int?, system: MGExportSystem) throws {
        let problems = preset.problems(on: system)
        guard problems.isEmpty else { throw MGError("mp4: preset " + problems.joined(separator: ",")) }
        guard maxBufferedFrames.map({ (1...8).contains($0) }) ?? true else { throw MGError("mp4: buffer limit") }
        try self.init(url: url, fileType: preset.codec == .proRes4444 ? .mov : .mp4, settings: preset.outputSettings,
                      width: preset.width, height: preset.height, fps: Int32(preset.fps), maxBufferedFrames: maxBufferedFrames,
                      space: preset.drawingSpace, alpha: preset.alpha, fits: true, sourceAttachments: preset.sourceAttachments)
    }

    private init(url: URL, fileType: AVFileType, settings: [String: Any], width: Int, height: Int, fps: Int32, maxBufferedFrames: Int?,
                 space: CGColorSpace, alpha: MGExportPreset.Alpha, fits: Bool, sourceAttachments: [String: Any]?) throws {
        self.maxBufferedFrames = maxBufferedFrames
        self.width = width; self.height = height; self.fps = fps
        self.space = space; self.alpha = alpha; self.fits = fits; self.sourceAttachments = sourceAttachments
        writer = try AVAssetWriter(outputURL: url, fileType: fileType)
        input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        guard writer.canAdd(input) else { throw MGError("mp4: unsupported settings") }
        writer.add(input)
        guard writer.startWriting() else { throw MGError("mp4: \(writer.error.map { "\($0)" } ?? "start failed")") }
        writer.startSession(atSourceTime: .zero)
    }

    /// Longest wait for the encoder to take a frame (seconds).
    static let readyTimeout = 10.0
    static let finishTimeout = 60.0

    /// Waits until `ready()`; throws as soon as `status()` is `.failed` or `.cancelled` (disk full, a cancel) and after
    /// `timeout` seconds, so a stopped writer never hangs the render.
    static func waitUntilReady(timeout: Double = MGMovieWriter.readyTimeout, ready: () -> Bool, status: () -> AVAssetWriter.Status,
                               error: () -> Error? = { nil }) throws {
        let deadline = DispatchTime.now() + timeout
        try Task.checkCancellation()
        while !ready() {
            try Task.checkCancellation()
            switch status() {
            case .failed: throw MGError("mp4: writer failed: \(error().map { "\($0)" } ?? "no error given")")
            case .cancelled: throw MGError("mp4: writer cancelled")
            default: break
            }
            guard DispatchTime.now() < deadline else { throw MGError("mp4: writer stalled") }
            Thread.sleep(forTimeInterval: 0.002)
        }
    }

    /// Stops the file (no partial MP4 is finished) and returns the error to throw; the render then removes its directory.
    private func abandon(_ e: Error) -> Error {
        cancel()
        return e
    }

    /// Cancels an unfinished file. Repeated calls, including after successful finish, have no effect.
    public func cancel() {
        if writer.status == .writing { writer.cancelWriting() }
    }

    public func append(_ image: CGImage) throws {
        guard writer.status == .writing else { throw MGError("mp4: writer stopped before append (\(writer.status.rawValue))") }
        do {
            try MGMovieWriter.waitUntilReady(ready: { input.isReadyForMoreMediaData }, status: { writer.status }, error: { writer.error })
        } catch { throw abandon(error) }
        var buffer: CVPixelBuffer?
        guard let pool = adaptor.pixelBufferPool else { throw abandon(MGError("mp4 pixel buffer")) }
        var allocation = kCVReturnSuccess
        do {
            try MGMovieWriter.waitUntilReady(ready: {
                if let limit = self.maxBufferedFrames {
                    allocation = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(nil, pool, [kCVPixelBufferPoolAllocationThresholdKey as String: limit] as CFDictionary, &buffer)
                } else { allocation = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) }
                return allocation != kCVReturnWouldExceedAllocationThreshold
            }, status: { self.writer.status }, error: { self.writer.error })
        } catch { throw abandon(error) }
        guard allocation == kCVReturnSuccess, let pb = buffer else {
            throw abandon(MGError("mp4 pixel buffer"))
        }
        CVPixelBufferLockBaseAddress(pb, [])
        let base = CVPixelBufferGetBaseAddress(pb), bytesPerRow = CVPixelBufferGetBytesPerRow(pb)
        let ctx = CGContext(data: base, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        guard let ctx else {
            CVPixelBufferUnlockBaseAddress(pb, [])
            throw abandon(MGError("mp4 pixel context"))
        }
        // A pooled buffer still holds an earlier frame: clear it, so a frame with transparent pixels never shows it.
        let full = CGRect(x: 0, y: 0, width: width, height: height)
        ctx.clear(full)
        if fits && alpha == .none { ctx.setFillColor(CGColor(gray: 0, alpha: 1)); ctx.fill(full) }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: fits ? MGExportPreset.fit(CGSize(width: image.width, height: image.height), into: full.size) : full)
        if alpha == .straight, let base {
            MGVideoPixels.unpremultiply(base.assumingMemoryBound(to: UInt8.self), width: width, height: height, bytesPerRow: bytesPerRow)
        }
        CVPixelBufferUnlockBaseAddress(pb, [])
        // A preset writer says what the buffer holds: the space it was drawn in and how its alpha is stored, so the
        // encoder never has to guess (the file's own tags are the preset's `colorProperties`).
        if let sourceAttachments { CVBufferSetAttachments(pb, sourceAttachments as CFDictionary, .shouldPropagate) }
        guard adaptor.append(pb, withPresentationTime: CMTime(value: frames, timescale: fps)) else {
            throw abandon(MGError("mp4 frame \(frames): \(writer.error.map { "\($0)" } ?? "\(writer.status.rawValue)")"))
        }
        frames += 1
    }

    /// Ends the file: the last frame lasts one frame period, so the movie is exactly frames / fps seconds long.
    public func finish() throws {
        guard writer.status == .writing else { throw abandon(MGError("mp4: writer stopped before the end (\(writer.status.rawValue))")) }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(value: frames, timescale: fps))
        let done = DispatchSemaphore(value: 0)
        let deadline = Date().addingTimeInterval(Self.finishTimeout)
        writer.finishWriting { done.signal() }
        while done.wait(timeout: .now() + 0.05) == .timedOut {
            do { try Task.checkCancellation() } catch { throw abandon(error) }
            guard Date() < deadline else { throw abandon(MGError("mp4: finish timed out")) }
        }
        guard writer.status == .completed else { throw MGError("mp4: \(writer.error.map { "\($0)" } ?? "failed")") }
    }
}
