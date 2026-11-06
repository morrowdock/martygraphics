// SPDX-License-Identifier: Apache-2.0
import XCTest
@testable import MartyGraphics

/// Raw (free-form JSON) templates, list defaults, throwing `make`, pack patches and fail-safe cases, and parsing or
/// patching with templates that are not registered.
final class TemplateExtensionTests: XCTestCase {
    override func tearDown() { MGPacks.resetRegistered() }

    /// A raw template: `labels` is a list of 1–6 short strings, one node per label. Rejects with specific reasons.
    static let labels = MGTemplate(
        name: "demo_labels", summary: "one node per label", paramsDoc: "labels:[1–6 strings ≤8], gap number=1.6",
        sample: .object(["labels": .array([.string("A"), .string("B")])])) { raw, _ in
            guard case .array(let list)? = raw["labels"], (1...6).contains(list.count) else { throw MGError("template.labels") }
            let gap: Double
            switch raw["gap"] { case nil: gap = 1.6; case .number(let d)? where (1...2).contains(d): gap = d; default: throw MGError("template.gap") }
            var items: [MGItem] = []
            for (i, v) in list.enumerated() {
                guard case .string(let s) = v else { throw MGError("template.labels.text") }
                items.append(MGMake.kind("n\(i)", .node, [MGPoint(1.5 + Double(i) * gap, 4)], ["r": 0.4]).with(text: s))
            }
            return MGTemplateBuild(title: "Labels", items: items)
        }

    static func rawPack(fixture: String = #"{"v":1,"template":"demo_labels","params":{"labels":["A","B","C"]}}"#,
                        patches: [MGFixtures.PatchDemo] = [], invalid: [(String, String)] = []) -> MGPack {
        MGPack(id: "demo_raw", title: "Raw demo", summary: "raw params", templates: [labels],
               fixtures: [MGFixtures.Demo(id: "demo_abc", title: "ABC", json: fixture)], patches: patches, invalid: invalid)
    }

    private func reason(_ json: String, extra: [MGTemplate] = []) -> String? {
        if case .failure(let e) = MGParser.scene(data: Data(json.utf8), extraTemplates: extra) { return e.reason }
        return nil
    }

    // MARK: raw templates

