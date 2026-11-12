// SPDX-License-Identifier: Apache-2.0
import Foundation

/// How the built-in renderer presents a solid: backdrop, exposure and tone, environment fill, shadow strength.
///
/// A look is pixels only. It never changes geometry, motion, cameras, framing, checks or any JSON the engine writes:
/// `snapshot.json` keeps `MGStudioLighting.studio` and each part's material parameters (what other renderers read);
/// a look scales that rig, reflects its own room and finishes surfaces inside this renderer only. `classic` is the renderer as it was before looks existed, unchanged.
/// See docs/VISUAL-STYLE.md.
public struct MGSolidLook: Equatable, Sendable {
    public var name: String
    /// Backdrop colours (sRGB 0...1): the light pool under the subject, and the far edge of the sweep.
    public var pool: [Double]
    public var edge: [Double]
    /// Pool radius as a multiple of the subject's projected radius.
    public var poolRadius: Double
    /// Darkening toward the frame corners (0 = none), backdrop only: the subject is never vignetted.
    public var vignette: Double
    /// Environment grey levels (zenith, horizon, floor), multiplied into the rig's environment colours' places.
    public var envZenith: Double
    public var envHorizon: Double
    public var envFloor: Double
    /// Multipliers on the rig: environment intensity, soft boxes, key, fill and rim lights.
    public var envIntensity: Double
    public var softboxes: Double
    public var key: Double
    public var fill: Double
    public var rim: Double
    /// Camera: exposure offset in stops, white point, contrast, saturation, bloom intensity.
    public var exposure: Double
    public var whitePoint: Double
    public var contrast: Double
    public var saturation: Double
    public var bloom: Double
    /// Screen-space ambient occlusion intensity.
    public var occlusion: Double
    /// Opacity of the key light's ground shadow and of the contact shadow under the subject.
    public var shadow: Double
    public var contact: Double
    /// Soft-shadow radius multiplier.
    public var shadowSoftness: Double
    /// The room the parts reflect (image-based lighting). Nil: the rig's environment at this look's levels. A look's
    /// own room is what gives metals and clear coats something to reflect; the rig's lights keep their directions.
    public var environment: MGStudioLighting.Environment? = nil
    /// How much of a soft box's half-size is its soft edge (0.25 = the rig's boxes; larger = longer gradients).
    public var boxFeather = 0.25
    /// Ambient-occlusion bias as a fraction of the camera distance (0 = the classic fixed bias). A bias that follows
    /// the scene's size keeps curved faces from occluding themselves in rings.
    public var occlusionBias = 0.0
    /// Surface finish, renderer only: the clear coat on plastics (strength, roughness; nil = the preset's own) and
    /// the strength of fine turning marks on machined metals (0 = none).
    public var plasticCoat: Double? = nil
    public var plasticCoatRoughness = 0.1
    public var machining = 0.0

    /// The renderer before looks existed: a near-black radial backdrop. Every pixel is as it was.
    public static let classic = MGSolidLook(
        name: "classic", pool: [0.09, 0.11, 0.16], edge: [0.02, 0.025, 0.042], poolRadius: 2.2, vignette: 0,
        envZenith: 1, envHorizon: 1, envFloor: 1, envIntensity: 1, softboxes: 1, key: 1, fill: 1, rim: 1,
        exposure: 0, whitePoint: 1, contrast: 0, saturation: 1, bloom: 0.22, occlusion: 0.9, shadow: 0.62, contact: 1,
        shadowSoftness: 1)

    /// A product studio to reflect: a dim room with large bright soft boxes (overhead, two tall strips, a rim band
    /// behind and a low card in front). `gain` scales the boxes; `room` scales the room's own grey.
    public static func productStudio(gain: Double, room: Double = 1) -> MGStudioLighting.Environment {
        MGStudioLighting.Environment(
            zenith: [0.06, 0.065, 0.075].map { min(0.9, $0 * room) }, horizon: [0.10, 0.105, 0.115].map { min(0.9, $0 * room) },
            floor: [0.035, 0.035, 0.04].map { min(0.9, $0 * room) },
            softboxes: [[25, 62, 95, 40, 1, 0.98, 0.96, 9 * gain],
                        [-80, 12, 16, 70, 0.9, 0.95, 1, 6 * gain],
                        [105, 14, 14, 64, 1, 0.96, 0.92, 4.5 * gain],
                        [180, 28, 110, 14, 0.85, 0.92, 1, 4 * gain],
                        [0, -8, 120, 10, 1, 1, 1, 0.8 * gain]],
            intensity: 1)
    }

    /// Graphite studio (dark): a lit floor pool on a graphite sweep, so dark parts keep their outline and shadows
    /// show; parts reflect a product studio, lit more by its soft boxes than by the key light; no bloom and a high
    /// white point so whites keep their form; coated plastics and machined metals.
    public static let studio: MGSolidLook = {
        var l = MGSolidLook(
            name: "studio", pool: [0.270, 0.288, 0.325], edge: [0.050, 0.055, 0.070], poolRadius: 1.8, vignette: 0.30,
            envZenith: 1, envHorizon: 1, envFloor: 1, envIntensity: 1, softboxes: 1, key: 0.5, fill: 1.25, rim: 0.9,
            exposure: -0.15, whitePoint: 1.8, contrast: 0.10, saturation: 1.04, bloom: 0, occlusion: 0.6, shadow: 0.50,
            contact: 0.55, shadowSoftness: 1.5)
        l.environment = productStudio(gain: 2.4)
        l.boxFeather = 0.5
        l.occlusionBias = 0.0006
        l.plasticCoat = 0.8; l.plasticCoatRoughness = 0.06
        l.machining = 1
        return l
    }()

