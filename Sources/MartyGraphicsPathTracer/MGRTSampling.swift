// SPDX-License-Identifier: Apache-2.0
import simd

/// CPU reference versions of the sampling math the Metal kernel uses.
/// They exist so the math can be unit-tested; the shader source mirrors them line for line.
public enum MGRTSampling {
    // MARK: Random numbers

    /// PCG-RXS-M-XS 32-bit step: advances `state` and returns a uniform float in [0, 1).
    public static func next(_ state: inout UInt32) -> Float {
        state = state &* 747_796_405 &+ 2_891_336_453
        var word = ((state >> ((state >> 28) &+ 4)) ^ state) &* 277_803_737
        word = (word >> 22) ^ word
        return Float(word >> 8) * (1.0 / 16_777_216.0)
    }

    /// Stateless integer hash (same as one PCG step) for seeding per-pixel streams.
    public static func hash(_ v: UInt32) -> UInt32 {
        let state = v &* 747_796_405 &+ 2_891_336_453
        let word = ((state >> ((state >> 28) &+ 4)) ^ state) &* 277_803_737
        return (word >> 22) ^ word
    }

    /// Per-pixel, per-sample stream seed. The kernel derives its stream identically.
    public static func seed(pixel: SIMD2<UInt32>, width: UInt32, sample: UInt32, seed: UInt32) -> UInt32 {
        hash(hash(pixel.y &* width &+ pixel.x &+ hash(seed)) ^ hash(sample &+ 0x9E37_79B9))
    }

    /// Radical inverse in `base` (Halton dimension).
    public static func radicalInverse(_ base: UInt32, _ index: UInt32) -> Float {
        var n = index, result: Double = 0, f = 1.0 / Double(base)
        let inv = f
        while n > 0 {
            result += f * Double(n % base)
            n /= base
            f *= inv
        }
        return Float(min(result, 0.99999994))
    }

    // MARK: Warps

    /// Shirley-Chiu concentric square-to-disk map.
    public static func concentricDisk(_ u: SIMD2<Float>) -> SIMD2<Float> {
        let o = 2 * u - 1
        if o.x == 0 && o.y == 0 { return .zero }
        let r: Float, theta: Float
        if abs(o.x) > abs(o.y) {
            r = o.x; theta = (.pi / 4) * (o.y / o.x)
        } else {
            r = o.y; theta = .pi / 2 - (.pi / 4) * (o.x / o.y)
        }
        return r * SIMD2(cos(theta), sin(theta))
    }

    public static func cosineHemisphere(_ u: SIMD2<Float>) -> SIMD3<Float> {
        let d = concentricDisk(u)
        return SIMD3(d.x, d.y, sqrt(max(0, 1 - simd_length_squared(d))))
    }

    // MARK: GGX (anisotropic, local frame with z = normal)

    public static func alphas(roughness: Float, anisotropy: Float) -> SIMD2<Float> {
        let a = max(roughness * roughness, 0.002)
        let aspect = sqrt(1 - 0.9 * min(max(anisotropy, 0), 0.95))
        return SIMD2(max(a / aspect, 0.002), max(a * aspect, 0.002))
    }

    public static func ggxD(_ m: SIMD3<Float>, alpha: SIMD2<Float>) -> Float {
        guard m.z > 0 else { return 0 }
        let t = m.x * m.x / (alpha.x * alpha.x) + m.y * m.y / (alpha.y * alpha.y) + m.z * m.z
        return 1 / (.pi * alpha.x * alpha.y * t * t)
    }

    public static func ggxLambda(_ w: SIMD3<Float>, alpha: SIMD2<Float>) -> Float {
        let z2 = w.z * w.z
        guard z2 > 0 else { return .infinity }
        let a2 = (alpha.x * alpha.x * w.x * w.x + alpha.y * alpha.y * w.y * w.y) / z2
        return 0.5 * (-1 + sqrt(1 + a2))
    }

    public static func ggxG1(_ w: SIMD3<Float>, alpha: SIMD2<Float>) -> Float {
        1 / (1 + ggxLambda(w, alpha: alpha))
    }

    /// Height-correlated Smith masking-shadowing.
    public static func ggxG2(_ wo: SIMD3<Float>, _ wi: SIMD3<Float>, alpha: SIMD2<Float>) -> Float {
        1 / (1 + ggxLambda(wo, alpha: alpha) + ggxLambda(wi, alpha: alpha))
    }

