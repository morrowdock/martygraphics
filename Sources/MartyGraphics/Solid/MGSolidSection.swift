// SPDX-License-Identifier: Apache-2.0
import Foundation

// Capped plane cuts of closed meshes: a true section with solid cap faces, so a cut part stays a closed, outward
// mesh (`edgeReport.isClosed`, `signedVolume > 0`). Each connected shell is cut on its own; the open edges left by the
// cut are chained into loops and the caps are triangulated with `MGTriangulator`. A pre-pass gives the exact triangle
// and vertex counts before any cut triangle is built. Foundation only, deterministic.

/// A cutting plane. Points with `normal · p > offset` are removed; the kept half is `normal · p <= offset`, and the
/// cap faces point along `normal` (out of the kept half, toward someone looking into the cut).
public struct MGSectionPlane: Hashable, Sendable {
    /// Unit normal.
    public var normal: MGVec3
    public var offset: Double
    /// `normal` is normalised; it must not be zero.
    public init(normal: MGVec3, offset: Double) {
        let l = normal.length
        self.normal = l > 0 ? normal * (1 / l) : .unitZ
        self.offset = l > 0 ? offset / l : offset
    }

    public func distance(_ p: MGVec3) -> Double { normal.dot(p) - offset }

    /// The same plane in a frame whose points map to this plane's frame by `t` (for example a part's local frame
    /// when `t` is the part's world transform).
    public func local(_ t: MGTransform) -> MGSectionPlane {
        MGSectionPlane(normal: t.inverse.applyVector(normal), offset: offset - normal.dot(t.translation))
    }
}

/// A capped cut of a closed mesh.
public struct MGSectionCut: Equatable, Sendable {
    /// Closed, outward mesh: the kept triangles first, then the cap triangles.
    public var mesh: MGMesh
    public var capFirstTriangle: Int
    public var capTriangleCount: Int
    /// Plane in the mesh's own frame (cap faces point along its normal).
    public var plane: MGSectionPlane
    /// Number of cap loops (outer boundaries and holes) and the cap area (outer loops minus holes).
    public var loops: Int
    public var capArea: Double

    /// Render mesh: the kept triangles with the part's crease angle, then the caps shaded flat (their normal is the
    /// plane normal), in the same triangle order as `mesh`.
    public func renderMesh(creaseAngle: Double) -> MGRenderMesh {
        // A cut built in code may carry any numbers; clamp the cap start so slicing never traps.
        let first = 3 * min(max(0, capFirstTriangle), mesh.triangleCount)
        let keptIndices = Array(mesh.indices[..<first])
        var out = MGMesh(positions: mesh.positions, indices: keptIndices).renderMesh(creaseAngle: creaseAngle)
        var map: [UInt32: UInt32] = [:]
        for i in mesh.indices[first...] {
            if let j = map[i] { out.indices.append(j); continue }
            let j = UInt32(out.positions.count)
            map[i] = j
            out.positions.append(mesh.positions[Int(i)]); out.normals.append(plane.normal); out.indices.append(j)
        }
        return out
    }
}

/// What a plane does to a mesh, from a cheap classification of its vertices.
public enum MGSectionCrossing: Equatable, Sendable {
    /// Nothing is removed (no vertex lies beyond the plane).
    case misses
    /// Everything is removed (no vertex lies on the kept side).
    case removesAll
    case cuts
}

public enum MGSolidSection {
    /// Vertices within this distance (times the mesh size, at least 1) of the plane count as lying on it.
    static let snap = 1e-9

