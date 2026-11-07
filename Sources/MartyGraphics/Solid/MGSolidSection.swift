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
        // A cut built in code may carry any numbers: a mesh with bad indices renders as nothing, and the cap start is
        // clamped, so this never traps.
        guard MGSolidSection.isWellFormed(mesh) else { return MGRenderMesh(positions: [], normals: [], indices: []) }
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

extension MGSectionCut {
    /// True when the cap range is valid (the last `capTriangleCount ≥ 1` triangles), the cut is a closed, outward mesh
    /// (`edgeReport.isClosed`, `signedVolume > 0`) and its cap triangle areas add up to the cap area (outer loops minus
    /// holes) within 1e-6 × max(1, cap area), so caps do not overlap or fold back. Linear time. The compiler refuses a
    /// step cut that fails it (`section.open.<id>`). It is a consistency check, not a proof: it does not test that cap
    /// vertices lie on the plane or that each shell is outward, and at sizes far below 1 mm² its absolute tolerance
    /// can miss a folded cap.
    public var isSound: Bool {
        // The caps are the last triangles: check the range without arithmetic that could overflow.
        let n = mesh.triangleCount
        guard capFirstTriangle >= 0, capFirstTriangle <= n, capTriangleCount >= 1, capTriangleCount == n - capFirstTriangle else { return false }
        guard MGSolidSection.isWellFormed(mesh), mesh.edgeReport.isClosed, mesh.signedVolume > 0 else { return false }
        var sum = 0.0
        for i in capFirstTriangle..<n { sum += mesh.faceNormal(i).length / 2 }
        return capArea >= 0 && abs(sum - capArea) <= 1e-6 * max(1, capArea)
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
        let e = try estimate(mesh, plane, workLimit: .max)
        return (e.triangles, e.vertices)
    }

    /// The pre-pass with a cap work limit (`section.budget` when exceeded); also returns the cap work it charged.
    static func estimate(_ mesh: MGMesh, _ plane: MGSectionPlane, workLimit: Int) throws -> (triangles: Int, vertices: Int, work: Int) {
        let t = try topology(mesh, plane, build: false, workLimit: workLimit)
        return (t.keptTriangles + t.capTriangles, t.vertexCount, t.work)
    }

