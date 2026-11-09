// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import MartyGraphics

/// Rule N1's model-name tokens (docs/SOLID-3D.md, "Model names"): the digits of a name such as "Mk4", "A320" or "F-35"
/// are not a typed number; every real number still is. One token rule for solid text and explainer text.
final class ModelNameNumberTests: XCTestCase {
    static let names = ["Mk4", "A320", "F-35", "P220", "B-52", "COVID-19", "R2-D2", "MiG29", "CO2", "H2O", "iPhone15", "Mk4s", "T-50"]
    static let numbers = ["4", "4th", "3D", "10mm", "5-engine", "x2", "X2", "x10", "v2", "m2", "mm3", "Pre-2020", "Mk-4", "Su-27",
                          "MiG-29", "A380-800", "Mk½", "Mk４", "CO₂", "-4", "Mk4-", "Mk--4", "4Mk"]

    func testTheTokenRule() {
        for t in Self.names { XCTAssertTrue(MGSolidFacts.isModelName(t), t) }
        for t in Self.numbers { XCTAssertFalse(MGSolidFacts.isModelName(t), t) }
    }

    /// Before: "the newer Mk4 differs" was `text.number.beat.1` (r2j). Now a model name passes; numbers do not.
    func testExplainerCaptions() {
        XCTAssertNil(XFix.refusal(XFix.doc(solid: XFix.gears, beats: #"[{"say":"The newer Mk4 differs."}]"#)))
        for ok in ["An A320 or an F-35 flies.", "The P220, the (Mk4) and the Mk4's case.", "Mk4."] {
            XCTAssertNil(XFix.refusal(XFix.doc(solid: XFix.gears, beats: #"[{"say":"\#(ok)"}]"#)), ok)
        }
        for bad in ["It has 4 engines.", "The Mk 4 differs.", "The Mk4.5 differs.", "Pre-2020 suits.", "It is x2 faster.", "A 3D view.",
                    "The Mk-4 differs.", "Mk4 has 2 arms."] {
            XCTAssertEqual(XFix.refusal(XFix.doc(solid: XFix.gears, beats: #"[{"say":"\#(bad)"}]"#))?.reason, "text.number.beat.1", bad)
        }
    }

    /// The same rule in solid text (`MGSolidFacts.fill`): captions, labels and arrow text. A placeholder ends a token.
    func testSolidText() throws {
        XCTAssertEqual(try MGSolidFacts.fill("The Mk4 layout, F-35 style.", where: "step.1", n1: true, [:], [:]).text, "The Mk4 layout, F-35 style.")
        XCTAssertFalse(try MGSolidFacts.fill("The Mk4 layout.", where: "step.1", n1: false, [:], [:]).typedNumbers)
        for bad in ["The Mk 4 layout.", "4 engines.", "x2."] {
            XCTAssertThrowsError(try MGSolidFacts.fill(bad, where: "step.1", n1: true, [:], [:]), bad) { e in
                XCTAssertEqual((e as? MGSolidIssue)?.reason, "text.number.step.1")
            }
        }
        let facts = ["n": MGSolidFact(value: 4, unit: "", tier: .solved, source: "test")]
        XCTAssertThrowsError(try MGSolidFacts.fill("{n}4 parts.", where: "step.1", n1: true, facts, [:]))
        XCTAssertEqual(try MGSolidFacts.fill("Mk{n} parts.", where: "step.1", n1: true, facts, [:]).text, "Mk4 parts.")
        // A whole assembly: a caption with a model name compiles under strict.
        let t = #"{"v": 2, "kind": "assembly", "parts": [{"id": "b", "shape": {"box": {"size": [10, 10, 10]}}}], "steps": [{"say": "The Mk4 box."}]}"#
        guard case .success = MGSolidParser.document(data: Data(t.utf8), profile: .strict) else { return XCTFail("refused") }
    }

    /// 2D text and table cells use the same rule (`MGExplainerHonesty.typedNumber`).
    func testBoardText() {
        XCTAssertFalse(MGExplainerHonesty.typedNumber("Mk4 suit"))
        XCTAssertTrue(MGExplainerHonesty.typedNumber("Mk 4 suit"))
        XCTAssertFalse(MGExplainerHonesty.typedNumber("{x}Mk4"))
        XCTAssertTrue(MGExplainerHonesty.typedNumber("Mk4 {x} 4"))
        let cells = #"[["Model","Layout"],["Mk4","arms, back"]]"#
        XCTAssertNil(XFix.refusal(XFix.doc(board: XFix.table(cells: cells), beats: #"[{"say":"Hi."}]"#)))
    }
}
