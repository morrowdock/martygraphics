// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
import CryptoKit
import SceneKit
@testable import MartyGraphics

/// Capped plane cuts, step `section` and `ghost`, part `opacity` and `emissive`, and snapshot v2 (open-vocabulary
/// phase 1, row 2). Ids refer to PHASE1-ACCEPTANCE.md (V, X, G).
final class SolidSectionTests: XCTestCase {
    func parse(_ text: String, profile: MGSolidProfile = .standard) -> Result<MGSolidDocument, MGSolidIssue> {
        MGSolidParser.document(data: Data(text.utf8), profile: profile)
    }
    func doc(_ text: String, file: StaticString = #filePath, line: UInt = #line) throws -> MGSolidDocument {
        switch parse(text) {
        case .success(let d): return d
        case .failure(let e): XCTFail("refused: \(e)", file: file, line: line); throw e
        }
    }
    func reason(_ text: String) -> String? {
        if case .failure(let e) = parse(text) { return e.reason }
        return nil
    }
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    func model(_ name: String) throws -> MGSolidDocument {
        let data = try Data(contentsOf: Self.root.appendingPathComponent("Examples/Solid3D/Sources/MartySolid3D/Models/\(name).json"))
        switch MGSolidParser.document(data: data) {
        case .success(let d): return d
        case .failure(let e): XCTFail("\(name): \(e)"); throw e
        }
    }

    /// A v2 document with a casing tube, a gear inside it and the given steps (JSON array body).
    func casing(_ steps: String, casingExtra: String = "", v: Int = 2) -> String {
        #"{"v": \#(v), "kind": "assembly", "parts": [{"id": "casing", "material": "aluminum", "shape": {"tube": {"inner": 30, "outer": 34, "length": 30, "z0": -15}}\#(casingExtra)}, {"id": "gear", "shape": {"gear": {"teeth": 20, "module": 2, "width": 10, "z0": -5}}, "joint": {"revolute": [0, 0, 1]}, "drive": {"input": 1}}], "steps": [\#(steps)]}"#
    }
    let cut = #""section": {"normal": [1, 0, 0], "offset": 0, "parts": ["casing"]}"#

    /// Cap triangle areas summed (each triangle's own area): equal to the cap area exactly when no two caps overlap.
    func capTriangleArea(_ c: MGSectionCut) -> Double {
        (c.capFirstTriangle..<(c.capFirstTriangle + c.capTriangleCount)).reduce(0) { $0 + c.mesh.faceNormal($1).length / 2 }
    }
    func assertSound(_ c: MGSectionCut, _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        let report = c.mesh.edgeReport
        XCTAssertTrue(c.isSound, what, file: file, line: line)
        XCTAssertTrue(report.isClosed, "\(what): \(report)", file: file, line: line)
        XCTAssertGreaterThan(c.mesh.signedVolume, 0, what, file: file, line: line)
        XCTAssertEqual(capTriangleArea(c), c.capArea, accuracy: 1e-6 * max(1, c.capArea), "\(what): caps overlap", file: file, line: line)
        // Every cap vertex lies on the plane; nothing kept lies beyond it.
        for i in c.mesh.indices[(3 * c.capFirstTriangle)...] {
            XCTAssertEqual(c.plane.distance(c.mesh.positions[Int(i)]), 0, accuracy: 1e-6, what, file: file, line: line)
        }
        let eps = 1e-6 * max(1, c.mesh.bounds.radius)
        XCTAssertTrue(c.mesh.positions.allSatisfy { c.plane.distance($0) <= eps }, what, file: file, line: line)
    }

    // MARK: X1, X2: capped cuts

