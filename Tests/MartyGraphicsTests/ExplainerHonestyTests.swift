// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import MartyGraphics

/// Truth tiers, rule N1 and the one legend across both views (spec PR 3b, tests T1–T14).
final class ExplainerHonestyTests: ExplainerTestCase {
    static let lbl = #"{"v":1,"items":[{"id":"lbl","k":"text","at":[1,1],"text":"A label"}]}"#

    // T1: one caption filled from a 2D engine value and a 3D fact.
    func testT1CaptionFromBothViews() throws {
        let s = try XFix.load(XFix.doc(board: XFix.rotate, solid: XFix.wheelGears,
                                       beats: #"[{"say":"Turned {theta}; the wheel turns {wheel.speed}.","ops":[{"op":"params","params":{"angle":30}}]}]"#))
        XCTAssertEqual(s.captions[0], "Turned 30°; the wheel turns -0.5.")
        XCTAssertEqual(s.claims.first { $0.id == "beat.1" }?.tier, .solved)
    }

    // T2: typed numbers in a caption.
    func testT2CaptionNumbers() throws {
        XCTAssertEqual(XFix.refusal(XFix.doc(solid: XFix.gears, beats: #"[{"say":"Hi."},{"say":"It has 30 teeth."}]"#))?.reason, "text.number.beat.2")
        for odd in ["½", "x²", "７", "\u{0BEF}"] {
            XCTAssertEqual(XFix.refusal(XFix.doc(solid: XFix.gears, beats: #"[{"say":"It has \#(odd) parts."}]"#))?.reason, "text.number.beat.1", odd)
        }
        let s = try XFix.load(XFix.doc(solid: XFix.gears, beats: #"[{"say":"About 30 teeth.","unchecked":"rounded by eye"}]"#))
        XCTAssertEqual(s.claims.last?.tier, .described)
        XCTAssertEqual(s.claims.last?.badge, "Not checked")
    }

    // T3: table number cells need a note.
    func testT3TableNumbers() throws {
        XCTAssertEqual(XFix.refusal(XFix.doc(board: XFix.table(), beats: #"[{"say":"Hi."}]"#))?.reason, "text.number.item.t")
        let basis = try XFix.load(XFix.doc(notes: #"{"t":{"basis":"NASA"}}"#, board: XFix.table(), beats: #"[{"say":"Hi."}]"#))
        XCTAssertEqual(basis.claims.first?.tier, .built)
        XCTAssertEqual(basis.claims.first?.badge, "Data as given")
        XCTAssertEqual(basis.legend.text, "Given 1")
        let unchecked = try XFix.load(XFix.doc(notes: #"{"t":{"unchecked":"from memory"}}"#, board: XFix.table(), beats: #"[{"say":"Hi."}]"#))
        XCTAssertEqual(unchecked.claims.first?.tier, .described)
        XCTAssertEqual(unchecked.legend.text, "Not checked 1")
        // Other numeric display fields: array values, bar values, plot ranges.
        for item in [#"{"id":"a","k":"array","at":[6,4],"vals":[3,1,2]}"#,
                     #"{"id":"a","k":"bars","at":[2,2],"w":6,"h":4,"bars":[{"label":"x","value":3}]}"#,
                     #"{"id":"a","k":"plot","at":[2,2],"w":6,"h":4,"xr":[0,10],"yr":[0,5],"pts":[[0,0],[10,5]]}"#] {
            XCTAssertEqual(XFix.refusal(XFix.doc(board: #"{"v":1,"items":[\#(item)]}"#, beats: #"[{"say":"Hi."}]"#))?.reason, "text.number.item.a", item)
        }
    }

    // T4: a table string cell shows a 3D fact; the filled text must fit the cell.
    func testT4CellShowsFact() throws {
        let s = try XFix.load(XFix.doc(board: XFix.table(cells: #"[["teeth"],["{p.teeth}"]]"#), solid: XFix.gears, beats: #"[{"say":"Hi."}]"#))
        XCTAssertEqual(s.state?.scene.item("t")?.list, ["teeth", "15"])
        XCTAssertEqual(s.claims.first { $0.id == "item.t" }?.tier, .solved)
        XCTAssertEqual(XFix.refusal(XFix.doc(board: XFix.table(cells: #"[["{p.teeth} teeth more"]]"#), solid: XFix.gears, beats: #"[{"say":"Hi."}]"#))?.reason, "table.cell")
    }

    // T5: `abs` in 2D text: no beat proves a sign.
    func testT5AbsInBoardText() {
        let board = #"{"v":1,"items":[{"id":"l","k":"text","at":[2,2],"text":"Speed {p.speed|abs}"}]}"#
        XCTAssertEqual(XFix.refusal(XFix.doc(board: board, solid: XFix.gears, beats: #"[{"say":"Hi."}]"#))?.reason, "text.sign.p.speed")
        // In a caption, `abs` needs a check of the same beat that proves the sign.
        XCTAssertEqual(XFix.refusal(XFix.doc(solid: XFix.gears, beats: #"[{"say":"It turns {w.speed|abs|frac}."}]"#))?.reason, "text.sign.w.speed")
    }

    // T6: `pct` applies to 3D speeds and ratios; a 2D value takes no modifier.
    func testT6Modifiers() throws {
        let s = try XFix.load(XFix.doc(board: XFix.rotate, solid: XFix.wheelGears, beats: #"[{"say":"The wheel turns at {wheel.speed|pct} of the input."}]"#))
        XCTAssertEqual(s.captions[0], "The wheel turns at -50% of the input.")
        XCTAssertEqual(XFix.refusal(XFix.doc(board: XFix.rotate, solid: XFix.wheelGears, beats: #"[{"say":"Turned {theta|pct}."}]"#))?.reason, "text.modifier.pct.theta")
    }

    // T7: a non-zero 3D fact that the 2D formatter would print as "0" is never shown as "0".
    func testT7NoFalseZero() {
        let solid = #"{"v":2,"parts":[{"id":"p","shape":{"shaft":{"radius":2,"length":4}},"joint":{"revolute":[0,0,1]},"drive":{"input":1}},{"id":"f","at":[10,0,0],"shape":{"shaft":{"radius":2,"length":4}},"joint":{"revolute":[0,0,1]},"drive":{"follow":{"source":"p","ratio":0.0001}}}]}"#
        XCTAssertEqual(MGPhysics.format(0.0001, unit: ""), "0", "the 2D formatter rounds it to 0")
        let doc = XFix.doc(board: XFix.table(cells: #"[["{f.speed}"]]"#), solid: solid, beats: #"[{"say":"Hi."}]"#)
        if let issue = XFix.refusal(doc) {
            XCTAssertEqual(issue.reason, "text.rounding.f.speed")
        } else {
            let s = try? XFix.load(doc)
            XCTAssertNotEqual(s?.state?.scene.item("t")?.list.first, "0")
        }
    }

    // T8: a template value the template marks as author data is Built ("Data as given"), counted as Schematic.
    func testT8BuiltValues() throws {
        let t = MGTemplate(name: "given_value", summary: "One value as given.", params: [MGParamSpec(name: "v", unit: "", range: 0...100)]) { p, _ in
            var b = MGTemplateBuild(title: "", items: [MGItem(id: "dot", kind: .body, color: .blue)])
            b.items[0].pts = [MGPoint(6, 4)]
            b.values = ["v": MGValue(value: p["v"], unit: "")]
            b.builtValues = ["v"]
            return b
        }
        try MGPacks.register(MGPack(id: "givenpack", title: "Given", summary: "test", templates: [t],
                                    fixtures: [.init(id: "given_value", title: "Given", json: #"{"v":1,"template":"given_value","params":{"v":3}}"#)]))
        let s = try XFix.load(XFix.doc(board: #"{"v":1,"template":"given_value","params":{"v":3}}"#, beats: #"[{"say":"The value is {v}."}]"#))
        XCTAssertEqual(s.claims.map(\.id), ["board.template", "beat.1"])
        XCTAssertEqual(s.claims.map(\.tier), [.built, .built])
        XCTAssertEqual(s.legend.text, "Schematic 2")
    }

    // T9: a 3D-only explainer converted from each shipped v2 example has the assembly's own legend and motion claims.
    func testT9ConvertedExamplesKeepTheirLegend() throws {
        for name in ["horizontal-reduction", "idler-gearbox"] {
            let assembly = try XFix.model(name)
            let doc = try MGSolidParser.document(json: assembly).get()
            let converted = try XCTUnwrap(MGExplainer.fromAssembly(assembly))
            let s = try XFix.load(converted.canonicalString)
            XCTAssertEqual(s.legend.text, doc.legend.text, name)
            XCTAssertEqual(s.legend.solved, doc.legend.solved, name)
            XCTAssertEqual(s.legend.schematic, doc.legend.built, name)
            XCTAssertEqual(s.legend.described, doc.legend.described, name)
            XCTAssertEqual(s.claims.filter { $0.kind == .motion }.map(\.id), doc.claims.filter { $0.kind == .motion }.map(\.id), name)
            XCTAssertEqual(s.claims.map(\.id), doc.claims.map { $0.id.replacingOccurrences(of: "step.", with: "beat.") }, name)
            XCTAssertEqual(s.captions.keys.sorted().map { s.captions[$0]! }, doc.steps.map(\.say), name)
        }
    }

    // T10: the legend groups in order, with the engine notes.
    func testT10LegendOrder() throws {
        let solid = #"{"v":2,"parts":[{"id":"p","shape":{"shaft":{"radius":2,"length":4}},"joint":{"revolute":[0,0,1]},"drive":{"input":1}},{"id":"f","at":[10,0,0],"shape":{"shaft":{"radius":2,"length":4}},"joint":{"revolute":[0,0,1]},"drive":{"follow":{"source":"p","ratio":2}}}]}"#
        let s = try XFix.load(XFix.doc(notes: #"{"t":{"basis":"a table"}}"#, board: XFix.table(), solid: solid,
                                       beats: #"[{"say":"It turns {p.speed} times.","check":[{"value":"p.speed","eq":1}]},{"say":"About 2 turns.","unchecked":"rough"}]"#))
        XCTAssertEqual(s.legend.text, "Solved 3 · Schematic 1 · Given 1 · Not checked 1")
        XCTAssertEqual(s.legend.notes, ["Some motion is schematic", "Shapes and drawings as authored"])
    }

    // T11: a `set` that writes a typed number.
    func testT11SetNumbers() {
        let lines = [XFix.header(#","notes":{"t":{"basis":"b"}}"#), #"{"board":{"v":1,"items":[{"id":"t","k":"text","at":[1,1],"text":"x"},{"id":"u","k":"text","at":[3,1],"text":"y"}]}}"#,
                     #"{"say":"One."}"#, #"{"op":"set","id":"t","key":"text","value":"7 km"}"#, #"{"op":"set","id":"u","key":"text","value":"7 km"}"#]
        let (s, ev) = XFix.stream(lines)
        XCTAssertEqual(XFix.reasons(ev), ["text.number.item.u"])
        XCTAssertEqual(s.state?.scene.item("t")?.text, "7 km")
        XCTAssertEqual(s.state?.scene.item("u")?.text, "y")
    }

    // T12: decimals in a noted cell are allowed in an explainer; the same table in a lesson is still refused (D3).
    func testT12DecimalsInNotedCell() throws {
        let cells = #"[["g","9.81 m"]]"#
        XCTAssertNoThrow(try XFix.load(XFix.doc(notes: #"{"t":{"basis":"standard gravity"}}"#, board: XFix.table(cells: cells), beats: #"[{"say":"Hi."}]"#)))
        var lesson = MGLessonSession()
        let ev = lesson.feed(#"{"scene":\#(XFix.table(cells: cells))}"# + "\n")
        XCTAssertEqual(LessonFixture.refusals(ev).map(\.reason), ["text.literal"])
    }

    // T13: a title may type a number; it is then Described.
    func testT13TitleNumbers() throws {
        let s = try XFix.load(XFix.doc(title: "Two gears, 45 mm apart", solid: XFix.gears, beats: #"[{"say":"Hi."}]"#))
        XCTAssertEqual(s.claims.first { $0.id == "title" }?.tier, .described)
        let f = try XFix.load(XFix.doc(title: "A {w.teeth}-tooth wheel", solid: XFix.gears, beats: #"[{"say":"Hi."}]"#))
        XCTAssertEqual(f.title, "A 30-tooth wheel")
        XCTAssertEqual(f.claims.first { $0.id == "title" }?.tier, .solved)
        XCTAssertEqual(XFix.refusal(XFix.doc(title: "A {theta} turn", board: XFix.rotate, beats: #"[{"say":"Hi."}]"#))?.reason, "explainer.title")
    }

    // T14: dotted checks use the #21 semantics; plain checks the #20 semantics; unknown names their own reasons.
    func testT14Checks() throws {
        let both = { (beats: String) in XFix.doc(board: XFix.rotate, solid: XFix.wheelGears, beats: beats) }
        XCTAssertNoThrow(try XFix.load(both(#"[{"say":"Hi.","check":[{"value":"wheel.speed","eq":-0.5,"tol":1e-9},{"value":"theta","eq":0}]}]"#)))
        XCTAssertEqual(XFix.refusal(both(#"[{"say":"Hi.","check":[{"value":"wheel.nope","lt":0}]}]"#))?.reason, "check.fact.wheel.nope")
        XCTAssertEqual(XFix.refusal(both(#"[{"say":"Hi.","check":[{"value":"nope","lt":0}]}]"#))?.reason, "check.unknown.nope")
        XCTAssertEqual(XFix.refusal(both(#"[{"say":"Hi.","check":[{"value":"wheel.speed","eq":0}]}]"#))?.reason, "check.failed.wheel.speed")
        // #21 `eq` with target 0 needs exactly 0; #20 `eq` compares displayed text.
        XCTAssertEqual(XFix.refusal(both(#"[{"say":"Hi.","check":[{"value":"wheel.speed","eq":-0.5,"wat":1}]}]"#))?.reason, "check.unknown.wat")
    }
}
