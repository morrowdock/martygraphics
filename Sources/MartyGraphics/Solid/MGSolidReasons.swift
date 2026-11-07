// SPDX-License-Identifier: Apache-2.0
import Foundation

// The catalog of every stable reason the Solid 3D formats give: refusals of assemblies, patches, component
// definitions, snapshots, step cuts and the check report, and the honesty warnings. One table; a test scans the Solid
// sources and the `marty-solid` tool and fails when a reason-shaped string is not in it, or when an entry matches
// nothing in the sources. Foundation only.

/// One stable reason pattern. `<…>` is a typed slot (see `MGSolidReasons.slots` and docs/REASONS.md): a slot matches
/// only values of its own domain, so a reason the engine gives fits exactly one pattern, or a specific pattern and the
/// general one it refines (`part.gear.bore` and `part.<shape>.<field>`; `lookup` picks the specific one).
public struct MGSolidReason: Equatable, Sendable {
    /// Where a reason comes from.
    public enum Format: String, CaseIterable, Sendable {
        /// `MGSolidParser.document` and every compile of an assembly: a patch recompiles the whole document, and a
        /// component definition compiles on its own, so these reasons can also answer a patch or a component.
        case assembly
        /// `MGSolidParser.applying` (only patches give these).
        case patch
        /// Component definitions (`MGSolidLibrary.register`, `validate`, `instantiate`) and `use` entries.
        case component
        /// `MGSolidReport` (`marty-solid check`): refusals after a document compiles.
        case check
        /// `MGSolidSnapshot.decode(data:)`.
        case snapshot
        /// `MGSolidSection.cut` and `estimate` called directly (an assembly reports these with `.<id>`).
        case section
        /// The `marty-solid` tool.
        case cli
        /// Explainer documents and streams (`MGExplainer`, `MGExplainerSession`, `MGExplainerReport`): the explainer's own
        /// reasons, and the lesson and solid reasons it names itself.
        case explainer
    }
    /// `refusal`, or `warning`: listed in `MGSolidDocument.warnings`; the strict profile refuses some (`strict`).
    public enum Kind: String, Sendable { case refusal, warning }

    public var pattern: String
    public var meaning: String
    public var formats: [Format]
    public var kind: Kind
    /// True for a warning the strict profile (`MGSolidProfile.strict`, `marty-solid check --strict`) refuses.
    public var strict: Bool

    /// True when `reason` fits the pattern, every slot holding a value of its domain.
    public func matches(_ reason: String) -> Bool { MGSolidReasons.slotCharacters(pattern, reason) != nil }

    /// `{"pattern", "meaning", "formats", "kind", "strict"}`.
    public var json: MGJSON {
        .object(["pattern": .string(pattern), "meaning": .string(meaning), "formats": .array(formats.map { MGJSON.string($0.rawValue) }),
                 "kind": .string(kind.rawValue), "strict": .bool(strict)])
    }
}

public enum MGSolidReasons {
    /// The objects whose keys are closed (`<object>.missing.<keys>`, `<object>.unknown.<keys>`). `part.<shape>` is a
    /// shape body; `part.drive.<crank>` is a `crankSlider` or `crankRod` drive. For `.unknown.` the object `component`
    /// is left out: a component definition's unknown top-level keys give the same string as an unknown component in
    /// `use` (`component.unknown.<keys>`, which describes both).
    public static let closedObjects = ["assembly", "params", "part", "part.<shape>", "part.emissive", "part.expect", "part.repeat",
                                       "part.drive.follow", "part.drive.<crank>", "constraint.gearMesh",
                                       "step", "step.check", "step.section", "component", "component.param.<ident>", "component.use"]

    /// Each slot and the values it holds (a regular expression over the reason's characters).
    public static let slots: [String: String] = [
        "n": "[1-9][0-9]*",
        "id": token, "name": token,
        "ident": "[A-Za-z][A-Za-z0-9_]{0,23}",
        "shape": MGSolidParser.shapeKeys.keys.sorted().joined(separator: "|"),
        "crank": "crankSlider|crankRod",
        "field": "[A-Za-z][A-Za-z0-9]*",
        "list": "focus|highlight",
        "direction": "axisWorld|upWorld",
        "modifier": "[A-Za-z0-9_]{1,32}",
        // `div` and `param` have their own entries (`component.expr.div` also covers a `div` with the wrong operands).
        "op": MGSolidComponents.ops.subtracting(["div", "param"]).sorted().joined(separator: "|"),
        "keys": "\(token)(?:,\(token))*",
    ]
    /// Warning prefixes that an explainer's strict check refuses (besides `MGSolidProfile.strictPrefixes`).
    public static let explainerStrictPrefixes = ["notes.unused."]
    /// An author name after `MGSolidParser.token`.
    static let token = "[A-Za-z0-9_.]{1,32}"
    /// Longest reason `lookup` and `matches` read (a `<keys>` list is bounded by the document size).
    public static let maxReasonBytes = 2 * MGSolidLimits.bytes

    /// The entry for a reason, nil when no pattern matches. When a specific pattern and the general one it refines both
    /// match (`part.gear.bore`, `part.<shape>.<field>`), the one whose slots hold the fewest characters wins; a test
    /// checks that every pattern's own sample reasons resolve to it.
    public static func lookup(_ reason: String) -> MGSolidReason? {
        var best: MGSolidReason?, bestSlots = Int.max
        for (k, e) in catalog.enumerated() {
            guard let n = slotCharacters(compiled[k], reason), n < bestSlots else { continue }
            best = e; bestSlots = n
        }
        return best
    }

    /// The entries whose pattern matches a reason, in catalog order.
    public static func matches(_ reason: String) -> [MGSolidReason] {
        catalog.indices.filter { slotCharacters(compiled[$0], reason) != nil }.map { catalog[$0] }
    }

