// SPDX-License-Identifier: Apache-2.0
// Apple framework IO for pack.py. No model calls and no alternate codec/OCR.
// Build: swiftc -O media.swift -o media
import Foundation
import AVFoundation
import Vision
import ImageIO
import CoreGraphics

struct Failure: Error, CustomStringConvertible {
    let description: String
    init(_ text: String) { description = text }
}
let width = 1280, height = 800
func image(_ path: String, raw: Bool = false) throws -> CGImage {
    if raw {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        guard data.count == width * height * 3,
              let provider = CGDataProvider(data: data as CFData),
              let result = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 24,
                  bytesPerRow: width * 3, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue), provider: provider,
                  decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { throw Failure("invalid RGB frame") }
        return result
    }
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          CGImageSourceGetType(source) as String? == "public.png",
          let result = CGImageSourceCreateImageAtIndex(source, 0, nil),
          result.width == width, result.height == height else { throw Failure("source must be 1280 x 800") }
    return result
}
func rgb(_ image: CGImage, w: Int = width, h: Int = height) throws -> Data {
    // A top-down RGB buffer; CoreGraphics bitmap rows start at the image's top.
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue), let memory = ctx.data else {
        throw Failure("RGB context failed")
    }
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    let pixels = memory.assumingMemoryBound(to: UInt8.self)
    var out = Data(count: w * h * 3)
    out.withUnsafeMutableBytes { (bytes: UnsafeMutableRawBufferPointer) in
        for i in 0..<(w * h) {
            bytes[i * 3] = pixels[i * 4]; bytes[i * 3 + 1] = pixels[i * 4 + 1]; bytes[i * 3 + 2] = pixels[i * 4 + 2]
        }
    }
    return out
}

func encode(_ paths: [String], _ output: String, raw: Bool) throws {
    guard !paths.isEmpty else { throw Failure("no frames to encode") }
    let writer = try AVAssetWriter(outputURL: URL(fileURLWithPath: output), fileType: .mp4)
    writer.metadata = []
    writer.shouldOptimizeForNetworkUse = true
    // Exactly the MovieWriter settings at locked engine 38f3863, SolidCLI/main.swift:388-418.
    let bitrate = max(2_000_000, min(40_000_000, Int(Double(width * height) * 30 * 0.2)))
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
        AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: bitrate,
            AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            AVVideoMaxKeyFrameIntervalKey: 60, AVVideoAllowFrameReorderingKey: false]])
    input.expectsMediaDataInRealTime = false
    input.metadata = []
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height])
    guard writer.canAdd(input) else { throw Failure("cannot add video input") }
    writer.add(input)
    guard writer.startWriting() else { throw Failure("writer start failed: \(String(describing: writer.error))") }
    writer.startSession(atSourceTime: .zero)
    do {
        for (k, path) in paths.enumerated() {
            try autoreleasepool {
                let frame = try image(path, raw: raw)
                let deadline = Date().addingTimeInterval(60)
                while !input.isReadyForMoreMediaData {
                    guard writer.status == .writing, Date() < deadline else { throw Failure("writer stalled or failed") }
                    Thread.sleep(forTimeInterval: 0.002)
                }
                var buffer: CVPixelBuffer?
                guard let pool = adaptor.pixelBufferPool,
                      CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess,
                      let pb = buffer else { throw Failure("pixel buffer failed") }
                CVPixelBufferLockBaseAddress(pb, [])
                defer { CVPixelBufferUnlockBaseAddress(pb, []) }
                guard let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pb), width: width, height: height,
                    bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pb),
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
                    else { throw Failure("video context failed") }
                ctx.draw(frame, in: CGRect(x: 0, y: 0, width: width, height: height))
                guard adaptor.append(pb, withPresentationTime: CMTime(value: Int64(k), timescale: 30)) else {
                    throw Failure("append failed")
                }
            }
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(value: Int64(paths.count), timescale: 30))
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        guard done.wait(timeout: .now() + 120) == .success, writer.status == .completed else {
            throw Failure("finish failed or timed out")
        }
    } catch { writer.cancelWriting(); throw error }
}

