// SPDX-License-Identifier: Apache-2.0
import XCTest
@testable import MartyGraphics

/// Blade rows, capped partial revolves and the turbomachinery material presets.
final class SolidTurboTests: XCTestCase {
    func assertClosed(_ m: MGMesh, _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        let r = m.edgeReport
        XCTAssertTrue(r.isClosed, "\(what): \(r)", file: file, line: line)
        XCTAssertEqual(r.degenerateTriangles, 0, what, file: file, line: line)
        XCTAssertGreaterThan(m.signedVolume, 0, "\(what) winds outward", file: file, line: line)
    }

    func testBladeRowIsClosedAndSectionsLieOnCylinders() {
        let row = MGMesh.bladeRow(count: 12, span: 60, chord: 30, root: 100, z: 5, thickness: 0.1, stagger: 0.6, twist: 0.3,
                                  tipChord: 24, camber: -0.04, sections: 6, chordSamples: 12)
        assertClosed(row, "blade row")
        XCTAssertEqual(row.triangleCount, 12 * (6 * 4 * 12 + 2 * (2 * 12 - 2)))
        let radii = row.positions.map { ($0.x * $0.x + $0.y * $0.y).squareRoot() }
        XCTAssertEqual(radii.min()!, 100, accuracy: 1e-9)
        XCTAssertEqual(radii.max()!, 160, accuracy: 1e-9)
        // Every vertex sits on one of the seven section cylinders.
        for r in radii { XCTAssertLessThan(abs((r - 100) / 10 - ((r - 100) / 10).rounded()), 1e-9) }
        // One blade: positive stagger puts the trailing edge (max z) at negative tangential angle (-θ).
        let one = MGMesh.bladeRow(count: 2, span: 60, chord: 30, root: 100, stagger: 0.6, sections: 2, chordSamples: 8)
        let first = one.positions.prefix(one.positions.count / 2)
        let te = first.max { $0.z < $1.z }!, le = first.min { $0.z < $1.z }!
        XCTAssertLessThan(atan2(te.y, te.x), atan2(le.y, le.x))
        XCTAssertEqual(te.z - le.z, 30 * cos(0.6), accuracy: 1.5)
    }

    func testPartialRevolveCapsBothCutFaces() {
        let wall: [MGVec2] = [MGVec2(100, 0), MGVec2(110, 0), MGVec2(115, 40), MGVec2(104, 40)]
        let cut = MGMesh.revolve(wall, segments: 96, closed: true, sweep: 1.5 * .pi, start: .pi)
        assertClosed(cut, "cut wall")
        let full = MGMesh.revolve(wall, segments: 96, closed: true)
        XCTAssertEqual(cut.signedVolume, 0.75 * full.signedVolume, accuracy: 0.01 * full.signedVolume)
        let cone: [MGVec2] = [MGVec2(0, 0), MGVec2(50, 10), MGVec2(30, 60), MGVec2(0, 70)]
        let openCut = MGMesh.revolve(cone, segments: 64, closed: false, sweep: .pi / 2, start: 0.3)
        assertClosed(openCut, "cut cone")
        // No vertex lies in the removed sector.
        for p in cut.positions where p.x * p.x + p.y * p.y > 1 {
            var a = atan2(p.y, p.x); if a < 0 { a += 2 * .pi }
            XCTAssertTrue(a >= .pi - 1e-9 || a <= 0.5 * .pi + 1e-9, "vertex at \(a)")
        }
        XCTAssertEqual(MGMesh.revolve(wall, segments: 96, closed: true, sweep: 2 * .pi), full)
    }

    func doc(_ shape: MGJSON, material: String = "titanium") -> Result<MGSolidDocument, MGSolidIssue> {
        MGSolidParser.document(json: .object(["v": .number(1), "kind": .string("assembly"), "parts": .array([
            .object(["id": .string("row"), "material": .string(material), "shape": shape])])]))
    }

    func row(_ fields: [String: MGJSON]) -> MGJSON {
        var f: [String: MGJSON] = ["count": .number(24), "span": .number(80), "chord": .number(40), "root": .number(200),
                                   "stagger": .number(35), "twist": .number(15), "camber": .number(-0.03)]
        for (k, v) in fields { f[k] = v }
        return .object(["bladeRow": .object(f)])
    }

