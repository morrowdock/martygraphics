// SPDX-License-Identifier: Apache-2.0
import Foundation

/// A planar region: one outer loop and zero or more hole loops, in the XY plane.
///
/// Orientation is normalised on construction: the outer loop runs counter-clockwise and holes run clockwise,
/// so material is always on the left of travel. Loops are implicitly closed (do not repeat the first point).
public struct MGProfile: Equatable, Sendable {
    public private(set) var outer: [MGVec2]
    public private(set) var holes: [[MGVec2]]

    public init(outer: [MGVec2], holes: [[MGVec2]] = []) {
        self.outer = MGProfile.signedArea(outer) < 0 ? outer.reversed() : outer
        self.holes = holes.map { MGProfile.signedArea($0) > 0 ? $0.reversed() : $0 }
    }

    /// Shoelace area; positive for counter-clockwise loops.
    public static func signedArea(_ loop: [MGVec2]) -> Double {
        guard loop.count > 2 else { return 0 }
        var a = 0.0
        for i in loop.indices { a += loop[i].cross(loop[(i + 1) % loop.count]) }
        return a / 2
    }

    /// Net area (outer minus holes).
    public var area: Double { MGProfile.signedArea(outer) + holes.reduce(0) { $0 + MGProfile.signedArea($1) } }

    public func withHoles(_ extra: [[MGVec2]]) -> MGProfile { MGProfile(outer: outer, holes: holes + extra) }

    // MARK: Primitive loops

    public static func circleLoop(radius: Double, segments: Int, center: MGVec2 = .zero, phase: Double = 0) -> [MGVec2] {
        (0..<max(3, segments)).map { center + MGVec2.polar(radius, phase + 2 * .pi * Double($0) / Double(max(3, segments))) }
    }

    public static func circle(radius: Double, segments: Int = 96) -> MGProfile {
        MGProfile(outer: circleLoop(radius: radius, segments: segments))
    }

    public static func annulus(inner: Double, outer: Double, segments: Int = 96) -> MGProfile {
        MGProfile(outer: circleLoop(radius: outer, segments: segments), holes: [circleLoop(radius: inner, segments: segments)])
    }

    /// Rectangle centred on the origin with rounded corners (`cornerRadius` 0 gives sharp corners).
    public static func roundedRectLoop(width: Double, height: Double, cornerRadius: Double, cornerSegments: Int = 6) -> [MGVec2] {
        let r = max(0, min(cornerRadius, min(width, height) / 2 - 1e-9))
        let hx = width / 2 - r, hy = height / 2 - r
        if r == 0 { return [MGVec2(-hx, -hy), MGVec2(hx, -hy), MGVec2(hx, hy), MGVec2(-hx, hy)] }
        var pts: [MGVec2] = []
        let centres = [MGVec2(hx, -hy), MGVec2(hx, hy), MGVec2(-hx, hy), MGVec2(-hx, -hy)]
        for (k, c) in centres.enumerated() {
            let start = -Double.pi / 2 + Double(k) * .pi / 2
            for s in 0...cornerSegments { pts.append(c + MGVec2.polar(r, start + Double(s) / Double(cornerSegments) * .pi / 2)) }
        }
        return pts
    }

    public static func regularPolygonLoop(sides: Int, circumradius: Double, phase: Double = 0, center: MGVec2 = .zero) -> [MGVec2] {
        circleLoop(radius: circumradius, segments: sides, center: center, phase: phase)
    }

    /// Smooth closed outline around several circles (a convex "lobed" plate, e.g. a planet carrier), built as the
    /// convex hull of densely sampled circles.
    public static func lobedLoop(lobes: [(center: MGVec2, radius: Double)], segments: Int = 48) -> [MGVec2] {
        var pts: [MGVec2] = []
        for l in lobes { pts += circleLoop(radius: l.radius, segments: segments, center: l.center) }
        return convexHull(pts)
    }

    /// Andrew's monotone chain; returns a counter-clockwise hull without collinear points.
    public static func convexHull(_ points: [MGVec2]) -> [MGVec2] {
        let p = points.sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
        guard p.count > 2 else { return p }
        func half(_ seq: [MGVec2]) -> [MGVec2] {
            var h: [MGVec2] = []
            for q in seq {
                while h.count >= 2, (h[h.count - 1] - h[h.count - 2]).cross(q - h[h.count - 2]) <= 1e-12 { h.removeLast() }
                h.append(q)
            }
            return h
        }
        let lower = half(p), upper = half(p.reversed())
        return Array(lower.dropLast() + upper.dropLast())
    }

