// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import MartyGraphics

/// The golden readout cases (docs/fixtures/v1/readouts.cases.json) through the authoritative parser, and the scene
/// rules of `func` readouts: placeholders in every text, step edits, patches, descriptions, lessons and the evaluation
/// bounds. tools/tests/test_mg_expr.py checks the same file against the offline mirror (tools/mg_expr.py), so a
/// difference between the two shows up as a failure on one side.
final class ReadoutCaseTests: XCTestCase {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static func load(_ name: String) throws -> [String: Any] {
        let data = try Data(contentsOf: root.appendingPathComponent("docs/fixtures/v1/" + name))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// A closed form: a number within `tolerance` relative (absolute below 1), or "nan", "inf", "-inf" exactly.
    static func same(_ actual: Double, _ expected: Any?, tolerance: Double = 1e-12) -> Bool {
        if let s = expected as? String {
            switch s {
            case "nan": return actual.isNaN
            case "inf": return actual == .infinity
            case "-inf": return actual == -.infinity
            default: return false
            }
        }
        guard let e = (expected as? NSNumber)?.doubleValue else { return false }
        return actual.isFinite && Swift.abs(actual - e) <= tolerance * Swift.max(1, Swift.abs(e))
    }

    static func inputs(_ c: [String: Any]) -> MGExpression.Inputs {
        func v(_ k: String) -> Double { (c[k] as? NSNumber)?.doubleValue ?? 0 }
        return MGExpression.Inputs(x: v("x"), y: v("y"), t: v("t"), a: v("a"), b: v("b"), c: v("c"))
    }

    func scene(_ json: String) throws -> MGScene { try MGParser.scene(data: Data(json.utf8)).get() }

    func reason(_ json: String) -> String? {
        if case .failure(let e) = MGParser.scene(data: Data(json.utf8)) { return e.reason }
        return nil
    }

    // MARK: shared cases

    func testDerivativesMatchTheClosedForms() throws {
        let cases = try XCTUnwrap(Self.load("readouts.cases.json")["derivatives"] as? [[String: Any]])
        XCTAssertGreaterThan(cases.count, 35)
        for c in cases {
            let text = try XCTUnwrap(c["text"] as? String)
            let expr = try MGExpression.compile(text, allowed: Set(MGExpression.Variable.allCases), reason: "func.y")
            let inputs = Self.inputs(c)
            let (value, slope) = expr.valueAndSlope(inputs)
            XCTAssertTrue(Self.same(value, c["value"]), "\(text): value \(value)")
            XCTAssertTrue(Self.same(slope, c["slope"]), "\(text): slope \(slope)")
            let plain = expr.value(inputs)
            XCTAssertTrue(value == plain || (value.isNaN && plain.isNaN), "\(text): the same operations as value")
        }
    }

    func testTheDualValueIsThePlainValueForEveryExpressionCase() throws {
        let cases = try XCTUnwrap(Self.load("expressions.cases.json")["values"] as? [[String: Any]])
        for c in cases {
            let text = try XCTUnwrap(c["text"] as? String)
            let expr = try MGExpression.compile(text, allowed: Set(MGExpression.Variable.allCases), reason: "func.y")
            let value = expr.valueAndSlope(Self.inputs(c)).value, plain = expr.value(Self.inputs(c))
            XCTAssertTrue(value == plain || (value.isNaN && plain.isNaN), text)
        }
    }

