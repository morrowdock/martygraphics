// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import MartyGraphics

/// A table with no data row (docs/EXPLAINER.md, "Empty tables"): a header waiting for its first `set` is not drawn and
/// does not open the board pane, so the pane opens (the story slides it open) when the table is first filled.
final class EmptyTableTests: ExplainerTestCase {
    static let header = #"{"v":1,"items":[{"id":"t","k":"table","at":[6,4],"header":true,"cells":[["Item","Value"]]}]}"#
    static let fill = #"{"op":"set","id":"t","key":"cells","value":[["Item","Value"],["Teeth","{p.teeth}"]]}"#

    func item(_ cells: String, header: Bool = true) throws -> MGItem {
        let scene = try MGParser.scene(json: XFix.json(#"{"v":1,"items":[{"id":"t","k":"table","at":[6,4],"header":\#(header),"cells":\#(cells)}]}"#)).get()
        return try XCTUnwrap(scene.item("t"))
    }

    func testTheRule() throws {
        XCTAssertTrue(try item(#"[["Item","Value"]]"#).isEmptyTable)
        XCTAssertTrue(try item(#"[["Item","Value"],["",""]]"#).isEmptyTable)
        var spaces = try item(#"[["Item","Value"],["",""]]"#); spaces.list[3] = " \n"
        XCTAssertTrue(spaces.isEmptyTable, "white space only")
        XCTAssertFalse(try item(#"[["Item","Value"],["","x"]]"#).isEmptyTable)
        XCTAssertFalse(try item(#"[["Item","Value"]]"#, header: false).isEmptyTable, "without a header the first row is data")
        XCTAssertTrue(try item(#"[["",""]]"#, header: false).isEmptyTable)
        var other = MGItem(id: "x", kind: .text, color: .accent); other.text = ""
        XCTAssertFalse(other.isEmptyTable)
        // A table whose shape does not match its cells (built through the public API) is not called empty.
        var odd = try item(#"[["Item","Value"]]"#); odd.num["rows"] = 3
        XCTAssertFalse(odd.isEmptyTable)
    }

    /// Before: the header-only table opened the board pane on the beats before its first fill (r2j). Now the solid
    /// takes the whole frame until the beat that fills the table, and that beat opens the pane.
    func testThePaneOpensAtTheFirstFill() throws {
        let doc = XFix.doc(board: Self.header, solid: XFix.gears, beats: """
            [{"say":"One."},{"say":"Two."},{"say":"Three.","ops":[\(Self.fill)]}]
            """)
        XCTAssertNil(XFix.refusal(doc))
        let clock = MGManualClock()
        var s = try XFix.load(doc, pacing: .speech, clock: clock)
        var shown: [Bool] = []
        var k = 0
        while let beat = s.presented.beat, beat == k {
            clock.advance(by: s.motionRemaining)
            _ = s.tick()
            shown.append(s.boardPane.shown)
            _ = s.lineEnded(k)
            k += 1
        }
        XCTAssertEqual(shown, [false, false, true])
        // The render tool's layout reads the same rule: full-width solid panes, then the split.
        let panes = MGExplainerFrame.beatPanes(try MGExplainer.parse(data: Data(doc.utf8)).get()).beats.map(\.pane)
        XCTAssertEqual(panes.count, 3)
        XCTAssertEqual(panes[0], panes[1])
        XCTAssertEqual(panes[0], MGExplainerFrame.contentArea(width: MGAnnotationAnchorRules.width, height: MGAnnotationAnchorRules.height))
        XCTAssertLessThan(panes[2].width, panes[0].width)
        // An empty table never counts toward the pane, beside text or alone.
        let scene = try MGParser.scene(json: XFix.json(Self.header)).get()
        XCTAssertEqual(MGExplainerBoardPane.rule(scene: scene, hasSolid: true), MGExplainerBoardPane(shown: false))
        XCTAssertTrue(MGExplainerBoardPane.rule(scene: scene, hasSolid: false).shown, "a board-only explainer keeps its pane")
    }
}