    func testRawTemplatesCompileFreeFormParamsAndKeepReasons() throws {
        XCTAssertTrue(Self.labels.isRaw)
        XCTAssertFalse(MGTemplates.library["bst"]!.isRaw)
        XCTAssertEqual(Self.labels.doc, "demo_labels{labels:[1–6 strings ≤8], gap number=1.6}: one node per label")
        let json = #"{"v":1,"template":"demo_labels","params":{"labels":["A","B","C"]}}"#
        XCTAssertEqual(reason(json), "template.unknown")                                        // not registered
        let scene = try MGParser.scene(data: Data(json.utf8), extraTemplates: [Self.labels]).get()
        XCTAssertEqual(scene.items.map(\.text), ["A", "B", "C"])
        XCTAssertEqual(reason(#"{"v":1,"template":"demo_labels","params":{"labels":[]}}"#, extra: [Self.labels]), "template.labels")
        XCTAssertEqual(reason(#"{"v":1,"template":"demo_labels","params":{"labels":[1]}}"#, extra: [Self.labels]), "template.labels.text")
        XCTAssertEqual(reason(#"{"v":1,"template":"demo_labels","params":{"labels":["A"],"gap":9}}"#, extra: [Self.labels]), "template.gap")
        // Template output is still re-validated: node text is limited to 8 characters.
        XCTAssertEqual(reason(#"{"v":1,"template":"demo_labels","params":{"labels":["far too long"]}}"#, extra: [Self.labels]), "node.text")
        XCTAssertEqual(reason(#"{"v":1,"template":"demo_labels","params":{"labels":["<b>"]}}"#, extra: [Self.labels]), "node.text")
    }

    func testRawParamsAreByteBoundedBeforeCompile() throws {
        var ran = false
        let t = MGTemplate(name: "demo_raw_bound", summary: "size bound", paramsDoc: "anything", sample: .object(["k": .bool(true)])) { _, _ in
            ran = true; return MGTemplateBuild(title: "Bound")
        }
        XCTAssertThrowsError(try t.validate(["x": .string(String(repeating: "a", count: MGLimits.rawParamsBytes + 1))])) {
            XCTAssertEqual(($0 as? MGError)?.reason, "template.params.bytes")
        }
        XCTAssertFalse(ran)                                                                  // refused before compile
        let nested: [String: MGJSON] = ["tags": .array([.string("p"), .object(["deep": .array([.bool(false)])])]), "none": .null]
        let p = try t.validate(nested)
        XCTAssertEqual(p.raw, .object(nested))
        XCTAssertTrue(p.numbers.isEmpty && p.lists.isEmpty && p.records.isEmpty)
        XCTAssertEqual(MGLimits.rawParamsBytes, 4096)
    }

    func testRawTemplateNilAndForeignErrorsAreTemplateBuild() {
        struct Foreign: Error {}
        let none = MGTemplate(name: "raw_none", summary: "x", paramsDoc: "{}", sample: .object([:])) { _, _ in nil }
        let foreign = MGTemplate(name: "raw_foreign", summary: "x", paramsDoc: "{}", sample: .object([:])) { _, _ in throw Foreign() }
        XCTAssertEqual(reason(#"{"v":1,"template":"raw_none","params":{}}"#, extra: [none]), "template.build")
        XCTAssertEqual(reason(#"{"v":1,"template":"raw_foreign","params":{}}"#, extra: [foreign]), "template.build")
    }

    func testRawParamsPatchMergesShallowly() throws {
        try MGPacks.register(Self.rawPack())
        let scene = try MGParser.scene(data: Data(#"{"v":1,"template":"demo_labels","params":{"labels":["A","B"]}}"#.utf8)).get()
        let gap = try MGPatch.parse(data: Data(#"{"v":1,"rev":0,"ops":[{"op":"params","params":{"gap":2}}]}"#.utf8)).get()
        let wider = try scene.applying(gap).get()
        XCTAssertEqual(wider.items.map(\.text), ["A", "B"])                                     // labels kept
        XCTAssertEqual(wider.item("n1")?.pts.first?.x, 3.5)
        let bad = try MGPatch.parse(data: Data(#"{"v":1,"rev":1,"ops":[{"op":"params","params":{"labels":null}}]}"#.utf8)).get()
        guard case .failure(let e) = wider.applying(bad) else { return XCTFail("null labels must be refused") }
        XCTAssertEqual(e.reason, "template.labels")
    }

    func testGrammarListsRawSchemaOnlyForRawTemplates() throws {
        try MGPacks.register(Self.rawPack())
        let templates = try XCTUnwrap(MGGrammar.document()["templates"] as? [[String: Any]])
        let raw = try XCTUnwrap(templates.first { $0["name"] as? String == "demo_labels" })
        let shape = try XCTUnwrap(raw["rawParams"] as? [String: Any])
        XCTAssertEqual(shape["doc"] as? String, "labels:[1–6 strings ≤8], gap number=1.6")
        XCTAssertEqual(shape["maxBytes"] as? Int, 4096)
        XCTAssertEqual(raw["parameters"] as? [String], [])
        let core = try XCTUnwrap(templates.first { $0["name"] as? String == "bst" })
        XCTAssertEqual(Set(core.keys), ["name", "parameters"])
        XCTAssertTrue(JSONSerialization.isValidJSONObject(MGGrammar.document()))
    }

    // MARK: list defaults

    static let steps = MGTemplate(
        name: "demo_steps", summary: "bars of the given heights",
        params: [.init(name: "h", unit: "", range: 0...5, integer: true, count: 0...4, listDefault: [1, 2]),
                 .init(name: "w", unit: "", range: 0.5...1, count: 1...2, listDefault: [0.5])],
        make: { p, _ in
            let h = p.lists["h"] ?? []
            let items = h.enumerated().map { MGMake.body("b\($0.offset)", MGPoint(2 + Double($0.offset) * 2, 1 + $0.element / 2), size: 0.8) }
            return MGTemplateBuild(title: "Steps \(h.count)", items: items.isEmpty ? [MGMake.text("none", MGPoint(6, 4), "No bars")] : items)
        })

    func testListDefaultsFillAbsentListsOnly() throws {
        let absent = try Self.steps.validate([:])
        XCTAssertEqual(absent.lists["h"], [1, 2]); XCTAssertEqual(absent.lists["w"], [0.5])
        XCTAssertEqual(try Self.steps.validate(["h": .array([])]).lists["h"], [])               // sent wins, even empty
        XCTAssertThrowsError(try Self.steps.validate(["h": .null])) { XCTAssertEqual(($0 as? MGError)?.reason, "template.h") }
        XCTAssertEqual(Self.steps.params[0].doc, "h:[0–4 ints 0–5]=[1,2]")
        XCTAssertEqual(Self.steps.params[1].doc, "w:[1–2 numbers 0.5–1]=[0.5]")
        // Without a default the absent-list rule is unchanged.
        XCTAssertThrowsError(try MGTemplates.library["bst"]!.validate([:])) { XCTAssertEqual(($0 as? MGError)?.reason, "template.values") }
        let scene = try MGParser.scene(data: Data(#"{"v":1,"template":"demo_steps","params":{}}"#.utf8), extraTemplates: [Self.steps]).get()
        XCTAssertEqual(scene.title, "Steps 2")
    }

    func testBadListDefaultsAreRefusedAtRegistrationAndLazily() {
        let bad = MGTemplate(name: "demo_list_bad", summary: "bad default",
                             params: [.init(name: "a", unit: "", range: 1...3, integer: true, count: 1...3, listDefault: [2.5])]) { _, _ in nil }
        XCTAssertThrowsError(try bad.validate([:])) { XCTAssertEqual(($0 as? MGError)?.reason, "template.a.default") }
        XCTAssertEqual(bad.declarationProblems, ["a: list default must fit its count, range and integer rule"])
        let scalar = MGTemplate(name: "list_scalar", summary: "test",
                                params: [.init(name: "a", unit: "", range: 0...2, defaultValue: 1, listDefault: [1])]) { _, _ in nil }
        XCTAssertEqual(scalar.declarationProblems, ["a: a list default needs a number-list parameter"])
        let pack = MGPack(id: "demo_bad_list", title: "x", summary: "x", templates: [bad],
                          fixtures: [MGFixtures.Demo(id: "demo_bad_list_1", title: "x", json: #"{"v":1,"template":"demo_list_bad","params":{"a":[1]}}"#)])
        XCTAssertEqual(MGPacks.validate(pack).first, .badParamSpec("demo_list_bad", "a: list default must fit its count, range and integer rule"))
        XCTAssertThrowsError(try MGPacks.register(pack))
        XCTAssertNil(MGTemplates.library["demo_list_bad"])
        XCTAssertEqual(MGPacks.validate(MGPack(id: "demo_ok_list", title: "x", summary: "x", templates: [Self.steps],
                                               fixtures: [MGFixtures.Demo(id: "demo_ok_list_1", title: "x", json: #"{"v":1,"template":"demo_steps","params":{}}"#)])), [])
    }

    // MARK: throwing make on declared templates

    func testDeclaredTemplatesMayThrowSpecificReasons() {
        let t = MGTemplate(name: "demo_throw", summary: "x", params: [.init(name: "n", unit: "", range: 0...9, integer: true)]) { p, _ in
            if p["n"] > 5 { throw MGError("template.n.layout") }
            return MGTemplateBuild(title: "Ok", items: [MGMake.body("b", MGPoint(3, 3))])
        }
        XCTAssertNil(reason(#"{"v":1,"template":"demo_throw","params":{"n":2}}"#, extra: [t]))
        XCTAssertEqual(reason(#"{"v":1,"template":"demo_throw","params":{"n":7}}"#, extra: [t]), "template.n.layout")
    }

    /// Regression: a thrown reason must be a bounded `template.<suffix>` token. Free text, very long text and reasons
    /// from other families (which would imitate parser reasons) are reported as `template.build`.
    func testThrownReasonsAreNormalised() throws {
        func thrower(_ name: String, _ why: String) -> MGTemplate {
            MGTemplate(name: name, summary: "x", paramsDoc: "{}", sample: .object([:])) { _, _ in throw MGError(why) }
        }
        let long = String(repeating: "Bad reason with spaces https://x.y\n", count: 3000)
        let suffix48 = "a" + String(repeating: "b", count: 47), suffix49 = suffix48 + "c"
        let cases: [(String, String)] = [
            (long, "template.build"), ("scene.version", "template.build"), ("template.", "template.build"),
            ("template.Upper", "template.build"), ("template.a..b", "template.build"), ("template.1a", "template.build"),
            ("template.\(suffix49)", "template.build"), ("template.\(suffix48)", "template.\(suffix48)"),
            ("template.words.count", "template.words.count"), ("template.é", "template.build")]
        for (k, (why, want)) in cases.enumerated() {
            let t = thrower("demo_thrower\(k)", why)
            XCTAssertEqual(reason("{\"v\":1,\"template\":\"demo_thrower\(k)\",\"params\":{}}", extra: [t]), want, String(why.prefix(30)))
            XCTAssertThrowsError(try t.compile([:])) { XCTAssertEqual(($0 as? MGError)?.reason, want) }
        }
        let declared = MGTemplate(name: "demo_thrower_d", summary: "x", params: []) { _, _ in throw MGError("scene.version") }
        XCTAssertEqual(reason(#"{"v":1,"template":"demo_thrower_d","params":{}}"#, extra: [declared]), "template.build")
    }

    /// Regression: the public entry point validates before it builds, so params that never passed `validate` cannot
    /// reach template code that relies on them (an empty `bst` list or a NaN node count used to trap).
    func testPublicCompileValidatesBeforeBuilding() throws {
        let bst = try XCTUnwrap(MGTemplates.library["bst"])
        XCTAssertThrowsError(try bst.compile([:])) { XCTAssertEqual(($0 as? MGError)?.reason, "template.values") }
        XCTAssertThrowsError(try bst.compile(["find": .number(3)])) { XCTAssertEqual(($0 as? MGError)?.reason, "template.values") }
        XCTAssertThrowsError(try MGGraphPack.shortestPath.compile(["n": .number(.nan)])) { XCTAssertEqual(($0 as? MGError)?.reason, "template.n") }
        XCTAssertThrowsError(try MGGraphPack.shortestPath.compile(["n": .number(3.5), "edges": .array([])])) { XCTAssertEqual(($0 as? MGError)?.reason, "template.n.integer") }
        XCTAssertNotNil(try bst.compile(["values": .array([.number(2), .number(1)])]))
    }

    // MARK: non-finite numbers built in code (no JSON form; must be refused, never crash)

    func testNonFiniteNumbersAreRefusedEverywhereTheyCanEnter() throws {
        let scene = try XCTUnwrap(MGFixtures.all.first { $0.id == "pointers" }?.scene)
        for bad in [Double.nan, .infinity, -.infinity] {
            XCTAssertFalse(MGJSON.object(["x": .array([.number(bad)])]).isEncodable)
            XCTAssertEqual(MGJSON.number(bad).canonicalByteCount, Int.max)
            XCTAssertEqual(MGJSON.number(bad).canonicalData, Data())                              // no exception
            let slider = MGPatch(ops: [.object(["op": .string("params"), "params": .object(["target": .number(bad)])])])
            XCTAssertEqual(scene.applying(slider).reasonIfFailed, "patch.number")
            let padded = MGPatch(ops: [.object(["op": .string("params"), "params": .object(["pad": .string(String(repeating: "a", count: 50_000)), "n": .number(bad)])])])
            XCTAssertEqual(scene.applying(padded).reasonIfFailed, "patch.number")
            XCTAssertEqual(MGPatch.parse(json: .object(["v": .number(1), "ops": .array([.object(["op": .string("step"), "index": .number(bad)])])])).reasonIfFailed, "patch.number")
            XCTAssertThrowsError(try Self.labels.validate(["labels": .array([.number(bad)])])) { XCTAssertEqual(($0 as? MGError)?.reason, "template.params.number") }
            let big = MGJSON.object(["v": .number(1), "template": .string("demo_labels"),
                                     "params": .object(["labels": .array([.string("A")]), "pad": .string(String(repeating: "a", count: 20_000)), "n": .number(bad)])])
            XCTAssertEqual(MGParser.scene(json: big, extraTemplates: [Self.labels]).reasonIfFailed, "scene.number")
            XCTAssertEqual(MGParser.scene(json: .object(["v": .number(1), "items": .array([.object(["id": .string("b"), "k": .string("body"), "at": .array([.number(bad), .number(1)])])])])).reasonIfFailed, "scene.number")
            XCTAssertEqual(MGSolidParser.document(json: .object(["v": .number(bad)])).reasonIfFailed, "assembly.bytes")
            // A lesson value built in code is refused before it is measured or turned into statements (before its keys).
            XCTAssertEqual(MGLesson.parse(json: .object(["v": .number(1), "kind": .string("lesson"), "pad": .number(bad)])).reasonIfFailed, "lesson.number")
        }
        // A finite value over the bound is still measured, not treated as small.
        XCTAssertGreaterThan(MGJSON.string(String(repeating: "a", count: 5000)).canonicalByteCount, MGLimits.rawParamsBytes)
    }

    // MARK: pack patches and fail-safe cases

    func testPackPatchesAndInvalidCasesAreValidated() {
        let good = MGFixtures.PatchDemo(id: "demo_add", scene: "demo_abc", ask: "Add D", json: #"{"v":1,"ops":[{"op":"params","params":{"labels":["A","B","C","D"]}}]}"#)
        let refused = ("too_many", #"{"v":1,"template":"demo_labels","params":{"labels":["1","2","3","4","5","6","7"]}}"#)
        XCTAssertEqual(MGPacks.validate(Self.rawPack(patches: [good], invalid: [refused])), [])
        let badPatch = MGFixtures.PatchDemo(id: "demo_bad", scene: "demo_abc", ask: "x", json: #"{"v":1,"ops":[{"op":"params","params":{"labels":[]}}]}"#)
        let noFixture = MGFixtures.PatchDemo(id: "demo_lost", scene: "nope", ask: "x", json: #"{"v":1,"ops":[{"op":"title","title":"x"}]}"#)
        let unparsable = MGFixtures.PatchDemo(id: "demo_junk", scene: "demo_abc", ask: "x", json: #"{"v":1,"ops":[]}"#)
        let accepted = ("fine", #"{"v":1,"template":"demo_labels","params":{"labels":["A"]}}"#)
        XCTAssertEqual(MGPacks.validate(Self.rawPack(patches: [badPatch, noFixture, unparsable], invalid: [accepted])),
                       [.patchInvalid("demo_bad", "template.labels"), .patchInvalid("demo_lost", "fixture.unknown"),
                        .patchInvalid("demo_junk", "patch.ops"), .invalidAccepted("fine")])
        XCTAssertThrowsError(try MGPacks.register(Self.rawPack(invalid: [accepted]))) { XCTAssertEqual($0 as? MGPackError, .invalidAccepted("fine")) }
        XCTAssertNil(MGTemplates.library["demo_labels"])
        XCTAssertEqual(MGPackError.patchInvalid("p", "why").description, "patch 'p' does not apply to its fixture: why")
        XCTAssertEqual(MGPackError.invalidAccepted("c").description, "invalid case 'c' was accepted")
    }

    func testCorePackPatchesApplyAndInvalidCasesFailWithExpectedReasons() throws {
        XCTAssertEqual(MGPacks.validate(MGPacks.core), [])
        XCTAssertEqual(MGPacks.core.patches.count, MGFixtures.patches.count)
        for pd in MGFixtures.patches {
            let base = try XCTUnwrap(MGFixtures.all.first { $0.id == pd.scene }?.scene, pd.id)
            XCTAssertNoThrow(try base.applying(MGPatch.parse(data: Data(pd.json.utf8)).get()).get(), pd.id)
        }
        let expected: [String: String] = [
            "root_extra_member": "scene.unknown.mood", "wire_version_three": "scene.version", "tree_value_too_big": "template.values",
            "pointers_without_vals": "template.vals", "pointers_descending": "template.check", "tree_repeated_key": "template.check",
            "template_not_registered": "template.unknown", "tree_find_as_text": "template.find",
            "title_unknown_value": "title.placeholder.total", "edge_missing_node": "edge.nodes", "node_id_reused": "id.duplicate.q",
            "label_with_link": "item.label", "caption_with_tag": "text.text", "code_line_with_tag": "text.text",
            "caption_blank_lines": "text.text", "node_far_left": "node.at", "orbit_with_depth": "orbit.at",
            "array_in_3d": "3d.kind.array", "table_in_3d": "3d.kind.table", "code_in_3d": "3d.text.code",
            "ragged_table": "table.cells", "region_two_points": "region.pts", "focus_on_missing_item": "step.focus",
            "wire_items_over_limit": "items.count"]
        XCTAssertEqual(Set(MGFixtures.invalid.map(\.0)), Set(expected.keys))
        XCTAssertEqual(MGFixtures.invalid.count, expected.count)                                   // names are unique
        for (name, json) in MGFixtures.invalid {
            guard case .failure(let e) = MGParser.scene(data: Data(json.utf8)) else { XCTFail("\(name) accepted"); continue }
            XCTAssertEqual(e.reason, expected[name], name)
        }
    }

    // MARK: extra templates on parse and patch

    func testExtraTemplatesParseAndPatchWithoutRegistering() throws {
        let json = #"{"v":1,"template":"demo_labels","params":{"labels":["A"]}}"#
        let scene = try MGParser.scene(json: MGJSON(any: try JSONSerialization.jsonObject(with: Data(json.utf8)))!, extraTemplates: [Self.labels]).get()
        let patch = try MGPatch.parse(data: Data(#"{"v":1,"rev":0,"ops":[{"op":"params","params":{"labels":["A","B"]}}]}"#.utf8)).get()
        guard case .failure(let e) = scene.applying(patch) else { return XCTFail("unregistered template must not resolve") }
        XCTAssertEqual(e.reason, "template.unknown")
        XCTAssertEqual(try scene.applying(patch, extraTemplates: [Self.labels]).get().items.count, 2)
        XCTAssertNil(MGTemplates.library["demo_labels"])
        // A registered template with the same name wins over an extra one.
        let shadow = MGTemplate(name: "bst", summary: "x", paramsDoc: "{}", sample: .object([:])) { _, _ in throw MGError("template.shadow") }
        XCTAssertNoThrow(try MGParser.scene(object: ["v": 1, "template": "bst", "params": ["values": [2, 1]]], extraTemplates: [shadow]).get())
    }

    // MARK: patches built in code

    func testCodeBuiltPatchesGetTheParseRules() throws {
        let scene = try XCTUnwrap(MGFixtures.all.first { $0.id == "pointers" }?.scene)
        let ok = MGPatch(ops: [.object(["op": .string("params"), "params": .object(["target": .number(11)])])], baseRevision: 0)
        XCTAssertEqual(try scene.applying(ok).get().revision, 1)
        XCTAssertEqual(MGPatch(ops: ok.ops), try MGPatch.parse(data: Data(#"{"v":1,"ops":[{"op":"params","params":{"target":11}}]}"#.utf8)).get())
        let cases: [(MGPatch, String)] = [
            (MGPatch(ops: []), "patch.ops"),
            (MGPatch(ops: Array(repeating: .object(["op": .string("title"), "title": .string("x")]), count: 13)), "patch.ops"),
            (MGPatch(ops: [.object(["op": .string("add")])]), "patch.add.missing"),                         // was a force unwrap
            (MGPatch(ops: [.object(["op": .string("fly")])]), "patch.op.fly"),
            (MGPatch(ops: [.string("x")]), "patch.op"),
            (MGPatch(ops: [.object(["op": .string("step"), "index": .number(0.5)])]), "patch.step"),
            (MGPatch(ops: [.object(["op": .string("title"), "title": .string(String(repeating: "a", count: MGLimits.patchBytes))])]), "patch.object"),
            (MGPatch(ops: ok.ops, baseRevision: 5), "patch.stale")
        ]
        for (patch, want) in cases {
            guard case .failure(let e) = scene.applying(patch) else { XCTFail("accepted: \(want)"); continue }
            XCTAssertEqual(e.reason, want)
        }
    }
}

private extension MGItem { func with(text: String) -> MGItem { var c = self; c.text = text; return c } }
private extension Result { var reasonIfFailed: String? {
    if case .failure(let e) = self { return (e as? MGError)?.reason ?? (e as? MGSolidIssue)?.reason ?? (e as? MGLessonIssue)?.reason ?? "\(e)" }; return nil
} }
