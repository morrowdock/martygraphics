// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import MartyGraphics

/// docs/EXPLAINER.md against the code (spec PR 3b, tests D1–D4).
final class ExplainerDocsTests: ExplainerTestCase {
    var page: String { (try? String(contentsOf: XFix.root.appendingPathComponent("docs/EXPLAINER.md"), encoding: .utf8)) ?? "" }

    /// The authoring card: the text between the card markers.
    var card: String {
        let p = page
        guard let a = p.range(of: "<!-- card:start -->\n"), let b = p.range(of: "<!-- card:end -->") else { return "" }
        return String(p[a.upperBound..<b.lowerBound])
    }

    func blocks(_ text: String) -> [String] {
        var out: [String] = [], cur: [String]?
        for line in text.components(separatedBy: "\n") {
            if line == "```json" { cur = [] } else if line == "```", let c = cur { out.append(c.joined(separator: "\n")); cur = nil } else { cur?.append(line) }
        }
        return out
    }

    // D1: the card section fits its byte budget.
    func testD1CardBudget() {
        XCTAssertFalse(card.isEmpty)
        XCTAssertTrue(card.hasPrefix("### Choose 2D, 3D or both"))
        XCTAssertLessThanOrEqual(card.utf8.count, 3072)
    }

    // D2: every JSON block of the card parses, equals its example file and passes `check --strict` with the expected captions.
    func testD2CardExamplesRun() throws {
        let b = blocks(card)
        XCTAssertEqual(b.count, 3)
        let names = ["planets-2d", "gears-3d", "gears-mixed"]
        let captions = [["Venus and Earth are almost the same width."],
                        ["The small gear has 15 teeth; the big gear has 30.", "The big gear turns 1/2 of a turn, the other way."],
                        ["Count the teeth: 15 and 30.", "So the big gear turns 1/2 of a turn."]]
        for (i, text) in b.enumerated() {
            XCTAssertEqual(XFix.json(text), XFix.json(try XFix.example(names[i])), names[i])
            let r = MGExplainerReport.check(data: Data(text.utf8), profile: .strict, engine: nil)
            XCTAssertTrue(r.ok, "\(names[i]): \(r.reason ?? "")")
            let got = r.json["beats"]?.arrayValue?.compactMap { b -> String? in if case .string(let s)? = b["caption"] { return s }; return nil }
            XCTAssertEqual(got, captions[i], names[i])
        }
    }

    // D3: every explainer reason in the catalog is named on the page, and every reason the page lists exists.
    func testD3ReasonsSync() {
        let p = page
        let owned = MGSolidReasons.catalog.filter { $0.formats.contains(.explainer) }
        XCTAssertGreaterThan(owned.count, 60)
        for e in owned { XCTAssertTrue(p.contains("`\(e.pattern)`"), "docs/EXPLAINER.md does not name \(e.pattern)") }
        guard let start = p.range(of: "Explainer reasons: "), let end = p.range(of: "Reasons are developer tokens.") else { return XCTFail("reason list") }
        let list = String(p[start.upperBound..<end.lowerBound])
        let re = try! NSRegularExpression(pattern: "`([a-z][A-Za-z0-9_]*\\.[A-Za-z0-9_.<>]*)`")
        let named = re.matches(in: list, range: NSRange(list.startIndex..., in: list)).compactMap { Range($0.range(at: 1), in: list).map { String(list[$0]) } }
        XCTAssertGreaterThan(named.count, 60)
        for n in named { XCTAssertTrue(MGSolidReasons.catalog.contains { $0.pattern == n }, "\(n) is not in the catalog") }
    }

    // D4: every limit in the page's limits table equals the constant in code.
    func testD4LimitsMatchCode() {
        var rows: [String: String] = [:]
        for line in page.components(separatedBy: "\n") where line.hasPrefix("| ") {
            let cells = line.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            if cells.count >= 2 { rows[cells[0]] = cells[1] }
        }
        let L = MGExplainerLimits.self
        let expected: [String: String] = [
            "Raw document input, read before parsing": "\(L.rawBytes / 1024) KiB",
            "Document (its flattened stream, the solid included)": "\(L.bytes / 1024) KiB",
            "Stream, every received byte counted": "\(L.bytes / 1024) KiB",
            "Statements per stream": "\(L.statements)",
            "`solid` statement": "\(MGSolidLimits.bytes / 1024) KiB canonical",
            "Any other statement": "\(L.statementBytes / 1024) KiB",
            "Beats per explainer, over all its streams": "\(L.beats)",
            "Commands per beat": "\(L.commandsPerBeat)",
            "Checks per beat, 2D and 3D together": "\(L.checksPerBeat)",
            "Highlight ids per beat": "\(L.highlightIDs)",
            "Notes": "\(L.notes)",
            "Note text": "\(L.noteText)",
            "Title (filled)": "\(L.title)",
            "Caption": "\(L.say)",
            "Caption `unchecked`": "\(L.unchecked)",
            "Nesting of a document": "\(L.documentDepth) levels",
            "Nesting of a stream statement": "\(L.statementDepth) levels (other than `solid`: \(MGLessonLimits.statementDepth), `lesson.depth`)",
        ]
        for (name, value) in expected { XCTAssertEqual(rows[name], value, name) }
        XCTAssertEqual(L.spinSecondsPerTurn, 4)
        XCTAssertTrue(page.contains("4 s per input turn"))
    }
}