    func reason(_ r: Result<MGSolidDocument, MGSolidIssue>) -> String? {
        if case .failure(let e) = r { return e.reason }
        return nil
    }

    func testBladeRowFormatParsesAndRejectsWithStableReasons() throws {
        let d = try doc(row([:])).get()
        XCTAssertTrue(d.assembly.parts[0].mesh.edgeReport.isClosed)
        XCTAssertEqual(d.assembly.parts[0].material, .titanium)
        XCTAssertEqual(reason(doc(row(["count": .number(1)]))), "part.bladeRow.count")
        XCTAssertEqual(reason(doc(row(["count": .number(12.5)]))), "part.bladeRow.count")
        XCTAssertEqual(reason(doc(row(["stagger": .number(70), "twist": .number(20)]))), "part.bladeRow.twist")
        XCTAssertEqual(reason(doc(row(["camber": .number(0.2)]))), "part.bladeRow.camber")
        XCTAssertEqual(reason(doc(row(["sections": .number(40)]))), "part.bladeRow.sections")
        XCTAssertEqual(reason(doc(row(["bogus": .number(1)]))), "part.bladeRow.unknown.bogus")
        // 128 thick, unstaggered blades on a 200 mm hub would overlap their neighbours.
        XCTAssertEqual(reason(doc(row(["count": .number(128), "stagger": .number(0), "twist": .number(0), "thickness": .number(0.35)]))),
                       "part.bladeRow.count")
        XCTAssertEqual(reason(doc(row(["count": .number(128), "sections": .number(24), "chordSamples": .number(32)]))),
                       "part.bladeRow.triangles")
        XCTAssertEqual(reason(doc(.object(["revolvedProfile": .object(["points": .array([.array([.number(10), .number(0)]),
                                                                                         .array([.number(20), .number(0)]),
                                                                                         .array([.number(20), .number(10)])]),
                                                                          "closed": .bool(true), "sweep": .number(400)])]))),
                       "part.revolvedProfile.sweep")
        XCTAssertEqual(reason(doc(row([:]), material: "unobtainium")), "part.material")
    }

    func testSweepSegmentsAreExactForWholeFractions() {
        XCTAssertEqual(MGMesh.sweepSegments(96, sweep: 210 * .pi / 180), 56)
        XCTAssertEqual(MGMesh.sweepSegments(96, sweep: 270 * .pi / 180), 72)
        XCTAssertEqual(MGMesh.sweepSegments(96, sweep: 100 * .pi / 180), 27)
        XCTAssertEqual(MGMesh.sweepSegments(96, sweep: 1 * .pi / 180), 2)
    }

    func testSnapshotWithTurboMaterialsRoundTripsThroughTheDecoder() throws {
        let parts: [MGJSON] = ["titanium", "nickelAlloy", "composite", "ceramic"].enumerated().map { k, m in
            .object(["id": .string("p\(k)"), "material": .string(m), "at": .array([.number(Double(k) * 30), .number(0), .number(0)]),
                     "shape": .object(["shaft": .object(["radius": .number(10), "length": .number(20)])])])
        }
        let d = try MGSolidParser.document(json: .object(["v": .number(1), "kind": .string("assembly"), "parts": .array(parts)])).get()
        let snap = MGSolidSnapshot.make(d.assembly, params: MGPoseParameters())
        let back = try JSONDecoder().decode(MGSolidSnapshot.self, from: snap.jsonData())
        XCTAssertEqual(back, snap)
        XCTAssertEqual(back.materials.map(\.id), ["titanium", "nickelAlloy", "composite", "ceramic"])
    }

    func testTurboMaterialPresetsHaveStableIDs() {
        for (preset, id) in [(MGMaterialPreset.titanium, "titanium"), (.nickelAlloy, "nickelAlloy"), (.composite, "composite"), (.ceramic, "ceramic")] {
            XCTAssertEqual(preset.id, id)
            let p = preset.parameters
            XCTAssertEqual(p.baseColor.count, 3)
            XCTAssertTrue((0...1).contains(p.roughness))
        }
        XCTAssertEqual(MGMaterialPreset.titanium.parameters.metallic, 1)
        XCTAssertEqual(MGMaterialPreset.composite.parameters.metallic, 0)
    }
}
