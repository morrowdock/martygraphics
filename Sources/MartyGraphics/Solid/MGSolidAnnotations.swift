// SPDX-License-Identifier: Apache-2.0
import Foundation

// Assembly v2 annotations (open vocabulary 3a): labels, arrows and dimensions anchored to parts or world points.
// The engine computes every annotation from the posed model: motion arrow directions, turn senses, the gravity
// direction check, measured dimensions (facts `dim.<id>`), tiers, visibility per step, warnings and the arrow and
// dimension geometry (thin cylinders and cones with exact counts). No author number is shown as checked.
// Foundation only, deterministic: every list is walked in authored order, never in dictionary order.

/// Hard limits for annotations. Input outside them is refused, never clamped (docs/SOLID-3D.md, Annotations).
public enum MGSolidAnnotationLimits {
    /// Labels, arrows and dimensions per document (`labels.count`, `arrows.count`, `dimensions.count`).
    public static let labels = 32, arrows = 32, dimensions = 16
    /// Annotations visible at once (`annotations.visible`, `step.annotate.count`).
    public static let visible = 12
    /// Largest default input (radians) of a document with annotations: 10,000 turns (`annotations.input`).
    public static let input = 2 * Double.pi * 10_000
    /// Filled text and `unchecked` text, in Unicode scalars. Authored text before filling may be up to
    /// `rawTextFactor` times `text`. A filled text over `MGAnnotationLayout.lineScalars` (40) draws on two lines
    /// (`MGAnnotationLayout.lines`).
    public static let text = 60, unchecked = 60, rawTextFactor = 4
    /// Most Unicode scalars in one grapheme cluster (one character) of annotation text (`text.grapheme`): a longer
    /// cluster (a letter with dozens of combining marks) could not be measured or broken into lines.
    public static let graphemeScalars = 8
    /// Triangle tests per frame for the occlusion ray test; over it, `occluded` is unknown (null).
    public static let occlusionTests = 2_000_000
    /// Motion line arrow `length` in mm, and `{"fact", "scale"}` scale (mm per unit) with the clamped result.
    public static let arrowLength: ClosedRange<Double> = 10...4000
    public static let lengthScale: ClosedRange<Double> = 0.001...1000
    public static let factLength: ClosedRange<Double> = 5...4000
    /// Default motion arrow length as a fraction of the model's bounding diagonal.
    public static let defaultLength = 0.15
    /// Author arrows shorter than this (mm) are refused (`arrow.length.<id>`); dimensions below `minDimension` mm
    /// (or an angle arm below it) are refused (`dimension.zero.<id>`).
    public static let minAuthorLength = 0.5, minDimension = 0.01
    /// A stated motion direction may differ from the engine's by at most this angle; a gravity force by `gravityDegrees`.
    public static let expectDegrees = 30.0, gravityDegrees = 10.0
    /// Arrow shaft radius and dimension line radius as fractions of the bounding diagonal.
    public static let shaftRadius = 0.006, lineRadius = 0.003
}

/// Where an annotation is anchored, as authored (the part id is resolved: an anchor name gives its part).
public enum MGAnnotationAnchor: Equatable, Sendable {
    /// The origin of the part's frame.
    case part(String)
    /// A point in the part's frame (mm).
    case offset(part: String, MGVec3)
    /// The centre of the part's mesh bounds, in its frame.
    case centre(part: String)
    /// A fixed world point (kernel frame: Z up, mm).
    case world(MGVec3)
    /// The centre of mass of the whole assembly at the pose, plus a world offset (kernel frame, mm): uniform density,
    /// each part weighted by its mesh volume (`MGMassPoint`). Force arrows only (docs/SOLID-3D.md, "Anchors").
    case centreOfMass(MGVec3)
}

/// One part's share of the assembly's centre of mass: its mesh's volume centroid in its own frame and its share of the
/// total volume (uniform density; the shares add up to 1).
public struct MGMassPoint: Equatable, Sendable {
    public let part: String
    public let centroid: MGVec3
    public let share: Double
}

/// A resolved anchor: a point in a part's frame (it moves with the part in every pose) or a fixed world point.
public struct MGAnnotationPoint: Equatable, Sendable {
    public let anchor: MGAnnotationAnchor
    /// The part the point rides on; nil for a world point.
    public var part: String? {
        switch anchor {
        case .part(let p), .offset(let p, _), .centre(let p): return p
        case .world, .centreOfMass: return nil
        }
    }
    /// The point in the part's frame, or the world point (a centre-of-mass anchor: its world offset).
    public internal(set) var local: MGVec3
    /// A centre-of-mass anchor: every part's share (filled once meshes exist); empty for every other anchor.
    public internal(set) var mass: [MGMassPoint] = []

    /// True for a centre-of-mass anchor.
    public var isCentreOfMass: Bool { if case .centreOfMass = anchor { return true }; return false }

    /// The point in the posed kernel world (Z up, mm). A centre-of-mass anchor is the share-weighted sum of every part's
    /// posed volume centroid, plus its offset.
    public func world(_ pose: MGPose) -> MGVec3 {
        if isCentreOfMass {
            var c = MGVec3.zero
            for m in mass { c = c + (pose.world[m.part] ?? .identity).apply(m.centroid) * m.share }
            return c + local
        }
        guard let p = part else { return local }
        return (pose.world[p] ?? .identity).apply(local)
    }
}

enum MGMassProperties {
    /// The volume and volume centroid of a closed mesh in its own frame (divergence theorem over its triangles, taken
    /// about the box centre). A mesh whose volume is not finite or below 1e-9 mm³ counts as its box (volume and centre).
    static func volume(_ mesh: MGMesh) -> (volume: Double, centroid: MGVec3) {
        let b = mesh.bounds
        guard !b.isEmpty else { return (0, .zero) }
        let o = b.center, pos = mesh.positions
        var v = 0.0, m = MGVec3.zero
        for i in 0..<mesh.triangleCount {
            let (i0, i1, i2) = mesh.triangle(i)
            guard i0 < pos.count, i1 < pos.count, i2 < pos.count else { continue }
            let a = pos[i0] - o, bb = pos[i1] - o, c = pos[i2] - o
            let t = a.dot(bb.cross(c)) / 6
            v += t
            m = m + (a + bb + c) * (t / 4)
        }
        if v.isFinite, abs(v) > 1e-9, m.x.isFinite, m.y.isFinite, m.z.isFinite { return (abs(v), o + m * (1 / v)) }
        let s = b.size
        return (max(0, s.x * s.y * s.z), o)
    }

    /// Every part's share of the assembly's mass (uniform density, by mesh volume; assembly order). Parts with no volume
    /// get no share; when no part has volume, every part with a mesh gets an equal share at its box centre.
    static func shares(_ assembly: MGAssembly) -> [MGMassPoint] {
        let parts = assembly.parts.map { ($0.id, volume($0.mesh)) }
        let total = parts.reduce(0) { $0 + $1.1.volume }
        if total.isFinite, total > 0 {
            return parts.filter { $0.1.volume > 0 }.map { MGMassPoint(part: $0.0, centroid: $0.1.centroid, share: $0.1.volume / total) }
        }
        let meshed = assembly.parts.filter { !$0.mesh.bounds.isEmpty }
        guard !meshed.isEmpty else { return [] }
        return meshed.map { MGMassPoint(part: $0.id, centroid: $0.mesh.bounds.center, share: 1 / Double(meshed.count)) }
    }
}

/// A text label at an anchor.
public struct MGSolidLabel: Equatable, Sendable {
    public let id: String
    public let at: MGAnnotationPoint
    /// The authored text and the text the learner sees (placeholders filled from engine facts).
    public internal(set) var template: String
    public internal(set) var text: String
    public let unchecked: String?
    /// Canonical facts the text shows, in order.
    public internal(set) var facts: [String] = []
    /// Described when `unchecked`; else the lowest tier of the facts it shows; nil when it shows no fact.
    public internal(set) var tier: MGSolidTier?
}

