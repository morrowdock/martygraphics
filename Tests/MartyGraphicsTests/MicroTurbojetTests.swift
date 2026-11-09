// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import MartyGraphics

/// The `microTurbojet` built-in component (every parameter corner through the strict check, the fit check, solved
/// rotation, the five-engine suit inside the part limits) and the `parts.resolved` repair detail (`limit`).
final class MicroTurbojetTests: ExplainerTestCase {
    func jet(_ with: String) -> String {
        #"{"v": 2, "kind": "assembly", "title": "Jet", "parts": [{"id": "jet", "use": "microTurbojet", "with": {\#(with)}}]}"#
    }
    func strict(_ text: String) -> MGSolidReport { MGSolidReport.check(data: Data(text.utf8), profile: .strict) }

    func testCatalogEntry() throws {
        let c = try XCTUnwrap(MGSolidLibrary.builtIn["microTurbojet"])
        XCTAssertEqual(c.parts, ["intakeLip", "impeller", "diffuser", "combustor", "nozzleGuideVanes", "turbineWheel", "nozzle", "shaft",
                                 "frontBearing", "rearBearing", "casing"])
        XCTAssertEqual(c.anchors, ["intake": "intakeLip", "exhaust": "nozzle", "mount": "casing", "input": "shaft",
                                   "compressor": "impeller", "turbine": "turbineWheel"])
        XCTAssertEqual(Set(c.anchorAbout.keys), Set(c.anchors.keys))
        XCTAssertEqual(c.params.map(\.name), ["cutaway", "diameter", "length"])
        XCTAssertEqual(c.params.map(\.min), [0, 60, 120])
        XCTAssertEqual(c.params.map(\.max), [1, 300, 900])
        XCTAssertEqual(c.params.map(\.defaultValue), [0, 110, 280])
        XCTAssertTrue(c.about.contains("thrust not modelled"), c.about)
        guard case .array(let entries)? = MGSolidLibrary.builtIn.catalog()["components"] else { return XCTFail("catalog") }
        XCTAssertNotNil(entries.first { $0["id"] == .string("microTurbojet") })
    }

