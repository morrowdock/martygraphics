// SPDX-License-Identifier: Apache-2.0
import XCTest
import simd
@testable import MartyGraphicsPathTracer

#if canImport(Metal)
final class MGRTGPUSmokeTests: XCTestCase {
    /// A large horizontal quad under a uniform sky.
    private func planeScene(albedo: Float, sky: Float) -> MGRTScene {
        let s: Float = 1000
        let plane = MGRTMesh(positions: [SIMD3(-s, 0, -s), SIMD3(s, 0, -s), SIMD3(s, 0, s), SIMD3(-s, 0, s)],
                             normals: Array(repeating: SIMD3(0, 1, 0), count: 4), indices: [0, 2, 1, 0, 3, 2], material: 0)
        let cam = MGRTCamera(position: SIMD3(0, 3, 0.01), target: .zero, verticalFOVDegrees: 30)
        return MGRTScene(meshes: [plane], instances: [MGRTInstance(mesh: 0)],
                         materials: [.diffuse(SIMD3(repeating: albedo))], camera: cam,
                         environment: .uniform(SIMD3(repeating: sky)))
    }

    private func requireDevice() throws {
        guard MGRTRenderer.isSupported else { throw XCTSkip("No Metal ray-tracing device") }
    }

    /// A Lambertian plane of albedo ρ under a uniform sky of radiance L reflects exactly ρ·L.
    func testDiffusePlaneUnderUniformSkyMatchesAnalyticRadiance() throws {
        try requireDevice()
        let renderer = try MGRTRenderer(scene: planeScene(albedo: 0.5, sky: 1))
        let out = try renderer.render(settings: MGRTSettings(width: 32, height: 24, samplesPerPixel: 16, denoise: false,
                                                             returnLinear: true))
        XCTAssertEqual(out.rgba8.count, 32 * 24 * 4)
        let linearMean = out.linear.reduce(0.0) { $0 + Double($1.y) } / Double(out.linear.count)
        XCTAssertEqual(linearMean, 0.5, accuracy: 0.01)
        let expected = MGRTSampling.linearToSRGB(MGRTSampling.acesFitted(SIMD3(repeating: 0.5)).y) * 255
        var total: Double = 0
        for i in stride(from: 0, to: out.rgba8.count, by: 4) { total += Double(out.rgba8[i + 1]) }
        let mean = total / Double(32 * 24)
        XCTAssertEqual(mean, Double(expected), accuracy: 2.5)
    }

    func testEstimatorsAgree() throws {
        try requireDevice()
        let renderer = try MGRTRenderer(scene: planeScene(albedo: 0.5, sky: 1))
        for flags in [UInt32(0), 1, 2] {
            var s = MGRTSettings(width: 32, height: 24, samplesPerPixel: 64, denoise: false, returnLinear: true)
            s.debugFlags = flags
            let out = try renderer.render(settings: s)
            let mean = out.linear.reduce(0.0) { $0 + Double($1.y) } / Double(out.linear.count)
            XCTAssertEqual(mean, 0.5, accuracy: 0.01, "flags \(flags)")
        }
    }

    /// White furnace: a sphere of a non-absorbing material under a uniform sky of radiance 1 must look
    /// close to 1 (exactly 1 for smooth glass; single-scattering microfacets lose a few percent when rough).
    func testFurnaceEnergyConservation() throws {
        try requireDevice()
        let cases: [(MGRTMaterial, ClosedRange<Double>)] = [
            (.glass(ior: 1.5, roughness: 0), 0.97...1.02),
            (.glass(ior: 1.5, roughness: 0.4), 0.88...1.02),
            (.metal(SIMD3(repeating: 1), roughness: 0.5), 0.85...1.01),
            (.metal(SIMD3(repeating: 1), roughness: 0.3, anisotropy: 0.8), 0.85...1.01),
            (.plastic(SIMD3(repeating: 1), roughness: 0.3), 0.85...1.02),
            (.diffuse(SIMD3(repeating: 1)), 0.97...1.02),
        ]
        let sphere = Self.sphere(radius: 1, segments: 96)
        for (material, range) in cases {
            let cam = MGRTCamera(position: SIMD3(0, 0, 4), target: .zero, verticalFOVDegrees: 12)
            let scene = MGRTScene(meshes: [sphere], instances: [MGRTInstance(mesh: 0)], materials: [material], camera: cam,
                                  environment: .uniform(SIMD3(repeating: 1)))
            let renderer = try MGRTRenderer(scene: scene)
            var settings = MGRTSettings(width: 24, height: 24, samplesPerPixel: 64, maxBounces: 24, denoise: false,
                                        clampIndirect: 0, returnLinear: true)
            settings.seed = 3
            settings.debugFlags = 16 // measure the BSDFs themselves, without path regularisation
            let out = try renderer.render(settings: settings)
            let mean = out.linear.reduce(0.0) { $0 + Double($1.y) } / Double(out.linear.count)
            XCTAssert(range.contains(mean), "\(material.kind) roughness \(material.roughness): \(mean)")
        }
    }