    func testTubeCutInHalfIsClosedWithTheExactHalfVolume() throws {
        let d = try doc(#"{"v": 2, "kind": "assembly", "parts": [{"id": "t", "shape": {"tube": {"inner": 10, "outer": 20, "length": 50}}}], "steps": [{"say": "Half.", "section": {"normal": [1, 0, 0], "offset": 0, "parts": ["t"]}}]}"#)
        let mesh = d.assembly.part("t")!.mesh
        let c = try XCTUnwrap(d.steps[0].section?.cuts["t"])
        assertSound(c, "tube")
        // The tube is a regular polygon prism; x = 0 passes through two of its vertices (snapped onto the plane).
        let n = Double(mesh.positions.filter { abs($0.z) < 1e-9 && abs($0.x * $0.x + $0.y * $0.y - 400) < 1e-6 }.count)
        let polygonFactor = n / (2 * .pi) * sin(2 * .pi / n)
        XCTAssertEqual(c.mesh.signedVolume, mesh.signedVolume / 2, accuracy: 1e-9 * mesh.signedVolume)
        XCTAssertEqual(c.mesh.signedVolume, 23_561.9 * polygonFactor, accuracy: 0.01 * 23_561.9)          // X1
        XCTAssertEqual(c.loops, 2)                       // two wall sections of the tube
        XCTAssertEqual(c.capArea, 2 * 10 * 50, accuracy: 1e-6)
    }

    func testEveryPlanetaryPartCutAtTheGearMidPlaneAndThroughTheAxis() throws {
        let d = try model("planetary")
        let world = d.pose(MGPoseParameters()).world
        var cutParts = 0
        for plane in [MGSectionPlane(normal: .unitZ, offset: 7), MGSectionPlane(normal: MGVec3(1, 0.3, 0), offset: 0)] {
            for p in d.assembly.parts {
                let local = plane.local(world[p.id] ?? .identity)
                guard MGSolidSection.crossing(p.mesh, local) == .cuts else { continue }
                let c = try MGSolidSection.cut(p.mesh, local)
                assertSound(c, p.id)                                                                       // X2
                let e = try MGSolidSection.estimate(p.mesh, local)
                XCTAssertEqual(e.triangles, c.mesh.triangleCount, p.id)
                XCTAssertEqual(e.vertices, c.mesh.positions.count, p.id)
                cutParts += 1
            }
        }
        XCTAssertGreaterThan(cutParts, 12)
    }

    /// G1-style property: the pre-pass count equals the built counts, and the two halves of any cut add up to the
    /// whole volume, on many planes through every primitive kind (vertex-snapping planes included).
    func testEstimateIsExactAndHalvesAddUpOnRandomPlanes() throws {
        let d = try doc(#"{"v": 2, "kind": "assembly", "parts": [{"id": "s", "shape": [{"gear": {"teeth": 17, "module": 1.5, "width": 8, "bore": 3, "keyway": [1.5, 1]}}, {"shaft": {"radius": 3, "length": 30}}, {"tube": {"inner": 5, "outer": 8, "length": 4, "z0": 20, "chamfer": 0.5}}, {"box": {"size": [10, 6, 4], "chamfer": 0.8, "at": [30, 0, 0]}}, {"hex": {"acrossFlats": 8, "length": 5, "z0": -8}}, {"plate": {"radius": 14, "thickness": 2, "z0": -12, "holes": [[6, 0, 2], [-6, 0, 2]]}}, {"revolvedProfile": {"points": [[8, -20], [12, -20], [12, -14], [8, -14]], "closed": true, "sweep": 270}}]}, {"id": "r", "shape": {"ringGear": {"teeth": 60, "module": 1, "width": 6, "outer": 36, "z0": 10}}}]}"#)
        for id in ["s", "r"] { try checkRandomPlanes(d.assembly.part(id)!.mesh, id) }
    }

    func checkRandomPlanes(_ mesh: MGMesh, _ id: String) throws {
        let whole = mesh.signedVolume
        var seed: UInt64 = 0x5EC7_10A5
        func rnd() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 11) / Double(1 << 53) }
        var planes: [MGSectionPlane] = [MGSectionPlane(normal: .unitX, offset: 0), MGSectionPlane(normal: .unitY, offset: 0),
                                        MGSectionPlane(normal: .unitZ, offset: 0), MGSectionPlane(normal: .unitZ, offset: 10),
                                        MGSectionPlane(normal: MGVec3(1, 1, 0), offset: 0)]
        for _ in 0..<40 {
            planes.append(MGSectionPlane(normal: MGVec3(rnd() - 0.5, rnd() - 0.5, rnd() - 0.5), offset: (rnd() - 0.5) * 30))
        }
        for (k, plane) in planes.enumerated() {
            let flipped = MGSectionPlane(normal: -plane.normal, offset: -plane.offset)
            guard MGSolidSection.crossing(mesh, plane) == .cuts else { continue }
            let a = try MGSolidSection.cut(mesh, plane), b = try MGSolidSection.cut(mesh, flipped)
            for c in [a, b] {
                assertSound(c, "\(id) plane \(k)")
                let e = try MGSolidSection.estimate(mesh, c.plane)
                XCTAssertEqual(e.triangles, c.mesh.triangleCount, "\(id) plane \(k)")
                XCTAssertEqual(e.vertices, c.mesh.positions.count, "\(id) plane \(k)")
            }
            XCTAssertEqual(a.mesh.signedVolume + b.mesh.signedVolume, whole, accuracy: 1e-7 * whole, "\(id) plane \(k)")
            XCTAssertEqual(a.capArea, b.capArea, accuracy: 1e-7 * max(1, a.capArea), "\(id) plane \(k)")
        }
    }

    /// Review B1: two outer loops and two holes in one shell (a thin-rim pulley, a double-wall cup). Each hole goes to
    /// the smallest containing outer loop by its own area, whatever the order of the profile points.
    func testNestedLoopsInOneShellForEveryPointOrder() throws {
        let profiles: [(String, [[Double]], Double)] = [
            ("pulley", [[8, 0], [42, 0], [42, 20], [40, 20], [40, 2], [15, 2], [15, 20], [8, 20]],
             Double.pi * (42 * 42 - 40 * 40 + 15 * 15 - 8 * 8)),
            ("cup", [[4, 0], [10, 0], [10, 20], [9, 20], [9, 2], [5, 2], [5, 20], [4, 20]],
             Double.pi * (10 * 10 - 9 * 9 + 5 * 5 - 4 * 4)),
        ]
        for (name, points, circleArea) in profiles {
            for r in 0..<points.count {
                let rotated = Array(points[r...] + points[..<r])
                let json = #"{"v": 2, "kind": "assembly", "parts": [{"id": "p", "shape": {"revolvedProfile": {"points": \#(rotated), "closed": true}}}], "steps": [{"say": "a", "section": {"normal": [0, 0, 1], "offset": 10, "parts": ["p"]}}]}"#
                let d = try doc(json)
                let c = try XCTUnwrap(d.steps[0].section?.cuts["p"])
                assertSound(c, "\(name) rotation \(r)")
                XCTAssertEqual(c.loops, 4, "\(name) rotation \(r)")
                // Two annuli of 96-gons: the polygon factor of the 96-segment revolve.
                XCTAssertEqual(c.capArea, circleArea * 96 / (2 * .pi) * sin(2 * .pi / 96), accuracy: 1e-6 * circleArea, "\(name) rotation \(r)")
            }
        }
    }