func prepare(_ request: [String: Any]) throws -> [String: Any] {
    guard let output = request["output"] as? String, let kind = request["kind"] as? String else {
        throw Failure("missing preparation fields")
    }
    let source: String
    if kind == "captures" {
        guard let paths = request["paths"] as? [String], !paths.isEmpty else { throw Failure("no capture frames") }
        source = output + "/intermediate.mp4"
        try encode(paths, source, raw: false) // Arm 2's one lossy generation before normalization.
    } else if kind == "video", let path = request["path"] as? String { source = path }
    else { throw Failure("unknown source kind") }
    let asset = AVURLAsset(url: URL(fileURLWithPath: source))
    guard let track = asset.tracks(withMediaType: .video).first else { throw Failure("no video track") }
    guard !track.formatDescriptions.isEmpty,
          CMFormatDescriptionGetMediaSubType(track.formatDescriptions[0] as! CMFormatDescription) == kCMVideoCodecType_H264 else {
        throw Failure("source must be H.264")
    }
    guard track.naturalSize == CGSize(width: width, height: height), track.preferredTransform == .identity,
          abs(Double(track.nominalFrameRate) - 30) < 0.001 else {
        throw Failure("video must be unrotated 1280 x 800 at 30 fps")
    }
    let duration = CMTimeGetSeconds(asset.duration)
    guard duration.isFinite, duration > 0 else { throw Failure("invalid video duration") }
    let count = Int((duration * 30).rounded())
    guard count > 0, abs(duration * 30 - Double(count)) < 0.01 else { throw Failure("duration not on 30 fps grid") }
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = false
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero
    var frames: [String] = []
    for k in 0..<count {
        try autoreleasepool {
            let frame = try generator.copyCGImage(at: CMTime(value: Int64(k), timescale: 30), actualTime: nil)
            guard frame.width == width, frame.height == height else { throw Failure("decoded size mismatch") }
            let path = output + String(format: "/%06d.rgb", k)
            try rgb(frame).write(to: URL(fileURLWithPath: path))
            frames.append(path)
        }
    }
    return ["frames": frames]
}

func ocr(_ request: [String: Any]) throws -> [String: Any] {
    guard let path = request["path"] as? String, let patterns = request["patterns"] as? [String: String] else {
        throw Failure("missing OCR fields")
    }
    let frame = try image(path, raw: true)
    let scan = VNRecognizeTextRequest()
    scan.recognitionLevel = .accurate
    scan.recognitionLanguages = ["en-US"]
    scan.usesLanguageCorrection = false
    try VNImageRequestHandler(cgImage: frame, options: [:]).perform([scan])
    var lines: [(CGRect, [String: Any])] = []
    for observation in scan.results ?? [] {
        guard let text = observation.topCandidates(1).first else { continue }
        var matches: [[String: Any]] = []
        for rule in patterns.keys.sorted() {
            let regex = try NSRegularExpression(pattern: patterns[rule]!)
            for match in regex.matches(in: text.string, range: NSRange(text.string.startIndex..., in: text.string)) {
                guard let range = Range(match.range, in: text.string), let box = try text.boundingBox(for: range) else {
                    throw Failure("Vision did not return the matched character box")
                }
                let b = box.boundingBox
                matches.append(["rule": rule, "box": [b.minX * Double(width), (1 - b.maxY) * Double(height),
                                                        b.width * Double(width), b.height * Double(height)]])
            }
        }
        lines.append((observation.boundingBox, ["text": text.string, "matches": matches]))
    }
    // Reading order, then x; no reliance on Vision observation order.
    lines.sort { a, b in a.0.maxY == b.0.maxY ? a.0.minX < b.0.minX : a.0.maxY > b.0.maxY }
    return ["lines": lines.map { $0.1 }]
}

func handle(_ request: [String: Any]) throws -> [String: Any] {
    switch request["op"] as? String {
    case "prepare": return try prepare(request)
    case "ocr": return try ocr(request)
    case "thumbnail":
        guard let path = request["path"] as? String else { throw Failure("missing thumbnail path") }
        return ["rgb": try rgb(image(path, raw: true), w: 256, h: 160).base64EncodedString()]
    case "encode":
        guard let paths = request["paths"] as? [String], let output = request["output"] as? String,
              let raw = request["raw"] as? Bool else { throw Failure("missing encode fields") }
        try encode(paths, output, raw: raw)
        return [:]
    default: throw Failure("unknown operation")
    }
}
// NDJSON worker. Every request is independent, with an autorelease pool per frame.
while let line = readLine() {
    do {
        let answer: [String: Any] = try autoreleasepool {
            guard let request = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
                throw Failure("expected JSON object")
            }
            return try handle(request)
        }
        let data = try JSONSerialization.data(withJSONObject: answer, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self)); fflush(stdout)
    } catch {
        let data = try! JSONSerialization.data(withJSONObject: ["error": String(describing: error)])
        print(String(decoding: data, as: UTF8.self)); fflush(stdout)
    }
}
