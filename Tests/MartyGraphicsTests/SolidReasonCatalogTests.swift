// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import MartyGraphics

/// The reason catalog (`MGSolidReasons`) against the sources: every reason-shaped string literal in the Solid sources and
/// the `marty-solid` tool, every single-word reason passed to a reason constructor, and every reason a key or frame
/// helper composes (`closed` gives `<object>.missing.<keys>` and `<object>.unknown.<keys>`, `transform` gives `.at` and
/// `.rot`) must match a catalog pattern; and every catalog pattern must match something in the sources.
final class SolidReasonCatalogTests: XCTestCase {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// Dotted literals that are not reasons, with why.
    static let notReasons: Set<String> = [
        "anodized.", "plastic.",                      // material name prefixes
        "count.",                                      // fact name prefix (`count.<id>`)
        "dim.",                                        // fact name prefix (`dim.<id>`)
        "annotation.",                                 // snapshot material id prefix (`annotation.<role>`)
        "hero.png", "exploded.png", "loop.gif", "loop.mp4", "story.mp4", "manifest.json", "snapshot.json",   // render output files
        "constraint.gearMesh.a", "constraint.gearMesh.b",                           // unused `what` of `expand` (it throws `ref.unknown.<id>`)
        "beat.*", "beat.*.check.*", "item.*", "board.template",                    // explainer claim ids
        "step.", "step.check.",                                                    // prefixes the explainer renames (to `view.*`, `check.*`)
        "repeat.count", "section.parts", "plate.holes", "extrudedProfile.holes", "shape.",
        "steps.annotate", "beats.view.annotate", "solid.",                         // limit detail field paths (`MGSolidLimitDetail.field`)
    ]
    /// Literals that are reason prefixes: the code appends `.<id>` (`MGSolidFrames.lints`).
    static let prefixes = ["frame.axis.off", "frame.child.absolute", "frame.child.far", "joint.idle"]

