// SPDX-License-Identifier: Apache-2.0
import AVFoundation
import Foundation

/// H.264 MP4 writer (AVFoundation, no installs): frames at a fixed rate, presentation time = frame index / rate.
/// Experimental SPI: import with `@_spi(Experimental) import MartyGraphics`. Use from one serial caller only.
@_spi(Experimental)
public final class MGMovieWriter {
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    public let width: Int, height: Int, fps: Int32
    private let maxBufferedFrames: Int?
    public private(set) var frames: Int64 = 0

    /// H.264 4:2:0 needs even sizes: an odd width or height is written one pixel smaller (the frame is scaled).
    public static func evenSize(_ w: Int, _ h: Int) -> (width: Int, height: Int) { (w - w % 2, h - h % 2) }

    public init(url: URL, width: Int, height: Int, fps: Int32, maxBufferedFrames: Int? = nil) throws {
        guard (2...16384).contains(width), (2...16384).contains(height), (1...240).contains(fps) else { throw MGError("mp4: dimensions or fps") }
        guard maxBufferedFrames.map({ (1...8).contains($0) }) ?? true else { throw MGError("mp4: buffer limit") }
        self.maxBufferedFrames = maxBufferedFrames
        (self.width, self.height) = MGMovieWriter.evenSize(width, height)
        self.fps = fps
        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        // About 0.2 bits per pixel per frame, at least 2 Mbit/s: sharp edges on dark studio backgrounds.
        let bitrate = max(2_000_000, min(40_000_000, Int(Double(self.width * self.height) * Double(fps) * 0.2)))
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: self.width, AVVideoHeightKey: self.height,
            // The frames are sRGB pixels: say so, with BT.709 primaries and matrix. An untagged file leaves a player to
            // guess the transfer function; one that assumes BT.709 and converts to the display shows the middle tones
            // several levels off the stills.
            AVVideoColorPropertiesKey: [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                                        AVVideoTransferFunctionKey: kCVImageBufferTransferFunction_sRGB as String,
                                        AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2],
            // No frame reordering (no B-frames): every sample's presentation time is its decode time, frame k at k / fps.
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: bitrate, AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                                              AVVideoMaxKeyFrameIntervalKey: Int(fps) * 2, AVVideoAllowFrameReorderingKey: false],
        ])
        input.expectsMediaDataInRealTime = false
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: self.width,
            kCVPixelBufferHeightKey as String: self.height,
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
        let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pb), width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: CVPixelBufferGetBytesPerRow(pb), space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        guard ctx != nil else {
            CVPixelBufferUnlockBaseAddress(pb, [])
            throw abandon(MGError("mp4 pixel context"))
        }
        ctx?.interpolationQuality = .high
        ctx?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        CVPixelBufferUnlockBaseAddress(pb, [])
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
