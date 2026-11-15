// SPDX-License-Identifier: Apache-2.0
import XCTest
import AVFoundation
import ImageIO
@testable import MartyGraphics

final class ProgrammaticVideoTests: XCTestCase {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    func example(_ name: String = "sorting") throws -> Data {
        try Data(contentsOf: root.appendingPathComponent("docs/examples/programmatic-video/\(name).json"))
    }

    func plan(_ data: Data) throws -> MGCheckedVideoPlan {
        try MGProgrammaticVideo.check(MGParser.scene(data: data, programmaticVideo: true).get(), programmaticVideo: true)
    }

    func changed(_ mutation: (inout [String: Any]) -> Void) throws -> Data {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: example()) as? [String: Any])
        var layer = try XCTUnwrap(object["layer2d"] as? [String: Any])
        mutation(&layer); object["layer2d"] = layer
        return try JSONSerialization.data(withJSONObject: object)
    }

    func refuse(_ mutation: (inout [String: Any]) -> Void, family: String = "video2d.", file: StaticString = #filePath, line: UInt = #line) throws {
        let result = MGParser.scene(data: try changed(mutation), programmaticVideo: true)
        guard case .failure(let error) = result else { return XCTFail("Accepted invalid input", file: file, line: line) }
        XCTAssertTrue(error.reason.hasPrefix(family), error.reason, file: file, line: line)
    }

    func testOptInAndLegacyCorpusCompatibility() throws {
        var count = 0
        let directories = ["Tests/MartyGraphicsTests", "docs/fixtures", "Examples/Explainers"]
        for directory in directories {
            guard let files = FileManager.default.enumerator(at: root.appendingPathComponent(directory), includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in files where url.pathExtension == "json" {
                let data = try Data(contentsOf: url)
                let baseline = MGParser.scene(data: data)
                let disabled = MGParser.scene(data: data, programmaticVideo: false)
                switch (baseline, disabled) {
                case (.success(let original), .success(let current)): XCTAssertEqual(original, current, url.path)
                case (.failure(let original), .failure(let current)): XCTAssertEqual(original, current, url.path)
                default: XCTFail("Compatibility changed: \(url.path)")
                }
                count += 1
            }
        }
        XCTAssertGreaterThan(count, 10)
        for name in ["sorting", "projectile", "git-flow"] {
            let data = try example(name)
            for result in [MGParser.scene(data: data), MGParser.scene(data: data, programmaticVideo: false)] {
                guard case .failure(let error) = result else { return XCTFail("Default parser accepted layer") }
                XCTAssertEqual(error.reason, "scene.unknown.layer2d")
            }
            XCTAssertEqual(try plan(data).durationFrames, 120)
        }
        let legacy = Data(#"{"v":1,"items":[{"id":"a","k":"body","at":[0,0]}]}"#.utf8)
        XCTAssertEqual(try MGParser.scene(data: legacy).get(), try MGParser.scene(data: legacy, programmaticVideo: true).get())
    }

    func testDraftSchemaMatchesBundledResource() throws {
        let bundled = try XCTUnwrap(Bundle.module.url(forResource: "scene-2d-layer.draft.schema", withExtension: "json"))
        XCTAssertEqual(try Data(contentsOf: bundled), try Data(contentsOf: root.appendingPathComponent("docs/schemas/scene-2d-layer.draft.schema.json")))
    }

    func testClosedEnvelopeAndBounds() throws {
        for value in [0, 1801, -1] { try refuse { $0["durationFrames"] = value } }
        for value in [0, 10, 31, 60] { try refuse { $0["fps"] = value } }
        try refuse({ $0["version"] = "next" }, family: "video2d.version")
        try refuse { $0["unexpected"] = true }
        try refuse { $0.removeValue(forKey: "captions") }
        for canvas in [["width": 319, "height": 720], ["width": 1921, "height": 720], ["width": 1280, "height": 179], ["width": 1280, "height": 1081], ["width": 1280.5, "height": 720]] {
            try refuse { $0["canvas"] = canvas }
        }
        try refuse { $0["elements"] = [] }
        try refuse { layer in
            let elements = layer["elements"] as! [[String: Any]]
            layer["elements"] = Array(repeating: elements[0], count: 65)
        }
        for property in ["at", "size"] {
            for value: [Double] in [[1921, 0], [0], [0, 0, 0], [-1921, 1]] {
                try refuse { layer in
                    var elements = layer["elements"] as! [[String: Any]]
                    elements[0][property] = value; layer["elements"] = elements
                }
            }
        }
        for (key, value) in [("opacity", -0.1 as Any), ("opacity", 1.1), ("color", "#bad"), ("id", "Bad"), ("id", String(repeating: "a", count: 33)), ("shape", "triangle"), ("run", "code")] {
            try refuse { layer in
                var elements = layer["elements"] as! [[String: Any]]
                elements[0][key] = value; layer["elements"] = elements
            }
        }
        let huge = Data(repeating: 32, count: 65537)
        XCTAssertThrowsError(try plan(huge))
    }

    func testSemanticRefusalsAndTextSafety() throws {
        try refuse({ layer in
            var elements = layer["elements"] as! [[String: Any]]
            elements[1]["id"] = elements[0]["id"]; layer["elements"] = elements
        }, family: "video2d.target")
        try refuse({ layer in
            var tracks = layer["tracks"] as! [[String: Any]]
            tracks[0]["target"] = "missing"; layer["tracks"] = tracks
        }, family: "video2d.target")
        try refuse({ layer in
            var tracks = layer["tracks"] as! [[String: Any]]
            tracks[0]["keyframes"] = [["frame": 0, "opacity": 0], ["frame": 120, "opacity": 1]]
            layer["tracks"] = tracks
        }, family: "video2d.frame")
        try refuse({ layer in layer["captions"] = [["startFrame": 0, "endFrame": 90, "text": "First"], ["startFrame": 89, "endFrame": 120, "text": "Overlap"]] }, family: "video2d.frame")
        try refuse({ layer in
            var elements = layer["elements"] as! [[String: Any]]
            elements[4]["highlightLine"] = 3; layer["elements"] = elements
        }, family: "video2d.highlight")
        for text in ["https://example.invalid", "<script>code</script>", "\u{202e}bad", "line\nline", String(repeating: "x", count: 121)] {
            try refuse { layer in
                var elements = layer["elements"] as! [[String: Any]]
                elements[4]["lines"] = [text]; layer["elements"] = elements
            }
        }
        let literal = try plan(changed { layer in
            var elements = layer["elements"] as! [[String: Any]]
            elements[4]["lines"] = ["if i < n: {literal}", "    never_execute()"]
            layer["elements"] = elements
        })
        XCTAssertEqual(literal.elements[4].lines?[0], "if i < n: {literal}")
    }

    func testPreflightChecksEveryFrameAndCaptionLayout() throws {
        try refuse({ layer in
            var tracks = layer["tracks"] as! [[String: Any]]
            tracks[0]["keyframes"] = [["frame": 0, "at": [300, 300]], ["frame": 60, "at": [1900, 300]]]
            layer["tracks"] = tracks
        }, family: "video2d.layout")
        try refuse({ layer in
            layer["captions"] = [["startFrame": 0, "endFrame": 120, "text": String(repeating: "W", count: 240)]]
        }, family: "video2d.layout")
        try refuse { layer in
            var elements = layer["elements"] as! [[String: Any]]
            elements[4]["at"] = [1250, 450]; layer["elements"] = elements
        }
    }

    func testTimelineStructuralGoldenAndRaster() throws {
        let checked = try plan(example())
        let first = try MGTimeline.videoFrame(0, in: checked)
        let middle = try MGTimeline.videoFrame(45, in: checked)
        let last = try MGTimeline.videoFrame(119, in: checked)
        XCTAssertEqual(first[0].at, [300, 300])
        XCTAssertEqual(middle[0].at[0], 300 + 180 * 45 / 89, accuracy: 1e-9)
        XCTAssertEqual(last[0].at, [480, 300])
        XCTAssertEqual(last[1].at, [300, 300])
        XCTAssertFalse(checked.warnings.isEmpty)
        XCTAssertThrowsError(try MGTimeline.videoFrame(-1, in: checked))
        XCTAssertThrowsError(try MGProgrammaticVideo.frame(120, in: checked))
        let image = try MGProgrammaticVideo.frame(0, in: checked)
        XCTAssertEqual(image.width, 1280); XCTAssertEqual(image.height, 720)
        let pixels = try XCTUnwrap(image.dataProvider?.data) as Data
        let position = (720 - 300) * image.bytesPerRow + 300 * 4
        XCTAssertEqual(pixels[position], 39, accuracy: 1)
        XCTAssertEqual(pixels[position + 1], 110, accuracy: 1)
        XCTAssertEqual(pixels[position + 2], 241, accuracy: 1)
        let without = try MGProgrammaticVideo.frame(0, in: checked, burnCaptions: false)
        XCTAssertNotEqual(pixels, try XCTUnwrap(without.dataProvider?.data) as Data)
        XCTAssertTrue(MGProgrammaticVideo.srt(checked).contains("00:00:00,000 --> 00:00:04,000"))
    }

    func testExampleMP4AndGIFExportsDecode() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("mg-pv-tests-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        for name in ["sorting", "projectile", "git-flow"] {
            let checked = try plan(example(name))
            for format in [MGVideoExportOptions.Format.mp4, .gif] {
                let destination = folder.appendingPathComponent("\(name)-\(format.rawValue).\(format.rawValue)")
                let receipt = try await MGProgrammaticVideo.export(checked, to: destination, options: .init(format: format), programmaticVideo: true)
                XCTAssertEqual(receipt.frameCount, format == .mp4 ? 120 : 40)
                XCTAssertEqual(receipt.durationSeconds, 4)
                XCTAssertEqual(receipt.width, format == .mp4 ? 1280 : 640)
                XCTAssertEqual(receipt.height, format == .mp4 ? 720 : 360)
                XCTAssertEqual(try String(contentsOf: XCTUnwrap(receipt.subtitles), encoding: .utf8), MGProgrammaticVideo.srt(checked))
                if format == .mp4 {
                    let asset = AVURLAsset(url: destination)
                    let track = try XCTUnwrap(asset.tracks(withMediaType: .video).first)
                    XCTAssertEqual(track.timeRange.duration.seconds, 4, accuracy: 1e-8)
                    XCTAssertEqual(track.naturalSize, CGSize(width: 1280, height: 720))
                    let reader = try AVAssetReader(asset: asset)
                    let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
                    reader.add(output); XCTAssertTrue(reader.startReading())
                    var count = 0
                    while let sample = output.copyNextSampleBuffer() {
                        XCTAssertNotNil(CMSampleBufferGetImageBuffer(sample))
                        XCTAssertEqual(CMSampleBufferGetPresentationTimeStamp(sample).seconds, Double(count) / 30, accuracy: 1e-8)
                        count += 1
                    }
                    XCTAssertEqual(count, 120); XCTAssertEqual(reader.status, .completed)
                } else {
                    let source = try XCTUnwrap(CGImageSourceCreateWithURL(destination as CFURL, nil))
                    XCTAssertEqual(CGImageSourceGetCount(source), 40)
                    var duration = 0.0
                    for index in 0..<40 {
                        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, index, nil))
                        XCTAssertEqual(image.width, 640); XCTAssertEqual(image.height, 360)
                        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any])
                        let gif = try XCTUnwrap(properties[kCGImagePropertyGIFDictionary] as? [CFString: Any])
                        duration += try XCTUnwrap(gif[kCGImagePropertyGIFDelayTime] as? Double)
                    }
                    XCTAssertEqual(duration, 4, accuracy: 1e-8)
                }
            }
        }
    }

    func testCancellationAndExportRefusalsRemovePartialFiles() async throws {
        let checked = try plan(example())
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("mg-pv-cancel-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let destination = folder.appendingPathComponent("cancel.mp4")
        do { _ = try await MGProgrammaticVideo.export(checked, to: destination); XCTFail("Missing opt-in") }
        catch { XCTAssertEqual((error as? MGError)?.reason, "video2d.optIn") }
        let task = Task {
            try await MGProgrammaticVideo.export(checked, to: destination, programmaticVideo: true) { index, _ in
                if index == 3 { withUnsafeCurrentTask { $0?.cancel() } }
            }
        }
        do { _ = try await task.value; XCTFail("Cancellation ignored") } catch is CancellationError {} catch { XCTFail("\(error)") }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), [])
        let odd = try plan(changed { $0["canvas"] = ["width": 1279, "height": 720] })
        do { _ = try await MGProgrammaticVideo.export(odd, to: destination, programmaticVideo: true); XCTFail("Odd MP4 dimensions accepted") }
        catch { XCTAssertEqual((error as? MGError)?.reason, "video2d.export.evenDimensions") }
        let duration = try plan(changed { $0["durationFrames"] = 121 })
        do { _ = try await MGProgrammaticVideo.export(duration, to: destination, options: .init(format: .gif), programmaticVideo: true); XCTFail("Invalid GIF duration") }
        catch { XCTAssertEqual((error as? MGError)?.reason, "video2d.export.gifDuration") }
    }

    func testWriterBackpressureFailureAndTimeout() throws {
        XCTAssertNoThrow(try MGMovieWriter.waitUntilReady(ready: { true }, status: { .writing }))
        for status in [AVAssetWriter.Status.failed, .cancelled] {
            XCTAssertThrowsError(try MGMovieWriter.waitUntilReady(ready: { false }, status: { status }))
        }
        XCTAssertThrowsError(try MGMovieWriter.waitUntilReady(timeout: 0.01, ready: { false }, status: { .writing }))
    }
}
