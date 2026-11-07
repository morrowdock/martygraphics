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
    func deep(_ levels: Int, holding leaf: MGJSON = .number(0)) -> MGJSON { var v = leaf; for _ in 0..<levels { v = .array([v]) }; return v }

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
            (with(valid, "junk", deep(MGLessonLimits.snapshotDepth + 1)), "snapshot.depth"),
            // Over the size and too deep at once: always the size reason, whatever the dictionary order.
            (with(with(valid, "junk", deep(64)), "zjunk", .string(huge)), "snapshot.bytes"),
            // Large data below the depth limit still counts toward the size (review N1).
            (with(valid, "junk", deep(40, holding: .string(huge))), "snapshot.bytes"),
            // Non-finite numbers are refused without being encoded (review S1), wherever they are.
            (with(valid, "x", .number(.nan)), "snapshot.number"),
            (with(valid, "rev", .number(.infinity)), "snapshot.number"),
            (with(valid, "junk", deep(40, holding: .number(-.infinity))), "snapshot.number"),
            (with(with(valid, "x", .number(.nan)), "zjunk", .string(huge)), "snapshot.bytes"),
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
        XCTAssertEqual(MGLessonSession.restore(deep(MGLessonLimits.snapshotDepth + 1), pacing: .immediate).failureReason, "snapshot.depth")
        XCTAssertEqual(MGLessonSession.restore(deep(MGLessonLimits.snapshotDepth), pacing: .immediate).failureReason, "snapshot.kind")
        XCTAssertEqual(MGLessonSession.restore(.number(1), pacing: .immediate).failureReason, "snapshot.kind")
        // The review's S1 input: before the fix this terminated the process inside the JSON encoder.
        let nan = MGJSON.object(["kind": .string("lessonSnapshot"), "v": .number(1), "x": .number(.nan)])
        XCTAssertEqual(MGLessonSession.restore(nan, pacing: .immediate).failureReason, "snapshot.number")
        XCTAssertEqual(MGLessonSession.restore(.array([.number(.nan), deep(40)]), pacing: .immediate).failureReason, "snapshot.number")
    }

    // MARK: session budgets: every snapshot of a session fits the cap (review S2)

    func testSnapshotCapIsDerivedFromTheSessionLimits() {
        XCTAssertEqual(MGLessonLimits.snapshotBytes, 291_570, "docs/LESSONS.md says 291,570 bytes")
        XCTAssertEqual(MGLessonLimits.snapshotBytes,
                       2 * (MGLimits.sceneBytes + MGLessonLimits.ids * 80 + MGLessonLimits.controls * MGLessonLimits.controlBytes + 256)
                       + MGLessonLimits.queueBytes + MGLessonLimits.lineBytes + (MGLimits.title * 4 + 2) + 2048)
        XCTAssertEqual(MGLessonLimits.snapshotDepth, 64, "docs/LESSONS.md says 64 levels")
        XCTAssertEqual(MGLessonLimits.statementDepth, 59, "docs/LESSONS.md says 59 levels")
        XCTAssertEqual(MGLessonLimits.documentDepth, 63, "docs/LESSONS.md says 63 levels")
        // The id history entry bound: the longest id with the longest kind and a 10-digit beat.
        let id = String(repeating: "h", count: 24)
        let longestKind = MGKind.allCases.map(\.rawValue).max { $0.utf8.count < $1.utf8.count }!
        let entry = MGJSON.object(["k": .object([id: .string(longestKind)]), "i": .object([id: .number(1e9)])]).canonicalByteCount
        XCTAssertLessThanOrEqual(entry - #"{"i":{},"k":{}}"#.utf8.count + 2, MGLessonLimits.idEntryBytes)
    }

    /// One beat stream of about `kib` KiB: 24 beats of a long line and nine 60-character title commands.
    func fullStream(first: Bool, tag: String) -> [String] {
        var out = first ? [scene] : [#"{"keep":true}"#]
        let line = String(repeating: "word ", count: 37) + tag
        let title = String(repeating: "t", count: 59 - tag.count) + tag
        for k in 0..<MGLessonLimits.beats {
            out.append(#"{"say":"\#(k) \#(line)"}"#)
            for _ in 0..<9 { out.append(#"{"op":"title","title":"\#(title)"}"#) }
        }
        out.append(#"{"end":true}"#)
        return out
    }

    func testOneFullStreamFitsTheQueue() throws {
        var s = MGLessonSession(pacing: .speech, clock: MGManualClock())
        let stream = lines(fullStream(first: true, tag: "a"))
        XCTAssertGreaterThan(stream.utf8.count, 20 * 1024)
        XCTAssertEqual(F.refusals(s.feed(stream)), [])
        XCTAssertEqual(s.waitingBeats, MGLessonLimits.beats - 1)
        XCTAssertLessThan(s.queueUsage, MGLessonLimits.queueBytes / 2)
        XCTAssertEqual(s.queueUsage, (s.snapshot()["pending"] ?? .null).canonicalByteCount, "the budget measures the snapshot entry exactly")
    }

    func testQueueBudgetAcrossFollowUpStreamsKeepsEverySnapshotRestorable() throws {
        let clock = MGManualClock()
        var s = MGLessonSession(pacing: .speech, clock: clock)
        var refusedAt: Int?
        for n in 0..<8 {
            for statement in fullStream(first: n == 0, tag: "s\(n)") {
                let before = (pending: s.waitingBeats, projected: s.projected, usage: s.queueUsage, open: s.openBeat)
                let index = s.nextStatement
                let refusals = F.refusals(s.feed(statement + "\n")).filter { $0.reason == "lesson.queue.bytes" }
                // A beat whose filled line does not fit is refused when it closes (its own `say` statement index);
                // that refusal shrinks the queue. Here: the statement itself was refused, so nothing changed.
                if refusals.contains(where: { $0.statement == index }) {
                    refusedAt = refusedAt ?? n
                    XCTAssertEqual(s.waitingBeats, before.pending, "a refused statement queues nothing")
                    XCTAssertEqual(s.projected, before.projected)
                    XCTAssertEqual(s.queueUsage, before.usage)
                    XCTAssertEqual(s.openBeat, before.open, "a refused say keeps the open beat")
                }
                for r in refusals where r.statement != index { XCTAssertLessThan(r.statement ?? .max, index, "a closing refusal names its say") }
                XCTAssertLessThanOrEqual(s.queueUsage, MGLessonLimits.queueBytes)
            }
        }
        XCTAssertNotNil(refusedAt, "follow-up streams fill the queue")
        let snapshot = s.snapshot()
        XCTAssertLessThanOrEqual(snapshot.canonicalByteCount, MGLessonLimits.snapshotBytes)
        let r = try MGLessonSession.restore(snapshot, pacing: .speech, clock: clock).get()
        XCTAssertEqual(r.snapshot(), snapshot)
        XCTAssertEqual(r.queueUsage, s.queueUsage)
        // Showing beats frees the budget: a new beat is accepted again.
        for _ in 0..<30 { if let k = s.openLine { s.lineEnded(k) } }
        XCTAssertEqual(F.refusals(s.feed(lines([#"{"keep":true}"#, #"{"say":"Again."}"#, #"{"end":true}"#]))), [])
    }

    func testRestoreRefusesAQueueOverTheBudget() throws {
        let clock = MGManualClock()
        var s = MGLessonSession(pacing: .speech, clock: clock)
        s.feed(lines(fullStream(first: true, tag: "a")))
        let snapshot = s.snapshot()
        guard case .array(let pending)? = snapshot["pending"] else { return XCTFail("no queue") }
        let doubled = with(snapshot, "pending", .array(pending + pending + pending + pending))
        XCTAssertLessThanOrEqual(doubled.canonicalByteCount, MGLessonLimits.snapshotBytes)
        XCTAssertEqual(MGLessonSession.restore(doubled, pacing: .speech, clock: clock).failureReason, "snapshot.pending")
    }

    func testIdHistoryIsBounded() throws {
        var s = MGLessonSession(pacing: .immediate, clock: MGManualClock())
        var reasons: [String] = []
        var id = 0
        for n in 0..<11 {
            var stream = [n == 0 ? scene : #"{"keep":true}"#]
            for _ in 0..<22 {
                stream.append(#"{"say":"More marks."}"#)
                let ids = (0..<5).map { _ -> String in id += 1; return "h\(id)" }
                for h in ids { stream.append(#"{"op":"add","item":{"id":"\#(h)","k":"highlight","target":"vA"}}"#) }
                for h in ids { stream.append(#"{"op":"remove","id":"\#(h)"}"#) }
            }
            stream.append(#"{"end":true}"#)
            reasons += F.refusals(s.feed(lines(stream))).map(\.reason)
            XCTAssertLessThanOrEqual(s.state!.kinds.count, MGLessonLimits.ids)
        }
        XCTAssertTrue(reasons.contains("lesson.ids.count"))
        XCTAssertEqual(s.state!.kinds.count, MGLessonLimits.ids)
        let snapshot = s.snapshot()
        XCTAssertLessThanOrEqual(snapshot.canonicalByteCount, MGLessonLimits.snapshotBytes)
        XCTAssertNoThrow(try MGLessonSession.restore(snapshot, pacing: .immediate).get())
        var kinds = snapshot["kinds"]!.objectValue!
        kinds["zz1"] = .string("highlight")
        XCTAssertEqual(MGLessonSession.restore(with(snapshot, "kinds", .object(kinds)), pacing: .immediate).failureReason, "snapshot.kinds")
    }

    func testFilledLinesAreBounded() throws {
        var s = MGLessonSession(pacing: .immediate, clock: MGManualClock())
        let many = String(repeating: "{ax0}", count: 39)   // 195 characters, each placeholder fills to "2"
        XCTAssertEqual(F.refusals(s.feed(lines([scene, #"{"say":"\#(many)"}"#, #"{"end":true}"#]))), [])
        XCTAssertNotNil(s.caption)
        XCTAssertThrowsError(try MGLessonSession.fillLine(String(repeating: "{x}", count: 60), ["x": MGValue(value: 1e300, unit: "")])) {
            XCTAssertEqual(($0 as? MGError)?.reason, "stmt.say.bytes")
        }
    }

    // MARK: line timing follows the restoring pacing (review S3)

    func testPausedEstimateSnapshotDoesNotSpinOnAnotherPacing() throws {
        let clock = MGManualClock()
        var source = MGLessonSession(pacing: .estimate(wordsPerSecond: 2.5), clock: clock)
        source.feed(lines([scene, #"{"say":"One line here."}"#, #"{"say":"Two."}"#, #"{"end":true}"#]))
        XCTAssertEqual(source.openLine, 0)
        source.pause()
        let saved = source.snapshot()
        XCTAssertNotNil(saved["lineLeft"])

        let speech = MGLessonController(pacing: .speech, clock: clock)
        XCTAssertNoThrow(try speech.restore(saved).get())
        speech.resume()
        XCTAssertNil(speech.session.nextWake, "a speech line waits for lineEnded; no timer")
        XCTAssertEqual(speech.session.openLine, 0)
        speech.lineEnded(0)
        XCTAssertEqual(speech.caption, "Two.")

        let immediate = MGLessonController(pacing: .immediate, clock: clock)
        XCTAssertNoThrow(try immediate.restore(saved).get())
        XCTAssertNil(immediate.session.openLine)
        immediate.resume()
        XCTAssertNil(immediate.session.nextWake)
        XCTAssertEqual(immediate.caption, "Two.")
        XCTAssertTrue(immediate.session.isComplete)

        // A hand-built paused snapshot with a line time but no open line keeps no timer either.
        let r = try MGLessonSession.restore(with(saved, "line", nil), pacing: .estimate(wordsPerSecond: 2.5), clock: clock).get()
        XCTAssertNil(r.lineRemaining); XCTAssertNil(r.lineEndsAt)
    }

    func testSpeechSnapshotOnAnEstimateControllerEndsItsLine() throws {
        let clock = MGManualClock()
        var source = MGLessonSession(pacing: .speech, clock: clock)
        source.feed(lines([scene, #"{"say":"One."}"#, #"{"say":"Two."}"#, #"{"end":true}"#]))
        XCTAssertEqual(source.openLine, 0)
        let saved = source.snapshot()
        XCTAssertNil(saved["lineLeft"])
        let rate = 2.5
        var r = try MGLessonSession.restore(saved, pacing: .estimate(wordsPerSecond: rate), clock: clock).get()
        XCTAssertEqual(r.nextWake, clock.now + MGLessonSession.lineDuration("One.", wordsPerSecond: rate))
        clock.advance(by: MGLessonSession.lineDuration("One.", wordsPerSecond: rate))
        let events = r.tick()
        XCTAssertTrue(events.contains(.lineEnded(beat: 0)))
        XCTAssertEqual(r.caption, "Two.")
    }

    // MARK: a beat presented by the restore tick is shown directly too (review N3)

    func testABeatDueAtRestoreIsShownDirectly() throws {
        let clock = MGManualClock()
        var source = MGLessonSession(pacing: .speech, clock: clock)
        source.feed(lines([scene, #"{"say":"One."}"#, #"{"say":"Two."}"#, #"{"op":"params","params":{"angle":90}}"#, #"{"end":true}"#]))
        XCTAssertEqual(source.waitingBeats, 1)
        let c = MGLessonController(pacing: .immediate, clock: clock)
        c.feed(lines([scene, #"{"say":"Old."}"#, #"{"end":true}"#]))
        var events: [MGLessonEvent] = []
        c.onEvent = { events.append($0) }
        let revision = c.board.revision
        XCTAssertNoThrow(try c.restore(source.snapshot()).get())
        XCTAssertEqual(c.board.revision, revision + 1, "one board update")
        XCTAssertTrue(events.contains(.lineDue(beat: 1, text: "Two.", changed: false)))
        XCTAssertEqual(events.last, .lessonComplete)
        XCTAssertEqual(c.caption, "Two.")
        XCTAssertEqual(c.state?.value("theta"), 90)
        XCTAssertEqual(c.board.scene?.items, c.state?.scene.items)
        XCTAssertEqual(c.board.transition, .direct)
        XCTAssertFalse(c.board.drawsOn)
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

    // MARK: second re-check: every snapshot of a session restores (review 2)

    /// A paused speech session with a queued beat (both states are in its snapshot).
    func pausedSnapshot(_ clock: MGManualClock) -> MGJSON {
        var s = MGLessonSession(pacing: .speech, clock: clock)
        s.feed(lines([#"{"lesson":{"v":1,"title":"Turning"}}"#, scene, #"{"say":"One."}"#, #"{"say":"Two."}"#, #"{"end":true}"#]))
        s.pause()
        return s.snapshot()
    }

    /// Review 2 S1: restored captions, titles and id history keys keep the bounds of a live session.
    func testRestoredFieldsKeepTheLiveBounds() throws {
        let clock = MGManualClock()
        let valid = pausedSnapshot(clock)
        XCTAssertNoThrow(try MGLessonSession.restore(valid, pacing: .speech, clock: clock).get())
        var kinds = valid["kinds"]!.objectValue!
        let longKey = String(repeating: "k", count: 30)
        var tooMany = kinds
        for i in 0..<(MGLessonLimits.ids + 1 - kinds.count) { tooMany["x\(i)"] = .string("highlight") }
        kinds[longKey] = .string("highlight")
        var introduced = valid["introduced"]!.objectValue!
        introduced["nope"] = .number(0)
        var baseline = valid["baseline"]!.objectValue!
        baseline["kinds"] = .object(kinds)
        let cases: [(MGJSON, String)] = [
            (with(valid, "caption", .string(String(repeating: "x", count: 200_000))), "snapshot.caption"),
            (with(valid, "caption", .string(String(repeating: "x", count: MGLessonLimits.lineBytes))), "snapshot.caption"),
            (with(valid, "title", .string(String(repeating: "t", count: MGLimits.title + 1))), "snapshot.title"),
            (with(valid, "title", .string("<b>Bold</b>")), "snapshot.title"),
            (with(valid, "title", .string(" Untrimmed")), "snapshot.title"),
            (with(valid, "kinds", .object(kinds)), "snapshot.kinds"),
            (with(valid, "kinds", .object(tooMany)), "snapshot.kinds"),
            (with(valid, "introduced", .object(introduced)), "snapshot.introduced"),
            (with(valid, "introduced", .object(["vA": .number(-1)])), "snapshot.introduced"),
            (with(valid, "baseline", .object(baseline)), "snapshot.kinds"),
        ]
        for (snapshot, reason) in cases {
            XCTAssertLessThanOrEqual(snapshot.canonicalByteCount, MGLessonLimits.snapshotBytes, reason)
            XCTAssertEqual(MGLessonSession.restore(snapshot, pacing: .speech, clock: clock).failureReason, reason)
        }
        // The review's reproduction: the oversized caption is refused at restore, so it can never grow past the cap.
        let c = MGLessonController(pacing: .speech, clock: clock)
        let before = observe(c)
        XCTAssertEqual(c.restore(cases[0].0).failureReason, "snapshot.caption")
        XCTAssertEqual(observe(c), before)
        // A filled line at the bound is accepted (a restored caption at exactly the bound restores).
        let atBound = String(repeating: "x", count: MGLessonLimits.lineBytes - 2)
        XCTAssertNoThrow(try MGLessonSession.restore(with(valid, "caption", .string(atBound)), pacing: .speech, clock: clock).get())
    }

    // The deepest legal snapshot round trip (review 2 S2, review 3 N2) is in DeepJSONGuardTests, on a 512 KiB stack.

    /// Review 3 N4: a restored title follows the live header rule, including the decimal-literal rule.
    func testRestoredTitleFollowsTheDecimalLiteralRule() throws {
        let clock = MGManualClock()
        var live = MGLessonSession(pacing: .immediate, clock: clock)
        XCTAssertEqual(F.refusals(live.feed(lines([#"{"lesson":{"v":1,"title":"Turn by 1.5 degrees"}}"#]))).map(\.reason), ["text.literal"])
        live.feed(lines([#"{"lesson":{"v":1,"title":"Turn 90 degrees."}}"#, scene, #"{"say":"Look."}"#, #"{"end":true}"#]))
        let valid = live.snapshot()
        XCTAssertEqual(valid["title"], .string("Turn 90 degrees."))
        XCTAssertNoThrow(try MGLessonSession.restore(valid, pacing: .immediate, clock: clock).get())
        for title in ["Turn by 1.5 degrees", "Scale by .5", "About 2e3 steps", "Turn by 2.e3"] {
            XCTAssertEqual(MGLessonSession.restore(with(valid, "title", .string(title)), pacing: .immediate, clock: clock).failureReason,
                           "snapshot.title", title)
            var header = MGLessonSession(pacing: .immediate, clock: clock)
            XCTAssertEqual(F.refusals(header.feed(lines([#"{"lesson":{"v":1,"title":"\#(title)"}}"#]))).map(\.reason), ["text.literal"],
                           "the live header refuses it too")
        }
    }

    /// Review 2 S3: a control is bounded on every path, including public `apply` and `restore`.
    func testControlsAreBoundedOnEveryPath() throws {
        let long = String(repeating: "p", count: 1000), fine = String(repeating: "q", count: 100)
        let t = MGTemplate(name: "long_param", summary: "long parameter names",
                           params: [MGParamSpec(name: long, unit: "", range: 0...1, defaultValue: 0),
                                    MGParamSpec(name: fine, unit: "", range: 0...1, defaultValue: 0)]) { _, _ in
            MGTemplateBuild(title: "Long", items: [MGMake.body("A", MGPoint(2, 2))])
        }
        try MGPacks.register(MGPack(id: "long_param_pack", title: "Long", summary: "long names", templates: [t],
                                    fixtures: [MGFixtures.Demo(id: "long_param_demo", title: "Long", json: #"{"v":1,"template":"long_param","params":{}}"#)]))
        func bind(_ id: String, _ param: String) -> MGJSON {
            F.json(#"{"op":"bind","control":{"id":"\#(id)","k":"slider","param":"\#(param)","min":0,"max":1,"step":1,"label":"Long"}}"#)
        }
        var s = MGLessonSession(pacing: .immediate, clock: MGManualClock())
        s.feed(#"{"scene":{"v":1,"template":"long_param","params":{}}}"# + "\n")
        let state = s.state
        XCTAssertEqual(s.apply(bind("a", long)).failureReason, "control.bytes")
        XCTAssertEqual(s.state, state)
        XCTAssertEqual(F.refusals(s.feed(bind("a", long).canonicalString + "\n")).map(\.reason), ["control.bytes"])
        XCTAssertNoThrow(try s.apply(bind("b", fine)).get())
        let c = MGLessonController(pacing: .immediate, clock: MGManualClock())
        c.feed(#"{"scene":{"v":1,"template":"long_param","params":{}}}"# + "\n")
        XCTAssertFalse(c.apply(bind("a", long)))
        XCTAssertEqual(c.lastIssue?.reason, "control.bytes")
        // A snapshot whose control names the long parameter is refused by the same rule when it is bound again.
        let snapshot = s.snapshot()
        guard case .array(let controls)? = snapshot["controls"] else { return XCTFail("no controls") }
        let tampered = with(snapshot, "controls", .array([with(controls[0], "param", .string(long))]))
        XCTAssertEqual(MGLessonSession.restore(tampered, pacing: .immediate).failureReason, "control.bytes")
        XCTAssertNoThrow(try MGLessonSession.restore(snapshot, pacing: .immediate).get())
    }

    /// The largest legal session along every path: header, streams with set-up and queued beats, follow-up `keep`
    /// streams, host `apply`, learner input, a full id history and a full queue. Its snapshot restores.
    func testTheLargestLegalSessionRestores() throws {
        let clock = MGManualClock()
        let c = MGLessonController(pacing: .speech, clock: clock)
        let title = String(repeating: "€", count: MGLimits.title)
        let label = String(repeating: "é", count: MGLimits.label)
        c.feed(lines([#"{"lesson":{"v":1,"title":"\#(title)"}}"#, scene,
                      #"{"op":"bind","control":{"id":"angle","k":"slider","param":"angle","min":-360,"max":360,"step":5,"label":"\#(label)"}}"#]))
        // Host `apply`: three more controls (four in all).
        for (id, param, lo, hi) in [("px", "px", -2, 2), ("py", "py", -2, 2), ("ghost", "ghost", 0, 1)] {
            XCTAssertTrue(c.apply(F.json(#"{"op":"bind","control":{"id":"\#(id)","k":"slider","param":"\#(param)","min":\#(lo),"max":\#(hi),"step":1,"label":"\#(label)"}}"#)))
        }
        // Follow-up streams fill the id history with the longest ids; every beat is shown.
        var id = 0, reasons: [String] = []
        for n in 0..<12 {
            var stream = n == 0 ? [] : [#"{"keep":true}"#]
            for _ in 0..<22 {
                stream.append(#"{"say":"More marks."}"#)
                let ids = (0..<5).map { _ -> String in id += 1; return "h" + String(format: "%023d", id) }
                for h in ids { stream.append(#"{"op":"add","item":{"id":"\#(h)","k":"highlight","target":"vA"}}"#) }
                for h in ids { stream.append(#"{"op":"remove","id":"\#(h)"}"#) }
            }
            stream.append(#"{"end":true}"#)
            var events: [MGLessonEvent] = []
            c.onEvent = { events.append($0) }
            c.feed(lines(stream))
            for _ in 0..<40 { if let k = c.session.openLine { c.lineEnded(k) } }
            reasons += F.refusals(events).map(\.reason)
        }
        XCTAssertTrue(reasons.contains("lesson.ids.count"))
        XCTAssertEqual(c.state?.kinds.count, MGLessonLimits.ids)
        // Learner input, then follow-up streams that fill the queue (the line stays open, so beats wait).
        XCTAssertTrue(c.control("angle", 45))
        for n in 0..<6 { c.feed(lines(fullStream(first: false, tag: "q\(n)"))) }
        XCTAssertGreaterThan(c.session.queueUsage, MGLessonLimits.queueBytes / 2)
        XCTAssertGreaterThan(c.session.waitingBeats, 0, "the snapshot holds the queue baseline: a second full state")
        let snapshot = c.session.snapshot()
        let size = snapshot.canonicalByteCount
        XCTAssertLessThanOrEqual(size, MGLessonLimits.snapshotBytes)
        XCTAssertGreaterThan(size, MGLessonLimits.snapshotBytes / 2, "a large snapshot, not a toy one")
        let r = try MGLessonSession.restore(snapshot, pacing: .speech, clock: clock).get()
        XCTAssertEqual(r.snapshot(), snapshot)
        let restored = MGLessonController(pacing: .speech, clock: clock)
        XCTAssertNoThrow(try restored.restore(snapshot).get())
    }
}
