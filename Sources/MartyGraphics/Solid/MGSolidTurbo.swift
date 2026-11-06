// SPDX-License-Identifier: Apache-2.0
import Foundation

// Turbomachinery primitives for the solid kernel: blade rows (airfoils wrapped on cylinders and repeated around the
// axis) and partial revolves with capped cut faces (cutaway casings). Foundation only.

extension MGMesh {
    /// A row of `count` identical blades around the Z axis, one closed shell per blade.
    ///
    /// Every blade section lies on a cylinder `r = root + span * t` (t = 0 at the root, 1 at the tip), so the tip is
    /// exactly at `root + span` at every angle. The section is a NACA 4-digit style airfoil; its mid-chord sits at
    /// axial position `z` and its leading edge points toward -Z (upstream).
    ///
    /// - `stagger`: chord angle from the axis at the root (radians). Positive puts the trailing edge behind the leading
    ///   edge in the direction of rotation (-θ), as on a compressor or fan rotor turning toward +θ.
    /// - `twist`: extra stagger at the tip (radians), linear along the span.
    /// - `camber`: signed maximum camber (chord fraction). Positive bows the blade toward +θ.
    /// - `phase`: angle of the first blade (radians).
    public static func bladeRow(count: Int, span: Double, chord: Double, root: Double, z: Double = 0, thickness: Double = 0.1,
                                stagger: Double = 0, twist: Double = 0, tipChord: Double? = nil, camber: Double = 0,
                                camberPosition: Double = 0.4, phase: Double = 0, sections: Int = 8, chordSamples: Int = 16) -> MGMesh {
        let blade = rowBlade(span: span, chord: chord, root: root, z: z, thickness: thickness, stagger: stagger, twist: twist,
                             tipChord: tipChord ?? chord, camber: camber, camberPosition: camberPosition,
                             sections: max(1, sections), chordSamples: max(4, chordSamples))
        var row = MGMesh()
        for k in 0..<max(1, count) {
            row.append(blade.transformed(.rotation(axis: .unitZ, angle: phase + 2 * .pi * Double(k) / Double(max(1, count)))))
        }
        return row
    }

    /// Closed airfoil loop in chord units (x 0 = leading edge, 1 = trailing edge), counter-clockwise.
    static func airfoilLoop(thickness: Double, camber: Double, camberPosition: Double, samples: Int) -> [MGVec2] {
        func thick(_ x: Double) -> Double {
            5 * thickness * (0.2969 * x.squareRoot() - 0.1260 * x - 0.3516 * x * x + 0.2843 * x * x * x - 0.1036 * x * x * x * x)
        }
        let m = abs(camber), p = min(0.9, max(0.1, camberPosition)), sign: Double = camber < 0 ? -1 : 1
        func camberLine(_ x: Double) -> Double {
            guard m > 0 else { return 0 }
            return sign * (x < p ? m / (p * p) * (2 * p * x - x * x) : m / ((1 - p) * (1 - p)) * ((1 - 2 * p) + 2 * p * x - x * x))
        }
        var loop: [MGVec2] = []
        for i in 0..<samples {   // upper surface, trailing edge to leading edge
            let x = 0.5 * (1 + cos(Double.pi * Double(i) / Double(samples)))
            loop.append(MGVec2(x, camberLine(x) + thick(x)))
        }
        for i in 0..<samples {   // lower surface, leading edge to trailing edge
            let x = 0.5 * (1 - cos(Double.pi * Double(i) / Double(samples)))
            loop.append(MGVec2(x, camberLine(x) - max(thick(x), i == 0 ? 0 : 1e-4)))
        }
        if MGProfile.signedArea(loop) < 0 { loop.reverse() }
        return loop
    }

    /// Section of a row blade at span fraction `t`, in unwrapped (axial z, tangential arc length w) coordinates.
    static func rowSection(_ loop: [MGVec2], t: Double, chord: Double, tipChord: Double, z: Double, stagger: Double, twist: Double) -> [MGVec2] {
        let c = chord + (tipChord - chord) * t, b = stagger + twist * t
        let cb = cos(b), sb = sin(b)
        return loop.map { p in
            let u = (p.x - 0.5) * c, v = p.y * c
            return MGVec2(z + u * cb + v * sb, -u * sb + v * cb)
        }
    }

