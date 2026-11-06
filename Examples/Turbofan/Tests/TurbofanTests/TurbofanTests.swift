// SPDX-License-Identifier: Apache-2.0
import XCTest
import simd
import MartyGraphics
import MartyGraphicsPathTracer
@testable import MartySolidRT
@testable import TurbofanKit

/// Snapshot-to-path-tracer adapter.
final class SolidRTAdapterTests: XCTestCase {
    func testSRGBToLinear() {
        XCTAssertEqual(MGSolidRT.linear(0), 0)
        XCTAssertEqual(MGSolidRT.linear(1), 1, accuracy: 1e-6)
        XCTAssertEqual(MGSolidRT.linear(0.5), 0.21404, accuracy: 1e-4)
        XCTAssertEqual(MGSolidRT.linear(0.02), 0.02 / 12.92, accuracy: 1e-7)
    }

    func testMaterialPresetsMapToPathTracerKinds() {
        func map(_ p: MGMaterialPreset) -> MGRTMaterial { MGSolidRT.material(id: p.id, p.parameters) }
        let brushed = map(.brushedSteel)
        XCTAssertEqual(brushed.kind, .metal)
        XCTAssertGreaterThan(brushed.anisotropy, 0)
        XCTAssertEqual(brushed.roughness, 0.32, accuracy: 1e-6)
        XCTAssertEqual(brushed.baseColor.x, MGSolidRT.linear(0.80), accuracy: 1e-6)
        let ti = map(.titanium)
        XCTAssertEqual(ti.kind, .metal)
        XCTAssertEqual(ti.anisotropy, 0)
        let anodized = map(.anodized(.blue))
        XCTAssertEqual(anodized.kind, .metal)
        XCTAssertEqual(anodized.coat, 0.25, accuracy: 1e-6)
        let paint = map(.plastic(.white))
        XCTAssertEqual(paint.kind, .plastic)
        XCTAssertEqual(paint.coat, 0.15, accuracy: 1e-6)
        let carbon = map(.composite)
        XCTAssertEqual(carbon.kind, .plastic)
        XCTAssertEqual(carbon.coat, 0.8, accuracy: 1e-6)
        let glass = map(.glass)
        XCTAssertEqual(glass.kind, .glass)
        XCTAssertEqual(glass.ior, 1.5, accuracy: 1e-6)
        XCTAssertEqual(map(.ceramic).kind, .plastic)
    }

    func smallAssembly() -> MGAssembly {
        MGAssembly(name: "Pair", parts: [
            MGPart(id: "hub", name: "Hub", mesh: .tube(inner: 5, outer: 20, from: 0, to: 10), material: .titanium,
                   joint: .revolute(axis: .unitZ), drive: .input(scale: 1, offset: 0)),
            MGPart(id: "case", name: "Case", mesh: .revolve([MGVec2(30, -5), MGVec2(34, -5), MGVec2(34, 15), MGVec2(30, 15)], segments: 48,
                                                            closed: true, sweep: 1.5 * .pi), material: .plastic(.white)),
            MGPart(id: "lens", name: "Lens", mesh: .cylinder(radius: 4, from: 12, to: 14), material: .glass),
        ])
    }

    func testSceneFromSnapshotKeepsTrianglesMaterialsAndCamera() throws {
        let a = smallAssembly()
        let snap = MGSolidSnapshot.make(a, params: MGPoseParameters(input: 0.3))
        var options = MGSolidRT.Options()
        options.environmentSize = (64, 32)
        let scene = MGSolidRT.scene(snap, options: options)
        XCTAssertNoThrow(try scene.validate())
        XCTAssertEqual(scene.meshes.count, 3)
        XCTAssertEqual(scene.instances.count, 3)
        XCTAssertEqual(scene.meshes.map(\.triangleCount), snap.parts.map(\.triangleCount))
        XCTAssertEqual(scene.materials.count, snap.materials.count)
        XCTAssertEqual(scene.areaLights.count, snap.lighting.lights.count)
        // Per-triangle materials follow the snapshot's material table.
        for (k, part) in snap.parts.enumerated() {
            XCTAssertEqual(Set(scene.meshes[k].materialIDs), [UInt32(part.material)])
            XCTAssertEqual(scene.materials[part.material].kind, MGSolidRT.material(id: snap.materials[part.material].id,
                                                                                  snap.materials[part.material].parameters).kind)
        }
        // Positions are the snapshot's, scaled from millimetres to metres.
        let first = snap.parts[1]
        let v = Int(snap.indices[first.firstTriangle * 3])
        let lo = Int(snap.indices[(first.firstTriangle * 3)..<((first.firstTriangle + first.triangleCount) * 3)].min()!)
        let p = scene.meshes[1].positions[v - lo]
        XCTAssertEqual(p.x, snap.positions[3 * v] * 0.001, accuracy: 1e-9)
        XCTAssertEqual(p.z, snap.positions[3 * v + 2] * 0.001, accuracy: 1e-9)
        // Closed parts stay closed and outward wound after the split.
        for m in scene.meshes { XCTAssertGreaterThan(m.signedVolume, 0) }
        let cam = scene.camera, pos = snap.camera.position
        XCTAssertEqual(cam.position.x, Float(pos.x) * 0.001, accuracy: 1e-6)
        XCTAssertEqual(cam.position.y, Float(pos.y) * 0.001, accuracy: 1e-6)
        XCTAssertEqual(cam.verticalFOVDegrees, Float(snap.camera.fieldOfView))
        XCTAssertEqual(scene.environment.width, 64)
    }

