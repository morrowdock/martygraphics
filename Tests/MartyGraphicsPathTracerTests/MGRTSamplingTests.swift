// SPDX-License-Identifier: Apache-2.0
import XCTest
import simd
@testable import MartyGraphicsPathTracer

final class MGRTSamplingTests: XCTestCase {
    typealias S = MGRTSampling

    func testRNGIsDeterministicAndUniform() {
        var a: UInt32 = S.seed(pixel: SIMD2(3, 7), width: 64, sample: 5, seed: 42)
        var b: UInt32 = S.seed(pixel: SIMD2(3, 7), width: 64, sample: 5, seed: 42)
        var c: UInt32 = S.seed(pixel: SIMD2(3, 7), width: 64, sample: 5, seed: 43)
        var sa: [Float] = [], sb: [Float] = [], sc: [Float] = []
        for _ in 0..<64 { sa.append(S.next(&a)); sb.append(S.next(&b)); sc.append(S.next(&c)) }
        XCTAssertEqual(sa, sb)
        XCTAssertNotEqual(sa, sc)
        var s: UInt32 = 12345
        var sum: Double = 0, sumSq: Double = 0
        let n = 200_000
        for _ in 0..<n {
            let x = S.next(&s)
            XCTAssert(x >= 0 && x < 1)
            sum += Double(x); sumSq += Double(x * x)
        }
        XCTAssertEqual(sum / Double(n), 0.5, accuracy: 0.005)
        XCTAssertEqual(sumSq / Double(n), 1.0 / 3.0, accuracy: 0.005)
    }

    func testRadicalInverse() {
        XCTAssertEqual(S.radicalInverse(2, 1), 0.5)
        XCTAssertEqual(S.radicalInverse(2, 3), 0.75)
        XCTAssertEqual(S.radicalInverse(3, 1), 1.0 / 3.0, accuracy: 1e-6)
        XCTAssertEqual(S.radicalInverse(3, 4), 1.0 / 3.0 + 1.0 / 9.0, accuracy: 1e-6)
    }

    func testConcentricDiskIsInsideAndAreaPreserving() {
        var sumR2: Double = 0
        let n = 200
        for j in 0..<n {
            for i in 0..<n {
                let d = S.concentricDisk(SIMD2((Float(i) + 0.5) / Float(n), (Float(j) + 0.5) / Float(n)))
                XCTAssertLessThanOrEqual(simd_length(d), 1.0001)
                sumR2 += Double(simd_length_squared(d))
            }
        }
        // E[r^2] = 1/2 for a uniform disk.
        XCTAssertEqual(sumR2 / Double(n * n), 0.5, accuracy: 0.002)
    }

    /// ∫ D(m) (m·n) dω_m = 1 for isotropic and anisotropic GGX.
    func testGGXNormalDistributionIsNormalised() {
        for alpha in [SIMD2<Float>(0.3, 0.3), SIMD2<Float>(0.6, 0.6), S.alphas(roughness: 0.5, anisotropy: 0.8)] {
            let nt = 3000, np = 256
            var integral: Double = 0
            for t in 0..<nt {
                let theta = (Double(t) + 0.5) / Double(nt) * Double.pi / 2
                let dTheta = Double.pi / 2 / Double(nt)
                for p in 0..<np {
                    let phi = (Double(p) + 0.5) / Double(np) * 2 * Double.pi
                    let m = SIMD3<Float>(Float(sin(theta) * cos(phi)), Float(sin(theta) * sin(phi)), Float(cos(theta)))
                    integral += Double(S.ggxD(m, alpha: alpha) * m.z) * sin(theta) * dTheta * (2 * Double.pi / Double(np))
                }
            }
            XCTAssertEqual(integral, 1, accuracy: 0.01, "alpha \(alpha)")
        }
    }

    /// The reflection pdf of VNDF sampling integrates to 1 over the sphere of outgoing directions.
    func testGGXReflectionPdfIntegratesToOne() {
        let alpha = S.alphas(roughness: 0.55, anisotropy: 0.4)
        let wo = simd_normalize(SIMD3<Float>(0.4, 0.2, 0.8))
        let nt = 2400, np = 480
        var integral: Double = 0
        for t in 0..<nt {
            let theta = (Double(t) + 0.5) / Double(nt) * Double.pi
            let dTheta = Double.pi / Double(nt)
            for p in 0..<np {
                let phi = (Double(p) + 0.5) / Double(np) * 2 * Double.pi
                let wi = SIMD3<Float>(Float(sin(theta) * cos(phi)), Float(sin(theta) * sin(phi)), Float(cos(theta)))
                integral += Double(S.ggxReflectionPdf(wo, wi, alpha: alpha)) * sin(theta) * dTheta * (2 * Double.pi / Double(np))
            }
        }
        XCTAssertEqual(integral, 1, accuracy: 0.02)
    }

