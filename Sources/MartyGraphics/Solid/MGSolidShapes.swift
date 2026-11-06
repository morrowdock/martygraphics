// SPDX-License-Identifier: Apache-2.0
import Foundation

/// A validated primitive from the solid part library, with its local offset inside the part.
///
/// Fields are kept as validated JSON so a document can tell cheaply whether a part's geometry changed.
public struct MGShapeSpec: Equatable, Sendable {
    public let kind: String
    public let fields: [String: MGJSON]
    public let offset: MGTransform

    func n(_ key: String, _ fallback: Double = 0) -> Double {
        if case .number(let d)? = fields[key] { return d }
        return fallback
    }
    func vec(_ key: String) -> [Double]? {
        guard case .array(let a)? = fields[key] else { return nil }
        return a.compactMap { if case .number(let d) = $0 { return d }; return nil }
    }
    func points(_ v: MGJSON?) -> [MGVec2] {
        guard case .array(let a)? = v else { return [] }
        return a.compactMap { p in
            guard case .array(let xy) = p, xy.count == 2, case .number(let x) = xy[0], case .number(let y) = xy[1] else { return nil }
            return MGVec2(x, y)
        }
    }

    /// Spur gear geometry for `gear` primitives.
    public var spurGear: MGSpurGear? {
        guard kind == "gear" else { return nil }
        return MGSpurGear(teeth: Int(n("teeth")), module: n("module"), pressureAngle: n("pressureAngle", 20) * .pi / 180, backlash: n("backlash", 0.06))
    }
    /// Ring gear geometry for `ringGear` primitives.
    public var ringGear: MGRingGear? {
        guard kind == "ringGear" else { return nil }
        return MGRingGear(teeth: Int(n("teeth")), module: n("module"), outerRadius: n("outer"),
                          pressureAngle: n("pressureAngle", 20) * .pi / 180, backlash: n("backlash", 0.06))
    }

    /// Builds the closed mesh in part-local coordinates (offset applied).
    public func mesh() -> MGMesh {
        let z0 = n("z0")
        let m: MGMesh
        switch kind {
        case "gear":
            let g = spurGear!
            let key = vec("keyway").map { (width: $0[0], depth: $0[1]) }
            m = .extrude(g.profile(bore: n("bore"), keyway: key), from: z0, to: z0 + n("width"), chamfer: n("chamfer", 0.28 * g.module))
        case "ringGear":
            let g = ringGear!
            m = .extrude(g.profile(outerSegments: 240), from: z0, to: z0 + n("width"), chamfer: n("chamfer", 0.28 * g.module))
        case "shaft":
            m = .cylinder(radius: n("radius"), from: z0, to: z0 + n("length"), chamfer: n("chamfer"), segments: segments(n("radius")))
        case "tube":
            m = .tube(inner: n("inner"), outer: n("outer"), from: z0, to: z0 + n("length"), chamfer: n("chamfer"), segments: segments(n("outer")))
        case "box":
            let s = vec("size") ?? [1, 1, 1]
            m = .chamferedBox(size: MGVec3(s[0], s[1], s[2]), chamfer: n("chamfer"))
        case "hex":
            m = .hexPrism(acrossFlats: n("acrossFlats"), from: z0, to: z0 + n("length"), chamfer: n("chamfer"))
        case "plate":
            var holes: [[MGVec2]] = []
            if case .array(let list)? = fields["holes"] {
                for h in list {
                    if case .array(let v) = h, v.count == 3, case .number(let x) = v[0], case .number(let y) = v[1], case .number(let r) = v[2] {
                        holes.append(MGProfile.circleLoop(radius: r, segments: max(16, min(64, Int(r * 6))), center: MGVec2(x, y)))
                    }
                }
            }
            let r = n("radius")
            m = .extrude(MGProfile(outer: MGProfile.circleLoop(radius: r, segments: segments(r) * 2), holes: holes),
                         from: z0, to: z0 + n("thickness"), chamfer: n("chamfer"))
        case "carrier":
            let outline = MGSolidModels.spiderOutline(armRadius: n("radius"), hubRadius: n("hub"), bossRadius: n("boss"),
                                                      armHalfWidth: n("armWidth") / 2, blend: max(0.5, n("blend", n("boss") * 0.5)),
                                                      samples: 720, arms: Int(n("arms")))
            m = .extrude(MGProfile(outer: outline), from: z0, to: z0 + n("thickness"), chamfer: n("chamfer"))
        case "extrudedProfile":
            var holes: [[MGVec2]] = []
            if case .array(let list)? = fields["holes"] { holes = list.map { points($0) } }
            m = .extrude(MGProfile(outer: points(fields["points"]), holes: holes), from: z0, to: z0 + n("depth"), chamfer: n("chamfer"))
        case "revolvedProfile":
            var closed = false
            if case .bool(let b)? = fields["closed"] { closed = b }
            let sweep = n("sweep", 360)
            m = sweep < 360 ? .revolve(points(fields["points"]), segments: 96, closed: closed, sweep: sweep * .pi / 180, start: n("start") * .pi / 180)
                : .revolve(points(fields["points"]), segments: 96, closed: closed)
        case "blade":
            m = .blade(span: n("span"), chord: n("chord"), thickness: n("thickness", 0.12), twist: n("twist") * .pi / 180,
                       root: n("root"), tipChord: n("tipChord", n("chord")), camber: n("camber"), camberPosition: n("camberPosition", 0.4))
        case "bladeRow":
            m = .bladeRow(count: Int(n("count")), span: n("span"), chord: n("chord"), root: n("root"), z: n("z"),
                          thickness: n("thickness", 0.1), stagger: n("stagger") * .pi / 180, twist: n("twist") * .pi / 180,
                          tipChord: n("tipChord", n("chord")), camber: n("camber"), camberPosition: n("camberPosition", 0.4),
                          phase: n("phase") * .pi / 180, sections: Int(n("sections", 8)), chordSamples: Int(n("chordSamples", 16)))
        default:
            m = MGMesh()
        }
        return offset == .identity ? m : m.transformed(offset)
    }

