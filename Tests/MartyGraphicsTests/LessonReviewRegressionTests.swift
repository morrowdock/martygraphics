// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import MartyGraphics

/// Regressions for the independent review of PR #20 (B1–B2, S1–S10, N1). Inputs are the review's fixtures, inlined.
final class LessonReviewRegressionTests: LessonTestCase {
    typealias F = LessonFixture
    static let scene0 = #"{"scene":{"v":1,"template":"rotate2d","params":{"pts":[[2,1],[4,1],[2,3]],"angle":0}}}"#
    static let bind = #"{"op":"bind","control":{"id":"angle","k":"slider","param":"angle","min":0,"max":360,"step":5,"label":"Angle"}}"#

    func feedLines(_ s: inout MGLessonSession, _ lines: [String]) -> [MGLessonEvent] { lines.flatMap { s.feed($0 + "\n") } }
    func angle(_ s: MGLessonState?) -> Double? { s?.value("theta") }

    // MARK: B1 a refused say changes nothing and the open beat continues

    func testB1RefusedSayLeavesStateAndTheOpenBeatUnchanged() {
        for pacing in [MGPacing.immediate, .speech] {
            var s = F.session(pacing)
            _ = feedLines(&s, [Self.scene0, #"{"say":"Turn."}"#, #"{"op":"params","params":{"angle":90}}"#])
            let state = s.state, projected = s.projected, log = s.log, waiting = s.waitingBeats
            for bad in [#"{"say":3}"#, #"{"say":"A is at .99"}"#, #"{"say":"{zz} moved"}"#, #"{"say":"<b>x</b>"}"#] {
                let events = s.feed(bad + "\n")
                XCTAssertEqual(events.count, 1, bad)
                XCTAssertEqual(F.refusals(events).count, 1, bad)
                XCTAssertEqual(s.state, state, bad); XCTAssertEqual(s.projected, projected, bad)
                XCTAssertEqual(s.log, log, bad); XCTAssertEqual(s.waitingBeats, waiting, bad)
                XCTAssertFalse(s.events.contains { $0.name == "lineQueued" }, bad)
            }
            let next = s.feed(#"{"op":"params","params":{"angle":180}}"# + "\n")
            XCTAssertEqual(F.refusals(next), [], "the next valid command attaches to the still-open beat")
            XCTAssertEqual(angle(s.projected), 180)
            XCTAssertEqual(angle(s.state), 0, "nothing presented yet")
            s.feed(#"{"end":true}"# + "\n")
            XCTAssertEqual(angle(s.state), 180)
            XCTAssertEqual(s.state?.beat, 0)
        }
        // The 25th say is refused without closing beat 24.
        var many = F.session()
        _ = feedLines(&many, [Self.scene0] + (0..<24).map { #"{"say":"Beat \#($0)."}"# })
        let before = (many.state, many.projected, many.waitingBeats)
        XCTAssertEqual(F.refusals(many.feed(#"{"say":"One too many."}"# + "\n")).map(\.reason), ["lesson.beats.count"])
        XCTAssertEqual(many.state, before.0); XCTAssertEqual(many.projected, before.1); XCTAssertEqual(many.waitingBeats, before.2)
        XCTAssertEqual(F.refusals(many.feed(#"{"op":"params","params":{"angle":30}}"# + "\n")), [])
    }

    // MARK: B2 checks hold on the state the learner sees at the end of the beat

    func testB2ALaterCommandCannotFalsifyAnEarlierCheck() {
        var s = F.session()
        let events = feedLines(&s, [Self.scene0, #"{"say":"A has x = 2."}"#, #"{"check":{"value":"ax","eq":2}}"#,
                                    #"{"op":"params","params":{"angle":90}}"#, #"{"end":true}"#])
        let refused = F.refusals(events)
        XCTAssertEqual(refused.map(\.reason), ["check.ax"])
        XCTAssertEqual(refused.first?.statement, 3, "the falsifying command is refused, not the proven claim")
        XCTAssertTrue(events.contains(.lineDue(beat: 0, text: "A has x = 2.", changed: false)))
        XCTAssertEqual(s.state?.value("ax") ?? .nan, 2, accuracy: 1e-9, "what is shown matches the line")

        // Interleaved: a harmless command between checks is kept; one that breaks the second check is refused.
        var t = F.session(.speech)
        let mixed = feedLines(&t, [Self.scene0, #"{"say":"Look at A."}"#, #"{"check":{"value":"ax","eq":2}}"#,
                                   #"{"op":"add","item":{"id":"hiA","k":"highlight","target":"vA"}}"#, #"{"check":{"value":"ay","eq":1}}"#,
                                   #"{"op":"animate","param":"angle","to":45}"#, #"{"end":true}"#])
        XCTAssertEqual(F.refusals(mixed).map(\.reason), ["check.ax"])
        XCTAssertNotNil(t.state?.scene.item("hiA"))
        XCTAssertEqual(angle(t.state), 0)

        // Learner divergence: a check that no longer holds at due time refuses the beat (no line, no presentation).
        var u = F.session(.speech)
        _ = feedLines(&u, [Self.scene0, #"{"say":"Drag."}"#, Self.bind, #"{"say":"A has x = 2."}"#, #"{"check":{"value":"ax","eq":2}}"#, #"{"end":true}"#])
        _ = try? u.control("angle", 90).get()
        let due = u.lineEnded(0)
        XCTAssertEqual(F.refusals(due).map(\.reason), ["check.ax"])
        XCTAssertFalse(due.contains { $0.name == "lineDue" })
        XCTAssertEqual(u.state?.beat, 0)
    }

    // MARK: S1 the input budget counts every byte; one stream's work and events are bounded

    func testS1BudgetCountsWhitespaceOversizedAndGarbageAndBoundsEvents() throws {
        var ws = F.session()
        let e1 = ws.feed(String(repeating: " ", count: 40_000) + Self.scene0 + "\n" + #"{"end":true}"# + "\n")
        XCTAssertEqual(F.refusals(e1).map(\.reason), ["lesson.bytes"])
        XCTAssertNil(ws.state, "the scene after the budget is not accepted")

        var big = F.session()
        let oversized = #"{"say":""# + String(repeating: "x", count: 4190) + #""}"#
        let e2 = big.feed(Array(repeating: oversized, count: 9).joined(separator: "\n") + "\n" + Self.scene0 + "\n")
        XCTAssertEqual(F.refusals(e2).map(\.reason).filter { $0 == "stmt.bytes" }.count, 7)
        XCTAssertEqual(F.refusals(e2).map(\.reason).last, "lesson.bytes")
        XCTAssertNil(big.state)

        var flood = F.session()
        let e3 = flood.feed(String(repeating: "{}", count: 1_000_000))
        XCTAssertEqual(e3.count, MGLessonLimits.statements + 1)
        XCTAssertEqual(F.refusals(e3).last?.reason, "lesson.statements.count")
        XCTAssertLessThanOrEqual(flood.history.count, MGLessonLimits.history)
        // Ending the stream resets the budget for the next stream.
        flood.endStream()
        XCTAssertTrue(flood.feed(Self.scene0 + "\n").contains(.firstPresented))

        XCTAssertEqual(MGLesson.parse(data: Data(repeating: 0x20, count: 70_000)).failureReason, "lesson.bytes")
        XCTAssertEqual(MGLesson.parse(data: Data("{".utf8)).failureReason, "lesson.json")
        // The rotation fixture still fits: a document's size is the size of its statement stream.
        XCTAssertLessThan(try F.lesson().statementStream.utf8.count, MGLessonLimits.lessonBytes)
    }

    // MARK: S2 reasons are single tokens; only animate.frame splits

    func testS2ReasonsAreSingleBoundedTokens() throws {
        let token = try NSRegularExpression(pattern: #"^[A-Za-z0-9_.,]{1,96}$"#)
        func ok(_ r: String) -> Bool { token.firstMatch(in: r, range: NSRange(r.startIndex..., in: r)) != nil }
        var s = try F.through(beat: 3)
        let cases: [(String, String)] = [
            (#"{"op":"unbind","id":"bad key\n"}"#, "control.unknown.bad_key_"),
            (#"{"op":"unbind","id":"bad:tail"}"#, "control.unknown.bad_tail"),
            (#"{"op":"unbind","id":"Ωmega"}"#, "control.unknown._mega"),
            (#"{"op":"unbind","id":"a.b.c"}"#, "control.unknown.a_b_c"),
            (#"{"op":"unbind","id":"\#(String(repeating: "q", count: 80))"}"#, "control.unknown." + String(repeating: "q", count: 32)),
            (#"{"op":"bad op\nx"}"#, "patch.op.bad_op_x"),
        ]
        for (command, reason) in cases {
            guard case .failure(let issue) = s.apply(F.json(command)) else { XCTFail(command); continue }
            XCTAssertEqual(issue.reason, reason, command)
            XCTAssertNil(issue.detail, "a colon in author text is not a wrapper")
            XCTAssertTrue(ok(issue.reason), issue.reason)
        }
        XCTAssertEqual(s.control("a b\n", 1).failureReason, "control.unknown.a_b_")
        XCTAssertEqual(MGLesson.parse(json: F.json(#"{"v":1,"kind":"lesson","scene":{},"beats":[],"x y":1}"#)).failureReason, "lesson.unknown.x_y")
        // The documented wrapper still splits.
        let wrapped = MGLessonSession.issue(MGError("animate.frame:template.pts.radius"))
        XCTAssertEqual(wrapped.reason, "animate.frame"); XCTAssertEqual(wrapped.detail, "template.pts.radius")
        XCTAssertEqual(MGLessonSession.issue(MGError("x:y")).reason, "x_y")
    }

    // MARK: S3 learner refusal order is defined

    func testS3LearnerRefusalOrderIsSortedNotDictionaryOrder() throws {
        let command = F.json(#"{"op":"params","params":{"zz":1,"aa":1,"mm":1}}"#)
        for _ in 0..<20 {
            var s = try F.through(beat: 3)
            XCTAssertEqual(s.apply(command, origin: .learner).failureReason, "control.unknown.aa")
        }
        var t = try F.through(beat: 3)
        XCTAssertEqual(t.apply(F.json(#"{"op":"params","params":{"zz":1,"angle":400}}"#), origin: .learner).failureReason, "control.value",
                       "angle sorts before zz")
    }

    // MARK: S4 two animations in one beat keep their own segments; no chord across the cut

    func testS4SeparateAnimationsNeverBlendAcrossAJump() throws {
        var s = F.session()
        let events = feedLines(&s, [Self.scene0, #"{"say":"Turn twice."}"#, #"{"op":"animate","param":"angle","to":90,"dur":1}"#,
                                    #"{"op":"params","params":{"angle":270}}"#, #"{"op":"animate","param":"angle","to":360,"dur":2}"#, #"{"end":true}"#])
        XCTAssertEqual(F.refusals(events), [])
        guard case .keyframes(let segments)? = s.lastChange?.transition else { return XCTFail("keyframes expected") }
        XCTAssertEqual(segments.map(\.duration), [1, 2], "each animate keeps its own duration")
        XCTAssertEqual(segments.map { $0.frames.count }, [19, 19])
        let plan = MGAdoption.plan(previous: [], next: s.state!.scene.items, transition: s.lastChange!.transition)
        XCTAssertEqual(plan.duration, 3)
        let r = hypot(2.0, 1.0)
        for k in 0...300 {
            let t = Double(k) / 100
            let v = try XCTUnwrap(MGTween.sample(plan.segments, at: t).first { $0.id == "vA" }?.pts.first)
            XCTAssertEqual((v - MGGeometryPack.origin).length, r, accuracy: r * 0.0011, "t = \(t) s")
        }
        let atCut = try XCTUnwrap(MGTween.sample(plan.segments, at: 1.0).first { $0.id == "ltheta" }?.text)
        XCTAssertEqual(atCut, "θ = 270°", "the second segment starts from its own first frame")
    }

    // MARK: S5 control labels cannot freeze an engine number

    func testS5ControlLabelsWithPlaceholdersAreRefused() {
        var s = F.session()
        let events = feedLines(&s, [#"{"scene":{"v":1,"template":"rotate2d","params":{"pts":[[2,1],[4,1],[2,3]],"angle":30}}}"#,
                                    #"{"op":"bind","control":{"id":"angle","k":"slider","param":"angle","min":0,"max":360,"step":5,"label":"A x {ax}"}}"#])
        XCTAssertEqual(F.refusals(events).map(\.reason), ["control.label.placeholder"])
        XCTAssertEqual(s.state?.controls, [])
        _ = s.feed(Self.bind + "\n")
        _ = try? s.control("angle", 90).get()
        XCTAssertEqual(s.state?.control("angle")?.label, "Angle")
    }

    // MARK: S6 snapshots keep the projection of queued beats

    func testS6SnapshotAfterALearnerChangeWithQueuedBeats() throws {
        for withCheck in [false, true] {
            let clock = MGManualClock()
            var s = F.session(.speech, clock: clock)
            var lines = [Self.scene0, #"{"say":"Drag."}"#, Self.bind, #"{"say":"A x {ax}."}"#]
            if withCheck { lines.append(#"{"check":{"value":"ax","eq":2}}"#) }
            _ = feedLines(&s, lines + [#"{"end":true}"#])
            _ = try s.control("angle", 45).get()
            var r = try MGLessonSession.restore(s.snapshot(), pacing: .speech, clock: clock).get()
            XCTAssertEqual(r.projected, s.projected, "check \(withCheck)")
            XCTAssertEqual(r.state, s.state)
            XCTAssertEqual(r.snapshot(), s.snapshot())
            let a = s.lineEnded(0), b = r.lineEnded(0)
            XCTAssertEqual(a, b)
            if withCheck {
                XCTAssertEqual(F.refusals(a).map(\.reason), ["check.ax"], "refused when due, as in the running session")
            } else {
                XCTAssertTrue(a.contains(.lineDue(beat: 1, text: "A x 0.71.", changed: true)), "\(a)")
            }
        }
    }

    // MARK: S7 a second load always reaches the board

    @MainActor func testS7ReloadingShowsTheNewScene() throws {
        let controller = MGLessonController(pacing: .immediate, clock: MGManualClock())
        let first = try MGLesson.parse(json: F.json(#"{"v":1,"kind":"lesson","scene":{"v":1,"template":"rotate2d","params":{"pts":[[2,1],[4,1],[2,3]],"angle":0}},"beats":[{"say":"Look."}]}"#)).get()
        let second = try MGLesson.parse(json: F.json(#"{"v":1,"kind":"lesson","scene":{"v":1,"template":"rotate2d","params":{"pts":[[2,1],[4,1],[2,3]],"angle":90}},"beats":[{"say":"Look."}]}"#)).get()
        XCTAssertTrue(controller.load(first))
        XCTAssertEqual(controller.board.scene?.values["theta"]?.value, 0)
        let firstPresented = controller.timing.firstPresentedAt
        XCTAssertTrue(controller.load(second))
        XCTAssertEqual(controller.board.scene?.values["theta"]?.value, 90)
        XCTAssertEqual(controller.board.scene?.items, controller.state?.scene.items)
        XCTAssertNotNil(firstPresented); XCTAssertNotNil(controller.timing.firstPresentedAt)
    }

    // MARK: S8 pause holds an in-flight animation

    func testS8TransitionClockHoldsAndResumes() throws {
        let t0 = Date(timeIntervalSince1970: 1_000)
        var clock = MGTransitionClock(start: t0)
        clock.pause(at: t0.addingTimeInterval(1))
        XCTAssertEqual(clock.elapsed(at: t0.addingTimeInterval(4)), 1, accuracy: 1e-9)
        clock.resume(at: t0.addingTimeInterval(4))
        XCTAssertEqual(clock.elapsed(at: t0.addingTimeInterval(5)), 2, accuracy: 1e-9)
        // Sampling a 6 s animation while held shows the same frame throughout the pause.
        var s = try F.through(beat: 3)
        let shown = s.state!.scene.items
        _ = try s.apply(F.json(#"{"op":"animate","param":"angle","to":180,"dur":6}"#)).get()
        let plan = MGAdoption.plan(previous: shown, next: s.state!.scene.items, transition: s.lastChange!.transition)
        var held = MGTransitionClock(start: t0)
        held.pause(at: t0.addingTimeInterval(1))
        let a = MGTween.sample(plan.segments, at: held.elapsed(at: t0.addingTimeInterval(2)))
        let b = MGTween.sample(plan.segments, at: held.elapsed(at: t0.addingTimeInterval(9)))
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a.first { $0.id == "vA" }, s.state!.scene.item("vA"), "still mid-turn")
    }

    func testS8PauseExtendsTheSettleTime() throws {
        let clock = MGManualClock()
        var s = F.session(.estimate(wordsPerSecond: 100), clock: clock)
        _ = feedLines(&s, [Self.scene0, #"{"say":"Turn."}"#, #"{"op":"animate","param":"angle","to":180,"dur":6}"#, #"{"end":true}"#])
        clock.advance(by: .seconds(1)); s.tick()
        s.pause()
        clock.advance(by: .seconds(10)); s.tick()
        XCTAssertFalse(s.isComplete)
        s.resume()
        clock.advance(by: .seconds(4)); s.tick()
        XCTAssertFalse(s.isComplete, "5 of 6 s played")
        clock.advance(by: .seconds(1)); s.tick()
        XCTAssertTrue(s.isComplete)
    }

    @MainActor func testS8ControllerHoldsTheBoardWhilePaused() {
        let controller = MGLessonController(pacing: .speech, clock: MGManualClock())
        controller.begin()
        controller.feed([Self.scene0, #"{"say":"Turn."}"#, #"{"op":"animate","param":"angle","to":180,"dur":6}"#, #"{"end":true}"#].joined(separator: "\n") + "\n")
        controller.pause()
        XCTAssertTrue(controller.board.transitionsPaused)
        controller.resume()
        XCTAssertFalse(controller.board.transitionsPaused)
    }

    // MARK: S9 template walkthroughs are flattened in a lesson

    func testS9GeneratedStepsAreDroppedSoStateAndBoardAgree() throws {
        var s = F.session()
        let events = feedLines(&s, [#"{"scene":{"v":1,"template":"bst","params":{"values":[2,1,3],"find":1}}}"#, #"{"say":"Look."}"#,
                                    #"{"op":"set","id":"h1","key":"label","value":"Found."}"#, #"{"end":true}"#])
        XCTAssertEqual(F.refusals(events), [])
        let scene = try XCTUnwrap(s.state?.scene)
        XCTAssertTrue(scene.steps.isEmpty)
        XCTAssertEqual(MGTimeline.items(scene, step: 0), scene.items, "every L3 item is on the board")
        XCTAssertEqual(MGTimeline.items(scene, step: 0).first { $0.id == "h1" }?.label, "Found.")
        // Outside lessons the v1 scene keeps its walkthrough.
        let plain = try MGParser.scene(data: Data(#"{"v":1,"template":"bst","params":{"values":[2,1,3],"find":1}}"#.utf8)).get()
        XCTAssertFalse(plain.steps.isEmpty)
        XCTAssertNil(MGTimeline.items(plain, step: 0).first { $0.id == "h1" })
    }

    // MARK: S10 decimal shorthand and exponents are decimal literals

    func testS10LeadingDotAndExponentLiteralsAreRefused() {
        var s = F.session()
        s.feed(Self.scene0 + "\n")
        for text in ["A x is .99.", "A x is -.99.", "(.5, 1)", "about 2e3", "about 2E-3", "x = 1.5", "turn ...5"] {
            XCTAssertEqual(F.refusals(s.feed(#"{"say":"\#(text)"}"# + "\n")).map(\.reason), ["text.literal"], text)
        }
        for text in ["Step 3. Then turn.", "Turn by 90°.", "The 3rd corner.", "Point v.5 is not a number.", "Use H2e as a name.", "Done."] {
            XCTAssertEqual(F.refusals(s.feed(#"{"say":"\#(text)"}"# + "\n")), [], text)
        }
        XCTAssertEqual(F.refusals(s.feed(#"{"op":"set","id":"lA","key":"text","value":"A at .5"}"# + "\n")).map(\.reason), ["text.literal"])
        var h = F.session()
        XCTAssertEqual(F.refusals(h.feed(#"{"lesson":{"v":1,"title":".5 turns"}}"# + "\n")).map(\.reason), ["text.literal"])
    }

    // MARK: N1 one header per stream

    func testN1ASecondHeaderIsOutOfOrder() {
        var s = F.session()
        let events = feedLines(&s, [#"{"lesson":{"v":1,"title":"One"}}"#, #"{"lesson":{"v":1,"title":"Two"}}"#, Self.scene0])
        XCTAssertEqual(F.refusals(events).map(\.reason), ["stmt.order"])
        XCTAssertEqual(s.title, "One")
        XCTAssertNotNil(s.state)
    }
}
