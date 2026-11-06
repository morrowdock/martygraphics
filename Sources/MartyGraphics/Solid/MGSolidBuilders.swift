// SPDX-License-Identifier: Apache-2.0
import Foundation

// Closed-solid constructors. Every builder returns a welded, consistently outward-wound mesh.
extension MGMesh {
    /// Extrudes a planar profile (with holes) along +Z from `z0` to `z1`.
    ///
    /// With `chamfer > 0`, all top and bottom edges get a 45-degree chamfer of that size: the caps use the profile
    /// inset by `chamfer`, the walls step out to the full profile. Keep the chamfer below the profile's smallest
    /// concave radius and below half the height.
    public static func extrude(_ profile: MGProfile, from z0: Double = 0, to z1: Double, chamfer: Double = 0) -> MGMesh {
        precondition(z1 > z0, "extrusion needs positive height")
        let c = max(0, min(chamfer, (z1 - z0) / 2 - 1e-9))
        let loops = [profile.outer] + profile.holes
        // Levels: (inset distance, z).
        let levels: [(Double, Double)] = c > 0 ? [(c, z0), (0, z0 + c), (0, z1 - c), (c, z1)] : [(0, z0), (0, z1)]
        var mesh = MGMesh()
        var base: [[Int]] = []  // base[loop][level] = first vertex index
        for loop in loops {
            var perLevel: [Int] = []
            for (d, z) in levels {
                perLevel.append(mesh.positions.count)
                let ring = d > 0 ? MGProfile.inset(loop, by: d) : loop
                mesh.positions += ring.map { MGVec3($0.x, $0.y, z) }
            }
            base.append(perLevel)
        }
        func tri(_ a: Int, _ b: Int, _ c: Int) { mesh.indices += [UInt32(a), UInt32(b), UInt32(c)] }
        // Walls: material is on the left of travel, so (a, b, c) with b ahead and c above faces outward.
        for (li, loop) in loops.enumerated() {
            let n = loop.count
            for l in 0..<(levels.count - 1) {
                let lo = base[li][l], hi = base[li][l + 1]
                for i in 0..<n {
                    let j = (i + 1) % n
                    tri(lo + i, lo + j, hi + j); tri(lo + i, hi + j, hi + i)
                }
            }
        }
        // Caps from one shared 2D triangulation of the inset loops.
        let capLoops = loops.map { c > 0 ? MGProfile.inset($0, by: c) : $0 }
        var pts: [MGVec2] = [], idx: [[Int]] = []
        for loop in capLoops { idx.append(Array(pts.count..<(pts.count + loop.count))); pts += loop }
        let tris = MGTriangulator.triangulate(points: pts, outer: idx[0], holes: Array(idx.dropFirst()))
        // Map 2D index -> (loop, i).
        var owner: [(Int, Int)] = []
        for (li, loop) in capLoops.enumerated() { for i in loop.indices { owner.append((li, i)) } }
        let top = levels.count - 1
        for (a, b, cc) in tris {
            let (la, ia) = owner[a], (lb, ib) = owner[b], (lc, ic) = owner[cc]
            tri(base[la][top] + ia, base[lb][top] + ib, base[lc][top] + ic)
            tri(base[la][0] + ia, base[lc][0] + ic, base[lb][0] + ib)
        }
        return mesh
    }

