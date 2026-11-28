// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import MartyGraphics

/// Repair hints are suggestions keyed by the parser's reason tokens; they never change a reason.
final class MGRepairHintTests: XCTestCase {
    /// Refused synthetic scenes, one per common authoring mistake. Each reason must come with a hint.
    static let refused: [(String, String)] = [
        (#"{"items":[]}"#, "scene.missing"),
        (#"{"v":1,"items":[{"id":"a","k":"body"}]}"#, "item.body.missing"),
        (#"{"v":1,"items":[{"id":"a","k":"body","at":[1,1],"radius":2}]}"#, "item.body.unknown.radius"),
        (#"{"v":1,"items":[{"id":"a","k":"text","at":[1,1],"text":"x < 4"}]}"#, "text.text"),
        (#"{"v":1,"items":[{"id":"a","k":"text","at":[1,1],"text":"{n} apples"}]}"#, "text.text.placeholder.n"),
        (#"{"v":1,"items":[{"id":"a","k":"vector","from":[1,1],"on":"a","angle":0,"len":1}]}"#, "vector.anchor"),
        (#"{"v":1,"items":[{"id":"a","k":"vector","from":[1,1],"dir":[1,0,0],"len":1}]}"#, "vector.dir"),
        (#"{"v":1,"dim":"3d","items":[{"id":"a","k":"vector","from":[1,1,0],"dir":[0,0,0],"len":1}]}"#, "vector.dir"),
        (#"{"v":1,"items":[{"id":"p","k":"plot","at":[1,1],"w":6,"h":4,"xr":[2,2],"yr":[0,1],"pts":[[2,0],[2,1]]}]}"#, "plot.xr"),
        (#"{"v":1,"items":[{"id":"a","k":"incline","at":[1,1],"base":4,"angle":85}]}"#, "incline.angle"),
        (#"{"v":1,"items":[{"id":"a","k":"array","at":[6,4],"vals":[1,2],"ptrs":[{"i":1,"label":"top"}]}],"steps":[{"say":"Pop.","do":[{"id":"a","key":"vals","value":[1]}]}]}"#, "array.ptr.i"),
        (#"{"v":1,"items":[{"id":"a","k":"body","at":[1,1]}],"steps":[{"say":"x","do":[{"id":"a","key":"radius","value":1}]}]}"#, "edit.key.radius"),
        (#"{"v":1,"items":[{"id":"a","k":"body","at":[1,1]}],"steps":[{"say":"a > b"}]}"#, "step.say"),
        (#"{"v":1,"template":"two_pointers","params":{"vals":[3,1,2],"target":4}}"#, "template.check"),
        (#"{"v":1,"items":[{"id":"g","k":"func","at":[1,1],"w":6,"h":4,"xr":[0,6],"yr":[-2,2],"y":"2x"}]}"#, "func.y.syntax"),
        (#"{"v":1,"items":[{"id":"g","k":"func","at":[1,1],"w":6,"h":4,"xr":[0,6],"yr":[-2,2],"y":"sin(x - t)"}]}"#, "func.y.var.t"),
        (#"{"v":1,"items":[{"id":"f","k":"field","at":[1,1],"w":6,"h":4,"xr":[-2,2],"yr":[-2,2],"dx":"-y","dy":"x","style":"dots"}]}"#, "field.style"),
        (#"{"v":1,"items":[{"id":"g","k":"func","at":[1,1],"w":6,"h":4,"xr":[0,6],"yr":[-2,2],"y":"sin(x)","readouts":["slope"]}]}"#, "func.readouts.mark"),
        (#"{"v":1,"items":[{"id":"g","k":"func","at":[1,1],"w":6,"h":4,"xr":[0,6],"yr":[-2,2],"y":"sin(x)"},{"id":"t","k":"text","at":[8,6],"text":"{g.slope}"}]}"#, "text.text.placeholder.readout"),
    ]

    func testEveryCommonMistakeGetsAHint() throws {
        for (json, expected) in Self.refused {
            guard case .failure(let error) = MGParser.scene(data: Data(json.utf8)) else { return XCTFail("accepted \(json)") }
            XCTAssertEqual(error.reason, expected, json)
            XCTAssertNotNil(MGRepairHint.text(for: error.reason), error.reason)
        }
    }

    /// Invalid template motion has its own hint with the parser's motion bounds, not the general template parameter hint.
    func testInvalidTemplateMotionGetsTheMotionHint() throws {
        let data = Data(#"{"v":1,"template":"motion","params":{}}"#.utf8)
        let bad: [MGMotion] = [
            .slide([.init(id: "dot", dir: MGPoint(1, 0), accel: 1)], travel: 0.1, hold: 0),
            .orbit(id: "dot", center: MGPoint(2, 4), period: 11, rotating: []),
            .projectile(id: "dot", vx: 1, vy0: 2, g: 2, flight: 0, visual: 2, hold: 0,
                        vxVector: nil, vyVector: nil, vectorScale: 1),
            .oscillate(id: "dot", amplitude: .infinity, period: 2, energy: 2, bars: nil, vector: nil, vectorLength: 1)
        ]
        for motion in bad {
            let template = MGTemplate(name: "motion", summary: "Motion", params: []) { _, _ in
                MGTemplateBuild(title: "Motion", items: [MGMake.body("dot", MGPoint(3, 4))], motion: motion)
            }
            guard case .failure(let error) = MGParser.scene(data: data, extraTemplates: [template]) else {
                return XCTFail("accepted \(motion)")
            }
            XCTAssertEqual(error.reason, "template.motion")
        }
        let hint = try XCTUnwrap(MGRepairHint.text(for: "template.motion"))
        XCTAssertEqual(hint, "the template built invalid motion; fix the template: slide travel, orbit and oscillate period "
                       + "and projectile visual are 0.3 to 10 seconds, hold is 0 to 10 seconds, projectile flight is above 0, "
                       + "and every other motion number is finite")
        XCTAssertNotEqual(hint, MGRepairHint.text(for: "template.values"))
    }

    func testComputedAndPatternHints() {
        XCTAssertEqual(MGRepairHint.text(for: "item.body.missing"), "a body needs at, id, k")
        XCTAssertEqual(MGRepairHint.text(for: "item.edge.unknown.c"),
                       "remove unknown keys; a edge allows a, b, color, dir, id, k, label")
        XCTAssertEqual(MGRepairHint.text(for: "id.duplicate.dot"), "item ids must be unique; rename one of the two")
        XCTAssertEqual(MGRepairHint.text(for: "body.at"), MGRepairHint.text(for: "line.to"))
        XCTAssertNil(MGRepairHint.text(for: "not.a.reason"))
        XCTAssertTrue(MGRepairHint.matches("item.*.unknown.*", "item.body.unknown.a,b"))
        XCTAssertFalse(MGRepairHint.matches("*.at", "body.atx"))
        XCTAssertFalse(MGRepairHint.matches("items", "items.count"))
    }

    /// Slider reasons (MGSliders.swift) get the slider rows, which sit before the generic rows that would also match.
    func testSliderReasonsGetTheSliderHints() throws {
        let line = #"{"id":"f","k":"func","at":[1,1],"w":10,"h":6,"xr":[-3,3],"yr":[-4,4],"y":"a*x","a":1}"#
        let refused: [(String, String)] = [
            (#"{"param":"a","min":0,"max":3,"step":0.5,"default":1,"label":"a = {a}"}"#, "slider.label.placeholder"),
            (#"{"param":"a","min":0,"max":3,"step":0.5,"default":1,"label":"a < b"}"#, "slider.label"),
            (#"{"param":"a","min":0,"max":3,"step":0.01,"default":1,"label":"a"}"#, "slider.step.count"),
            (#"{"param":"a","min":0,"max":3,"step":0.4,"default":1,"label":"a"}"#, "slider.step"),
            (#"{"param":"a","min":0,"max":3,"step":0.5,"default":1.25,"label":"a"}"#, "slider.default"),
            (#"{"param":"b","min":0,"max":3,"step":0.5,"default":1,"label":"b"}"#, "slider.unbound"),
        ]
        func row(_ pattern: String) -> String? { MGRepairHint.table.first { $0.0 == pattern }?.1 }
        for (slider, expected) in refused {
            let json = #"{"v":1,"items":["# + line + #"],"sliders":["# + slider + "]}"
            guard case .failure(let error) = MGParser.scene(data: Data(json.utf8)) else { XCTFail("accepted \(json)"); continue }
            XCTAssertEqual(error.reason, expected, json)
            XCTAssertEqual(MGRepairHint.text(for: error.reason), row(expected), json)
        }
        XCTAssertNotEqual(MGRepairHint.text(for: "slider.label.placeholder"), row("*.placeholder"))
        XCTAssertEqual(MGRepairHint.text(for: "slider.a.min.func.at"), row("slider.*.min.*"))
        XCTAssertNotEqual(MGRepairHint.text(for: "slider.a.min.func.at"), row("*.at"))
        XCTAssertEqual(MGRepairHint.text(for: "slider.c.max.func.w"), row("slider.*.max.*"))
        XCTAssertEqual(MGRepairHint.text(for: "slider.unknown.unit"), row("slider.unknown.*"))
        XCTAssertNil(MGRepairHint.text(for: "sliders.count"))
        XCTAssertTrue(MGRepairHint.text(for: "scene.unknown.zz")?.contains("alt, sliders,") ?? false)
        XCTAssertTrue(MGParser.topKeys.contains("sliders"))
    }
}

/// The shared corpus (docs/fixtures/repair-hints/corpus.json) holds the exact hint for every scene reason sample,
/// every kind's computed missing/unknown hint, pattern-precedence cases and reasons with no hint. The Python mirror
/// asserts the same file (tools/tests/test_repair_hints.py), so the two implementations are compared by output.
final class RepairHintCorpusTests: XCTestCase {
    func testSceneHintsMatchTheSharedCorpus() throws {
        let url = XFix.root.appendingPathComponent("docs/fixtures/repair-hints/corpus.json")
        let corpus = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let scene = try XCTUnwrap(corpus["scene"] as? [[String: Any]])
        XCTAssertEqual(scene.count, 327)
        for entry in scene {
            let reason = try XCTUnwrap(entry["reason"] as? String)
            XCTAssertEqual(MGRepairHint.text(for: reason), entry["hint"] as? String, reason)
        }
    }
}