/// An arrow. Motion directions and turn senses come from the engine; force, flow and pointer arrows are drawn as
/// authored (a gravity force is checked against world −Z).
public struct MGSolidArrow: Equatable, Sendable {
    public enum Meaning: String, Equatable, Sendable, CaseIterable { case force, flow, motion, pointer }
    public enum Style: String, Equatable, Sendable { case line, turn }
    public enum Length: Equatable, Sendable {
        /// 15 % of the model's bounding diagonal.
        case automatic
        case millimetres(Double)
        /// |fact| × scale mm, clamped to 5...4000.
        case fact(String, scale: Double)
    }
    public let id: String
    public let meaning: Meaning
    public let style: Style
    /// Turn arrows: the revolute part.
    public let on: String?
    public let from: MGAnnotationPoint?
    public let to: MGAnnotationPoint?
    /// Turn arrows: the stated sense, `cw` or `ccw` (seen from the tip of the joint axis).
    public let sense: String?
    /// Motion line arrows: the stated world direction (unit).
    public let expect: MGVec3?
    public let lengthSpec: Length
    /// Force arrows: `gravity`.
    public let cause: String?
    public internal(set) var template: String?
    public internal(set) var text: String?
    public let unchecked: String?
    public internal(set) var facts: [String] = []
    /// Engine results. Turn arrows: +1 when the part turns counter-clockwise about its joint axis (seen from the
    /// axis tip), −1 clockwise. Motion line arrows: the direction at the default input (unit, kernel world) and the
    /// length in mm.
    public internal(set) var turnSign: Double?
    public internal(set) var direction: MGVec3?
    public internal(set) var length: Double?
    /// The arc of a turn arrow, in the part's joint frame: centre on the joint axis and radius (mm).
    public internal(set) var arcCentre: MGVec3 = .zero
    public internal(set) var arcRadius: Double = 0
    /// The smallest arc radius that clears the part: 1.15 × the mesh's widest radius about the joint axis (mm).
    public internal(set) var arcClearance: Double = 0
    /// Claim tier (see docs); nil when the arrow makes no claim (a pointer whose text shows no fact).
    public internal(set) var tier: MGSolidTier?
    /// True when the arrow's length shows a fact (it claims a magnitude).
    public var scaled: Bool { if case .fact = lengthSpec { return true }; return false }
    /// The engine colour role: force = warn, flow = accent, motion = good, pointer = ink (the theme's ink colour).
    public var colorRole: String {
        switch meaning { case .force: return "warn"; case .flow: return "accent"; case .motion: return "good"; case .pointer: return "ink" }
    }
}

/// A dimension: a distance or an angle the engine measures between anchors. Its value is the fact `dim.<id>`.
public struct MGSolidDimension: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable { case distance, angle }
    public let id: String
    public let kind: Kind
    public let a: MGAnnotationPoint
    public let b: MGAnnotationPoint
    public let vertex: MGAnnotationPoint?
    /// Distance along one world axis: 0 = x, 1 = y, 2 = z.
    public let along: Int?
    /// True for `"over": "input"`: largest minus smallest value over one input turn.
    public let over: Bool
    public internal(set) var value: Double = 0
    /// `mm` or `°`.
    public var unit: String { kind == .angle ? "°" : "mm" }
    public internal(set) var template: String
    public internal(set) var text: String = ""
    public internal(set) var facts: [String] = []
    public internal(set) var tier: MGSolidTier = .solved
    /// The fact name of the value.
    public var factName: String { "dim." + id }
}

/// One drawable piece of an arrow or a dimension: a capped cylinder or a cone from `start` to `end` (kernel world,
/// mm). Every renderer builds the same pieces; SceneKit scales one unit cylinder and one unit cone per piece.
public struct MGAnnotationPrimitive: Equatable, Sendable {
    public enum Shape: String, Equatable, Sendable { case cylinder, cone }
    public var shape: Shape
    public var start: MGVec3
    public var end: MGVec3
    public var radius: Double
    /// Hidden pieces draw nothing (a zero-length shaft, or a motion arrow on a still anchor during a spin).
    public var hidden: Bool
}

/// The annotations of a compiled document, in authored order.
public struct MGSolidAnnotations: Equatable, Sendable {
    public internal(set) var labels: [MGSolidLabel] = []
    public internal(set) var arrows: [MGSolidArrow] = []
    public internal(set) var dimensions: [MGSolidDimension] = []
    /// True when some step lists `annotate`: then each step shows exactly its list and the plain view shows none.
    public internal(set) var stepped = false
    /// The model's bounding diagonal at the default input with explode 0 (mm); sizes arrows and lines.
    public internal(set) var diagonal: Double = 1

    public init() {}
    public var isEmpty: Bool { labels.isEmpty && arrows.isEmpty && dimensions.isEmpty }
    /// Every annotation id: labels, then arrows, then dimensions.
    public var ids: [String] { labels.map(\.id) + arrows.map(\.id) + dimensions.map(\.id) }
    /// `label`, `arrow` or `dimension`; nil for an unknown id.
    public func kind(_ id: String) -> String? {
        if labels.contains(where: { $0.id == id }) { return "label" }
        if arrows.contains(where: { $0.id == id }) { return "arrow" }
        if dimensions.contains(where: { $0.id == id }) { return "dimension" }
        return nil
    }
    public func label(_ id: String) -> MGSolidLabel? { labels.first { $0.id == id } }
    public func arrow(_ id: String) -> MGSolidArrow? { arrows.first { $0.id == id } }
    public func dimension(_ id: String) -> MGSolidDimension? { dimensions.first { $0.id == id } }

    /// Dimension lines use the ink colour.
    public static let dimensionRole = "ink"
    /// sRGB colour of an annotation colour role (`ink` is the theme's ink colour, the `white` role).
    public static func srgb(_ role: String) -> [Double] {
        MGSolidPalette.srgb(role == "ink" ? .white : MGColorRole(rawValue: role) ?? .white)
    }

    // MARK: Mesh counts (exact, known before any piece is built)

    /// Segments around a cylinder or cone.
    static let segments = 8
    /// Chords of a turn arc (270°) and of an angle arc.
    static let arcChords = 24
    static let cylinderCounts = (triangles: 4 * segments, vertices: 4 * segments + 2)
    static let coneCounts = (triangles: 2 * segments, vertices: 3 * segments + 1)

    /// Pieces each annotation draws (fixed: pieces never appear or vanish with the pose; they hide instead).
    static func pieces(arrow a: MGSolidArrow) -> (cylinders: Int, cones: Int) { a.style == .turn ? (arcChords, 1) : (1, 1) }
    static func pieces(dimension d: MGSolidDimension) -> (cylinders: Int, cones: Int) { pieces(kind: d.kind, along: d.along != nil) }
    static func pieces(kind: MGSolidDimension.Kind, along: Bool) -> (cylinders: Int, cones: Int) {
        kind == .angle ? (arcChords + 2, 0) : (along ? 5 : 3, 0)
    }
    static func counts(_ p: (cylinders: Int, cones: Int)) -> (triangles: Int, vertices: Int) {
        (p.cylinders * cylinderCounts.triangles + p.cones * coneCounts.triangles,
         p.cylinders * cylinderCounts.vertices + p.cones * coneCounts.vertices)
    }
    /// Exact triangles and vertices of every arrow and dimension (they join the document's mesh budget).
    public var meshEstimate: (triangles: Int, vertices: Int) {
        var t = 0, v = 0
        for a in arrows { let c = Self.counts(Self.pieces(arrow: a)); t += c.triangles; v += c.vertices }
        for d in dimensions { let c = Self.counts(Self.pieces(dimension: d)); t += c.triangles; v += c.vertices }
        return (t, v)
    }
}

// MARK: Parsing

extension MGSolidAnnotations {
    typealias L = MGSolidAnnotationLimits

    /// Every name an annotation id may not take, and the part references an anchor may name.
    struct Names {
        /// Resolved part ids (copies included).
        var ids: Set<String>
        /// `repeat` base ids with their copy counts.
        var repeated: [String: Int]
        /// Component anchors to the ids they name.
        var aliases: [String: String]
        /// Component instance ids (every dotted prefix of a resolved id or anchor).
        var instances: Set<String>

        init(ids: Set<String>, repeated: [String: Int], aliases: [String: String]) {
            self.ids = ids; self.repeated = repeated; self.aliases = aliases
            var inst = Set<String>()
            for name in ids.sorted() + aliases.keys.sorted() {
                var cut = name.endIndex
                while let dot = name[..<cut].lastIndex(of: ".") { inst.insert(String(name[..<dot])); cut = dot }
            }
            instances = inst
        }
        func taken(_ id: String) -> Bool { ids.contains(id) || repeated[id] != nil || aliases[id] != nil || instances.contains(id) }

        /// A part reference: a part id, a `repeat` copy id or an anchor name. A base id with copies or an instance id
        /// is ambiguous (`anchor.ambiguous.<id>`); anything else unknown (`anchor.ref.<id>`).
        func part(_ ref: String, owner: String) throws -> String {
            let t = MGSolidParser.token(ref)
            let target = aliases[ref] ?? ref
            if repeated[target] != nil || instances.contains(target) || instances.contains(ref) {
                throw MGSolidIssue("anchor.ambiguous.\(t)", part: owner)
            }
            guard ids.contains(target) else { throw MGSolidIssue("anchor.ref.\(t)", part: owner) }
            return target
        }
    }

