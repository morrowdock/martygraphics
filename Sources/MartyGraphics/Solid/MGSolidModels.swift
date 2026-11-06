// SPDX-License-Identifier: Apache-2.0
import Foundation

/// A built planetary gear set and the numbers needed to check it.
public struct MGPlanetaryModel: Sendable {
    public var assembly: MGAssembly
    public var sun: MGSpurGear
    public var planet: MGSpurGear
    public var ring: MGRingGear
    public var planetCount: Int
    /// Distance from the central axis to each planet axis (sun + planet pitch radii).
    public var carrierRadius: Double
    /// Planet centre directions in the carrier frame.
    public var planetAngles: [Double]
    /// Planet tooth phase at input 0 (carrier frame) and the ring's space phase.
    public var planetPhases: [Double]
    public var ringPhase: Double
    /// Carrier turns per sun turn with the ring held: zSun / (zSun + zRing).
    public var carrierRatio: Double
    public var faceWidth: Double
    public static let sunID = "sun", ringID = "ring", carrierID = "carrier"
    public static func planetID(_ i: Int) -> String { "planet\(i + 1)" }
}

/// A built in-line slider-crank and its dimensions.
public struct MGSliderCrankModel: Sendable {
    public var assembly: MGAssembly
    public var crankRadius: Double
    public var rodLength: Double
    public static let crankID = "crank", pistonID = "piston", rodID = "rod"
}

public enum MGSolidModelError: Error, Equatable, CustomStringConvertible {
    case invalid(String)
    public var description: String { switch self { case .invalid(let m): return m } }
}

