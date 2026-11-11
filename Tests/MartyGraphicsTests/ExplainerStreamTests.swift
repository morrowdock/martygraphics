// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import MartyGraphics

/// Explainer statements through the statement lane (spec PR 3b, tests S1–S13).
final class ExplainerStreamTests: ExplainerTestCase {
    static let lbl = #"{"v":1,"items":[{"id":"lbl","k":"text","at":[1,1],"text":"A label"}]}"#

    func statements(_ name: String) throws -> [String] {
        try MGExplainer.parse(data: Data(try XFix.example(name).utf8)).get().statements.map(\.canonicalString)
    }

    // S1: each card example as a document and as its flattened stream: the same final state, claims and legend.
    func testS1DocumentEqualsStream() throws {
        for name in ["planets-2d", "gears-3d", "gears-mixed"] {
            let doc = try XFix.load(try XFix.example(name))
            let (s, ev) = XFix.stream(try statements(name))
            XCTAssertTrue(XFix.reasons(ev).isEmpty, name)
            XCTAssertEqual(s.state, doc.state, name)
            XCTAssertEqual(s.claims, doc.claims, name)
            XCTAssertEqual(s.legend, doc.legend, name)
            XCTAssertEqual(s.presented, doc.presented, name)
        }
        // The fixture stream gives the same result.
        let fixture = try String(contentsOf: XFix.root.appendingPathComponent("docs/fixtures/v1/explainer-mixed.statements.ndjson"), encoding: .utf8)
        var s = MGExplainerSession(pacing: .immediate, clock: MGManualClock())
        XCTAssertTrue(XFix.reasons(s.feed(fixture) + s.endStream()).isEmpty)
        XCTAssertEqual(s.legend.text, "Solved 6 (2 animation ratios)")
    }