    func testAcceptedItemsGiveTheClosedForms() throws {
        let cases = try XCTUnwrap(Self.load("readouts.cases.json")["accepted"] as? [[String: Any]])
        XCTAssertGreaterThan(cases.count, 15)
        for c in cases {
            let name = try XCTUnwrap(c["name"] as? String)
            let object = try XCTUnwrap(c["item"] as? [String: Any])
            let scene = try MGParser.scene(object: ["v": 1, "items": [object]] as [String: Any]).get()
            let item = try XCTUnwrap(scene.items.first, name)
            let expected = try XCTUnwrap(c["readouts"] as? [String: Any], name)
            let shown = try XCTUnwrap(c["shown"] as? [String: String], name)
            let tolerance = c["tolerance"] as? [String: Any] ?? [:]
            XCTAssertEqual(Set(MGReadout.requested(item).map(\.rawValue)), Set(expected.keys), name)
            for (key, closed) in expected {
                let r = try XCTUnwrap(MGReadout(rawValue: key), name)
                let got = try XCTUnwrap(item.num[r.key], "\(name) \(key)")
                let bound = (tolerance[key] as? NSNumber)?.doubleValue ?? 1e-12
                XCTAssertTrue(Self.same(got, closed, tolerance: bound), "\(name) \(key): \(got)")
                XCTAssertEqual(scene.values["f.\(key)"]?.value, got, name)
                XCTAssertEqual(scene.values["f.\(key)"]?.text, shown[key], "\(name) \(key)")
            }
            // The readouts survive the wire form (the numbers are derived again, never serialised).
            let ctx = MGContext(width: scene.width, height: scene.height, is3D: false, values: [:])
            XCTAssertEqual(try MGParser.item(.object(item.wire()), ctx), item, name)
            XCTAssertEqual(item.wire()["readouts"], .array(MGReadout.requested(item).map { .string($0.rawValue) }), name)
        }
    }

    func testRefusedScenesGiveTheGoldenReasons() throws {
        let cases = try XCTUnwrap(Self.load("readouts.cases.json")["refused"] as? [[String: Any]])
        XCTAssertGreaterThan(cases.count, 25)
        for c in cases {
            let name = try XCTUnwrap(c["name"] as? String)
            guard case .failure(let error) = MGParser.scene(object: try XCTUnwrap(c["scene"], name)) else { XCTFail("accepted: \(name)"); continue }
            XCTAssertEqual(error.reason, c["reason"] as? String, name)
        }
    }

    func testFilledTexts() throws {
        let cases = try XCTUnwrap(Self.load("readouts.cases.json")["filled"] as? [[String: Any]])
        XCTAssertGreaterThan(cases.count, 2)
        for c in cases {
            let name = try XCTUnwrap(c["name"] as? String)
            let scene = try MGParser.scene(object: try XCTUnwrap(c["scene"], name)).get()
            let texts = try XCTUnwrap(c["texts"] as? [String: String], name)
            for (path, expected) in texts {
                let parts = path.split(separator: ".").map(String.init)
                let got: String?
                switch parts[0] {
                case "title": got = scene.title
                case "alt": got = scene.alt
                case "steps":
                    let step = scene.steps[try XCTUnwrap(Int(parts[1]))]
                    got = parts[2] == "say" ? step.say : step.alt
                case "items":
                    let item = scene.item(parts[1])
                    got = parts[2] == "text" ? item?.text : item?.label
                default: got = nil
                }
                XCTAssertEqual(got, expected, "\(name): \(path)")
            }
        }
    }

    func testTheDocumentationSceneIsTheFirstFilledCase() throws {
        let data = try Data(contentsOf: Self.root.appendingPathComponent("docs/fixtures/v1/calculus.scene.json"))
        let filled = try XCTUnwrap(Self.load("readouts.cases.json")["filled"] as? [[String: Any]])
        let embedded = try MGParser.scene(object: try XCTUnwrap(filled.first?["scene"])).get()
        XCTAssertEqual(try MGParser.scene(data: data).get(), embedded)
        // An explainer environment without 3D facts fills the readouts the same way (explainer compatibility, B1).
        let json = try XCTUnwrap(MGJSON(any: try JSONSerialization.jsonObject(with: data)))
        XCTAssertEqual(try MGParser.scene(json: json, extraTemplates: [], env: MGParseEnvironment()).get(), embedded)
    }

    // MARK: scene rules

    static let sine = #"{"id":"f","k":"func","at":[1,1],"w":6,"h":4,"xr":[-3.2,3.2],"yr":[-2.5,2.5],"y":"a*sin(x)","a":1,"mark":1,"shade":[0,3.14159],"readouts":["slope","area"]}"#

