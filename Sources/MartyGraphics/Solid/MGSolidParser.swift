// SPDX-License-Identifier: Apache-2.0
import Foundation

/// Hard limits for the solid assembly format v1. Input outside them is rejected, never clamped.
public enum MGSolidLimits {
    public static let bytes = 64 * 1024
    /// Wire parts (before `repeat`) and resolved parts (after).
    public static let parts = 48, resolvedParts = 96
    public static let shapesPerPart = 8, repeatCount = 12
    public static let profilePoints = 256, profileHoles = 16, plateHoles = 32
    public static let constraints = 128, steps = 16, idsPerStep = 16
    public static let title = 80, name = 60, say = 240
    public static let teeth: ClosedRange<Double> = 8...200, ringTeeth: ClosedRange<Double> = 20...400
    public static let module: ClosedRange<Double> = 0.2...20
    /// Lengths and coordinates in millimetres.
    public static let length: ClosedRange<Double> = 0.05...4000, coordinate: ClosedRange<Double> = -4000...4000
}

/// A rejection with a stable machine reason (for example `part.gear.teeth`) and the part it concerns, if any.
public struct MGSolidIssue: Error, Equatable, CustomStringConvertible, Sendable {
    public let reason: String
    public let part: String?
    public init(_ reason: String, part: String? = nil) { self.reason = reason; self.part = part }
    public var description: String { part.map { "\(reason) (\($0))" } ?? reason }
}

/// One authored step of an explainer.
public struct MGSolidStep: Equatable, Sendable {
    public var say: String
    public var focus: [String]
    public var highlight: [String]
    public var explode: Double?
    public var camera: String?
    /// Extra yaw in degrees added to the camera preset.
    public var orbit: Double
    /// Input turns played during the step (for example to show the gears running).
    public var spin: Double
}

/// Meshing data the compiler derived for one gear part.
public struct MGSolidGear: Equatable, Sendable {
    public var part: String
    public var spur: MGSpurGear?
    public var ring: MGRingGear?
    /// Gear frame in the part frame (the primitive's offset).
    public var local: MGTransform
    public var teeth: Int { spur?.teeth ?? ring?.teeth ?? 0 }
    public var module: Double { spur?.module ?? ring?.module ?? 0 }
}

/// A parsed, validated, compiled assembly document.
public struct MGSolidDocument: Equatable, Sendable {
    public var title: String
    public var assembly: MGAssembly
    public var steps: [MGSolidStep]
    public var defaults: MGPoseParameters
    public var gears: [String: MGSolidGear]
    /// Per-part validated shapes (stable identity: unchanged shapes keep their meshes across patches).
    public var shapes: [String: [MGShapeSpec]]
    /// Input-to-joint ratios the constraint solver found (joint radians or mm per input radian).
    public var ratios: [String: Double]
    /// The source JSON this document was compiled from.
    public var source: MGJSON

    public func pose(_ params: MGPoseParameters) -> MGPose { assembly.pose(params) }
}

/// Strict decoder and compiler for the solid assembly JSON format (closed keys, bounded values, resolved references).
public enum MGSolidParser {
    public static func document(data: Data, reusing previous: MGSolidDocument? = nil) -> Result<MGSolidDocument, MGSolidIssue> {
        guard data.count <= MGSolidLimits.bytes else { return .failure(.init("assembly.bytes")) }
        guard let object = try? JSONSerialization.jsonObject(with: data), let json = MGJSON(any: object) else {
            return .failure(.init("json"))
        }
        return document(json: json, reusing: previous)
    }

    public static func document(json: MGJSON, reusing previous: MGSolidDocument? = nil) -> Result<MGSolidDocument, MGSolidIssue> {
        do { return .success(try compile(json, previous)) }
        catch let e as MGSolidIssue { return .failure(e) }
        catch let e as MGError { return .failure(.init(e.reason)) }
        catch { return .failure(.init("unknown")) }
    }

    /// Applies a patch and recompiles. `{"params": {...}}` only changes the defaults; `{"parts": {"id": {...}}}` merges
    /// fields into existing parts by id; `"constraints"` and `"steps"` replace those arrays. Part ids are stable, and
    /// parts whose shapes did not change keep their meshes.
    public static func applying(_ patch: MGJSON, to doc: MGSolidDocument) -> Result<MGSolidDocument, MGSolidIssue> {
        guard case .object(let p) = patch else { return .failure(.init("patch.object")) }
        let allowed: Set<String> = ["params", "parts", "constraints", "steps", "title"]
        guard Set(p.keys).isSubset(of: allowed), !p.isEmpty else {
            return .failure(.init("patch.unknown.\(Set(p.keys).subtracting(allowed).sorted().joined(separator: ","))"))
        }
        guard case .object(var src) = doc.source else { return .failure(.init("patch.source")) }
        for key in ["params", "constraints", "steps", "title"] { if let v = p[key] { src[key] = v } }
        if let parts = p["parts"] {
            guard case .object(let edits) = parts, case .array(var list)? = src["parts"] else { return .failure(.init("patch.parts")) }
            for (id, edit) in edits {
                guard case .object(let fields) = edit else { return .failure(.init("patch.parts.object", part: id)) }
                guard fields["id"] == nil else { return .failure(.init("patch.parts.id", part: id)) }
                guard let k = list.firstIndex(where: { $0["id"] == .string(id) }), case .object(var o) = list[k] else {
                    return .failure(.init("ref.unknown.\(id)"))
                }
                for (key, value) in fields { if value == .null { o.removeValue(forKey: key) } else { o[key] = value } }
                list[k] = .object(o)
            }
            src["parts"] = .array(list)
        }
        return document(json: .object(src), reusing: doc)
    }

    // MARK: Compile

    static let topKeys: Set<String> = ["v", "kind", "title", "units", "params", "parts", "constraints", "steps"]
    static let partKeys: Set<String> = ["id", "name", "shape", "material", "parent", "at", "rot", "joint", "drive", "explode",
                                        "explodeWindow", "repeat", "phase", "smooth"]

