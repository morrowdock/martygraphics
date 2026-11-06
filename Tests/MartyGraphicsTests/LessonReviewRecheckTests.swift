// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import MartyGraphics

/// Regressions for the second independent review of PR #20 (R1–R8), adapted from its proposed
/// `AdversarialReviewFixtures.swift`. The review's fixture files are inlined byte for byte (or generated to the same
/// bytes), so the tests do not depend on files outside the repository.
final class LessonReviewRecheckTests: LessonTestCase {
    typealias F = LessonFixture
    let scene = #"{"scene":{"v":1,"template":"rotate2d","params":{"pts":[[2,1],[4,1],[2,3]],"angle":0}}}"#
    let bind = #"{"op":"bind","control":{"id":"angle","k":"slider","param":"angle","min":0,"max":360,"step":5,"label":"Angle"}}"#
    func reasons(_ events: [MGLessonEvent]) -> [String] { F.refusals(events).map(\.reason) }
    func lines(_ l: [String]) -> String { l.joined(separator: "\n") + "\n" }

    // MARK: R1 refused input after a finished lesson keeps playback finished

    func testR1RefusedFollowupPreservesCompletedPlayback() throws {
        for tail in ["{\"say\":3}\n", "model chatter after the end", "{\"op\":\"remove\",\"id\":\"vA\"}\n"] {
            var s = MGLessonSession(pacing: .immediate, clock: MGManualClock())
            s.feed(lines([scene, #"{"say":"Look."}"#, #"{"end":true}"#]))
            XCTAssertTrue(s.isComplete)
            let before = s.state, projected = s.projected, caption = s.caption, change = s.lastChange, log = s.log
            let events = s.feed(tail) + s.endStream()
            XCTAssertEqual(reasons(events), [tail.hasPrefix("{\"say") ? "stmt.order" : tail.hasPrefix("{") ? "stmt.order" : "stmt.json"], tail)
            XCTAssertTrue(s.isComplete, "a refused follow-up must not reopen completed playback: \(tail)")
            XCTAssertFalse(events.contains(.lessonComplete), "completion is not reported twice")
            XCTAssertEqual(s.state, before); XCTAssertEqual(s.projected, projected)
            XCTAssertEqual(s.caption, caption); XCTAssertEqual(s.lastChange, change); XCTAssertEqual(s.log, log)
        }
        // finishNow's fast-forward also survives a refused follow-up, and an accepted `keep` reopens playback.
        var s = MGLessonSession(pacing: .speech, clock: MGManualClock())
        s.feed(try F.stream())
        s.finishNow()
        XCTAssertTrue(s.isComplete)
        s.feed("{\"say\":3}\n")
        XCTAssertTrue(s.isComplete)
        s.feed(lines([#"{"keep":true}"#]))
        XCTAssertFalse(s.isComplete)
        s.feed(lines([#"{"say":"Again."}"#, #"{"end":true}"#]))
        XCTAssertFalse(s.isComplete, "fast-forward ended with the old stream; speech pacing waits for the line")
        XCTAssertEqual(s.openLine, 5)
    }

    // MARK: R2 a due-time refusal of the last beat keeps projected == state

    func testR2FinalDueTimeRefusalSynchronizesProjectionAndRestore() throws {
        let clock = MGManualClock()
        var s = MGLessonSession(pacing: .speech, clock: clock)
        s.feed(lines([scene, #"{"say":"Drag."}"#, bind, #"{"say":"A has x = 2."}"#, #"{"check":{"value":"ax","eq":2}}"#, #"{"end":true}"#]))
        _ = try s.control("angle", 90).get()
        let events = s.lineEnded(0)
        XCTAssertEqual(reasons(events), ["check.ax"])
        XCTAssertFalse(events.contains { $0.name == "lineDue" })
        XCTAssertEqual(s.waitingBeats, 0)
        XCTAssertEqual(s.projected, s.state, "no waiting beat means the projection is the presented state")
        XCTAssertEqual(s.projected?.value("theta"), 90)
        let restored = try MGLessonSession.restore(s.snapshot(), pacing: .speech, clock: clock).get()
        XCTAssertEqual(restored.projected, s.projected)
        XCTAssertEqual(restored.snapshot(), s.snapshot())
        // A refused (check-failed) beat that is the last one also leaves the projection on the shown state.
        var t = MGLessonSession(pacing: .immediate, clock: clock)
        t.feed(lines([scene, #"{"say":"Turn."}"#, #"{"op":"params","params":{"angle":90}}"#, #"{"say":"Wrong."}"#, #"{"check":{"value":"ax","eq":5}}"#, #"{"end":true}"#]))
        XCTAssertEqual(t.projected, t.state)
    }

    // MARK: R3 set-up animations settle before completion

    func testR3SetupAnimationMustSettleBeforeCompletion() throws {
        let clock = MGManualClock()
        var s = MGLessonSession(pacing: .speech, clock: clock)
        let events = s.feed(lines([scene, #"{"op":"animate","param":"angle","to":90,"dur":6}"#, #"{"end":true}"#]))
        XCTAssertEqual(reasons(events), [])
        XCTAssertEqual(s.lastChange?.transition.keyframeDuration, 6)
        XCTAssertFalse(s.isComplete)
        XCTAssertFalse(events.contains(.lessonComplete))
        XCTAssertEqual(s.nextWake, .seconds(6))
        clock.advance(by: .seconds(5)); s.tick(); XCTAssertFalse(s.isComplete)
        clock.advance(by: .seconds(1)); XCTAssertEqual(s.tick(), [.lessonComplete])
        // Paused while the set-up turn plays: the remaining time continues after resume.
        let c2 = MGManualClock()
        var p = MGLessonSession(pacing: .speech, clock: c2)
        p.feed(lines([scene, #"{"op":"animate","param":"angle","to":90,"dur":6}"#]))
        c2.advance(by: .seconds(2)); p.pause()
        p.feed(lines([#"{"end":true}"#]))
        c2.advance(by: .seconds(30)); p.tick(); XCTAssertFalse(p.isComplete)
        p.resume()
        c2.advance(by: .seconds(3)); p.tick(); XCTAssertFalse(p.isComplete)
        c2.advance(by: .seconds(1)); p.tick(); XCTAssertTrue(p.isComplete)
        // A replacement scene does not inherit the old deadline.
        var r = MGLessonSession(pacing: .speech, clock: c2)
        r.feed(lines([scene, #"{"op":"animate","param":"angle","to":90,"dur":6}"#, #"{"end":true}"#]))
        r.feed(lines([scene, #"{"end":true}"#]))
        XCTAssertTrue(r.isComplete)
    }

    // MARK: R4 trailing-point exponents are decimal literals

    func testR4TrailingPointExponentAndNarrationFalsePositives() {
        var s = MGLessonSession()
        s.feed(scene + "\n")
        for text in ["A x = 2.e3.", "A x = 2.e-3.", "A x = 2.E+3.", "A x = .2e3.", "A x = +.5.", "A x = \u{2212}.5."] {
            XCTAssertEqual(reasons(s.feed("{\"say\":\"" + text + "\"}\n")), ["text.literal"], text)
        }
        for text in ["Step 3. Then turn.", "Turn by 90°.", "Use v2e3 as a name.", "Ends at 3.", "Version v2.e3 is a name."] {
            XCTAssertEqual(reasons(s.feed("{\"say\":\"" + text + "\"}\n")), [], text)
        }
    }

    // MARK: R5 an invalid keyframe step is refused, never a trap

    func testR5InvalidStepIsRefused() throws {
        var s = MGLessonSession()
        s.feed(scene + "\n")
        let start = try XCTUnwrap(s.state?.scene)
        for step: Double in [0, -5, .nan, .infinity, -.infinity] {
            guard case .failure(let e) = MGTween.keyframes(start, param: "angle", to: 0, maxStep: step) else { XCTFail("step \(step)"); continue }
            XCTAssertEqual(e.reason, "animate.step")
        }
        XCTAssertEqual(try MGTween.keyframes(start, param: "angle", to: 0, maxStep: 1e-9).get().count, 1)
        guard case .failure(let tiny) = MGTween.keyframes(start, param: "angle", to: 1, maxStep: 1e-9) else { return XCTFail("tiny step") }
        XCTAssertEqual(tiny.reason, "animate.to", "a tiny step can never exceed the keyframe bound")
        XCTAssertLessThanOrEqual(try MGTween.keyframes(start, param: "angle", to: 1, maxStep: 1.0 / 72).get().count, MGTween.maxFrames)
    }

    // MARK: R6 a refused controller load keeps a streamed lesson

    @MainActor func testR6FailedLoadAfterFeedPreservesExistingLesson() throws {
        let controller = MGLessonController(pacing: .immediate, clock: MGManualClock())
        controller.feed(scene + "\n")
        let before = controller.state, board = controller.board.scene, timing = controller.timing, caption = controller.caption
        let invalid = try MGLesson.parse(data: Data(#"{"v":1,"kind":"lesson","scene":{"v":1,"template":"rotate2d","params":{"pts":[[2,1],[4,1],[2,3]],"angle":0}},"beats":[{"say":"Look.","ops":[{"op":"params","params":{"angle":400}}]}]}"#.utf8)).get()
        XCTAssertFalse(controller.load(invalid))
        XCTAssertEqual(controller.lastIssue?.reason, "template.angle")
        XCTAssertEqual(controller.state, before)
        XCTAssertNotNil(controller.board.scene)
        XCTAssertEqual(controller.board.scene, board)
        XCTAssertEqual(controller.timing, timing)
        XCTAssertEqual(controller.caption, caption)
        // A valid load afterwards still replaces the lesson and starts its own timing.
        XCTAssertTrue(controller.load(try F.lesson()))
        XCTAssertNotNil(controller.timing.requestAt)
        XCTAssertNil(controller.lastIssue)
    }

    // MARK: R7 lesson-owned unknown keys become author segments

    func testR7UnknownLessonKeysAreSegments() throws {
        var s = MGLessonSession()
        let events = s.feed(lines([scene, #"{"say":"Look."}"#, #"{"check":{"value":"ax","eq":2,"a.b:c Ω":0}}"#, #"{"end":true}"#]))
        XCTAssertEqual(reasons(events), ["check.unknown.a_b_c__"])
        let long = String(repeating: "k", count: 80)
        XCTAssertEqual(reasons(s.feed(#"{"keep":true}"# + "\n" + #"{"say":"More."}"# + "\n" + #"{"check":{"value":"ax","eq":2,"\#(long)":1}}"# + "\n")),
                       ["check.unknown." + String(repeating: "k", count: 32)])
        XCTAssertEqual(reasons(s.feed(#"{"op":"bind","control":{"id":"b","k":"slider","param":"px","min":-1,"max":1,"step":1,"label":"P","x.y":1}}"# + "\n")),
                       ["control.unknown.x_y"])
        var h = MGLessonSession()
        XCTAssertEqual(reasons(h.feed(#"{"lesson":{"v":1,"t.i":1}}"# + "\n")), ["lesson.unknown.t_i"])
        XCTAssertEqual(MGLesson.parse(json: F.json(#"{"v":1,"kind":"lesson","scene":{"v":1},"beats":[{"say":"a","x.y":1}]}"#)).failureReason, "beat.unknown.x_y")
    }

    // MARK: R8 snapshot boundary for a partially received statement

    func testR8UnfinishedInputIsReplayedAfterRestore() throws {
        let clock = MGManualClock()
        var s = MGLessonSession(pacing: .speech, clock: clock)
        s.feed(scene + "\n" + #"{"say":"Tu"#)
        XCTAssertEqual(String(decoding: s.unfinishedInput, as: UTF8.self), #"{"say":"Tu"#)
        var r = try MGLessonSession.restore(s.snapshot(), pacing: .speech, clock: clock).get()
        XCTAssertTrue(r.unfinishedInput.isEmpty, "a snapshot covers complete statements only")
        let suffix = "rn.\"}\n{\"end\":true}\n"
        let replay = r.feed(s.unfinishedInput) + r.feed(suffix)
        let original = s.feed(suffix)
        XCTAssertEqual(replay, original)
        XCTAssertTrue(original.contains(.lineDue(beat: 0, text: "Turn.", changed: false)))
        XCTAssertEqual(r.state, s.state)
        XCTAssertEqual(r.snapshot(), s.snapshot(), "byte budget equal after the replay")
    }

    // MARK: further adversarial positives from the review

    func testCheckSurvivesBindAndRefusesAnimateWithoutMutatingState() {
        var s = MGLessonSession()
        let events = s.feed(lines([scene, #"{"say":"Check then bind."}"#, #"{"check":{"value":"ax","eq":2}}"#, bind,
                                   #"{"op":"animate","param":"angle","to":90,"dur":1}"#, #"{"op":"params","params":{"angle":180}}"#,
                                   #"{"op":"unbind","id":"angle"}"#, #"{"end":true}"#]))
        XCTAssertEqual(reasons(events), ["check.ax", "check.ax"])
        XCTAssertEqual(s.state?.value("theta"), 0)
        XCTAssertTrue(s.state?.controls.isEmpty == true)
    }

    func testUnicodeReasonsTinyStatementsAndDeepNesting() {
        var s = MGLessonSession()
        let omega = String(repeating: "\\u03a9", count: 200)
        let events = s.feed(lines([scene, #"{"op":"unbind","id":"bad key\n"}"#, #"{"op":"unbind","id":"bad:tail"}"#, #"{"op":"unbind","id":"a.b.c"}"#,
                                   #"{"op":"unbind","id":"😀‍🔥  \u0000"}"#, #"{"op":"unbind","id":"é"}"#,
                                   #"{"op":"unbind","id":""# + omega + #""}"#, #"{"end":true}"#]))
        XCTAssertEqual(reasons(events).count, 6)
        for reason in reasons(events) {
            XCTAssertLessThanOrEqual(reason.utf8.count, 96)
            XCTAssertTrue(reason.unicodeScalars.allSatisfy { $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "_" || $0 == "." || $0 == ",") }, reason)
        }
        XCTAssertEqual(reasons(events).last, "control.unknown." + String(repeating: "_", count: 32))
        var many = MGLessonSession()
        let tiny = many.feed(String(repeating: "{}\n", count: 300))
        XCTAssertEqual(tiny.count, 257)
        XCTAssertEqual(reasons(tiny).last, "lesson.statements.count")
        var deep = MGLessonSession()
        let nested = deep.feed(String(repeating: "[", count: 1900) + String(repeating: "]", count: 1900) + "\n" + scene + "\n" + #"{"end":true}"# + "\n")
        XCTAssertTrue(["stmt.json", "stmt.kind"].contains(reasons(nested).first ?? ""), "\(reasons(nested))")
        XCTAssertEqual(reasons(nested).count, 1)
        XCTAssertNotNil(deep.state, "the scene after the nested value is still scanned")
    }

    func testPausedRestoreKeepsRemainingAnimationAndEventOrder() throws {
        let clock = MGManualClock()
        var s = MGLessonSession(pacing: .estimate(wordsPerSecond: 100), clock: clock)
        s.feed(lines([scene, #"{"say":"Turn."}"#, #"{"op":"animate","param":"angle","to":180,"dur":6}"#, #"{"end":true}"#]))
        clock.advance(by: .seconds(1)); s.tick(); s.pause()
        clock.advance(by: .seconds(20))
        var r = try MGLessonSession.restore(s.snapshot(), pacing: .estimate(wordsPerSecond: 100), clock: clock).get()
        XCTAssertEqual(r.snapshot(), s.snapshot())
        XCTAssertEqual(r.resume(), s.resume())
        clock.advance(by: .seconds(4)); XCTAssertEqual(r.tick(), s.tick()); XCTAssertFalse(r.isComplete)
        clock.advance(by: .seconds(1)); XCTAssertEqual(r.tick(), s.tick()); XCTAssertTrue(r.isComplete)
    }

    // MARK: exact replay of the first review's fixture files (inlined / generated to the same bytes)

    func testExactEarlierReviewFixtures() throws {
        let whitespace = String(repeating: " ", count: 40_000) + scene + "\n" + #"{"end":true}"# + "\n"
        let oversized = #"{"say":""# + String(repeating: "x", count: 4100) + #""}"# + "\n" + scene + "\n"
        XCTAssertEqual(whitespace.utf8.count, 40_100); XCTAssertEqual(oversized.utf8.count, 4198)
        let cases: [(String, String, [String], Double?)] = [
            ("invalid-say", lines([scene, #"{"say":"Turn."}"#, #"{"op":"params","params":{"angle":90}}"#, #"{"say":3}"#, #"{"op":"params","params":{"angle":180}}"#, #"{"end":true}"#]), ["stmt.say"], 180),
            ("false-final-check", lines([scene, #"{"say":"A has x = 2."}"#, #"{"check":{"value":"ax","eq":2}}"#, #"{"op":"params","params":{"angle":90}}"#, #"{"end":true}"#]), ["check.ax"], 0),
            ("whitespace-over-budget", whitespace, ["lesson.bytes"], nil),
            ("oversized-then-scene", oversized, ["stmt.bytes"], 0),
            ("unsafe-reason", lines([scene, #"{"op":"unbind","id":"bad key\n"}"#, #"{"end":true}"#]), ["control.unknown.bad_key_"], 0),
            ("wide-keyframe-seam", lines([scene, #"{"say":"Turn twice."}"#, #"{"op":"animate","param":"angle","to":90,"dur":1}"#, #"{"op":"params","params":{"angle":270}}"#, #"{"op":"animate","param":"angle","to":360,"dur":1}"#, #"{"end":true}"#]), [], 360),
            ("stale-control-label", lines([#"{"scene":{"v":1,"template":"rotate2d","params":{"pts":[[2,1],[4,1],[2,3]],"angle":30}}}"#, #"{"op":"bind","control":{"id":"angle","k":"slider","param":"angle","min":0,"max":360,"step":5,"label":"A x {ax}"}}"#, #"{"end":true}"#]), ["control.label.placeholder"], 30),
            ("decimal-shorthand", lines([scene, #"{"say":"A x is .99."}"#, #"{"end":true}"#]), ["text.literal"], 0),
        ]
        for (name, text, expected, angle) in cases {
            var s = MGLessonSession()
            XCTAssertEqual(reasons(s.feed(text)), expected, name)
            XCTAssertEqual(s.state?.value("theta"), angle, name)
            if name == "wide-keyframe-seam" {
                guard case .keyframes(let segments)? = s.lastChange?.transition else { XCTFail(name); continue }
                XCTAssertEqual(segments.map(\.duration), [1, 1])
            }
        }
        var bst = MGLessonSession()
        XCTAssertEqual(reasons(bst.feed(lines([#"{"scene":{"v":1,"template":"bst","params":{"values":[2,1,3],"find":1}}}"#, #"{"say":"Look."}"#, #"{"op":"set","id":"h1","key":"label","value":"Found."}"#, #"{"end":true}"#]))), [])
        XCTAssertTrue(bst.state?.scene.steps.isEmpty == true)
        XCTAssertEqual(bst.state?.scene.item("h1")?.label, "Found.")
        var big = MGLessonSession()
        let first = oversized.split(separator: "\n").map(String.init)
        XCTAssertEqual(reasons(big.feed(Array(repeating: first[0], count: 9).joined(separator: "\n") + "\n" + first[1] + "\n")).last, "lesson.bytes")
        XCTAssertNil(big.state)
        var learner = MGLessonSession()
        learner.feed(scene + "\n")
        XCTAssertEqual(learner.apply(F.json(#"{"op":"params","params":{"zz":1,"aa":1}}"#), origin: .learner).failureReason, "control.unknown.aa")
    }

    @MainActor func testExactEarlierReloadDocuments() throws {
        let controller = MGLessonController(pacing: .immediate, clock: MGManualClock())
        for (json, expected) in [(#"{"v":1,"kind":"lesson","scene":{"v":1,"template":"rotate2d","params":{"pts":[[2,1],[4,1],[2,3]],"angle":0}},"beats":[{"say":"Look."}]}"#, 0.0),
                                 (#"{"v":1,"kind":"lesson","scene":{"v":1,"template":"rotate2d","params":{"pts":[[2,1],[4,1],[2,3]],"angle":90}},"beats":[{"say":"Look."}]}"#, 90.0)] {
            XCTAssertTrue(controller.load(try MGLesson.parse(data: Data(json.utf8)).get()))
            XCTAssertEqual(controller.board.scene?.values["theta"]?.value, expected)
        }
    }
}