    /// Characters the slots of `pattern` hold in `reason`, or nil when it does not match.
    static func slotCharacters(_ pattern: String, _ reason: String) -> Int? {
        guard let re = compiledByPattern[pattern] ?? regex(pattern) else { return nil }
        return slotCharacters(re, reason)
    }

    static func slotCharacters(_ re: NSRegularExpression, _ reason: String) -> Int? {
        guard reason.utf8.count <= maxReasonBytes, reason.utf8.allSatisfy({ $0 < 0x80 }) else { return nil }
        let full = NSRange(reason.startIndex..., in: reason)
        guard let m = re.firstMatch(in: reason, options: [.anchored], range: full), m.range == full else { return nil }
        return (1..<m.numberOfRanges).reduce(0) { $0 + (m.range(at: $1).location == NSNotFound ? 0 : m.range(at: $1).length) }
    }

    /// The anchored expression of a pattern: literal characters escaped, each slot a capture group of its domain,
    /// `<object>` one of `closedObjects` (with their own slots).
    static func regex(_ pattern: String) -> NSRegularExpression? {
        func body(_ p: String) -> String {
            var out = "", i = p.startIndex
            while i < p.endIndex {
                if p[i] == "<", let close = p[i...].firstIndex(of: ">") {
                    let name = String(p[p.index(after: i)..<close])
                    if name == "object" {
                        let unknown = p[close...].hasPrefix(">.unknown.")
                        let objects = closedObjects.filter { !(unknown && $0 == "component") }
                        out += "(?:" + objects.map { body($0) }.joined(separator: "|") + ")"
                    } else {
                        out += "(" + (slots[name] ?? "(?!)") + ")"
                    }
                    i = p.index(after: close)
                } else {
                    out += NSRegularExpression.escapedPattern(for: String(p[i])); i = p.index(after: i)
                }
            }
            return out
        }
        return try? NSRegularExpression(pattern: "^" + body(pattern) + "$")
    }

    /// One compiled expression per catalog entry, in catalog order, and the same by pattern.
    static let compiled: [NSRegularExpression] = catalog.map { regex($0.pattern)! }
    static let compiledByPattern: [String: NSRegularExpression] = Dictionary(uniqueKeysWithValues: zip(catalog.map(\.pattern), compiled))

    /// `{"catalog": "martygraphics.solid.reasons/1", "slots", "closedObjects", "formats", "reasons": [entries]}`.
    public static var json: MGJSON {
        let formats: [String: MGJSON] = [
            "assembly": "Assembly documents, and every compile of one: a patch recompiles the document; a component compiles on its own.",
            "patch": "Patches (MGSolidParser.applying).", "component": "Component definitions and use entries.",
            "check": "The check report (MGSolidReport, marty-solid check), after the document compiles.",
            "snapshot": "MGSolidSnapshot.decode(data:).", "section": "MGSolidSection.cut and estimate called directly.",
            "cli": "The marty-solid tool.",
            "explainer": "Explainer documents and streams (MGExplainer, MGExplainerSession, MGExplainerReport).",
        ].mapValues { .string($0) }
        return .object(["catalog": .string("martygraphics.solid.reasons/1"),
                        "slots": .object(slots.mapValues { MGJSON.string($0) }),
                        "closedObjects": .array(closedObjects.map { MGJSON.string($0) }),
                        "formats": .object(formats), "reasons": .array(catalog.map(\.json))])
    }

    private static func r(_ pattern: String, _ formats: [MGSolidReason.Format], _ meaning: String) -> MGSolidReason {
        MGSolidReason(pattern: pattern, meaning: meaning, formats: formats, kind: .refusal, strict: false)
    }
    private static func x(_ pattern: String, _ meaning: String) -> MGSolidReason {
        MGSolidReason(pattern: pattern, meaning: meaning, formats: [.explainer], kind: .refusal, strict: false)
    }
    private static func w(_ pattern: String, strict: Bool, _ meaning: String) -> MGSolidReason {
        MGSolidReason(pattern: pattern, meaning: meaning, formats: [.assembly], kind: .warning, strict: strict)
    }

    private static let text = "valid text (not empty after trimming, no `<`, `>`, `://` or control characters)"

