// SPDX-License-Identifier: Apache-2.0
import Foundation

/// Hard limits for the solid assembly format v1. Input outside them is rejected, never clamped.
public enum MGSolidLimits {
    public static let bytes = 64 * 1024
    /// Wire parts (before `repeat`) and resolved parts (after).
    public static let parts = 48, resolvedParts = 96
    /// Wire parts (before `repeat`) after component expansion: authored entries plus every part the `use` instances
    /// make (`parts.count` above it). The resolved limit (`resolvedParts`) still applies after `repeat`.
    public static let expandedParts = 96
    public static let shapesPerPart = 8, repeatCount = 12
    public static let profilePoints = 256, profileHoles = 16, plateHoles = 32
    public static let constraints = 128, steps = 16, idsPerStep = 16
    public static let title = 80, name = 60, say = 240
    /// v2: the reason text of an `unchecked` caption, and claim checks per step.
    public static let unchecked = 60, checksPerStep = 8
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
    /// Repair detail of `annotations.visible` (nil for every other reason).
    public let visibility: MGAnnotationVisibilityDetail?
    /// Repair detail of a length, count or size limit (the report's `limit`; `parts.resolved` adds its instances); nil
    /// for every other reason.
    public let limit: MGSolidLimitDetail?
    public init(_ reason: String, part: String? = nil) { self.reason = reason; self.part = part; visibility = nil; limit = nil }
    /// A limit reason with its repair detail (nil when the refusal had another cause).
    public init(_ reason: String, part: String? = nil, limit: MGSolidLimitDetail?) {
        self.reason = reason; self.part = part; visibility = nil; self.limit = limit
    }
    private init(reason: String, part: String?, visibility: MGAnnotationVisibilityDetail?, limit: MGSolidLimitDetail?) {
        self.reason = reason; self.part = part; self.visibility = visibility; self.limit = limit
    }
    /// The same issue with `prefix` before its limit field (a step's issue in the document: `steps[2].`).
    func prefixed(_ prefix: String) -> MGSolidIssue {
        guard let l = limit else { return self }
        return MGSolidIssue(reason: reason, part: part, visibility: visibility, limit: l.prefixed(prefix))
    }
    /// `annotations.visible` with its repair detail; `part` is the detail's annotation id.
    public init(visibility v: MGAnnotationVisibilityDetail) { reason = "annotations.visible"; part = v.annotation; visibility = v; limit = nil }
    /// Another visibility reason (`step.annotate.count`, `view.annotate.count`) with its repair detail.
    public init(_ reason: String, visibility v: MGAnnotationVisibilityDetail) {
        self.reason = reason; part = v.annotation; visibility = v; limit = nil
    }
    /// `parts.resolved` with its repair detail (no part: the whole document is over the limit).
    public init(limit l: MGSolidLimitDetail) { reason = "parts.resolved"; part = nil; visibility = nil; limit = l }
    public var description: String { part.map { "\(reason) (\($0))" } ?? reason }
}

/// Why the annotation visibility limit refused a document, as report fields (`visibility`): the first annotation over
/// the limit (in authored order, or in the step's or beat's `annotate` list), the number that would show at once, the
/// limit, the cause, and the step or beat (1-based in JSON) when one step or beat is at fault. The reason itself stays
/// one token (`annotations.visible`, `step.annotate.count`, `view.annotate.count`).
public struct MGAnnotationVisibilityDetail: Equatable, Sendable {
    public enum Cause: String, Equatable, Sendable {
        /// The document has no step, so the plain view shows every annotation (in an explainer: the solid statement,
        /// which is checked before any beat view and may not have steps).
        case noSteps = "nosteps"
        /// The document has steps, but none uses `annotate`, so the plain view and every step show every annotation.
        case unannotated
        /// One step's `annotate` lists more than the limit (`step.annotate.count`; `step` names it).
        case step
        /// One explainer beat's `view.annotate` lists more than the limit (`view.annotate.count`; `beat` names it).
        case beat
    }
    public let annotation: String
    public let count: Int
    public let limit: Int
    public let cause: Cause
    /// The step (cause `step`) or beat (cause `beat`) at fault, 0-based; nil when no single one is.
    public let index: Int?

    public init(annotation: String, count: Int, limit: Int, cause: Cause, index: Int? = nil) {
        self.annotation = String(annotation.unicodeScalars.prefix(64)); self.count = count; self.limit = limit; self.cause = cause
        self.index = index
    }

    /// The same numbers as a limit detail (the report's `limit`): the list over the limit (`annotations`, a step's
    /// `annotate` or a beat's `view.annotate`; `prefix` goes before `annotations`), the count and the limit.
    public func limitDetail(prefix: String = "") -> MGSolidLimitDetail {
        let field: String
        switch cause {
        case .step: field = index.map { "steps[\($0)].annotate" } ?? "steps.annotate"
        case .beat: field = index.map { "beats[\($0)].view.annotate" } ?? "beats.view.annotate"
        case .noSteps, .unannotated: field = prefix + "annotations"
        }
        return MGSolidLimitDetail(field: field, actual: count, limit: limit, unit: "annotations")
    }

    /// This detail for step or beat `i` (0-based) with `cause`.
    func at(_ i: Int, cause: Cause) -> MGAnnotationVisibilityDetail {
        MGAnnotationVisibilityDetail(annotation: annotation, count: count, limit: limit, cause: cause, index: i)
    }

    /// `{"annotation", "cause", "count", "limit"}`, plus `"step"` (cause `step`) or `"beat"` (cause `beat`), 1-based.
    public var json: MGJSON {
        var o: [String: MGJSON] = ["annotation": .string(annotation), "cause": .string(cause.rawValue), "count": .number(Double(count)),
                                   "limit": .number(Double(limit))]
        if let index, cause == .step || cause == .beat { o[cause.rawValue] = .number(Double(index + 1)) }
        return .object(o)
    }
}

/// Repair detail of a refusal from a length, count or size limit (the report's `limit`): the field it concerns, the
/// value the engine measured (`actual`), the limit, the unit, and the smallest allowed value when a value below it is
/// refused too (an empty text of `1–60` characters). `parts.resolved` (the number of parts after `use` and `repeat`
/// expansion against `MGSolidLimits.resolvedParts`) also lists the component instances (`use` ids) that add the most
/// parts, with their resolved part counts, most first, ties by id, at most `maxContributors` (`top`). The reason itself
/// stays one token.
public struct MGSolidLimitDetail: Equatable, Sendable {
    /// One component instance: its `use` id, the component it uses and the parts it resolved to.
    public struct Contributor: Equatable, Sendable {
        public let id: String
        public let component: String
        public let parts: Int
        public init(id: String, component: String, parts: Int) {
            self.id = String(id.unicodeScalars.prefix(64)); self.component = String(component.unicodeScalars.prefix(64)); self.parts = parts
        }
    }
    /// Most instances listed in `top`.
    public static let maxContributors = 5
    /// Longest `field`, in Unicode scalars.
    public static let maxField = 128
    /// The measured value (`actual` in JSON; `count` too for `parts.resolved`).
    public let count: Int
    public let limit: Int
    public let top: [Contributor]
    /// A path into the document: object keys joined by `.`, array entries as `[i]` (0-based), for example `title`,
    /// `beats[2].say`, `solid.annotations.labels[4].text`; a part a component made is `parts[id=<id>]`. At most
    /// `maxField` scalars of ASCII letters, digits, `_`, `.`, `[`, `]` and `=` (anything else becomes `_`).
    public let field: String
    /// What is counted: `characters` (Unicode scalars), `entries`, `bytes`, `triangles`, `vertices`, `levels`, `nodes`,
    /// `parts`, `annotations`, `statements`, `beats`, `frames` or `scalars`.
    public let unit: String
    /// The smallest allowed value, when a value below it is refused too; nil otherwise.
    public let minimum: Int?
    /// False when the engine stopped counting at the first value over the limit (a bounded walk), so `actual` is a
    /// lower bound (`limit + 1`), not the full count.
    public let exact: Bool
    /// True for `parts.resolved` (the JSON keeps its `count` and `top`).
    let contributors: Bool

