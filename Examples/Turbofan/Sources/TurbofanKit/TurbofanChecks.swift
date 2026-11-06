// SPDX-License-Identifier: Apache-2.0
import Foundation
import MartyGraphics

/// Geometric checks for a coaxial turbomachine assembly whose engine axis is the kernel X axis through the origin.
///
/// 1. Spin rates: each part's rotation per input radian about the engine axis, measured from posed transforms.
/// 2. Coaxiality: at sampled input angles every vertex of every part keeps its radius and axial position. Then each
///    rotating part sweeps exactly the solid of revolution of its (radius, axial) "shadow".
/// 3. Clearance: two parts that turn at different rates can touch at some angle if and only if their shadows meet.
///    Shadows are rasterised on a grid (triangles projected to the (r, x) half-plane), and a chamfer distance field
///    gives each rotating part's smallest gap to anything that does not turn with it.
public enum TurbofanChecks {
    public struct Clearance: Sendable, Equatable {
        public var part: String
        /// Smallest gap in millimetres (grid estimate; 0 means the shadows overlap).
        public var gap: Double
        /// The closest part that does not turn with `part`.
        public var nearest: String
    }

    public struct Report: Sendable {
        public var parts: Int
        public var triangles: Int
        public var openParts: [String]
        /// Rotation per input radian about the engine axis, by part id.
        public var rates: [String: Double]
        /// Largest change of any vertex's radius or axial position across the sampled input angles (mm).
        public var coaxialError: Double
        /// Largest offset of a rotating part's rotation axis from the engine axis (mm or radians).
        public var axisError: Double
        public var sampledAngles: Int
        public var clearances: [Clearance]
        public var cell: Double

        public var interferences: [Clearance] { clearances.filter { $0.gap <= 0 } }
        /// Distinct nonzero spin rates (one per spool).
        public var spoolRates: [Double] {
            var out: [Double] = []
            for r in rates.values where abs(r) > 1e-9 && !out.contains(where: { abs($0 - r) < 1e-6 }) { out.append(r) }
            return out.sorted()
        }
    }

    /// Rotation of `b` relative to `a` about kernel X, plus how far the relative motion is from a pure X rotation.
    static func xRotation(_ a: MGTransform, _ b: MGTransform) -> (angle: Double, error: Double) {
        let d = b * a.inverse
        let angle = atan2(d.c1.z, d.c1.y)
        let pure = MGTransform.rotation(axis: .unitX, angle: angle)
        let err = max((d.c0 - pure.c0).length, (d.c1 - pure.c1).length, (d.c2 - pure.c2).length, d.translation.length)
        return (angle, err)
    }

    public static func run(_ doc: MGSolidDocument, samples: Int = 24, cell: Double = 1.0, vertexStride: Int = 1) -> Report {
        let a = doc.assembly
        let pose0 = a.pose(MGPoseParameters(input: 0))
        let delta = 1e-3
        let poseD = a.pose(MGPoseParameters(input: delta))
        var rates: [String: Double] = [:]
        var axisError = 0.0
        for p in a.parts {
            let r = xRotation(pose0.world[p.id] ?? .identity, poseD.world[p.id] ?? .identity)
            rates[p.id] = abs(r.angle) < 1e-12 ? 0 : r.angle / delta
            axisError = max(axisError, r.error)
        }
        // Coaxiality at sampled angles (includes many whole and fractional turns of both spools).
        var coaxial = 0.0
        for k in 1...max(1, samples) {
            let input = Double(k) * 2 * .pi / Double(max(1, samples)) * 1.37
            let pose = a.pose(MGPoseParameters(input: input))
            for p in a.parts where rates[p.id] != 0 {
                let t0 = pose0.world[p.id] ?? .identity, t = pose.world[p.id] ?? .identity
                for i in stride(from: 0, to: p.mesh.positions.count, by: max(1, vertexStride)) {
                    let v = p.mesh.positions[i]
                    let q0 = t0.apply(v), q = t.apply(v)
                    let dr = abs((q.y * q.y + q.z * q.z).squareRoot() - (q0.y * q0.y + q0.z * q0.z).squareRoot())
                    coaxial = max(coaxial, dr, abs(q.x - q0.x))
                }
            }
        }
        var open: [String] = []
        for p in a.parts where !p.mesh.edgeReport.isClosed { open.append(p.id) }
        let clearances = clearance(a, pose: pose0, rates: rates, cell: cell)
        return Report(parts: a.parts.count, triangles: a.parts.reduce(0) { $0 + $1.mesh.triangleCount }, openParts: open, rates: rates,
                      coaxialError: coaxial, axisError: axisError, sampledAngles: samples, clearances: clearances, cell: cell)
    }

