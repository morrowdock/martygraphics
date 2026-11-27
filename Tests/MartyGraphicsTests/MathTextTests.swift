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

    /// Formulas that differ only in grouping are heard differently: a compound part ends with an end word before what
    /// follows, and a power or subscript of a function is read after a pause.
    func testGroupingIsHeard() throws {
        let pairs = [("(x + 1)/y + z", "(x + 1)/(y + z)"), ("a/b + c", "a/(b + c)"), ("sin(x)^2", "sin x^2"),
                     ("sin(x)^2", "sin(x^2)"), ("sin x^2", "sin(x^2)"), ("sqrt(x)^2", "sqrt(x^2)"), ("sqrt(x) + 1", "sqrt(x + 1)"),
                     ("abs(x) - 1", "abs(x - 1)"), ("f(x)^2", "f(x^2)"), ("max(a, b) + c", "max(a, b + c)"),
                     ("x^(n + 1) + 2", "x^(n + 1 + 2)"), ("x_(n + 1) + 2", "x_(n + 1 + 2)"),
                     ("(a/(b + c))/d", "a/((b + c)/d)"), ("sin(x)_1", "sin(x_1)")]
        for (a, b) in pairs {
            XCTAssertNotEqual(try MGMathText.parse(a).spoken, try MGMathText.parse(b).spoken, "\(a) against \(b)")
        }
        XCTAssertEqual(try MGMathText.parse("(x + 1)/y + z").spoken,
                       "the fraction with numerator x plus 1 and denominator y, end fraction, plus z")
        XCTAssertEqual(try MGMathText.parse("sin(x)^2").spoken, "sine of x, squared")
        XCTAssertEqual(try MGMathText.parse("sin x^2").spoken, "sine of x squared")
        // Every long-form fraction in the goldens is closed.
        let spoken = try XCTUnwrap(Self.cases()["spoken"] as? [[String: String]]).compactMap { $0["spoken"] }
        for s in spoken {
            XCTAssertEqual(s.components(separatedBy: "the fraction with numerator").count,
                           s.components(separatedBy: ", end fraction").count, s)
        }
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
        let parsed = try scene(Self.math("  y = a sin x  ")).get()
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
        XCTAssertEqual(sceneReason(Self.math("x^2"), extra: #","dim":"3d""#), "3d.text.math")
        XCTAssertEqual(sceneReason(#"{"id":"eq","k":"text","at":[6,4],"style":"maths","text":"x"}"#), "text.style")
    }

    /// The documented order for math text: `3d.text.math`; `text.math` for a brace or a line break anywhere in the raw
    /// text; the plain-text rules (`text.text`); then the markup of the raw, untrimmed text.
    func testSceneRefusalOrder() {
        // Math text has no placeholders: a brace is `text.math` before any placeholder is looked up or filled.
        XCTAssertEqual(sceneReason(Self.math("x = {v}")), "text.math", "a placeholder")
        XCTAssertEqual(sceneReason(Self.math("x = {")), "text.math", "an unclosed brace")
        XCTAssertEqual(sceneReason(Self.math("x = }")), "text.math", "a stray brace")
        XCTAssertEqual(sceneReason(Self.math("x < {v}")), "text.math", "braces before the plain-text rules")
        // Line breaks anywhere, also leading and trailing ones that trimming would have removed.
        XCTAssertEqual(sceneReason(Self.math("x\ny")), "text.math")
        XCTAssertEqual(sceneReason(Self.math("x^2\n")), "text.math", "a trailing line feed")
        XCTAssertEqual(sceneReason(Self.math("\nx^2")), "text.math", "a leading line feed")
        XCTAssertEqual(sceneReason(Self.math("x^2\r")), "text.math", "a carriage return")
        XCTAssertEqual(sceneReason(Self.math("x^2" + String(Character(Unicode.Scalar(0x2028)!)))), "text.math", "a line separator")
        // Then the plain-text rules, then the markup, untrimmed: only plain spaces may pad it.
        XCTAssertEqual(sceneReason(Self.math("x < 1")), "text.text")
        XCTAssertEqual(sceneReason(Self.math("x^2\t")), "text.text", "a tab is a control character")
        XCTAssertEqual(sceneReason(Self.math("x^2" + String(Character(Unicode.Scalar(0xa0)!)))), "text.math",
                       "a trailing no-break space is not trimmed away")
        XCTAssertNil(sceneReason(Self.math("  x^2  ")))
        // 3D first: a 3D scene refuses math text whatever its text.
        XCTAssertEqual(sceneReason(Self.math("x = {v}"), extra: #","dim":"3d""#), "3d.text.math")
        XCTAssertEqual(sceneReason(Self.math("x < 1"), extra: #","dim":"3d""#), "3d.text.math")
        // Other styles are unchanged: plain text keeps its placeholder reasons and its trimming.
        XCTAssertEqual(sceneReason(#"{"id":"t","k":"text","at":[6,4],"text":"x = {v}"}"#), "text.text.placeholder.v")
        XCTAssertNil(sceneReason(#"{"id":"t","k":"text","at":[6,4],"text":"x^2\n"}"#))
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

    // MARK: fitting across the canvas

    /// The fit rule on plain numbers, from the shared cases (tools/tests/test_mg_math.py checks the same rows).
    func testFitGoldens() throws {
        XCTAssertEqual(MGMathText.minimumSize, 11)
        XCTAssertEqual(MGMathText.fitMargin, 8)
        let rows = try XCTUnwrap(Self.cases()["fit"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(rows.count, 8)
        func number(_ row: [String: Any], _ key: String) throws -> Double { try XCTUnwrap((row[key] as? NSNumber)?.doubleValue, key) }
        for row in rows {
            let fit = MGMathText.fit(width: try number(row, "width"), centre: try number(row, "centre"), canvas: try number(row, "canvas"))
            let label = "\(row)"
            XCTAssertEqual(fit.scale, try number(row, "scale"), accuracy: 1e-12, label)
            XCTAssertEqual(fit.left, try number(row, "left"), accuracy: 1e-9, label)
            XCTAssertEqual(fit.width, try number(row, "drawn"), accuracy: 1e-9, label)
            XCTAssertEqual(fit.clipped, try XCTUnwrap(row["clipped"] as? Bool), label)
        }
        XCTAssertEqual(Set(rows.compactMap { $0["clipped"] as? Bool }), [true, false], "both outcomes are covered")
    }

    func testFitRuleProperties() {
        let lowest = MGMathText.minimumSize / MGMathText.boardSize
        for canvas in [0.0, 10, 100, 236, 320, 480, 1280] {
            for width in [0.0, 1, 50, 199.5, 304, 400, 640, 2000, .nan, .infinity] {
                for centre in [-50.0, 0, canvas / 2, canvas, canvas + 50] {
                    let fit = MGMathText.fit(width: width, centre: centre, canvas: canvas)
                    let room = Swift.max(0, canvas - 2 * MGMathText.fitMargin)
                    let label = "width \(width) centre \(centre) canvas \(canvas)"
                    XCTAssertTrue(fit.scale <= 1 && fit.scale >= lowest - 1e-12, label)
                    XCTAssertGreaterThanOrEqual(fit.left, MGMathText.fitMargin - 1e-9, label)
                    XCTAssertLessThanOrEqual(fit.width, room + 1e-9, label)
                    if room > 0 { XCTAssertLessThanOrEqual(fit.left + fit.width, canvas - MGMathText.fitMargin + 1e-9, label) }
                    if fit.clipped {
                        XCTAssertEqual(fit.scale, lowest, accuracy: 1e-12, label)
                        XCTAssertEqual(fit.width, room, accuracy: 1e-9, label)
                    } else if width.isFinite {
                        XCTAssertEqual(fit.width, width * fit.scale, accuracy: 1e-9, label)
                    }
                }
            }
        }
    }

    /// A valid formula at the token bound stays inside a narrow canvas: scaled down, or clipped honestly below the
    /// minimum size. Checked on `MGLayout.bounds`, which uses the same fit as the renderer, so nothing is drawn.
    func testLongFormulasStayInsideNarrowCanvases() throws {
        let longest = String(repeating: "x+", count: 23) + "2 x"
        for text in [longest, "x = (-b ± sqrt(b^2 - 4 a c))/(2 a)", "1/2 m v^2"] {
            for (x, canvas) in [(6.0, 1280.0), (6, 640), (6, 480), (6, 320), (6, 200), (0.2, 1280), (11.8, 640)] {
                let parsed = try scene(Self.math(text).replacingOccurrences(of: "[6,4]", with: "[\(x),4]")).get()
                let item = try XCTUnwrap(parsed.item("eq"))
                let vp = MGViewport(size: CGSize(width: canvas, height: 720), width: 12, height: 8, camera: nil)
                let box = try XCTUnwrap(MGLayout.bounds(item, in: parsed.items, vp))
                let label = "\(text) at x \(x) on \(canvas)"
                // The box is the drawn box with 4 points of padding at each side.
                XCTAssertGreaterThanOrEqual(Double(box.minX), MGMathText.fitMargin - 4 - 1e-6, label)
                XCTAssertLessThanOrEqual(Double(box.maxX), canvas - MGMathText.fitMargin + 4 + 1e-6, label)
                let m = try MGMathText.parse(text).layout(size: MGMathText.boardSize, measure: MGMathText.roughWidth)
                let fit = MGMathText.fit(width: m.width, centre: Double(vp.point(item.pts[0]).x), canvas: canvas)
                XCTAssertEqual(Double(box.width), fit.width + 8, accuracy: 1e-6, label)
                XCTAssertEqual(Double(box.height), (m.ascent + m.descent) * fit.scale + 6, accuracy: 1e-6, label)
                if m.width <= canvas - 2 * MGMathText.fitMargin { XCTAssertEqual(fit.scale, 1, label) }
            }
        }
        // The longest formula is about 640 points wide at the board size: it keeps its size on a 1280 canvas, is
        // scaled down on 640 and 480, and is clipped at the minimum size on 320.
        let m = try MGMathText.parse(longest).layout(size: MGMathText.boardSize, measure: MGMathText.roughWidth)
        XCTAssertEqual(MGMathText.fit(width: m.width, centre: 640, canvas: 1280).scale, 1)
        let mid = MGMathText.fit(width: m.width, centre: 240, canvas: 480)
        XCTAssertTrue(mid.scale < 1 && !mid.clipped, "\(m.width) \(mid)")
        let narrow = MGMathText.fit(width: m.width, centre: 160, canvas: 320)
        XCTAssertTrue(narrow.clipped, "\(m.width) \(narrow)")
        XCTAssertEqual(narrow.scale * MGMathText.boardSize, MGMathText.minimumSize, accuracy: 1e-9)
    }

    func testUnmeasurableRunsDoNotBreakTheLayout() throws {
        let l = try MGMathText.parse("x^2 + 1/2").layout(size: 17) { _, _, _ in .nan }
        XCTAssertEqual(l.width.isFinite, true)
        XCTAssertTrue(l.runs.allSatisfy { $0.x.isFinite && $0.y.isFinite })
    }
}
