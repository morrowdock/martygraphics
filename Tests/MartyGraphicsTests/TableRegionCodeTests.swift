// SPDX-License-Identifier: Apache-2.0
import XCTest
import SwiftUI
@testable import MartyGraphics

/// The additive 2D kinds `table` and `region` and the text style `code`: strict parsing with stable reasons, exact wire
/// round trips (also in small worlds), 2D only, step edits and patches, layout bounds and a render smoke test.
final class TableRegionCodeTests: XCTestCase {
    private let ctx = MGContext(width: 12, height: 8, is3D: false, values: [:])

    private func item(_ object: [String: Any], width: Double = 12, height: Double = 8, dim: String = "2d") -> Result<MGScene, MGError> {
        MGParser.scene(object: ["v": 1, "dim": dim, "world": ["w": width, "h": height], "items": [object]])
    }
    private func reason(_ object: [String: Any], width: Double = 12, height: Double = 8, dim: String = "2d") -> String? {
        if case .failure(let e) = item(object, width: width, height: height, dim: dim) { return e.reason }
        return nil
    }
    private func roundTrips(_ scene: MGScene, file: StaticString = #filePath, line: UInt = #line) {
        let c = MGContext(width: scene.width, height: scene.height, is3D: scene.is3D, values: scene.values)
        for i in scene.items { XCTAssertEqual(try MGParser.item(.object(i.wire()), c), i, i.id, file: file, line: line) }
    }

    static let table: [String: Any] = ["id": "t", "k": "table", "at": [6, 4], "cells": [["name", "qty"], ["pen", 3], ["cup", ""]],
                                       "header": true, "marked": [[1, 1]], "label": "Lookup"]

    func testTableParsesAndRoundTrips() throws {
        let scene = try item(Self.table).get()
        let t = try XCTUnwrap(scene.items.first)
        XCTAssertEqual(t.kind, .table)
        XCTAssertEqual(t.list, ["name", "qty", "pen", "3", "cup", ""])
        XCTAssertEqual(t.num["rows"], 3); XCTAssertEqual(t.num["cols"], 2)
        XCTAssertEqual(t.num["cw"], 1.6); XCTAssertEqual(t.num["rh"], 0.7)
        XCTAssertEqual(t.marked, [3])
        XCTAssertTrue(t.has("header"))
        XCTAssertEqual(t.color, .accent)
        roundTrips(scene)
    }

    func testTableRefusalsUseStableReasons() {
        func with(_ key: String, _ value: Any) -> [String: Any] { var o = Self.table; o[key] = value; return o }
        XCTAssertEqual(reason(with("cells", [["a"], ["b", "c"]])), "table.cells")                       // ragged
        XCTAssertEqual(reason(with("cells", [] as [Any])), "table.cells")
        XCTAssertEqual(reason(with("cells", Array(repeating: ["a"], count: MGLimits.tableRows + 1))), "table.cells")
        XCTAssertEqual(reason(with("cells", [Array(repeating: "a", count: MGLimits.tableCols + 1)])), "table.cells")
        XCTAssertEqual(reason(with("cells", ["a"])), "table.cells")                                     // row not an array
        XCTAssertEqual(reason(with("cells", [["<b>x</b>"]])), "table.cell")
        XCTAssertEqual(reason(with("cells", [["https://example.org"]])), "table.cell")
        XCTAssertEqual(reason(with("cells", [["thirteen chars"]])), "table.cell")                       // over 12
        XCTAssertEqual(reason(with("cells", [[true]])), "table.cell")
        XCTAssertEqual(reason(with("cells", [[1e6]])), "table.cell")
        XCTAssertEqual(reason(with("marked", [[3, 0]])), "table.marked")                                // row out of range
        XCTAssertEqual(reason(with("marked", [[0, 0.5]])), "table.marked")
        XCTAssertEqual(reason(with("marked", [0])), "table.marked")
        XCTAssertEqual(reason(with("cw", 0.1)), "table.cw")
        XCTAssertEqual(reason(with("header", 1)), "table.header")
        XCTAssertEqual(reason(with("extra", 1)), "item.table.unknown.extra")
        var missing = Self.table; missing["cells"] = nil
        XCTAssertEqual(reason(missing), "item.table.missing")
        XCTAssertEqual(reason(Self.table, dim: "3d"), "3d.kind.table")
    }

    func testDefaultedTablesAndNumericCellsRoundTripInSmallWorlds() throws {
        // The defaults (1.6 x 0.7) are capped to the accepted range, so a defaulted table re-parses in a 2 x 2 world.
        let small = try item(["id": "t", "k": "table", "at": [1, 1], "cells": [["a"]]], width: 2, height: 2).get()
        XCTAssertLessThanOrEqual(try XCTUnwrap(small.items.first?.num["cw"]), 2.0 / 3)
        roundTrips(small)
        let numeric = try item(["id": "t", "k": "table", "at": [6, 4], "cells": [[-123456, 0.5, 42]]]).get()
        XCTAssertEqual(numeric.items.first?.list, ["-123456", "0.5", "42"])
        roundTrips(numeric)
    }