    static func sources() throws -> [(name: String, text: String)] {
        let dir = root.appendingPathComponent("Sources/MartyGraphics/Solid")
        var urls = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" && $0.lastPathComponent != "MGSolidReasons.swift" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        // Explainer documents give reasons from this catalog too (format `explainer`).
        let explainer = root.appendingPathComponent("Sources/MartyGraphics/Explainer")
        urls += try FileManager.default.contentsOfDirectory(at: explainer, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        urls.append(root.appendingPathComponent("Examples/Solid3D/Sources/MartySolidCLI/main.swift"))
        return try urls.map { ($0.lastPathComponent, try String(contentsOf: $0, encoding: .utf8)) }
    }

    /// String literals outside comments, with each `\(…)` interpolation replaced by `*`. Raw (`#"…"#`) and multi-line
    /// literals are skipped (the sources build no reason with them).
    static func literals(_ src: String) -> [String] {
        let s = Array(src.unicodeScalars)
        var out: [String] = []
        var i = 0
        func starts(_ t: String, _ k: Int) -> Bool { let u = Array(t.unicodeScalars); return k + u.count <= s.count && Array(s[k..<k + u.count]) == u }
        while i < s.count {
            if starts("//", i) { while i < s.count, s[i] != "\n" { i += 1 }; continue }
            if starts("/*", i) { while i < s.count, !starts("*/", i) { i += 1 }; i += 2; continue }
            guard s[i] == "\"" else { i += 1; continue }
            if starts("\"\"\"", i) { i += 3; while i < s.count, !starts("\"\"\"", i) { i += 1 }; i += 3; continue }
            if i > 0, s[i - 1] == "#" { i += 1; while i < s.count, !starts("\"#", i) { i += 1 }; i += 2; continue }
            var j = i + 1, buf = ""
            while j < s.count, s[j] != "\"" {
                if s[j] == "\\", j + 1 < s.count, s[j + 1] == "(" {
                    var depth = 1, k = j + 2
                    while k < s.count, depth > 0 {
                        if s[k] == "(" { depth += 1 } else if s[k] == ")" { depth -= 1 }
                        else if s[k] == "\"" { k += 1; while k < s.count, s[k] != "\"" { k += 1 } }
                        k += 1
                    }
                    buf += "*"; j = k; continue
                }
                if s[j] == "\\" { buf.unicodeScalars.append(s[j]); j += 1 }
                if j < s.count { buf.unicodeScalars.append(s[j]) }
                j += 1
            }
            out.append(buf)
            i = j + 1
        }
        return out
    }

    static func matches(_ pattern: String, _ text: String) -> [[String]] {
        let re = try! NSRegularExpression(pattern: pattern)
        return re.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { m in
            (1..<m.numberOfRanges).map { Range(m.range(at: $0), in: text).map { String(text[$0]) } ?? "" }
        }
    }

    /// True when some string fits both: `*` in `literal` and `<…>` in `pattern` each match any run of characters.
    static func intersects(_ literal: String, _ pattern: String) -> Bool {
        enum T: Equatable { case c(Character), star }
        let a: [T] = literal.map { $0 == "*" ? .star : .c($0) }
        var b: [T] = []
        var inside = false
        for ch in pattern {
            if inside { if ch == ">" { inside = false }; continue }
            if ch == "<" { inside = true; b.append(.star) } else { b.append(.c(ch)) }
        }
        var memo: [Int: Bool] = [:]
        func f(_ i: Int, _ j: Int) -> Bool {
            let key = i * 1000 + j
            if let v = memo[key] { return v }
            var r = false
            if i == a.count && j == b.count { r = true }
            if !r, i < a.count, a[i] == .star { r = f(i + 1, j) || (j < b.count && f(i, j + 1)) }
            if !r, j < b.count, b[j] == .star { r = f(i, j + 1) || (i < a.count && f(i + 1, j)) }
            if !r, i < a.count, j < b.count, case .c(let x) = a[i], case .c(let y) = b[j], x == y { r = f(i + 1, j + 1) }
            memo[key] = r
            return r
        }
        return f(0, 0)
    }

    /// The last argument of each call to `helper` (`closed`, `transform`), with `*` for interpolations. A variable
    /// argument resolves to its `let <name> = "…"` in the same file, which must be unique.
    static func helperArguments(_ helper: String, _ text: String) -> [String] {
        var out: [String] = []
        for m in matches(helper + #"\([^\n]*?, ("[^"]+"|\w+)\)"#, text) {
            var arg = m[0]
            if !arg.hasPrefix("\"") {
                let defs = matches(#"let "# + arg + #" = ("[^"\n]+")\n"#, text)
                XCTAssertEqual(defs.count, 1, "\(helper) argument \(arg) needs one literal definition")
                guard let d = defs.first else { continue }
                arg = d[0]
            }
            out.append(String(arg.dropFirst().dropLast()).replacingOccurrences(of: #"\\\((?:[^()]|\([^()]*\))*\)"#, with: "*", options: .regularExpression))
        }
        return out
    }

    /// Every reason the sources can name: (literal with `*` for interpolations, where it came from).
    static func sourceReasons() throws -> [(String, String)] {
        var found: [(String, String)] = []
        let dotted = try NSRegularExpression(pattern: #"^(\*|[a-z][A-Za-z0-9_]*)(\.(\*|[A-Za-z0-9_*]+)?)+$"#)
        for (name, text) in try sources() {
            for lit in literals(text) where lit.contains(".") && !notReasons.contains(lit) && !prefixes.contains(lit) {
                if dotted.firstMatch(in: lit, range: NSRange(lit.startIndex..., in: lit)) != nil { found.append((lit, name)) }
            }
            for m in matches(#"(?:MGSolidIssue|\.init|MGError)\("([a-z][A-Za-z]*)""#, text) { found.append((m[0], name)) }
            for what in helperArguments("closed", text) {
                found.append((what + ".missing.*", "\(name) closed")); found.append((what + ".unknown.*", "\(name) closed"))
            }
            // The explainer's closed-key helper follows the lesson rule: `<what>.missing` and `<what>.unknown.<keys>`.
            for what in helperArguments("closedKeys", text) {
                found.append((what + ".missing", "\(name) closedKeys")); found.append((what + ".unknown.*", "\(name) closedKeys"))
            }
            for what in helperArguments("transform", text) {
                found.append((what + ".at", "\(name) transform")); found.append((what + ".rot", "\(name) transform"))
            }
        }
        for p in prefixes { found.append((p + ".*", "MGSolidFrames.swift lints")) }
        return found
    }

    func testEveryReasonInTheSourcesIsInTheCatalog() throws {
        let found = try Self.sourceReasons()
        XCTAssertGreaterThan(found.count, 200)
        let patterns = MGSolidReasons.catalog.map(\.pattern)
        for (lit, from) in found {
            XCTAssertTrue(patterns.contains { Self.intersects(lit, $0) }, "\(lit) (\(from)) is not in MGSolidReasons.catalog")
        }
        for p in patterns {
            XCTAssertTrue(found.contains { Self.intersects($0.0, p) }, "catalog entry \(p) matches nothing in the sources")
        }
        // A reason the sources spell out in full resolves, and to its own entry when the catalog lists it verbatim.
        // (Literals that end in `.` are prefixes such as `MGSolidProfile.strictPrefixes`.)
        for (lit, from) in found where !lit.contains("*") && !lit.hasSuffix(".") {
            let got = MGSolidReasons.lookup(lit)?.pattern
            XCTAssertNotNil(got, "\(lit) (\(from)) resolves to no entry")
            if patterns.contains(lit) { XCTAssertEqual(got, lit, "\(lit) (\(from))") }
        }
    }

    func testTheDocsPageListsEveryPattern() throws {
        let page = try String(contentsOf: Self.root.appendingPathComponent("docs/REASONS.md"), encoding: .utf8)
        let rows = page.split(separator: "\n").filter { $0.hasPrefix("| `") }
        for e in MGSolidReasons.catalog {
            XCTAssertTrue(page.contains("| `\(e.pattern)` | \(e.formats.map(\.rawValue).joined(separator: ", ")) |"), "docs/REASONS.md: \(e.pattern)")
        }
        XCTAssertEqual(rows.count, MGSolidReasons.catalog.count + 12, "one row per pattern, plus the twelve slot rows")
    }

    func testClosedObjectsAreTheClosedCallSites() throws {
        var sites = Set<String>()
        for (_, text) in try Self.sources() { sites.formUnion(Self.helperArguments("closed", text)) }
        let listed = Set(MGSolidReasons.closedObjects.map { $0.replacingOccurrences(of: #"<[^>]*>"#, with: "*", options: .regularExpression) })
        XCTAssertEqual(sites, listed)
    }

    func testCatalogShape() {
        let patterns = MGSolidReasons.catalog.map(\.pattern)
        XCTAssertEqual(Set(patterns).count, patterns.count, "patterns are unique")
        let token = try! NSRegularExpression(pattern: #"^([A-Za-z0-9_.]|<[a-z]+>)+$"#)
        for e in MGSolidReasons.catalog {
            XCTAssertNotNil(token.firstMatch(in: e.pattern, range: NSRange(e.pattern.startIndex..., in: e.pattern)), e.pattern)
            XCTAssertFalse(e.meaning.isEmpty, e.pattern)
            XCTAssertTrue(e.meaning.hasSuffix("."), e.pattern)
            XCTAssertFalse(e.formats.isEmpty, e.pattern)
            let strictPrefixes = MGSolidProfile.strictPrefixes + MGSolidReasons.explainerStrictPrefixes + MGSolidReasons.reportStrictPrefixes
            XCTAssertEqual(e.strict, e.kind == .warning && strictPrefixes.contains { e.pattern.hasPrefix($0) }, e.pattern)
        }
        // The JSON form is deterministic and encodable.
        XCTAssertEqual(MGSolidReasons.json.canonicalString, MGSolidReasons.json.canonicalString)
        XCTAssertTrue(MGSolidReasons.json.isEncodable)
    }

    /// Sample values for each slot, including author names that contain `.missing.` and `.unknown.`.
    static let samples: [String: [String]] = [
        "n": ["1", "12"], "id": ["a", "x.missing.y", "x.unknown.y", "stage1.pinion", String(repeating: "A", count: 32)],
        "name": ["a", "x.missing.y", "nope.speed"], "ident": ["foo", "b2"], "shape": MGSolidParser.shapeKeys.keys.sorted(),
        "crank": ["crankSlider", "crankRod"], "field": ["radius", "width"], "list": ["focus", "highlight"],
        "direction": ["axisWorld", "upWorld"], "modifier": ["abs", "zz"],
        "op": MGSolidComponents.ops.subtracting(["div", "param"]).sorted(), "keys": ["a", "a,b", "x.missing.y,z", "x.unknown.y"],
    ]

    /// Reasons a pattern stands for: every slot at its first sample, then one slot at a time over all its samples
    /// (`<object>` over every closed object).
    static func sampleReasons(_ pattern: String) -> [String] {
        var parts: [String] = [], rest = Substring(pattern)
        while let open = rest.firstIndex(of: "<"), let close = rest[open...].firstIndex(of: ">") {
            parts.append(String(rest[..<open])); parts.append(String(rest[open...close])); rest = rest[rest.index(after: close)...]
        }
        parts.append(String(rest))
        func fill(_ choice: [Int: String]) -> String {
            parts.enumerated().map { i, x in
                guard x.hasPrefix("<") else { return x }
                let name = String(x.dropFirst().dropLast())
                return choice[i] ?? (name == "object" ? "assembly" : samples[name]![0])
            }.joined()
        }
        var out = [fill([:])]
        for (i, x) in parts.enumerated() where x.hasPrefix("<") {
            let name = String(x.dropFirst().dropLast())
            if name == "object" {
                let unknown = parts[i + 1].hasPrefix(".unknown.")
                for o in MGSolidReasons.closedObjects where !(unknown && o == "component") {
                    for v in sampleReasons(o) { out.append(fill([i: v])) }
                }
            } else {
                for v in samples[name]! { out.append(fill([i: v])) }
            }
        }
        return out
    }

    /// Every pattern's sample reasons resolve to that pattern and to no other: typed slots keep emitted reasons apart.
    func testEverySampleReasonResolvesToItsOwnPattern() {
        XCTAssertEqual(Set(Self.samples.keys), Set(MGSolidReasons.slots.keys))
        var checked = 0
        for e in MGSolidReasons.catalog {
            for reason in Self.sampleReasons(e.pattern) {
                XCTAssertEqual(MGSolidReasons.lookup(reason)?.pattern, e.pattern, reason)
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 600)
    }

    /// Reasons the engine gives at run time resolve to their own entry.
    func testLookupOfReasonsTheEngineGives() throws {
        let box = #"{"box":{"size":[4,4,4]}}"#
        func reason(_ json: String) -> String? {
            guard case .failure(let e) = MGSolidParser.document(data: Data(json.utf8)) else { return nil }
            return e.reason
        }
        var cases: [(String, String)] = [
            (#"{"v":1,"kind":"assembly"}"#, "<object>.missing.<keys>"),
            (#"{"v":1,"kind":"assembly","parts":[{"id":"a","shape":\#(box)}],"extra":1}"#, "<object>.unknown.<keys>"),
            (#"{"v":3,"kind":"assembly","parts":[{"id":"a","shape":\#(box)}]}"#, "assembly.version"),
            (#"{"v":1,"kind":"assembly","parts":[{"id":"a","shape":{"gear":{"teeth":12,"module":2,"width":5,"bore":30}}}]}"#, "part.gear.bore"),
            (#"{"v":1,"kind":"assembly","parts":[{"id":"a","shape":{"box":{"size":[4,4,4],"chamfer":3}}}]}"#, "part.<shape>.chamfer"),
            (#"{"v":1,"kind":"assembly","parts":[{"id":"a","shape":{"shaft":{"radius":-1,"length":5}}}]}"#, "part.<shape>.<field>"),
            (#"{"v":1,"kind":"assembly","parts":[{"id":"a","shape":\#(box),"parent":"zz"}]}"#, "ref.unknown.<id>"),
            (#"{"v":1,"kind":"assembly","parts":[{"id":"a","shape":\#(box)},{"id":"a","shape":\#(box)}]}"#, "id.duplicate.<id>"),
            (#"{"v":1,"kind":"assembly","parts":[{"id":"a","shape":\#(box),"at":[1,2]}]}"#, "part.at"),
            (#"{"v":2,"kind":"assembly","parts":[{"id":"a","shape":\#(box),"tier":"solved"}]}"#, "tier.key"),
            (#"{"v":2,"kind":"assembly","parts":[{"id":"a","shape":\#(box)}],"steps":[{"say":"Two 2 parts."}]}"#, "text.number.step.<n>"),
            (#"{"v":2,"kind":"assembly","parts":[{"id":"a","shape":\#(box)}],"steps":[{"say":"{nope.speed}"}]}"#, "text.placeholder.<name>"),
            (#"{"v":1,"kind":"assembly","parts":[{"id":"s","use":"spurPair","with":{"module":50}}]}"#, "component.param.range.<ident>"),
            (#"{"v":1,"kind":"assembly","parts":[{"id":"s","use":"nothing"}]}"#, "component.unknown.<keys>"),
            ("not json", "json"),
        ]
        // Author keys that contain `.missing.` or `.unknown.` (independent review of PR #30).
        cases += [
            (#"{"v":1,"kind":"assembly","parts":[{"id":"a","shape":\#(box)}],"x.missing.y":1}"#, "<object>.unknown.<keys>"),
            (#"{"v":1,"kind":"assembly","parts":[{"id":"a","shape":\#(box),"drive":{"follow":{"source":"a","ratio":1,"x":1}},"joint":{"revolute":[0,0,1]}}]}"#, "<object>.unknown.<keys>"),
        ]
        for (json, pattern) in cases {
            let r = reason(json)
            XCTAssertNotNil(r, json)
            XCTAssertEqual(r.flatMap { MGSolidReasons.lookup($0)?.pattern }, pattern, "\(json) -> \(r ?? "accepted")")
        }
        // A component parameter spec without `default`, and one with an unknown key.
        var lib = MGSolidLibrary.builtIn
        for (spec, want, pattern) in [(#"{"min":1,"max":2}"#, "component.param.foo.missing.default", "<object>.missing.<keys>"),
                                      (#"{"min":1,"max":2,"default":1,"extra":0}"#, "component.param.foo.unknown.extra", "<object>.unknown.<keys>")] {
            let def = #"{"v":1,"kind":"component","id":"probe","title":"P","about":"A.","params":{"foo":\#(spec)},"parts":[{"id":"c","shape":\#(box)}]}"#
            guard case .failure(let e) = lib.register(Data(def.utf8)) else { XCTFail(want); continue }
            XCTAssertEqual(e.reason, want)
            XCTAssertEqual(MGSolidReasons.lookup(e.reason)?.pattern, pattern, e.reason)
        }
        XCTAssertEqual(MGSolidReasons.matches("component.param.foo.missing.default").map(\.pattern), ["<object>.missing.<keys>"])
        XCTAssertEqual(MGSolidReasons.lookup("joint.idle.disc")?.kind, .warning)
        XCTAssertEqual(MGSolidReasons.lookup("joint.idle.disc")?.strict, true)
        XCTAssertEqual(MGSolidReasons.lookup("frame.child.far.x")?.strict, false)
        XCTAssertEqual(MGSolidReasons.lookup("check.meshOpen")?.formats, [.check])
        XCTAssertEqual(MGSolidReasons.lookup("patch.unknown.")?.pattern, "patch.unknown.")
        XCTAssertEqual(MGSolidReasons.lookup("patch.unknown.a,b")?.pattern, "patch.unknown.<keys>")
        XCTAssertNil(MGSolidReasons.lookup("joint.idle.a,b"), "an id holds no comma")
        XCTAssertNil(MGSolidReasons.lookup("text.number.step.0"), "steps count from 1")
        XCTAssertNil(MGSolidReasons.lookup(String(repeating: "a", count: MGSolidReasons.maxReasonBytes + 1)))
        // A long key list (as from a document with thousands of unknown keys) still resolves.
        let longKeys = (0..<6_000).map { "k\($0)" }.joined(separator: ",")
        XCTAssertEqual(MGSolidReasons.lookup("assembly.unknown." + longKeys)?.pattern, "<object>.unknown.<keys>")
        XCTAssertNil(MGSolidReasons.lookup("no.such.reason here"))
        XCTAssertNil(MGSolidReasons.lookup(""))
    }
}
