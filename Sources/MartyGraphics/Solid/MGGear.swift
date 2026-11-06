// SPDX-License-Identifier: Apache-2.0
import Foundation

/// Involute function inv(a) = tan(a) - a.
@inline(__always) func mgInvolute(_ a: Double) -> Double { tan(a) - a }

/// Schematic external involute spur gear (standard full-depth proportions).
///
/// Addendum 1 m, dedendum 1.25 m, an elliptical root fillet below the base circle and a small backlash allowance.
/// This is a teaching model for visual meshing; it is not a validated manufacturing profile (no profile shift,
/// tip relief or undercut trochoid).
public struct MGSpurGear: Equatable, Sendable {
    public var teeth: Int
    public var module: Double
    /// Pressure angle in radians (default 20 degrees).
    public var pressureAngle: Double
    /// Total circular backlash, in modules, removed from each tooth's thickness at the pitch circle.
    public var backlash: Double
    /// Samples along each involute flank.
    public var flankSamples: Int

    public init(teeth: Int, module: Double, pressureAngle: Double = 20 * .pi / 180, backlash: Double = 0.06, flankSamples: Int = 12) {
        precondition(teeth >= 6, "a spur gear needs at least 6 teeth")
        self.teeth = teeth; self.module = module; self.pressureAngle = pressureAngle
        self.backlash = backlash; self.flankSamples = flankSamples
    }

    public var pitchRadius: Double { module * Double(teeth) / 2 }
    public var baseRadius: Double { pitchRadius * cos(pressureAngle) }
    public var tipRadius: Double { pitchRadius + module }
    public var rootRadius: Double { pitchRadius - 1.25 * module }
    public var angularPitch: Double { 2 * .pi / Double(teeth) }

    /// Half the angular tooth thickness at radius `r` (involute region, r >= base radius).
    public func halfThicknessAngle(at r: Double) -> Double {
        let s = Double.pi * module / 2 - backlash * module
        let ar = acos(min(1, baseRadius / max(r, baseRadius)))
        return s / (2 * pitchRadius) + mgInvolute(pressureAngle) - mgInvolute(ar)
    }

    /// Counter-clockwise outline. Tooth `k` is centred at polar angle `phase + k * angularPitch`.
    public func outline(phase: Double = 0) -> [MGVec2] {
        let rb = baseRadius, ra = tipRadius, rf = rootRadius
        let flankStart = max(rb, rf)
        let psiStart = halfThicknessAngle(at: flankStart)
        // Fillet below the base circle: a quarter ellipse that leaves the flank radially and meets the root tangentially.
        let hasFillet = rf < rb
        let filletWidth = hasFillet ? 0.6 * (.pi / Double(teeth) - psiStart) : 0
        let filletSamples = 5
        // Rising flank, from the root circle to the tip: (radius, half-angle) pairs.
        var flank: [(Double, Double)] = []
        if hasFillet {
            for s in stride(from: filletSamples, to: 0, by: -1) {
                let t = Double(s) / Double(filletSamples) * .pi / 2
                flank.append((rb - (rb - rf) * sin(t), psiStart + filletWidth * (1 - cos(t))))
            }
        }
        // Involute sampled evenly in roll angle for even curvature.
        let e0 = (max(0, flankStart * flankStart / (rb * rb) - 1)).squareRoot()
        let e1 = (ra * ra / (rb * rb) - 1).squareRoot()
        for s in 0...flankSamples {
            let e = e0 + (e1 - e0) * Double(s) / Double(flankSamples)
            let r = rb * (1 + e * e).squareRoot()
            flank.append((r, halfThicknessAngle(at: r)))
        }
        let psiTip = halfThicknessAngle(at: ra)
        let psiRoot = flank[0].1
        let tipSamples = 3, rootSamples = 5
        var pts: [MGVec2] = []
        pts.reserveCapacity(teeth * (2 * flank.count + tipSamples + rootSamples))
        for k in 0..<teeth {
            let c = phase + Double(k) * angularPitch
            for (r, psi) in flank { pts.append(.polar(r, c - psi)) }
            for s in 1..<tipSamples { pts.append(.polar(ra, c - psiTip + 2 * psiTip * Double(s) / Double(tipSamples))) }
            for (r, psi) in flank.reversed() { pts.append(.polar(r, c + psi)) }
            let a0 = c + psiRoot, a1 = c + angularPitch - psiRoot
            for s in 1..<rootSamples { pts.append(.polar(rf, a0 + (a1 - a0) * Double(s) / Double(rootSamples))) }
        }
        return pts
    }

    /// Gear blank profile with a round bore and an optional keyway (width, depth beyond the bore).
    public func profile(phase: Double = 0, bore: Double, boreSegments: Int = 72, keyway: (width: Double, depth: Double)? = nil) -> MGProfile {
        MGProfile(outer: outline(phase: phase), holes: bore > 0 ? [MGSpurGear.boreLoop(radius: bore, segments: boreSegments, keyway: keyway)] : [])
    }

