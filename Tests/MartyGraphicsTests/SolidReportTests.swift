// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import MartyGraphics

/// `MGSolidReport` (the `marty-solid check` report as a library API), patch reports, the render plan, the engine identity
/// and the guarded snapshot decoder. The tool's exact bytes are pinned by the golden tests in Examples/Solid3D.
final class SolidReportTests: XCTestCase {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let models = ["planetary", "slider-crank", "propeller", "planetary-components", "slider-crank-component", "horizontal-reduction",
                         "idler-gearbox"]
    static func data(_ name: String) throws -> Data {
        try Data(contentsOf: root.appendingPathComponent("Examples/Solid3D/Sources/MartySolid3D/Models/\(name).json"))
    }
    static func doc(_ json: String) throws -> MGSolidDocument { try MGSolidParser.document(data: Data(json.utf8)).get() }

    static let disc = #"{"v":1,"kind":"assembly","title":"Disc","parts":[{"id":"disc","shape":{"shaft":{"radius":20,"length":5}},"joint":{"revolute":[0,0,1]},"drive":{"input":1}}]}"#

    func testSectionsAddDisjointKeys() throws {
        for name in Self.models {
            let doc = try MGSolidParser.document(data: Self.data(name)).get()
            var seen = Set(MGSolidReport.summary(doc, checks: MGSolidReport.Checks(doc), profile: .standard).keys)
            seen.formUnion(["ok", "reason", "part", "file", "engine", "patch"])
            for s in MGSolidReport.sections {
                let keys = Set(s.fields(doc).keys)
                XCTAssertTrue(keys.isDisjoint(with: seen), "\(name): section \(s.name) repeats \(keys.intersection(seen))")
                seen.formUnion(keys)
            }
        }
    }

    func testEveryExampleReportIsAcceptedAndDeterministic() throws {
        for name in Self.models {
            let a = MGSolidReport.check(data: try Self.data(name)), b = MGSolidReport.check(data: try Self.data(name), profile: .strict)
            XCTAssertTrue(a.ok, name); XCTAssertTrue(b.ok, name)
            XCTAssertEqual(a.text, MGSolidReport.check(data: try Self.data(name)).text, name)
            XCTAssertEqual(a.json["strict"], .bool(false)); XCTAssertEqual(b.json["strict"], .bool(true))
            XCTAssertEqual(a.json["engine"], MGEngine.identity)
            XCTAssertEqual(a.json["file"]?["sha256"], .string(MGSolidSource(data: try Self.data(name)).sha256))
            XCTAssertNil(MGSolidReport.check(data: try Self.data(name), engine: nil).json["engine"])
        }
    }

