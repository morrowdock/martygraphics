// SPDX-License-Identifier: Apache-2.0
import CoreGraphics
import Foundation
import MartyGraphics
import XCTest
@testable import MartyGraphicsMLKit

final class MLKitV2Tests: XCTestCase {
    private let grayscale = "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAAAAABX3VL4AAAADklEQVR4nGNg3Myg8R8ABCYB3HMXR8sAAAAASUVORK5CYII="
    private let rgb = "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAFklEQVR4nGNgEPyv7d/OcIRjqbGyOAAcxgPwRSGXjgAAAABJRU5ErkJggg=="
    private let oversized = "iVBORw0KGgoAAAANSUhEUgAAAEEAAAABCAAAAACkxJz1AAAADElEQVR4nGNgpBQAAAijAELmivaAAAAAAElFTkSuQmCC"

    private func check(_ item: [String: Any]) throws -> Result<MGMLDocument, MGMLIssue> {
        let root: [String: Any] = ["v": 1, "kind": "ml-explainer", "title": "Illustrative example", "items": [item]]
        return MGMLKit.check(data: try JSONSerialization.data(withJSONObject: root), mlKit: true)
    }

    private func expect(_ reason: MGMLReason, _ item: [String: Any], _ path: String,
                        file: StaticString = #filePath, line: UInt = #line) throws {
        guard case .failure(let issue) = try check(item) else {
            return XCTFail("Expected \(reason)", file: file, line: line)
        }
        XCTAssertEqual(issue, MGMLIssue(reason: reason, path: "items[0]." + path), file: file, line: line)
    }

    private func candidates(_ scores: [Double]) -> [[String: Any]] {
        scores.enumerated().map { ["token": String(UnicodeScalar(65 + $0.offset)!), "logit": $0.element] }
    }

    private func meaning(_ coordinates: [[Double]], vectors: Bool = false) -> [String: Any] {
        let key = vectors ? "vector" : "position"
        let points: [[String: Any]] = zip(["dog", "cat", "car", "tree"], coordinates).map { ["label": $0.0, key: $0.1] }
        return ["id": "map", "kind": "meaningMap", vectors ? "vectors" : "points": points]
    }

    func testMeaningMapUsesEuclideanDistanceAndStableTies() throws {
        var input = meaning([[2, 1], [4, 2], [-2, -1], [6, 3]])
        input["nearestNeighbors"] = true
        input["cluster"] = ["dog", "cat"]
        let document = try check(input).get()
        guard case .meaningMap(let map) = document.items[0].content else { return XCTFail("Expected a map") }
        XCTAssertEqual(map.label, "illustrative positions")
        XCTAssertEqual(map.points.map(\.position), [[2, 1], [4, 2], [-2, -1], [6, 3]])
        XCTAssertEqual(map.cluster, ["dog", "cat"])
        XCTAssertEqual(map.neighbors.map(\.to), [1, 0, 0, 1])
        XCTAssertEqual(try XCTUnwrap(map.neighbors.first { $0.from == 2 }).value, sqrt(20), accuracy: 1e-14)
        XCTAssertEqual(try XCTUnwrap(map.neighbors.first { $0.from == 3 }).value, sqrt(5), accuracy: 1e-14)
    }

    func testMeaningMapAcceptsTheOriginWithLinks() throws {
        var input = meaning([[0, 0], [0, 1], [-1, 0]])
        input["nearestNeighbors"] = true
        let document = try check(input).get()
        guard case .meaningMap(let map) = document.items[0].content else { return XCTFail("Expected a map") }
        XCTAssertEqual(map.neighbors.map(\.to), [1, 0, 0])
    }

    func testMeaningMapVectorLinksRequirePositiveCosineBeforeProjection() throws {
        var input = meaning([[-2, 0, 0], [2, 1, 0], [4, 2, 0], [0, 0, 1]], vectors: true)
        input["nearestNeighbors"] = true
        let document = try check(input).get()
        guard case .meaningMap(let map) = document.items[0].content else { return XCTFail("Expected a map") }
        XCTAssertEqual(map.neighbors.map(\.from), [1, 2])
        XCTAssertEqual(map.neighbors.map(\.to), [2, 1])
        for edge in map.neighbors {
            XCTAssertEqual(edge.value, 1, accuracy: 1e-14)
        }
        _ = try document.frame(document.frameCount - 1, size: .portrait, transparent: true)
    }

