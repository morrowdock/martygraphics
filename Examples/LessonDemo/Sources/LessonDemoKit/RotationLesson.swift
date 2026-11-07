// SPDX-License-Identifier: Apache-2.0
import Foundation
import MartyGraphics

/// The rotation lesson (example content, synthetic): a triangle turned about the origin, an angle slider, and
/// coordinate labels bound to engine-computed rotated vertices. The same JSON is `docs/fixtures/v1/rotation.*`
/// (a test keeps the copies equal).
public enum RotationLesson {
    /// Lesson document (L1). Every number the learner sees comes from `{name}` engine values.
    public static let document = #"""
    {"v":1,"kind":"lesson","title":"Rotating a triangle",
     "scene":{"v":1,"template":"rotate2d","params":{"pts":[[2,1],[4,1],[2,3]],"angle":0}},
     "beats":[
      {"say":"This is triangle ABC. Each label shows a corner's coordinates.",
       "ops":[{"op":"add","item":{"id":"hiA","k":"highlight","target":"vA","label":"A"}}]},
      {"say":"Now we turn the triangle about the origin O by {theta}.",
       "ops":[{"op":"animate","param":"angle","to":90,"dur":1.5}]},
      {"say":"A moved from ({ax0}, {ay0}) to ({ax}, {ay}). Its distance to O is still {ra}.",
       "ops":[{"op":"set","id":"hiA","key":"label","value":"A after the turn"}],
       "check":[{"value":"ax","eq":-1},{"value":"ay","eq":2},{"value":"ra","eq":2.24}]},
      {"say":"Your turn. Drag the slider. The engine moves the triangle and updates every label.",
       "ops":[{"op":"remove","id":"hiA"},
              {"op":"bind","control":{"id":"angle","k":"slider","param":"angle","min":0,"max":360,"step":5,"label":"Angle"}}]},
      {"say":"At {theta} every coordinate changes sign. A is now at ({ax}, {ay}).",
       "ops":[{"op":"animate","param":"angle","to":180,"dur":1.5},
              {"op":"add","item":{"id":"hiShape","k":"highlight","target":"shape","label":"half a turn"}}],
       "check":[{"value":"ax","eq":-2},{"value":"ay","eq":-1}]}
     ]}
    """#

    /// Registers the opt-in geometry pack once per process.
    public static func register() {
        if MGPacks.pack(ofTemplate: "rotate2d") == nil { try? MGPacks.register(MGGeometryPack.pack) }
    }

    public static func lesson() throws -> MGLesson {
        register()
        return try MGLesson.parse(data: Data(document.utf8)).get()
    }

    /// The lesson as a statement stream (lane B surface): one JSON object per line.
    public static func statements() throws -> [String] { try lesson().statements.map(\.canonicalString) }

    /// A short, stable fingerprint of a lesson state (canonical scene source + beat + controls), FNV-1a 64.
    public static func fingerprint(_ state: MGLessonState?) -> String {
        guard let state else { return "none" }
        var hash: UInt64 = 0xcbf29ce484222325
        for b in state.canonical { hash = (hash ^ UInt64(b)) &* 0x100000001b3 }
        return String(hash, radix: 16)
    }

    /// Reference rotation, computed here (not read back from the engine).
    static func rotate(_ p: (Double, Double), _ degrees: Double) -> (Double, Double) {
        let a = degrees * .pi / 180
        return (p.0 * cos(a) - p.1 * sin(a), p.0 * sin(a) + p.1 * cos(a))
    }
    static func label(_ letter: String, _ p: (Double, Double)) -> String {
        "\(letter) (\(MGPhysics.format(p.0, unit: "")), \(MGPhysics.format(p.1, unit: "")))"
    }

    /// Headless scripted check through the real engine (no window, no gestures): beats, labels, the slider, same
    /// state for slider and script, refusal keeps state, streaming first-visible, speech event order, snapshot.
    /// It checks state, narration and validation only, not what the board looks like.
    public static func verify() -> (ok: Bool, lines: [String]) {
        var lines: [String] = [], ok = true
        func check(_ label: String, _ condition: Bool) { lines.append((condition ? "PASS " : "FAIL ") + label); ok = ok && condition }
        do {
            let lesson = try lesson()
            let triangle = [("A", (2.0, 1.0)), ("B", (4.0, 1.0)), ("C", (2.0, 3.0))]
            func labels(_ s: MGLessonSession) -> [String] { ["lA", "lB", "lC"].compactMap { s.state?.scene.item($0)?.text } }
            func expected(_ angle: Double) -> [String] { triangle.map { label($0.0, rotate($0.1, angle)) } }

            var s = MGLessonSession(pacing: .speech, clock: MGManualClock())
            check("lesson loads (5 beats, all checks pass)", (try? s.load(lesson).get()) != nil)
            check("beat 1 caption", s.caption == "This is triangle ABC. Each label shows a corner's coordinates.")
            check("beat 1 labels A (2, 1), B (4, 1), C (2, 3)", labels(s) == expected(0))
            s.lineEnded(0)
            check("beat 2 turns to 90° with 18 engine keyframes", { if case .keyframes(let seg)? = s.lastChange?.transition { return seg.count == 1 && seg[0].frames.count == 19 }; return false }())
            check("beat 2 caption says 90°", s.caption == "Now we turn the triangle about the origin O by 90°.")
            s.lineEnded(1)
            check("beat 3 caption from engine values", s.caption == "A moved from (2, 1) to (-1, 2). Its distance to O is still 2.24.")
            check("beat 3 labels A (-1, 2), B (-1, 4), C (-3, 2)", labels(s) == expected(90))
            s.lineEnded(2)
            check("beat 4 binds the angle slider", s.state?.controls.map(\.id) == ["angle"])
            var script = s
            check("slider to 90° accepted", (try? s.control("angle", 90).get()) != nil)
            check("slider at 90° labels", labels(s) == expected(90))
            _ = script.apply(.object(["op": .string("params"), "params": .object(["angle": .number(90)])]))
            check("slider and scripted params give the same state", fingerprint(s.state) == fingerprint(script.state))
            for a in stride(from: 0.0, through: 360, by: 5) { _ = s.control("angle", a); if labels(s) != expected(a) { check("labels at \(a)°", false) } }
            check("labels match the reference at every 5° step", ok)
            let before = s.state
            check("slider 361° refused (control.value), state kept", s.control("angle", 361).failureReason == "control.value" && s.state == before)
            check("invalid command refused (highlight.target), state kept",
                  s.apply(.object(["op": .string("add"), "item": .object(["id": .string("h"), "k": .string("highlight"), "target": .string("nope")])])).failureReason == "highlight.target" && s.state == before)
            _ = s.control("angle", 45)
            let snap = s.snapshot()
            let restored = try MGLessonSession.restore(snap, pacing: .speech, clock: s.clock).get()
            check("snapshot at 45° restores the same state", restored.state == s.state)
            s.lineEnded(3)
            check("beat 5 sets the angle itself: caption says 180° and (-2, -1)", s.caption == "At 180° every coordinate changes sign. A is now at (-2, -1).")
            check("beat 5 labels", labels(s) == expected(180))
            s.lineEnded(4)
            check("no refusals during the lesson", !s.events.contains { if case .refused = $0 { return $0.beat != nil }; return false })

            // Streaming: the figure is visible after the second statement.
            var stream = MGLessonSession(pacing: .estimate(wordsPerSecond: 2.5), clock: MGManualClock())
            let statements = try self.statements()
            var firstAt: Int?
            for (i, line) in statements.enumerated() where firstAt == nil {
                if stream.feed(line + "\n").contains(.firstPresented) { firstAt = i }
            }
            check("streamed: first visible after statement index 1 (\(statements[0].utf8.count + statements[1].utf8.count + 2) bytes)", firstAt == 1)
            var bad = MGLessonSession(pacing: .immediate, clock: MGManualClock())
            bad.feed(statements[0...3].joined(separator: "\n") + "\n")
            let marks = bad.projected?.scene.items
            let refused = bad.feed(#"{"op":"add","item":{"id":"bad","k":"rocket"}}"# + "\n")
            check("streamed refusal keeps earlier marks", refused.contains { if case .refused(let i) = $0 { return i.reason == "item.kind" }; return false } && bad.projected?.scene.items == marks)
        } catch {
            check("unexpected error \(error)", false)
        }
        return (ok, lines)
    }
}

extension Result where Failure == MGLessonIssue {
    var failureReason: String? { if case .failure(let e) = self { return e.reason }; return nil }
}
