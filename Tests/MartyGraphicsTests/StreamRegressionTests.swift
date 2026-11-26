// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import MartyGraphics

/// Streaming invariants: `finish()` equals the strict parse for every chunking, previews only ever show validated
/// items that resolve, previews grow monotonically, and truncated, prefixed or oversized text never yields a scene.
final class StreamRegressionTests: XCTestCase {
    private typealias R = MGRegression

    private func run(_ chunks: [String]) -> (previews: [MGScene], parser: MGStreamParser) {
        var parser = MGStreamParser()
        var previews: [MGScene] = []
        for chunk in chunks { if let preview = parser.feed(chunk) { previews.append(preview) } }
        return (previews, parser)
    }

    func testEveryDeterministicChunkingMatchesTheStrictParse() throws {
        let sources = MGFixtures.all.map(\.json) + [R.allKinds, R.allKinds3D, R.edgeFirst, R.twoPointers, R.timeline, R.tricky]
        for json in sources {
            let strict = try R.scene(json)
            let byID = Dictionary(uniqueKeysWithValues: strict.items.map { ($0.id, $0) })
            for seed in UInt64(1)...8 {
                let result = run(R.chunks(json, seed: seed))
                XCTAssertEqual(result.parser.text, json)
                XCTAssertEqual(try result.parser.finish().get(), strict, "seed \(seed)")
                XCTAssertFalse(result.previews.isEmpty, "seed \(seed)")
                var previous = Set<String>()
                for preview in result.previews {
                    let ids = Set(preview.items.map(\.id))
                    XCTAssertTrue(previous.isSubset(of: ids), "previews only grow (seed \(seed))")
                    previous = ids
                    // A previewed item is exactly the item the strict parse produces.
                    for item in preview.items { XCTAssertEqual(item, byID[item.id], "\(item.id) seed \(seed)") }
                }
            }
        }
    }

    func testItemsWaitForTheirReferencesBeforePreviewing() throws {
        var parser = MGStreamParser()
        var idSets: [Set<String>] = []
        for character in R.edgeFirst {
            if let preview = parser.feed(String(character)) { idSets.append(Set(preview.items.map(\.id))) }
        }
        XCTAssertEqual(idSets.first, ["na"])                     // the edge waits for both nodes
        XCTAssertEqual(idSets.last, ["ab", "na", "nb"])
        for ids in idSets where ids.contains("ab") { XCTAssertTrue(ids.isSuperset(of: ["na", "nb"])) }
        XCTAssertEqual(try parser.finish().get(), try R.scene(R.edgeFirst))
    }

    func testStepsJoinOnlyOnceComplete() throws {
        var parser = MGStreamParser()
        var stepCounts: [Int] = []
        for character in R.timeline {
            if let preview = parser.feed(String(character)) { stepCounts.append(preview.steps.count) }
        }
        XCTAssertTrue(stepCounts.contains(0))
        XCTAssertEqual(stepCounts.last, 3)
        XCTAssertTrue(stepCounts.allSatisfy { $0 == 0 || $0 == 3 })
    }

    func testTemplatePreviewWaitsForClosedParams() throws {
        let json = R.twoPointers
        let paramsEnd = try XCTUnwrap(json.firstIndex(of: "}"))
        let expected = json.distance(from: json.startIndex, to: paramsEnd) + 1
        var parser = MGStreamParser()
        var first: Int?
        for (offset, character) in json.enumerated() {
            if parser.feed(String(character)) != nil, first == nil { first = offset + 1 }
        }
        XCTAssertEqual(first, expected)
        XCTAssertEqual(try parser.finish().get(), try R.scene(json))
    }

    func testEscapedQuotesAndStructuralCharactersInsideStrings() throws {
        let members = MGStreamParser.members(Array(R.tricky.utf8))
        XCTAssertEqual(members.map(\.key), ["v", "title", "items"])
        XCTAssertTrue(members.allSatisfy(\.complete))
        var parser = MGStreamParser()
        var last: MGScene?
        for character in R.tricky { if let preview = parser.feed(String(character)) { last = preview } }
        XCTAssertEqual(last?.title, "Say \"hi\", [ok] : yes")
        XCTAssertEqual(last?.item("t")?.text, "a,b]c\"d")
    }

