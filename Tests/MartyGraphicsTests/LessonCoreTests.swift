// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import MartyGraphics

/// Acceptance group U (Foundation-only core). This file imports only Foundation and XCTest.
final class LessonCoreTests: LessonTestCase {
    typealias F = LessonFixture

    // MARK: U1 core imports

    func testU1CoreFilesImportOnlyFoundation() throws {
        let sources = F.root.appendingPathComponent("Sources/MartyGraphics")
        let tests = F.root.appendingPathComponent("Tests/MartyGraphicsTests")
        let core = ["MGLesson.swift", "MGLessonSession.swift", "MGLessonSnapshot.swift", "MGSceneDiff.swift", "MGTween.swift", "MGGeometryPack.swift"]
            .map { sources.appendingPathComponent($0) }
        let coreTests = ["LessonCoreTests.swift", "LessonStreamTests.swift", "LessonTestSupport.swift"].map { tests.appendingPathComponent($0) }
        for url in core + coreTests {
            let imports = try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.hasPrefix("import ") || $0.hasPrefix("@testable import ") }
            let allowed: Set<String> = core.contains(url) ? ["import Foundation"] : ["import Foundation", "import XCTest", "@testable import MartyGraphics"]
            XCTAssertFalse(imports.isEmpty, url.lastPathComponent)
            for line in imports { XCTAssertTrue(allowed.contains(line), "\(url.lastPathComponent): \(line)") }
        }
    }

    // MARK: U2 document parse

    func testU2DocumentParsesAndBadDocumentsAreRefusedWithoutState() throws {
        let lesson = try F.lesson()
        XCTAssertEqual(lesson.beats.count, 5)
        XCTAssertEqual(lesson.title, "Rotating a triangle")
        var ok = F.session()
        XCTAssertNoThrow(try ok.load(lesson).get())
        XCTAssertEqual(ok.state?.beat, 4)

        let base = try JSONSerialization.jsonObject(with: F.file("rotation.lesson.json")) as! [String: Any]
        func variant(_ change: (inout [String: Any]) -> Void) -> MGJSON { var d = base; change(&d); return MGJSON(any: d)! }
        let beat: [String: Any] = ["say": "Look."]
        let cases: [(MGJSON, String)] = [
            (variant { $0["extra"] = 1 }, "lesson.unknown.extra"),
            (variant { $0["v"] = 2 }, "lesson.version"),
            (variant { $0["beats"] = Array(repeating: beat, count: 25) }, "lesson.beats.count"),
            (variant { $0["beats"] = [["say": "Many.", "ops": Array(repeating: ["op": "remove", "id": "ghost"], count: 13)]] }, "beat.ops.count"),
            (variant { $0["scene"] = ["v": 1, "items": [["id": "a", "k": "body", "at": [1, 1]]], "steps": [["say": "x"]]] }, "lesson.scene.steps"),
            (variant { $0["beats"] = [["say": "Jump.", "ops": [["op": "step", "index": 0]]]] }, "lesson.op.step"),
            (variant { $0["beats"] = [["say": "Steps.", "ops": [["op": "steps", "steps": []]]]] }, "lesson.op.steps"),
            (variant { $0["beats"] = [["say": "Dim.", "ops": [["op": "dim", "dim": "3d"]]]] }, "lesson.op.dim"),
            (variant { $0["beats"] = Array(repeating: ["say": String(repeating: "word ", count: 300)], count: 24) }, "lesson.bytes"),
        ]
        for (json, reason) in cases {
            XCTAssertEqual(MGLesson.parse(json: json).failureReason, reason)
        }
        // Shape-valid documents are then validated by the engine, all-or-nothing, with the location of the problem.
        var s = F.session()
        let bad = try MGLesson.parse(json: variant {
            $0["beats"] = [["say": "One."], ["say": "Two.", "ops": [["op": "add", "item": ["id": "r", "k": "rocket"]]]]]
        }).get()
        guard case .failure(let issue) = s.load(bad) else { return XCTFail("rocket accepted") }
        XCTAssertEqual(issue.reason, "item.kind")
        XCTAssertEqual(issue.beat, 1)
        XCTAssertEqual(issue.statement, 4)
        XCTAssertNil(s.state)
        XCTAssertTrue(s.history.isEmpty)
        // A refused document leaves an existing lesson exactly as it was.
        let before = ok.state
        XCTAssertEqual(ok.load(bad).failureReason, "item.kind")
        XCTAssertEqual(ok.state, before)
    }

    // MARK: U3 stable ids

    func testU3TemplateIdsSurviveEveryAngleAndBeat() throws {
        var s = try F.through(beat: 3)
        let templateIDs = ["xaxis", "yaxis", "ghost", "shape", "vA", "lA", "vB", "lB", "vC", "lC", "pivot", "arc", "ltheta"]
        func kinds(_ s: MGLessonSession) -> [String: MGKind] {
            Dictionary(uniqueKeysWithValues: (s.state?.scene.items ?? []).filter { templateIDs.contains($0.id) }.map { ($0.id, $0.kind) })
        }
        let reference = kinds(s)
        XCTAssertEqual(Set(reference.keys), Set(templateIDs))
        var angles = Array(stride(from: 0.0, through: 360, by: 1))
        var rng = LessonRNG(seed: 7)
        angles += (0..<200).map { _ in Double.random(in: 0...360, using: &rng) }
        for a in angles {
            XCTAssertNoThrow(try s.control("angle", a).get(), "angle \(a)")
            XCTAssertEqual(kinds(s), reference, "angle \(a)")
            XCTAssertEqual(s.state?.scene.items.count, templateIDs.count)
        }
        // Over the whole lesson, the only non-template ids are exactly those named by add / remove commands in the log.
        var full = F.session()
        _ = try full.load(F.lesson()).get()
        let extra = Set(full.state!.scene.items.map(\.id)).subtracting(templateIDs)
        let added = full.log.compactMap { entry -> String? in
            guard entry.command["op"] == .string("add"), case .string(let id)? = entry.command["item"]?["id"] else { return nil }
            return id
        }
        let removed = full.log.compactMap { entry -> String? in
            guard entry.command["op"] == .string("remove"), case .string(let id)? = entry.command["id"] else { return nil }
            return id
        }
        XCTAssertEqual(added, ["hiA", "hiShape"])
        XCTAssertEqual(removed, ["hiA"])
        XCTAssertEqual(extra, Set(added).subtracting(removed))
        XCTAssertEqual(full.state?.introduced, ["hiA": 0, "hiShape": 4])
    }

    // MARK: U4 one-object update

    func testU4OneObjectUpdateTouchesOnlyThatObject() throws {
        var s = try F.through(beat: 0)
        let before = s.state!.scene.items
        _ = try s.apply(F.json(#"{"op":"set","id":"hiA","key":"label","value":"x"}"#)).get()
        let diff = MGSceneDiff(from: before, to: s.state!.scene.items)
        XCTAssertEqual(diff.changed, ["hiA"])
        XCTAssertEqual(diff.added, []); XCTAssertEqual(diff.removed, [])
        XCTAssertEqual(s.lastChange?.diff, diff)
        for item in before where item.id != "hiA" { XCTAssertEqual(s.state!.scene.item(item.id), item) }

        let mid = s.state!.scene.items
        _ = try s.apply(F.json(#"{"op":"add","item":{"id":"hiB","k":"highlight","target":"vB"}}"#)).get()
        let added = MGSceneDiff(from: mid, to: s.state!.scene.items)
        XCTAssertEqual(added.added, ["hiB"]); XCTAssertEqual(added.changed, []); XCTAssertEqual(added.removed, [])

        var turn = try F.through(beat: 3)
        let still = turn.state!.scene.items
        _ = try turn.control("angle", 30).get()
        let moved = MGSceneDiff(from: still, to: turn.state!.scene.items)
        XCTAssertTrue(Set(moved.changed).isSubset(of: ["shape", "vA", "vB", "vC", "lA", "lB", "lC", "arc", "ltheta"]), "\(moved.changed)")
        XCTAssertTrue(Set(["xaxis", "yaxis", "ghost", "pivot"]).isSubset(of: Set(moved.unchanged)))
        XCTAssertEqual(turn.lastChange?.transition, .direct)
    }

    // MARK: U5 slider == script == animate

    func testU5SliderScriptAndAnimateGiveIdenticalState() throws {
        var a = try F.through(beat: 3), b = a, c = a
        _ = try a.control("angle", 90).get()
        _ = try b.apply(F.json(#"{"op":"params","params":{"angle":90}}"#), origin: .script).get()
        _ = try c.apply(F.json(#"{"op":"animate","param":"angle","to":90,"dur":1}"#), origin: .script).get()
        for other in [b, c] {
            XCTAssertEqual(a.state!.scene.source.canonicalData, other.state!.scene.source.canonicalData)
            XCTAssertEqual(a.state!.scene.items, other.state!.scene.items)
            XCTAssertEqual(a.state!.scene.values, other.state!.scene.values)
            XCTAssertEqual(a.state!.scene.revision, other.state!.scene.revision)
            XCTAssertEqual(a.state!.beat, other.state!.beat)
            XCTAssertEqual(a.state!.controls, other.state!.controls)
            XCTAssertEqual(a.state, other.state)
        }
        XCTAssertEqual(a.log.last?.origin, .learner)
        XCTAssertEqual(b.log.last?.origin, .script)
        XCTAssertEqual(a.log.last?.command, b.log.last?.command, "the slider sends the same params command as the script")
        guard case .keyframes(let segments)? = c.lastChange?.transition else { return XCTFail("animate must carry keyframes") }
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments.last?.frames.last, c.state?.scene)
        // A learner command through the generic entry point is gated the same way.
        var d = try F.through(beat: 3)
        _ = try d.apply(F.json(#"{"op":"params","params":{"angle":90}}"#), origin: .learner).get()
        XCTAssertEqual(d.state, a.state)
        XCTAssertEqual(d.apply(F.json(#"{"op":"params","params":{"px":1}}"#), origin: .learner).failureReason, "control.unknown.px")
        XCTAssertEqual(d.apply(F.json(#"{"op":"remove","id":"vA"}"#), origin: .learner).failureReason, "control.op")
    }

    // MARK: U6 refusals

    func testU6InvalidCommandsAreRefusedWithStableReasonsAndChangeNothing() throws {
        let bound = #"{"op":"bind","control":{"id":"angle","k":"slider","param":"angle","min":0,"max":360,"step":5,"label":"Angle"}}"#
        let cases: [(String, String)] = [
            (#"{"op":"set","id":"ghostX","key":"label","value":"a"}"#, "patch.set.ref"),
            (#"{"op":"remove","id":"nope"}"#, "patch.remove.ref"),
            (#"{"op":"add","item":{"id":"vA","k":"body","at":[1,1]}}"#, "id.duplicate.vA"),
            (#"{"op":"add","item":{"id":"h2","k":"highlight","target":"nope"}}"#, "highlight.target"),
            (#"{"op":"add","item":{"id":"r","k":"rocket"}}"#, "item.kind"),
            (#"{"op":"params","params":{"angle":400}}"#, "template.angle"),
            (#"{"op":"explode"}"#, "patch.op.explode"),
            (#"{"op":"animate","param":"nope","to":1,"dur":1}"#, "animate.param"),
            (#"{"op":"animate","param":"angle","to":90,"dur":0}"#, "animate.dur"),
            (#"{"op":"bind","control":{"id":"a2","k":"slider","param":"angle","min":-500,"max":0,"step":1,"label":"x"}}"#, "control.range"),
            (bound, "control.duplicate.angle"),
            (#"{"op":"set","id":"vA","key":"k","value":"text"}"#, "patch.set.key"),
            (#"{"op":"step","index":0}"#, "lesson.op.step"),
            (#"{"op":"set","id":"lA","key":"text","value":"A is at 1.23"}"#, "text.literal"),
        ]
        for (command, reason) in cases {
            var s = try F.through(beat: 3)
            let before = s.state, projected = s.projected, log = s.log, change = s.lastChange
            guard case .failure(let issue) = s.apply(F.json(command)) else { XCTFail(command); continue }
            XCTAssertEqual(issue.reason, reason, command)
            XCTAssertEqual(issue.command, 0, command)
            XCTAssertEqual(s.state, before, command)
            XCTAssertEqual(s.state?.scene.revision, before?.scene.revision, command)
            XCTAssertEqual(s.projected, projected, command)
            XCTAssertEqual(s.log, log, command)
            XCTAssertEqual(s.lastChange, change, command)
        }
        var s = try F.through(beat: 3)
        let before = s.state
        XCTAssertEqual(s.control("angle", 361).failureReason, "control.value")
        XCTAssertEqual(s.control("angle", -1).failureReason, "control.value")
        XCTAssertEqual(s.control("angle", .nan).failureReason, "control.value")
        XCTAssertEqual(s.control("zoom", 1).failureReason, "control.unknown.zoom")
        XCTAssertEqual(s.state, before)

        // An id that was removed may come back only with the same kind.
        _ = try s.apply(F.json(#"{"op":"remove","id":"shape"}"#)).get()
        let hidden = s.state
        XCTAssertEqual(s.apply(F.json(#"{"op":"add","item":{"id":"shape","k":"text","at":[1,1],"text":"x"}}"#)).failureReason, "lesson.id.kind.shape")
        XCTAssertEqual(s.state, hidden)

        // A batch is atomic: command 1 fails, so command 0 is not applied either.
        var batch = try F.through(beat: 3)
        let start = batch.state
        guard case .failure(let issue) = batch.apply([F.json(#"{"op":"add","item":{"id":"hiB","k":"highlight","target":"vB"}}"#),
                                                      F.json(#"{"op":"remove","id":"nope"}"#)]) else { return XCTFail("batch accepted") }
        XCTAssertEqual(issue.reason, "patch.remove.ref")
        XCTAssertEqual(issue.command, 1)
        XCTAssertEqual(batch.state, start)
        XCTAssertNil(batch.state?.scene.item("hiB"))
    }

    // MARK: U7 labels equal the independent rotation

    func testU7LabelNumbersMatchAnIndependentRotation() throws {
        var s = try F.through(beat: 3)
        var angles = Array(stride(from: -360.0, through: 360, by: 1))
        var rng = LessonRNG(seed: 11)
        angles += (0..<500).map { _ in Double.random(in: -360...360, using: &rng) }
        for a in angles {
            _ = try s.apply(MGLessonEngine.paramsCommand("angle", a)).get()
            let scene = s.state!.scene
            for (k, letter) in ["A", "B", "C"].enumerated() {
                let label = try XCTUnwrap(scene.item("l\(letter)")?.text)
                let n = F.numbers(label)
                XCTAssertEqual(n.count, 2, label)
                let ref = F.rotate(F.triangle[k], a)
                XCTAssertEqual(n[0], ref.0, accuracy: F.tol(ref.0) + 1e-9, "\(letter) x at \(a)°: \(label)")
                XCTAssertEqual(n[1], ref.1, accuracy: F.tol(ref.1) + 1e-9, "\(letter) y at \(a)°: \(label)")
            }
            XCTAssertEqual(scene.item("ltheta")?.text, "θ = " + MGPhysics.format(a, unit: "°"))
        }
        // 50 random valid polygons and pivots.
        var accepted = 0
        while accepted < 50 {
            let count = Int.random(in: 3...6, using: &rng)
            let pts = (0..<count).map { _ in [Double.random(in: -3...3, using: &rng), Double.random(in: -3...3, using: &rng)] }
            let px = Double.random(in: -1...1, using: &rng), py = Double.random(in: -1...1, using: &rng)
            let angle = Double.random(in: -360...360, using: &rng)
            let json = MGJSON(any: ["v": 1, "template": "rotate2d", "params": ["pts": pts, "angle": angle, "px": px, "py": py]] as [String: Any])!
            guard case .success(let scene) = MGParser.scene(json: json) else { continue }
            accepted += 1
            for (k, p) in pts.enumerated() {
                let letter = MGGeometryPack.letters[k]
                let n = F.numbers(try XCTUnwrap(scene.item("l\(letter)")?.text))
                let ref = F.rotate((p[0], p[1]), angle, pivot: (px, py))
                XCTAssertEqual(n[0], ref.0, accuracy: F.tol(ref.0) + 1e-9)
                XCTAssertEqual(n[1], ref.1, accuracy: F.tol(ref.1) + 1e-9)
                // The drawn vertex is the same point in world units (O at world (7, 5)).
                let v = try XCTUnwrap(scene.item("v\(letter)")?.pts.first)
                XCTAssertEqual(v.x - 7, ref.0, accuracy: 1e-9); XCTAssertEqual(v.y - 5, ref.1, accuracy: 1e-9)
            }
        }
        // Narration filled at due time uses the same strings as the labels.
        var full = F.session()
        let events = try full.load(F.lesson()).get()
        let lines = F.lineDue(events)
        XCTAssertEqual(lines.count, 5)
        XCTAssertEqual(lines[1], "Now we turn the triangle about the origin O by 90°.")
        XCTAssertEqual(lines[2], "A moved from (2, 1) to (-1, 2). Its distance to O is still 2.24.")
        XCTAssertEqual(lines[4], "At 180° every coordinate changes sign. A is now at (-2, -1).")
        XCTAssertEqual(full.state?.scene.item("lA")?.text, "A (-2, -1)")
        XCTAssertTrue(lines[4].contains(full.state!.scene.item("lA")!.text!.dropFirst(2)))
    }

    // MARK: U8 narration from the presented state

    func testU8DueLineIsFilledFromThePresentedState() throws {
        var s = F.session(.speech)
        s.feed(#"{"scene":{"v":1,"template":"rotate2d","params":{"pts":[[2,1],[4,1],[2,3]]}}}"# + "\n")
        s.feed(#"{"say":"Turn it yourself."}"# + "\n")
        s.feed(#"{"op":"bind","control":{"id":"angle","k":"slider","param":"angle","min":0,"max":360,"step":5,"label":"Angle"}}"# + "\n")
        s.feed(#"{"say":"A is at ({ax}, {ay})."}"# + "\n")
        let queued = s.feed(#"{"end":true}"# + "\n")
        XCTAssertTrue(queued.contains(.lineQueued(beat: 1, text: "A is at (2, 1).")), "\(queued)")
        XCTAssertEqual(s.openLine, 0)
        _ = try s.control("angle", 45).get()
        let due = s.lineEnded(0)
        XCTAssertTrue(due.contains(.lineDue(beat: 1, text: "A is at (0.71, 2.12).", changed: true)), "\(due)")
        XCTAssertEqual(s.caption, "A is at (0.71, 2.12).")
        // D3: no decimal literals in lesson text; integers stay allowed.
        var d = F.session()
        d.feed(#"{"scene":{"v":1,"template":"rotate2d","params":{"pts":[[2,1],[4,1],[2,3]]}}}"# + "\n")
        XCTAssertEqual(F.refusals(d.feed(#"{"say":"A is at 1.23 now."}"# + "\n")).map(\.reason), ["text.literal"])
        XCTAssertEqual(F.refusals(d.feed(#"{"say":"Turn by 90°."}"# + "\n")), [])
        XCTAssertEqual(F.refusals(d.feed(#"{"op":"add","item":{"id":"t","k":"text","at":[1,1],"text":"x = 0.5"}}"# + "\n")).map(\.reason), ["text.literal"])
    }

    // MARK: U9 checks prove claims

    func testU9AFailingCheckRefusesTheWholeBeat() throws {
        var statements = try F.statements()
        statements[8] = #"{"check":{"value":"ax","eq":-1.5}}"#
        var s = F.session()
        var events: [MGLessonEvent] = []
        for line in statements[0...11] { events += s.feed(line + "\n") }
        let refused = F.refusals(events)
        XCTAssertEqual(refused.first?.reason, "check.ax")
        XCTAssertEqual(refused.first?.beat, 2)
        XCTAssertEqual(refused.first?.statement, 8)
        XCTAssertEqual(refused.dropFirst().map(\.reason), ["beat.refused", "beat.refused"], "the beat's later checks are cascades")
        XCTAssertFalse(s.events.contains(.beatPresented(beat: 2)))
        XCTAssertFalse(s.events.contains { if case .lineQueued(2, _) = $0 { return true }; return false })
        // The state is the end of beat index 1: turned to 90°, the highlight label not yet changed.
        XCTAssertEqual(s.state?.beat, 1)
        XCTAssertEqual(s.state?.scene.item("hiA")?.label, "A")
        XCTAssertEqual(s.state?.value("ax") ?? .nan, -1, accuracy: 1e-9)
        for line in statements[12...] { s.feed(line + "\n") }
        XCTAssertEqual(s.state?.beat, 4)
        XCTAssertNotNil(s.state?.scene.item("hiShape"))

        var u = try F.through(beat: 1)
        u.feed(#"{"keep":true}"# + "\n" + #"{"say":"Check."}"# + "\n")
        XCTAssertEqual(F.refusals(u.feed(#"{"check":{"value":"zz","eq":1}}"# + "\n")).map(\.reason), ["check.unknown.zz"])
        var t = try F.through(beat: 1)
        t.feed(#"{"keep":true}"# + "\n" + #"{"say":"Close enough."}"# + "\n")
        XCTAssertEqual(F.refusals(t.feed(#"{"check":{"value":"ra","eq":2.236,"tol":0.01}}"# + "\n")), [])
        XCTAssertEqual(F.refusals(t.feed(#"{"check":{"value":"ax","lt":0}}"# + "\n")), [])
        XCTAssertEqual(F.refusals(t.feed(#"{"check":{"value":"ay","gt":3}}"# + "\n")).map(\.reason), ["check.ay"])
    }

    // MARK: U10 keyframes are true rotations

    func testU10KeyframesKeepEveryVertexOnItsCircle() throws {
        let s = try F.through(beat: 0)
        let start = s.state!.scene
        let frames = try MGTween.keyframes(start, param: "angle", to: 90).get()
        XCTAssertEqual(frames.count, 18)
        let thetas = [0.0] + frames.compactMap { $0.values["theta"]?.value }
        for (p, q) in zip(thetas, thetas.dropFirst()) { XCTAssertLessThanOrEqual(abs(q - p), 5 + 1e-9) }
        for f in frames {
            for (k, name) in ["a", "b", "c"].enumerated() {
                let r0 = hypot(F.triangle[k].0, F.triangle[k].1)
                let x = try XCTUnwrap(f.values[name + "x"]).value, y = try XCTUnwrap(f.values[name + "y"]).value
                XCTAssertEqual(hypot(x, y), r0, accuracy: 1e-9, name)
                let v = try XCTUnwrap(f.item("v" + name.uppercased())?.pts.first)
                XCTAssertEqual(hypot(v.x - 7, v.y - 5), r0, accuracy: 1e-9)
            }
        }
        let committed = try start.applying(MGPatch.parse(json: F.json(#"{"v":1,"ops":[{"op":"params","params":{"angle":90}}]}"#)).get()).get()
        XCTAssertEqual(frames.last, committed)
        // Guard documenting the old defect: the linear point blend cuts the corner of a turn.
        let mid = MGTimeline.blend(from: start.items, to: committed.items, t: 0.5)
        let v = try XCTUnwrap(mid.first { $0.id == "vA" }?.pts.first)
        XCTAssertLessThanOrEqual((v - MGGeometryPack.origin).length, 0.75 * hypot(2, 1))
        // Sampling the keyframes keeps the vertex on its circle (renderer acceptance R3 checks screen points too).
        let lists = ([start] + frames).map(\.items)
        for f in stride(from: 0.0, through: 1, by: 0.01) {
            let w = try XCTUnwrap(MGTween.sample(lists, at: f).first { $0.id == "vA" }?.pts.first)
            XCTAssertEqual((w - MGGeometryPack.origin).length, hypot(2, 1), accuracy: hypot(2, 1) * 0.0011, "fraction \(f)")
        }
    }

    // MARK: U11 snapshot round trip

    func testU11SnapshotRoundTripAtEveryBeatAndAfterALearnerChange() throws {
        let clock = MGManualClock()
        var s = F.session(.speech, clock: clock)
        s.feed(try F.stream())
        for k in 0..<5 {
            if k == 4 { _ = try s.control("angle", 45).get() }
            var r = try MGLessonSession.restore(s.snapshot(), pacing: .speech, clock: clock).get()
            XCTAssertEqual(r.state, s.state, "beat \(k)")
            XCTAssertEqual(r.projected, s.projected, "beat \(k)")
            XCTAssertEqual(r.openLine, s.openLine)
            XCTAssertEqual(r.caption, s.caption)
            XCTAssertEqual(r.snapshot(), s.snapshot(), "beat \(k)")
            XCTAssertEqual(r.lineEnded(k), s.lineEnded(k), "next events after beat \(k)")
            XCTAssertEqual(r.state, s.state)
        }
        clock.advance(by: .seconds(5))
        XCTAssertEqual(s.tick(), [.lessonComplete])
        // A snapshot whose template is not registered is refused, never partly loaded.
        let snap = s.snapshot()
        MGPacks.resetRegistered()
        XCTAssertEqual(MGLessonSession.restore(snap, pacing: .speech).failureReason, "template.unknown")
        XCTAssertEqual(MGLessonSession.restore(.object(["kind": .string("lessonSnapshot"), "v": .number(2)]), pacing: .speech).failureReason, "snapshot.version")
    }

    // MARK: U13 limits are refusals

    func testU13LimitsAreRefusalsNotClamps() throws {
        var s = try F.through(beat: 3)
        let long = #"{"say":""# + String(repeating: "a", count: 4100) + #""}"#
        XCTAssertEqual(F.refusals(s.feed(long + "\n")).map(\.reason), ["stmt.bytes"])
        for id in ["b1", "b2", "b3"] {
            XCTAssertNoThrow(try s.apply(F.json(#"{"op":"bind","control":{"id":"\#(id)","k":"slider","param":"px","min":-1,"max":1,"step":0.5,"label":"Pivot"}}"#)).get())
        }
        XCTAssertEqual(s.apply(F.json(#"{"op":"bind","control":{"id":"b4","k":"slider","param":"py","min":-1,"max":1,"step":0.5,"label":"Pivot"}}"#)).failureReason, "control.count")
        XCTAssertEqual(s.apply(F.json(#"{"op":"animate","param":"angle","to":90,"dur":6.1}"#)).failureReason, "animate.dur")
        XCTAssertEqual(s.apply(F.json(#"{"op":"animate","param":"ghost","to":0}"#)).failureReason, "animate.param", "integer parameters do not animate")
        _ = try s.apply(F.json(#"{"op":"params","params":{"angle":0}}"#)).get()
        let frames = try MGTween.keyframes(s.state!.scene, param: "angle", to: 360).get()
        XCTAssertEqual(frames.count, MGTween.maxFrames)
        _ = try s.apply(F.json(#"{"op":"params","params":{"angle":-360}}"#)).get()
        XCTAssertEqual(s.apply(F.json(#"{"op":"animate","param":"angle","to":1}"#)).failureReason, "animate.to")
        XCTAssertEqual(s.apply(F.json(#"{"op":"animate","param":"angle","to":361}"#)).failureReason, "animate.to")
        XCTAssertEqual(s.apply(F.json(#"{"op":"unbind","id":"nope"}"#)).failureReason, "control.unknown.nope")
        XCTAssertNoThrow(try s.apply(F.json(#"{"op":"unbind","id":"b1"}"#)).get())
        XCTAssertNil(s.state?.control("b1"))
        // 13 commands in one beat.
        var t = try F.through(beat: 0)
        t.feed(#"{"keep":true}"# + "\n" + #"{"say":"Many."}"# + "\n")
        var reasons: [String] = []
        for _ in 0..<13 { reasons += F.refusals(t.feed(#"{"op":"set","id":"vA","key":"label","value":"A"}"# + "\n")).map(\.reason) }
        XCTAssertEqual(reasons, ["beat.ops.count"])
    }

    // MARK: U14 document form equals statement form

    func testU14DocumentAndStatementFormsEndInTheSameState() throws {
        var document = F.session(), fixture = F.session(), flattened = F.session()
        let loaded = try document.load(F.lesson()).get()
        let fed = fixture.feed(try F.stream())
        let flat = flattened.feed(try F.lesson().statementStream)
        XCTAssertEqual(document.state, fixture.state)
        XCTAssertEqual(document.state, flattened.state)
        XCTAssertEqual(F.lineDue(loaded), F.lineDue(fed))
        XCTAssertEqual(F.lineDue(loaded), F.lineDue(flat))
        XCTAssertEqual(F.beatEvents(loaded), F.beatEvents(fed))
        XCTAssertEqual(try F.lesson().statements.count, try F.statements().count)
    }

    // MARK: U15 rotation template rejections

    func testU15RotationTemplateRejections() throws {
        func scene(_ params: String) -> String? {
            if case .failure(let e) = MGParser.scene(data: Data(#"{"v":1,"template":"rotate2d","params":\#(params)}"#.utf8)) { return e.reason }
            return nil
        }
        XCTAssertNil(scene(#"{"pts":[[2,1],[4,1],[2,3]]}"#))
        XCTAssertEqual(scene(#"{"pts":[[4.6,0],[4,1],[2,3]]}"#), "template.pts.x", "outside the field range")
        XCTAssertEqual(scene(#"{"pts":[[3.6,2.77],[0,1],[2,0]]}"#), "template.pts.radius")
        XCTAssertEqual(scene(#"{"pts":[[0,1],[1,1],[2,1]]}"#), "template.pts.area")
        XCTAssertEqual(scene(#"{"pts":[[2,1],[2.5,1],[2,3]]}"#), "template.pts.gap")
        XCTAssertEqual(scene(#"{"pts":[[1,0],[2,0],[3,1],[3,2],[2,3],[1,3],[0,2]]}"#), "template.pts.count")
        XCTAssertEqual(scene(#"{"pts":[[2,1],[4,1],[2,3]],"angle":361}"#), "template.angle")
        XCTAssertEqual(scene(#"{"pts":[[2,1],[4,1],[2,3]],"ghost":0.5}"#), "template.ghost.integer")
        // Pivot shifts the board limit: a vertex 3 from a pivot at y = 2 would leave the board when turned.
        XCTAssertNil(scene(#"{"pts":[[0,1],[1,1],[0,2]],"py":2}"#))
        XCTAssertEqual(scene(#"{"pts":[[0,-1],[1,-1],[0,0]],"py":2}"#), "template.pts.radius")
        XCTAssertTrue(MGPacks.validate(MGGeometryPack.pack).isEmpty)
        MGPacks.resetRegistered()
        XCTAssertEqual(scene(#"{"pts":[[2,1],[4,1],[2,3]]}"#), "template.unknown")
    }

    // MARK: U16 existing behaviour unchanged

    func testU16DefaultGrammarDocumentIsUnchanged() throws {
        MGPacks.resetRegistered()
        let data = try JSONSerialization.data(withJSONObject: MGGrammar.document(), options: [.sortedKeys, .withoutEscapingSlashes])
        // FNV-1a 64 of the canonical default grammar document. Its inputs (MGGrammar, MGParser key tables, MGKind,
        // MGColorRole, core templates, MGLimits) match origin/main 6211345 except for the additive `table` and `region`
        // kinds (two more `kinds` entries); lessons add nothing to the default document.
        var hash: UInt64 = 0xcbf29ce484222325
        for b in data { hash = (hash ^ UInt64(b)) &* 0x100000001b3 }
        XCTAssertEqual(String(hash, radix: 16), Self.grammarHash, "byte count \(data.count)")
        XCTAssertEqual(data.count, Self.grammarBytes)
        XCTAssertFalse(MGTemplates.library.keys.contains("rotate2d"), "the geometry pack is opt-in")
    }
    static let grammarHash = "96001c839d70324d"
    static let grammarBytes = 2700
}
