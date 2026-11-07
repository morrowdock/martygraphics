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
    /// Filled text and `unchecked` text, in Unicode scalars. Authored text before filling may be up to
    /// `rawTextFactor` times `text`.
    public static let text = 40, unchecked = 60, rawTextFactor = 4
    /// Input samples per turn for motion arrow directions and dimension `over` ranges.
    public static let samples = 720
    /// A motion arrow on a still anchor looks this many samples ahead (1/8 turn) while a view plays.
    public static let lookAhead = 90
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
}

/// A resolved anchor: a point in a part's frame (it moves with the part in every pose) or a fixed world point.
public struct MGAnnotationPoint: Equatable, Sendable {
    public let anchor: MGAnnotationAnchor
    /// The part the point rides on; nil for a world point.
    public var part: String? {
        switch anchor {
        case .part(let p), .offset(let p, _), .centre(let p): return p
        case .world: return nil
        }
    }
    /// The point in the part's frame, or the world point.
    public internal(set) var local: MGVec3

    /// The point in the posed kernel world (Z up, mm).
    public func world(_ pose: MGPose) -> MGVec3 {
        guard let p = part else { return local }
        return (pose.world[p] ?? .identity).apply(local)
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
            guard case .array(let a) = v, a.count <= max else { throw MGSolidIssue(reason) }
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
        for e in labels {
            guard case .object(let lo) = e else { throw MGSolidIssue("label.object") }
            try MGSolidParser.closed(lo, ["id", "at", "text"], ["unchecked"], "label")
            let id = try identify(lo, "label")
            do {
                let at = try anchor(lo["at"]!, names, owner: id)
                let template = try text(lo["text"]!, "label.text.\(id)")
                let unchecked = try lo["unchecked"].map { try MGSolidParser.text($0, L.unchecked, "label.unchecked.\(id)") }
                out.labels.append(MGSolidLabel(id: id, at: at, template: template, text: template, unchecked: unchecked))
            } catch let e as MGSolidIssue { throw e.part == nil ? MGSolidIssue(e.reason, part: id) : e }
        }
        for e in arrows {
            guard case .object(let ao) = e else { throw MGSolidIssue("arrow.object") }
            try MGSolidParser.closed(ao, ["id", "meaning"], ["text", "unchecked", "on", "style", "sense", "from", "to", "expect", "length", "cause"], "arrow")
            let id = try identify(ao, "arrow")
            do { out.arrows.append(try arrow(ao, id, names)) }
            catch let e as MGSolidIssue { throw e.part == nil ? MGSolidIssue(e.reason, part: id) : e }
        }
        for e in dimensions {
            guard case .object(let d) = e else { throw MGSolidIssue("dimension.object") }
            try MGSolidParser.closed(d, ["id", "a", "b"], ["kind", "vertex", "along", "over", "text"], "dimension")
            let id = try identify(d, "dimension")
            do { out.dimensions.append(try dimension(d, id, names)) }
            catch let e as MGSolidIssue { throw e.part == nil ? MGSolidIssue(e.reason, part: id) : e }
        }
        return out
    }

    /// Authored annotation text: the solid text rule, at most `rawTextFactor × text` scalars before filling.
    static func text(_ v: MGJSON, _ reason: String) throws -> String {
        try MGSolidParser.text(v, L.text * L.rawTextFactor, reason)
    }

    static func vector3(_ v: MGJSON?, _ reason: String) throws -> MGVec3 {
        guard case .array(let a)? = v, a.count == 3 else { throw MGSolidIssue(reason) }
        return MGVec3(try MGSolidParser.num(a[0], MGSolidLimits.coordinate, reason), try MGSolidParser.num(a[1], MGSolidLimits.coordinate, reason),
                      try MGSolidParser.num(a[2], MGSolidLimits.coordinate, reason))
    }

