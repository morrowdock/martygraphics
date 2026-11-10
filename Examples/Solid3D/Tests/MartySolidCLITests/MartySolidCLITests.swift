// SPDX-License-Identifier: Apache-2.0
import AVFoundation
import Foundation
import ImageIO
import XCTest

/// `marty-solid` in fresh processes. Each process has its own hash seed, so a refusal chosen by dictionary order
/// would vary between runs; these tests also pin the exit codes (0 accepted, 1 refused, 2 usage) and JSON output.
final class MartySolidCLITests: XCTestCase {
    var binary: URL {
        // The test bundle sits next to the products, including the `marty-solid` executable.
        Bundle(for: Self.self).bundleURL.deletingLastPathComponent().appendingPathComponent("marty-solid")
    }
    var models: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/MartySolid3D/Models")
    }

    func run(_ args: [String]) throws -> (status: Int32, json: [String: Any]?, text: String) {
        let p = Process()
        p.executableURL = binary
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        try p.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, try? JSONSerialization.jsonObject(with: data) as? [String: Any], String(decoding: data, as: UTF8.self))
    }

    func write(_ text: String, _ name: String) throws -> String {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("marty-solid-cli-tests-\(ProcessInfo.processInfo.processIdentifier)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try Data(text.utf8).write(to: url)
        return url.path
    }

    func testBinaryIsBuilt() {
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: binary.path), binary.path)
    }

    func testRefusalOrderIsTheSameInEveryProcess() throws {
        let box = #"{"box":{"size":[4,4,4]}}"#
        let names = ["bad one", "bad two", "bad 3", "bad four", "bad five", "bad six", "bad 7", "bad eight"]
        let anchors = try write(#"{"v":1,"kind":"component","id":"badAnchors","title":"T","about":"A.","parts":[{"id":"c","shape":\#(box)}],"anchors":{\#(names.map { #""\#($0)":"c""# }.joined(separator: ","))}}"#, "bad-anchors.json")
        let checks = try write(#"{"v":1,"kind":"component","id":"badChecks","title":"T","about":"A.","parts":[{"id":"c","shape":\#(box)}],"checks":{\#(names.map { #""\#($0)":{"lt":[1,2]}"# }.joined(separator: ","))}}"#, "bad-checks.json")
        for _ in 0..<10 {
            let a = try run(["component", "check", anchors]), c = try run(["component", "check", checks])
            XCTAssertEqual(a.status, 1)
            XCTAssertEqual(a.json?["reason"] as? String, "component.anchor.bad_3")
            XCTAssertEqual(c.status, 1)
            XCTAssertEqual(c.json?["reason"] as? String, "component.check.name.bad_3")
        }
    }

    func testExitCodesAndReports() throws {
        let catalog = try run(["components"])
        XCTAssertEqual(catalog.status, 0)
        XCTAssertEqual((catalog.json?["components"] as? [Any])?.count, 10)
        XCTAssertEqual(catalog.text.split(separator: "\n").count, 1)   // one line of compact JSON
        let accepted = try run(["check", models.appendingPathComponent("planetary-components.json").path])
        XCTAssertEqual(accepted.status, 0)
        XCTAssertEqual(accepted.json?["ok"] as? Bool, true)
        let refused = try run(["check", try write(#"{"v":1,"kind":"assembly","parts":[{"id":"s","use":"spurPair","with":{"module":50}}]}"#, "refused.json")])
        XCTAssertEqual(refused.status, 1)
        XCTAssertEqual(refused.json?["reason"] as? String, "component.param.range.module")
        XCTAssertEqual(refused.json?["part"] as? String, "s")
        let component = try run(["component", "check", try write(#"{"v":1,"kind":"component","id":"cube","title":"Cube","about":"One box.","parts":[{"id":"c","shape":{"box":{"size":[4,4,4]}}}]}"#, "cube.json")])
        XCTAssertEqual(component.status, 0)
        XCTAssertEqual((component.json?["use"] as? [String: Any])?["use"] as? String, "cube")
        XCTAssertEqual(try run(["bogus"]).status, 2)
        XCTAssertEqual(try run(["component", "check", "/nonexistent.json"]).status, 2)
    }

    func testStrictRefusesWhatTheNormalCheckOnlyWarns() throws {
        let idle = try write(#"{"v":2,"kind":"assembly","parts":[{"id":"disc","shape":{"shaft":{"radius":20,"length":5}},"joint":{"revolute":[0,0,1]}}],"steps":[{"say":"A disc on a joint."}]}"#, "idle.json")
        let normal = try run(["check", idle])
        XCTAssertEqual(normal.status, 0)
        XCTAssertEqual(normal.json?["ok"] as? Bool, true)
        XCTAssertEqual((normal.json?["warnings"] as? [[String: Any]])?.first?["reason"] as? String, "joint.idle.disc")
        for args in [["check", "--strict", idle], ["check", idle, "--strict"]] {
            let strict = try run(args)
            XCTAssertEqual(strict.status, 1)
            XCTAssertEqual(strict.json?["ok"] as? Bool, false)
            XCTAssertEqual(strict.json?["reason"] as? String, "joint.idle.disc")
            XCTAssertEqual(strict.json?["part"] as? String, "disc")
            XCTAssertEqual(strict.json?["strict"] as? Bool, true)
            XCTAssertNotNil(strict.json?["readBack"] as? [String])   // the full report is still printed
        }
        let example = try run(["check", "--strict", models.appendingPathComponent("horizontal-reduction.json").path])
        XCTAssertEqual(example.status, 0)
        XCTAssertEqual(example.json?["version"] as? Int, 2)
        XCTAssertEqual((example.json?["legend"] as? [String: Any])?["text"] as? String, "Solved 8 · Not checked 1")
        // Which fact filled each placeholder, and what each check proved.
        let stepFacts = example.json?["stepFacts"] as? [[String: Any]]
        XCTAssertEqual(stepFacts?[1]["facts"] as? [String], ["pinion.teeth", "wheel.teeth"])
        let check = (stepFacts?[3]["checks"] as? [[String: Any]])?.first
        XCTAssertEqual(check?["text"] as? String, "wheel.speed < 0")
        XCTAssertEqual(check?["comparison"] as? String, "lt")
        XCTAssertEqual(check?["target"] as? Double, 0)
        let exact = (stepFacts?[2]["checks"] as? [[String: Any]])?.first
        XCTAssertEqual(exact?["text"] as? String, "wheel.speed = -0.375 ± 1e-09")
        XCTAssertEqual(exact?["tolerance"] as? Double, 1e-9)
        XCTAssertEqual((example.json?["facts"] as? [String: Any]).flatMap { ($0["wheel.speed"] as? [String: Any])?["tier"] as? String }, "solved")
        XCTAssertEqual(try run(["check", "--strict", idle, idle]).status, 2)
        XCTAssertEqual(try run(["check", "--strict", "--strict", idle]).status, 2)
    }

    // MARK: Golden output

    var repo: URL { models.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() }
    var golden: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Golden") }

    /// Fields this release adds to the check report; the golden files hold the output of the release before.
    static let added: Set<String> = ["engine", "partTiers", "motionTiers", "anchorIssues", "anchorUntested", "anchor", "arrowIssues", "arrow"]

    /// Removes top-level members from pretty-printed JSON. The writer puts each top-level key on its own line with an
    /// indent of two spaces and nests everything else deeper, so this is an exact text operation.
    static func strip(_ text: String, _ keys: Set<String>) -> String {
        var out: [String] = []
        var skipping = false
        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("  \"") { skipping = keys.contains(String(line.dropFirst(3).prefix { $0 != "\"" })) }
            else if line == "}" { skipping = false }
            if !skipping { out.append(line) }
        }
        if let close = out.lastIndex(of: "}"), close > 0, out[close - 1].hasSuffix(",") { out[close - 1].removeLast() }
        return out.joined(separator: "\n")
    }

    /// Every shipped example and every JSON file under docs/assets, plus two synthetic inputs (an oversized file and an
    /// idle joint that strict refuses): golden name to path.
    func goldenInputs() throws -> [(String, String)] {
        var out: [(String, String)] = []
        for f in try FileManager.default.contentsOfDirectory(atPath: models.path).filter({ $0.hasSuffix(".json") }).sorted() {
            out.append(("models-" + f.dropLast(5), models.appendingPathComponent(f).path))
        }
        let assets = repo.appendingPathComponent("docs/assets")
        let found = FileManager.default.enumerator(atPath: assets.path)!.compactMap { $0 as? String }.filter { $0.hasSuffix(".json") }.sorted()
        for f in found { out.append(("docs-assets-" + f.dropLast(5).replacingOccurrences(of: "/", with: "-"), assets.appendingPathComponent(f).path)) }
        out.append(("synthetic-oversize", try write(String(repeating: " ", count: 65_537), "oversize.json")))
        out.append(("synthetic-idle", try write(#"{"v":2,"kind":"assembly","parts":[{"id":"disc","shape":{"shaft":{"radius":20,"length":5}},"joint":{"revolute":[0,0,1]}}],"steps":[{"say":"A disc on a joint."}]}"#, "idle.json")))
        return out
    }

    /// The check report moved into the library (`MGSolidReport`). For every input, with and without `--strict`, the
    /// output minus the added fields is byte-identical to the output of the release before (the golden files).
    func testCheckOutputIsByteIdenticalToTheGoldenFiles() throws {
        let inputs = try goldenInputs()
        let files = Set(try FileManager.default.contentsOfDirectory(atPath: golden.path).filter { $0.hasSuffix(".json") })
        XCTAssertEqual(files, Set(inputs.flatMap { ["\($0.0).check.json", "\($0.0).strict.json"] }), "one golden pair per input")
        XCTAssertGreaterThanOrEqual(inputs.count, 18)
        for (name, path) in inputs {
            for (mode, args) in [("check", ["check", path]), ("strict", ["check", "--strict", path])] {
                let want = try String(contentsOf: golden.appendingPathComponent("\(name).\(mode).json"), encoding: .utf8)
                let got = try run(args)
                XCTAssertNotNil(got.json?["engine"] as? [String: Any], "\(name) \(mode): engine")
                if got.json?["readBack"] != nil {
                    XCTAssertNotNil(got.json?["partTiers"] as? [Any], "\(name) \(mode): partTiers")
                    XCTAssertNotNil(got.json?["motionTiers"] as? [Any], "\(name) \(mode): motionTiers")
                }
                XCTAssertEqual(Self.strip(got.text, Self.added), want, "\(name) \(mode)")
                XCTAssertEqual(got.status, want.contains(#""ok" : true"#) ? 0 : 1, "\(name) \(mode)")
            }
        }
    }

    /// Framing alone never refuses a shipped document (PR #51 re-check): every golden input that passed
    /// `check --strict` at main (a13f1f1; `Fixtures/strict-at-main.json`, generated from main's strict goldens) still
    /// passes at head, and its warnings only grow: every warning it had at main is still there, and every added one is
    /// a warning reason (`marty-solid reasons`). The golden test above proves the golden files are the head's output.
    func testEveryShippedDocumentAcceptedAtMainIsStillAccepted() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/strict-at-main.json")
        let fixture = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let accepted = try XCTUnwrap(fixture["accepted"] as? [String: [String]])
        XCTAssertGreaterThanOrEqual(accepted.count, 12)
        XCTAssertNotNil(accepted["docs-assets-jet-suit-ai-lesson"], "the published AI lesson")
        let catalog = try XCTUnwrap(run(["reasons"]).json?["reasons"] as? [[String: Any]])
        let warningPatterns = catalog.filter { $0["kind"] as? String == "warning" }.compactMap { $0["pattern"] as? String }
        func isWarning(_ reason: String) -> Bool {
            warningPatterns.contains { p in
                let rx = "^" + NSRegularExpression.escapedPattern(for: p).replacingOccurrences(of: #"<[a-z]+>"#, with: "[^ ]+", options: .regularExpression) + "$"
                return reason.range(of: rx, options: .regularExpression) != nil
            }
        }
        for (name, before) in accepted.sorted(by: { $0.key < $1.key }) {
            let data = try Data(contentsOf: golden.appendingPathComponent("\(name).strict.json"))
            let head = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any], name)
            XCTAssertEqual(head["ok"] as? Bool, true, "\(name): accepted at main, refused at head: \(head["reason"] ?? "")")
            var now = (head["warnings"] as? [[String: Any]] ?? []).compactMap { $0["reason"] as? String }
            for w in before {
                if let k = now.firstIndex(of: w) { now.remove(at: k) } else { XCTFail("\(name): lost warning \(w)") }
            }
            for w in now { XCTAssertTrue(isWarning(w), "\(name): added \(w) is not a warning") }
        }
    }

    func testStripRemovesOnlyTheNamedTopLevelMembers() {
        let text = "{\n  \"a\" : 1,\n  \"engine\" : {\n    \"x\" : [\n      1\n    ]\n  },\n  \"z\" : {\n    \"engine\" : 2\n  }\n}\n"
        XCTAssertEqual(Self.strip(text, ["engine"]), "{\n  \"a\" : 1,\n  \"z\" : {\n    \"engine\" : 2\n  }\n}\n")
        XCTAssertEqual(Self.strip(text, ["z"]), "{\n  \"a\" : 1,\n  \"engine\" : {\n    \"x\" : [\n      1\n    ]\n  }\n}\n")
    }

    // MARK: version, reasons, --patch

    func testVersionNamesTheEngineAndThisBuild() throws {
        let v = try run(["version"])
        XCTAssertEqual(v.status, 0)
        XCTAssertEqual(v.json?["name"] as? String, "MartyGraphics")
        XCTAssertEqual(v.json?["version"] as? String, "unreleased")
        XCTAssertEqual(v.json?["reportFormat"] as? Int, 1)
        let exe = v.json?["executableSHA256"] as? String
        XCTAssertEqual(exe?.count, 64)
        XCTAssertEqual(exe?.allSatisfy { $0.isHexDigit && !$0.isUppercase }, true)
        let check = try run(["check", models.appendingPathComponent("propeller.json").path])
        XCTAssertEqual((check.json?["engine"] as? [String: Any])?["executableSHA256"] as? String, exe)
        XCTAssertEqual(try run(["version", "extra"]).status, 2)
    }

    func testReasonsCatalog() throws {
        let r = try run(["reasons"])
        XCTAssertEqual(r.status, 0)
        XCTAssertEqual(r.json?["catalog"] as? String, "martygraphics.solid.reasons/1")
        let reasons = r.json?["reasons"] as? [[String: Any]] ?? []
        XCTAssertGreaterThan(reasons.count, 150)
        let patterns = reasons.compactMap { $0["pattern"] as? String }
        for p in ["check.meshOpen", "check.gearsInterpenetrate", "joint.idle.<id>", "patch.bytes", "solidSnapshot.depth", "assembly.bytes"] {
            XCTAssertTrue(patterns.contains(p), p)
        }
        XCTAssertTrue(reasons.allSatisfy { ($0["meaning"] as? String)?.isEmpty == false && ($0["formats"] as? [String])?.isEmpty == false })
    }

    func testCheckWithAPatch() throws {
        let base = try write(#"{"v":1,"kind":"assembly","title":"Disc","parts":[{"id":"disc","shape":{"shaft":{"radius":20,"length":5}},"joint":{"revolute":[0,0,1]},"drive":{"input":1}}]}"#, "base.json")
        let rename = try write(#"{"title":"Disc","parts":{"disc":{"name":"Big disc"}}}"#, "rename.json")
        let unplug = try write(#"{"parts":{"disc":{"drive":null}}}"#, "unplug.json")
        let bogus = try write(#"{"bogus":1}"#, "bogus.json")
        let ok = try run(["check", base, "--patch", rename])
        XCTAssertEqual(ok.status, 0)
        let patch = ok.json?["patch"] as? [String: Any]
        XCTAssertEqual(patch?["applied"] as? Bool, true)
        XCTAssertEqual(patch?["fields"] as? [String], ["parts.disc.name", "title"])
        XCTAssertEqual(patch?["changed"] as? [String], ["parts.disc.name"])
        XCTAssertEqual(ok.json?["title"] as? String, "Disc")
        for args in [["check", "--strict", base, "--patch", unplug], ["check", "--patch", unplug, base, "--strict"]] {
            let strict = try run(args)
            XCTAssertEqual(strict.status, 1)
            XCTAssertEqual(strict.json?["reason"] as? String, "joint.idle.disc")
            XCTAssertEqual((strict.json?["patch"] as? [String: Any])?["changed"] as? [String], ["parts.disc.drive"])
        }
        let refused = try run(["check", base, "--patch", bogus])
        XCTAssertEqual(refused.status, 1)
        XCTAssertEqual(refused.json?["reason"] as? String, "patch.unknown.bogus")
        XCTAssertEqual((refused.json?["patch"] as? [String: Any])?["refusedAt"] as? String, "patch")
        let big = try write(String(repeating: " ", count: 65_537), "big-patch.json")
        XCTAssertEqual(try run(["check", base, "--patch", big]).json?["reason"] as? String, "patch.bytes")
        XCTAssertEqual(try run(["check", base, "--patch"]).status, 2)
        XCTAssertEqual(try run(["check", base, "--patch", rename, "--patch", rename]).status, 2)
        XCTAssertEqual(try run(["check", base, "--patch", "--strict"]).status, 2)
    }

    func testRefusalsCarryTheEngine() throws {
        let bad = try write("{}", "empty.json")
        let render = try run(["render", bad, FileManager.default.temporaryDirectory.appendingPathComponent("never-\(UUID().uuidString)").path])
        XCTAssertEqual(render.status, 1)
        XCTAssertEqual(render.json?["reason"] as? String, "assembly.missing.kind,parts,v")
        XCTAssertNotNil(render.json?["engine"] as? [String: Any])
        let component = try run(["component", "check", bad])
        XCTAssertEqual(component.status, 1)
        XCTAssertNotNil(component.json?["engine"] as? [String: Any])
    }

    /// Review fixture (PR #43): every component path keeps the limit detail and the repair line (`component check`, a
    /// library loaded with `--component`, and an instance refused by `--with`).
    func testComponentRefusalsKeepTheLimitDetail() throws {
        let title = String(repeating: "x", count: 81)
        let bad = try write(#"{"v": 1, "kind": "component", "id": "c", "title": "\#(title)", "about": "Synthetic.", "parts": [{"id": "a", "shape": {"box": {"size": [10, 10, 10]}}}]}"#, "bad-component.json")
        let good = try write(#"{"v": 2, "kind": "assembly", "parts": [{"id": "a", "shape": {"box": {"size": [10, 10, 10]}}}], "steps": [{"say": "Box."}]}"#, "good-assembly.json")
        let repair = "title has 81 characters; the limit is 80. Shorten it to at most 80 characters (1 fewer)."
        for args in [["component", "check", bad], ["check", good, "--component", bad]] {
            let r = try run(args)
            XCTAssertEqual(r.status, 1, "\(args)")
            let report = r.json ?? [:]
            XCTAssertEqual(report["reason"] as? String, "component.title", "\(args)")
            let limit = report["limit"] as? [String: Any]
            XCTAssertEqual(limit?["field"] as? String, "title", "\(args)")
            XCTAssertEqual(limit?["actual"] as? Int, 81, "\(args)")
            XCTAssertEqual(limit?["limit"] as? Int, 80, "\(args)")
            XCTAssertEqual(report["repair"] as? String, repair, "\(args)")
        }
        // A file over the explainer limit is read only to one byte past it: `limit` gives the file's own size.
        let pad = String(repeating: " ", count: 200_000)
        let huge = try write(#"{"kind": "explainer", "pad": "\#(pad)"}"#, "huge.explainer.json")
        let size = try XCTUnwrap((try FileManager.default.attributesOfItem(atPath: huge)[.size] as? NSNumber)?.intValue)
        let big = try run(["check", huge])
        XCTAssertEqual(big.json?["reason"] as? String, "explainer.bytes")
        XCTAssertEqual((big.json?["limit"] as? [String: Any])?["actual"] as? Int, size)
        // An instance refused for its `with` values keeps `repair` too.
        let ranged = try write(#"{"v": 1, "kind": "component", "id": "r", "title": "Ranged", "about": "Synthetic.", "params": {"w": {"default": 4, "min": 1, "max": 8}}, "parts": [{"id": "a", "shape": {"box": {"size": [{"param": "w"}, 4, 4]}}}]}"#, "ranged.json")
        let r = try run(["component", "check", ranged, "--with", "w=20"])
        XCTAssertEqual(r.status, 1)
        XCTAssertNotNil(r.json?["repair"] as? String)
    }

    /// Open vocabulary 3a (C1): reports of documents without annotations keep their keys; an annotated document adds
    /// `annotations`, `placements` and `legend.notes`, and its placement records are byte-identical in fresh processes (P4).
    func testAnnotationReportAndFreshProcessPlacement() throws {
        for name in ["planetary", "slider-crank", "propeller", "planetary-components", "slider-crank-component", "horizontal-reduction", "idler-gearbox"] {
            let r = try run(["check", models.appendingPathComponent("\(name).json").path])
            XCTAssertEqual(r.status, 0, name)
            XCTAssertNil(r.json?["annotations"], name); XCTAssertNil(r.json?["placements"], name)
            XCTAssertNil((r.json?["legend"] as? [String: Any])?["notes"], name)
        }
        let winch = models.appendingPathComponent("annotated-winch.json").path
        let strict = try run(["check", "--strict", winch])
        XCTAssertEqual(strict.status, 0)
        XCTAssertEqual((strict.json?["legend"] as? [String: Any])?["text"] as? String, "Solved 12")
        XCTAssertEqual((strict.json?["legend"] as? [String: Any])?["notes"] as? [String], ["Arrow lengths are not to scale"])
        let annotations = try XCTUnwrap(strict.json?["annotations"] as? [[String: Any]])
        XCTAssertEqual(annotations.map { $0["id"] as? String }, ["lPinion", "lWheel", "aPinion", "aWheel", "aWeight", "aLift", "centres"])
        XCTAssertEqual(annotations.last?["value"] as? Double, 56)
        XCTAssertEqual(annotations.last?["text"] as? String, "Centres 56 mm")
        XCTAssertNotNil(annotations.first?["occludedAtDefaultCamera"] as? Bool)
        let claims = try XCTUnwrap((strict.json?["legend"] as? [String: Any])?["claims"] as? [[String: Any]])
        XCTAssertEqual(claims.filter { $0["kind"] as? String == "annotation" }.count, 7)
        func placements(_ out: String) throws -> String {
            let range = try XCTUnwrap(out.range(of: #""placements" : "#))
            let tail = out[range.upperBound...]
            let end = try XCTUnwrap(tail.range(of: #""ratios""#))
            return String(tail[..<end.lowerBound])
        }
        let first = try placements(strict.text)
        XCTAssertTrue(first.contains(#""candidate""#))
        for _ in 0..<8 { XCTAssertEqual(try placements(try run(["check", winch]).text), first) }
    }

    /// Three annotation errors at once give the same first reason in every process (authored order).
    func testAnnotationRefusalOrderIsTheSameInEveryProcess() throws {
        let gears = #"{"id":"p","shape":{"gear":{"teeth":15,"module":2,"width":8}},"joint":{"revolute":[0,0,1]},"drive":{"input":1}},{"id":"w","at":[45,0,0],"shape":{"gear":{"teeth":30,"module":2,"width":8}},"joint":{"revolute":[0,0,1]}}"#
        let bad = try write(#"{"v":2,"kind":"assembly","parts":[\#(gears)],"constraints":[{"gearMesh":{"a":"p","b":"w"}}],"annotations":{"labels":[{"id":"l1","at":"p","text":"T","size":1,"color":2,"bold":3}],"arrows":[{"id":"a1","meaning":"motion","style":"turn","on":"w","sense":"ccw","from":"p","expect":[1,0,0]}],"dimensions":[{"id":"d1","a":"p","b":"p"}]},"steps":[{"say":"Gears."}]}"#, "bad-annotations.json")
        let arrows = try write(#"{"v":2,"kind":"assembly","parts":[\#(gears)],"constraints":[{"gearMesh":{"a":"p","b":"w"}}],"annotations":{"arrows":[{"id":"a1","meaning":"motion","style":"turn","on":"w","sense":"ccw","from":"p","expect":[1,0,0],"length":3}]},"steps":[{"say":"Gears."}]}"#, "bad-arrow.json")
        for _ in 0..<10 {
            let a = try run(["check", bad]), b = try run(["check", arrows])
            XCTAssertEqual(a.status, 1)
            XCTAssertEqual(a.json?["reason"] as? String, "label.unknown.bold,color,size")
            XCTAssertEqual(b.json?["reason"] as? String, "arrow.key.expect.a1")
            XCTAssertEqual(b.json?["part"] as? String, "a1")
        }
    }
    // MARK: Explainer documents (spec PR 3b, tests C2–C6 and N8)

    var explainers: URL { repo.appendingPathComponent("Examples/Explainers") }

    // C2: `check` on an explainer prints ONE report with the keys of the explainer report.
    func testC2ExplainerCheckReport() throws {
        let r = try run(["check", explainers.appendingPathComponent("gears-mixed.explainer.json").path])
        XCTAssertEqual(r.status, 0)
        let keys = Set(r.json?.keys.map { $0 } ?? [])
        for k in ["ok", "reason", "strict", "kind", "version", "location", "file", "views", "ids", "beats", "annotations", "legend",
                  "warnings", "budget", "engine", "title", "primary"] { XCTAssertTrue(keys.contains(k), k) }
        XCTAssertEqual(r.json?["kind"] as? String, "explainer")
        XCTAssertEqual((r.json?["legend"] as? [String: Any])?["text"] as? String, "Solved 6")
        let views = r.json?["views"] as? [String: Any]
        XCTAssertNotNil(views?["board"] as? [String: Any])
        XCTAssertNotNil((views?["solid"] as? [String: Any])?["facts"])
        XCTAssertEqual((r.json?["beats"] as? [[String: Any]])?.compactMap { $0["caption"] as? String },
                       ["Count the teeth: 15 and 30.", "So the big gear turns 1/2 of a turn."])
    }

    // C3: `--strict` refuses an unused note, and still prints the full report.
    func testC3StrictRefusesUnusedNote() throws {
        let doc = try write(#"{"v":1,"kind":"explainer","notes":{"ghost":{"basis":"b"}},"board":{"v":1,"items":[{"id":"l","k":"text","at":[1,1],"text":"A label"}]},"beats":[{"say":"Hi."}]}"#, "unused-note.json")
        let normal = try run(["check", doc])
        XCTAssertEqual(normal.status, 0)
        XCTAssertEqual((normal.json?["warnings"] as? [[String: Any]])?.first?["reason"] as? String, "notes.unused.ghost")
        let strict = try run(["check", "--strict", doc])
        XCTAssertEqual(strict.status, 1)
        XCTAssertEqual(strict.json?["reason"] as? String, "notes.unused.ghost")
        XCTAssertNotNil(strict.json?["beats"] as? [Any])
        XCTAssertNotNil(strict.json?["legend"] as? [String: Any])
    }

    // C4: a lesson document, an oversized explainer, and a FIFO.
    func testC4KindsLimitsAndFiles() throws {
        let lesson = try run(["check", try write(#"{"v":1,"kind":"lesson","scene":{"v":1,"items":[]},"beats":[]}"#, "lesson.json")])
        XCTAssertEqual(lesson.status, 1)
        XCTAssertEqual(lesson.json?["reason"] as? String, "kind.unsupported")
        let big = #"{"v":1,"kind":"explainer","title":""# + String(repeating: "x", count: 128 * 1024) + #""}"#
        let tooLarge = try run(["check", try write(big, "big.json")])
        XCTAssertEqual(tooLarge.status, 1)
        XCTAssertEqual(tooLarge.json?["reason"] as? String, "explainer.bytes")
        let fifo = FileManager.default.temporaryDirectory.appendingPathComponent("marty-fifo-\(ProcessInfo.processInfo.processIdentifier)").path
        unlink(fifo)
        XCTAssertEqual(mkfifo(fifo, 0o644), 0)
        defer { unlink(fifo) }
        XCTAssertEqual(try run(["check", fifo]).status, 2)
        // Refused explainers report their location.
        let refused = try run(["check", try write(#"{"v":1,"kind":"explainer","board":{"v":1,"items":[{"id":"t","k":"text","at":[1,1],"text":"7 km"}]},"beats":[{"say":"Hi."}]}"#, "n1.json")])
        XCTAssertEqual(refused.status, 1)
        XCTAssertEqual(refused.json?["reason"] as? String, "text.number.item.t")
        XCTAssertEqual((refused.json?["location"] as? [String: Any])?["view"] as? String, "board")
    }

    func renderOrSkip(_ args: [String]) throws -> (status: Int32, json: [String: Any]?, text: String) {
        let r = try run(args)
        if r.status == 2 { throw XCTSkip("render failed (no Metal device on this host?)") }
        return r
    }

    // C5: `render` on the mixed example writes every output, and the manifest hashes match the files.
    func testC5RenderMixed() throws {
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("explainer-render-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: out) }
        let r = try renderOrSkip(["render", explainers.appendingPathComponent("gears-mixed.explainer.json").path, out.path, "--size", "640x400", "--snapshots"])
        XCTAssertEqual(r.status, 0, r.text)
        let files = Set(try FileManager.default.contentsOfDirectory(atPath: out.path))
        XCTAssertEqual(files, ["board-0.png", "solid-0.png", "beat-1.png", "beat-2.png", "snapshot-beat-1.json", "snapshot-beat-2.json",
                               "loop.gif", "loop.mp4", "story.mp4", "manifest.json"])
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: out.appendingPathComponent("manifest.json"))) as? [String: Any]
        XCTAssertEqual(manifest?["legend"] as? String, "Solved 6")
        // The board has a table in every beat, so its pane shows in every beat (the adaptive rule changes nothing here).
        let outputs = manifest?["outputs"] as? [[String: Any]] ?? []
        XCTAssertEqual(outputs.filter { ($0["file"] as? String)?.hasPrefix("beat-") == true }.map { $0["boardPane"] as? Bool }, [true, true])
        // story.mp4: one record with the beats' start times; the captions are the stills' captions.
        let story = try XCTUnwrap(outputs.first { $0["file"] as? String == "story.mp4" })
        XCTAssertEqual(story["fps"] as? Int, 30)
        XCTAssertEqual(story["width"] as? Int, 640); XCTAssertEqual(story["height"] as? Int, 400)
        let beats = try XCTUnwrap(story["beats"] as? [[String: Any]])
        XCTAssertEqual(beats.map { $0["beat"] as? Int }, [1, 2])
        XCTAssertEqual(beats[0]["start"] as? Double, 0)
        XCTAssertEqual(try XCTUnwrap(beats[1]["start"] as? Double), try XCTUnwrap(beats[0]["seconds"] as? Double), accuracy: 1e-9)
        let frames = try XCTUnwrap(story["frames"] as? Int)
        XCTAssertEqual(Double(frames) / 30, try XCTUnwrap(story["seconds"] as? Double), accuracy: 1e-9)
        XCTAssertLessThanOrEqual(frames, 2 * 9 * 30)
        for o in manifest?["outputs"] as? [[String: Any]] ?? [] {
            let name = try XCTUnwrap(o["file"] as? String)
            let data = try Data(contentsOf: out.appendingPathComponent(name))
            XCTAssertEqual(o["bytes"] as? Int, data.count, name)
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/shasum"); p.arguments = ["-a", "256", out.appendingPathComponent(name).path]
            let pipe = Pipe(); p.standardOutput = pipe; try p.run(); p.waitUntilExit()
            let sum = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).split(separator: " ").first.map(String.init)
            XCTAssertEqual(o["sha256"] as? String, sum, name)
        }
    }

    // C6: `render` on the 2D-only example has no solid outputs.
    func testC6Render2DOnly() throws {
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("explainer-render-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: out) }
        let r = try renderOrSkip(["render", explainers.appendingPathComponent("planets-2d.explainer.json").path, out.path, "--size", "640x400"])
        XCTAssertEqual(r.status, 0, r.text)
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: out.path)), ["board-0.png", "beat-1.png", "story.mp4", "manifest.json"])
        let none = FileManager.default.temporaryDirectory.appendingPathComponent("explainer-render-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: none) }
        XCTAssertEqual(try renderOrSkip(["render", explainers.appendingPathComponent("planets-2d.explainer.json").path, none.path, "--size", "640x400",
                                         "--no-story"]).status, 0)
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: none.path)), ["board-0.png", "beat-1.png", "manifest.json"])
    }

    /// The adaptive board pane in stills: a text-only board gives the solid the whole frame until a beat adds a table.
    func testExplainerStillsFollowTheBoardPaneRule() throws {
        let gears = #"{"v":2,"parts":[{"id":"p","shape":{"gear":{"teeth":15,"module":2,"width":8}},"joint":{"revolute":[0,0,1]},"drive":{"input":1}},{"id":"w","at":[45,0,0],"shape":{"gear":{"teeth":30,"module":2,"width":8}},"joint":{"revolute":[0,0,1]}}],"constraints":[{"gearMesh":{"a":"p","b":"w"}}]}"#
        let doc = try write(#"{"v":1,"kind":"explainer","board":{"v":1,"items":[{"id":"cap","k":"text","at":[6,7],"text":"Figures"}]},"solid":\#(gears),"beats":[{"say":"One."},{"say":"Two.","ops":[{"op":"add","item":{"id":"t","k":"table","at":[6,4],"header":true,"cells":[["Gear","Teeth"],["small","{p.teeth}"]]}}]}]}"#, "pane.json")
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("explainer-pane-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: out) }
        let r = try renderOrSkip(["render", doc, out.path, "--size", "640x400", "--no-loop", "--story-fps", "10"])
        XCTAssertEqual(r.status, 0, r.text)
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: out.appendingPathComponent("manifest.json"))) as? [String: Any]
        let outputs = manifest?["outputs"] as? [[String: Any]] ?? []
        let stills = outputs.filter { ($0["file"] as? String)?.hasPrefix("beat-") == true }
        XCTAssertEqual(stills.map { $0["boardPane"] as? Bool }, [false, true])
        // The split beat's board pane fits its two-row table: between the bounds, well under the old 45 %.
        let share = try XCTUnwrap(stills[1]["boardShare"] as? Double)
        XCTAssertGreaterThanOrEqual(share, 0.279); XCTAssertLessThan(share, 0.40)
        XCTAssertNil(stills[0]["boardShare"])
        let story = try XCTUnwrap(outputs.first { $0["file"] as? String == "story.mp4" })
        XCTAssertEqual(story["fps"] as? Int, 10)
        // The layout change slides the pane over the camera move (no cut), and the manifest says so.
        let cutBeats = try XCTUnwrap(story["beats"] as? [[String: Any]])
        XCTAssertEqual(cutBeats.map { $0["cut"] as? Bool }, [false, false])
        XCTAssertNil(cutBeats[1]["cutReason"])
        XCTAssertEqual(cutBeats[1]["path"] as? String, "straight")
        XCTAssertEqual(cutBeats[1]["layout"] as? NSDictionary, ["path": "slide", "change": "open", "seconds": 0.6] as NSDictionary)
        XCTAssertNil(cutBeats[0]["layout"])
        // The story's hold camera of each beat is the camera of that beat's still, in both layouts (full frame, split).
        let beats = try XCTUnwrap(story["beats"] as? [[String: Any]])
        XCTAssertEqual(beats.count, 2)
        for (b, still) in zip(beats, stills) {
            let held = try XCTUnwrap(b["camera"] as? NSDictionary), shot = try XCTUnwrap(still["camera"] as? NSDictionary)
            XCTAssertEqual(held, shot)
        }
    }

    /// The board pane opens at beat 2 and closes at beat 4: the story has no cut, both layout changes slide over the
    /// camera move, and every hold camera is the still's camera in both layouts. During each slide the caption band is
    /// empty, the opening board pane shows no item of the new beat's board (the table with the value 15), and no label
    /// is drawn (the move frames equal those of the same lesson with no labels shown). A settled hold frame shows the
    /// still's picture. A second render in a fresh process gives the same story record and the same stills.
    func testBoardPaneOpensAndClosesWithoutACut() throws {
        let gears = #"{"v":2,"parts":[{"id":"p","shape":{"gear":{"teeth":15,"module":2,"width":8}},"joint":{"revolute":[0,0,1]},"drive":{"input":1}},{"id":"w","at":[45,0,0],"shape":{"gear":{"teeth":30,"module":2,"width":8}},"joint":{"revolute":[0,0,1]}}],"constraints":[{"gearMesh":{"a":"p","b":"w"}}],"annotations":{"labels":[{"id":"lp","at":"p","text":"Small gear"},{"id":"lw","at":"w","text":"Big gear"}]}}"#
        // Subject first: a label on a part makes that part the beat's subject, so the label-free control (`annotate: []`)
        // gives the same subject explicitly (`focus` on the small gear where only its label shows; the big gear, or both,
        // span the model: a whole-model view in both renders), and the two renders share every camera.
        func lesson(_ labels: Bool) -> String {
            let a = { (ids: String, focus: String) in labels ? #","view":{"annotate":[\#(ids)]}"# : focus }
            let small = #","view":{"focus":["p"],"annotate":[]}"#, none = #","view":{"annotate":[]}"#
            return #"{"v":1,"kind":"explainer","board":{"v":1,"items":[{"id":"cap","k":"text","at":[6,7],"text":"Figures"}]},"solid":\#(gears),"beats":[{"say":"One."\#(a(#""lp""#, small))},{"say":"Two."\#(a(#""lw""#, none)),"ops":[{"op":"add","item":{"id":"t","k":"table","at":[6,4],"header":true,"cells":[["Gear","Teeth"],["small","{p.teeth}"]]}}]},{"say":"Three."\#(a(#""lp","lw""#, none))},{"say":"Four."\#(a(#""lp""#, small)),"ops":[{"op":"remove","id":"t"}]}]}"#
        }
        let doc = try write(lesson(true), "pane-slide.json"), plain = try write(lesson(false), "pane-slide-plain.json")
        var outs: [URL] = []
        defer { for o in outs { try? FileManager.default.removeItem(at: o) } }
        func render(_ doc: String) throws -> (URL, [[String: Any]], [[String: Any]]) {
            let out = FileManager.default.temporaryDirectory.appendingPathComponent("explainer-slide-\(UUID().uuidString)")
            outs.append(out)
            let r = try renderOrSkip(["render", doc, out.path, "--size", "640x400", "--no-loop", "--story-fps", "10"])
            XCTAssertEqual(r.status, 0, r.text)
            let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: out.appendingPathComponent("manifest.json"))) as? [String: Any]
            let outputs = manifest?["outputs"] as? [[String: Any]] ?? []
            let story = try XCTUnwrap(outputs.first { $0["file"] as? String == "story.mp4" })
            return (out, try XCTUnwrap(story["beats"] as? [[String: Any]]), outputs.filter { ($0["file"] as? String)?.hasPrefix("beat-") == true })
        }
        let (out, beats, stills) = try render(doc)
        XCTAssertEqual(stills.map { $0["boardPane"] as? Bool }, [false, true, true, false])
        XCTAssertEqual(beats.map { $0["cut"] as? Bool }, [false, false, false, false])
        XCTAssertEqual(beats.compactMap { $0["cutReason"] }.count, 0)
        XCTAssertEqual(beats.map { ($0["layout"] as? [String: Any])?["change"] as? String }, [nil, "open", nil, "close"])
        for k in [1, 3] {
            XCTAssertEqual((beats[k]["layout"] as? [String: Any])?["path"] as? String, "slide")
            XCTAssertEqual(beats[k]["layout"].flatMap { ($0 as? [String: Any])?["seconds"] as? Double }, beats[k]["moveSeconds"] as? Double)
            XCTAssertNotEqual(beats[k]["path"] as? String, "cut")
        }
        // Every hold camera is the still's camera, full frame and split.
        for (b, still) in zip(beats, stills) {
            XCTAssertEqual(try XCTUnwrap(b["camera"] as? NSDictionary), try XCTUnwrap(still["camera"] as? NSDictionary))
        }
        func frames(_ k: Int, _ beats: [[String: Any]]) throws -> (start: Int, hold: Int, end: Int) {
            let start = Int((try XCTUnwrap(beats[k]["start"] as? Double) * 10).rounded())
            let hold = Int((try XCTUnwrap(beats[k]["holdStart"] as? Double) * 10).rounded())
            return (start, hold, start + Int((try XCTUnwrap(beats[k]["seconds"] as? Double) * 10).rounded()) - 1)
        }
        // During each slide: no caption text; on the first hold frame the caption appears.
        let movie = out.appendingPathComponent("story.mp4")
        for k in [1, 3] {
            let f = try frames(k, beats)
            XCTAssertEqual(f.hold - f.start, 6)
            for i in f.start..<f.hold { XCTAssertEqual(try captionTextPixels(movie, frame: i, fps: 10, width: 640, height: 400), 0, "move frame \(i)") }
            XCTAssertGreaterThan(try captionTextPixels(movie, frame: f.hold, fps: 10, width: 640, height: 400), 20)
        }
        // The content area (memory rows run top to bottom): under the title band, above the caption band.
        let rows = (400 - 66 - 278)..<(400 - 66)
        // The opening board pane during the move shows the previous beat's board ("Figures" only), never the new
        // beat's table: the table's rows (white text on the hold frame, away from the rows of "Figures", which is nearly
        // opaque on the last move frame) have no bright pixel on any move frame.
        let open = try frames(1, beats)
        let boardX = 14..<(12 + Int(608 * 0.28) - 4)
        func bright(_ px: [UInt8], _ y: Int, _ limit: UInt8) -> Int {
            boardX.reduce(0) { n, x in let i = (y * 640 + x) * 4; return n + (px[i] > limit && px[i + 1] > limit && px[i + 2] > limit ? 1 : 0) }
        }
        let held = try moviePixels(movie, frame: open.hold, fps: 10, width: 640, height: 400)
        let lastMove = try moviePixels(movie, frame: open.hold - 1, fps: 10, width: 640, height: 400)
        let previousRows = Set(rows.filter { bright(lastMove, $0, 110) > 0 })   // the board's text ink is a muted blue
        XCTAssertFalse(previousRows.isEmpty, "the previous board's text fades in")
        let tableRows = rows.filter { bright(held, $0, 180) > 0 && !(($0 - 3)...($0 + 3)).contains(where: previousRows.contains) }
        // (A table already drawn on the last move frame would put its rows among `previousRows` and fail here.)
        XCTAssertGreaterThan(tableRows.reduce(0) { $0 + bright(held, $1, 180) }, 40, "the table shows from the hold")
        // The second half of the slide: in its first frames the pane has not yet covered the strip, which still shows the
        // previous beat's 3D (a bright close-up of the small gear, its subject); a table drawn early would show here too.
        for i in (open.start + (open.hold - open.start) / 2)..<open.hold {
            let px = try moviePixels(movie, frame: i, fps: 10, width: 640, height: 400)
            XCTAssertEqual(tableRows.reduce(0) { $0 + bright(px, $1, 110) }, 0, "move frame \(i): no item of the new board")
        }
        // No label during a move: each move frame equals the same frame of the lesson with no labels shown (same
        // cameras, same board); the hold frames differ by the labels.
        let (plainOut, plainBeats, _) = try render(plain)
        for (a, b) in zip(beats, plainBeats) { XCTAssertEqual(a["camera"] as? NSDictionary, b["camera"] as? NSDictionary) }
        let plainMovie = plainOut.appendingPathComponent("story.mp4")
        func differing(_ i: Int) throws -> Int {
            let a = try moviePixels(movie, frame: i, fps: 10, width: 640, height: 400)
            let b = try moviePixels(plainMovie, frame: i, fps: 10, width: 640, height: 400)
            var n = 0
            for y in rows { for x in 0..<640 {
                let j = (y * 640 + x) * 4
                if (0..<3).contains(where: { abs(Int(a[j + $0]) - Int(b[j + $0])) > 48 }) { n += 1 }
            } }
            return n
        }
        for k in [1, 3] {
            let f = try frames(k, beats)
            for i in f.start..<f.hold { XCTAssertLessThan(try differing(i), 50, "move frame \(i): a label is drawn") }
            XCTAssertGreaterThan(try differing(f.end), 200, "beat \(k + 1)'s hold shows its labels")
        }
        // A settled hold frame (no spin) shows the still's picture, within video coding error, in both layouts.
        for k in [2, 3] {
            let f = try frames(k, beats)
            let frame = try moviePixels(movie, frame: f.end, fps: 10, width: 640, height: 400)
            let still = try pngPixels(out.appendingPathComponent("beat-\(k + 1).png"), width: 640, height: 400)
            var total = 0, far = 0
            for j in stride(from: 0, to: frame.count, by: 4) {
                let d = (0..<3).map { abs(Int(frame[j + $0]) - Int(still[j + $0])) }.max()!
                total += d; if d > 40 { far += 1 }
            }
            // Video coding error: up to about 4.4 levels on the detailed close-up of the small gear (beat 4's subject).
            XCTAssertLessThan(Double(total) / Double(640 * 400), 5, "beat \(k + 1): mean difference")
            XCTAssertLessThan(far, 640 * 400 / 200, "beat \(k + 1): pixels far from the still")
        }
        // Determinism: a fresh process gives the same story record (holds, paths, cameras, layout) and the same stills.
        // Known pre-existing issue (not this fixture): with highlighted beats and an open board pane, SceneKit's bloom
        // pass can change a few pixels by one level between processes; main a13f1f1 shows it too (PR #51 re-check).
        let (_, beats2, stills2) = try render(doc)
        XCTAssertEqual(beats2 as NSArray, beats as NSArray)
        XCTAssertEqual(stills2.map { $0["sha256"] as? String }, stills.map { $0["sha256"] as? String })
    }

    /// Pixel bounds between fresh processes (docs/SOLID-3D.md, "Determinism"). A pixel's difference is the largest
    /// range of any channel over the runs. Measured on 2026-11-10 at d35e0c3 (Apple M1, macOS 27.2): 164 stills of 21
    /// documents at 1280 x 800, 5 fresh processes each. Per still, the largest measured values were: mean difference
    /// 0.1081 levels, share of pixels more than 16 levels apart 0.0112 %, share of differing pixels 5.016 %. The bounds
    /// are 1.5 x, 2 x and 2 x those. The single largest difference (99 levels) is reported, not a gate. The cause is
    /// inside SceneKit's physically based shading, not in the engine's data.
    static let crossProcessMaxMeanDifference = 0.1622
    static let crossProcessMaxPercentAbove16 = 0.0225
    static let crossProcessMaxDifferingPercent = 10.03

    /// Fresh processes: every byte the engine decides is identical (check reports, the manifest with its cameras,
    /// framing, layout and placement records, snapshot JSON); the stills are within the measured pixel bound. A
    /// representative shipped set: the worst measured channel difference (planetary-components), the worst differing
    /// share (robot-joint-gearbox), an explainer with a board pane (gears-mixed) and the published AI lesson.
    func testCrossProcessOutputIsByteIdenticalExceptBoundedPixels() throws {
        let docs = [models.appendingPathComponent("planetary-components.json"),
                    repo.appendingPathComponent("docs/assets/from-a-prompt/robot-joint/robot-joint-gearbox.json"),
                    explainers.appendingPathComponent("gears-mixed.explainer.json"),
                    repo.appendingPathComponent("docs/assets/jet-suit-ai/lesson.json")]
        for doc in docs {
            let name = doc.lastPathComponent
            var checks: [String] = [], manifests: [Data] = [], others: [[String: Data]] = [], stills: [[String: [UInt8]]] = []
            var sizes: [String: (Int, Int)] = [:]
            for _ in 0..<3 {
                let check = try run(["check", doc.path])
                XCTAssertEqual(check.status, 0, "\(name): check")
                checks.append(check.text)
                let out = FileManager.default.temporaryDirectory.appendingPathComponent("cross-\(UUID().uuidString)")
                defer { try? FileManager.default.removeItem(at: out) }
                let r = try renderOrSkip(["render", doc.path, out.path, "--size", "1280x800", "--no-loop", "--no-story"])
                XCTAssertEqual(r.status, 0, "\(name): \(r.text)")
                manifests.append(try Self.decidedManifest(out.appendingPathComponent("manifest.json")))
                let files = try FileManager.default.contentsOfDirectory(atPath: out.path)
                var json: [String: Data] = [:], png: [String: [UInt8]] = [:]
                for f in files where f.hasSuffix(".json") && f != "manifest.json" { json[f] = try Data(contentsOf: out.appendingPathComponent(f)) }
                for f in files where f.hasSuffix(".png") {
                    let src = try XCTUnwrap(CGImageSourceCreateWithURL(out.appendingPathComponent(f) as CFURL, nil))
                    let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(src, 0, nil))
                    sizes[f] = (image.width, image.height)
                    png[f] = pixels(image, width: image.width, height: image.height)
                }
                others.append(json); stills.append(png)
            }
            XCTAssertEqual(Set(checks).count, 1, "\(name): the check report is byte-identical")
            XCTAssertEqual(Set(manifests).count, 1, "\(name): the manifest (cameras, framing, records) is byte-identical")
            for o in others.dropFirst() { XCTAssertEqual(o, others[0], "\(name): snapshot JSON is byte-identical") }
            XCTAssertFalse(stills[0].isEmpty, name)
            for s in stills.dropFirst() { XCTAssertEqual(Set(s.keys), Set(stills[0].keys), name) }
            for (file, base) in stills[0] {
                let (w, h) = try XCTUnwrap(sizes[file])
                let b = try XCTUnwrap(stills[1][file]), c = try XCTUnwrap(stills[2][file])
                XCTAssertEqual(b.count, base.count, "\(name) \(file)"); XCTAssertEqual(c.count, base.count, "\(name) \(file)")
                guard b.count == base.count, c.count == base.count else { continue }
                var maxDiff = 0, differing = 0, above16 = 0, total = 0
                base.withUnsafeBufferPointer { p0 in b.withUnsafeBufferPointer { p1 in c.withUnsafeBufferPointer { p2 in
                    var i = 0
                    while i < p0.count {
                        var d = 0
                        for k in i..<(i + 4) {
                            let x = Int(p0[k]), y = Int(p1[k]), z = Int(p2[k])
                            d = max(d, max(x, y, z) - min(x, y, z))
                        }
                        if d > 0 { differing += 1; maxDiff = max(maxDiff, d); total += d }
                        if d > 16 { above16 += 1 }
                        i += 4
                    }
                } } }
                let n = Double(w * h), percent = Double(differing) * 100 / n
                let mean = Double(total) / n, percentAbove16 = Double(above16) * 100 / n
                print("cross-process \(name) \(file): max \(maxDiff), mean \(mean), above 16 \(above16), differing \(differing)")
                XCTAssertLessThanOrEqual(mean, Self.crossProcessMaxMeanDifference, "\(name) \(file): mean difference")
                XCTAssertLessThanOrEqual(percentAbove16, Self.crossProcessMaxPercentAbove16, "\(name) \(file): \(above16) pixels above 16 levels")
                XCTAssertLessThanOrEqual(percent, Self.crossProcessMaxDifferingPercent, "\(name) \(file): differing pixels \(differing)")
            }
        }
    }

    /// A render manifest without what is not decided by the engine: `renderSecondsPerFrame` (wall time) and the bytes
    /// and SHA-256 of image and video files (GPU pixels and the hardware encoder). Every other member is kept and
    /// serialised with sorted keys.
    static func decidedManifest(_ url: URL) throws -> Data {
        var m = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        m["renderSecondsPerFrame"] = nil
        m["outputs"] = (m["outputs"] as? [[String: Any]] ?? []).map { o -> [String: Any] in
            guard let f = o["file"] as? String, f.hasSuffix(".png") || f.hasSuffix(".mp4") || f.hasSuffix(".gif") else { return o }
            var o = o; o["sha256"] = nil; o["bytes"] = nil; return o
        }
        return try JSONSerialization.data(withJSONObject: m, options: [.sortedKeys])
    }

    /// RGBA pixels of frame `index` of a movie (memory rows top to bottom).
    func moviePixels(_ movie: URL, frame index: Int, fps: Int, width: Int, height: Int) throws -> [UInt8] {
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: movie))
        gen.requestedTimeToleranceBefore = .zero; gen.requestedTimeToleranceAfter = .zero
        return pixels(try gen.copyCGImage(at: CMTime(value: CMTimeValue(index * 10 + 1), timescale: CMTimeScale(fps * 10)), actualTime: nil),
                      width: width, height: height)
    }

    /// RGBA pixels of a PNG file (memory rows top to bottom).
    func pngPixels(_ url: URL, width: Int, height: Int) throws -> [UInt8] {
        let src = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        return pixels(try XCTUnwrap(CGImageSourceCreateImageAtIndex(src, 0, nil)), width: width, height: height)
    }

    func pixels(_ image: CGImage, width: Int, height: Int) -> [UInt8] {
        var px = [UInt8](repeating: 0, count: width * height * 4)
        let ctx = CGContext(data: &px, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return px
    }

    /// Bright (text) pixels in the caption band of frame `index` of a movie: the band is a dark fill over the scene, so
    /// only caption text is bright there.
    func captionTextPixels(_ movie: URL, frame index: Int, fps: Int, width: Int, height: Int) throws -> Int {
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: movie))
        gen.requestedTimeToleranceBefore = .zero; gen.requestedTimeToleranceAfter = .zero
        let image = try gen.copyCGImage(at: CMTime(value: CMTimeValue(index * 10 + 1), timescale: CMTimeScale(fps * 10)), actualTime: nil)
        let band = Int(120.0 * Double(width) / 1280)
        var px = [UInt8](repeating: 0, count: width * height * 4)
        let ctx = CGContext(data: &px, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var n = 0
        // Memory rows run top to bottom: the band is the last `band` rows.
        for y in (height - band + 2)..<height { for x in 0..<width {
            let i = (y * width + x) * 4
            if px[i] > 200, px[i + 1] > 200, px[i + 2] > 200 { n += 1 }
        } }
        return n
    }

    /// Two gears 1,000 mm apart with focus steps: during the camera move into step 2 the caption band is empty (the
    /// caption names the right gear, which the move has not reached); the caption appears on the first hold frame.
    func testStoryCaptionWaitsForTheHold() throws {
        let doc = try write(#"{"v":2,"kind":"assembly","title":"Two separate gears","parts":[{"id":"a","shape":{"gear":{"teeth":15,"module":2,"width":8}},"joint":{"revolute":[0,0,1]},"drive":{"input":1}},{"id":"b","at":[1000,0,0],"shape":{"gear":{"teeth":30,"module":2,"width":8}},"joint":{"revolute":[0,0,1]},"drive":{"input":1}}],"annotations":{"labels":[{"id":"la","at":"a","text":"Left gear {a.teeth}"},{"id":"lb","at":"b","text":"Right gear {b.teeth}"}]},"steps":[{"say":"The left gear has {a.teeth} teeth.","focus":["a"],"annotate":["la"]},{"say":"The right gear has {b.teeth} teeth.","focus":["b"],"annotate":["lb"]}]}"#, "two-gears.json")
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("story-gears-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: out) }
        XCTAssertEqual(try renderOrSkip(["render", doc, out.path, "--size", "640x400", "--no-loop", "--story-fps", "10"]).status, 0)
        let m = try JSONSerialization.jsonObject(with: Data(contentsOf: out.appendingPathComponent("manifest.json"))) as? [String: Any]
        let story = try XCTUnwrap((m?["outputs"] as? [[String: Any]])?.first { $0["file"] as? String == "story.mp4" })
        let beats = try XCTUnwrap(story["beats"] as? [[String: Any]])
        let start = Int((try XCTUnwrap(beats[1]["start"] as? Double) * 10).rounded())
        let hold = Int((try XCTUnwrap(beats[1]["holdStart"] as? Double) * 10).rounded())
        XCTAssertEqual(hold - start, 6)                                   // the 0.6 s move at 10 fps
        let movie = out.appendingPathComponent("story.mp4")
        XCTAssertGreaterThan(try captionTextPixels(movie, frame: start - 1, fps: 10, width: 640, height: 400), 20)   // step 1's hold
        for f in start..<hold {                                          // every move frame: no caption text
            XCTAssertEqual(try captionTextPixels(movie, frame: f, fps: 10, width: 640, height: 400), 0, "move frame \(f)")
        }
        XCTAssertGreaterThan(try captionTextPixels(movie, frame: hold, fps: 10, width: 640, height: 400), 20)        // hold start
    }

    /// An annotated assembly: each step's hold frame has the still's camera and the same annotations off view.
    func testAnnotatedAssemblyStoryHoldsOnTheStillCamera() throws {
        let winch = FileManager.default.temporaryDirectory.appendingPathComponent("story-winch-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: winch) }
        XCTAssertEqual(try renderOrSkip(["render", models.appendingPathComponent("annotated-winch.json").path, winch.path, "--size", "640x400",
                                         "--no-loop", "--story-fps", "10"]).status, 0)
        let wm = try JSONSerialization.jsonObject(with: Data(contentsOf: winch.appendingPathComponent("manifest.json"))) as? [String: Any]
        let wOut = wm?["outputs"] as? [[String: Any]] ?? []
        let wSteps = wOut.filter { ($0["file"] as? String)?.hasPrefix("step-") == true }
        let wBeats = try XCTUnwrap(wOut.first { $0["file"] as? String == "story.mp4" }?["beats"] as? [[String: Any]])
        XCTAssertEqual(wSteps.count, 5); XCTAssertEqual(wBeats.count, 5)
        for (b, still) in zip(wBeats, wSteps) {
            XCTAssertEqual(try XCTUnwrap(b["camera"] as? NSDictionary), try XCTUnwrap(still["camera"] as? NSDictionary))
            XCTAssertEqual(b["offView"] as? Int, still["offView"] as? Int)
        }
        XCTAssertFalse(wSteps.compactMap { $0["offView"] as? Int }.isEmpty)
    }

    /// A box figure's whole view to a close-up of the engine on its back from the side: the straight move passes an
    /// arm, so the story takes a routed path instead of cutting. The manifest says which path and why; the routed move
    /// lasts 1.0 s; the hold cameras are the stills' cameras.
    func testABlockedStoryMoveTakesARoutedPath() throws {
        let doc = try write(#"{"v":2,"kind":"assembly","title":"Figure","parts":[{"id":"body","at":[0,0,1215],"shape":{"box":{"size":[400,250,740]}}},{"id":"head","at":[0,0,1680],"shape":{"box":{"size":[184,200,218]}}},{"id":"armL","at":[-550,0,1450],"shape":{"box":{"size":[700,120,120]}}},{"id":"armR","at":[550,0,1450],"shape":{"box":{"size":[700,120,120]}}},{"id":"legs","at":[0,0,420],"shape":{"box":{"size":[300,200,840]}}},{"id":"engine","at":[0,170,1300],"shape":{"box":{"size":[90,90,200]}}}],"steps":[{"say":"The figure.","camera":"hero"},{"say":"The engine.","focus":["engine"],"camera":"side"}]}"#, "routed-figure.json")
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("story-routed-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: out) }
        let r = try renderOrSkip(["render", doc, out.path, "--size", "640x400", "--no-loop", "--story-fps", "10"])
        XCTAssertEqual(r.status, 0, r.text)
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: out.appendingPathComponent("manifest.json"))) as? [String: Any]
        let outputs = manifest?["outputs"] as? [[String: Any]] ?? []
        let story = try XCTUnwrap(outputs.first { $0["file"] as? String == "story.mp4" })
        XCTAssertEqual(story["routedTransitionSeconds"] as? Double, 1)
        let beats = try XCTUnwrap(story["beats"] as? [[String: Any]])
        XCTAssertNil(beats[0]["path"])
        XCTAssertTrue(["pullback", "arc", "combined"].contains(beats[1]["path"] as? String ?? ""), "\(beats[1])")
        XCTAssertEqual(beats[1]["pathReason"] as? String, "blocked")
        XCTAssertEqual(beats[1]["blockedBy"] as? String, "armR")
        XCTAssertEqual(beats[1]["cut"] as? Bool, false)
        XCTAssertNil(beats[1]["cutReason"])
        XCTAssertEqual(beats[1]["moveSeconds"] as? Double, 1)
        XCTAssertEqual(try XCTUnwrap(beats[1]["holdStart"] as? Double) - (try XCTUnwrap(beats[1]["start"] as? Double)), 1, accuracy: 1e-9)
        let stills = outputs.filter { ($0["file"] as? String)?.hasPrefix("step-") == true }
        for (b, still) in zip(beats, stills) { XCTAssertEqual(try XCTUnwrap(b["camera"] as? NSDictionary), try XCTUnwrap(still["camera"] as? NSDictionary)) }
    }

    /// The arrow rule in fresh processes: the synthetic arrow inside an engine casing is refused the same way every run
    /// (`annotation.arrow.hidden.push`, its view, the casing; no move: every move that clears the casing takes the tail
    /// off the nozzle, `noSuggest` code `tail`); standard warns.
    func testAHiddenArrowIsRefusedTheSameWayInFreshProcesses() throws {
        let doc = repo.appendingPathComponent("docs/fixtures/arrow-visibility/arrow-in-casing.explainer.json").path
        let first = try run(["check", "--strict", doc])
        XCTAssertEqual(first.status, 1, first.text)
        XCTAssertEqual(first.json?["reason"] as? String, "annotation.arrow.hidden.push")
        let arrow = try XCTUnwrap(first.json?["arrow"] as? [String: Any])
        XCTAssertEqual(arrow["by"] as? String, "engine.casing")
        XCTAssertEqual(arrow["beat"] as? Int, 2)
        XCTAssertTrue(arrow["suggest"] is NSNull)
        XCTAssertEqual((arrow["noSuggest"] as? [String: Any])?["code"] as? String, "tail")
        for _ in 0..<2 { XCTAssertEqual(try run(["check", "--strict", doc]).text, first.text) }
        let standard = try run(["check", doc])
        XCTAssertEqual(standard.status, 0, standard.text)
        XCTAssertEqual((standard.json?["warnings"] as? [[String: Any]])?.compactMap { $0["reason"] as? String }, ["annotation.arrow.hidden.push"])
    }

    /// The back presets and the part-only anchor `{"part": id}` in fresh processes: the same check text each time, a
    /// hidden part-only centre refused in strict mode (a warning in the normal check), and renders framed from behind.
    func testBackPresetsAndPartCentreAnchorsInFreshProcesses() throws {
        let parts = #"[{"id":"shell","shape":{"box":{"size":[200,200,200]}}},{"id":"core","shape":{"box":{"size":[40,40,40]}}},{"id":"side","at":[400,0,0],"shape":{"box":{"size":[40,40,40]}}}]"#
        let steps = #"[{"say":"From behind, left.","camera":"backLeft"},{"say":"The side box from behind, right.","focus":["side"],"camera":"backRight"}]"#
        let ok = try write(#"{"v":2,"kind":"assembly","title":"Back views","parts":\#(parts),"annotations":{"labels":[{"id":"l1","at":{"part":"side"},"text":"Side"}]},"steps":\#(steps)}"#, "back-ok.json")
        let first = try run(["check", "--strict", ok])
        XCTAssertEqual(first.status, 0, first.text)
        for _ in 0..<2 { XCTAssertEqual(try run(["check", "--strict", ok]).text, first.text) }
        let hidden = try write(#"{"v":2,"kind":"assembly","title":"Back views","parts":\#(parts),"annotations":{"labels":[{"id":"l1","at":{"part":"core"},"text":"Core"}]},"steps":\#(steps)}"#, "back-hidden.json")
        let refused = try run(["check", "--strict", hidden])
        XCTAssertEqual(refused.status, 1, refused.text)
        XCTAssertEqual(refused.json?["reason"] as? String, "annotation.anchor.hidden.l1")
        for _ in 0..<2 { XCTAssertEqual(try run(["check", "--strict", hidden]).text, refused.text) }
        let standard = try run(["check", hidden])
        XCTAssertEqual(standard.status, 0, standard.text)
        XCTAssertTrue((standard.json?["warnings"] as? [[String: Any]])?.contains { $0["reason"] as? String == "annotation.anchor.hidden.l1" } ?? false, standard.text)
        let alias = try write(#"{"v":2,"kind":"assembly","parts":\#(parts),"steps":[{"say":"A.","camera":"three-quarter-back"}]}"#, "back-alias.json")
        let a = try run(["check", alias])
        XCTAssertEqual(a.status, 1, a.text)
        XCTAssertEqual(a.json?["reason"] as? String, "step.camera")
        XCTAssertTrue((a.json?["repair"] as? String)?.contains("backRight") ?? false, a.text)
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("back-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: out) }
        let r = try renderOrSkip(["render", ok, out.path, "--size", "320x200", "--no-loop", "--no-story"])
        XCTAssertEqual(r.status, 0, r.text)
        let m = try JSONSerialization.jsonObject(with: Data(contentsOf: out.appendingPathComponent("manifest.json"))) as? [String: Any]
        let stills = (m?["outputs"] as? [[String: Any]] ?? []).filter { ($0["file"] as? String)?.hasPrefix("step-") == true }
        XCTAssertEqual(stills.count, 2)
        XCTAssertEqual((stills[0]["camera"] as? [String: Any])?["yaw"] as? Double, 135)
        XCTAssertEqual((stills[1]["camera"] as? [String: Any])?["yaw"] as? Double, 225)
        XCTAssertEqual(stills[1]["framing"] as? String, "focus")
        for s in stills { XCTAssertTrue(FileManager.default.fileExists(atPath: out.appendingPathComponent(s["file"] as! String).path)) }
    }

    /// `story.mp4` for an assembly with steps; a story over the frame cap is refused before any file is written, and
    /// `--no-story` renders the same document without it. A bad `--story-fps` is a usage error.
    func testAssemblyStoryAndItsCap() throws {
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("story-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: out) }
        let r = try renderOrSkip(["render", models.appendingPathComponent("slider-crank.json").path, out.path, "--size", "320x200", "--no-loop",
                                  "--story-fps", "10"])
        XCTAssertEqual(r.status, 0, r.text)
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: out.appendingPathComponent("manifest.json"))) as? [String: Any]
        let story = try XCTUnwrap((manifest?["outputs"] as? [[String: Any]])?.first { $0["file"] as? String == "story.mp4" })
        let storyBeats = try XCTUnwrap(story["beats"] as? [[String: Any]])
        XCTAssertEqual(storyBeats.count, 4)
        XCTAssertEqual(story["fps"] as? Int, 10)
        // Each step's hold camera is its still's camera.
        let stepStills = (manifest?["outputs"] as? [[String: Any]] ?? []).filter { ($0["file"] as? String)?.hasPrefix("step-") == true }
        XCTAssertEqual(stepStills.count, 4)
        for (b, still) in zip(storyBeats, stepStills) {
            XCTAssertEqual(try XCTUnwrap(b["camera"] as? NSDictionary), try XCTUnwrap(still["camera"] as? NSDictionary))
        }
        XCTAssertEqual(story["codec"] as? String, "h264")
        // 16 steps that each spin 3 turns hold 9 s each: 4,320 frames at 30 fps, over the 3,600 cap.
        let steps = (0..<16).map { _ in #"{"say":"It turns.","spin":3}"# }.joined(separator: ",")
        let long = try write(#"{"v":2,"kind":"assembly","parts":[{"id":"p","shape":{"gear":{"teeth":15,"module":2,"width":8}},"joint":{"revolute":[0,0,1]},"drive":{"input":1}}],"steps":[\#(steps)]}"#, "long-story.json")
        let never = FileManager.default.temporaryDirectory.appendingPathComponent("never-\(UUID().uuidString)")
        let refused = try run(["render", long, never.path, "--size", "320x200", "--no-loop"])
        XCTAssertEqual(refused.status, 1, refused.text)
        XCTAssertEqual(refused.json?["reason"] as? String, "story.frames")
        XCTAssertNotNil(refused.json?["engine"] as? [String: Any])
        XCTAssertFalse(FileManager.default.fileExists(atPath: never.path))
        // At 10 fps the same story fits (1,440 frames); without the story nothing is refused.
        let plain = FileManager.default.temporaryDirectory.appendingPathComponent("plain-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: plain) }
        XCTAssertEqual(try renderOrSkip(["render", long, plain.path, "--size", "320x200", "--no-loop", "--no-story"]).status, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: plain.appendingPathComponent("story.mp4").path))
        XCTAssertEqual(try run(["render", long, never.path, "--story-fps", "24"]).status, 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: never.path))
    }

    /// `microTurbojet` at every parameter corner through `check --strict` in fresh processes: exact exit codes and
    /// reasons. Five engines, a mannequin and a back pack pass (68 parts).
    func testMicroTurbojetCornersAndFiveEngineSuit() throws {
        for d in [60, 300] { for l in [120, 900] { for cut in [0, 1] {
            let f = try write(#"{"v":2,"kind":"assembly","parts":[{"id":"jet","use":"microTurbojet","with":{"diameter":\#(d),"length":\#(l),"cutaway":\#(cut)}}]}"#,
                              "jet-\(d)-\(l)-\(cut).json")
            let r = try run(["check", f, "--strict"])
            if d == 300 && l == 120 {
                XCTAssertEqual(r.status, 1, "\(d) \(l) \(cut)")
                XCTAssertEqual(r.json?["reason"] as? String, "component.check.fits")
            } else {
                XCTAssertEqual(r.status, 0, "\(d) \(l) \(cut): \(r.text)")
                XCTAssertEqual(r.json?["parts"] as? Int, 11)
                XCTAssertEqual((r.json?["warnings"] as? [Any])?.count, 0)
            }
        } } }
        let arm = { (id: String, hand: String, x: Int, y: Int) in
            #"{"id":"\#(id)","use":"microTurbojet","with":{"diameter":70,"length":200},"parent":"pilot.\#(hand)","at":[\#(x),\#(y),200],"rot":[1,0,0,180]}"#
        }
        let suit = try write(#"{"v":2,"kind":"assembly","parts":[{"id":"pilot","use":"mannequin","with":{"leftShoulder":25,"rightShoulder":25}},{"id":"pack","parent":"pilot.back","at":[0,40,0],"shape":{"box":{"size":[260,80,380]}}},{"id":"back","use":"microTurbojet","parent":"pack","at":[0,95,140],"rot":[1,0,0,180]},\#(arm("armL1", "leftHand", 78, -38)),\#(arm("armL2", "leftHand", 78, 38)),\#(arm("armR1", "rightHand", -78, -38)),\#(arm("armR2", "rightHand", -78, 38))]}"#, "suit.json")
        let r = try run(["check", suit, "--strict"])
        XCTAssertEqual(r.status, 0, r.text)
        XCTAssertEqual(r.json?["parts"] as? Int, 68)
    }

    /// `parts.resolved` names the resolved count, the limit and the largest instances, the same in every process.
    func testPartsResolvedDetailInFreshProcesses() throws {
        let uses = ["tLH", "tLF", "tRH", "tRF", "tB", "tX"].enumerated().map { #"{"id":"\#($1)","use":"centrifugalCompressor","at":[\#($0 * 300),0,0]}"# }
        let f = try write(#"{"v":2,"kind":"assembly","parts":[{"id":"pilot","use":"mannequin"},\#(uses.joined(separator: ","))]}"#, "six.json")
        var first: String?
        for _ in 0..<3 {
            let r = try run(["check", f, "--strict"])
            XCTAssertEqual(r.status, 1)
            XCTAssertEqual(r.json?["reason"] as? String, "parts.resolved")
            let limit = try XCTUnwrap(r.json?["limit"] as? [String: Any])
            XCTAssertEqual(limit["count"] as? Int, 180)
            XCTAssertEqual(limit["limit"] as? Int, 96)
            let top = try XCTUnwrap(limit["top"] as? [[String: Any]])
            XCTAssertEqual(top.map { $0["id"] as? String }, ["tB", "tLF", "tLH", "tRF", "tRH"])
            XCTAssertEqual(top.map { $0["parts"] as? Int }, [28, 28, 28, 28, 28])
            XCTAssertEqual(Set(top.compactMap { $0["use"] as? String }), ["centrifugalCompressor"])
            let text = r.text.components(separatedBy: "\n").filter { !$0.contains("executableSHA256") }.joined()
            if let first { XCTAssertEqual(text, first) } else { first = text }
        }
    }

    /// Pixels of one colour in frame `index` of a movie (or in a PNG when `movie` is a still): their count and the angle
    /// (degrees from vertical, signed: positive leans right) of their principal axis.
    func colourBlob(_ url: URL, frame index: Int? = nil, fps: Int = 10, width: Int, height: Int,
                    _ match: (UInt8, UInt8, UInt8) -> Bool) throws -> (count: Int, angle: Double) {
        let image: CGImage
        if let index {
            let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            gen.requestedTimeToleranceBefore = .zero; gen.requestedTimeToleranceAfter = .zero
            image = try gen.copyCGImage(at: CMTime(value: CMTimeValue(index * 10 + 1), timescale: CMTimeScale(fps * 10)), actualTime: nil)
        } else {
            let src = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
            image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(src, 0, nil))
        }
        var px = [UInt8](repeating: 0, count: width * height * 4)
        let ctx = CGContext(data: &px, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var n = 0.0, sx = 0.0, sy = 0.0, sxx = 0.0, syy = 0.0, sxy = 0.0
        for y in 0..<height { for x in 0..<width {
            let i = (y * width + x) * 4
            guard match(px[i], px[i + 1], px[i + 2]) else { continue }
            let fx = Double(x), fy = Double(height - y)
            n += 1; sx += fx; sy += fy; sxx += fx * fx; syy += fy * fy; sxy += fx * fy
        } }
        guard n > 2 else { return (Int(n), 0) }
        let cxx = sxx / n - (sx / n) * (sx / n), cyy = syy / n - (sy / n) * (sy / n), cxy = sxy / n - (sx / n) * (sy / n)
        // Principal axis angle from the x axis, then from vertical.
        let theta = 0.5 * atan2(2 * cxy, cxx - cyy) * 180 / .pi
        return (Int(n), 90 - (theta < 0 ? theta + 180 : theta))
    }

    /// A step pose and a show-only part, rendered for real: the arm stands in step 1 and leans in step 2 (its still and
    /// its story hold frame), it leans part-way in the middle of the camera move between them, and the flag shows only
    /// in step 2.
    func testStepPoseAndShowOnlyPartRender() throws {
        let doc = try write(#"{"v":2,"kind":"assembly","title":"Pose","parts":[{"id":"base","shape":{"box":{"size":[400,40,20]}},"material":"plastic.muted"},{"id":"arm","parent":"base","at":[0,0,10],"shape":{"shaft":{"radius":12,"length":300}},"material":"plastic.white","emissive":{"role":"green","intensity":3}},{"id":"flag","parent":"base","at":[160,0,60],"shape":{"box":{"size":[40,20,40]}},"material":"plastic.white","emissive":{"role":"red","intensity":3}}],"steps":[{"say":"Upright.","camera":"front","focus":["base","arm"]},{"say":"Leaning.","camera":"front","focus":["base","arm"],"pose":{"arm":{"rot":[0,1,0,60]}},"show":["flag"]}]}"#, "pose.json")
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("pose-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: out) }
        let r = try renderOrSkip(["render", doc, out.path, "--size", "320x200", "--no-loop", "--story-fps", "10"])
        XCTAssertEqual(r.status, 0, r.text)
        // The lit parts bloom to white at their core; their coloured glow around it gives their shape.
        func green(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> Bool { g > 120 && Int(g) > Int(r) + 40 }
        func red(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> Bool { r > 120 && Int(r) > Int(g) + 40 }
        let still1 = try colourBlob(out.appendingPathComponent("step-1.png"), width: 320, height: 200, green)
        let still2 = try colourBlob(out.appendingPathComponent("step-2.png"), width: 320, height: 200, green)
        XCTAssertGreaterThan(still1.count, 50); XCTAssertGreaterThan(still2.count, 50)
        XCTAssertLessThan(abs(still1.angle), 10, "\(still1)")
        XCTAssertGreaterThan(still2.angle, 45, "\(still2)")
        XCTAssertEqual(try colourBlob(out.appendingPathComponent("step-1.png"), width: 320, height: 200, red).count, 0)
        XCTAssertGreaterThan(try colourBlob(out.appendingPathComponent("step-2.png"), width: 320, height: 200, red).count, 10)
        XCTAssertEqual(try colourBlob(out.appendingPathComponent("hero.png"), width: 320, height: 200, red).count, 0)
        let m = try JSONSerialization.jsonObject(with: Data(contentsOf: out.appendingPathComponent("manifest.json"))) as? [String: Any]
        let story = try XCTUnwrap((m?["outputs"] as? [[String: Any]])?.first { $0["file"] as? String == "story.mp4" })
        let beats = try XCTUnwrap(story["beats"] as? [[String: Any]])
        XCTAssertEqual(beats.map { $0["cut"] as? Bool }, [false, false])
        let start = Int((try XCTUnwrap(beats[1]["start"] as? Double) * 10).rounded())
        let hold = Int((try XCTUnwrap(beats[1]["holdStart"] as? Double) * 10).rounded())
        let movie = out.appendingPathComponent("story.mp4")
        let before = try colourBlob(movie, frame: start - 1, width: 320, height: 200, green)
        let middle = try colourBlob(movie, frame: (start + hold) / 2, width: 320, height: 200, green)
        let after = try colourBlob(movie, frame: hold + 2, width: 320, height: 200, green)
        XCTAssertLessThan(abs(before.angle), 10, "\(before)")
        XCTAssertGreaterThan(middle.angle, before.angle + 10, "\(middle)")
        XCTAssertLessThan(middle.angle, after.angle - 10, "\(middle)")
        XCTAssertEqual(after.angle, still2.angle, accuracy: 6)
        XCTAssertEqual(try colourBlob(movie, frame: start - 1, width: 320, height: 200, red).count, 0)
        XCTAssertGreaterThan(try colourBlob(movie, frame: hold + 2, width: 320, height: 200, red).count, 10)
    }

    /// A focus step with a wall between the camera and the focus: the still draws the wall as an automatic ghost and its
    /// manifest record (and the story beat) give `autoGhost`, `occluded`, `focusSamples`, `view` and `offView`.
    func testRenderRecordsTheUnblockedFocus() throws {
        let doc = try write(#"{"v":2,"kind":"assembly","title":"Blocked","parts":[{"id":"target","shape":{"box":{"size":[60,60,60]}}},{"id":"wall","at":[0,-100,0],"shape":{"box":{"size":[400,20,400]}}}],"steps":[{"say":"The whole model.","camera":"front"},{"say":"The block.","focus":["target"],"camera":"front"}]}"#, "blocked.json")
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("blocked-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: out) }
        let r = try renderOrSkip(["render", doc, out.path, "--size", "320x200", "--no-loop", "--story-fps", "10"])
        XCTAssertEqual(r.status, 0, r.text)
        let m = try JSONSerialization.jsonObject(with: Data(contentsOf: out.appendingPathComponent("manifest.json"))) as? [String: Any]
        let outputs = m?["outputs"] as? [[String: Any]] ?? []
        let steps = outputs.filter { ($0["file"] as? String)?.hasPrefix("step-") == true }
        XCTAssertEqual(steps.count, 2)
        XCTAssertNil(steps[0]["autoGhost"])
        XCTAssertEqual(steps[1]["autoGhost"] as? [String], ["wall"])
        XCTAssertEqual(steps[1]["occluded"] as? Double, 0)
        XCTAssertEqual(steps[1]["view"] as? String, "preset")
        XCTAssertEqual(steps[1]["offView"] as? Int, 0)
        XCTAssertGreaterThan(steps[1]["focusSamples"] as? Int ?? 0, 0)
        let beats = try XCTUnwrap(outputs.first { $0["file"] as? String == "story.mp4" }?["beats"] as? [[String: Any]])
        XCTAssertEqual(beats[1]["autoGhost"] as? [String], ["wall"])
        XCTAssertEqual(beats.map { $0["cut"] as? Bool }, [false, false])
        XCTAssertEqual(try XCTUnwrap(beats[1]["camera"] as? NSDictionary), try XCTUnwrap(steps[1]["camera"] as? NSDictionary))
    }

    // The legend counts every 2D item a presented beat showed, also when a later beat removes it: the same legend and
    // claim order (first-shown order) in 10 fresh processes, and the same legend in the render manifest.
    func testLegendCountsRemovedItemsInEveryProcess() throws {
        let table = { (id: String) in #"{"op":"add","item":{"id":"\#(id)","k":"table","at":[6,4],"header":true,"cells":[["Planet","km"],["Earth",12756]]}}"# }
        let doc = try write(#"{"v":1,"kind":"explainer","notes":{"zz":{"basis":"Survey data"},"mm":{"unchecked":"from memory"}},"board":{"v":1,"items":[{"id":"keep","k":"text","at":[1,7],"text":"Gears"},{"id":"bb","k":"text","at":[1,1],"text":"Teeth {p.teeth}"}]},"solid":{"v":2,"parts":[{"id":"p","shape":{"gear":{"teeth":15,"module":2,"width":8}},"joint":{"revolute":[0,0,1]},"drive":{"input":1}},{"id":"w","at":[45,0,0],"shape":{"gear":{"teeth":30,"module":2,"width":8}},"joint":{"revolute":[0,0,1]}}],"constraints":[{"gearMesh":{"a":"p","b":"w"}}]},"beats":[{"say":"One.","ops":[\#(table("zz"))]},{"say":"Two.","ops":[\#(table("mm")),{"op":"remove","id":"bb"}]},{"say":"Three.","ops":[{"op":"remove","id":"zz"},{"op":"add","item":{"id":"aa","k":"text","at":[1,2],"text":"Rate {w.speed}"}}]},{"say":"Four.","ops":[{"op":"remove","id":"mm"},{"op":"remove","id":"aa"}]}]}"#, "removed-items.json")
        for _ in 0..<10 {
            let r = try run(["check", doc])
            XCTAssertEqual(r.status, 0, r.text)
            let legend = r.json?["legend"] as? [String: Any]
            XCTAssertEqual(legend?["text"] as? String, "Solved 4 · Given 1 · Not checked 1")
            XCTAssertEqual((legend?["claims"] as? [[String: Any]])?.compactMap { $0["id"] as? String },
                           ["p", "w", "item.bb", "item.zz", "item.mm", "item.aa"])
        }
        // The reported case, rendered: a noted table that beat 1 adds and beat 2 removes stays in the legend line.
        let twoD = try write(#"{"v":1,"kind":"explainer","notes":{"t":{"basis":"Survey data"}},"board":{"v":1,"items":[{"id":"keep","k":"text","at":[1,7],"text":"Planets"}]},"beats":[{"say":"Here are the sizes.","ops":[\#(table("t"))]},{"say":"Now without the table.","ops":[{"op":"remove","id":"t"}]}]}"#, "removed-table.json")
        XCTAssertEqual((try run(["check", twoD]).json?["legend"] as? [String: Any])?["text"] as? String, "Given 1")
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("explainer-render-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: out) }
        let r = try renderOrSkip(["render", twoD, out.path, "--size", "640x400"])
        XCTAssertEqual(r.status, 0, r.text)
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: out.appendingPathComponent("manifest.json"))) as? [String: Any]
        XCTAssertEqual(manifest?["legend"] as? String, "Given 1")
    }

    // N8: three simultaneous id collisions give the same first reason in 20 fresh processes (own hash seeds).
    func testN8CollisionOrderIsTheSameInEveryProcess() throws {
        let doc = try write(#"{"v":1,"kind":"explainer","board":{"v":1,"items":[{"id":"cc","k":"text","at":[1,1],"text":"c"},{"id":"aa","k":"text","at":[2,1],"text":"a"},{"id":"bb","k":"text","at":[3,1],"text":"b"}]},"solid":{"v":2,"parts":[{"id":"bb","shape":{"box":{"size":[1,1,1]}}},{"id":"aa","shape":{"box":{"size":[1,1,1]}}},{"id":"cc","shape":{"box":{"size":[1,1,1]}}}]},"beats":[{"say":"Hi."}]}"#, "collisions.json")
        for _ in 0..<20 {
            let r = try run(["check", doc])
            XCTAssertEqual(r.status, 1)
            XCTAssertEqual(r.json?["reason"] as? String, "explainer.id.duplicate.bb")
        }
    }


    // Review P2-7: restore revalidates beats in beat order, then statement order: the same first reason in 20 fresh
    // processes (each with its own hash seed). `snapshot check` restores an explainer snapshot with every check.
    func testSnapshotCheckOrderIsTheSameInEveryProcess() throws {
        let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")
        let clean = try run(["snapshot", "check", fixtures.appendingPathComponent("explainer-mixed.snapshot.json").path])
        XCTAssertEqual(clean.status, 0, clean.text)
        // Saved at beat 1 with beat 2 queued, before snapshots held `shown`: the legend is presented-only (2 motion
        // claims, the table, beat 1's caption) and the record is the state shown now.
        XCTAssertEqual(clean.json?["legend"] as? String, "Solved 4")
        XCTAssertEqual(clean.json?["caption"] as? String, "Count the teeth: 15 and 30.")
        for _ in 0..<20 {
            let r = try run(["snapshot", "check", fixtures.appendingPathComponent("explainer-two-false-checks.snapshot.json").path])
            XCTAssertEqual(r.status, 1)
            XCTAssertEqual(r.json?["reason"] as? String, "check.failed.p.speed")
        }
        XCTAssertEqual(try run(["snapshot", "check", try write("[", "bad-snapshot.json")]).json?["reason"] as? String, "snapshot.json")
    }

}
