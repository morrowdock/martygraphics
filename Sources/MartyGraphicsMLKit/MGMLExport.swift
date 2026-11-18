// SPDX-License-Identifier: Apache-2.0
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
@_spi(Experimental) import MartyGraphics

public enum MGMLExportFormat: String, Sendable {
    case mp4
    case pngSequence
}

public struct MGMLExportReceipt: Codable, Equatable, Sendable {
    public let frames: Int
    public let fps: Int
    public let width: Int
    public let height: Int
    public let transparent: Bool
}

extension MGMLDocument {
    /// Writes one silent H.264 movie or a directory of zero-based RGBA PNG frames at 30 fps.
    public func export(to destination: URL, size: MGMLSize, format: MGMLExportFormat = .mp4,
                       theme: MGTheme = .board) throws -> MGMLExportReceipt {
        guard destination.isFileURL else { throw MGMLReason.destination }
        try Task.checkCancellation()
        let manager = FileManager.default
        guard !manager.fileExists(atPath: destination.path) else { throw MGMLReason.exists }
        let staging = destination.deletingLastPathComponent()
            .appendingPathComponent(".mg-ml-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: staging) }

        let partial = staging.appendingPathComponent(format == .mp4 ? "video.mp4" : "frames")
        let movie: MGMovieWriter?
        switch format {
        case .mp4:
            movie = try MGMovieWriter(url: partial, width: size.width, height: size.height,
                                      fps: Int32(Self.framesPerSecond), maxBufferedFrames: 8)
        case .pngSequence:
            movie = nil
            try manager.createDirectory(at: partial, withIntermediateDirectories: false)
        }
        defer { movie?.cancel() }
        let transparent = format == .pngSequence
        var index = 0
        for item in items {
            var lastKey: Int?
            var cached: CGImage?
            for frame in 0..<item.content.frameCount {
                try Task.checkCancellation()
                try autoreleasepool {
                    let key = item.content.imageKey(frame)
                    let image: CGImage
                    if key == lastKey, let cached {
                        image = cached
                    } else {
                        image = try draw(item, at: frame, size: size, theme: theme, transparent: transparent)
                        cached = image
                        lastKey = key
                    }
                    if let movie {
                        try movie.append(image)
                    } else {
                        let file = partial.appendingPathComponent(String(format: "frame-%05d.png", index))
                        try Self.writePNG(image, to: file)
                    }
                }
                index += 1
            }
        }
        try movie?.finish()
        try Task.checkCancellation()
        try manager.moveItem(at: partial, to: destination)
        return MGMLExportReceipt(frames: index, fps: Self.framesPerSecond,
                                 width: size.width, height: size.height, transparent: transparent)
    }

    private static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw MGMLReason.png
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw MGMLReason.png }
    }
}