    /// Monte Carlo with the VNDF sampler and its pdf agrees with quadrature of the same BRDF.
    func testVNDFSamplerMatchesPdf() {
        let alpha = S.alphas(roughness: 0.45, anisotropy: 0)
        let wo = simd_normalize(SIMD3<Float>(0.5, 0.0, 0.7))
        func brdfCos(_ wi: SIMD3<Float>) -> Float {
            guard wi.z > 0 else { return 0 }
            let h = simd_normalize(wo + wi)
            return S.ggxD(h, alpha: alpha) * S.ggxG2(wo, wi, alpha: alpha) / (4 * wo.z)
        }
        var state: UInt32 = 99
        var mc: Double = 0
        let n = 200_000
        for _ in 0..<n {
            let m = S.sampleVNDF(wo, alpha: alpha, SIMD2(S.next(&state), S.next(&state)))
            let wi = 2 * simd_dot(wo, m) * m - wo
            let pdf = S.ggxReflectionPdf(wo, wi, alpha: alpha)
            if pdf > 0 { mc += Double(brdfCos(wi) / pdf) }
        }
        mc /= Double(n)
        var quad: Double = 0
        let nt = 1500, np = 300
        for t in 0..<nt {
            let theta = (Double(t) + 0.5) / Double(nt) * Double.pi / 2
            for p in 0..<np {
                let phi = (Double(p) + 0.5) / Double(np) * 2 * Double.pi
                let wi = SIMD3<Float>(Float(sin(theta) * cos(phi)), Float(sin(theta) * sin(phi)), Float(cos(theta)))
                quad += Double(brdfCos(wi)) * sin(theta) * (Double.pi / 2 / Double(nt)) * (2 * Double.pi / Double(np))
            }
        }
        XCTAssertEqual(mc, quad, accuracy: 0.01)
        XCTAssertLessThanOrEqual(quad, 1.0)
    }

    func testFresnel() {
        XCTAssertEqual(S.fresnelDielectric(cosI: 1, eta: 1.5), 0.04, accuracy: 1e-5)
        XCTAssertEqual(S.fresnelDielectric(cosI: 0.1, eta: 1 / 1.5), 1) // total internal reflection
        XCTAssertEqual(S.fresnelDielectric(cosI: 0, eta: 1.5), 1, accuracy: 1e-5)
        let f = S.fresnelSchlick(SIMD3(0.5, 0.5, 0.5), cosTheta: 1)
        XCTAssertEqual(f.x, 0.5, accuracy: 1e-6)
    }

    func testEnvironmentDistributionIsNormalisedAndConsistent() {
        let env = MGRTEnvironment.studio(width: 128, height: 64)
        let dist = env.makeDistribution()
        XCTAssertEqual(dist.marginalCDF.first, 0)
        XCTAssertEqual(dist.marginalCDF.last, 1)
        XCTAssert(zip(dist.marginalCDF, dist.marginalCDF.dropFirst()).allSatisfy { $0 <= $1 })
        for j in 0..<dist.height {
            let row = Array(dist.conditionalCDF[j * (dist.width + 1)..<(j + 1) * (dist.width + 1)])
            XCTAssertEqual(row.first, 0)
            XCTAssertEqual(row.last, 1)
            XCTAssert(zip(row, row.dropFirst()).allSatisfy { $0 <= $1 })
        }
        let mass = dist.pdfUV.reduce(0.0) { $0 + Double($1) } / Double(dist.width * dist.height)
        XCTAssertEqual(mass, 1, accuracy: 1e-4)

        // Solid-angle pdf integrates to 1 (uniform-sphere Monte Carlo), and sampled pdfs match evaluation.
        var state: UInt32 = 7
        var integral: Double = 0
        let n = 200_000
        for _ in 0..<n {
            let z = 1 - 2 * S.next(&state), phi = 2 * Float.pi * S.next(&state)
            let r = sqrt(max(0, 1 - z * z))
            integral += Double(dist.pdf(SIMD3(r * cos(phi), z, r * sin(phi)))) * 4 * Double.pi
        }
        XCTAssertEqual(integral / Double(n), 1, accuracy: 0.03)
        for _ in 0..<2000 {
            let s = dist.sample(SIMD2(S.next(&state), S.next(&state)))
            guard s.pdf > 0 else { continue }
            XCTAssertEqual(s.pdf, dist.pdf(s.direction), accuracy: max(1e-3, s.pdf * 2e-3))
        }
    }

