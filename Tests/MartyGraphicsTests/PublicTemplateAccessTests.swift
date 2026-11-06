// SPDX-License-Identifier: Apache-2.0
import XCTest
import MartyGraphics   // public API only: this file proves what a host outside the module can reach

/// What host documentation or tooling may read without `@testable`: the built-in and registered pack
/// lists, each template's `validate`, `compile`, `sample` and `paramsDoc`, pack patches and fail-safe cases, code-built
/// patches and parsing with unregistered templates.
final class PublicTemplateAccessTests: XCTestCase {
    func testHostCanReadPacksAndCheckTemplateParams() throws {
        XCTAssertEqual(MGPacks.builtIn.map(\.id), ["core"])
        XCTAssertEqual(Array(MGPacks.all.prefix(MGPacks.builtIn.count)).map(\.id), MGPacks.builtIn.map(\.id))
        let core = try XCTUnwrap(MGPacks.builtIn.first)
        XCTAssertFalse(core.patches.isEmpty)
        XCTAssertFalse(core.invalid.isEmpty)
        for t in core.templates {
            XCTAssertFalse(t.isRaw); XCTAssertNil(t.paramsDoc); XCTAssertNil(t.sample)
        }
        // Check parameters, then compile them (validate + build); the parser remains the final check.
        let bst = try XCTUnwrap(core.templates.first { $0.name == "bst" })
        XCTAssertEqual(try bst.validate(["values": .array([.number(4), .number(2), .number(6)])]).lists["values"], [4, 2, 6])
        let built = try XCTUnwrap(try bst.compile(["values": .array([.number(4), .number(2), .number(6)])]))
        XCTAssertEqual(built.items.filter { $0.kind == .node }.count, 3)
        XCTAssertThrowsError(try bst.validate(["values": .array([.number(1), .number(1)])]))
        // `compile` validates first, so params a host gets wrong are refused with a reason instead of trapping.
        for (params, reason) in [([:], "template.values"), (["values": .array([])], "template.values"),
                                 (["values": .array([.number(1)]), "find": .string("x")], "template.find")] as [([String: MGJSON], String)] {
            XCTAssertThrowsError(try bst.compile(params)) { XCTAssertEqual(($0 as? MGError)?.reason, reason) }
        }
    }

    func testHostCanUseRawTemplateSamplesAndExtras() throws {
        let raw = MGTemplate(name: "host_words", summary: "one text line per word", paramsDoc: "words:[1–3 strings]",
                             sample: .object(["words": .array([.string("one"), .string("two")])])) { params, _ in
            guard case .array(let words)? = params["words"], (1...3).contains(words.count) else { throw MGError("template.words") }
            return MGTemplateBuild(title: "Words", items: words.enumerated().compactMap { k, w in
                guard case .string(let s) = w else { return nil }
                return MGMake.text("w\(k)", MGPoint(6, 6 - Double(k)), s)
            })
        }
        XCTAssertTrue(raw.isRaw)
        let sample = try XCTUnwrap(raw.sample?.objectValue)
        XCTAssertNotNil(try raw.compile(sample))
        XCTAssertThrowsError(try raw.compile(["words": .array([.number(.nan)])])) { XCTAssertEqual(($0 as? MGError)?.reason, "template.params.number") }
        let scene = try MGParser.scene(object: ["v": 1, "template": "host_words", "params": raw.sample!.any], extraTemplates: [raw]).get()
        XCTAssertEqual(scene.items.count, 2)
        let patch = MGPatch(ops: [.object(["op": .string("params"), "params": .object(["words": .array([.string("x")])])])], baseRevision: scene.revision)
        XCTAssertEqual(try scene.applying(patch, extraTemplates: [raw]).get().items.count, 1)
        let demo = MGFixtures.PatchDemo(id: "host_patch", scene: "host_fixture", ask: "Fewer words", json: #"{"v":1,"ops":[{"op":"params","params":{"words":["a"]}}]}"#)
        let pack = MGPack(id: "host_pack", title: "Host", summary: "x", templates: [raw],
                          fixtures: [MGFixtures.Demo(id: "host_fixture", title: "x", json: #"{"v":1,"template":"host_words","params":{"words":["a","b"]}}"#)],
                          patches: [demo], invalid: [("empty", #"{"v":1,"template":"host_words","params":{"words":[]}}"#)])
        XCTAssertEqual(MGPacks.validate(pack), [])
    }
}