    /// Offsets a loop by `distance` toward its left side (into the material for normalised loops), using mitred
    /// vertex normals. Intended for small chamfer insets that are smaller than the local feature size.
    public static func inset(_ loop: [MGVec2], by distance: Double) -> [MGVec2] {
        let n = loop.count
        guard n > 2, distance != 0 else { return loop }
        return (0..<n).map { i in
            let prev = loop[(i + n - 1) % n], cur = loop[i], next = loop[(i + 1) % n]
            let n1 = (cur - prev).normalized.perpendicular, n2 = (next - cur).normalized.perpendicular
            var m = (n1 + n2).normalized
            if m.length == 0 { m = n1 }
            let c = max(0.35, m.dot(n1))
            return cur + m * (distance / c)
        }
    }

    // MARK: Polar helpers (for star-shaped loops around the origin)

    /// True when the loop's polar angle about the origin never decreases (counter-clockwise order) and sweeps one
    /// full turn: the loop is star-shaped about the origin and can be zipped with another such loop.
    public static func isPolarMonotonic(_ loopCCW: [MGVec2]) -> Bool {
        guard loopCCW.count > 2, !loopCCW.contains(where: { $0.length < 1e-12 }) else { return false }
        var total = 0.0
        for i in loopCCW.indices {
            var d = loopCCW[(i + 1) % loopCCW.count].angle - loopCCW[i].angle
            while d <= -.pi { d += 2 * .pi }
            while d > .pi { d -= 2 * .pi }
            if d < -1e-12 { return false }
            total += d
        }
        return abs(total - 2 * .pi) < 1e-6
    }

    /// Polar boundary function of a polar-monotonic counter-clockwise loop: the distance from the origin to the
    /// loop's polygon along the ray at `angle`. Exact for the straight-edged polygon.
    public struct PolarBoundary: Sendable {
        let points: [MGVec2]
        let angles: [Double]   // unwrapped, non-decreasing, angles[0] in (-pi, pi]

        public init(loopCCW: [MGVec2]) {
            points = loopCCW
            var a: [Double] = [loopCCW[0].angle]
            for i in 1..<loopCCW.count {
                var d = loopCCW[i].angle - loopCCW[i - 1].angle
                while d < -1e-12 { d += 2 * .pi }
                a.append(a[i - 1] + d)
            }
            angles = a
        }

        public func radius(at angle: Double) -> Double {
            var t = angle
            while t < angles[0] { t += 2 * .pi }
            while t >= angles[0] + 2 * .pi { t -= 2 * .pi }
            // Largest i with angles[i] <= t.
            var lo = 0, hi = angles.count - 1
            if t >= angles[hi] { lo = hi } else {
                while hi - lo > 1 { let mid = (lo + hi) / 2; if angles[mid] <= t { lo = mid } else { hi = mid } }
            }
            let a = points[lo], b = points[(lo + 1) % points.count]
            let u = MGVec2(cos(t), sin(t)), e = b - a
            let den = u.cross(e)
            if abs(den) < 1e-15 { return max(a.length, b.length) }
            return a.cross(e) / den
        }
    }
}

/// Polygon triangulation for profile caps.
public enum MGTriangulator {
    /// Triangulates a profile whose points are given by index into `points`. Returns counter-clockwise triangles
    /// (seen from +Z). Uses a zipper merge for star-shaped annuli (gears, rings, tubes) and ear clipping with
    /// hole bridging otherwise.
    public static func triangulate(points: [MGVec2], outer: [Int], holes: [[Int]]) -> [(Int, Int, Int)] {
        if holes.count == 1 {
            let o = outer.map { points[$0] }, h = Array(holes[0].reversed()).map { points[$0] }
            if MGProfile.isPolarMonotonic(o), MGProfile.isPolarMonotonic(h) {
                let strip = zipper(points: points, outer: outer, innerCCW: Array(holes[0].reversed()))
                // Keep the strip only when every triangle winds counter-clockwise (then it covers the region once).
                if strip.allSatisfy({ a, b, c in (points[b] - points[a]).cross(points[c] - points[a]) > 0 }) { return strip }
            }
        }
        return earClip(points: points, outer: outer, holes: holes)
    }