    /// Every corner of the three parameter ranges through `check --strict`: six accepted with no warning, the two short
    /// wide corners refused by the fit check.
    func testEveryParameterCornerWithStrict() throws {
        for d in [60, 300] { for l in [120, 900] { for cut in [0, 1] {
            let r = strict(jet(#""diameter": \#(d), "length": \#(l), "cutaway": \#(cut)"#))
            if d == 300 && l == 120 {
                XCTAssertFalse(r.ok, "\(d) \(l) \(cut)")
                XCTAssertEqual(r.reason, "component.check.fits", "\(d) \(l) \(cut)")
                XCTAssertEqual(r.part, "jet")
            } else {
                XCTAssertTrue(r.ok, "\(d) \(l) \(cut): \(r.reason ?? "")")
                XCTAssertEqual(r.json["parts"], .number(11))
                XCTAssertEqual(r.json["warnings"], .array([]))
            }
        } } }
        // Out of range and not whole: refused before any check.
        XCTAssertEqual(strict(jet(#""diameter": 59"#)).reason, "component.param.range.diameter")
        XCTAssertEqual(strict(jet(#""length": 901"#)).reason, "component.param.range.length")
        XCTAssertEqual(strict(jet(#""cutaway": 0.5"#)).reason, "component.param.integer.cutaway")
    }

    /// The fit check is the geometry's own condition: the compressor stage (to the end of the front bearing,
    /// 0.1 × length + 0.26 × diameter) ends before the combustor (0.38 × length).
    func testFitBoundary() {
        XCTAssertEqual(strict(jet(#""diameter": 200, "length": 180"#)).reason, "component.check.fits")   // 70 > 68.4
        XCTAssertTrue(strict(jet(#""diameter": 200, "length": 190"#)).ok)                                 // 71 < 72.2
    }

    /// Shaft, compressor and turbine turn together, one turn per input turn, Solved; thrust has no fact.
    func testRotationIsSolved() throws {
        let doc = try MGSolidParser.document(data: Data(jet("").utf8)).get()
        for id in ["jet.shaft", "jet.impeller", "jet.turbineWheel", "jet.input", "jet.compressor", "jet.turbine"] {
            let f = try XCTUnwrap(doc.fact("\(id).speed"), id)
            XCTAssertEqual(f.value, 1, id)
            XCTAssertEqual(f.tier, .solved, id)
        }
        XCTAssertNil(doc.fact("jet.thrust"))
        XCTAssertNil(doc.fact("jet.combustor.speed"))
        XCTAssertLessThan(doc.assembly.parts.reduce(0) { $0 + $1.mesh.triangleCount }, 25_000)
        // Every part is a closed mesh, so a step can cut any of them (section-ready).
        let cut = #"{"v": 2, "kind": "assembly", "parts": [{"id": "jet", "use": "microTurbojet"}], "steps": [{"say": "Inside.", "section": {"normal": [1, 0, 0], "offset": 0, "parts": ["jet.casing", "jet.intakeLip", "jet.diffuser", "jet.combustor", "jet.nozzleGuideVanes", "jet.nozzle", "jet.impeller", "jet.turbineWheel", "jet.shaft", "jet.frontBearing", "jet.rearBearing"]}}]}"#
        let r = strict(cut)
        XCTAssertTrue(r.ok, r.reason ?? "")
    }

    /// Five engines, a mannequin and a back pack: 68 parts, inside the 96-part limit and the 96 expanded wire parts.
    static let suit = """
        {"v": 2, "kind": "assembly", "title": "Five engines", "parts": [
         {"id": "pilot", "use": "mannequin", "with": {"leftShoulder": 25, "rightShoulder": 25, "leftElbow": 20, "rightElbow": 20}},
         {"id": "pack", "parent": "pilot.back", "at": [0, 40, 0], "shape": {"box": {"size": [260, 80, 380]}}},
         {"id": "back", "use": "microTurbojet", "parent": "pack", "at": [0, 95, 140], "rot": [1, 0, 0, 180]},
         {"id": "armL1", "use": "microTurbojet", "with": {"diameter": 70, "length": 200}, "parent": "pilot.leftHand", "at": [78, -38, 200], "rot": [1, 0, 0, 180]},
         {"id": "armL2", "use": "microTurbojet", "with": {"diameter": 70, "length": 200}, "parent": "pilot.leftHand", "at": [78, 38, 200], "rot": [1, 0, 0, 180]},
         {"id": "armR1", "use": "microTurbojet", "with": {"diameter": 70, "length": 200}, "parent": "pilot.rightHand", "at": [-78, -38, 200], "rot": [1, 0, 0, 180]},
         {"id": "armR2", "use": "microTurbojet", "with": {"diameter": 70, "length": 200}, "parent": "pilot.rightHand", "at": [-78, 38, 200], "rot": [1, 0, 0, 180]}]}
        """

    func testFiveEnginesAMannequinAndAPackPassStrict() throws {
        let r = strict(Self.suit)
        XCTAssertTrue(r.ok, r.reason ?? "")
        XCTAssertEqual(r.json["parts"], .number(68))
        XCTAssertEqual(r.json["warnings"], .array([]))
        // A sixth engine still fits (79 parts).
        let six = Self.suit.replacingOccurrences(of: #"{"id": "back","#, with: #"{"id": "spare", "use": "microTurbojet", "at": [1000, 0, 0]}, {"id": "back","#)
        XCTAssertEqual(strict(six).json["parts"], .number(79))
    }

    // MARK: parts.resolved

    func compressors(_ ids: [String], vanes: [String: Int] = [:]) -> String {
        let uses = ids.enumerated().map { k, id -> String in
            let v = vanes[id].map { #", "with": {"vanes": \#($0), "diffuserVanes": 12}"# } ?? ""
            return #"{"id": "\#(id)", "use": "centrifugalCompressor", "at": [\#(k * 300), 0, 0]\#(v)}"#
        }
        return #"{"v": 2, "kind": "assembly", "parts": [{"id": "pilot", "use": "mannequin"}, \#(uses.joined(separator: ", "))]}"#
    }

    /// Six compressor stages and a mannequin: 180 parts. The report names the count, the limit and the five largest
    /// instances (ties by id), in every run; the reason stays one token.
    func testPartsResolvedNamesTheCountAndTheLargestInstances() throws {
        let text = compressors(["tRH", "tLH", "tB", "tLF", "tRF", "tX"])
        let r = MGSolidReport.check(data: Data(text.utf8), profile: .strict)
        XCTAssertEqual(r.reason, "parts.resolved")
        XCTAssertNil(r.part)
        let top: [MGJSON] = ["tB", "tLF", "tLH", "tRF", "tRH"].map {
            .object(["id": .string($0), "use": .string("centrifugalCompressor"), "parts": .number(28)])
        }
        XCTAssertEqual(r.json["limit"], .object(["count": .number(180), "limit": .number(96), "top": .array(top), "field": .string("parts"),
                                                 "actual": .number(180), "unit": .string("parts")]))
        for _ in 0..<3 { XCTAssertEqual(MGSolidReport.check(data: Data(text.utf8), profile: .strict).json, r.json) }
        XCTAssertNotNil(MGSolidReasons.lookup("parts.resolved"))
        // Larger instances come first.
        let mixed = MGSolidReport.check(data: Data(compressors(["a", "b", "c", "d"], vanes: ["c": 12]).utf8))
        guard case .array(let list)? = mixed.json["limit"]?["top"] else { return XCTFail("top") }
        XCTAssertEqual(list.map { $0["id"] }, [.string("c"), .string("a"), .string("b"), .string("d"), .string("pilot")])
        XCTAssertEqual(list.first?["parts"], .number(38))
        XCTAssertEqual(mixed.json["limit"]?["count"], .number(12 + 38 + 3 * 28))
        // Another limit refusal gives its own detail, without `top`.
        XCTAssertNil(MGSolidReport.check(data: Data(#"{"v": 2, "kind": "assembly", "parts": []}"#.utf8)).json["limit"]?["top"])
    }

    /// Repeats alone over the limit: the count and the limit, no instance.
    func testPartsResolvedWithoutComponents() throws {
        let parts = (0..<9).map { #"{"id": "p\#($0)", "at": [\#($0 * 100), 0, 0], "repeat": {"count": 12, "axis": [0, 0, 1]}, "shape": {"box": {"size": [4, 4, 4], "at": [20, 0, 0]}}}"# }
        let r = MGSolidReport.check(data: Data(#"{"v": 2, "kind": "assembly", "parts": [\#(parts.joined(separator: ", "))]}"#.utf8))
        XCTAssertEqual(r.reason, "parts.resolved")
        XCTAssertEqual(r.json["limit"], .object(["count": .number(108), "limit": .number(96), "top": .array([]), "field": .string("parts"),
                                                 "actual": .number(108), "unit": .string("parts")]))
    }

    /// The explainer check report carries the same detail, and the refused document leaves the session unchanged.
    func testExplainerReportCarriesTheDetail() throws {
        let solid = compressors(["tLH", "tLF", "tRH", "tRF", "tB", "tX"]).replacingOccurrences(of: #""kind": "assembly", "#, with: "")
        let doc = XFix.doc(solid: solid, beats: #"[{"say":"Six stages."}]"#)
        let r = MGExplainerReport.check(data: Data(doc.utf8), profile: .strict)
        XCTAssertEqual(r.json["reason"], .string("parts.resolved"))
        XCTAssertEqual(r.json["limit"]?["count"], .number(180))
        XCTAssertEqual(r.json["limit"]?["limit"], .number(96))
        guard case .array(let top)? = r.json["limit"]?["top"] else { return XCTFail("top") }
        XCTAssertEqual(top.map { $0["id"] }, ["tB", "tLF", "tLH", "tRF", "tRH"].map { MGJSON.string($0) })
        // A stream that sends the solid statement: refused, nothing changes.
        var s = MGExplainerSession(pacing: .immediate, clock: MGManualClock())
        _ = s.feed(XFix.header() + "\n")
        let legend = s.legend
        let line = #"{"solid":\#(solid)}"# + "\n"
        let events = s.feed(line)
        XCTAssertTrue(events.contains { if case .refused(let i) = $0 { return i.reason == "parts.resolved" && i.limit?.count == 180 }; return false },
                      "\(events)")
        XCTAssertNil(s.solid)
        XCTAssertNil(s.presented.beat)
        XCTAssertEqual(s.legend, legend)
    }

    /// The expanded wire limit: authored `parts` keep 1–48 entries; expansion may reach 96 wire parts.
    func testExpandedWireLimit() throws {
        // 49 authored parts: refused as before.
        let many = (0..<49).map { #"{"id": "b\#($0)", "at": [\#($0 * 10), 0, 0], "shape": {"box": {"size": [4, 4, 4]}}}"# }
        XCTAssertEqual(MGSolidReport.check(data: Data(#"{"v": 2, "kind": "assembly", "parts": [\#(many.joined(separator: ", "))]}"#.utf8)).reason,
                       "parts.count")
        // 25 slider-cranks are 100 wire parts: over the expanded limit.
        let cranks = (1...25).map { #"{"id": "e\#($0)", "use": "sliderCrank", "at": [0, \#($0 * 100), 0]}"# }.joined(separator: ", ")
        XCTAssertEqual(MGSolidReport.check(data: Data(#"{"v": 2, "kind": "assembly", "parts": [\#(cranks)]}"#.utf8)).reason, "parts.count")
    }
}