    // MARK: Shadows

    struct Grid {
        let cell: Double, r0: Double, x0: Double, nr: Int, nx: Int
        func index(_ i: Int, _ j: Int) -> Int { j * nr + i }
    }

    /// Distance from point p to the 2D triangle (a, b, c); 0 inside.
    static func distance(_ p: MGVec2, _ a: MGVec2, _ b: MGVec2, _ c: MGVec2) -> Double {
        func seg(_ u: MGVec2, _ v: MGVec2) -> Double {
            let d = v - u, l2 = d.dot(d)
            let t = l2 > 0 ? min(1, max(0, (p - u).dot(d) / l2)) : 0
            return (p - (u + d * t)).length
        }
        let area = (b - a).cross(c - a)
        if abs(area) > 1e-12 {
            let s1 = (b - a).cross(p - a), s2 = (c - b).cross(p - b), s3 = (a - c).cross(p - c)
            if (s1 >= 0 && s2 >= 0 && s3 >= 0) || (s1 <= 0 && s2 <= 0 && s3 <= 0) { return 0 }
        }
        return min(seg(a, b), seg(b, c), seg(c, a))
    }

    /// Grid cells (indices) covered by a part's (r, x) shadow: cells whose centre lies within half a cell diagonal
    /// of a projected triangle.
    static func shadow(_ mesh: MGMesh, _ t: MGTransform, _ g: Grid) -> Set<Int> {
        let pts = mesh.positions.map { v -> MGVec2 in
            let q = t.apply(v)
            return MGVec2((q.y * q.y + q.z * q.z).squareRoot(), q.x)
        }
        var seen = Set<[Int64]>()
        var cells = Set<Int>()
        let reach = g.cell * 0.7072
        for k in 0..<mesh.triangleCount {
            let (i, j, l) = mesh.triangle(k)
            let a = pts[i], b = pts[j], c = pts[l]
            var key = [a, b, c].flatMap { [Int64(($0.x * 100).rounded()), Int64(($0.y * 100).rounded())] }
            // Triangles of a surface of revolution repeat around the axis: rasterise each projection once.
            let pairs = [(key[0], key[1]), (key[2], key[3]), (key[4], key[5])].sorted { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1 < $1.1 }
            key = pairs.flatMap { [$0.0, $0.1] }
            guard seen.insert(key).inserted else { continue }
            let lo = MGVec2(min(a.x, b.x, c.x) - reach, min(a.y, b.y, c.y) - reach)
            let hi = MGVec2(max(a.x, b.x, c.x) + reach, max(a.y, b.y, c.y) + reach)
            let i0 = max(0, Int(((lo.x - g.r0) / g.cell).rounded(.down))), i1 = min(g.nr - 1, Int(((hi.x - g.r0) / g.cell).rounded(.up)))
            let j0 = max(0, Int(((lo.y - g.x0) / g.cell).rounded(.down))), j1 = min(g.nx - 1, Int(((hi.y - g.x0) / g.cell).rounded(.up)))
            guard i0 <= i1, j0 <= j1 else { continue }
            for jj in j0...j1 {
                for ii in i0...i1 {
                    let centre = MGVec2(g.r0 + (Double(ii) + 0.5) * g.cell, g.x0 + (Double(jj) + 0.5) * g.cell)
                    if distance(centre, a, b, c) <= reach { cells.insert(g.index(ii, jj)) }
                }
            }
        }
        return cells
    }

