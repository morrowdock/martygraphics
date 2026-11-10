// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import MartyGraphics

/// Rule N1's declared names (docs/SOLID-3D.md, "Declared names"): a document may list `names`; a text token that exactly
/// equals one is not a typed number. Everything else with a number character stays under N1. A name may not be a
/// number or a number with a unit. One rule for solid and explainer documents.
final class DeclaredNamesTests: XCTestCase {
    static func asm(_ say: String, names: String? = nil, labels: String? = nil) -> String {
        let n = names.map { #", "names": \#($0)"# } ?? ""
        let l = labels.map { #", "annotations": {"labels": \#($0)}"# } ?? ""
        return #"{"v": 2, "kind": "assembly", "parts": [{"id": "b", "shape": {"box": {"size": [10, 10, 10]}}}], "steps": [{"say": "\#(say)"}]\#(n)\#(l)}"#
    }
    func compile(_ t: String) -> Result<MGSolidDocument, MGSolidIssue> { MGSolidParser.document(data: Data(t.utf8), profile: .strict) }
    func reason(_ t: String) -> String? { if case .failure(let e) = compile(t) { return e.reason }; return nil }

    /// Before: "the newer Mk4 differs" was `text.number.beat.1` (r2j). Declared, it passes; undeclared, it is still
    /// refused (no lexical exception).
    func testADeclaredNamePassesAndAnUndeclaredOneIsRefused() {
        XCTAssertNil(reason(Self.asm("The newer Mk4 differs.", names: #"["Mk4"]"#)))
        XCTAssertEqual(reason(Self.asm("The newer Mk4 differs.")), "text.number.step.1")
        XCTAssertNil(reason(Self.asm("The (Mk4) and the Mk4's case.", names: #"["Mk4"]"#)), "punctuation ends a token")
        XCTAssertEqual(reason(Self.asm("The Mk4s differ.", names: #"["Mk4"]"#)), "text.number.step.1", "whole token only")
        XCTAssertEqual(reason(Self.asm("The mk4 differs.", names: #"["Mk4"]"#)), "text.number.step.1", "case-sensitive")
        XCTAssertEqual(reason(Self.asm("The Mk4 has 4 engines.", names: #"["Mk4"]"#)), "text.number.step.1", "real numbers still count")
        XCTAssertEqual(reason(Self.asm("The Mk 4 differs.", names: #"["Mk4"]"#)), "text.number.step.1")
        XCTAssertNil(reason(Self.asm("An F-35 and an A320.", names: #"["F-35", "A320"]"#)))
        // Labels use the same list.
        XCTAssertNil(reason(Self.asm("Box.", names: #"["Mk4"]"#, labels: #"[{"id": "l", "at": "b", "text": "Mk4 box"}]"#)))
        XCTAssertEqual(reason(Self.asm("Box.", labels: #"[{"id": "l", "at": "b", "text": "Mk4 box"}]"#)), "text.number.label.l")
    }

    /// The review's quantities pass no more: undeclared they are typed numbers, and declared they are refused as names.
    func testQuantitiesAreNeverNames() {
        for q in ["Mach2", "USD120", "RPM120"] {
            XCTAssertEqual(reason(Self.asm("It runs at \(q).")), "text.number.step.1", q)
            XCTAssertEqual(reason(Self.asm("It runs at \(q).", names: #"["\#(q)"]"#)), "names.number.1", q)
        }
        for q in ["120RPM", "km-5", "4th", "x2", "2x", "120", "12-30", "m2", "kg5"] {
            XCTAssertEqual(reason(Self.asm("Box.", names: #"["Mk4", "\#(q)"]"#)), "names.number.2", q)
        }
        for ok in ["Mk4", "A320", "F-35", "P220", "B-52", "COVID-19", "V8", "M6", "CO2", "R2-D2"] {
            XCTAssertNil(reason(Self.asm("Box.", names: #"["\#(ok)"]"#)), ok)
        }
        // A caption with a quantity and a real placeholder makes no "Numbers solved" claim: it is refused.
        let mixed = #"{"v": 2, "kind": "assembly", "parts": [{"id": "rotor", "shape": {"box": {"size": [10, 10, 10]}}, "joint": {"revolute": [0, 0, 1]}, "drive": {"input": 1}}], "steps": [{"say": "It flies at Mach2; the rotor turns {rotor.speed} turns per input turn."}]}"#
        XCTAssertEqual(reason(mixed), "text.number.step.1")
    }

    /// The re-check's list (PR #49): numbers, numbers with a unit and quantities are refused as names (`names.number.1`)
    /// and model names are accepted, each in a solid caption and an explainer caption beside a real placeholder. An
    /// accepted name's caption is still a Solved claim; a refused one makes no claim at all.
    func testNamesBesideARealPlaceholder() throws {
        let refused = ["2e3", "1e-3", "1E3", "120N", "100W", "0x1F", "3D", "Mach2", "USD120", "RPM120"]
        let accepted = ["Mk4", "A320", "F-35", "P220"]
        func solid(_ name: String) -> String {
            #"{"v": 2, "kind": "assembly", "names": ["\#(name)"], "parts": [{"id": "rotor", "shape": {"box": {"size": [10, 10, 10]}}, "joint": {"revolute": [0, 0, 1]}, "drive": {"input": 1}}], "steps": [{"say": "The \#(name) rotor turns {rotor.speed} turns per input turn."}]}"#
        }
        func explainer(_ name: String) -> String {
            #"{"v": 1, "kind": "explainer", "names": ["\#(name)"], "solid": \#(XFix.gears), "beats": [{"say": "The \#(name) gear turns {p.speed} turns per input turn."}]}"#
        }
        for n in refused {
            XCTAssertEqual(reason(solid(n)), "names.number.1", "solid \(n)")
            XCTAssertEqual(XFix.refusal(explainer(n))?.reason, "names.number.1", "explainer \(n)")
        }
        for n in accepted {
            guard case .success(let d) = compile(solid(n)) else { return XCTFail("solid \(n): \(reason(solid(n)) ?? "")") }
            XCTAssertEqual(d.claims.first { $0.id == "step.1" }?.tier, .solved, "solid \(n)")
            XCTAssertNil(XFix.refusal(explainer(n)), "explainer \(n)")
            let s = try XFix.load(explainer(n))
            XCTAssertEqual(s.claims.first { $0.id == "beat.1" }?.tier, .solved, "explainer \(n)")
        }
        // A name with no number character needs no declaration: refused as `names.token.1`.
        XCTAssertEqual(reason(solid("Daedalus")), "names.token.1")
    }

    /// `set` and `add` on a board item use the declared names too (review: `set` did not pass them).
    func testBoardCommandsUseTheNames() {
        let board = #"{"v":1,"items":[{"id":"model","k":"text","at":[6,4],"text":"Model"}]}"#
        func doc(_ names: String?, op: String) -> String {
            let n = names.map { #", "names": \#($0)"# } ?? ""
            return #"{"v": 1, "kind": "explainer"\#(n), "board": \#(board), "beats": [{"say": "Model.", "ops": [\#(op)]}]}"#
        }
        let set = #"{"op":"set","id":"model","key":"text","value":"Mk4"}"#
        let add = #"{"op":"add","item":{"id":"m2","k":"text","at":[6,3],"text":"Mk4"}}"#
        XCTAssertNil(XFix.refusal(doc(#"["Mk4"]"#, op: set)))
        XCTAssertEqual(XFix.refusal(doc(nil, op: set))?.reason, "text.number.item.model")
        XCTAssertNil(XFix.refusal(doc(#"["Mk4"]"#, op: add)))
        XCTAssertEqual(XFix.refusal(doc(nil, op: add))?.reason, "text.number.item.m2")
        let setCell = #"{"op":"set","id":"model","key":"text","value":"Mk 4"}"#
        XCTAssertEqual(XFix.refusal(doc(#"["Mk4"]"#, op: setCell))?.reason, "text.number.item.model")
    }

    func testTheNamesList() {
        XCTAssertEqual(reason(Self.asm("Box.", names: #"[]"#)), "names.count")
        XCTAssertEqual(reason(Self.asm("Box.", names: #""Mk4""#)), "names.count")
        XCTAssertEqual(reason(Self.asm("Box.", names: #"[4]"#)), "names.count")
        XCTAssertEqual(reason(Self.asm("Box.", names: "[" + (0..<25).map { #""N\#($0)""# }.joined(separator: ",") + "]")), "names.count")
        XCTAssertEqual(reason(Self.asm("Box.", names: #"["Mk4", "Mk 5"]"#)), "names.token.2")
        XCTAssertEqual(reason(Self.asm("Box.", names: #"["Mk4."]"#)), "names.token.1")
        XCTAssertEqual(reason(Self.asm("Box.", names: #"["Daedalus"]"#)), "names.token.1", "no number character")
        XCTAssertEqual(reason(Self.asm("Box.", names: #"["\#(String(repeating: "A", count: 24))5"]"#)), "names.text.1")
        // v1 has no `names`.
        let v1 = #"{"v": 1, "kind": "assembly", "parts": [{"id": "b", "shape": {"box": {"size": [10, 10, 10]}}}], "names": ["Mk4"]}"#
        XCTAssertEqual(reason(v1), "assembly.unknown.names")
        guard case .success(let d) = compile(Self.asm("Box.", names: #"["Mk4", "Mk4", "A320"]"#)) else { return XCTFail("compile") }
        XCTAssertEqual(d.names, ["Mk4", "A320"], "repeats kept once")
    }

    /// Explainers: header `names` cover beat captions, 2D text and the solid's labels; quantities are refused.
    func testExplainers() throws {
        func doc(_ names: String?, say: String, label: String? = nil, board: String? = nil) -> String {
            let n = names.map { #", "names": \#($0)"# } ?? ""
            let l = label.map { #", "annotations": {"labels": [{"id": "l", "at": "p", "text": "\#($0)"}]}"# } ?? ""
            let solid = XFix.gears.replacingOccurrences(of: #"}]}"#, with: #"}]\#(l)}"#)
            let b = board.map { #", "board": \#($0)"# } ?? ""
            return #"{"v": 1, "kind": "explainer"\#(n), "solid": \#(solid)\#(b), "beats": [{"say": "\#(say)"}]}"#
        }
        XCTAssertNil(XFix.refusal(doc(#"["Mk4"]"#, say: "The newer Mk4 differs.")))
        XCTAssertEqual(XFix.refusal(doc(nil, say: "The newer Mk4 differs."))?.reason, "text.number.beat.1")
        XCTAssertEqual(XFix.refusal(doc(#"["Mach2"]"#, say: "It flies at Mach2."))?.reason, "names.number.1")
        XCTAssertNil(XFix.refusal(doc(#"["Mk4"]"#, say: "Gears.", label: "Mk4 gear")))
        XCTAssertNotNil(XFix.refusal(doc(nil, say: "Gears.", label: "Mk4 gear")))
        let table = #"{"v":1,"items":[{"id":"t","k":"table","at":[6,4],"header":true,"cells":[["Model","Layout"],["Mk4","arms, back"]]}]}"#
        XCTAssertNil(XFix.refusal(doc(#"["Mk4"]"#, say: "Gears.", board: table)))
        XCTAssertEqual(XFix.refusal(doc(nil, say: "Gears.", board: table))?.reason, "text.number.item.t")
        // The header round-trips through the statement stream.
        let parsed = try MGExplainer.parse(data: Data(doc(#"["Mk4"]"#, say: "The newer Mk4 differs.").utf8)).get()
        XCTAssertEqual(parsed.names, ["Mk4"])
        XCTAssertTrue(parsed.statementStream.contains(#""names":["Mk4"]"#))
    }

    /// The rule functions themselves.
    func testTokensAndQuantities() {
        XCTAssertFalse(MGExplainerHonesty.typedNumber("Mk4 suit", names: ["Mk4"]))
        XCTAssertTrue(MGExplainerHonesty.typedNumber("Mk4 suit", names: []))
        XCTAssertTrue(MGExplainerHonesty.typedNumber("Mk 4 suit", names: ["Mk4"]))
        XCTAssertFalse(MGExplainerHonesty.typedNumber("{x}Mk4", names: ["Mk4"]))
        XCTAssertTrue(MGExplainerHonesty.typedNumber("Mk4 {x} 4", names: ["Mk4"]))
        for q in ["Mach2", "USD120", "RPM120", "120", "4th", "x2", "kmh-90", "2e3", "1e-3", "1E3", "120N", "100W", "0x1F", "3D", "Ⅻ"] {
            XCTAssertTrue(MGSolidFacts.isQuantityName(q), q)
        }
        for n in ["Mk4", "A320", "F-35", "P220", "V8", "COVID-19", "MiG-29", "A380-800", "St4"] { XCTAssertFalse(MGSolidFacts.isQuantityName(n), n) }
        XCTAssertEqual(MGSolidFacts.numberLiterals(Array("1e-3")), [0..<1, 3..<4])
        XCTAssertEqual(MGSolidFacts.numberLiterals(Array("Ⅻ")), [0..<1])
    }
}
