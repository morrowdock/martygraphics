// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import MartyGraphics

/// Values built in code that nest far deeper than any legal input are refused by every public entry point, before any
/// recursive walk (encoding, validation, comparison) can exhaust the call stack. The deepest legal value is accepted.
///
/// Swift frees nested enum values and nested Foundation arrays recursively. The 100,000-level values are kept in static
/// storage, which is never freed, so no test frees one. Values near the legal limits (about 2,000 levels) are freed
/// normally.
@MainActor
final class DeepJSONGuardTests: LessonTestCase {
    static let levels = 100_000
    static func deep(_ levels: Int, holding leaf: MGJSON = .number(0)) -> MGJSON {
        var v = leaf; for _ in 0..<levels { v = .array([v]) }; return v
    }
    /// Never freed (see the type's note).
    static let hostile = deep(levels)
    static let hostileObject: MGJSON = { var v = MGJSON.number(0); for _ in 0..<levels { v = .object(["a": v]) }; return v }()
    nonisolated(unsafe) static let hostileAny: [Any] = { var v: [Any] = [0]; for _ in 1..<levels { v = [v] }; return v }()

    /// A raw template that accepts any `tree`.
    static let nested = MGTemplate(name: "deep_tree", summary: "nested tree", paramsDoc: "tree: any JSON", sample: .object(["tree": .number(0)])) { raw, _ in
        guard raw["tree"] != nil else { throw MGError("template.tree") }
        return MGTemplateBuild(title: "Tree", items: [MGMake.body("A", MGPoint(2, 2))])
    }
    func register() throws {
        try MGPacks.register(MGPack(id: "deep_tree_pack", title: "Deep", summary: "nested raw params", templates: [Self.nested],
                                    fixtures: [MGFixtures.Demo(id: "deep_tree_demo", title: "Tree", json: #"{"v":1,"template":"deep_tree","params":{"tree":[[0]]}}"#)]))
    }
    func sceneJSON(_ tree: MGJSON) -> MGJSON {
        .object(["v": .number(1), "template": .string("deep_tree"), "params": .object(["tree": tree])])
    }
    func paramsOp(_ tree: MGJSON) -> MGJSON { .object(["op": .string("params"), "params": .object(["tree": tree])]) }
    func reason<T, E: Error>(_ r: Result<T, E>) -> String? {
        guard case .failure(let e) = r else { return nil }
        return (e as? MGError)?.reason ?? (e as? MGLessonIssue)?.reason ?? (e as? MGSolidIssue)?.reason ?? "\(e)"
    }
    func thrown(_ body: () throws -> Any?) -> String? {
        do { _ = try body(); return nil } catch { return (error as? MGError)?.reason ?? "\(error)" }
    }

    func testTheWalkIsIterativeAndTheEncoderNeverSeesADeepValue() {
        let m = Self.hostile.measure()
        XCTAssertEqual(m.depth, Self.levels)
        XCTAssertTrue(m.finite)
        XCTAssertFalse(m.stopped)
        XCTAssertEqual(Self.hostileObject.measure().depth, Self.levels)
        XCTAssertTrue(Self.hostile.isEncodable, "finite, so encodable in principle")
        XCTAssertEqual(Self.hostile.canonicalByteCount, Int.max, "never encoded: counts as over every byte bound")
        XCTAssertEqual(Self.hostile.canonicalData, Data())
        XCTAssertEqual(Self.hostileObject.canonicalByteCount, Int.max)
        XCTAssertNil(MGJSON(any: Self.hostileAny), "the Foundation conversion is bounded too")
        // Nesting is counted like the system JSON parser counts it: arrays and objects on one path.
        XCTAssertEqual(MGJSON.number(1).measure().depth, 0)
        XCTAssertEqual(MGJSON.array([]).measure().depth, 1)
        XCTAssertEqual(MGJSON.object(["a": .array([.number(1)])]).measure().depth, 2)
        // `MGLimits.depth` is the encoding limit, exactly.
        XCTAssertEqual(MGLimits.depth, 2056)
        XCTAssertEqual(Self.deep(MGLimits.depth).canonicalByteCount, 2 * MGLimits.depth + 1)
        XCTAssertEqual(Self.deep(MGLimits.depth + 1).canonicalByteCount, Int.max)
        XCTAssertNotNil(MGJSON(any: try! JSONSerialization.jsonObject(with: Data((String(repeating: "[", count: 512) + String(repeating: "]", count: 512)).utf8))))
    }

    func testEveryScenePatchAndTemplateEntryRefusesAHostileValue() throws {
        let deep = Self.hostile
        let hostileScene = sceneJSON(deep)
        XCTAssertEqual(reason(MGParser.scene(json: hostileScene)), "scene.depth")
        XCTAssertEqual(reason(MGParser.scene(json: hostileScene, extraTemplates: [Self.nested])), "scene.depth")
        XCTAssertEqual(reason(MGParser.scene(json: .object(["v": .number(1), "items": Self.hostileObject]))), "scene.depth")
        XCTAssertEqual(reason(MGParser.scene(object: ["v": 1, "template": "deep_tree", "params": ["tree": Self.hostileAny]] as [String: Any])), "json")
        XCTAssertEqual(reason(MGParser.scene(object: Self.hostileAny, extraTemplates: [Self.nested])), "json")
        // A NaN anywhere still wins (the reasons keep their order: number, depth, size).
        XCTAssertEqual(reason(MGParser.scene(json: .object(["v": .number(.nan), "items": deep]))), "scene.number")

        let wire = MGJSON.object(["v": .number(1), "ops": .array([paramsOp(deep)])])
        XCTAssertEqual(reason(MGPatch.parse(json: wire)), "patch.depth")
        XCTAssertEqual(reason(MGPatch.parse(json: Self.hostileObject)), "patch.depth")
        XCTAssertEqual(reason(MGPatch.parse(object: Self.hostileAny)), "patch.json")

        let base = try MGParser.scene(json: sceneJSON(.number(0)), extraTemplates: [Self.nested]).get()
        for ops in [[paramsOp(deep)], [.object(["op": .string("title"), "title": deep])], [deep], [Self.hostileObject]] {
            XCTAssertEqual(reason(base.applying(MGPatch(ops: ops), extraTemplates: [Self.nested])), "patch.depth")
        }

        XCTAssertEqual(thrown { try Self.nested.validate(["tree": deep]) }, "template.params.depth")
        XCTAssertEqual(thrown { try Self.nested.compile(["tree": Self.hostileObject]) }, "template.params.depth")
        XCTAssertEqual(thrown { try Self.nested.validate(["tree": .array([.number(.infinity), deep])]) }, "template.params.number")
    }

    func testSolidEntriesRefuseAHostileValueWithTheirSizeReason() throws {
        // Solid has no depth reason: its first check measures the canonical size, which never encodes a deep value.
        let box: MGJSON = .object(["box": .object(["size": .array([.number(4), .number(4), .number(4)])])])
        let doc = try MGSolidParser.document(json: .object(["v": .number(1), "kind": .string("assembly"),
                                                           "parts": .array([.object(["id": .string("a"), "shape": box])])])).get()
        XCTAssertEqual(reason(MGSolidParser.document(json: .object(["v": .number(1), "kind": .string("assembly"), "parts": Self.hostile]))), "assembly.bytes")
        XCTAssertEqual(reason(MGSolidParser.applying(.object(["params": Self.hostile]), to: doc)), "assembly.bytes")
        var library = MGSolidLibrary()
        XCTAssertEqual(reason(library.register(json: .object(["v": .number(1), "kind": .string("component"), "parts": Self.hostileObject]))), "component.bytes")
        XCTAssertEqual(reason(MGSolidComponent.parse(Self.hostile, library: library)), "component.object")
    }

    func testEveryLessonEntryRefusesAHostileValueAndChangesNothing() throws {
        try register()
        let deep = Self.hostile
        let lesson = MGJSON.object(["v": .number(1), "kind": .string("lesson"), "scene": sceneJSON(deep),
                                    "beats": .array([.object(["say": .string("One.")])])])
        XCTAssertEqual(reason(MGLesson.parse(json: lesson)), "lesson.depth")
        XCTAssertEqual(reason(MGLesson.parse(json: Self.hostileObject)), "lesson.depth")

        var s = MGLessonSession(pacing: .immediate, clock: MGManualClock())
        s.feed(#"{"scene":{"v":1,"template":"deep_tree","params":{"tree":0}}}"# + "\n" + #"{"end":true}"# + "\n")
        let before = s.snapshot()
        for command in [paramsOp(deep), deep, Self.hostileObject, .object(["op": .string("title"), "title": Self.hostileObject])] {
            XCTAssertEqual(s.apply(command).failureReason, "lesson.depth")
            XCTAssertEqual(s.apply([paramsOp(.number(1)), command]).failureReason, "lesson.depth")
            XCTAssertEqual(s.snapshot(), before, "a refused command changes nothing")
        }
        XCTAssertEqual(MGLessonSession.restore(deep, pacing: .immediate).failureReason, "snapshot.depth")
        // 100,000 objects are over the size cap first (the walk stops early, so its work is bounded).
        XCTAssertEqual(MGLessonSession.restore(Self.hostileObject, pacing: .immediate).failureReason, "snapshot.bytes")
        XCTAssertEqual(MGLessonSession.restore(.object(["kind": .string("lessonSnapshot"), "v": .number(1), "scene": sceneJSON(deep)]),
                                               pacing: .immediate).failureReason, "snapshot.depth")

        let c = MGLessonController(pacing: .immediate, clock: MGManualClock())
        c.begin()
        c.feed(#"{"scene":{"v":1,"template":"deep_tree","params":{"tree":0}}}"# + "\n" + #"{"end":true}"# + "\n")
        let shown = c.session.snapshot()
        XCTAssertFalse(c.apply(paramsOp(deep)))
        XCTAssertEqual(c.lastIssue?.reason, "lesson.depth")
        XCTAssertEqual(c.restore(deep).failureReason, "snapshot.depth")
        XCTAssertEqual(c.lastIssue?.reason, "snapshot.depth")
        XCTAssertEqual(c.session.snapshot(), shown)
    }

    /// The deepest legal value at each scene, patch and template entry: a raw template's `params` that fills 4 KiB.
    func testTheDeepestLegalValueIsAcceptedAtEveryEntry() throws {
        func fits(_ k: Int) -> Bool { MGJSON.object(["tree": Self.deep(k)]).canonicalByteCount <= MGLimits.rawParamsBytes }
        var k = 1
        while fits(k + 1) { k += 1 }
        let tree = Self.deep(k)
        XCTAssertGreaterThan(k, 2000)
        XCTAssertNoThrow(try Self.nested.validate(["tree": tree]))
        XCTAssertEqual(thrown { try Self.nested.validate(["tree": Self.deep(k + 1)]) }, "template.params.bytes")
        let scene = sceneJSON(tree)
        XCTAssertLessThanOrEqual(scene.measure().depth, MGLimits.depth)
        let parsed = try MGParser.scene(json: scene, extraTemplates: [Self.nested]).get()
        XCTAssertEqual(parsed.source, scene)
        // As a patch: the patch wrapper takes some of the 4 KiB, so the deepest patch tree is a little shallower.
        let base = try MGParser.scene(json: sceneJSON(.number(0)), extraTemplates: [Self.nested]).get()
        var p = 1
        while MGJSON.object(["v": .number(1), "ops": .array([paramsOp(Self.deep(p + 1))])]).canonicalByteCount <= MGLimits.patchBytes { p += 1 }
        XCTAssertNoThrow(try base.applying(MGPatch(ops: [paramsOp(Self.deep(p))]), extraTemplates: [Self.nested]).get())
        XCTAssertEqual(reason(base.applying(MGPatch(ops: [paramsOp(Self.deep(p + 1))]), extraTemplates: [Self.nested])), "patch.object")
        let wire = MGJSON.object(["v": .number(1), "ops": .array([paramsOp(Self.deep(p))])])
        XCTAssertNoThrow(try MGPatch.parse(json: wire).get())
        // Through the Foundation form: the deepest legal tree converts.
        XCTAssertEqual(MGJSON(any: scene.any), scene)
    }
}
