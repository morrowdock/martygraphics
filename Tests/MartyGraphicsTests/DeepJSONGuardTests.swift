// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import MartyGraphics

/// Values and entry points for the nesting tests. Not actor-isolated, so a small-stack thread can use them.
enum Deep {
    enum Shape: CaseIterable, Sendable { case arrays, objects }
    static let cap = MGLimits.depth

    /// `levels` containers of `shape` around 0: `[[0]]` or `{"a":{"a":0}}` for 2.
    static func value(_ levels: Int, _ shape: Shape) -> MGJSON {
        var v = MGJSON.number(0)
        for _ in 0..<levels { v = shape == .arrays ? .array([v]) : .object(["a": v]) }
        return v
    }
    static func text(_ levels: Int, _ shape: Shape) -> String {
        shape == .arrays ? String(repeating: "[", count: levels) + "0" + String(repeating: "]", count: levels)
                         : String(repeating: #"{"a":"#, count: levels) + "0" + String(repeating: "}", count: levels)
    }

    /// 100,000 levels. Swift frees nested values recursively, so these live in static storage and are never freed.
    static let levels = 100_000
    static let hostile = value(levels, .arrays)
    static let hostileObject = value(levels, .objects)
    nonisolated(unsafe) static let hostileAny: [Any] = { var v: [Any] = [0]; for _ in 1..<levels { v = [v] }; return v }()

    /// A raw template that accepts any `tree` and draws one body.
    static func template() -> MGTemplate {
        MGTemplate(name: "deep_tree", summary: "nested tree", paramsDoc: "tree: any JSON", sample: .object(["tree": .number(0)])) { raw, _ in
            guard raw["tree"] != nil else { throw MGError("template.tree") }
            return MGTemplateBuild(title: "Tree", items: [MGMake.body("A", MGPoint(2, 2))])
        }
    }
    static func register() throws {
        try MGPacks.register(MGPack(id: "deep_tree_pack", title: "Deep", summary: "nested raw params", templates: [template()],
                                    fixtures: [MGFixtures.Demo(id: "deep_tree_demo", title: "Tree", json: #"{"v":1,"template":"deep_tree","params":{"tree":[[0]]}}"#)]))
    }
    /// Scene nesting = tree + 2 (the scene, `params`).
    static func scene(_ tree: MGJSON) -> MGJSON {
        .object(["v": .number(1), "template": .string("deep_tree"), "params": .object(["tree": tree])])
    }
    /// Command nesting = tree + 2 (the command, `params`).
    static func paramsOp(_ tree: MGJSON) -> MGJSON { .object(["op": .string("params"), "params": .object(["tree": tree])]) }
    /// Patch nesting = tree + 4 (the patch, `ops`, the op, `params`).
    static func patch(_ tree: MGJSON) -> MGJSON { .object(["v": .number(1), "ops": .array([paramsOp(tree)])]) }
    /// Lesson document nesting = ops tree + 6 (the document, `beats`, the beat, `ops`, the command, `params`).
    static func lesson(sceneTree: MGJSON = .number(0), opsTree: MGJSON? = nil) -> MGJSON {
        var beat: [String: MGJSON] = ["say": .string("One.")]
        if let opsTree { beat["ops"] = .array([paramsOp(opsTree)]) }
        return .object(["v": .number(1), "kind": .string("lesson"), "scene": scene(sceneTree), "beats": .array([.object(beat)])])
    }
    static let box: MGJSON = .object(["box": .object(["size": .array([.number(4), .number(4), .number(4)])])])
    static func assembly(title: MGJSON = .string("Box")) -> MGJSON {
        .object(["v": .number(1), "kind": .string("assembly"), "title": title, "parts": .array([.object(["id": .string("a"), "shape": box])])])
    }
    static func component(title: MGJSON) -> MGJSON {
        .object(["v": .number(1), "kind": .string("component"), "id": .string("deep"), "title": title, "about": .string("x"),
                 "parts": .array([.object(["id": .string("a"), "shape": box])])])
    }
    static func lines(_ l: [String]) -> String { l.joined(separator: "\n") + "\n" }

    static func reason<T, E: Error>(_ r: Result<T, E>) -> String? {
        guard case .failure(let e) = r else { return nil }
        return (e as? MGError)?.reason ?? (e as? MGLessonIssue)?.reason ?? (e as? MGSolidIssue)?.reason ?? "\(e)"
    }
    static func thrown(_ body: () throws -> Any?) -> String? {
        do { _ = try body(); return nil } catch { return (error as? MGError)?.reason ?? "\(error)" }
    }
}

/// One expectation: `got` must equal `want` (nil means accepted).
struct DeepCheck { let label: String; let got: String?; let want: String? }

final class DeepBox<T>: @unchecked Sendable { var value: T?; init() {} }

/// Runs `body` on a new thread with a 512 KiB stack, the size of an iOS secondary thread (`Thread.stackSize` works on
/// Darwin and Linux), and returns its result. A recursive step deeper than the cap would crash the test process here.
func onSmallStack<T>(_ body: @escaping @Sendable () -> T) -> T {
    let box = DeepBox<T>(), done = DispatchSemaphore(value: 0)
    let thread = Thread { box.value = body(); done.signal() }
    thread.stackSize = 512 * 1024
    thread.start()
    done.wait()
    return box.value!
}

/// JSON nests at most `MGLimits.depth` levels at every public entry point. The check runs first and does not recurse,
/// so no encode, parse, compare, hash or free ever sees a deeper value. The tests run each entry point at the cap
/// (accepted, or refused for another reason) and at the cap + 1 (the depth reason), with nested arrays and with nested
/// objects (the costlier form for the encoder), on a 512 KiB stack.
@MainActor
final class DeepJSONGuardTests: LessonTestCase {
    func verify(_ checks: [DeepCheck], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(checks.isEmpty, file: file, line: line)
        for c in checks { XCTAssertEqual(c.got, c.want, c.label, file: file, line: line) }
    }

    func testTheCapsAreDerived() {
        XCTAssertEqual(MGLimits.depth, 64)
        XCTAssertEqual(MGLessonLimits.snapshotDepth, 64)
        XCTAssertEqual(MGLessonLimits.statementDepth, 59)
        XCTAssertEqual(MGLessonLimits.documentDepth, 63)
        XCTAssertEqual(MGLessonLimits.sceneDepth, 61)
        XCTAssertEqual(Deep.value(3, .objects).measure().depth, 3)
        XCTAssertEqual(MGJSON.textNesting(Array(Deep.text(3, .objects).utf8)), 3)
        XCTAssertEqual(MGJSON.textNesting(Array(#"{"a":"[[{\"]]","b":[1]}"#.utf8)), 2, "brackets in strings do not count")
        XCTAssertEqual(MGJSON.number(1).measure().depth, 0)
    }

    func testValueOperationsAtTheCapOnASmallStack() {
        verify(onSmallStack { () -> [DeepCheck] in
            var out: [DeepCheck] = []
            for shape in Deep.Shape.allCases {
                let atCap = Deep.value(Deep.cap, shape), over = Deep.value(Deep.cap + 1, shape)
                let s = "\(shape)"
                out.append(DeepCheck(label: "encode \(s)", got: atCap.canonicalByteCount == Int.max ? "not encoded" : nil, want: nil))
                out.append(DeepCheck(label: "encode \(s) +1", got: over.canonicalByteCount == Int.max ? "not encoded" : nil, want: "not encoded"))
                out.append(DeepCheck(label: "any \(s)", got: MGJSON(any: atCap.any) == atCap ? nil : "differs", want: nil))
                out.append(DeepCheck(label: "any \(s) +1", got: MGJSON(any: over.any) == nil ? "nil" : nil, want: "nil"))
                out.append(DeepCheck(label: "hash \(s)", got: atCap.hashValue == Deep.value(Deep.cap, shape).hashValue ? nil : "differs", want: nil))
                let parsed = try? JSONSerialization.jsonObject(with: Data(Deep.text(Deep.cap, shape).utf8))
                out.append(DeepCheck(label: "text \(s)", got: MGJSON(any: parsed) == atCap ? nil : "differs", want: nil))
            }
            return out
        })
    }

    func testScenePatchAndTemplateEntriesAtTheCapOnASmallStack() throws {
        try Deep.register()
        verify(onSmallStack { () -> [DeepCheck] in
            var out: [DeepCheck] = []
            let base = try! MGParser.scene(json: Deep.scene(.number(0))).get()
            let t = Deep.template()
            for shape in Deep.Shape.allCases {
                for (k, over) in [(Deep.cap, false), (Deep.cap + 1, true)] {
                    let s = "\(shape) \(k)"
                    let sceneTree = Deep.value(k - 2, shape), patchTree = Deep.value(k - 4, shape)
                    out.append(DeepCheck(label: "scene json \(s)", got: Deep.reason(MGParser.scene(json: Deep.scene(sceneTree))), want: over ? "scene.depth" : nil))
                    let sceneText = #"{"v":1,"template":"deep_tree","params":{"tree":"# + Deep.text(k - 2, shape) + "}}"
                    out.append(DeepCheck(label: "scene data \(s)", got: Deep.reason(MGParser.scene(data: Data(sceneText.utf8))), want: over ? "scene.depth" : nil))
                    out.append(DeepCheck(label: "scene data extras \(s)", got: Deep.reason(MGParser.scene(data: Data(sceneText.utf8), extraTemplates: [t])), want: over ? "scene.depth" : nil))
                    var stream = MGStreamParser()
                    _ = stream.feed(sceneText)
                    out.append(DeepCheck(label: "stream \(s)", got: Deep.reason(stream.finish()), want: over ? "scene.depth" : nil))
                    out.append(DeepCheck(label: "patch json \(s)", got: Deep.reason(MGPatch.parse(json: Deep.patch(patchTree))), want: over ? "patch.depth" : nil))
                    let patchText = #"{"v":1,"ops":[{"op":"params","params":{"tree":"# + Deep.text(k - 4, shape) + "}}]}"
                    out.append(DeepCheck(label: "patch data \(s)", got: Deep.reason(MGPatch.parse(data: Data(patchText.utf8))), want: over ? "patch.depth" : nil))
                    out.append(DeepCheck(label: "applying \(s)", got: Deep.reason(base.applying(MGPatch(ops: [Deep.paramsOp(patchTree)]))), want: over ? "patch.depth" : nil))
                    let paramsTree = Deep.value(k - 1, shape)
                    out.append(DeepCheck(label: "validate \(s)", got: Deep.thrown { try t.validate(["tree": paramsTree]) }, want: over ? "template.params.depth" : nil))
                    out.append(DeepCheck(label: "compile \(s)", got: Deep.thrown { try t.compile(["tree": paramsTree]) }, want: over ? "template.params.depth" : nil))
                }
            }
            return out
        })
    }

    func testSolidEntriesAtTheCapOnASmallStack() throws {
        verify(onSmallStack { () -> [DeepCheck] in
            var out: [DeepCheck] = []
            let doc = try! MGSolidParser.document(json: Deep.assembly()).get()
            for shape in Deep.Shape.allCases {
                for (k, over) in [(Deep.cap, false), (Deep.cap + 1, true)] {
                    let s = "\(shape) \(k)"
                    // At the cap the guard passes and the closed schema refuses the title instead.
                    let title = Deep.value(k - 1, shape)
                    out.append(DeepCheck(label: "document \(s)", got: Deep.reason(MGSolidParser.document(json: Deep.assembly(title: title))),
                                         want: over ? "assembly.depth" : "assembly.title"))
                    let text = Deep.assembly(title: .string("T")).canonicalString.replacingOccurrences(of: #""T""#, with: Deep.text(k - 1, shape))
                    out.append(DeepCheck(label: "document data \(s)", got: Deep.reason(MGSolidParser.document(data: Data(text.utf8))),
                                         want: over ? "assembly.depth" : "assembly.title"))
                    out.append(DeepCheck(label: "applying \(s)", got: Deep.reason(MGSolidParser.applying(.object(["title": title]), to: doc)),
                                         want: over ? "patch.depth" : "assembly.title"))
                    let component = Deep.component(title: title)
                    let componentReason = Deep.reason(MGSolidComponent.parse(component, library: MGSolidLibrary()))
                    out.append(DeepCheck(label: "component \(s)", got: componentReason == "component.nesting" ? "component.nesting" : nil,
                                         want: over ? "component.nesting" : nil))
                    let componentText = Deep.component(title: .string("T")).canonicalString.replacingOccurrences(of: #""T""#, with: Deep.text(k - 1, shape))
                    let dataReason = Deep.reason(MGSolidLibrary().validate(Data(componentText.utf8)))
                    out.append(DeepCheck(label: "component data \(s)", got: dataReason == "component.nesting" ? "component.nesting" : nil,
                                         want: over ? "component.nesting" : nil))
                }
            }
            return out
        })
    }

    func testLessonEntriesAtTheCapOnASmallStack() throws {
        try Deep.register()
        verify(onSmallStack { () -> [DeepCheck] in
            var out: [DeepCheck] = []
            let d = MGLessonLimits.statementDepth
            for shape in Deep.Shape.allCases {
                for (k, over) in [(d, false), (d + 1, true)] {
                    let s = "\(shape) \(k)"
                    // A lesson document at its cap: a command at the statement cap.
                    let document = Deep.lesson(opsTree: Deep.value(k - 2, shape))
                    out.append(DeepCheck(label: "lesson json \(s)", got: Deep.reason(MGLesson.parse(json: document)), want: over ? "lesson.depth" : nil))
                    out.append(DeepCheck(label: "lesson data \(s)", got: Deep.reason(MGLesson.parse(data: Data(document.canonicalString.utf8))),
                                         want: over ? "lesson.depth" : nil))
                    if !over {
                        var l = MGLessonSession(pacing: .immediate, clock: MGManualClock())
                        out.append(DeepCheck(label: "load \(s)", got: Deep.reason(l.load(try! MGLesson.parse(json: document).get())), want: nil))
                    }
                    // Stream statements, counted on the text.
                    let sceneStatement = #"{"scene":{"v":1,"template":"deep_tree","params":{"tree":"# + Deep.text(k - 3, shape) + "}}}"
                    var a = MGLessonSession(pacing: .speech, clock: MGManualClock())
                    out.append(DeepCheck(label: "scene statement \(s)", got: MGLessonFixtureReasons.first(a.feed(Deep.lines([sceneStatement]))),
                                         want: over ? "lesson.depth" : nil))
                    var b = MGLessonSession(pacing: .speech, clock: MGManualClock())
                    b.feed(Deep.lines([#"{"scene":{"v":1,"template":"deep_tree","params":{"tree":0}}}"#, #"{"say":"One."}"#, #"{"say":"Two."}"#]))
                    let before = b.snapshot()
                    let command = #"{"op":"params","params":{"tree":"# + Deep.text(k - 2, shape) + "}}"
                    out.append(DeepCheck(label: "command statement \(s)", got: MGLessonFixtureReasons.first(b.feed(Deep.lines([command]))),
                                         want: over ? "lesson.depth" : nil))
                    if over { out.append(DeepCheck(label: "refused statement \(s)", got: b.snapshot()["pending"] == before["pending"] ? nil : "changed", want: nil)) }
                    // Host apply: a value built in code.
                    var c = MGLessonSession(pacing: .immediate, clock: MGManualClock())
                    c.feed(Deep.lines([#"{"scene":{"v":1,"template":"deep_tree","params":{"tree":0}}}"#, #"{"end":true}"#]))
                    let shown = c.snapshot()
                    out.append(DeepCheck(label: "apply \(s)", got: c.apply(Deep.paramsOp(Deep.value(k - 2, shape))).failureReason, want: over ? "lesson.depth" : nil))
                    if over { out.append(DeepCheck(label: "refused apply \(s)", got: c.snapshot() == shown ? nil : "changed", want: nil)) }
                }
                // Restore at the snapshot cap and one over (an unknown extra key is ignored, but it is measured).
                var e = MGLessonSession(pacing: .immediate, clock: MGManualClock())
                e.feed(Deep.lines([#"{"scene":{"v":1,"template":"deep_tree","params":{"tree":0}}}"#, #"{"end":true}"#]))
                guard case .object(var o) = e.snapshot() else { return [DeepCheck(label: "snapshot", got: "not an object", want: nil)] }
                o["junk"] = Deep.value(MGLessonLimits.snapshotDepth - 1, shape)
                out.append(DeepCheck(label: "restore \(shape) cap", got: MGLessonSession.restore(.object(o), pacing: .immediate).failureReason, want: nil))
                o["junk"] = Deep.value(MGLessonLimits.snapshotDepth, shape)
                out.append(DeepCheck(label: "restore \(shape) +1", got: MGLessonSession.restore(.object(o), pacing: .immediate).failureReason, want: "snapshot.depth"))
            }
            return out
        })
    }

    /// The deepest snapshot a live session makes (a queued command at the statement cap) restores and reads back from
    /// JSON text, with arrays and with objects, on a small stack.
    func testDeepestLiveSnapshotRoundTripsOnASmallStack() throws {
        try Deep.register()
        verify(onSmallStack { () -> [DeepCheck] in
            var out: [DeepCheck] = []
            let d = MGLessonLimits.statementDepth
            for shape in Deep.Shape.allCases {
                let clock = MGManualClock()
                var s = MGLessonSession(pacing: .speech, clock: clock)
                let events = s.feed(Deep.lines([#"{"scene":{"v":1,"template":"deep_tree","params":{"tree":"# + Deep.text(d - 3, shape) + "}}}",
                                                #"{"say":"One."}"#, #"{"say":"Two."}"#,
                                                #"{"op":"params","params":{"tree":"# + Deep.text(d - 2, shape) + "}}", #"{"end":true}"#]))
                out.append(DeepCheck(label: "stream \(shape)", got: MGLessonFixtureReasons.first(events), want: nil))
                let snapshot = s.snapshot()
                out.append(DeepCheck(label: "depth \(shape)", got: "\(snapshot.measure().depth)", want: "\(MGLessonSlots.snapshot)"))
                out.append(DeepCheck(label: "restore \(shape)", got: (try? MGLessonSession.restore(snapshot, pacing: .speech, clock: clock).get().snapshot()) == snapshot ? nil : "differs", want: nil))
                let object = try? JSONSerialization.jsonObject(with: snapshot.canonicalData)
                let back = MGJSON(any: object)
                out.append(DeepCheck(label: "text \(shape)", got: back?.canonicalData == snapshot.canonicalData ? nil : "differs", want: nil))
                out.append(DeepCheck(label: "restore text \(shape)", got: back.flatMap { MGLessonSession.restore($0, pacing: .speech, clock: clock).failureReason }, want: nil))
            }
            return out
        })
    }

    /// Review S1: `restore` refuses a scene source deeper than a live session makes, so the next snapshot (which copies
    /// the scene into `baseline`) still restores.
    func testRestoreRefusesASceneDeeperThanALiveSession() throws {
        try Deep.register()
        verify(onSmallStack { () -> [DeepCheck] in
            var out: [DeepCheck] = []
            let clock = MGManualClock()
            var s = MGLessonSession(pacing: .speech, clock: clock)
            s.feed(Deep.lines([#"{"scene":{"v":1,"template":"deep_tree","params":{"tree":0}}}"#, #"{"end":true}"#]))
            guard case .object(var o) = s.snapshot() else { return [DeepCheck(label: "snapshot", got: "not an object", want: nil)] }
            for shape in Deep.Shape.allCases {
                o["scene"] = Deep.scene(Deep.value(MGLessonLimits.sceneDepth - 2, shape))
                switch MGLessonSession.restore(.object(o), pacing: .speech, clock: clock) {
                case .failure(let e): out.append(DeepCheck(label: "deepest scene \(shape)", got: e.reason, want: nil))
                case .success(var r):
                    r.feed(Deep.lines([#"{"keep":true}"#, #"{"say":"More."}"#]))
                    let next = r.snapshot()
                    out.append(DeepCheck(label: "baseline \(shape)", got: next["baseline"] == nil ? "no baseline" : nil, want: nil))
                    out.append(DeepCheck(label: "next \(shape)", got: MGLessonSession.restore(next, pacing: .speech, clock: clock).failureReason, want: nil))
                }
                o["scene"] = Deep.scene(Deep.value(MGLessonLimits.sceneDepth - 1, shape))
                out.append(DeepCheck(label: "deeper scene \(shape)", got: MGLessonSession.restore(.object(o), pacing: .speech, clock: clock).failureReason,
                                     want: "snapshot.depth"))
            }
            return out
        })
    }

    // MARK: 100,000 levels

    func testHostileValuesAreRefusedEverywhereOnASmallStack() throws {
        try Deep.register()
        verify(onSmallStack { () -> [DeepCheck] in
            let deep = Deep.hostile, objects = Deep.hostileObject
            var out: [DeepCheck] = []
            func check(_ label: String, _ got: String?, _ want: String?) { out.append(DeepCheck(label: label, got: got, want: want)) }
            check("measure", "\(deep.measure().depth)", "\(Deep.levels)")
            check("encode", deep.canonicalByteCount == Int.max ? "not encoded" : nil, "not encoded")
            check("encode objects", objects.canonicalByteCount == Int.max ? "not encoded" : nil, "not encoded")
            check("any", MGJSON(any: Deep.hostileAny) == nil ? "nil" : nil, "nil")
            check("scene", Deep.reason(MGParser.scene(json: Deep.scene(deep))), "scene.depth")
            check("scene objects", Deep.reason(MGParser.scene(json: .object(["v": .number(1), "items": objects]))), "scene.depth")
            check("scene nan first", Deep.reason(MGParser.scene(json: .object(["v": .number(.nan), "items": deep]))), "scene.number")
            check("scene object", Deep.reason(MGParser.scene(object: ["v": 1, "params": ["tree": Deep.hostileAny]] as [String: Any])), "json")
            check("patch", Deep.reason(MGPatch.parse(json: Deep.patch(deep))), "patch.depth")
            check("patch objects", Deep.reason(MGPatch.parse(json: objects)), "patch.depth")
            check("patch object", Deep.reason(MGPatch.parse(object: Deep.hostileAny)), "patch.json")
            let base = try! MGParser.scene(json: Deep.scene(.number(0))).get()
            for (i, ops) in [[Deep.paramsOp(deep)], [deep], [objects]].enumerated() {
                check("applying \(i)", Deep.reason(base.applying(MGPatch(ops: ops))), "patch.depth")
            }
            let t = Deep.template()
            check("validate", Deep.thrown { try t.validate(["tree": deep]) }, "template.params.depth")
            check("compile", Deep.thrown { try t.compile(["tree": objects]) }, "template.params.depth")
            check("lesson", Deep.reason(MGLesson.parse(json: Deep.lesson(sceneTree: deep))), "lesson.depth")
            check("lesson objects", Deep.reason(MGLesson.parse(json: objects)), "lesson.depth")
            var s = MGLessonSession(pacing: .immediate, clock: MGManualClock())
            s.feed(Deep.lines([#"{"scene":{"v":1,"template":"deep_tree","params":{"tree":0}}}"#, #"{"end":true}"#]))
            let before = s.snapshot()
            for (i, command) in [Deep.paramsOp(deep), deep, objects].enumerated() {
                check("apply \(i)", s.apply(command).failureReason, "lesson.depth")
                check("apply batch \(i)", s.apply([Deep.paramsOp(.number(1)), command]).failureReason, "lesson.depth")
            }
            check("apply unchanged", s.snapshot() == before ? nil : "changed", nil)
            check("restore", MGLessonSession.restore(deep, pacing: .immediate).failureReason, "snapshot.depth")
            check("restore objects", MGLessonSession.restore(objects, pacing: .immediate).failureReason, "snapshot.bytes")
            check("solid document", Deep.reason(MGSolidParser.document(json: Deep.assembly(title: objects))), "assembly.depth")
            let doc = try! MGSolidParser.document(json: Deep.assembly()).get()
            check("solid applying", Deep.reason(MGSolidParser.applying(.object(["params": deep]), to: doc)), "patch.depth")
            check("solid component", Deep.reason(MGSolidComponent.parse(Deep.component(title: objects), library: MGSolidLibrary())), "component.nesting")
            var library = MGSolidLibrary()
            check("solid register", Deep.reason(library.register(json: Deep.component(title: deep))), "component.nesting")
            return out
        })
    }

    func testControllerRefusesHostileValuesAndChangesNothing() throws {
        try Deep.register()
        let c = MGLessonController(pacing: .immediate, clock: MGManualClock())
        c.begin()
        c.feed(Deep.lines([#"{"scene":{"v":1,"template":"deep_tree","params":{"tree":0}}}"#, #"{"end":true}"#]))
        let shown = c.session.snapshot()
        XCTAssertFalse(c.apply(Deep.paramsOp(Deep.hostile)))
        XCTAssertEqual(c.lastIssue?.reason, "lesson.depth")
        XCTAssertEqual(c.restore(Deep.hostile).failureReason, "snapshot.depth")
        XCTAssertEqual(c.lastIssue?.reason, "snapshot.depth")
        XCTAssertEqual(c.session.snapshot(), shown)
    }
}

/// The first refusal reason among events (nil when none).
enum MGLessonFixtureReasons {
    static func first(_ events: [MGLessonEvent]) -> String? {
        events.lazy.compactMap { if case .refused(let i) = $0 { return i.reason } else { return nil } }.first
    }
}

/// Derived snapshot depth reached by the deepest live session.
enum MGLessonSlots { static let snapshot = MGLessonLimits.statementDepth + 5 }
