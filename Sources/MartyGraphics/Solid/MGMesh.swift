// SPDX-License-Identifier: Apache-2.0
import Foundation

/// An indexed triangle mesh with shared (welded) vertices.
///
/// The topology is kept welded so closedness can be checked edge by edge. Rendering normals are derived
/// separately by `renderMesh(creaseAngle:)`, which splits vertices only across sharp edges: gear flanks stay
/// smooth while tooth tips, chamfers and caps keep crisp edges.
public struct MGMesh: Equatable, Sendable {
    public var positions: [MGVec3]
    /// Counter-clockwise triangles (seen from outside), three indices each.
    public var indices: [UInt32]

    public init(positions: [MGVec3] = [], indices: [UInt32] = []) {
        self.positions = positions; self.indices = indices
    }

    public var triangleCount: Int { indices.count / 3 }

    public func triangle(_ i: Int) -> (Int, Int, Int) {
        (Int(indices[3 * i]), Int(indices[3 * i + 1]), Int(indices[3 * i + 2]))
    }

    /// Unnormalised face normal (length = twice the triangle area).
    public func faceNormal(_ i: Int) -> MGVec3 {
        let (a, b, c) = triangle(i)
        return (positions[b] - positions[a]).cross(positions[c] - positions[a])
    }

    public var bounds: MGBounds {
        var b = MGBounds.empty
        for p in positions { b.include(p) }
        return b
    }

    /// Signed volume from the divergence theorem; positive when faces wind outward.
    public var signedVolume: Double {
        var v = 0.0
        for i in 0..<triangleCount {
            let (a, b, c) = triangle(i)
            v += positions[a].dot(positions[b].cross(positions[c]))
        }
        return v / 6
    }

    public var surfaceArea: Double {
        (0..<triangleCount).reduce(0) { $0 + faceNormal($1).length / 2 }
    }

    /// Edge-manifold report. A closed, consistently oriented mesh has every directed edge exactly once and
    /// its reverse exactly once, so each undirected edge is shared by exactly two triangles.
    public struct EdgeReport: Equatable, Sendable {
        public var edges = 0
        /// Undirected edges used by only one triangle (holes in the surface).
        public var boundaryEdges = 0
        /// Undirected edges used by more than two triangles, or twice in the same direction (flipped faces).
        public var badEdges = 0
        public var degenerateTriangles = 0
        public var isClosed: Bool { boundaryEdges == 0 && badEdges == 0 && edges > 0 }
    }

    public var edgeReport: EdgeReport {
        var directed: [UInt64: Int] = [:]
        directed.reserveCapacity(indices.count)
        var report = EdgeReport()
        func key(_ a: Int, _ b: Int) -> UInt64 { UInt64(a) << 32 | UInt64(b) }
        for i in 0..<triangleCount {
            let (a, b, c) = triangle(i)
            if a == b || b == c || a == c { report.degenerateTriangles += 1; continue }
            for (u, v) in [(a, b), (b, c), (c, a)] { directed[key(u, v), default: 0] += 1 }
        }
        var seen = Set<UInt64>()
        for (k, n) in directed {
            let u = Int(k >> 32), v = Int(k & 0xFFFF_FFFF)
            let lo = min(u, v), hi = max(u, v)
            guard seen.insert(key(lo, hi)).inserted else { continue }
            report.edges += 1
            let forward = directed[key(lo, hi)] ?? 0, backward = directed[key(hi, lo)] ?? 0
            if forward == 1 && backward == 1 { continue }
            if forward + backward == 1 { report.boundaryEdges += 1 } else { report.badEdges += 1 }
            _ = n
        }
        return report
    }

    /// Fraction of triangles whose normal points away from the mesh centroid (a cheap outward check for
    /// star-shaped parts; the signed volume is the authoritative orientation test).
    public func outwardFraction(about center: MGVec3? = nil) -> Double {
        guard triangleCount > 0 else { return 0 }
        let c = center ?? bounds.center
        var out = 0
        for i in 0..<triangleCount {
            let (a, b, cc) = triangle(i)
            let centroid = (positions[a] + positions[b] + positions[cc]) * (1.0 / 3)
            if faceNormal(i).dot(centroid - c) > 0 { out += 1 }
        }
        return Double(out) / Double(triangleCount)
    }

    public func transformed(_ t: MGTransform) -> MGMesh {
        MGMesh(positions: positions.map(t.apply), indices: indices)
    }

    /// Appends another mesh (disjoint shells stay separate and individually closed).
    public mutating func append(_ other: MGMesh) {
        let base = UInt32(positions.count)
        positions += other.positions
        indices += other.indices.map { $0 + base }
    }

    public static func merged(_ meshes: [MGMesh]) -> MGMesh {
        var m = MGMesh()
        for part in meshes { m.append(part) }
        return m
    }

    /// Render-ready mesh with per-vertex normals. Faces meeting at more than `creaseAngle` radians are
    /// shaded flat across that edge; smaller angles are smoothed (area weighted). `0` gives flat shading,
    /// `.pi` fully smooth shading.
    public func renderMesh(creaseAngle: Double = 0.6) -> MGRenderMesh {
        let n = triangleCount
        var faceN = [MGVec3](repeating: .zero, count: n)
        var unit = [MGVec3](repeating: .zero, count: n)
        var incident = [[Int32]](repeating: [], count: positions.count)
        for i in 0..<n {
            faceN[i] = faceNormal(i); unit[i] = faceN[i].normalized
            let (a, b, c) = triangle(i)
            incident[a].append(Int32(i)); incident[b].append(Int32(i)); incident[c].append(Int32(i))
        }
        let threshold = cos(creaseAngle) - 1e-9
        var outPositions: [MGVec3] = [], outNormals: [MGVec3] = [], outIndices: [UInt32] = []
        outPositions.reserveCapacity(positions.count * 2); outNormals.reserveCapacity(positions.count * 2)
        outIndices.reserveCapacity(indices.count)
        // Per original vertex: list of (normal, new index) already emitted, to share identical corners.
        var emitted = [[(MGVec3, UInt32)]](repeating: [], count: positions.count)
        for i in 0..<n {
            let corners = triangle(i)
            for v in [corners.0, corners.1, corners.2] {
                var sum = MGVec3.zero
                for g in incident[v] where unit[Int(g)].dot(unit[i]) >= threshold { sum += faceN[Int(g)] }
                let normal = sum.length > 0 ? sum.normalized : unit[i]
                if let hit = emitted[v].first(where: { ($0.0 - normal).length < 1e-6 }) {
                    outIndices.append(hit.1)
                } else {
                    let idx = UInt32(outPositions.count)
                    outPositions.append(positions[v]); outNormals.append(normal)
                    emitted[v].append((normal, idx)); outIndices.append(idx)
                }
            }
        }
        return MGRenderMesh(positions: outPositions, normals: outNormals, indices: outIndices)
    }
}

/// Mesh with split vertices and per-vertex unit normals, ready for a GPU renderer.
public struct MGRenderMesh: Equatable, Sendable {
    public var positions: [MGVec3]
    public var normals: [MGVec3]
    public var indices: [UInt32]
}
