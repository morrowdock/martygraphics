// SPDX-License-Identifier: Apache-2.0
import Foundation

// Truth-tier calculus over a compiled solid document: claims, the learner legend, badges and `describe(id)`.
// The engine computes every tier from what produced a claim; nothing here reads an author-set tier.
// Foundation only, deterministic.

/// One visible claim with its engine-computed tier and the chip text a renderer shows.
public struct MGSolidClaim: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable { case motion, caption, title, check, annotation }
    public var kind: Kind
    /// Part id (motion; the base id for `repeat` copies), an annotation id (annotation), `step.<n>` (caption,
    /// 1-based), `title`, or `step.<n>.check.<k>` (a claim check, 1-based).
    public var id: String
    public var tier: MGSolidTier
    /// Chip text: "Solved" (motion), "Numbers solved" (caption, title), "Checked" (check), "Schematic motion",
    /// "Schematic" or "Not checked".
    public var badge: String
    /// Engine text that says why the claim has this tier.
    public var why: String
}

/// The scene legend: claim counts by tier, its one-line text and engine-generated notes. Always shown (owner D4).
public struct MGSolidLegend: Equatable, Sendable {
    public var claims: [MGSolidClaim]
    public var solved: Int
    public var built: Int
    public var described: Int
    /// For example "Solved 9 · Schematic 2 · Not checked 1" (groups with no claims are left out).
    public var text: String
    /// "Some motion is schematic" when a motion claim is below Solved; the author cannot remove it.
    public var note: String?
    /// Static parts make no motion claim; their shapes are as authored.
    public var shapes: String
    /// Every engine note in order: "Some motion is schematic" (as `note`), then "Arrow lengths are not to scale" when
    /// a non-pointer arrow has no fact length.
    public var notes: [String] = []
}

/// What the engine does not check for each motion source (shown in `describe` and the check report).
public enum MGSolidNotChecked {
    public static let bySource: [String: [String]] = [
        "input": ["what drives the input", "power and torque"],
        "gearMesh": ["3D tooth contact", "load, strength and wear", "friction and efficiency"],
        "follow": ["the mechanism that keeps the authored ratio", "slip"],
        "crankSlider": ["forces and dynamics", "joint clearance"],
        "crankRod": ["forces and dynamics", "joint clearance"],
    ]
}

extension MGSolidTier {
    /// Chip text for a claim of this tier and kind.
    func badge(_ kind: MGSolidClaim.Kind) -> String {
        switch self {
        // A caption's tier covers its numbers, not its words; the chip says so.
        case .solved: return kind == .motion || kind == .annotation ? "Solved" : kind == .check ? "Checked" : "Numbers solved"
        case .built: return kind == .motion ? "Schematic motion" : "Schematic"
        case .described: return "Not checked"
        }
    }
}

enum MGSolidTiers {
    /// Caption or title tier: `described` when marked `unchecked` or when it has a typed number (a number character
    /// outside a placeholder: v1 text, a title); otherwise the lowest tier of the facts it shows; nil when it shows no
    /// engine number. Claim checks never give a caption a tier: the engine cannot tell what the prose claims, so
    /// each check is its own claim.
    static func text(facts: [MGSolidFact], unchecked: Bool, typedNumbers: Bool = false) -> MGSolidTier? {
        if unchecked || typedNumbers { return .described }
        return facts.map(\.tier).min()
    }
}

extension MGSolidDocument {
    /// True when the part's own joint moves: a compiled drive with a non-zero rate, or a crank closed form.
    func ownMotion(_ id: String) -> Bool {
        guard let p = assembly.part(id), p.joint != .fixed, let d = p.drive, let s = motionSources[id] else { return false }
        guard s != "fixed", s != "phase" else { return false }
        switch d {
        case .input(let scale, _): return scale != 0
        case .follow(_, let r, _), .gear(_, let r, _, _): return r != 0
        case .crankSlider, .crankRod: return true
        }
    }

    /// Engine tier of a part's motion: the lowest tier over its own moving joint and every moving ancestor.
    /// nil when the part's own joint does not move (it is static, idle, or only rides on a moving parent).
    public func motionTier(_ id: String) -> MGSolidTier? {
        let id = canonicalPart(id) ?? id
        guard ownMotion(id) else { return nil }
        var tier = driveTiers[id] ?? .solved
        var cur = assembly.part(id)?.parent, seen: Set<String> = [id]
        while let c = cur, seen.insert(c).inserted {
            if ownMotion(c) { tier = min(tier, driveTiers[c] ?? .solved) }
            cur = assembly.part(c)?.parent
        }
        return tier
    }

