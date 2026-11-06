// SPDX-License-Identifier: Apache-2.0
// Example-local procedural geometry: involute gear profiles, chamfered extrusion, lathe solids,
// and crease-angle smoothing. Not part of the library API.
import Foundation
import simd
import MartyGraphicsPathTracer

/// Collects triangles; each is oriented to agree with an outward hint, so callers never track winding.
struct MeshBuilder {
    private(set) var triangles: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)] = []

    mutating func tri(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, outward hint: SIMD3<Float>) {
        let n = simd_cross(b - a, c - a)
        // Drop zero-area slivers (they carry meaningless face normals into the smoothing).
        let longest = max(simd_length_squared(b - a), simd_length_squared(c - a), simd_length_squared(c - b))
        guard simd_length(n) > 1e-6 * longest, simd_length_squared(n) > 1e-18 else { return }
        triangles.append(simd_dot(n, hint) >= 0 ? (a, b, c) : (a, c, b))
    }

    mutating func quad(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ d: SIMD3<Float>, outward hint: SIMD3<Float>) {
        tri(a, b, c, outward: hint)
        tri(a, c, d, outward: hint)
    }

    /// Welds positions, smooths normals across edges flatter than `creaseDegrees`, and adds
    /// circumferential tangents about the local +y axis (for radially brushed metal).
    func mesh(material: UInt32, creaseDegrees: Float = 32) -> MGRTMesh {
        let cosCrease = cos(creaseDegrees * .pi / 180)
        func key(_ p: SIMD3<Float>) -> SIMD3<Int32> { SIMD3<Int32>((p * 1e5).rounded(.toNearestOrEven)) }
        var ids: [SIMD3<Int32>: Int] = [:]
        var corners: [[Int]] = []  // per welded position: list of triangle*3+k
        var cornerPos: [Int] = []
        var faceN: [SIMD3<Float>] = []
        var angles: [Float] = []
        for (t, tri) in triangles.enumerated() {
            let p = [tri.0, tri.1, tri.2]
            faceN.append(simd_normalize(simd_cross(p[1] - p[0], p[2] - p[0])))
            for k in 0..<3 {
                let e1 = simd_normalize(p[(k + 1) % 3] - p[k]), e2 = simd_normalize(p[(k + 2) % 3] - p[k])
                angles.append(acos(min(max(simd_dot(e1, e2), -1), 1)))
                let kk = key(p[k])
                let id: Int
                if let existing = ids[kk] { id = existing } else { id = corners.count; ids[kk] = id; corners.append([]) }
                corners[id].append(t * 3 + k)
                cornerPos.append(id)
            }
        }
        var positions: [SIMD3<Float>] = [], normals: [SIMD3<Float>] = [], tangents: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        indices.reserveCapacity(triangles.count * 3)
        var vertexIDs: [SIMD4<Int32>: UInt32] = [:]
        for (t, tri) in triangles.enumerated() {
            let p = [tri.0, tri.1, tri.2]
            for k in 0..<3 {
                var n = SIMD3<Float>.zero
                for c in corners[cornerPos[t * 3 + k]] {
                    let f = c / 3
                    if simd_dot(faceN[f], faceN[t]) >= cosCrease { n += faceN[f] * angles[c] }
                }
                n = simd_length_squared(n) > 0 ? simd_normalize(n) : faceN[t]
                let q = SIMD3<Int32>((n * 2000).rounded(.toNearestOrEven))
                let vk = SIMD4<Int32>(Int32(cornerPos[t * 3 + k]), q.x, q.y, q.z)
                if let v = vertexIDs[vk] {
                    indices.append(v)
                } else {
                    let v = UInt32(positions.count)
                    vertexIDs[vk] = v
                    positions.append(p[k])
                    normals.append(n)
                    let tan = SIMD3<Float>(p[k].z, 0, -p[k].x)
                    tangents.append(simd_length_squared(tan) > 1e-10 ? simd_normalize(tan) : SIMD3(1, 0, 0))
                    indices.append(v)
                }
            }
        }
        return MGRTMesh(positions: positions, normals: normals, tangents: tangents, indices: indices, material: material)
    }
}

enum Involute {
    static func inv(_ a: Double) -> Double { tan(a) - a }