    /// Parses the v2 `annotations` object: closed keys, limits, ids in the document's one namespace, anchors resolved
    /// against the expanded parts. Text, directions and values are computed later (`prepare`, `finish`).
    static func parse(_ json: MGJSON, _ names: Names) throws -> MGSolidAnnotations {
        guard case .object(let o) = json else { throw MGSolidIssue("annotations.object") }
        try MGSolidParser.closed(o, [], ["labels", "arrows", "dimensions"], "annotations")
        func list(_ key: String, _ max: Int, _ reason: String) throws -> [MGJSON] {
            guard let v = o[key] else { return [] }
            guard case .array(let a) = v else { throw MGSolidIssue(reason) }
            if let l = MGSolidParser.countDetail("annotations.\(key)", a.count, 0...max) { throw MGSolidIssue(reason, limit: l) }
            return a
        }
        let labels = try list("labels", L.labels, "labels.count")
        let arrows = try list("arrows", L.arrows, "arrows.count")
        let dimensions = try list("dimensions", L.dimensions, "dimensions.count")
        var out = MGSolidAnnotations()
        var seen = Set<String>()
        func identify(_ o: [String: MGJSON], _ what: String) throws -> String {
            guard let id = try? MGParser.identifier(o["id"] ?? .null, "") else { throw MGSolidIssue("\(what).id") }
            guard !names.taken(id), seen.insert(id).inserted else { throw MGSolidIssue("id.duplicate.\(id)", part: id) }
            return id
        }
        // A refusal names its annotation (`part`); a limit detail gets the annotation's path.
        func named(_ e: MGSolidIssue, _ id: String, _ path: String) -> MGSolidIssue {
            (e.part == nil ? MGSolidIssue(e.reason, part: id, limit: e.limit) : e).prefixed(path)
        }
        for (k, e) in labels.enumerated() {
            guard case .object(let lo) = e else { throw MGSolidIssue("label.object") }
            try MGSolidParser.closed(lo, ["id", "at", "text"], ["unchecked"], "label")
            let id = try identify(lo, "label")
            do {
                let at = try anchor(lo["at"]!, names, owner: id)
                let template = try text(lo["text"]!, "label.text.\(id)", id: id)
                let unchecked = try lo["unchecked"].map { try MGSolidParser.text($0, L.unchecked, "label.unchecked.\(id)", field: "unchecked") }
                out.labels.append(MGSolidLabel(id: id, at: at, template: template, text: template, unchecked: unchecked))
            } catch let e as MGSolidIssue { throw named(e, id, "annotations.labels[\(k)].") }
        }
        for (k, e) in arrows.enumerated() {
            guard case .object(let ao) = e else { throw MGSolidIssue("arrow.object") }
            try MGSolidParser.closed(ao, ["id", "meaning"], ["text", "unchecked", "on", "style", "sense", "from", "to", "expect", "length", "cause"], "arrow")
            let id = try identify(ao, "arrow")
            do { out.arrows.append(try arrow(ao, id, names)) }
            catch let e as MGSolidIssue { throw named(e, id, "annotations.arrows[\(k)].") }
        }
        for (k, e) in dimensions.enumerated() {
            guard case .object(let d) = e else { throw MGSolidIssue("dimension.object") }
            try MGSolidParser.closed(d, ["id", "a", "b"], ["kind", "vertex", "along", "over", "text"], "dimension")
            let id = try identify(d, "dimension")
            do { out.dimensions.append(try dimension(d, id, names)) }
            catch let e as MGSolidIssue { throw named(e, id, "annotations.dimensions[\(k)].") }
        }
        return out
    }

    /// Authored annotation text: the solid text rule, at most `rawTextFactor × text` scalars before filling.
    /// `id`: the annotation, named by `text.grapheme`.
    static func text(_ v: MGJSON, _ reason: String, id: String) throws -> String {
        let t = try MGSolidParser.text(v, L.text * L.rawTextFactor, reason, field: "text")
        let widest = t.map { $0.unicodeScalars.count }.max() ?? 0
        guard widest <= L.graphemeScalars else {
            throw MGSolidIssue("text.grapheme", part: id, limit: MGSolidLimitDetail(field: "text", actual: widest, limit: L.graphemeScalars,
                                                                                    unit: "scalars"))
        }
        return t
    }

    static func vector3(_ v: MGJSON?, _ reason: String) throws -> MGVec3 {
        guard case .array(let a)? = v, a.count == 3 else { throw MGSolidIssue(reason) }
        return MGVec3(try MGSolidParser.num(a[0], MGSolidLimits.coordinate, reason), try MGSolidParser.num(a[1], MGSolidLimits.coordinate, reason),
                      try MGSolidParser.num(a[2], MGSolidLimits.coordinate, reason))
    }

    /// `"p"`, `{"part": "p", "offset": [x, y, z]}`, `{"part": "p", "point": "centre"}`, `{"part": "p"}` (the same as
    /// `"point": "centre"`), `{"world": [x, y, z]}`, or, where `centreOfMass` allows it (a force arrow's ends),
    /// `{"point": "centreOfMass"}` with an optional world `"offset": [x, y, z]` (any other use is `anchor.point`).
    static func anchor(_ v: MGJSON, _ names: Names, owner: String, centreOfMass: Bool = false) throws -> MGAnnotationPoint {
        switch v {
        case .string(let ref):
            return MGAnnotationPoint(anchor: .part(try names.part(ref, owner: owner)), local: .zero)
        case .object(let o):
            let keys = Set(o.keys)
            if keys == ["point"] || keys == ["point", "offset"], o["point"] == .string("centreOfMass") {
                guard centreOfMass else { throw MGSolidIssue("anchor.point") }
                let off = keys.contains("offset") ? try vector3(o["offset"], "anchor.offset") : .zero
                // The parts' shares are filled in once meshes exist (`prepare`).
                return MGAnnotationPoint(anchor: .centreOfMass(off), local: off)
            }
            if keys == ["world"] { return MGAnnotationPoint(anchor: .world(try vector3(o["world"], "anchor.world")), local: try vector3(o["world"], "anchor.world")) }
            guard case .string(let ref)? = o["part"], keys == ["part"] || keys == ["part", "offset"] || keys == ["part", "point"] else {
                throw MGSolidIssue("anchor.form")
            }
            if keys.contains("offset") {
                let off = try vector3(o["offset"], "anchor.offset")
                return MGAnnotationPoint(anchor: .offset(part: try names.part(ref, owner: owner), off), local: off)
            }
            guard keys == ["part"] || o["point"] == .string("centre") else { throw MGSolidIssue("anchor.point") }
            // The mesh centre is filled in once meshes exist (`prepare`).
            return MGAnnotationPoint(anchor: .centre(part: try names.part(ref, owner: owner)), local: .zero)
        default:
            throw MGSolidIssue("anchor.form")
        }
    }

    static func arrow(_ o: [String: MGJSON], _ id: String, _ names: Names) throws -> MGSolidArrow {
        guard case .string(let m)? = o["meaning"], let meaning = MGSolidArrow.Meaning(rawValue: m) else { throw MGSolidIssue("arrow.meaning.\(id)") }
        var style = MGSolidArrow.Style.line
        if meaning == .motion, let s = o["style"] {
            guard case .string(let sv) = s, let st = MGSolidArrow.Style(rawValue: sv) else { throw MGSolidIssue("arrow.style.\(id)") }
            style = st
        }
        let common: Set<String> = ["id", "meaning", "text", "unchecked"]
        let allowed: Set<String>, required: Set<String>
        switch (meaning, style) {
        case (.motion, .turn): allowed = common.union(["style", "on", "sense"]); required = ["on"]
        case (.motion, .line): allowed = common.union(["style", "from", "expect", "length"]); required = ["from"]
        case (.force, _): allowed = common.union(["from", "to", "cause"]); required = ["from", "to"]
        default: allowed = common.union(["from", "to"]); required = ["from", "to"]
        }
        if let wrong = Set(o.keys).subtracting(allowed).sorted().first { throw MGSolidIssue("arrow.key.\(MGSolidParser.token(wrong)).\(id)") }
        let missing = required.subtracting(o.keys)
        guard missing.isEmpty else { throw MGSolidIssue("arrow.missing.\(missing.sorted().joined(separator: ","))") }
        var on: String?
        if let v = o["on"] {
            guard case .string(let ref) = v else { throw MGSolidIssue("arrow.on.\(id)") }
            on = try names.part(ref, owner: id)
        }
        let from = try o["from"].map { try anchor($0, names, owner: id, centreOfMass: meaning == .force) }
        let to = try o["to"].map { try anchor($0, names, owner: id, centreOfMass: meaning == .force) }
        if meaning == .motion, style == .line, from?.part == nil { throw MGSolidIssue("arrow.from.\(id)") }
        var sense: String?
        if let v = o["sense"] {
            guard case .string(let s) = v, s == "cw" || s == "ccw" else { throw MGSolidIssue("arrow.sense.form.\(id)") }
            sense = s
        }
        var expect: MGVec3?
        if let v = o["expect"] {
            let e = try vector3(v, "arrow.expect.form.\(id)")
            guard e.length > 1e-9 else { throw MGSolidIssue("arrow.expect.form.\(id)") }
            expect = e.normalized
        }
        var length = MGSolidArrow.Length.automatic
        if let v = o["length"] {
            switch v {
            case .number:
                length = .millimetres(try MGSolidParser.num(v, L.arrowLength, "arrow.length.form.\(id)"))
            case .object(let lo):
                guard Set(lo.keys) == ["fact", "scale"], case .string(let f)? = lo["fact"], MGSolidFacts.isName(f) else {
                    throw MGSolidIssue("arrow.length.form.\(id)")
                }
                length = .fact(f, scale: try MGSolidParser.num(lo["scale"], L.lengthScale, "arrow.length.form.\(id)"))
            default: throw MGSolidIssue("arrow.length.form.\(id)")
            }
        }
        var cause: String?
        if let v = o["cause"] {
            guard v == .string("gravity") else { throw MGSolidIssue("arrow.cause.\(id)") }
            cause = "gravity"
        }
        let template = try o["text"].map { try text($0, "arrow.text.\(id)", id: id) }
        let unchecked = try o["unchecked"].map { try MGSolidParser.text($0, L.unchecked, "arrow.unchecked.\(id)", field: "unchecked") }
        // `unchecked` marks the arrow's text; without text it would mark nothing.
        if unchecked != nil, template == nil { throw MGSolidIssue("arrow.unchecked.text.\(id)") }
        return MGSolidArrow(id: id, meaning: meaning, style: style, on: on, from: from, to: to, sense: sense, expect: expect,
                            lengthSpec: length, cause: cause, template: template, text: template, unchecked: unchecked)
    }

