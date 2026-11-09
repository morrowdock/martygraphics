// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import MartyGraphics

/// Every refusal from a length, count or size limit reports its numbers (docs/REASONS.md, "Limit details"): the
/// report's `limit` gives the field path, the measured value (`actual`), the limit and the unit, and `repair` says it
/// in one line. A catalog test fails when a limit reason has no fixture here, or when a reason whose meaning names a
/// bound is neither a limit reason nor exempt with a stated cause. Fixtures are new synthetic documents.
final class SolidLimitDetailTests: XCTestCase {
    static let box = #"{"id": "a", "shape": {"box": {"size": [10, 10, 10]}}}"#
    static func x(_ n: Int) -> String { String(repeating: "x", count: n) }
    static func list(_ n: Int, _ item: (Int) -> String) -> String { (0..<n).map(item).joined(separator: ", ") }

    /// A v2 assembly with `extra` top-level members (default parts: one box `a`).
    static func asm(_ extra: String = "", parts: String = box, steps: String = #"[{"say": "Box."}]"#) -> String {
        #"{"v": 2, "kind": "assembly", "parts": [\#(parts)], "steps": \#(steps)\#(extra.isEmpty ? "" : ", " + extra)}"#
    }
    static func labels(_ n: Int) -> String { list(n) { #"{"id": "l\#($0)", "at": "a", "text": "Label"}"# } }
    static func component(_ id: String = "c", parts: String = #"{"id": "p", "shape": {"box": {"size": [4, 4, 4]}}}"#, _ extra: String = "") -> String {
        #"{"v": 1, "kind": "component", "id": "\#(id)", "title": "T", "about": "Synthetic fixture."\#(extra.isEmpty ? "" : ", " + extra), "parts": [\#(parts)]}"#
    }
    /// An explainer with a one-box solid (`annotations` optional) and `beats`.
    static func xp(_ extra: String = "", annotations: String? = nil, beats: String = #"[{"say": "A box."}]"#) -> String {
        let ann = annotations.map { #", "annotations": \#($0)"# } ?? ""
        return #"{"v": 1, "kind": "explainer", "solid": {"v": 2, "parts": [\#(box)]\#(ann)}, "beats": \#(beats)\#(extra.isEmpty ? "" : ", " + extra)}"#
    }

    static func check(_ text: String, library: MGSolidLibrary = .builtIn) -> MGJSON {
        MGSolidReport.check(data: Data(text.utf8), library: library, engine: nil).json
    }
    static func explain(_ text: String) -> MGJSON { MGExplainerReport.check(data: Data(text.utf8), engine: nil).json }
    static func register(_ text: String, into l: MGSolidLibrary = .builtIn) -> MGJSON {
        var lib = l
        switch lib.register(Data(text.utf8)) {
        case .failure(let e): return MGSolidReport.refused(e, engine: nil).json
        case .success: return .object(["ok": .bool(true)])
        }
    }
    static func library(_ defs: [String]) -> MGSolidLibrary {
        var l = MGSolidLibrary.builtIn
        for d in defs { _ = l.register(Data(d.utf8)) }
        return l
    }

    /// One fixture per limit pattern: the report (or refusal) it gives.
    static var fixtures: [String: () -> MGJSON] {
        let row = #"{"bladeRow": {"count": 78, "span": 40, "chord": 10, "root": 500, "sections": 24, "chordSamples": 32}}"#
        let leaf = #"{"add":[1,1,1,1,1,1,1,1]}"#
        let mid = #"{"add":[\#(Array(repeating: leaf, count: 8).joined(separator: ","))]}"#
        let big = #"{"add":[\#(Array(repeating: mid, count: 8).joined(separator: ","))]}"#
        let shapes = (0..<4).map { _ in #"{"box":{"size":[1,\#(big),\#(big)]}}"# }.joined(separator: ",")
        let long = String(repeating: "q", count: 24)
        return [
            "assembly.bytes": { MGSolidReport.check(data: Data(repeating: 0x20, count: MGSolidLimits.bytes + 1), engine: nil).json },
            "assembly.title": { check(asm(#""title": "\#(x(81))""#)) },
            "assembly.budget": { check(asm(parts: #"{"id": "a", "shape": [\#(Array(repeating: row, count: 7).joined(separator: ", "))]}"#)) },
            "text.grapheme": { check(asm(#""annotations": {"labels": [{"id": "l", "at": "a", "text": "e\#(String(repeating: "\\u0301", count: 9))"}]}"#)) },
            "parts.count": { check(asm(parts: list(49) { #"{"id": "p\#($0)", "shape": {"box": {"size": [1, 1, 1]}}}"# })) },
            "parts.resolved": { check(asm(parts: list(33) { #"{"id": "p\#($0)", "shape": {"box": {"size": [1, 1, 1]}}, "repeat": {"count": 3}}"# })) },
            "part.name": { check(asm(parts: #"{"id": "a", "name": "\#(x(61))", "shape": {"box": {"size": [1, 1, 1]}}}"#)) },
            "part.shape.count": { check(asm(parts: #"{"id": "a", "shape": [\#(list(9) { _ in #"{"box": {"size": [1, 1, 1]}}"# })]}"#)) },
            "part.repeat.count": { check(asm(parts: #"{"id": "a", "shape": {"box": {"size": [1, 1, 1]}}, "repeat": {"count": 13}}"#)) },
            "part.<shape>.holes": { check(asm(parts: #"{"id": "a", "shape": {"plate": {"radius": 100, "thickness": 5, "holes": [\#(list(33) { _ in "[0, 0, 1]" })]}}}"#)) },
            "part.bladeRow.triangles": { check(asm(parts: #"{"id": "a", "shape": {"bladeRow": {"count": 128, "span": 80, "chord": 40, "root": 200, "stagger": 35, "twist": 15, "camber": -0.03, "sections": 24, "chordSamples": 32}}}"#)) },
            "constraints.count": { check(asm(#""constraints": [\#(list(129) { _ in "{}" })]"#)) },
            "steps.count": { check(asm(steps: "[" + list(17) { _ in #"{"say": "Box."}"# } + "]")) },
            "step.say": { check(asm(steps: #"[{"say": "\#(x(241))"}]"#)) },
            "step.<list>": { check(asm(steps: #"[{"say": "Box.", "focus": [\#(list(17) { _ in #""a""# })]}]"#)) },
            "step.pose": { check(asm(steps: #"[{"say": "Box.", "pose": {}}]"#)) },
            "step.unchecked": { check(asm(steps: #"[{"say": "Box.", "unchecked": "\#(x(61))"}]"#)) },
            "step.check": { check(asm(steps: #"[{"say": "Box.", "check": []}]"#)) },
            "step.ghost": { check(asm(steps: #"[{"say": "Box.", "ghost": []}]"#)) },
            "step.section.parts": { check(asm(steps: #"[{"say": "Box.", "section": {"normal": [0, 0, 1], "parts": []}}]"#)) },
            "labels.count": { check(asm(#""annotations": {"labels": [\#(list(33) { _ in "{}" })]}"#)) },
            "arrows.count": { check(asm(#""annotations": {"arrows": [\#(list(33) { _ in "{}" })]}"#)) },
            "dimensions.count": { check(asm(#""annotations": {"dimensions": [\#(list(17) { _ in "{}" })]}"#)) },
            "annotations.visible": { check(asm(#""annotations": {"labels": [\#(labels(13))]}"#)) },
            "label.text.<id>": { check(asm(#""annotations": {"labels": [{"id": "lEx", "at": "a", "text": "\#(x(61))"}]}"#)) },
            "label.unchecked.<id>": { check(asm(#""annotations": {"labels": [{"id": "l", "at": "a", "text": "Hi", "unchecked": "\#(x(61))"}]}"#)) },
            "arrow.text.<id>": { check(asm(#""annotations": {"arrows": [{"id": "p", "meaning": "pointer", "from": {"world": [0, 0, 60]}, "to": "a", "text": "\#(x(61))"}]}"#)) },
            "arrow.unchecked.<id>": { check(asm(#""annotations": {"arrows": [{"id": "p", "meaning": "pointer", "from": {"world": [0, 0, 60]}, "to": "a", "text": "Hi", "unchecked": "\#(x(61))"}]}"#)) },
            "dimension.text.form.<id>": { check(asm(#""annotations": {"dimensions": [{"id": "d", "a": "a", "b": {"world": [0, 0, 100]}, "text": "\#(x(241))"}]}"#)) },
            "step.annotate.count": { check(asm(#""annotations": {"labels": [\#(labels(13))]}"#, steps: #"[{"say": "Box.", "annotate": [\#(list(13) { #""l\#($0)""# })]}]"#)) },
            "patch.bytes": { MGSolidReport.check(data: Data(asm().utf8), patch: Data(repeating: 0x20, count: MGSolidLimits.bytes + 1), engine: nil).json },
            "component.bytes": { register(component("c", #""pad": "\#(x(17_000))""#)) },
            "component.title": { register(#"{"v": 1, "kind": "component", "id": "c", "title": "\#(x(81))", "about": "A.", "parts": [{"id": "p", "shape": {"box": {"size": [4, 4, 4]}}}]}"#) },
            "component.about": { register(#"{"v": 1, "kind": "component", "id": "c", "title": "T", "about": "\#(x(161))", "parts": [{"id": "p", "shape": {"box": {"size": [4, 4, 4]}}}]}"#) },
            "component.params": { register(component("c", #""params": {\#(list(17) { #""k\#($0)": {"default": 1, "min": 0, "max": 2}"# })}"#)) },
            "component.parts.count": { register(#"{"v": 1, "kind": "component", "id": "c", "title": "T", "about": "A.", "parts": []}"#) },
            "component.depth": {
                let l = library([component("d4"), component("d3", parts: #"{"id": "u", "use": "d4"}"#), component("d2", parts: #"{"id": "u", "use": "d3"}"#)])
                return register(component("d1", parts: #"{"id": "u", "use": "d2"}"#), into: l)
            },
            "component.constraints": { register(component("c", #""constraints": [\#(list(33) { _ in "{}" })]"#)) },
            "component.anchors": { register(component("c", #""anchors": {\#(list(9) { #""m\#($0)": "p""# })}"#)) },
            "component.anchorAbout": { register(component("c", #""anchors": {"m": "p"}, "anchorAbout": {"m": "\#(x(121))"}"#)) },
            "component.checks": { register(component("c", #""checks": {\#(list(9) { #""k\#($0)": {"lt": [0, 1]}"# })}"#)) },
            "component.expr.size": { register(component("wide", parts: #"{"id": "c", "shape": [\#(shapes)]}"#)) },
            "component.id.length": {
                let l = library([component("i" + long.dropFirst(), parts: #"{"id": "\#(long)", "shape": {"box": {"size": [4, 4, 4]}}}"#)])
                return register(component("o" + long.dropFirst(), parts: #"{"id": "\#(long)", "use": "\#("i" + long.dropFirst())"}"#), into: l)
            },
            "explainer.bytes": { MGExplainerReport.check(data: Data(repeating: 0x20, count: MGExplainerLimits.rawBytes + 1), engine: nil).json },
            "explainer.title": { explain(xp(#""title": "\#(x(81))""#)) },
            "explainer.statements.count": {
                var s = MGExplainerSession(pacing: .immediate, clock: MGManualClock())
                var events = s.feed(#"{"explainer": {"v": 1}}"# + "\n")
                for _ in 0..<300 { events += s.feed("{}\n") }
                let issue = XFix.refusals(events).first { $0.reason == "explainer.statements.count" }
                return issue.map { MGExplainerReport.refused($0, profile: nil, source: nil, engine: nil).json } ?? .null
            },
            "explainer.beats.count": { explain(xp(beats: "[" + list(17) { _ in #"{"say": "A box."}"# } + "]")) },
            "notes.count": { explain(xp(#""notes": {}"#)) },
            "notes.text.<id>": { explain(xp(#""notes": {"t3": {"basis": "\#(x(61))"}}"#)) },
            "beat.unchecked.<n>": { explain(xp(beats: #"[{"say": "A box.", "unchecked": "\#(x(61))"}]"#)) },
            "beat.ops.count": { explain(xp(beats: #"[{"say": "A box.", "ops": [\#(list(13) { _ in "{}" })]}]"#)) },
            "beat.checks.count": { explain(xp(beats: #"[{"say": "A box.", "check": [\#(list(9) { _ in "{}" })]}]"#)) },
            "beat.highlight.count": { explain(xp(beats: #"[{"say": "A box.", "highlight": []}]"#)) },
            "stmt.bytes": { explain(#"{"v": 1, "kind": "explainer", "board": {"v": 1, "items": [], "zz": "\#(x(5000))"}, "beats": [{"say": "A box."}]}"#) },
            "stmt.say": { explain(xp(beats: #"[{"say": "\#(x(201))"}]"#)) },
            "view.focus": { explain(xp(beats: #"[{"say": "A box.", "view": {"focus": [\#(list(17) { _ in #""a""# })]}}]"#)) },
            "view.ghost": { explain(xp(beats: #"[{"say": "A box.", "view": {"ghost": []}}]"#)) },
            "view.section.parts": { explain(xp(beats: #"[{"say": "A box.", "view": {"section": {"normal": [0, 0, 1], "parts": []}}}]"#)) },
            "view.annotate.count": { explain(xp(annotations: #"{"labels": [\#(labels(13))]}"#, beats: #"[{"say": "A box.", "view": {"annotate": [\#(list(13) { #""l\#($0)""# })]}}]"#)) },
            "view.pose": { explain(xp(beats: #"[{"say": "A box.", "view": {"pose": {}}}]"#)) },
            "view.hide": { explain(xp(beats: #"[{"say": "A box.", "view": {"hide": []}}]"#)) },
            "view.show": { explain(xp(beats: #"[{"say": "A box.", "view": {"show": []}}]"#)) },
        ]
    }

    /// Exact expected values for a sample of the fixtures: field path, which value key, the value, the limit, the repair.
    static let exact: [String: (field: String, bound: String, actual: Int, limit: Int, repair: String)] = [
        "assembly.bytes": ("document", "actual", 65_537, 65_536, "document has 65,537 bytes; the limit is 65,536. Make it at most 65,536 bytes."),
        "assembly.title": ("title", "actual", 81, 80, "title has 81 characters; the limit is 80. Shorten it to at most 80 characters (1 fewer)."),
        "parts.count": ("parts", "actual", 49, 48, "parts has 49 entries; the limit is 48. Use at most 48 entries (1 fewer)."),
        "part.name": ("parts[0].name", "actual", 61, 60, "parts[0].name has 61 characters; the limit is 60. Shorten it to at most 60 characters (1 fewer)."),
        "part.repeat.count": ("parts[0].repeat.count", "actual", 13, 12, "parts[0].repeat.count has 13 copies; the limit is 12. Use at most 12 copies (1 fewer)."),
        "part.<shape>.holes": ("parts[0].shape.plate.holes", "actual", 33, 32, "parts[0].shape.plate.holes has 33 holes; the limit is 32. Use at most 32 holes (1 fewer)."),
        "step.say": ("steps[0].say", "actual", 241, 240, "steps[0].say has 241 characters; the limit is 240. Shorten it to at most 240 characters (1 fewer)."),
        "step.<list>": ("steps[0].focus", "actual", 17, 16, "steps[0].focus has 17 ids; the limit is 16. Use at most 16 ids (1 fewer)."),
        "step.ghost": ("steps[0].ghost", "actual", 0, 16, "steps[0].ghost has 0 ids; it needs 1 to 16 ids."),
        "label.text.<id>": ("annotations.labels[0].text", "actual", 61, 60, "annotations.labels[0].text has 61 characters; the limit is 60. Shorten it to at most 60 characters (1 fewer)."),
        "step.annotate.count": ("steps[0].annotate", "actual", 13, 12, "steps[0].annotate has 13 annotations; the limit is 12. Use at most 12 annotations (1 fewer)."),
        "component.title": ("title", "actual", 81, 80, "title has 81 characters; the limit is 80. Shorten it to at most 80 characters (1 fewer)."),
        "component.expr.size": ("use", "actualAtLeast", 4097, 4096, "use has at least 4,097 nodes; the limit is 4,096. Use at most 4,096 nodes."),
        "explainer.title": ("title", "actual", 81, 80, "title has 81 characters; the limit is 80. Shorten it to at most 80 characters (1 fewer)."),
        "notes.text.<id>": ("notes.t3.basis", "actual", 61, 60, "notes.t3.basis has 61 characters; the limit is 60. Shorten it to at most 60 characters (1 fewer)."),
        "stmt.say": ("beats[0].say", "actual", 201, 200, "beats[0].say has 201 characters; the limit is 200. Shorten it to at most 200 characters (1 fewer)."),
        "view.ghost": ("beats[0].view.ghost", "actual", 0, 16, "beats[0].view.ghost has 0 ids; it needs 1 to 16 ids."),
        "view.annotate.count": ("beats[0].view.annotate", "actual", 13, 12, "beats[0].view.annotate has 13 annotations; the limit is 12. Use at most 12 annotations (1 fewer)."),
        "explainer.beats.count": ("beats", "actual", 17, 16, "beats has 17 beats; the limit is 16. Use at most 16 beats (1 fewer)."),
    ]

    /// The catalog test: one fixture per limit pattern; each is refused for that pattern with `limit` (a field path, the
    /// measured value over the limit or under the minimum, the limit, a unit) and a `repair` line that states both
    /// numbers.
    func testEveryLimitReasonReportsItsNumbers() throws {
        let fixtures = Self.fixtures
        XCTAssertEqual(Set(fixtures.keys), MGSolidReasons.limitPatterns, "one fixture per limit pattern")
        for pattern in fixtures.keys.sorted() {
            let r = fixtures[pattern]!()
            guard case .string(let reason)? = r["reason"] else { XCTFail("\(pattern): not refused: \(r.canonicalString.prefix(200))"); continue }
            XCTAssertEqual(MGSolidReasons.lookup(reason)?.pattern, pattern, "\(pattern): refused for \(reason)")
            guard case .object(let l)? = r["limit"] else { XCTFail("\(pattern): no limit detail (\(reason))"); continue }
            // Exactly one of `actual`, `actualAtLeast` (a lower bound), `actualAtMost`.
            let values = ["actual", "actualAtLeast", "actualAtMost"].compactMap { k -> Double? in if case .number(let v)? = l[k] { return v }; return nil }
            guard case .string(let field)? = l["field"], !field.isEmpty, values.count == 1, case .number(let limit)? = l["limit"],
                  case .string(let unit)? = l["unit"], !unit.isEmpty else { XCTFail("\(pattern): incomplete limit \(l)"); continue }
            let actual = values[0]
            var minimum: Double?
            if case .number(let m)? = l["minimum"] { minimum = m }
            XCTAssertTrue(actual > limit || (minimum.map { actual < $0 } ?? false), "\(pattern): \(actual) within \(minimum ?? 0)...\(limit)")
            if let e = Self.exact[pattern] {
                XCTAssertEqual(field, e.field, pattern)
                XCTAssertEqual(l[e.bound], .number(Double(e.actual)), "\(pattern) \(e.bound)")
                XCTAssertEqual(limit, Double(e.limit), pattern)
                XCTAssertEqual(r["repair"], .string(e.repair), pattern)
            }
            guard case .string(let repair)? = r["repair"] else { XCTFail("\(pattern): no repair"); continue }
            XCTAssertTrue(repair.hasPrefix(field + " has "), "\(pattern): \(repair)")
            XCTAssertLessThanOrEqual(repair.unicodeScalars.count, MGAnnotationAnchorIssue.repairScalars)
        }
    }

    /// Every catalog entry whose meaning names a length, count or size bound is a limit reason or exempt with a cause;
    /// both lists name only catalog patterns and never the same one.
    func testEveryBoundInTheCatalogIsALimitOrExempt() {
        let patterns = Set(MGSolidReasons.catalog.map(\.pattern))
        XCTAssertTrue(MGSolidReasons.limitPatterns.isSubset(of: patterns), "\(MGSolidReasons.limitPatterns.subtracting(patterns).sorted())")
        XCTAssertTrue(Set(MGSolidReasons.limitExempt.keys).isSubset(of: patterns), "\(Set(MGSolidReasons.limitExempt.keys).subtracting(patterns).sorted())")
        XCTAssertTrue(MGSolidReasons.limitPatterns.isDisjoint(with: MGSolidReasons.limitExempt.keys))
        let bound = try! NSRegularExpression(pattern: #"at most [0-9]|more than [0-9]|over [0-9]|longer than [0-9]|exceeds? [0-9±]|[0-9]+[–-][0-9,]+ (characters|entries|scalars|strings)|fewer than [0-9]|of [0-9]+–[0-9]+|[0-9]+ KiB|[0-9]+ MiB|more than (one|two)|too many|no entry or more|no id or more|no shape or more|1–[0-9]+|[0-9],[0-9]{3}"#)
        var missing: [String] = []
        for e in MGSolidReasons.catalog {
            let m = e.meaning
            guard bound.firstMatch(in: m, range: NSRange(m.startIndex..., in: m)) != nil else { continue }
            if !MGSolidReasons.limitPatterns.contains(e.pattern) && MGSolidReasons.limitExempt[e.pattern] == nil { missing.append(e.pattern) }
        }
        XCTAssertEqual(missing, [], "a bound with no limit detail and no stated exemption")
        // The JSON catalog flags them.
        guard case .array(let entries)? = MGSolidReasons.json["reasons"] else { return XCTFail("reasons") }
        let flagged = entries.compactMap { e -> String? in if e["limit"] == .bool(true), case .string(let p)? = e["pattern"] { return p }; return nil }
        XCTAssertEqual(Set(flagged), MGSolidReasons.limitPatterns)
    }

    /// docs/REASONS.md, "Limit details", names every limit pattern and every exempt pattern.
    func testTheReasonsPageListsTheLimitPatterns() throws {
        let page = try String(contentsOf: XFix.root.appendingPathComponent("docs/REASONS.md"), encoding: .utf8)
        guard let start = page.range(of: "## Limit details"), let end = page.range(of: "## Reasons", range: start.upperBound..<page.endIndex) else {
            return XCTFail("no Limit details section")
        }
        let section = String(page[start.upperBound..<end.lowerBound])
        for p in MGSolidReasons.limitPatterns.union(MGSolidReasons.limitExempt.keys).sorted() {
            XCTAssertTrue(section.contains("`\(p)`"), "docs/REASONS.md Limit details: \(p)")
        }
    }

    /// The round-2f cases: a label over 60 characters and a title over 80 give the field, the count and the limit.
    func testTheRound2fTextRefusalsNowCarryTheirLimit() {
        let label = Self.check(Self.asm(#""annotations": {"labels": [{"id": "lEx", "at": "a", "text": "\#(Self.x(69))"}]}"#))
        XCTAssertEqual(label["limit"], .object(["field": .string("annotations.labels[0].text"), "actual": .number(69), "limit": .number(60),
                                                "unit": .string("characters"), "minimum": .number(1)]))
        XCTAssertEqual(label["repair"], .string("annotations.labels[0].text has 69 characters; the limit is 60. Shorten it to at most 60 characters (9 fewer)."))
        let title = Self.explain(Self.xp(#""title": "\#(Self.x(87))""#))
        XCTAssertEqual(title["reason"], .string("explainer.title"))
        XCTAssertEqual(title["limit"]?["actual"], .number(87))
        XCTAssertEqual(title["limit"]?["limit"], .number(80))
        XCTAssertEqual(title["limit"]?["field"], .string("title"))
        let note = Self.explain(Self.xp(#""notes": {"t3": {"basis": "\#(Self.x(70))"}}"#))
        XCTAssertEqual(note["reason"], .string("notes.text.t3"))
        XCTAssertEqual(note["limit"]?["field"], .string("notes.t3.basis"))
        XCTAssertEqual(note["limit"]?["actual"], .number(70))
        // A limit reason for another cause has no `limit` (a markup character, not a length).
        let markup = Self.check(Self.asm(#""title": "<b>""#))
        XCTAssertEqual(markup["reason"], .string("assembly.title"))
        XCTAssertNil(markup["limit"])
        XCTAssertNotNil(markup["repair"])
    }

    /// The field path names the step, beat or part (0-based) and the explainer's solid.
    func testFieldPathsNameTheirEntry() {
        let step = Self.check(Self.asm(steps: #"[{"say": "Box."}, {"say": "Box.", "unchecked": "\#(Self.x(61))"}]"#))
        XCTAssertEqual(step["limit"]?["field"], .string("steps[1].unchecked"))
        let part = Self.check(Self.asm(parts: Self.box + #", {"id": "b", "name": "\#(Self.x(61))", "shape": {"box": {"size": [1, 1, 1]}}}"#))
        XCTAssertEqual(part["limit"]?["field"], .string("parts[1].name"))
        let solid = Self.explain(#"{"v": 1, "kind": "explainer", "solid": {"v": 2, "parts": [\#(Self.box)], "annotations": {"labels": [{"id": "l", "at": "a", "text": "\#(Self.x(61))"}]}}, "beats": [{"say": "A box."}]}"#)
        XCTAssertEqual(solid["limit"]?["field"], .string("solid.annotations.labels[0].text"))
        let view = Self.explain(Self.xp(beats: #"[{"say": "A box."}, {"say": "A box.", "view": {"ghost": []}}]"#))
        XCTAssertEqual(view["reason"], .string("view.ghost"))
        XCTAssertEqual(view["limit"]?["field"], .string("beats[1].view.ghost"))
    }

    /// A part a component made is named by its id (the authored `parts` does not hold it at an index).
    func testAComponentPartIsNamedByItsId() {
        let l = Self.library([Self.component("c", parts: #"{"id": "p", "name": "\#(Self.x(61))", "shape": {"box": {"size": [4, 4, 4]}}}"#)])
        let r = Self.check(Self.asm(parts: #"{"id": "u", "use": "c"}"#), library: l)
        if r["reason"] == .string("part.name") {
            XCTAssertEqual(r["limit"]?["field"], .string("parts[id=u.p].name"))
        } else {
            // The library refuses the component itself (its own compile checks the name).
            let reg = Self.register(Self.component("c", parts: #"{"id": "p", "name": "\#(Self.x(61))", "shape": {"box": {"size": [4, 4, 4]}}}"#))
            XCTAssertEqual(reg["reason"], .string("part.name"))
            XCTAssertEqual(reg["limit"]?["actual"], .number(61))
        }
    }

    /// A count that stops at the first value over the limit says so (`actualAtLeast`, "at least"), never as `actual`.
    func testABoundedCountIsALowerBound() {
        let l = MGSolidLimitDetail(field: "parts", actual: 97, limit: 96, unit: "parts", exact: false)
        XCTAssertEqual(l.json, .object(["field": .string("parts"), "actualAtLeast": .number(97), "limit": .number(96), "unit": .string("parts")]))
        XCTAssertEqual(l.repair, "parts has at least 97 parts; the limit is 96. Use at most 96 parts.")
        let resolved = MGSolidLimitDetail(count: 99, limit: 96, top: [])
        XCTAssertEqual(resolved.json, .object(["count": .number(99), "limit": .number(96), "top": .array([]), "field": .string("parts"),
                                               "actual": .number(99), "unit": .string("parts")]))
    }

    /// Review fixtures (PR #43): a repeat count is reported as given (exact up to 2^53, a bound above), never capped.
    func testARepeatCountIsReportedAsGiven() {
        func detail(_ count: String) -> MGJSON? {
            Self.check(Self.asm(parts: #"{"id": "a", "shape": {"box": {"size": [10, 10, 10]}}, "repeat": {"count": \#(count)}}"#))["limit"]
        }
        let trillion = detail("1000000000000")
        XCTAssertEqual(trillion?["actual"], .number(1_000_000_000_000))
        XCTAssertNil(trillion?["actualAtLeast"])
        XCTAssertEqual(Self.check(Self.asm(parts: #"{"id": "a", "shape": {"box": {"size": [10, 10, 10]}}, "repeat": {"count": 1000000000000}}"#))["repair"],
                       .string("parts[0].repeat.count has 1,000,000,000,000 copies; the limit is 12. Use at most 12 copies (999,999,999,988 fewer)."))
        let huge = detail("1e17")
        XCTAssertNil(huge?["actual"])
        XCTAssertEqual(huge?["actualAtLeast"], .number(9_007_199_254_740_992))
        let negative = detail("-1e17")
        XCTAssertEqual(negative?["actualAtMost"], .number(-9_007_199_254_740_992))
        // Integers at the 2^53 boundary: the parser keeps them as Int64, so only 2^53 itself is exact.
        XCTAssertEqual(detail("9007199254740992")?["actual"], .number(9_007_199_254_740_992))
        XCTAssertNil(detail("9007199254740992")?["actualAtLeast"])
        let above = detail("9007199254740993")
        XCTAssertNil(above?["actual"])
        XCTAssertEqual(above?["actualAtLeast"], .number(9_007_199_254_740_992))
        XCTAssertEqual(Self.check(Self.asm(parts: #"{"id": "a", "shape": {"box": {"size": [10, 10, 10]}}, "repeat": {"count": 9007199254740993}}"#))["repair"],
                       .string("parts[0].repeat.count has at least 9,007,199,254,740,992 copies; the limit is 12. Use at most 12 copies."))
        XCTAssertEqual(detail("9223372036854775807")?["actualAtLeast"], .number(9_007_199_254_740_992))
        XCTAssertNil(detail("9223372036854775807")?["actual"])
        XCTAssertEqual(detail("-9007199254740993")?["actualAtMost"], .number(-9_007_199_254_740_992))
        XCTAssertEqual(detail("9007199254740991")?["actual"], .number(9_007_199_254_740_991))
        // A decimal: a whole value is exact; a fraction is not a count (no `limit`).
        XCTAssertEqual(detail("13.0")?["actual"], .number(13))
        XCTAssertNil(detail("12.5"))
        XCTAssertEqual(Self.check(Self.asm(parts: #"{"id": "a", "shape": {"box": {"size": [10, 10, 10]}}, "repeat": {"count": 12.5}}"#))["reason"],
                       .string("part.repeat.count"))
        XCTAssertEqual(detail("0")?["actual"], .number(0))
        XCTAssertEqual(detail("0")?["minimum"], .number(2))
    }

    /// Review fixtures (PR #43): full field paths.
    func testFieldPathsNameTheShapeEntryAndTheExplainerSolid() {
        let holes = Self.list(33) { _ in "[0, 0, 1]" }
        let compound = Self.check(Self.asm(parts: #"{"id": "a", "shape": [{"box": {"size": [10, 10, 10]}}, {"plate": {"radius": 100, "thickness": 5, "holes": [\#(holes)]}}]}"#))
        XCTAssertEqual(compound["limit"]?["field"], .string("parts[0].shape[1].plate.holes"))
        let single = Self.check(Self.asm(parts: #"{"id": "a", "shape": {"plate": {"radius": 100, "thickness": 5, "holes": [\#(holes)]}}}"#))
        XCTAssertEqual(single["limit"]?["field"], .string("parts[0].shape.plate.holes"))
        let parts = Self.list(33) { #"{"id": "p\#($0)", "shape": {"box": {"size": [1, 1, 1]}}, "repeat": {"count": 3}}"# }
        let resolved = Self.explain(#"{"v": 1, "kind": "explainer", "solid": {"v": 2, "parts": [\#(parts)]}, "beats": [{"say": "Boxes."}]}"#)
        XCTAssertEqual(resolved["reason"], .string("parts.resolved"))
        XCTAssertEqual(resolved["limit"]?["field"], .string("solid.parts"))
        XCTAssertEqual(resolved["limit"]?["count"], .number(99))
        XCTAssertEqual(resolved["limit"]?["top"], .array([]))
        XCTAssertEqual(resolved["repair"], .string("solid.parts has 99 parts; the limit is 96. Use at most 96 parts (3 fewer)."))
    }

    /// Review fixtures (PR #43): a blank explainer title keeps its minimum-length detail.
    func testABlankExplainerTitleKeepsItsMinimum() {
        let r = Self.explain(Self.xp(#""title": " ""#))
        XCTAssertEqual(r["reason"], .string("explainer.title"))
        XCTAssertEqual(r["limit"], .object(["field": .string("title"), "actual": .number(0), "limit": .number(80), "unit": .string("characters"),
                                            "minimum": .number(1)]))
    }

    /// The same refusal gives the same report bytes in a fresh call (no dictionary order leaks into `limit` or `repair`).
    func testLimitDetailIsDeterministic() {
        let t = Self.asm(#""annotations": {"labels": [{"id": "lEx", "at": "a", "text": "\#(Self.x(69))"}]}"#)
        XCTAssertEqual(MGSolidReport.check(data: Data(t.utf8), engine: nil).text, MGSolidReport.check(data: Data(t.utf8), engine: nil).text)
    }
}