    /// Cuts a closed mesh by the plane and caps every cut. Reasons: `section.mesh` (bad indices or non-finite numbers),
    /// `section.miss` / `section.empty` (the plane removes nothing / everything: `crossing` is not `.cuts`),
    /// `section.loops` (the open edges left by the cut do not chain into closed loops, so the input was not closed)
    /// and `section.nesting` (a hole loop lies outside every outer loop). Check `isSound` on the result.
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
            guard let tris = MGCapTriangulator.triangulate(points: pts, outer: slots[0], holes: Array(slots.dropFirst())) else {
                throw MGSolidIssue("section.nesting")
            }
            for (a, b, c) in tris {
                out.indices += [UInt32(ids[a]), UInt32(ids[b]), UInt32(ids[c])]
            }
            area += group.area
        }
        return MGSectionCut(mesh: out, capFirstTriangle: capFirst, capTriangleCount: out.triangleCount - capFirst, plane: plane,
                            loops: t.groups.reduce(0) { $0 + 1 + $1.holes.count }, capArea: area)
    }

    // MARK: Pre-pass

    struct Group { var outer: [Int]; var holes: [[Int]]; var area: Double; var outerArea: Double }

    /// Splits a closed vertex loop at every repeated vertex into simple loops (each of at least three vertices).
    static func simpleLoops(_ loop: [Int]) throws -> [[Int]] {
        var out: [[Int]] = [], stack: [Int] = [], at: [Int: Int] = [:]
        for v in loop {
            if let i = at[v] {
                out.append(Array(stack[i...]))
                for u in stack[(i + 1)...] { at[u] = nil }
                stack.removeSubrange((i + 1)...)
            } else { at[v] = stack.count; stack.append(v) }
        }
        out.append(stack)
        guard out.allSatisfy({ $0.count >= 3 }) else { throw MGSolidIssue("section.loops") }
        return out
    }
    struct Topology {
        var keptTriangles = 0, capTriangles = 0, vertexCount = 0, work = 0
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
    /// `workLimit`: cap work units (loop points grouped, containment and bridge scans) the pre-pass may spend before it
    /// refuses with `section.budget`; `work` reports what it spent.
    static func topology(_ mesh: MGMesh, _ plane: MGSectionPlane, build: Bool, workLimit: Int = .max) throws -> Topology {
        var work = 0
        guard isWellFormed(mesh), plane.normal.dot(plane.normal).isFinite, plane.offset.isFinite else { throw MGSolidIssue("section.mesh") }
        switch crossing(mesh, plane) {
        case .misses: throw MGSolidIssue("section.miss")
        case .removesAll: throw MGSolidIssue("section.empty")
        case .cuts: break
        }
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
        // A loop that passes a vertex twice (two sections touching at a point, or a bore that touches the outer wall)
        // is split there into simple loops.
        var simple: [[Int]] = []
        for loop in loops { simple += try simpleLoops(loop) }
        // Group loops: outer loops (positive area about the normal) take the holes they contain. Each hole goes to the
        // containing outer loop with the smallest own (gross) area in its own shell; a cavity whose outer loop is in
        // another shell (an inverted inner shell) falls back to any shell. A hole that touches its outer loop at a
        // vertex is spliced into the outer loop there instead of bridged.
        let (e1, e2) = basis(plane.normal)
        func flat(_ loop: [Int]) -> [MGVec2] { loop.map { let p = position($0); return MGVec2(p.dot(e1), p.dot(e2)) } }
        let flats = simple.map(flat)
        let areas = flats.map(MGProfile.signedArea)
        var groups: [Group] = []
        var groupFlat: [[MGVec2]] = []
        var groupIDs: [Set<Int>] = []
        var groupShell: [Int] = []
        for (k, loop) in simple.enumerated() where areas[k] >= 0 {
            groups.append(Group(outer: loop, holes: [], area: areas[k], outerArea: areas[k]))
            groupFlat.append(flats[k]); groupIDs.append(Set(loop)); groupShell.append(shellOf[loop[0]]!)
        }
        // Hole -> outer search, fast for nested and concentric loops: outer loops are walked in order of gross
        // area from the first one large enough to hold the hole; a bounding-box test rejects most, and one hole point
        // (not a vertex of that outer loop) decides containment with a single point-in-polygon test. Every visit is
        // charged to the cap work budget (`section.budget`), so no arrangement of loops can run long.
        func charge(_ units: Int) throws {
            work += units
            guard work <= workLimit else { throw MGSolidIssue("section.budget") }
        }
        func box(_ f: [MGVec2]) -> (MGVec2, MGVec2) {
            var lo = f[0], hi = f[0]
            for q in f { lo = MGVec2(min(lo.x, q.x), min(lo.y, q.y)); hi = MGVec2(max(hi.x, q.x), max(hi.y, q.y)) }
            return (lo, hi)
        }
        try charge(flats.reduce(0) { $0 + $1.count })
        let order = groups.indices.sorted { (groups[$0].outerArea, $0) < (groups[$1].outerArea, $1) }
        let orderedArea = order.map { groups[$0].outerArea }
        let groupBox = groupFlat.map(box)
        for (k, loop) in simple.enumerated() where areas[k] < 0 {
            let shell = shellOf[loop[0]]!
            let hb = box(flats[k])
            let tol = 1e-9 * max(1, hb.1.x - hb.0.x, hb.1.y - hb.0.y)
            // First outer loop whose gross area could hold this hole (binary search).
            var lo = 0, hi = order.count
            while lo < hi { let mid = (lo + hi) / 2; if orderedArea[mid] < -areas[k] * (1 - 1e-9) { lo = mid + 1 } else { hi = mid } }
            func smallest(sameShell: Bool) throws -> Int? {
                for g in order[lo...] {
                    try charge(1)
                    guard !sameShell || groupShell[g] == shell else { continue }
                    let (b0, b1) = groupBox[g]
                    guard b0.x <= hb.0.x + tol, b0.y <= hb.0.y + tol, b1.x >= hb.1.x - tol, b1.y >= hb.1.y - tol else { continue }
                    guard let i = loop.firstIndex(where: { !groupIDs[g].contains($0) }) else { try charge(loop.count); continue }
                    try charge(i + 1 + groupFlat[g].count)
                    if MGSolidParser.inside(flats[k][i], groupFlat[g]) { return g }
                }
                return nil
            }
            guard let g = try smallest(sameShell: true) ?? smallest(sameShell: false) else { throw MGSolidIssue("section.nesting") }
            if let j = loop.firstIndex(where: { groupIDs[g].contains($0) }), let i = groups[g].outer.firstIndex(of: loop[j]) {
                // Splice: …, v, (the hole from after v round to before v), v, … : one weakly simple outer loop.
                try charge(2 * (groups[g].outer.count + loop.count))
                let o = groups[g].outer
                let around = Array(loop[(j + 1)...] + loop[..<j])
                groups[g].outer = Array(o[...i]) + around + [loop[j]] + Array(o[(i + 1)...])
                groupFlat[g] = flat(groups[g].outer)
                groupIDs[g].formUnion(loop)
            } else {
                try charge(loop.count)
                groups[g].holes.append(loop)
            }
            groups[g].area += areas[k]
        }
        // Triangulation work (charged here, before any cap is built): bridging each hole scans the polygon built so
        // far twice (the bridge ray and its visibility test) plus one containment test against the outer loop; the
        // zipper strip and the grid ear clipper visit each point a bounded number of times on ordinary loops.
        for g in groups {
            var poly = g.outer.count
            try charge(poly)
            for h in g.holes { try charge(3 * poly + h.count); poly += h.count + 2 }
        }
        // Each outer loop with h bridged holes and m points in all triangulates into m + 2h - 2 triangles (ear clipping
        // with hole bridges, or the zipper strip for one hole).
        for g in groups { t.capTriangles += g.outer.count + g.holes.reduce(0) { $0 + $1.count } + 2 * g.holes.count - 2 }
        t.groups = groups
        t.work = work
        return t
    }
}