    func testMalformedTableItemsAreRefusedNotTrapped() {
        let base = try? item(Self.table).get().items.first
        for cols in [0, 7, 2.25, -Double.infinity, 1e300, .nan] {
            guard var bad = base else { return XCTFail("table did not parse") }
            bad.num["cols"] = cols
            XCTAssertThrowsError(try MGParser.item(.object(bad.wire()), ctx), "cols \(cols)")
        }
    }

    func testRegionParsesRoundTripsAndRefuses() throws {
        let region: [String: Any] = ["id": "r", "k": "region", "pts": [[1, 1], [4, 1], [3, 3]], "dashed": true, "label": "Zone"]
        let scene = try item(region).get()
        let r = try XCTUnwrap(scene.items.first)
        XCTAssertEqual(r.pts, [MGPoint(1, 1), MGPoint(4, 1), MGPoint(3, 3)])
        XCTAssertTrue(r.has("dashed"))
        roundTrips(scene)
        var two = region; two["pts"] = [[1, 1], [2, 2]]
        XCTAssertEqual(reason(two), "region.pts")
        var outside = region; outside["pts"] = [[1, 1], [40, 1], [3, 3]]
        XCTAssertEqual(reason(outside), "region.pts")
        var many = region; many["pts"] = Array(repeating: [1, 1], count: MGLimits.points + 1)
        XCTAssertEqual(reason(many), "region.pts")
        XCTAssertEqual(reason(region, dim: "3d"), "3d.kind.region")
    }

    func testCodeTextKeepsIndentAndAllowsComparisonsButNotMarkup() throws {
        func code(_ text: String, style: String? = "code") -> MGJSON {
            var o: [String: MGJSON] = ["id": .string("c"), "k": .string("text"), "at": .array([.number(1), .number(2)]), "text": .string(text)]
            if let style { o["style"] = .string(style) }
            return .object(o)
        }
        let line = try MGParser.item(code("    if k <= m"), ctx)
        XCTAssertEqual(line.text, "    if k <= m")
        XCTAssertTrue(line.has("code"))
        XCTAssertEqual(try MGParser.item(.object(line.wire()), ctx), line)
        XCTAssertEqual(try MGParser.item(code("if a > b"), ctx).text, "if a > b")
        for bad in ["<em>k</em>", "end </p>", "<!-- note -->", "<?xml?>", "q ```r```", "go to http://h.example", "    "] {
            XCTAssertThrowsError(try MGParser.item(code(bad), ctx), bad) { XCTAssertEqual(($0 as? MGError)?.reason, "text.text") }
        }
        // Other styles keep the strict rule: no angle brackets at all, and surrounding spaces are trimmed.
        XCTAssertThrowsError(try MGParser.item(code("k <= m", style: nil), ctx))
        XCTAssertEqual(try MGParser.item(code("  plain", style: nil), ctx).text, "plain")
        XCTAssertThrowsError(try MGParser.item(code("x", style: "fancy"), ctx)) { XCTAssertEqual(($0 as? MGError)?.reason, "text.style") }
    }

    /// Regression: text is checked before style, as before `code` existed, so an old invalid document keeps its reason.
    func testInvalidTextKeepsItsEarlierReasonOrder() {
        XCTAssertEqual(reason(["id": "t", "k": "text", "at": [1, 1], "text": "<b>", "style": "fancy"]), "text.text")
        XCTAssertEqual(reason(["id": "t", "k": "text", "at": [1, 1], "text": "ok", "style": "fancy"]), "text.style")
    }

