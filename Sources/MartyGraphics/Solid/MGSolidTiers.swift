// SPDX-License-Identifier: Apache-2.0
import Foundation

// Truth-tier calculus over a compiled solid document: claims, the learner legend, badges and `describe(id)`.
// The engine computes every tier from what produced a claim; nothing here reads an author-set tier.
// Foundation only, deterministic.

/// One visible claim with its engine-computed tier and the chip text a renderer shows.
public struct MGSolidClaim: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable { case motion, caption, title }
    public var kind: Kind
    /// Part id (motion; the base id for `repeat` copies), `step.<n>` (caption, 1-based) or `title`.
    public var id: String
    public var tier: MGSolidTier
    /// Chip text: "Solved", "Schematic motion", "Schematic" or "Not checked".
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
        case .solved: return "Solved"
        case .built: return kind == .motion ? "Schematic motion" : "Schematic"
        case .described: return "Not checked"
        }
    }
}

enum MGSolidTiers {
    /// Tier of an engine motion source. Every PR-1 source is a solver or a closed-form drive; scripted tracks and
    /// author-set states (later PRs) will map to `built` here.
    static func tier(ofSource s: String) -> MGSolidTier { .solved }

    /// Caption or title tier: `described` when marked `unchecked`; otherwise the lowest tier of the facts it shows
    /// or checks; nil when it shows and checks no engine number (prose the engine neither proves nor flags).
    /// In v1 documents (no placeholders) a text with a number character is `described`.
    static func text(facts: [MGSolidFact], unchecked: Bool) -> MGSolidTier? {
        if unchecked { return .described }
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
        guard ownMotion(id), let s = motionSources[id] else { return nil }
        var tier = MGSolidTiers.tier(ofSource: s)
        var cur = assembly.part(id)?.parent, seen: Set<String> = [id]
        while let c = cur, seen.insert(c).inserted {
            if ownMotion(c), let cs = motionSources[c] { tier = min(tier, MGSolidTiers.tier(ofSource: cs)) }
            cur = assembly.part(c)?.parent
        }
        return tier
    }

    /// Every visible claim with its tier. Motion claims are listed once per authored part (`repeat` copies share
    /// their base id), in part order; then the title and the captions.
    public var claims: [MGSolidClaim] {
        var out: [MGSolidClaim] = []
        var seen = Set<String>()
        for p in assembly.parts {
            let base = copies[p.id] ?? p.id
            guard let t = motionTier(p.id), seen.insert(base).inserted else { continue }
            let s = motionSources[p.id] ?? "input"
            out.append(MGSolidClaim(kind: .motion, id: base, tier: t, badge: t.badge(.motion), why: "Moved by \(s)"))
        }
        if let t = titleTier {
            out.append(MGSolidClaim(kind: .title, id: "title", tier: t, badge: t.badge(.title), why: "Every number in it is an engine fact"))
        }
        for (i, s) in steps.enumerated() {
            guard let t = s.tier else { continue }
            let why: String
            if let u = s.unchecked { why = "Marked unchecked: \(u)" }
            else if version < 2 { why = "Assembly v1 text: its numbers are not checked" }
            else if t == .solved { why = s.checks.isEmpty ? "Every number in it is an engine fact" : "Its numbers are engine facts and its checks passed" }
            else { why = "It shows a fact below Solved" }
            out.append(MGSolidClaim(kind: .caption, id: "step.\(i + 1)", tier: t, badge: t.badge(.caption), why: why))
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
        return MGSolidLegend(claims: c, solved: s, built: b, described: d,
                             text: groups.isEmpty ? "No engine-checked claims" : groups.joined(separator: " · "),
                             note: note, shapes: "Shapes as authored")
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
        guard let pid = canonicalPart(id), let p = assembly.part(pid) else { return nil }
        let base = copies[pid] ?? pid
        // Facts are keyed by part id or by `repeat` base id; an anchor names one of those.
        let key = aliases[id] ?? id
        let source = motionSources[pid]
        let motion: String
        if let t = motionTier(pid), let s = source {
            let speed = facts[pid + ".speed"].map { " (\($0.text) turns per input turn)" } ?? facts[pid + ".travel"].map { " (travel \($0.text) per input turn)" } ?? ""
            motion = t == .solved ? "Solved by \(s)\(speed)" : "Schematic (\(s))"
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
