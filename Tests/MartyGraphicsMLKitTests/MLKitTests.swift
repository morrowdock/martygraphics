// SPDX-License-Identifier: Apache-2.0
import CoreGraphics
import Foundation
import XCTest
@testable import MartyGraphicsMLKit

final class MLKitTests: XCTestCase {
    private let vision: [String: Any] = [
        "id": "vision", "kind": "visionPipeline", "caption": "Illustrative",
        "imageSize": [120, 80], "patchSize": 20, "embeddingWidth": 96, "textTokens": ["a", "b"]
    ]
    private let next: [String: Any] = [
        "id": "next", "kind": "nextTokenProbabilities", "tokens": ["Next", "is"],
        "candidates": [["token": "A", "logit": 0], ["token": "B", "logit": 0], ["token": "C", "logit": 0]],
        "chosen": "A"
    ]
    private let loop: [String: Any] = [
        "id": "loop", "kind": "agentLoop",
        "states": ["plan", "toolCall", "toolResult", "review", "act", "revise", "stop"],
        "requiresReview": true, "stepBudget": 12
    ]

    private func data(_ items: [[String: Any]], _ overrides: [String: Any] = [:]) throws -> Data {
        let root: [String: Any] = ["v": 1, "kind": "ml-explainer", "title": "Synthetic lesson", "items": items]
        return try JSONSerialization.data(withJSONObject: root.merging(overrides) { _, new in new })
    }

    private func checked(_ item: [String: Any]) throws -> MLItem.Content {
        try MGMLKit.check(data: data([item]), mlKit: true).get().items[0].content
    }

    private func expect(_ reason: MGMLReason, _ path: String, _ data: Data, optedIn: Bool = true,
                        file: StaticString = #filePath, line: UInt = #line) {
        guard case .failure(let issue) = MGMLKit.check(data: data, mlKit: optedIn) else {
            return XCTFail("Accepted input expected to fail with \(reason)", file: file, line: line)
        }
        XCTAssertEqual(issue, MGMLIssue(reason: reason, path: path), file: file, line: line)
    }

    private func changed(_ item: [String: Any], _ key: String, _ value: Any?) throws -> Data {
        var item = item
        item[key] = value
        return try data([item])
    }

    func testDocumentRefusalsInStableOrder() throws {
        expect(.optIn, "", try data([vision]), optedIn: false)
        expect(.bytes, "", Data(repeating: 32, count: MGMLKit.maximumInputBytes + 1))
        expect(.json, "", Data([0, 100]))
        expect(.json, "", Data("{".utf8))
        expect(.object, "", Data("[]".utf8))
        expect(.unknown, "", try data([vision], ["extra": true]))
        expect(.version, "v", try data([vision], ["v": true]))
        expect(.kind, "kind", try data([vision], ["kind": "explainer"]))
        expect(.title, "title", try data([vision], ["title": " "]))
        expect(.items, "items", try data([]))
        expect(.items, "items", try data(Array(repeating: vision, count: 5)))
        expect(.object, "items[0]", try data([], ["items": [2]]))
        expect(.itemKind, "items[0].kind", try changed(vision, "kind", "newShape"))
        expect(.id, "items[0].id", try changed(vision, "id", "not an id"))
        expect(.duplicateID, "items[1].id", try data([vision, vision]))
        expect(.unknown, "items[0]", try changed(vision, "claim", "typed"))
    }

    func testVisionDerivesRectangularPatchGridAndTokenCount() throws {
        guard case .vision(let item) = try checked(vision) else { return XCTFail("Wrong item") }
        XCTAssertEqual(item.columns, 6)
        XCTAssertEqual(item.rows, 4)
        XCTAssertEqual(item.patchCount, 24)
        XCTAssertEqual(item.textTokens, ["a", "b"])
        let report = MGMLKit.report(MGMLKit.check(data: try data([vision]), mlKit: true))
        XCTAssertTrue(report.contains("\"illustrativeJoinedTokenCount\" : 26"))
        XCTAssertTrue(report.contains("\"patchCountBasis\" : \"derived\""))
        XCTAssertTrue(report.contains("\"embeddingWidthBasis\" : \"illustrative\""))
    }

