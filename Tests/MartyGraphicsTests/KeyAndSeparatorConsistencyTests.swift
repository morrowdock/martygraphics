// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import MartyGraphics

/// A repeated object key is refused with one reason on every scene `Data` path, the stream's `finish()` included. The
/// stream preview stops from the chunk that closes the repeated key, so it never shows either value
/// (`scene.key.duplicate.<path>`). The scan keeps its state across chunks and reads each byte once.
final class RepeatedKeyTests: XCTestCase {
    private static let body = #"{"id":"a","k":"body","at":[2,2]}"#
    /// A scene up to the point where a second `title` key may follow; it previews with the title "First".
    private static let head: String = #"{"v":1,"title":"First","items":["# + RepeatedKeyTests.body + "],"

    private func reason(_ text: String) -> String? {
        let result: Result<MGScene, MGError> = MGParser.scene(data: Data(text.utf8))
        guard case .failure(let error) = result else { return nil }
        return error.reason
    }

    private func finishReason(_ parser: MGStreamParser) -> String? {
        let result: Result<MGScene, MGError> = parser.finish()
        guard case .failure(let error) = result else { return nil }
        return error.reason
    }

    func testARepeatedTopLevelKeyIsRefusedWithItsName() {
        let text: String = #"{"v":1,"title":"First","title":"Second","items":["# + Self.body + "]}"
        XCTAssertEqual(reason(text), "scene.key.duplicate.title")
    }

    func testThePathNamesEveryObjectKeyAndArrayIndex() {
        let second: String = #"{"id":"b","k":"body","at":[3,3],"at":[4,4]}"#
        let items: String = #"{"v":1,"items":["# + Self.body + "," + second + "]}"
        XCTAssertEqual(reason(items), "scene.key.duplicate.items.1.at")
        let world: String = #"{"v":1,"world":{"w":12,"h":8,"w":10},"items":["# + Self.body + "]}"
        XCTAssertEqual(reason(world), "scene.key.duplicate.world.w")
        let step: String = #"{"v":1,"items":["# + Self.body + #"],"steps":[{"say":"One."},{"say":"Two.","say":"Three."}]}"#
        XCTAssertEqual(reason(step), "scene.key.duplicate.steps.1.say")
    }

    func testTheSameKeyInSeparateObjectsIsAccepted() throws {
        let second: String = #"{"id":"b","k":"body","at":[5,5]}"#
        let text: String = #"{"v":1,"title":"Two bodies","items":["# + Self.body + "," + second + "]}"
        let scene: MGScene = try MGParser.scene(data: Data(text.utf8)).get()
        XCTAssertEqual(scene.items.map(\.id), ["a", "b"])
    }

    func testKeysCompareAfterEscapesAreDecoded() {
        // "\u0074itle" is the key "title" spelled with an escape.
        let escaped: String = #"{"v":1,"title":"First","\u0074itle":"Second","items":["# + Self.body + "]}"
        XCTAssertEqual(reason(escaped), "scene.key.duplicate.title")
    }