    /// Heitz (2018) visible-normal sampling. `wo.z` must be > 0.
    public static func sampleVNDF(_ wo: SIMD3<Float>, alpha: SIMD2<Float>, _ u: SIMD2<Float>) -> SIMD3<Float> {
        let vh = simd_normalize(SIMD3(alpha.x * wo.x, alpha.y * wo.y, wo.z))
        let lensq = vh.x * vh.x + vh.y * vh.y
        let t1: SIMD3<Float> = lensq > 0 ? SIMD3(-vh.y, vh.x, 0) / sqrt(lensq) : SIMD3(1, 0, 0)
        let t2 = simd_cross(vh, t1)
        let r = sqrt(u.x), phi = 2 * Float.pi * u.y
        let p1 = r * cos(phi)
        var p2 = r * sin(phi)
        let s = 0.5 * (1 + vh.z)
        p2 = (1 - s) * sqrt(max(0, 1 - p1 * p1)) + s * p2
        let nh = p1 * t1 + p2 * t2 + sqrt(max(0, 1 - p1 * p1 - p2 * p2)) * vh
        return simd_normalize(SIMD3(alpha.x * nh.x, alpha.y * nh.y, max(1e-6, nh.z)))
    }

    /// Solid-angle pdf of `wi` when reflecting `wo` about a VNDF-sampled microfacet normal.
    public static func ggxReflectionPdf(_ wo: SIMD3<Float>, _ wi: SIMD3<Float>, alpha: SIMD2<Float>) -> Float {
        guard wo.z > 0 else { return 0 }
        let hsum = wo + wi
        guard simd_length_squared(hsum) > 0 else { return 0 }
        let m = simd_normalize(hsum)
        let woDotM = simd_dot(wo, m)
        guard m.z > 0, woDotM > 0 else { return 0 }
        return ggxG1(wo, alpha: alpha) * ggxD(m, alpha: alpha) / (4 * wo.z)
    }

    // MARK: Fresnel

    /// Unpolarised Fresnel reflectance; `eta` = transmitted / incident index, `cosI` >= 0.
    public static func fresnelDielectric(cosI: Float, eta: Float) -> Float {
        let c = min(max(cosI, 0), 1)
        let sin2T = (1 - c * c) / (eta * eta)
        if sin2T >= 1 { return 1 }
        let cosT = sqrt(1 - sin2T)
        let rs = (c - eta * cosT) / (c + eta * cosT)
        let rp = (eta * c - cosT) / (eta * c + cosT)
        return 0.5 * (rs * rs + rp * rp)
    }

    public static func fresnelSchlick(_ f0: SIMD3<Float>, cosTheta: Float) -> SIMD3<Float> {
        let m = pow(1 - min(max(cosTheta, 0), 1), 5)
        return f0 + (SIMD3<Float>(repeating: 1) - f0) * m
    }

    // MARK: Colour

    public static func luminance(_ c: SIMD3<Float>) -> Float {
        simd_dot(c, SIMD3(0.2126, 0.7152, 0.0722))
    }

    /// Stephen Hill's fitted ACES RRT+ODT (sRGB primaries in and out).
    public static func acesFitted(_ color: SIMD3<Float>) -> SIMD3<Float> {
        let input = simd_float3x3(rows: [SIMD3(0.59719, 0.35458, 0.04823),
                                         SIMD3(0.07600, 0.90834, 0.01566),
                                         SIMD3(0.02840, 0.13383, 0.83777)])
        let output = simd_float3x3(rows: [SIMD3(1.60475, -0.53108, -0.07367),
                                          SIMD3(-0.10208, 1.10813, -0.00605),
                                          SIMD3(-0.00327, -0.07276, 1.07602)])
        let v = input * color
        let a = v * (v + 0.0245786) - 0.000090537
        let b = v * (0.983729 * v + 0.4329510) + 0.238081
        let r = output * (a / b)
        return simd_clamp(r, SIMD3<Float>(repeating: 0), SIMD3<Float>(repeating: 1))
    }

    /// IEEE 754 binary16 bits for `value`, rounded to nearest even (no Float16 dependency,
    /// so the package also builds for x86_64 macOS).
    public static func halfBits(_ value: Float) -> UInt16 {
        let bits = value.bitPattern
        let sign = UInt16((bits >> 16) & 0x8000)
        let exponent = Int((bits >> 23) & 0xFF)
        var mantissa = bits & 0x7F_FFFF
        if exponent == 0xFF { return sign | 0x7C00 | (mantissa != 0 ? 0x200 : 0) }
        var e = exponent - 127 + 15
        if e >= 0x1F { return sign | 0x7C00 }
        if e <= 0 {
            if e < -10 { return sign }
            mantissa |= 0x80_0000
            let shift = UInt32(14 - e)
            var half = mantissa >> shift
            let rest = mantissa & ((1 << shift) - 1), halfway = UInt32(1) << (shift - 1)
            if rest > halfway || (rest == halfway && (half & 1) == 1) { half += 1 }
            return sign | UInt16(half)
        }
        var half = mantissa >> 13
        let rest = mantissa & 0x1FFF
        if rest > 0x1000 || (rest == 0x1000 && (half & 1) == 1) {
            half += 1
            if half == 0x400 { half = 0; e += 1 }
            if e >= 0x1F { return sign | 0x7C00 }
        }
        return sign | UInt16(e << 10) | UInt16(half)
    }

    public static func linearToSRGB(_ x: Float) -> Float {
        x <= 0.0031308 ? 12.92 * x : 1.055 * pow(x, 1 / 2.4) - 0.055
    }
}
