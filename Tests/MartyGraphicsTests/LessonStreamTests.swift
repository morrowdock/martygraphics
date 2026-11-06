// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import MartyGraphics

/// Acceptance group S (streaming lane) and U12 (determinism). This file imports only Foundation and XCTest.
final class LessonStreamTests: LessonTestCase {
    typealias F = LessonFixture

    // MARK: S1 partial statements wait

    func testS1NothingHappensBeforeAStatementCloses() throws {
        let stream = try F.stream()
        var bytewise = F.session()
        var accepted = 0
        for (i, ch) in stream.enumerated() {
            let before = (bytewise.projected, bytewise.state, bytewise.history.count)
            let events = bytewise.feed(String(ch))
            if ch != "}" {
                XCTAssertTrue(events.isEmpty, "event at offset \(i)")
                XCTAssertEqual(bytewise.projected, before.0, "projected changed at offset \(i)")
                XCTAssertEqual(bytewise.state, before.1, "presented changed at offset \(i)")
                XCTAssertEqual(bytewise.history.count, before.2)
            }
            accepted += events.filter { if case .accepted = $0 { return true }; return false }.count
        }
        XCTAssertEqual(accepted, try F.statements().count, "each statement exactly once")
        var whole = F.session()
        whole.feed(stream)
        XCTAssertEqual(bytewise.state, whole.state)
        XCTAssertEqual(bytewise.events, whole.events)
        // Eight seeded random chunkings give the same events and state.
        var rng = LessonRNG(seed: 3)
        let bytes = Array(stream.utf8)
        for _ in 0..<8 {
            var s = F.session(), i = 0
            while i < bytes.count {
                let n = Int.random(in: 1...40, using: &rng)
                s.feed(String(decoding: bytes[i..<min(bytes.count, i + n)], as: UTF8.self)); i += n
            }
            XCTAssertEqual(s.events, whole.events)
            XCTAssertEqual(s.state, whole.state)
        }
        // Braces, escaped quotes and \n inside a string do not end a statement; it is recognised once, at its real end.
        var tricky = F.session()
        tricky.feed(try F.statements()[1] + "\n")
        let text = #"{"say":"a } b { c \"q\" d\nnext"}"#
        var seen: [Int] = []
        for (i, ch) in text.enumerated() {
            let events = tricky.feed(String(ch))
            if events.contains(where: { if case .accepted = $0 { return true }; if case .refused = $0 { return true }; return false }) { seen.append(i) }
        }
        XCTAssertEqual(seen, [text.count - 1])
        // Its text is refused by the text rule (a lone brace), with the statement's own index.
        XCTAssertEqual(F.refusals(tricky.events).map(\.statement), [1])
        var ok = F.session()
        ok.feed(try F.statements()[1] + "\n")
        XCTAssertEqual(F.refusals(ok.feed(#"{"say":"say \"hi\"\nthen [stop]"}"#)), [])
    }

    // MARK: S2 a refused statement keeps earlier marks

    func testS2ARefusalMidStreamKeepsEarlierMarksAndTheStreamContinues() throws {
        var statements = try F.statements()
        statements.insert(#"{"op":"add","item":{"id":"hb","k":"highlight","target":"bad"}}"#, at: 4)
        statements.insert(#"{"op":"add","item":{"id":"bad","k":"rocket"}}"#, at: 4)
        var s = F.session()
        for line in statements[0..<4] { s.feed(line + "\n") }
        let marks = s.projected!.scene.items
        var events: [MGLessonEvent] = []
        for line in statements[4..<6] { events += s.feed(line + "\n") }
        XCTAssertEqual(F.refusals(events).map(\.reason), ["item.kind", "highlight.target"])
        XCTAssertEqual(F.refusals(events).map(\.statement), [4, 5])
        XCTAssertEqual(F.refusals(events).map(\.beat), [0, 0])
        XCTAssertEqual(s.projected!.scene.items, marks, "every earlier mark is still present and unchanged")
        for line in statements[6...] { events += s.feed(line + "\n") }
        XCTAssertEqual(F.refusals(events).count, 2, "later valid statements all apply")
        var clean = F.session()
        clean.feed(try F.stream())
        XCTAssertEqual(s.state, clean.state)
    }

    // MARK: S3 first visible before the end (measured with an injected clock)

    func testS3FirstPresentedComesRightAfterTheSceneStatement() throws {
        let clock = MGManualClock()
        var s = F.session(.estimate(wordsPerSecond: 2.5), clock: clock)
        var marks: [(statement: Int, event: MGLessonEvent, at: Duration)] = []
        for (i, line) in try F.statements().enumerated() {
            clock.advance(by: .milliseconds(10))
            for e in s.feed(line + "\n") { marks.append((i, e, clock.now)) }
        }
        let first = try XCTUnwrap(marks.first { $0.event == .firstPresented })
        let ended = try XCTUnwrap(marks.first { $0.event == .streamEnded })
        XCTAssertEqual(first.statement, 1)
        XCTAssertLessThan(first.at, ended.at)
        XCTAssertEqual(first.at, .milliseconds(20))
        XCTAssertEqual(ended.at, .milliseconds(200))
        print("S3 injected clock: firstPresented=\(first.at) streamEnded=\(ended.at)")
    }

    // MARK: S4 say-beat timing events in order

    func testS4SpeechPacingEventOrder() throws {
        let clock = MGManualClock()
        var s = F.session(.speech, clock: clock)
        s.feed(try F.stream())
        for k in 0..<5 {
            let log = s.events
            let queued = try XCTUnwrap(log.firstIndex { $0.name == "lineQueued" && $0.beat == k })
            let due = try XCTUnwrap(log.firstIndex { $0.name == "lineDue" && $0.beat == k })
            let presented = try XCTUnwrap(log.firstIndex { $0.name == "beatPresented" && $0.beat == k })
            XCTAssertLessThan(queued, due); XCTAssertLessThan(due, presented)
            XCTAssertFalse(log.contains { $0.name == "lineDue" && $0.beat == k + 1 }, "beat \(k + 1) due before line \(k) ended")
            if k == 1 {
                // Ending a line that is not open is ignored and recorded; no event changes.
                let count = s.history.count
                XCTAssertEqual(s.lineEnded(2), [])
                XCTAssertEqual(s.history.count, count)
                XCTAssertEqual(s.hostIssues.last?.reason, "line.order")
            }
            XCTAssertEqual(s.lineStarted(k), [.lineStarted(beat: k)])
            clock.advance(by: k < 4 ? .seconds(2) : .milliseconds(500))
            let after = s.lineEnded(k)
            XCTAssertEqual(after.first, .lineEnded(beat: k))
            if k < 4 { XCTAssertEqual(after.dropFirst().first?.name, "lineDue") }
        }
        XCTAssertFalse(s.isComplete)
        XCTAssertTrue(s.events.contains(.streamEnded))
        clock.advance(by: .milliseconds(1000))
        XCTAssertEqual(s.tick(), [.lessonComplete], "after the last line and the 1.5 s turn have settled")
        XCTAssertEqual(s.events.last, .lessonComplete)
    }

    func testS4EstimatePacingSpacesLinesByWordCount() throws {
        let clock = MGManualClock()
        var s = F.session(.estimate(wordsPerSecond: 2.5), clock: clock)
        s.feed(try F.stream())
        var dueAt: [Int: Duration] = [:], text: [Int: String] = [:]
        func collect() { for r in s.history { if case .lineDue(let k, let t, _) = r.event, dueAt[k] == nil { dueAt[k] = r.at; text[k] = t } } }
        collect()
        var guardCount = 0
        while !s.isComplete, let wake = s.nextWake, guardCount < 50 {
            clock.advance(by: max(.zero, wake - clock.now)); s.tick(); collect(); guardCount += 1
        }
        XCTAssertTrue(s.isComplete)
        XCTAssertEqual(dueAt.count, 5)
        var total = Duration.zero
        for k in 0..<4 {
            let expected = MGLessonSession.lineDuration(text[k]!, wordsPerSecond: 2.5)
            let words = Double(text[k]!.split(separator: " ").count)
            XCTAssertEqual(expected, .milliseconds(Int64((min(12, max(1, words / 2.5)) * 1000).rounded())))
            XCTAssertEqual(dueAt[k + 1]! - dueAt[k]!, expected, "beat \(k)")
            total += expected
        }
        // T4b on the injected clock: lineDue(0) → lessonComplete = Σ line durations (+ the last settle if longer).
        let last = MGLessonSession.lineDuration(text[4]!, wordsPerSecond: 2.5)
        let complete = try XCTUnwrap(s.history.first { $0.event == .lessonComplete }).at
        XCTAssertEqual(complete - dueAt[0]!, total + max(last, .milliseconds(1500)))
        print("T4b injected clock: lineDue(0) → lessonComplete = \(complete - dueAt[0]!) (lines \(total + last))")
    }

    // MARK: S5 finishNow

    func testS5FinishNowPresentsTheRestInOrder() throws {
        var s = F.session(.speech)
        s.feed(try F.stream())
        XCTAssertEqual(s.openLine, 0)
        let events = s.finishNow()
        XCTAssertEqual(events.filter { $0.name == "beatPresented" }.map(\.beat), [1, 2, 3, 4])
        XCTAssertEqual(events.filter { $0.name == "lineDue" }.map(\.beat), [1, 2, 3, 4])
        XCTAssertEqual(events.first, .lineEnded(beat: 0))
        XCTAssertEqual(events.last, .lessonComplete)
        var immediate = F.session()
        immediate.feed(try F.stream())
        XCTAssertEqual(s.state, immediate.state)
    }

    // MARK: S6 follow-up keeps the scene

    func testS6FollowUpKeepsIdsAndStateAndANewSceneReplaces() throws {
        var s = F.session()
        s.feed(try F.stream())
        let before = s.state!
        let events = s.feed([#"{"keep":true}"#, #"{"say":"Look at B: ({bx}, {by})."}"#,
                             #"{"op":"add","item":{"id":"hiB","k":"highlight","target":"vB"}}"#, #"{"end":true}"#].joined(separator: "\n") + "\n")
        XCTAssertEqual(F.refusals(events), [])
        XCTAssertTrue(events.contains(.beatPresented(beat: 5)), "beat numbers continue")
        XCTAssertTrue(events.contains(.lineDue(beat: 5, text: "Look at B: (-4, -1).", changed: false)))
        for item in before.scene.items { XCTAssertEqual(s.state?.scene.item(item.id), item) }
        XCTAssertNotNil(s.state?.scene.item("hiB"))
        XCTAssertEqual(s.state?.controls, before.controls)
        // A new stream with a scene and no keep replaces the lesson.
        s.feed(#"{"scene":{"v":1,"template":"rotate2d","params":{"pts":[[1,1],[3,1],[1,2]]}}}"# + "\n")
        XCTAssertEqual(s.state?.beat, -1)
        XCTAssertEqual(s.state?.controls, [])
        XCTAssertNil(s.state?.scene.item("hiB"))
        s.endStream()
        // keep followed by a scene is out of order.
        XCTAssertEqual(F.refusals(s.feed(#"{"keep":true}"# + "\n" + #"{"scene":{"v":1,"template":"rotate2d","params":{"pts":[[1,1],[3,1],[1,2]]}}}"# + "\n")).map(\.reason), ["stmt.order"])
    }

    // MARK: S7 garbage is refused and the stream continues

    func testS7GarbageIsRefusedAndTheStreamContinues() throws {
        var s = F.session()
        XCTAssertEqual(F.refusals(s.feed(#"{"op":"remove","id":"x"}"# + "\n")).map(\.reason), ["stmt.order"], "a command before any scene")
        s.feed(try F.statements()[1] + "\n")
        let cases: [(String, String)] = [
            ("[1,2]", "stmt.kind"), (#"{"say":3}"#, "stmt.say"), (#"{"say":"see <b>this</b>"}"#, "stmt.say"),
            (#"{"x":1}"#, "stmt.kind"), (#"{"end":"yes"}"#, "stmt.kind"),
            (#"{"lesson":{"v":1}}"#, "stmt.order"), (#"{"say":"{zz} moved."}"#, "stmt.say.placeholder.zz"),
            (#"{"a":}"#, "stmt.json"),
        ]
        for (text, reason) in cases { XCTAssertEqual(F.refusals(s.feed(text + "\n")).map(\.reason), [reason], text) }
        let garbage = s.feed("model chatter here, then ")
        XCTAssertEqual(garbage, [], "garbage is reported when the next statement starts")
        let next = s.feed(#"{"say":"Still going."}"# + "\n")
        XCTAssertEqual(F.refusals(next).map(\.reason), ["stmt.json"], "reported once")
        XCTAssertTrue(next.contains { if case .accepted = $0 { return true }; return false })
        XCTAssertEqual(F.refusals(s.feed("trailing")), [])
        XCTAssertEqual(F.refusals(s.endStream()).map(\.reason), ["stmt.json"])
        XCTAssertEqual(s.state?.beat, 0, "the valid beat was presented")
    }

    // MARK: S8 pause and resume

    func testS8PauseHoldsBeatsButStatementsStillValidate() throws {
        let clock = MGManualClock()
        var s = F.session(.estimate(wordsPerSecond: 2.5), clock: clock)
        let lines = try F.statements()
        for line in lines[0...6] { s.feed(line + "\n") }        // beat 1 is complete, beat 0 is being spoken
        clock.advance(by: .seconds(30)); s.tick()                // beat 0 ends, beat 1 becomes due
        XCTAssertEqual(s.openLine, 1)
        s.pause()
        var held: [MGLessonEvent] = []
        for line in lines[7...] { held += s.feed(line + "\n") }
        clock.advance(by: .seconds(60)); held += s.tick()
        XCTAssertFalse(held.contains { $0.name == "lineDue" || $0.name == "beatPresented" }, "\(held)")
        XCTAssertEqual(held.filter { $0.name == "lineQueued" }.map(\.beat), [2, 3, 4])
        XCTAssertEqual(s.projected?.beat, 4, "statements validated while paused")
        XCTAssertEqual(s.state?.beat, 1)
        XCTAssertNil(s.nextWake)
        let resumed = s.resume()
        XCTAssertEqual(resumed, [], "the rest of line 1 still plays")
        var guardCount = 0
        while !s.isComplete, let wake = s.nextWake, guardCount < 50 { clock.advance(by: max(.zero, wake - clock.now)); s.tick(); guardCount += 1 }
        let order = s.events.filter { ["lineDue", "beatPresented", "lineEnded"].contains($0.name) }.map { "\($0.name)\($0.beat!)" }
        XCTAssertEqual(order, ["lineDue0", "beatPresented0", "lineEnded0", "lineDue1", "beatPresented1", "lineEnded1",
                               "lineDue2", "beatPresented2", "lineEnded2", "lineDue3", "beatPresented3", "lineEnded3",
                               "lineDue4", "beatPresented4", "lineEnded4"])
        XCTAssertEqual(s.events.last, .lessonComplete)
    }

    // MARK: U12 determinism

    func testU12TwentyRunsGiveIdenticalStateAndEvents() throws {
        var states: Set<Data> = [], sequences: [[MGLessonEvent]] = []
        for _ in 0..<20 {
            var s = F.session()
            s.feed(try F.stream())
            states.insert(s.state!.canonical)
            sequences.append(s.events)
        }
        XCTAssertEqual(states.count, 1)
        XCTAssertTrue(sequences.allSatisfy { $0 == sequences[0] })
        var hash: UInt64 = 0xcbf29ce484222325
        for b in states.first! { hash = (hash ^ UInt64(b)) &* 0x100000001b3 }
        print("U12 final state FNV-1a: \(String(hash, radix: 16)) (\(states.first!.count) bytes)")
    }
}