    func segments(_ r: Double) -> Int { max(24, min(128, Int(r * 4))) }

    /// Vertex and triangle counts of `mesh()`, computed from the fields without building the mesh (for budgets).
    public var meshEstimate: (vertices: Int, triangles: Int) {
        // `extrude`: every loop at 2 (or 4 with a chamfer) levels; walls between levels; two caps triangulated with
        // one bridge per hole (V + 2H - 2 triangles each).
        func extrude(_ loops: [Int], height: Double, chamfer: Double) -> (vertices: Int, triangles: Int) {
            let levels = max(0, min(chamfer, height / 2 - 1e-9)) > 0 ? 4 : 2
            let n = loops.reduce(0, +)
            return (n * levels, n * (levels - 1) * 2 + 2 * (n + 2 * (loops.count - 1) - 2))
        }
        // `revolve`: one ring per off-axis point, one vertex per pole.
        func revolve(_ points: Int, poles: Int, segments: Int, closed: Bool) -> (vertices: Int, triangles: Int) {
            ((points - poles) * segments + poles, 2 * segments * (closed ? points : points - 2))
        }
        switch kind {
        case "gear":
            let g = spurGear!
            let bore = n("bore")
            var loops = [g.outline().count]
            if bore > 0 {
                let key = vec("keyway").map { (width: $0[0], depth: $0[1]) }
                loops.append(MGSpurGear.boreLoop(radius: bore, segments: 72, keyway: key).count)
            }
            return extrude(loops, height: n("width"), chamfer: n("chamfer", 0.28 * g.module))
        case "ringGear":
            let g = ringGear!
            return extrude([240, g.outline().count], height: n("width"), chamfer: n("chamfer", 0.28 * g.module))
        case "shaft":
            let r = n("radius"), len = n("length")
            let c = max(0, min(n("chamfer"), r / 2, len / 2 - 1e-9))
            return revolve(c > 0 ? 6 : 4, poles: 2, segments: segments(r), closed: false)
        case "tube":
            let c = max(0, min(n("chamfer"), (n("outer") - n("inner")) / 3, n("length") / 2 - 1e-9))
            return revolve(c > 0 ? 8 : 4, poles: 0, segments: segments(n("outer")), closed: true)
        case "box":
            let s = vec("size") ?? [1, 1, 1]
            let c = max(0, min(n("chamfer"), min(s[0], s[1], s[2]) / 2 - 1e-6))
            return extrude([c > 0 ? 8 : 4], height: s[2], chamfer: c * 0.999)
        case "hex":
            return extrude([6], height: n("length"), chamfer: n("chamfer"))
        case "plate":
            var loops = [max(3, segments(n("radius")) * 2)]
            if case .array(let list)? = fields["holes"] {
                for h in list {
                    if case .array(let v) = h, v.count == 3, case .number(let r) = v[2] { loops.append(max(16, min(64, Int(r * 6)))) }
                }
            }
            return extrude(loops, height: n("thickness"), chamfer: n("chamfer"))
        case "carrier":
            return extrude([720], height: n("thickness"), chamfer: n("chamfer"))
        case "extrudedProfile":
            var loops = [points(fields["points"]).count]
            if case .array(let list)? = fields["holes"] { loops += list.map { points($0).count } }
            return extrude(loops, height: n("depth"), chamfer: n("chamfer"))
        case "revolvedProfile":
            let pts = points(fields["points"])
            var closed = false
            if case .bool(let b)? = fields["closed"] { closed = b }
            return revolve(pts.count, poles: pts.filter { $0.x < 1e-9 }.count, segments: 96, closed: closed)
        case "blade":
            // 15 sections of a 56-point loop, side quads between sections and two caps.
            return (15 * 56, 14 * 56 * 2 + 2 * (56 - 2))
        default:
            return (0, 0)
        }
    }
}