    static func sphere(radius: Float, segments: Int) -> MGRTMesh {
        var p: [SIMD3<Float>] = [], n: [SIMD3<Float>] = [], idx: [UInt32] = []
        let rings = segments / 2
        for j in 0...rings {
            let theta = Float.pi * Float(j) / Float(rings)
            for i in 0...segments {
                let phi = 2 * Float.pi * Float(i) / Float(segments)
                let d = SIMD3<Float>(sin(theta) * cos(phi), cos(theta), sin(theta) * sin(phi))
                p.append(d * radius)
                n.append(d)
            }
        }
        let row = UInt32(segments + 1)
        for j in 0..<UInt32(rings) {
            for i in 0..<UInt32(segments) {
                let a = j * row + i, b = a + 1, c = a + row, d = c + 1
                // Outward winding: (a, b, c) with theta down and phi around (+y up).
                idx += [a, b, c, b, d, c]
            }
        }
        return MGRTMesh(positions: p, normals: n, indices: idx, material: 0)
    }

    func testRenderIsDeterministicPerSeed() throws {
        try requireDevice()
        var scene = planeScene(albedo: 0.7, sky: 0.8)
        // A box on the plane plus an area light, so shadows and NEE are exercised.
        let box = Self.box(center: SIMD3(0, 0.5, 0), size: 1)
        scene.meshes.append(box)
        scene.materials.append(.metal(MGRTMaterial.brass, roughness: 0.3))
        scene.instances.append(MGRTInstance(mesh: 1))
        scene.areaLights = [.softbox(center: SIMD3(2, 4, 1), toward: .zero, size: SIMD2(1, 1), radiance: SIMD3(repeating: 10))]
        scene.camera = MGRTCamera(position: SIMD3(3, 3, 4), target: SIMD3(0, 0.5, 0), verticalFOVDegrees: 35,
                                  apertureRadius: 0.05)
        let renderer = try MGRTRenderer(scene: scene)
        let settings = MGRTSettings(width: 40, height: 30, samplesPerPixel: 4, seed: 9)
        let a = try renderer.render(settings: settings)
        let b = try renderer.render(settings: settings)
        XCTAssertEqual(a.rgba8, b.rgba8)
        var other = settings
        other.seed = 10
        other.denoise = false
        let c = try renderer.render(settings: other)
        XCTAssertNotEqual(a.rgba8, c.rgba8)
        XCTAssertNotNil(a.cgImage())
        // Not a constant image: the box and its shadow must show.
        let greens = stride(from: 1, to: a.rgba8.count, by: 4).map { a.rgba8[$0] }
        XCTAssertGreaterThan(Int(greens.max()!) - Int(greens.min()!), 25)
        XCTAssertGreaterThan(a.stats.traceMilliseconds, 0)
        // Moving the instance changes the image.
        let moved = try renderer.render(settings: settings,
                                        transforms: [matrix_identity_float4x4, simd_float4x4(translation: SIMD3(1, 0, 0))])
        XCTAssertNotEqual(a.rgba8, moved.rgba8)
    }

    static func box(center: SIMD3<Float>, size: Float) -> MGRTMesh {
        var p: [SIMD3<Float>] = [], n: [SIMD3<Float>] = [], idx: [UInt32] = []
        let h = size / 2
        let faces: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)] = [
            (SIMD3(1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, 0, 1)), (SIMD3(-1, 0, 0), SIMD3(0, 0, 1), SIMD3(0, 1, 0)),
            (SIMD3(0, 1, 0), SIMD3(0, 0, 1), SIMD3(1, 0, 0)), (SIMD3(0, -1, 0), SIMD3(1, 0, 0), SIMD3(0, 0, 1)),
            (SIMD3(0, 0, 1), SIMD3(1, 0, 0), SIMD3(0, 1, 0)), (SIMD3(0, 0, -1), SIMD3(0, 1, 0), SIMD3(1, 0, 0)),
        ]
        for (normal, a, b) in faces {
            let base = UInt32(p.count)
            for (s, t) in [(Float(-1), Float(-1)), (1, -1), (1, 1), (-1, 1)] {
                p.append(center + h * (normal + s * a + t * b))
                n.append(normal)
            }
            idx += [base, base + 1, base + 2, base, base + 2, base + 3]
        }
        return MGRTMesh(positions: p, normals: n, indices: idx, material: 1)
    }
}

extension simd_float4x4 {
    init(translation t: SIMD3<Float>) {
        self = matrix_identity_float4x4
        columns.3 = SIMD4(t, 1)
    }
}
#endif
