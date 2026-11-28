// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import MartyGraphics

/// A repeated object key is refused with one reason on every scene path: the strict parse, the stream's `finish()`
/// and the stream preview, which stops instead of showing either value (`scene.key.duplicate.<path>`).
final class RepeatedKeyTests: XCTestCase {
    private static let body = #"{"id":"a","k":"body","at":[2,2]}"#

    private func reason(_ text: String) -> String? {
        let result: Result<MGScene, MGError> = MGParser.scene(data: Data(text.utf8))
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
        let first: String = #"{"v":1,"title":"First","items":["# + Self.body + "],"
        let preview: MGScene? = parser.feed(first)
        XCTAssertEqual(preview?.title, "First")
        let after: MGScene? = parser.feed(#""title":"Second"}"#)
        XCTAssertNil(after, "no preview shows the second title")
        XCTAssertEqual(parser.previewRefusal?.reason, "scene.key.duplicate.title")
        let finish: Result<MGScene, MGError> = parser.finish()
        guard case .failure(let error) = finish else { return XCTFail("finish accepted a repeated key") }
        XCTAssertEqual(error.reason, parser.previewRefusal?.reason)
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
        let finish: Result<MGScene, MGError> = parser.finish()
        guard case .failure(let error) = finish else { return XCTFail("finish accepted a repeated key") }
        XCTAssertEqual(error.reason, "scene.key.duplicate.title")
    }

    func testARepeatedKeyInsideAnItemNeverPreviewsTheItem() {
        let text: String = #"{"v":1,"items":[{"id":"a","k":"body","at":[2,2],"at":[5,5]}]}"#
        var previews = 0
        var parser = MGStreamParser()
        for character in text {
            if parser.feed(String(character)) != nil { previews += 1 }
        }
        XCTAssertEqual(previews, 0)
        XCTAssertEqual(parser.previewRefusal?.reason, "scene.key.duplicate.items.0.at")
        let finish: Result<MGScene, MGError> = parser.finish()
        guard case .failure(let error) = finish else { return XCTFail("finish accepted a repeated key") }
        XCTAssertEqual(error.reason, "scene.key.duplicate.items.0.at")
    }

    func testEveryBuiltInFixtureStillStreamsAndParses() throws {
        for fixture in MGFixtures.all {
            let strict: MGScene = try MGParser.scene(data: Data(fixture.json.utf8)).get()
            var parser = MGStreamParser()
            _ = parser.feed(fixture.json)
            XCTAssertNil(parser.previewRefusal, fixture.id)
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
