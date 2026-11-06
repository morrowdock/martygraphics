// SPDX-License-Identifier: Apache-2.0
import Foundation
import MartyGraphics

/// Geometric checks for a coaxial turbomachine assembly whose engine axis is the kernel X axis through the origin.
///
/// 1. Spin rates: each part's rotation per input radian about the engine axis, measured from posed transforms.
/// 2. Coaxiality: at sampled input angles every vertex of every part keeps its radius and axial position. Then each
///    rotating part sweeps exactly the solid of revolution of its (radius, axial) "shadow".
/// 3. Clearance: two parts that turn at different rates can touch at some angle if and only if their shadows meet.
///    Triangles are projected to the (r, x) half-plane. A grid pass (chamfer distance field over rasterised
///    shadows) finds how far to look; an exact pass then measures distances between convex regions that contain each
///    triangle's true shadow (the projection swept toward the axis by how far the flat triangle can dip below it),
///    giving a true lower bound on the gap.
public enum TurbofanChecks {
    public struct Clearance: Sendable, Equatable {
        public var part: String
        /// A lower bound on the smallest gap, in millimetres, at any angle: the exact distance between regions that
        /// contain the true (r, x) shadows (projected triangles swept inward by how far each flat triangle can dip
        /// toward the axis). Interference when it is not positive.
        public var gap: Double
        /// The closest part that does not turn with `part`.
        public var nearest: String
        /// Distance between the grid shadows in millimetres (a coarse estimate used to bound the search).
        public var gridGap: Double
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
        /// Smallest lower-bound gap over all rotating parts (mm).
        public var minimumGap: Double { clearances.map(\.gap).min() ?? .infinity }
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

    // MARK: Exact lower bound

    /// One mesh triangle projected to the (r, x) half-plane, and a convex region that contains the true triangle's
    /// (r, x) shadow.
    ///
    /// The radius about the axis is a convex function, so on a flat triangle the true radius is never above the linear
    /// interpolation of the vertex radii that the projection uses; the true point lies at or inward of (toward the
    /// axis from) its projection. With `u` the unit direction of the centroid in the (y, z) plane, `r(p) >= p · u`,
    /// which is linear, so the dip is at most `bulge = max_i (r_i - v_i · u)`. For a facet of a surface of revolution
    /// with angular step Δ this is the sagitta `R (1 - cos(Δ / 2))`. `hull` is the projection swept inward by `bulge`:
    /// the convex hull of the three projected vertices and their copies moved `bulge` toward the axis.
    struct ProjectedTriangle {
        var a: MGVec2, b: MGVec2, c: MGVec2
        var bulge: Double
        var hull: [MGVec2]
        var lo: MGVec2, hi: MGVec2

        init(a: MGVec2, b: MGVec2, c: MGVec2, bulge: Double) {
            self.a = a; self.b = b; self.c = c; self.bulge = bulge
            let pts = [a, b, c]
            hull = MGProfile.convexHull(bulge > 0 ? pts + pts.map { MGVec2($0.x - bulge, $0.y) } : pts)
            lo = MGVec2(hull.map(\.x).min()!, hull.map(\.y).min()!)
            hi = MGVec2(hull.map(\.x).max()!, hull.map(\.y).max()!)
        }
    }