extension MGMesh {
    /// Twisted, tapered blade with a symmetric NACA 00xx section: span along +X from `root`, chord along Y,
    /// thickness along Z. `twist` (radians) rotates the tip section about the span axis relative to the root.
    /// `camber` (max camber as a chord fraction, NACA 4-digit "m") and `camberPosition` ("p") give a cambered section;
    /// the camber line offset is applied vertically (no thickness rotation), which is a schematic simplification.
    public static func blade(span: Double, chord: Double, thickness: Double, twist: Double, root: Double = 0, tipChord: Double? = nil,
                             camber: Double = 0, camberPosition: Double = 0.4, sections: Int = 14, chordSamples: Int = 28) -> MGMesh {
        func thick(_ x: Double) -> Double {
            5 * thickness * (0.2969 * x.squareRoot() - 0.1260 * x - 0.3516 * x * x + 0.2843 * x * x * x - 0.1036 * x * x * x * x)
        }
        func camberLine(_ x: Double) -> Double {
            guard camber > 0 else { return 0 }
            let m = camber, p = min(0.9, max(0.1, camberPosition))
            return x < p ? m / (p * p) * (2 * p * x - x * x) : m / ((1 - p) * (1 - p)) * ((1 - 2 * p) + 2 * p * x - x * x)
        }
        // Closed section loop (counter-clockwise in the chord/thickness plane), cosine-spaced.
        var loop: [MGVec2] = []
        for i in 0..<chordSamples {   // upper surface, trailing edge to leading edge
            let x = 0.5 * (1 + cos(Double.pi * Double(i) / Double(chordSamples)))
            loop.append(MGVec2(x, camberLine(x) + thick(x)))
        }
        for i in 0..<chordSamples {   // lower surface, leading edge to trailing edge
            let x = 0.5 * (1 - cos(Double.pi * Double(i) / Double(chordSamples)))
            loop.append(MGVec2(x, camberLine(x) - max(thick(x), i == 0 ? 0 : 1e-4)))
        }
        if MGProfile.signedArea(loop) < 0 { loop.reverse() }
        let n = loop.count
        var mesh = MGMesh()
        let c1 = tipChord ?? chord
        for s in 0...sections {
            let t = Double(s) / Double(sections)
            let c = chord + (c1 - chord) * t, a = twist * t, x = root + span * t
            for p in loop {
                // Section in (chord -> Y, thickness -> Z), quarter-chord pitch axis.
                let local = MGVec2((p.x - 0.25) * c, p.y * c).rotated(by: a)
                mesh.positions.append(MGVec3(x, local.x, local.y))
            }
        }
        // Sides: the loop is counter-clockwise seen from +X (the sweep direction), as in `extrude`.
        for s in 0..<sections {
            let lo = s * n, hi = (s + 1) * n
            for i in 0..<n {
                let j = (i + 1) % n
                mesh.indices += [UInt32(lo + i), UInt32(lo + j), UInt32(hi + j), UInt32(lo + i), UInt32(hi + j), UInt32(hi + i)]
            }
        }
        // Caps.
        let tris = MGTriangulator.triangulate(points: loop, outer: Array(0..<n), holes: [])
        let top = sections * n
        for (a, b, c) in tris {
            mesh.indices += [UInt32(a), UInt32(c), UInt32(b)]                       // root cap faces -X
            mesh.indices += [UInt32(top + a), UInt32(top + b), UInt32(top + c)]     // tip cap faces +X
        }
        return mesh
    }
}