/// Original synthetic teaching models built from the solid kernel.
public enum MGSolidModels {
    /// Simple planetary (epicyclic) gear set: sun input, fixed ring, carrier output.
    ///
    /// Requires `ringTeeth == sunTeeth + 2 * planetTeeth` (coaxial centres) and `(sunTeeth + ringTeeth)` divisible by
    /// `planets` (equally spaced planets can all mesh). Units are millimetres; the gear axis is +Z.
    public static func planetary(sunTeeth: Int = 24, planetTeeth: Int = 18, ringTeeth: Int = 60, planets: Int = 3,
                                 module: Double = 2, faceWidth: Double = 14) throws -> MGPlanetaryModel {
        guard ringTeeth == sunTeeth + 2 * planetTeeth else {
            throw MGSolidModelError.invalid("ring teeth must equal sun teeth + 2 x planet teeth")
        }
        guard planets >= 2, (sunTeeth + ringTeeth) % planets == 0 else {
            throw MGSolidModelError.invalid("sun + ring teeth must be divisible by the planet count")
        }
        let m = module, fw = faceWidth
        let sun = MGSpurGear(teeth: sunTeeth, module: m)
        let planet = MGSpurGear(teeth: planetTeeth, module: m)
        let ringOuter = MGRingGear(teeth: ringTeeth, module: m, outerRadius: 0).rootRadius + 3.2 * m
        let d = sun.pitchRadius + planet.pitchRadius
        let betas = (0..<planets).map { 2 * Double.pi * Double($0) / Double(planets) }
        let phases = betas.map { MGGearPhase.external(zA: sunTeeth, phaseA: 0, zB: planetTeeth, beta: $0) }
        let ringPhase = MGGearPhase.ringSpaces(zRing: ringTeeth, zPlanet: planetTeeth, phasePlanet: phases[0], beta: betas[0])
        let ring = MGRingGear(teeth: ringTeeth, module: m, outerRadius: ringOuter)
        let ratio = Double(sunTeeth) / Double(sunTeeth + ringTeeth)
        let chamfer = 0.28 * m
        let z = MGVec3.unitZ

        var parts: [MGPart] = []
        // Housing base, bolts.
        let baseR = ringOuter + 15.1, boltR = ringOuter + 7.6
        let boltHoles = (0..<6).map { MGProfile.circleLoop(radius: 2.6, segments: 32, center: .polar(boltR, Double($0) * .pi / 3 + .pi / 6)) }
        let baseProfile = MGProfile(outer: MGProfile.circleLoop(radius: baseR, segments: 192),
                                    holes: [MGProfile.circleLoop(radius: 8, segments: 48)] + boltHoles)
        parts.append(MGPart(id: "base", name: "Housing base", mesh: .extrude(baseProfile, from: -9, to: -1.5, chamfer: 1.2),
                            material: .plastic(.muted), explode: MGVec3(0, 0, -46), explodeWindow: 0.35...1))
        for k in 0..<6 {
            let c = MGVec2.polar(boltR, Double(k) * .pi / 3 + .pi / 6)
            let bolt = MGMesh.merged([.hexPrism(acrossFlats: 7, from: -1.5, to: 2.6, chamfer: 0.6),
                                      .cylinder(radius: 2.5, from: -9.5, to: -1.4, chamfer: 0.3, segments: 32)])
            parts.append(MGPart(id: "bolt\(k + 1)", name: "Bolt", mesh: bolt, material: .blackOxide,
                                placement: .translation(MGVec3(c.x, c.y, 0)), parent: "base",
                                explode: MGVec3(0, 0, 16), explodeWindow: 0.0...0.4))
        }
        // Ring gear (held by the housing).
        parts.append(MGPart(id: MGPlanetaryModel.ringID, name: "Ring gear (\(ringTeeth)T, fixed)",
                            mesh: .extrude(ring.profile(phase: ringPhase, outerSegments: 240), from: -1.5, to: fw, chamfer: chamfer),
                            material: .darkSteel, explode: MGVec3(0, 0, -22), explodeWindow: 0.25...0.85))
        // Sun gear with input shaft.
        parts.append(MGPart(id: MGPlanetaryModel.sunID, name: "Sun gear (\(sunTeeth)T, input)",
                            mesh: .extrude(sun.profile(bore: 6, keyway: (width: 3, depth: 1.6)), from: 0, to: fw, chamfer: chamfer),
                            material: .brass, joint: .revolute(axis: z), drive: .input(scale: 1, offset: 0)))
        parts.append(MGPart(id: "inputShaft", name: "Input shaft",
                            mesh: .merged([.cylinder(radius: 5.92, from: -9, to: fw + 2.5, chamfer: 0.6),
                                           .chamferedBox(size: MGVec3(2.9, 2.9, fw - 2), chamfer: 0.3).transformed(.translation(MGVec3(6.0, 0, fw / 2)))]),
                            material: .brushedSteel, parent: MGPlanetaryModel.sunID, explode: MGVec3(0, 0, -30), explodeWindow: 0.45...1))
        // Carrier (spider plate, pins, output shaft).
        let plateZ0 = fw + 3.0, plateZ1 = fw + 9.0
        let spider = spiderOutline(armRadius: d, hubRadius: 15, bossRadius: 9.5, armHalfWidth: 6.5, blend: 5, samples: 720)
        let carrierMesh = MGMesh.merged([
            .extrude(MGProfile(outer: spider), from: plateZ0, to: plateZ1, chamfer: 0.9),
            .revolve([MGVec2(0, plateZ1 - 0.5), MGVec2(15, plateZ1 - 0.5), MGVec2(15, plateZ1 + 2.2), MGVec2(13.6, plateZ1 + 3.6), MGVec2(0, plateZ1 + 3.6)],
                     segments: 96, closed: false)])
        parts.append(MGPart(id: MGPlanetaryModel.carrierID, name: "Planet carrier (output)", mesh: carrierMesh, material: .anodized(.blue),
                        joint: .revolute(axis: z), drive: .follow(source: MGPlanetaryModel.sunID, ratio: ratio, offset: 0),
                        explode: MGVec3(0, 0, 50), explodeWindow: 0.0...0.6))
        parts.append(MGPart(id: "outputShaft", name: "Output shaft",
                            mesh: .merged([.cylinder(radius: 9, from: plateZ1 + 3, to: plateZ1 + 30, chamfer: 0.9),
                                           .chamferedBox(size: MGVec3(4, 4.5, 16), chamfer: 0.4).transformed(.translation(MGVec3(9.4, 0, plateZ1 + 19)))]),
                            material: .brushedSteel, parent: MGPlanetaryModel.carrierID, explode: MGVec3(0, 0, 18), explodeWindow: 0.1...0.7))
        for (i, b) in betas.enumerated() {
            let c = MGVec2.polar(d, b)
            parts.append(MGPart(id: "pin\(i + 1)", name: "Planet pin",
                                mesh: .cylinder(radius: 4, from: -0.8, to: plateZ1 + 1.4, chamfer: 0.5, segments: 48),
                                material: .polishedSteel, placement: .translation(MGVec3(c.x, c.y, 0)), parent: MGPlanetaryModel.carrierID))
            let planetMesh = MGMesh.merged([.extrude(planet.profile(bore: 4.3), from: 0.4, to: fw - 0.4, chamfer: chamfer)])
            parts.append(MGPart(id: MGPlanetaryModel.planetID(i), name: "Planet gear (\(planetTeeth)T)", mesh: planetMesh,
                                material: .brushedSteel, placement: .translation(MGVec3(c.x, c.y, 0)), parent: MGPlanetaryModel.carrierID,
                                joint: .revolute(axis: z),
                                drive: .gear(driver: MGPlanetaryModel.sunID, ratio: -Double(sunTeeth) / Double(planetTeeth),
                                             carrier: MGPlanetaryModel.carrierID, offset: phases[i]),
                                explode: MGVec3(0, 0, -28), explodeWindow: 0.12...0.75))
        }
        var pairs: [MGGearPair] = []
        for i in 0..<planets {
            pairs.append(MGGearPair(a: MGPlanetaryModel.sunID, b: MGPlanetaryModel.planetID(i), teethA: sunTeeth, teethB: planetTeeth,
                                    carrier: MGPlanetaryModel.carrierID))
            pairs.append(MGGearPair(a: MGPlanetaryModel.ringID, b: MGPlanetaryModel.planetID(i), teethA: ringTeeth, teethB: planetTeeth,
                                    isInternal: true, carrier: MGPlanetaryModel.carrierID))
        }
        let assembly = MGAssembly(name: "Planetary gear set", parts: parts, gearPairs: pairs)
        return MGPlanetaryModel(assembly: assembly, sun: sun, planet: planet, ring: ring, planetCount: planets, carrierRadius: d,
                                planetAngles: betas, planetPhases: phases, ringPhase: ringPhase, carrierRatio: ratio, faceWidth: fw)
    }