    static func dimension(_ o: [String: MGJSON], _ id: String, _ names: Names) throws -> MGSolidDimension {
        var kind = MGSolidDimension.Kind.distance
        if let v = o["kind"] {
            guard case .string(let k) = v, let kk = MGSolidDimension.Kind(rawValue: k) else { throw MGSolidIssue("dimension.kind.\(id)") }
            kind = kk
        }
        var along: Int?
        if let v = o["along"] {
            guard kind == .distance, case .string(let s) = v, let i = ["x", "y", "z"].firstIndex(of: s) else { throw MGSolidIssue("dimension.along.\(id)") }
            along = i
        }
        var over = false
        if let v = o["over"] {
            guard v == .string("input") else { throw MGSolidIssue("dimension.over.form.\(id)") }
            over = true
        }
        guard (kind == .angle) == (o["vertex"] != nil) else { throw MGSolidIssue("dimension.vertex.\(id)") }
        let a = try anchor(o["a"]!, names, owner: id), b = try anchor(o["b"]!, names, owner: id)
        let vertex = try o["vertex"].map { try anchor($0, names, owner: id) }
        let template = try o["text"].map { try text($0, "dimension.text.form.\(id)", id: id) } ?? "{dim.\(id)}"
        return MGSolidDimension(id: id, kind: kind, a: a, b: b, vertex: vertex, along: along, over: over, template: template)
    }
}

// MARK: Engine (after the document compiles)

extension MGSolidDocument {
    /// The lowest drive tier over a part and every ancestor whose own joint moves; nil when nothing in its chain moves.
    func chainTier(_ id: String) -> MGSolidTier? {
        var tier: MGSolidTier?
        var cur: String? = id, seen = Set<String>()
        while let c = cur, seen.insert(c).inserted {
            if ownMotion(c) { tier = min(tier ?? .solved, driveTiers[c] ?? .solved) }
            cur = assembly.part(c)?.parent
        }
        return tier
    }

    /// Ids of the annotations a step shows (`nil`: the plain view). Without any step `annotate`, every annotation shows
    /// everywhere; with one, each step shows exactly its list and the plain view shows none.
    public func visibleAnnotations(step: Int?) -> [String] {
        if !annotations.stepped { return annotations.ids }
        guard let i = step, steps.indices.contains(i) else { return [] }
        return steps[i].annotate ?? []
    }
}

enum MGSolidAnnotationEngine {
    typealias L = MGSolidAnnotationLimits

    /// The step `annotate` references and the visibility rule. Runs right after parsing, before any mesh is built.
    /// `perStep` (an explainer's solid): more than `visible` annotations make the document stepped, so the limit applies
    /// to each step's (beat's) own list, and a step without `annotate` shows none. At most `visible` annotations keep
    /// the plain rule (no `annotate` anywhere: every annotation everywhere), so such documents do not change.
    /// `stepped`: the document is stepped whatever its steps (an explainer document whose beats choose their labels).
    static func checkVisibility(_ a: inout MGSolidAnnotations, _ steps: [MGSolidStep], perStep: Bool = false, stepped: Bool = false) throws {
        let ids = Set(a.ids)
        a.stepped = stepped || steps.contains { $0.annotate != nil } || (perStep && a.ids.count > L.visible)
        for s in steps {
            for id in s.annotate ?? [] where !ids.contains(id) { throw MGSolidIssue("step.annotate.ref.\(MGSolidParser.token(id))") }
        }
        if !a.stepped, a.ids.count > L.visible {
            throw MGSolidIssue(visibility: MGAnnotationVisibilityDetail(annotation: a.ids[L.visible], count: a.ids.count, limit: L.visible,
                                                                        cause: steps.isEmpty ? .noSteps : .unannotated))
        }
    }

    /// Mesh centres, the model scale, turn arcs and every dimension value (facts `dim.<id>`), before text is filled.
    static func prepare(_ doc: inout MGSolidDocument) throws {
        guard !doc.annotations.isEmpty else { return }
        var a = doc.annotations
        var shares: [MGMassPoint]?
        func resolve(_ p: inout MGAnnotationPoint) {
            if case .centre(let id) = p.anchor { p.local = doc.assembly.part(id)?.mesh.bounds.center ?? .zero }
            if p.isCentreOfMass {
                if shares == nil { shares = MGMassProperties.shares(doc.assembly) }
                p.mass = shares ?? []
            }
        }
        for i in a.labels.indices { var p = a.labels[i].at; resolve(&p); a.labels[i] = a.labels[i].with(at: p) }
        for i in a.arrows.indices { a.arrows[i] = a.arrows[i].resolving(resolve) }
        for i in a.dimensions.indices { a.dimensions[i] = a.dimensions[i].resolving(resolve) }
        let rest = doc.assembly.pose(MGPoseParameters(input: doc.defaults.input, explode: 0))
        let bounds = doc.assembly.bounds(rest)
        let diag = bounds.isEmpty ? 1 : bounds.size.length
        a.diagonal = diag.isFinite && diag > 1e-9 ? diag : 1
        // Turn arcs: in the part's joint frame, around the joint axis at the middle of the mesh along it, 15 % outside
        // the widest point of the mesh, so the arc stays visible from every side.
        for i in a.arrows.indices where a.arrows[i].style == .turn {
            guard let id = a.arrows[i].on, let part = doc.assembly.part(id), case .revolute(let axis) = part.joint else { continue }
            let n = axis.normalized
            var lo = Double.infinity, hi = -Double.infinity, radial = 0.0
            for v in part.mesh.positions {
                let t = v.dot(n)
                lo = min(lo, t); hi = max(hi, t); radial = max(radial, (v - n * t).length)
            }
            let r = a.diagonal * L.shaftRadius
            a.arrows[i].arcCentre = lo <= hi ? n * ((lo + hi) / 2) : .zero
            a.arrows[i].arcClearance = 1.15 * radial
            a.arrows[i].arcRadius = max(1.15 * radial, 8 * r)
        }
        doc.annotations = a
        for i in doc.annotations.dimensions.indices {
            var d = doc.annotations.dimensions[i]
            try measure(&d, doc)
            guard doc.facts[d.factName] == nil else { throw MGSolidIssue("dimension.fact.\(d.id)", part: d.id) }
            doc.facts[d.factName] = MGSolidFact(value: d.value, unit: d.unit, tier: d.tier, source: "dimension")
            doc.annotations.dimensions[i] = d
        }
    }

    /// A dimension's value at one pose: |b − a| (or one world component with `along`) or the angle at the vertex; nil
    /// when an angle arm is shorter than `minDimension`.
    static func dimensionValue(_ d: MGSolidDimension, _ pose: MGPose) -> Double? {
        let pa = d.a.world(pose), pb = d.b.world(pose)
        if d.kind == .angle, let v = d.vertex?.world(pose) {
            let u = pa - v, w = pb - v
            guard u.length >= L.minDimension, w.length >= L.minDimension else { return nil }
            let c = max(-1, min(1, u.dot(w) / (u.length * w.length)))
            return acos(c) * 180 / .pi
        }
        let delta = pb - pa
        if let k = d.along { return abs([delta.x, delta.y, delta.z][k]) }
        return delta.length
    }