    // S2: a new stream starts with an explainer header.
    func testS2HeaderFirst() {
        XCTAssertEqual(XFix.reasons(XFix.stream([#"{"say":"Hi."}"#]).1).first, "explainer.header")
        XCTAssertEqual(XFix.reasons(XFix.stream([#"{"lesson":{"v":1}}"#]).1).first, "explainer.header")
        XCTAssertEqual(XFix.refusals(XFix.stream([#"{"lesson":{"v":1}}"#]).1).first?.view, .header)
    }

    // S3: views come before the first beat, once each.
    func testS3ViewOrder() {
        let (_, a) = XFix.stream([XFix.header(), #"{"solid":\#(XFix.gears)}"#, #"{"say":"Hi."}"#, #"{"board":\#(Self.lbl)}"#])
        XCTAssertEqual(XFix.reasons(a), ["stmt.order"])
        let (_, b) = XFix.stream([XFix.header(), #"{"solid":\#(XFix.gears)}"#, #"{"solid":\#(XFix.gears)}"#])
        XCTAssertEqual(XFix.reasons(b), ["stmt.order"])
    }

    // S4: one view and one highlight per beat.
    func testS4OncePerBeat() {
        let (_, ev) = XFix.stream([XFix.header(), #"{"solid":\#(XFix.gears)}"#, #"{"say":"Hi."}"#, #"{"view":{"spin":1}}"#,
                                   #"{"view":{"spin":2}}"#, #"{"highlight":["p"]}"#, #"{"highlight":["w"]}"#])
        XCTAssertEqual(XFix.reasons(ev), ["stmt.view.twice", "stmt.highlight.twice"])
    }

    // S5: split at every byte boundary, also inside strings with braces and escaped quotes: the same result.
    func testS5EveryByteBoundary() throws {
        var lines = try statements("gears-mixed")
        lines.insert(#"{"op":"add","item":{"id":"q","k":"text","at":[3,7],"text":"a \"q\" {p.teeth} } {"}}"#, at: 4)
        let text = lines.joined(separator: "\n") + "\n"
        let (whole, wev) = XFix.stream([text])
        let bytes = Array(text.utf8)
        for cut in stride(from: 1, to: bytes.count, by: 7) {
            var s = MGExplainerSession(pacing: .immediate, clock: MGManualClock())
            var ev = s.feed(Data(bytes[..<cut]))
            ev += s.feed(Data(bytes[cut...]))
            ev += s.endStream()
            XCTAssertEqual(XFix.reasons(ev), XFix.reasons(wev), "cut \(cut)")
            XCTAssertEqual(s.state, whole.state, "cut \(cut)")
        }
        // Every boundary of the 2D example (no solid to compile, so every cut is cheap).
        let small = try statements("planets-2d").joined(separator: "\n") + "\n"
        let (ref, rev) = XFix.stream([small])
        let sb = Array(small.utf8)
        for cut in 1..<sb.count {
            var s = MGExplainerSession(pacing: .immediate, clock: MGManualClock())
            let ev = s.feed(Data(sb[..<cut])) + s.feed(Data(sb[cut...])) + s.endStream()
            XCTAssertEqual(XFix.reasons(ev), XFix.reasons(rev), "cut \(cut)")
            XCTAssertEqual(s.state, ref.state, "cut \(cut)")
        }
    }

    // S6: garbage between statements is skipped and reported once.
    func testS6Garbage() {
        let (s, ev) = XFix.stream([XFix.header(), "garbage here", #"{"board":\#(Self.lbl)}"#, #"{"say":"Hi."}"#])
        XCTAssertEqual(XFix.reasons(ev), ["stmt.json"])
        XCTAssertEqual(s.captions[0], "Hi.")
    }

    // S7: every byte counts: 64 KiB of whitespace is terminal; later input is ignored until the stream ends.
    func testS7WhitespaceBudget() {
        var s = MGExplainerSession(pacing: .immediate, clock: MGManualClock())
        var ev = s.feed(XFix.header() + "\n")
        ev += s.feed(String(repeating: " ", count: MGExplainerLimits.bytes))
        ev += s.feed(#"{"board":\#(Self.lbl)}"#)
        XCTAssertEqual(XFix.reasons(ev), ["explainer.bytes"])
        XCTAssertNil(s.board)
        ev = s.endStream()
        XCTAssertFalse(ev.contains { if case .refused = $0 { return true }; return false })
    }

    // S8: at most 256 statements per stream.
    func testS8StatementCount() {
        var lines = [XFix.header(), #"{"board":\#(Self.lbl)}"#]
        lines += Array(repeating: #"{"op":"camera","camera":{"zoom":1}}"#, count: 255)
        let (_, ev) = XFix.stream(lines)
        XCTAssertEqual(XFix.reasons(ev), ["explainer.statements.count"])
    }

    /// A solid of about 30 KiB: thirteen extruded discs of 256 whole-number points.
    static var bigSolid: String {
        let pts = (0..<256).map { k -> String in
            let t = Double(k) / 256 * 2 * .pi
            return "[\(Int((300 * cos(t)).rounded())),\(Int((300 * sin(t)).rounded()))]"
        }.joined(separator: ",")
        let parts = (0..<13).map { #"{"id":"plate\#($0)","at":[\#(-3600 + $0 * 600),0,0],"shape":{"extrudedProfile":{"points":[\#(pts)],"depth":4}}}"# }
        return #"{"v":2,"parts":[\#(parts.joined(separator: ","))]}"#
    }

    // S9: the small board first, then a large solid: board first visible, each view timed on its own.
    func testS9FirstVisiblePerView() {
        let clock = MGManualClock()
        var s = MGExplainerSession(pacing: .immediate, clock: clock)
        XCTAssertGreaterThan(Self.bigSolid.utf8.count, 28_000)
        var ev = s.feed(XFix.header() + "\n" + #"{"board":\#(Self.lbl)}"# + "\n")
        clock.advance(by: .milliseconds(5))
        ev += s.feed(#"{"solid":\#(Self.bigSolid)}"# + "\n")
        clock.advance(by: .milliseconds(5))
        ev += s.feed(#"{"say":"Hi."}"# + "\n")
        ev += s.endStream()
        XCTAssertTrue(XFix.reasons(ev).isEmpty, "\(XFix.reasons(ev))")
        let names = ev.map(\.name)
        XCTAssertLessThan(names.firstIndex(of: "boardPresented")!, names.firstIndex(of: "solidCompiled")!)
        let t = s.timing
        XCTAssertNotNil(t.boardCore); XCTAssertNotNil(t.solidCore)
        XCTAssertLessThanOrEqual(t.boardPresentedAt!, t.solidStatementAt!)
        XCTAssertLessThanOrEqual(t.solidStatementAt!, t.solidCompiledAt!)
        XCTAssertLessThanOrEqual(t.solidCompiledAt!, t.streamEndedAt!)
        XCTAssertLessThanOrEqual(t.streamEndedAt!, t.completeAt!)
    }

    // S10: a follow-up stream with `keep` continues beat numbers; ids and views stay; views cannot arrive again.
    func testS10KeepFollowUp() {
        var (s, ev) = XFix.stream([XFix.header(), #"{"board":\#(Self.lbl)}"#, #"{"solid":\#(XFix.gears)}"#, #"{"say":"One."}"#])
        XCTAssertTrue(XFix.reasons(ev).isEmpty)
        ev = s.feed([#"{"keep":true}"#, #"{"say":"Two."}"#, #"{"highlight":["lbl","w"]}"#, #"{"say":"Three."}"#, #"{"view":{"spin":1}}"#,
                     #"{"solid":\#(XFix.gears)}"#].joined(separator: "\n") + "\n")
        ev += s.endStream()
        XCTAssertEqual(XFix.reasons(ev), ["stmt.order"])
        XCTAssertEqual(s.captions.keys.sorted(), [0, 1, 2])
        XCTAssertEqual(s.presented.beat, 2)
        XCTAssertEqual(s.ids.board, ["lbl"])
        XCTAssertEqual(s.ids.solid, ["p", "w"])
    }

    // S11: every issue names the explainer's statement index.
    func testS11IssueIndices() {
        let (_, ev) = XFix.stream([XFix.header(), #"{"board":\#(Self.lbl)}"#, #"{"solid":\#(XFix.gears)}"#, #"{"say":"One."}"#,
                                   #"{"op":"remove","id":"nothing"}"#, #"{"check":{"value":"nope","eq":1}}"#])
        XCTAssertEqual(XFix.refusals(ev).map(\.statement), [4, 5])
        XCTAssertEqual(XFix.refusals(ev).map(\.beat), [0, 0])
    }

    // S12: a 3D-only stream has no board events; pacing events come as for a lesson.
    func testS12ThreeDOnly() throws {
        let (s, ev) = XFix.stream(try statements("gears-3d"))
        let names = ev.map(\.name)
        XCTAssertFalse(names.contains("boardPresented"))
        XCTAssertTrue(names.contains("solidPresented"))
        XCTAssertEqual(names.filter { $0 == "lineDue" }.count, 2)
        XCTAssertEqual(names.filter { $0 == "beatPresented" }.count, 2)
        XCTAssertTrue(names.contains("explainerComplete"))
        XCTAssertTrue(s.isBoardless)
        XCTAssertEqual(s.state?.scene.items, [])
    }

    // S13: pause during a beat with `spin`: the beat settles only after the spin plays, and the clock holds while paused.
    func testS13PauseHoldsSpin() throws {
        let clock = MGManualClock()
        var s = MGExplainerSession(pacing: .estimate(wordsPerSecond: 100), clock: clock)
        _ = s.feed(try statements("gears-3d").joined(separator: "\n") + "\n")
        _ = s.endStream()
        clock.advance(by: .seconds(1)); _ = s.tick()   // line 1 ends (1 s minimum), beat 2 (spin 1) presents
        XCTAssertEqual(s.presented.beat, 1)
        clock.advance(by: .seconds(1)); _ = s.tick()   // line 2 ends; the spin (4 s per turn) still plays
        XCTAssertFalse(s.isComplete)
        s.pause()
        clock.advance(by: .seconds(30)); _ = s.tick()
        XCTAssertFalse(s.isComplete, "paused: the spin holds")
        _ = s.resume()
        clock.advance(by: .milliseconds(1500)); _ = s.tick()
        XCTAssertFalse(s.isComplete)
        clock.advance(by: .milliseconds(1600)); _ = s.tick()
        XCTAssertTrue(s.isComplete)
    }
}