    /// Star-shaped outline of a three-arm carrier: a hub, radial arms and pin bosses joined by a smooth union.
    static func spiderOutline(armRadius: Double, hubRadius: Double, bossRadius: Double, armHalfWidth: Double, blend: Double, samples: Int, arms: Int = 3) -> [MGVec2] {
        func smin(_ a: Double, _ b: Double, _ k: Double) -> Double {
            let h = max(k - abs(a - b), 0) / k
            return min(a, b) - h * h * k / 4
        }
        func sdf(_ p: MGVec2) -> Double {
            var d = p.length - hubRadius
            for i in 0..<arms {
                let dir = MGVec2.polar(1, 2 * .pi * Double(i) / Double(arms)), c = dir * armRadius
                let t = max(0, min(armRadius, p.dot(dir)))
                let arm = (p - dir * t).length - armHalfWidth
                let boss = (p - c).length - bossRadius
                d = smin(d, smin(arm, boss, blend), blend)
            }
            return d
        }
        let maxR = armRadius + bossRadius + blend
        return (0..<samples).map { s in
            let a = 2 * Double.pi * Double(s) / Double(samples), u = MGVec2.polar(1, a)
            // Outermost boundary crossing along the ray (shape is star-shaped about the origin).
            var lo = 0.0, hi = maxR
            let steps = 64
            for k in stride(from: steps, through: 0, by: -1) {
                let t = maxR * Double(k) / Double(steps)
                if sdf(u * t) < 0 { lo = t; hi = min(maxR, t + maxR / Double(steps)); break }
            }
            for _ in 0..<40 { let mid = (lo + hi) / 2; if sdf(u * mid) < 0 { lo = mid } else { hi = mid } }
            return u * lo
        }
    }