    static func measure(_ d: inout MGSolidDimension, _ doc: MGSolidDocument) throws {
        func value(_ pose: MGPose) throws -> Double {
            guard let v = dimensionValue(d, pose) else { throw MGSolidIssue("dimension.zero.\(d.id)", part: d.id) }
            return v
        }
        let at = try value(doc.assembly.pose(MGPoseParameters(input: doc.defaults.input, explode: 0)))
        let parts = [d.a.part, d.b.part, d.vertex?.part].compactMap { $0 }
        let chain = parts.compactMap(doc.chainTier).min()
        if d.over {
            guard chain != nil else { throw MGSolidIssue("dimension.over.\(d.id)", part: d.id) }
            // The range over one input turn from the joint's closed form (`dimension.over.motion.<id>` otherwise). The anchor
            // held still is world-fixed only within the epsilon, so the range is known within `bound` (2 × that anchor's
            // motion bound): over the dimension tolerance, the range is not one Solved fact (`dimension.over.motion.<id>`,
            // with `dimensionMotion`).
            let r = try MGSolidAnnotationMotion.rangeBound(d, doc, explode: 0)
            d.value = r.value
            let tol = 1e-9 * max(1, abs(r.value), doc.annotations.diagonal)
            if !(r.bound <= tol) {
                var issue = MGSolidIssue("dimension.over.motion.\(d.id)", part: d.id)
                issue.dimensionMotion = MGDimensionMotion.over(d, step: nil, r, tolerance: tol)
                throw issue
            }
            // A range below 0.01 mm (or 0.01°) means nothing changes over the turn.
            if d.value < L.minDimension { throw MGSolidIssue("dimension.over.still.\(d.id)", part: d.id) }
            d.tier = chain ?? .solved
        } else {
            if d.kind == .distance, at < L.minDimension { throw MGSolidIssue("dimension.zero.\(d.id)", part: d.id) }
            d.value = at
            // At input 0 no drive speed affects the pose; at another default input the pose depends on the drive chain.
            d.tier = doc.defaults.input == 0 ? .solved : (chain ?? .solved)
        }
    }

    static func angle(_ a: MGVec3, _ b: MGVec3) -> Double {
        let c = a.normalized.dot(b.normalized)
        return acos(max(-1, min(1, c))) * 180 / .pi
    }

    /// Fills one annotation text. `abs` is refused: no step proves a sign for an annotation (`text.sign.<name>`).
    static func fill(_ template: String, _ w: String, n1: Bool, _ doc: MGSolidDocument, tooLong: String, field: String) throws -> MGSolidFilledText {
        let filled = try MGSolidFacts.fill(template, where: w, n1: n1, doc.facts, doc.aliases, names: Set(doc.names))
        for (name, mods) in zip(filled.facts, filled.modifiers) where mods.contains("abs") { throw MGSolidIssue("text.sign.\(MGSolidParser.token(name))") }
        let empty = filled.text.trimmingCharacters(in: .whitespaces).isEmpty
        guard !empty, filled.text.unicodeScalars.count <= L.text else {
            throw MGSolidIssue(tooLong, limit: MGSolidLimitDetail(field: field, actual: empty ? 0 : filled.text.unicodeScalars.count, limit: L.text,
                                                                  unit: "characters", minimum: 1))
        }
        return filled
    }

    /// Arrow directions and checks, every annotation text, and every annotation tier. Runs after the captions are filled.
    static func finish(_ doc: inout MGSolidDocument) throws {
        guard !doc.annotations.isEmpty else { return }
        var a = doc.annotations
        let rest = doc.assembly.pose(MGPoseParameters(input: doc.defaults.input, explode: 0))
        for i in a.labels.indices {
            var l = a.labels[i]
            do {
                let f = try fill(l.template, "label.\(l.id)", n1: l.unchecked == nil, doc, tooLong: "label.text.\(l.id)",
                                 field: "annotations.labels[\(i)].text")
                l.text = f.text; l.facts = f.facts
                l.tier = MGSolidTiers.text(facts: f.facts.compactMap { doc.facts[$0] }, unchecked: l.unchecked != nil)
            } catch let e as MGSolidIssue { throw MGSolidIssue(e.reason, part: l.id, limit: e.limit) }
            a.labels[i] = l
        }
        for i in a.arrows.indices {
            var r = a.arrows[i]
            do { try check(&r, doc, rest, index: i) } catch let e as MGSolidIssue { throw MGSolidIssue(e.reason, part: r.id, limit: e.limit) }
            a.arrows[i] = r
        }
        for i in a.dimensions.indices {
            var d = a.dimensions[i]
            do {
                let f = try fill(d.template, "dimension.\(d.id)", n1: true, doc, tooLong: "dimension.text.form.\(d.id)",
                                 field: "annotations.dimensions[\(i)].text")
                guard f.facts.contains(d.factName) else { throw MGSolidIssue("dimension.text.\(d.id)") }
                d.text = f.text; d.facts = f.facts
                d.tier = min(d.tier, f.facts.compactMap { doc.facts[$0]?.tier }.min() ?? .solved)
            } catch let e as MGSolidIssue { throw MGSolidIssue(e.reason, part: d.id, limit: e.limit) }
            a.dimensions[i] = d
        }
        doc.annotations = a
    }

    static func check(_ r: inout MGSolidArrow, _ doc: MGSolidDocument, _ rest: MGPose, index: Int = 0) throws {
        var textTier: MGSolidTier?
        if let t = r.template {
            let f = try fill(t, "arrow.\(r.id)", n1: r.unchecked == nil, doc, tooLong: "arrow.text.\(r.id)", field: "annotations.arrows[\(index)].text")
            r.text = f.text; r.facts = f.facts
            textTier = MGSolidTiers.text(facts: f.facts.compactMap { doc.facts[$0] }, unchecked: r.unchecked != nil)
        }
        var base: MGSolidTier?
        switch (r.meaning, r.style) {
        case (.motion, .turn):
            guard let id = r.on, let part = doc.assembly.part(id) else { throw MGSolidIssue("arrow.turn.joint.\(r.id)") }
            guard case .revolute = part.joint else { throw MGSolidIssue("arrow.turn.joint.\(r.id)") }
            guard doc.ownMotion(id) else { throw MGSolidIssue("arrow.still.\(r.id)") }
            // A turn arrow claims one world sense for every view, so every moving joint above the part must be linear
            // (`annotation.motion.nonlinear.<id>`: a crank rod, or a part on one, swings back and forth), and their
            // axes parallel, so the composed world rate is one constant (`<part>.worldSpeed`; `arrow.turn.steady.<id>`).
            guard MGSolidAnnotationMotion.linearChain(doc, id) else { throw MGSolidIssue("annotation.motion.nonlinear.\(r.id)") }
            guard let s = doc.facts[id + ".worldSpeed"]?.value else { throw MGSolidIssue("arrow.turn.steady.\(r.id)") }
            guard s != 0, s.isFinite else { throw MGSolidIssue("arrow.still.\(r.id)") }
            r.turnSign = s > 0 ? 1 : -1
            if let stated = r.sense, (stated == "ccw") != (s > 0) { throw MGSolidIssue("arrow.sense.\(r.id)") }
            base = doc.motionTier(id)
        case (.motion, .line):
            guard let from = r.from, let part = from.part else { throw MGSolidIssue("arrow.from.\(r.id)") }
            // Only linear chains: a crank closed form reverses, so its direction is not one claim for a view.
            guard MGSolidAnnotationMotion.linearChain(doc, part) else { throw MGSolidIssue("annotation.motion.nonlinear.\(r.id)") }
            guard let dir = MGSolidAnnotationMotion.direction(doc, from, rest) else { throw MGSolidIssue("arrow.still.\(r.id)") }
            r.direction = dir
            if let e = r.expect, angle(e, dir) > L.expectDegrees { throw MGSolidIssue("arrow.expect.\(r.id)") }
            base = doc.chainTier(part) ?? .solved
            switch r.lengthSpec {
            case .automatic: r.length = L.defaultLength * doc.annotations.diagonal
            case .millimetres(let mm): r.length = mm
            case .fact(let name, let scale):
                guard let (_, fact) = MGSolidFacts.lookup(name, doc.facts, doc.aliases), fact.value.isFinite else { throw MGSolidIssue("arrow.length.fact.\(r.id)") }
                r.length = min(max(abs(fact.value) * scale, L.factLength.lowerBound), L.factLength.upperBound)
                base = min(base ?? .solved, fact.tier)
            }
        case (.force, _), (.flow, _), (.pointer, _):
            guard let from = r.from, let to = r.to else { throw MGSolidIssue("arrow.missing.from,to") }
            let d = to.world(rest) - from.world(rest)
            guard d.length >= L.minAuthorLength else { throw MGSolidIssue("arrow.length.\(r.id)") }
            if r.cause == "gravity", angle(d, MGVec3(0, 0, -1)) > L.gravityDegrees { throw MGSolidIssue("arrow.gravity.\(r.id)") }
            switch r.meaning {
            case .force: base = r.cause == nil ? .described : .solved
            case .flow: base = .described
            default: base = nil
            }
        }
        if let b = base { r.tier = min(b, textTier ?? .solved) } else { r.tier = textTier }
    }