    func testPCAProjectsCenteredVectorsOntoTwoLeadingAxes() throws {
        let input = meaning([[5, 4, 8], [-1, 4, 8], [2, 5, 8], [2, 3, 8]], vectors: true)
        let doc = try check(input).get()
        guard case .meaningMap(let map) = doc.items[0].content else { return XCTFail("Expected a map") }
        XCTAssertEqual(map.label, "2D projection (PCA) of the given vectors")
        XCTAssertEqual(map.dimension, 3)
        let expected = [[3.0, 0], [-3, 0], [0, 1], [0, -1]]
        for (point, truth) in zip(map.points, expected) {
            for (coordinate, value) in zip(point.position, truth) {
                XCTAssertEqual(coordinate, value, accuracy: 1e-12)
            }
        }
        XCTAssertEqual(MGMLKit.report(.success(doc)), MGMLKit.report(try check(input)))

        let rotated = try check(meaning([[5, 4, 3], [1, 0, -1], [3, 2, 1]], vectors: true)).get()
        guard case .meaningMap(let line) = rotated.items[0].content else { return XCTFail("Expected a map") }
        XCTAssertEqual(line.points[0].position[0], sqrt(12.0), accuracy: 1e-12)
        XCTAssertEqual(line.points[1].position[0], -sqrt(12.0), accuracy: 1e-12)
        XCTAssertEqual(line.points.map { $0.position[1] }, [0, 0, 0])
    }

    func testMeaningMapRefusals() throws {
        let valid = meaning([[1, 0], [0, 1], [-1, 0]])
        try expect(.mapCount, meaning([[1, 0], [0, 1]]), "points")
        try expect(.mapLengths, meaning([[1, 2, 3], [1, 2, 3, 4], [0, 0, 0]], vectors: true), "vectors[1].vector")
        try expect(.mapCoordinates, meaning([[1, 0], [1e20, 1], [-1, 0]]), "points[1].position[0]")
        try expect(.mapCoordinates, valid.merging(["vectors": []]) { _, new in new }, "points")
        try expect(.mapCoordinates, valid.merging(["vectorCitation": "Unexpected"]) { _, new in new }, "vectorCitation")
        try expect(.mapCluster, valid.merging(["cluster": ["missing"]]) { _, new in new }, "cluster")
        var zeroVector = meaning([[0, 0, 0], [0, 1, 0], [-1, 0, 0]], vectors: true)
        zeroVector["nearestNeighbors"] = true
        try expect(.mapCosine, zeroVector, "vectors")

        var duplicate = valid
        var entries = try XCTUnwrap(valid["points"] as? [[String: Any]])
        entries[1]["label"] = entries[0]["label"]
        duplicate["points"] = entries
        try expect(.mapDuplicate, duplicate, "points[1].label")

        let invalidJSON = Data("""
        {"v":1,"kind":"ml-explainer","title":"Map","items":[{"id":"map","kind":"meaningMap","points":[
        {"label":"dog","position":[1,0]},{"label":"cat","position":[NaN,1]},{"label":"car","position":[-1,0]}]}]}
        """.utf8)
        XCTAssertEqual(MGMLKit.check(data: invalidJSON, mlKit: true), .failure(.init(reason: .json, path: "")))
        let nan: MGJSON = .object(["points": .array([
            .object(["label": .string("dog"), "position": .array([.number(1), .number(0)])]),
            .object(["label": .string("cat"), "position": .array([.number(.nan), .number(1)])]),
            .object(["label": .string("car"), "position": .array([.number(-1), .number(0)])])
        ])])
        XCTAssertThrowsError(try MLMeaningMap(MLObject(nan, path: "map", keys: ["points"]))) {
            XCTAssertEqual($0 as? MGMLIssue, .init(reason: .mapCoordinates, path: "map.points[1].position[0]"))
        }
    }

    private func picture(_ png: String, patchSize: Int = 2) -> [String: Any] {
        ["id": "image", "kind": "pictureToNumbers", "caption": "Original test pixels",
         "imagePNG": png, "patchSize": patchSize, "highlight": [0, 0]]
    }

    func testPicturePreservesDecodedChannelsAndPixelOrder() throws {
        let grey = try check(picture(grayscale)).get()
        let color = try check(picture(rgb)).get()
        guard case .picture(let a) = grey.items[0].content, case .picture(let b) = color.items[0].content else {
            return XCTFail("Expected pictures")
        }
        XCTAssertEqual(a.image.values, [1, 179, 40, 255])
        XCTAssertEqual(a.vectorLength, 4)
        XCTAssertEqual(b.image.values, [0, 17, 255, 43, 79, 135, 196, 8, 165, 51, 35, 23])
        XCTAssertEqual(b.vectorLength, 12)
        XCTAssertEqual(Array(b.patchPixel(x: 0, y: 1)), [196, 8, 165])
        XCTAssertEqual(b.displayed(at: 0).gridOpacity, 0)
        XCTAssertFalse(b.displayed(at: 54).flattened)
        XCTAssertTrue(b.displayed(at: b.frameCount - 1).flattened)

        let selected = try check(picture(rgb, patchSize: 1).merging(["highlight": [1, 0]]) { _, new in new }).get()
        guard case .picture(let patch) = selected.items[0].content else { return XCTFail("Expected a patch") }
        XCTAssertEqual(Array(patch.patchPixel(x: 0, y: 0)), [43, 79, 135])
        XCTAssertEqual(patch.vectorLength, 3)
    }