/// Cap triangulation for section loops. One hole: the zipper strip when both loops are star-shaped about the hole's
/// centre and every strip triangle winds counter-clockwise (linear). Otherwise holes are bridged into the outer loop
/// (`MGTriangulator.bridge`) and the polygon is ear-clipped on a linked list, testing only reflex vertices through a
/// uniform grid, so gear-sized loops (thousands of points) clip fast (no proven linear bound). Both give exactly
/// m + 2h - 2 triangles for m points and h holes.
enum MGCapTriangulator {
    /// nil when a hole's rightmost point is not inside the outer loop (bridging needs it; only a self-intersecting
    /// input can fail), so bridging never traps.
    static func triangulate(points: [MGVec2], outer: [Int], holes: [[Int]]) -> [(Int, Int, Int)]? {
        if holes.count == 1 {
            let h = holes[0].map { points[$0] }
            let c = h.reduce(MGVec2.zero, +) * (1 / Double(h.count))
            let local = points.map { $0 - c }
            let o = outer.map { local[$0] }, hl = Array(holes[0].reversed()).map { local[$0] }
            if MGProfile.isPolarMonotonic(o), MGProfile.isPolarMonotonic(hl) {
                let strip = MGTriangulator.zipper(points: local, outer: outer, innerCCW: Array(holes[0].reversed()))
                if strip.allSatisfy({ a, b, c in (local[b] - local[a]).cross(local[c] - local[a]) > 0 }) { return strip }
            }
        }
        var poly = outer
        let ordered = holes.filter { $0.count > 2 }.sorted { h1, h2 in
            (h1.map { points[$0].x }.max() ?? 0) > (h2.map { points[$0].x }.max() ?? 0)
        }
        let outerLoop = outer.map { points[$0] }
        for hole in ordered {
            guard let right = hole.max(by: { points[$0].x < points[$1].x }), MGSolidParser.inside(points[right], outerLoop) else { return nil }
            poly = MGTriangulator.bridge(points: points, poly: poly, hole: hole)
        }
        return clip(points, poly)
    }

