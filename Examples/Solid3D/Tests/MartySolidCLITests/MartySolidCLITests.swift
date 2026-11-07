// SPDX-License-Identifier: Apache-2.0
import Foundation
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
        XCTAssertEqual((catalog.json?["components"] as? [Any])?.count, 7)
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
    static let added: Set<String> = ["engine", "partTiers", "motionTiers"]

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
                               "loop.gif", "manifest.json"])
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: out.appendingPathComponent("manifest.json"))) as? [String: Any]
        XCTAssertEqual(manifest?["legend"] as? String, "Solved 6")
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
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: out.path)), ["board-0.png", "beat-1.png", "manifest.json"])
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

}
