// SPDX-License-Identifier: Apache-2.0
import Foundation

// The check report of an explainer: what `marty-solid check` prints for `"kind": "explainer"`, as a library API.
// ONE report for both views; the solid view embeds the assembly report fields (`MGSolidReport`). Foundation only.

public struct MGExplainerReport: Equatable, Sendable {
    public internal(set) var ok: Bool
    /// The first refusal reason, nil when `ok`.
    public internal(set) var reason: String?
    /// Where the first refusal is, nil when `ok` or when the refusal is a report check.
    public internal(set) var location: MGExplainerIssue?
    /// The full report object (docs/EXPLAINER.md, "The check report").
    public internal(set) var json: MGJSON

    public var exitCode: Int32 { ok ? 0 : 1 }
    /// Pretty-printed JSON with sorted keys: exactly what `marty-solid` prints.
    public var text: String { MGSolidReport.text(json) }

    /// Parses, loads and checks a document. Bytes over 128 KiB are refused (`explainer.bytes`) before they are parsed.
    public static func check(data: Data, library: MGSolidLibrary = .builtIn, profile: MGSolidProfile = .standard,
                             engine: MGJSON? = MGEngine.identity) -> MGExplainerReport {
        if MGSolidReport.badEngine(engine) { return MGExplainerReport(ok: false, reason: "report.engine", location: nil, json: MGSolidReport.engineRefusal.json) }
        guard data.count <= MGExplainerLimits.rawBytes else {
            return refused(MGExplainerIssue("explainer.bytes", view: .header), profile: nil, source: nil, engine: engine)
        }
        let source = MGSolidSource(data: data)
        let doc: MGExplainer
        switch MGExplainer.parse(data: data) {
        case .failure(let issue): return refused(issue, profile: profile, source: source, engine: engine)
        case .success(let d): doc = d
        }
        var session = MGExplainerSession(pacing: .immediate, clock: MGManualClock(), library: library)
        if case .failure(let issue) = session.load(doc) { return refused(issue, profile: profile, source: source, engine: engine) }
        return make(session, doc: doc, profile: profile, source: source, engine: engine)
    }

    /// The short report of a refused document: `{"ok": false, "reason", "location", "kind", "version"}`, plus `strict`
    /// when a profile is given, `file` when a source is given, and `engine`.
    public static func refused(_ issue: MGExplainerIssue, profile: MGSolidProfile?, source: MGSolidSource?,
                               engine: MGJSON? = MGEngine.identity) -> MGExplainerReport {
        var o: [String: MGJSON] = ["ok": .bool(false), "reason": .string(issue.reason), "location": issue.location,
                                   "kind": .string("explainer"), "version": .number(1)]
        // `annotations.visible` only: which annotation is over the limit and why (other refusals keep their exact keys).
        if let v = issue.visibility { o["visibility"] = v.json }
        if let profile { o["strict"] = .bool(profile == .strict) }
        if let source { o["file"] = file(source) }
        if let engine { o["engine"] = engine }
        return MGExplainerReport(ok: false, reason: issue.reason, location: issue, json: .object(o))
    }

    static func file(_ s: MGSolidSource) -> MGJSON {
        .object(["lines": .number(Double(s.lines)), "bytes": .number(Double(s.bytes)), "sha256": .string(s.sha256)])
    }

