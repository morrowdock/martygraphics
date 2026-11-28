// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import MartyGraphics

/// The golden `func` / `field` / `alt` cases (docs/fixtures/v1/graphs.cases.json) through the authoritative parser. The
/// offline mirror (tools/mg_expr.py) checks the same file in tools/tests/test_mg_expr.py, so a difference between the
/// two shows up as a failure on one side.
final class GraphCaseTests: XCTestCase {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static func cases() throws -> [String: Any] {
        let data = try Data(contentsOf: root.appendingPathComponent("docs/fixtures/v1/graphs.cases.json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testAcceptedItemsMatchTheGoldenSampling() throws {
        let accepted = try XCTUnwrap(Self.cases()["accepted"] as? [[String: Any]])
        XCTAssertGreaterThan(accepted.count, 15)
        for c in accepted {
            let name = try XCTUnwrap(c["name"] as? String)
            let object = try XCTUnwrap(c["item"] as? [String: Any])
            let scene = try MGParser.scene(object: ["v": 1, "items": [object]] as [String: Any]).get()
            let item = try XCTUnwrap(scene.items.first, name)
            if item.kind == .function {
                XCTAssertEqual(item.pts.count - 1, c["samples"] as? Int, name)
                XCTAssertEqual(item.marked, c["starts"] as? [Int], name)
                if let mark = c["mark"] as? Double { XCTAssertEqual(try XCTUnwrap(item.num["my"], name), mark, accuracy: 1e-12, name) }
                // Samples run left to right from exactly x0 (or the first value) to exactly x1 (or the last value).
                let xs = item.pts.dropFirst().map(\.x)
                XCTAssertEqual(xs, xs.sorted(), name)
            } else {
                XCTAssertEqual(item.kind, .field, name)
                XCTAssertEqual(item.n("cols"), (c["cols"] as? NSNumber)?.doubleValue, name)
                XCTAssertEqual(item.n("rows"), (c["rows"] as? NSNumber)?.doubleValue, name)
                XCTAssertEqual(item.marked, c["missing"] as? [Int], name)
                XCTAssertEqual(item.pts.count - 1, Int(item.n("cols") * item.n("rows")), name)
                if let vectors = c["vectors"] as? [[Double]] {
                    XCTAssertEqual(Array(item.pts.dropFirst()), vectors.map { MGPoint($0[0], $0[1]) }, name)
                }
            }
            // Every accepted item round-trips through its wire form (the samples are derived, never serialised).
            let ctx = MGContext(width: scene.width, height: scene.height, is3D: false, values: [:])
            XCTAssertEqual(try MGParser.item(.object(item.wire()), ctx), item, name)
            XCTAssertNil(item.wire()["pts"], name)
        }
    }

    func testRefusedScenesGiveTheGoldenReasons() throws {
        let refused = try XCTUnwrap(Self.cases()["refused"] as? [[String: Any]])
        XCTAssertGreaterThan(refused.count, 40)
        for c in refused {
            let name = try XCTUnwrap(c["name"] as? String)
            let scene = try XCTUnwrap(c["scene"], name)
            guard case .failure(let error) = MGParser.scene(object: scene) else { XCTFail("accepted: \(name)"); continue }
            XCTAssertEqual(error.reason, c["reason"] as? String, name)
        }
    }

    private static func reason(_ json: String) -> String? {
        if case .failure(let e) = MGParser.scene(data: Data(json.utf8)) { return e.reason }
        return nil
    }

    /// `func.empty` uses the rule of `curve.empty`: some piece draws a segment of nonzero length inside the ranges. A
    /// one-point piece, or a graph that only touches the window at a single point, draws nothing; a line along an edge
    /// is drawn (tools/mg_expr.py: the same).
    func testAFuncIsVisibleOnlyWhenAPieceDrawsASegment() throws {
        let one = try MGExpression.compile("sqrt(-(x^2))", allowed: [.x], reason: "func.y")
        let oneValue: (Double) -> Double = { one.value(MGExpression.Inputs().with(x: $0)) }
        let single = MGGraph.curve(oneValue, x0: -1, x1: 1, y0: -1, y1: 1, measure: false)
        XCTAssertEqual(single.samples.count, 1)
        XCTAssertFalse(single.visible)
        let touch = try MGExpression.compile("-(x^2)", allowed: [.x], reason: "func.y")
        let touchValue: (Double) -> Double = { touch.value(MGExpression.Inputs().with(x: $0)) }
        XCTAssertFalse(MGGraph.curve(touchValue, x0: -1, x1: 1, y0: 0, y1: 1, measure: false).visible)
        let line = try MGExpression.compile("x", allowed: [.x], reason: "func.y")
        let lineValue: (Double) -> Double = { line.value(MGExpression.Inputs().with(x: $0)) }
        XCTAssertTrue(MGGraph.curve(lineValue, x0: -1, x1: 1, y0: -1, y1: 1, measure: false).visible)
        let item = #"{"id":"f","k":"func","at":[1,1],"w":6,"h":4,"xr":[-1,1],"yr":[-1,1],"y":"Y"}"#
        let singleScene = #"{"v":1,"items":["# + item.replacingOccurrences(of: "Y", with: "sqrt(-(x^2))") + "]}"
        XCTAssertEqual(Self.reason(singleScene), "func.empty")
        let edgeScene = #"{"v":1,"items":["# + item.replacingOccurrences(of: "Y", with: "1") + "]}"
        XCTAssertNil(Self.reason(edgeScene))
    }

    func testDocumentationScenesEqualTheBuiltInFixtures() throws {
        for (file, id) in [("graphs.scene.json", "graphs"), ("wave.scene.json", "wave")] {
            let data = try Data(contentsOf: Self.root.appendingPathComponent("docs/fixtures/v1/" + file))
            let scene = try MGParser.scene(data: data).get()
            XCTAssertEqual(scene, MGFixtures.all.first { $0.id == id }?.scene, file)
        }
    }
}