    /// Round bore, counter-clockwise, optionally with a rectangular keyway centred on +X.
    public static func boreLoop(radius: Double, segments: Int, keyway: (width: Double, depth: Double)?) -> [MGVec2] {
        guard let key = keyway, key.width > 0, key.width < radius else { return MGProfile.circleLoop(radius: radius, segments: segments) }
        let half = asin(key.width / 2 / radius)
        var pts: [MGVec2] = []
        let outerX = radius + key.depth
        pts.append(MGVec2(outerX, key.width / 2))
        for s in 0...segments {
            let a = half + (2 * .pi - 2 * half) * Double(s) / Double(segments)
            pts.append(.polar(radius, a))
        }
        pts.append(MGVec2(outerX, -key.width / 2))
        return pts
    }
}

/// Schematic internal (ring) gear: tooth spaces have the shape of an external gear's teeth with the same count.
public struct MGRingGear: Equatable, Sendable {
    public var teeth: Int
    public var module: Double
    public var pressureAngle: Double
    /// Backlash in modules, added to each tooth space.
    public var backlash: Double
    public var outerRadius: Double
    public var flankSamples: Int

    public init(teeth: Int, module: Double, outerRadius: Double, pressureAngle: Double = 20 * .pi / 180, backlash: Double = 0.06, flankSamples: Int = 10) {
        precondition(teeth >= 12, "a ring gear needs at least 12 teeth")
        self.teeth = teeth; self.module = module; self.outerRadius = outerRadius
        self.pressureAngle = pressureAngle; self.backlash = backlash; self.flankSamples = flankSamples
    }

    public var pitchRadius: Double { module * Double(teeth) / 2 }
    public var baseRadius: Double { pitchRadius * cos(pressureAngle) }
    /// Internal tooth tips point inward.
    public var tipRadius: Double { pitchRadius - module }
    public var rootRadius: Double { pitchRadius + 1.25 * module }
    public var angularPitch: Double { 2 * .pi / Double(teeth) }

    /// Half the angular width of a tooth space at radius `r`.
    public func halfSpaceAngle(at r: Double) -> Double {
        let s = Double.pi * module / 2 + backlash * module
        let ar = acos(min(1, baseRadius / max(r, baseRadius)))
        return s / (2 * pitchRadius) + mgInvolute(pressureAngle) - mgInvolute(ar)
    }

    /// Counter-clockwise loop of the toothed bore. Space `k` is centred at `phase + k * angularPitch`.
    public func outline(phase: Double = 0) -> [MGVec2] {
        let ri = tipRadius, rf = rootRadius
        let e0 = (max(0, ri * ri / (baseRadius * baseRadius) - 1)).squareRoot()
        let e1 = (rf * rf / (baseRadius * baseRadius) - 1).squareRoot()
        var flank: [(Double, Double)] = []
        for s in 0...flankSamples {
            let e = e0 + (e1 - e0) * Double(s) / Double(flankSamples)
            let r = max(ri, baseRadius * (1 + e * e).squareRoot())
            flank.append((r, halfSpaceAngle(at: r)))
        }
        let psiTip = flank[0].1, psiRoot = flank[flank.count - 1].1
        let bottomSamples = 3, tipSamples = 5
        var pts: [MGVec2] = []
        for k in 0..<teeth {
            let c = phase + Double(k) * angularPitch
            for (r, psi) in flank { pts.append(.polar(r, c - psi)) }
            for s in 1..<bottomSamples { pts.append(.polar(rf, c - psiRoot + 2 * psiRoot * Double(s) / Double(bottomSamples))) }
            for (r, psi) in flank.reversed() { pts.append(.polar(r, c + psi)) }
            let a0 = c + psiTip, a1 = c + angularPitch - psiTip
            for s in 1..<tipSamples { pts.append(.polar(ri, a0 + (a1 - a0) * Double(s) / Double(tipSamples))) }
        }
        return pts
    }

    public func profile(phase: Double = 0, outerSegments: Int = 180) -> MGProfile {
        MGProfile(outer: MGProfile.circleLoop(radius: outerRadius, segments: outerSegments), holes: [outline(phase: phase)])
    }
}

/// Meshing phase rules for parallel-axis spur gears (all angles in radians, counter-clockwise, measured in a frame
/// where both gear centres are fixed).
public enum MGGearPhase {
    /// Phase for gear B meshing externally with gear A when B's centre lies in direction `beta` from A's centre.
    /// A tooth centred on the line of centres on A must face a space on B.
    public static func external(zA: Int, phaseA: Double, zB: Int, beta: Double) -> Double {
        let za = Double(zA), zb = Double(zB)
        return normalise(beta + .pi + (.pi - za * (phaseA - beta)) / zb, pitch: 2 * .pi / zb)
    }

    /// Phase of the ring's tooth spaces so that a planet (zP teeth, tooth phase `phaseP`) whose centre lies in
    /// direction `beta` from the ring centre meshes: the planet tooth on the line of centres enters a ring space.
    public static func ringSpaces(zRing: Int, zPlanet: Int, phasePlanet: Double, beta: Double) -> Double {
        normalise(beta + Double(zPlanet) * (phasePlanet - beta) / Double(zRing), pitch: 2 * .pi / Double(zRing))
    }

    static func normalise(_ a: Double, pitch: Double) -> Double {
        let r = a.truncatingRemainder(dividingBy: pitch)
        return r < 0 ? r + pitch : r
    }
}