    struct Spec {
        var teeth: Int
        var module: Double
        var pressureAngle: Double = 20 * .pi / 180
        /// Tooth thinning (external) or space widening (internal) as arc length at the pitch circle.
        var backlash: Double = 0.04
        var pitchRadius: Double { Double(teeth) * module / 2 }
        var baseRadius: Double { pitchRadius * cos(pressureAngle) }
    }

    /// Half the angular width of an external tooth (or internal space) at radius `r`.
    /// Below the base circle (external gears) the involute cannot continue; a smooth root fillet
    /// widens the tooth quadratically toward the root circle, tangent to the involute at the base circle,
    /// so the outline's polar angle stays strictly monotonic.
    static func halfAngle(_ s: Spec, _ r: Double, isInternal: Bool) -> Double {
        let thin = s.backlash * s.module / (2 * s.pitchRadius)
        func involutePart(_ rr: Double) -> Double {
            let ar = acos(min(1, s.baseRadius / rr))
            return .pi / (2 * Double(s.teeth)) + inv(s.pressureAngle) - inv(ar) + (isInternal ? thin : -thin)
        }
        guard r < s.baseRadius else { return involutePart(r) }
        let rf = s.pitchRadius - 1.25 * s.module
        let atBase = involutePart(s.baseRadius)
        let widen = 0.3 * (.pi / Double(s.teeth) - atBase)
        let x = (s.baseRadius - r) / max(s.baseRadius - rf, 1e-9)
        return atBase + widen * x * x
    }

    /// Radii along a flank from `r0` to `r1`, dense where the involute curves most.
    static func flankRadii(_ s: Spec, from r0: Double, to r1: Double, samples: Int) -> [Double] {
        var radii: [Double] = []
        if r0 < s.baseRadius {
            for i in 0..<4 { radii.append(r0 + (s.baseRadius - r0) * Double(i) / 4) }
        }
        let t0 = sqrt(max(0, pow(max(r0, s.baseRadius) / s.baseRadius, 2) - 1))
        let t1 = sqrt(max(0, pow(r1 / s.baseRadius, 2) - 1))
        for i in 0...samples {
            let t = t0 + (t1 - t0) * Double(i) / Double(samples)
            radii.append(s.baseRadius * sqrt(1 + t * t))
        }
        return radii
    }

    /// Closed CCW outline of an external spur gear, monotonic in angle (star-shaped about the centre).
    /// Tooth 0 is centred on angle 0.
    static func external(_ s: Spec, flank: Int = 12, arc: Int = 5) -> [SIMD2<Float>] {
        let ra = s.pitchRadius + s.module, rf = s.pitchRadius - 1.25 * s.module
        let pitch = 2 * Double.pi / Double(s.teeth)
        let radii = flankRadii(s, from: rf, to: ra, samples: flank)
        var pts: [(Double, Double)] = []  // (angle, radius)
        for k in 0..<s.teeth {
            let c = Double(k) * pitch
            let psiRoot = halfAngle(s, rf, isInternal: false), psiTip = halfAngle(s, ra, isInternal: false)
            for i in 0..<arc { pts.append((c - pitch / 2 + (pitch / 2 - psiRoot) * Double(i) / Double(arc), rf)) }
            for r in radii { pts.append((c - halfAngle(s, r, isInternal: false), r)) }
            for i in 1..<arc { pts.append((c - psiTip + 2 * psiTip * Double(i) / Double(arc), ra)) }
            for r in radii.reversed() { pts.append((c + halfAngle(s, r, isInternal: false), r)) }
            for i in 1..<arc { pts.append((c + psiRoot + (pitch / 2 - psiRoot) * Double(i) / Double(arc), rf)) }
        }
        return clean(pts)
    }

    /// Closed CCW inner outline of an internal (ring) gear. Tooth 0 (pointing inward) is centred on angle 0.
    static func `internal`(_ s: Spec, flank: Int = 12, arc: Int = 5) -> [SIMD2<Float>] {
        let rTip = s.pitchRadius - s.module, rRoot = s.pitchRadius + 1.25 * s.module
        let pitch = 2 * Double.pi / Double(s.teeth)
        let radii = flankRadii(s, from: rTip, to: rRoot, samples: flank)
        var pts: [(Double, Double)] = []
        for k in 0..<s.teeth {
            let c = Double(k) * pitch + pitch / 2  // space centre
            let psiTip = halfAngle(s, rTip, isInternal: true), psiRoot = halfAngle(s, rRoot, isInternal: true)
            for i in 0..<arc { pts.append((c - pitch / 2 + (pitch / 2 - psiTip) * Double(i) / Double(arc), rTip)) }
            for r in radii { pts.append((c - halfAngle(s, r, isInternal: true), r)) }
            for i in 1..<arc { pts.append((c - psiRoot + 2 * psiRoot * Double(i) / Double(arc), rRoot)) }
            for r in radii.reversed() { pts.append((c + halfAngle(s, r, isInternal: true), r)) }
            for i in 1..<arc { pts.append((c + psiTip + (pitch / 2 - psiTip) * Double(i) / Double(arc), rTip)) }
        }
        return clean(pts)
    }