    /// `annotation.unused.<id>` (some step uses `annotate`, no step shows it; strict refuses),
    /// `annotation.cut.<id>` (a part anchor lies in the half that the same step's section removes; a warning only),
    /// `annotation.anchor.off.<id>` (a label's or pointer's anchor lies off the part it names,
    /// `MGSolidDocument.offPartAnchors`; strict refuses) and `annotation.arrow.weight.<id>` (a gravity arrow's line of
    /// action misses the centre of mass, `MGSolidDocument.weightPlacements`; a warning only), in authored order. The view rule
    /// `annotation.anchor.hidden.<id>` needs each still's camera, so the check report adds it
    /// (`MGSolidDocument.stepAnchorIssues`), not the compile.
    static func warnings(_ doc: MGSolidDocument) -> [MGSolidIssue] {
        let a = doc.annotations
        guard !a.isEmpty else { return [] }
        var shown = Set<String>()
        for i in doc.steps.indices { shown.formUnion(doc.visibleAnnotations(step: i)) }
        let rest = doc.assembly.pose(MGPoseParameters(input: doc.defaults.input, explode: 0))
        var out: [MGSolidIssue] = []
        let off = Set(doc.offPartAnchors.filter { $0.cause == .offPart }.map(\.id))
        let weight = Set(doc.weightPlacements.map(\.id))
        for id in a.ids {
            if a.stepped, !shown.contains(id) { out.append(MGSolidIssue("annotation.unused.\(id)", part: id)) }
            let points = anchors(a, id)
            let cut = doc.steps.indices.contains { i in
                guard let sec = doc.steps[i].section, doc.visibleAnnotations(step: i).contains(id) else { return false }
                return points.contains { p in
                    guard let part = p.part, sec.parts.contains(part) else { return false }
                    return sec.plane.distance(p.world(rest)) > 1e-9
                }
            }
            if cut { out.append(MGSolidIssue("annotation.cut.\(id)", part: id)) }
            if off.contains(id) { out.append(MGSolidIssue("annotation.anchor.off.\(id)", part: id)) }
            if weight.contains(id) { out.append(MGSolidIssue("annotation.arrow.weight.\(id)", part: id)) }
        }
        return out
    }

    /// The authored anchors of one annotation (a turn arrow: its part's origin).
    static func anchors(_ a: MGSolidAnnotations, _ id: String) -> [MGAnnotationPoint] {
        if let l = a.label(id) { return [l.at] }
        if let r = a.arrow(id) {
            if let on = r.on { return [MGAnnotationPoint(anchor: .part(on), local: .zero)] }
            return [r.from, r.to].compactMap { $0 }
        }
        if let d = a.dimension(id) { return [d.a, d.vertex, d.b].compactMap { $0 } }
        return []
    }
}

extension MGSolidLabel {
    func with(at p: MGAnnotationPoint) -> MGSolidLabel {
        MGSolidLabel(id: id, at: p, template: template, text: text, unchecked: unchecked, facts: facts, tier: tier)
    }
}

extension MGSolidArrow {
    func resolving(_ f: (inout MGAnnotationPoint) -> Void) -> MGSolidArrow {
        var a = from, b = to
        if a != nil { f(&a!) }
        if b != nil { f(&b!) }
        var r = MGSolidArrow(id: id, meaning: meaning, style: style, on: on, from: a, to: b, sense: sense, expect: expect,
                             lengthSpec: lengthSpec, cause: cause, template: template, text: text, unchecked: unchecked)
        r.facts = facts
        return r
    }
}

extension MGSolidDimension {
    func resolving(_ f: (inout MGAnnotationPoint) -> Void) -> MGSolidDimension {
        var pa = a, pb = b, pv = vertex
        f(&pa); f(&pb)
        if pv != nil { f(&pv!) }
        return MGSolidDimension(id: id, kind: kind, a: pa, b: pb, vertex: pv, along: along, over: over, template: template)
    }
}

// MARK: Geometry

extension MGSolidAnnotations {
    /// A unit vector perpendicular to `n` and its right-handed partner (`n × e1`).
    static func basis(_ n: MGVec3) -> (MGVec3, MGVec3) {
        let helper = abs(n.x) < 0.9 ? MGVec3.unitX : MGVec3.unitY
        let e1 = (helper - n * n.dot(helper)).normalized
        return (e1, n.cross(e1))
    }

    /// A shaft and a head from `p` to `q` (the head is 4 shaft radii long and 2.5 wide; a short arrow is all head).
    static func lineArrow(_ p: MGVec3, _ q: MGVec3, radius r: Double, hidden: Bool = false) -> [MGAnnotationPrimitive] {
        let d = q - p, len = d.length
        guard len > 1e-9, len.isFinite, !hidden else {
            return [MGAnnotationPrimitive(shape: .cylinder, start: p, end: p, radius: r, hidden: true),
                    MGAnnotationPrimitive(shape: .cone, start: p, end: p, radius: 2.5 * r, hidden: true)]
        }
        let u = d * (1 / len), head = min(4 * r, len)
        let neck = q - u * head
        return [MGAnnotationPrimitive(shape: .cylinder, start: p, end: neck, radius: r, hidden: len - head < 1e-9),
                MGAnnotationPrimitive(shape: .cone, start: neck, end: q, radius: 2.5 * r, hidden: false)]
    }

    /// Where a pointer's head is drawn (docs/SOLID-3D.md, "Pointers to a part centre"). A pointer whose tip is a part's
    /// centre (`{"part": p, "point": "centre"}` or `{"part": p}`) ends on that part's surface: at the first crossing of
    /// the part's mesh (the step's capped cut when the step cuts the part) on the segment from the pointer's start `p`
    /// to the centre, at the pose. So its head is not buried inside its own part. Any other tip, and a centre with no
    /// crossing on that segment (a ring's centre lies in its hole), is drawn where it is. The crossing is the
    /// watertight ray test of the anchor checks, in the part's frame; it reads every triangle of that one part.
    static func pointerTip(_ doc: MGSolidDocument, _ to: MGAnnotationPoint?, from p: MGVec3, pose: MGPose, step: Int?) -> MGVec3 {
        guard let to else { return .zero }
        let c = to.world(pose)
        guard case .centre(let id) = to.anchor, let part = doc.assembly.part(id) else { return c }
        var mesh = part.mesh
        if let i = step, doc.steps.indices.contains(i), let cut = doc.steps[i].section?.cuts[id] { mesh = cut.mesh }
        let t = pose.world[id] ?? .identity, inv = t.inverse
        let a = inv.apply(p), b = to.local
        guard (b - a).length > 1e-9, let ray = WatertightRay(a, b - a), mgSegmentMeetsBox(a, b - a, mesh.bounds) else { return c }
        let pos = mesh.positions
        var best: Double?
        for i in 0..<mesh.triangleCount {
            let (i0, i1, i2) = mesh.triangle(i)
            guard i0 < pos.count, i1 < pos.count, i2 < pos.count else { continue }
            if let s = ray.hit(pos[i0], pos[i1], pos[i2]), s > 1e-9, s < 1, s < (best ?? 1) { best = s }
        }
        guard let s = best else { return c }
        return t.apply(a + (b - a) * s)
    }

    static func segment(_ p: MGVec3, _ q: MGVec3, _ r: Double) -> MGAnnotationPrimitive {
        MGAnnotationPrimitive(shape: .cylinder, start: p, end: q, radius: r, hidden: (q - p).length < 1e-9)
    }

    /// The frame a turn arrow rides in: its part's world frame without the part's own joint turn.
    static func jointFrame(_ doc: MGSolidDocument, _ id: String, _ pose: MGPose) -> MGTransform {
        let w = pose.world[id] ?? .identity
        guard case .revolute(let axis)? = doc.assembly.part(id)?.joint else { return w }
        return w * .rotation(axis: axis, angle: -(pose.values[id] ?? 0))
    }