    /// The value the engine measured.
    public var actual: Int { count }

    /// `parts.resolved`: `top` is sorted (most parts first, then id) and cut to `maxContributors`.
    public init(count: Int, limit: Int, top: [Contributor]) {
        self.count = count; self.limit = limit
        self.top = Array(top.sorted { $0.parts != $1.parts ? $0.parts > $1.parts : $0.id < $1.id }.prefix(MGSolidLimitDetail.maxContributors))
        field = "parts"; unit = "parts"; minimum = nil; contributors = true; exact = true
    }

    /// Any other limit: `field` is sanitised and cut to `maxField` scalars.
    public init(field: String, actual: Int, limit: Int, unit: String, minimum: Int? = nil, exact: Bool = true) {
        count = actual; self.limit = limit; top = []; contributors = false; self.unit = unit; self.minimum = minimum; self.exact = exact
        let f = String(field.unicodeScalars.prefix(MGSolidLimitDetail.maxField).map { u -> Character in
            u.isASCII && (CharacterSet.alphanumerics.contains(u) || "_.[]=".unicodeScalars.contains(u)) ? Character(u) : "_"
        })
        self.field = f.isEmpty ? "_" : f
    }

    /// The same detail with `prefix` before its field (`solid.` for an explainer's solid).
    func prefixed(_ prefix: String) -> MGSolidLimitDetail {
        if contributors { return self }
        return MGSolidLimitDetail(field: prefix + field, actual: count, limit: limit, unit: unit, minimum: minimum, exact: exact)
    }

    /// `{"field", "actual", "limit", "unit"}`, plus `"minimum"` when set and `"exact": false` for a lower bound;
    /// `parts.resolved` also keeps
    /// `{"count", "top": [{"id", "use", "parts"}]}` (`use`: the component id).
    public var json: MGJSON {
        var o: [String: MGJSON] = ["field": .string(field), "actual": .number(Double(count)), "limit": .number(Double(limit)), "unit": .string(unit)]
        if let minimum { o["minimum"] = .number(Double(minimum)) }
        if !exact { o["exact"] = .bool(false) }
        if contributors {
            o["count"] = .number(Double(count))
            o["top"] = .array(top.map { .object(["id": .string($0.id), "use": .string($0.component), "parts": .number(Double($0.parts))]) })
        }
        return .object(o)
    }

    /// One line: `title has 87 characters; the limit is 80. Shorten it to at most 80 characters.`
    public var repair: String {
        func n(_ i: Int) -> String {
            let digits = String(i.magnitude)
            var out = ""
            for (k, c) in digits.enumerated() { if k > 0, (digits.count - k) % 3 == 0 { out.append(",") }; out.append(c) }
            return (i < 0 ? "-" : "") + out
        }
        if let minimum, count < minimum {
            return "\(field) has \(n(count)) \(unit); it needs \(n(minimum)) to \(n(limit)) \(unit)."
        }
        let verb: String
        switch unit {
        case "characters", "scalars": verb = "Shorten it to at most"
        case "bytes": verb = "Make it at most"
        default: verb = "Use at most"
        }
        let over = count - limit
        let has = exact ? "has \(n(count))" : "has more than \(n(limit))"
        var line = "\(field) \(has) \(unit); the limit is \(n(limit)). \(verb) \(n(limit)) \(unit)"
        if exact, over > 0, unit != "bytes" { line += " (\(n(over)) fewer)" }
        return line + "."
    }
}

/// One authored step of an explainer.
public struct MGSolidStep: Equatable, Sendable {
    /// What the learner sees: in assembly v2 with every `{placeholder}` filled from engine facts.
    public internal(set) var say: String
    public internal(set) var focus: [String]
    public internal(set) var highlight: [String]
    public internal(set) var explode: Double?
    public internal(set) var camera: String?
    /// Extra yaw in degrees added to the camera preset.
    public internal(set) var orbit: Double
    /// Input turns played during the step (for example to show the gears running).
    public internal(set) var spin: Double
    /// The authored text before placeholders are filled (equal to `say` in v1).
    public internal(set) var template: String = ""
    /// v2: the author's reason when the caption's numbers are not engine facts (`"unchecked": "…"`).
    public internal(set) var unchecked: String?
    /// v2: claims the engine proved before accepting the document.
    public internal(set) var checks: [MGSolidClaimCheck] = []
    /// v2: canonical names of the facts the caption shows, in order.
    public internal(set) var facts: [String] = []
    /// Engine-computed caption tier; nil when the caption shows and checks no engine number (see docs/SOLID-3D.md).
    public internal(set) var tier: MGSolidTier?
    /// v2: a capped plane cut of some parts, shown during this step.
    public internal(set) var section: MGSolidStepSection?
    /// v2: parts shown see-through during this step (opacity `MGSolidView.ghostOpacity`), in part order.
    public internal(set) var ghost: [String] = []
    /// v2: the annotations this step shows (0–12 ids, authored order); nil when the step has no `annotate`.
    public internal(set) var annotate: [String]?
    /// v2: placements this step shows instead of the authored ones (`pose`): resolved part id → placement in the parent
    /// frame, for every part whose own placement the pose changes. Empty for a step without `pose`. The other steps,
    /// the plain view, `hero.png`, `exploded.png` and the loop keep the authored placements.
    public internal(set) var pose: [String: MGTransform] = [:]
    /// v2: the authored `pose` object (nil without one), compiled after the assembly (`MGSolidPoses.compile`).
    var poseSource: [String: MGJSON]?
    /// v2: parts this step hides (`hide`, resolved ids, authored order).
    public internal(set) var hide: [String] = []
    /// v2: show-only parts this step shows (`show`, resolved ids, authored order).
    public internal(set) var show: [String] = []

    /// The pose this step shows with `spin` (0...1) of its spin played: the document's default input plus the played
    /// turns, the step's explode value (or the default) and the step's `pose` placements.
    public func poseParameters(defaults: MGPoseParameters, spin: Double = 1) -> MGPoseParameters {
        MGPoseParameters(input: defaults.input + self.spin * 2 * .pi * spin, explode: explode ?? defaults.explode, placements: pose)
    }
}