    func testPartAndMotionTiers() throws {
        let doc = try MGSolidParser.document(data: Self.data("horizontal-reduction")).get()
        let json = MGSolidReport.make(doc).json
        guard case .array(let parts)? = json["partTiers"], case .array(let motions)? = json["motionTiers"] else { return XCTFail("tiers") }
        XCTAssertEqual(parts.count, doc.assembly.parts.count)
        for (p, entry) in zip(doc.assembly.parts, parts) {
            XCTAssertEqual(entry["part"], .string(p.id))
            XCTAssertEqual(entry["tier"], doc.motionTier(p.id).map { .string($0.name) } ?? .null, p.id)
            XCTAssertEqual(entry["motion"] == .string("own"), doc.motionTier(p.id) != nil, p.id)
        }
        XCTAssertEqual(motions.count, doc.claims.filter { $0.kind == .motion }.count)
        let wheel = parts.first { $0["part"] == .string("wheel") }
        XCTAssertEqual(wheel?["tier"], .string("solved")); XCTAssertEqual(wheel?["source"], .string("gearMesh"))
        let collar = parts.first { $0["part"] == .string("collar") }
        XCTAssertEqual(collar?["motion"], .string("rides")); XCTAssertEqual(collar?["ridesOn"], .string("wheel"))
        XCTAssertEqual(collar?["tier"], .null)

        // An input scale other than ±1 is author behaviour (Built); an idle joint has no tier.
        let built = try Self.doc(#"{"v":2,"kind":"assembly","parts":[{"id":"a","shape":{"shaft":{"radius":20,"length":5}},"joint":{"revolute":[0,0,1]},"drive":{"input":2}},{"id":"b","shape":{"shaft":{"radius":5,"length":5}},"joint":{"revolute":[0,0,1]},"at":[60,0,0]}],"steps":[{"say":"A disc."}]}"#)
        let t = MGSolidReport.make(built).json
        guard case .array(let builtParts)? = t["partTiers"] else { return XCTFail("partTiers") }
        XCTAssertEqual(builtParts.map { $0["motion"] }, [.string("own"), .string("idle")])
        XCTAssertEqual(t["motionTiers"], .array([.object(["id": .string("a"), "tier": .string("built"), "badge": .string("Schematic motion"),
                                                          "source": .string("input")])]))
    }

    func testRefusalShapes() {
        let short = MGSolidReport.check(data: Data(count: MGSolidLimits.bytes + 1))
        XCTAssertEqual(short.json, .object(["ok": .bool(false), "reason": .string("assembly.bytes"), "part": .null, "engine": MGEngine.identity]))
        XCTAssertEqual(short.exitCode, 1)
        let bad = MGSolidReport.check(data: Data("{}".utf8), profile: .strict)
        XCTAssertEqual(bad.reason, "assembly.missing.kind,parts,v")
        XCTAssertEqual(bad.json["strict"], .bool(true))
        XCTAssertEqual(bad.json["file"], .object(["lines": .number(1), "sha256": .string("44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a")]))
        let strict = MGSolidReport.check(data: Data(#"{"v":2,"kind":"assembly","parts":[{"id":"disc","shape":{"shaft":{"radius":20,"length":5}},"joint":{"revolute":[0,0,1]}}],"steps":[{"say":"A disc on a joint."}]}"#.utf8), profile: .strict)
        XCTAssertEqual(strict.reason, "joint.idle.disc"); XCTAssertEqual(strict.part, "disc")
        XCTAssertNotNil(strict.json["readBack"], "a refused report still holds every field")
        XCTAssertEqual(MGSolidReport.text(.object(["x": .number(.nan)])), #"{"ok": false, "reason": "report.encoding"}"#)
    }

    func testPatchReport() throws {
        let base = Data(Self.disc.utf8)
        let before = MGSolidReport.check(data: base).text
        let r = MGSolidReport.check(data: base, patch: Data(#"{"title":"Disc","parts":{"disc":{"name":"Big disc"}}}"#.utf8))
        XCTAssertTrue(r.ok)
        XCTAssertEqual(r.json["patch"]?["applied"], .bool(true))
        XCTAssertEqual(r.json["patch"]?["fields"], .array([.string("parts.disc.name"), .string("title")]))
        XCTAssertEqual(r.json["patch"]?["changed"], .array([.string("parts.disc.name")]))
        XCTAssertEqual(r.json["file"], MGSolidSource(data: base).json, "file names the base")
        XCTAssertNotNil(r.json["patch"]?["file"]?["sha256"])
        XCTAssertNil(r.json["patch"]?["refusedAt"])

        let refused = MGSolidReport.check(data: base, patch: Data(#"{"bogus":1}"#.utf8))
        XCTAssertEqual(refused.reason, "patch.unknown.bogus")
        XCTAssertEqual(refused.json["patch"]?["refusedAt"], .string("patch"))
        XCTAssertEqual(refused.json["patch"]?["fields"], .array([.string("bogus")]))
        XCTAssertNil(refused.json["patch"]?["changed"])
        // A refused patch changes nothing: the base checks exactly as before.
        XCTAssertEqual(MGSolidReport.check(data: base).text, before)

        let strict = MGSolidReport.check(data: base, patch: Data(#"{"parts":{"disc":{"drive":null}}}"#.utf8), profile: .strict)
        XCTAssertEqual(strict.reason, "joint.idle.disc")
        XCTAssertEqual(strict.json["patch"]?["applied"], .bool(true), "the patched document compiled; strict refused it")
        XCTAssertEqual(strict.json["patch"]?["changed"], .array([.string("parts.disc.drive")]))

        XCTAssertEqual(MGSolidReport.check(data: Data("nope".utf8), patch: Data("{}".utf8)).json["patch"]?["refusedAt"], .string("base"))
        let cases: [(Data, String)] = [
            (Data(count: MGSolidLimits.bytes + 1), "patch.bytes"), (Data([0xff, 0xfe]), "patch.json"), (Data("{".utf8), "patch.json"),
            (Data((String(repeating: "[", count: 65) + String(repeating: "]", count: 65)).utf8), "patch.depth"),
            (Data("[]".utf8), "patch.object"), (Data("{}".utf8), "patch.unknown."),
        ]
        let doc = try Self.doc(Self.disc)
        for (patch, reason) in cases {
            XCTAssertEqual(MGSolidReport.check(data: base, patch: patch).reason, reason)
            guard case .failure(let e) = MGSolidParser.applying(data: patch, to: doc) else { XCTFail(reason); continue }
            XCTAssertEqual(e.reason, reason)
            XCTAssertNotNil(MGSolidReasons.lookup(reason), reason)
        }
        XCTAssertNil(MGSolidReport.check(data: base, patch: Data(count: MGSolidLimits.bytes + 1)).json["patch"]?["file"])
        // A component part edit reads and writes the `use` entry's `set`.
        let comp = try MGSolidParser.document(data: Self.data("slider-crank-component")).get()
        let id = comp.assembly.parts.first { $0.id.contains(".") }!.id
        let edit = MGSolidReport.check(data: try Self.data("slider-crank-component"),
                                       patch: Data(#"{"parts":{"\#(id)":{"material":"brass"}}}"#.utf8))
        XCTAssertEqual(edit.json["patch"]?["changed"], .array([.string("parts.\(id).material")]), edit.text)
    }

    func testSourceFacts() {
        XCTAssertEqual(MGSHA256.hex(Data()), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertEqual(MGSHA256.hex(Data("abc".utf8)), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(MGSHA256.hex(Data("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".utf8)),
                       "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
        XCTAssertEqual(MGSHA256.hex(Data(repeating: 0x61, count: 1_000)), "41edece42d63e8d9bf515a9ba6932e1c20cbc9f5a5d134645adb5db1b9737ea3")
        XCTAssertEqual(MGSolidSource(data: Data("a\nb\n".utf8)).lines, 2)
        XCTAssertEqual(MGSolidSource(data: Data("a\nb".utf8)).lines, 2)
        XCTAssertEqual(MGSolidSource(data: Data("{}".utf8)).sizeText, "2 bytes on one line")
        XCTAssertEqual(MGSolidSource(data: Data("{\n}\n".utf8)).sizeText, "2 lines")
    }

    func testEngineIdentityMatchesTheChangelog() throws {
        let changelog = try String(contentsOf: Self.root.appendingPathComponent("CHANGELOG.md"), encoding: .utf8)
        let heading = changelog.split(separator: "\n").first { $0.hasPrefix("## ") }.map { String($0.dropFirst(3)) }
        XCTAssertEqual(heading?.lowercased(), MGEngine.version.lowercased())
        XCTAssertEqual(MGEngine.identity["name"], .string("MartyGraphics"))
        XCTAssertEqual(MGEngine.identity["reportFormat"], .number(1))
    }

    func testRenderPlan() throws {
        let data = try Self.data("idler-gearbox")
        let doc = try MGSolidParser.document(data: data).get()
        let plan = MGSolidRenderPlan(doc, sourceName: "idler-gearbox.json", source: MGSolidSource(data: data))
        XCTAssertEqual(plan.stills.map(\.file), ["hero.png", "exploded.png"] + doc.steps.indices.map { "step-\($0 + 1).png" })
        XCTAssertEqual(plan.stills[1].title, doc.title + " · exploded")
        XCTAssertEqual(plan.stills[2].caption, "1. " + doc.steps[0].say)
        XCTAssertEqual(plan.stills[2].step, 0)
        XCTAssertEqual(plan.footer, "Rendered by the MartyGraphics solid engine from idler-gearbox.json (\(MGSolidSource(data: data).lines) lines)")
        XCTAssertEqual(plan.loop.count, 120)
        XCTAssertEqual(plan.loop[0].params, MGPoseParameters(input: doc.defaults.input, explode: 0))
        XCTAssertEqual(plan.loop[78].params.explode, 1, accuracy: 1e-12)
        XCTAssertEqual(plan.loop[60].orbit, 180)
        XCTAssertTrue(MGSolidRenderPlan(doc, sourceName: "x", source: MGSolidSource(data: data), loop: false).loop.isEmpty)
        XCTAssertEqual(MGSolidRenderPlan.snapshot(doc).format, MGSolidSnapshot.formatV2)
        let manifest = try MGSolidRenderPlan.manifest(doc, sourceName: "idler-gearbox.json", source: MGSolidSource(data: data), framesRendered: 2,
                                                  secondsPerFrame: 0.5, outputs: [])
        XCTAssertEqual(manifest["checks"], MGSolidReport.Checks(doc).json)
        XCTAssertEqual(manifest["engine"], MGEngine.identity)
    }
}

/// Every public `MGSolidReport` and `MGSolidRenderPlan` entry point on a 512 KiB stack (an iOS secondary thread), with
/// hostile values retained in static storage (`Deep`), so Swift's recursive destruction is not what is tested.
final class SolidReportSmallStackTests: XCTestCase {
    static let deepEngine = Deep.value(MGSolidReport.engineDepth + 1, .objects)

    func testEntryPointsRefuseHostileValuesFirst() throws {
        let base = Data(SolidReportTests.disc.utf8)
        let doc = try MGSolidParser.document(data: base).get()
        let deepText = Data(Deep.text(30_000, .arrays).utf8)   // 60,001 bytes: under the size cap, far over the depth cap
        let results = onSmallStack { () -> [String?] in
            var out: [String?] = []
            for engine in [Deep.hostile, Deep.hostileObject, SolidReportSmallStackTests.deepEngine, MGJSON.number(.infinity)] {
                out.append(MGSolidReport.text(engine).hasPrefix(#"{"ok": false, "reason": "report.encoding"}"#) ? "refused" : "encoded")
                out.append(MGSolidReport.check(data: base, engine: engine).reason)
                out.append(MGSolidReport.check(data: base, patch: Data("{}".utf8), engine: engine).reason)
                out.append(MGSolidReport.make(doc, engine: engine).reason)
                out.append(MGSolidReport.refused(MGSolidIssue("json"), engine: engine).text)
                do { _ = try MGSolidRenderPlan.manifest(doc, sourceName: "x", source: MGSolidSource(data: base), framesRendered: 0,
                                                        secondsPerFrame: 0, outputs: [], engine: engine); out.append(nil) }
                catch { out.append((error as? MGSolidIssue)?.reason) }
            }
            do { _ = try MGSolidRenderPlan.manifest(doc, sourceName: "x", source: MGSolidSource(data: base), framesRendered: 0,
                                                    secondsPerFrame: 0, outputs: [Deep.hostile]); out.append(nil) }
            catch { out.append((error as? MGSolidIssue)?.reason) }
            // Deep document and patch text are refused by the parsers' own guards; the reports encode.
            let deepDoc = MGSolidReport.check(data: deepText)
            out.append(deepDoc.reason); out.append(deepDoc.text.contains("assembly.depth") ? "encoded" : deepDoc.text)
            let deepPatch = MGSolidReport.check(data: base, patch: deepText)
            out.append(deepPatch.reason); out.append(deepPatch.text.contains("patch.depth") ? "encoded" : deepPatch.text)
            let ok = MGSolidReport.check(data: base)
            out.append(ok.text.hasPrefix("{\n") ? "encoded" : ok.text)
            return out
        }
        let engineRefused = MGSolidReport.engineRefusal.text
        var want: [String?] = []
        // `text` encodes any finite value up to `MGLimits.depth`; the 9-level engine is refused only as an engine.
        for textResult in ["refused", "refused", "encoded", "refused"] {
            want += [textResult, "report.engine", "report.engine", "report.engine", engineRefused, "report.engine"]
        }
        want += ["report.encoding", "assembly.depth", "encoded", "patch.depth", "encoded", "encoded"]
        XCTAssertEqual(results, want)
        XCTAssertEqual(MGSolidReport.engineRefusal.json["engine"], nil)
    }

    /// The report's own nesting: author ids and strings cannot add levels.
    func testReportDepthIsBounded() throws {
        for name in SolidReportTests.models {
            let data = try SolidReportTests.data(name)
            XCTAssertLessThanOrEqual(MGSolidReport.check(data: data, engine: nil).json.measure().depth, 6, name)
            XCTAssertLessThanOrEqual(MGSolidReport.check(data: data, patch: Data(#"{"title":"T"}"#.utf8), engine: nil).json.measure().depth, 6, name)
            XCTAssertLessThanOrEqual(MGSolidReport.check(data: data).json.measure().depth, max(6, 1 + MGEngine.identity.measure().depth), name)
        }
        let maxEngine = Deep.value(MGSolidReport.engineDepth, .arrays)
        let r = MGSolidReport.check(data: Data(SolidReportTests.disc.utf8), engine: maxEngine)
        XCTAssertTrue(r.ok)
        XCTAssertEqual(r.json.measure().depth, 1 + MGSolidReport.engineDepth)
    }
}

/// `MGSolidSnapshot.decode(data:)`: the #28 guard (UTF-8 only, 64 levels, finite numbers) runs before `JSONDecoder`.
final class SolidSnapshotDecodeTests: XCTestCase {
    static func snapshot() throws -> Data {
        let doc = try MGSolidParser.document(data: Data(SolidReportTests.disc.utf8)).get()
        return try MGSolidSnapshot.make(doc.assembly, params: doc.defaults).jsonData()
    }
    static func reason(_ data: Data) -> String? {
        do { _ = try MGSolidSnapshot.decode(data: data); return nil } catch { return (error as? MGSolidIssue)?.reason ?? "\(error)" }
    }

    func testRoundTripAndRefusals() throws {
        let data = try Self.snapshot()
        XCTAssertNil(Self.reason(data))
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains(#""aspect":1.6"#), "the replacements below need this field")
        // The encoder may escape the slash in the format name; replace either spelling.
        let unknownFormat = text.replacingOccurrences(of: #"snapshot\/1""#, with: #"snapshot\/9""#)
            .replacingOccurrences(of: #"snapshot/1""#, with: #"snapshot/9""#)
        XCTAssertNotEqual(unknownFormat, text)
        let cases: [(Data, String)] = [
            (Data(text.utf16.flatMap { [UInt8($0 & 0xff), UInt8($0 >> 8)] }), "solidSnapshot.json"),
            (Data([0xff]) + data, "solidSnapshot.json"),
            (Data((String(repeating: "[", count: 65) + "0" + String(repeating: "]", count: 65)).utf8), "solidSnapshot.depth"),
            (Data(text.replacingOccurrences(of: #""aspect":1.6"#, with: #""aspect":1e999"#).utf8), "solidSnapshot.number"),
            (Data(text.replacingOccurrences(of: #""aspect":1.6"#, with: #""aspect":-1e400"#).utf8), "solidSnapshot.number"),
            (Data(text.replacingOccurrences(of: #""aspect":1.6"#, with: #""aspect":1."# + String(repeating: "6", count: 70)).utf8), "solidSnapshot.number"),
            (Data(text.replacingOccurrences(of: #""aspect":1.6"#, with: #""aspect":NaN"#).utf8), "solidSnapshot.invalid"),
            (Data(text.replacingOccurrences(of: #""aspect":1.6"#, with: #""aspect":-2"#).utf8), "solidSnapshot.invalid"),
            (Data(unknownFormat.utf8), "solidSnapshot.invalid"),
            (Data("[]".utf8), "solidSnapshot.invalid"),
        ]
        for (k, (d, want)) in cases.enumerated() { XCTAssertEqual(Self.reason(d), want, "case \(k)") }
        // Numbers inside strings, and `true` / `false` / `null`, are not number literals.
        XCTAssertNil(MGSolidSnapshot.guardRefusal(Data(#"{"a":"1e999","b":true,"c":false,"d":null,"e":-0.5e-3}"#.utf8)))
        for r in ["solidSnapshot.json", "solidSnapshot.depth", "solidSnapshot.number", "solidSnapshot.invalid", "solidSnapshot.bytes"] {
            XCTAssertEqual(MGSolidReasons.lookup(r)?.formats, [.snapshot], r)
        }
    }

    /// On a 512 KiB stack (an iOS secondary thread): a real snapshot decodes, text at the cap reaches the decoder, and
    /// deeper text (also 100,000 levels) is refused before it.
    func testDecodeOnASmallStack() throws {
        let data = try Self.snapshot()
        let results = onSmallStack { () -> [String?] in
            let reason = SolidSnapshotDecodeTests.reason
            var out: [String?] = [reason(data)]
            for shape in Deep.Shape.allCases {
                out.append(reason(Data(Deep.text(Deep.cap, shape).utf8)))
                out.append(reason(Data(Deep.text(Deep.cap + 1, shape).utf8)))
                out.append(reason(Data(Deep.text(100_000, shape).utf8)))
            }
            return out
        }
        XCTAssertEqual(results, [nil] + Array(repeating: ["solidSnapshot.invalid", "solidSnapshot.depth", "solidSnapshot.depth"], count: 2).flatMap { $0 })
    }
}