    func testTruncatedPrefixedAndOversizedTextNeverYieldsAScene() {
        // Every strict prefix of a valid scene fails the final parse.
        let json = R.edgeFirst
        for length in stride(from: 0, to: json.count, by: 7) {
            var parser = MGStreamParser()
            _ = parser.feed(String(json.prefix(length)))
            XCTAssertThrowsError(try parser.finish().get(), "prefix \(length)")
        }
        var prefixed = MGStreamParser()
        XCTAssertNil(prefixed.feed("xyz" + json))
        XCTAssertNil(prefixed.feed(" "))
        XCTAssertEqual(R.reason(prefixed.finish()), "json")

        var oversized = MGStreamParser()
        XCTAssertNotNil(oversized.feed(#"{"v":1,"items":[{"id":"dot","k":"body","at":[3,4]}],"title":""#))
        XCTAssertNil(oversized.feed(String(repeating: "x", count: MGLimits.sceneBytes * 2)))
        XCTAssertNil(oversized.feed(#""}"#))
        XCTAssertEqual(R.reason(oversized.finish()), "json")

        var invalid = MGStreamParser()
        XCTAssertNil(invalid.feed(#"{"v":1,"items":[{"id":"dot","k":"rocket"}]}"#))
        XCTAssertEqual(R.reason(invalid.finish()), "item.kind")
    }

    func testTolerantScannerReportsCompletenessOnly() {
        func text(_ bytes: [UInt8]) -> String { String(decoding: bytes, as: UTF8.self) }
        let open = MGStreamParser.members(Array(#"{"a":1,"b":[1,2"#.utf8))
        XCTAssertEqual(open.map(\.key), ["a", "b"])
        XCTAssertEqual(open.map(\.complete), [true, false])
        XCTAssertEqual(open.map { text($0.raw) }, ["1", "[1,2"])
        // A bare number stays open until a delimiter follows it.
        XCTAssertEqual(MGStreamParser.members(Array(#"{"a":1"#.utf8)).map(\.complete), [false])
        XCTAssertTrue(MGStreamParser.members(Array("[1]".utf8)).isEmpty)
        XCTAssertTrue(MGStreamParser.members(Array("   {".utf8)).isEmpty)
        XCTAssertTrue(MGStreamParser.members([]).isEmpty)
        let elements = MGStreamParser.elements(Array(#"[{"a":[1]},"x\"]",3,4"#.utf8)).map(text)
        XCTAssertEqual(elements, [#"{"a":[1]}"#, #""x\"]""#, "3"])
        XCTAssertTrue(MGStreamParser.elements(Array("{}".utf8)).isEmpty)
        XCTAssertNil(MGStreamParser.valueEnd(Array(#""abc\"#.utf8), 0))
        XCTAssertEqual(MGStreamParser.valueEnd(Array(#""a\"b","#.utf8), 0), 6)
    }

    func testScannerReturnsCompleteNonemptyValuesInOrder() throws {
        let tokens = ["0", "false", "\"\"", #"{"a":1}"#, "null"]
        let bytes = Array(("[" + tokens.joined(separator: ",") + "]").utf8)
        var cursor = 1
        for token in tokens {
            let end = try XCTUnwrap(MGStreamParser.valueEnd(bytes, cursor))
            XCTAssertGreaterThan(end, cursor)
            XCTAssertEqual(String(decoding: bytes[cursor..<end], as: UTF8.self), token)
            cursor = end + 1
        }
        XCTAssertEqual(cursor, bytes.count)
        XCTAssertEqual(MGStreamParser.elements(bytes).map { String(decoding: $0, as: UTF8.self) }, tokens)
        XCTAssertEqual(MGStreamParser.elements(bytes, limit: 2).map { String(decoding: $0, as: UTF8.self) },
                       Array(tokens.prefix(2)))
    }

    func testTextBudgetAcceptsExactLimitAndRefusesFurtherInput() throws {
        let json = R.edgeFirst
        let padded = json + String(repeating: " ", count: MGLimits.sceneBytes * 2 - json.utf8.count)
        var parser = MGStreamParser()
        XCTAssertNotNil(parser.feed(padded))
        XCTAssertEqual(try parser.finish().get(), try R.scene(json))
        XCTAssertNil(parser.feed(" "))
        XCTAssertEqual(parser.text, padded)
        XCTAssertNil(parser.feed(" "))
        XCTAssertEqual(parser.text, padded)
        XCTAssertEqual(R.reason(parser.finish()), "json")
    }

    func testPreviewItemBudgetAtBoundary() throws {
        let items = (1...MGLimits.items + 1).map { id in
            #"{"id":"dot\#(id)","k":"body","at":[3,4]}"#
        }
        func scene(_ items: ArraySlice<String>) -> String {
            #"{"v":1,"items":["# + items.joined(separator: ",") + "]}"
        }
        var atLimit = MGStreamParser()
        XCTAssertEqual(atLimit.feed(scene(items.prefix(MGLimits.items)))?.items.count, MGLimits.items)
        XCTAssertEqual(try atLimit.finish().get().items.count, MGLimits.items)

        var beyondLimit = MGStreamParser()
        XCTAssertNil(beyondLimit.feed(scene(items[...])))
        XCTAssertEqual(beyondLimit.candidateValidationCount, 0)
        XCTAssertEqual(R.reason(beyondLimit.finish()), "items.count")
    }

    func testWhitespaceFeedsDoNotRetryWaitingCandidates() throws {
        var parser = MGStreamParser()
        XCTAssertNil(parser.feed(#"{"v":1,"items":[{"id":"ab","k":"edge","a":"na","b":"nb"},"#))
        let attempts = parser.candidateValidationCount
        XCTAssertEqual(attempts, 1)
        for _ in 0..<32 { XCTAssertNil(parser.feed(" ")) }
        XCTAssertEqual(parser.candidateValidationCount, attempts)

        let preview = try XCTUnwrap(parser.feed(#"{"id":"na","k":"node","at":[2,3],"text":"A"},{"id":"nb","k":"node","at":[4,3],"text":"B"}]}"#))
        XCTAssertEqual(Set(preview.items.map(\.id)), ["ab", "na", "nb"])
        XCTAssertLessThanOrEqual(parser.candidateValidationCount, 5)
        XCTAssertEqual(try parser.finish().get().items.count, 3)
    }
}