    private static func clean(_ pts: [(Double, Double)]) -> [SIMD2<Float>] {
        var out: [SIMD2<Float>] = []
        for (a, r) in pts {
            let p = SIMD2<Float>(Float(r * cos(a)), Float(r * sin(a)))
            if let last = out.last, simd_distance(last, p) < 1e-6 { continue }
            out.append(p)
        }
        if let first = out.first, let last = out.last, simd_distance(first, last) < 1e-6 { out.removeLast() }
        return out
    }

    /// True when the contour's polar angle strictly increases and winds once (star-shaped about the centre).
    static func isAngularlyMonotonic(_ pts: [SIMD2<Float>]) -> Bool {
        var total: Double = 0
        for i in 0..<pts.count {
            let a = pts[i], b = pts[(i + 1) % pts.count]
            var d = Double(atan2(b.y, b.x) - atan2(a.y, a.x))
            if d < -Double.pi { d += 2 * .pi }
            if d > Double.pi { d -= 2 * .pi }
            if d <= 0 { return false }
            total += d
        }
        return abs(total - 2 * .pi) < 1e-3
    }
}

enum Solids {
    static func world(_ p: SIMD2<Float>, _ y: Float) -> SIMD3<Float> { SIMD3(p.x, y, p.y) }

    /// Per-vertex outward normals of a closed CCW contour (mitred).
    static func contourNormals(_ c: [SIMD2<Float>]) -> [SIMD2<Float>] {
        let n = c.count
        return (0..<n).map { i in
            let prev = c[(i + n - 1) % n], cur = c[i], next = c[(i + 1) % n]
            let e0 = simd_normalize(cur - prev), e1 = simd_normalize(next - cur)
            let n0 = SIMD2(e0.y, -e0.x), n1 = SIMD2(e1.y, -e1.x)
            let m = simd_normalize(n0 + n1)
            return m / max(simd_dot(m, n0), 0.5)
        }
    }

    /// Circle sampled at the angles of `like`, so the annulus between them triangulates by index.
    /// Points that share a polar angle (radial flank segments) map to one identical point, so the
    /// resulting cap triangles are exactly degenerate and dropped without leaving cracks.
    static func circle(radius: Float, like contour: [SIMD2<Float>]) -> [SIMD2<Float>] {
        var out: [SIMD2<Float>] = []
        var lastAngle: Float = .nan
        for p in contour {
            let a = atan2(p.y, p.x)
            if let prev = out.last, abs(a - lastAngle) < 2e-5 { out.append(prev); continue }
            out.append(radius * simd_normalize(p))
            lastAngle = a
        }
        return out
    }

    static func circle(radius: Float, segments: Int) -> [SIMD2<Float>] {
        (0..<segments).map { i in
            let a = 2 * Float.pi * Float(i) / Float(segments)
            return SIMD2(radius * cos(a), radius * sin(a))
        }
    }