    func testEnvironmentSamplingPrefersSoftboxes() {
        let env = MGRTEnvironment.studio(width: 128, height: 64)
        let dist = env.makeDistribution()
        var state: UInt32 = 11
        var bright = 0
        for _ in 0..<4000 {
            let s = dist.sample(SIMD2(S.next(&state), S.next(&state)))
            if S.luminance(env.radiance(s.direction)) > 0.5 { bright += 1 }
        }
        XCTAssertGreaterThan(Double(bright) / 4000, 0.8)
    }

    func testEnvironmentMappingRoundTrips() {
        for (u, v) in [(Float(0.1), Float(0.3)), (0.75, 0.5), (0.5, 0.9)] {
            let uv = MGRTEnvironment.uv(MGRTEnvironment.direction(u: u, v: v))
            XCTAssertEqual(uv.x, u, accuracy: 1e-5)
            XCTAssertEqual(uv.y, v, accuracy: 1e-5)
        }
    }

    func testCameraRays() {
        let cam = MGRTCamera(position: SIMD3(0, 2, 10), target: SIMD3(0, 2, 0), verticalFOVDegrees: 40,
                             apertureRadius: 0.2, focusDistance: 8)
        let pin = MGRTCamera(position: cam.position, target: cam.target, verticalFOVDegrees: 40)
        let center = pin.ray(ndc: .zero, lens: SIMD2(0.5, 0.5), aspect: 1.5)
        XCTAssertEqual(simd_distance(center.direction, SIMD3(0, 0, -1)), 0, accuracy: 1e-6)
        let top = pin.ray(ndc: SIMD2(0, 1), lens: .zero, aspect: 1.5)
        XCTAssertEqual(acos(simd_dot(top.direction, SIMD3(0, 0, -1))) * 180 / .pi, 20, accuracy: 1e-3)
        XCTAssertGreaterThan(top.direction.y, 0)
        let right = pin.ray(ndc: SIMD2(1, 0), lens: .zero, aspect: 1.5)
        XCTAssertGreaterThan(right.direction.x, 0)
        // Thin lens: every lens sample through a film point meets the pinhole ray on the focus plane.
        let ndc = SIMD2<Float>(0.3, -0.4)
        let p = pin.ray(ndc: ndc, lens: .zero, aspect: 1.5)
        let onFocus = p.origin + p.direction * (8 / simd_dot(p.direction, SIMD3(0, 0, -1)))
        for lens in [SIMD2<Float>(0.1, 0.9), SIMD2(0.8, 0.2), SIMD2(0.5, 0.5)] {
            let r = cam.ray(ndc: ndc, lens: lens, aspect: 1.5)
            XCTAssertLessThanOrEqual(simd_distance(r.origin, cam.position), 0.2001)
            let t = (onFocus.z - r.origin.z) / r.direction.z
            XCTAssertEqual(simd_distance(r.origin + t * r.direction, onFocus), 0, accuracy: 1e-4)
        }
    }

    func testToneCurveAndHalfConversion() {
        XCTAssertEqual(S.acesFitted(.zero).x, 0, accuracy: 0.002)
        XCTAssertEqual(S.acesFitted(SIMD3(repeating: 100)).x, 1, accuracy: 0.01)
        var last: Float = -1
        for i in 0...100 {
            let v = S.acesFitted(SIMD3(repeating: Float(i) * 0.1)).y
            XCTAssertGreaterThanOrEqual(v, last)
            last = v
        }
        XCTAssertEqual(S.halfBits(1), 0x3C00)
        XCTAssertEqual(S.halfBits(0.5), 0x3800)
        XCTAssertEqual(S.halfBits(-2), 0xC000)
        XCTAssertEqual(S.halfBits(65504), 0x7BFF)
        XCTAssertEqual(S.halfBits(1e6), 0x7C00)
        XCTAssertEqual(S.halfBits(Float(pow(2.0, -24.0))), 0x0001)
        XCTAssertEqual(S.halfBits(1e-9), 0)
    }

    func testSceneValidation() throws {
        let quad = MGRTMesh(positions: [SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0, 0, 1)],
                            normals: Array(repeating: SIMD3(0, 1, 0), count: 3), indices: [0, 2, 1], material: 0)
        let cam = MGRTCamera(position: SIMD3(0, 1, 3), target: .zero)
        let good = MGRTScene(meshes: [quad], instances: [MGRTInstance(mesh: 0)], materials: [.diffuse(SIMD3(repeating: 0.5))],
                             camera: cam, environment: .uniform(SIMD3(repeating: 1)))
        XCTAssertNoThrow(try good.validate())
        var bad = good
        bad.meshes[0].indices = [0, 2, 9]
        XCTAssertThrowsError(try bad.validate())
        bad = good
        bad.instances = [MGRTInstance(mesh: 3)]
        XCTAssertThrowsError(try bad.validate())
        bad = good
        bad.meshes[0].materialIDs = [4]
        XCTAssertThrowsError(try bad.validate())
    }
}