    /// Two-pass chamfer distance (cells) to the nearest occupied cell.
    static func distanceField(_ occupied: [Bool], _ g: Grid) -> [Float] {
        let inf: Float = 1e9, d1: Float = 1, d2: Float = 1.41421356
        var d = occupied.map { $0 ? Float(0) : inf }
        for j in 0..<g.nx {
            for i in 0..<g.nr {
                let k = g.index(i, j)
                var v = d[k]
                if i > 0 { v = min(v, d[k - 1] + d1) }
                if j > 0 {
                    v = min(v, d[k - g.nr] + d1)
                    if i > 0 { v = min(v, d[k - g.nr - 1] + d2) }
                    if i < g.nr - 1 { v = min(v, d[k - g.nr + 1] + d2) }
                }
                d[k] = v
            }
        }
        for j in stride(from: g.nx - 1, through: 0, by: -1) {
            for i in stride(from: g.nr - 1, through: 0, by: -1) {
                let k = g.index(i, j)
                var v = d[k]
                if i < g.nr - 1 { v = min(v, d[k + 1] + d1) }
                if j < g.nx - 1 {
                    v = min(v, d[k + g.nr] + d1)
                    if i < g.nr - 1 { v = min(v, d[k + g.nr + 1] + d2) }
                    if i > 0 { v = min(v, d[k + g.nr - 1] + d2) }
                }
                d[k] = v
            }
        }
        return d
    }

    static func clearance(_ a: MGAssembly, pose: MGPose, rates: [String: Double], cell: Double) -> [Clearance] {
        var bounds = MGBounds.empty
        for p in a.parts {
            let t = pose.world[p.id] ?? .identity
            for c in p.mesh.bounds.corners { bounds.include(t.apply(c)) }
        }
        guard !bounds.isEmpty else { return [] }
        let rMax = max(abs(bounds.min.y), abs(bounds.max.y), abs(bounds.min.z), abs(bounds.max.z)) * 1.415 + 4 * cell
        let g = Grid(cell: cell, r0: 0, x0: bounds.min.x - 4 * cell, nr: Int((rMax / cell).rounded(.up)) + 1,
                     nx: Int(((bounds.max.x - bounds.min.x + 8 * cell) / cell).rounded(.up)) + 1)
        var shadows: [String: Set<Int>] = [:]
        for p in a.parts { shadows[p.id] = shadow(p.mesh, pose.world[p.id] ?? .identity, g) }
        func group(_ id: String) -> Int64 { Int64(((rates[id] ?? 0) * 1e6).rounded()) }
        var result: [Clearance] = []
        let groups = Set(a.parts.map { group($0.id) })
        for gid in groups.sorted() where gid != 0 {
            var occupied = [Bool](repeating: false, count: g.nr * g.nx)
            for p in a.parts where group(p.id) != gid { for c in shadows[p.id]! { occupied[c] = true } }
            let field = distanceField(occupied, g)
            for p in a.parts where group(p.id) == gid {
                var best = Float.infinity, at = -1
                for c in shadows[p.id]! where field[c] < best { best = field[c]; at = c }
                var nearest = ""
                if at >= 0 {
                    // The non-co-rotating part closest to that cell.
                    let ci = at % g.nr, cj = at / g.nr
                    var bestD = Int.max
                    for q in a.parts where group(q.id) != gid {
                        for c in shadows[q.id]! {
                            let di = c % g.nr - ci, dj = c / g.nr - cj
                            let dd = di * di + dj * dj
                            if dd < bestD { bestD = dd; nearest = q.id }
                        }
                    }
                }
                // Shadow cells reach about 0.7 cell beyond each surface, so the surface gap is the field distance plus
                // up to 1.4 cells; report the conservative (smaller) value.
                result.append(Clearance(part: p.id, gap: Double(best) * cell, nearest: nearest))
            }
        }
        return result.sorted { $0.part < $1.part }
    }
}
