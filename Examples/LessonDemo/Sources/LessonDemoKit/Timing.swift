// SPDX-License-Identifier: Apache-2.0
import Foundation
import SwiftUI
import MartyGraphics

/// Timing receipts on the machine that runs them (acceptance group T). Time to first visible and time to complete are
/// separate rows. Not device numbers: a physical iPad receipt is still pending.
public enum LessonTiming {
    public struct Row { public let name: String; public let median: Double; public let p95: Double; public let runs: Int }

    static func ms(_ d: Duration) -> Double { Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15 }

    static func sample(_ runs: Int, _ body: () -> Duration) -> (Double, Double) {
        var values = (0..<runs).map { _ in ms(body()) }
        values.sort()
        return (values[values.count / 2], values[min(values.count - 1, Int(Double(values.count) * 0.95))])
    }

    @MainActor public static func run() -> [Row] {
        RotationLesson.register()
        let clock = ContinuousClock()
        guard let statements = try? RotationLesson.statements() else { return [] }
        let stream = statements.joined(separator: "\n") + "\n"
        var rows: [Row] = []
        func add(_ name: String, _ runs: Int, _ body: () -> Duration) { let s = sample(runs, body); rows.append(Row(name: name, median: s.0, p95: s.1, runs: runs)) }

        // T1b: scene statement complete → firstPresented (core).
        add("T1b scene statement → firstPresented (core)", 200) {
            var s = MGLessonSession(clock: MGManualClock()); s.feed(statements[0] + "\n")
            return clock.measure { _ = s.feed(statements[1] + "\n") }
        }
        // T1: scene statement complete → first frame drawn offscreen (core + Canvas draw at 1024 × 768 via ImageRenderer).
        add("T1 scene statement → first offscreen frame 1024×768", 30) {
            var s = MGLessonSession(clock: MGManualClock()); s.feed(statements[0] + "\n")
            return clock.measure {
                s.feed(statements[1] + "\n")
                let scene = s.state!.scene
                let size = CGSize(width: 1024, height: 768)
                let input = MGRenderInput(scene: scene, items: MGTimeline.items(scene, step: 0),
                                          viewport: MGViewport(size: size, width: scene.width, height: scene.height, camera: nil))
                _ = ImageRenderer(content: Canvas { ctx, _ in MGCanvasRenderer.draw(input, in: ctx) }.frame(width: size.width, height: size.height)).cgImage
            }
        }
        // T2: learner control tick → state committed.
        var tick = MGLessonSession(clock: MGManualClock())
        if let lesson = try? RotationLesson.lesson() { _ = tick.load(lesson) }
        var angle = 0.0
        add("T2 learner control tick → committed", 500) {
            angle = angle >= 355 ? 0 : angle + 5
            return clock.measure { _ = tick.control("angle", angle) }
        }
        // T3: animate 0 → 180 keyframes.
        var base = MGLessonSession(clock: MGManualClock()); base.feed(statements[0...1].joined(separator: "\n") + "\n")
        let start = base.state!.scene
        add("T3 animate 0→180 (36 keyframes) → ready", 100) { clock.measure { _ = MGTween.keyframes(start, param: "angle", to: 180) } }
        // T4a: first byte fed → streamEnded (replayed, no model).
        add("T4a full lesson fed → streamEnded", 100) { var s = MGLessonSession(clock: MGManualClock()); return clock.measure { _ = s.feed(stream) } }
        // T4b: lineDue(0) → lessonComplete at estimate(2.5) on an injected clock (pacing arithmetic, not wall time).
        let manual = MGManualClock()
        var paced = MGLessonSession(pacing: .estimate(wordsPerSecond: 2.5), clock: manual)
        paced.feed(stream)
        while !paced.isComplete, let wake = paced.nextWake { manual.advance(by: max(.zero, wake - manual.now)); paced.tick() }
        let due0 = paced.history.first { $0.event.name == "lineDue" }?.at ?? .zero
        let done = paced.history.first { $0.event == .lessonComplete }?.at ?? .zero
        rows.append(Row(name: "T4b lineDue(0) → lessonComplete at estimate(2.5), injected clock", median: ms(done - due0), p95: ms(done - due0), runs: 1))
        return rows
    }

    public static func report(_ rows: [Row]) -> String {
        var host = utsname(); uname(&host)
        let machine = withUnsafeBytes(of: &host.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        #if DEBUG
        let config = "debug"
        #else
        let config = "release"
        #endif
        var out = ["machine \(machine), \(os), \(config) build, \(ProcessInfo.processInfo.activeProcessorCount) cores"]
        for r in rows { out.append(String(format: "%@: median %.3f ms, p95 %.3f ms (%d runs)", r.name, r.median, r.p95, r.runs)) }
        return out.joined(separator: "\n")
    }
}