    /// Revolves a profile drawn in the (radius, height) plane about the Z axis.
    ///
    /// `points` use `x` = radius (>= 0) and `y` = height. A closed loop must not touch the axis; an open polyline
    /// (`closed: false`) must start and end on the axis (radius 0), which become single pole vertices. Orientation
    /// is normalised so normals face outward.
    public static func revolve(_ points: [MGVec2], segments: Int = 96, closed: Bool) -> MGMesh {
        precondition(points.count >= 2, "revolve needs a profile")
        let n = max(3, segments)
        var prof = points
        // The (closed) polygon, with the axis segment for open profiles, must be counter-clockwise.
        if MGProfile.signedArea(prof) < 0 { prof.reverse() }
        if !closed { precondition(prof.first!.x < 1e-9 && prof.last!.x < 1e-9, "open revolve profiles must end on the axis") }
        var mesh = MGMesh()
        var start: [Int] = [], isPole: [Bool] = []
        for p in prof {
            start.append(mesh.positions.count)
            if p.x < 1e-9 {
                isPole.append(true); mesh.positions.append(MGVec3(0, 0, p.y))
            } else {
                isPole.append(false)
                for j in 0..<n {
                    let a = 2 * Double.pi * Double(j) / Double(n)
                    mesh.positions.append(MGVec3(p.x * cos(a), p.x * sin(a), p.y))
                }
            }
        }
        func v(_ k: Int, _ j: Int) -> UInt32 { UInt32(isPole[k] ? start[k] : start[k] + j % n) }
        let count = prof.count, spans = closed ? count : count - 1
        for k in 0..<spans {
            let k1 = (k + 1) % count
            if isPole[k] && isPole[k1] { continue }
            for j in 0..<n {
                let a = v(k, j), b = v(k, j + 1), c = v(k1, j + 1), d = v(k1, j)
                if !isPole[k] { mesh.indices += [a, b, c] }
                if !isPole[k1] { mesh.indices += [a, c, d] }
            }
        }
        return mesh
    }

    /// Solid cylinder along Z with optional edge chamfer.
    public static func cylinder(radius: Double, from z0: Double = 0, to z1: Double, chamfer: Double = 0, segments: Int = 96) -> MGMesh {
        let c = max(0, min(chamfer, radius / 2, (z1 - z0) / 2 - 1e-9))
        var p: [MGVec2] = [MGVec2(0, z0)]
        if c > 0 { p += [MGVec2(radius - c, z0), MGVec2(radius, z0 + c), MGVec2(radius, z1 - c), MGVec2(radius - c, z1)] }
        else { p += [MGVec2(radius, z0), MGVec2(radius, z1)] }
        p.append(MGVec2(0, z1))
        return revolve(p, segments: segments, closed: false)
    }

    /// Hollow tube (shaft sleeve, spacer, housing) along Z with optional chamfers on all four circular edges.
    public static func tube(inner: Double, outer: Double, from z0: Double = 0, to z1: Double, chamfer: Double = 0, segments: Int = 96) -> MGMesh {
        precondition(outer > inner && inner > 0, "tube radii must satisfy 0 < inner < outer")
        let c = max(0, min(chamfer, (outer - inner) / 3, (z1 - z0) / 2 - 1e-9))
        let p: [MGVec2] = c > 0
            ? [MGVec2(inner + c, z0), MGVec2(outer - c, z0), MGVec2(outer, z0 + c), MGVec2(outer, z1 - c),
               MGVec2(outer - c, z1), MGVec2(inner + c, z1), MGVec2(inner, z1 - c), MGVec2(inner, z0 + c)]
            : [MGVec2(inner, z0), MGVec2(outer, z0), MGVec2(outer, z1), MGVec2(inner, z1)]
        return revolve(p, segments: segments, closed: true)
    }

    /// Box centred on the origin with every edge chamfered.
    public static func chamferedBox(size: MGVec3, chamfer: Double) -> MGMesh {
        let c = max(0, min(chamfer, min(size.x, size.y, size.z) / 2 - 1e-6))
        let w = size.x / 2, h = size.y / 2
        let loop: [MGVec2] = c > 0
            ? [MGVec2(-w + c, -h), MGVec2(w - c, -h), MGVec2(w, -h + c), MGVec2(w, h - c),
               MGVec2(w - c, h), MGVec2(-w + c, h), MGVec2(-w, h - c), MGVec2(-w, -h + c)]
            : [MGVec2(-w, -h), MGVec2(w, -h), MGVec2(w, h), MGVec2(-w, h)]
        // Vertical edges are chamfered by the octagon; the extrusion chamfers the horizontal ones.
        return extrude(MGProfile(outer: loop), from: -size.z / 2, to: size.z / 2, chamfer: c * 0.999)
    }

    /// Hexagonal prism (bolt head, nut) along Z.
    public static func hexPrism(acrossFlats: Double, from z0: Double = 0, to z1: Double, chamfer: Double = 0) -> MGMesh {
        let r = acrossFlats / 2 / cos(.pi / 6)
        return extrude(MGProfile(outer: MGProfile.regularPolygonLoop(sides: 6, circumradius: r, phase: .pi / 6)), from: z0, to: z1, chamfer: chamfer)
    }
}
