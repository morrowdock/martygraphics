// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import MartyGraphics

/// Repair hints are suggestions keyed by the parser's reason tokens; they never change a reason.
final class MGRepairHintTests: XCTestCase {
    /// Refused synthetic scenes, one per common authoring mistake. Each reason must come with a hint.
    static let refused: [(String, String)] = [
        (#"{"items":[]}"#, "scene.missing"),
        (#"{"v":1,"items":[{"id":"a","k":"body"}]}"#, "item.body.missing"),
        (#"{"v":1,"items":[{"id":"a","k":"body","at":[1,1],"radius":2}]}"#, "item.body.unknown.radius"),
        (#"{"v":1,"items":[{"id":"a","k":"text","at":[1,1],"text":"x < 4"}]}"#, "text.text"),
        (#"{"v":1,"items":[{"id":"a","k":"text","at":[1,1],"text":"{n} apples"}]}"#, "text.text.placeholder.n"),
        (#"{"v":1,"items":[{"id":"a","k":"vector","from":[1,1],"on":"a","angle":0,"len":1}]}"#, "vector.anchor"),
        (#"{"v":1,"items":[{"id":"a","k":"vector","from":[1,1],"dir":[1,0,0],"len":1}]}"#, "vector.dir"),
        (#"{"v":1,"items":[{"id":"a","k":"incline","at":[1,1],"base":4,"angle":85}]}"#, "incline.angle"),
        (#"{"v":1,"items":[{"id":"a","k":"array","at":[6,4],"vals":[1,2],"ptrs":[{"i":1,"label":"top"}]}],"steps":[{"say":"Pop.","do":[{"id":"a","key":"vals","value":[1]}]}]}"#, "array.ptr.i"),
        (#"{"v":1,"items":[{"id":"a","k":"body","at":[1,1]}],"steps":[{"say":"x","do":[{"id":"a","key":"radius","value":1}]}]}"#, "edit.key.radius"),
        (#"{"v":1,"items":[{"id":"a","k":"body","at":[1,1]}],"steps":[{"say":"a > b"}]}"#, "step.say"),
        (#"{"v":1,"template":"two_pointers","params":{"vals":[3,1,2],"target":4}}"#, "template.check"),
    ]

    func testEveryCommonMistakeGetsAHint() throws {
        for (json, expected) in Self.refused {
            guard case .failure(let error) = MGParser.scene(data: Data(json.utf8)) else { return XCTFail("accepted \(json)") }
            XCTAssertEqual(error.reason, expected, json)
            XCTAssertNotNil(MGRepairHint.text(for: error.reason), error.reason)
        }
    }

    func testComputedAndPatternHints() {
        XCTAssertEqual(MGRepairHint.text(for: "item.body.missing"), "a body needs at, id, k")
        XCTAssertEqual(MGRepairHint.text(for: "item.edge.unknown.c"),
                       "remove unknown keys; a edge allows a, b, color, dir, id, k, label")
        XCTAssertEqual(MGRepairHint.text(for: "id.duplicate.dot"), "item ids must be unique; rename one of the two")
        XCTAssertEqual(MGRepairHint.text(for: "body.at"), MGRepairHint.text(for: "line.to"))
        XCTAssertNil(MGRepairHint.text(for: "not.a.reason"))
        XCTAssertTrue(MGRepairHint.matches("item.*.unknown.*", "item.body.unknown.a,b"))
        XCTAssertFalse(MGRepairHint.matches("*.at", "body.atx"))
        XCTAssertFalse(MGRepairHint.matches("items", "items.count"))
    }
}
