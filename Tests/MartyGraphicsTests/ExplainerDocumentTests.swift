// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import MartyGraphics

/// Explainer documents (spec PR 3b, tests X1–X18). Every refusal test also checks that nothing changed.
final class ExplainerDocumentTests: ExplainerTestCase {
    // X1: the three card examples are accepted with --strict; captions and legends are exact.
    func testX1CardExamples() throws {
        let twoD = try XFix.load(try XFix.example("planets-2d"))
        XCTAssertEqual(Array(twoD.captions.values), ["Venus and Earth are almost the same width."])
        XCTAssertEqual(twoD.legend.text, "Given 1")
        XCTAssertEqual(twoD.claims.map(\.id), ["item.t"])
        XCTAssertEqual(twoD.claims.first?.badge, "Data as given")
        XCTAssertTrue(twoD.isBoardless == false && twoD.solid == nil)

        let threeD = try XFix.load(try XFix.example("gears-3d"))
        XCTAssertEqual(threeD.captions[0], "The small gear has 15 teeth; the big gear has 30.")
        XCTAssertEqual(threeD.captions[1], "The big gear turns 1/2 of a turn, the other way.")
        XCTAssertEqual(threeD.legend.text, "Solved 5")   // 2 motion, 2 captions, 1 check; the title shows no fact
        XCTAssertEqual(threeD.claims.map(\.id), ["p", "w", "beat.1", "beat.2", "beat.2.check.1"])
        XCTAssertTrue(threeD.isBoardless)

        let mixed = try XFix.load(try XFix.example("gears-mixed"))
        XCTAssertEqual(mixed.state?.scene.item("t")?.list, ["gear", "teeth", "turns", "small", "15", "1", "big", "30", "-0.5"])
        XCTAssertEqual(mixed.captions[0], "Count the teeth: 15 and 30.")
        XCTAssertEqual(mixed.captions[1], "So the big gear turns 1/2 of a turn.")
        XCTAssertEqual(mixed.legend.text, "Solved 6")    // 2 motion, 1 table, 2 captions, 1 check
        XCTAssertEqual(mixed.claims.map(\.id), ["p", "w", "item.t", "beat.1", "beat.2", "beat.2.check.1"])

        for name in ["planets-2d", "gears-3d", "gears-mixed"] {
            let r = MGExplainerReport.check(data: Data(try XFix.example(name).utf8), profile: .strict, engine: nil)
            XCTAssertTrue(r.ok, "\(name): \(r.reason ?? "")")
        }
    }