    struct RawPart {
        var id: String, name: String, shapes: [MGShapeSpec], material: MGMaterialPreset
        var parent: String?, placement: MGTransform, joint: MGJoint
        var drive: MGJSON?, explode: MGVec3, window: ClosedRange<Double>, phase: Double, crease: Double
        var base: String, instance: Int?
    }

    static func compile(_ json: MGJSON, _ previous: MGSolidDocument?) throws -> MGSolidDocument {
        guard case .object(let o) = json else { throw MGSolidIssue("assembly.object") }
        guard json.canonicalData.count <= MGSolidLimits.bytes else { throw MGSolidIssue("assembly.bytes") }
        try closed(o, ["v", "kind", "parts"], topKeys, "assembly")
        guard o["v"] == .number(1) else { throw MGSolidIssue("assembly.version") }
        guard o["kind"] == .string("assembly") else { throw MGSolidIssue("assembly.kind") }
        if let u = o["units"], u != .string("mm") { throw MGSolidIssue("assembly.units") }
        let title = try o["title"].map { try text($0, MGSolidLimits.title, "assembly.title") } ?? "Assembly"
        var defaults = MGPoseParameters()
        if let p = o["params"] {
            guard case .object(let po) = p else { throw MGSolidIssue("params") }
            try closed(po, [], ["input", "explode"], "params")
            if let v = po["input"] { defaults.input = try num(v, -1e6...1e6, "params.input") }
            if let v = po["explode"] { defaults.explode = try num(v, 0...1, "params.explode") }
        }
        guard case .array(let rawParts)? = o["parts"], (1...MGSolidLimits.parts).contains(rawParts.count) else { throw MGSolidIssue("parts.count") }

        // Parts, with `repeat` expansion.
        var parts: [RawPart] = []
        var repeated: [String: Int] = [:]
        var wireIDs = Set<String>()
        for entry in rawParts {
            let expanded = try part(entry)
            guard wireIDs.insert(expanded[0].base).inserted else { throw MGSolidIssue("id.duplicate.\(expanded[0].base)", part: expanded[0].base) }
            if expanded.count > 1 || expanded[0].instance != nil { repeated[expanded[0].base] = expanded.count }
            parts += expanded
        }
        guard parts.count <= MGSolidLimits.resolvedParts else { throw MGSolidIssue("parts.resolved") }
        var ids = Set<String>()
        for p in parts { guard ids.insert(p.id).inserted else { throw MGSolidIssue("id.duplicate.\(p.id)", part: p.id) } }
        // Resolve parents (a repeated child of a repeated parent pairs by instance).
        for i in parts.indices {
            guard let parent = parts[i].parent else { continue }
            if let count = repeated[parent] {
                guard let k = parts[i].instance, repeated[parts[i].base] == count else { throw MGSolidIssue("part.parent.repeat", part: parts[i].id) }
                parts[i].parent = parent + "\(k)"
            } else if !ids.contains(parent) || parent == parts[i].id {
                throw MGSolidIssue("ref.unknown.\(parent)", part: parts[i].id)
            }
        }
        func expand(_ id: String, _ what: String) throws -> [String] {
            if let c = repeated[id] { return (1...c).map { id + "\($0)" } }
            guard ids.contains(id) else { throw MGSolidIssue("ref.unknown.\(id)", part: nil) }
            return [id]
        }
        let byID = Dictionary(parts.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        // Gears.
        var gears: [String: MGSolidGear] = [:]
        for p in parts {
            if let s = p.shapes.first(where: { $0.kind == "gear" || $0.kind == "ringGear" }) {
                gears[p.id] = MGSolidGear(part: p.id, spur: s.spurGear, ring: s.ringGear, local: s.offset)
            }
        }

        // Constraints.
        struct Mesh { var a: String, b: String, carrier: String? }
        var meshes: [Mesh] = [], fixed: [String] = []
        if let c = o["constraints"] {
            guard case .array(let list) = c, list.count <= MGSolidLimits.constraints else { throw MGSolidIssue("constraints.count") }
            for entry in list {
                guard case .object(let co) = entry, co.count == 1, let (kind, body) = co.first else { throw MGSolidIssue("constraint.object") }
                switch kind {
                case "fixed":
                    guard case .string(let id) = body else { throw MGSolidIssue("constraint.fixed") }
                    fixed += try expand(id, "constraint.fixed")
                case "gearMesh":
                    guard case .object(let g) = body else { throw MGSolidIssue("constraint.gearMesh") }
                    try closed(g, ["a", "b"], ["a", "b", "carrier"], "constraint.gearMesh")
                    guard case .string(let a)? = g["a"], case .string(let b)? = g["b"] else { throw MGSolidIssue("constraint.gearMesh.ref") }
                    var carrier: String?
                    if let cv = g["carrier"] {
                        guard case .string(let cid) = cv, byID[cid] != nil else { throw MGSolidIssue("constraint.gearMesh.carrier") }
                        carrier = cid
                    }
                    let la = try expand(a, "constraint.gearMesh.a"), lb = try expand(b, "constraint.gearMesh.b")
                    let pairs: [(String, String)]
                    if la.count == lb.count { pairs = Array(zip(la, lb)) }
                    else if la.count == 1 { pairs = lb.map { (la[0], $0) } }
                    else if lb.count == 1 { pairs = la.map { ($0, lb[0]) } }
                    else { throw MGSolidIssue("constraint.gearMesh.repeat") }
                    for (x, y) in pairs { meshes.append(Mesh(a: x, b: y, carrier: carrier)) }
                default: throw MGSolidIssue("constraint.unknown.\(kind)")
                }
            }
        }

        // Rest pose (all joints 0, explode 0): frames used for mesh geometry checks.
        let restAssembly = MGAssembly(name: title, parts: parts.map {
            MGPart(id: $0.id, name: $0.name, mesh: MGMesh(), material: $0.material, placement: $0.placement, parent: $0.parent, joint: $0.joint)
        })
        let rest = restAssembly.pose(MGPoseParameters())
        func gearFrame(_ id: String) -> MGTransform { (rest.world[id] ?? .identity) * (gears[id]?.local ?? .identity) }
        func jointAxisWorld(_ id: String) -> MGVec3? {
            guard case .revolute(let axis)? = byID[id]?.joint else { return nil }
            return (rest.world[id] ?? .identity).applyVector(axis).normalized
        }

        // Explicit drives.
        var drives: [String: MGDrive] = [:]
        var inputs: [String: Double] = [:]
        for p in parts {
            guard let d = p.drive else { continue }
            guard p.joint != .fixed else { throw MGSolidIssue("part.drive.joint", part: p.id) }
            guard case .object(let dobj) = d, dobj.count == 1, let (kind, body) = dobj.first else { throw MGSolidIssue("part.drive", part: p.id) }
            switch kind {
            case "input":
                inputs[p.id] = try num(body, -1000...1000, "part.drive.input")
            case "follow":
                guard case .object(let f) = body else { throw MGSolidIssue("part.drive.follow", part: p.id) }
                try closed(f, ["source", "ratio"], ["source", "ratio"], "part.drive.follow")
                guard case .string(let s)? = f["source"], byID[s] != nil, s != p.id else { throw MGSolidIssue("ref.unknown.\(f["source"].map { "\($0)" } ?? "")", part: p.id) }
                drives[p.id] = .follow(source: s, ratio: try num(f["ratio"], -1000...1000, "part.drive.follow.ratio"), offset: 0)
            case "crankSlider", "crankRod":
                guard case .object(let f) = body else { throw MGSolidIssue("part.drive.\(kind)", part: p.id) }
                try closed(f, ["crank", "radius", "rod"], ["crank", "radius", "rod"], "part.drive.\(kind)")
                guard case .string(let s)? = f["crank"], byID[s] != nil, s != p.id else { throw MGSolidIssue("ref.unknown.crank", part: p.id) }
                let r = try num(f["radius"], MGSolidLimits.length, "part.drive.\(kind).radius")
                let l = try num(f["rod"], MGSolidLimits.length, "part.drive.\(kind).rod")
                guard l > r else { throw MGSolidIssue("part.drive.\(kind).rod", part: p.id) }
                if kind == "crankSlider" {
                    guard case .prismatic = p.joint else { throw MGSolidIssue("part.drive.crankSlider.joint", part: p.id) }
                    drives[p.id] = .crankSlider(crank: s, crankRadius: r, rodLength: l, offset: 0)
                } else {
                    drives[p.id] = .crankRod(crank: s, crankRadius: r, rodLength: l)
                }
            default: throw MGSolidIssue("part.drive.unknown.\(kind)", part: p.id)
            }
        }

        // Gear-mesh geometry checks and automatic tooth phasing.
        var meshAxis: [Int: MGVec3] = [:]
        for (k, m) in meshes.enumerated() {
            guard let ga = gears[m.a], let gb = gears[m.b] else { throw MGSolidIssue("constraint.gearMesh.gear", part: gears[m.a] == nil ? m.a : m.b) }
            guard m.a != m.b else { throw MGSolidIssue("constraint.gearMesh.self", part: m.a) }
            guard abs(ga.module - gb.module) < 1e-9 else { throw MGSolidIssue("constraint.gearMesh.module", part: m.b) }
            guard gb.spur != nil else { throw MGSolidIssue("constraint.gearMesh.kind", part: m.b) }
            guard jointAxisWorld(m.a) != nil || fixed.contains(m.a) || byID[m.a]?.joint == .fixed,
                  jointAxisWorld(m.b) != nil else { throw MGSolidIssue("constraint.gearMesh.joint", part: m.b) }
            for id in [m.a, m.b] {
                // A driven or phased gear turns about its own axis: the joint axis must pass through the gear centre.
                let g = gears[id]!.local
                var axis = g.c2
                if case .revolute(let a)? = byID[id]?.joint { axis = a.normalized }
                let off = g.translation - axis * axis.dot(g.translation)
                guard g.c2.cross(axis).length < 1e-6, off.length < 1e-6 else { throw MGSolidIssue("constraint.gearMesh.joint", part: id) }
            }
            let fa = gearFrame(m.a), fb = gearFrame(m.b)
            let n = fa.c2.normalized
            guard abs(abs(n.dot(fb.c2.normalized)) - 1) < 1e-6 else { throw MGSolidIssue("constraint.gearMesh.axis", part: m.b) }
            let delta = fb.translation - fa.translation
            let planar = delta - n * n.dot(delta)
            let expected = ga.ring != nil ? Double(ga.teeth - gb.teeth) * ga.module / 2 : Double(ga.teeth + gb.teeth) * ga.module / 2
            guard abs(planar.length - expected) <= 0.02 * ga.module else { throw MGSolidIssue("constraint.gearMesh.distance", part: m.b) }
            if let c = m.carrier {
                guard let ca = jointAxisWorld(c) ?? Optional(gearFrame(c).c2) , abs(abs(ca.dot(n)) - 1) < 1e-6 else { throw MGSolidIssue("constraint.gearMesh.carrier", part: c) }
                guard byID[m.b]?.parent == c || byID[m.a]?.parent == c else { throw MGSolidIssue("constraint.gearMesh.carrier", part: c) }
            }
            meshAxis[k] = n
        }
        // Tooth phase propagation over the mesh graph, starting from gears with an authored phase (default 0).
        var q0: [String: Double] = [:]
        func worldPhase(_ id: String, _ n: MGVec3, _ e1: MGVec3, _ e2: MGVec3) -> (phase: Double, sign: Double) {
            let f = gearFrame(id)
            let sign: Double = (jointAxisWorld(id) ?? f.c2).dot(n) >= 0 ? 1 : -1
            let x = f.c0
            return (atan2(x.dot(e2), x.dot(e1)) + sign * (q0[id] ?? 0), sign)
        }
        var order: [String] = []
        for m in meshes { for id in [m.a, m.b] where !order.contains(id) { order.append(id) } }
        var visited = Set<String>()
        for start in order where !visited.contains(start) {
            q0[start] = (byID[start]?.phase ?? 0)
            visited.insert(start)
            var queue = [start]
            while let cur = queue.first {
                queue.removeFirst()
                for (k, m) in meshes.enumerated() where m.a == cur || m.b == cur {
                    let other = m.a == cur ? m.b : m.a
                    let n = meshAxis[k]!
                    let helper = abs(n.x) < 0.9 ? MGVec3.unitX : MGVec3.unitY
                    let e1 = (helper - n * n.dot(helper)).normalized, e2 = n.cross(e1)
                    let ca = gearFrame(m.a).translation, cb = gearFrame(m.b).translation
                    let d = cb - ca
                    let beta = atan2(d.dot(e2), d.dot(e1))
                    let ga = gears[m.a]!, gb = gears[m.b]!
                    // Required world phase of `other`, given `cur`.
                    let required: Double
                    if ga.ring != nil {
                        if cur == m.a {
                            let pr = worldPhase(m.a, n, e1, e2).phase
                            required = beta + Double(ga.teeth) * (pr - beta) / Double(gb.teeth)
                        } else {
                            let pp = worldPhase(m.b, n, e1, e2).phase
                            required = MGGearPhase.ringSpaces(zRing: ga.teeth, zPlanet: gb.teeth, phasePlanet: pp, beta: beta)
                        }
                    } else if cur == m.a {
                        required = MGGearPhase.external(zA: ga.teeth, phaseA: worldPhase(m.a, n, e1, e2).phase, zB: gb.teeth, beta: beta)
                    } else {
                        required = MGGearPhase.external(zA: gb.teeth, phaseA: worldPhase(m.b, n, e1, e2).phase, zB: ga.teeth, beta: beta + .pi)
                    }
                    let pitch = 2 * Double.pi / Double(gears[other]!.teeth)
                    let (current, sign) = worldPhase(other, n, e1, e2)
                    if visited.contains(other) {
                        var diff = (required - current).truncatingRemainder(dividingBy: pitch)
                        if diff < 0 { diff += pitch }
                        guard min(diff, pitch - diff) < 1e-6 * pitch + 1e-9 else { throw MGSolidIssue("constraint.gearMesh.phase", part: other) }
                    } else {
                        q0[other] = (q0[other] ?? 0) + sign * (required - current)
                        visited.insert(other); queue.append(other)
                    }
                }
            }
        }

        // Linear velocity solve: inputs, fixed joints and mesh equations give d(q)/d(input) for every gear joint.
        var unknown: [String] = []
        func col(_ id: String) -> Int {
            if let i = unknown.firstIndex(of: id) { return i }
            unknown.append(id); return unknown.count - 1
        }
        var rows: [([Int: Double], Double)] = []
        for (id, scale) in inputs.sorted(by: { $0.key < $1.key }) { rows.append(([col(id): 1], scale)) }
        for id in fixed {
            guard byID[id]?.joint != .fixed else { continue }
            rows.append(([col(id): 1], 0))
        }
        for (k, m) in meshes.enumerated() {
            let n = meshAxis[k]!
            let ga = gears[m.a]!, gb = gears[m.b]!
            var row: [Int: Double] = [:]
            func addRel(_ id: String, _ coef: Double) {
                // Rotation about n relative to the carrier.
                if let s = jointAxisWorld(id).map({ $0.dot(n) >= 0 ? 1.0 : -1.0 }) { row[col(id), default: 0] += coef * s }
                if let c = m.carrier, byID[id]?.parent != c, let cs = jointAxisWorld(c).map({ $0.dot(n) >= 0 ? 1.0 : -1.0 }) {
                    row[col(c), default: 0] -= coef * cs
                }
            }
            let sign: Double = ga.ring != nil ? -1 : 1
            addRel(m.a, Double(ga.teeth)); addRel(m.b, sign * Double(gb.teeth))
            rows.append((row, 0))
        }
        var ratios: [String: Double] = [:]
        if !unknown.isEmpty {
            let solved = try solve(rows, columns: unknown.count)
            for (i, id) in unknown.enumerated() {
                guard let v = solved[i] else { throw MGSolidIssue("constraint.underdetermined", part: id) }
                ratios[id] = v
            }
        }
        for (id, r) in ratios {
            guard drives[id] == nil else { throw MGSolidIssue("constraint.conflict.drive", part: id) }
            drives[id] = .input(scale: r, offset: q0[id] ?? 0)
        }
        for (id, phase) in q0 where drives[id] == nil && phase != 0 {
            // Fixed gears keep their phase as a constant joint value.
            drives[id] = .input(scale: 0, offset: phase)
        }

        // Steps.
        var steps: [MGSolidStep] = []
        if let s = o["steps"] {
            guard case .array(let list) = s, list.count <= MGSolidLimits.steps else { throw MGSolidIssue("steps.count") }
            for entry in list { steps.append(try step(entry, expand)) }
        }

        // Meshes (reused when the shape list is unchanged).
        var assemblyParts: [MGPart] = []
        var shapes: [String: [MGShapeSpec]] = [:]
        for p in parts {
            shapes[p.id] = p.shapes
            let mesh: MGMesh
            if let prev = previous, prev.shapes[p.id] == p.shapes, let old = prev.assembly.part(p.id) { mesh = old.mesh }
            else { mesh = MGMesh.merged(p.shapes.map { $0.mesh() }) }
            var joint = p.joint, drive = drives[p.id]
            if joint == .fixed, let d = drive, case .input(0, let offset) = d {
                // A fixed gear's phase becomes a placement rotation about its gear axis.
                joint = .revolute(axis: gears[p.id]?.local.c2 ?? .unitZ); drive = .input(scale: 0, offset: offset)
            }
            assemblyParts.append(MGPart(id: p.id, name: p.name, mesh: mesh, material: p.material, placement: p.placement, parent: p.parent,
                                        joint: joint, drive: drive, explode: p.explode, explodeWindow: p.window, creaseAngle: p.crease))
        }
        let pairs = meshes.map { m in
            MGGearPair(a: m.a, b: m.b, teethA: gears[m.a]!.teeth, teethB: gears[m.b]!.teeth, isInternal: gears[m.a]!.ring != nil, carrier: m.carrier)
        }
        let assembly = MGAssembly(name: title, parts: assemblyParts, gearPairs: pairs)
        if let issue = assembly.validate().first { throw MGSolidIssue("assembly.\(issue)") }
        return MGSolidDocument(title: title, assembly: assembly, steps: steps, defaults: defaults, gears: gears, shapes: shapes,
                               ratios: ratios, source: json)
    }

    /// Gauss-Jordan elimination with partial pivoting on a (possibly redundant) linear system. Returns nil entries for
    /// free unknowns; throws on inconsistent rows.
    static func solve(_ rows: [([Int: Double], Double)], columns n: Int) throws -> [Double?] {
        var a = rows.map { r -> [Double] in
            var line = [Double](repeating: 0, count: n + 1)
            for (c, v) in r.0 { line[c] += v }
            line[n] = r.1
            return line
        }
        var pivotOf = [Int?](repeating: nil, count: n)
        var row = 0
        for c in 0..<n where row < a.count {
            guard let p = (row..<a.count).max(by: { abs(a[$0][c]) < abs(a[$1][c]) }), abs(a[p][c]) > 1e-9 else { continue }
            a.swapAt(row, p)
            let pv = a[row][c]
            for k in 0...n { a[row][k] /= pv }
            for r in 0..<a.count where r != row && abs(a[r][c]) > 0 {
                let f = a[r][c]
                for k in 0...n { a[r][k] -= f * a[row][k] }
            }
            pivotOf[c] = row; row += 1
        }
        for r in row..<a.count where abs(a[r][n]) > 1e-7 { throw MGSolidIssue("constraint.conflict") }
        return (0..<n).map { c in
            guard let r = pivotOf[c] else { return nil }
            // Pivot rows that still depend on a free unknown are underdetermined too.
            for k in 0..<n where k != c && pivotOf[k] == nil && abs(a[r][k]) > 1e-9 { return nil }
            return a[r][n]
        }
    }

    // MARK: Parts

    static func part(_ entry: MGJSON) throws -> [RawPart] {
        guard case .object(let o) = entry else { throw MGSolidIssue("part.object") }
        let pid: String
        do { pid = try MGParser.identifier(o["id"] ?? .null, "part.id") } catch { throw MGSolidIssue("part.id") }
        func fail(_ r: String) -> MGSolidIssue { MGSolidIssue(r, part: pid) }
        do {
            try closed(o, ["id", "shape"], partKeys, "part")
            let name = try o["name"].map { try text($0, MGSolidLimits.name, "part.name") } ?? pid
            var shapeList: [MGJSON]
            switch o["shape"] {
            case .array(let l)?: shapeList = l
            case let s?: shapeList = [s]
            case nil: shapeList = []
            }
            guard (1...MGSolidLimits.shapesPerPart).contains(shapeList.count) else { throw MGSolidIssue("part.shape.count") }
            let shapes = try shapeList.map(shape)
            guard shapes.filter({ $0.kind == "gear" || $0.kind == "ringGear" }).count <= 1 else { throw MGSolidIssue("part.shape.gears") }
            let material = try materialPreset(o["material"] ?? .string("brushedSteel"))
            var parent: String?
            if let p = o["parent"] { parent = try MGParser.identifier(p, "part.parent") }
            let placement = try transform(o["at"], o["rot"], "part")
            var joint = MGJoint.fixed
            if let j = o["joint"] {
                guard case .object(let jo) = j, jo.count == 1, let (k, v) = jo.first else { throw MGSolidIssue("part.joint") }
                let axis = try vector(v, "joint.axis")
                guard axis.length > 1e-9 else { throw MGSolidIssue("joint.axis") }
                switch k {
                case "revolute": joint = .revolute(axis: axis.normalized)
                case "prismatic": joint = .prismatic(axis: axis.normalized)
                default: throw MGSolidIssue("part.joint.unknown.\(k)")
                }
            }
            let explode = try o["explode"].map { try vector($0, "part.explode") } ?? .zero
            var window: ClosedRange<Double> = 0...1
            if let w = o["explodeWindow"] {
                guard case .array(let a) = w, a.count == 2 else { throw MGSolidIssue("part.explodeWindow") }
                let lo = try num(a[0], 0...1, "part.explodeWindow"), hi = try num(a[1], 0...1, "part.explodeWindow")
                guard hi > lo else { throw MGSolidIssue("part.explodeWindow") }
                window = lo...hi
            }
            let phase = try o["phase"].map { try num($0, -360...360, "part.phase") * .pi / 180 } ?? 0
            let crease = try o["smooth"].map { try num($0, 0...180, "part.smooth") * .pi / 180 } ?? 0.6
            let raw = RawPart(id: pid, name: name, shapes: shapes, material: material, parent: parent, placement: placement, joint: joint,
                              drive: o["drive"], explode: explode, window: window, phase: phase, crease: crease, base: pid, instance: nil)
            guard let r = o["repeat"] else { return [raw] }
            guard case .object(let ro) = r else { throw MGSolidIssue("part.repeat") }
            try closed(ro, ["count"], ["count", "axis", "angle"], "part.repeat")
            let countValue = try num(ro["count"], 2...Double(MGSolidLimits.repeatCount), "part.repeat.count")
            guard countValue.rounded() == countValue else { throw MGSolidIssue("part.repeat.count") }
            let count = Int(countValue)
            let axis = try ro["axis"].map { try vector($0, "part.repeat.axis") } ?? .unitZ
            guard axis.length > 1e-9 else { throw MGSolidIssue("part.repeat.axis") }
            let total = try ro["angle"].map { try num($0, -360...360, "part.repeat.angle") } ?? 360
            let step = total == 360 || total == -360 ? total / Double(count) : total / Double(max(1, count - 1))
            return (0..<count).map { k in
                var c = raw
                c.id = pid + "\(k + 1)"; c.instance = k + 1
                c.placement = .rotation(axis: axis, angle: step * Double(k) * .pi / 180) * placement
                return c
            }
        } catch let e as MGSolidIssue {
            throw e.part == nil ? fail(e.reason) : e
        } catch let e as MGError {
            throw fail(e.reason)
        }
    }

    static let shapeKeys: [String: (required: Set<String>, optional: Set<String>)] = [
        "gear": (["teeth", "module", "width"], ["bore", "keyway", "z0", "pressureAngle", "chamfer", "backlash"]),
        "ringGear": (["teeth", "module", "width", "outer"], ["z0", "pressureAngle", "chamfer", "backlash"]),
        "shaft": (["radius", "length"], ["z0", "chamfer"]),
        "tube": (["inner", "outer", "length"], ["z0", "chamfer"]),
        "box": (["size"], ["chamfer"]),
        "hex": (["acrossFlats", "length"], ["z0", "chamfer"]),
        "plate": (["radius", "thickness"], ["z0", "chamfer", "holes"]),
        "carrier": (["arms", "radius", "hub", "boss", "armWidth", "thickness"], ["z0", "chamfer", "blend"]),
        "extrudedProfile": (["points", "depth"], ["holes", "z0", "chamfer"]),
        "revolvedProfile": (["points"], ["closed"]),
        "blade": (["span", "chord"], ["thickness", "twist", "root", "tipChord", "camber", "camberPosition"]),
    ]

    static func shape(_ entry: MGJSON) throws -> MGShapeSpec {
        guard case .object(let wrapper) = entry, wrapper.count == 1, let (kind, body) = wrapper.first else { throw MGSolidIssue("part.shape") }
        guard let keys = shapeKeys[kind] else { throw MGSolidIssue("part.shape.unknown.\(kind)") }
        guard case .object(var f) = body else { throw MGSolidIssue("part.\(kind)") }
        let w = "part.\(kind)"
        try closed(f, keys.required, keys.optional.union(["at", "rot"]), w)
        let offset = try transform(f["at"], f["rot"], w)
        f.removeValue(forKey: "at"); f.removeValue(forKey: "rot")
        let L = MGSolidLimits.length
        func n(_ k: String, _ range: ClosedRange<Double> = MGSolidLimits.length) throws -> Double {
            try num(f[k], range, "\(w).\(k)")
        }
        func opt(_ k: String, _ range: ClosedRange<Double>) throws -> Double? { f[k] == nil ? nil : try n(k, range) }
        func integer(_ k: String, _ range: ClosedRange<Double>) throws -> Int {
            let v = try n(k, range)
            guard v.rounded() == v else { throw MGSolidIssue("\(w).\(k)") }
            return Int(v)
        }
        _ = try opt("z0", MGSolidLimits.coordinate)
        _ = try opt("chamfer", 0...50)
        switch kind {
        case "gear":
            let z = try integer("teeth", MGSolidLimits.teeth)
            let m = try n("module", MGSolidLimits.module)
            let width = try n("width")
            _ = try opt("pressureAngle", 14.5...25); _ = try opt("backlash", 0...0.3)
            let g = MGSpurGear(teeth: z, module: m)
            let bore = try opt("bore", 0...4000) ?? 0
            guard bore < g.rootRadius - 0.5 * m else { throw MGSolidIssue("\(w).bore") }
            if let k = f["keyway"] {
                guard case .array(let a) = k, a.count == 2 else { throw MGSolidIssue("\(w).keyway") }
                let kw = try num(a[0], 0.1...1000, "\(w).keyway"), kd = try num(a[1], 0.1...1000, "\(w).keyway")
                guard bore > 0, kw < bore, bore + kd < g.rootRadius - 0.3 * m else { throw MGSolidIssue("\(w).keyway") }
            }
            if let c = try opt("chamfer", 0...50) { guard c < min(width / 2, 0.45 * m) else { throw MGSolidIssue("\(w).chamfer") } }
        case "ringGear":
            let z = try integer("teeth", MGSolidLimits.ringTeeth)
            let m = try n("module", MGSolidLimits.module)
            let width = try n("width")
            _ = try opt("pressureAngle", 14.5...25); _ = try opt("backlash", 0...0.3)
            let g = MGRingGear(teeth: z, module: m, outerRadius: 0)
            let outer = try n("outer")
            guard outer >= g.rootRadius + m else { throw MGSolidIssue("\(w).outer") }
            guard g.tipRadius > g.baseRadius else { throw MGSolidIssue("\(w).teeth") }
            if let c = try opt("chamfer", 0...50) { guard c < min(width / 2, 0.45 * m) else { throw MGSolidIssue("\(w).chamfer") } }
        case "shaft":
            let r = try n("radius"), len = try n("length")
            if let c = try opt("chamfer", 0...50) { guard c < min(r, len / 2) else { throw MGSolidIssue("\(w).chamfer") } }
        case "tube":
            let i = try n("inner"), o = try n("outer"), len = try n("length")
            guard o > i else { throw MGSolidIssue("\(w).outer") }
            if let c = try opt("chamfer", 0...50) { guard c < min((o - i) / 3, len / 2) else { throw MGSolidIssue("\(w).chamfer") } }
        case "box":
            let s = try vector(f["size"] ?? .null, "\(w).size")
            guard [s.x, s.y, s.z].allSatisfy({ L.contains($0) }) else { throw MGSolidIssue("\(w).size") }
            if let c = try opt("chamfer", 0...50) { guard c < min(s.x, s.y, s.z) / 2 else { throw MGSolidIssue("\(w).chamfer") } }
        case "hex":
            let a = try n("acrossFlats"), len = try n("length")
            if let c = try opt("chamfer", 0...50) { guard c < min(a / 4, len / 2) else { throw MGSolidIssue("\(w).chamfer") } }
        case "plate":
            let r = try n("radius"), t = try n("thickness")
            let ch = try opt("chamfer", 0...50) ?? 0
            guard ch < min(r / 4, t / 2) else { throw MGSolidIssue("\(w).chamfer") }
            if let h = f["holes"] {
                guard case .array(let list) = h, list.count <= MGSolidLimits.plateHoles else { throw MGSolidIssue("\(w).holes") }
                var circles: [(MGVec2, Double)] = []
                for e in list {
                    guard case .array(let v) = e, v.count == 3 else { throw MGSolidIssue("\(w).holes") }
                    let x = try num(v[0], MGSolidLimits.coordinate, "\(w).holes"), y = try num(v[1], MGSolidLimits.coordinate, "\(w).holes")
                    let hr = try num(v[2], L, "\(w).holes")
                    let c = MGVec2(x, y)
                    // Chamfers grow holes and shrink the rim, so keep a wall of at least 0.5 mm after both.
                    guard c.length + hr + 2 * ch + 0.5 < r else { throw MGSolidIssue("\(w).holes.outside") }
                    guard !circles.contains(where: { ($0.0 - c).length < $0.1 + hr + 2 * ch + 0.5 }) else { throw MGSolidIssue("\(w).holes.overlap") }
                    circles.append((c, hr))
                }
            }
        case "carrier":
            _ = try integer("arms", 1...8)
            let r = try n("radius"), hub = try n("hub"), boss = try n("boss"), aw = try n("armWidth"), t = try n("thickness")
            _ = try opt("blend", 0.1...1000)
            guard aw / 2 < boss, hub < r + boss else { throw MGSolidIssue("\(w).armWidth") }
            if let c = try opt("chamfer", 0...50) { guard c < min(t / 2, aw / 4) else { throw MGSolidIssue("\(w).chamfer") } }
        case "extrudedProfile":
            let outer = try pointList(f["points"], 3, "\(w).points")
            let depth = try n("depth")
            var holes: [[MGVec2]] = []
            if let h = f["holes"] {
                guard case .array(let list) = h, list.count <= MGSolidLimits.profileHoles else { throw MGSolidIssue("\(w).holes") }
                holes = try list.map { try pointList($0, 3, "\(w).holes") }
            }
            guard abs(MGProfile.signedArea(outer)) > 1e-6, !selfIntersects(outer) else { throw MGSolidIssue("\(w).points") }
            for h in holes {
                guard abs(MGProfile.signedArea(h)) > 1e-6, !selfIntersects(h), h.allSatisfy({ inside($0, outer) }),
                      !loopsCross(h, outer) else { throw MGSolidIssue("\(w).holes") }
            }
            for i in holes.indices { for j in holes.indices where j > i {
                guard !loopsCross(holes[i], holes[j]), !inside(holes[i][0], holes[j]), !inside(holes[j][0], holes[i]) else { throw MGSolidIssue("\(w).holes.overlap") }
            } }
            if let c = try opt("chamfer", 0...50), c > 0 {
                guard c < depth / 2 else { throw MGSolidIssue("\(w).chamfer") }
                // The chamfered caps use inset loops; they must stay simple and separate too.
                let p = MGProfile(outer: outer, holes: holes)
                let io = MGProfile.inset(p.outer, by: c), ih = p.holes.map { MGProfile.inset($0, by: c) }
                guard !selfIntersects(io), MGProfile.signedArea(io) > 0 else { throw MGSolidIssue("\(w).chamfer") }
                for h in ih { guard !selfIntersects(h), !loopsCross(h, io), inside(h[0], io) else { throw MGSolidIssue("\(w).chamfer") } }
            }
        case "revolvedProfile":
            let pts = try pointList(f["points"], 2, "\(w).points")
            guard pts.allSatisfy({ $0.x >= 0 }) else { throw MGSolidIssue("\(w).points.radius") }
            var closedLoop = false
            if let c = f["closed"] { guard case .bool(let b) = c else { throw MGSolidIssue("\(w).closed") }; closedLoop = b }
            if closedLoop {
                guard pts.count >= 3, pts.allSatisfy({ $0.x > 1e-6 }), abs(MGProfile.signedArea(pts)) > 1e-6, !selfIntersects(pts) else { throw MGSolidIssue("\(w).points") }
            } else {
                guard pts.count >= 3, pts.first!.x == 0, pts.last!.x == 0 else { throw MGSolidIssue("\(w).axis") }
                guard pts.dropFirst().dropLast().allSatisfy({ $0.x > 1e-6 }), abs(MGProfile.signedArea(pts)) > 1e-6, !selfIntersects(pts) else { throw MGSolidIssue("\(w).points") }
            }
        case "blade":
            _ = try n("span"); let chord = try n("chord")
            _ = try opt("thickness", 0.02...0.4); _ = try opt("twist", -80...80); _ = try opt("root", 0...4000)
            _ = try opt("tipChord", 0.05...4000)
            _ = try opt("camber", 0...0.09); _ = try opt("camberPosition", 0.1...0.9)
            _ = chord
        default: break
        }
        return MGShapeSpec(kind: kind, fields: f, offset: offset)
    }

    static func pointList(_ v: MGJSON?, _ minCount: Int, _ what: String) throws -> [MGVec2] {
        guard case .array(let a)? = v, (minCount...MGSolidLimits.profilePoints).contains(a.count) else { throw MGSolidIssue(what) }
        return try a.map { p in
            guard case .array(let xy) = p, xy.count == 2 else { throw MGSolidIssue(what) }
            return MGVec2(try num(xy[0], MGSolidLimits.coordinate, what), try num(xy[1], MGSolidLimits.coordinate, what))
        }
    }

    static func segmentsCross(_ a: MGVec2, _ b: MGVec2, _ c: MGVec2, _ d: MGVec2) -> Bool {
        let d1 = (b - a).cross(c - a), d2 = (b - a).cross(d - a), d3 = (d - c).cross(a - c), d4 = (d - c).cross(b - c)
        return d1 * d2 < 0 && d3 * d4 < 0
    }
    static func selfIntersects(_ loop: [MGVec2]) -> Bool {
        let n = loop.count
        for i in 0..<n { for j in (i + 2)..<max(i + 2, n) where !(i == 0 && j == n - 1) {
            if segmentsCross(loop[i], loop[(i + 1) % n], loop[j], loop[(j + 1) % n]) { return true }
        } }
        return false
    }
    static func loopsCross(_ p: [MGVec2], _ q: [MGVec2]) -> Bool {
        for i in p.indices { for j in q.indices {
            if segmentsCross(p[i], p[(i + 1) % p.count], q[j], q[(j + 1) % q.count]) { return true }
        } }
        return false
    }
    static func inside(_ p: MGVec2, _ loop: [MGVec2]) -> Bool {
        var c = false
        var j = loop.count - 1
        for i in loop.indices {
            let a = loop[i], b = loop[j]
            if (a.y > p.y) != (b.y > p.y), p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x { c.toggle() }
            j = i
        }
        return c
    }

    static func materialPreset(_ v: MGJSON) throws -> MGMaterialPreset {
        guard case .string(let s) = v else { throw MGSolidIssue("part.material") }
        let simple: [String: MGMaterialPreset] = ["brushedSteel": .brushedSteel, "polishedSteel": .polishedSteel, "darkSteel": .darkSteel,
                                                  "blackOxide": .blackOxide, "brass": .brass, "bronze": .bronze, "aluminum": .aluminum,
                                                  "rubber": .rubber, "glass": .glass]
        if let m = simple[s] { return m }
        let parts = s.split(separator: ".", maxSplits: 1).map(String.init)
        if parts.count == 2, let role = MGColorRole(rawValue: parts[1]) {
            if parts[0] == "anodized" { return .anodized(role) }
            if parts[0] == "plastic" { return .plastic(role) }
        }
        throw MGSolidIssue("part.material")
    }

    static func step(_ entry: MGJSON, _ expand: (String, String) throws -> [String]) throws -> MGSolidStep {
        guard case .object(let o) = entry else { throw MGSolidIssue("step.object") }
        try closed(o, ["say"], ["say", "focus", "highlight", "explode", "camera", "orbit", "spin"], "step")
        func ids(_ key: String) throws -> [String] {
            guard let v = o[key] else { return [] }
            guard case .array(let list) = v, list.count <= MGSolidLimits.idsPerStep else { throw MGSolidIssue("step.\(key)") }
            return try list.flatMap { e -> [String] in
                guard case .string(let id) = e else { throw MGSolidIssue("step.\(key)") }
                return try expand(id, "step.\(key)")
            }
        }
        var camera: String?
        if let c = o["camera"] {
            guard case .string(let s) = c, MGSolidCamera.presets[s] != nil else { throw MGSolidIssue("step.camera") }
            camera = s
        }
        return MGSolidStep(say: try text(o["say"] ?? .null, MGSolidLimits.say, "step.say"), focus: try ids("focus"), highlight: try ids("highlight"),
                           explode: try o["explode"].map { try num($0, 0...1, "step.explode") }, camera: camera,
                           orbit: try o["orbit"].map { try num($0, -360...360, "step.orbit") } ?? 0,
                           spin: try o["spin"].map { try num($0, -20...20, "step.spin") } ?? 0)
    }

    // MARK: Helpers

    static func closed(_ o: [String: MGJSON], _ required: Set<String>, _ optional: Set<String>, _ what: String) throws {
        do { try MGParser.closed(o, required: required, optional: optional, what) } catch let e as MGError { throw MGSolidIssue(e.reason) }
    }
    static func num(_ v: MGJSON?, _ range: ClosedRange<Double>, _ what: String) throws -> Double {
        guard case .number(let d)? = v, d.isFinite, range.contains(d) else { throw MGSolidIssue(what) }
        return d
    }
    static func vector(_ v: MGJSON, _ what: String) throws -> MGVec3 {
        guard case .array(let a) = v, a.count == 3 else { throw MGSolidIssue(what) }
        return MGVec3(try num(a[0], MGSolidLimits.coordinate, what), try num(a[1], MGSolidLimits.coordinate, what), try num(a[2], MGSolidLimits.coordinate, what))
    }
    /// `at`: [x, y, z]; `rot`: [axisX, axisY, axisZ, degrees].
    static func transform(_ at: MGJSON?, _ rot: MGJSON?, _ what: String) throws -> MGTransform {
        var t = MGTransform.identity
        if let r = rot {
            guard case .array(let a) = r, a.count == 4 else { throw MGSolidIssue("\(what).rot") }
            let axis = MGVec3(try num(a[0], -1e3...1e3, "\(what).rot"), try num(a[1], -1e3...1e3, "\(what).rot"), try num(a[2], -1e3...1e3, "\(what).rot"))
            guard axis.length > 1e-9 else { throw MGSolidIssue("\(what).rot") }
            t = .rotation(axis: axis, angle: try num(a[3], -360...360, "\(what).rot") * .pi / 180)
        }
        if let p = at { t = .translation(try vector(p, "\(what).at")) * t }
        return t
    }
    static func text(_ v: MGJSON, _ max: Int, _ what: String) throws -> String {
        guard case .string(let s) = v else { throw MGSolidIssue(what) }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, s.unicodeScalars.count <= max, !s.contains("<"), !s.contains(">"), !s.contains("://"),
              !s.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw MGSolidIssue(what) }
        return t
    }
}