    func testEveryTextCanNameAReadoutWhereverTheGraphIs() throws {
        let s = try scene(#"{"v":1,"title":"m = {f.slope}","alt":"area {f.area}","items":[{"id":"t","k":"text","at":[6,7],"text":"area {f.area}"},{"id":"b","k":"body","at":[2,2],"label":"m {f.slope}"},"# + Self.sine + #"],"steps":[{"say":"slope {f.slope}","alt":"A = {f.area}"}]}"#)
        XCTAssertEqual(s.title, "m = 0.54")
        XCTAssertEqual(s.alt, "area 2")
        XCTAssertEqual(s.item("t")?.text, "area 2")
        XCTAssertEqual(s.item("b")?.label, "m 0.54")
        XCTAssertEqual(s.steps.first?.say, "slope 0.54")
        XCTAssertEqual(s.steps.first?.alt, "A = 2")
        XCTAssertEqual(s.values["f.slope"]?.unit, "")
        XCTAssertEqual(Set(s.values.keys), ["f.slope", "f.area"])
    }

    func testAPatchComputesTheReadoutsAgainAndFillsTheTextAgain() throws {
        let s = try scene(#"{"v":1,"items":[{"id":"t","k":"text","at":[6,7],"text":"slope {f.slope}"},"# + Self.sine + #"]}"#)
        XCTAssertEqual(s.item("t")?.text, "slope 0.54")
        let taller = try MGPatch.parse(data: Data(#"{"v":1,"rev":0,"ops":[{"op":"set","id":"f","key":"a","value":2}]}"#.utf8)).get()
        let next = try s.applying(taller).get()
        XCTAssertEqual(next.item("t")?.text, "slope 1.08")
        XCTAssertEqual(try XCTUnwrap(next.values["f.slope"]?.value), 2 * cos(1), accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(next.values["f.area"]?.value), 2 * (1 - cos(3.14159)), accuracy: 1e-12)
        // A patch that breaks a readout is refused as a whole, and the scene before it stays.
        let corner = try MGPatch.parse(data: Data(#"{"v":1,"ops":[{"op":"set","id":"f","key":"y","value":"abs(x - 1)"}]}"#.utf8)).get()
        guard case .failure(let e) = s.applying(corner) else { return XCTFail("a corner at the mark must not apply") }
        XCTAssertEqual(e.reason, "func.readouts.slope")
    }

    func testAStepEditMayChangeEverythingButTheNumbers() throws {
        let edits = #"[{"id":"f","key":"color","value":"teal"},{"id":"f","key":"label","value":"m = {f.slope}"},{"id":"f","key":"yl","value":"y"}]"#
        let s = try scene(#"{"v":1,"items":["# + Self.sine + #"],"steps":[{"say":"one {f.slope}"},{"say":"two","do":"# + edits + #"}]}"#)
        let last = try XCTUnwrap(MGTimeline.items(s, step: 1).first)
        XCTAssertEqual(last.color, .teal)
        XCTAssertEqual(last.label, "m = 0.54")
        XCTAssertEqual(last.num[MGReadout.slope.key], s.values["f.slope"]?.value)
        XCTAssertEqual(reason(#"{"v":1,"items":["# + Self.sine + #"],"steps":[{"say":"one"},{"say":"two","do":[{"id":"f","key":"shade","value":[0,3]}]}]}"#), "func.readouts.edit")
        XCTAssertEqual(reason(#"{"v":1,"items":["# + Self.sine + #"],"steps":[{"say":"one"},{"say":"two","do":[{"id":"f","key":"a","value":2}]}]}"#), "func.readouts.edit")
    }

    func testTheDescriptionSpeaksTheReadouts() throws {
        let s = try scene(#"{"v":1,"items":["# + Self.sine + #"]}"#)
        let f = try XCTUnwrap(s.items.first)
        let phrase = MGDescribe.item(f, in: s.items)
        XCTAssertTrue(phrase.contains("shaded from x = 0 to 3.14 (signed area 2)"), phrase)
        XCTAssertTrue(phrase.contains("marking the point (1, 0.84) where the slope is 0.54"), phrase)
        // Without readouts the description is as before.
        let plain = try scene(#"{"v":1,"items":[{"id":"f","k":"func","at":[1,1],"w":6,"h":4,"xr":[-3.2,3.2],"yr":[-2.5,2.5],"y":"sin(x)","mark":1}]}"#)
        XCTAssertFalse(MGDescribe.item(plain.items[0], in: plain.items).contains("slope"))
    }

    func testLessonAndExplainerLinesCanNameAReadout() throws {
        let s = try scene(#"{"v":1,"items":["# + Self.sine + #"]}"#)
        XCTAssertEqual(try MGLessonSession.fillLine("The slope is {f.slope}.", s.values), "The slope is 0.54.")
        XCTAssertEqual(try MGLessonSession.fillLine("Area {f.area}.", s.values, env: MGParseEnvironment()), "Area 2.")
        // A dotted name that is not a readout still goes to the explainer's 3D facts, and a plain scene refuses it
        // with its old reason.
        XCTAssertThrowsError(try MGParser.fill("{f.teeth}", s.values, "say")) { XCTAssertEqual(($0 as? MGError)?.reason, "say.placeholder") }
        XCTAssertThrowsError(try MGParser.fill("{f.value}", s.values, "say")) { XCTAssertEqual(($0 as? MGError)?.reason, "say.placeholder.readout") }
    }

    func testTheGrammarDocumentListsTheReadouts() throws {
        let expression = try XCTUnwrap(MGGrammar.document()["expression"] as? [String: Any])
        XCTAssertEqual(expression["readouts"] as? [String], ["value", "slope", "area"])
        XCTAssertTrue(MGParser.allowedKeys(.function).contains("readouts"))
        XCTAssertFalse(MGParser.required(.function).contains("readouts"))
    }

    // MARK: methods and bounds

    func testTheEvaluationCountsAreTheDocumentedOnes() throws {
        var n = 0
        _ = try MGReadout.area({ n += 1; return $0 }, 0, 1, y0: -1, y1: 2)
        XCTAssertEqual(n, 962)
        XCTAssertEqual(MGLimits.readoutPanels, 128)
        XCTAssertEqual(MGLimits.readouts, MGReadout.allCases.count)
        n = 0
        _ = try MGReadout.fallbackSlope({ n += 1; return $0 * Swift.abs($0) }, at: 0, step: 1.0 / 4096)
        XCTAssertEqual(n, 7)
    }

    func testTheFallbackRunsOnlyWhereTheRuleHasNoValue() throws {
        let rule = try MGExpression.compile("x*abs(x)", allowed: [.x], reason: "func.y")
        XCTAssertTrue(rule.valueAndSlope(MGExpression.Inputs(x: 0)).slope.isNaN)
        XCTAssertEqual(rule.valueAndSlope(MGExpression.Inputs(x: 0.5)).slope, 1)
        XCTAssertEqual(try MGReadout.fallbackSlope({ $0 * Swift.abs($0) }, at: 0, step: 1.0 / 4096), 0)
        // A corner never passes, however small.
        for scale in [1.0, 1e-3, 1e-6] {
            XCTAssertThrowsError(try MGReadout.fallbackSlope({ scale * Swift.abs($0) }, at: 0, step: 1.0 / 4096), "\(scale)")
        }
    }

    func testTheAreaEstimateCoversTheRealErrorOfAnEndpointSingularity() throws {
        // sqrt(x) on [0, 4]: the rule converges slowly at the vertical tangent; its estimate is still above the error.
        var fine: [Double] = [], coarse: [Double] = []
        let f = { (x: Double) in x.squareRoot() }
        let a = MGReadout.gauss(f, 0, 4, panels: 128, values: &fine).sum, b = MGReadout.gauss(f, 0, 4, panels: 64, values: &coarse).sum
        XCTAssertGreaterThan(Swift.abs(a - b), Swift.abs(a - 16.0 / 3))
        XCTAssertLessThan(Swift.abs(a - b), MGReadout.resolution(a) / 2)
    }

    func testTheResolutionIsTheLastDigitTheEngineShows() {
        for (v, step, shown) in [(0.375, 0.01, "0.38"), (12.34, 0.1, "12.3"), (-150.4, 1.0, "-150"), (99.96, 0.1, "100")] {
            XCTAssertEqual(MGReadout.resolution(v), step, "\(v)")
            XCTAssertEqual(MGValue(value: v, unit: "").text, shown, "\(v)")
        }
    }
}