    // X2: document shape.
    func testX2DocumentShape() {
        func r(_ s: String) -> String? { XFix.refusal(s)?.reason }
        let solid = XFix.gears
        XCTAssertEqual(r(#"{"v":1,"kind":"explainer","solid":\#(solid)}"#), "explainer.beats")
        let beats17 = "[" + Array(repeating: #"{"say":"Hi."}"#, count: 17).joined(separator: ",") + "]"
        XCTAssertEqual(r(XFix.doc(solid: solid, beats: beats17)), "explainer.beats.count")
        XCTAssertEqual(r(XFix.doc(solid: solid, beats: #"[{"say":"Hi."}]"#).replacingOccurrences(of: #""v":1,"kind""#, with: #""v":2,"kind""#)), "explainer.version")
        XCTAssertEqual(r(XFix.doc(solid: solid, beats: #"[{"say":"Hi."}]"#).replacingOccurrences(of: #""kind":"explainer""#, with: #""kind":"lesson""#)), "explainer.kind")
        XCTAssertEqual(r(XFix.doc(solid: solid, beats: #"[{"say":"Hi."}]"#, extra: #""foo":1"#)), "explainer.unknown.foo")
        XCTAssertEqual(r(XFix.doc(beats: #"[{"say":"Hi."}]"#)), "explainer.empty")
        XCTAssertEqual(r("[1]"), "explainer.object")
        XCTAssertEqual(r("{"), "explainer.json")
    }

    // X3, X4: the views may not carry their own walkthrough, title or dimension.
    func testX3X4ViewShapes() {
        func r(_ board: String? = nil, _ solid: String? = nil) -> String? { XFix.refusal(XFix.doc(board: board, solid: solid, beats: #"[{"say":"Hi."}]"#))?.reason }
        XCTAssertEqual(r(#"{"v":1,"items":[{"id":"a","k":"text","at":[1,1],"text":"x"}],"steps":[{"say":"s"}]}"#), "explainer.board.steps")
        XCTAssertEqual(r(#"{"v":1,"title":"T","items":[{"id":"a","k":"text","at":[1,1],"text":"x"}]}"#), "explainer.board.title")
        XCTAssertEqual(r(#"{"v":1,"dim":"3d","items":[{"id":"a","k":"text","at":[1,1],"text":"x"}]}"#), "explainer.board.dim")
        XCTAssertEqual(r(nil, XFix.gears.replacingOccurrences(of: #"{"v":2"#, with: #"{"v":1"#)), "explainer.solid.version")
        XCTAssertEqual(r(nil, String(XFix.gears.dropLast()) + #","steps":[{"say":"s"}]}"#), "explainer.solid.steps")
        XCTAssertEqual(r(nil, String(XFix.gears.dropLast()) + #","title":"T"}"#), "explainer.solid.title")
    }

    // X5, X6: commands need a board, views need a solid; `title` is the explainer's.
    func testX5X6MissingViewsAndTitleOp() {
        XCTAssertEqual(XFix.refusal(XFix.doc(solid: XFix.gears, beats: #"[{"say":"Hi.","ops":[{"op":"camera","camera":{"zoom":1}}]}]"#))?.reason, "explainer.board.missing")
        XCTAssertEqual(XFix.refusal(XFix.doc(board: XFix.table(), beats: #"[{"say":"Hi.","view":{"spin":1}}]"#))?.reason, "explainer.solid.missing")
        XCTAssertEqual(XFix.refusal(XFix.doc(notes: #"{"t":{"basis":"b"}}"#, board: XFix.table(), beats: #"[{"say":"Hi.","ops":[{"op":"title","title":"New"}]}]"#))?.reason, "explainer.op.title")
        // The same in a stream: refused alone; the beat stays.
        let (s, ev) = XFix.stream([XFix.header(), #"{"solid":\#(XFix.gears)}"#, #"{"say":"Hi."}"#, #"{"op":"camera","camera":{"zoom":1}}"#])
        XCTAssertEqual(XFix.reasons(ev), ["explainer.board.missing"])
        XCTAssertEqual(s.captions[0], "Hi.")
    }

    // X7: `tier` is never authored, anywhere.
    func testX7TierKey() {
        XCTAssertEqual(XFix.refusal(XFix.doc(board: #"{"v":1,"items":[{"id":"a","k":"text","at":[1,1],"text":"x","tier":"solved"}]}"#, beats: #"[{"say":"Hi."}]"#))?.reason, "tier.key")
        XCTAssertEqual(XFix.refusal(XFix.doc(solid: String(XFix.gears.dropLast()) + #","tier":1}"#, beats: #"[{"say":"Hi."}]"#))?.reason, "tier.key")
        XCTAssertEqual(XFix.refusal(XFix.doc(solid: XFix.gears, beats: #"[{"say":"Hi.","tier":"solved"}]"#))?.reason, "tier.key")
        let (_, ev) = XFix.stream([XFix.header(), #"{"solid":\#(XFix.gears)}"#, #"{"say":"Hi."}"#, #"{"view":{"spin":1,"tier":2}}"#])
        XCTAssertEqual(XFix.reasons(ev), ["tier.key"])
    }

    // X8: raw input over 128 KiB is refused without parsing.
    func testX8RawBytes() {
        let before = MGExplainer.parses.value
        let big = Data(repeating: 0x20, count: MGExplainerLimits.rawBytes + 1)
        XCTAssertEqual(MGExplainer.parse(data: big).failureIssue?.reason, "explainer.bytes")
        XCTAssertEqual(MGExplainer.parses.value, before, "the JSON parser never ran")
        XCTAssertEqual(MGExplainerReport.check(data: big, engine: nil).reason, "explainer.bytes")
    }

    // X9: the document's size is its flattened stream; source formatting does not count, content does.
    func testX9FlattenedSize() {
        func doc(_ pad: Int) -> String {
            XFix.doc(solid: #"{"v":2,"parts":[{"id":"a","name":"\#(String(repeating: "x", count: pad))","shape":{"box":{"size":[1,1,1]}}}]}"#, beats: #"[{"say":"Hi."}]"#)
        }
        let base = MGExplainer.parse(data: Data(doc(1000).utf8))
        guard case .success(let d) = base else { return XCTFail("\(base)") }
        let size = d.statementStream.utf8.count
        let exact = 1000 + MGExplainerLimits.bytes - size
        guard case .success(let at) = MGExplainer.parse(data: Data(doc(exact).utf8)) else { return XCTFail("at the limit") }
        XCTAssertEqual(at.statementStream.utf8.count, MGExplainerLimits.bytes)
        XCTAssertEqual(MGExplainer.parse(data: Data(doc(exact + 1).utf8)).failureIssue?.reason, "explainer.bytes")
        // 70 KiB of whitespace between tokens does not count.
        let spaced = doc(10).replacingOccurrences(of: ",", with: "," + String(repeating: " ", count: 9000))
        XCTAssertGreaterThan(spaced.utf8.count, MGExplainerLimits.bytes)
        XCTAssertNotNil(try? MGExplainer.parse(data: Data(spaced.utf8)).get())
    }

    /// A torus `ring` repeated 12 times (24,576 triangles each). Cuts read part triangles once per distinct part and
    /// plane; the section work budget is 400,000 reads per document.
    static var budgetSolid: String {
        let pts = (0..<128).map { k -> String in
            let t = Double(k) / 128 * 2 * .pi
            return "[\(20 + 5 * cos(t)),\(5 * sin(t))]"
        }.joined(separator: ",")
        return #"{"v":2,"parts":[{"id":"ring","shape":{"revolvedProfile":{"points":[\#(pts)],"closed":true}},"repeat":{"count":12}}]}"#
    }

    // X10: a beat view whose cut passes the budget is refused alone; the other beats present; nothing else changes.
    func testX10ViewOverBudget() throws {
        var s = MGExplainerSession(pacing: .immediate, clock: MGManualClock())
        _ = s.feed(XFix.header() + "\n" + #"{"solid":\#(Self.budgetSolid)}"# + "\n")
        func beat(_ say: String, _ view: String) -> [MGExplainerEvent] { s.feed(#"{"say":"\#(say)"}"# + "\n" + #"{"view":\#(view)}"# + "\n") }
        XCTAssertTrue(XFix.reasons(beat("One.", #"{"section":{"normal":[0,0,1],"offset":1,"parts":["ring1","ring2","ring3","ring4","ring5"]}}"#)).isEmpty)
        XCTAssertTrue(XFix.reasons(beat("Two.", #"{"section":{"normal":[0,0,1],"offset":2,"parts":["ring1"]}}"#)).isEmpty)
        let before = s.solid
        let ev = beat("Three.", #"{"section":{"normal":[0,0,1],"offset":0,"parts":["ring"]}}"#)
        XCTAssertEqual(XFix.reasons(ev), ["section.budget"])
        XCTAssertEqual(XFix.refusals(ev).first?.beat, 2)
        XCTAssertTrue(s.solid == before, "the cut cache and the budget counter are unchanged")
        XCTAssertTrue(XFix.reasons(beat("Four.", #"{"section":{"normal":[0,0,1],"offset":-1,"parts":["ring1"]}}"#)).isEmpty)
        let end = s.endStream()
        XCTAssertTrue(XFix.reasons(end).isEmpty)
        let presented = s.events.compactMap { if case .beatPresented(let k) = $0 { return k } else { return nil } }
        XCTAssertEqual(presented, [0, 1, 2, 3])
        XCTAssertEqual(s.solid?.steps.count, 3, "beats 1, 2 and 4 have cuts; beat 3 shows the default view")
        XCTAssertNil(s.stepOf[2], "beat 3 has no cut")
    }

    // X11: one beat highlights a table row and a 3D part together; highlight changes no state.
    func testX11HighlightBothViews() throws {
        var s = MGExplainerSession(pacing: .speech, clock: MGManualClock())
        _ = s.feed([XFix.header(#","notes":{"t":{"basis":"b"}}"#), #"{"board":\#(XFix.table())}"#, #"{"solid":\#(XFix.wheelGears)}"#,
                    #"{"say":"Look."}"#].joined(separator: "\n") + "\n")
        let source = s.lesson.projected?.scene.source
        let ev = s.feed(#"{"highlight":["t.r2","wheel"]}"# + "\n")
        XCTAssertTrue(XFix.reasons(ev).isEmpty)
        XCTAssertEqual(s.lesson.projected?.scene.source, source, "highlight is presentation only")
        _ = s.endStream()
        XCTAssertEqual(s.presented.beat, 0)
        XCTAssertEqual(s.presented.tableRows, ["t": [2]])
        XCTAssertEqual(s.presented.solidHighlight, ["wheel"])
        XCTAssertTrue(s.presented.boardEmphasis.isEmpty)
        XCTAssertEqual(s.state?.scene.source, source)
    }

    // X12: table sub-addresses inside the table's size, decimal without sign or leading zero.
    func testX12SubAddresses() {
        for bad in ["t.r9", "t.r01", "t.r-1", "t.r1c9", "t.rx", "t.c1"] {
            let (_, ev) = XFix.stream([XFix.header(#","notes":{"t":{"basis":"b"}}"#), #"{"board":\#(XFix.table())}"#, #"{"say":"Look."}"#,
                                       #"{"highlight":["\#(bad)"]}"#])
            XCTAssertEqual(XFix.reasons(ev), ["beat.highlight.ref.\(MGLessonIssue.segment(bad))"], bad)
        }
        let (s, ev) = XFix.stream([XFix.header(#","notes":{"t":{"basis":"b"}}"#), #"{"board":\#(XFix.table())}"#, #"{"say":"Look."}"#,
                                   #"{"highlight":["t.r4","t.r0c1"]}"#])
        XCTAssertTrue(XFix.reasons(ev).isEmpty)
        XCTAssertEqual(s.presented.tableRows, ["t": [4]])
        XCTAssertEqual(s.presented.tableCells, ["t": [1]])
    }

    func mixedPrefix(_ notes: String = "") -> [String] {
        [XFix.header(#","notes":{"t":{"basis":"b"}}"#), #"{"board":\#(XFix.table())}"#, #"{"solid":\#(XFix.wheelGears)}"#,
         #"{"say":"One."}"#, #"{"view":{"spin":1}}"#]
    }

    // X13: a failing 3D check refuses the whole beat; later statements of the beat are cascades.
    func testX13ThreeDCheckFails() {
        var lines = mixedPrefix()
        lines += [#"{"say":"Two."}"#, #"{"op":"set","id":"t","key":"label","value":"Widths"}"#, #"{"view":{"spin":2}}"#,
                  #"{"check":{"value":"wheel.speed","gt":0}}"#, #"{"highlight":["wheel"]}"#, #"{"view":{"spin":1}}"#]
        let (s, ev) = XFix.stream(lines)
        XCTAssertEqual(XFix.reasons(ev), ["check.failed.wheel.speed", "beat.refused", "beat.refused"])
        XCTAssertEqual(XFix.refusals(ev).first?.beat, 1)
        XCTAssertNil(s.state?.scene.item("t")?.label, "the 2D state is back at the start of beat 2")
        XCTAssertEqual(s.presented.beat, 0)
        XCTAssertEqual(s.solid?.steps.count, 1, "beat 2's view was dropped and its cut budget released")
        XCTAssertTrue(s.beats[1]!.dropped)
    }

    // X14: a failing 2D check: the same, through the lesson path.
    func testX14TwoDCheckFails() {
        let lines = [XFix.header(), #"{"board":\#(XFix.rotate)}"#, #"{"solid":\#(XFix.wheelGears)}"#, #"{"say":"One."}"#,
                     #"{"say":"Two."}"#, #"{"op":"params","params":{"angle":30}}"#, #"{"view":{"spin":2}}"#,
                     #"{"check":{"value":"theta","eq":0}}"#, #"{"highlight":["wheel"]}"#]
        let (s, ev) = XFix.stream(lines)
        XCTAssertEqual(XFix.reasons(ev), ["check.theta", "beat.refused"])
        XCTAssertEqual(s.state?.value("theta"), 0)
        XCTAssertEqual(s.presented.beat, 0)
        XCTAssertNil(s.presented.step)
        XCTAssertEqual(s.solid?.steps.count, 0)
    }

    // X15: a refused view is refused alone; the beat presents with the default view and keeps its commands and checks.
    func testX15ViewRefusedAlone() {
        let lines = [XFix.header(), #"{"board":\#(XFix.rotate)}"#, #"{"solid":\#(XFix.wheelGears)}"#, #"{"say":"One."}"#,
                     #"{"say":"Two."}"#, #"{"op":"params","params":{"angle":30}}"#, #"{"view":{"camera":"nowhere"}}"#,
                     #"{"check":{"value":"theta","eq":30}}"#]
        let (s, ev) = XFix.stream(lines)
        XCTAssertEqual(XFix.reasons(ev), ["view.camera"])
        XCTAssertEqual(s.presented.beat, 1)
        XCTAssertNil(s.presented.step)
        XCTAssertEqual(s.state?.value("theta"), 30)
        XCTAssertEqual(s.claims.last?.id, "beat.2.check.1")
    }

    // X16: a learner change makes a 2D check false at presentation: the beat is refused and its 3D view never shows.
    func testX16LearnerBreaksCheckAtPresentation() {
        var s = MGExplainerSession(pacing: .speech, clock: MGManualClock())
        _ = s.feed([XFix.header(), #"{"board":\#(XFix.rotate)}"#, #"{"solid":\#(XFix.wheelGears)}"#,
                    #"{"op":"bind","control":{"id":"angle","k":"slider","param":"angle","min":0,"max":360,"step":5,"label":"Angle"}}"#,
                    #"{"say":"Look."}"#, #"{"say":"Still at {theta}."}"#, #"{"check":{"value":"theta","eq":0}}"#,
                    #"{"view":{"spin":1}}"#].joined(separator: "\n") + "\n")
        _ = s.endStream()
        XCTAssertEqual(s.presented.beat, 0)
        XCTAssertNotNil(try? s.control("angle", 90).get())
        let ev = s.lineEnded(0)
        XCTAssertEqual(XFix.reasons(ev), ["check.theta"])
        XCTAssertEqual(s.presented.beat, 0)
        XCTAssertNil(s.presented.step, "beat 2's view is not shown")
    }

    // X17: describe routes by namespace member.
    func testX17Describe() throws {
        let s = try XFix.load(try XFix.example("gears-mixed"))
        XCTAssertEqual(s.describe("t")?["kind"], .string("table"))
        XCTAssertEqual(s.describe("t.r1")?["row"], .number(1))
        XCTAssertEqual(s.describe("w")?["id"], .string("w"))
        XCTAssertNotNil(s.describe("w")?["facts"]?["w.teeth"])
        XCTAssertNil(s.describe("nothing"))
        XCTAssertNil(s.describe("t.r9"))
    }

    // X18: snapshot and restore, with a moved slider; a snapshot whose solid no longer compiles is refused whole.
    func testX18SnapshotRestore() throws {
        var s = MGExplainerSession(pacing: .speech, clock: MGManualClock())
        _ = s.feed([XFix.header(#","title":"Turn {wheel.teeth}""#), #"{"board":\#(XFix.rotate)}"#, #"{"solid":\#(XFix.wheelGears)}"#,
                    #"{"op":"bind","control":{"id":"angle","k":"slider","param":"angle","min":0,"max":360,"step":5,"label":"Angle"}}"#,
                    #"{"say":"One."}"#, #"{"view":{"spin":1}}"#, #"{"say":"Two {theta}."}"#, #"{"highlight":["wheel","shape"]}"#,
                    #"{"say":"Three {wheel.speed|abs|frac}."}"#, #"{"check":{"value":"wheel.speed","lt":0}}"#, #"{"view":{"explode":1}}"#,
                    #"{"highlight":["wheel"]}"#].joined(separator: "\n") + "\n")
        _ = s.endStream()
        _ = s.lineEnded(0); _ = s.lineEnded(1)
        XCTAssertEqual(s.presented.beat, 2)
        XCTAssertNotNil(try? s.control("angle", 45).get())
        let snap = s.snapshot()
        // Through JSON text and back.
        let text = snap.canonicalString
        let back = MGJSON(any: try JSONSerialization.jsonObject(with: Data(text.utf8)))!
        guard case .success(let r) = MGExplainerSession.restore(back, pacing: .speech, clock: MGManualClock()) else {
            return XCTFail("\(MGExplainerSession.restore(back, pacing: .speech, clock: MGManualClock()))")
        }
        XCTAssertEqual(r.state, s.state)
        XCTAssertEqual(r.presented, s.presented)
        XCTAssertEqual(r.legend, s.legend)
        XCTAssertEqual(r.title, "Turn 30")
        XCTAssertEqual(r.captions, s.captions)
        XCTAssertEqual(r.solid?.steps.count, s.solid?.steps.count)
        // A snapshot whose solid no longer compiles: refused with the solid's reason; nothing is loaded.
        guard case .object(var o) = back, case .string(let src)? = o["solid"] else { return XCTFail() }
        o["solid"] = .string(src.replacingOccurrences(of: #""teeth":30"#, with: #""teeth":3"#))
        XCTAssertEqual(MGExplainerSession.restore(.object(o), pacing: .speech).failureIssue?.reason, "part.gear.teeth")
        o["solid"] = .string(src)
        o["lesson"] = .string("{")
        XCTAssertEqual(MGExplainerSession.restore(.object(o), pacing: .speech).failureIssue?.reason, "snapshot.lesson")
    }
}

extension Result {
    var failureIssue: Failure? { if case .failure(let e) = self { return e }; return nil }
}
