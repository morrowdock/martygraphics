// SPDX-License-Identifier: Apache-2.0
// Example-local scene: a two-stage reduction gearbox built from the procedural parts in
// GearGeometry.swift. Stage 1: 15-tooth pinion drives a 30-tooth spur gear (2:1).
// Stage 2: planetary set, sun 24 / planets 18 (x3) / fixed ring 60, output on the carrier (3.5:1).
// Overall 7:1. All dimensions are scene units; module 0.09 (spur) and 0.08 (planetary).
import Foundation
import simd
import MartyGraphicsPathTracer

struct Gearbox {
    // GEAR TRAIN BEGIN: these lines set every tooth count and module (the side-by-side frame quotes them verbatim).
    static let pinionTeeth = 15, spurTeeth = 30
    static let sunTeeth = 24, planetTeeth = 18, ringTeeth = 60
    static let spurModule = 0.09, planetModule = 0.08
    static let planets = 3
    // GEAR TRAIN END

    static var stage1Ratio: Double { Double(spurTeeth) / Double(pinionTeeth) }
    static var stage2Ratio: Double { 1 + Double(ringTeeth) / Double(sunTeeth) }
    static var carrierRadius: Float { Float(Double(sunTeeth + planetTeeth) * planetModule / 2) }
    static var spurCentreDistance: Float { Float(Double(pinionTeeth + spurTeeth) * spurModule / 2) }
    /// Direction (angle in the x-z plane) from the main axis to the pinion axis.
    static let pinionBearing: Double = -0.35 * .pi

    enum Part: Int, CaseIterable {
        case floor, base, ring, carrier, planet0, planet1, planet2, sun, spur, collar, pinion, pinionShaft
    }

    /// Materials, by index.
    enum M: UInt32 { case floor, base, brushedSteel, polishedSteel, brass, gunmetal, chrome, blackOxide }

    static let materials: [MGRTMaterial] = [
        .plastic(SIMD3(0.010, 0.010, 0.011), roughness: 0.32, specular: 0.6),           // floor: dark satin
        .plastic(SIMD3(0.018, 0.019, 0.021), roughness: 0.42, specular: 0.8, coat: 0.0), // base: black anodised
        .metal(MGRTMaterial.steel, roughness: 0.34, anisotropy: 0.75),                    // brushed steel ring
        .metal(MGRTMaterial.steel * 1.05, roughness: 0.16),                               // polished steel
        .metal(MGRTMaterial.brass, roughness: 0.22),                                      // brass
        .metal(SIMD3(0.30, 0.30, 0.32), roughness: 0.30),                                 // gunmetal carrier
        .metal(MGRTMaterial.chrome * 1.25, roughness: 0.07),                              // chrome shafts
        .metal(SIMD3(0.06, 0.06, 0.065), roughness: 0.25, coat: 0.6, coatRoughness: 0.08), // black oxide collar
    ]

    let meshes: [MGRTMesh]
    /// Mesh index for each part (instances in `Part` order).
    let partMesh: [Part: Int]
    let triangleCount: Int

