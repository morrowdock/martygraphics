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
    /// Total mesh size over every resolved part (after `repeat`), counted before any mesh is built. At the limit the
    /// kernel meshes (about 36 MB), the render meshes built while loading (about 90 MB) and the SceneKit buffers
    /// (about 80 MB) typically take about 200 MB (peaks can reach about twice that while normals are built), which recent iPhones and iPads can hold; the planetary example uses under 4%.
    public static let triangles = 1_500_000, vertices = 1_000_000
    /// Largest solved joint ratio (joint radians or mm per input radian).
    public static let ratio = 1000.0
    /// Largest tooth overlap, in modules, that an internal gear pair may show over its mesh sweep.
    public static let toothOverlap = 0.01
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
            return .failure(.init("patch.unknown.\(Set(p.keys).subtracting(allowed).map(token).sorted().joined(separator: ","))"))
        }
        guard case .object(var src) = doc.source else { return .failure(.init("patch.source")) }
        for key in ["params", "constraints", "steps", "title"] { if let v = p[key] { src[key] = v } }
        if let parts = p["parts"] {
            guard case .object(let edits) = parts, case .array(var list)? = src["parts"] else { return .failure(.init("patch.parts")) }
            for (id, edit) in edits.sorted(by: { $0.key < $1.key }) {
                guard case .object(let fields) = edit else { return .failure(.init("patch.parts.object", part: token(id))) }
                guard fields["id"] == nil else { return .failure(.init("patch.parts.id", part: token(id))) }
                guard let k = list.firstIndex(where: { $0["id"] == .string(id) }), case .object(var o) = list[k] else {
                    return .failure(.init("ref.unknown.\(token(id))"))
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
        // Mesh budget over every resolved part, counted from the validated fields before any mesh is built.
        var triangles = 0, vertices = 0
        for p in parts { for s in p.shapes { let e = s.meshEstimate; triangles += e.triangles; vertices += e.vertices } }
        guard triangles <= MGSolidLimits.triangles, vertices <= MGSolidLimits.vertices else { throw MGSolidIssue("assembly.budget") }
        var ids = Set<String>()
        for p in parts { guard ids.insert(p.id).inserted else { throw MGSolidIssue("id.duplicate.\(p.id)", part: p.id) } }
        // Resolve parents (a repeated child of a repeated parent pairs by instance).
        for i in parts.indices {
            guard let parent = parts[i].parent else { continue }
            if let count = repeated[parent] {
                guard let k = parts[i].instance, repeated[parts[i].base] == count else { throw MGSolidIssue("part.parent.repeat", part: parts[i].id) }
                parts[i].parent = parent + "\(k)"
            } else if !ids.contains(parent) || parent == parts[i].id {
                throw MGSolidIssue("ref.unknown.\(token(parent))", part: parts[i].id)
            }
        }
        func expand(_ id: String, _ what: String) throws -> [String] {
            if let c = repeated[id] { return (1...c).map { id + "\($0)" } }
            guard ids.contains(id) else { throw MGSolidIssue("ref.unknown.\(token(id))", part: nil) }
            return [id]
        }
        let byID = Dictionary(parts.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        // Parent cycles, rejected here so every chain walk below ends.
        for p in parts {
            var seen: Set<String> = [p.id]
            var cur = p.parent
            while let c = cur {
                guard seen.insert(c).inserted else { throw MGSolidIssue("part.parent.cycle", part: p.id) }
                cur = byID[c]?.parent
            }
        }
        /// Parent chain of a part, nearest first.
        func ancestors(_ id: String) -> [String] {
            var out: [String] = []
            var cur = byID[id]?.parent
            while let c = cur { out.append(c); cur = byID[c]?.parent }
            return out
        }

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
                default: throw MGSolidIssue("constraint.unknown.\(token(kind))")
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
                guard case .string(let s)? = f["source"], s != p.id else { throw MGSolidIssue("part.drive.follow.source", part: p.id) }
                guard byID[s] != nil else { throw MGSolidIssue("ref.unknown.\(token(s))", part: p.id) }
                drives[p.id] = .follow(source: s, ratio: try num(f["ratio"], -1000...1000, "part.drive.follow.ratio"), offset: 0)
            case "crankSlider", "crankRod":
                guard case .object(let f) = body else { throw MGSolidIssue("part.drive.\(kind)", part: p.id) }
                try closed(f, ["crank", "radius", "rod"], ["crank", "radius", "rod"], "part.drive.\(kind)")
                guard case .string(let s)? = f["crank"], s != p.id else { throw MGSolidIssue("part.drive.\(kind).crank", part: p.id) }
                guard byID[s] != nil else { throw MGSolidIssue("ref.unknown.\(token(s))", part: p.id) }
                let r = try num(f["radius"], MGSolidLimits.length, "part.drive.\(kind).radius")
                let l = try num(f["rod"], MGSolidLimits.length, "part.drive.\(kind).rod")
                guard l > r else { throw MGSolidIssue("part.drive.\(kind).rod", part: p.id) }
                if kind == "crankSlider" {
                    guard case .prismatic = p.joint else { throw MGSolidIssue("part.drive.crankSlider.joint", part: p.id) }
                    drives[p.id] = .crankSlider(crank: s, crankRadius: r, rodLength: l, offset: 0)
                } else {
                    drives[p.id] = .crankRod(crank: s, crankRadius: r, rodLength: l)
                }
            default: throw MGSolidIssue("part.drive.unknown.\(token(kind))", part: p.id)
            }
        }

        // Gear-mesh geometry checks.
        func axisLine(_ id: String) -> (point: MGVec3, dir: MGVec3)? {
            guard let dir = jointAxisWorld(id) else { return nil }
            return ((rest.world[id] ?? .identity).translation, dir)
        }
        /// Signed joint terms that turn `id` about `n`, from `id` up its parent chain to (not including) `stop`.
        /// Every moving joint on the way must be a revolute parallel to `n` whose axis passes through `centre`,
        /// so the gear only spins: its centre stays put relative to `stop`.
        func turning(_ id: String, centre: MGVec3, n: MGVec3, stop: String?, own: String, owner: String) throws -> [(String, Double)] {
            var terms: [(String, Double)] = []
            for p in [id] + ancestors(id) {
                if p == stop { break }
                guard byID[p]?.joint != .fixed, !fixed.contains(p) else { continue }
                guard let line = axisLine(p) else { throw MGSolidIssue(p == id ? own : "constraint.gearMesh.parentMoves", part: owner) }
                let d = centre - line.point
                guard line.dir.cross(n).length < 1e-6, (d - line.dir * line.dir.dot(d)).length < 1e-6 else {
                    throw MGSolidIssue(p == id ? own : "constraint.gearMesh.parentRotates", part: owner)
                }
                if p != id, drives[p] != nil { throw MGSolidIssue("constraint.gearMesh.parentDrive", part: owner) }
                terms.append((p, line.dir.dot(n) >= 0 ? 1 : -1))
            }
            return terms
        }
        var meshAxis: [Int: MGVec3] = [:]
        var meshTerms: [Int: (a: [(String, Double)], b: [(String, Double)])] = [:]
        var interference: [String: Double] = [:]
        for (k, m) in meshes.enumerated() {
            guard let ga = gears[m.a], let gb = gears[m.b] else { throw MGSolidIssue("constraint.gearMesh.gear", part: gears[m.a] == nil ? m.a : m.b) }
            guard m.a != m.b else { throw MGSolidIssue("constraint.gearMesh.self", part: m.a) }
            guard abs(ga.module - gb.module) < 1e-9 else { throw MGSolidIssue("constraint.gearMesh.module", part: m.b) }
            guard let sb = gb.spur else { throw MGSolidIssue("constraint.gearMesh.kind", part: m.b) }
            let paA = ga.spur?.pressureAngle ?? ga.ring!.pressureAngle
            guard abs(paA - sb.pressureAngle) < 1e-9 else { throw MGSolidIssue("constraint.gearMesh.pressureAngle", part: m.b) }
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
            // How each gear turns: its own joint plus coaxial parents, relative to the carrier when there is one.
            let own = "constraint.gearMesh.joint"
            var ta: [(String, Double)], tb: [(String, Double)], bTurns: Bool
            if let c = m.carrier {
                let ca = jointAxisWorld(c) ?? gearFrame(c).c2.normalized
                guard abs(abs(ca.dot(n)) - 1) < 1e-6 else { throw MGSolidIssue("constraint.gearMesh.carrier", part: c) }
                let aUnder = ancestors(m.a).contains(c), bUnder = ancestors(m.b).contains(c)
                guard aUnder || bUnder else { throw MGSolidIssue("constraint.gearMesh.carrier", part: c) }
                let origin = (rest.world[c] ?? .identity).translation
                let tc = try turning(c, centre: origin, n: n, stop: nil, own: "constraint.gearMesh.carrier", owner: c)
                func relative(_ id: String, _ centre: MGVec3, _ under: Bool) throws -> (own: [(String, Double)], total: [(String, Double)]) {
                    if under { let t = try turning(id, centre: centre, n: n, stop: c, own: own, owner: id); return (t, t) }
                    // A gear outside a turning carrier must sit on the carrier axis, or its centre moves in the carrier frame.
                    let d = centre - origin
                    guard tc.isEmpty || (d - n * n.dot(d)).length < 1e-6 else { throw MGSolidIssue("constraint.gearMesh.carrier", part: id) }
                    let t = try turning(id, centre: centre, n: n, stop: nil, own: own, owner: id)
                    return (t, t + tc.map { ($0.0, -$0.1) })
                }
                let ra = try relative(m.a, fa.translation, aUnder), rb = try relative(m.b, fb.translation, bUnder)
                ta = ra.total; tb = rb.total; bTurns = !rb.own.isEmpty
            } else {
                ta = try turning(m.a, centre: fa.translation, n: n, stop: nil, own: own, owner: m.a)
                tb = try turning(m.b, centre: fb.translation, n: n, stop: nil, own: own, owner: m.b)
                bTurns = !tb.isEmpty
            }
            guard jointAxisWorld(m.b) != nil || bTurns else { throw MGSolidIssue(own, part: m.b) }
            do {
                // Sweep the real outlines over one pitch: internal pairs interfere when the ring has too few more teeth
                // than the planet, and external pairs with small pinions or low pressure angles undercut each other.
                let key = "\(ga.ring != nil ? "R" : "S"),\(ga.teeth),\(gb.teeth),\(ga.module),\(paA),\(ga.ring?.backlash ?? ga.spur?.backlash ?? 0),\(sb.backlash)"
                let worst = interference[key] ?? MGSolidChecks.pairInterference(ga, gb)
                interference[key] = worst
                guard worst <= MGSolidLimits.toothOverlap * ga.module else { throw MGSolidIssue("constraint.gearMesh.interference", part: m.b) }
            }
            meshAxis[k] = n
            meshTerms[k] = (ta, tb)
        }

        // Tooth phasing over the mesh graph, starting from gears with an authored phase (default 0). Every meshed gear
        // has a phase knob: an offset on its own revolute joint (which also turns its children, so phased descendants
        // are compensated), or for a gear without a joint a turn of its gear shape (children stay put).
        var knob: [String: Double] = [:]
        func knobAxis(_ id: String) -> MGVec3 { jointAxisWorld(id) ?? gearFrame(id).c2.normalized }
        func worldPhase(_ id: String, _ n: MGVec3, _ e1: MGVec3, _ e2: MGVec3) -> Double {
            let x = gearFrame(id).c0
            var a = atan2(x.dot(e2), x.dot(e1))
            for p in [id] + ancestors(id) where p == id || jointAxisWorld(p) != nil {
                if let v = knob[p] { a += (knobAxis(p).dot(n) >= 0 ? 1 : -1) * v }
            }
            return a
        }
        var visited = Set<String>()
        func turnKnob(_ id: String, by d: Double) {
            knob[id, default: 0] += d
            guard jointAxisWorld(id) != nil else { return }
            for y in visited.sorted() where y != id {
                let chain = ancestors(y)
                // Only a visited part with its own joint shields y; a jointless gear stores its phase in its shape.
                guard let k = chain.firstIndex(of: id),
                      !chain[..<k].contains(where: { visited.contains($0) && jointAxisWorld($0) != nil }) else { continue }
                knob[y, default: 0] -= (knobAxis(id).dot(knobAxis(y)) >= 0 ? 1 : -1) * d
            }
        }
        /// World tooth phase `b` needs to mesh with `a` (both in the basis e1, e2 about n).
        func requiredPhase(_ m: Mesh, from cur: String, _ phaseOf: (String) -> Double, _ e1: MGVec3, _ e2: MGVec3,
                           centres: (MGVec3, MGVec3)) -> Double {
            let d = centres.1 - centres.0
            let beta = atan2(d.dot(e2), d.dot(e1))
            let ga = gears[m.a]!, gb = gears[m.b]!
            if ga.ring != nil {
                if cur == m.a { return beta + Double(ga.teeth) * (phaseOf(m.a) - beta) / Double(gb.teeth) }
                return MGGearPhase.ringSpaces(zRing: ga.teeth, zPlanet: gb.teeth, phasePlanet: phaseOf(m.b), beta: beta)
            }
            if cur == m.a { return MGGearPhase.external(zA: ga.teeth, phaseA: phaseOf(m.a), zB: gb.teeth, beta: beta) }
            return MGGearPhase.external(zA: gb.teeth, phaseA: phaseOf(m.b), zB: ga.teeth, beta: beta + .pi)
        }
        func basis(_ n: MGVec3) -> (MGVec3, MGVec3) {
            let helper = abs(n.x) < 0.9 ? MGVec3.unitX : MGVec3.unitY
            let e1 = (helper - n * n.dot(helper)).normalized
            return (e1, n.cross(e1))
        }
        func pitchOffset(_ required: Double, _ current: Double, _ teeth: Int) -> Double {
            let pitch = 2 * Double.pi / Double(teeth)
            var diff = (required - current).truncatingRemainder(dividingBy: pitch)
            if diff < 0 { diff += pitch }
            return min(diff, pitch - diff) / pitch
        }
        var order: [String] = []
        for m in meshes { for id in [m.a, m.b] where !order.contains(id) { order.append(id) } }
        for start in order where !visited.contains(start) {
            turnKnob(start, by: byID[start]?.phase ?? 0)
            visited.insert(start)
            var queue = [start]
            while !queue.isEmpty {
                let cur = queue.removeFirst()
                for (k, m) in meshes.enumerated() where m.a == cur || m.b == cur {
                    let other = m.a == cur ? m.b : m.a
                    let n = meshAxis[k]!
                    let (e1, e2) = basis(n)
                    let required = requiredPhase(m, from: cur, { worldPhase($0, n, e1, e2) }, e1, e2,
                                                 centres: (gearFrame(m.a).translation, gearFrame(m.b).translation))
                    let current = worldPhase(other, n, e1, e2)
                    if visited.contains(other) {
                        guard pitchOffset(required, current, gears[other]!.teeth) < 1e-6 else { throw MGSolidIssue("constraint.gearMesh.phase", part: other) }
                    } else {
                        turnKnob(other, by: (knobAxis(other).dot(n) >= 0 ? 1 : -1) * (required - current))
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
            let ga = gears[m.a]!, gb = gears[m.b]!
            let sign: Double = ga.ring != nil ? -1 : 1
            var row: [Int: Double] = [:]
            for (id, s) in meshTerms[k]!.a { row[col(id), default: 0] += Double(ga.teeth) * s }
            for (id, s) in meshTerms[k]!.b { row[col(id), default: 0] += sign * Double(gb.teeth) * s }
            rows.append((row, 0))
        }
        var ratios: [String: Double] = [:]
        if !unknown.isEmpty {
            let solved = try solve(rows, columns: unknown.count)
            for (i, id) in unknown.enumerated() {
                guard let v = solved[i] else { throw MGSolidIssue("constraint.underdetermined", part: id) }
                guard abs(v) <= MGSolidLimits.ratio else { throw MGSolidIssue("constraint.ratio", part: id) }
                ratios[id] = v
            }
        }
        for id in unknown {
            guard drives[id] == nil else { throw MGSolidIssue("constraint.conflict.drive", part: id) }
            drives[id] = .input(scale: ratios[id]!, offset: knob[id] ?? 0)
        }
        for (id, phase) in knob.sorted(by: { $0.key < $1.key }) where drives[id] == nil && phase != 0 && jointAxisWorld(id) != nil {
            drives[id] = .input(scale: 0, offset: phase)
        }

        // Steps.
        var steps: [MGSolidStep] = []
        if let s = o["steps"] {
            guard case .array(let list) = s, list.count <= MGSolidLimits.steps else { throw MGSolidIssue("steps.count") }
            for entry in list { steps.append(try step(entry, expand)) }
        }

        // Meshes (reused when the shape list is unchanged). A gear without a joint keeps its tooth phase in its shape.
        var assemblyParts: [MGPart] = []
        var shapes: [String: [MGShapeSpec]] = [:]
        for p in parts {
            var list = p.shapes
            if p.joint == .fixed, let phase = knob[p.id], phase != 0,
               let i = list.firstIndex(where: { $0.kind == "gear" || $0.kind == "ringGear" }) {
                let s = list[i]
                list[i] = MGShapeSpec(kind: s.kind, fields: s.fields, offset: s.offset * .rotation(axis: .unitZ, angle: phase))
                gears[p.id]?.local = list[i].offset
            }
            shapes[p.id] = list
            let mesh: MGMesh
            if let prev = previous, prev.shapes[p.id] == list, let old = prev.assembly.part(p.id) { mesh = old.mesh }
            else { mesh = MGMesh.merged(list.map { $0.mesh() }) }
            assemblyParts.append(MGPart(id: p.id, name: p.name, mesh: mesh, material: p.material, placement: p.placement, parent: p.parent,
                                        joint: p.joint, drive: drives[p.id], explode: p.explode, explodeWindow: p.window, creaseAngle: p.crease))
        }
        let pairs = meshes.enumerated().map { k, m in
            MGGearPair(a: m.a, b: m.b, teethA: gears[m.a]!.teeth, teethB: gears[m.b]!.teeth, isInternal: gears[m.a]!.ring != nil,
                       carrier: m.carrier, axis: meshAxis[k])
        }
        let assembly = MGAssembly(name: title, parts: assemblyParts, gearPairs: pairs)
        if let issue = assembly.validate().first { throw MGSolidIssue(issue == "drive cycle" ? "part.drive.cycle" : "assembly.invalid") }

        // The compiled motion must match what the solver assumed: replay the posed assembly and check every mesh keeps
        // its axis, centre distance, tooth phase and tooth ratio.
        let scale = max(1, ratios.values.map(abs).max() ?? 1, inputs.values.map(abs).max() ?? 1)
        let delta = 0.05 / scale
        let samples = [0, delta, 7.3 * delta, 29 * delta, 1.7]
        let worlds = samples.map { assembly.pose(MGPoseParameters(input: $0)).world }
        for (k, m) in meshes.enumerated() {
            let ga = gears[m.a]!, gb = gears[m.b]!
            let n0 = meshAxis[k]!
            func frame(_ w: [String: MGTransform], _ id: String) -> MGTransform { (w[id] ?? .identity) * gears[id]!.local }
            for w in worlds {
                let fa = frame(w, m.a), fb = frame(w, m.b)
                let n = fa.c2.normalized
                let d = fb.translation - fa.translation
                let expected = ga.ring != nil ? Double(ga.teeth - gb.teeth) * ga.module / 2 : Double(ga.teeth + gb.teeth) * ga.module / 2
                guard abs(abs(n.dot(fb.c2.normalized)) - 1) < 1e-6, abs((d - n * n.dot(d)).length - expected) <= 0.02 * ga.module else {
                    throw MGSolidIssue("constraint.gearMesh.motion", part: m.b)
                }
                let (e1, e2) = basis(n)
                func phase(_ id: String) -> Double { let x = frame(w, id).c0; return atan2(x.dot(e2), x.dot(e1)) }
                let required = requiredPhase(m, from: m.a, phase, e1, e2, centres: (fa.translation, fb.translation))
                guard pitchOffset(required, phase(m.b), gb.teeth) < 1e-6 else { throw MGSolidIssue("constraint.gearMesh.motion", part: m.b) }
            }
            // Tooth ratio over a small input step, measured relative to the carrier frame.
            func turn(_ id: String) -> Double {
                let c0 = m.carrier.map { worlds[0][$0] ?? .identity } ?? .identity, c1 = m.carrier.map { worlds[1][$0] ?? .identity } ?? .identity
                let nc = c0.inverse.applyVector(n0)
                let x0 = c0.inverse.applyVector(frame(worlds[0], id).c0), x1 = c1.inverse.applyVector(frame(worlds[1], id).c0)
                return atan2(nc.dot(x0.cross(x1)), x0.dot(x1))
            }
            let sign: Double = ga.ring != nil ? -1 : 1
            let ta = Double(ga.teeth) * turn(m.a), tb = sign * Double(gb.teeth) * turn(m.b)
            guard abs(ta + tb) <= 1e-6 * (abs(ta) + abs(tb)) + 1e-9 else { throw MGSolidIssue("constraint.gearMesh.motion", part: m.b) }
        }
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
                default: throw MGSolidIssue("part.joint.unknown.\(token(k))")
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
        guard let keys = shapeKeys[kind] else { throw MGSolidIssue("part.shape.unknown.\(token(kind))") }
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
            let pa = try opt("pressureAngle", 14.5...25) ?? 20, backlash = try opt("backlash", 0...0.3) ?? 0.06
            let g = MGSpurGear(teeth: z, module: m, pressureAngle: pa * .pi / 180, backlash: backlash)
            // The tooth needs a real tip land, and the sampled outline must stay star-shaped (no crossing flanks).
            guard g.halfThicknessAngle(at: g.tipRadius) > 0.01 / Double(z) else { throw MGSolidIssue("\(w).tip") }
            guard MGProfile.isPolarMonotonic(g.outline()) else { throw MGSolidIssue("\(w).profile") }
            let bore = try opt("bore", 0...4000) ?? 0
            guard bore < g.rootRadius - 0.5 * m else { throw MGSolidIssue("\(w).bore") }
            var key: (width: Double, depth: Double)?
            if let k = f["keyway"] {
                guard case .array(let a) = k, a.count == 2 else { throw MGSolidIssue("\(w).keyway") }
                let kw = try num(a[0], 0.1...1000, "\(w).keyway"), kd = try num(a[1], 0.1...1000, "\(w).keyway")
                guard bore > 0, kw < bore, bore + kd < g.rootRadius - 0.3 * m else { throw MGSolidIssue("\(w).keyway") }
                key = (kw, kd)
            }
            let profile = g.profile(bore: bore, keyway: key)
            // The bore (with its keyway corners) must stay inside the root circle.
            guard profileCapsSeparate(profile, inset: 0) else { throw MGSolidIssue(key == nil ? "\(w).bore" : "\(w).keyway") }
            f["chamfer"] = .number(try capChamfer(profile, width: width, explicit: opt("chamfer", 0...50), fallback: 0.28 * m, w))
        case "ringGear":
            let z = try integer("teeth", MGSolidLimits.ringTeeth)
            let m = try n("module", MGSolidLimits.module)
            let width = try n("width")
            let pa = try opt("pressureAngle", 14.5...25) ?? 20, backlash = try opt("backlash", 0...0.3) ?? 0.06
            let outer = try n("outer")
            let g = MGRingGear(teeth: z, module: m, outerRadius: outer, pressureAngle: pa * .pi / 180, backlash: backlash)
            guard outer >= g.rootRadius + m else { throw MGSolidIssue("\(w).outer") }
            guard g.tipRadius > g.baseRadius else { throw MGSolidIssue("\(w).teeth") }
            // Ring teeth need a tip land at the bore, and tooth spaces must stay open at the root.
            guard Double.pi / Double(z) - g.halfSpaceAngle(at: g.tipRadius) > 0.01 / Double(z) else { throw MGSolidIssue("\(w).tip") }
            guard g.halfSpaceAngle(at: g.rootRadius) > 0.01 / Double(z), MGProfile.isPolarMonotonic(g.outline()) else { throw MGSolidIssue("\(w).profile") }
            f["chamfer"] = .number(try capChamfer(g.profile(outerSegments: 240), width: width, explicit: opt("chamfer", 0...50),
                                                 fallback: 0.28 * m, w))
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

    /// True when the cap loops of a gear-like profile (one star-shaped outer loop, at most one star-shaped hole),
    /// inset by `inset` as the chamfered extrusion does, stay star-shaped about the axis and the hole stays strictly
    /// inside the outer loop. That is what keeps the zipper-triangulated caps and chamfer bands from crossing.
    static func profileCapsSeparate(_ p: MGProfile, inset c: Double) -> Bool {
        let outer = c > 0 ? MGProfile.inset(p.outer, by: c) : p.outer
        guard MGProfile.isPolarMonotonic(outer) else { return false }
        guard let h = p.holes.first else { return true }
        let hole = Array((c > 0 ? MGProfile.inset(h, by: c) : h).reversed())
        guard MGProfile.isPolarMonotonic(hole) else { return false }
        let inner = hole.map(\.length).max() ?? 0, rim = outer.map(\.length).min() ?? 0
        guard inner < rim - 1e-6 * max(1, rim) else { return false }
        // The cap strip is built exactly as the extrusion builds it: every triangle must wind counter-clockwise, which
        // (with the strip's boundary being the two loops) means the cap covers the region once, without overlap.
        // Requiring the strip itself (not the ear-clipping fallback) also keeps large gears fast to build.
        let pts = outer + hole
        let tris = MGTriangulator.zipper(points: pts, outer: Array(0..<outer.count), innerCCW: Array(outer.count..<pts.count))
        return tris.allSatisfy { a, b, c in (pts[b] - pts[a]).cross(pts[c] - pts[a]) > 0 }
    }

    /// The cap chamfer of a gear or ring: an authored value must be below half the width and keep the inset caps
    /// valid; without one, the default (at most a quarter of the width) is used when valid, else half of it, else none.
    static func capChamfer(_ p: MGProfile, width: Double, explicit: Double?, fallback: Double, _ w: String) throws -> Double {
        if let c = explicit {
            guard c < width / 2, c == 0 || profileCapsSeparate(p, inset: c) else { throw MGSolidIssue("\(w).chamfer") }
            return c
        }
        let c = min(fallback, width / 4)
        return [c, c / 2].first { profileCapsSeparate(p, inset: $0) } ?? 0
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
        let keys = Set(o.keys)
        guard required.isSubset(of: keys) else { throw MGSolidIssue("\(what).missing") }
        let extra = keys.subtracting(required.union(optional))
        guard extra.isEmpty else { throw MGSolidIssue("\(what).unknown.\(extra.map(token).sorted().joined(separator: ","))") }
    }
    /// An author-supplied name as it appears inside a reason: ASCII letters, digits and `_` (anything else becomes
    /// `_`), at most 32 characters, so reasons stay single tokens without spaces or JSON text.
    static func token(_ s: String) -> String {
        let t = String(s.unicodeScalars.prefix(32).map { u -> Character in
            u.isASCII && (CharacterSet.alphanumerics.contains(u) || u == "_") ? Character(u) : "_"
        })
        return t.isEmpty ? "_" : t
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
