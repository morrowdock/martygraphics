// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import MartyGraphics

/// `MGLessonController.restore(_:)`: a saved lesson state is validated first, a refusal changes nothing but
/// `lastIssue`, and a success shows the board as it was (no blend, no keyframes, no draw-on) with honest timing marks.
@MainActor
final class LessonControllerRestoreTests: LessonTestCase {
    typealias F = LessonFixture
    let scene = #"{"scene":{"v":1,"template":"rotate2d","params":{"pts":[[2,1],[4,1],[2,3]],"angle":0}}}"#
    let bind = #"{"op":"bind","control":{"id":"angle","k":"slider","param":"angle","min":0,"max":360,"step":5,"label":"Angle"}}"#
    func lines(_ l: [String]) -> String { l.joined(separator: "\n") + "\n" }

    /// A copy of a snapshot object with one key replaced (nil removes it).
    func with(_ j: MGJSON, _ key: String, _ value: MGJSON?) -> MGJSON {
        var o = j.objectValue!; o[key] = value; return .object(o)
    }
    func deep(_ levels: Int) -> MGJSON { var v = MGJSON.number(0); for _ in 0..<levels { v = .array([v]) }; return v }

    /// Everything a refused restore must leave alone.
    struct Observed: Equatable {
        let state: MGLessonState?, caption: String?, snapshot: MGJSON, history: Int, nextWake: Duration?
        let board: MGScene?, boardRevision: Int, transition: MGTransition, drawsOn: Bool, held: Bool
        let timing: MGLessonTiming, selection: String?, paused: Bool
    }
    func observe(_ c: MGLessonController) -> Observed {
        Observed(state: c.state, caption: c.caption, snapshot: c.session.snapshot(), history: c.session.history.count,
                 nextWake: c.session.nextWake, board: c.board.scene, boardRevision: c.board.revision,
                 transition: c.board.transition, drawsOn: c.board.drawsOn, held: c.board.transitionsPaused,
                 timing: c.timing, selection: c.selection, paused: c.session.isPaused)
    }

    // MARK: success

