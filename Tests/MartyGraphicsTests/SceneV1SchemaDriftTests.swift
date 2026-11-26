// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
import MartyGraphics

final class SceneV1SchemaDriftTests: XCTestCase {
    func testDraftStructureMatchesGrammar() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("docs/schemas/scene-v1.draft.schema.json"))
        let schema = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let grammar = MGGrammar.document()
        let properties = try XCTUnwrap(schema["properties"] as? [String: [String: Any]])
        let definitions = try XCTUnwrap(schema["$defs"] as? [String: [String: Any]])

        XCTAssertEqual(properties["v"]?["const"] as? Int, grammar["version"] as? Int)
        XCTAssertEqual(Set(properties.keys), Set(try XCTUnwrap(grammar["sceneKeys"] as? [String])))
        let colors = try XCTUnwrap(definitions["color"]?["enum"] as? [String])
        XCTAssertEqual(Set(colors), Set(try XCTUnwrap(grammar["colors"] as? [String])))

        let kinds = try XCTUnwrap(grammar["kinds"] as? [[String: Any]])
        let itemBranches = try XCTUnwrap(definitions["item"]?["oneOf"] as? [[String: String]])
        let names = try kinds.map { try XCTUnwrap($0["name"] as? String) }
        XCTAssertEqual(Set(itemBranches.compactMap { $0["$ref"] }), Set(names.map { "#/$defs/\($0)" }))
        for (kind, name) in zip(kinds, names) {
            let item = try XCTUnwrap(definitions[name])
            let fields = try XCTUnwrap(item["properties"] as? [String: Any])
            let required = try XCTUnwrap(item["required"] as? [String])
            XCTAssertEqual(item["additionalProperties"] as? Bool, false, name)
            XCTAssertEqual(Set(fields.keys), Set(try XCTUnwrap(kind["allowedKeys"] as? [String])), name)
            XCTAssertEqual(Set(required), Set(try XCTUnwrap(kind["requiredKeys"] as? [String])), name)
        }
    }
}