    /// Every visible claim with its tier. Motion claims are listed once per authored part (`repeat` copies share
    /// their base id), in part order; then annotation claims (labels, arrows, dimensions); then the title and the
    /// captions.
    /// A part that every view hides (the plain view, so `hero.png`, and every step) is never seen: it makes no motion
    /// claim.
    public var claims: [MGSolidClaim] {
        var out: [MGSolidClaim] = []
        var seen = Set<String>()
        let unseen = neverShownParts
        for p in assembly.parts where !unseen.contains(p.id) {
            let base = copies[p.id] ?? p.id
            guard let t = motionTier(p.id), seen.insert(base).inserted else { continue }
            let s = motionSources[p.id] ?? "input"
            let why = t == .solved ? "Moved by \(s)" : (driveTiers[p.id] ?? .solved) < .solved
                ? "Moved by \(s), from a speed or ratio the author set" : "Rides on a part whose motion the author set"
            out.append(MGSolidClaim(kind: .motion, id: base, tier: t, badge: t.badge(.motion), why: why))
        }
        out += annotationClaims
        if let t = titleTier {
            let why = t == .solved ? "Its numbers are engine facts" : t == .described ? "Title has typed numbers" : "It shows a fact below Solved"
            out.append(MGSolidClaim(kind: .title, id: "title", tier: t, badge: t.badge(.title), why: why))
        }
        for (i, s) in steps.enumerated() {
            if let t = s.tier {
                let why: String
                if let u = s.unchecked { why = "Marked unchecked: \(u)" }
                else if version < 2 { why = "Assembly v1 text: its numbers are not checked" }
                else if t == .solved { why = "Its numbers are engine facts; its words are not checked" }
                else { why = "It shows a fact below Solved" }
                out.append(MGSolidClaim(kind: .caption, id: "step.\(i + 1)", tier: t, badge: t.badge(.caption), why: why))
            }
            for (k, c) in s.checks.enumerated() {
                let t = fact(c.value)?.tier ?? .solved
                out.append(MGSolidClaim(kind: .check, id: "step.\(i + 1).check.\(k + 1)", tier: t, badge: t.badge(.check), why: "Checked: \(c.text)"))
            }
        }
        return out
    }

    /// The learner legend (owner D4: always shown).
    public var legend: MGSolidLegend {
        let c = claims
        let n = { (t: MGSolidTier) in c.filter { $0.tier == t }.count }
        let (s, b, d) = (n(.solved), n(.built), n(.described))
        var groups: [String] = []
        if s > 0 { groups.append("Solved \(s)") }
        if b > 0 { groups.append("Schematic \(b)") }
        if d > 0 { groups.append("Not checked \(d)") }
        let note = c.contains { $0.kind == .motion && $0.tier < .solved } ? "Some motion is schematic" : nil
        var notes = note.map { [$0] } ?? []
        if annotations.arrows.contains(where: { $0.meaning != .pointer && !$0.scaled }) { notes.append("Arrow lengths are not to scale") }
        return MGSolidLegend(claims: c, solved: s, built: b, described: d,
                             text: groups.isEmpty ? "No engine-checked claims" : groups.joined(separator: " · "),
                             note: note, shapes: "Shapes as authored", notes: notes)
    }

    /// Annotation claims in authored order (labels, arrows, dimensions); an annotation with no tier makes no claim, and
    /// neither does an arrow that every still listing it drops (`undrawnArrows`).
    var annotationClaims: [MGSolidClaim] {
        var out: [MGSolidClaim] = []
        func add(_ id: String, _ t: MGSolidTier?, _ why: String) {
            guard let t else { return }
            out.append(MGSolidClaim(kind: .annotation, id: id, tier: t, badge: t.badge(.annotation), why: why))
        }
        for l in annotations.labels {
            add(l.id, l.tier, l.unchecked.map { "Marked unchecked: \($0)" }
                ?? (l.tier == .solved ? "Its numbers are engine facts; its words are not checked" : "It shows a fact below Solved"))
        }
        for r in annotations.arrows where !undrawnArrows.contains(r.id) {
            let why: String
            if let u = r.unchecked { why = "Marked unchecked: \(u)" }
            else {
                switch (r.meaning, r.style) {
                case (.motion, .turn): why = "Turn sense from the engine (motion of \(r.on ?? ""))"
                case (.motion, .line): why = r.scaled ? "Direction from the engine; length shows a fact" : "Direction from the engine; length not to scale"
                case (.force, _): why = r.cause == nil ? "Direction and length as authored" : "Direction checked against gravity; length not to scale"
                case (.flow, _): why = "Direction and length as authored"
                case (.pointer, _): why = "Its numbers are engine facts"
                }
            }
            add(r.id, r.tier, why)
        }
        for d in annotations.dimensions {
            add(d.id, d.tier, d.over ? "Measured by the engine over one input turn" : "Measured by the engine at the default input")
        }
        return out
    }

