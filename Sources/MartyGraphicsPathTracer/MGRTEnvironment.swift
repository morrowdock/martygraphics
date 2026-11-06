// SPDX-License-Identifier: Apache-2.0
import simd

/// A latitude-longitude HDR environment (linear RGB) with +y up.
///
/// Direction mapping (shared with the shader): `u = atan2(d.z, d.x) / 2π + 0.5`,
/// `v = acos(d.y) / π`. The studio preset is generated procedurally; no image is loaded.
public struct MGRTEnvironment: Sendable {
    public let width: Int
    public let height: Int
    public let texels: [SIMD4<Float>]
    /// Multiplier applied at lookup time.
    public var intensity: Float

    public init(width: Int, height: Int, texels: [SIMD4<Float>], intensity: Float = 1) {
        precondition(width > 0 && height > 0 && texels.count == width * height, "environment size")
        self.width = width
        self.height = height
        self.texels = texels
        self.intensity = intensity
    }

    public static func uniform(_ color: SIMD3<Float>, width: Int = 16, height: Int = 8) -> MGRTEnvironment {
        MGRTEnvironment(width: width, height: height, texels: Array(repeating: SIMD4(color, 1), count: width * height))
    }

    /// A planar rectangular light at infinity, seen through a gnomonic (tangent-plane) projection.
    public struct Softbox: Sendable, Equatable {
        /// Direction from the scene toward the softbox centre.
        public var direction: SIMD3<Float>
        /// Half extents on the tangent plane (tan of the half angles): x horizontal, y toward +up.
        public var halfSize: SIMD2<Float>
        public var radiance: SIMD3<Float>
        /// Edge transition as a fraction of the half size.
        public var softness: Float
        let a: SIMD3<Float>
        let b: SIMD3<Float>

        public init(direction: SIMD3<Float>, halfSize: SIMD2<Float>, radiance: SIMD3<Float>, softness: Float = 0.08) {
            let n = simd_normalize(direction)
            self.direction = n
            self.halfSize = halfSize
            self.radiance = radiance
            self.softness = softness
            let helper: SIMD3<Float> = abs(n.y) > 0.95 ? SIMD3(0, 0, 1) : SIMD3(0, 1, 0)
            a = simd_normalize(simd_cross(helper, n))
            b = simd_cross(n, a)
        }

        func contribution(_ d: SIMD3<Float>) -> SIMD3<Float> {
            let c = simd_dot(d, direction)
            guard c > 0.05 else { return .zero }
            let x = abs(simd_dot(d, a) / c) / halfSize.x, y = abs(simd_dot(d, b) / c) / halfSize.y
            func edge(_ t: Float) -> Float {
                let s = max(softness, 1e-3)
                let k = min(max((1 - t) / s, 0), 1)
                return k * k * (3 - 2 * k)
            }
            let mask = edge(x) * edge(y)
            guard mask > 0 else { return .zero }
            // Real diffusion panels are slightly brighter in the middle.
            let falloff = 0.82 + 0.18 * (1 - min(1, 0.5 * (x * x + y * y)))
            return radiance * mask * falloff
        }
    }

    /// Default dark studio: a large overhead key, two vertical strips and a faint gradient.
    public static let studioSoftboxes: [Softbox] = [
        Softbox(direction: SIMD3(-0.45, 1.0, -0.35), halfSize: SIMD2(0.55, 0.32), radiance: SIMD3(1, 0.98, 0.95) * 4.5),
        Softbox(direction: SIMD3(1.0, 0.32, 0.25), halfSize: SIMD2(0.10, 0.85), radiance: SIMD3(0.95, 0.98, 1.0) * 5.5),
        Softbox(direction: SIMD3(-1.0, 0.28, -0.75), halfSize: SIMD2(0.08, 0.75), radiance: SIMD3(1.0, 0.97, 0.92) * 4.0),
        Softbox(direction: SIMD3(0.0, 1.0, 0.35), halfSize: SIMD2(1.1, 1.1), radiance: SIMD3(1, 1, 1) * 0.18, softness: 0.5),
    ]

    public static func studio(width: Int = 1024, height: Int = 512, softboxes: [Softbox] = studioSoftboxes,
                              zenith: SIMD3<Float> = SIMD3(0.018, 0.020, 0.024),
                              horizon: SIMD3<Float> = SIMD3(0.010, 0.010, 0.011),
                              nadir: SIMD3<Float> = SIMD3(0.002, 0.002, 0.002),
                              intensity: Float = 1) -> MGRTEnvironment {
        var texels = [SIMD4<Float>](repeating: .zero, count: width * height)
        let offsets: [SIMD2<Float>] = [SIMD2(0.25, 0.25), SIMD2(0.75, 0.25), SIMD2(0.25, 0.75), SIMD2(0.75, 0.75)]
        for j in 0..<height {
            for i in 0..<width {
                var sum = SIMD3<Float>.zero
                for o in offsets {
                    let d = direction(u: (Float(i) + o.x) / Float(width), v: (Float(j) + o.y) / Float(height))
                    let t = d.y
                    var c = t >= 0 ? simd_mix(horizon, zenith, SIMD3(repeating: pow(t, 0.6)))
                                   : simd_mix(horizon, nadir, SIMD3(repeating: pow(-t, 0.4)))
                    for box in softboxes { c += box.contribution(d) }
                    sum += c
                }
                texels[j * width + i] = SIMD4(sum / Float(offsets.count), 1)
            }
        }
        return MGRTEnvironment(width: width, height: height, texels: texels, intensity: intensity)
    }