    func testAKeyIsOneReasonSegment() {
        // A dot in an author key cannot add a segment to the reason.
        let path: String? = MGJSON.duplicateKeyPath(Array(#"{"x.y":1,"x.y":2}"#.utf8))
        XCTAssertEqual(path, "x_y")
        let none: String? = MGJSON.duplicateKeyPath(Array(#"{"a":{"a":1},"b":[{"a":1},{"a":2}]}"#.utf8))
        XCTAssertNil(none)
    }

    func testEverySceneDataEntryPointGivesTheSameReason() {
        let text: String = #"{"v":1,"title":"First","title":"Second","items":["# + Self.body + "]}"
        let data = Data(text.utf8)
        let want = "scene.key.duplicate.title"
        let plain: Result<MGScene, MGError> = MGParser.scene(data: data)
        let extras: Result<MGScene, MGError> = MGParser.scene(data: data, extraTemplates: [])
        let video: Result<MGScene, MGError> = MGParser.scene(data: data, programmaticVideo: true)
        let noVideo: Result<MGScene, MGError> = MGParser.scene(data: data, programmaticVideo: false)
        for result in [plain, extras, video, noVideo] {
            guard case .failure(let error) = result else { XCTFail("accepted a repeated key"); continue }
            XCTAssertEqual(error.reason, want)
        }
    }

    func testTheStreamStopsPreviewingAtARepeatedKey() {
        var parser = MGStreamParser()
        let preview: MGScene? = parser.feed(Self.head)
        XCTAssertEqual(preview?.title, "First")
        let after: MGScene? = parser.feed(#""title":"Second"}"#)
        XCTAssertNil(after, "no preview shows the second title")
        XCTAssertEqual(parser.repeatedKeyPath, "title")
        XCTAssertEqual(finishReason(parser), "scene.key.duplicate.title")
    }

    func testTheChunkThatClosesARepeatedKeyStopsThePreviewsBeforeItsValueArrives() {
        var parser = MGStreamParser()
        let preview: MGScene? = parser.feed(Self.head)
        XCTAssertEqual(preview?.title, "First")
        // The key alone completes no member, so the preview's shape does not change; the scan still reads the key.
        let key: MGScene? = parser.feed(#""title""#)
        XCTAssertNil(key)
        XCTAssertEqual(parser.repeatedKeyPath, "title", "the key's closing quote stops the previews")
        let value: MGScene? = parser.feed(#":"Second"}"#)
        XCTAssertNil(value, "no preview shows the second title")
        XCTAssertEqual(finishReason(parser), "scene.key.duplicate.title")
    }

    func testAKeySplitAcrossChunksCountsWhenItsClosingQuoteArrives() {
        // The second key as written, and spelled with an escape ("\u0074itle" is "title"): every cut, the escape's
        // backslash and its hex digits included, leaves the key open until the chunk with its closing quote.
        let spellings: [String] = [#""title""#, #""\u0074itle""#]
        for spelling in spellings {
            let characters: [Character] = Array(spelling)
            for cut in 1..<characters.count {
                let left = String(characters[..<cut])
                let right = String(characters[cut...])
                var parser = MGStreamParser()
                _ = parser.feed(Self.head)
                let open: MGScene? = parser.feed(left)
                XCTAssertNil(open, left)
                XCTAssertNil(parser.repeatedKeyPath, left + " is not a closed key yet")
                let closed: MGScene? = parser.feed(right)
                XCTAssertNil(closed, right)
                XCTAssertEqual(parser.repeatedKeyPath, "title", left + " | " + right)
                _ = parser.feed(#":"Second"}"#)
                XCTAssertEqual(finishReason(parser), "scene.key.duplicate.title", left + " | " + right)
            }
        }
    }

    func testNoChunkingPreviewsASecondValue() {
        let text: String = #"{"v":1,"title":"First","items":["# + Self.body + #"],"title":"Second"}"#
        var titles: [String] = []
        var parser = MGStreamParser()
        for character in text {
            var chunk = ""
            chunk.append(character)
            guard let preview = parser.feed(chunk) else { continue }
            let title: String? = preview.title
            titles.append(title ?? "(none)")
        }
        XCTAssertFalse(titles.isEmpty)
        XCTAssertFalse(titles.contains("Second"))
        XCTAssertEqual(finishReason(parser), "scene.key.duplicate.title")
    }

    func testARepeatedKeyInsideAnItemNeverPreviewsTheItem() {
        let text: String = #"{"v":1,"items":[{"id":"a","k":"body","at":[2,2],"at":[5,5]}]}"#
        var previews = 0
        var parser = MGStreamParser()
        for character in text {
            var chunk = ""
            chunk.append(character)
            if parser.feed(chunk) != nil { previews += 1 }
        }
        XCTAssertEqual(previews, 0)
        XCTAssertEqual(parser.repeatedKeyPath, "items.0.at")
        XCTAssertEqual(finishReason(parser), "scene.key.duplicate.items.0.at")
    }

    func testFinishGivesTheStrictReasonInTheParseOrder() {
        // UTF-8, depth, repeated key, then the system parser, whatever stopped the previews.
        let repeated: String = #"{"v":1,"title":"First","title":"Second","items":["# + Self.body + "]"
        let levels: Int = MGLimits.depth + 1
        let deep: String = String(repeating: "[", count: levels) + String(repeating: "]", count: levels)
        let cases: [(rest: String, want: String)] = [
            ("}", "scene.key.duplicate.title"),
            // Too deep as well: the depth check comes first.
            (#","camera":"# + deep + "}", "scene.depth"),
            // Never closed, so not JSON as well: the repeated key comes before the system parser.
            ("", "scene.key.duplicate.title"),
        ]
        for (rest, want) in cases {
            var parser = MGStreamParser()
            let first: MGScene? = parser.feed(repeated)
            XCTAssertNil(first, want)
            XCTAssertEqual(parser.repeatedKeyPath, "title", want)
            if !rest.isEmpty {
                let second: MGScene? = parser.feed(rest)
                XCTAssertNil(second, want)
            }
            let text: String = repeated + rest
            XCTAssertEqual(finishReason(parser), want)
            XCTAssertEqual(reason(text), want)
        }
        // Bytes that are not UTF-8 give `json` first, even with a repeated key (a stream's text is always UTF-8).
        let open: [UInt8] = Array(#"{"v":1,"title":""#.utf8)
        let close: [UInt8] = Array(#"","title":"B"}"#.utf8)
        let bytes: [UInt8] = open + [0xFF] + close
        let notUTF8: Result<MGScene, MGError> = MGParser.scene(data: Data(bytes))
        guard case .failure(let error) = notUTF8 else { return XCTFail("accepted bytes that are not UTF-8") }
        XCTAssertEqual(error.reason, "json")
    }

    func testTheScanReadsEachByteOnceHoweverTheTextIsSplit() {
        let second: String = #"{"id":"b","k":"body","at":[3,3],"at":[4,4]}"#
        let plain: String = #"{"v":1,"title":"Two bodies","items":["# + Self.body + "]}"
        let repeated: String = #"{"v":1,"items":["# + Self.body + "," + second + "]}"
        let escaped: String = #"{"v":1,"title":"First","\u0074itle":"Second"}"#
        for text in [plain, repeated, escaped] {
            let bytes: [UInt8] = Array(text.utf8)
            var whole = MGKeyScanner()
            let wholeSteps: Int = whole.consume(bytes)
            for size in 1...8 {
                var pieces = MGKeyScanner()
                var steps = 0
                var start = 0
                while start < bytes.count {
                    let end: Int = min(start + size, bytes.count)
                    steps += pieces.consume(bytes[start..<end])
                    start = end
                }
                XCTAssertEqual(pieces.path, whole.path, text)
                XCTAssertEqual(steps, wholeSteps, text)
            }
        }
        // One step per byte: all of the text when no key repeats, up to the repeated key's closing quote otherwise.
        var once = MGKeyScanner()
        let plainSteps: Int = once.consume(Array(plain.utf8))
        XCTAssertNil(once.path)
        XCTAssertEqual(plainSteps, plain.utf8.count)
        let upToKey: String = #"{"v":1,"items":["# + Self.body + #",{"id":"b","k":"body","at":[3,3],"at""#
        var stops = MGKeyScanner()
        let repeatedSteps: Int = stops.consume(Array(repeated.utf8))
        XCTAssertEqual(stops.path, "items.1.at")
        XCTAssertEqual(repeatedSteps, upToKey.utf8.count)
        // Nothing is read after the repeated key.
        let after: Int = stops.consume(Array(plain.utf8))
        XCTAssertEqual(after, 0)
    }

    func testTheStreamScansEachByteOnce() {
        // However a scene is chunked, the scan reads each byte once: as many steps as one feed of the whole text.
        for fixture in MGFixtures.all {
            let total: Int = fixture.json.utf8.count
            var whole = MGStreamParser()
            _ = whole.feed(fixture.json)
            XCTAssertEqual(whole.keyScanSteps, total, fixture.id)
            let characters: [Character] = Array(fixture.json)
            for size in [7, 64] {
                var parser = MGStreamParser()
                var start = 0
                while start < characters.count {
                    let end: Int = min(start + size, characters.count)
                    _ = parser.feed(String(characters[start..<end]))
                    start = end
                }
                XCTAssertEqual(parser.keyScanSteps, total, fixture.id)
                XCTAssertNil(parser.repeatedKeyPath, fixture.id)
            }
        }
    }

    func testEveryBuiltInFixtureStillStreamsAndParses() throws {
        for fixture in MGFixtures.all {
            let strict: MGScene = try MGParser.scene(data: Data(fixture.json.utf8)).get()
            var parser = MGStreamParser()
            _ = parser.feed(fixture.json)
            XCTAssertNil(parser.repeatedKeyPath, fixture.id)
            let streamed: MGScene = try parser.finish().get()
            XCTAssertEqual(streamed, strict, fixture.id)
        }
    }

    func testTheRefusalHasARepairHint() {
        let hint: String? = MGRepairHint.text(for: "scene.key.duplicate.items.0.at")
        XCTAssertNotNil(hint)
        XCTAssertTrue(hint?.hasPrefix("each key may appear once per object") ?? false)
    }
}

/// Plain text follows one rule on the 2D board and in Solid 3D: control characters (Cc, Cf) and the line and paragraph
/// separators U+2028 and U+2029 are refused with the field's own reason.
final class TextSeparatorTests: XCTestCase {
    private static func character(_ value: UInt32) -> String {
        guard let scalar = Unicode.Scalar(value) else { return "" }
        return String(Character(scalar))
    }

    /// U+2028 and U+2029 (Zl, Zp), U+007F (Cc; JSON strings may hold it raw) and U+200E (Cf).
    private static let refused: [UInt32] = [0x2028, 0x2029, 0x7F, 0x200E]

    private func boardReason(title: String) -> String? {
        let text: String = #"{"v":1,"title":""# + title + #"","items":[{"id":"a","k":"body","at":[2,2]}]}"#
        let result: Result<MGScene, MGError> = MGParser.scene(data: Data(text.utf8))
        guard case .failure(let error) = result else { return nil }
        return error.reason
    }

    private func solidReason(title: String = "Box", name: String = "Box", say: String = "Box.") -> String? {
        let part: String = #"{"id": "a", "name": ""# + name + #"", "shape": {"box": {"size": [10, 10, 10]}}}"#
        let steps: String = #"[{"say": ""# + say + #""}]"#
        let text: String = #"{"v": 2, "kind": "assembly", "title": ""# + title + #"", "parts": ["# + part + #"], "steps": "# + steps + "}"
        let result: Result<MGSolidDocument, MGSolidIssue> = MGSolidParser.document(data: Data(text.utf8))
        guard case .failure(let issue) = result else { return nil }
        return issue.reason
    }

    func testOrdinaryTextIsAcceptedOnBoth() {
        XCTAssertNil(boardReason(title: "A title"))
        XCTAssertNil(solidReason(title: "A title", name: "A box", say: "A box."))
    }

    func testBoardTextRefusesSeparatorsAndControls() {
        for value in Self.refused {
            let title: String = "A" + Self.character(value) + "B"
            XCTAssertEqual(boardReason(title: title), "title", String(value, radix: 16))
        }
    }

    func testSolidTextRefusesSeparatorsAndControlsWithTheFieldReason() {
        for value in Self.refused {
            let mark: String = Self.character(value)
            let label = String(value, radix: 16)
            XCTAssertEqual(solidReason(title: "A" + mark + "B"), "assembly.title", label)
            XCTAssertEqual(solidReason(name: "A" + mark + "B"), "part.name", label)
            XCTAssertEqual(solidReason(say: "A" + mark + "B."), "step.say", label)
        }
    }

    func testASeparatorAtTheEndIsRefusedToo() {
        // Trimming would remove a trailing separator; the rule reads the authored text.
        let mark: String = Self.character(0x2028)
        XCTAssertEqual(boardReason(title: "AB" + mark), "title")
        XCTAssertEqual(solidReason(title: "AB" + mark), "assembly.title")
    }

    func testTheSolidRuleMatchesTheBoardRuleScalarByScalar() {
        let values: [UInt32] = Self.refused + [0x41, 0x20, 0xE9, 0x2192, 0x2264]
        for value in values {
            guard let scalar = Unicode.Scalar(value) else { continue }
            let solid: Bool = MGSolidParser.isRefusedScalar(scalar)
            let board: Bool = boardReason(title: "A" + Self.character(value) + "B") != nil
            XCTAssertEqual(solid, board, String(value, radix: 16))
        }
    }
}
