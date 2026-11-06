// SPDX-License-Identifier: Apache-2.0
import Foundation

/// Geometric checks a host can run before showing a compiled assembly.
public enum MGSolidChecks {
    public struct MeshReport: Equatable, Sendable {
        /// Deepest radial intrusion of one gear outline into the other's material (mm); <= 0 means no overlap.
        public var maxPenetration: Double
        /// Smallest radial clearance seen between mating outlines (mm); small and positive means engaged with backlash.
        public var minClearance: Double
        public var samples: Int
        public var pairs: Int
    }

    /// Sweeps every gear pair of a compiled document over `samples` input angles and measures 2D tooth overlap in
    /// the gears' common plane. Outline vertices of each gear are tested against the other's polygon.
    public static func gearMeshes(_ doc: MGSolidDocument, samples: Int = 120, inputRange: ClosedRange<Double> = 0...(2 * .pi)) -> MeshReport {
        var pen = -Double.infinity, gap = Double.infinity
        var outlines: [String: [MGVec2]] = [:]
        func outline(_ id: String) -> [MGVec2] {
            if let o = outlines[id] { return o }
            let g = doc.gears[id]
            let o = g?.spur?.outline() ?? g?.ring?.outline() ?? []
            outlines[id] = o
            return o
        }
        for k in 0..<max(1, samples) {
            let s = inputRange.lowerBound + (inputRange.upperBound - inputRange.lowerBound) * Double(k) / Double(max(1, samples))
            let pose = doc.pose(MGPoseParameters(input: s))
            for pair in doc.assembly.gearPairs {
                guard let ga = doc.gears[pair.a], let gb = doc.gears[pair.b] else { continue }
                let fa = (pose.world[pair.a] ?? .identity) * ga.local, fb = (pose.world[pair.b] ?? .identity) * gb.local
                let r = contact(outline(pair.a), fa, ring: ga.ring != nil, outline(pair.b), fb)
                pen = max(pen, r.penetration); gap = min(gap, r.gap)
            }
        }
        return MeshReport(maxPenetration: pen, minClearance: gap, samples: samples, pairs: doc.assembly.gearPairs.count)
    }

    /// Deepest tooth overlap (mm) of one meshing pair at standard centre distance, swept over one tooth pitch in the
    /// frame where both centres are fixed. `a` is a spur gear or a ring; `b` is a spur gear. The gears are phased
    /// with `MGGearPhase` and turned at the tooth ratio, so any overlap is interference of the tooth shapes
    /// themselves (for example a ring with too few more teeth than its planet).
    public static func pairInterference(_ a: MGSolidGear, _ b: MGSolidGear, samples: Int = 16) -> Double {
        guard let sb = b.spur, a.spur != nil || a.ring != nil else { return .infinity }
        let za = Double(a.teeth), zb = Double(sb.teeth), m = a.module
        let isRing = a.ring != nil
        let outlineA = a.spur?.outline() ?? a.ring!.outline()
        let d = (isRing ? za - zb : za + zb) * m / 2
        // Phases at input 0 with b's centre on +X (beta = 0).
        let phaseB = isRing ? 0 : MGGearPhase.external(zA: a.teeth, phaseA: 0, zB: sb.teeth, beta: 0)
        let outlineB = sb.outline(phase: phaseB)
        var worst = -Double.infinity
        for k in 0..<max(1, samples) {
            let t = 2 * Double.pi / za * Double(k) / Double(max(1, samples))
            // External gears counter-rotate; a planet turns the same way as its ring (zA tA = +/- zB tB).
            let tb = (isRing ? 1 : -1) * t * za / zb
            let fa = MGTransform.rotation(axis: .unitZ, angle: t)
            let fb = MGTransform.translation(MGVec3(d, 0, 0)) * .rotation(axis: .unitZ, angle: tb)
            worst = max(worst, contact(outlineA, fa, ring: isRing, outlineB, fb).penetration)
        }
        return worst
    }

    /// Radial overlap of outline `b` with gear `a` (a spur gear, or a ring when `ring` is true) and vice versa.
    public static func contact(_ a: [MGVec2], _ fa: MGTransform, ring: Bool, _ b: [MGVec2], _ fb: MGTransform) -> (penetration: Double, gap: Double) {
        guard a.count > 2, b.count > 2 else { return (-.infinity, .infinity) }
        let pa = MGProfile.PolarBoundary(loopCCW: a), pb = MGProfile.PolarBoundary(loopCCW: b)
        let ia = fa.inverse, ib = fb.inverse
        let ra = a.map(\.length), rb = b.map(\.length)
        let aLo = ra.min()! - 0.5, aHi = ra.max()! + 0.5, bLo = rb.min()! - 0.5, bHi = rb.max()! + 0.5
        var pen = -Double.infinity, gap = Double.infinity
        for p in b {
            let l = ia.apply(fb.apply(MGVec3(p.x, p.y, 0)))
            let r = (l.x * l.x + l.y * l.y).squareRoot()
            guard r > aLo, r < aHi else { continue }
            let boundary = pa.radius(at: atan2(l.y, l.x))
            let d = ring ? r - boundary : boundary - r
            pen = max(pen, d); gap = min(gap, -d)
        }
        for p in a {
            let l = ib.apply(fa.apply(MGVec3(p.x, p.y, 0)))
            let r = (l.x * l.x + l.y * l.y).squareRoot()
            guard r > bLo, r < bHi else { continue }
            let d = pb.radius(at: atan2(l.y, l.x)) - r
            pen = max(pen, d); gap = min(gap, -d)
        }
        return (pen, gap)
    }
}