    public static func direction(u: Float, v: Float) -> SIMD3<Float> {
        let phi = 2 * Float.pi * (u - 0.5), theta = Float.pi * v
        return SIMD3(sin(theta) * cos(phi), cos(theta), sin(theta) * sin(phi))
    }

    public static func uv(_ d: SIMD3<Float>) -> SIMD2<Float> {
        let u = atan2(d.z, d.x) / (2 * Float.pi) + 0.5
        let v = acos(min(max(d.y, -1), 1)) / Float.pi
        return SIMD2(u - floor(u), min(max(v, 0), 1))
    }

    /// Nearest-texel radiance (CPU reference; the GPU filters bilinearly).
    public func radiance(_ d: SIMD3<Float>) -> SIMD3<Float> {
        let uv = Self.uv(d)
        let i = min(width - 1, Int(uv.x * Float(width))), j = min(height - 1, Int(uv.y * Float(height)))
        let t = texels[j * width + i]
        return SIMD3(t.x, t.y, t.z) * intensity
    }

    public func makeDistribution() -> MGRTEnvironmentDistribution {
        MGRTEnvironmentDistribution(self)
    }
}

/// Piecewise-constant 2D distribution over the lat-long map, weighted by luminance × sin θ.
public struct MGRTEnvironmentDistribution: Sendable {
    public let width: Int
    public let height: Int
    /// `height + 1` entries, 0 ... 1.
    public let marginalCDF: [Float]
    /// `height` rows of `width + 1` entries, each 0 ... 1.
    public let conditionalCDF: [Float]
    /// Joint density over the unit square (integrates to 1 over [0,1]^2).
    public let pdfUV: [Float]

    init(_ env: MGRTEnvironment) {
        let w = env.width, h = env.height
        var f = [Double](repeating: 0, count: w * h)
        var rowIntegral = [Double](repeating: 0, count: h)
        var conditional = [Float](repeating: 0, count: h * (w + 1))
        for j in 0..<h {
            let sinTheta = sin(Double.pi * (Double(j) + 0.5) / Double(h))
            var acc = 0.0
            for i in 0..<w {
                let t = env.texels[j * w + i]
                let lum = Double(MGRTSampling.luminance(SIMD3(t.x, t.y, t.z)))
                let value = (max(lum, 0) + 1e-6) * sinTheta
                f[j * w + i] = value
                acc += value
                conditional[j * (w + 1) + i + 1] = Float(acc)
            }
            rowIntegral[j] = acc / Double(w)
            for i in 0...w {
                conditional[j * (w + 1) + i] = acc > 0 ? Float(Double(conditional[j * (w + 1) + i]) / acc) : Float(i) / Float(w)
            }
            conditional[j * (w + 1) + w] = 1
        }
        var marginal = [Float](repeating: 0, count: h + 1)
        var acc = 0.0
        let total = rowIntegral.reduce(0, +) / Double(h)
        for j in 0..<h {
            acc += rowIntegral[j]
            marginal[j + 1] = Float(acc / (total * Double(h)))
        }
        marginal[h] = 1
        width = w
        height = h
        marginalCDF = marginal
        conditionalCDF = conditional
        pdfUV = f.map { Float($0 / total) }
    }

    /// Largest index `i` in `lo..<hi` with `cdf[i] <= u` (cdf strictly covers 0...1).
    static func search(_ cdf: [Float], offset: Int, count: Int, _ u: Float) -> Int {
        var lo = 0, hi = count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if cdf[offset + mid] <= u { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }

    /// Returns a direction and its solid-angle pdf.
    public func sample(_ u: SIMD2<Float>) -> (direction: SIMD3<Float>, pdf: Float) {
        let j = Self.search(marginalCDF, offset: 0, count: height, u.y)
        let m0 = marginalCDF[j], m1 = marginalCDF[j + 1]
        let dv = m1 > m0 ? (u.y - m0) / (m1 - m0) : 0.5
        let row = j * (width + 1)
        let i = Self.search(conditionalCDF, offset: row, count: width, u.x)
        let c0 = conditionalCDF[row + i], c1 = conditionalCDF[row + i + 1]
        let du = c1 > c0 ? (u.x - c0) / (c1 - c0) : 0.5
        let uu = (Float(i) + du) / Float(width), vv = (Float(j) + dv) / Float(height)
        let d = MGRTEnvironment.direction(u: uu, v: vv)
        let sinTheta = sin(Float.pi * vv)
        guard sinTheta > 1e-6 else { return (d, 0) }
        return (d, pdfUV[j * width + i] / (2 * Float.pi * Float.pi * sinTheta))
    }

    /// Solid-angle pdf of sampling `d`.
    public func pdf(_ d: SIMD3<Float>) -> Float {
        let uv = MGRTEnvironment.uv(d)
        let i = min(width - 1, Int(uv.x * Float(width))), j = min(height - 1, Int(uv.y * Float(height)))
        let sinTheta = sqrt(max(0, 1 - d.y * d.y))
        guard sinTheta > 1e-6 else { return 0 }
        return pdfUV[j * width + i] / (2 * Float.pi * Float.pi * sinTheta)
    }
}