    func testAreaLightsDeliverTheRequestedIrradiance() {
        let c = SIMD3<Float>(1, 2, 3)
        let lights = MGSolidRT.areaLights(.studio, center: c, distance: 10, lightScale: 0.7)
        for (l, src) in zip(lights, MGStudioLighting.studio.lights) {
            let centre = l.corner + l.edgeU / 2 + l.edgeV / 2
            XCTAssertEqual(simd_distance(centre, c), 10, accuracy: 1e-3)
            XCTAssertGreaterThan(simd_dot(l.normal, c - centre), 0, "\(src.name) faces the scene")
            // Small-source approximation: E = L * A / d^2 on the light's axis.
            let e = MGRTSampling.luminance(l.radiance) * l.area / 100
            XCTAssertEqual(e / MGRTSampling.luminance(MGSolidRT.linear(src.color)), Float(src.intensity) / 1000 * 0.7, accuracy: 1e-3)
            XCTAssertFalse(l.visibleToCamera)
        }
    }

    func testMotionMovesASnapshotPartToANewPose() {
        let a = smallAssembly()
        let p0 = a.pose(MGPoseParameters(input: 0.3)), p1 = a.pose(MGPoseParameters(input: 1.1))
        let m = MGSolidRT.motion(from: p0.world["hub"]!, to: p1.world["hub"]!)
        let local = MGVec3(20, 0, 10)
        let w0 = MGSolidStage.zUpToYUp.apply(p0.world["hub"]!.apply(local)), w1 = MGSolidStage.zUpToYUp.apply(p1.world["hub"]!.apply(local))
        let moved = m * SIMD4(Float(w0.x) * 0.001, Float(w0.y) * 0.001, Float(w0.z) * 0.001, 1)
        XCTAssertEqual(moved.x, Float(w1.x) * 0.001, accuracy: 1e-6)
        XCTAssertEqual(moved.y, Float(w1.y) * 0.001, accuracy: 1e-6)
        XCTAssertEqual(moved.z, Float(w1.z) * 0.001, accuracy: 1e-6)
    }

    func testGPURenderOfAdaptedSceneWhenAvailable() throws {
        guard MGRTRenderer.isSupported else { throw XCTSkip("No Metal ray-tracing device") }
        var options = MGSolidRT.Options()
        options.environmentSize = (128, 64)
        let snap = MGSolidSnapshot.make(smallAssembly(), params: MGPoseParameters(), aspect: 1.5)
        let r = try MGRTRenderer(scene: MGSolidRT.scene(snap, options: options))
        let out = try r.render(settings: MGRTSettings(width: 48, height: 32, samplesPerPixel: 4))
        let luma = stride(from: 0, to: out.rgba8.count, by: 4).map { Int(out.rgba8[$0 + 1]) }
        XCTAssertGreaterThan(luma.max() ?? 0, 40, "lit pixels")
        XCTAssertEqual(out.stats.triangles, snap.triangleCount)
    }
}

/// Turbofan model and its geometric checks.
final class TurbofanCheckTests: XCTestCase {
    func testDistanceToTriangle() {
        let a = MGVec2(0, 0), b = MGVec2(4, 0), c = MGVec2(0, 4)
        XCTAssertEqual(TurbofanChecks.distance(MGVec2(1, 1), a, b, c), 0)
        XCTAssertEqual(TurbofanChecks.distance(MGVec2(-2, 1), a, b, c), 2, accuracy: 1e-12)
        XCTAssertEqual(TurbofanChecks.distance(MGVec2(3, 3), a, b, c), 2 / 2.squareRoot(), accuracy: 1e-12)
        // Degenerate (collinear) triangles act as segments.
        XCTAssertEqual(TurbofanChecks.distance(MGVec2(2, 1), a, b, MGVec2(2, 0)), 1, accuracy: 1e-12)
    }