    /// Points of a turn arc (270° in the turn's sense) in the joint frame: the chord ends, then the head start and tip.
    static func turnArc(_ r: MGSolidArrow, axis: MGVec3, headLength: Double, sense: Double = 1) -> [MGVec3] {
        let n = axis.normalized
        let (e1, e2) = basis(n)
        let sweep = 1.5 * Double.pi, s = (r.turnSign ?? 1) * (sense < 0 ? -1 : 1)
        let headAngle = min(headLength / max(r.arcRadius, 1e-9), sweep / 2)
        func p(_ t: Double) -> MGVec3 { r.arcCentre + (e1 * cos(t) + e2 * (s * sin(t))) * r.arcRadius }
        var out = (0...arcChords).map { p(Double($0) * (sweep - headAngle) / Double(arcChords)) }
        out.append(p(sweep))
        return out
    }

    /// The pieces of one arrow or dimension in the posed kernel world. Their number never changes with the pose.
    /// Internal: renderers get pieces only through the checked paths (`MGSolidRenderer`, `MGSolidSnapshot.make`). A
    /// motion line arrow follows the exact velocity at the pose and hides while its anchor is still; a turn arrow rides its part's joint frame, so it does not spin with the part.
    /// `sense` −1 draws the motion of a view that plays the input backwards (`MGSolidView.motionSense`).
    /// `step`: the view's step (`MGSolidView.step`); motion arrows take its size (`MGSolidDocument.motionArrowDiagonal`).
    static func primitives(_ doc: MGSolidDocument, _ id: String, params: MGPoseParameters, sense: Double = 1,
                           step: Int? = nil) -> [MGAnnotationPrimitive] {
        let a = doc.annotations
        let pose = doc.assembly.pose(params)
        var sr = a.diagonal * MGSolidAnnotationLimits.shaftRadius
        let lr = a.diagonal * MGSolidAnnotationLimits.lineRadius
        if let r = a.arrow(id) {
            // Motion arrows (turn and line) are sized to the view's step focus, so a small spinning part in a close-up
            // keeps a small arrow; other arrows keep the model's size.
            let md = r.meaning == .motion ? doc.motionArrowDiagonal(step: step) : a.diagonal
            if r.meaning == .motion { sr = md * MGSolidAnnotationLimits.shaftRadius }
            switch (r.meaning, r.style) {
            case (.motion, .turn):
                guard let on = r.on, case .revolute(let axis)? = doc.assembly.part(on)?.joint else { return lineArrow(.zero, .zero, radius: sr) }
                let f = jointFrame(doc, on, pose)
                var sized = r
                if md != a.diagonal { sized.arcRadius = max(r.arcClearance, 8 * sr) }
                let pts = turnArc(sized, axis: axis, headLength: 4 * sr, sense: sense).map(f.apply)
                var out = (0..<arcChords).map { segment(pts[$0], pts[$0 + 1], sr) }
                out.append(MGAnnotationPrimitive(shape: .cone, start: pts[arcChords], end: pts[arcChords + 1], radius: 2.5 * sr, hidden: false))
                return out
            case (.motion, .line):
                guard let from = r.from else { return lineArrow(.zero, .zero, radius: sr) }
                let p = from.world(pose)
                let dir = MGSolidAnnotationMotion.direction(doc, from, pose, sense: sense)
                var length = r.length ?? 0
                if case .automatic = r.lengthSpec, md != a.diagonal { length = MGSolidAnnotationLimits.defaultLength * md }
                return lineArrow(p, p + (dir ?? .zero) * length, radius: sr, hidden: dir == nil)
            default:
                let p = r.from?.world(pose) ?? .zero
                let q = r.meaning == .pointer ? pointerTip(doc, r.to, from: p, pose: pose, step: step) : (r.to?.world(pose) ?? .zero)
                return lineArrow(p, q, radius: sr)
            }
        }
        guard let d = a.dimension(id) else { return [] }
        let pa = d.a.world(pose), pb = d.b.world(pose)
        if d.kind == .angle, let v = d.vertex?.world(pose) {
            let u = pa - v, w = pb - v
            let e1 = u.normalized
            var e2 = w - e1 * e1.dot(w)
            if e2.length < 1e-9 { e2 = basis(e1.length > 0 ? e1 : .unitX).0 }
            e2 = e2.normalized
            let theta = MGSolidAnnotationEngine.angle(u, w) * .pi / 180
            let rho = 0.35 * min(u.length, w.length)
            let pts = (0...arcChords).map { k -> MGVec3 in
                let t = theta * Double(k) / Double(arcChords)
                return v + (e1 * cos(t) + e2 * sin(t)) * rho
            }
            return [segment(v, pa, lr), segment(v, pb, lr)] + (0..<arcChords).map { segment(pts[$0], pts[$0 + 1], lr) }
        }
        let (start, end, extensions) = dimensionLine(d, pa, pb, a.diagonal)
        let u = (end - start).normalized
        var t = u.cross(.unitZ)
        if t.length < 1e-6 { t = u.cross(.unitX) }
        t = t.normalized * (5 * lr)
        return extensions.map { segment($0.0, $0.1, lr) } + [segment(start, end, lr), segment(start - t, start + t, lr), segment(end - t, end + t, lr)]
    }

    /// The dimension line (and, with `along`, its two extension lines): the line runs parallel to the axis, offset
    /// by 5 % of the bounding diagonal so it clears the measured points.
    static func dimensionLine(_ d: MGSolidDimension, _ pa: MGVec3, _ pb: MGVec3, _ diag: Double) -> (MGVec3, MGVec3, [(MGVec3, MGVec3)]) {
        guard let k = d.along else { return (pa, pb, []) }
        var c = pa
        switch k { case 0: c.x = pb.x; case 1: c.y = pb.y; default: c.z = pb.z }
        var n = pb - c
        if n.length < 1e-6 { n = k == 2 ? .unitX : .unitZ }
        let o = n.normalized * (0.05 * diag)
        // The line runs from a + o to c + o, parallel to the axis and as long as the measured component.
        let a1 = pa + o, c1 = c + o
        return (a1, c1, [(pa, a1), (pb, c1)])
    }

    /// Where the text of an annotation attaches (kernel world): a label's anchor, an arrow's midpoint (the arc's
    /// middle for a turn), a dimension line's midpoint (the arc's middle for an angle). Also the screen line the text
    /// is offset from (nil for labels and arcs).
    static func attach(_ doc: MGSolidDocument, _ id: String, _ pose: MGPose, _ params: MGPoseParameters,
                       sense: Double = 1, step: Int? = nil) -> (point: MGVec3, line: (MGVec3, MGVec3)?)? {
        let a = doc.annotations
        if let l = a.label(id) { return (l.at.world(pose), nil) }
        let prims = primitives(doc, id, params: params, sense: sense, step: step)
        if let r = a.arrow(id) {
            if r.style == .turn { let m = prims[arcChords / 2]; return (m.start, nil) }
            let p = prims[0].start, q = prims[1].end
            return ((p + q) * 0.5, (p, q))
        }
        if let d = a.dimension(id) {
            if d.kind == .angle { let m = prims[2 + arcChords / 2]; return (m.start, nil) }
            let line = prims[d.along == nil ? 0 : 2]
            return ((line.start + line.end) * 0.5, (line.start, line.end))
        }
        return nil
    }
}

// MARK: Piece meshes (render vertices with normals; exact counts)

extension MGAnnotationPrimitive {
    /// The piece as render triangles in the frame of `start`/`end` (empty when hidden).
    public var renderMesh: MGRenderMesh {
        guard !hidden else { return MGRenderMesh(positions: [], normals: [], indices: []) }
        let n = MGSolidAnnotations.segments
        let d = end - start, len = d.length
        let w = len > 1e-12 ? d * (1 / len) : MGVec3.unitZ
        let (u, v) = MGSolidAnnotations.basis(w)
        var pos: [MGVec3] = [], nor: [MGVec3] = [], idx: [UInt32] = []
        func ring(_ k: Int) -> MGVec3 { let t = 2 * Double.pi * Double(k) / Double(n); return u * cos(t) + v * sin(t) }
        switch shape {
        case .cylinder:
            for k in 0..<n { let r = ring(k); pos += [start + r * radius, end + r * radius]; nor += [r, r] }
            for k in 0..<n {
                let a = UInt32(2 * k), b = UInt32(2 * ((k + 1) % n))
                idx += [a, b, a + 1, b, b + 1, a + 1]
            }
            for (centre, normal, flip) in [(start, -w, true), (end, w, false)] {
                let c = UInt32(pos.count); pos.append(centre); nor.append(normal)
                for k in 0..<n { pos.append(centre + ring(k) * radius); nor.append(normal) }
                for k in 0..<n {
                    let a = c + 1 + UInt32(k), b = c + 1 + UInt32((k + 1) % n)
                    idx += flip ? [c, b, a] : [c, a, b]
                }
            }
        case .cone:
            let slope = radius / max(len, 1e-12)
            for k in 0..<n {
                let r = ring(k), sn = (r + w * slope).normalized
                pos += [start + r * radius, end]; nor += [sn, sn]
            }
            for k in 0..<n {
                let a = UInt32(2 * k), b = UInt32(2 * ((k + 1) % n))
                idx += [a, b, a + 1]
            }
            let c = UInt32(pos.count); pos.append(start); nor.append(-w)
            for k in 0..<n { pos.append(start + ring(k) * radius); nor.append(-w) }
            for k in 0..<n {
                let a = c + 1 + UInt32(k), b = c + 1 + UInt32((k + 1) % n)
                idx += [c, b, a]
            }
        }
        return MGRenderMesh(positions: pos, normals: nor, indices: idx)
    }
}