    /// Merges two polar-monotonic CCW loops around the origin into a triangle strip.
    static func zipper(points: [MGVec2], outer: [Int], innerCCW: [Int]) -> [(Int, Int, Int)] {
        func unwrap(_ loop: [Int], from start: Double) -> [Double] {
            var a: [Double] = []
            var prev = start
            for (k, i) in loop.enumerated() {
                var t = points[i].angle
                if k == 0 { while t < start - 1e-12 { t += 2 * .pi }; while t >= start + 2 * .pi { t -= 2 * .pi } }
                else { while t < prev - 1e-12 { t += 2 * .pi } }
                a.append(t); prev = t
            }
            return a
        }
        let a0 = points[outer[0]].angle
        let ao = unwrap(outer, from: a0) + [a0 + 2 * .pi]
        // Rotate the inner loop so it starts at the last vertex at or before a0: the strip then opens with the inner
        // chain behind the outer one, never ahead of it (an inner apex ahead of a falling flank winds backwards).
        let raw = innerCCW.map { (points[$0].angle - a0).truncatingRemainder(dividingBy: 2 * .pi) }
        let norm = raw.map { $0 > 1e-12 ? $0 - 2 * .pi : $0 }   // in (-2 pi, 0]
        let start = norm.indices.max { norm[$0] < norm[$1] } ?? 0
        let inner = Array(innerCCW[start...] + innerCCW[..<start])
        var ai0: [Double] = [a0 + norm[start]]
        for k in inner.indices.dropFirst() {
            var t = points[inner[k]].angle
            let prev = ai0[k - 1]
            while t < prev - 1e-12 { t += 2 * .pi }
            while t - 2 * .pi >= prev - 1e-12 { t -= 2 * .pi }
            ai0.append(t)
        }
        let ai = ai0 + [ai0[0] + 2 * .pi]
        let n = outer.count, m = inner.count
        var i = 0, j = 0
        var tris: [(Int, Int, Int)] = []
        tris.reserveCapacity(n + m)
        while i < n || j < m {
            var advanceOuter = j >= m || (i < n && ao[i + 1] <= ai[j + 1])
            if i < n && j < m {
                // Angle order alone can wind a triangle backwards next to steep (near-radial) edges such as tooth
                // flanks. When only the other candidate is counter-clockwise, take it, but never let a chain run
                // more than one step ahead of the angle order (that would leave long overlapping slivers).
                let o0 = points[outer[i % n]], o1 = points[outer[(i + 1) % n]]
                let q0 = points[inner[j % m]], q1 = points[inner[(j + 1) % m]]
                let outerOK = (o1 - o0).cross(q0 - o0) > 0, innerOK = (q1 - o0).cross(q0 - o0) > 0
                if advanceOuter, !outerOK, innerOK, ai[j] <= ao[i + 1] { advanceOuter = false }
                else if !advanceOuter, !innerOK, outerOK, ao[i] <= ai[j + 1] { advanceOuter = true }
            }
            if advanceOuter {
                tris.append((outer[i % n], outer[(i + 1) % n], inner[j % m])); i += 1
            } else {
                tris.append((outer[i % n], inner[(j + 1) % m], inner[j % m])); j += 1
            }
        }
        return tris
    }

    /// Ear clipping with hole bridging (after Eberly, "Triangulation by Ear Clipping").
    static func earClip(points: [MGVec2], outer: [Int], holes: [[Int]]) -> [(Int, Int, Int)] {
        var poly = outer
        let orderedHoles = holes.filter { $0.count > 2 }.sorted { h1, h2 in
            (h1.map { points[$0].x }.max() ?? 0) > (h2.map { points[$0].x }.max() ?? 0)
        }
        for hole in orderedHoles { poly = bridge(points: points, poly: poly, hole: hole) }
        return clip(points: points, poly: poly)
    }