    static func rowBlade(span: Double, chord: Double, root: Double, z: Double, thickness: Double, stagger: Double, twist: Double,
                         tipChord: Double, camber: Double, camberPosition: Double, sections: Int, chordSamples: Int) -> MGMesh {
        let loop = airfoilLoop(thickness: thickness, camber: camber, camberPosition: camberPosition, samples: chordSamples)
        let n = loop.count
        var mesh = MGMesh()
        for s in 0...sections {
            let t = Double(s) / Double(sections)
            let r = root + span * t
            for q in rowSection(loop, t: t, chord: chord, tipChord: tipChord, z: z, stagger: stagger, twist: twist) {
                let a = q.y / r
                mesh.positions.append(MGVec3(r * cos(a), r * sin(a), q.x))
            }
        }
        for s in 0..<sections {
            let lo = s * n, hi = (s + 1) * n
            for i in 0..<n {
                let j = (i + 1) % n
                mesh.indices += [UInt32(lo + i), UInt32(lo + j), UInt32(hi + j), UInt32(lo + i), UInt32(hi + j), UInt32(hi + i)]
            }
        }
        let tris = MGTriangulator.triangulate(points: loop, outer: Array(0..<n), holes: [])
        let top = sections * n
        for (a, b, c) in tris {
            mesh.indices += [UInt32(a), UInt32(c), UInt32(b)]
            mesh.indices += [UInt32(top + a), UInt32(top + b), UInt32(top + c)]
        }
        if mesh.signedVolume < 0 { mesh.flipWinding() }
        return mesh
    }

    /// Reverses every triangle (turns the surface inside out).
    mutating func flipWinding() {
        for t in 0..<triangleCount { indices.swapAt(3 * t + 1, 3 * t + 2) }
    }

    /// Revolves a profile through `sweep` radians starting at angle `start`, closing both cut faces with flat caps.
    ///
    /// Same profile rules as `revolve(_:segments:closed:)`; a sweep of a full turn gives that result. Used for
    /// cutaway casings: the caps are real solid faces, so any renderer shows the wall section.
    public static func revolve(_ points: [MGVec2], segments: Int = 96, closed: Bool, sweep: Double, start: Double = 0) -> MGMesh {
        guard sweep < 2 * .pi - 1e-9 else { return revolve(points, segments: segments, closed: closed) }
        precondition(points.count >= 2 && sweep > 0, "revolve needs a profile and a positive sweep")
        var prof = points
        if MGProfile.signedArea(prof) < 0 { prof.reverse() }
        if !closed { precondition(prof.first!.x < 1e-9 && prof.last!.x < 1e-9, "open revolve profiles must end on the axis") }
        let n = max(2, Int((Double(max(3, segments)) * sweep / (2 * .pi)).rounded(.up)))
        var mesh = MGMesh()
        var first: [Int] = [], isPole: [Bool] = []
        for p in prof {
            first.append(mesh.positions.count)
            if p.x < 1e-9 {
                isPole.append(true); mesh.positions.append(MGVec3(0, 0, p.y))
            } else {
                isPole.append(false)
                for j in 0...n {
                    let a = start + sweep * Double(j) / Double(n)
                    mesh.positions.append(MGVec3(p.x * cos(a), p.x * sin(a), p.y))
                }
            }
        }
        func v(_ k: Int, _ j: Int) -> UInt32 { UInt32(isPole[k] ? first[k] : first[k] + j) }
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
        // Caps: the profile polygon (closed along the axis for open profiles) at both ends of the sweep.
        let tris = MGTriangulator.triangulate(points: prof, outer: Array(0..<count), holes: [])
        for (a, b, c) in tris {
            mesh.indices += [v(a, 0), v(b, 0), v(c, 0)]
            mesh.indices += [v(a, n), v(c, n), v(b, n)]
        }
        if mesh.signedVolume < 0 { mesh.flipWinding() }
        return mesh
    }
}

