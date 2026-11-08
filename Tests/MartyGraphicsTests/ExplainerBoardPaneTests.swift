// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import MartyGraphics

/// The adaptive board pane (`MGExplainerBoardPane`, `MGExplainerSession.boardPane`): with a solid, the board pane shows
/// only while the shown board has a non-text item; its texts move to the title band otherwise. Deterministic, read from
/// the shown state, unchanged by a refused beat.
final class ExplainerBoardPaneTests: ExplainerTestCase {
    static let caption = #"{"v":1,"items":[{"id":"cap","k":"text","at":[6,7],"text":"Small gear: {p.teeth} teeth"},{"id":"cap2","k":"text","at":[6,6],"text":"Figures"}]}"#
    static let addTable = #"{"op":"add","item":{"id":"t","k":"table","at":[6,4],"header":true,"cells":[["Gear","Teeth"],["small","{p.teeth}"]]}}"#

    /// The pane in each presented beat, stepped as `marty-solid render` steps them (each beat settled).
    func panes(_ doc: String) throws -> [MGExplainerBoardPane] {
        let clock = MGManualClock()
        var s = try XFix.load(doc, pacing: .speech, clock: clock)
        var out: [MGExplainerBoardPane] = []
        var k = 0
        while let beat = s.presented.beat, beat == k {
            clock.advance(by: s.motionRemaining)
            _ = s.tick()
            out.append(s.boardPane)
            _ = s.lineEnded(k)
            k += 1
        }
        return out
    }

    func testRuleOnScenes() throws {
        XCTAssertEqual(MGExplainerBoardPane.rule(scene: nil, hasSolid: true), MGExplainerBoardPane(shown: false))
        let text = try MGParser.scene(json: XFix.json(#"{"v":1,"items":[{"id":"a","k":"text","at":[1,1],"text":"  First  "},{"id":"b","k":"text","at":[1,2],"text":"Second"}]}"#)).get()
        XCTAssertEqual(MGExplainerBoardPane.rule(scene: text, hasSolid: true), MGExplainerBoardPane(shown: false, texts: ["First", "Second"]))
        XCTAssertEqual(MGExplainerBoardPane.rule(scene: text, hasSolid: true).line, "First · Second")
        // Without a solid the board is the only view: always drawn, nothing moves.
        XCTAssertEqual(MGExplainerBoardPane.rule(scene: text, hasSolid: false), MGExplainerBoardPane(shown: true))
        let table = try MGParser.scene(json: XFix.json(XFix.table())).get()
        XCTAssertEqual(MGExplainerBoardPane.rule(scene: table, hasSolid: true), MGExplainerBoardPane(shown: true))
        // Any non-text kind keeps the pane: a line beside text.
        let vector = try MGParser.scene(json: XFix.json(#"{"v":1,"items":[{"id":"a","k":"text","at":[1,1],"text":"Push"},{"id":"v","k":"line","from":[1,1],"to":[3,1]}]}"#)).get()
        XCTAssertTrue(MGExplainerBoardPane.rule(scene: vector, hasSolid: true).shown)
        XCTAssertNil(MGExplainerBoardPane(shown: false).line)
    }

    /// A text-only board until a beat adds a table, then a beat removes it again.
    func testPaneFollowsTheShownBoardBeatByBeat() throws {
        let doc = XFix.doc(board: Self.caption, solid: XFix.gears, beats: """
            [{"say":"One."},{"say":"Two.","ops":[\(Self.addTable)]},{"say":"Three.","ops":[{"op":"remove","id":"t"}]}]
            """)
        let p = try panes(doc)
        XCTAssertEqual(p.map(\.shown), [false, true, false])
        // The board text is filled from the shown state and kept in board order.
        XCTAssertEqual(p[0].texts, ["Small gear: 15 teeth", "Figures"])
        XCTAssertEqual(p[0].line, "Small gear: 15 teeth · Figures")
        XCTAssertEqual(p[1].texts, [])
        XCTAssertEqual(p[2], p[0])
        // Same document, fresh sessions: the same panes.
        for _ in 0..<3 { XCTAssertEqual(try panes(doc), p) }
    }

    /// The pane reads the shown state: before the first beat's line, the session shows the board's first state.
    func testBoardOnlyAndSolidOnlyExplainers() throws {
        let boardOnly = XFix.doc(board: Self.caption.replacingOccurrences(of: "{p.teeth}", with: "few"), beats: #"[{"say":"One."}]"#)
        XCTAssertEqual(try panes(boardOnly).map(\.shown), [true])
        let solidOnly = XFix.doc(solid: XFix.gears, beats: #"[{"say":"One."}]"#)
        XCTAssertEqual(try panes(solidOnly), [MGExplainerBoardPane(shown: false)])
        XCTAssertEqual(MGExplainerSession().boardPane, MGExplainerBoardPane(shown: false))
    }

    /// A refused beat that would add a table leaves the pane as it was (its state never became the shown state).
    func testRefusedBeatLeavesThePaneUnchanged() throws {
        let hidden = MGExplainerBoardPane(shown: false, texts: ["Small gear: 15 teeth", "Figures"])
        let (s, ev) = XFix.stream([XFix.header(), #"{"solid":\#(XFix.gears)}"#, #"{"board":\#(Self.caption)}"#, #"{"say":"One."}"#,
                                   #"{"say":"Two."}"#, Self.addTable, #"{"check":{"value":"p.speed","eq":5}}"#])
        XCTAssertEqual(XFix.reasons(ev), ["check.failed.p.speed"])
        XCTAssertNil(s.state?.scene.item("t"))
        XCTAssertEqual(s.boardPane, hidden)
        // The same stream without the false check shows the table, and the pane.
        let (ok, okEvents) = XFix.stream([XFix.header(), #"{"solid":\#(XFix.gears)}"#, #"{"board":\#(Self.caption)}"#, #"{"say":"One."}"#,
                                          #"{"say":"Two."}"#, Self.addTable])
        XCTAssertEqual(XFix.reasons(okEvents), [])
        XCTAssertNotNil(ok.state?.scene.item("t"))
        XCTAssertEqual(ok.boardPane, MGExplainerBoardPane(shown: true))
    }
}