    /// Every stable reason, grouped as in docs/REASONS.md.
    public static let catalog: [MGSolidReason] = [
        // Input text and document shape.
        r("json", [.assembly, .component], "The bytes are not UTF-8 JSON text (invalid UTF-8, a raw NUL byte, or text the JSON parser rejects)."),
        r("unknown", [.assembly, .component], "An unexpected internal error. Please report it with the input."),
        r("assembly.bytes", [.assembly, .patch], "The document is over 64 KiB (`MGSolidLimits.bytes`): its bytes, or its canonical JSON after a patch."),
        r("assembly.depth", [.assembly, .patch], "The document nests deeper than 64 levels (`MGLimits.depth`)."),
        r("assembly.object", [.assembly], "The document is not a JSON object."),
        r("assembly.kind", [.assembly], "`kind` is not \"assembly\"."),
        r("assembly.version", [.assembly], "`v` is not 1 or 2."),
        r("assembly.units", [.assembly], "`units` is present and is not \"mm\"."),
        r("assembly.title", [.assembly], "The title is not \(text) of at most 80 characters, also after placeholders are filled."),
        r("assembly.budget", [.assembly], "Part meshes plus step cuts would exceed 1,500,000 triangles or 1,000,000 vertices (counted before any mesh is built)."),
        r("assembly.invalid", [.assembly], "The compiled assembly failed its structural validation (a parent, drive source or explode window the earlier checks did not refuse)."),
        r("<object>.missing.<keys>", [.assembly, .component], "Required keys are missing from an object. `<object>` names the object (see `closedObjects`); `<keys>` lists the missing keys."),
        r("<object>.unknown.<keys>", [.assembly, .component], "An object has keys it does not allow (in a v1 document this includes every v2 key). `<object>` names the object (see `closedObjects`; a component definition's own unknown keys give `component.unknown.<keys>`); `<keys>` lists the keys."),
        r("part.at", [.assembly], "A part's `at` is not three coordinates in -4000...4000 mm."),
        r("part.rot", [.assembly], "A part's `rot` is not [axisX, axisY, axisZ, degrees] with a non-zero axis (each value in -1000...1000) and an angle in -360...360."),
        r("part.<shape>.at", [.assembly], "A shape's `at` is not three coordinates in -4000...4000 mm."),
        r("part.<shape>.rot", [.assembly], "A shape's `rot` is not [axisX, axisY, axisZ, degrees] with a non-zero axis and an angle in -360...360."),
        r("component.use.at", [.assembly, .component], "A `use` entry's `at` is not three coordinates in -4000...4000 mm."),
        r("component.use.rot", [.assembly, .component], "A `use` entry's `rot` is not [axisX, axisY, axisZ, degrees] with a non-zero axis and an angle in -360...360."),
        r("tier.key", [.assembly, .explainer], "A v2 document has a key named `tier` somewhere (tiers are computed by the engine, never authored)."),
        // Parameters.
        r("params", [.assembly], "`params` is not an object."),
        r("params.input", [.assembly], "`params.input` is not a number in -1e6...1e6."),
        r("params.explode", [.assembly], "`params.explode` is not a number in 0...1."),
        // Parts.
        r("parts.count", [.assembly, .component], "`parts` is not an array of 1–48 entries, or component expansion makes more than 48 wire parts."),
        r("parts.resolved", [.assembly], "More than 96 parts after `repeat` expansion."),
        r("id.duplicate.<id>", [.assembly, .component], "Two parts, `repeat` copies, component instances or anchors share an id (they share one namespace)."),
        r("ref.unknown.<id>", [.assembly, .patch], "A reference names no part: a `parent`, a drive `source` or `crank`, a constraint, a step id list, a section part, or a patch part id."),
        r("part.object", [.assembly], "A part entry is not an object."),
        r("part.id", [.assembly, .component], "A part id is not an identifier (an ASCII letter, then up to 23 ASCII letters, digits or `_`)."),
        r("part.name", [.assembly], "A part name is not \(text) of at most 60 characters."),
        r("part.parent", [.assembly], "`parent` is not an identifier."),
        r("part.parent.cycle", [.assembly], "Parents form a cycle."),
        r("part.parent.repeat", [.assembly], "A repeated child of a repeated parent does not repeat the same number of times (copies pair by instance)."),
        r("part.shape", [.assembly], "A shape entry is not an object with exactly one shape kind."),
        r("part.shape.count", [.assembly], "A part has no shape or more than 8."),
        r("part.shape.gears", [.assembly], "A part has more than one `gear` or `ringGear` shape."),
        r("part.shape.unknown.<name>", [.assembly], "Unknown shape kind (gear, ringGear, shaft, tube, box, hex, plate, carrier, extrudedProfile, revolvedProfile, blade, bladeRow)."),
        r("part.material", [.assembly], "Unknown material: not a preset name, `anodized.<role>` or `plastic.<role>`."),
        r("part.joint", [.assembly], "`joint` is not an object with exactly one kind."),
        r("part.joint.unknown.<name>", [.assembly], "Unknown joint kind (revolute, prismatic)."),
        r("joint.axis", [.assembly], "A joint axis is not three coordinates, or it is zero."),
        r("part.explode", [.assembly], "`explode` is not three coordinates in -4000...4000 mm."),
        r("part.explodeWindow", [.assembly], "`explodeWindow` is not [lo, hi] with 0 ≤ lo < hi ≤ 1."),
        r("part.phase", [.assembly], "`phase` is not a number of degrees in -360...360."),
        r("part.smooth", [.assembly], "`smooth` is not a crease angle in 0...180 degrees."),
        r("part.offAxis", [.assembly], "`offAxis` is not a boolean (v2)."),
        r("part.opacity", [.assembly], "`opacity` is not a number in 0.1...1 (v2)."),
        r("part.emissive", [.assembly], "`emissive` is not an object, or its `intensity` is not in 0...4 (v2)."),
        r("part.emissive.role", [.assembly], "`emissive.role` is not a colour role (v2)."),
        r("part.expect", [.assembly], "`expect` is not a non-empty object (v2)."),
        r("part.expect.<direction>", [.assembly], "`expect.axisWorld` or `expect.upWorld` is not a non-zero direction of three coordinates (v2)."),
        r("part.repeat", [.assembly], "`repeat` is not an object."),
        r("part.repeat.count", [.assembly], "`repeat.count` is not a whole number in 2...12."),
        r("part.repeat.axis", [.assembly], "`repeat.axis` is not a non-zero direction of three coordinates."),
        r("part.repeat.angle", [.assembly], "`repeat.angle` is not in -360...360 degrees."),
        // Shapes.
        r("part.<shape>", [.assembly], "A shape's body is not an object."),
        r("part.<shape>.<field>", [.assembly], "A shape field is missing, not a number, out of its range, or not a whole number where one is needed (teeth, arms, counts), or a size derived from it fails (a ring gear's teeth: tip radius not above base radius; a box `size`)."),
        r("part.<shape>.chamfer", [.assembly], "The chamfer is too large for the shape (for example half the width or more), or the chamfered cap outlines would cross."),
        r("part.<shape>.tip", [.assembly], "A gear or ring gear tooth has no real tip land (too few teeth for the pressure angle and backlash)."),
        r("part.<shape>.profile", [.assembly], "The sampled tooth outline of a gear or ring gear crosses itself, or a ring's tooth spaces close at the root."),
        r("part.<shape>.outer", [.assembly], "A ring gear's `outer` radius is less than one module beyond its root circle, or a tube's `outer` is not larger than its `inner`."),
        r("part.gear.bore", [.assembly], "The bore reaches the tooth root (it must stay half a module inside the root circle)."),
        r("part.gear.keyway", [.assembly], "`keyway` is not [width, depth] in 0.1...1000, has no bore, is not narrower than the bore, or reaches the root."),
        r("part.<shape>.holes", [.assembly], "Holes are not a list of valid entries: a plate takes at most 32 [x, y, radius]; an extruded profile at most 16 simple loops inside its outline."),
        r("part.plate.holes.outside", [.assembly], "A plate hole (grown by the chamfers) leaves less than 0.5 mm of rim."),
        r("part.<shape>.holes.overlap", [.assembly], "Two plate holes are closer than 0.5 mm (after chamfers), or two profile holes cross or nest."),
        r("part.carrier.armWidth", [.assembly], "Carrier arms are wider than twice the boss radius, or the hub reaches beyond radius + boss."),
        r("part.<shape>.points", [.assembly], "Profile points are not 3–256 [x, y] pairs (2–256 for a revolved profile), enclose no area, or cross themselves."),
        r("part.revolvedProfile.points.radius", [.assembly], "A revolved profile point has x < 0 (x is the radius)."),
        r("part.revolvedProfile.axis", [.assembly], "An open revolved profile has fewer than 3 points, or it does not start and end on the axis (x = 0)."),
        r("part.revolvedProfile.sweep", [.assembly], "`sweep` is not in 1...360 degrees."),
        r("part.revolvedProfile.start", [.assembly], "`start` is not in -360...360 degrees."),
        r("part.blade.twist", [.assembly], "|`pitch` + `twist`| exceeds 85 degrees."),
        r("part.bladeRow.twist", [.assembly], "|`stagger` + `twist`| exceeds 85 degrees."),
        r("part.bladeRow.triangles", [.assembly], "The blade row would have more than 250,000 triangles."),
        r("part.bladeRow.chord", [.assembly], "A blade section reaches half a turn of its cylinder (the chord is too large for the radius)."),
        r("part.bladeRow.count", [.assembly], "Neighbouring blades touch (too many blades for the chord)."),
        // Drives.
        r("part.drive.joint", [.assembly], "A part without a joint has a drive."),
        r("part.drive", [.assembly], "`drive` is not an object with exactly one kind."),
        r("part.drive.input", [.assembly], "`drive.input` is not a number in -1000...1000."),
        r("part.drive.follow", [.assembly], "`drive.follow` is not an object."),
        r("part.drive.follow.source", [.assembly], "`follow.source` is not a string, or it names the part itself."),
        r("part.drive.follow.ratio", [.assembly], "`follow.ratio` is not a number in -1000...1000."),
        r("part.drive.<crank>", [.assembly], "A `crankSlider` or `crankRod` body is not an object."),
        r("part.drive.<crank>.crank", [.assembly], "A crank drive's `crank` is not a string, or it names the part itself."),
        r("part.drive.<crank>.radius", [.assembly], "A crank drive's `radius` is not a length in 0.05...4000 mm."),
        r("part.drive.<crank>.rod", [.assembly], "A crank drive's `rod` is not a length in 0.05...4000 mm, or it is not longer than the crank radius."),
        r("part.drive.crankSlider.joint", [.assembly], "A `crankSlider` part does not have a prismatic joint."),
        r("part.drive.unknown.<name>", [.assembly], "Unknown drive kind (input, follow, crankSlider, crankRod)."),
        r("part.drive.cycle", [.assembly], "Drives depend on each other in a cycle."),
        // Constraints.
        r("constraints.count", [.assembly, .component], "`constraints` is not an array of at most 128 entries (component constraints included)."),
        r("constraint.object", [.assembly], "A constraint is not an object with exactly one kind."),
        r("constraint.unknown.<name>", [.assembly], "Unknown constraint kind (fixed, gearMesh)."),
        r("constraint.fixed", [.assembly], "`fixed` is not a part id string."),
        r("constraint.gearMesh", [.assembly], "A `gearMesh` body is not an object."),
        r("constraint.gearMesh.ref", [.assembly], "`a` or `b` is not a string."),
        r("constraint.gearMesh.repeat", [.assembly], "`a` and `b` name repeated parts with different counts."),
        r("constraint.gearMesh.carrier", [.assembly], "The carrier is unknown, its axis is not parallel to the mesh, neither gear is under it, a gear outside it is off its axis, or it does more than spin about that axis."),
        r("constraint.gearMesh.gear", [.assembly], "A meshed part has no `gear` or `ringGear` shape."),
        r("constraint.gearMesh.self", [.assembly], "A gear meshes with itself."),
        r("constraint.gearMesh.module", [.assembly], "The two gears have different modules."),
        r("constraint.gearMesh.kind", [.assembly], "`b` is a ring gear (a ring gear can only be `a`)."),
        r("constraint.gearMesh.pressureAngle", [.assembly], "The two gears have different pressure angles."),
        r("constraint.gearMesh.joint", [.assembly], "A gear's joint axis does not run along the gear axis through its centre, or a meshed gear cannot turn."),
        r("constraint.gearMesh.axis", [.assembly], "The two gear axes are not parallel."),
        r("constraint.gearMesh.distance", [.assembly], "The centre distance differs from the standard distance by more than 0.02 module."),
        r("constraint.gearMesh.parentMoves", [.assembly], "A moving ancestor of a gear has no revolute axis, so the gear centre would move."),
        r("constraint.gearMesh.parentRotates", [.assembly], "A moving ancestor of a gear turns about an axis that is not the mesh axis through the gear centre."),
        r("constraint.gearMesh.parentDrive", [.assembly], "A turning ancestor of a gear has its own drive."),
        r("constraint.gearMesh.interference", [.assembly], "The tooth outlines overlap by more than 0.01 module over one pitch (undercut or too small a tooth difference)."),
        r("constraint.gearMesh.phase", [.assembly], "The teeth cannot be phased to mesh around a loop of gears."),
        r("constraint.gearMesh.motion", [.assembly], "Replaying the compiled motion breaks a mesh (axis, centre distance, tooth phase or tooth ratio)."),
        r("constraint.underdetermined", [.assembly], "A gear's speed is not fixed by the inputs, `fixed` constraints and meshes."),
        r("constraint.ratio", [.assembly], "A solved joint ratio exceeds 1000 per input radian."),
        r("constraint.conflict", [.assembly], "Inputs, `fixed` constraints and meshes contradict each other."),
        r("constraint.conflict.drive", [.assembly], "A part that the mesh solve moves also has its own drive."),
        // Steps.
        r("steps.count", [.assembly], "`steps` is not an array of at most 16 entries."),
        r("step.object", [.assembly], "A step is not an object."),
        r("step.say", [.assembly], "A step's `say` is not \(text) of at most 240 characters, also after placeholders are filled."),
        r("step.<list>", [.assembly, .component], "A step id list (`focus`, `highlight`) is not an array of at most 16 strings."),
        r("step.camera", [.assembly], "`camera` is not a camera preset name."),
        r("step.explode", [.assembly], "`explode` is not a number in 0...1."),
        r("step.orbit", [.assembly], "`orbit` is not in -360...360 degrees."),
        r("step.spin", [.assembly], "`spin` is not in -20...20 input turns."),
        r("step.unchecked", [.assembly], "`unchecked` is not \(text) of at most 60 characters (v2)."),
        r("step.check", [.assembly], "`check` is not an array of 1–8 claim checks (v2)."),
        r("step.ghost", [.assembly], "`ghost` is not a non-empty array of at most 16 part id strings (v2)."),
        r("step.section", [.assembly], "`section` is not an object (v2)."),
        r("step.section.normal", [.assembly], "`section.normal` is not a non-zero direction of three coordinates."),
        r("step.section.offset", [.assembly], "`section.offset` is not in -4000...4000 mm."),
        r("step.section.parts", [.assembly], "`section.parts` is not 1–16 part id strings."),
        // Claim checks and text.
        r("check.object", [.assembly, .explainer], "A claim check is not an object."),
        r("check.value", [.assembly, .explainer], "A claim check's `value` is not a fact name."),
        r("check.comparison", [.assembly, .explainer], "A claim check does not have exactly one of `eq`, `lt`, `gt`."),
        r("check.eq", [.assembly, .explainer], "The `eq` target is not a number in -1e6...1e6."),
        r("check.lt", [.assembly, .explainer], "The `lt` target is not a number in -1e6...1e6."),
        r("check.gt", [.assembly, .explainer], "The `gt` target is not a number in -1e6...1e6."),
        r("check.tol", [.assembly, .explainer], "`tol` is given without `eq`, or it is not in 0...1e6."),
        r("check.fact.<name>", [.assembly, .explainer], "A claim check names a fact that does not exist."),
        r("check.failed.<name>", [.assembly, .explainer], "A claim check is false for the engine's value."),
        r("text.brace", [.assembly], "A `{` or `}` in the title or a caption is unbalanced or nested."),
        r("text.placeholder", [.assembly], "A placeholder is malformed: no valid fact name, too many modifiers, too long, or a modifier with a dot."),
        r("text.placeholder.<name>", [.assembly], "A placeholder names no fact."),
        r("text.modifier.<modifier>", [.assembly, .explainer], "Unknown placeholder modifier (abs, inv, pct, deg, frac)."),
        r("text.modifier.<modifier>.<name>", [.assembly, .explainer], "A modifier cannot apply to this fact: a value with a unit, `pct` or `deg` on a fact that is not a turn rate, a modifier after a terminal one, `inv` of 0, or no exact fraction."),
        r("text.range.<name>", [.assembly], "A placeholder value overflows or underflows, or would print as 0 although it is not 0."),
        r("text.rounding.<name>", [.assembly], "A placeholder would show a non-zero value as \"0\"; use `frac` or `inv`."),
        r("text.number.step.<n>", [.assembly], "A v2 caption has a number character outside a placeholder and the step is not marked `unchecked` (rule N1)."),
        r("text.sign.<name>", [.assembly, .explainer], "`abs` hides a sign that no strict-inequality check in the same step proves (the title can never use `abs`)."),
        r("expect.axis.<id>", [.assembly], "The part's world turn axis differs from `expect.axisWorld` by more than 1 degree (v2)."),
        r("expect.up.<id>", [.assembly], "The part's local +Z in the world differs from `expect.upWorld` by more than 1 degree (v2)."),
        // Step section cuts.
        r("section.miss.<id>", [.assembly], "A step's section plane misses a listed part."),
        r("section.empty.<id>", [.assembly], "A step's section plane removes a listed part completely."),
        r("section.open.<id>", [.assembly], "A built cut fails the consistency check (closed, outward, caps without overlap)."),
        r("section.loops.<id>", [.assembly], "The open edges of a cut do not chain into closed loops (the part mesh is not closed)."),
        r("section.nesting.<id>", [.assembly], "A hole loop of a cut has no outer loop that contains it."),
        r("section.mesh.<id>", [.assembly], "The part mesh is malformed or the plane is not finite."),
        r("section.budget", [.assembly, .section], "The step cuts exceed the section work budget (part triangles read, or cap work)."),
        r("section.miss", [.section], "The plane misses the mesh."),
        r("section.empty", [.section], "The plane removes the whole mesh."),
        r("section.loops", [.section], "The open edges of the cut do not chain into closed loops."),
        r("section.nesting", [.section], "A hole loop has no outer loop that contains it."),
        r("section.mesh", [.section], "The mesh is malformed or the plane is not finite."),
        // Honesty warnings.
        w("joint.idle.<id>", strict: true, "A jointed part that no drive or constraint moves, so it never moves."),
        w("frame.axis.off.<id>", strict: true, "A revolute part's axis line misses its own mesh bounds (mark an intended outside axis with `\"offAxis\": true`, v2)."),
        w("frame.child.absolute.<id>", strict: false, "A child placed as if its `at` / `rot` were world values (the double offset), confirmed by bounds."),
        w("frame.child.far.<id>", strict: false, "A child's bounds miss its parent's bounds grown by 1.5 parent sizes."),
        // Patches.
        r("patch.bytes", [.patch], "The patch text is over 64 KiB."),
        r("patch.json", [.patch], "The patch bytes are not UTF-8 JSON text (invalid UTF-8, a raw NUL byte, or text the JSON parser rejects)."),
        r("patch.depth", [.patch], "The patch nests deeper than 64 levels."),
        r("patch.object", [.patch], "The patch is not a JSON object."),
        r("patch.unknown.<keys>", [.patch], "The patch has keys other than params, parts, constraints, steps and title (`<keys>` lists them)."),
        r("patch.unknown.", [.patch], "The patch is an empty object."),
        r("patch.source", [.patch], "The document has no object source to patch."),
        r("patch.parts", [.patch], "`parts` is not an object of edits by id, or the document has no parts array."),
        r("patch.parts.object", [.patch], "A part edit is not an object."),
        r("patch.parts.id", [.patch], "A part edit sets `id` (ids are stable)."),
        r("patch.parts.set", [.patch], "An edit of a part inside a component instance cannot merge into that `use` entry's `set`."),
        // Components.
        r("component.bytes", [.component, .cli], "A definition is over 16 KiB (its bytes, or its canonical JSON)."),
        r("component.nesting", [.component], "A definition nests deeper than 64 levels."),
        r("component.object", [.component], "A definition is not a JSON object."),
        r("component.version", [.component], "`v` is not 1."),
        r("component.kind", [.component], "`kind` is not \"component\"."),
        r("component.id", [.component], "The component id is not an identifier."),
        r("component.title", [.component], "The title is not \(text) of at most 80 characters."),
        r("component.about", [.component], "`about` is not \(text) of at most 160 characters."),
        r("component.params", [.component], "`params` is not an object of at most 16 parameters."),
        r("component.param.name.<name>", [.component], "A parameter name is not an identifier, or it is an expression operator name."),
        r("component.param.<ident>", [.component], "A parameter is not an object with numbers min ≤ default ≤ max in ±1e6, a boolean `integer` (whole bounds and default when true) and an `about` of valid text."),
        r("component.parts.count", [.component], "`parts` is not an array of 1–24 entries."),
        r("component.part", [.component], "A part entry is not an object with a string id (after parameters are substituted)."),
        r("component.use", [.component], "A nested `use` is not a string."),
        r("component.use.parent", [.component], "A `use` entry's `parent` is not a string."),
        r("component.cycle.<id>", [.component], "A component uses itself, directly or through other components."),
        r("component.unknown.<keys>", [.assembly, .component], "`use` names a component that is not in the library (`<keys>` is then its id). The same string also answers a component definition with unknown top-level keys: one string, two causes."),
        r("component.depth", [.assembly, .component], "`use` nests more than 3 levels deep."),
        r("component.constraints", [.component], "`constraints` is not an array of at most 32 entries."),
        r("component.anchors", [.component], "`anchors` is not an object of at most 8 anchors."),
        r("component.anchor.<name>", [.component], "An anchor name is not an identifier or is taken, or its target is not a part, copy or nested anchor of the component."),
        r("component.checks", [.component], "`checks` is not an object of at most 8 checks."),
        r("component.check.name.<name>", [.component], "A check name is not an identifier."),
        r("component.check", [.component], "A check is not `{\"lt\": [a, b]}`, `{\"le\": [a, b]}` or `{\"int\": a}`."),
        r("component.check.<ident>", [.assembly, .component], "A component check is false for the parameters of an instance."),
        r("component.expr", [.component], "An expression has an unknown operator or is not a number or an expression."),
        r("component.expr.<op>", [.component], "An expression operator (add, mul, min, max, sub, neg, pi, sin, cos) has the wrong operands (`<op>` names it)."),
        r("component.expr.depth", [.component], "An expression nests deeper than 8 levels."),
        r("component.expr.size", [.component], "An instance evaluates more than 4,096 expression nodes."),
        r("component.expr.param", [.component], "`param` does not take a string."),
        r("component.expr.param.<name>", [.component], "`param` names no parameter."),
        r("component.expr.div", [.component], "Division by zero, or `div` without exactly two operands (one string, two causes)."),
        r("component.expr.range", [.component], "An expression result is not finite or exceeds ±1e6."),
        r("component.param.unknown.<name>", [.assembly, .component], "`with` names no parameter of the component."),
        r("component.param.value.<ident>", [.assembly, .component], "A `with` value is not a finite number."),
        r("component.param.range.<ident>", [.assembly, .component], "A `with` value is outside the parameter's min...max."),
        r("component.param.integer.<ident>", [.assembly, .component], "A `with` value is not whole for an integer parameter."),
        r("component.with", [.assembly, .component], "`with` is not an object."),
        r("component.set", [.assembly, .component], "`set` is not an object."),
        r("component.set.repeat.<id>", [.assembly, .component], "`set` names one copy of a repeated part; edit the base id (every copy)."),
        r("component.set.unknown.<id>", [.assembly, .component], "`set` names no part of the instance."),
        r("component.set.id", [.assembly, .component], "A `set` entry is not an object, or it sets `id` or `use`."),
        r("component.id.length", [.assembly, .component], "A resolved part id (`stage1.gears.pinion`, with any `repeat` suffix) is longer than 64 characters."),
        r("component.ref.unknown.<id>", [.component], "A reference inside a component names no inner part, copy or anchor."),
        r("ref.component.<id>", [.assembly], "A part reference names a component instance (a group); only steps may name an instance."),
        r("component.duplicate.<id>", [.component], "The library already has a component with this id."),
        r("component.library.count", [.component], "The library already holds 128 components."),
        // Check report.
        r("check.meshOpen", [.check], "A part mesh or a step cut is not closed (`checks.openMeshes` lists them; a cut as `step.<n>.<part>`)."),
        r("check.gearsInterpenetrate", [.check], "The gear tooth sweep over one input turn overlaps more than `checks.toleranceMM` (0.01 of the smallest module)."),
        // Snapshots.
        r("solidSnapshot.bytes", [.snapshot], "The snapshot text is over 256 MiB (`MGSolidSnapshot.maxBytes`)."),
        r("solidSnapshot.json", [.snapshot], "The snapshot bytes are not valid UTF-8, or they hold a raw NUL byte."),
        r("solidSnapshot.depth", [.snapshot], "The snapshot text nests deeper than 64 levels."),
        r("solidSnapshot.number", [.snapshot], "A number literal is longer than 64 characters or does not read as a finite number (for example `1e999`)."),
        r("solidSnapshot.invalid", [.snapshot], "The JSON decoder or a validating initialiser refused the snapshot (format, slot sizes, ranges, v2 fields in /1)."),
        // Tool.
        r("report.encoding", [.check, .cli], "A value given to `MGSolidReport.text` or as render manifest outputs is not finite or nests too deep, so it is not encoded (reports the engine builds never are)."),
        r("report.engine", [.check, .explainer], "The host's `engine` value is not finite, nests deeper than 8 levels or is larger than 4,096 bytes (`MGSolidReport.engineDepth`, `engineBytes`)."),

        // Explainer documents (docs/EXPLAINER.md).
        x("explainer.json", "The document bytes are not UTF-8 JSON text."),
        x("explainer.object", "The document, or a header statement's value, is not a JSON object."),
        x("explainer.number", "A document or statement built in code holds NaN or an infinity."),
        x("explainer.depth", "The document nests deeper than 63 levels, or a stream statement deeper than 64."),
        x("explainer.bytes", "The raw document is over 128 KiB, its flattened statement stream is over 64 KiB, or a stream received more than 64 KiB."),
        x("explainer.version", "`v` is not 1 (the explainer format version)."),
        x("explainer.kind", "`kind` is not \"explainer\"."),
        x("explainer.missing", "A header statement has no `v`."),
        x("explainer.unknown.<keys>", "The document or a header statement has keys it does not allow (`<keys>`: sorted author segments)."),
        x("explainer.title", "The title is not plain text of 1–80 characters after 3D facts fill it, or it names a 2D value."),
        x("explainer.primary", "`primary` is not \"board\" or \"solid\", or it names a view the explainer does not have."),
        x("explainer.empty", "The explainer has neither a `board` nor a `solid`."),
        x("explainer.header", "A new stream does not start with an explainer header (or `keep`)."),
        x("explainer.statements.count", "A stream holds more than 256 statements (terminal)."),
        x("explainer.board", "`board` is not an object."),
        x("explainer.board.steps", "The board has `steps` (beats replace them)."),
        x("explainer.board.title", "The board has a `title` (the explainer has one title)."),
        x("explainer.board.dim", "The board is `\"dim\": \"3d\"` (3D belongs in `solid`)."),
        x("explainer.board.missing", "A beat command needs a board, and the explainer has none."),
        x("explainer.solid", "`solid` is not an object."),
        x("explainer.solid.version", "The solid is not an assembly v2."),
        x("explainer.solid.steps", "The solid has `steps` (beats replace them)."),
        x("explainer.solid.title", "The solid has a `title` (the explainer has one title)."),
        x("explainer.solid.missing", "A beat `view` needs a solid, and the explainer has none."),
        x("explainer.beats", "`beats` is missing, not an array, or empty."),
        x("explainer.beats.count", "More than 16 beats in one explainer, over all its streams."),
        x("explainer.op.title", "A beat command is `title` (the explainer has one title)."),
        x("explainer.id.duplicate.<id>", "A 2D item or control id equals a 3D part, copy, `repeat` base, instance or anchor id, or a control id equals a 2D item id (one namespace)."),
        x("explainer.id.view.<id>", "A 2D command (`set`, `remove`) names a 3D id."),
        x("notes.object", "`notes` is not an object."),
        x("notes.count", "`notes` has no entry or more than 24."),
        x("notes.entry.<id>", "A note key is not an item id, or its value is not exactly one of `basis` and `unchecked`."),
        x("notes.text.<id>", "A note's text is not plain text of 1–60 characters."),
        x("notes.view.<id>", "A note key names a 3D id (notes mark 2D items only)."),
        MGSolidReason(pattern: "notes.unused.<id>", meaning: "A note names no 2D item the board ever has.",
                      formats: [.explainer], kind: .warning, strict: true),
        x("beat.object", "A beat is not an object."),
        x("beat.missing", "A beat has no `say`."),
        x("beat.unknown.<keys>", "A beat or a `say` statement has keys it does not allow."),
        x("beat.unchecked.<n>", "Beat `<n>`'s `unchecked` is not plain text of 1–60 characters."),
        x("beat.ops", "A beat's `ops` is not an array."),
        x("beat.ops.count", "A beat has more than 12 commands."),
        x("beat.check", "A beat's `check` is not an array."),
        x("beat.checks.count", "A beat has more than 8 checks, 2D and 3D together."),
        x("beat.refused", "A statement belongs to a beat that a failed check already refused (a cascade)."),
        x("beat.highlight", "A `highlight` is not an array of strings."),
        x("beat.highlight.count", "A `highlight` has no id or more than 16."),
        x("beat.highlight.ref.<id>", "A highlight id names no 2D item, control, 3D member or table row or cell of the board at that beat."),
        MGSolidReason(pattern: "beat.highlight.stale.<id>", meaning: "At presentation a highlight id no longer resolves; it is dropped and recorded in `hostIssues` (nothing is refused).",
                      formats: [.explainer], kind: .warning, strict: false),
        x("stmt.json", "A stream statement is not UTF-8 JSON text, or non-whitespace text between statements was skipped."),
        x("stmt.kind", "A stream statement is not one of the explainer statement kinds."),
        x("stmt.order", "A statement comes out of order (a view after the first beat or twice, a beat statement with no open beat, a header mid-stream)."),
        x("stmt.bytes", "A statement other than `solid` is over 4 KiB."),
        x("stmt.say", "A caption is not a string of 1–200 characters."),
        x("stmt.view.twice", "A beat has a second `view` statement."),
        x("stmt.highlight.twice", "A beat has a second `highlight` statement."),
        x("lesson.depth", "A statement other than `solid` nests deeper than 59 levels (the lesson statement cap)."),
        x("view.object", "A beat `view` is not an object."),
        x("view.unknown.<keys>", "A beat `view` has keys that are not view keys (focus, explode, camera, orbit, spin, section, ghost)."),
        x("view.focus", "A beat view's `focus` is not an array of at most 16 strings."),
        x("view.camera", "A beat view's `camera` is not a camera preset name."),
        x("view.explode", "A beat view's `explode` is not a number in 0...1."),
        x("view.orbit", "A beat view's `orbit` is not a number of degrees in -360...360."),
        x("view.spin", "A beat view's `spin` is not a number of input turns in -20...20."),
        x("view.ghost", "A beat view's `ghost` is not a non-empty array, or it has more than 16 entries or a non-string entry."),
        x("view.section", "A beat view's `section` is not an object."),
        x("view.section.normal", "A beat view's section normal is not three coordinates, or it is zero."),
        x("view.section.offset", "A beat view's section offset is not in -4000...4000 mm."),
        x("view.section.parts", "A beat view's section `parts` is not an array of 1–16 strings."),
        x("view.section.missing.<keys>", "A beat view's `section` has no `normal` or no `parts`."),
        x("view.section.unknown.<keys>", "A beat view's `section` has keys it does not allow."),
        x("check.unknown.<keys>", "A 3D check (dotted `value`) has keys it does not allow (the assembly's `step.check.unknown.<keys>`)."),
        x("text.number.beat.<n>", "Beat `<n>`'s caption types a number character outside a placeholder and has no `unchecked` (rule N1)."),
        x("text.number.item.<id>", "A 2D item without a note shows a typed number: in its text, a table or array cell, a bar value or a plot range (rule N1)."),
        x("text.number.control.<id>", "A control label types a number character (rule N1; a label takes no placeholder)."),
        x("text.number.template", "A raw template's params carry a string with a typed number (rule N1)."),
        x("snapshot.bytes", "An explainer snapshot is over its size cap."),
        x("snapshot.number", "An explainer snapshot holds NaN or an infinity."),
        x("snapshot.json", "Explainer snapshot text is not UTF-8 JSON."),
        x("snapshot.setup", "The explainer snapshot's set-up commands are not valid."),
        x("snapshot.controls", "A saved control is not one that a checked `bind` of the script or the host made (its label is learner-visible text)."),
        x("snapshot.depth", "An explainer snapshot nests deeper than 64 levels."),
        x("snapshot.kind", "The value is not an explainer snapshot."),
        x("snapshot.version", "The explainer snapshot version is not 1."),
        x("snapshot.header", "The explainer snapshot has no header object."),
        x("snapshot.header.missing", "The explainer snapshot header has no `v`."),
        x("snapshot.header.unknown.<keys>", "The explainer snapshot header has keys it does not allow."),
        x("snapshot.frozen", "The explainer snapshot's `frozen` flag is not a boolean."),
        x("snapshot.beats", "The explainer snapshot's beat records are not valid, or a kept beat is neither shown nor queued in the lesson."),
        x("snapshot.next", "The explainer snapshot's statement position is not valid."),
        x("snapshot.board", "The explainer snapshot's board is not valid, or the board and the boardless lesson disagree."),
        x("snapshot.solid", "The explainer snapshot's solid is not valid JSON text, or 3D beat data has no solid."),
        x("snapshot.lesson", "The explainer snapshot's lesson snapshot is not JSON text."),
        x("snapshot.pending", "A beat the restored lesson still queues does not match the explainer's beat, or a queued command breaks the explainer's command rules."),
        x("snapshot.presented", "The explainer snapshot's presented beats are not valid."),
        x("snapshot.beat", "The explainer snapshot's presented beat names no kept beat, or not the lesson's presented beat."),
        x("snapshot.stream", "The explainer snapshot's stream status is not valid."),
        r("kind.unsupported", [.cli], "`marty-solid check` or `render` got a lesson document (`\"kind\": \"lesson\"`), a format the tool does not take."),
    ]
}