    /// True when every index names a vertex, the index count is a multiple of three and every position is finite.
    /// Meshes built by the engine always are; `cut` and `estimate` refuse others (`section.mesh`) instead of trapping.
    public static func isWellFormed(_ mesh: MGMesh) -> Bool {
        mesh.indices.count % 3 == 0 && mesh.indices.allSatisfy { Int($0) < mesh.positions.count }
            && mesh.positions.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }
    }

    /// Classifies a mesh against a plane without building anything (`.misses` for a mesh that is not well formed).
    public static func crossing(_ mesh: MGMesh, _ plane: MGSectionPlane) -> MGSectionCrossing {
        guard isWellFormed(mesh), plane.normal.dot(plane.normal).isFinite, plane.offset.isFinite else { return .misses }
        let d = distances(mesh, plane)
        var kept = false, removed = false
        for i in 0..<mesh.triangleCount {
            let (a, b, c) = mesh.triangle(i)
            for v in [a, b, c] { if d[v] < 0 { kept = true } else if d[v] > 0 { removed = true } }
            if kept && removed { return .cuts }
        }
        if !removed { return .misses }
        return kept ? .cuts : .removesAll
    }

    /// Exact triangle and vertex counts of `cut(mesh, plane)`, from a pre-pass that classifies vertices, counts the
    /// clipped triangles and chains the cap loops, but builds no cut triangle and no cap. Throws what `cut` throws.
    public static func estimate(_ mesh: MGMesh, _ plane: MGSectionPlane) throws -> (triangles: Int, vertices: Int) {
        let t = try topology(mesh, plane, build: false)
        return (t.keptTriangles + t.capTriangles, t.vertexCount)
    }

    /// Cuts a closed mesh by the plane and caps every cut. Reasons: `section.loops` (the open edges left by the cut
    /// do not chain into closed loops, so the input was not closed), `section.nesting` (a hole loop lies outside
    /// every outer loop of its shell) and `section.mesh` (bad indices or non-finite numbers).
    public static func cut(_ mesh: MGMesh, _ plane: MGSectionPlane) throws -> MGSectionCut {
        let t = try topology(mesh, plane, build: true)
        var out = MGMesh(positions: t.positions, indices: t.indices)
        let capFirst = out.triangleCount
        let (e1, e2) = basis(plane.normal)
        var area = 0.0
        for group in t.groups {
            // Cap triangles in the plane basis: counter-clockwise seen from +normal, so they face out of the kept half.
            let loops = [group.outer] + group.holes
            var ids: [Int] = [], pts: [MGVec2] = []
            var slots: [[Int]] = []
            for loop in loops {
                var slot: [Int] = []
                for v in loop { slot.append(pts.count); ids.append(v); let p = t.positions[v]; pts.append(MGVec2(p.dot(e1), p.dot(e2))) }
                slots.append(slot)
            }
            // The zipper strip needs star-shaped loops about the origin: centre an annulus on its hole first.
            var local = pts
            if group.holes.count == 1 {
                let h = slots[1].map { pts[$0] }
                let c = h.reduce(MGVec2.zero, +) * (1 / Double(h.count))
                local = pts.map { $0 - c }
            }
            for (a, b, c) in MGTriangulator.triangulate(points: local, outer: slots[0], holes: Array(slots.dropFirst())) {
                out.indices += [UInt32(ids[a]), UInt32(ids[b]), UInt32(ids[c])]
            }
            area += group.area
        }
        return MGSectionCut(mesh: out, capFirstTriangle: capFirst, capTriangleCount: out.triangleCount - capFirst, plane: plane,
                            loops: t.groups.reduce(0) { $0 + 1 + $1.holes.count }, capArea: area)
    }

    // MARK: Pre-pass

    struct Group { var outer: [Int]; var holes: [[Int]]; var area: Double }
    struct Topology {
        var keptTriangles = 0, capTriangles = 0, vertexCount = 0
        var positions: [MGVec3] = []
        var indices: [UInt32] = []
        var groups: [Group] = []
    }

    static func distances(_ mesh: MGMesh, _ plane: MGSectionPlane) -> [Double] {
        let eps = snap * max(1, mesh.bounds.radius)
        return mesh.positions.map { p in let d = plane.distance(p); return abs(d) <= eps ? 0 : d }
    }

    /// Orthonormal basis (e1, e2) of the plane with e1 × e2 = n.
    static func basis(_ n: MGVec3) -> (MGVec3, MGVec3) {
        let helper = abs(n.x) < 0.9 ? MGVec3.unitX : MGVec3.unitY
        let e1 = (helper - n * n.dot(helper)).normalized
        return (e1, n.cross(e1))
    }

    /// Clips every triangle (Sutherland-Hodgman against the kept half `d <= 0`), dedups the cut points per mesh edge,
    /// finds the open edges the cut leaves and chains them into cap loops grouped by shell. With `build == false` it
    /// only counts, so the counts are known before any cut triangle exists.
    static func topology(_ mesh: MGMesh, _ plane: MGSectionPlane, build: Bool) throws -> Topology {
        guard isWellFormed(mesh), plane.normal.dot(plane.normal).isFinite, plane.offset.isFinite else { throw MGSolidIssue("section.mesh") }
        let d = distances(mesh, plane)
        let n = mesh.positions.count
        // Shells: connected components over shared vertices (union-find). Each shell is capped on its own, so merged
        // shapes that overlap (a shaft through a hub) never mix their loops.
        var parent = Array(0..<n)
        func find(_ x: Int) -> Int {
            var r = x
            while parent[r] != r { r = parent[r] }
            var y = x
            while parent[y] != r { let next = parent[y]; parent[y] = r; y = next }
            return r
        }
        for i in 0..<mesh.triangleCount {
            let (a, b, c) = mesh.triangle(i)
            let ra = find(a)
            for v in [b, c] { let rv = find(v); if rv != ra { parent[rv] = ra } }
        }
        // Output vertices: kept and on-plane vertices keep their positions; cut points are keyed by their mesh edge.
        var t = Topology()
        var vertexOf = [Int](repeating: -1, count: n)
        var cutOf: [UInt64: Int] = [:]
        var onPlane = Set<Int>()       // output ids that lie on the plane (cut points and on-plane vertices)
        var shellOf: [Int: Int] = [:]  // output id on the plane -> shell root
        func vertex(_ v: Int) -> Int {
            if vertexOf[v] >= 0 { return vertexOf[v] }
            let id = t.vertexCount; t.vertexCount += 1
            vertexOf[v] = id
            if build || d[v] == 0 { t.positions.append(mesh.positions[v]) }
            if d[v] == 0 { onPlane.insert(id); shellOf[id] = find(v) }
            return id
        }
        func cutPoint(_ a: Int, _ b: Int) -> Int {
            let lo = min(a, b), hi = max(a, b), key = UInt64(lo) << 32 | UInt64(hi)
            if let id = cutOf[key] { return id }
            let id = t.vertexCount; t.vertexCount += 1
            cutOf[key] = id
            let s = d[lo] / (d[lo] - d[hi])
            t.positions.append(mesh.positions[lo] + (mesh.positions[hi] - mesh.positions[lo]) * s)
            onPlane.insert(id); shellOf[id] = find(lo)
            return id
        }
        // In count-only mode positions are kept for plane points only; map ids to them.
        var planeSlot: [Int: Int] = [:]
        func position(_ id: Int) -> MGVec3 { build ? t.positions[id] : t.positions[planeSlot[id]!] }
        // Directed edges of kept triangles whose two ends lie on the plane: the only edges that can be left open.
        var planeEdges: [UInt64: Int] = [:]
        var poly: [Int] = []
        poly.reserveCapacity(4)
        for i in 0..<mesh.triangleCount {
            let (a, b, c) = mesh.triangle(i)
            let tri = [a, b, c]
            let da = d[a], db = d[b], dc = d[c]
            if da > 0 && db > 0 && dc > 0 { continue }
            if da >= 0 && db >= 0 && dc >= 0 {
                // Touches the plane but keeps no area unless all three lie on it; a face in the plane stays only when
                // it faces out of the kept half (its solid is on the kept side).
                guard da == 0 && db == 0 && dc == 0, mesh.faceNormal(i).dot(plane.normal) > 0 else { continue }
            }
            poly.removeAll(keepingCapacity: true)
            for k in 0..<3 {
                let p = tri[k], q = tri[(k + 1) % 3]
                if d[p] <= 0 { poly.append(vertex(p)) }
                if (d[p] < 0 && d[q] > 0) || (d[p] > 0 && d[q] < 0) { poly.append(cutPoint(p, q)) }
            }
            guard poly.count >= 3 else { continue }
            for k in 1..<(poly.count - 1) {
                t.keptTriangles += 1
                if build { t.indices += [UInt32(poly[0]), UInt32(poly[k]), UInt32(poly[k + 1])] }
            }
            for k in poly.indices {
                let u = poly[k], v = poly[(k + 1) % poly.count]
                if onPlane.contains(u) && onPlane.contains(v) { planeEdges[UInt64(u) << 32 | UInt64(v), default: 0] += 1 }
            }
        }
        if !build {
            // Count-only mode stored plane points in creation order; rebuild the id -> slot map.
            var slot = 0
            for id in 0..<t.vertexCount where onPlane.contains(id) { planeSlot[id] = slot; slot += 1 }
        }
        // Open edges: a plane edge without its reverse. The cap uses each reversed, so its loops run counter-clockwise
        // about the normal around solid and clockwise around holes.
        var next: [Int: [Int]] = [:]
        var open = 0
        for (key, count) in planeEdges.sorted(by: { $0.key < $1.key }) {
            let u = Int(key >> 32), v = Int(key & 0xFFFF_FFFF)
            let back = planeEdges[UInt64(v) << 32 | UInt64(u)] ?? 0
            for _ in 0..<max(0, count - back) { next[v, default: []].append(u); open += 1 }
        }
        var loops: [[Int]] = []
        var used = 0
        for start in next.keys.sorted() {
            while let first = next[start]?.first {
                next[start]!.removeFirst(); used += 1
                var loop = [start], cur = first
                while cur != start {
                    loop.append(cur)
                    guard var outs = next[cur], !outs.isEmpty else { throw MGSolidIssue("section.loops") }
                    let nxt = outs.removeFirst(); next[cur] = outs; used += 1
                    cur = nxt
                }
                guard loop.count >= 3 else { throw MGSolidIssue("section.loops") }
                loops.append(loop)
            }
        }
        guard used == open else { throw MGSolidIssue("section.loops") }
        // Group loops by shell: outer loops (positive area about the normal) take the holes they contain, each hole
        // going to the smallest containing outer loop of its own shell.
        let (e1, e2) = basis(plane.normal)
        func flat(_ loop: [Int]) -> [MGVec2] { loop.map { let p = position($0); return MGVec2(p.dot(e1), p.dot(e2)) } }
        let flats = loops.map(flat)
        let areas = flats.map(MGProfile.signedArea)
        var groups: [Group] = []
        var groupFlat: [[MGVec2]] = []
        var groupShell: [Int] = []
        for (k, loop) in loops.enumerated() where areas[k] >= 0 {
            groups.append(Group(outer: loop, holes: [], area: areas[k])); groupFlat.append(flats[k]); groupShell.append(shellOf[loop[0]]!)
        }
        for (k, loop) in loops.enumerated() where areas[k] < 0 {
            let shell = shellOf[loop[0]]!, p = flats[k][0]
            let best = groups.indices.filter { groupShell[$0] == shell && MGSolidParser.inside(p, groupFlat[$0]) }
                .min { groups[$0].area < groups[$1].area }
            // Every hole point must lie inside its outer loop (hole bridging needs it); only a self-intersecting
            // input can fail this.
            guard let g = best, flats[k].allSatisfy({ MGSolidParser.inside($0, groupFlat[g]) }) else { throw MGSolidIssue("section.nesting") }
            groups[g].holes.append(loop); groups[g].area += areas[k]
        }
        // Each outer loop with h holes and m points in all triangulates into m + 2h - 2 triangles (ear clipping with
        // hole bridges, or the zipper strip for one hole).
        for g in groups { t.capTriangles += g.outer.count + g.holes.reduce(0) { $0 + $1.count } + 2 * g.holes.count - 2 }
        t.groups = groups
        return t
    }
}