    /// Review S1: a plane through an inner-rim vertex of a tube makes the bore loop touch the outer loop; it is split
    /// and spliced, not refused. A cavity (an inverted inner shell) is capped as a hole of the outer shell.
    func testPinchedLoopsAndCavities() throws {
        for (normal, offset) in [("[-1, 0, 1]", 15.0), ("[1, 0, -1]", -15.0), ("[-1, 0, 1]", 15.001), ("[0, -1, 1]", 15.0)] {
            let d = try doc(#"{"v": 2, "kind": "assembly", "parts": [{"id": "t", "shape": {"tube": {"inner": 10, "outer": 20, "length": 50, "z0": -25}}}], "steps": [{"say": "a", "section": {"normal": \#(normal), "offset": \#(offset), "parts": ["t"]}}]}"#)
            let c = try XCTUnwrap(d.steps[0].section?.cuts["t"])
            assertSound(c, "tube \(normal) \(offset)")
            let e = try MGSolidSection.estimate(d.assembly.part("t")!.mesh, c.plane)
            XCTAssertEqual(e.triangles, c.mesh.triangleCount)
            XCTAssertEqual(e.vertices, c.mesh.positions.count)
        }
        var shell = MGMesh.chamferedBox(size: MGVec3(6, 6, 6), chamfer: 0)
        var cavity = MGMesh.chamferedBox(size: MGVec3(4, 4, 4), chamfer: 0)
        for t in 0..<cavity.triangleCount { cavity.indices.swapAt(3 * t + 1, 3 * t + 2) }
        shell.append(cavity)
        shell.append(MGMesh.chamferedBox(size: MGVec3(2, 2, 2), chamfer: 0))
        let c = try MGSolidSection.cut(shell, MGSectionPlane(normal: .unitX, offset: 0))
        assertSound(c, "cavity")
        XCTAssertEqual(c.capArea, 36 - 16 + 4, accuracy: 1e-9)
        XCTAssertEqual(c.mesh.signedVolume, (216 - 64 + 8) / 2.0, accuracy: 1e-9)
    }

    /// Review S2: large caps (a 200-tooth gear without a bore, cut across its face and obliquely) are triangulated by
    /// the grid ear clipper with exact counts.
    func testLargeCapsAreExactAndSound() throws {
        let d = try doc(#"{"v": 2, "kind": "assembly", "parts": [{"id": "g", "shape": {"gear": {"teeth": 200, "module": 1, "width": 10, "z0": -5}}}], "steps": [{"say": "a", "section": {"normal": [0, 0, 1], "offset": 0, "parts": ["g"]}}, {"say": "b", "section": {"normal": [0.02, 0.01, 1], "offset": 0.5, "parts": ["g"]}}, {"say": "c", "section": {"normal": [1, 0.2, 0], "offset": 30, "parts": ["g"]}}]}"#)
        let mesh = d.assembly.part("g")!.mesh
        for (i, s) in d.steps.enumerated() {
            let c = try XCTUnwrap(s.section?.cuts["g"])
            assertSound(c, "step \(i + 1)")
            let e = try MGSolidSection.estimate(mesh, c.plane)
            XCTAssertEqual(e.triangles, c.mesh.triangleCount)
        }
        let face = try XCTUnwrap(d.steps[0].section?.cuts["g"])
        XCTAssertGreaterThan(face.capTriangleCount, 10_000)
    }

    /// Second review R1: a "labyrinth" revolve (many concentric fins in one shell) caps every annulus correctly, and the
    /// hole-to-outer search charges work proportional to the loop points here and is budgeted (`section.budget`).
    func testConcentricLabyrinthIsSoundAndCapWorkIsBudgeted() throws {
        var points: [[Double]] = [[1, -2]]
        var x = 2.0
        for _ in 0..<40 { points += [[x, -2], [x, 2], [x + 1, 2], [x + 1, -2]]; x += 3 }
        points += [[x, -3], [1, -3]]
        let json = #"{"v": 2, "kind": "assembly", "parts": [{"id": "lab", "shape": {"revolvedProfile": {"points": \#(points), "closed": true}}}], "steps": [{"say": "a", "section": {"normal": [0, 0, 1], "offset": 0, "parts": ["lab"]}}]}"#
        let d = try doc(json)
        let c = try XCTUnwrap(d.steps[0].section?.cuts["lab"])
        assertSound(c, "labyrinth")
        XCTAssertEqual(c.loops, 80)                       // 40 fins, each an annulus: an outer loop and its hole
        let mesh = d.assembly.part("lab")!.mesh, plane = c.plane
        let e = try MGSolidSection.estimate(mesh, plane, workLimit: .max)
        XCTAssertEqual(e.triangles, c.mesh.triangleCount)
        // The charged work is a small multiple of the loop points (80 loops of 96 points).
        XCTAssertLessThan(e.work, 30 * 80 * 96)
        XCTAssertThrowsError(try MGSolidSection.estimate(mesh, plane, workLimit: e.work - 1)) {
            XCTAssertEqual(($0 as? MGSolidIssue)?.reason, "section.budget")
        }
        var steps = d.steps
        steps[0].section?.cuts = [:]
        XCTAssertThrowsError(try MGSolidSections.compile(&steps, d.assembly, defaults: d.defaults, budget: (0, 0), shapes: d.shapes,
                                                         previous: nil, capWork: e.work - 1)) {
            XCTAssertEqual(($0 as? MGSolidIssue)?.reason, "section.budget")
        }
        XCTAssertTrue(steps[0].section!.cuts.isEmpty, "nothing is cut when the cap work budget refuses")
    }

    func testPlanesOnFacesEdgesAndVertices() throws {
        let box = MGMesh.chamferedBox(size: MGVec3(10, 10, 10), chamfer: 0)
        // A face lying in the plane: nothing beyond it (misses), or nothing kept (removes all).
        XCTAssertEqual(MGSolidSection.crossing(box, MGSectionPlane(normal: .unitX, offset: 5)), .misses)
        XCTAssertEqual(MGSolidSection.crossing(box, MGSectionPlane(normal: -.unitX, offset: -5)), .removesAll)
        // Diagonal plane through two opposite edges: every cut point is a box vertex.
        let diagonal = try MGSolidSection.cut(box, MGSectionPlane(normal: MGVec3(1, -1, 0), offset: 0))
        assertSound(diagonal, "diagonal")
        XCTAssertEqual(diagonal.mesh.signedVolume, 500, accuracy: 1e-9)
        XCTAssertEqual(diagonal.capArea, 10 * 10 * 2.0.squareRoot(), accuracy: 1e-9)
        // Cutting one corner off leaves a small triangular cap.
        let corner = try MGSolidSection.cut(box, MGSectionPlane(normal: MGVec3(1, 1, 1), offset: 14))
        assertSound(corner, "corner")
    }

    func testOpenOrInsideOutMeshesAreRefused() {
        var open = MGMesh.chamferedBox(size: MGVec3(4, 4, 4), chamfer: 0)
        open.indices.removeLast(3)
        XCTAssertThrowsError(try MGSolidSection.cut(open, MGSectionPlane(normal: .unitX, offset: 0))) {
            XCTAssertEqual(($0 as? MGSolidIssue)?.reason, "section.loops")
        }
        var inverted = MGMesh.chamferedBox(size: MGVec3(4, 4, 4), chamfer: 0)
        for t in 0..<inverted.triangleCount { inverted.indices.swapAt(3 * t + 1, 3 * t + 2) }
        XCTAssertThrowsError(try MGSolidSection.estimate(inverted, MGSectionPlane(normal: .unitX, offset: 0))) {
            XCTAssertEqual(($0 as? MGSolidIssue)?.reason, "section.nesting")
        }
    }

    /// Meshes and cuts built in code with bad numbers are refused or clamped, never a trap.
    func testMalformedInputsDoNotTrap() throws {
        let plane = MGSectionPlane(normal: .unitX, offset: 0)
        var bad = MGMesh.chamferedBox(size: MGVec3(4, 4, 4), chamfer: 0)
        bad.indices[0] = 9_999
        XCTAssertEqual(MGSolidSection.crossing(bad, plane), .misses)
        XCTAssertThrowsError(try MGSolidSection.cut(bad, plane)) { XCTAssertEqual(($0 as? MGSolidIssue)?.reason, "section.mesh") }
        var nan = MGMesh.chamferedBox(size: MGVec3(4, 4, 4), chamfer: 0)
        nan.positions[0].x = .nan
        XCTAssertThrowsError(try MGSolidSection.estimate(nan, plane)) { XCTAssertEqual(($0 as? MGSolidIssue)?.reason, "section.mesh") }
        XCTAssertThrowsError(try MGSolidSection.cut(MGMesh.chamferedBox(size: MGVec3(4, 4, 4), chamfer: 0),
                                                   MGSectionPlane(normal: .unitX, offset: .infinity)))
        XCTAssertEqual(MGSectionPlane(normal: .zero, offset: 3).normal, .unitZ)
        var c = try MGSolidSection.cut(MGMesh.chamferedBox(size: MGVec3(4, 4, 4), chamfer: 0), plane)
        for first in [-5, 1_000_000] {
            c.capFirstTriangle = first
            XCTAssertEqual(c.renderMesh(creaseAngle: 0.6).indices.count, c.mesh.indices.count)
        }
        // Second review R3: a cap range that would overflow, or does not end at the last triangle, is not sound (no trap).
        let good = try MGSolidSection.cut(MGMesh.chamferedBox(size: MGVec3(4, 4, 4), chamfer: 0), plane)
        XCTAssertTrue(good.isSound)
        for (first, count) in [(good.capFirstTriangle, Int.max), (Int.max, Int.max), (-1, good.capTriangleCount + 1),
                               (good.capFirstTriangle + 1, good.capTriangleCount - 1), (good.mesh.triangleCount, 0)] {
            var bad = good
            bad.capFirstTriangle = first; bad.capTriangleCount = count
            XCTAssertFalse(bad.isSound, "\(first) \(count)")
            _ = bad.renderMesh(creaseAngle: 0.6)
        }
        // A bad cap index (review S3) renders nothing instead of trapping, and the cut is not sound.
        c.mesh.indices[c.mesh.indices.count - 1] = 9_999
        XCTAssertEqual(c.renderMesh(creaseAngle: 0.6).indices.count, 0)
        XCTAssertFalse(c.isSound)
        // `cut` refuses a plane that removes nothing or everything itself (review N7), even for tiny meshes.
        let tiny = MGMesh.chamferedBox(size: MGVec3(4e-10, 4e-10, 4e-10), chamfer: 0)
        XCTAssertThrowsError(try MGSolidSection.cut(tiny, MGSectionPlane(normal: .unitX, offset: 1))) {
            XCTAssertEqual(($0 as? MGSolidIssue)?.reason, "section.miss")
        }
        XCTAssertThrowsError(try MGSolidSection.cut(tiny, MGSectionPlane(normal: .unitX, offset: -1))) {
            XCTAssertEqual(($0 as? MGSolidIssue)?.reason, "section.empty")
        }
        // Opacity and light set in code are limited to their ranges, so the snapshot always decodes (review N2).
        let mesh = MGMesh.chamferedBox(size: MGVec3(4, 4, 4), chamfer: 0)
        let a = MGAssembly(name: "code", parts: [
            MGPart(id: "a", name: "a", mesh: mesh, material: .brass, opacity: .nan, emission: MGEmission(role: .red, intensity: 10)),
            MGPart(id: "b", name: "b", mesh: mesh, material: .brass, opacity: 0, emission: MGEmission(role: .red, intensity: -3)),
            MGPart(id: "c", name: "c", mesh: mesh, material: .brass, opacity: 5)])
        let view = MGSolidView(a)
        XCTAssertEqual([view.part("a").opacity, view.part("b").opacity, view.part("c").opacity], [1, 0.1, 1])
        XCTAssertEqual(view.part("a").emission?.intensity, 4)
        let snap = MGSolidSnapshot.build(a, view: view, params: MGPoseParameters(), camera: nil, aspect: 1.6, lighting: .studio,
                                         stage: MGSolidStage.zUpToYUp)
        XCTAssertEqual(try MGSolidSnapshot.decode(data: snap.jsonData()), snap)
    }

    // MARK: X3, X4: step section and ghost

    func testStepSectionCutsOnlyTheListedPartAndSnapshotV2MarksTheCaps() throws {
        let d = try doc(casing(#"{"say": "Whole."}, {"say": "Cut.", \#(cut)}"#))
        XCTAssertNil(d.steps[0].section)
        let v = d.view(step: 1)
        let c = try XCTUnwrap(v.part("casing").cut)                                                       // X3
        assertSound(c, "casing")
        XCTAssertNil(v.part("gear").cut)
        XCTAssertEqual(d.view(step: 0), d.view(step: nil))
        let params = MGPoseParameters(input: 0.7)
        let snap = MGSolidSnapshot.make(d, step: 1, params: params)
        XCTAssertEqual(snap.format, "martygraphics.solid.snapshot/2")
        let casingRange = try XCTUnwrap(snap.parts.first { $0.id == "casing" }), gearRange = try XCTUnwrap(snap.parts.first { $0.id == "gear" })
        XCTAssertEqual(casingRange.capTriangleCount, c.capTriangleCount)
        XCTAssertEqual(casingRange.capFirstTriangle, casingRange.firstTriangle + c.capFirstTriangle)
        XCTAssertEqual(casingRange.triangleCount, c.mesh.triangleCount)
        XCTAssertNil(gearRange.capFirstTriangle)
        XCTAssertEqual(gearRange.triangleCount, d.assembly.part("gear")!.mesh.renderMesh(creaseAngle: 0.6).indices.count / 3)
        // The cap triangles lie on the world plane of the snapshot's section (Y up), facing along its normal.
        let s = try XCTUnwrap(snap.section)
        XCTAssertEqual(s.parts, ["casing"])
        let n = MGVec3(s.normal[0], s.normal[1], s.normal[2])
        func p(_ i: UInt32) -> MGVec3 { let k = 3 * Int(i); return MGVec3(Double(snap.positions[k]), Double(snap.positions[k + 1]), Double(snap.positions[k + 2])) }
        for t in casingRange.capFirstTriangle!..<(casingRange.capFirstTriangle! + casingRange.capTriangleCount!) {
            let a = p(snap.indices[3 * t]), b = p(snap.indices[3 * t + 1]), cc = p(snap.indices[3 * t + 2])
            for q in [a, b, cc] { XCTAssertEqual(n.dot(q), s.offset, accuracy: 1e-3) }
            XCTAssertGreaterThan((b - a).cross(cc - a).dot(n), 0)
        }
        XCTAssertEqual(try MGSolidSnapshot.decode(data: snap.jsonData()), snap)        // V4
    }

    func testGhostAndPartAppearance() throws {
        let d = try doc(casing(#"{"say": "Ghost.", "ghost": ["casing"]}"#, casingExtra: #", "emissive": {"role": "orange", "intensity": 2}"#))
        let snap = MGSolidSnapshot.make(d, step: 0, params: MGPoseParameters())
        XCTAssertEqual(snap.parts.first { $0.id == "casing" }?.opacity, 0.2)                              // X4
        XCTAssertEqual(snap.parts.first { $0.id == "gear" }?.opacity, 1)
        XCTAssertNil(snap.section)
        let plain = MGSolidSnapshot.make(d, step: nil, params: MGPoseParameters())
        XCTAssertEqual(plain.parts.first { $0.id == "casing" }?.opacity, 1)
        let lit = try XCTUnwrap(plain.materials.first { $0.emission != nil })
        XCTAssertEqual(lit.id, "aluminum+emissive.orange.2")
        // Material ids carry the exact intensity (review N1): close intensities never share a material.
        XCTAssertEqual(MGEmission(role: .red, intensity: 1.231).id, "emissive.red.1.231")
        XCTAssertNotEqual(MGEmission(role: .red, intensity: 1.231).id, MGEmission(role: .red, intensity: 1.234).id)
        XCTAssertEqual(lit.emission, MGSolidSnapshot.Emission(color: MGSolidPalette.srgb(.orange), intensity: 2))
        XCTAssertEqual(d.assembly.part("casing")?.emission, MGEmission(role: .orange, intensity: 2))
        // A part's own opacity; a ghost never makes a part more opaque than it is.
        let faint = try doc(casing(#"{"say": "Ghost.", "ghost": ["casing", "gear"]}"#, casingExtra: #", "opacity": 0.15"#))
        XCTAssertEqual(faint.view(step: 0).part("casing").opacity, 0.15)
        XCTAssertEqual(faint.view(step: 0).part("gear").opacity, 0.2)
        XCTAssertEqual(faint.view(step: nil).part("gear").opacity, 1)
        // Appearance is not a claim: the legend does not change.
        XCTAssertEqual(faint.legend, try doc(casing(#"{"say": "Ghost."}"#)).legend)
    }

    func testSectionAndAppearanceRefusalsWithNearMisses() {
        let cases: [(bad: String, good: String, reason: String)] = [
            (casing(#"{"say": "a"}"#, casingExtra: #", "opacity": 0.05"#), casing(#"{"say": "a"}"#, casingExtra: #", "opacity": 0.1"#), "part.opacity"),     // X5
            (casing(#"{"say": "a"}"#, casingExtra: #", "emissive": {"role": "red", "intensity": 5}"#),
             casing(#"{"say": "a"}"#, casingExtra: #", "emissive": {"role": "red", "intensity": 4}"#), "part.emissive"),                                   // X5
            (casing(#"{"say": "a"}"#, casingExtra: #", "emissive": {"role": "crimson"}"#), casing(#"{"say": "a"}"#, casingExtra: #", "emissive": {"role": "red"}"#), "part.emissive.role"),
            (casing(#"{"say": "a"}"#, casingExtra: #", "emissive": {"intensity": 1}"#), casing(#"{"say": "a"}"#, casingExtra: #", "emissive": {"role": "teal", "intensity": 0}"#), "part.emissive.missing.role"),
            (casing(#"{"say": "a", "section": {"normal": [0, 0, 0], "parts": ["casing"]}}"#), casing(#"{"say": "a", \#(cut)}"#), "step.section.normal"),
            (casing(#"{"say": "a", "section": {"normal": [1, 0, 0], "parts": []}}"#), casing(#"{"say": "a", \#(cut)}"#), "step.section.parts"),
            (casing(#"{"say": "a", "section": {"normal": [1, 0, 0]}}"#), casing(#"{"say": "a", \#(cut)}"#), "step.section.missing.parts"),
            (casing(#"{"say": "a", "section": {"normal": [1, 0, 0], "parts": ["casing"], "keep": "front"}}"#), casing(#"{"say": "a", \#(cut)}"#), "step.section.unknown.keep"),
            (casing(#"{"say": "a", "section": {"normal": [1, 0, 0], "parts": ["shell"]}}"#), casing(#"{"say": "a", \#(cut)}"#), "ref.unknown.shell"),
            // The plane misses the casing (nothing would be cut away), or removes all of it.
            (casing(#"{"say": "a", "section": {"normal": [1, 0, 0], "offset": 40, "parts": ["casing"]}}"#),
             casing(#"{"say": "a", "section": {"normal": [1, 0, 0], "offset": 33, "parts": ["casing"]}}"#), "section.miss.casing"),
            (casing(#"{"say": "a", "section": {"normal": [1, 0, 0], "offset": -40, "parts": ["casing"]}}"#),
             casing(#"{"say": "a", "section": {"normal": [1, 0, 0], "offset": -33, "parts": ["casing"]}}"#), "section.empty.casing"),
            (casing(#"{"say": "a", "ghost": []}"#), casing(#"{"say": "a", "ghost": ["casing"]}"#), "step.ghost"),
            (casing(#"{"say": "a", "ghost": ["shell"]}"#), casing(#"{"say": "a", "ghost": ["gear"]}"#), "ref.unknown.shell"),
        ]
        for c in cases {
            XCTAssertEqual(reason(c.bad), c.reason)
            XCTAssertNil(reason(c.good), c.reason)
        }
        // A refusal names the part.
        if case .failure(let e) = parse(cases[9].bad) { XCTAssertEqual(e.part, "casing") } else { XCTFail() }
    }

    func testNewKeysNeedVersionTwo() {
        XCTAssertEqual(reason(casing(#"{"say": "a"}"#, casingExtra: #", "opacity": 0.5"#, v: 1)), "part.unknown.opacity")          // V2
        XCTAssertEqual(reason(casing(#"{"say": "a"}"#, casingExtra: #", "emissive": {"role": "red"}"#, v: 1)), "part.unknown.emissive")
        XCTAssertEqual(reason(casing(#"{"say": "a", \#(cut)}"#, v: 1)), "step.unknown.section")
        XCTAssertEqual(reason(casing(#"{"say": "a", "ghost": ["casing"]}"#, v: 1)), "step.unknown.ghost")
        XCTAssertNil(reason(casing(#"{"say": "a", \#(cut), "ghost": ["casing"]}"#, casingExtra: #", "opacity": 0.5"#)))         // V3
    }

    func testRepeatCopiesAndBudgetAndReuse() throws {
        // A `repeat` base in `parts` cuts every copy; a repeated id is listed once.
        let d = try doc(#"{"v": 2, "kind": "assembly", "parts": [{"id": "post", "at": [20, 0, 0], "shape": {"shaft": {"radius": 3, "length": 20}}, "repeat": {"count": 4}}], "steps": [{"say": "a", "section": {"normal": [0, 0, 1], "offset": 10, "parts": ["post", "post2"]}}]}"#)
        XCTAssertEqual(d.steps[0].section?.parts, ["post1", "post2", "post3", "post4"])
        for id in ["post1", "post2", "post3", "post4"] { assertSound(try XCTUnwrap(d.steps[0].section?.cuts[id]), id) }
        // The plane is in assembly coordinates: every copy is cut at the same height, so all four caps are equal.
        let areas = Set(d.steps[0].section!.cuts.values.map { ($0.capArea * 1e6).rounded() })
        XCTAssertEqual(areas.count, 1)
        // Cuts count toward the mesh budget before they are built.
        var steps = d.steps
        for i in steps.indices { steps[i].section?.cuts = [:] }
        let tight = MGSolidLimits.triangles - 10
        XCTAssertThrowsError(try MGSolidSections.compile(&steps, d.assembly, defaults: d.defaults, budget: (tight, 0), shapes: d.shapes, previous: nil)) {
            XCTAssertEqual(($0 as? MGSolidIssue)?.reason, "assembly.budget")
        }
        XCTAssertTrue(steps[0].section!.cuts.isEmpty, "nothing is cut when the budget refuses")
        // Each distinct part and plane reads its part's mesh once; the total read is bounded too.
        let reads = d.assembly.parts.reduce(0) { $0 + $1.mesh.triangleCount }
        XCTAssertThrowsError(try MGSolidSections.compile(&steps, d.assembly, defaults: d.defaults, budget: (0, 0), shapes: d.shapes,
                                                         previous: nil, work: reads - 1)) {
            XCTAssertEqual(($0 as? MGSolidIssue)?.reason, "section.budget")
        }
        XCTAssertTrue(steps[0].section!.cuts.isEmpty)
        XCTAssertNoThrow(try MGSolidSections.compile(&steps, d.assembly, defaults: d.defaults, budget: (0, 0), shapes: d.shapes,
                                                     previous: nil, work: reads))
        XCTAssertEqual(steps, d.steps)
        // A patch that keeps shapes and placements reuses the cuts.
        guard case .success(let patched) = MGSolidParser.applying(.object(["params": .object(["explode": .number(0.5)])]), to: d) else { return XCTFail() }
        XCTAssertEqual(patched.steps[0].section, d.steps[0].section)
    }

    /// A moving part is cut at the document's default input; the cut then moves with it.
    func testCutFollowsItsPart() throws {
        let d = try doc(#"{"v": 2, "kind": "assembly", "params": {"input": 1.5707963267948966}, "parts": [{"id": "arm", "shape": {"box": {"size": [40, 6, 6], "at": [20, 0, 0]}}, "joint": {"revolute": [0, 0, 1]}, "drive": {"input": 1}}], "steps": [{"say": "a", "section": {"normal": [0, 1, 0], "offset": 20, "parts": ["arm"]}}]}"#)
        // At input pi/2 the arm points along +Y; y > 20 is cut away, so 20 mm of arm stay.
        let c = try XCTUnwrap(d.steps[0].section?.cuts["arm"])
        assertSound(c, "arm")
        XCTAssertEqual(c.mesh.bounds.max.x, 20, accuracy: 1e-9)
        XCTAssertEqual(c.mesh.signedVolume, 20 * 6 * 6, accuracy: 1e-6)
    }

    // MARK: Renderer

    func testRendererSwapsInCapsAndShowsGhostsAndLight() throws {
        let d = try doc(casing(#"{"say": "Cut.", \#(cut)}, {"say": "Ghost.", "ghost": ["casing"]}"#,
                               casingExtra: #", "emissive": {"role": "orange", "intensity": 2}"#))
        let r = MGSolidRenderer(assembly: d.assembly)
        func node(_ id: String) -> SCNNode { r.scene.rootNode.childNode(withName: id, recursively: true)! }
        func triangles(_ id: String) -> Int { node(id).geometry!.elements[0].primitiveCount }
        let plain = node("casing").geometry!, gear = node("gear").geometry!
        XCTAssertEqual(node("casing").geometry?.firstMaterial?.emission.intensity, 2)
        r.show(d.view(step: 0))
        let cutMesh = try XCTUnwrap(d.steps[0].section?.cuts["casing"])
        XCTAssertEqual(triangles("casing"), cutMesh.renderMesh(creaseAngle: 0.6).indices.count / 3)
        XCTAssertTrue(node("gear").geometry === gear, "uncut parts keep their geometry")
        XCTAssertEqual(node("casing").opacity, 1)
        let cutGeometry = node("casing").geometry!
        r.show(d.view(step: 1))
        XCTAssertTrue(node("casing").geometry === plain)
        XCTAssertEqual(node("casing").opacity, 0.2, accuracy: 1e-6)
        XCTAssertFalse(node("casing").castsShadow)
        XCTAssertFalse(node("casing").geometry!.firstMaterial!.writesToDepthBuffer)
        XCTAssertTrue(node("gear").geometry!.firstMaterial!.writesToDepthBuffer)
        r.highlight(["gear"])
        XCTAssertEqual(node("casing").opacity, 0.2, accuracy: 1e-6)
        XCTAssertEqual(node("casing").geometry?.firstMaterial?.emission.intensity, 2, "a part's own light survives dimming")
        // The cut geometry is built once and reused.
        r.show(d.view(step: 0))
        XCTAssertTrue(node("casing").geometry === cutGeometry)
        // Second review R2: a different cut with the same counts and cap area (moved within its plane, x = 0) is
        // rebuilt, not reused.
        var moved = cutMesh
        moved.mesh.positions = moved.mesh.positions.map { $0 + MGVec3(0, 100, 0) }
        var other = d.view(step: 0)
        other.parts["casing"]?.cut = moved
        r.show(other)
        XCTAssertFalse(node("casing").geometry === cutGeometry)
        XCTAssertEqual(Double(node("casing").geometry!.boundingBox.min.y), moved.mesh.bounds.min.y, accuracy: 1e-3)
        r.show(MGSolidView(d.assembly))
        XCTAssertTrue(node("casing").geometry === plain)
    }

    // MARK: V. Compatibility and snapshot v2

    /// V1, V4: the v1 snapshot of every shipped example keeps its exact bytes (hashes recorded at PR 1 head 72545a5).
    func testV1SnapshotBytesAreUnchanged() throws {
        let expected = ["planetary": "3b449df1e301a93b997d2bd7c1345debea06d80b53353c7d21f140f1a4ada030",
                        "slider-crank": "f8fc4e67cc3b11784fd6993c01d6ede50ce30cb17c7f21be951465c9e24e9920",
                        "propeller": "bfafe9e3b112547a133b788764db797ac9b1ad445a73f3589e15b046388d2c83",
                        "horizontal-reduction": "890a0c0ab8a2c24cfdb429f4d5b3d90f637b29200d4f66aaa9264750e33e78c4"]
        for (name, hash) in expected {
            let d = try model(name)
            let snap = MGSolidSnapshot.make(d.assembly, params: MGPoseParameters(input: 0.4, explode: 0.3))
            let data = try snap.jsonData()
            XCTAssertEqual(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), hash, name)
            XCTAssertEqual(snap.format, "martygraphics.solid.snapshot/1")
            XCTAssertEqual(try MGSolidSnapshot.decode(data: data), snap)
        }
    }

    func testSnapshotDecoderDispatchesOnFormat() throws {
        let d = try doc(casing(#"{"say": "Cut.", \#(cut), "ghost": ["gear"]}"#, casingExtra: #", "emissive": {"role": "teal"}"#))
        let v2 = MGSolidSnapshot.make(d, step: 0, params: MGPoseParameters())
        let data = try v2.jsonData()
        XCTAssertEqual(try MGSolidSnapshot.decode(data: data), v2)
        func mutated(_ edit: (inout [String: Any]) -> Void) throws -> Bool {
            var o = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            edit(&o)
            return (try? MGSolidSnapshot.decode(data: JSONSerialization.data(withJSONObject: o))) != nil
        }
        // v2 fields in a v1 file fail instead of being ignored.
        XCTAssertFalse(try mutated { $0["format"] = "martygraphics.solid.snapshot/1" })
        XCTAssertFalse(try mutated { $0["format"] = "martygraphics.solid.snapshot/3" })
        XCTAssertFalse(try mutated { o in var p = o["parts"] as! [[String: Any]]; p[1]["opacity"] = 0.05; o["parts"] = p })
        XCTAssertFalse(try mutated { o in var p = o["parts"] as! [[String: Any]]; p[1].removeValue(forKey: "opacity"); o["parts"] = p })
        XCTAssertFalse(try mutated { o in var p = o["parts"] as! [[String: Any]]; p[0]["capTriangleCount"] = 1_000_000_000; o["parts"] = p })
        XCTAssertFalse(try mutated { o in var p = o["parts"] as! [[String: Any]]; p[0].removeValue(forKey: "capFirstTriangle"); o["parts"] = p })
        XCTAssertFalse(try mutated { o in var s = o["section"] as! [String: Any]; s["normal"] = [0, 2, 0]; o["section"] = s })
        XCTAssertFalse(try mutated { o in var s = o["section"] as! [String: Any]; s["parts"] = ["nothing"]; o["section"] = s })
        XCTAssertFalse(try mutated { o in var m = o["materials"] as! [[String: Any]]; m[0]["emission"] = ["color": [1, 1], "intensity": 1]; o["materials"] = m })
        XCTAssertTrue(try mutated { _ in })
    }

    // MARK: Worked example

    func testIdlerGearboxExample() throws {
        let d = try model("idler-gearbox")
        XCTAssertEqual(d.version, 2)
        XCTAssertEqual(d.warnings, [])
        guard case .success = MGSolidParser.document(data: try Data(contentsOf: Self.root.appendingPathComponent("Examples/Solid3D/Sources/MartySolid3D/Models/idler-gearbox.json")), profile: .strict) else { return XCTFail("strict") }
        XCTAssertEqual(d.fact("idler.speed")!.value, -16.0 / 23, accuracy: 1e-12)
        XCTAssertEqual(d.fact("output.speed")!.value, 16.0 / 28, accuracy: 1e-12)
        XCTAssertEqual(d.steps[3].say, "The idler turns the other way, at 16/23 of the input speed.")
        XCTAssertEqual(d.steps[4].say, "The output turns the same way as the input, 4/7 of a turn per input turn.")
        XCTAssertEqual(d.steps.map { $0.section != nil }, [false, true, true, true, true, false])
        XCTAssertEqual(d.steps[5].ghost, ["casing"])
        // Four steps share one plane, so the casing is cut once.
        let cuts = d.steps.compactMap { $0.section?.cuts["casing"] }
        XCTAssertEqual(cuts.count, 4)
        XCTAssertTrue(cuts.allSatisfy { $0 == cuts[0] })
        let c = cuts[0]
        assertSound(c, "casing")
        // The frame wall (6 mm all round, chamfered) and the base foot are cut; the front cover is gone.
        XCTAssertEqual(c.mesh.bounds.min.y, 0, accuracy: 1e-9)
        XCTAssertEqual(c.loops, 3)
        let whole = d.assembly.part("casing")!.mesh
        XCTAssertLessThan(c.mesh.signedVolume, 0.6 * whole.signedVolume)
        // Three solved motions, four captions with engine facts and two claim checks; sections and ghosts make no claim.
        XCTAssertEqual(d.legend.text, "Solved 9")
    }
}
