// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import MartyGraphics

/// Work bounds of the 2D engine: graph checks per scene (`items.expr` counts graph edits), the timeline items cache and
/// the stream preview. Ordinary scenes at and just over each limit.
final class EngineBoundsTests: XCTestCase {
    static func json(_ s: String) -> MGJSON { MGJSON(any: try! JSONSerialization.jsonObject(with: Data(s.utf8)))! }

    /// One `func` item `g`, a text item `t`, and one step per edit of `g` (and of `t`) after a first step without edits.
    static func scene(graphEdits: Int, textEdits: Int = 0) -> String {
        let items = #"{"id":"g","k":"func","at":[1,1],"w":6,"h":4,"xr":[-3,3],"yr":[-2,2],"y":"a*x/10","a":1},"#
            + #"{"id":"t","k":"text","at":[8,6],"text":"Slope"}"#
        let edits = (0..<graphEdits).map { #"{"id":"g","key":"a","value":\#($0 + 2)}"# }
            + (0..<textEdits).map { #"{"id":"t","key":"text","value":"Slope \#($0 + 2)"}"# }
        let steps = [#"{"say":"Start."}"#] + edits.enumerated().map { #"{"say":"Step \#($0.offset + 1).","do":[\#($0.element)]}"# }
        return #"{"v":1,"items":["# + items + #"],"steps":["# + steps.joined(separator: ",") + "]}"
    }

    static func reason(_ s: String) -> String? {
        if case .failure(let e) = MGParser.scene(data: Data(s.utf8)) { return e.reason }
        return nil
    }

    // MARK: graph checks per scene

    func testStepEditsOfAGraphCountAgainstTheGraphBudget() throws {
        // One graph and five edits of it: six checks, the limit.
        let atLimit = try MGParser.scene(data: Data(Self.scene(graphEdits: MGLimits.exprItems - 1).utf8)).get()
        let last = atLimit.steps.count - 1
        XCTAssertEqual(MGTimeline.items(atLimit, step: last).first { $0.id == "g" }?.num["a"], Double(MGLimits.exprItems))
        // One more edit of the graph is over it.
        XCTAssertEqual(Self.reason(Self.scene(graphEdits: MGLimits.exprItems)), "items.expr")
        // Edits of other items do not count.
        XCTAssertNoThrow(try MGParser.scene(data: Data(Self.scene(graphEdits: MGLimits.exprItems - 1, textEdits: 2).utf8)).get())
    }

    func testGraphEditsCountsStepAndOverEditsThatNameAGraph() {
        let o = Self.json(#"{"v":1,"items":[{"id":"w","k":"field"},{"id":"b","k":"body"}],"#
            + #""over":[{"id":"tg","key":"a","value":2},{"id":"w","key":"a","value":2},{"id":"tb","key":"label","value":"B"}],"#
            + #""steps":[{"say":"A.","do":[{"id":"w","key":"a","value":3},{"id":"tg","key":"a","value":3},{"id":"b","key":"at","value":[1,1]}]}]}"#)
            .objectValue!
        // `over` counts only template graphs (it may name only template items); steps count every graph.
        XCTAssertEqual(MGParser.graphEdits(o, templateGraphs: ["tg"], templateSteps: []), 3)
        XCTAssertEqual(MGParser.graphEdits(o, templateGraphs: [], templateSteps: []), 1)
        // Without wire steps, the template's own step edits count.
        var withoutSteps = o; withoutSteps["steps"] = nil
        var step = MGStep(say: "A."); step.edits = [MGEdit(id: "tg", key: "a", value: .number(4)), MGEdit(id: "x", key: "a", value: .number(4))]
        XCTAssertEqual(MGParser.graphEdits(withoutSteps, templateGraphs: ["tg"], templateSteps: [step]), 2)
    }

    // MARK: timeline items cache

    func testTimelineCacheComputesTheItemsOncePerRevisionAndStep() throws {
        var scene = try MGParser.scene(data: Data(Self.scene(graphEdits: 3).utf8)).get()
        let cache = MGTimelineCache()
        for _ in 0..<20 { XCTAssertEqual(cache.items(scene, step: 3), MGTimeline.items(scene, step: 3)) }
        XCTAssertEqual(cache.computed, 1)
        XCTAssertEqual(cache.items(scene, step: 1), MGTimeline.items(scene, step: 1))
        XCTAssertEqual(cache.computed, 2)
        scene.revision += 1
        XCTAssertEqual(cache.items(scene, step: 1), MGTimeline.items(scene, step: 1))
        XCTAssertEqual(cache.computed, 3, "another revision is another scene")
        XCTAssertEqual(MGDescribe.board(stepItems: cache.items(scene, step: 1), hiding: []), MGDescribe.board(scene, step: 1))
    }

    // MARK: stream preview

    func testStreamPreviewIsNotParsedAgainWhileNothingNewCompletes() throws {
        let json = #"{"v":1,"items":[{"id":"b","k":"body","at":[3,4]}],"steps":[{"say":"One."},{"say":"Two."}]}"#
        var parser = MGStreamParser()
        XCTAssertEqual(parser.feed(String(json.dropLast()))?.steps.count, 2, "steps join once complete")
        let count = parser.previewValidationCount
        for _ in 0..<64 { XCTAssertNil(parser.feed(" ")) }
        XCTAssertNil(parser.feed("}"))
        XCTAssertEqual(parser.previewValidationCount, count)
        XCTAssertEqual(try parser.finish().get(), try MGParser.scene(data: Data(json.utf8)).get())
    }

    func testStreamStepsTrialRunsAgainOnlyWhenItsRootChanges() throws {
        var parser = MGStreamParser()
        let head = #"{"v":1,"steps":[{"say":"One.","show":["c"]}],"items":[{"id":"b","k":"body","at":[3,4]},"#
        let first = try XCTUnwrap(parser.feed(head))
        XCTAssertEqual(first.steps, [], "the steps name an item that has not arrived")
        let count = parser.previewValidationCount
        for _ in 0..<64 { XCTAssertNil(parser.feed(" ")) }
        XCTAssertEqual(parser.previewValidationCount, count)
        let second = try XCTUnwrap(parser.feed(#"{"id":"c","k":"body","at":[6,4]}]}"#))
        XCTAssertEqual(second.steps.count, 1)
        XCTAssertEqual(Set(second.items.map(\.id)), ["b", "c"])
    }
}

/// The lesson `animate` caps (per beat, per stream, per `apply` batch, in snapshots) and waiting beats without keyframes.
final class LessonAnimateBoundsTests: LessonTestCase {
    typealias F = LessonFixture
    static let scene0 = #"{"scene":{"v":1,"template":"rotate2d","params":{"pts":[[2,1],[4,1],[2,3]],"angle":0}}}"#
    static func animate(_ to: Int) -> String { #"{"op":"animate","param":"angle","to":\#(to),"dur":1}"# }

    func feed(_ s: inout MGLessonSession, _ lines: [String]) -> [MGLessonEvent] { lines.flatMap { s.feed($0 + "\n") } }
    func with(_ o: MGJSON, _ key: String, _ value: MGJSON?) -> MGJSON {
        guard case .object(var d) = o else { return o }
        d[key] = value
        return .object(d)
    }

    func testAnimatesPerBeatAtAndOverTheCap() {
        var s = F.session()
        let events = feed(&s, [Self.scene0, #"{"say":"Turn."}"#, Self.animate(5), Self.animate(10), Self.animate(15), #"{"end":true}"#])
        let refused = F.refusals(events)
        XCTAssertEqual(refused.map(\.reason), ["lesson.animate.count"])
        XCTAssertEqual(refused.first?.beat, 0)
        XCTAssertEqual(refused.first?.command, MGLessonLimits.animatesPerBeat)
        XCTAssertEqual(s.state?.value("theta"), 10, "the refused command changed nothing")
    }

    func testAnimatesPerStreamAtAndOverTheCap() {
        var s = F.session()
        var lines = [Self.scene0, Self.animate(5)]   // a set-up animate counts too
        var angle = 5
        for beat in 0..<12 {
            lines.append(#"{"say":"Beat \#(beat + 1)."}"#)
            for _ in 0..<MGLessonLimits.animatesPerBeat { angle += 5; lines.append(Self.animate(angle)) }
        }
        let refused = F.refusals(feed(&s, lines + [#"{"end":true}"#]))
        XCTAssertEqual(refused.map(\.reason), ["lesson.animate.count"], "the 25th animate of the stream")
        XCTAssertEqual(refused.first?.beat, 11)
        XCTAssertEqual(s.state?.value("theta"), Double(angle - 5))
        // A new stream has its own budget.
        let next = F.refusals(feed(&s, [#"{"keep":true}"#, #"{"say":"Again."}"#, Self.animate(0), #"{"end":true}"#]))
        XCTAssertEqual(next, [])
        XCTAssertEqual(s.state?.value("theta"), 0)
    }

    func testApplyBatchHoldsAtMostOneBeatOfAnimates() {
        var s = F.session()
        _ = feed(&s, [Self.scene0, #"{"end":true}"#])
        let over = s.apply([Self.animate(5), Self.animate(10), Self.animate(15)].map(F.json))
        XCTAssertEqual(over.failureReason, "lesson.animate.count")
        if case .failure(let issue) = over { XCTAssertEqual(issue.command, 2) }
        XCTAssertEqual(s.state?.value("theta"), 0)
        XCTAssertNoThrow(try s.apply([Self.animate(5), Self.animate(10)].map(F.json)).get())
        XCTAssertEqual(s.state?.value("theta"), 10)
    }

    func testWaitingBeatKeepsNoKeyframesAndBuildsThemWhenPresented() throws {
        let lines = [Self.scene0, #"{"say":"One."}"#, #"{"op":"params","params":{"angle":45}}"#, #"{"say":"Two."}"#,
                     Self.animate(135), #"{"end":true}"#]
        var waiting = F.session(.speech)
        _ = feed(&waiting, lines)
        XCTAssertEqual(waiting.waitingBeats, 1)
        for t in waiting.pending.flatMap(\.transitions) {
            if case .keyframes = t { XCTFail("a waiting beat holds no keyframe scenes") }
        }
        waiting.lineEnded(0)
        guard case .keyframes(let built)? = waiting.lastChange?.transition else { return XCTFail("the animate plays keyframes") }
        // The same keyframes as a session that presents the beat at once (the engine is deterministic).
        var direct = F.session()
        _ = feed(&direct, lines)
        guard case .keyframes(let expected)? = direct.lastChange?.transition else { return XCTFail("the animate plays keyframes") }
        XCTAssertEqual(built, expected)
        XCTAssertEqual(built.first?.frames.count, 1 + 90 / 5, "the start scene and one keyframe per 5°")
        XCTAssertEqual(waiting.state?.value("theta"), 135)
        XCTAssertEqual(waiting.state, direct.state)
    }

    func testSnapshotKeepsTheStreamAnimateCount() throws {
        var s = F.session(.speech)
        _ = feed(&s, [Self.scene0, #"{"say":"One."}"#, Self.animate(5), Self.animate(10), #"{"say":"Two."}"#, Self.animate(15)])
        let snap = s.snapshot()
        XCTAssertEqual(snap["stream"]?["animates"], .number(3))
        let restored = try MGLessonSession.restore(snap, pacing: .speech, clock: MGManualClock()).get()
        XCTAssertEqual(restored.stream.animates, 3)
        XCTAssertEqual(restored.snapshot(), snap)
        // A snapshot without an animate is unchanged (no `animates` key).
        var plain = F.session(.speech)
        _ = feed(&plain, [Self.scene0, #"{"say":"One."}"#])
        XCTAssertNil(plain.snapshot()["stream"]?["animates"])

        let stream = try XCTUnwrap(snap["stream"])
        let over = with(snap, "stream", with(stream, "animates", .number(Double(MGLessonLimits.animatesPerStream + 1))))
        XCTAssertEqual(MGLessonSession.restore(over, pacing: .speech, clock: MGManualClock()).failureReason, "snapshot.stream")
        guard case .array(var pending)? = snap["pending"], case .array(let commands)? = pending[0]["commands"] else { return XCTFail("no waiting beat") }
        pending[0] = with(pending[0], "commands", .array(Array(repeating: commands[0], count: MGLessonLimits.animatesPerBeat + 1)))
        XCTAssertEqual(MGLessonSession.restore(with(snap, "pending", .array(pending)), pacing: .speech, clock: MGManualClock()).failureReason,
                       "snapshot.pending")
    }

    func testRefusedAnimateKeepsItsPlaceInTheStreamCount() {
        // The beat's check holds theta at 0, so each `animate` builds its keyframes and is then refused by the check.
        var s = F.session()
        var lines = [Self.scene0, #"{"say":"Hold."}"#, #"{"check":{"value":"theta","eq":0}}"#]
        lines += (1...MGLessonLimits.animatesPerStream).map { Self.animate(5 * $0) }
        lines.append(Self.animate(5))
        let refused = F.refusals(feed(&s, lines))
        XCTAssertEqual(refused.count, MGLessonLimits.animatesPerStream + 1)
        XCTAssertEqual(Set(refused.prefix(MGLessonLimits.animatesPerStream).map(\.reason)), ["check.theta"])
        XCTAssertEqual(refused.last?.reason, "lesson.animate.count", "the 25th is refused before it runs")
        XCTAssertEqual(s.stream.animates, MGLessonLimits.animatesPerStream)
        XCTAssertEqual(s.projected?.value("theta"), 0)
    }

    func testKeepStreamCountsTheAnimatesStillWaiting() {
        var s = F.session(.speech)
        _ = feed(&s, [Self.scene0, #"{"say":"Intro."}"#, #"{"say":"One."}"#, Self.animate(5), Self.animate(10), #"{"end":true}"#])
        XCTAssertEqual(s.waitingBeats, 1, "the intro's line is open, so beat 1 waits")
        _ = feed(&s, [#"{"keep":true}"#])
        XCTAssertEqual(s.stream.animates, 2, "the waiting beat's animates count toward the new stream")
        var lines: [String] = []
        var angle = 10
        for beat in 0..<11 {
            lines.append(#"{"say":"More \#(beat + 1)."}"#)
            for _ in 0..<MGLessonLimits.animatesPerBeat { angle += 5; lines.append(Self.animate(angle)) }
        }
        lines += [#"{"say":"Last."}"#, Self.animate(angle + 5)]
        let refused = F.refusals(feed(&s, lines))
        XCTAssertEqual(refused.map(\.reason), ["lesson.animate.count"], "24 wait; the 25th is refused")
        XCTAssertEqual(s.queuedAnimates, MGLessonLimits.animatesPerStream)
    }

    /// A `.speech` session whose waiting beats hold `pairs` beats of 2 `animate` commands and a last beat with one
    /// `params` command (the intro's line stays open, so nothing after it is shown). `end`: the stream ends (the last
    /// beat closes).
    func waitingQueue(pairs: Int, end: Bool = true) -> MGLessonSession {
        var s = F.session(.speech)
        var lines = [Self.scene0, #"{"say":"Intro."}"#]
        var angle = 0
        for beat in 0..<pairs {
            lines.append(#"{"say":"Beat \#(beat + 1)."}"#)
            for _ in 0..<MGLessonLimits.animatesPerBeat { angle += 5; lines.append(Self.animate(angle)) }
        }
        lines += [#"{"say":"Last."}"#, #"{"op":"params","params":{"angle":\#(angle + 5)}}"#] + (end ? [#"{"end":true}"#] : [])
        XCTAssertEqual(F.refusals(feed(&s, lines)), [])
        XCTAssertEqual(s.waitingBeats, pairs + 1)
        return s
    }

    /// `snap` with the last waiting beat's `params` command made an `animate` to the same angle.
    func lastCommandAnimates(_ snap: MGJSON) -> MGJSON {
        guard case .array(var pending)? = snap["pending"], case .array(var commands)? = pending.last?["commands"],
              case .number(let to)? = commands.first?["s"]?["params"]?["angle"] else { XCTFail("no waiting params command"); return snap }
        commands[0] = with(commands[0], "s", F.json(Self.animate(Int(to))))
        pending[pending.count - 1] = with(pending[pending.count - 1], "commands", .array(commands))
        return with(snap, "pending", .array(pending))
    }

    func testRestoreCountsTheWaitingAnimatesTogether() throws {
        let clock = MGManualClock()
        // At the cap: 24 waiting animates restore, and the stream count stays 24.
        let full = waitingQueue(pairs: 12).snapshot()
        XCTAssertEqual(full["stream"]?["animates"], .number(24))
        XCTAssertEqual(try MGLessonSession.restore(full, pacing: .speech, clock: clock).get().stream.animates, 24)
        // One more waiting `animate` in a later beat: 25 together, each beat within its own cap.
        XCTAssertEqual(MGLessonSession.restore(lastCommandAnimates(full), pacing: .speech, clock: clock).failureReason, "snapshot.pending")
        // The same edit with room left restores, and the count covers the queue (23) though the snapshot stores 22.
        let room = waitingQueue(pairs: 11).snapshot()
        let edited = try MGLessonSession.restore(lastCommandAnimates(room), pacing: .speech, clock: clock).get()
        XCTAssertEqual(edited.stream.animates, 23)
        XCTAssertEqual(edited.queuedAnimates, 23)
    }

    func testLegacySnapshotTakesTheCountFromTheQueue() throws {
        let s = waitingQueue(pairs: 2, end: false)
        let snap = s.snapshot()
        let stream = try XCTUnwrap(snap["stream"])
        XCTAssertEqual(stream["animates"], .number(4))
        let legacy = with(snap, "stream", with(stream, "animates", nil))   // written before the count was kept
        var restored = try MGLessonSession.restore(legacy, pacing: .speech, clock: MGManualClock()).get()
        XCTAssertEqual(restored.stream.animates, 4, "at least the animates the waiting beats hold")
        XCTAssertEqual(restored.snapshot(), snap)
        // The same stream goes on with the rest of its budget: 20 more, then the 25th is refused.
        var lines: [String] = []
        var angle = 25
        for beat in 0..<10 {
            lines.append(#"{"say":"More \#(beat + 1)."}"#)
            for _ in 0..<MGLessonLimits.animatesPerBeat { angle += 5; lines.append(Self.animate(angle)) }
        }
        lines += [#"{"say":"Last."}"#, Self.animate(angle + 5)]
        XCTAssertEqual(F.refusals(feed(&restored, lines)).map(\.reason), ["lesson.animate.count"])
    }

    func testReplayedScriptKeepsTheCaps() {
        let a = F.json(Self.animate(5)), other = F.json(#"{"op":"params","params":{"angle":10}}"#)
        XCTAssertNoThrow(try MGLessonEngine.checkReplayAnimates(setup: [a, other], beats: [[a, a, other]]))
        XCTAssertThrowsError(try MGLessonEngine.checkReplayAnimates(setup: [], beats: [[a, other, a, a]]))
        let setup = Array(repeating: a, count: MGLessonLimits.animatesPerStream + 1)
        XCTAssertThrowsError(try MGLessonEngine.checkReplayAnimates(setup: setup, beats: []))
        XCTAssertEqual(MGLessonEngine.excessAnimate([a, other, a, a]), 3)
        XCTAssertEqual(MGLessonEngine.excessAnimate([a], used: MGLessonLimits.animatesPerStream), 0)
        XCTAssertNil(MGLessonEngine.excessAnimate([a, a], used: MGLessonLimits.animatesPerStream - 2))
    }
}
