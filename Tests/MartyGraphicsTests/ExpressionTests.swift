// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import MartyGraphics

/// The closed `func` / `field` expression grammar (`MGExpression`): the golden values and refusals shared with the
/// offline mirror (docs/fixtures/v1/expressions.cases.json, tools/tests/test_mg_expr.py), precedence, the bounds and
/// purity.
final class ExpressionTests: XCTestCase {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static func cases() throws -> [String: Any] {
        let data = try Data(contentsOf: root.appendingPathComponent("docs/fixtures/v1/expressions.cases.json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    static func variables(_ letters: String) -> Set<MGExpression.Variable> {
        Set(letters.compactMap { MGExpression.Variable(rawValue: String($0)) })
    }

    /// A golden value: a number (1e-12 relative), or "nan", "inf" or "-inf".
    static func matches(_ actual: Double, _ expected: Any?) -> Bool {
        if let s = expected as? String {
            switch s {
            case "nan": return actual.isNaN
            case "inf": return actual == .infinity
            case "-inf": return actual == -.infinity
            default: return false
            }
        }
        guard let e = (expected as? NSNumber)?.doubleValue else { return false }
        return actual.isFinite && abs(actual - e) <= 1e-12 * max(1, abs(e))
    }

    func testGoldenValues() throws {
        let values = try XCTUnwrap(Self.cases()["values"] as? [[String: Any]])
        XCTAssertGreaterThan(values.count, 40)
        for c in values {
            let text = try XCTUnwrap(c["text"] as? String)
            let expression = try MGExpression.compile(text, allowed: Set(MGExpression.Variable.allCases), reason: "func.y")
            func input(_ key: String) -> Double { (c[key] as? NSNumber)?.doubleValue ?? 0 }
            let value = expression.value(MGExpression.Inputs(x: input("x"), y: input("y"), t: input("t"),
                                                            a: input("a"), b: input("b"), c: input("c")))
            XCTAssertTrue(Self.matches(value, c["value"]), "\(text) gave \(value)")
        }
    }

    func testGoldenRefusals() throws {
        let refusals = try XCTUnwrap(Self.cases()["refusals"] as? [[String: Any]])
        XCTAssertGreaterThan(refusals.count, 30)
        for c in refusals {
            let text = try XCTUnwrap(c["text"] as? String)
            let allowed = Self.variables(c["allowed"] as? String ?? "x")
            let expected = c["reason"] as? String
            do {
                _ = try MGExpression.compile(text, allowed: allowed, reason: "func.y")
                XCTAssertNil(expected, "accepted: \(text)")
            } catch let error as MGError {
                XCTAssertEqual(error.reason, expected, text)
            }
        }
    }

    func testPrecedenceAssociativityAndTheReasonPrefix() throws {
        func value(_ s: String, x: Double = 0) throws -> Double { try MGExpression.compile(s, allowed: [.x], reason: "r").value(.init(x: x)) }
        XCTAssertEqual(try value("2^3^2"), 512)
        XCTAssertEqual(try value("-2^2"), -4)
        XCTAssertEqual(try value("(-2)^2"), 4)
        XCTAssertEqual(try value("8/4/2"), 1)
        XCTAssertEqual(try value("2*3+4*5"), 26)
        XCTAssertEqual(try value("x^2 - 2*x + 1", x: 1), 0)
        // The caller's reason is the prefix, so a field reports its own key.
        XCTAssertThrowsError(try MGExpression.compile("2x", allowed: [.x], reason: "field.dx")) {
            XCTAssertEqual(($0 as? MGError)?.reason, "field.dx.syntax")
        }
    }

    func testTheLargestAcceptedExpressionsStayWithinTheBounds() throws {
        // 48 tokens (a leading minus and 24 terms), 8 nested parentheses and 80 scalars are accepted; one more is not.
        let terms = "-" + Array(repeating: "x", count: 24).joined(separator: "+")
        XCTAssertEqual(try MGExpression.compile(terms, allowed: [.x], reason: "r").value(.init(x: 1)), 22)
        XCTAssertThrowsError(try MGExpression.compile(terms + "+x", allowed: [.x], reason: "r")) { XCTAssertEqual(($0 as? MGError)?.reason, "r.tokens") }
        let deep = String(repeating: "(", count: MGLimits.exprDepth) + "x" + String(repeating: ")", count: MGLimits.exprDepth)
        XCTAssertNoThrow(try MGExpression.compile(deep, allowed: [.x], reason: "r"))
        XCTAssertThrowsError(try MGExpression.compile("(" + deep + ")", allowed: [.x], reason: "r")) { XCTAssertEqual(($0 as? MGError)?.reason, "r.depth") }
        let padded = "x" + String(repeating: " ", count: MGLimits.exprLength - 1)
        XCTAssertNoThrow(try MGExpression.compile(padded, allowed: [.x], reason: "r"))
        XCTAssertThrowsError(try MGExpression.compile(padded + " ", allowed: [.x], reason: "r")) { XCTAssertEqual(($0 as? MGError)?.reason, "r") }
    }

    func testCompilingIsPureAndTheProgramIsBounded() throws {
        let text = "a*sin(b*x) + c"
        let e = try MGExpression.compile(text, allowed: [.x, .a, .b, .c], reason: "func.y")
        XCTAssertEqual(e.text, text)
        XCTAssertEqual(e.variables, [.x, .a, .b, .c])
        XCTAssertLessThanOrEqual(e.program.count, MGLimits.exprTokens)
        XCTAssertEqual(e, try MGExpression.compile(text, allowed: [.x, .a, .b, .c], reason: "func.y"))
        let inputs = MGExpression.Inputs(x: 0.5, a: 2, b: 3, c: 1)
        XCTAssertEqual(e.value(inputs), 2 * sin(1.5) + 1)
        XCTAssertEqual(e.value(inputs), e.value(inputs))
        // Every function of the vocabulary is reachable, and nothing else is a name.
        for f in MGExpression.Function.allCases {
            let call = f.arity == 2 ? "\(f.rawValue)(x, 1)" : "\(f.rawValue)(x)"
            XCTAssertNoThrow(try MGExpression.compile(call, allowed: [.x], reason: "r"), call)
        }
        for name in ["NSExpression", "FUNCTION", "self", "eval", "x.y", "valueForKey"] {
            XCTAssertThrowsError(try MGExpression.compile(name, allowed: [.x], reason: "r"), name)
        }
    }
}