    init() {
        var meshes: [MGRTMesh] = []
        var partMesh: [Part: Int] = [:]
        func add(_ part: Part, _ m: MGRTMesh) { partMesh[part] = meshes.count; meshes.append(m) }

        let sunSpec = Involute.Spec(teeth: Self.sunTeeth, module: Self.planetModule)
        let planetSpec = Involute.Spec(teeth: Self.planetTeeth, module: Self.planetModule)
        let ringSpec = Involute.Spec(teeth: Self.ringTeeth, module: Self.planetModule)
        let spurSpec = Involute.Spec(teeth: Self.spurTeeth, module: Self.spurModule)
        let pinionSpec = Involute.Spec(teeth: Self.pinionTeeth, module: Self.spurModule)

        var b = MeshBuilder()
        Solids.floor(halfSize: 40, cells: 40, into: &b)
        add(.floor, b.mesh(material: M.floor.rawValue))

        b = MeshBuilder()
        Solids.lathe(Solids.cylinderProfile(outer: 3.35, y0: 0, y1: 0.22, chamfer: 0.035), segments: 256, into: &b)
        add(.base, b.mesh(material: M.base.rawValue))

        // Ring gear: internal teeth, plain outer wall.
        b = MeshBuilder()
        let ringInner = Involute.internal(ringSpec)
        Solids.annulus(outer: Solids.circle(radius: 2.78, like: ringInner), inner: ringInner, y0: 0.22, y1: 0.82,
                       chamfer: 0.018, into: &b)
        add(.ring, b.mesh(material: M.brushedSteel.rawValue))

        // Carrier: plate, hub and three planet pins.
        b = MeshBuilder()
        Solids.lathe(Solids.cylinderProfile(outer: 1.98, y0: 0.27, y1: 0.41, chamfer: 0.02), segments: 192, into: &b)
        var pins = MeshBuilder()
        Solids.lathe(Solids.cylinderProfile(outer: 0.155, y0: 0.40, y1: 1.02, chamfer: 0.025), segments: 48, into: &pins)
        let pinTris = pins.triangles
        for k in 0..<Self.planets {
            let a = Float(k) * 2 * .pi / Float(Self.planets)
            let off = SIMD3<Float>(Self.carrierRadius * cos(a), 0, Self.carrierRadius * sin(a))
            for t in pinTris {
                let n = simd_cross(t.1 - t.0, t.2 - t.0)
                b.tri(t.0 + off, t.1 + off, t.2 + off, outward: n)
            }
        }
        add(.carrier, b.mesh(material: M.gunmetal.rawValue))

        b = MeshBuilder()
        let planetOuter = Involute.external(planetSpec)
        Solids.annulus(outer: planetOuter, inner: Solids.circle(radius: 0.17, like: planetOuter), y0: 0.44, y1: 0.94,
                       chamfer: 0.014, into: &b)
        let planetMesh = b.mesh(material: M.brass.rawValue)
        add(.planet0, planetMesh)
        partMesh[.planet1] = partMesh[.planet0]
        partMesh[.planet2] = partMesh[.planet0]

        // Sun gear with its shaft.
        b = MeshBuilder()
        let sunOuter = Involute.external(sunSpec)
        Solids.annulus(outer: sunOuter, inner: Solids.circle(radius: 0.225, like: sunOuter), y0: 0.44, y1: 0.94,
                       chamfer: 0.014, into: &b)
        Solids.lathe(Solids.cylinderProfile(outer: 0.22, y0: 0.30, y1: 2.05, chamfer: 0.03), segments: 96, into: &b)
        add(.sun, b.mesh(material: M.polishedSteel.rawValue))

        // Spur gear: toothed rim, recessed web and hub.
        b = MeshBuilder()
        let spurOuter = Involute.external(spurSpec)
        let rimInner: Float = Float(spurSpec.pitchRadius - 1.25 * Self.spurModule) - 0.13
        Solids.annulus(outer: spurOuter, inner: Solids.circle(radius: rimInner, like: spurOuter), y0: 1.25, y1: 1.60,
                       chamfer: 0.016, into: &b)
        Solids.lathe([SIMD2(0.40, 1.365), SIMD2(rimInner + 0.01, 1.365), SIMD2(rimInner + 0.01, 1.485), SIMD2(0.40, 1.485)],
                     segments: 192, into: &b)
        Solids.lathe(Solids.cylinderProfile(outer: 0.44, inner: 0.225, y0: 1.20, y1: 1.66, chamfer: 0.03), segments: 128, into: &b)
        add(.spur, b.mesh(material: M.polishedSteel.rawValue))

        b = MeshBuilder()
        Solids.lathe(Solids.cylinderProfile(outer: 0.34, inner: 0.22, y0: 1.66, y1: 1.82, chamfer: 0.025), segments: 96, into: &b)
        add(.collar, b.mesh(material: M.blackOxide.rawValue))

        b = MeshBuilder()
        let pinionOuter = Involute.external(pinionSpec)
        Solids.annulus(outer: pinionOuter, inner: Solids.circle(radius: 0.15, like: pinionOuter), y0: 1.25, y1: 1.60,
                       chamfer: 0.014, into: &b)
        Solids.lathe(Solids.cylinderProfile(outer: 0.27, inner: 0.15, y0: 1.60, y1: 1.78, chamfer: 0.02), segments: 96, into: &b)
        add(.pinion, b.mesh(material: M.brass.rawValue))

        b = MeshBuilder()
        Solids.lathe(Solids.cylinderProfile(outer: 0.15, y0: 1.12, y1: 2.55, chamfer: 0.03), segments: 64, into: &b)
        add(.pinionShaft, b.mesh(material: M.chrome.rawValue))

        self.meshes = meshes
        self.partMesh = partMesh
        triangleCount = Part.allCases.reduce(0) { $0 + meshes[partMesh[$1]!].triangleCount }
    }