    /// Ear clipping of one (weakly simple, counter-clockwise) polygon given as point indices; poly.count - 2 triangles.
    static func clip(_ points: [MGVec2], _ poly: [Int]) -> [(Int, Int, Int)] {
        let n = poly.count
        guard n >= 3 else { return [] }
        var next = (0..<n).map { ($0 + 1) % n }, prev = (0..<n).map { ($0 + n - 1) % n }
        var removed = [Bool](repeating: false, count: n)
        func p(_ k: Int) -> MGVec2 { points[poly[k]] }
        func convex(_ k: Int) -> Bool { (p(k) - p(prev[k])).cross(p(next[k]) - p(k)) > 1e-14 }
        // Grid over the polygon bounds holding the nodes that are not convex (only they can lie inside an ear).
        var lo = p(0), hi = p(0)
        for k in 0..<n { let q = p(k); lo = MGVec2(min(lo.x, q.x), min(lo.y, q.y)); hi = MGVec2(max(hi.x, q.x), max(hi.y, q.y)) }
        let side = max(1, Int(Double(n).squareRoot()))
        let w = max(hi.x - lo.x, 1e-12), h = max(hi.y - lo.y, 1e-12)
        let tol = 1e-9 * max(1, w, h)
        func cell(_ x: Double, _ y: Double) -> (Int, Int) {
            (min(side - 1, max(0, Int((x - lo.x) / w * Double(side)))), min(side - 1, max(0, Int((y - lo.y) / h * Double(side)))))
        }
        var grid = [[Int]](repeating: [], count: side * side)
        var reflex = [Bool](repeating: false, count: n)
        func register(_ k: Int) {
            let now = !convex(k)
            if now && !reflex[k] { let (cx, cy) = cell(p(k).x, p(k).y); grid[cy * side + cx].append(k) }
            reflex[k] = now
        }
        for k in 0..<n { register(k) }
        func isEar(_ k: Int) -> Bool {
            guard convex(k) else { return false }
            let ia = prev[k], ic = next[k], a = p(ia), b = p(k), c = p(ic)
            let (x0, y0) = cell(min(a.x, b.x, c.x) - tol, min(a.y, b.y, c.y) - tol)
            let (x1, y1) = cell(max(a.x, b.x, c.x) + tol, max(a.y, b.y, c.y) + tol)
            for cy in y0...y1 { for cx in x0...x1 { for q in grid[cy * side + cx] where reflex[q] && !removed[q] && q != ia && q != k && q != ic {
                let pq = p(q)
                if pq == a || pq == b || pq == c { continue }
                if MGTriangulator.pointInTriangle(pq, a, b, c) { return false }
            } } }
            return true
        }
        var tris: [(Int, Int, Int)] = []
        tris.reserveCapacity(n - 2)
        var alive = n, k = 0, misses = 0
        func cut(_ k: Int) {
            tris.append((poly[prev[k]], poly[k], poly[next[k]]))
            removed[k] = true
            let a = prev[k], b = next[k]
            next[a] = b; prev[b] = a; alive -= 1
            register(a); register(b)
        }
        while alive > 3 {
            if isEar(k) {
                let back = prev[k]
                cut(k); k = back; misses = 0
            } else {
                k = next[k]; misses += 1
                if misses > alive {
                    // Degenerate input: cut the flattest vertex to guarantee progress (as `MGTriangulator.clip` does).
                    var best = k, bestFlat = Double.infinity, q = k
                    for _ in 0..<alive {
                        let f = abs((p(q) - p(prev[q])).cross(p(next[q]) - p(q)))
                        if f < bestFlat { bestFlat = f; best = q }
                        q = next[q]
                    }
                    k = prev[best]; cut(best); misses = 0
                }
            }
        }
        tris.append((poly[prev[k]], poly[k], poly[next[k]]))
        return tris
    }
}
