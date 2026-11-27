// SPDX-License-Identifier: Apache-2.0
import Foundation
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

public struct MGVideoExportOptions: Sendable {
    public enum Format: String, Sendable { case mp4, gif }
    public var format: Format
    public var burnCaptions: Bool
    public var writeSRT: Bool
    /// `mp4` only: write with a delivery preset (`MGExportPreset`: Shorts, X, lessons): its frame (the plan's frame is
    /// fitted, centred), codec (a ProRes 4444 preset writes a QuickTime file), bit rate, key frames, colour handling and
    /// alpha. nil keeps the plan's own frame and the engine's H.264 settings. Refusals: `video2d.export.preset` (the
    /// preset cannot be written), `video2d.export.presetRate` (not 30 fps, the plan's rate), `video2d.export.presetDuration`
    /// (longer than the preset's `maxSeconds`).
    public var preset: MGExportPreset?
    public init(format: Format = .mp4, burnCaptions: Bool = true, writeSRT: Bool = true, preset: MGExportPreset? = nil) {
        self.format = format; self.burnCaptions = burnCaptions; self.writeSRT = writeSRT; self.preset = preset
    }
}

public struct MGVideoExportReceipt: Equatable, Sendable {
    public let destination: URL
    public let subtitles: URL?
    public let frameCount: Int
    public let fps: Int
    public let width: Int
    public let height: Int
    public let durationSeconds: Double
    public let warnings: [String]
}

extension MGProgrammaticVideo {
    public static func srt(_ plan: MGCheckedVideoPlan) -> String {
        func timestamp(_ frame: Int) -> String {
            let milliseconds = (frame * 1000 + 15) / 30
            return String(format: "%02d:%02d:%02d,%03d", milliseconds / 3_600_000, (milliseconds / 60_000) % 60, (milliseconds / 1000) % 60, milliseconds % 1000)
        }
        return plan.captions.enumerated().map { index, caption in
            "\(index + 1)\n\(timestamp(caption.startFrame)) --> \(timestamp(caption.endFrame))\n\(caption.text)\n"
        }.joined(separator: "\n")
    }

    public static func export(_ plan: MGCheckedVideoPlan, to destination: URL, options: MGVideoExportOptions = .init(),
                              programmaticVideo: Bool = false, progress: (@Sendable (Int, Int) -> Void)? = nil) async throws -> MGVideoExportReceipt {
        guard programmaticVideo else { throw MGError("video2d.optIn") }
        try Task.checkCancellation()
        guard destination.isFileURL else { throw MGError("video2d.export.destination") }
        let manager = FileManager.default
        let subtitles = options.writeSRT ? destination.deletingPathExtension().appendingPathExtension("srt") : nil
        guard !manager.fileExists(atPath: destination.path), subtitles.map({ !manager.fileExists(atPath: $0.path) && $0 != destination }) ?? true else { throw MGError("video2d.export.exists") }
        var width = plan.canvas.width, height = plan.canvas.height
        let stride: Int, fps: Int
        switch options.format {
        case .mp4:
            if let preset = options.preset {
                guard preset.problems.isEmpty else { throw MGError("video2d.export.preset") }
                guard preset.fps == 30 else { throw MGError("video2d.export.presetRate") }
                guard preset.maxSeconds.map({ Double(plan.durationFrames) / 30 <= $0 + 1e-9 }) ?? true else { throw MGError("video2d.export.presetDuration") }
                width = preset.width; height = preset.height
            } else {
                guard width % 2 == 0, height % 2 == 0 else { throw MGError("video2d.export.evenDimensions") }
            }
            stride = 1; fps = 30
        case .gif:
            guard plan.durationFrames <= 450, plan.durationFrames % 3 == 0 else { throw MGError("video2d.export.gifDuration") }
            let scale = min(1, 640 / Double(max(width, height)))
            width = Int((Double(width) * scale).rounded()); height = Int((Double(height) * scale).rounded())
            stride = 3; fps = 10
        }
        let folder = destination.deletingLastPathComponent().appendingPathComponent(".mg-video-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: folder) }
        let partial = folder.appendingPathComponent("video." + (options.format == .mp4 ? options.preset?.fileExtension ?? "mp4" : options.format.rawValue))
        let count = plan.durationFrames / stride
        var movie: MGMovieWriter?
        var gif: CGImageDestination?
        if options.format == .mp4 {
            if let preset = options.preset { movie = try MGMovieWriter(url: partial, preset: preset, maxBufferedFrames: 8) }
            else { movie = try MGMovieWriter(url: partial, width: width, height: height, fps: 30, maxBufferedFrames: 8) }
        }
        else {
            gif = CGImageDestinationCreateWithURL(partial as CFURL, UTType.gif.identifier as CFString, count, nil)
            guard let gif else { throw MGError("video2d.export.gifWriter") }
            CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        }
        defer { movie?.cancel() }
        progress?(0, count)
        for outputIndex in 0..<count {
            try Task.checkCancellation()
            try autoreleasepool {
                let image = try frame(outputIndex * stride, in: plan, burnCaptions: options.burnCaptions)
                if let movie { try movie.append(image) }
                else if let gif {
                    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw MGError("video2d.budget.raster") }
                    context.interpolationQuality = .high
                    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                    guard let scaled = context.makeImage() else { throw MGError("video2d.budget.raster") }
                    CGImageDestinationAddImage(gif, scaled, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1, kCGImagePropertyGIFUnclampedDelayTime: 0.1]] as CFDictionary)
                }
            }
            progress?(outputIndex + 1, count)
        }
        try Task.checkCancellation()
        if let movie { try movie.finish() }
        if let gif, !CGImageDestinationFinalize(gif) { throw MGError("video2d.export.gifFinish") }
        try Task.checkCancellation()
        let partialSRT = folder.appendingPathComponent("captions.srt")
        if subtitles != nil { try srt(plan).write(to: partialSRT, atomically: true, encoding: .utf8) }
        var publishedVideo = false
        do {
            try manager.moveItem(at: partial, to: destination)
            publishedVideo = true
            if let subtitles { try manager.moveItem(at: partialSRT, to: subtitles) }
        } catch {
            if publishedVideo { try? manager.removeItem(at: destination) }
            throw error
        }
        return MGVideoExportReceipt(destination: destination, subtitles: subtitles, frameCount: count, fps: fps, width: width, height: height,
                                    durationSeconds: Double(plan.durationFrames) / 30, warnings: plan.warnings)
    }
}
