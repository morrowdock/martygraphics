// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import MartyGraphics

/// The golden `curve` cases (docs/fixtures/v1/curves.cases.json) through the authoritative parser. The offline mirror
/// (tools/mg_expr.py) checks the same file in tools/tests/test_mg_expr.py, so a difference between the two shows up as
/// a failure on one side. The listed points come from closed forms, not from either sampler.
final class CurveCaseTests: XCTestCase {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static func cases() throws -> [String: Any] {
        let data = try Data(contentsOf: root.appendingPathComponent("docs/fixtures/v1/curves.cases.json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    static func numbers(_ value: Any?) -> [Double]? { (value as? [NSNumber])?.map(\.doubleValue) }

    /// Equal to 1e-12 relative: some JSON parsers read a 17-digit number such as 1.4000000000000001 one ulp off.
    static func close(_ actual: [Double], _ expected: [Double]?, _ name: String, file: StaticString = #filePath, line: UInt = #line) {
        guard let expected, expected.count == actual.count else {
            let message: String = "\(name): \(actual) vs \(String(describing: expected))"
            return XCTFail(message, file: file, line: line)
        }
        for (a, e) in zip(actual, expected) {
            let tolerance: Double = 1e-12 * Swift.max(1, abs(e))
            XCTAssertEqual(a, e, accuracy: tolerance, name, file: file, line: line)
        }
    }

    func testAcceptedCurvesMatchTheGoldenSampling() throws {
        let accepted = try XCTUnwrap(Self.cases()["accepted"] as? [[String: Any]])
        XCTAssertGreaterThan(accepted.count, 15)
        for c in accepted {
            let name = try XCTUnwrap(c["name"] as? String)
            let object = try XCTUnwrap(c["item"] as? [String: Any])
            let scene = try MGParser.scene(object: ["v": 1, "items": [object]] as [String: Any]).get()
            let item = try XCTUnwrap(scene.items.first, name)
            XCTAssertEqual(item.kind, .curve, name)
            let samples: Int = item.pts.count - 1
            let golden: Int? = c["samples"] as? Int
            XCTAssertEqual(samples, golden, name)
            let starts: [Int]? = c["starts"] as? [Int]
            XCTAssertEqual(item.marked, starts, name)
            let window: [Double] = [item.n("x0"), item.n("x1"), item.n("y0"), item.n("y1")]
            Self.close(window, Self.numbers(c["window"]), name)
            let theta: [Double] = [item.n("th0"), item.n("th1")]
            Self.close(theta, Self.numbers(c["theta"]), name)
            XCTAssertEqual(MGGraph.isClosed(item), c["closed"] as? Bool, name)
            if let mark = Self.numbers(c["mark"]) {
                XCTAssertEqual(try XCTUnwrap(item.num["mx"], name), mark[0], accuracy: 1e-12, name)
                XCTAssertEqual(try XCTUnwrap(item.num["my"], name), mark[1], accuracy: 1e-12, name)
            } else {
                XCTAssertNil(item.num["mx"], name)
            }
            let points = try XCTUnwrap(c["points"] as? [String: Any], name)
            for (key, value) in points {
                let index: Int = try XCTUnwrap(Int(key), name)
                let expected: [Double] = try XCTUnwrap(Self.numbers(value), name)
                let p = item.pts[1 + index]
                XCTAssertEqual(p.x, expected[0], accuracy: 1e-9, "\(name) sample \(index)")
                XCTAssertEqual(p.y, expected[1], accuracy: 1e-9, "\(name) sample \(index)")
            }
            // Every accepted item round-trips through its wire form (the samples and the drawn window are derived).
            let ctx = MGContext(width: scene.width, height: scene.height, is3D: false, values: [:])
            XCTAssertEqual(try MGParser.item(.object(item.wire()), ctx), item, name)
            XCTAssertNil(item.wire()["pts"], name)
            let given: [NSNumber]? = object["xr"] as? [NSNumber]
            var givenXR: MGJSON?
            if let given {
                var values: [MGJSON] = []
                for n in given { values.append(MGJSON.number(n.doubleValue)) }
                givenXR = MGJSON.array(values)
            }
            XCTAssertEqual(item.wire()["xr"], givenXR, name)
        }
    }

    func testRefusedScenesGiveTheGoldenReasons() throws {
        let refused = try XCTUnwrap(Self.cases()["refused"] as? [[String: Any]])
        XCTAssertGreaterThan(refused.count, 35)
        for c in refused {
            let name = try XCTUnwrap(c["name"] as? String)
            let scene = try XCTUnwrap(c["scene"], name)
            guard case .failure(let error) = MGParser.scene(object: scene) else { XCTFail("accepted: \(name)"); continue }
            XCTAssertEqual(error.reason, c["reason"] as? String, name)
        }
    }

    func testTheDocumentationSceneEqualsTheBuiltInFixture() throws {
        let data = try Data(contentsOf: Self.root.appendingPathComponent("docs/fixtures/v1/curves.scene.json"))
        let parsed: MGScene = try MGParser.scene(data: data).get()
        let demo: MGFixtures.Demo? = MGFixtures.all.first(where: { (d: MGFixtures.Demo) -> Bool in d.id == "curves" })
        XCTAssertEqual(parsed, demo?.scene)
    }
}