    func testPictureRefusals() throws {
        try expect(.picturePNG, picture("invalid"), "imagePNG")
        try expect(.pictureSize, picture(oversized, patchSize: 1), "imagePNG")
        try expect(.picturePatch, picture(rgb, patchSize: 3), "patchSize")
        try expect(.pictureSelection, picture(rgb).merging(["highlight": [0, 1]]) { _, new in new }, "highlight")
        try expect(.pictureCaption, picture(rgb).filter { $0.key != "caption" }, "caption")
        try expect(.picturePresentation, picture(rgb).merging(["presentation": "photo"]) { _, new in new }, "presentation")
    }

    func testPictureRefusesPNGColorMetadata() throws {
        // The RGB fixture with one color metadata chunk inserted after IHDR.
        let fixtures = [
            "gAMA": "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAABGdBTUEAALGPC/xhBQAAABZJREFUeJxjYBD8r+3fznCEY6mxsjgAHMYD8EUhl44AAAAASUVORK5CYII=",
            "iCCP": "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAFWlDQ1BUZXN0AAB4nCsoyk/LzEkFAAv+AvJK9b7sAAAAFklEQVR4nGNgEPyv7d/OcIRjqbGyOAAcxgPwRSGXjgAAAABJRU5ErkJggg==",
            "sRGB": "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAAXNSR0IArs4c6QAAABZJREFUeJxjYBD8r+3fznCEY6mxsjgAHMYD8EUhl44AAAAASUVORK5CYII=",
            "cHRM": "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAIGNIUk0AAHomAACAhAAA+gAAAIDoAAB1MAAA6mAAADqYAAAXcJy6UTwAAAAWSURBVHicY2AQ/K/t385whGOpsbI4ABzGA/BFIZeOAAAAAElFTkSuQmCC"
        ]
        for (chunk, png) in fixtures {
            guard case .failure(let issue) = try check(picture(png)) else {
                XCTFail("Accepted PNG with \(chunk)")
                continue
            }
            XCTAssertEqual(issue, .init(reason: .pictureColorMetadata, path: "items[0].imagePNG"), chunk)
        }
    }

    private func generation(selection: String = "greedy") -> [String: Any] {
        ["id": "steps", "kind": "generationLoop", "prompt": ["Test"], "stepCount": 2, "selection": selection,
         "steps": [["candidates": candidates([0, 0, -10])], ["candidates": candidates([0, log(2)]), "temperature": 2]]]
    }

    func testGenerationComputesGreedyAndSeededTokenSequences() throws {
        let doc = try check(generation()).get()
        guard case .generation(let loop) = doc.items[0].content else { return XCTFail("Expected generation") }
        XCTAssertEqual(loop.steps.map(\.token), ["A", "B"])
        XCTAssertEqual(loop.steps[1].distribution.probabilities[1], sqrt(2) / (1 + sqrt(2)), accuracy: 1e-12)
        XCTAssertNil(loop.displayed(at: 0).stepIndex)
        let stepOne = MLGeneration.introFrames
        XCTAssertEqual(loop.displayed(at: stepOne).stepIndex, 0)
        XCTAssertFalse(loop.displayed(at: stepOne + 22).appended)
        XCTAssertTrue(loop.displayed(at: stepOne + 29).appended)
        XCTAssertEqual(loop.displayed(at: loop.frameCount - 1).stepIndex, 1)

        let input = generation(selection: "sample").merging(["seed": 0]) { _, new in new }
        let sampled = try check(input).get()
        guard case .generation(let model) = sampled.items[0].content else { return XCTFail("Expected sampled generation") }
        XCTAssertEqual(model.steps.map(\.token), ["B", "B"])
        XCTAssertEqual(try XCTUnwrap(model.steps[0].draw), 0.8833108082136426, accuracy: 1e-15)
        XCTAssertEqual(try XCTUnwrap(model.steps[1].draw), 0.43152799704850997, accuracy: 1e-15)
        XCTAssertEqual(sampled, try check(input).get())
    }