    /// Solid between two index-matched CCW contours (`outer` encloses `inner`), from y0 to y1,
    /// with 45° chamfers of size `chamfer` on all four edge loops.
    static func annulus(outer: [SIMD2<Float>], inner: [SIMD2<Float>], y0: Float, y1: Float, chamfer c: Float,
                        into b: inout MeshBuilder) {
        precondition(outer.count == inner.count, "contours must match")
        let n = outer.count
        let no = contourNormals(outer), ni = contourNormals(inner)
        let oIn = (0..<n).map { outer[$0] - c * no[$0] }, iIn = (0..<n).map { inner[$0] + c * ni[$0] }
        let ya = y0 + c, yb = y1 - c
        for i in 0..<n {
            let j = (i + 1) % n
            let edgeO = simd_normalize(SIMD2(outer[j].y - outer[i].y, -(outer[j].x - outer[i].x)))
            let edgeI = simd_normalize(SIMD2(inner[j].y - inner[i].y, -(inner[j].x - inner[i].x)))
            let hO = SIMD3(edgeO.x, 0, edgeO.y), hI = -SIMD3(edgeI.x, 0, edgeI.y)
            b.quad(world(outer[i], ya), world(outer[j], ya), world(outer[j], yb), world(outer[i], yb), outward: hO)
            b.quad(world(inner[i], ya), world(inner[j], ya), world(inner[j], yb), world(inner[i], yb), outward: hI)
            if c > 0 {
                b.quad(world(oIn[i], y0), world(oIn[j], y0), world(outer[j], ya), world(outer[i], ya), outward: hO - SIMD3(0, 1, 0))
                b.quad(world(outer[i], yb), world(outer[j], yb), world(oIn[j], y1), world(oIn[i], y1), outward: hO + SIMD3(0, 1, 0))
                b.quad(world(iIn[i], y0), world(iIn[j], y0), world(inner[j], ya), world(inner[i], ya), outward: hI - SIMD3(0, 1, 0))
                b.quad(world(inner[i], yb), world(inner[j], yb), world(iIn[j], y1), world(iIn[i], y1), outward: hI + SIMD3(0, 1, 0))
            }
            b.quad(world(iIn[i], y1), world(oIn[i], y1), world(oIn[j], y1), world(iIn[j], y1), outward: SIMD3(0, 1, 0))
            b.quad(world(iIn[i], y0), world(oIn[i], y0), world(oIn[j], y0), world(iIn[j], y0), outward: SIMD3(0, -1, 0))
        }
    }

    /// Solid of revolution about +y from a closed (r, y) profile (either orientation).
    static func lathe(_ profile: [SIMD2<Float>], segments: Int, into b: inout MeshBuilder) {
        var p = profile
        var area: Float = 0
        for i in 0..<p.count { let a = p[i], c = p[(i + 1) % p.count]; area += a.x * c.y - c.x * a.y }
        if area < 0 { p.reverse() }
        for k in 0..<p.count {
            let a = p[k], c = p[(k + 1) % p.count]
            let e = c - a
            guard simd_length_squared(e) > 0 else { continue }
            let n2 = simd_normalize(SIMD2(e.y, -e.x))
            for i in 0..<segments {
                let t0 = 2 * Float.pi * Float(i) / Float(segments), t1 = 2 * Float.pi * Float(i + 1) / Float(segments)
                let tm = (t0 + t1) / 2
                func pt(_ q: SIMD2<Float>, _ t: Float) -> SIMD3<Float> { SIMD3(q.x * cos(t), q.y, q.x * sin(t)) }
                b.quad(pt(a, t0), pt(a, t1), pt(c, t1), pt(c, t0), outward: SIMD3(n2.x * cos(tm), n2.y, n2.x * sin(tm)))
            }
        }
    }

    /// A chamfered cylinder (or tube when `inner` > 0) from y0 to y1.
    static func cylinderProfile(outer r: Float, inner: Float = 0, y0: Float, y1: Float, chamfer c: Float) -> [SIMD2<Float>] {
        var pts: [SIMD2<Float>] = []
        if inner > 0 {
            pts += [SIMD2(inner + c, y0), SIMD2(r - c, y0), SIMD2(r, y0 + c), SIMD2(r, y1 - c), SIMD2(r - c, y1),
                    SIMD2(inner + c, y1), SIMD2(inner, y1 - c), SIMD2(inner, y0 + c)]
        } else {
            pts += [SIMD2(0, y0), SIMD2(r - c, y0), SIMD2(r, y0 + c), SIMD2(r, y1 - c), SIMD2(r - c, y1), SIMD2(0, y1)]
        }
        return pts
    }

    /// A flat square floor made of `cells`×`cells` quads, normal +y.
    static func floor(halfSize: Float, cells: Int, into b: inout MeshBuilder) {
        let step = 2 * halfSize / Float(cells)
        for j in 0..<cells {
            for i in 0..<cells {
                let x0 = -halfSize + Float(i) * step, z0 = -halfSize + Float(j) * step
                b.quad(SIMD3(x0, 0, z0), SIMD3(x0 + step, 0, z0), SIMD3(x0 + step, 0, z0 + step), SIMD3(x0, 0, z0 + step),
                       outward: SIMD3(0, 1, 0))
            }
        }
    }
}