    func testDistanceFieldIsChamferEuclidean() {
        let g = TurbofanChecks.Grid(cell: 1, r0: 0, x0: 0, nr: 20, nx: 20)
        var occ = [Bool](repeating: false, count: 400)
        occ[g.index(5, 5)] = true
        let d = TurbofanChecks.distanceField(occ, g)
        XCTAssertEqual(d[g.index(5, 5)], 0)
        XCTAssertEqual(d[g.index(12, 5)], 7)
        XCTAssertEqual(d[g.index(8, 9)], 3 * 1.41421356 + 1, accuracy: 1e-4)   // (3, 4): chamfer 5.24 vs true 5
    }

    /// A rotor blade row (tip radius `tip`) inside a 270-degree cutaway casing wall (inner radius `casingInner`).
    func rig(casingInner: Double, tip: Double = 112) throws -> MGSolidDocument {
        func num(_ a: [Double]) -> MGJSON { .array(a.map { .number($0) }) }
        let rot = num([0, 1, 0, 90])
        let json: MGJSON = .object(["v": .number(1), "kind": .string("assembly"), "parts": .array([
            .object(["id": .string("rotor"), "rot": rot, "joint": .object(["revolute": num([0, 0, 1])]), "drive": .object(["input": .number(2)]),
                     "shape": .array([.object(["shaft": .object(["radius": .number(60), "length": .number(80), "z0": .number(-40)])]),
                                      .object(["bladeRow": .object(["count": .number(16), "span": .number(tip - 58), "chord": .number(30), "root": .number(58),
                                                                    "stagger": .number(30), "sections": .number(4), "chordSamples": .number(8)])])])]),
            .object(["id": .string("casing"), "rot": rot, "material": .string("darkSteel"),
                     "shape": .object(["revolvedProfile": .object(["points": .array([num([casingInner, -50]), num([casingInner + 8, -50]),
                                                                                       num([casingInner + 8, 50]), num([casingInner, 50])]),
                                                                    "closed": .bool(true), "sweep": .number(270), "start": .number(270)])])]),
        ])])
        return try MGSolidParser.document(json: json).get()
    }

    /// The true swept gap of the rig: the blade tips reach radius `tip` (their vertices lie on that cylinder; every
    /// other blade point is inside it), and the flat facets of the casing wall (270 degrees in 72 segments) come in to
    /// `casingInner * cos(1.875 degrees)` at their middles. The blade and wall overlap axially, and the rotor sweeps
    /// every angle, so the smallest gap at some angle is exactly the difference.
    func trueGap(casingInner: Double, tip: Double) -> Double {
        XCTAssertEqual(MGMesh.sweepSegments(96, sweep: 270 * .pi / 180), 72)
        return casingInner * cos(3.75 / 2 * .pi / 180) - tip
    }

    func testClearanceIsALowerBoundOnTheTrueGap() throws {
        let ok = TurbofanChecks.run(try rig(casingInner: 118), samples: 6, cell: 1)
        XCTAssertTrue(ok.openParts.isEmpty)
        XCTAssertEqual(ok.rates["rotor"]!, 2, accuracy: 1e-9)
        XCTAssertEqual(ok.rates["casing"], 0)
        XCTAssertLessThan(ok.coaxialError, 1e-9)
        let gap = try XCTUnwrap(ok.clearances.first { $0.part == "rotor" })
        XCTAssertEqual(gap.nearest, "casing")
        // The reported gap is never above the true gap; here it is the true gap less the 1e-5 mm merge margin.
        let truth = trueGap(casingInner: 118, tip: 112)
        XCTAssertLessThanOrEqual(gap.gap, truth)
        XCTAssertGreaterThan(gap.gap, truth - 0.001)
        XCTAssertTrue(ok.interferences.isEmpty)
        let bad = TurbofanChecks.run(try rig(casingInner: 110), samples: 6, cell: 1)
        XCTAssertEqual(bad.interferences.map(\.part), ["rotor"])
    }