    /// In-line slider-crank: crank disc with pin, connecting rod, piston in a cylinder sleeve. Axis of the crank is
    /// +Z; the piston slides along +X. Units are millimetres.
    public static func sliderCrank(crankRadius r: Double = 18, rodLength l: Double = 62) throws -> MGSliderCrankModel {
        guard l > r + 10 else { throw MGSolidModelError.invalid("rod must be longer than the crank radius plus clearance") }
        let z = MGVec3.unitZ
        var parts: [MGPart] = []
        let rest = r + l  // piston pin x at top dead centre
        // Frame: base block and crank bearing housing.
        parts.append(MGPart(id: "frame", name: "Frame", mesh: .merged([
            .chamferedBox(size: MGVec3(rest + 70, 64, 8), chamfer: 1.5).transformed(.translation(MGVec3((rest + 30) / 2 - 10, 0, -22))),
            .tube(inner: 6.2, outer: 14, from: -18, to: -6, chamfer: 1, segments: 72)]),
            material: .darkSteel, explode: MGVec3(0, 0, -24), explodeWindow: 0.3...1))
        // Cylinder sleeve along X (a tube rotated so its axis is X), cut away by the renderer's section plane.
        let sleeve = MGMesh.tube(inner: 16.4, outer: 20, from: 0, to: 64, chamfer: 0.8, segments: 96)
            .transformed(.rotation(axis: .unitY, angle: .pi / 2))
            .transformed(.translation(MGVec3(rest - 30, 0, 0)))
        parts.append(MGPart(id: "cylinder", name: "Cylinder (cutaway)", mesh: sleeve, material: .darkSteel,
                            explode: MGVec3(0, 0, 30), explodeWindow: 0.0...0.5))
        // Crank: disc web + shaft + crank pin.
        let web = MGProfile(outer: spiderOutline(armRadius: r, hubRadius: 13, bossRadius: 8, armHalfWidth: 7, blend: 6, samples: 360, arms: 1))
        parts.append(MGPart(id: MGSliderCrankModel.crankID, name: "Crank", mesh: .merged([
            .extrude(web, from: -6, to: 0, chamfer: 0.8),
            .cylinder(radius: 6, from: -20, to: -5.5, chamfer: 0.6),
            .cylinder(radius: 5, from: -0.5, to: 9, chamfer: 0.5, segments: 64).transformed(.translation(MGVec3(r, 0, 0)))]),
            material: .brushedSteel, joint: .revolute(axis: z), drive: .input(scale: 1, offset: 0),
            explode: MGVec3(0, 0, -10), explodeWindow: 0.2...0.8))
        // Piston (lathe profile around its own axis, then laid along X) with wrist pin.
        let pistonProfile: [MGVec2] = [MGVec2(0, -12), MGVec2(15.2, -12), MGVec2(16, -11), MGVec2(16, -8), MGVec2(15.2, -8), MGVec2(15.2, -6.5),
                                       MGVec2(16, -6.5), MGVec2(16, -4), MGVec2(15.2, -4), MGVec2(15.2, -2.5), MGVec2(16, -2.5),
                                       MGVec2(16, 12), MGVec2(15, 13), MGVec2(0, 13)]
        let pistonBody = MGMesh.revolve(pistonProfile, segments: 96, closed: false)
            .transformed(.rotation(axis: .unitY, angle: .pi / 2)).transformed(.translation(MGVec3(6, 0, 0)))
        parts.append(MGPart(id: MGSliderCrankModel.pistonID, name: "Piston", mesh: .merged([
            pistonBody, .cylinder(radius: 4, from: -14, to: 14, chamfer: 0.4, segments: 48).transformed(.rotation(axis: .unitX, angle: .pi / 2))]),
            material: .aluminum, joint: .prismatic(axis: .unitX),
            drive: .crankSlider(crank: MGSliderCrankModel.crankID, crankRadius: r, rodLength: l, offset: 0),
            explode: MGVec3(26, 0, 0), explodeWindow: 0.1...0.7))
        // Connecting rod from the wrist pin (origin) back along -X to the crank pin.
        let rodOutline = spiderOutline(armRadius: l, hubRadius: 9, bossRadius: 11, armHalfWidth: 4.5, blend: 7, samples: 540, arms: 1)
            .map { MGVec2(-$0.x, -$0.y) }
        let rodProfile = MGProfile(outer: rodOutline, holes: [MGProfile.circleLoop(radius: 4.2, segments: 40),
                                                              MGProfile.circleLoop(radius: 5.2, segments: 48, center: MGVec2(-l, 0))])
        parts.append(MGPart(id: MGSliderCrankModel.rodID, name: "Connecting rod",
                            mesh: .extrude(rodProfile, from: 1.5, to: 6.5, chamfer: 0.7), material: .anodized(.orange),
                            placement: .identity, parent: MGSliderCrankModel.pistonID, joint: .revolute(axis: z),
                            drive: .crankRod(crank: MGSliderCrankModel.crankID, crankRadius: r, rodLength: l),
                            explode: MGVec3(0, 0, 22), explodeWindow: 0.0...0.6))
        return MGSliderCrankModel(assembly: MGAssembly(name: "Slider-crank", parts: parts), crankRadius: r, rodLength: l)
    }
}