    func testGenerationRefusals() throws {
        let valid = generation()
        try expect(.generationCount, valid.merging(["stepCount": 9]) { _, new in new }, "stepCount")
        try expect(.generationLogits, valid.merging(["steps": []]) { _, new in new }, "steps")
        try expect(.generationLogits, valid.merging(["steps": [[:], [:]]]) { _, new in new }, "steps[0].candidates")
        var steps = try XCTUnwrap(valid["steps"] as? [[String: Any]])
        steps[0]["candidates"] = [["token": "A", "logit": 0], ["token": "B"]]
        try expect(.generationLogits, valid.merging(["steps": steps]) { _, new in new }, "steps[0].candidates[1].logit")
        steps[0]["candidates"] = candidates([0, -1])
        for chosen in ["absent", "B"] {
            steps[0]["chosen"] = chosen
            try expect(.generationChosen, valid.merging(["steps": steps]) { _, new in new }, "steps[0].chosen")
        }
        try expect(.generationSelection, generation(selection: "sample"), "seed")
        try expect(.generationSelection, generation(selection: "other"), "selection")
        try expect(.generationSelection, valid.merging(["seed": 0]) { _, new in new }, "seed")
    }

    func testTemperatureSweepChecksEveryStageAndHoldsLabelsDuringTween() throws {
        let input: [String: Any] = ["id": "sweep", "kind": "nextTokenProbabilities", "chosen": "A", "tokens": ["Test"],
                                    "candidates": candidates([1, 0]), "temperatures": [0.5, 1, 2, 4]]
        let doc = try check(input).get()
        guard case .probabilities(let sweep) = doc.items[0].content else { return XCTFail("Expected probabilities") }
        XCTAssertTrue(sweep.isSweep)
        for (distribution, t) in zip(sweep.distributions, [0.5, 1, 2, 4]) {
            XCTAssertEqual(distribution.parameter, t)
            XCTAssertEqual(distribution.probabilities[0], 1 / (1 + exp(-1 / t)), accuracy: 1e-12)
            XCTAssertEqual(distribution.sum, 1, accuracy: 1e-12)
        }
        let start = MLProbabilities.introFrames + MLProbabilities.stageFrames
        let tween = try XCTUnwrap(sweep.displayed(at: start + 7))
        let end = try XCTUnwrap(sweep.displayed(at: start + MLProbabilities.transitionFrames - 1))
        XCTAssertEqual(tween.stage, sweep.distributions[0])
        XCTAssertNotEqual(tween.values, tween.stage.probabilities)
        XCTAssertEqual(end.stage, sweep.distributions[1])
        XCTAssertEqual(end.values, end.stage.probabilities)
        try expect(.sweep, input.merging(["temperature": 1]) { _, new in new }, "temperatures")
        try expect(.sweep, input.merging(["temperatures": [1]]) { _, new in new }, "temperatures")
        try expect(.sweep, input.merging(["temperatures": [1, 2, 3, 4, 5]]) { _, new in new }, "temperatures")
        try expect(.sweep, input.merging(["temperatures": [1, 1]]) { _, new in new }, "temperatures[1]")
        try expect(.sweep, input.merging(["temperatures": [1, 0]]) { _, new in new }, "temperatures[1]")
    }

    private var attention: [String: Any] {
        ["id": "weights", "kind": "attention", "imagePNG": rgb, "patchSize": 1, "query": [1, 0],
         "scores": [0, log(2.0), log(3.0)]]
    }

    func testAttentionDerivesGridTargetsAndNormalizedWeights() throws {
        let doc = try check(attention).get()
        guard case .attention(let item) = doc.items[0].content else { return XCTFail("Expected attention") }
        XCTAssertEqual(item.targets.map(\.column), [0, 0, 1])
        XCTAssertEqual(item.targets.map(\.row), [0, 1, 1])
        for (actual, expected) in zip(item.distribution.probabilities, [1.0 / 6, 2.0 / 6, 0.5]) {
            XCTAssertEqual(actual, expected, accuracy: 1e-12)
        }
        XCTAssertEqual(item.distribution.sum, 1, accuracy: 1e-12)
        XCTAssertEqual(item.strongest, 0.5, accuracy: 1e-12)
        XCTAssertEqual(item.displayed(at: 0), 0)
        XCTAssertEqual(item.displayed(at: MLAttention.frameCount - 1), 1)
    }