    func testVisionRefusals() throws {
        expect(.caption, "items[0].caption", try changed(vision, "caption", nil))
        expect(.caption, "items[0].caption", try changed(vision, "caption", " "))
        expect(.citation, "items[0].citation", try changed(vision, "citation", "<b>invalid</b>"))
        expect(.citation, "items[0].embeddingWidthCitation", try changed(vision, "embeddingWidthCitation", false))
        expect(.visionSize, "items[0].imageSize", try changed(vision, "imageSize", [120, 80.5]))
        expect(.visionSize, "items[0].patchSize", try changed(vision, "patchSize", 0))
        expect(.patchDivision, "items[0].patchSize", try changed(vision, "patchSize", 30))
        expect(.patchDivision, "items[0].patchSize", try changed(vision, "patchSize", 80))
        expect(.patchCount, "items[0].patchSize",
               try data([vision.merging(["imageSize": [65, 65], "patchSize": 1]) { _, new in new }]))
        expect(.embeddingWidth, "items[0].embeddingWidth", try changed(vision, "embeddingWidth", 0))
        expect(.visionLabel, "items[0].projectorLabel", try changed(vision, "projectorLabel", false))
        expect(.tokens, "items[0].textTokens", try changed(vision, "textTokens", []))
        expect(.tokens, "items[0].textTokens[0]", try changed(vision, "textTokens", ["a\u{202e}"]))
    }

    func testSoftmaxUsesMaxShiftAndTemperature() throws {
        var input = next
        input["candidates"] = [["token": "A", "logit": 999_999], ["token": "B", "logit": 999_998],
                               ["token": "C", "logit": -999_999]]
        input["temperature"] = 2
        guard case .probabilities(let item) = try checked(input) else { return XCTFail("Wrong item") }
        let base = item.distributions[0].probabilities
        let hot = item.distributions[1].probabilities
        XCTAssertEqual(base[0], 1 / (1 + exp(-1.0)), accuracy: MGMLKit.probabilityTolerance)
        XCTAssertEqual(hot[0], 1 / (1 + exp(-0.5)), accuracy: MGMLKit.probabilityTolerance)
        XCTAssertEqual(base[2], 0)
        XCTAssertEqual(hot[2], 0)
        XCTAssertLessThan(hot[0], base[0])
        for frame in MLProbabilities.introFrames..<item.frameCount {
            let displayed = try XCTUnwrap(item.displayed(at: frame))
            XCTAssertEqual(displayed.values.reduce(0, +), 1, accuracy: MGMLKit.probabilityTolerance)
        }
        XCTAssertTrue(try XCTUnwrap(item.displayed(at: item.frameCount - 1)).selection)
    }

    func testTopKThenTopPBreakTiesAndRenormalize() throws {
        var input = next
        input["topK"] = 2
        input["topP"] = 0.75
        guard case .probabilities(let item) = try checked(input) else { return XCTFail("Wrong item") }
        XCTAssertEqual(item.distributions.map(\.stage), [.softmax, .topK, .topP])
        XCTAssertEqual(item.distributions[1].probabilities, [0.5, 0.5, 0])
        XCTAssertEqual(item.distributions[2].probabilities, [0.5, 0.5, 0])
        input["topP"] = 0.5
        guard case .probabilities(let prefix) = try checked(input) else { return XCTFail("Wrong item") }
        XCTAssertEqual(prefix.distributions.last?.probabilities, [1, 0, 0])
        input["candidates"] = [["token": "A", "logit": 0], ["token": "B", "logit": -50]]
        input["topP"] = 1
        guard case .probabilities(let full) = try checked(input) else { return XCTFail("Wrong item") }
        XCTAssertGreaterThan(try XCTUnwrap(full.distributions.last).probabilities[1], 0)
    }

    func testProbabilityRefusals() throws {
        expect(.tokens, "items[0].tokens", try changed(next, "tokens", []))
        expect(.candidates, "items[0].candidates", try changed(next, "candidates", []))
        expect(.candidates, "items[0].candidates[1].token",
               try changed(next, "candidates", [["token": "A", "logit": 0], ["token": "A", "logit": 2]]))
        expect(.logit, "items[0].candidates[1].logit",
               try changed(next, "candidates", [["token": "A", "logit": 0], ["token": "B", "logit": 1_000_001]]))
        expect(.temperature, "items[0].temperature", try changed(next, "temperature", 0))
        expect(.topK, "items[0].topK", try changed(next, "topK", 4))
        expect(.topP, "items[0].topP", try changed(next, "topP", 0))
        expect(.chosen, "items[0].chosen", try changed(next, "chosen", "missing"))
        var excluded = next
        excluded["topK"] = 1
        expect(.chosen, "items[0].chosen", try changed(excluded, "chosen", "B"))
    }

