// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import MartyGraphics

/// Regression tests for the PR #32 third check: a restored heading, board motion under `finishNow` and `.immediate`,
/// and speech (`lineDue`) as a learner-visible claim, for every pacing.
final class ExplainerThirdCheckTests: ExplainerTestCase {
    static let animatedLines = [XFix.header(), #"{"board":\#(XFix.rotate)}"#, #"{"say":"Start."}"#, #"{"say":"The angle is {theta}."}"#,
                                #"{"op":"animate","param":"angle","to":90,"dur":6}"#, #"{"check":{"value":"theta","eq":90}}"#]
    func feed(_ s: inout MGExplainerSession, _ lines: [String]) -> [MGExplainerEvent] { s.feed(lines.joined(separator: "\n") + "\n") }
    func dueLines(_ ev: [MGExplainerEvent]) -> [String] { XFix.lineDue(ev) }

    // F1: a restored scene's wire heading is refused like an authored one (current state and baseline).
    func testF1RestoredHeadingIsRefused() throws {
        var s = MGExplainerSession(pacing: .speech, clock: MGManualClock())
        _ = feed(&s, [XFix.header(), #"{"board":{"v":1,"template":"bst","params":{"values":[2,1,3]}}}"#, #"{"say":"The tree has {n} nodes."}"#,
                      #"{"check":{"value":"n","eq":3}}"#, #"{"say":"Again {n}."}"#])
        _ = s.endStream()
        let clean = s.snapshot().objectValue!
        guard case .success = MGExplainerSession.restore(.object(clean), pacing: .speech) else { return XCTFail("clean") }
        func edit(_ path: String) -> MGJSON {
            var o = clean
            guard case .string(let t)? = o["lesson"], var l = XFix.json(t).objectValue else { return .null }
            if path == "scene", var sc = l["scene"]?.objectValue { sc["title"] = .string("The tree has 999 nodes."); l["scene"] = .object(sc) }
            if path == "baseline", var b = l["baseline"]?.objectValue, var sc = b["scene"]?.objectValue {
                sc["title"] = .string("The tree has 999 nodes."); b["scene"] = .object(sc); l["baseline"] = .object(b)
            }
            if path == "title" { l["title"] = .string("The tree has 999 nodes") }
            o["lesson"] = .string(MGJSON.object(l).canonicalString)
            return .object(o)
        }
        XCTAssertEqual(MGExplainerSession.restore(edit("scene"), pacing: .speech).failureIssue?.reason, "explainer.board.title")
        XCTAssertEqual(MGExplainerSession.restore(edit("baseline"), pacing: .speech).failureIssue?.reason, "explainer.board.title")
        // A saved inner lesson title is never kept (the explainer's title comes from its own header).
        guard case .success(let r) = MGExplainerSession.restore(edit("title"), pacing: .speech) else { return XCTFail("inner title") }
        XCTAssertNil(r.lesson.title)
        XCTAssertEqual(r.legend, s.legend)
    }

    // F2: `finishNow` ends the board motion itself: a new direct change, so a host adopts the end state at once.
    @MainActor func testF2FinishNowEndsTheBoardMotion() {
        let clock = MGManualClock()
        let c = MGExplainerController(pacing: .speech, clock: clock)
        c.begin()
        c.feed(Self.animatedLines.joined(separator: "\n") + "\n"); c.endStream()
        c.lineEnded(0)
        XCTAssertEqual(c.board.transition.keyframeDuration, 6, accuracy: 1e-9)
        clock.advance(by: .seconds(3)); c.pause()
        let revision = c.board.revision
        c.finishNow()
        XCTAssertGreaterThan(c.board.revision, revision, "the board adopts again")
        XCTAssertEqual(c.board.transition, .direct, "no tween is left to play the 45° frame")
        XCTAssertEqual(c.board.scene?.values["theta"]?.value, 90)
        XCTAssertEqual(c.session.caption, "The angle is 90°.")
        XCTAssertTrue(c.session.claims.contains { $0.id == "beat.2.check.1" })
    }

    // F2: `.immediate` pacing plays no motion: every change reaches the board as a direct change, also a follow-up
    // beat on a board already shown.
    @MainActor func testF2ImmediateShowsTheEndStateDirectly() {
        let c = MGExplainerController(pacing: .immediate, clock: MGManualClock())
        c.begin()
        c.feed([XFix.header(), #"{"board":\#(XFix.rotate)}"#, #"{"say":"Start."}"#].joined(separator: "\n") + "\n"); c.endStream()
        c.feed([#"{"keep":true}"#, #"{"say":"The angle is {theta}."}"#, #"{"op":"animate","param":"angle","to":90,"dur":6}"#,
                #"{"check":{"value":"theta","eq":90}}"#].joined(separator: "\n") + "\n")
        c.endStream()
        XCTAssertEqual(c.session.presented.beat, 1)
        XCTAssertEqual(c.board.transition, .direct)
        XCTAssertEqual(c.board.scene?.values["theta"]?.value, 90)
        XCTAssertEqual(c.session.caption, "The angle is 90°.")
    }

    // Speech, `.speech` pacing: the line with a 2D number is due only when the board has played; paused time waits.
    func testSpeechLineWaitsForTheBoardSpeechPacing() {
        let clock = MGManualClock()
        var s = MGExplainerSession(pacing: .speech, clock: clock)
        var ev = feed(&s, Self.animatedLines) + s.endStream()
        XCTAssertEqual(dueLines(ev), ["Start."], "a line without engine numbers is due at once")
        ev = s.lineEnded(0)
        XCTAssertTrue(dueLines(ev).isEmpty, "not spoken while the board is at another angle")
        XCTAssertEqual(ev.map(\.name).filter { $0 == "beatPresented" }.count, 1)
        clock.advance(by: .seconds(3)); s.pause()
        clock.advance(by: .seconds(30)); XCTAssertTrue(dueLines(s.tick()).isEmpty)
        _ = s.resume()
        clock.advance(by: .milliseconds(2999)); XCTAssertTrue(dueLines(s.tick()).isEmpty)
        clock.advance(by: .milliseconds(1))
        XCTAssertEqual(dueLines(s.tick()), ["The angle is 90°."])
        XCTAssertEqual(s.openLine, 1)
        XCTAssertEqual(dueLines(s.lineEnded(1)), [])
        XCTAssertTrue(s.isComplete || s.nextWake != nil)
    }

    // Speech, `.estimate` pacing: the line's time starts when it is due, so it never ends before it was spoken.
    func testSpeechLineWaitsForTheBoardEstimatePacing() {
        let clock = MGManualClock()
        var s = MGExplainerSession(pacing: .estimate(wordsPerSecond: 100), clock: clock)
        var ev = feed(&s, Self.animatedLines) + s.endStream()
        clock.advance(by: .seconds(1)); ev += s.tick()   // "Start." ends (1 s), beat 2 presents, its line waits
        XCTAssertEqual(dueLines(ev), ["Start."])
        var all = ev
        for _ in 0..<14 { clock.advance(by: .milliseconds(500)); all += s.tick() }
        let names = all.map { e -> String in if case .lineDue(let k, _, _) = e { return "due\(k)" }; if case .lineEnded(let k) = e { return "end\(k)" }; return "" }.filter { !$0.isEmpty }
        XCTAssertEqual(names, ["due0", "end0", "due1", "end1"], "line 2 is due after the 6 s motion, and ends after it")
        XCTAssertEqual(dueLines(all).last, "The angle is 90°.")
    }

    // Speech, `.immediate` pacing and `finishNow`: no motion is played, so the full line is due at once.
    func testSpeechLineImmediateAndFinishNow() {
        var i = MGExplainerSession(pacing: .immediate, clock: MGManualClock())
        let ev = feed(&i, Self.animatedLines) + i.endStream()
        XCTAssertEqual(dueLines(ev), ["Start.", "The angle is 90°."])
        XCTAssertEqual(i.lesson.lastChange?.transition, .direct)
        let clock = MGManualClock()
        var f = MGExplainerSession(pacing: .speech, clock: clock)
        _ = feed(&f, Self.animatedLines); _ = f.endStream()
        XCTAssertTrue(dueLines(f.lineEnded(0)).isEmpty)
        clock.advance(by: .seconds(2))
        let done = f.finishNow()
        XCTAssertEqual(dueLines(done), ["The angle is 90°."])
        XCTAssertEqual(f.lesson.lastChange?.transition, .direct)
        XCTAssertTrue(f.boardSettled)
        // A line the host ended before it was due is dropped, never spoken late.
        var g = MGExplainerSession(pacing: .speech, clock: clock)
        _ = feed(&g, Self.animatedLines); _ = g.endStream(); _ = g.lineEnded(0)
        XCTAssertTrue(dueLines(g.lineEnded(1)).isEmpty)
        clock.advance(by: .seconds(10))
        XCTAssertTrue(dueLines(g.tick()).isEmpty)
    }
}