    static func bridge(points: [MGVec2], poly: [Int], hole: [Int]) -> [Int] {
        let hStart = hole.indices.max { points[hole[$0]].x < points[hole[$1]].x }!
        let m = points[hole[hStart]]
        // Cast a ray toward +x; find the closest edge crossing.
        var bestX = Double.infinity, bestEdge = -1
        let n = poly.count
        for k in 0..<n {
            let a = points[poly[k]], b = points[poly[(k + 1) % n]]
            guard (a.y - m.y) * (b.y - m.y) <= 0, a.y != b.y else { continue }
            let x = a.x + (m.y - a.y) / (b.y - a.y) * (b.x - a.x)
            if x >= m.x - 1e-12, x < bestX { bestX = x; bestEdge = k }
        }
        precondition(bestEdge >= 0, "hole is not inside the outer loop m=\(m) poly=\(poly.count) hole=\(hole.count) outer0=\(points[poly[0]])")
        let a = points[poly[bestEdge]], b = points[poly[(bestEdge + 1) % n]]
        var candidate = a.x > b.x ? bestEdge : (bestEdge + 1) % n
        let ip = MGVec2(bestX, m.y), pp = points[poly[candidate]]
        // Any reflex vertex inside triangle (m, ip, pp) blocks visibility; pick the one with the smallest angle.
        var bestAngle = Double.infinity
        for k in 0..<n where k != candidate {
            let q = points[poly[k]]
            guard q.x >= m.x, isReflex(points, poly, k) else { continue }
            if pointInTriangle(q, m, ip, pp) || pointInTriangle(q, m, pp, ip) {
                let d = q - m
                let ang = abs(atan2(d.y, d.x))
                if ang < bestAngle || (ang == bestAngle && d.length < (points[poly[candidate]] - m).length) {
                    bestAngle = ang; candidate = k
                }
            }
        }
        let holeSeq = Array(hole[hStart...] + hole[..<hStart]) + [hole[hStart]]
        return Array(poly[...candidate]) + holeSeq + [poly[candidate]] + Array(poly[(candidate + 1)...])
    }

    static func isReflex(_ points: [MGVec2], _ poly: [Int], _ k: Int) -> Bool {
        let n = poly.count
        let a = points[poly[(k + n - 1) % n]], b = points[poly[k]], c = points[poly[(k + 1) % n]]
        return (b - a).cross(c - b) <= 0
    }

    static func pointInTriangle(_ p: MGVec2, _ a: MGVec2, _ b: MGVec2, _ c: MGVec2) -> Bool {
        let d1 = (b - a).cross(p - a), d2 = (c - b).cross(p - b), d3 = (a - c).cross(p - c)
        return d1 >= -1e-12 && d2 >= -1e-12 && d3 >= -1e-12
    }

    static func clip(points: [MGVec2], poly input: [Int]) -> [(Int, Int, Int)] {
        var poly = input
        var tris: [(Int, Int, Int)] = []
        tris.reserveCapacity(poly.count)
        var guardCount = 0
        var k = 0
        while poly.count > 3 {
            let n = poly.count
            let ia = poly[(k + n - 1) % n], ib = poly[k % n], ic = poly[(k + 1) % n]
            let a = points[ia], b = points[ib], c = points[ic]
            var ear = (b - a).cross(c - b) > 1e-14
            if ear {
                for q in poly where q != ia && q != ib && q != ic {
                    let p = points[q]
                    if p == a || p == b || p == c { continue }
                    if pointInTriangle(p, a, b, c) { ear = false; break }
                }
            }
            if ear {
                tris.append((ia, ib, ic)); poly.remove(at: k % n); guardCount = 0
                k = max(0, (k % n) - 1)
            } else {
                k = (k + 1) % n; guardCount += 1
                if guardCount > n {
                    // Degenerate input: drop the flattest vertex to guarantee progress.
                    let flat = (0..<n).min { x, y in
                        abs((points[poly[x]] - points[poly[(x + n - 1) % n]]).cross(points[poly[(x + 1) % n]] - points[poly[x]])) <
                        abs((points[poly[y]] - points[poly[(y + n - 1) % n]]).cross(points[poly[(y + 1) % n]] - points[poly[y]]))
                    }!
                    tris.append((poly[(flat + n - 1) % n], poly[flat], poly[(flat + 1) % n]))
                    poly.remove(at: flat); guardCount = 0; k = 0
                }
            }
        }
        if poly.count == 3 { tris.append((poly[0], poly[1], poly[2])) }
        return tris
    }
}
