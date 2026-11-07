// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import MartyGraphics   // the load test builds an MGLesson directly, bypassing parse

/// Lesson values built in code with NaN or an infinity have no JSON form. They must be refused with `lesson.number` /
/// `snapshot.number`, atomically, and never become an empty statement that is silently skipped. Finite extremes
/// (negative zero, 1e300, the largest finite double) keep their ordinary behaviour.
final class LessonNumericTests: XCTestCase {
    static let values: [(String, Double)] = [("nan", .nan), ("inf", .infinity), ("negative_inf", -.infinity),
                                             ("negative_zero", -0.0), ("huge", 1e300), ("largest", .greatestFiniteMagnitude)]

    var scene: MGJSON {
        .object(["v": .number(1), "items": .array([.object(["id": .string("probe"), "k": .string("node"), "at": .array([.number(2), .number(2)]), "text": .string("p")])])])
    }

    func lesson(op: MGJSON? = nil, check: MGJSON? = nil) -> MGJSON {
        var beat: [String: MGJSON] = ["say": .string("Synthetic step")]
        if let op { beat["ops"] = .array([op]) }
        if let check { beat["check"] = .array([check]) }
        return .object(["v": .number(1), "kind": .string("lesson"), "scene": scene, "beats": .array([.object(beat)])])
    }

    func testNonFiniteCommandsAndChecksAreRefusedNotDropped() throws {
        for (name, value) in Self.values {
            let command = MGJSON.object(["op": .string("set"), "id": .string("probe"), "key": .string("at"), "value": .array([.number(value), .number(2)])])
            let check = MGJSON.object(["value": .string("missing"), "eq": .number(value)])
            for (kind, input) in [("command", lesson(op: command)), ("check", lesson(check: check))] {
                let parsed = MGLesson.parse(json: input)
                if value.isFinite {
                    // Finite values parse; whatever `load` then decides, every statement reaches the session.
                    let built = try parsed.get()
                    XCTAssertFalse(built.statementStream.contains("\n\n"), "\(kind).\(name): no empty statement line")
                } else {
                    guard case .failure(let e) = parsed else { XCTFail("\(kind).\(name) was accepted"); continue }
                    XCTAssertEqual(e.reason, "lesson.number", "\(kind).\(name)")
                }
            }

            // Direct apply: refused atomically, the state is unchanged.
            var session = MGLessonSession()
            _ = try session.load(MGLesson.parse(json: lesson()).get()).get()
            let before = session.state
            switch session.apply(command) {
            case .failure(let error):
                XCTAssertEqual(session.state, before, "direct.\(name)")
                if !value.isFinite { XCTAssertEqual(error.reason, "lesson.number", "direct.\(name)") }
            case .success:
                XCTAssertTrue(value.isFinite, "direct.\(name) accepted a non-finite value")
            }

            // Snapshot restore: a non-finite field refuses the whole snapshot.
            var snapshot = try XCTUnwrap(session.snapshot().objectValue)
            snapshot["settleLeft"] = .number(value)
            switch MGLessonSession.restore(.object(snapshot), pacing: .immediate) {
            case .failure(let error): if !value.isFinite { XCTAssertEqual(error.reason, "snapshot.number", "restore.\(name)") }
            case .success: XCTAssertTrue(value.isFinite, "restore.\(name) accepted a non-finite value")
            }
        }
    }

    /// `load` refuses an unencodable statement (it would serialise to an empty line the scanner skips) and leaves the
    /// session unchanged.
    func testLoadRefusesAnUnencodableStatementAtomically() throws {
        var session = MGLessonSession()
        _ = try session.load(MGLesson.parse(json: lesson()).get()).get()
        let before = session.state
        for (op, check) in [(MGJSON.object(["op": .string("set"), "id": .string("probe"), "key": .string("r"), "value": .number(.nan)]), nil),
                            (nil, MGJSON.object(["value": .string("missing"), "eq": .number(.infinity)]))] as [(MGJSON?, MGJSON?)] {
            let direct = MGLesson(title: nil, scene: scene, beats: [MGLesson.Beat(say: "Synthetic step", ops: op.map { [$0] } ?? [], checks: check.map { [$0] } ?? [])])
            guard case .failure(let e) = session.load(direct) else { XCTFail("unencodable statement was loaded"); continue }
            XCTAssertEqual(e.reason, "lesson.number")
            XCTAssertEqual(e.statement, 3)                                   // header, scene, say, then the bad statement
            XCTAssertEqual(session.state, before)
        }
    }

    func testNonFiniteCommandCannotHideAnOversizedPayload() {
        let bad = MGJSON.object(["op": .string("set"), "id": .string("probe"), "key": .string("text"), "value": .number(.nan),
                                 "padding": .string(String(repeating: "x", count: 40_000))])
        let input = lesson(op: bad)
        XCTAssertEqual(input.canonicalByteCount, Int.max)
        guard case .failure(let e) = MGLesson.parse(json: input) else { return XCTFail("an unencodable command hid a 40,000-byte payload") }
        XCTAssertEqual(e.reason, "lesson.number")
        // A finite command with the same payload is measured and refused by size.
        let big = MGJSON.object(["op": .string("set"), "id": .string("probe"), "key": .string("text"), "value": .string("x"),
                                 "padding": .string(String(repeating: "x", count: 40_000))])
        guard case .failure(let e2) = MGLesson.parse(json: lesson(op: big)) else { return XCTFail("oversized lesson accepted") }
        XCTAssertEqual(e2.reason, "lesson.bytes")
    }
}