    /// A part id from an id, a component anchor or a `repeat` base id (its first copy); nil when none matches.
    func canonicalPart(_ id: String) -> String? {
        if assembly.part(id) != nil { return id }
        if let a = aliases[id], assembly.part(a) != nil { return a }
        let base = aliases[id] ?? id
        return assembly.parts.first { copies[$0.id] == base }?.id
    }

    /// Facts, motion and tier of one part, its anchor or its `repeat` base id, and what the engine does not check:
    /// `{"id", "name", "motion", "tier", "facts": {name: {value, unit, text, tier, source}}, "notChecked": […]}`.
    /// nil for an unknown id.
    public func describe(_ id: String) -> MGJSON? {
        if let kind = annotations.kind(id) { return describeAnnotation(id, kind) }
        guard let pid = canonicalPart(id), let p = assembly.part(pid) else { return nil }
        let base = copies[pid] ?? pid
        // Facts are keyed by part id or by `repeat` base id; an anchor names one of those.
        let key = aliases[id] ?? id
        let source = motionSources[pid]
        let motion: String
        if let t = motionTier(pid), let s = source {
            var speed = ""
            if let f = facts[pid + ".speed"] {
                let frame = movingAncestor(pid) != nil ? " relative to \(p.parent ?? "its parent")" : ""
                speed = " (\(f.text) turns per input turn\(frame)"
                if !frame.isEmpty { speed += facts[pid + ".worldSpeed"].map { "; \($0.text) in the world frame" } ?? "; no world speed: the axes are not parallel" }
                speed += ")"
            } else if let f = facts[pid + ".travel"] { speed = " (travel \(f.text) per input turn)" }
            motion = t == .solved ? "Solved by \(s)\(speed)" : "Schematic: \(s)\(speed), from numbers the author set"
        } else if p.joint != .fixed && p.drive == nil {
            motion = "Idle: the joint has no drive or constraint, so it never moves"
        } else if let mover = movingAncestor(pid) {
            motion = "Static on \(mover), which moves"
        } else {
            motion = "Static"
        }
        var fs: [String: MGJSON] = [:]
        for (name, f) in facts where name.hasPrefix(key + ".") || name == "count." + base {
            fs[name] = .object(["value": .number(f.value), "unit": .string(f.unit), "text": .string(f.text),
                                "tier": .string(f.tier.name), "source": .string(f.source)])
        }
        let tier = motionTier(pid)
        return .object(["id": .string(key), "name": .string(p.name), "motion": .string(motion),
                        "tier": tier.map { .string($0.name) } ?? .null, "facts": .object(fs),
                        "notChecked": .array((source.flatMap { MGSolidNotChecked.bySource[$0] } ?? []).map { .string($0) })])
    }

    /// `{"id", "kind", "meaning", "tier", "text", "value"?, "anchors"}` of one annotation; anchors are kernel world
    /// points (Z up, mm) at the default input with explode 0.
    func describeAnnotation(_ id: String, _ kind: String) -> MGJSON {
        let pose = assembly.pose(MGPoseParameters(input: defaults.input, explode: 0))
        func point(_ p: MGVec3) -> MGJSON { .array([.number(p.x), .number(p.y), .number(p.z)]) }
        let anchors = MGSolidAnnotationEngine.anchors(annotations, id).map { point($0.world(pose)) }
        var o: [String: MGJSON] = ["id": .string(id), "kind": .string(kind), "anchors": .array(anchors), "meaning": .null, "tier": .null, "text": .null]
        if let l = annotations.label(id) { o["text"] = .string(l.text); o["tier"] = l.tier.map { .string($0.name) } ?? .null }
        if let r = annotations.arrow(id) {
            o["meaning"] = .string(r.meaning.rawValue); o["text"] = r.text.map { .string($0) } ?? .null
            o["tier"] = r.tier.map { .string($0.name) } ?? .null
        }
        if let d = annotations.dimension(id) {
            o["meaning"] = .string(d.kind.rawValue); o["text"] = .string(d.text); o["tier"] = .string(d.tier.name)
            o["value"] = .number(d.value); o["unit"] = .string(d.unit)
        }
        return .object(o)
    }

    /// Nearest ancestor whose own joint moves.
    func movingAncestor(_ id: String) -> String? {
        var cur = assembly.part(id)?.parent, seen: Set<String> = [id]
        while let c = cur, seen.insert(c).inserted {
            if ownMotion(c) { return c }
            cur = assembly.part(c)?.parent
        }
        return nil
    }
}
