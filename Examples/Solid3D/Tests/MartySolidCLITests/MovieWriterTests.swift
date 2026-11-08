// SPDX-License-Identifier: Apache-2.0
import AVFoundation
import Foundation
import XCTest
@testable import MartySolidCLI

/// The `loop.mp4` writer stops instead of hanging when AVFoundation stops: a failed or cancelled writer, and a writer
/// that never becomes ready, throw (so `render` removes its output directory and writes no manifest).
final class MovieWriterTests: XCTestCase {
    func frame(_ w: Int, _ h: Int) -> CGImage {
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(gray: 0.5, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()!
    }
    func temp(_ name: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("movie-writer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir.appendingPathComponent(name)
    }

    func testWaitStopsOnFailureCancelAndTimeout() throws {
        XCTAssertNoThrow(try MovieWriter.waitUntilReady(ready: { true }, status: { .writing }))
        for status in [AVAssetWriter.Status.failed, .cancelled] {
            let t0 = Date()
            XCTAssertThrowsError(try MovieWriter.waitUntilReady(ready: { false }, status: { status })) { e in
                XCTAssertTrue("\(e)".hasPrefix("mp4: writer"), "\(e)")
            }
            XCTAssertLessThan(Date().timeIntervalSince(t0), 1)   // at once, not after the timeout
        }
        let t0 = Date()
        XCTAssertThrowsError(try MovieWriter.waitUntilReady(timeout: 0.05, ready: { false }, status: { .writing })) { e in
            XCTAssertTrue("\(e)".contains("not ready"), "\(e)")
        }
        XCTAssertLessThan(Date().timeIntervalSince(t0), 2)
    }

    /// A real writer that is cancelled mid-loop: the next frame and `finish` throw, quickly.
    func testCancelledWriterThrowsInsteadOfHanging() throws {
        let movie = try MovieWriter(url: try temp("loop.mp4"), width: 64, height: 48, fps: 10)
        try movie.append(frame(64, 48))
        movie.writer.cancelWriting()
        let t0 = Date()
        XCTAssertThrowsError(try movie.append(frame(64, 48)))
        XCTAssertThrowsError(try movie.finish())
        XCTAssertLessThan(Date().timeIntervalSince(t0), 5)
        XCTAssertEqual(movie.frames, 1)
    }

    func testWriterThatCannotStartThrows() throws {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("no-such-dir-\(UUID().uuidString)/loop.mp4")
        XCTAssertThrowsError(try MovieWriter(url: missing, width: 64, height: 48, fps: 10))
    }

    func testCompleteMovieHasExactFrameTimes() throws {
        let url = try temp("loop.mp4")
        let movie = try MovieWriter(url: url, width: 65, height: 49, fps: 10)   // odd sizes are written one pixel smaller
        XCTAssertEqual(movie.width, 64); XCTAssertEqual(movie.height, 48)
        for _ in 0..<5 { try movie.append(frame(65, 49)) }
        try movie.finish()
        let asset = AVURLAsset(url: url)
        let track = try XCTUnwrap(asset.tracks(withMediaType: .video).first)
        XCTAssertEqual(CMTimeGetSeconds(track.timeRange.duration), 0.5, accuracy: 1e-9)
        let reader = try AVAssetReader(asset: asset)
        let out = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(out); reader.startReading()
        var times: [Double] = []
        while let s = out.copyNextSampleBuffer() { if CMSampleBufferGetNumSamples(s) > 0 { times.append(CMSampleBufferGetPresentationTimeStamp(s).seconds) } }
        assertTimes(times, [0, 0.1, 0.2, 0.3, 0.4])
    }
}

private func assertTimes(_ a: [Double], _ b: [Double], accuracy: Double = 1e-9, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(a.count, b.count, file: file, line: line)
    for (x, y) in zip(a, b) { XCTAssertEqual(x, y, accuracy: accuracy, file: file, line: line) }
}
