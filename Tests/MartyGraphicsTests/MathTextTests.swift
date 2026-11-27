// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import MartyGraphics

/// Math text (`MGMathText`, text style `math`): the golden spoken forms and refusals shared with the offline mirror
/// (docs/fixtures/v1/math.cases.json, tools/tests/test_mg_math.py), the bounds, the scene rules, the spoken form in
/// `MGDescribe`, and the typeset layout (with a fixed-width measure, so it runs without fonts).
final class MathTextTests: XCTestCase {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static func cases() throws -> [String: Any] {
        let data = try Data(contentsOf: root.appendingPathComponent("docs/fixtures/v1/math.cases.json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func reason(_ text: String) -> String? {
        do { _ = try MGMathText.parse(text); return nil } catch let e as MGError { return e.reason } catch { return "unexpected" }
    }

    func scene(_ items: String, extra: String = "") -> Result<MGScene, MGError> {
        MGParser.scene(data: Data(#"{"v":1\#(extra),"items":[\#(items)]}"#.utf8))
    }

    func sceneReason(_ items: String, extra: String = "") -> String? {
        if case .failure(let e) = scene(items, extra: extra) { return e.reason }
        return nil
    }

    static func math(_ text: String) -> String {
        let escaped = String(data: try! JSONSerialization.data(withJSONObject: [text]), encoding: .utf8)!.dropFirst().dropLast()
        return #"{"id":"eq","k":"text","at":[6,4],"style":"math","text":\#(escaped)}"#
    }

    // MARK: golden cases

    func testGoldenSpokenForms() throws {
        let spoken = try XCTUnwrap(Self.cases()["spoken"] as? [[String: String]])
        XCTAssertGreaterThanOrEqual(spoken.count, 40)
        for c in spoken {
            let text = try XCTUnwrap(c["text"]), expected = try XCTUnwrap(c["spoken"])
            XCTAssertEqual(try MGMathText.parse(text).spoken, expected, text)
            XCTAssertEqual(MGMathText.spoken(text), expected, text)
        }
    }

    func testGoldenRefusals() throws {
        let refusals = try XCTUnwrap(Self.cases()["refusals"] as? [[String: String]])
        XCTAssertGreaterThanOrEqual(refusals.count, 30)
        for c in refusals {
            let text = try XCTUnwrap(c["text"])
            XCTAssertEqual(reason(text), c["reason"], text)
            XCTAssertNil(MGMathText.spoken(text), text)
        }
        XCTAssertEqual(Set(refusals.compactMap { $0["reason"] }),
                       ["text.math", "text.math.syntax", "text.math.tokens", "text.math.depth", "text.math.name", "text.math.unit"])
    }

    // MARK: limits

    func testLimitsAreTheDocumentedOnes() {
        XCTAssertEqual(MGLimits.mathLength, 80)
        XCTAssertEqual(MGLimits.mathTokens, 48)
        XCTAssertEqual(MGLimits.mathDepth, 4)
    }

    func testLengthBound() {
        let exact = String(repeating: "1 + ", count: 19) + "1234"   // 80 scalars, 39 tokens
        XCTAssertEqual(exact.unicodeScalars.count, 80)
        XCTAssertNil(reason(exact))
        XCTAssertEqual(reason(exact + "5"), "text.math", "81 scalars")
        // Unicode scalars: a Greek letter is one, and spaces count.
        let greek = "θ" + String(repeating: " ", count: 79)
        XCTAssertNil(reason(greek))
        XCTAssertEqual(reason(greek + " "), "text.math")
    }

    func testTokenBound() {
        let exact = String(repeating: "x+", count: 23) + "2 x"
        XCTAssertNil(reason(exact))
        XCTAssertEqual(reason(String(repeating: "x+", count: 24) + "x"), "text.math.tokens")
        // `+-` is one token (±).
        XCTAssertNil(reason(String(repeating: "x+-", count: 23) + "2 x"))
    }

    func testDepthBound() {
        XCTAssertNil(reason("((((x))))"))
        XCTAssertEqual(reason("(((((x)))))"), "text.math.depth")
        XCTAssertNil(reason("a/(b/(c/(d/e)))"))
        XCTAssertEqual(reason("a/(b/(c/(d/(e/f))))"), "text.math.depth")
        XCTAssertNil(reason("x^(y^(z^(w^v)))"))
        XCTAssertEqual(reason("x^(y^(z^(w^(v^u))))"), "text.math.depth")
        XCTAssertNil(reason("sqrt(sqrt(sqrt(sqrt(x))))"))
        XCTAssertEqual(reason("sqrt(sqrt(sqrt(sqrt(x^2))))"), "text.math.depth")
        // Parentheses around a fraction's part or a script are grouping only: they do not add a level.
        let tree = try? MGMathText.parse("(a + b)/(c + d)")
        XCTAssertEqual(tree.map { MGMathText.depth($0.root) }, 1)
    }

    func testRefusalOrder() {
        XCTAssertEqual(reason("ma + 1."), "text.math.syntax", "numbers are read before names")
        XCTAssertEqual(reason(String(repeating: "ma+", count: 25) + "ma"), "text.math.tokens", "tokens before names")
        XCTAssertEqual(reason("ma + (((((x)))))"), "text.math.depth", "parentheses before names")
        XCTAssertEqual(reason("ma + [kgs]"), "text.math.name", "left to right")
        XCTAssertEqual(reason("[kgs] + ma"), "text.math.unit", "left to right")
        XCTAssertEqual(reason("x {v} ma"), "text.math", "the alphabet first")
    }

    // MARK: scenes

    func testSceneAcceptsMathStyleAndRoundTrips() throws {
        let parsed = try scene(Self.math("  y = a sin x\n")).get()
        let item = try XCTUnwrap(parsed.item("eq"))
        XCTAssertTrue(item.has("math"))
        XCTAssertEqual(item.text, "y = a sin x")
        XCTAssertEqual(item.color, .muted)
        let wire = item.wire()
        XCTAssertEqual(wire["style"], .string("math"))
        XCTAssertEqual(wire["text"], .string("y = a sin x"))
        XCTAssertEqual(try MGParser.item(.object(wire), MGContext(width: 12, height: 8, is3D: false, values: [:])), item)
    }

    func testSceneRefusals() {
        XCTAssertEqual(sceneReason(Self.math("ma")), "text.math.name")
        XCTAssertEqual(sceneReason(Self.math("[kgs]")), "text.math.unit")
        XCTAssertEqual(sceneReason(Self.math("x^")), "text.math.syntax")
        // The plain-text rules run first, as for every style.
        XCTAssertEqual(sceneReason(Self.math("x < 1")), "text.text")
        XCTAssertEqual(sceneReason(Self.math("x = {v}")), "text.text.placeholder.v")
        XCTAssertEqual(sceneReason(Self.math("x\ny")), "text.math", "a line feed is plain text but not math")
        XCTAssertEqual(sceneReason(Self.math("x^2"), extra: #","dim":"3d""#), "3d.text.math")
        XCTAssertEqual(sceneReason(#"{"id":"eq","k":"text","at":[6,4],"style":"maths","text":"x"}"#), "text.style")
    }

    func testStepEditsAreCheckedAsMath() {
        let steps = #","steps":[{"say":"Square it.","do":[{"id":"eq","key":"text","value":"x^2"}]}]"#
        XCTAssertNil(sceneReason(Self.math("x"), extra: steps))
        let bad = #","steps":[{"say":"Square it.","do":[{"id":"eq","key":"text","value":"xx"}]}]"#
        XCTAssertEqual(sceneReason(Self.math("x"), extra: bad), "text.math.name")
        let restyle = #","steps":[{"say":"Now as math.","do":[{"id":"t","key":"style","value":"math"}]}]"#
        XCTAssertEqual(sceneReason(#"{"id":"t","k":"text","at":[6,4],"text":"speed"}"#, extra: restyle), "text.math.name")
    }

    func testTextWithoutMathStyleIsUnchanged() throws {
        // Markup characters stay plain text in the other styles: nothing is parsed or spoken differently.
        let parsed = try scene(#"{"id":"t","k":"text","at":[6,4],"text":"x^2 + 2 x"}"#).get()
        XCTAssertFalse(try XCTUnwrap(parsed.item("t")).has("math"))
        XCTAssertEqual(MGDescribe.board(parsed), "The text “x^2 + 2 x”.")
    }

    func testDescribeAndVoiceOverReadTheSpokenForm() throws {
        let parsed = try scene(Self.math("x^2 + 2 x") + "," + #"{"id":"t","k":"text","at":[2,2],"text":"Area"}"#).get()
        XCTAssertEqual(MGDescribe.board(parsed), "The formula “x squared plus 2 x”; the text “Area”.")
        XCTAssertEqual(MGDescribe.accessibilityValue(parsed, step: 0, describing: true),
                       "The formula “x squared plus 2 x”; the text “Area”.")
        // An item built in code that bypasses the parser falls back to its text.
        var raw = MGItem(id: "r", kind: .text, color: .white)
        raw.text = "x^"; raw.flags.insert("math")
        XCTAssertEqual(MGDescribe.item(raw, in: [raw]), "the text “x^”")
    }

    func testGrammarDocumentListsTheVocabulary() throws {
        let math = try XCTUnwrap(MGGrammar.document()["math"] as? [String: Any])
        XCTAssertEqual(math["maxLength"] as? Int, 80)
        XCTAssertEqual(math["maxTokens"] as? Int, 48)
        XCTAssertEqual(math["maxDepth"] as? Int, 4)
        XCTAssertEqual((math["greek"] as? [String])?.count, 34)
        XCTAssertEqual((math["units"] as? [String])?.count, 38)
        XCTAssertEqual(math["functions"] as? [String], MGExpression.Function.allCases.map(\.rawValue))
        XCTAssertEqual(math["constants"] as? [String], ["inf"])
        XCTAssertTrue((math["greek"] as? [String] ?? []).allSatisfy { $0.unicodeScalars.allSatisfy(\.isASCII) })
    }

    // MARK: layout

    /// A fixed-width face: half the size per scalar.
    static func measure(_ text: String, _ size: Double, _ italic: Bool) -> Double { Double(text.unicodeScalars.count) * size * 0.5 }

    func layout(_ text: String, size: Double = 20) throws -> MGMathLayout {
        try MGMathText.parse(text).layout(size: size, measure: Self.measure)
    }

    func run(_ l: MGMathLayout, _ text: String) throws -> MGMathLayout.Run {
        try XCTUnwrap(l.runs.first { $0.text == text }, "no run \(text) in \(l.runs.map(\.text))")
    }

    func testSuperscriptIsSmallerAndRaised() throws {
        let l = try layout("x^2")
        let x = try run(l, "x"), two = try run(l, "2")
        XCTAssertTrue(x.italic); XCTAssertFalse(two.italic)
        XCTAssertEqual(x.size, 20); XCTAssertEqual(two.size, 14, accuracy: 1e-9)
        XCTAssertEqual(x.y, 0); XCTAssertLessThan(two.y, -5)
        XCTAssertGreaterThan(two.x, x.x + 9)
        XCTAssertTrue(l.strokes.isEmpty)
    }

    func testSubscriptIsLowered() throws {
        let l = try layout("x_1")
        XCTAssertGreaterThan(try run(l, "1").y, 2)
        let both = try layout("x_1^2")
        XCTAssertGreaterThan(try run(both, "1").y, try run(l, "1").y - 1e-9)
        XCTAssertLessThan(try run(both, "2").y, 0)
        XCTAssertEqual(try run(both, "1").x, try run(both, "2").x, accuracy: 1e-9)
    }

    func testFractionHasABarBetweenCentredParts() throws {
        let l = try layout("1/2")
        XCTAssertEqual(l.strokes.count, 1)
        let bar = try XCTUnwrap(l.strokes.first)
        XCTAssertEqual(bar.points.count, 2)
        XCTAssertEqual(bar.points[0].y, bar.points[1].y)
        let top = try run(l, "1"), bottom = try run(l, "2")
        XCTAssertLessThan(top.y, bar.points[0].y)
        XCTAssertGreaterThan(bottom.y, bar.points[0].y)
        XCTAssertEqual(top.x, bottom.x, accuracy: 1e-9)
        XCTAssertEqual(top.size, 17, accuracy: 1e-9)
        // Grouping parentheses around the parts are not drawn.
        XCTAssertFalse(try layout("(x + 1)/2").runs.contains { $0.text == "(" || $0.text == ")" })
    }

    func testRootAndAbsoluteValueAreStrokes() throws {
        let root = try layout("sqrt(x)")
        XCTAssertEqual(root.strokes.count, 1)
        let sign = try XCTUnwrap(root.strokes.first).points
        XCTAssertEqual(sign.count, 5)
        let x = try run(root, "x")
        XCTAssertGreaterThan(x.x, sign[3].x)
        XCTAssertLessThan(sign[3].y, x.y - 0.72 * 20, "the bar is above the radicand")
        XCTAssertGreaterThanOrEqual(sign[4].x, x.x + Self.measure("x", 20, true))
        XCTAssertEqual(try layout("abs(x)").strokes.count, 2)
    }

    func testTallParenthesesAreDrawn() throws {
        XCTAssertEqual(try layout("(x + 1)").strokes.count, 0)
        XCTAssertEqual(try layout("(x + 1)").runs.filter { $0.text == "(" || $0.text == ")" }.count, 2)
        let tall = try layout("(1/2)^2")
        XCTAssertEqual(tall.strokes.count, 3, "parentheses around a script's base stay: a bar and two tall parentheses")
        let around = try layout("2 (1/x)")
        XCTAssertEqual(around.strokes.count, 3, "a fraction bar and two tall parentheses")
    }

    func testGlyphsAndFaces() throws {
        XCTAssertTrue(try run(try layout("theta"), "θ").italic)
        XCTAssertFalse(try run(try layout("Delta x"), "Δ").italic)
        XCTAssertFalse(try run(try layout("sin x"), "sin").italic)
        XCTAssertNoThrow(try run(try layout("x - 1"), "−"))
        XCTAssertNoThrow(try run(try layout("a · b"), "·"))
        XCTAssertNoThrow(try run(try layout("a * b"), "·"))
        XCTAssertNoThrow(try run(try layout("a +- b"), "±"))
        XCTAssertNoThrow(try run(try layout("x = inf"), "∞"))
        XCTAssertNoThrow(try run(try layout("30°"), "30°"))
        XCTAssertNoThrow(try run(try layout("asin(x)"), "arcsin"))
        let units = try layout("9.8 [m/s^2]")
        XCTAssertEqual(units.runs.map(\.text), ["9.8", "m", "/", "s", "2"])
        XCTAssertFalse(try run(units, "m").italic)
        XCTAssertLessThan(try run(units, "2").y, 0)
        XCTAssertEqual(try layout("[J/(kg K)]").runs.map(\.text), ["J", "/", "(", "kg", "·", "K", ")"])
        XCTAssertEqual(try layout("[ohm]").runs.map(\.text), ["Ω"])
    }

    func testScriptsShrinkToHalfTheBaseSize() throws {
        let l = try layout("x^(y^(z^w))")
        XCTAssertEqual(try run(l, "y").size, 14, accuracy: 1e-9)
        XCTAssertEqual(try run(l, "z").size, 10, accuracy: 1e-9)
        XCTAssertEqual(try run(l, "w").size, 10, accuracy: 1e-9)
    }

    func testLayoutIsDeterministicAndBoundsEveryRun() throws {
        let spoken = try XCTUnwrap(Self.cases()["spoken"] as? [[String: String]])
        for c in spoken {
            let text = try XCTUnwrap(c["text"])
            let a = try layout(text), b = try layout(text)
            XCTAssertEqual(a, b, text)
            XCTAssertGreaterThan(a.width, 0, text)
            for r in a.runs {
                XCTAssertGreaterThanOrEqual(r.x, -1e-9, text)
                XCTAssertLessThanOrEqual(r.x + Self.measure(r.text, r.size, r.italic), a.width + 1e-9, text)
                XCTAssertGreaterThanOrEqual(r.y - MGMathText.ascentRatio * r.size, -a.ascent - 1e-9, text)
                XCTAssertLessThanOrEqual(r.y + MGMathText.descentRatio * r.size, a.descent + 1e-9, text)
            }
            for s in a.strokes {
                for p in s.points {
                    XCTAssertTrue(p.x >= -1e-9 && p.x <= a.width + 1e-9, text)
                    XCTAssertTrue(p.y >= -a.ascent - 1e-9 && p.y <= a.descent + 1e-9, text)
                }
            }
        }
    }

    func testBoardBoundsUseTheTypesetBox() throws {
        let parsed = try scene(Self.math("1/2 m v^2") + "," + #"{"id":"t","k":"text","at":[3,3],"text":"1/2 m v^2"}"#).get()
        let vp = MGViewport(size: CGSize(width: 1280, height: 720), width: 12, height: 8, camera: nil)
        let math = try XCTUnwrap(parsed.item("eq")), plain = try XCTUnwrap(parsed.item("t"))
        let box = try XCTUnwrap(MGLayout.bounds(math, in: parsed.items, vp))
        let centre = vp.point(math.pts[0])
        XCTAssertEqual(box.midX, centre.x, accuracy: 1e-6)
        XCTAssertEqual(box.midY, centre.y, accuracy: 1e-6)
        // The stacked fraction makes the box taller than a line of plain text, and the markup is not measured as text.
        let line = try XCTUnwrap(MGLayout.bounds(plain, in: parsed.items, vp))
        XCTAssertGreaterThan(box.height, line.height)
        XCTAssertLessThan(box.width, line.width)
        let m = try MGMathText.parse("1/2 m v^2").layout(size: MGMathText.boardSize, measure: MGMathText.roughWidth)
        XCTAssertEqual(Double(box.width), m.width + 8, accuracy: 1e-6)
        XCTAssertEqual(Double(box.height), m.ascent + m.descent + 6, accuracy: 1e-6)
    }

    func testUnmeasurableRunsDoNotBreakTheLayout() throws {
        let l = try MGMathText.parse("x^2 + 1/2").layout(size: 17) { _, _, _ in .nan }
        XCTAssertEqual(l.width.isFinite, true)
        XCTAssertTrue(l.runs.allSatisfy { $0.x.isFinite && $0.y.isFinite })
    }
}
