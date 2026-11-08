// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import MartyGraphics

/// Regression tests for the PR #32 re-check (R1–R3): nothing false may be shown to the learner, also while the board
/// animates and after a restore.
final class ExplainerRecheckTests: ExplainerTestCase {
    static let bind = #"{"op":"bind","control":{"id":"slider","k":"slider","param":"angle","min":0,"max":360,"step":5,"label":"Angle"}}"#

    func animated(_ pacing: MGPacing, clock: MGManualClock) -> MGExplainerSession {
        var s = MGExplainerSession(pacing: pacing, clock: clock)
        _ = s.feed([XFix.header(), #"{"board":\#(XFix.rotate)}"#, #"{"say":"Start."}"#, #"{"say":"The angle is {theta}."}"#,
                    #"{"op":"animate","param":"angle","to":90,"dur":6}"#, #"{"check":{"value":"theta","eq":90}}"#].joined(separator: "\n") + "\n")
        _ = s.endStream()
        return s
    }

    // R1: while the beat animates, the caption shows no 2D number and its 2D check is pending; both appear when the
    // board has played to the state they describe. Paused time does not count.
    func testR1AnimatedBeatWaitsForTheBoard() {
        let clock = MGManualClock()
        var s = animated(.speech, clock: clock)
        XCTAssertEqual(s.caption, "Start.")
        _ = s.lineEnded(0)
        XCTAssertEqual(s.presented.beat, 1)
        XCTAssertFalse(s.boardSettled)
        XCTAssertEqual(s.motionRemaining, .seconds(6))
        XCTAssertEqual(s.caption, "The angle is ….", "no number the board does not show yet")
        XCTAssertEqual(s.pendingClaims, ["beat.2", "beat.2.check.1"])
        XCTAssertFalse(s.claims.contains { $0.id.hasPrefix("beat.2") }, "not Checked while the board is at another angle")
        XCTAssertEqual(s.nextWake, clock.now + .seconds(6), "the host is woken when the numbers can show")
        clock.advance(by: .seconds(3)); _ = s.tick()
        XCTAssertEqual(s.caption, "The angle is ….")
        s.pause()
        clock.advance(by: .seconds(20)); _ = s.tick()
        XCTAssertEqual(s.motionRemaining, .seconds(3), "paused: the board holds, and so does the caption")
        XCTAssertEqual(s.caption, "The angle is ….")
        _ = s.resume()
        clock.advance(by: .milliseconds(2999)); _ = s.tick()
        XCTAssertFalse(s.boardSettled)
        clock.advance(by: .milliseconds(1)); _ = s.tick()
        XCTAssertTrue(s.boardSettled)
        XCTAssertEqual(s.caption, "The angle is 90°.")
        XCTAssertTrue(s.pendingClaims.isEmpty)
        XCTAssertTrue(s.claims.contains { $0.id == "beat.2.check.1" && $0.badge == "Checked" })
    }

    // R1: `.immediate` pacing and `finishNow` play no motion; a 3D-fact caption during a spin shows its numbers (3D
    // facts hold at every pose).
    func testR1NoMotionAndSpinCaptions() throws {
        let immediate = animated(.immediate, clock: MGManualClock())
        XCTAssertTrue(immediate.boardSettled)
        XCTAssertEqual(immediate.caption, "The angle is 90°.")
        var finish = animated(.speech, clock: MGManualClock())
        _ = finish.lineEnded(0)
        XCTAssertFalse(finish.boardSettled)
        _ = finish.finishNow()
        XCTAssertTrue(finish.boardSettled)
        XCTAssertEqual(finish.caption, "The angle is 90°.")
        var spin = MGExplainerSession(pacing: .speech, clock: MGManualClock())
        _ = spin.feed(try MGExplainer.parse(data: Data(try XFix.example("gears-3d").utf8)).get().statementStream)
        _ = spin.endStream(); _ = spin.lineEnded(0)
        XCTAssertEqual(spin.caption, "The big gear turns 1/2 of a turn, the other way.")
        XCTAssertTrue(spin.pendingClaims.isEmpty)
    }

    func boundSession() -> MGExplainerSession {
        var s = MGExplainerSession(pacing: .speech, clock: MGManualClock())
        _ = s.feed([XFix.header(), #"{"board":\#(XFix.rotate)}"#, Self.bind, #"{"say":"Angle {theta}."}"#,
                    #"{"say":"Still {theta}."}"#].joined(separator: "\n") + "\n")
        _ = s.endStream()
        return s
    }
    func lesson(_ o: [String: MGJSON]) -> [String: MGJSON] { guard case .string(let t)? = o["lesson"] else { return [:] }; return XFix.json(t).objectValue! }
    func withLesson(_ o: [String: MGJSON], _ edit: (inout [String: MGJSON]) -> Void) -> MGJSON {
        var o = o, l = lesson(o); edit(&l); o["lesson"] = .string(MGJSON.object(l).canonicalString); return .object(o)
    }
    func forgedLabel(_ scene: inout [String: MGJSON]) {
        guard case .array(var cs)? = scene["controls"], var c = cs.first?.objectValue else { return XCTFail("controls") }
        c["label"] = .string("Correct angle: 999°"); cs[0] = .object(c); scene["controls"] = .array(cs)
    }

    // R2: a saved control label is never trusted: it must be one a checked `bind` made.
    func testR2RestoreRefusesForgedControlLabels() throws {
        let s = boundSession()
        let clean = s.snapshot().objectValue!
        XCTAssertNotNil(clean["lesson"].flatMap { _ in lesson(clean)["baseline"] }, "beat 2 waits, so the lesson holds a baseline")
        guard case .success = MGExplainerSession.restore(.object(clean), pacing: .speech) else { return XCTFail("clean") }
        XCTAssertEqual(MGExplainerSession.restore(withLesson(clean) { forgedLabel(&$0) }, pacing: .speech).failureIssue?.reason, "snapshot.controls")
        XCTAssertEqual(MGExplainerSession.restore(withLesson(clean) { l in
            guard var b = l["baseline"]?.objectValue else { return }
            forgedLabel(&b); l["baseline"] = .object(b)
        }, pacing: .speech).failureIssue?.reason, "snapshot.controls")
        // A control the host bound restores (it is recorded with its checked command); a forged host bind does not.
        var h = boundSession()
        let hostBind = XFix.json(#"{"op":"bind","control":{"id":"knob","k":"slider","param":"angle","min":0,"max":90,"step":5,"label":"Knob"}}"#)
        XCTAssertNotNil(try? h.apply([hostBind]).get())
        let snap = h.snapshot().objectValue!
        guard case .success(let r) = MGExplainerSession.restore(.object(snap), pacing: .speech) else { return XCTFail("host bind") }
        XCTAssertEqual(r.state?.controls.map(\.label), ["Angle", "Knob"])
        var forged = snap
        forged["hostBinds"] = .array([.string(#"{"control":{"id":"knob","k":"slider","label":"Knob 999","max":90,"min":0,"param":"angle","step":5},"op":"bind"}"#)])
        XCTAssertEqual(MGExplainerSession.restore(.object(forged), pacing: .speech).failureIssue?.reason, "text.number.control.knob")
    }

    // R3: a saved check that is not a check is refused; the legend after a restore equals a fresh run's legend.
    func testR3RestoreRefusesMalformedChecksAndKeepsTheLegend() throws {
        var fresh = MGExplainerSession(pacing: .speech, clock: MGManualClock())
        _ = try fresh.load(MGExplainer.parse(data: Data(try XFix.example("gears-mixed").utf8)).get()).get()
        let clean = fresh.snapshot().objectValue!
        func with(_ specs: [String]) -> MGJSON {
            var o = clean
            var beats = o["beats"]!.arrayValue!
            var b0 = beats[0].objectValue!
            b0["checkSpecs"] = .array(specs.map { .string($0) })
            beats[0] = .object(b0); o["beats"] = .array(beats)
            return .object(o)
        }
        for (specs, reason) in [(["null"], "check.object"), (Array(repeating: "null", count: 8), "check.object"), (["3"], "check.object"),
                                ([#"{"eq":1}"#], "check.missing"), ([#"{"value":7,"eq":1}"#], "check.value"),
                                ([#"{"value":"p.teeth","eq":15,"x":1}"#], "check.unknown.x")] {
            XCTAssertEqual(MGExplainerSession.restore(with(specs), pacing: .speech).failureIssue?.reason, reason, "\(specs)")
        }
        // The legend comes only from claims and checks the restore evaluated: equal to the fresh run.
        guard case .success(let r) = MGExplainerSession.restore(.object(clean), pacing: .speech) else { return XCTFail("clean") }
        XCTAssertEqual(r.legend, fresh.legend)
        // At beat 1 (beat 2 still waits): 2 motion claims, the table, beat 1's caption; beat 2's caption and check
        // count once beat 2 is presented (presented-only legend).
        XCTAssertEqual(r.legend.text, "Solved 4")
        let bound = boundSession()
        guard case .success(let rb) = MGExplainerSession.restore(bound.snapshot(), pacing: .speech) else { return XCTFail("bound") }
        XCTAssertEqual(rb.legend, bound.legend)
        XCTAssertEqual(rb.claims, bound.claims)
        // A saved highlight over its limit is refused too.
        var o = clean
        var beats = o["beats"]!.arrayValue!
        var b0 = beats[0].objectValue!
        b0["highlight"] = .array(Array(repeating: .string("p"), count: 17))
        beats[0] = .object(b0); o["beats"] = .array(beats)
        XCTAssertEqual(MGExplainerSession.restore(.object(o), pacing: .speech).failureIssue?.reason, "beat.highlight.count")
    }

    // R1 in the SwiftUI host: the caption it shows waits for the board, and appears when the board has played.
    @MainActor func testR1HostCaptionWaitsForTheBoard() throws {
        let clock = MGManualClock()
        let c = MGExplainerController(pacing: .speech, clock: clock)
        c.begin()
        let doc = XFix.doc(board: XFix.rotate, beats: #"[{"say":"The angle is {theta}.","ops":[{"op":"animate","param":"angle","to":90,"dur":2}],"check":[{"value":"theta","eq":90}]}]"#)
        XCTAssertTrue(c.load(try MGExplainer.parse(data: Data(doc.utf8)).get()))
        XCTAssertEqual(c.session.caption, "The angle is ….")
        XCTAssertEqual(c.board.transition.keyframeDuration, 2, accuracy: 1e-9)
        clock.advance(by: .seconds(2))
        c.next()   // any host call re-reads the session; the controller's own timer does the same at `nextWake`
        XCTAssertEqual(c.session.caption, "The angle is 90°.")
    }
}
