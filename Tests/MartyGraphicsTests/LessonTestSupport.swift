// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import MartyGraphics

/// Shared fixtures and an independent reference for the lesson tests. The reference rotation is computed here, never
/// read back from the engine. Beats and statements are zero-based (beat n in docs prose = index n − 1).
enum LessonFixture {
    static let triangle: [(Double, Double)] = [(2, 1), (4, 1), (2, 3)]

    static var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }
    static func file(_ name: String) throws -> Data { try Data(contentsOf: root.appendingPathComponent("docs/fixtures/v1/" + name)) }

    static func lesson() throws -> MGLesson { try MGLesson.parse(data: file("rotation.lesson.json")).get() }
    static func statements() throws -> [String] {
        String(decoding: try file("rotation.statements.ndjson"), as: UTF8.self).split(separator: "\n").map(String.init)
    }
    static func stream() throws -> String { try statements().joined(separator: "\n") + "\n" }

    static func session(_ pacing: MGPacing = .immediate, clock: MGManualClock = MGManualClock()) -> MGLessonSession {
        MGLessonSession(pacing: pacing, clock: clock)
    }

    /// The fixture fed as a stream with only the statements of beats 0…`beat` (and the end of the stream), immediate pacing.
    static func through(beat: Int) throws -> MGLessonSession {
        var s = session()
        var beats = -1
        for line in try statements() {
            if line.hasPrefix(#"{"say""#) { beats += 1; if beats > beat { break } }
            if line == #"{"end":true}"# { break }
            s.feed(line + "\n")
        }
        s.endStream()
        XCTAssertEqual(s.state?.beat, beat)
        return s
    }

    /// x′, y′ of `p` turned by `degrees` about `pivot`.
    static func rotate(_ p: (Double, Double), _ degrees: Double, pivot: (Double, Double) = (0, 0)) -> (Double, Double) {
        let a = degrees * .pi / 180, dx = p.0 - pivot.0, dy = p.1 - pivot.1
        return (pivot.0 + dx * cos(a) - dy * sin(a), pivot.1 + dx * sin(a) + dy * cos(a))
    }
    /// Half a unit of the last digit `MGPhysics.format` shows.
    static func tol(_ v: Double) -> Double { abs(v) < 10 ? 0.005 : abs(v) < 100 ? 0.05 : 0.5 }
    /// "A (1.23, -0.13)" → [1.23, -0.13].
    static func numbers(_ label: String) -> [Double] {
        let pattern = try! NSRegularExpression(pattern: #"-?\d+(\.\d+)?"#)
        return pattern.matches(in: label, range: NSRange(label.startIndex..., in: label)).compactMap {
            Range($0.range, in: label).flatMap { Double(label[$0]) }
        }
    }

    static func json(_ s: String) -> MGJSON { MGJSON(any: try! JSONSerialization.jsonObject(with: Data(s.utf8)))! }
    static func refusals(_ events: [MGLessonEvent]) -> [MGLessonIssue] {
        events.compactMap { if case .refused(let i) = $0 { return i } else { return nil } }
    }
    static func lineDue(_ events: [MGLessonEvent]) -> [String] {
        events.compactMap { if case .lineDue(_, let text, _) = $0 { return text } else { return nil } }
    }
    /// Events without the statement-level acknowledgements (for comparing a document load with a stream).
    static func beatEvents(_ events: [MGLessonEvent]) -> [MGLessonEvent] {
        events.filter { if case .accepted = $0 { return false }; return true }
    }
}

/// Deterministic generator so failures reproduce.
struct LessonRNG: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        var z = state; z = (z ^ (z >> 33)) &* 0xff51afd7ed558ccd; return z ^ (z >> 33)
    }
}

extension Result where Failure == MGLessonIssue {
    var failureReason: String? { if case .failure(let e) = self { return e.reason }; return nil }
}

/// Registers the opt-in geometry pack per test and drops it afterwards, like the graph pack tests.
class LessonTestCase: XCTestCase {
    override func setUp() { super.setUp(); try? MGPacks.register(MGGeometryPack.pack) }
    override func tearDown() { MGPacks.resetRegistered(); super.tearDown() }
}
