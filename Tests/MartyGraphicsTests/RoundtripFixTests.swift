// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import MartyGraphics

/// Regression tests for three fixed engine issues: world-sized node/array defaults, transitive anchor
/// visibility and version-1-only stream previews. Synthetic data only.
/// Numeric array cells whose formatted text exceeds the 6-scalar string-cell limit are deliberately NOT covered:
/// that needs a protocol decision first.
final class RoundtripFixTests: XCTestCase {
    private typealias R = MGRegression

    private func context(_ scene: MGScene) -> MGContext {
        MGContext(width: scene.width, height: scene.height, is3D: scene.is3D, values: scene.values)
    }

    // MARK: defaults stay inside the range their own key accepts

    func testDefaultsAreValidInEveryWorldTheyParseIn() throws {
        XCTAssertNil(R.reason(#"{"v":1,"world":{"w":2,"h":2},"items":[{"id":"n","k":"node","at":[1,1],"text":"A"}],"steps":[{"say":"Rename.","do":[{"id":"n","key":"text","value":"B"}]}]}"#))
        XCTAssertNil(R.reason(#"{"v":1,"world":{"w":3,"h":3},"items":[{"id":"a","k":"array","at":[1.5,1.5],"vals":[1,2]}],"steps":[{"say":"Mark.","do":[{"id":"a","key":"marked","value":[0]}]}]}"#))
        let scene = try R.scene(#"{"v":1,"world":{"w":2,"h":2},"items":[{"id":"n","k":"node","at":[1,1],"text":"A"}]}"#)
        XCTAssertNoThrow(try MGParser.item(.object(scene.items[0].wire()), context(scene)))
    }

    func testDefaultsChangeOnlyBelowTheirBoundarySpan() throws {
        // Default 12 x 8 world and the boundary spans where the old default first becomes valid.
        for (world, r, cell) in [("", 0.5, 1.0), (#""world":{"w":3,"h":2},"#, 0.5, 0.75), (#""world":{"w":4,"h":2},"#, 0.5, 1.0)] {
            let scene = try R.scene(#"{"v":1,"# + world + #""items":[{"id":"n","k":"node","at":[1,1],"text":"A"},{"id":"a","k":"array","at":[1,1],"vals":[1]}]}"#)
            XCTAssertEqual(scene.items[0].n("r"), r, world)
            XCTAssertEqual(scene.items[1].n("cell"), cell, world)
        }
    }

    func testSmallWorldDefaultsAreCappedToTheirUpperBound() throws {
        let scene = try R.scene(#"{"v":1,"world":{"w":2,"h":2},"items":[{"id":"n","k":"node","at":[1,1],"text":"A"},{"id":"a","k":"array","at":[1,1],"vals":[1]}]}"#)
        XCTAssertEqual(scene.items[0].n("r"), 2.0 / 6, accuracy: 1e-12)
        XCTAssertEqual(scene.items[1].n("cell"), 0.5, accuracy: 1e-12)
        // Explicit values keep their existing range check: the fix only moves the default.
        XCTAssertEqual(R.reason(#"{"v":1,"world":{"w":2,"h":2},"items":[{"id":"n","k":"node","at":[1,1],"text":"A","r":0.5}]}"#), "node.r")
        XCTAssertEqual(R.reason(#"{"v":1,"world":{"w":2,"h":2},"items":[{"id":"a","k":"array","at":[1,1],"vals":[1],"cell":1}]}"#), "array.cell")
    }

    func testDefaultedItemsRoundTripAtEverySmallSpan() throws {
        for span in [2.0, 2.5, 2.9, 3.0, 3.5, 3.99, 4.0] {
            let json = #"{"v":1,"world":{"w":\#(span),"h":2},"items":[{"id":"n","k":"node","at":[1,1],"text":"A"},{"id":"a","k":"array","at":[1,1],"vals":[1,2]}]}"#
            let scene = try R.scene(json)
            for item in scene.items {
                let again = try MGParser.item(.object(item.wire()), context(scene))
                XCTAssertEqual(again, item, "span \(span) \(item.id)")
            }
        }
    }

    // MARK: anchor visibility is transitive

    func testHighlightChainsToHiddenAnchorsAreHidden() throws {
        let scene = try R.scene(#"{"v":1,"items":[{"id":"dot","k":"body","at":[6,4]},{"id":"inner","k":"highlight","target":"dot"},{"id":"outer","k":"highlight","target":"inner"}],"steps":[{"say":"Before."},{"say":"Reveal.","show":["dot"]}]}"#)
        XCTAssertEqual(MGTimeline.items(scene, step: 0).map(\.id), [])
        XCTAssertEqual(MGTimeline.items(scene, step: 1).map(\.id), ["dot", "inner", "outer"])
    }

    func testLongChainsAndMixedAnchorsCollapseTogether() throws {
        // A vector on a hidden body, then a 3-deep highlight chain on that vector, all disappear together and reappear
        // together; an unrelated item is unaffected.
        let scene = try R.scene(#"{"v":1,"items":[{"id":"free","k":"body","at":[2,2]},{"id":"ball","k":"body","at":[6,4]},{"id":"push","k":"vector","on":"ball","angle":0,"len":2},{"id":"h1","k":"highlight","target":"push"},{"id":"h2","k":"highlight","target":"h1"},{"id":"h3","k":"highlight","target":"h2"}],"steps":[{"say":"Before."},{"say":"Reveal.","show":["ball"]}]}"#)
        XCTAssertEqual(MGTimeline.items(scene, step: 0).map(\.id), ["free"])
        XCTAssertEqual(MGTimeline.items(scene, step: 1).map(\.id), ["free", "ball", "push", "h1", "h2", "h3"])
        for step in 0...1 {
            let visible = MGTimeline.items(scene, step: step)
            let ids = Set(visible.map(\.id))
            for item in visible where item.kind == .highlight { XCTAssertTrue(ids.contains(item.ref ?? ""), "step \(step) \(item.id)") }
        }
    }

    func testScenesWithoutHiddenAnchorsAreUnchanged() throws {
        let scene = try R.scene(#"{"v":1,"items":[{"id":"dot","k":"body","at":[6,4]},{"id":"inner","k":"highlight","target":"dot"},{"id":"outer","k":"highlight","target":"inner"}]}"#)
        XCTAssertEqual(MGTimeline.items(scene, step: 0).map(\.id), ["dot", "inner", "outer"])
    }

    // MARK: only version 1 is previewed

    func testPreviewRequiresVersionOne() {
        var parser = MGStreamParser()
        XCTAssertNil(parser.feed(#"{"v":2,"items":[{"id":"dot","k":"body","at":[3,4]}]}"#))
        if case .failure(let error) = parser.finish() { XCTAssertEqual(error.reason, "scene.version") } else { XCTFail("v:2 must not parse") }
    }

    func testNonOneVersionsNeverPreviewEvenWithATemplate() {
        for version in [#"2"#, #"0"#, #""1""#, #"null"#, #"1.5"#] {
            var parser = MGStreamParser()
            XCTAssertNil(parser.feed(#"{"v":\#(version),"items":[{"id":"dot","k":"body","at":[3,4]}]}"#), version)
            var templated = MGStreamParser()
            XCTAssertNil(templated.feed(#"{"v":\#(version),"template":"two_pointers","params":{"vals":[1,2,4,7],"target":9}}"#), version)
        }
    }

    func testVersionOneAndVersionlessTemplatePreviewsStillWork() {
        var parser = MGStreamParser()
        XCTAssertEqual(parser.feed(#"{"v":1,"items":[{"id":"dot","k":"body","at":[3,4]}"#)?.items.map(\.id), ["dot"])
        var decimal = MGStreamParser()
        XCTAssertNotNil(decimal.feed(#"{"v":1.0,"items":[{"id":"dot","k":"body","at":[3,4]}"#))
        // `v` may stream after the template; the preview starts as soon as template and params close.
        var templated = MGStreamParser()
        XCTAssertNotNil(templated.feed(#"{"template":"two_pointers","params":{"vals":[1,2,4,7],"target":9}"#))
        // A version that is still streaming in (incomplete member) does not block or fake a preview.
        var partial = MGStreamParser()
        XCTAssertNil(partial.feed(#"{"v":"#))
    }
}