    // MARK: Kinematics

    /// Angles (radians, about +y in the x-z plane convention of the profiles) at carrier angle `c`.
    struct Pose {
        var carrier: Double
        var sun: Double
        var planetCentre: [Double]
        var planet: [Double]
        var spur: Double
        var pinion: Double
    }

    /// Mesh phase for an external pair: driven gear B at bearing `beta` from gear A.
    static func externalPhase(beta: Double, angleA: Double, teethA: Int, teethB: Int) -> Double {
        let fA = (beta - angleA) * Double(teethA) / (2 * .pi)
        return beta + .pi - (2 * .pi / Double(teethB)) * (0.5 - fA)
    }

    static func pose(carrier c: Double) -> Pose {
        let sun = stage2Ratio * c  // ring fixed: ω_sun = (1 + Zr/Zs) ω_carrier
        var centres: [Double] = [], angles: [Double] = []
        for k in 0..<Self.planets {
            let beta = c + Double(k) * 2 * .pi / Double(Self.planets)
            centres.append(beta)
            angles.append(externalPhase(beta: beta, angleA: sun, teethA: sunTeeth, teethB: planetTeeth))
        }
        let spur = sun  // keyed to the sun shaft
        let pinion = externalPhase(beta: pinionBearing, angleA: spur, teethA: spurTeeth, teethB: pinionTeeth)
        return Pose(carrier: c, sun: sun, planetCentre: centres, planet: angles, spur: spur, pinion: pinion)
    }

    /// Ring-mesh residual in tooth fractions for each planet (0 means perfect mesh; checked by --verify).
    static func ringResidual(_ p: Pose) -> [Double] {
        (0..<planets).map { k in
            let beta = p.planetCentre[k]
            let fR = beta * Double(ringTeeth) / (2 * .pi)
            let fP = (beta - p.planet[k]) * Double(planetTeeth) / (2 * .pi)
            var r = (fR - fP - 0.5).truncatingRemainder(dividingBy: 1)
            if r > 0.5 { r -= 1 }
            if r < -0.5 { r += 1 }
            return r
        }
    }

    /// Rotation about +y that maps profile angle θ to θ + a (x' = x cos a - z sin a, z' = x sin a + z cos a).
    static func rotY(_ a: Double) -> simd_float4x4 {
        let c = Float(cos(a)), s = Float(sin(a))
        return simd_float4x4(columns: (SIMD4(c, 0, s, 0), SIMD4(0, 1, 0, 0), SIMD4(-s, 0, c, 0), SIMD4(0, 0, 0, 1)))
    }

    static func translate(_ t: SIMD3<Float>) -> simd_float4x4 {
        var m = matrix_identity_float4x4
        m.columns.3 = SIMD4(t, 1)
        return m
    }

    /// Per-instance transforms for a pose and per-part lift (explode) heights.
    func transforms(_ p: Pose, lift: [Part: Float]) -> [simd_float4x4] {
        Part.allCases.map { part in
            let up = SIMD3<Float>(0, lift[part] ?? 0, 0)
            switch part {
            case .floor, .base, .ring: return Self.translate(up)
            case .carrier: return Self.translate(up) * Self.rotY(p.carrier)
            case .planet0, .planet1, .planet2:
                let k = part.rawValue - Part.planet0.rawValue
                let a = p.planetCentre[k]
                let centre = SIMD3<Float>(Self.carrierRadius * Float(cos(a)), 0, Self.carrierRadius * Float(sin(a)))
                return Self.translate(centre + up) * Self.rotY(p.planet[k])
            case .sun: return Self.translate(up) * Self.rotY(p.sun)
            case .spur, .collar: return Self.translate(up) * Self.rotY(p.spur)
            case .pinion, .pinionShaft:
                let b = Self.pinionBearing
                let centre = SIMD3<Float>(Self.spurCentreDistance * Float(cos(b)), 0, Self.spurCentreDistance * Float(sin(b)))
                return Self.translate(centre + up) * Self.rotY(p.pinion)
            }
        }
    }

    // MARK: Timeline (seamless loop)

    static let loopSeconds = 10.0
    /// Carrier turns 1/3 per loop (one planet spacing), so every part returns to an identical pose:
    /// ring passes 20 teeth relative to the carrier; sun turns 7/6 (28 pitches); planets turn -7/9 of a turn (-14 pitches);
    /// spur gear 7/6 (35 pitches); pinion -7/3 turns (35 pitches).
    static let carrierPerLoop = 2 * Double.pi / 3