/// A gravity arrow drawn away from the assembly's centre of mass (docs/SOLID-3D.md, "Weight at the centre of mass"):
/// `annotation.arrow.weight.<id>`, a warning, with the centre-of-mass anchors that draw it from the centre.
public struct MGWeightPlacement: Equatable, Sendable {
    public let id: String
    /// The view that measured it: its 0-based step (nil: the plain view) and camera preset.
    public let step: Int?, camera: String
    /// How far (mm) the arrow's start lies from the centre of mass across that view (its depth along the view left
    /// out), and the most allowed.
    public let distance: Double, tolerance: Double
    /// The centre of mass at the rest pose (kernel world, mm), the authored vector (end minus start) and the start's
    /// depth offset from the centre along that view (kept, so the arrow stays in front of or behind the body as authored).
    public let centre: MGVec3, vector: MGVec3, depth: MGVec3

    public var reason: String { "annotation.arrow.weight.\(id)" }

    /// Set by the check reports, which apply the suggestion to a copy and check it again (`verifying`): nil before,
    /// true when the copy compiles, no longer warns for this arrow and shows it (no arrow issue in any still), false
    /// otherwise, with `unverified` saying why.
    public internal(set) var verified: Bool? = nil
    public internal(set) var unverified: String? = nil

    /// This placement with the report's re-check of its suggestion.
    func verifying(_ why: String?) -> MGWeightPlacement {
        var p = self; p.verified = why == nil; p.unverified = why; return p
    }

    /// `{"from": {"point": "centreOfMass", "offset": depth}, "to": {"point": "centreOfMass", "offset": depth + vector}}`
    /// at full precision (the applied suggestion keeps the authored vector exactly; a zero offset is left out).
    public var suggest: MGJSON {
        func end(_ o: MGVec3) -> MGJSON {
            let v = [o.x, o.y, o.z].map { $0 == 0 ? 0 : $0 }
            return v.allSatisfy { $0 == 0 } ? .object(["point": .string("centreOfMass")])
                : .object(["point": .string("centreOfMass"), "offset": .array(v.map { .number($0) })])
        }
        return .object(["from": end(depth), "to": end(depth + vector)])
    }

    var viewName: String { step.map { "step \($0 + 1)" } ?? "the plain view" }

    public var repair: String {
        if verified == false {
            let line = "Weight arrow \(id) starts \(MGAnnotationAnchorIssue.number(distance)) mm from the centre of mass across \(viewName) "
                + "(`\(camera)`; at most \(MGAnnotationAnchorIssue.number(tolerance)) mm): weight acts at the centre of mass. No checked suggestion: "
                + "drawn from the centre with its depth, \(unverified ?? "it does not pass"). Draw it from {\"point\": \"centreOfMass\"} with an offset toward the camera."
            return MGAnnotationAnchorIssue.bounded(line, MGAnnotationAnchorIssue.repairScalars)
        }
        let line = "Weight arrow \(id) starts \(MGAnnotationAnchorIssue.number(distance)) mm from the centre of mass across \(viewName) "
            + "(`\(camera)`; at most \(MGAnnotationAnchorIssue.number(tolerance)) mm): weight acts at the centre of mass. Use \(MGAnnotationAnchorIssue.compactExact(suggest))."
        return MGAnnotationAnchorIssue.bounded(line, MGAnnotationAnchorIssue.repairScalars)
    }

    /// `{"id", "reason", "step", "camera", "distance", "tolerance", "centreOfMass": [x, y, z], "suggest", "verified",
    /// "repair"}` (measures to 0.001 mm; `step` 1-based, null for the plain view; `suggest` at full precision, null when
    /// the re-check refused it; `verified` null when no re-check ran).
    public var json: MGJSON {
        func r(_ x: Double) -> MGJSON { x.isFinite ? .number((x * 1000).rounded() / 1000) : .null }
        return .object(["id": .string(id), "reason": .string(reason), "step": step.map { .number(Double($0 + 1)) } ?? .null,
                        "camera": .string(camera), "distance": r(distance), "tolerance": r(tolerance),
                        "centreOfMass": .array([r(centre.x), r(centre.y), r(centre.z)]), "suggest": verified == false ? .null : suggest,
                        "verified": verified.map(MGJSON.bool) ?? .null, "repair": .string(repair)])
    }
}

extension MGSolidDocument {
    /// Share of the model's bounding diagonal by which a gravity arrow's start may miss the centre of mass across a view.
    public static let weightShare = 0.05

    /// The centre of mass of the whole assembly at the rest pose (default input, explode 0; `MGMassProperties.shares`).
    public var restCentreOfMass: MGVec3? {
        let shares = MGMassProperties.shares(assembly)
        guard !shares.isEmpty else { return nil }
        let rest = assembly.pose(MGPoseParameters(input: defaults.input, explode: 0))
        var c = MGVec3.zero
        for m in shares { c = c + (rest.world[m.part] ?? .identity).apply(m.centroid) * m.share }
        return c.x.isFinite && c.y.isFinite && c.z.isFinite ? c : nil
    }

    /// Gravity force arrows (`"cause": "gravity"`) with no centre-of-mass end, placed off the body (no end on a part,
    /// or a tail (`arrowTail`) farther from its part's box than the off-part tolerance `max(partShare × that box's
    /// diagonal, modelShare × the model's diagonal)`), whose start, at the rest pose, lies farther than `weightShare` ×
    /// the model's bounding diagonal from the centre of mass across a view that shows the arrow: the offset with its
    /// component along the view's direction left out (the steps that show it, each at its camera preset and orbit; the
    /// plain view, `hero`, when no step does). Depth is left out because an arrow drawn in front of (or behind) the
    /// body at the centre's place on screen reads right and stays visible; a weight drawn at a thigh does not. The first
    /// such view (step order) is reported. A warning, never a refusal; the suggestion draws the arrow from the centre of
    /// mass with the authored vector and the authored depth offset along that view. Deterministic.
    public var weightPlacements: [MGWeightPlacement] {
        let gravity = annotations.arrows.filter { $0.meaning == .force && $0.cause == "gravity" }
        guard !gravity.isEmpty, let c = restCentreOfMass else { return [] }
        let rest = assembly.pose(MGPoseParameters(input: defaults.input, explode: 0))
        let tol = MGSolidDocument.weightShare * annotations.diagonal
        let back = MGSolidStage.zUpToYUp.inverse
        var out: [MGWeightPlacement] = []
        for r in gravity {
            guard let f = r.from, let t = r.to, !f.isCentreOfMass, !t.isCentreOfMass else { continue }
            // An arrow on its part is that part's weight (a hanging load): only a weight placed off the body is measured.
            if let tail = arrowTail(r), let b = assembly.part(tail.part)?.mesh.bounds, !b.isEmpty,
               tail.distance <= Swift.max(MGAnnotationAnchorRules.partShare * b.size.length, MGAnnotationAnchorRules.modelShare * annotations.diagonal) {
                continue
            }
            let p = f.world(rest), v = t.world(rest) - p
            guard v.length.isFinite, v.length > 1e-9 else { continue }
            var views: [(step: Int?, camera: String, yaw: Double, pitch: Double)] = []
            for i in steps.indices where visibleAnnotations(step: i).contains(r.id) {
                let name = steps[i].camera ?? "hero", d = MGSolidCamera.presets[name] ?? MGSolidCamera.presets["hero"]!
                views.append((i, name, d.yaw + steps[i].orbit, d.pitch))
            }
            if views.isEmpty, visibleAnnotations(step: nil).contains(r.id), let d = MGSolidCamera.presets["hero"] { views.append((nil, "hero", d.yaw, d.pitch)) }
            let w = p - c
            for view in views {
                let fwd = back.applyVector(MGSolidFraming.Basis(yaw: view.yaw, pitch: view.pitch).fwd).normalized
                let depth = fwd * w.dot(fwd)
                let across = (w - depth).length
                guard across.isFinite, across > tol else { continue }
                out.append(MGWeightPlacement(id: r.id, step: view.step, camera: view.camera, distance: across, tolerance: tol, centre: c,
                                             vector: v, depth: depth))
                break
            }
        }
        return out
    }
}