    func testRestoreShowsTheSavedLessonDirectlyAndClearsSelection() throws {
        let clock = MGManualClock()
        let source = MGLessonController(pacing: .immediate, clock: clock)
        source.begin(); source.feed(try F.stream())
        XCTAssertTrue(source.session.isComplete)
        let saved = source.session.snapshot()

        let c = MGLessonController(pacing: .immediate, clock: clock)
        c.begin(); c.feed(lines([scene, #"{"say":"Other."}"#, #"{"op":"params","params":{"angle":45}}"#, #"{"end":true}"#]))
        c.selection = "vA"
        XCTAssertFalse(c.apply(F.json(#"{"op":"remove","id":"nope"}"#)))
        XCTAssertNotNil(c.lastIssue)
        let shownBefore = c.board.scene!.items
        var events: [MGLessonEvent] = []
        c.onEvent = { events.append($0) }

        XCTAssertNoThrow(try c.restore(saved).get())
        XCTAssertEqual(c.state, source.state)
        XCTAssertEqual(c.state?.value("theta"), 180)
        XCTAssertEqual(c.caption, source.caption)
        XCTAssertEqual(c.controls.map(\.id), ["angle"])
        XCTAssertEqual(saved["settleLeft"], .number(1.5), "the last animate had not settled when saved")
        XCTAssertEqual(c.session.snapshot(), with(saved, "settleLeft", .number(0)), "the same lesson, with nothing left to settle")
        XCTAssertNil(c.selection)
        XCTAssertNil(c.lastIssue)
        XCTAssertEqual(events, [], "a complete lesson has nothing due at once; the restore itself emits nothing")
        // The board shows the restored state as it is: no blend, no keyframes and no draw-on, also on a first appearance.
        XCTAssertEqual(c.board.scene?.items, c.state?.scene.items)
        XCTAssertEqual(c.board.transition, .direct)
        XCTAssertFalse(c.board.drawsOn)
        for previous in [shownBefore, nil] {
            let plan = MGAdoption.plan(previous: previous, next: c.board.scene!.items, transition: c.board.transition, drawsOn: c.board.drawsOn)
            XCTAssertFalse(plan.blends); XCTAssertEqual(plan.appear, [:]); XCTAssertTrue(plan.segments.isEmpty)
        }
        // The default plan is unchanged: a first appearance still draws every item on.
        XCTAssertFalse(MGAdoption.plan(previous: nil, next: c.board.scene!.items, transition: .direct).appear.isEmpty)
        // A learner change after the restore takes the usual path, and the board draws on as before.
        XCTAssertTrue(c.control("angle", 90))
        XCTAssertEqual(c.board.scene?.values["theta"]?.value, 90)
        XCTAssertTrue(c.board.drawsOn)
    }

    // MARK: refusal

    func testRefusedSnapshotChangesNothingButLastIssue() throws {
        let clock = MGManualClock()
        // A valid snapshot with a queued beat (speech pacing: beat 0 shown, beat 1 waits).
        var donor = MGLessonSession(pacing: .speech, clock: clock)
        donor.feed(lines([scene, #"{"say":"One."}"#, #"{"op":"params","params":{"angle":90}}"#,
                          #"{"say":"Two."}"#, #"{"op":"params","params":{"angle":180}}"#, #"{"end":true}"#]))
        XCTAssertEqual(donor.waitingBeats, 1)
        let valid = donor.snapshot()
        XCTAssertNoThrow(try MGLessonSession.restore(valid, pacing: .speech, clock: clock).get())
        guard case .array(var pending)? = valid["pending"], case .array(let commands)? = pending[0]["commands"] else { return XCTFail("no pending beat") }
        pending[0] = with(pending[0], "commands", .array(Array(repeating: commands[0], count: 13)))
        let huge = String(repeating: "a", count: MGLessonLimits.snapshotBytes)

        let cases: [(MGJSON, String)] = [
            (.string("not a snapshot"), "snapshot.kind"),
            (with(valid, "kind", .string("lesson")), "snapshot.kind"),
            (with(valid, "v", .number(2)), "snapshot.version"),
            (with(valid, "v", nil), "snapshot.version"),
            (with(valid, "stream", nil), "snapshot.stream"),
            (with(valid, "pending", .string("x")), "snapshot.pending"),
            (with(valid, "pending", .array(pending)), "snapshot.pending"),
            (with(valid, "paused", .number(1)), "snapshot.paused"),
            (with(valid, "scene", F.json(#"{"v":1,"template":"rotate2d","params":{"pts":[[2,1],[4,1],[2,3]],"angle":400}}"#)), "template.angle"),
            (with(valid, "title", .string(huge)), "snapshot.bytes"),
            (with(valid, "junk", .array(Array(repeating: .null, count: 300_000))), "snapshot.bytes"),
            (with(valid, "junk", deep(MGLessonLimits.snapshotDepth + 8)), "snapshot.depth"),
            (with(valid, "junk", deep(2_000)), "snapshot.depth"),
            // Over the size and too deep at once: always the size reason, whatever the dictionary order.
            (with(with(valid, "junk", deep(64)), "zjunk", .string(huge)), "snapshot.bytes"),
        ]

        let c = MGLessonController(pacing: .speech, clock: clock)
        c.begin()
        c.feed(lines([scene, #"{"say":"Look."}"#, bind, #"{"op":"animate","param":"angle","to":90,"dur":6}"#,
                      #"{"say":"More."}"#, #"{"op":"params","params":{"angle":30}}"#, #"{"end":true}"#]))
        clock.advance(by: .seconds(1))
        c.markFrame(clock); c.lineStarted(0)
        c.selection = "vB"
        c.pause()
        var events: [MGLessonEvent] = []
        c.onEvent = { events.append($0) }
        let before = observe(c)
        XCTAssertTrue(before.paused); XCTAssertTrue(before.held)
        XCTAssertNotNil(before.timing.requestAt); XCTAssertNotNil(before.timing.firstPresentedAt); XCTAssertNotNil(before.timing.firstFrameAt)

        for (snapshot, reason) in cases {
            for _ in 0..<3 {
                let result = c.restore(snapshot)
                XCTAssertEqual(result.failureReason, reason)
                XCTAssertEqual(c.lastIssue?.reason, reason)
                XCTAssertEqual(observe(c), before, reason)
            }
        }
        XCTAssertEqual(events, [], "a refused restore emits no event")
        // The controller still runs its lesson afterwards.
        c.resume(); c.lineEnded(0)
        XCTAssertEqual(c.caption, "More.")
    }

    func testOversizeIsCheckedFirstInTheCore() {
        let huge = MGJSON.object(["kind": .string("lessonSnapshot"), "v": .number(2), "x": .string(String(repeating: "b", count: 300_000))])
        XCTAssertEqual(MGLessonSession.restore(huge, pacing: .immediate).failureReason, "snapshot.bytes")
        XCTAssertEqual(MGLessonSession.restore(.array(Array(repeating: .number(1), count: 200_000)), pacing: .immediate).failureReason, "snapshot.bytes")
        XCTAssertEqual(MGLessonSession.restore(deep(40), pacing: .immediate).failureReason, "snapshot.depth")
        XCTAssertEqual(MGLessonSession.restore(.number(1), pacing: .immediate).failureReason, "snapshot.kind")
    }

    /// No false refusal: a stream that queues its full beat budget (speech pacing, no line ended) still restores.
    func testABusySnapshotStaysUnderTheLimits() throws {
        let clock = MGManualClock()
        var s = MGLessonSession(pacing: .speech, clock: clock)
        var stream = [scene, bind]
        let words = String(repeating: "word ", count: 36)
        for k in 0..<MGLessonLimits.beats {
            stream.append(#"{"say":"Beat \#(k) \#(words)"}"#)
            for a in 0..<9 { stream.append(#"{"op":"params","params":{"angle":\#((k * 9 + a + 1) % 360)}}"#) }
        }
        let events = s.feed(lines(stream))
        XCTAssertEqual(F.refusals(events), [])
        s.endStream()
        XCTAssertEqual(s.waitingBeats, MGLessonLimits.beats - 1)
        let snapshot = s.snapshot()
        XCTAssertLessThan(snapshot.canonicalData.count, MGLessonLimits.snapshotBytes / 4)
        let r = try MGLessonSession.restore(snapshot, pacing: .speech, clock: clock).get()
        XCTAssertEqual(r.snapshot(), snapshot)
    }

    // MARK: pause

    func testRestoreNeverStartsPlayback() throws {
        let clock = MGManualClock()
        func running() -> MGLessonController {
            let c = MGLessonController(pacing: .speech, clock: clock)
            c.feed(lines([scene, #"{"say":"One."}"#, #"{"op":"params","params":{"angle":90}}"#, #"{"say":"Two."}"#, #"{"end":true}"#]))
            return c
        }
        let unpaused = running().session.snapshot()
        let pausedSource = running(); pausedSource.pause()
        let paused = pausedSource.session.snapshot()

        // The controller is paused: a running snapshot comes back paused.
        let a = running(); a.pause()
        XCTAssertNoThrow(try a.restore(unpaused).get())
        XCTAssertTrue(a.session.isPaused); XCTAssertTrue(a.board.transitionsPaused); XCTAssertNil(a.session.nextWake)
        a.lineEnded(0)
        XCTAssertEqual(a.caption, "One.", "no beat while paused")
        a.resume(); a.lineEnded(0)
        XCTAssertEqual(a.caption, "Two.")

        // The snapshot was paused: it stays paused on a running controller.
        let b = running()
        XCTAssertNoThrow(try b.restore(paused).get())
        XCTAssertTrue(b.session.isPaused); XCTAssertTrue(b.board.transitionsPaused)

        // Neither paused: playback continues, and the board does not hold transitions.
        let d = running(); d.pause(); d.resume()
        XCTAssertNoThrow(try d.restore(unpaused).get())
        XCTAssertFalse(d.session.isPaused); XCTAssertFalse(d.board.transitionsPaused)
        d.lineEnded(0)
        XCTAssertEqual(d.caption, "Two.")
    }

    // MARK: animation and settle time

    func testRestoreDuringAnAnimationShowsTheEndStateAndDoesNotWaitForIt() throws {
        let clock = MGManualClock()
        let c = MGLessonController(pacing: .speech, clock: clock)
        c.begin()
        c.feed(lines([scene, #"{"say":"Turn."}"#, #"{"op":"animate","param":"angle","to":90,"dur":6}"#, #"{"end":true}"#]))
        XCTAssertEqual(c.board.transition.keyframeDuration, 6, accuracy: 1e-9)
        clock.advance(by: .seconds(1))
        let saved = c.session.snapshot()

        // The plain session restore keeps the remaining settle time (5 s) of the animation.
        var plain = try MGLessonSession.restore(saved, pacing: .speech, clock: clock).get()
        plain.lineEnded(0)
        XCTAssertFalse(plain.isComplete)

        var events: [MGLessonEvent] = []
        c.onEvent = { events.append($0) }
        XCTAssertNoThrow(try c.restore(saved).get())
        XCTAssertEqual(c.board.transition, .direct, "the old animation stops; nothing replays")
        XCTAssertFalse(c.board.drawsOn)
        XCTAssertEqual(c.board.scene?.values["theta"]?.value, 90)
        XCTAssertEqual(c.board.scene?.items, c.state?.scene.items)
        XCTAssertEqual(c.session.openLine, 0)
        XCTAssertEqual(events, [])
        // The board shows the end state, so nothing is left to settle: the lesson completes when the line ends.
        c.lineEnded(0)
        XCTAssertTrue(c.session.isComplete)
        XCTAssertEqual(events, [.lineEnded(beat: 0), .lessonComplete])
        XCTAssertEqual(c.timing.lessonCompleteAt, clock.now)
        XCTAssertNil(c.timing.timeToComplete, "no request mark in a restored run")
    }

    func testARestoreThatOnlyWaitedToSettleCompletesAtOnce() throws {
        let clock = MGManualClock()
        var s = MGLessonSession(pacing: .speech, clock: clock)
        s.feed(lines([scene, #"{"say":"Turn."}"#, #"{"op":"animate","param":"angle","to":90,"dur":6}"#, #"{"end":true}"#]))
        s.lineEnded(0)
        XCTAssertFalse(s.isComplete)
        let c = MGLessonController(pacing: .speech, clock: clock)
        var events: [MGLessonEvent] = []
        c.onEvent = { events.append($0) }
        XCTAssertNoThrow(try c.restore(s.snapshot()).get())
        XCTAssertEqual(events, [.lessonComplete])
        XCTAssertTrue(c.session.isComplete)
        XCTAssertNil(c.session.nextWake)
    }

    // MARK: streaming after a restore

    func testRestoreThenContinueStreamingWithUnfinishedInput() throws {
        let clock = MGManualClock()
        let a = MGLessonController(pacing: .immediate, clock: clock)
        // The partial statement ends inside the two UTF-8 bytes of "°".
        let head = Data(lines([scene, #"{"say":"Look."}"#]).utf8)
        let tail = Data(#"{"say":"Turn 90° now."}"#.utf8) + Data("\n".utf8)
        let cut = tail.firstIndex(of: 0xC2)! + 1
        a.feed(head + tail.prefix(cut))
        let unfinished = a.session.unfinishedInput
        XCTAssertEqual(unfinished.last, 0xC2)
        let saved = a.session.snapshot()

        let b = MGLessonController(pacing: .immediate, clock: clock)
        XCTAssertNoThrow(try b.restore(saved).get())
        XCTAssertTrue(b.session.unfinishedInput.isEmpty)
        var aEvents: [MGLessonEvent] = [], bEvents: [MGLessonEvent] = []
        a.onEvent = { aEvents.append($0) }; b.onEvent = { bEvents.append($0) }
        let rest = Data(tail.suffix(from: cut)) + Data(lines([#"{"op":"animate","param":"angle","to":90,"dur":1}"#, #"{"end":true}"#]).utf8)
        b.feed(unfinished); b.feed(rest)
        a.feed(rest)
        XCTAssertEqual(bEvents, aEvents)
        XCTAssertTrue(aEvents.contains(.lineDue(beat: 1, text: "Turn 90° now.", changed: false)))
        XCTAssertEqual(b.state, a.state)
        XCTAssertEqual(b.caption, "Turn 90° now.")
        XCTAssertEqual(b.session.snapshot(), a.session.snapshot(), "same byte budget after the replay")
        // New changes after the restore reach the board with their own transition and draw-on as usual.
        XCTAssertEqual(b.board.scene?.items, b.state?.scene.items)
        XCTAssertEqual(b.board.transition.keyframeDuration, 1, accuracy: 1e-9)
        XCTAssertTrue(b.board.drawsOn)
    }

    // MARK: timing marks

    func testRestoredRunHasNoFakeFirstVisibleTime() throws {
        let clock = MGManualClock()
        let c = MGLessonController(pacing: .immediate, clock: clock)
        c.begin()
        clock.advance(by: .milliseconds(20))
        c.markFrame(clock)
        c.feed(lines([scene, #"{"say":"Look."}"#, #"{"end":true}"#]))
        XCTAssertNotNil(c.timing.timeToFirstVisible)
        XCTAssertNotNil(c.timing.timeToComplete)
        let saved = c.session.snapshot()

        clock.advance(by: .seconds(30))
        XCTAssertNoThrow(try c.restore(saved).get())
        XCTAssertEqual(c.timing, MGLessonTiming())
        XCTAssertNil(c.timing.timeToFirstVisible)
        // The view draws the restored board: that frame is not a first-visible mark.
        c.markFrame(clock)
        c.feed(#"{"keep":true}"# + "\n")
        XCTAssertNil(c.timing.firstFrameAt)
        XCTAssertNil(c.timing.firstPresentedAt)
        // Later events in this run keep their own marks, with no duration (there is no request mark).
        clock.advance(by: .seconds(2))
        c.feed(lines([#"{"say":"Again."}"#, #"{"end":true}"#]))
        XCTAssertEqual(c.timing.streamEndedAt, clock.now)
        XCTAssertEqual(c.timing.lessonCompleteAt, clock.now)
        XCTAssertNil(c.timing.timeToStreamEnded)
        XCTAssertNil(c.timing.timeToComplete)
        // A new timed run starts with load (or begin).
        XCTAssertTrue(c.load(try F.lesson()))
        XCTAssertEqual(c.timing.requestAt, clock.now)
        XCTAssertNotNil(c.timing.timeToFirstVisible)
    }
}
