// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import MartyGraphics

/// Reusable solid components: definitions, `use` expansion, the built-in library and its refusals.
final class SolidComponentTests: XCTestCase {
    let lib = MGSolidLibrary.builtIn

    func compile(_ s: String, _ library: MGSolidLibrary = .builtIn) -> Result<MGSolidDocument, MGSolidIssue> {
        MGSolidParser.document(data: Data(s.utf8), library: library)
    }
    func reason(_ s: String, _ library: MGSolidLibrary = .builtIn) -> String? {
        if case .failure(let e) = compile(s, library) { return e.reason }
        return nil
    }
    func doc(_ parts: String, constraints: String = "", steps: String = "") -> String {
        "{\"v\": 1, \"kind\": \"assembly\", \"parts\": [\(parts)], \"constraints\": [\(constraints)], \"steps\": [\(steps)]}"
    }
    func component(_ id: String, params: String = "{}", parts: String, extra: String = "") -> String {
        "{\"v\": 1, \"kind\": \"component\", \"id\": \"\(id)\", \"title\": \"T\", \"about\": \"A test component.\", \"params\": \(params), \"parts\": [\(parts)]\(extra)}"
    }
    func registered(_ sources: [String]) throws -> MGSolidLibrary {
        var l = MGSolidLibrary.builtIn
        for s in sources { _ = try l.register(Data(s.utf8)).get() }
        return l
    }
    func registerReason(_ source: String, _ library: MGSolidLibrary = .builtIn) -> String? {
        var l = library
        if case .failure(let e) = l.register(Data(source.utf8)) { return e.reason }
        return nil
    }
    func modelURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Examples/Solid3D/Sources/MartySolid3D/Models/\(name).json")
    }
    let box = "{\"box\": {\"size\": [4, 4, 4]}}"

    // MARK: Library

    func testBuiltInLibraryAndCatalog() throws {
        XCTAssertEqual(lib.ids, ["centrifugalCompressor", "fanStage", "housingBase", "mannequin", "planetaryStage", "propeller", "shaftWithBearing",
                                 "sliderCrank", "spurPair"])
        XCTAssertEqual(MGSolidBuiltInComponents.sources.count, lib.ids.count)   // none was refused while loading
        guard case .array(let entries)? = lib.catalog()["components"] else { return XCTFail("catalog") }
        XCTAssertEqual(entries.count, 9)
        let spur = try XCTUnwrap(entries.first { $0["id"] == .string("spurPair") })
        XCTAssertEqual(spur["parts"], .array([.string("pinion"), .string("wheel")]))
        XCTAssertEqual(spur["anchors"]?["output"], .string("wheel"))
        XCTAssertEqual(spur["params"]?["pinionTeeth"]?["integer"], .bool(true))
        XCTAssertEqual(spur["params"]?["module"]?["default"], .number(2))
        for e in entries {
            guard case .string(let about)? = e["about"] else { return XCTFail("about") }
            XCTAssertLessThanOrEqual(about.count, MGSolidComponentLimits.about)
        }
        // Small enough for a model to read on every request.
        XCTAssertLessThan(lib.catalog().canonicalData.count, 8 * 1024)
    }

    /// Every built-in compiles at its defaults with closed meshes and engaging, non-interpenetrating gears, and passes
    /// the full registration check a new component gets.
    func testEveryBuiltInInstantiatesAndChecks() throws {
        for id in lib.ids {
            let d = try lib.instantiate(id).get()
            for p in d.assembly.parts { XCTAssertTrue(p.mesh.edgeReport.isClosed, "\(id): \(p.id)") }
            XCTAssertTrue(d.assembly.parts.allSatisfy { $0.id.hasPrefix(id + ".") })
            let report = MGSolidChecks.gearMeshes(d, samples: 48)
            if report.pairs > 0 { XCTAssertLessThanOrEqual(report.maxPenetration, 0.01 * 2, id) }
            var others = MGSolidLibrary()
            for o in lib.ids where o != id { others.components[o] = lib[o] }
            XCTAssertNoThrow(try others.validate(lib[id]!.source.canonicalData).get(), id)
        }
    }

    func testSpurPairRatioCentreDistanceAndMesh() throws {
        for (z1, z2, m) in [(12, 36, 2.0), (18, 40, 1.5), (25, 25, 3.0)] {
            let d = try lib.instantiate("spurPair", with: ["pinionTeeth": Double(z1), "wheelTeeth": Double(z2), "module": m]).get()
            XCTAssertEqual(d.ratios["spurPair.wheel"]!, -Double(z1) / Double(z2), accuracy: 1e-12)
            let w = d.pose(MGPoseParameters()).world
            XCTAssertEqual((w["spurPair.wheel"]!.translation - w["spurPair.pinion"]!.translation).length, m * Double(z1 + z2) / 2, accuracy: 1e-9)
            for s in [0.3, 2.9] { for r in d.assembly.gearResiduals(MGPoseParameters(input: s)) { XCTAssertEqual(r, 0, accuracy: 1e-9) } }
            let report = MGSolidChecks.gearMeshes(d, samples: 48)
            XCTAssertEqual(report.pairs, 1)
            XCTAssertLessThanOrEqual(report.maxPenetration, 0.01 * m)
            XCTAssertLessThan(report.minClearance, 0.3 * m)   // the teeth engage
        }
    }

    func testPlanetaryStageRatioPlanetsAndChecks() throws {
        let d = try lib.instantiate("planetaryStage").get()
        XCTAssertEqual(d.ratios["planetaryStage.carrier"]!, 24.0 / 84.0, accuracy: 1e-12)
        XCTAssertEqual(d.assembly.parts.filter { $0.id.hasPrefix("planetaryStage.planet") }.count, 3)
        XCTAssertEqual(d.gears["planetaryStage.ring"]?.teeth, 60)
        let four = try lib.instantiate("planetaryStage", with: ["sunTeeth": 20, "planetTeeth": 16, "planets": 4]).get()
        XCTAssertEqual(four.ratios["planetaryStage.carrier"]!, 20.0 / 72.0, accuracy: 1e-12)
        XCTAssertEqual(four.assembly.parts.filter { $0.id.hasPrefix("planetaryStage.planet") }.count, 4)
        XCTAssertLessThanOrEqual(MGSolidChecks.gearMeshes(four, samples: 36).maxPenetration, 0.02)
        // Unequal spacing and crowded planets are refused by the component's own checks, by name.
        func refusal(_ with: [String: Double]) -> String? {
            if case .failure(let e) = lib.instantiate("planetaryStage", with: with) { return e.reason }
            return nil
        }
        XCTAssertEqual(refusal(["planets": 5]), "component.check.spacing")
        XCTAssertEqual(refusal(["planets": 6, "sunTeeth": 12, "planetTeeth": 24]), "component.check.planetsClear")
    }

    func testSliderCrankStrokeIsTwiceTheRadius() throws {
        for (r, l) in [(18.0, 62.0), (25.0, 80.0)] {
            let d = try lib.instantiate("sliderCrank", with: ["radius": r, "rod": l]).get()
            let x0 = d.pose(MGPoseParameters(input: 0)).world["sliderCrank.piston"]!.translation.x
            let x1 = d.pose(MGPoseParameters(input: .pi)).world["sliderCrank.piston"]!.translation.x
            XCTAssertEqual(abs(x0 - x1), 2 * r, accuracy: 1e-9)
        }
        if case .failure(let e) = lib.instantiate("sliderCrank", with: ["radius": 30, "rod": 60]) { XCTAssertEqual(e.reason, "component.check.rodLength") }
        else { XCTFail("short rod accepted") }
    }

    func testPropellerBladeCountAndFanStage() throws {
        for n in [2, 3, 5] {
            let d = try lib.instantiate("propeller", with: ["blades": Double(n)]).get()
            XCTAssertEqual(d.assembly.parts.filter { $0.id.hasPrefix("propeller.blade") }.count, n)
            XCTAssertEqual(d.ratios["propeller.hub"], 1)
        }
        let fan = try lib.instantiate("fanStage", with: ["blades": 24]).get()
        XCTAssertEqual(fan.shapes["fanStage.rotor"]?.first?.fields["count"], .number(24))
    }

    // MARK: Use in assemblies

    func testUsePlacementAnchorsGroupsAndRepeatRoots() throws {
        let d = try compile(doc("{\"id\": \"s1\", \"use\": \"spurPair\", \"at\": [0, 0, 50], \"rot\": [1, 0, 0, 90]}",
                                steps: "{\"say\": \"Both gears.\", \"highlight\": [\"s1\"]}, {\"say\": \"Output.\", \"highlight\": [\"s1.output\"]}")).get()
        let w = d.pose(MGPoseParameters()).world
        XCTAssertEqual((w["s1.wheel"]!.translation - MGVec3(48, 0, 50)).length, 0, accuracy: 1e-9)
        XCTAssertEqual((w["s1.pinion"]!.c2 - MGVec3(0, -1, 0)).length, 0, accuracy: 1e-9)   // the gear axes turn with the instance
        XCTAssertEqual(d.ratios["s1.wheel"]!, -1.0 / 3.0, accuracy: 1e-12)
        XCTAssertEqual(d.steps[0].highlight, ["s1.pinion", "s1.wheel"])
        XCTAssertEqual(d.steps[1].highlight, ["s1.wheel"])
        // A repeated root part turns about its own frame inside the instance, then the instance frame applies.
        let ring = component("pins", parts: "{\"id\": \"pin\", \"at\": [10, 0, 0], \"repeat\": {\"count\": 4}, \"shape\": \(box)}")
        let l = try registered([ring])
        let p = try compile(doc("{\"id\": \"p\", \"use\": \"pins\", \"at\": [100, 0, 0]}"), l).get().pose(MGPoseParameters()).world
        XCTAssertEqual((p["p.pin2"]!.translation - MGVec3(100, 10, 0)).length, 0, accuracy: 1e-9)
        XCTAssertEqual((p["p.pin3"]!.translation - MGVec3(90, 0, 0)).length, 0, accuracy: 1e-9)
    }

    /// A component built from components: a compound two-stage train whose second pinion is keyed to the first wheel
    /// through `set`, with anchors that reach through the nesting.
    func testNestedComponentsCompoundTrain() throws {
        let twoStage = component("twoStage", parts: """
            {"id": "first", "use": "spurPair"},
            {"id": "second", "use": "spurPair", "at": [48, 0, 14],
             "set": {"pinion": {"parent": "first.output", "at": [0, 0, 14], "joint": null, "drive": null}}}
            """, extra: ", \"anchors\": {\"input\": \"first.input\", \"output\": \"second.output\"}")
        let l = try registered([twoStage])
        XCTAssertEqual(l["twoStage"]?.parts, ["first.pinion", "first.wheel", "second.pinion", "second.wheel"])
        let d = try compile(doc("{\"id\": \"box\", \"use\": \"twoStage\"}", steps: "{\"say\": \"Out.\", \"highlight\": [\"box.output\", \"box.second\"]}"), l).get()
        XCTAssertEqual(d.ratios["box.second.wheel"]!, 1.0 / 9.0, accuracy: 1e-12)
        XCTAssertEqual(d.steps[0].highlight, ["box.second.wheel", "box.second.pinion"])
        let w = d.pose(MGPoseParameters()).world
        XCTAssertEqual((w["box.second.pinion"]!.translation - MGVec3(48, 0, 14)).length, 0, accuracy: 1e-9)
        XCTAssertEqual((w["box.second.wheel"]!.translation - MGVec3(96, 0, 14)).length, 0, accuracy: 1e-9)
        XCTAssertLessThanOrEqual(MGSolidChecks.gearMeshes(d, samples: 36).maxPenetration, 0.02)
        // Outer parts drive and reference inner parts by their full ids.
        let motor = "{\"id\": \"motor\", \"at\": [0, 0, -30], \"shape\": {\"shaft\": {\"radius\": 3, \"length\": 10}}, \"joint\": {\"revolute\": [0, 0, 1]}, \"drive\": {\"input\": 1}}"
        let driven = try compile(doc("\(motor), {\"id\": \"e\", \"use\": \"sliderCrank\", \"at\": [0, 100, 0], \"set\": {\"crank\": {\"drive\": {\"follow\": {\"source\": \"motor\", \"ratio\": 2}}}}}")).get()
        XCTAssertEqual(driven.assembly.part("e.crank")?.drive, .follow(source: "motor", ratio: 2, offset: 0))
        let x0 = driven.pose(MGPoseParameters(input: 0)).world["e.piston"]!.translation.x
        let x1 = driven.pose(MGPoseParameters(input: .pi / 2)).world["e.piston"]!.translation.x
        XCTAssertEqual(abs(x0 - x1), 36, accuracy: 1e-9)   // the crank turns twice as fast as the motor
    }

    func testPatchesEditInstancesAndInnerParts() throws {
        let base = try compile(doc("{\"id\": \"s1\", \"use\": \"spurPair\"}")).get()
        let fewer = try MGSolidParser.applying(.object(["parts": .object(["s1": .object(["with": .object(["wheelTeeth": .number(40)])])])]), to: base).get()
        XCTAssertEqual(fewer.ratios["s1.wheel"]!, -12.0 / 40.0, accuracy: 1e-12)
        let restyled = try MGSolidParser.applying(.object(["parts": .object(["s1.wheel": .object(["material": .string("bronze")])])]), to: base).get()
        XCTAssertEqual(restyled.assembly.part("s1.wheel")?.material, .bronze)
        XCTAssertEqual(restyled.assembly.part("s1.pinion")?.mesh, base.assembly.part("s1.pinion")?.mesh)
        guard case .failure(let e) = MGSolidParser.applying(.object(["parts": .object(["s1.ghost": .object(["material": .string("brass")])])]), to: base) else {
            return XCTFail("ghost accepted")
        }
        XCTAssertEqual(e.reason, "component.set.unknown.ghost")
        // A document compiled with a host library keeps it for patches.
        let l = try registered([component("cube", parts: "{\"id\": \"c\", \"shape\": \(box)}")])
        let d = try compile(doc("{\"id\": \"k\", \"use\": \"cube\"}"), l).get()
        XCTAssertNoThrow(try MGSolidParser.applying(.object(["title": .string("Cube")]), to: d).get())
    }

    // MARK: Refusals

    func testUseRefusals() throws {
        let cases: [(String, String)] = [
            (doc("{\"id\": \"s\", \"use\": \"nope\"}"), "component.unknown.nope"),
            (doc("{\"id\": \"s\", \"use\": \"spurPair\", \"with\": {\"teeth\": 18}}"), "component.param.unknown.teeth"),
            (doc("{\"id\": \"s\", \"use\": \"spurPair\", \"with\": {\"module\": 50}}"), "component.param.range.module"),
            (doc("{\"id\": \"s\", \"use\": \"spurPair\", \"with\": {\"pinionTeeth\": 12.5}}"), "component.param.integer.pinionTeeth"),
            (doc("{\"id\": \"s\", \"use\": \"spurPair\", \"with\": {\"module\": \"2\"}}"), "component.param.value.module"),
            (doc("{\"id\": \"s\", \"use\": \"spurPair\", \"with\": {\"module\": {\"param\": \"module\"}}}"), "component.param.value.module"),
            (doc("{\"id\": \"s\", \"use\": \"spurPair\", \"with\": [1]}"), "component.with"),
            (doc("{\"id\": \"s\", \"use\": \"spurPair\", \"repeat\": {\"count\": 2}}"), "component.use.unknown.repeat"),
            (doc("{\"id\": \"s\", \"use\": \"spurPair\", \"set\": {\"ghost\": {\"material\": \"brass\"}}}"), "component.set.unknown.ghost"),
            (doc("{\"id\": \"s\", \"use\": \"spurPair\", \"set\": {\"wheel\": {\"id\": \"w\"}}}"), "component.set.id"),
            (doc("{\"id\": \"s\", \"use\": \"spurPair\", \"rot\": [0, 0, 0, 90]}"), "component.use.rot"),
            (doc("{\"id\": \"s\", \"use\": \"spurPair\"}, {\"id\": \"s\", \"shape\": \(box)}"), "id.duplicate.s"),
            (doc("{\"id\": \"s\", \"use\": \"spurPair\"}, {\"id\": \"s\", \"use\": \"spurPair\"}"), "id.duplicate.s"),
            (doc("{\"id\": \"s\", \"use\": \"spurPair\"}", constraints: "{\"fixed\": \"s\"}"), "ref.component.s"),
            (doc("{\"id\": \"s\", \"use\": \"spurPair\"}, {\"id\": \"x\", \"parent\": \"s.ghost\", \"shape\": \(box)}"), "ref.unknown.s.ghost"),
            (doc("{\"id\": \"a.b\", \"shape\": \(box)}"), "part.id"),
            // Expanded documents keep every assembly check: a wheel moved off the centre distance is refused.
            (doc("{\"id\": \"s\", \"use\": \"spurPair\", \"set\": {\"wheel\": {\"at\": [50, 0, 0]}}}"), "constraint.gearMesh.distance"),
        ]
        for (json, expected) in cases {
            XCTAssertEqual(reason(json), expected, json)
            XCTAssertEqual(reason(json), reason(json))
            XCTAssertFalse(reason(json)?.contains(where: { $0 == " " || $0 == "\"" }) ?? true)
        }
        // The part count applies after expansion: 13 slider-cranks are 52 parts.
        let many = (1...13).map { "{\"id\": \"e\($0)\", \"use\": \"sliderCrank\", \"at\": [0, \($0 * 200), 0]}" }.joined(separator: ", ")
        XCTAssertEqual(reason(doc(many)), "parts.count")
    }

    func testMeshBudgetAppliesAfterExpansion() throws {
        // One blade row of 78 blades is 249,288 triangles, under the per-row cap; two per part, four instances exceed
        // the 1.5 M budget of the expanded assembly although each definition is small.
        let row = "{\"bladeRow\": {\"count\": 78, \"span\": 40, \"chord\": 10, \"root\": 500, \"sections\": 24, \"chordSamples\": 32}}"
        let heavy = component("heavy", parts: "{\"id\": \"rows\", \"shape\": [\(row), \(row)]}")
        var l = MGSolidLibrary.builtIn
        XCTAssertNoThrow(try l.add(Data(heavy.utf8), compile: false).get())
        XCTAssertLessThan(heavy.utf8.count, 400)
        let four = (1...4).map { "{\"id\": \"h\($0)\", \"use\": \"heavy\", \"at\": [0, 0, \($0 * 50)]}" }.joined(separator: ", ")
        let t0 = Date()
        XCTAssertEqual(reason(doc(four), l), "assembly.budget")
        XCTAssertLessThan(Date().timeIntervalSince(t0), 2)   // refused before any mesh is built
    }

    func testExpressionRefusals() throws {
        func part(_ field: String) -> String { component("bad", params: "{\"w\": {\"default\": 4, \"min\": 1, \"max\": 9}}",
                                                         parts: "{\"id\": \"c\", \"shape\": {\"shaft\": {\"radius\": 2, \"length\": \(field)}}}") }
        var deep = "{\"param\": \"w\"}"
        for _ in 0..<9 { deep = "{\"neg\": \(deep)}" }
        let cases: [(String, String)] = [
            (part("{\"param\": \"nope\"}"), "component.expr.param.nope"),
            (part("{\"div\": [{\"param\": \"w\"}, 0]}"), "component.expr.div"),
            (part("{\"add\": []}"), "component.expr.add"),
            (part("{\"sub\": [1]}"), "component.expr.sub"),
            (part("{\"add\": [\"w\"]}"), "component.expr"),
            (part("{\"param\": 3}"), "component.expr.param"),
            (part("{\"mul\": [1000000, {\"param\": \"w\"}]}"), "component.expr.range"),
            (part(deep), "component.expr.depth"),
            // A valid expression that gives an invalid shape is refused by the assembly checks at registration.
            (part("{\"neg\": {\"param\": \"w\"}}"), "part.shaft.length"),
        ]
        for (json, expected) in cases { XCTAssertEqual(registerReason(json), expected, json) }
        // Node budget per instance (reachable inside 16 KiB of compact JSON, about 5,000 nodes).
        let wide = "{\"add\": [" + Array(repeating: "{\"add\": [1, 1, 1, 1, 1, 1, 1, 1]}", count: 8).joined(separator: ", ") + "]}"
        let leaf: MGJSON = .object(["add": .array(Array(repeating: .number(1), count: 8))])
        let node: MGJSON = .object(["add": .array(Array(repeating: leaf, count: 8))])
        let big: MGJSON = .object(["add": .array(Array(repeating: .object(["add": .array(Array(repeating: node, count: 8))]), count: 8))])
        var ctx = MGSolidComponents.Context(library: .builtIn)
        XCTAssertThrowsError(try MGSolidComponents.eval(big, [:], 1, &ctx)) { XCTAssertEqual(($0 as? MGSolidIssue)?.reason, "component.expr.size") }
        let many = Array(repeating: "{\"id\": \"cX\", \"shape\": {\"shaft\": {\"radius\": 2, \"length\": \(wide)}}}", count: 24).enumerated()
            .map { $0.element.replacingOccurrences(of: "cX", with: "c\($0.offset)") }.joined(separator: ", ")
        XCTAssertNil(registerReason(component("wide", parts: many)))   // 24 x 73 nodes stays inside the node budget
    }

    func testDefinitionRefusals() throws {
        let ok = "{\"id\": \"c\", \"shape\": \(box)}"
        let cases: [(String, String)] = [
            ("[1]", "component.object"),
            (component("x", parts: ok).replacingOccurrences(of: "\"kind\": \"component\"", with: "\"kind\": \"assembly\""), "component.kind"),
            (component("x y", parts: ok), "component.id"),
            (component("x", parts: ok, extra: ", \"steps\": []"), "component.unknown.steps"),
            (component("x", parts: ""), "component.parts.count"),
            (component("x", params: "{\"n\": {\"default\": 4, \"min\": 5, \"max\": 9}}", parts: ok), "component.param.n"),
            (component("x", params: "{\"n\": {\"default\": 4.5, \"min\": 1, \"max\": 9, \"integer\": true}}", parts: ok), "component.param.n"),
            (component("x", params: "{\"n\": {\"default\": 4, \"min\": 1}}", parts: ok), "component.param.n.missing.max"),
            (component("x", params: "{\"add\": {\"default\": 4, \"min\": 1, \"max\": 9}}", parts: ok), "component.param.name.add"),
            (component("x", parts: "\(ok), \(ok)"), "id.duplicate.c"),
            (component("x", parts: "{\"id\": \"c.d\", \"shape\": \(box)}"), "part.id"),
            (component("x", parts: "{\"id\": \"c\", \"parent\": \"outside\", \"shape\": \(box)}"), "component.ref.unknown.outside"),
            (component("x", parts: ok, extra: ", \"anchors\": {\"out\": \"ghost\"}"), "component.anchor.out"),
            (component("x", parts: ok, extra: ", \"anchors\": {\"c\": \"c\"}"), "component.anchor.c"),
            (component("x", parts: ok, extra: ", \"checks\": {\"never\": {\"lt\": [2, 1]}}"), "component.check.never"),
            (component("x", parts: ok, extra: ", \"checks\": {\"odd\": {\"eq\": [2, 1]}}"), "component.check"),
            (component("x", parts: "{\"id\": \"u\", \"use\": \"x\"}"), "component.cycle.x"),
            (component("x", parts: "{\"id\": \"u\", \"use\": \"ghost\"}"), "component.unknown.ghost"),
            (component("spurPair", parts: ok), "component.duplicate.spurPair"),
            // Compiled alone at its defaults: an underdetermined gear is refused at registration.
            (component("x", parts: "{\"id\": \"g\", \"use\": \"spurPair\", \"set\": {\"pinion\": {\"drive\": null}}}"), "constraint.underdetermined"),
        ]
        for (json, expected) in cases { XCTAssertEqual(registerReason(json), expected, json) }
        // validate() never registers.
        let fine = component("fine", parts: ok)
        XCTAssertNoThrow(try lib.validate(Data(fine.utf8)).get())
        XCTAssertNil(lib["fine"])
        var l = lib
        XCTAssertNoThrow(try l.register(Data(fine.utf8)).get())
        XCTAssertNotNil(l["fine"])
        XCTAssertEqual(registerReason(fine, l), "component.duplicate.fine")
        guard case .array(let entries)? = l.catalog()["components"] else { return XCTFail("catalog") }
        XCTAssertTrue(entries.contains { $0["id"] == .string("fine") })
    }

    func testNestingDepthCycleAndIdLength() throws {
        let ok = "{\"id\": \"c\", \"shape\": \(box)}"
        let a = component("a", parts: ok), b = component("b", parts: "{\"id\": \"x\", \"use\": \"a\"}")
        let c = component("c", parts: "{\"id\": \"x\", \"use\": \"b\"}"), d = component("d", parts: "{\"id\": \"x\", \"use\": \"c\"}")
        let l = try registered([a, b, c])
        XCTAssertNotNil(try compile(doc("{\"id\": \"top\", \"use\": \"c\"}"), l).get().assembly.part("top.x.x.c"))
        XCTAssertEqual(registerReason(d, l), "component.depth")
        // A cycle cannot be registered; a library assembled by hand is still refused instead of recursing.
        var cyc = MGSolidLibrary()
        for (id, uses) in [("p", "q"), ("q", "p")] {
            let src = component(id, parts: "{\"id\": \"x\", \"use\": \"\(uses)\"}")
            let j = MGJSON(any: try JSONSerialization.jsonObject(with: Data(src.utf8)))!
            cyc.components[id] = MGSolidComponent(id: id, title: "T", about: "A.", params: [], anchors: [:], parts: [], uses: [uses], source: j)
        }
        XCTAssertEqual(reason(doc("{\"id\": \"t\", \"use\": \"p\"}"), cyc), "component.cycle.p")
        // Expanded ids stay at most 64 characters.
        let long = String(repeating: "a", count: 24)
        let inner = component("inner", parts: "{\"id\": \"\(long)\", \"shape\": \(box)}")
        let outer = component("outer", parts: "{\"id\": \"\(long)\", \"use\": \"inner\"}")
        let l2 = try registered([inner, outer])
        XCTAssertEqual(reason(doc("{\"id\": \"\(long)\", \"use\": \"outer\"}"), l2), "component.id.length")
    }

    // MARK: Worked examples

    func testComponentExampleModelsAndSizeBenefit() throws {
        let planetary = try MGSolidParser.document(data: Data(contentsOf: modelURL("planetary-components"))).get()
        XCTAssertEqual(planetary.ratios["stage.carrier"]!, 24.0 / 84.0, accuracy: 1e-12)
        XCTAssertEqual(planetary.steps.count, 5)
        XCTAssertEqual(planetary.steps[3].highlight, ["stage.carrier"])
        for p in planetary.assembly.parts { XCTAssertTrue(p.mesh.edgeReport.isClosed, p.id) }
        XCTAssertLessThanOrEqual(MGSolidChecks.gearMeshes(planetary, samples: 36).maxPenetration, 0.02)
        let crank = try MGSolidParser.document(data: Data(contentsOf: modelURL("slider-crank-component"))).get()
        let x0 = crank.pose(MGPoseParameters(input: 0)).world["engine.piston"]!.translation.x
        let x1 = crank.pose(MGPoseParameters(input: .pi)).world["engine.piston"]!.translation.x
        XCTAssertEqual(abs(x0 - x1), 36, accuracy: 1e-9)
        // The documented example (docs/SOLID-3D.md, "Use in an assembly") compiles and uses two components in 15 lines or fewer.
        let docs = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("docs/SOLID-3D.md"), encoding: .utf8)
        let section = try XCTUnwrap(docs.range(of: "### Use in an assembly\n\n```json\n"))
        let snippet = String(docs[section.upperBound...].prefix { $0 != "`" })
        XCTAssertLessThanOrEqual(snippet.split(separator: "\n").count, 15)
        let documented = try compile(snippet).get()
        XCTAssertEqual(documented.ratios["stage.carrier"]!, 24.0 / 84.0, accuracy: 1e-12)
        XCTAssertEqual(Set(documented.assembly.parts.map { $0.id.split(separator: ".")[0] }), ["base", "stage"])
        XCTAssertEqual(documented.steps[2].highlight, ["stage.sun", "stage.ring", "stage.carrier", "stage.planet1", "stage.planet2", "stage.planet3"])
        // The component versions are much smaller than the hand-written ones they replace.
        for (with, without) in [("planetary-components", "planetary"), ("slider-crank-component", "slider-crank")] {
            let a = try Data(contentsOf: modelURL(with)).count, b = try Data(contentsOf: modelURL(without)).count
            XCTAssertLessThan(a * 3, b * 2, "\(with) \(a) vs \(without) \(b)")
        }
    }
}
