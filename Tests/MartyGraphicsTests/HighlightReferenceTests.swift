// SPDX-License-Identifier: Apache-2.0
import XCTest
import CoreGraphics
@testable import MartyGraphics

final class HighlightReferenceTests: XCTestCase {
    private let viewport = MGViewport(size: CGSize(width: 600, height: 400), width: 12, height: 8, camera: nil)

    private func highlight(_ id: String, target: String) -> MGItem {
        var item = MGItem(id: id, kind: .highlight, color: .yellow)
        item.ref = target
        return item
    }

    private func parse(_ items: [MGItem], steps: [[String: Any]] = []) throws -> MGScene {
        var object: [String: Any] = ["v": 1, "items": items.map { MGJSON.object($0.wire()).any }]
        if !steps.isEmpty { object["steps"] = steps }
        return try MGParser.scene(object: object).get()
    }

    func testSelfTargetAndDirectCycleRejectSafely() {
        for items in [
            [highlight("self", target: "self")],
            [highlight("a", target: "b"), highlight("b", target: "a")]
        ] {
            XCTAssertThrowsError(try parse(items))
            for item in items { XCTAssertNil(MGLayout.bounds(item, in: items, viewport)) }
        }
    }

    func testIndirectCycleRejectsSafely() {
        let items = [highlight("a", target: "b"), highlight("b", target: "c"), highlight("c", target: "a")]
        XCTAssertThrowsError(try parse(items)) { error in
            XCTAssertEqual((error as? MGError)?.reason, "highlight.cycle")
        }
        for item in items { XCTAssertNil(MGLayout.bounds(item, in: items, viewport)) }
    }

    func testLongAcyclicChainParsesAndUsesTerminalBounds() throws {
        let body = MGMake.body("dot", MGPoint(6, 4), size: 1)
        let chain = (0..<23).map { highlight("h\($0)", target: $0 == 22 ? "dot" : "h\($0 + 1)") }
        let scene = try parse(chain + [body])
        let first = try XCTUnwrap(scene.item("h0"))
        let terminal = try XCTUnwrap(scene.item("dot"))
        XCTAssertEqual(MGLayout.bounds(first, in: scene.items, viewport), MGLayout.bounds(terminal, in: scene.items, viewport))
    }

    func testDeepPublicAPIChainAndCycleDoNotRecurse() {
        let body = MGMake.body("dot", MGPoint(6, 4), size: 1)
        let chain = (0..<512).map { highlight("h\($0)", target: $0 == 511 ? "dot" : "h\($0 + 1)") }
        let items = chain + [body]
        XCTAssertEqual(MGLayout.bounds(chain[0], in: items, viewport), MGLayout.bounds(body, in: items, viewport))
        var cyclic = chain
        cyclic[511].ref = "h0"
        XCTAssertNil(MGLayout.bounds(cyclic[0], in: cyclic, viewport))
    }

    func testCumulativeStepEditsCannotIntroduceCycleOrSelfTarget() throws {
        let items = [MGMake.body("dot", MGPoint(6, 4)), highlight("a", target: "dot"), highlight("b", target: "dot")]
        let first: [String: Any] = ["say": "Connect one marker.", "do": [["id": "a", "key": "target", "value": "b"]]]
        XCTAssertNoThrow(try parse(items, steps: [first]))
        let cycle: [String: Any] = ["say": "Connect the second marker.", "do": [["id": "b", "key": "target", "value": "a"]]]
        XCTAssertThrowsError(try parse(items, steps: [first, cycle]))
        let selfTarget: [String: Any] = ["say": "Redirect a marker.", "do": [["id": "a", "key": "target", "value": "a"]]]
        XCTAssertThrowsError(try parse(items, steps: [selfTarget]))
        let missing: [String: Any] = ["say": "Redirect a marker.", "do": [["id": "a", "key": "target", "value": "missing"]]]
        XCTAssertThrowsError(try parse(items, steps: [missing]))
    }

    func testInvalidReferencePatchKeepsOriginalScene() throws {
        let items = [MGMake.body("dot", MGPoint(6, 4)), highlight("a", target: "dot"), highlight("b", target: "a")]
        let scene = try parse(items)
        let patch = try MGPatch.parse(object: ["v": 1, "rev": 0, "ops": [["op": "set", "id": "a", "key": "target", "value": "b"]]]).get()
        XCTAssertThrowsError(try scene.applying(patch).get())
        XCTAssertEqual(scene.item("a")?.ref, "dot")
        XCTAssertEqual(scene.revision, 0)
    }
}