/// Validation for the turbomachinery shape fields (used by `MGSolidParser`). Reasons are stable strings.
enum MGSolidTurbo {
    static let bladeRowKeys: (required: Set<String>, optional: Set<String>) =
        (["count", "span", "chord", "root"],
         ["z", "thickness", "stagger", "twist", "tipChord", "camber", "camberPosition", "phase", "sections", "chordSamples"])
    /// Triangles one blade row may produce.
    static let rowTriangles = 250_000

    static func number(_ f: [String: MGJSON], _ key: String, _ range: ClosedRange<Double>, _ fallback: Double? = nil) throws -> Double {
        guard let v = f[key] else {
            if let d = fallback { return d }
            throw MGSolidIssue("part.bladeRow.\(key)")
        }
        guard case .number(let d) = v, d.isFinite, range.contains(d) else { throw MGSolidIssue("part.bladeRow.\(key)") }
        return d
    }

    static func integer(_ f: [String: MGJSON], _ key: String, _ range: ClosedRange<Double>, _ fallback: Double? = nil) throws -> Int {
        let d = try number(f, key, range, fallback)
        guard d.rounded() == d else { throw MGSolidIssue("part.bladeRow.\(key)") }
        return Int(d)
    }

    static func validateBladeRow(_ f: [String: MGJSON]) throws {
        let L = MGSolidLimits.length
        let count = try integer(f, "count", 2...128)
        let span = try number(f, "span", L), chord = try number(f, "chord", L), root = try number(f, "root", L)
        let tipChord = try number(f, "tipChord", L, chord)
        _ = try number(f, "z", MGSolidLimits.coordinate, 0)
        let thickness = try number(f, "thickness", 0.02...0.4, 0.1)
        let stagger = try number(f, "stagger", -80...80, 0), twist = try number(f, "twist", -80...80, 0)
        guard abs(stagger + twist) <= 85 else { throw MGSolidIssue("part.bladeRow.twist") }
        let camber = try number(f, "camber", -0.09...0.09, 0)
        let camberPosition = try number(f, "camberPosition", 0.1...0.9, 0.4)
        _ = try number(f, "phase", -360...360, 0)
        let sections = try integer(f, "sections", 2...24, 8), samples = try integer(f, "chordSamples", 6...32, 16)
        let perBlade = sections * 4 * samples + 2 * (2 * samples - 2)
        guard count * perBlade <= rowTriangles else { throw MGSolidIssue("part.bladeRow.triangles") }
        // Sections must stay well inside a half turn of their cylinder, and neighbouring blades must not touch.
        let loop = MGMesh.airfoilLoop(thickness: thickness, camber: camber, camberPosition: camberPosition, samples: samples)
        for t in [0.0, 0.5, 1.0] {
            let r = root + span * t
            let section = MGMesh.rowSection(loop, t: t, chord: chord, tipChord: tipChord, z: 0, stagger: stagger * .pi / 180,
                                            twist: twist * .pi / 180)
            let w = section.map(\.y)
            guard let lo = w.min(), let hi = w.max(), max(abs(lo), abs(hi)) < r else { throw MGSolidIssue("part.bladeRow.chord") }
            let pitch = 2 * Double.pi * r / Double(count)
            let next = section.map { MGVec2($0.x, $0.y + pitch) }
            guard !MGSolidParser.loopsCross(section, next), !MGSolidParser.inside(next[0], section) else {
                throw MGSolidIssue("part.bladeRow.count")
            }
        }
    }

    /// Optional `sweep` (degrees, 1...360) and `start` (degrees) of a revolved profile.
    static func validateSweep(_ f: [String: MGJSON]) throws {
        if let s = f["sweep"] {
            guard case .number(let d) = s, d.isFinite, (1...360).contains(d) else { throw MGSolidIssue("part.revolvedProfile.sweep") }
        }
        if let s = f["start"] {
            guard case .number(let d) = s, d.isFinite, (-360...360).contains(d) else { throw MGSolidIssue("part.revolvedProfile.start") }
        }
    }
}