    func testAttentionRefusals() throws {
        try expect(.attentionGrid, attention.merging(["patchSize": 2]) { _, new in new }, "patchSize")
        try expect(.attentionQuery, attention.merging(["query": [2, 0]]) { _, new in new }, "query")
        try expect(.attentionScores, attention.merging(["scores": [0, 1]]) { _, new in new }, "scores")
        try expect(.attentionScores, attention.merging(["scores": [0, 1, 1_000_001]]) { _, new in new }, "scores[2]")
    }

    func testImageMarkerIdentifierRemainsInvisible() throws {
        var input = meaning([[2, 1], [3, 1.4], [-2, 1]])
        var points = try XCTUnwrap(input["points"] as? [[String: Any]])
        points[1]["imagePNG"] = rgb
        input["points"] = points
        let first = try check(input).get()
        points[1]["label"] = "Another key"
        input["points"] = points
        let second = try check(input).get()
        let imageA = try first.frame(first.frameCount - 1, size: .portrait, transparent: true)
        let imageB = try second.frame(second.frameCount - 1, size: .portrait, transparent: true)
        XCTAssertEqual(try XCTUnwrap(imageA.dataProvider?.data) as Data,
                       try XCTUnwrap(imageB.dataProvider?.data) as Data)
    }

    func testVisionStageFocusChangesPlaybackWithoutChangingTheFacts() throws {
        let base: [String: Any] = [
            "id": "vision", "kind": "visionPipeline", "caption": "Illustrative diagram",
            "imageSize": [120, 80], "patchSize": 20, "embeddingWidth": 64, "textTokens": ["Test"]
        ]
        let standard = try check(base)
        let staged = try check(base.merging(["stageFocus": true]) { _, new in new })
        XCTAssertEqual(MGMLKit.report(standard), MGMLKit.report(staged))
        XCTAssertEqual(try standard.get().frameCount, 90)
        let document = try staged.get()
        XCTAssertEqual(document.frameCount, 180)
        guard case .vision(let vision) = document.items[0].content else { return XCTFail("Expected vision") }
        XCTAssertEqual([0, 40, 80, 120].compactMap { vision.focus(at: $0)?.stage }, [0, 1, 2, 3])
        let first = try document.frame(12, size: .landscape, transparent: true, composition: .rightColumn)
        let second = try document.frame(52, size: .landscape, transparent: true, composition: .rightColumn)
        XCTAssertNotEqual(try XCTUnwrap(first.dataProvider?.data) as Data,
                          try XCTUnwrap(second.dataProvider?.data) as Data)
        try expect(.visionFocus, base.merging(["stageFocus": "true"]) { _, new in new }, "stageFocus")
    }

    func testNewSamplesAndSafeTransparentCompositions() throws {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Examples/Explainers")
        let asset = try Data(contentsOf: directory.appendingPathComponent("ml-dog.png"))
        let sources = ["meaning-map", "picture-to-numbers", "generation-loop", "temperature-sweep", "attention"]
        for source in sources {
            let data = try Data(contentsOf: directory.appendingPathComponent("ml-\(source).json"))
            let doc = try MGMLKit.check(data: data, mlKit: true).get()
            if case .meaningMap(let map) = doc.items[0].content {
                XCTAssertEqual(map.neighbors.map(\.from), [0, 1, 2, 3, 4, 5])
                XCTAssertEqual(map.neighbors.map(\.to), [1, 0, 3, 2, 5, 4])
            }
            if ["meaning-map", "picture-to-numbers", "attention"].contains(source) {
                XCTAssertTrue(String(decoding: data, as: UTF8.self).contains(asset.base64EncodedString()))
            }
            for size in [MGMLSize.portrait, .landscape] {
                let image = try doc.frame(doc.frameCount - 1, size: size, transparent: true, composition: .rightColumn)
                let data = try XCTUnwrap(image.dataProvider?.data) as Data
                XCTAssertEqual(data.count, image.bytesPerRow * size.height)
                func anyAlpha(left: Int, right: Int, top: Int, bottom: Int) -> Bool {
                    for y in top..<bottom {
                        for x in left..<right where data[y * image.bytesPerRow + x * 4 + 3] > 0 { return true }
                    }
                    return false
                }
                if size == .portrait {
                    XCTAssertFalse(anyAlpha(left: 0, right: size.width, top: 0, bottom: 220), source)
                    XCTAssertFalse(anyAlpha(left: 0, right: size.width, top: 1500, bottom: size.height), source)
                } else {
                    XCTAssertFalse(anyAlpha(left: 0, right: 864, top: 0, bottom: size.height), source)
                }
                XCTAssertTrue(anyAlpha(left: size == .portrait ? 64 : 864, right: size.width,
                                       top: 220, bottom: min(1500, size.height)), source)
            }
        }
    }
}
