// SPDX-License-Identifier: Apache-2.0
import XCTest
import AVFoundation
import ImageIO
@_spi(Experimental) @testable import MartyGraphics

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
        for fixture in MGFixtures.all {
            let data = Data(fixture.json.utf8)
            XCTAssertEqual(try MGParser.scene(data: data).get(), try MGParser.scene(data: data, programmaticVideo: false).get(), fixture.id)
        }
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

    func testTickFormattingUsesDoubleAndNormalizesZero() {
        XCTAssertEqual(MGVideoDrawing.tick(0), "0")
        XCTAssertEqual(MGVideoDrawing.tick(-0.0), "0")
        XCTAssertEqual(MGVideoDrawing.tick(2.5), "2.5")
        XCTAssertEqual(MGVideoDrawing.tick(12345), "1.234E+04")
    }

    func testAxesAndNumberLineZeroTickLabels() throws {
        let checked = try plan(changed { layer in
            layer["elements"] = [
                ["id": "axes", "kind": "axes", "at": [300, 300], "color": "#276EF1",
                 "size": [400, 200], "xRange": [-1, 1], "yRange": [-1, 1], "ticks": 3],
                ["id": "number-line", "kind": "numberLine", "at": [300, 200], "color": "#276EF1",
                 "length": 400, "range": [-1, 1], "ticks": 3],
            ]
            layer["tracks"] = []
        })
        XCTAssertEqual(MGVideoDrawing.ticks(checked.elements[0]).map { $0.0 }, ["-1", "-1", "0", "0", "1", "1"])
        XCTAssertEqual(MGVideoDrawing.ticks(checked.elements[1]).map { $0.0 }, ["-1", "0", "1"])
    }

    func testTrackCaptionAndPrimitiveBounds() throws {
        XCTAssertEqual(MGVideoDrawing.tick(-0.0), "0")
        for value in [0.0000001, -0.0000001] {
            let tick = try XCTUnwrap(Double(MGVideoDrawing.tick(value)))
            XCTAssertEqual(tick, value, accuracy: 1e-20)
        }
        try refuse { layer in
            let tracks = layer["tracks"] as! [[String: Any]]
            layer["tracks"] = Array(repeating: tracks[0], count: 65)
        }
        try refuse { layer in
            var tracks = layer["tracks"] as! [[String: Any]]
            tracks[0]["keyframes"] = Array(repeating: ["frame": 0, "opacity": 1], count: 121)
            layer["tracks"] = tracks
        }
        try refuse { layer in layer["captions"] = Array(repeating: ["startFrame": 0, "endFrame": 1, "text": "Caption"], count: 61) }
        try refuse({ layer in
            var tracks = layer["tracks"] as! [[String: Any]]
            tracks[0]["keyframes"] = [["frame": 1, "opacity": 0], ["frame": 1, "opacity": 1]]
            layer["tracks"] = tracks
        }, family: "video2d.frame")
        try refuse { layer in
            var tracks = layer["tracks"] as! [[String: Any]]
            tracks[0]["keyframes"] = [["frame": 0], ["frame": 1]]
            layer["tracks"] = tracks
        }
        let primitives: [[String: Any]] = [
            ["kind": "arrow", "to": [400, 300], "strokeWidth": 17],
            ["kind": "label", "text": String(repeating: "x", count: 161), "fontSize": 24],
            ["kind": "label", "text": "Text", "fontSize": 11],
            ["kind": "axes", "size": [400, 200], "xRange": [0, 1], "yRange": [0, 1], "ticks": 21],
            ["kind": "axes", "size": [400, 200], "xRange": [1, 0], "yRange": [0, 1], "ticks": 5],
            ["kind": "numberLine", "length": 100, "range": [-10001, 1], "ticks": 5],
            ["kind": "numberLine", "length": 1, "range": [0, 10000], "ticks": 20],
            ["kind": "code", "lines": Array(repeating: "code", count: 25), "fontSize": 24, "highlightLine": 1],
            ["kind": "code", "lines": ["code"], "fontSize": 41, "highlightLine": 1],
        ]
        for primitive in primitives {
            try refuse { layer in
                var element = primitive
                element["id"] = "primitive"; element["at"] = [300, 300]; element["color"] = "#276EF1"
                layer["elements"] = [element]; layer["tracks"] = []
            }
        }
    }

    func testSparseKeyframesAndHoldHighlight() throws {
        for interpolation in ["linear", "hold"] {
            let checked = try plan(changed { layer in
                layer["tracks"] = [["target": "three", "interpolation": interpolation, "keyframes": [
                    ["frame": 0, "opacity": 0.5], ["frame": 30, "at": [400, 300]],
                    ["frame": 60, "at": [500, 300]], ["frame": 90, "opacity": 1],
                ]]]
            })
            XCTAssertEqual(try MGTimeline.videoFrame(15, in: checked)[0].at, [300, 300])
            XCTAssertEqual(try MGTimeline.videoFrame(45, in: checked)[0].at, [interpolation == "linear" ? 450 : 400, 300])
            XCTAssertEqual(try MGTimeline.videoFrame(119, in: checked)[0].at, [500, 300])
            XCTAssertEqual(try MGTimeline.videoFrame(45, in: checked)[0].opacity, interpolation == "linear" ? 0.75 : 0.5)
        }
        let sorting = try plan(example())
        XCTAssertEqual(try MGTimeline.videoFrame(29, in: sorting)[4].highlightLine, 1)
        XCTAssertEqual(try MGTimeline.videoFrame(30, in: sorting)[4].highlightLine, 2)
        let git = try plan(example("git-flow"))
        XCTAssertEqual(try MGTimeline.videoFrame(0, in: git)[2].opacity, 0)
        XCTAssertEqual(try MGTimeline.videoFrame(119, in: git)[2].opacity, 1)
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
        let scene = try MGParser.scene(data: example(), programmaticVideo: true).get()
        XCTAssertTrue(scene.animates)
        XCTAssertEqual(MGTimeline.cycle(scene), 4)
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

    func testCodeHighlightDrawingBoundsAtReservedBand() throws {
        try refuse({ layer in
            layer["elements"] = [["id": "code", "kind": "code", "at": [100, 152], "color": "#FFFFFF", "fontSize": 40, "lines": ["code"], "highlightLine": 1]]
            layer["tracks"] = []; layer["captions"] = []
        }, family: "video2d.layout.elements.code.frame.0")
        for lines in [["code"], ["code", "print(value)"], ["Åg_j"]] {
            let initial = try plan(changed { layer in
                layer["elements"] = [["id": "code", "kind": "code", "at": [100, 300], "color": "#FFFFFF", "fontSize": 40, "lines": lines, "highlightLine": lines.count]]
                layer["tracks"] = []; layer["captions"] = []
            })
            let boundary = 300 - floor(MGVideoDrawing.bounds(initial.elements[0]).minY - 96)
            let checked = try plan(changed { layer in
                layer["elements"] = [["id": "code", "kind": "code", "at": [100, boundary], "color": "#FFFFFF", "fontSize": 40, "lines": lines, "highlightLine": lines.count]]
                layer["tracks"] = []; layer["captions"] = []
            })
            let layout = MGVideoDrawing.codeLayout(checked.elements[0])
            XCTAssertGreaterThanOrEqual(layout.bounds.minY, 96)
            XCTAssertLessThan(layout.bounds.minY, 97)
            XCTAssertTrue(layout.bounds.contains(try XCTUnwrap(layout.highlight)))
            for line in layout.lines { XCTAssertTrue(layout.bounds.contains(line.bounds)) }
            let image = try MGProgrammaticVideo.frame(0, in: checked, burnCaptions: false)
            let empty = try MGVideoDrawing.draw([], plan: checked, frame: 0, burnCaptions: false)
            let pixels = try XCTUnwrap(image.dataProvider?.data) as Data
            let background = try XCTUnwrap(empty.dataProvider?.data) as Data
            XCTAssertNotEqual(pixels, background)
            let band = ((image.height - 96) * image.bytesPerRow)..<(image.height * image.bytesPerRow)
            XCTAssertTrue(pixels[band] == background[band], "Code or highlight entered the reserved band")
        }
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
                XCTAssertEqual(receipt.durationSeconds, 4, accuracy: 1e-8)
                XCTAssertEqual(receipt.width, format == .mp4 ? 1280 : 640)
                XCTAssertEqual(receipt.height, format == .mp4 ? 720 : 360)
                XCTAssertEqual(try String(contentsOf: XCTUnwrap(receipt.subtitles), encoding: .utf8), MGProgrammaticVideo.srt(checked))
                if format == .mp4 {
                    let asset = AVURLAsset(url: destination)
                    let tracks = try await asset.loadTracks(withMediaType: .video)
                    let track = try XCTUnwrap(tracks.first)
                    let timeRange = try await track.load(.timeRange)
                    let naturalSize = try await track.load(.naturalSize)
                    XCTAssertEqual(CMTimeCompare(timeRange.duration, CMTime(value: 120, timescale: 30)), 0)
                    XCTAssertEqual(naturalSize, CGSize(width: 1280, height: 720))
                    let reader = try AVAssetReader(asset: asset)
                    let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
                    reader.add(output); XCTAssertTrue(reader.startReading())
                    var count = 0
                    while let sample = output.copyNextSampleBuffer() {
                        XCTAssertNotNil(CMSampleBufferGetImageBuffer(sample))
                        XCTAssertEqual(CMTimeCompare(CMSampleBufferGetPresentationTimeStamp(sample), CMTime(value: Int64(count), timescale: 30)), 0)
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

    func testMaximumMP4DimensionsAndRoundedSRT() async throws {
        let checked = try plan(changed { layer in
            layer["canvas"] = ["width": 1920, "height": 1080]
            layer["durationFrames"] = 3; layer["tracks"] = []
            layer["captions"] = [["startFrame": 1, "endFrame": 2, "text": "One frame"]]
        })
        XCTAssertTrue(MGProgrammaticVideo.srt(checked).contains("00:00:00,033 --> 00:00:00,067"))
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("mg-pv-1080-\(UUID()).mp4")
        defer { try? FileManager.default.removeItem(at: destination) }
        let receipt = try await MGProgrammaticVideo.export(checked, to: destination, options: .init(writeSRT: false), programmaticVideo: true)
        XCTAssertEqual(receipt.width, 1920); XCTAssertEqual(receipt.height, 1080)
        XCTAssertEqual(receipt.frameCount, 3); XCTAssertEqual(receipt.durationSeconds, 0.1, accuracy: 1e-8)
        XCTAssertNil(receipt.subtitles)
        let asset = AVURLAsset(url: destination)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let naturalSize = try await track.load(.naturalSize)
        let timeRange = try await track.load(.timeRange)
        XCTAssertEqual(naturalSize, CGSize(width: 1920, height: 1080))
        XCTAssertEqual(CMTimeCompare(timeRange.duration, CMTime(value: 3, timescale: 30)), 0)
    }

    func testCancellationAndExportRefusalsRemovePartialFiles() async throws {
        let checked = try plan(example())
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("mg-pv-cancel-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let destination = folder.appendingPathComponent("cancel.mp4")
        do { _ = try await MGProgrammaticVideo.export(checked, to: destination); XCTFail("Missing opt-in") }
        catch { XCTAssertEqual((error as? MGError)?.reason, "video2d.optIn") }
        for format in [MGVideoExportOptions.Format.mp4, .gif] {
            let task = Task {
                try await MGProgrammaticVideo.export(checked, to: destination, options: .init(format: format), programmaticVideo: true) { index, _ in
                    if index == 3 { withUnsafeCurrentTask { $0?.cancel() } }
                }
            }
            do { _ = try await task.value; XCTFail("Cancellation ignored") } catch is CancellationError {} catch { XCTFail("\(error)") }
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), [])
        }
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