    /// Distinct projected triangles of a posed mesh (rotated copies of a blade or a revolve facet share one projection).
    static func projectedTriangles(_ mesh: MGMesh, _ t: MGTransform) -> [ProjectedTriangle] {
        let q = mesh.positions.map(t.apply)
        var index: [[Int64]: Int] = [:]
        var out: [ProjectedTriangle] = []
        for k in 0..<mesh.triangleCount {
            let (i, j, l) = mesh.triangle(k)
            let v = [q[i], q[j], q[l]]
            let pts = v.map { MGVec2(($0.y * $0.y + $0.z * $0.z).squareRoot(), $0.x) }
            let cy = (v[0].y + v[1].y + v[2].y) / 3, cz = (v[0].z + v[1].z + v[2].z) / 3
            let len = (cy * cy + cz * cz).squareRoot()
            // Any unit direction u gives a valid bound; try the centroid direction and the middle of the vertices'
            // angular range (the optimum for a facet of a surface of revolution) and keep the smaller.
            func dip(_ uy: Double, _ uz: Double) -> Double {
                var d = 0.0
                for k in 0..<3 {
                    let along: Double = v[k].y * uy + v[k].z * uz
                    d = max(d, pts[k].x - along)
                }
                return d
            }
            var bulge = max(pts[0].x, pts[1].x, pts[2].x)   // always valid: the triangle may reach the axis
            if len > 1e-9 { bulge = min(bulge, dip(cy / len, cz / len)) }
            let off = pts.indices.filter { pts[$0].x > 1e-9 }
            if let first = off.first {
                let a0 = atan2(v[first].z, v[first].y)
                var lo = 0.0, hi = 0.0
                for k in off {
                    var d = atan2(v[k].z, v[k].y) - a0
                    if d > .pi { d -= 2 * .pi } else if d < -.pi { d += 2 * .pi }
                    lo = min(lo, d); hi = max(hi, d)
                }
                if hi - lo < .pi {
                    let m = a0 + (lo + hi) / 2
                    bulge = min(bulge, dip(cos(m), sin(m)))
                }
            }
            var corners: [(Int64, Int64)] = []
            for q in pts { corners.append((Int64((q.x * 1e6).rounded()), Int64((q.y * 1e6).rounded()))) }
            corners.sort { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1 < $1.1 }
            let key: [Int64] = [corners[0].0, corners[0].1, corners[1].0, corners[1].1, corners[2].0, corners[2].1]
            if let at = index[key] {
                if bulge > out[at].bulge { out[at] = ProjectedTriangle(a: out[at].a, b: out[at].b, c: out[at].c, bulge: bulge) }
                continue
            }
            index[key] = out.count
            out.append(ProjectedTriangle(a: pts[0], b: pts[1], c: pts[2], bulge: bulge))
        }
        return out
    }

    /// Exact distance between two convex polygons (counter-clockwise; one or two points act as a point or segment).
    /// 0 when they touch or overlap.
    static func polygonDistance(_ p: [MGVec2], _ q: [MGVec2]) -> Double {
        func edges(_ h: [MGVec2]) -> [(MGVec2, MGVec2)] {
            h.count == 1 ? [(h[0], h[0])] : h.count == 2 ? [(h[0], h[1])] : h.indices.map { (h[$0], h[($0 + 1) % h.count]) }
        }
        func crosses(_ a: MGVec2, _ b: MGVec2, _ c: MGVec2, _ d: MGVec2) -> Bool {
            let d1 = (b - a).cross(c - a), d2 = (b - a).cross(d - a), d3 = (d - c).cross(a - c), d4 = (d - c).cross(b - c)
            return d1 * d2 < 0 && d3 * d4 < 0
        }
        func inside(_ v: MGVec2, _ h: [MGVec2]) -> Bool {
            guard h.count >= 3 else { return false }
            return h.indices.allSatisfy { (h[($0 + 1) % h.count] - h[$0]).cross(v - h[$0]) >= 0 }
        }
        func toSegment(_ v: MGVec2, _ a: MGVec2, _ b: MGVec2) -> Double {
            let d = b - a, l2 = d.dot(d)
            let t = l2 > 0 ? min(1, max(0, (v - a).dot(d) / l2)) : 0
            return (v - (a + d * t)).length
        }
        let pe = edges(p), qe = edges(q)
        for (a, b) in pe { for (c, d) in qe where crosses(a, b, c, d) { return 0 } }
        if p.contains(where: { inside($0, q) }) || q.contains(where: { inside($0, p) }) { return 0 }
        // Disjoint convex sets: the closest pair has a vertex of one on an edge of the other.
        var best = Double.infinity
        for v in p { for (a, b) in qe { best = min(best, toSegment(v, a, b)) } }
        for v in q { for (a, b) in pe { best = min(best, toSegment(v, a, b)) } }
        return best
    }