/// Meshing data the compiler derived for one gear part.
public struct MGSolidGear: Equatable, Sendable {
    public internal(set) var part: String
    public internal(set) var spur: MGSpurGear?
    public internal(set) var ring: MGRingGear?
    /// Gear frame in the part frame (the primitive's offset).
    public internal(set) var local: MGTransform
    public var teeth: Int { spur?.teeth ?? ring?.teeth ?? 0 }
    public var module: Double { spur?.module ?? ring?.module ?? 0 }
}

/// A parsed, validated, compiled assembly document.
public struct MGSolidDocument: Equatable, Sendable {
    public internal(set) var title: String
    public internal(set) var assembly: MGAssembly
    public internal(set) var steps: [MGSolidStep]
    public internal(set) var defaults: MGPoseParameters
    public internal(set) var gears: [String: MGSolidGear]
    /// Per-part validated shapes (stable identity: unchanged shapes keep their meshes across patches).
    public internal(set) var shapes: [String: [MGShapeSpec]]
    /// Input-to-joint ratios the constraint solver found (joint radians or mm per input radian).
    public internal(set) var ratios: [String: Double]
    /// The source JSON this document was compiled from (with its `use` entries, before component expansion).
    public internal(set) var source: MGJSON
    /// The components `use` entries were resolved against; patches recompile with the same library.
    public internal(set) var library: MGSolidLibrary = .builtIn
    /// Assembly format version (1 or 2). New keys are legal only in v2; v1 keeps its exact meaning.
    public internal(set) var version: Int = 1
    /// Engine facts by canonical name (`stage.carrier.speed`, `count.stage.planet`); look names up with `fact(_:)`.
    public internal(set) var facts: [String: MGSolidFact] = [:]
    /// Component anchors to the part (or `repeat` base) ids they name (`stage.output` → `stage.carrier`).
    public internal(set) var aliases: [String: String] = [:]
    /// `repeat` copy ids to their base id (`planet2` → `planet`).
    public internal(set) var copies: [String: String] = [:]
    /// What moves each driven part: `input`, `follow`, `crankSlider`, `crankRod`, `gearMesh`, `fixed` or `phase`.
    public internal(set) var motionSources: [String: String] = [:]
    /// Engine tier of each driven part's own motion through its drive chain (`input` at ±1, crank closed forms and
    /// mesh solves from them are Solved; other `input` scales and `follow` ratios are author behaviour, Built).
    public internal(set) var driveTiers: [String: MGSolidTier] = [:]
    /// Base ids of parts marked `"offAxis": true` (v2).
    public internal(set) var offAxis: Set<String> = []
    /// Engine-computed title tier (v2, when the title shows facts).
    public internal(set) var titleTier: MGSolidTier?
    /// Honesty warnings (idle joints and frame lints in part order, then annotation warnings in authored order). The
    /// plain API only warns; the strict profile (`MGSolidProfile.strict`, the model harness) refuses some of them.
    public internal(set) var warnings: [MGSolidIssue] = []
    /// v2: labels, arrows and dimensions (empty for v1 and for documents without `annotations`).
    public internal(set) var annotations = MGSolidAnnotations()
    /// v2: canonical names of the facts the title shows, in order.
    public internal(set) var titleFacts: [String] = []
    /// The annotation fingerprint the compiler checked (`checkedAnnotations` refuses a changed document or a foreign view).
    public internal(set) var checkedFingerprint: String?
    /// v2: show-only parts: every part some step lists in `show`, in part order. Such a part shows only in the steps that
    /// list it; the plain view, `hero.png`, `exploded.png`, the loop and every other step hide it.
    public internal(set) var showOnly: [String] = []

    public func pose(_ params: MGPoseParameters) -> MGPose { assembly.pose(params) }

    /// A fact by name; component anchors resolve (`stage.output.speed`).
    public func fact(_ name: String) -> MGSolidFact? { MGSolidFacts.lookup(name, facts, aliases)?.fact }
}

/// Assembly format versions. `v: 1` keeps its exact meaning; `v: 2` is a strict superset whose new keys are legal
/// only when `v` is 2 (a v1 document with one is refused with the existing `….unknown.<key>` reason). Later
/// features add their keys to the v2 sets here.
struct MGSolidFormat: Equatable {
    let version: Int
    static let v1 = MGSolidFormat(version: 1), v2 = MGSolidFormat(version: 2)
    static let topKeysV2: Set<String> = ["annotations"]
    static let partKeysV2: Set<String> = ["expect", "offAxis", "opacity", "emissive"]
    static let stepKeysV2: Set<String> = ["check", "unchecked", "section", "ghost", "annotate", "pose", "hide", "show"]
    var isV2: Bool { version >= 2 }
    var topKeys: Set<String> { isV2 ? MGSolidParser.topKeys.union(Self.topKeysV2) : MGSolidParser.topKeys }
    var partKeys: Set<String> { isV2 ? MGSolidParser.partKeys.union(Self.partKeysV2) : MGSolidParser.partKeys }
    var stepKeys: Set<String> { isV2 ? MGSolidParser.stepKeys.union(Self.stepKeysV2) : MGSolidParser.stepKeys }
}

/// Strict decoder and compiler for the solid assembly JSON format (closed keys, bounded values, resolved references).
public enum MGSolidParser {
    /// `profile: .strict` (the model harness) also refuses the warnings listed in `MGSolidProfile.strictPrefixes`.
    public static func document(data: Data, reusing previous: MGSolidDocument? = nil,
                                library: MGSolidLibrary = .builtIn, profile: MGSolidProfile = .standard) -> Result<MGSolidDocument, MGSolidIssue> {
        guard data.count <= MGSolidLimits.bytes else { return .failure(bytesIssue("assembly.bytes", data.count)) }
        if let r = MGJSON.dataRefusal(data, json: "json", depth: "assembly.depth") { return .failure(.init(r)) }
        guard let object = try? JSONSerialization.jsonObject(with: data), let json = MGJSON(any: object) else {
            return .failure(.init("json"))
        }
        return document(json: json, reusing: previous, library: library, profile: profile)
    }

    /// A byte-limit refusal (`assembly.bytes`, `patch.bytes`) with its detail: the whole document, `bytes` long.
    static func bytesIssue(_ reason: String, _ bytes: Int, limit: Int = MGSolidLimits.bytes) -> MGSolidIssue {
        MGSolidIssue(reason, limit: MGSolidLimitDetail(field: "document", actual: bytes, limit: limit, unit: "bytes"))
    }

    /// `library` resolves `use` entries (components); see docs/SOLID-3D.md, Components.
    public static func document(json: MGJSON, reusing previous: MGSolidDocument? = nil,
                                library: MGSolidLibrary = .builtIn, profile: MGSolidProfile = .standard) -> Result<MGSolidDocument, MGSolidIssue> {
        document(json: json, reusing: previous, library: library, profile: profile, perStepAnnotations: false)
    }