    /// Regression: the 3D view cannot draw a code listing, so `code` text is refused in 3D, also through a patch.
    func testCodeTextIsRefusedIn3D() throws {
        let line: [String: Any] = ["id": "c", "k": "text", "at": [2, 2], "text": "i += 1", "style": "code"]
        XCTAssertEqual(reason(line, dim: "3d"), "3d.text.code")
        XCTAssertNil(reason(["id": "c", "k": "text", "at": [2, 2], "text": "i += 1"], dim: "3d"))   // plain text stays fine
        let flat = try item(line).get()
        let toDepth = try MGPatch.parse(data: Data(#"{"v":1,"ops":[{"op":"dim","dim":"3d"}]}"#.utf8)).get()
        guard case .failure(let e) = flat.applying(toDepth) else { return XCTFail("code text must not enter 3D") }
        XCTAssertEqual(e.reason, "3d.text.code")
        let depth = #"{"v":1,"dim":"3d","items":[{"id":"c","k":"text","at":[2,2],"text":"x"}],"steps":[{"say":"s","do":[{"id":"c","key":"style","value":"code"}]}]}"#
        XCTAssertEqual(MGRegression.reason(depth), "3d.text.code")
    }

    func testStepEditsAndPatchesReachTheNewKinds() throws {
        let json = #"{"v":1,"items":[{"id":"t","k":"table","at":[6,4],"cells":[["a","b"],["c","d"]]},{"id":"r","k":"region","pts":[[1,1],[3,1],[2,3]]}],"steps":[{"say":"One."},{"say":"Two.","do":[{"id":"t","key":"marked","value":[[1,0]]}]}]}"#
        let scene = try MGParser.scene(data: Data(json.utf8)).get()
        XCTAssertEqual(MGTimeline.items(scene, step: 1).first { $0.id == "t" }?.marked, [2])
        let bad = #"{"v":1,"items":[{"id":"t","k":"table","at":[6,4],"cells":[["a"]]}],"steps":[{"say":"x","do":[{"id":"t","key":"marked","value":[[4,0]]}]}]}"#
        XCTAssertEqual(MGRegression.reason(bad), "table.marked")
        let patch = try MGPatch.parse(data: Data(#"{"v":1,"rev":0,"ops":[{"op":"set","id":"r","key":"pts","value":[[1,1],[5,1],[5,5],[1,5]]}]}"#.utf8)).get()
        XCTAssertEqual(try scene.applying(patch).get().item("r")?.pts.count, 4)
        let broken = try MGPatch.parse(data: Data(#"{"v":1,"ops":[{"op":"set","id":"t","key":"cells","value":[["a"],["b","c"]]}]}"#.utf8)).get()
        XCTAssertEqual(scene.applying(broken).failureReason, "table.cells")
    }

    func testBlendKeepsWholeTableCounts() throws {
        let a = try item(["id": "t", "k": "table", "at": [6, 4], "cells": [["a"]]]).get().items
        let b = try item(["id": "t", "k": "table", "at": [6, 4], "cells": [["a", "b"], ["c", "d"]]]).get().items
        let mid = MGTimeline.blend(from: a, to: b, t: 0.5)
        XCTAssertEqual(mid.first?.num["rows"], 2); XCTAssertEqual(mid.first?.num["cols"], 2)
    }

    @MainActor func testLayoutBoundsAndRenderSmoke() throws {
        let scene = try XCTUnwrap(MGFixtures.all.first { $0.id == "cells" }?.scene)
        let size = CGSize(width: 480, height: 320)
        let vp = MGViewport(size: size, width: scene.width, height: scene.height, camera: nil)
        let grid = try XCTUnwrap(scene.item("grid")), zone = try XCTUnwrap(scene.item("zone")), code = try XCTUnwrap(scene.item("line1"))
        let gridBox = try XCTUnwrap(MGLayout.bounds(grid, in: scene.items, vp))
        XCTAssertEqual(gridBox.width, vp.length(1.4 * 2), accuracy: 0.5)
        XCTAssertEqual(gridBox.height, vp.length(0.6 * 3), accuracy: 0.5)
        XCTAssertNotNil(MGLayout.bounds(zone, in: scene.items, vp))
        let codeBox = try XCTUnwrap(MGLayout.bounds(code, in: scene.items, vp))
        XCTAssertEqual(codeBox.minX, vp.point(MGPoint(1.2, 6.8)).x, accuracy: 0.01)                  // left-aligned at `at`
        let input = MGRenderInput(scene: scene, items: MGTimeline.items(scene, step: 1), viewport: vp, focus: "grid", time: 1)
        let renderer = ImageRenderer(content: Canvas { context, _ in MGCanvasRenderer.draw(input, in: context) }.frame(width: size.width, height: size.height))
        renderer.scale = 1
        XCTAssertEqual(try XCTUnwrap(renderer.cgImage).width, 480)
        // A directly built table with an unchecked count draws nothing instead of trapping.
        var odd = grid; odd.num["rows"] = .nan
        let oddInput = MGRenderInput(scene: scene, items: [odd], viewport: vp, focus: nil, time: 0)
        let oddRenderer = ImageRenderer(content: Canvas { context, _ in MGCanvasRenderer.draw(oddInput, in: context) }.frame(width: size.width, height: size.height))
        XCTAssertNotNil(oddRenderer.cgImage)
    }

    func testStreamingPreviewsMatchStrictParse() throws {
        let json = try XCTUnwrap(MGFixtures.all.first { $0.id == "cells" }?.json)
        var parser = MGStreamParser()
        for character in json { _ = parser.feed(String(character)) }
        XCTAssertEqual(try parser.finish().get(), try MGRegression.scene(json))
    }
}

private extension Result where Failure == MGError {
    var failureReason: String? { if case .failure(let e) = self { return e.reason }; return nil }
}
