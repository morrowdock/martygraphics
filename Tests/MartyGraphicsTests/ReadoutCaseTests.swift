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
        var n = 0, e = 0
        _ = try MGReadout.area({ n += 1; return $0 }, enclose: { e += 1; return ($0, $1) }, 0, 1, y0: -1, y1: 2)
        XCTAssertEqual(n, 962)
        XCTAssertEqual(e, 1)
        XCTAssertEqual(MGLimits.readoutPanels, 128)
        XCTAssertEqual(MGLimits.readouts, MGReadout.allCases.count)
        XCTAssertEqual(MGReadout.certifyDepth, 10)
        XCTAssertEqual(MGReadout.certifyBudget, 256)
    }

    func local(_ text: String, _ x: Double) throws -> MGExpression.Local {
        try MGExpression.compile(text, allowed: Set(MGExpression.Variable.allCases), reason: "func.y").local(MGExpression.Inputs(x: x))
    }

    func testTheOneSidedRules() throws {
        // Both sides of a smooth composition are the same number; a corner's are not, however small it is.
        XCTAssertEqual(try local("x*abs(x)", 0).left, 0)
        XCTAssertEqual(try local("x*abs(x)", 0).right, 0)
        XCTAssertEqual(try local("abs(x)", 0).left, -1)
        XCTAssertEqual(try local("abs(x)", 0).right, 1)
        XCTAssertEqual(try local("min(x, x^3)", 1).left, 3)
        XCTAssertEqual(try local("min(x, x^3)", 1).right, 1)
        for scale in ["1", "0.001", "0.000001", "0.0000000001"] {
            let l = try local(scale + "*abs(x)", 0)
            XCTAssertNotEqual(l.left, l.right, scale)
        }
        // A power's exponent is constant only when it does not read x, never because its derivative is 0 at a point.
        XCTAssertEqual(try local("(x - 1)^2", 0).left, -2)
        XCTAssertEqual(try local("(x - 1)^2", 0).right, -2)
        XCTAssertTrue(try local("(x - 1)^(2 + x^2)", 0).right.isNaN)
        // The sides of the kinks, poles and domain edges, in program order (x, 1, -, abs: the abs is at its kink).
        XCTAssertEqual(try local("abs(x - 1)", 1).sides, [0, 0, 0, 0])
        XCTAssertEqual(try local("abs(x - 1)", 1.5).sides, [0, 0, 0, 1])
        XCTAssertNil(try local("sqrt(x)^0", -1).sides)
    }

    func testTheViewCheckReadsEverySample() {
        // f leaves the y range only at the first node of the coarser rule: the band would be clipped there.
        let node = 1.0 / 128 + 1.0 / 128 * MGReadout.nodes[0]
        XCTAssertThrowsError(try MGReadout.area({ $0 == node ? 1 : 0 }, enclose: { _, _ in (0, 0) }, 0, 1, y0: -0.5, y1: 0.5)) {
            XCTAssertEqual(($0 as? MGError)?.reason, "func.readouts.view")
        }
    }

    func testTheCertificationIsBounded() {
        func run(_ enclose: @escaping (Double, Double) -> (lo: Double, hi: Double)?) -> (String?, Int) {
            var used = 0
            do {
                try MGReadout.certify({ used += 1; return enclose($0, $1) }, 0, 1, y0: -1, y1: 1)
            } catch {
                return ((error as? MGError)?.reason, used)
            }
            return (nil, used)
        }
        func check(_ got: (String?, Int), _ reason: String?, _ count: Int, line: UInt = #line) {
            XCTAssertEqual(got.0, reason, line: line)
            XCTAssertEqual(got.1, count, line: line)
        }
        // Depth first: a cell that never certifies is refused after `certifyDepth` halvings (11 enclosures).
        check(run { _, _ in nil }, "func.readouts.area", 11)
        check(run { _, _ in (5, 6) }, "func.readouts.view", 11)
        // Within the drawing tolerance (1 % of the y range) a cell is certified.
        check(run { _, _ in (-1.02, 1.02) }, nil, 1)
        check(run { _, _ in (-1.03, 1) }, "func.readouts.view", 11)
        // Cells of 1/512 and narrower certify: 1,023 cells would be needed, so the budget refuses it after 256.
        check(run { $1 - $0 <= 1.0 / 512 ? (0, 0) : nil }, "func.readouts.area", MGReadout.certifyBudget)
        check(run { $1 - $0 <= 1.0 / 64 ? (0, 0) : nil }, nil, 127)
    }

    func testEnclosuresHoldEveryValue() throws {
        let cases: [(String, Double, Double)] = [
            ("x^3 - 2*x", -2, 2.5), ("sin(x) + cos(3*x)", -4, 4), ("abs(x - 1)*exp(-x)", -1, 3), ("tan(x)", -1.5, 1.5),
            ("min(x, x^2) - max(x, 0.5)", -2, 2), ("(x + 3)^x", 0, 2), ("x^4 - x^2", -1.5, 1.5),
            ("sqrt(x) + ln(x + 1)", 0, 4), ("cosh(x) - 2", -2, 2),
        ]
        for (text, x0, x1) in cases {
            let expr = try MGExpression.compile(text, allowed: [.x], reason: "func.y")
            for k in 0..<16 {
                let a = x0 + (x1 - x0) * Double(k) / 16, b = x0 + (x1 - x0) * Double(k + 1) / 16
                let e = try XCTUnwrap(expr.enclosure(MGExpression.Inputs(), a, b), "\(text) \(k)")
                for j in 0...32 {
                    let v = expr.value(MGExpression.Inputs(x: a + (b - a) * Double(j) / 32))
                    XCTAssertTrue(v >= e.lo && v <= e.hi, "\(text) \(k): \(v) not in \(e)")
                }
            }
        }
        let pole = try MGExpression.compile("1/(x - 0.3)", allowed: [.x], reason: "func.y")
        XCTAssertNil(pole.enclosure(MGExpression.Inputs(), 0.25, 0.5))
        XCTAssertNotNil(pole.enclosure(MGExpression.Inputs(), 0.31, 0.5))
    }

    func testEnclosuresRoundOutward() throws {
        func enclosure(_ text: String, _ a: Double, _ b: Double) throws -> MGExpression.Bounds? {
            try MGExpression.compile(text, allowed: [.x], reason: "func.y").enclosure(MGExpression.Inputs(), a, b)
        }
        // In double precision (10^20 + x) - 10^20 is 0 for |x| < 8192. The enclosure still holds the analytic x, so the
        // divisor x + 1 below has no enclosure over [-2, 2]: it is 0 at -1.
        let cancel = try XCTUnwrap(try enclosure("(10^20 + x) - 10^20", -2, 2))
        XCTAssertLessThanOrEqual(cancel.lo, -2)
        XCTAssertGreaterThanOrEqual(cancel.hi, 2)
        XCTAssertNil(try enclosure("1/(((10^20+x)-10^20)+1)", -2, 2))
        // An inexact result is bounded by the doubles on either side of it: 0.1 + 0.2 and 3 × 0.1 are both exactly
        // 0.3000000000000000166…, between 0.3 and 0.30000000000000004.
        for text in ["x + 0.2", "3*x"] {
            let e = try XCTUnwrap(try enclosure(text, 0.1, 0.1), text)
            XCTAssertEqual(e.lo, 0.3, text)
            XCTAssertEqual(e.hi, 0.30000000000000004, text)
        }
        // An exact result stays exact, so a domain edge at an end of the interval is still inside the domain.
        let shifted = try XCTUnwrap(try enclosure("x - 1", 1, 2))
        XCTAssertEqual(shifted.lo, 0)
        XCTAssertEqual(shifted.hi, 1)
        let cap = try XCTUnwrap(try enclosure("1 - x^2", -1, 1))
        XCTAssertEqual(cap.lo, 0)
        XCTAssertEqual(cap.hi, 1)
        XCTAssertEqual(try XCTUnwrap(try enclosure("sqrt(1 - x^2)", -1, 1)).lo, 0)
        XCTAssertNotNil(try enclosure("asin(x/2)", -2, 2))
        // A library function widens by `libraryUlps` to each side.
        let v = exp(1.0), e = try XCTUnwrap(try enclosure("exp(x)", 1, 1))
        XCTAssertEqual(MGExpression.libraryUlps, 4)
        XCTAssertEqual(e.lo, v - 4 * v.ulp)
        XCTAssertEqual(e.hi, v + 4 * v.ulp)
        // Whole powers by repeated squaring: 0.1 × 0.1 is exactly 0.0100000000000000011102…, between 0.01 and
        // 0.010000000000000002.
        XCTAssertEqual(MGExpression.wholePower(3, 5, up: false), 243)
        XCTAssertEqual(MGExpression.wholePower(0.1, 2, up: false), 0.01)
        XCTAssertEqual(MGExpression.wholePower(0.1, 2, up: true), 0.010000000000000002)
    }

    func testPolesAndPeaksCountWhenTheyMayBeInside() {
        // tan's pole at 22.5π lies between these two adjacent doubles; the plain double-precision test misses it.
        let a = 70.68583470577035, b = 70.68583470577036
        XCTAssertEqual(a.nextUp, b)
        XCTAssertFalse(((a - .pi / 2) / .pi).rounded(.up) <= ((b - .pi / 2) / .pi).rounded(.down))
        XCTAssertTrue(MGExpression.mayHold(a, b, .pi / 2, period: .pi))
        XCTAssertNil(MGExpression.enclose(.tan, a, b))
        XCTAssertNotNil(MGExpression.enclose(.tan, 70, 70.6))
        XCTAssertFalse(MGExpression.mayHold(0, 1.5, .pi / 2, period: .pi))
    }

    func testTheSlopeCertifiesBothHalvesOfTheProbeInterval() throws {
        let probe = 4.0 / Double(MGLimits.funcIntervals) / 1024  // xr [-2, 2]
        let twice = try MGExpression.compile("abs((x-0.000003)*(x-0.000006))", allowed: [.x], reason: "func.y")
        // The abs argument is on the same side at the mark and at both probes, where the old three-point check looked…
        for x in [-probe, 0, probe] { XCTAssertEqual(twice.local(MGExpression.Inputs(x: x)).sides?.last, 1) }
        // …but crosses 0 twice in between: its enclosure over [0, probe] holds both signs.
        let left = try XCTUnwrap(twice.intervals(MGExpression.Inputs(), -probe, 0)).edges
        let right = try XCTUnwrap(twice.intervals(MGExpression.Inputs(), 0, probe)).edges
        XCTAssertEqual(MGExpression.strictSide(try XCTUnwrap(left.last ?? nil)), 1)
        XCTAssertEqual(MGExpression.strictSide(try XCTUnwrap(right.last ?? nil)), 0)
        // x*abs(x) at 0: the abs is at its kink at the mark and on one side of it over each half (x, x, abs, *).
        let corner = try MGExpression.compile("x*abs(x)", allowed: [.x], reason: "func.y")
        let edges = try XCTUnwrap(corner.intervals(MGExpression.Inputs(), 0, probe)).edges
        XCTAssertEqual(edges.map { $0 == nil }, [true, true, false, true])
        XCTAssertEqual(edges[2]?.lo, 0)
        XCTAssertEqual(edges[2]?.hi, probe)
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