    /// `"p"`, `{"part": "p", "offset": [x, y, z]}`, `{"part": "p", "point": "centre"}` or `{"world": [x, y, z]}`.
    static func anchor(_ v: MGJSON, _ names: Names, owner: String) throws -> MGAnnotationPoint {
        switch v {
        case .string(let ref):
            return MGAnnotationPoint(anchor: .part(try names.part(ref, owner: owner)), local: .zero)
        case .object(let o):
            let keys = Set(o.keys)
            if keys == ["world"] { return MGAnnotationPoint(anchor: .world(try vector3(o["world"], "anchor.world")), local: try vector3(o["world"], "anchor.world")) }
            guard case .string(let ref)? = o["part"], keys == ["part", "offset"] || keys == ["part", "point"] else { throw MGSolidIssue("anchor.form") }
            if keys.contains("offset") {
                let off = try vector3(o["offset"], "anchor.offset")
                return MGAnnotationPoint(anchor: .offset(part: try names.part(ref, owner: owner), off), local: off)
            }
            guard o["point"] == .string("centre") else { throw MGSolidIssue("anchor.point") }
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
        let from = try o["from"].map { try anchor($0, names, owner: id) }
        let to = try o["to"].map { try anchor($0, names, owner: id) }
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
        let template = try o["text"].map { try text($0, "arrow.text.\(id)") }
        let unchecked = try o["unchecked"].map { try MGSolidParser.text($0, L.unchecked, "arrow.unchecked.\(id)") }
        // `unchecked` marks the arrow's text; without text it would mark nothing.
        if unchecked != nil, template == nil { throw MGSolidIssue("arrow.unchecked.\(id)") }
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
        let template = try o["text"].map { try text($0, "dimension.text.form.\(id)") } ?? "{dim.\(id)}"
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
    static func checkVisibility(_ a: inout MGSolidAnnotations, _ steps: [MGSolidStep]) throws {
        let ids = Set(a.ids)
        a.stepped = steps.contains { $0.annotate != nil }
        for s in steps {
            for id in s.annotate ?? [] where !ids.contains(id) { throw MGSolidIssue("step.annotate.ref.\(MGSolidParser.token(id))") }
        }
        if !a.stepped, a.ids.count > L.visible { throw MGSolidIssue("annotations.visible") }
    }

    /// Mesh centres, the model scale, turn arcs and every dimension value (facts `dim.<id>`), before text is filled.
    static func prepare(_ doc: inout MGSolidDocument) throws {
        guard !doc.annotations.isEmpty else { return }
        var a = doc.annotations
        func resolve(_ p: inout MGAnnotationPoint) {
            if case .centre(let id) = p.anchor { p.local = doc.assembly.part(id)?.mesh.bounds.center ?? .zero }
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

    /// One dimension value: |b − a| (or one world component with `along`) or the angle at the vertex, at the default
    /// input with explode 0; with `over`, largest minus smallest over one input turn (720 samples, ends included).
    static func measure(_ d: inout MGSolidDimension, _ doc: MGSolidDocument) throws {
        func value(_ pose: MGPose) throws -> Double {
            let pa = d.a.world(pose), pb = d.b.world(pose)
            if d.kind == .angle, let v = d.vertex?.world(pose) {
                let u = pa - v, w = pb - v
                guard u.length >= L.minDimension, w.length >= L.minDimension else { throw MGSolidIssue("dimension.zero.\(d.id)", part: d.id) }
                let c = max(-1, min(1, u.dot(w) / (u.length * w.length)))
                return acos(c) * 180 / .pi
            }
            let delta = pb - pa
            if let k = d.along { return abs([delta.x, delta.y, delta.z][k]) }
            return delta.length
        }
        let at = try value(doc.assembly.pose(MGPoseParameters(input: doc.defaults.input, explode: 0)))
        let parts = [d.a.part, d.b.part, d.vertex?.part].compactMap { $0 }
        let chain = parts.compactMap(doc.chainTier).min()
        if d.over {
            guard chain != nil else { throw MGSolidIssue("dimension.over.\(d.id)", part: d.id) }
            var lo = Double.infinity, hi = -Double.infinity
            for k in 0...L.samples {
                let v = try value(doc.assembly.pose(MGPoseParameters(input: 2 * .pi * Double(k) / Double(L.samples), explode: 0)))
                lo = min(lo, v); hi = max(hi, v)
            }
            d.value = hi - lo
            if d.kind == .distance, d.value < L.minDimension { throw MGSolidIssue("dimension.zero.\(d.id)", part: d.id) }
            d.tier = chain ?? .solved
        } else {
            if d.kind == .distance, at < L.minDimension { throw MGSolidIssue("dimension.zero.\(d.id)", part: d.id) }
            d.value = at
            // At input 0 no drive speed affects the pose; at another default input the pose depends on the drive chain.
            d.tier = doc.defaults.input == 0 ? .solved : (chain ?? .solved)
        }
    }

    /// The motion direction of a part anchor at input `u` (unit, kernel world), or nil while it is still: the velocity
    /// (central difference); when that is zero (a piston at dead centre), the first non-zero velocity within
    /// `ahead` samples of 1/720 turn.
    static func velocityDirection(_ doc: MGSolidDocument, _ p: MGAnnotationPoint, input u: Double, explode: Double, ahead: Int) -> MGVec3? {
        let h = 1e-4
        let still = 1e-9 * max(1, doc.annotations.diagonal)
        for k in 0...max(0, ahead) {
            let x = u + 2 * .pi * Double(k) / Double(L.samples)
            let d = p.world(doc.assembly.pose(MGPoseParameters(input: x + h, explode: explode)))
                - p.world(doc.assembly.pose(MGPoseParameters(input: x - h, explode: explode)))
            if d.length > still, d.x.isFinite, d.y.isFinite, d.z.isFinite { return d.normalized }
        }
        return nil
    }

    static func angle(_ a: MGVec3, _ b: MGVec3) -> Double {
        let c = a.normalized.dot(b.normalized)
        return acos(max(-1, min(1, c))) * 180 / .pi
    }

    /// Fills one annotation text. `abs` is refused: no step proves a sign for an annotation (`text.sign.<name>`).
    static func fill(_ template: String, _ w: String, n1: Bool, _ doc: MGSolidDocument, tooLong: String) throws -> MGSolidFilledText {
        let filled = try MGSolidFacts.fill(template, where: w, n1: n1, doc.facts, doc.aliases)
        for (name, mods) in zip(filled.facts, filled.modifiers) where mods.contains("abs") { throw MGSolidIssue("text.sign.\(MGSolidParser.token(name))") }
        guard !filled.text.trimmingCharacters(in: .whitespaces).isEmpty, filled.text.unicodeScalars.count <= L.text else { throw MGSolidIssue(tooLong) }
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
                let f = try fill(l.template, "label.\(l.id)", n1: l.unchecked == nil, doc, tooLong: "label.text.\(l.id)")
                l.text = f.text; l.facts = f.facts
                l.tier = MGSolidTiers.text(facts: f.facts.compactMap { doc.facts[$0] }, unchecked: l.unchecked != nil)
            } catch let e as MGSolidIssue { throw MGSolidIssue(e.reason, part: l.id) }
            a.labels[i] = l
        }
        for i in a.arrows.indices {
            var r = a.arrows[i]
            do { try check(&r, doc, rest) } catch let e as MGSolidIssue { throw MGSolidIssue(e.reason, part: r.id) }
            a.arrows[i] = r
        }
        for i in a.dimensions.indices {
            var d = a.dimensions[i]
            do {
                let f = try fill(d.template, "dimension.\(d.id)", n1: true, doc, tooLong: "dimension.text.form.\(d.id)")
                guard f.facts.contains(d.factName) else { throw MGSolidIssue("dimension.text.\(d.id)") }
                d.text = f.text; d.facts = f.facts
                d.tier = min(d.tier, f.facts.compactMap { doc.facts[$0]?.tier }.min() ?? .solved)
            } catch let e as MGSolidIssue { throw MGSolidIssue(e.reason, part: d.id) }
            a.dimensions[i] = d
        }
        doc.annotations = a
    }

    static func check(_ r: inout MGSolidArrow, _ doc: MGSolidDocument, _ rest: MGPose) throws {
        var textTier: MGSolidTier?
        if let t = r.template {
            let f = try fill(t, "arrow.\(r.id)", n1: r.unchecked == nil, doc, tooLong: "arrow.text.\(r.id)")
            r.text = f.text; r.facts = f.facts
            textTier = MGSolidTiers.text(facts: f.facts.compactMap { doc.facts[$0] }, unchecked: r.unchecked != nil)
        }
        var base: MGSolidTier?
        switch (r.meaning, r.style) {
        case (.motion, .turn):
            guard let id = r.on, let part = doc.assembly.part(id) else { throw MGSolidIssue("arrow.turn.joint.\(r.id)") }
            guard case .revolute = part.joint else { throw MGSolidIssue("arrow.turn.joint.\(r.id)") }
            guard doc.ownMotion(id) else { throw MGSolidIssue("arrow.still.\(r.id)") }
            // A turn arrow claims one sense for the whole view, so the part must turn at a steady rate: a linear drive
            // with a speed fact. A crank rod swings back and forth (`arrow.turn.steady.<id>`; use a motion line arrow).
            guard let s = doc.facts[id + ".worldSpeed"]?.value ?? doc.facts[id + ".speed"]?.value else {
                throw MGSolidIssue("arrow.turn.steady.\(r.id)")
            }
            guard s != 0, s.isFinite else { throw MGSolidIssue("arrow.still.\(r.id)") }
            r.turnSign = s > 0 ? 1 : -1
            if let stated = r.sense, (stated == "ccw") != (s > 0) { throw MGSolidIssue("arrow.sense.\(r.id)") }
            base = doc.motionTier(id)
        case (.motion, .line):
            guard let from = r.from, let part = from.part else { throw MGSolidIssue("arrow.from.\(r.id)") }
            guard let dir = velocityDirection(doc, from, input: doc.defaults.input, explode: 0, ahead: L.samples) else {
                throw MGSolidIssue("arrow.still.\(r.id)")
            }
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

    /// `annotation.unused.<id>` (some step uses `annotate`, no step shows it; strict refuses) and
    /// `annotation.cut.<id>` (a part anchor lies in the half that the same step's section removes; a warning only),
    /// in authored order.
    static func warnings(_ doc: MGSolidDocument) -> [MGSolidIssue] {
        let a = doc.annotations
        guard !a.isEmpty else { return [] }
        var shown = Set<String>()
        for i in doc.steps.indices { shown.formUnion(doc.visibleAnnotations(step: i)) }
        let rest = doc.assembly.pose(MGPoseParameters(input: doc.defaults.input, explode: 0))
        var out: [MGSolidIssue] = []
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
    static func turnArc(_ r: MGSolidArrow, axis: MGVec3, headLength: Double) -> [MGVec3] {
        let n = axis.normalized
        let (e1, e2) = basis(n)
        let sweep = 1.5 * Double.pi, s = r.turnSign ?? 1
        let headAngle = min(headLength / max(r.arcRadius, 1e-9), sweep / 2)
        func p(_ t: Double) -> MGVec3 { r.arcCentre + (e1 * cos(t) + e2 * (s * sin(t))) * r.arcRadius }
        var out = (0...arcChords).map { p(Double($0) * (sweep - headAngle) / Double(arcChords)) }
        out.append(p(sweep))
        return out
    }

    /// The pieces of one arrow or dimension in the posed kernel world. Their number never changes with the pose.
    /// A motion line arrow follows the engine velocity at the pose (looking 1/8 turn ahead at a dead centre) and
    /// hides while its anchor is still; a turn arrow rides its part's joint frame, so it does not spin with the part.
    public static func primitives(_ doc: MGSolidDocument, _ id: String, params: MGPoseParameters) -> [MGAnnotationPrimitive] {
        let a = doc.annotations
        let pose = doc.assembly.pose(params)
        let sr = a.diagonal * MGSolidAnnotationLimits.shaftRadius, lr = a.diagonal * MGSolidAnnotationLimits.lineRadius
        if let r = a.arrow(id) {
            switch (r.meaning, r.style) {
            case (.motion, .turn):
                guard let on = r.on, case .revolute(let axis)? = doc.assembly.part(on)?.joint else { return lineArrow(.zero, .zero, radius: sr) }
                let f = jointFrame(doc, on, pose)
                let pts = turnArc(r, axis: axis, headLength: 4 * sr).map(f.apply)
                var out = (0..<arcChords).map { segment(pts[$0], pts[$0 + 1], sr) }
                out.append(MGAnnotationPrimitive(shape: .cone, start: pts[arcChords], end: pts[arcChords + 1], radius: 2.5 * sr, hidden: false))
                return out
            case (.motion, .line):
                guard let from = r.from else { return lineArrow(.zero, .zero, radius: sr) }
                let p = from.world(pose)
                let dir = MGSolidAnnotationEngine.velocityDirection(doc, from, input: params.input, explode: params.explode,
                                                                    ahead: MGSolidAnnotationLimits.lookAhead)
                return lineArrow(p, p + (dir ?? .zero) * (r.length ?? 0), radius: sr, hidden: dir == nil)
            default:
                return lineArrow(r.from?.world(pose) ?? .zero, r.to?.world(pose) ?? .zero, radius: sr)
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
        let a1 = pa + o, c1 = c + o + (pb - c)
        return (a1, c1, [(pa, a1), (pb, c1)])
    }

    /// Where the text of an annotation attaches (kernel world): a label's anchor, an arrow's midpoint (the arc's
    /// middle for a turn), a dimension line's midpoint (the arc's middle for an angle). Also the screen line the text
    /// is offset from (nil for labels and arcs).
    static func attach(_ doc: MGSolidDocument, _ id: String, _ pose: MGPose, _ params: MGPoseParameters) -> (point: MGVec3, line: (MGVec3, MGVec3)?)? {
        let a = doc.annotations
        if let l = a.label(id) { return (l.at.world(pose), nil) }
        let prims = primitives(doc, id, params: params)
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
