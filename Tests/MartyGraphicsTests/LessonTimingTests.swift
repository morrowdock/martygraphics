// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import MartyGraphics

/// Acceptance group T on this machine (core only). Numbers are printed, not gated: the proposed budgets apply to a
/// physical-device receipt. The ceilings asserted here are loose guards against gross regressions in a debug build.
/// Release numbers: `swift run -c release --package-path Examples/LessonDemo lesson-demo --timing`.
final class LessonTimingTests: LessonTestCase {
    typealias F = LessonFixture

    static func measure(_ runs: Int, _ body: () throws -> Void) rethrows -> (median: Double, p95: Double) {
        var samples: [Double] = []
        let clock = ContinuousClock()
        for _ in 0..<runs {
            let d = try clock.measure(body)
            samples.append(Double(d.components.attoseconds) / 1e15 + Double(d.components.seconds) * 1000)
        }
        samples.sort()
        return (samples[samples.count / 2], samples[min(samples.count - 1, Int(Double(samples.count) * 0.95))])
    }

    func testTimingCoreOperations() throws {
        let statements = try F.statements(), stream = try F.stream()
        let t1b = Self.measure(50) {
            var s = F.session(); s.feed(statements[0] + "\n")
            let e = s.feed(statements[1] + "\n")
            XCTAssertTrue(e.contains(.firstPresented))
        }
        var tick = try F.through(beat: 3), angle = 0.0
        let t2 = try Self.measure(200) { angle = angle >= 355 ? 0 : angle + 5; _ = try tick.control("angle", angle).get() }
        let start = try F.through(beat: 3).state!.scene
        let t3 = try Self.measure(30) { _ = try MGTween.keyframes(start, param: "angle", to: 180).get() }
        let t4a = Self.measure(30) { var s = F.session(); XCTAssertTrue(s.feed(stream).contains(.streamEnded)) }
        func row(_ name: String, _ m: (median: Double, p95: Double)) -> String { String(format: "%@ median %.3f ms p95 %.3f ms", name, m.median, m.p95) }
        print(["T1b scene statement → firstPresented", "T2 control tick", "T3 animate 0→180 (36 keyframes)", "T4a full stream → streamEnded"]
            .enumerated().map { row($0.element, [t1b, t2, t3, t4a][$0.offset]) }.joined(separator: "\n"))
        XCTAssertLessThan(t1b.p95, 50); XCTAssertLessThan(t2.p95, 20); XCTAssertLessThan(t3.p95, 200); XCTAssertLessThan(t4a.p95, 300)
    }
}
