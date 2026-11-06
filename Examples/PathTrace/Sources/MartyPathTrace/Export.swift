// SPDX-License-Identifier: Apache-2.0
import AVFoundation
import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers
import MartyGraphicsPathTracer

enum ExportError: Error, CustomStringConvertible {
    case failed(String)
    var description: String {
        switch self { case let .failed(why): return why }
    }
}

enum Export {
    static func png(_ image: CGImage, to url: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw ExportError.failed("Cannot create PNG \(url.lastPathComponent)")
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw ExportError.failed("Cannot finalize PNG") }
    }

    static func sha256(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func scaled(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }

    static func writeJSON(_ object: Any, to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url)
    }
}

/// H.264 MP4 writer fed with RGBA8 frames.
final class VideoWriter {
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let fps: Int32
    private var frameIndex: Int64 = 0
    let width: Int, height: Int

    init(url: URL, width: Int, height: Int, fps: Int, bitsPerSecond: Int) throws {
        self.width = width
        self.height = height
        self.fps = Int32(fps)
        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitsPerSecond,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoMaxKeyFrameIntervalKey: fps * 2,
                AVVideoAllowFrameReorderingKey: true,
            ] as [String: Any],
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
        ]
        input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
        ])
        guard writer.canAdd(input) else { throw ExportError.failed("Cannot add video input") }
        writer.add(input)
        guard writer.startWriting() else { throw ExportError.failed("Cannot start video: \(String(describing: writer.error))") }
        writer.startSession(atSourceTime: .zero)
    }

    func append(rgba: [UInt8]) throws {
        while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.005) }
        guard let pool = adaptor.pixelBufferPool else { throw ExportError.failed("No pixel buffer pool") }
        var pb: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb)
        guard let buffer = pb else { throw ExportError.failed("No pixel buffer") }
        CVPixelBufferLockBaseAddress(buffer, [])
        let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        rgba.withUnsafeBufferPointer { src in
            for y in 0..<height {
                let row = base + y * stride
                let s = y * width * 4
                for x in 0..<width {
                    row[x * 4] = src[s + x * 4 + 2]
                    row[x * 4 + 1] = src[s + x * 4 + 1]
                    row[x * 4 + 2] = src[s + x * 4]
                    row[x * 4 + 3] = 255
                }
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        let time = CMTime(value: frameIndex, timescale: fps)
        guard adaptor.append(buffer, withPresentationTime: time) else {
            throw ExportError.failed("Video append failed: \(String(describing: writer.error))")
        }
        frameIndex += 1
    }

    func finish() throws {
        input.markAsFinished()
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        guard writer.status == .completed else { throw ExportError.failed("Video finish failed: \(String(describing: writer.error))") }
    }
}

/// Animated GIF writer (frames are added as they render; ImageIO quantises each frame).
final class GIFWriter {
    private let dest: CGImageDestination
    private let delay: Double

    init(url: URL, frameCount: Int, delay: Double) throws {
        guard let d = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frameCount, nil) else {
            throw ExportError.failed("Cannot create GIF")
        }
        dest = d
        self.delay = delay
        CGImageDestinationSetProperties(d, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
    }

    func add(_ image: CGImage) {
        CGImageDestinationAddImage(dest, image, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay,
                                                                                  kCGImagePropertyGIFUnclampedDelayTime: delay]] as CFDictionary)
    }

    func finish() throws {
        guard CGImageDestinationFinalize(dest) else { throw ExportError.failed("Cannot finalize GIF") }
    }
}