    /// Rounding of projected coordinates when merging rotated copies (1e-6 mm) is covered by this margin.
    static let mergeMargin = 1e-5

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
        var projected: [String: [ProjectedTriangle]] = [:]
        for p in a.parts {
            let t = pose.world[p.id] ?? .identity
            shadows[p.id] = shadow(p.mesh, t, g)
            projected[p.id] = projectedTriangles(p.mesh, t)
        }
        func group(_ id: String) -> Int64 { Int64(((rates[id] ?? 0) * 1e6).rounded()) }
        var result: [Clearance] = []
        let groups = Set(a.parts.map { group($0.id) })
        let bucket = 8.0
        let maxBulge = projected.values.flatMap { $0.map(\.bulge) }.max() ?? 0
        func key(_ i: Int, _ j: Int) -> Int64 { Int64(i) << 32 | Int64(UInt32(bitPattern: Int32(j))) }
        for gid in groups.sorted() where gid != 0 {
            // Grid pass: a distance field over everything that does not turn with this group bounds the search radius.
            var occupied = [Bool](repeating: false, count: g.nr * g.nx)
            for p in a.parts where group(p.id) != gid { for c in shadows[p.id]! { occupied[c] = true } }
            let field = distanceField(occupied, g)
            // Exact pass: projected triangles of the other parts in a spatial hash.
            var others: [(part: String, tri: ProjectedTriangle)] = []
            for p in a.parts where group(p.id) != gid { for t in projected[p.id]! { others.append((p.id, t)) } }
            var buckets: [Int64: [Int]] = [:]
            for (n, o) in others.enumerated() {
                for i in Int((o.tri.lo.x / bucket).rounded(.down))...Int((o.tri.hi.x / bucket).rounded(.down)) {
                    for j in Int((o.tri.lo.y / bucket).rounded(.down))...Int((o.tri.hi.y / bucket).rounded(.down)) {
                        buckets[key(i, j), default: []].append(n)
                    }
                }
            }
            var stamp = [Int](repeating: -1, count: others.count), serial = 0
            for p in a.parts where group(p.id) == gid {
                var best = Float.infinity
                for c in shadows[p.id]! where field[c] < best { best = field[c] }
                guard best.isFinite else { continue }
                // Every projected point lies in a marked cell whose centre is within 0.71 cell of it, and the chamfer
                // field is never below the Euclidean distance, so the closest projected pair is at most best + 1.42
                // cells apart, and the swept regions lie within one bulge of the projections. Search wider by two bulges.
                let reach = (Double(best) + 2) * cell + 2 * maxBulge
                var lower = Double.infinity, nearest = ""
                for s in projected[p.id]! {
                    serial += 1
                    for i in Int(((s.lo.x - reach) / bucket).rounded(.down))...Int(((s.hi.x + reach) / bucket).rounded(.down)) {
                        for j in Int(((s.lo.y - reach) / bucket).rounded(.down))...Int(((s.hi.y + reach) / bucket).rounded(.down)) {
                            guard let list = buckets[key(i, j)] else { continue }
                            for n in list where stamp[n] != serial {
                                stamp[n] = serial
                                let t = others[n].tri
                                let gap = max(0, t.lo.x - s.hi.x, s.lo.x - t.hi.x, t.lo.y - s.hi.y, s.lo.y - t.hi.y)
                                guard gap - mergeMargin < lower, gap <= reach else { continue }
                                let d = polygonDistance(s.hull, t.hull) - mergeMargin
                                if d < lower { lower = d; nearest = others[n].part }
                            }
                        }
                    }
                }
                // A true lower bound on the swept gap in millimetres; interference when it is not positive.
                result.append(Clearance(part: p.id, gap: lower == .infinity ? Double(best) * cell : lower, nearest: nearest,
                                        gridGap: Double(best) * cell))
            }
        }
        return result.sorted { $0.part < $1.part }
    }
}