    /// Paper studio (light): the same boxes in a bright room on a near-white sweep, for print and light pages.
    public static let paper: MGSolidLook = {
        var l = MGSolidLook(
            name: "paper", pool: [0.930, 0.935, 0.945], edge: [0.720, 0.740, 0.770], poolRadius: 2.6, vignette: 0.10,
            envZenith: 1, envHorizon: 1, envFloor: 1, envIntensity: 1, softboxes: 1, key: 0.5, fill: 1.2, rim: 0.6,
            exposure: -0.30, whitePoint: 1.8, contrast: 0.16, saturation: 1.05, bloom: 0, occlusion: 0.45, shadow: 0.30,
            contact: 0.30, shadowSoftness: 1.6)
        l.environment = productStudio(gain: 1.5, room: 6)
        l.boxFeather = 0.5
        l.occlusionBias = 0.0006
        l.plasticCoat = 0.8; l.plasticCoatRoughness = 0.06
        l.machining = 1
        return l
    }()

    /// The looks by name, in a fixed order (`marty-solid render --look`).
    public static let names = ["classic", "studio", "paper"]
    public static func named(_ name: String) -> MGSolidLook? {
        switch name {
        case "classic": return .classic
        case "studio": return .studio
        case "paper": return .paper
        default: return nil
        }
    }

    /// The rig as this look lights it: the same lights and directions, scaled, and the room the parts reflect (the
    /// look's own, or the rig's at this look's levels). Used inside the renderer only.
    public func lighting(_ rig: MGStudioLighting) -> MGStudioLighting {
        guard self != .classic else { return rig }
        var l = rig
        for i in l.lights.indices {
            switch l.lights[i].name {
            case "key": l.lights[i].intensity *= key
            case "fill": l.lights[i].intensity *= fill
            case "rim": l.lights[i].intensity *= rim
            default: break
            }
        }
        if let environment { l.environment = environment; return l }
        // A neutral studio: the gradient keeps the rig's slight cool tint, at this look's levels (capped below the
        // soft boxes so they still read as lights).
        l.environment.zenith = l.environment.zenith.map { min(0.9, $0 * envZenith) }
        l.environment.horizon = l.environment.horizon.map { min(0.9, $0 * envHorizon) }
        l.environment.floor = l.environment.floor.map { min(0.9, $0 * envFloor) }
        l.environment.softboxes = l.environment.softboxes.map { s in
            guard s.count == 8 else { return s }
            var t = s; t[7] *= softboxes; return t
        }
        l.environment.intensity *= envIntensity
        return l
    }

    /// Where the backdrop's light pool sits in a frame: centre and radii in pixels (origin top-left).
    public struct Pool: Equatable, Sendable {
        public var x: Double, y: Double, rx: Double, ry: Double
        public init(x: Double, y: Double, rx: Double, ry: Double) { self.x = x; self.y = y; self.rx = rx; self.ry = ry }
        /// The pool of a frame with no subject: a wide pool a little below the middle.
        public static func centred(width: Int, height: Int) -> Pool {
            let m = Double(max(width, height))
            return Pool(x: Double(width) * 0.5, y: Double(height) * 0.58, rx: m * 0.62, ry: m * 0.62 * 0.6)
        }
    }

    /// The backdrop as `width * height` RGBA bytes (sRGB, opaque, rows from the top): a soft pool of light falling
    /// off to the edge colour, a corner vignette, and a fixed half-level dither so the slow gradient never bands in
    /// 8 bits. It is a pure function of its arguments (CPU, no randomness), so it is byte-identical in every run.
    public func backdrop(width: Int, height: Int, pool: Pool) -> [UInt8] {
        let w = max(1, width), h = max(1, height)
        // A pool that is not finite (a degenerate camera) falls back to the centred pool.
        let p = [pool.x, pool.y, pool.rx, pool.ry].allSatisfy(\.isFinite) ? pool : Pool.centred(width: w, height: h)
        var out = [UInt8](repeating: 255, count: w * h * 4)
        let rx = max(1, p.rx), ry = max(1, p.ry)
        let cx = Double(w) * 0.5, cy = Double(h) * 0.5
        let corner = cx * cx + cy * cy
        let c0 = self.pool, c1 = edge
        out.withUnsafeMutableBufferPointer { px in
            for y in 0..<h {
                let dy = (Double(y) + 0.5 - p.y) / ry
                let vy = Double(y) + 0.5 - cy
                for x in 0..<w {
                    let dx = (Double(x) + 0.5 - p.x) / rx
                    // A Lorentzian pool: full at the centre, half at one radius, a long soft tail.
                    let g = 1 / (1 + dx * dx + dy * dy)
                    let vx = Double(x) + 0.5 - cx
                    let v = 1 - vignette * (vx * vx + vy * vy) / corner
                    // Triangular dither in -1...1 levels from two integer hashes of the pixel.
                    var n = UInt32(truncatingIfNeeded: x &* 1973 &+ y &* 9277 &+ 0x68BC21EB)
                    n = (n ^ (n >> 15)) &* 0x2C1B3C6D; n = (n ^ (n >> 12)) &* 0x297A2D39; n ^= n >> 15
                    let d = (Double(n & 0xFFFF) + Double((n >> 16) & 0xFFFF)) / 65535 - 1
                    let i = (y * w + x) * 4
                    for k in 0..<3 {
                        let c = (c1[k] + (c0[k] - c1[k]) * g) * v * 255 + d * 0.5
                        px[i + k] = UInt8(min(255, max(0, c.rounded())))
                    }
                }
            }
        }
        return out
    }
}