    /// `perStepAnnotations` (an explainer's solid): with more than `MGSolidAnnotationLimits.visible` annotations, the
    /// document is stepped even when no step uses `annotate` (the limit applies to each step's own list).
    /// `steppedAnnotations`: stepped whatever the steps (an explainer document in which some beat has `annotate`).
    static func document(json: MGJSON, reusing previous: MGSolidDocument? = nil, library: MGSolidLibrary = .builtIn,
                         profile: MGSolidProfile = .standard, perStepAnnotations: Bool,
                         steppedAnnotations: Bool = false) -> Result<MGSolidDocument, MGSolidIssue> {
        if json.nestsTooDeep { return .failure(.init("assembly.depth")) }
        do {
            let doc = try compile(json, previous, library, perStepAnnotations: perStepAnnotations, steppedAnnotations: steppedAnnotations)
            if let refusal = profile.refusal(doc) { return .failure(refusal) }
            return .success(doc)
        }
        catch let e as MGSolidIssue { return .failure(e) }
        catch let e as MGError { return .failure(.init(e.reason)) }
        catch { return .failure(.init("unknown")) }
    }

    /// Applies a patch and recompiles. `{"params": {...}}` only changes the defaults; `{"parts": {"id": {...}}}` merges
    /// fields into existing parts by id; `"constraints"` and `"steps"` replace those arrays. Part ids are stable, and
    /// parts whose shapes did not change keep their meshes. An id inside a component instance (`stage1.pinion`) merges
    /// into that `use` entry's `set`; the instance id itself (`stage1`) edits the `use` entry (`with`, `at`, …).
    /// `profile: .strict` refuses a patch whose result the strict profile would refuse (an idle joint, a frame error).
    public static func applying(_ patch: MGJSON, to doc: MGSolidDocument,
                                profile: MGSolidProfile = .standard) -> Result<MGSolidDocument, MGSolidIssue> {
        if patch.nestsTooDeep { return .failure(.init("patch.depth")) }
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
                if let k = list.firstIndex(where: { $0["id"] == .string(id) }), case .object(var o) = list[k] {
                    for (key, value) in fields { if value == .null { o.removeValue(forKey: key) } else { o[key] = value } }
                    list[k] = .object(o)
                    continue
                }
                // `stage1.pinion` (or `stage1.gears.pinion`): merge into the `set` of the `use` entry `stage1`.
                let head = id.split(separator: ".", maxSplits: 1).map(String.init)
                guard head.count == 2, let k = list.firstIndex(where: { $0["id"] == .string(head[0]) && $0["use"] != nil }),
                      case .object(var o) = list[k] else {
                    return .failure(.init("ref.unknown.\(token(id))"))
                }
                guard case .object(var set) = o["set"] ?? .object([:]), case .object(var inner) = set[head[1]] ?? .object([:]) else {
                    return .failure(.init("patch.parts.set", part: token(id)))
                }
                for (key, value) in fields { inner[key] = value }
                set[head[1]] = .object(inner)
                o["set"] = .object(set)
                list[k] = .object(o)
            }
            src["parts"] = .array(list)
        }
        return document(json: .object(src), reusing: doc, library: doc.library, profile: profile)
    }

    /// `applying` for patch JSON text. Before the system parser runs, a patch over `MGSolidLimits.bytes` is refused
    /// (`patch.bytes`), and so are bytes that are not UTF-8 JSON text (`patch.json`) or that nest deeper than
    /// `MGLimits.depth` (`patch.depth`). Text the parser rejects is `patch.json` too.
    public static func applying(data: Data, to doc: MGSolidDocument,
                                profile: MGSolidProfile = .standard) -> Result<MGSolidDocument, MGSolidIssue> {
        patchJSON(data).flatMap { applying($0, to: doc, profile: profile) }
    }

    /// Patch text to a value, with the guards of `applying(data:to:)`.
    static func patchJSON(_ data: Data) -> Result<MGJSON, MGSolidIssue> {
        guard data.count <= MGSolidLimits.bytes else { return .failure(bytesIssue("patch.bytes", data.count)) }
        if let r = MGJSON.dataRefusal(data, json: "patch.json", depth: "patch.depth") { return .failure(.init(r)) }
        guard let object = try? JSONSerialization.jsonObject(with: data), let json = MGJSON(any: object) else {
            return .failure(.init("patch.json"))
        }
        return .success(json)
    }

    // MARK: Compile

    static let topKeys: Set<String> = ["v", "kind", "title", "units", "params", "parts", "constraints", "steps"]
    static let partKeys: Set<String> = ["id", "name", "shape", "material", "parent", "at", "rot", "joint", "drive", "explode",
                                        "explodeWindow", "repeat", "phase", "smooth"]
    static let stepKeys: Set<String> = ["say", "focus", "highlight", "explode", "camera", "orbit", "spin"]

    struct RawPart {
        var id: String, name: String, shapes: [MGShapeSpec], material: MGMaterialPreset
        var parent: String?, placement: MGTransform, joint: MGJoint
        var drive: MGJSON?, explode: MGVec3, window: ClosedRange<Double>, phase: Double, crease: Double
        var base: String, instance: Int?
        /// v2: `offAxis` and `expect` (`axisWorld`, `upWorld`).
        var offAxis = false, expectAxis: MGVec3? = nil, expectUp: MGVec3? = nil
        /// v2: `opacity` and `emissive`.
        var opacity = 1.0, emission: MGEmission? = nil
    }

    /// The `parts.resolved` detail: every top-level `use` instance with the resolved parts its expansion made (part ids
    /// the expansion generated start with `<instance id>.`; authored ids never hold a dot).
    static func resolvedDetail(_ authored: [String: MGJSON], _ parts: [RawPart]) -> MGSolidLimitDetail {
        var uses: [(id: String, component: String)] = []
        if case .array(let entries)? = authored["parts"] {
            for e in entries { if case .string(let id)? = e["id"], case .string(let c)? = e["use"] { uses.append((id, c)) } }
        }
        let top = uses.map { u -> MGSolidLimitDetail.Contributor in
            let prefix = u.id + "."
            return .init(id: u.id, component: u.component, parts: parts.reduce(0) { $0 + ($1.base.hasPrefix(prefix) ? 1 : 0) })
        }.filter { $0.parts > 0 }
        return MGSolidLimitDetail(count: parts.count, limit: MGSolidLimits.resolvedParts, top: top)
    }

    /// True when any object anywhere in the value has a key named `tier` (authors cannot set tiers).
    /// `assembly.budget` with its detail (triangles first, then vertices), or nil within both limits.
    static func budgetIssue(_ triangles: Int, _ vertices: Int) -> MGSolidIssue? {
        if triangles > MGSolidLimits.triangles {
            return MGSolidIssue("assembly.budget", limit: MGSolidLimitDetail(field: "parts", actual: triangles, limit: MGSolidLimits.triangles, unit: "triangles"))
        }
        if vertices > MGSolidLimits.vertices {
            return MGSolidIssue("assembly.budget", limit: MGSolidLimitDetail(field: "parts", actual: vertices, limit: MGSolidLimits.vertices, unit: "vertices"))
        }
        return nil
    }

    static func hasTierKey(_ v: MGJSON) -> Bool {
        switch v {
        case .object(let o): return o["tier"] != nil || o.values.contains(where: hasTierKey)
        case .array(let a): return a.contains(where: hasTierKey)
        default: return false
        }
    }

    static func compile(_ json: MGJSON, _ previous: MGSolidDocument?, _ library: MGSolidLibrary = .builtIn,
                        perStepAnnotations: Bool = false, steppedAnnotations: Bool = false) throws -> MGSolidDocument {
        guard case .object(var o) = json else { throw MGSolidIssue("assembly.object") }
        let canonical = json.canonicalByteCount
        guard canonical <= MGSolidLimits.bytes else { throw bytesIssue("assembly.bytes", canonical) }
        // The key set follows the declared version; anything but 2 checks the v1 keys first, exactly as before.
        let format: MGSolidFormat = o["v"] == .number(2) ? .v2 : .v1
        // In v2 a `tier` key anywhere (top level included) is refused before any other key check.
        if format.isV2, hasTierKey(json) { throw MGSolidIssue("tier.key") }
        try closed(o, ["v", "kind", "parts"], format.topKeys, "assembly")
        guard o["v"] == .number(1) || format.isV2 else { throw MGSolidIssue("assembly.version") }
        guard o["kind"] == .string("assembly") else { throw MGSolidIssue("assembly.kind") }
        if let u = o["units"], u != .string("mm") { throw MGSolidIssue("assembly.units") }
        let title = try o["title"].map { try text($0, MGSolidLimits.title, "assembly.title", field: "title") } ?? "Assembly"
        var defaults = MGPoseParameters()
        if let p = o["params"] {
            guard case .object(let po) = p else { throw MGSolidIssue("params") }
            try closed(po, [], ["input", "explode"], "params")
            if let v = po["input"] { defaults.input = try num(v, -1e6...1e6, "params.input") }
            if let v = po["explode"] { defaults.explode = try num(v, 0...1, "params.explode") }
        }
        // Component instances (`use`) expand into plain parts first; every check below applies to the expanded parts.
        let authored = o
        let expansion = try MGSolidComponents.expand(o, library)
        o = expansion.object
        // Authored `parts` hold 1–48 entries (checked before expansion); expanded component parts may reach `expandedParts`.
        let wireCap = expansion.generated.isEmpty ? MGSolidLimits.parts : MGSolidLimits.expandedParts
        guard case .array(let rawParts)? = o["parts"] else { throw MGSolidIssue("parts.count") }
        if let l = countDetail("parts", rawParts.count, 1...wireCap) { throw MGSolidIssue("parts.count", limit: l) }

        // Parts, with `repeat` expansion.
        var parts: [RawPart] = []
        var repeated: [String: Int] = [:]
        var wireIDs = Set<String>()
        // A part's limit detail names it by its index in the authored `parts`, or `[id=…]` for a part a component made.
        var authoredIDs: [String] = []
        if case .array(let list)? = authored["parts"] { authoredIDs = list.map { $0["id"]?.stringValue ?? "" } }
        for entry in rawParts {
            var expanded: [RawPart]
            do { expanded = try part(entry, generated: expansion.generated, format: format) }
            catch let e as MGSolidIssue where e.limit != nil {
                let id = entry["id"]?.stringValue ?? ""
                throw e.prefixed(authoredIDs.firstIndex(of: id).map { "parts[\($0)]." } ?? "parts[id=\(token(id))].")
            }
            if let frame = expansion.frames[expanded[0].base] {
                // An instance placed with `at` / `rot` carries its root parts (outside any `repeat` turn).
                for k in expanded.indices { expanded[k].placement = frame * expanded[k].placement }
            }
            guard wireIDs.insert(expanded[0].base).inserted else { throw MGSolidIssue("id.duplicate.\(token(expanded[0].base))", part: expanded[0].base) }
            if expanded.count > 1 || expanded[0].instance != nil { repeated[expanded[0].base] = expanded.count }
            parts += expanded
        }
        guard parts.count <= MGSolidLimits.resolvedParts else { throw MGSolidIssue(limit: resolvedDetail(authored, parts)) }
        // Mesh budget over every resolved part, counted from the validated fields before any mesh is built.
        var triangles = 0, vertices = 0
        for p in parts { for s in p.shapes { let e = s.meshEstimate; triangles += e.triangles; vertices += e.vertices } }
        if let b = budgetIssue(triangles, vertices) { throw b }
        var ids = Set<String>()
        for p in parts { guard ids.insert(p.id).inserted else { throw MGSolidIssue("id.duplicate.\(token(p.id))", part: p.id) } }
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
            guard case .array(let list) = c else { throw MGSolidIssue("constraints.count") }
            if let l = countDetail("constraints", list.count, 0...MGSolidLimits.constraints) { throw MGSolidIssue("constraints.count", limit: l) }
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
        // What moves each driven part (facts, tiers and the read-back name it).
        var sources: [String: String] = [:]
        for p in parts { if case .object(let d)? = p.drive, let k = d.keys.first { sources[p.id] = k } }
        for id in unknown where sources[id] == nil { sources[id] = fixed.contains(id) ? "fixed" : "gearMesh" }
        for id in drives.keys where sources[id] == nil { sources[id] = "phase" }
        // Tier of each part's own drive. An `input` scale is the reference speed only at ±1 (or 0, held); any other
        // scale, and every `follow` ratio, is behaviour the author set (Built). A gear-mesh solve takes the lowest
        // tier of the inputs in its connected part of the velocity system.
        var ownTiers: [String: MGSolidTier] = [:]
        for (id, s) in inputs { ownTiers[id] = s == 0 || abs(abs(s) - 1) < 1e-12 ? .solved : .built }
        for p in parts where sources[p.id] == "follow" { ownTiers[p.id] = .built }
        var root = Array(0..<unknown.count)
        func find(_ i: Int) -> Int { var i = i; while root[i] != i { root[i] = root[root[i]]; i = root[i] }; return i }
        for (row, _) in rows { let cols = row.keys.sorted(); for c in cols.dropFirst() { root[find(c)] = find(cols[0]) } }
        var componentTier: [Int: MGSolidTier] = [:]
        for (i, id) in unknown.enumerated() where inputs[id] != nil {
            componentTier[find(i)] = min(componentTier[find(i)] ?? .solved, ownTiers[id] ?? .solved)
        }
        for (i, id) in unknown.enumerated() where inputs[id] == nil { ownTiers[id] = componentTier[find(i)] ?? .solved }

        // Steps.
        var steps: [MGSolidStep] = []
        if let s = o["steps"] {
            guard case .array(let list) = s else { throw MGSolidIssue("steps.count") }
            if let l = countDetail("steps", list.count, 0...MGSolidLimits.steps) { throw MGSolidIssue("steps.count", limit: l) }
            for (i, entry) in list.enumerated() {
                // A visibility refusal of one step names the step; a limit detail gets the step's path.
                do { steps.append(try step(entry, expand, format, grouped: !expansion.generated.isEmpty)) }
                catch let e as MGSolidIssue where e.visibility != nil { throw MGSolidIssue(e.reason, visibility: e.visibility!.at(i, cause: .step)) }
                catch let e as MGSolidIssue where e.limit != nil { throw e.prefixed("steps[\(i)].") }
            }
        }
        let showOnly = try MGSolidStepVisibility.check(steps, order: parts.map(\.id))
        // v2 annotations: parsed and resolved before any mesh is built; their arrow and dimension pieces join the mesh
        // budget with exact counts.
        var annotations = MGSolidAnnotations()
        if format.isV2 {
            if let a = o["annotations"] {
                annotations = try MGSolidAnnotations.parse(a, .init(ids: ids, repeated: repeated, aliases: expansion.aliases))
            }
            try MGSolidAnnotationEngine.checkVisibility(&annotations, steps, perStep: perStepAnnotations, stepped: steppedAnnotations)
            // Poses stay exact enough: a document with annotations keeps its default input within 10,000 turns.
            if !annotations.isEmpty, abs(defaults.input) > MGSolidAnnotationLimits.input { throw MGSolidIssue("annotations.input") }
            let e = annotations.meshEstimate
            triangles += e.triangles; vertices += e.vertices
            if let b = budgetIssue(triangles, vertices) { throw b }
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
                                        joint: p.joint, drive: drives[p.id], explode: p.explode, explodeWindow: p.window, creaseAngle: p.crease,
                                        opacity: p.opacity, emission: p.emission))
        }
        let pairs = meshes.enumerated().map { k, m in
            MGGearPair(a: m.a, b: m.b, teethA: gears[m.a]!.teeth, teethB: gears[m.b]!.teeth, isInternal: gears[m.a]!.ring != nil,
                       carrier: m.carrier, axis: meshAxis[k])
        }
        let assembly = MGAssembly(name: title, parts: assemblyParts, gearPairs: pairs)
        if let issue = assembly.validate().first { throw MGSolidIssue(issue == "drive cycle" ? "part.drive.cycle" : "assembly.invalid") }
        try MGSolidSections.compile(&steps, assembly, defaults: defaults, budget: (triangles, vertices), shapes: shapes, previous: previous)

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
        var copies: [String: String] = [:]
        for p in parts where repeated[p.base] != nil && p.id != p.base { copies[p.id] = p.base }
        var doc = MGSolidDocument(title: title, assembly: assembly, steps: steps, defaults: defaults, gears: gears, shapes: shapes,
                                  ratios: ratios, source: json, library: library)
        doc.version = format.version
        doc.copies = copies
        doc.aliases = expansion.aliases
        doc.motionSources = sources
        doc.offAxis = Set(parts.filter(\.offAxis).map(\.base))
        doc.annotations = annotations
        doc.showOnly = showOnly
        (doc.facts, doc.driveTiers) = MGSolidFacts.table(assembly, gears: gears, sources: sources, ownTiers: ownTiers,
                                                         copies: copies, aliases: expansion.aliases)
        if format.isV2 {
            // Step poses: each posed step is checked against a compile of the document with that pose applied.
            try MGSolidPoses.compile(&doc, authored: authored)
            var expects: [String: (axis: MGVec3?, up: MGVec3?)] = [:]
            for p in parts where p.expectAxis != nil || p.expectUp != nil { expects[p.base] = (p.expectAxis, p.expectUp) }
            try MGSolidFrames.checkExpectations(assembly, expects, copies: copies)
            try MGSolidAnnotationEngine.prepare(&doc)
            try fillText(&doc)
            try MGSolidAnnotationEngine.finish(&doc)
            try MGSolidStepVisibility.checkClaims(doc)
            try MGSolidPoses.checkFacts(doc)
            try MGSolidAnnotationEngine.checkViews(doc)
        } else {
            // v1 text is never filled. A caption or title with a number in it makes a claim the engine did not check.
            for i in doc.steps.indices where doc.steps[i].say.contains(where: MGSolidFacts.isNumber) { doc.steps[i].tier = .described }
            if doc.title.contains(where: MGSolidFacts.isNumber) { doc.titleTier = .described }
        }
        doc.warnings = MGSolidFrames.lints(doc) + MGSolidAnnotationEngine.warnings(doc)
        // Frame lints at each step's pose (a posed child far from its parent), each reason once.
        for i in doc.steps.indices where !doc.steps[i].pose.isEmpty {
            for w in MGSolidFrames.lints(doc, placements: doc.steps[i].pose) where !doc.warnings.contains(where: { $0.reason == w.reason }) {
                doc.warnings.append(w)
            }
        }
        // Binds views and annotation output to this compiled document (`checkedAnnotations`).
        doc.checkedFingerprint = doc.annotationFingerprint
        return doc
    }

    /// v2 text: fills the title and every step from the facts table, applies rule N1 to captions (no number character
    /// outside a placeholder unless the step is `unchecked`), proves step `check` claims and sets text tiers. A title
    /// may type numbers, but then it is Described. `abs` hides a sign, so it needs a check in the same step that
    /// proves the sign of that fact (`text.sign.<name>`); a title cannot use it.
    static func fillText(_ doc: inout MGSolidDocument) throws {
        let title = try MGSolidFacts.fill(doc.title, where: "title", n1: false, doc.facts, doc.aliases)
        guard title.text.unicodeScalars.count <= MGSolidLimits.title else {
            throw MGSolidIssue("assembly.title", limit: MGSolidLimitDetail(field: "title", actual: title.text.unicodeScalars.count,
                                                                           limit: MGSolidLimits.title, unit: "characters"))
        }
        for (name, mods) in zip(title.facts, title.modifiers) where mods.contains("abs") { throw MGSolidIssue("text.sign.\(token(name))") }
        doc.title = title.text
        doc.titleFacts = title.facts
        doc.assembly.name = title.text
        doc.titleTier = MGSolidTiers.text(facts: title.facts.compactMap { doc.facts[$0] }, unchecked: false, typedNumbers: title.typedNumbers)
        for i in doc.steps.indices {
            var s = doc.steps[i]
            let filled = try MGSolidFacts.fill(s.template, where: "step.\(i + 1)", n1: s.unchecked == nil, doc.facts, doc.aliases)
            guard !filled.text.isEmpty, filled.text.unicodeScalars.count <= MGSolidLimits.say else {
                throw MGSolidIssue("step.say", limit: MGSolidLimitDetail(field: "steps[\(i)].say", actual: filled.text.unicodeScalars.count,
                                                                         limit: MGSolidLimits.say, unit: "characters", minimum: 1))
            }
            var signed = Set<String>()
            for c in s.checks {
                let t = token(c.value)
                guard let (name, fact) = MGSolidFacts.lookup(c.value, doc.facts, doc.aliases) else { throw MGSolidIssue("check.fact.\(t)") }
                guard c.holds(fact.value) else { throw MGSolidIssue("check.failed.\(t)") }
                if c.provesSign { signed.insert(name) }
            }
            for (name, mods) in zip(filled.facts, filled.modifiers) where mods.contains("abs") && !signed.contains(name) {
                throw MGSolidIssue("text.sign.\(token(name))")
            }
            s.say = filled.text
            s.facts = filled.facts
            s.tier = MGSolidTiers.text(facts: filled.facts.compactMap { doc.facts[$0] }, unchecked: s.unchecked != nil)
            doc.steps[i] = s
        }
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

    /// `generated`: dotted ids made by component expansion (`stage1.pinion`); authored ids stay plain identifiers.
    static func part(_ entry: MGJSON, generated: Set<String> = [], format: MGSolidFormat = .v1) throws -> [RawPart] {
        guard case .object(let o) = entry else { throw MGSolidIssue("part.object") }
        let pid: String
        if case .string(let s)? = o["id"], generated.contains(s) { pid = s }
        else { do { pid = try MGParser.identifier(o["id"] ?? .null, "part.id") } catch { throw MGSolidIssue("part.id") } }
        func fail(_ r: String) -> MGSolidIssue { MGSolidIssue(r, part: pid) }
        do {
            try closed(o, ["id", "shape"], format.partKeys, "part")
            let name = try o["name"].map { try text($0, MGSolidLimits.name, "part.name", field: "name", part: pid) } ?? pid
            var shapeList: [MGJSON]
            switch o["shape"] {
            case .array(let l)?: shapeList = l
            case let s?: shapeList = [s]
            case nil: shapeList = []
            }
            if let l = countDetail("shape", shapeList.count, 1...MGSolidLimits.shapesPerPart, unit: "shapes") {
                throw MGSolidIssue("part.shape.count", part: pid, limit: l)
            }
            let shapes = try shapeList.map(shape)
            guard shapes.filter({ $0.kind == "gear" || $0.kind == "ringGear" }).count <= 1 else { throw MGSolidIssue("part.shape.gears") }
            let material = try materialPreset(o["material"] ?? .string("brushedSteel"))
            var parent: String?
            if case .string(let s)? = o["parent"], generated.contains(s) { parent = s }
            else if case .string(let s)? = o["parent"], s.contains(".") { throw MGSolidIssue("ref.unknown.\(token(s))") }
            else if let p = o["parent"] { parent = try MGParser.identifier(p, "part.parent") }
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
            var raw = RawPart(id: pid, name: name, shapes: shapes, material: material, parent: parent, placement: placement, joint: joint,
                              drive: o["drive"], explode: explode, window: window, phase: phase, crease: crease, base: pid, instance: nil)
            if let v = o["offAxis"] {
                guard case .bool(let b) = v else { throw MGSolidIssue("part.offAxis") }
                raw.offAxis = b
            }
            if let v = o["opacity"] { raw.opacity = try num(v, MGSolidView.opacityRange, "part.opacity") }
            if let e = o["emissive"] {
                guard case .object(let eo) = e else { throw MGSolidIssue("part.emissive") }
                try closed(eo, ["role"], ["intensity"], "part.emissive")
                guard case .string(let r)? = eo["role"], let role = MGColorRole(rawValue: r) else { throw MGSolidIssue("part.emissive.role") }
                raw.emission = MGEmission(role: role, intensity: try eo["intensity"].map { try num($0, MGEmission.intensityRange, "part.emissive") } ?? 1)
            }
            if let e = o["expect"] {
                guard case .object(let eo) = e, !eo.isEmpty else { throw MGSolidIssue("part.expect") }
                try closed(eo, [], ["axisWorld", "upWorld"], "part.expect")
                func direction(_ key: String) throws -> MGVec3? {
                    guard let v = eo[key] else { return nil }
                    let d = try vector(v, "part.expect.\(key)")
                    guard d.length > 1e-9 else { throw MGSolidIssue("part.expect.\(key)") }
                    return d.normalized
                }
                raw.expectAxis = try direction("axisWorld")
                raw.expectUp = try direction("upWorld")
            }
            guard let r = o["repeat"] else { return [raw] }
            guard case .object(let ro) = r else { throw MGSolidIssue("part.repeat") }
            try closed(ro, ["count"], ["count", "axis", "angle"], "part.repeat")
            guard case .number(let countValue)? = ro["count"], countValue.isFinite, countValue.rounded() == countValue else {
                throw MGSolidIssue("part.repeat.count", part: pid)
            }
            guard (2...Double(MGSolidLimits.repeatCount)).contains(countValue) else {
                throw MGSolidIssue("part.repeat.count", part: pid, limit: MGSolidLimitDetail(
                    field: "repeat.count", actual: countValue > 1e9 ? Int(1e9) : countValue < -1e9 ? Int(-1e9) : Int(countValue),
                    limit: MGSolidLimits.repeatCount, unit: "copies", minimum: 2))
            }
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
            throw e.part == nil ? MGSolidIssue(e.reason, part: pid, limit: e.limit) : e
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
        "revolvedProfile": (["points"], ["closed", "sweep", "start"]),
        "blade": (["span", "chord"], ["thickness", "twist", "pitch", "root", "tipChord", "camber", "camberPosition"]),
        "bladeRow": MGSolidTurbo.bladeRowKeys,
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
                guard case .array(let list) = h else { throw MGSolidIssue("\(w).holes") }
                if let l = countDetail("shape.plate.holes", list.count, 0...MGSolidLimits.plateHoles, unit: "holes") { throw MGSolidIssue("\(w).holes", limit: l) }
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
                guard case .array(let list) = h else { throw MGSolidIssue("\(w).holes") }
                if let l = countDetail("shape.extrudedProfile.holes", list.count, 0...MGSolidLimits.profileHoles, unit: "holes") {
                    throw MGSolidIssue("\(w).holes", limit: l)
                }
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
            try MGSolidTurbo.validateSweep(f)
            if closedLoop {
                guard pts.count >= 3, pts.allSatisfy({ $0.x > 1e-6 }), abs(MGProfile.signedArea(pts)) > 1e-6, !selfIntersects(pts) else { throw MGSolidIssue("\(w).points") }
            } else {
                guard pts.count >= 3, pts.first!.x == 0, pts.last!.x == 0 else { throw MGSolidIssue("\(w).axis") }
                guard pts.dropFirst().dropLast().allSatisfy({ $0.x > 1e-6 }), abs(MGProfile.signedArea(pts)) > 1e-6, !selfIntersects(pts) else { throw MGSolidIssue("\(w).points") }
            }
        case "blade":
            _ = try n("span"); let chord = try n("chord")
            _ = try opt("thickness", 0.02...0.4); _ = try opt("root", 0...4000)
            // Section angle pitch + twist × t, so the tip angle stays below 85 degrees as for blade rows.
            let twist = try opt("twist", -80...80) ?? 0, pitch = try opt("pitch", -80...80) ?? 0
            guard abs(pitch + twist) <= 85 else { throw MGSolidIssue("\(w).twist") }
            _ = try opt("tipChord", 0.05...4000)
            _ = try opt("camber", 0...0.09); _ = try opt("camberPosition", 0.1...0.9)
            _ = chord
        case "bladeRow":
            try MGSolidTurbo.validateBladeRow(f)
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
                                                  "rubber": .rubber, "glass": .glass, "titanium": .titanium, "nickelAlloy": .nickelAlloy,
                                                  "composite": .composite, "ceramic": .ceramic]
        if let m = simple[s] { return m }
        let parts = s.split(separator: ".", maxSplits: 1).map(String.init)
        if parts.count == 2, let role = MGColorRole(rawValue: parts[1]) {
            if parts[0] == "anodized" { return .anodized(role) }
            if parts[0] == "plastic" { return .plastic(role) }
        }
        throw MGSolidIssue("part.material")
    }

    /// `grouped`: the document has component instances, so its step id lists arrive expanded (an instance id became its
    /// parts); their authored entries were counted against `idsPerStep` before expansion (`MGSolidComponents.expand`).
    static func step(_ entry: MGJSON, _ expand: (String, String) throws -> [String], _ format: MGSolidFormat = .v1,
                     grouped: Bool = false) throws -> MGSolidStep {
        guard case .object(let o) = entry else { throw MGSolidIssue("step.object") }
        try closed(o, ["say"], format.stepKeys, "step")
        let cap = grouped ? MGSolidLimits.resolvedParts : MGSolidLimits.idsPerStep
        func ids(_ key: String) throws -> [String] {
            guard let v = o[key] else { return [] }
            guard case .array(let list) = v else { throw MGSolidIssue("step.\(key)") }
            if let l = countDetail(key, list.count, 0...cap, unit: "ids") { throw MGSolidIssue("step.\(key)", limit: l) }
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
        let say = try text(o["say"] ?? .null, MGSolidLimits.say, "step.say", field: "say")
        var step = MGSolidStep(say: say, focus: try ids("focus"), highlight: try ids("highlight"),
                               explode: try o["explode"].map { try num($0, 0...1, "step.explode") }, camera: camera,
                               orbit: try o["orbit"].map { try num($0, -360...360, "step.orbit") } ?? 0,
                               spin: try o["spin"].map { try num($0, -20...20, "step.spin") } ?? 0)
        step.template = say
        if let u = o["unchecked"] { step.unchecked = try text(u, MGSolidLimits.unchecked, "step.unchecked", field: "unchecked") }
        if let c = o["check"] {
            guard case .array(let list) = c else { throw MGSolidIssue("step.check") }
            if let l = countDetail("check", list.count, 1...MGSolidLimits.checksPerStep, unit: "checks") { throw MGSolidIssue("step.check", limit: l) }
            step.checks = try list.map(MGSolidClaimCheck.parse)
        }
        if let g = o["ghost"] {
            guard case .array(let list) = g else { throw MGSolidIssue("step.ghost") }
            if list.isEmpty { throw MGSolidIssue("step.ghost", limit: countDetail("ghost", 0, 1...cap, unit: "ids")) }
            step.ghost = unique(try ids("ghost"))
        }
        if let sec = o["section"] {
            guard case .object(let so) = sec else { throw MGSolidIssue("step.section") }
            try closed(so, ["normal", "parts"], ["offset"], "step.section")
            let normal = try vector(so["normal"] ?? .null, "step.section.normal")
            guard normal.length > 1e-9 else { throw MGSolidIssue("step.section.normal") }
            let offset = try so["offset"].map { try num($0, MGSolidLimits.coordinate, "step.section.offset") } ?? 0
            guard case .array(let list) = so["parts"]! else { throw MGSolidIssue("step.section.parts") }
            if let l = countDetail("section.parts", list.count, 1...cap, unit: "ids") { throw MGSolidIssue("step.section.parts", limit: l) }
            let parts = try list.flatMap { e -> [String] in
                guard case .string(let id) = e else { throw MGSolidIssue("step.section.parts") }
                return try expand(id, "step.section.parts")
            }
            step.section = MGSolidStepSection(plane: MGSectionPlane(normal: normal, offset: offset), parts: unique(parts))
        }
        if let a = o["annotate"] {
            guard case .array(let list) = a else { throw MGSolidIssue("step.annotate") }
            guard list.count <= MGSolidAnnotationLimits.visible else {
                let first: String
                if case .string(let s) = list[MGSolidAnnotationLimits.visible] { first = s } else { first = "" }
                throw MGSolidIssue("step.annotate.count", visibility: MGAnnotationVisibilityDetail(annotation: first, count: list.count,
                                                                                                   limit: MGSolidAnnotationLimits.visible, cause: .step))
            }
            step.annotate = unique(try list.map { e -> String in
                guard case .string(let id) = e else { throw MGSolidIssue("step.annotate") }
                return id
            })
        }
        for key in ["hide", "show"] {
            guard let v = o[key] else { continue }
            guard case .array(let list) = v else { throw MGSolidIssue("step.\(key)") }
            if list.isEmpty { throw MGSolidIssue("step.\(key)", limit: countDetail(key, 0, 1...cap, unit: "ids")) }
            let resolved = unique(try ids(key))
            if key == "hide" { step.hide = resolved } else { step.show = resolved }
        }
        if let p = o["pose"] { step.poseSource = try MGSolidPoses.parse(p) }
        return step
    }

    // MARK: Helpers

    /// The list without repeats, first occurrence kept.
    static func unique(_ list: [String]) -> [String] {
        var seen = Set<String>()
        return list.filter { seen.insert($0).inserted }
    }

    static func closed(_ o: [String: MGJSON], _ required: Set<String>, _ optional: Set<String>, _ what: String) throws {
        let keys = Set(o.keys)
        // Name the missing keys (sorted), so an author or a model can repair from the reason alone.
        let missing = required.subtracting(keys)
        guard missing.isEmpty else { throw MGSolidIssue("\(what).missing.\(missing.map(token).sorted().joined(separator: ","))") }
        let extra = keys.subtracting(required.union(optional))
        guard extra.isEmpty else { throw MGSolidIssue("\(what).unknown.\(extra.map(token).sorted().joined(separator: ","))") }
    }
    /// An author-supplied name as it appears inside a reason: ASCII letters, digits, `_` and `.` (anything else
    /// becomes `_`), at most 32 characters, so reasons stay single tokens without spaces or JSON text. The dot keeps
    /// component part ids (`stage1.pinion`) readable.
    static func token(_ s: String) -> String {
        let t = String(s.unicodeScalars.prefix(32).map { u -> Character in
            u.isASCII && (CharacterSet.alphanumerics.contains(u) || u == "_" || u == ".") ? Character(u) : "_"
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
    /// Plain text of 1...`max` Unicode scalars. A text that is empty after trimming or longer than `max` is refused with
    /// a limit detail at `field` (characters; minimum 1); any other fault without one.
    static func text(_ v: MGJSON, _ max: Int, _ what: String, field: String? = nil, part: String? = nil) throws -> String {
        guard case .string(let s) = v else { throw MGSolidIssue(what, part: part) }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty || s.unicodeScalars.count > max {
            throw MGSolidIssue(what, part: part, limit: MGSolidLimitDetail(field: field ?? what, actual: t.isEmpty ? 0 : s.unicodeScalars.count,
                                                                           limit: max, unit: "characters", minimum: 1))
        }
        guard !s.contains("<"), !s.contains(">"), !s.contains("://"),
              !s.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw MGSolidIssue(what, part: part) }
        return t
    }

    /// The limit detail of a count `n` against `range` (nil inside it).
    static func countDetail(_ field: String, _ n: Int, _ range: ClosedRange<Int>, unit: String = "entries") -> MGSolidLimitDetail? {
        guard !range.contains(n) else { return nil }
        return MGSolidLimitDetail(field: field, actual: n, limit: range.upperBound, unit: unit, minimum: range.lowerBound > 0 ? range.lowerBound : nil)
    }
}