    func testProbabilitySumRefusesInvalidEngineDistributions() throws {
        let issue = MGMLIssue(reason: .sum, path: "candidates")
        for values in [[0.2, 0.3], [1.1, -0.1], [Double.nan, 0.5]] {
            let distribution = MLProbabilities.Distribution(stage: .softmax, parameter: nil, probabilities: values)
            XCTAssertThrowsError(try MLProbabilities.checkSum(distribution, issue: issue)) {
                XCTAssertEqual($0 as? MGMLIssue, issue)
            }
        }
        XCTAssertThrowsError(try MLProbabilities.normalize([0, 0], stage: .softmax, parameter: nil, issue: issue))
        let near = MLProbabilities.Distribution(stage: .softmax, parameter: nil, probabilities: [0.5, 0.5 - 5e-13])
        XCTAssertNoThrow(try MLProbabilities.checkSum(near, issue: issue))
    }

    func testAgentReviewBranchesAndBudget() throws {
        guard case .agent(let agent) = try checked(loop) else { return XCTFail("Wrong item") }
        XCTAssertEqual(agent.edges.filter { $0.to == .act }, [.init(from: .review, to: .act)])
        XCTAssertEqual(agent.edges.filter { $0.decision == "reject" }.map(\.to), [.stop, .revise])
        XCTAssertTrue(agent.edges.contains(.init(from: .revise, to: .plan)))
        XCTAssertFalse(agent.edges.contains { $0.from == .stop })
        XCTAssertEqual(agent.minimumSteps, 5)
        let bypass = loop.merging(["states": ["plan", "toolCall", "toolResult", "act", "stop"],
                                   "requiresReview": false, "stepBudget": 4]) { _, new in new }
        guard case .agent(let withoutReview) = try checked(bypass) else { return XCTFail("Wrong item") }
        XCTAssertEqual(withoutReview.minimumSteps, 4)
        XCTAssertTrue(withoutReview.edges.contains(.init(from: .toolResult, to: .act)))
    }

    func testAgentRefusals() throws {
        expect(.review, "items[0].requiresReview", try changed(loop, "requiresReview", 1))
        expect(.states, "items[0].states", try changed(loop, "states", ["plan", "plan", "stop"]))
        expect(.states, "items[0].states", try changed(loop, "states", ["plan", "review", "stop"]))
        expect(.stop, "items[0].states", try changed(loop, "states", ["plan", "toolCall", "toolResult", "review", "act"]))
        expect(.review, "items[0].states", try changed(loop, "states", ["plan", "toolCall", "toolResult", "act", "stop"]))
        expect(.budget, "items[0].stepBudget", try changed(loop, "stepBudget", 4))
        expect(.budget, "items[0].stepBudget", try changed(loop, "stepBudget", 33))
    }

    func testRenderAndDestinationChecks() throws {
        let document = try MGMLKit.check(data: data([vision, next, loop]), mlKit: true).get()
        let image = try document.frame(0, size: .portrait, transparent: true)
        let replay = try document.frame(0, size: .portrait, transparent: true)
        XCTAssertEqual(image.width, 1080)
        XCTAssertEqual(image.height, 1920)
        let pixels = try XCTUnwrap(image.dataProvider?.data) as Data
        XCTAssertEqual(pixels, try XCTUnwrap(replay.dataProvider?.data) as Data)
        XCTAssertEqual(pixels.prefix(4), Data([0, 0, 0, 0]))
        XCTAssertTrue(pixels.contains(255))
        for index in [-1, document.frameCount] {
            XCTAssertThrowsError(try document.frame(index, size: .square)) { XCTAssertEqual($0 as? MGMLReason, .frame) }
        }
        XCTAssertThrowsError(try document.export(to: URL(string: "https://example.com/output.mp4")!, size: .square)) {
            XCTAssertEqual($0 as? MGMLReason, .destination)
        }
        XCTAssertThrowsError(try document.export(to: FileManager.default.temporaryDirectory, size: .square)) {
            XCTAssertEqual($0 as? MGMLReason, .exists)
        }
    }
}