    /// The report of a loaded explainer. Refusal order: the solid's report checks (`check.meshOpen`,
    /// `check.gearsInterpenetrate`), then the strict profile (the solid's strict refusals, then `notes.unused.<id>`).
    /// A refused report still holds every field, so the author can repair from it.
    public static func make(_ s: MGExplainerSession, doc: MGExplainer? = nil, profile: MGSolidProfile = .standard,
                            source: MGSolidSource? = nil, engine: MGJSON? = MGEngine.identity) -> MGExplainerReport {
        var reason: String?, location: MGExplainerIssue?
        var solidJSON: MGJSON = .null
        if let d = s.solid {
            let r = MGSolidReport.make(d, profile: profile, engine: nil)
            if !r.ok, let why = r.reason { reason = why; location = MGExplainerIssue(why, view: .solid, id: r.part) }
            if case .object(var o) = r.json {
                for k in ["ok", "reason", "part", "strict", "engine", "file"] { o.removeValue(forKey: k) }
                solidJSON = .object(o)
            }
        }
        if reason == nil, profile == .strict, let id = s.unusedNotes.first {
            reason = "notes.unused.\(MGLessonIssue.segment(id))"; location = MGExplainerIssue(reason!, view: .header)
        }
        var boardJSON: MGJSON = .null
        if s.board != nil, let st = s.lesson.state {
            var values: [String: MGJSON] = [:]
            for (name, v) in st.scene.values {
                values[name] = .object(["value": num(v.value), "unit": .string(v.unit), "text": .string(v.text),
                                        "tier": .string((st.scene.builtValues.contains(name) ? MGTier.built : .solved).name)])
            }
            boardJSON = .object(["items": .array(st.scene.items.map { .string($0.id) }), "template": st.scene.template.map(MGJSON.string) ?? .null,
                                 "values": .object(values)])
        }
        let ids = s.ids
        var beats: [MGJSON] = []
        for b in s.keptBeats {
            let n = b.index + 1
            var facts: [MGJSON] = []
            for body in MGExplainerHonesty.placeholders(b.say) {
                let name = body.split(separator: "|", omittingEmptySubsequences: false).first.map(String.init) ?? body
                if name.contains("."), let d = s.solid, let (canonical, _) = MGSolidFacts.lookup(name, d.facts, d.aliases) { facts.append(.string(canonical)) }
                else { facts.append(.string(name)) }
            }
            let checks: [MGJSON] = b.checkSpecs.map { c in
                let comparison = ["eq", "lt", "gt"].first { c[$0] != nil } ?? "eq"
                return .object(["value": c["value"] ?? .null, "comparison": .string(comparison), "target": c[comparison] ?? .null,
                                "tol": c["tol"] ?? .null])
            }
            var hb: [MGJSON] = [], hs: [MGJSON] = [], ha: [MGJSON] = []
            for id in b.highlight ?? [] {
                if s.set3D.contains(id) {
                    if let d = s.solid, MGExplainerHonesty.parts3D(id, d) != nil { hs.append(.string(id)) } else { ha.append(.string(id)) }
                } else { hb.append(.string(id)) }
            }
            let tier = s.claims.first { $0.id == "beat.\(n)" }?.tier
            beats.append(.object(["n": .number(Double(n)), "caption": s.captions[b.index].map(MGJSON.string) ?? .null, "template": .string(b.say),
                                  "unchecked": b.unchecked.map(MGJSON.string) ?? .null, "tier": tier.map { .string($0.name) } ?? .null,
                                  "facts": .array(facts), "checks": .array(checks),
                                  "highlight": .object(["board": .array(hb), "solid": .array(hs), "annotations": .array(ha)]),
                                  "view": b.view ?? .null]))
        }
        let legend = s.legend
        let claims: [MGJSON] = legend.claims.map { c in
            .object(["kind": .string(c.kind.rawValue), "id": .string(c.id), "tier": .string(c.tier.name), "badge": .string(c.badge), "why": .string(c.why)])
        }
        let warnings: [MGJSON] = s.warnings.map { w in .object(["reason": .string(w.reason), "view": .string(w.view.rawValue), "id": w.id.map(MGJSON.string) ?? .null]) }
        var triangles = 0
        if case .object(let so) = solidJSON, case .number(let t)? = so["triangles"] { triangles = Int(t) }
        let bytes = doc.map { $0.statementStream.utf8.count }
        var o: [String: MGJSON] = [
            "ok": .bool(reason == nil), "reason": reason.map(MGJSON.string) ?? .null, "location": location?.location ?? .null,
            "strict": .bool(profile == .strict), "kind": .string("explainer"), "version": .number(1),
            "title": s.title.map(MGJSON.string) ?? .null, "primary": .string(s.primary ?? (s.solid != nil ? "solid" : "board")),
            "views": .object(["board": boardJSON, "solid": solidJSON]),
            "ids": .object(["board": .array(ids.board.map { .string($0) }), "controls": .array(ids.controls.map { .string($0) }),
                            "solid": .array(ids.solid.filter { !(s.solid?.annotations.ids.contains($0) ?? false) }.map { .string($0) }),
                            "annotations": .array((s.solid?.annotations.ids ?? []).map { .string($0) })]),
            "beats": .array(beats),
            // One entry per 3D annotation (the assembly report's `annotations`, PR 3a).
            "annotations": s.solid?.annotationReport ?? .array([]),
            "legend": .object(["text": .string(legend.text),
                               "groups": .object(["solved": num(legend.solved), "schematic": num(legend.schematic),
                                                  "given": num(legend.given), "described": num(legend.described)]),
                               "notes": .array(legend.notes.map { .string($0) }), "claims": .array(claims)]),
            "warnings": .array(warnings),
            "budget": .object(["bytes": bytes.map { num($0) } ?? .null, "limit": num(MGExplainerLimits.bytes),
                               "statements": doc.map { num($0.statements.count) } ?? .null,
                               "triangles": num(triangles), "triangleLimit": num(MGSolidLimits.triangles)]),
        ]
        if let source { o["file"] = file(source) }
        if let engine { o["engine"] = engine }
        return MGExplainerReport(ok: reason == nil, reason: reason, location: location, json: .object(o))
    }
}

private func num(_ d: Double) -> MGJSON { d.isFinite ? .number(d) : .null }
private func num(_ i: Int) -> MGJSON { .number(Double(i)) }
