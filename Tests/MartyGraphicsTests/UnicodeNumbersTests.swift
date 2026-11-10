// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import MartyGraphics

/// Rule N1 and the declared names read text in Unicode NFKC form (docs/SOLID-3D.md, "Declared names" and "Which
/// characters are numbers"): a full-width or other compatibility form is the plain form, so "Ｍａｃｈ２" is the
/// quantity "Mach2", and a compatibility symbol whose NFKC form holds a digit is a number. Names still match exactly
/// (case-sensitive, whole token) after the normalization.
final class UnicodeNumbersTests: XCTestCase {
    func reason(_ t: String) -> String? {
        if case .failure(let e) = MGSolidParser.document(data: Data(t.utf8), profile: .strict) { return e.reason }
        return nil
    }
    func asm(_ say: String, names: String? = nil) -> String { DeclaredNamesTests.asm(say, names: names) }

    /// The #49 re-check: a full-width quantity passed as a declared name. In NFKC form it is "Mach2": refused.
    func testFullWidthQuantitiesAreRefusedAsNames() {
        for q in ["Ｍａｃｈ２", "ＵＳＤ１２０", "ｒｐｍ１２０", "Mach２", "１２０"] {
            XCTAssertEqual(reason(asm("Box.", names: #"["\#(q)"]"#)), "names.number.1", q)
            let explainer = #"{"v": 1, "kind": "explainer", "names": ["\#(q)"], "solid": \#(XFix.gears), "beats": [{"say": "Gears."}]}"#
            XCTAssertEqual(XFix.refusal(explainer)?.reason, "names.number.1", "explainer \(q)")
        }
        // A full-width model name is still a name, kept in NFKC form, and repeats in either form are kept once.
        guard case .success(let d) = MGSolidParser.document(data: Data(asm("Box.", names: #"["Ａ３２０", "A320", "Ｍｋ４"]"#).utf8), profile: .strict)
        else { return XCTFail("compile") }
        XCTAssertEqual(d.names, ["A320", "Mk4"])
    }

    /// A declared name matches a caption token exactly after both are normalized: either form passes, and a different
    /// case or a longer token is still a typed number.
    func testNamesMatchExactlyAfterNormalization() {
        XCTAssertNil(reason(asm("The Ａ３２０ lands.", names: #"["A320"]"#)))
        XCTAssertNil(reason(asm("The A320 lands.", names: #"["Ａ３２０"]"#)))
        XCTAssertEqual(reason(asm("The ａ３２０ lands.", names: #"["A320"]"#)), "text.number.step.1", "case-sensitive after NFKC")
        XCTAssertEqual(reason(asm("The Ａ３２０ｓ land.", names: #"["A320"]"#)), "text.number.step.1", "whole token only")
        XCTAssertEqual(reason(asm("The A320 has ２ engines.", names: #"["A320"]"#)), "text.number.step.1", "real numbers still count")
        XCTAssertFalse(MGExplainerHonesty.typedNumber("Ｍｋ４ suit", names: ["Mk4"]))
        XCTAssertTrue(MGExplainerHonesty.typedNumber("ｍｋ４ suit", names: ["Mk4"]))
    }

    /// Which characters are numbers: every digit script, superscripts, subscripts, fractions, circled numbers, Roman and
    /// CJK numerals, and compatibility symbols whose NFKC form holds a digit. Each one in a caption is a typed number.
    func testEveryNumberFormIsATypedNumberInACaption() {
        let numbers: [(String, String)] = [
            ("２", "full-width digit"), ("٢", "Arabic-Indic digit"), ("۲", "Extended Arabic-Indic digit"), ("२", "Devanagari digit"),
            ("²", "superscript"), ("₂", "subscript"), ("½", "fraction"), ("②", "circled number"), ("⑵", "parenthesized number"),
            ("Ⅻ", "Roman numeral"), ("二", "CJK numeral"), ("𝟐", "mathematical bold digit"),
            ("㋀", "telegraph symbol for January (NFKC: 1月)"), ("㍘", "telegraph symbol for hour zero (NFKC: 0点)"),
        ]
        for (ch, what) in numbers {
            XCTAssertTrue(MGSolidFacts.isNumber(Character(ch)), what)
            XCTAssertEqual(reason(asm("It has \(ch) parts.")), "text.number.step.1", what)
            let explainer = #"{"v": 1, "kind": "explainer", "solid": \#(XFix.gears), "beats": [{"say": "It has \#(ch) parts."}]}"#
            XCTAssertEqual(XFix.refusal(explainer)?.reason, "text.number.beat.1", "explainer \(what)")
        }
        // Not numbers: letters (Latin, full-width, Greek) and a unit symbol whose NFKC form has no digit.
        for ch in ["A", "Ａ", "π", "㎏"] {
            XCTAssertFalse(MGSolidFacts.isNumber(Character(ch)), ch)
        }
        XCTAssertNil(reason(asm("A Ａ box, ㎏ for mass.")))
    }

    /// NFKC changes only what the rules read: the caption is shown as written.
    func testTheCaptionIsShownAsWritten() throws {
        let d = try MGSolidParser.document(data: Data(asm("The Ａ３２０ lands.", names: #"["A320"]"#).utf8), profile: .strict).get()
        XCTAssertEqual(d.steps[0].say, "The Ａ３２０ lands.")
    }
}