    static func smoothstep(_ x: Double) -> Double {
        let t = min(max(x, 0), 1)
        return t * t * t * (t * (6 * t - 15) + 10)
    }

    /// Explode amount 0...1 for a part at loop time `t`; staggered by layer.
    static func explode(_ t: Double, layer: Int) -> Double {
        let u = t / loopSeconds
        let stagger = 0.022 * Double(layer)
        let out = smoothstep((u - 0.30 - stagger) / 0.17)
        let back = smoothstep((u - 0.64 - (0.088 - stagger)) / 0.17)
        return out * (1 - back)
    }

    static let liftHeight: [Part: (layer: Int, height: Float)] = [
        .carrier: (0, 0.30), .planet0: (1, 0.95), .planet1: (1, 0.95), .planet2: (1, 0.95),
        .sun: (2, 1.65), .spur: (3, 2.35), .pinion: (3, 2.35), .pinionShaft: (3, 2.35), .collar: (4, 2.95),
    ]

    func frame(at t: Double) -> (transforms: [simd_float4x4], explode: Double) {
        let c = Self.carrierPerLoop * t / Self.loopSeconds
        var lift: [Part: Float] = [:]
        for (part, v) in Self.liftHeight { lift[part] = v.height * Float(Self.explode(t, layer: v.layer)) }
        let e = Self.explode(t, layer: 2)
        return (transforms(Self.pose(carrier: c), lift: lift), e)
    }

    static func camera(at t: Double, explode e: Double, aperture: Float = 0.045) -> MGRTCamera {
        let w = 2 * Double.pi * t / loopSeconds
        let yaw = (-34 + 9 * sin(w)) * Double.pi / 180
        let elevation = (25 + 6 * e) * Double.pi / 180
        let distance = 12.0 - 0.8 * sin(w) + 3.6 * e
        let target = SIMD3<Float>(0.15, Float(0.9 + 1.45 * e), 0)
        let dir = SIMD3<Float>(Float(cos(elevation) * sin(yaw)), Float(sin(elevation)), Float(cos(elevation) * cos(yaw)))
        let pos = target + Float(distance) * dir
        return MGRTCamera(position: pos, target: target, verticalFOVDegrees: 28, apertureRadius: aperture,
                          focusDistance: simd_length(pos - target) - 0.9)
    }

    // MARK: Lighting

    static let areaLights: [MGRTAreaLight] = [
        // Large overhead key, front-left.
        .softbox(center: SIMD3(-4.2, 8.0, 3.6), toward: SIMD3(0, 0.8, 0), size: SIMD2(5.0, 3.2),
                 radiance: SIMD3(1.0, 0.97, 0.93) * 5.5),
        // Wide top-back panel: what the flat gear faces reflect toward the camera.
        .softbox(center: SIMD3(4.6, 5.6, -6.8), toward: SIMD3(0, 0.6, 0), size: SIMD2(7.5, 3.4),
                 radiance: SIMD3(0.95, 0.97, 1.0) * 2.4, visibleToCamera: false),
        // Tall strip rim light, right.
        .softbox(center: SIMD3(6.8, 2.6, -1.2), toward: SIMD3(0, 1.0, 0), size: SIMD2(0.8, 4.6),
                 radiance: SIMD3(0.92, 0.96, 1.0) * 8.0, visibleToCamera: false),
        // Dim overhead panel far behind, aimed at the floor: a soft pool of light behind the subject.
        .softbox(center: SIMD3(3.0, 7.0, -13.0), toward: SIMD3(1.0, 0, -7.5), size: SIMD2(9.0, 6.0),
                 radiance: SIMD3(0.85, 0.9, 1.0) * 1.1, visibleToCamera: false),
        // Low kicker strip, back-left, for edge highlights on the teeth.
        .softbox(center: SIMD3(-6.0, 1.6, -3.0), toward: SIMD3(0, 0.9, 0), size: SIMD2(0.6, 3.5),
                 radiance: SIMD3(1.0, 0.95, 0.88) * 5.0, visibleToCamera: false),
    ]

    func scene(camera: MGRTCamera) -> MGRTScene {
        let instances = Part.allCases.map { MGRTInstance(mesh: partMesh[$0]!) }
        var env = MGRTEnvironment.studio()
        env.intensity = 0.85
        return MGRTScene(meshes: meshes, instances: instances, materials: Self.materials, camera: camera,
                         areaLights: Self.areaLights, environment: env)
    }
}