    /// A near miss that is not aligned with the 1 mm grid: the grid alone can over-report it, the bound cannot.
    func testNearMissOffTheGridIsNotOverReported() throws {
        let r = TurbofanChecks.run(try rig(casingInner: 114.21, tip: 112.79), samples: 4, cell: 1)
        let gap = try XCTUnwrap(r.clearances.first { $0.part == "rotor" })
        let truth = trueGap(casingInner: 114.21, tip: 112.79)   // 1.359 mm
        XCTAssertEqual(truth, 1.359, accuracy: 0.001)
        XCTAssertLessThanOrEqual(gap.gap, truth)
        XCTAssertGreaterThan(gap.gap, truth - 0.001)
        XCTAssertGreaterThan(gap.gridGap, 0)
        XCTAssertTrue(r.interferences.isEmpty)
        // Touching within a few hundredths of a millimetre still counts as clear only when it is.
        let touching = TurbofanChecks.run(try rig(casingInner: 112.79 / cos(3.75 / 2 * .pi / 180) - 0.02, tip: 112.79), samples: 2, cell: 1)
        XCTAssertEqual(touching.interferences.map(\.part), ["rotor"])
    }

    func testFacetBulgeIsTheSagitta() {
        // One facet of a radius-900 wall with a 3.75-degree step dips 900 (1 - cos 1.875 degrees) = 0.48 mm.
        let a = 3.75 * .pi / 180
        let mesh = MGMesh(positions: [MGVec3(0, 900, 0), MGVec3(0, 900 * cos(a), 900 * sin(a)), MGVec3(10, 900, 0)], indices: [0, 1, 2])
        let t = TurbofanChecks.projectedTriangles(mesh, .identity)
        XCTAssertEqual(t.count, 1)
        XCTAssertEqual(t[0].bulge, 900 * (1 - cos(a / 2)), accuracy: 1e-9)
        XCTAssertEqual(t[0].bulge, 0.482, accuracy: 0.001)
        // The region reaches in to the facet's middle radius, 900 cos 1.875 degrees, and no further.
        XCTAssertEqual(t[0].lo.x, 900 * cos(a / 2), accuracy: 1e-9)
        XCTAssertEqual(t[0].hi.x, 900, accuracy: 1e-9)
    }

    func testPolygonDistance() {
        let sq = [MGVec2(0, 0), MGVec2(2, 0), MGVec2(2, 2), MGVec2(0, 2)]
        XCTAssertEqual(TurbofanChecks.polygonDistance(sq, sq.map { MGVec2($0.x + 5, $0.y + 1) }), 3, accuracy: 1e-12)
        XCTAssertEqual(TurbofanChecks.polygonDistance(sq, [MGVec2(1, 1)]), 0)
        XCTAssertEqual(TurbofanChecks.polygonDistance(sq, [MGVec2(3, -1), MGVec2(3, 5)]), 1, accuracy: 1e-12)
        XCTAssertEqual(TurbofanChecks.polygonDistance(sq, [MGVec2(1, -1), MGVec2(1, 5)]), 0)
    }

    func testBundledTurbofanPassesItsChecks() throws {
        let m = try TurbofanModel.load()
        XCTAssertEqual(m.document.assembly.parts.count, 23)
        XCTAssertEqual(m.document.steps.count, 8)
        XCTAssertEqual(m.authoredInputScale("lpShaft"), 1)
        XCTAssertEqual(m.authoredInputScale("hpShaft"), 3)
        // A coarser grid (it only bounds the exact search) and a vertex stride keep the debug-build test quick.
        let r = TurbofanChecks.run(m.document, samples: 4, cell: 2, vertexStride: 7)
        XCTAssertTrue(r.openParts.isEmpty, "\(r.openParts)")
        XCTAssertEqual(r.spoolRates, [1, 3])
        XCTAssertLessThan(r.axisError, 1e-9)
        XCTAssertLessThan(r.coaxialError, 1e-6)
        XCTAssertTrue(r.interferences.isEmpty, "\(r.interferences)")
        XCTAssertGreaterThan(r.minimumGap, 2)
        XCTAssertLessThan(r.triangles, 1_000_000)
        for s in m.document.steps { XCTAssertLessThanOrEqual(s.say.count, MGSolidLimits.say) }
    }

    func testEditedModelWithBladeIntoCasingFailsTheCheck() throws {
        // Lengthen the HP compressor's first rotor until its tips reach into the casing.
        let m = try TurbofanModel.load()
        var text = String(decoding: m.data, as: UTF8.self)
        let range = try XCTUnwrap(text.range(of: #""count": 36, "span": "#))
        let after = text[range.upperBound...]
        let end = try XCTUnwrap(after.firstIndex(of: ","))
        text.replaceSubrange(range.upperBound..<end, with: "120")
        let edited = try TurbofanModel.load(data: Data(text.utf8))
        let r = TurbofanChecks.run(edited.document, samples: 2, cell: 2, vertexStride: 7)
        XCTAssertTrue(r.interferences.contains { $0.part == "hpc" }, "\(r.clearances)")
    }
}
