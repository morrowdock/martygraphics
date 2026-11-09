// SPDX-License-Identifier: Apache-2.0
import Foundation

// The check report of a solid document: what `marty-solid check` prints, as a library API that any host (an MCP
// server, a data pipeline) can call and get the same JSON. Foundation only, deterministic.

/// Line count, byte count and SHA-256 of a source document, as the report names it (`file`).
public struct MGSolidSource: Equatable, Sendable {
    /// Lines of UTF-8 text split at "\n" (a final newline does not start a line).
    public var lines: Int
    public var bytes: Int
    /// Lowercase hex SHA-256 of the bytes.
    public var sha256: String

    public init(data: Data) {
        let text = String(decoding: data, as: UTF8.self)
        lines = text.split(separator: "\n", omittingEmptySubsequences: false).count - (text.hasSuffix("\n") ? 1 : 0)
        bytes = data.count
        sha256 = MGSHA256.hex(data)
    }

    /// `{"lines", "sha256"}`: the report's `file` object.
    public var json: MGJSON { .object(["lines": .number(Double(lines)), "sha256": .string(sha256)]) }
}

/// The check report: the engine checks beyond parsing (closed meshes, step section cuts, a gear tooth sweep), the
/// refusal they lead to, and the honesty data (facts, tiers, legend, read-back) a model repairs from.
///
/// Refusal order after a document compiles: `check.meshOpen` (a part or a step cut is not a closed mesh), then
/// `check.gearsInterpenetrate` (the tooth sweep overlaps more than the tolerance), then the profile's refusal (strict:
/// `joint.idle.<id>`, `frame.axis.off.<id>`). A refused report still holds every field, so the author can repair from it.
public struct MGSolidReport: Equatable, Sendable {
    public internal(set) var ok: Bool
    /// The first refusal reason, nil when `ok`.
    public internal(set) var reason: String?
    /// The part the reason concerns, if any.
    public internal(set) var part: String?
    /// The full report object (see docs/SOLID-3D.md, "The check report"). It nests at most 6 levels, plus the `engine`
    /// object one level down (at most `engineDepth`), so it stays far inside `MGLimits.depth`.
    public internal(set) var json: MGJSON

    /// 0 when accepted, 1 when refused (the `marty-solid` exit code).
    public var exitCode: Int32 { ok ? 0 : 1 }
    /// Pretty-printed JSON with sorted keys: exactly what `marty-solid` prints.
    public var text: String { MGSolidReport.text(json) }

    /// Pretty-printed JSON with sorted keys, or `{"ok": false, "reason": "report.encoding"}` when the value cannot be
    /// encoded (a non-finite number or nesting deeper than `MGLimits.depth`; reports never hold either).
    public static func text(_ json: MGJSON) -> String {
        let refusal = #"{"ok": false, "reason": "report.encoding"}"#
        // The walk does not recurse; only a finite value at most `MGLimits.depth` deep reaches the recursive
        // conversion (`any`) and the system encoder.
        let m = json.measure()
        guard m.finite, m.depth <= MGLimits.depth else { return refusal }
        let object = json.any
        guard JSONSerialization.isValidJSONObject(object),
              let d = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else { return refusal }
        return String(decoding: d, as: UTF8.self)
    }

    /// Deepest `engine` value a report carries, and its largest canonical size.
    public static let engineDepth = 8, engineBytes = 4096

    /// True when a host's `engine` value is not usable: a non-finite number, deeper than `engineDepth`, or larger than
    /// `engineBytes`. One walk that does not recurse and stops early, so a hostile value is never converted or compared.
    static func badEngine(_ engine: MGJSON?) -> Bool {
        guard let engine else { return false }
        let m = engine.measure(stopAbove: engineBytes)
        return m.stopped || !m.finite || m.depth > engineDepth || m.bytes > engineBytes
    }

    /// The refusal for an unusable `engine` value (`report.engine`); it carries no engine.
    static var engineRefusal: MGSolidReport {
        MGSolidReport(ok: false, reason: "report.engine", part: nil,
                      json: .object(["ok": .bool(false), "reason": .string("report.engine"), "part": .null]))
    }
}

// MARK: Engine checks

extension MGSolidReport {
    /// Engine checks beyond parsing: closed meshes (step section cuts included, as `step.<n>.<part>`) and a gear tooth
    /// sweep over one input turn (96 samples) when the model has gear meshes.
    public struct Checks: Equatable, Sendable {
        /// Ids of parts whose mesh is not closed, sorted, then step cuts that are not sound (`step.<n>.<part>`).
        public var openMeshes: [String]
        /// Number of gear pairs swept.
        public var gearPairs: Int
        /// False when the sweep overlaps more than `toleranceMM`; nil without gear pairs.
        public var gearsEngage: Bool?
        /// `{"meshesClosed", "openMeshes", "sections"?, "gearPairs", "maxPenetrationMM"?, "minClearanceMM"?,
        /// "toleranceMM"?, "gearsEngage"?}`.
        public var json: MGJSON
        public var meshesClosed: Bool { openMeshes.isEmpty }

        public init(_ doc: MGSolidDocument) {
            var open = doc.assembly.parts.filter { !$0.mesh.edgeReport.isClosed }.map(\.id).sorted()
            var sections: [MGJSON] = []
            for (i, step) in doc.steps.enumerated() {
                guard let sec = step.section else { continue }
                var parts: [MGJSON] = []
                for id in sec.parts {
                    guard let cut = sec.cuts[id] else { continue }
                    // Closed, outward and with caps that do not overlap (`MGSectionCut.isSound`).
                    let closed = cut.isSound
                    if !closed { open.append("step.\(i + 1).\(id)") }
                    parts.append(.object(["part": .string(id), "closed": .bool(closed), "triangles": num(cut.mesh.triangleCount),
                                          "capTriangles": num(cut.capTriangleCount), "capLoops": num(cut.loops)]))
                }
                let n = sec.plane.normal
                sections.append(.object(["step": num(i + 1), "normal": .array([num(n.x), num(n.y), num(n.z)]),
                                         "offset": num(sec.plane.offset), "parts": .array(parts)]))
            }
            var out: [String: MGJSON] = ["meshesClosed": .bool(open.isEmpty), "openMeshes": .array(open.map { MGJSON.string($0) })]
            if !sections.isEmpty { out["sections"] = .array(sections) }
            let sweep = MGSolidChecks.gearMeshes(doc, samples: 96, inputRange: 0...(2 * .pi))
            out["gearPairs"] = num(sweep.pairs)
            var engage: Bool?
            if sweep.pairs > 0 {
                // Same tolerance the compiler uses for interference: 0.01 of the smallest module in the model.
                let module = doc.gears.values.compactMap { $0.spur?.module ?? $0.ring?.module }.min() ?? 1
                let tolerance = MGSolidLimits.toothOverlap * module
                engage = sweep.maxPenetration <= tolerance
                out["maxPenetrationMM"] = num(sweep.maxPenetration)
                out["minClearanceMM"] = num(sweep.minClearance)
                out["toleranceMM"] = num(tolerance)
                out["gearsEngage"] = .bool(engage!)
            }
            openMeshes = open; gearPairs = sweep.pairs; gearsEngage = engage; json = .object(out)
        }

        /// `check.meshOpen`, then `check.gearsInterpenetrate`; nil when both pass.
        public var refusal: String? {
            if !meshesClosed { return "check.meshOpen" }
            if gearsEngage == false { return "check.gearsInterpenetrate" }
            return nil
        }
    }
}

/// A JSON number, or null for a value JSON cannot carry (NaN, an infinity).
private func num(_ d: Double) -> MGJSON { d.isFinite ? .number(d) : .null }
private func num(_ i: Int) -> MGJSON { .number(Double(i)) }
private func str(_ s: String?) -> MGJSON { s.map(MGJSON.string) ?? .null }

// MARK: Report

extension MGSolidReport {
    /// One group of report fields. The report merges every section's fields; a test keeps their keys disjoint, so a
    /// later feature adds a section (and its docs) without touching the others.
    struct Section {
        let name: String
        let fields: (MGSolidDocument) -> [String: MGJSON]
    }

    /// Sections after the summary, in order.
    static let sections: [Section] = [
        Section(name: "honesty", fields: honesty),
        Section(name: "tiers", fields: tiers),
        Section(name: "annotations", fields: annotations),
        Section(name: "stepViews", fields: stepViews),
    ]

    /// The report of a compiled document. `profile: .strict` adds the strict refusals (the document should be compiled
    /// with the standard profile so the report can show what strict refuses). `source` adds the `file` object;
    /// `engine` adds the `engine` object (nil leaves it out). Every entry point first refuses an unusable `engine`
    /// (`report.engine`: non-finite, deeper than `engineDepth` or larger than `engineBytes`).
    ///
    /// `anchorViews` (default true) runs the view rule of the anchor checks on every step still
    /// (`MGSolidDocument.stepAnchorIssues`): each issue is a warning `annotation.anchor.hidden.<id>` (or
    /// `annotation.anchor.untested.<id>` for an anchor the view's triangle budget left untested), and the strict profile
    /// refuses the first one in step order (after every other refusal). An explainer passes false and tests its beats instead
    /// (`MGExplainerReport`). The report lists every anchor issue in `anchorIssues` and the anchors a view's budget left
    /// untested in `anchorUntested` (both only for a document with annotations); a refusal for an anchor reason adds
    /// `anchor`, the issue it names.
    public static func make(_ doc: MGSolidDocument, profile: MGSolidProfile = .standard, source: MGSolidSource? = nil,
                            engine: MGJSON? = MGEngine.identity, anchorViews: Bool = true) -> MGSolidReport {
        if badEngine(engine) { return engineRefusal }
        let checks = Checks(doc)
        var reason = checks.refusal, part: String? = nil
        if reason == nil, let r = profile.refusal(doc) { reason = r.reason; part = r.part }
        var anchors = MGAnnotationAnchorReport()
        anchors.issues = doc.offPartAnchors
        if anchorViews {
            let framed = doc.stepAnchorViews()
            for v in framed { anchors.append(doc.anchorIssues(v)) }
            anchors.suggest(doc, views: framed)
        }
        let views = anchors.issues.filter { $0.cause != .offPart }
        if reason == nil, profile == .strict, let first = views.first { reason = first.reason; part = first.id }
        var o = summary(doc, checks: checks, profile: profile)
        o["ok"] = .bool(reason == nil)
        o["reason"] = str(reason)
        if let part { o["part"] = .string(part) }
        if let source { o["file"] = source.json }
        if let engine { o["engine"] = engine }
        for s in sections { o.merge(s.fields(doc)) { a, _ in a } }
        // The view rule's warnings follow the document's own warnings (one per issue, in step order).
        if case .array(var w)? = o["warnings"] {
            w += views.map { .object(["reason": .string($0.reason), "part": .string($0.id)]) }
            o["warnings"] = .array(w)
        }
        // Documents with annotations only; other reports keep their exact keys.
        if !doc.annotations.isEmpty {
            o["anchorIssues"] = .array(anchors.issues.map(\.json))
            o["anchorUntested"] = anchors.untestedJSON
        }
        let hit = reason.flatMap { anchorIssue($0, anchors.issues) }
        if let hit { o["anchor"] = hit.json }
        if let r = reason { o["repair"] = .string(repair(r, part: part, anchor: hit)) }
        return MGSolidReport(ok: reason == nil, reason: reason, part: part, json: .object(o))
    }

    /// The report's one-line `repair` for refusal `reason`, built from its structured detail: the anchor issue's
    /// `repair`, else the limit detail's (`MGSolidLimitDetail.repair`), else the catalog meaning of the reason
    /// (`MGSolidReasons.lookup`), else the bare reason. At most `MGAnnotationAnchorIssue.repairScalars` Unicode scalars;
    /// deterministic.
    static func repair(_ reason: String, part: String?, anchor: MGAnnotationAnchorIssue? = nil, limit: MGSolidLimitDetail? = nil,
                       visibility: MGAnnotationVisibilityDetail? = nil) -> String {
        if let anchor { return anchor.repair }
        let line: String
        if let limit { line = limit.repair }
        else if let m = MGSolidReasons.lookup(reason)?.meaning {
            line = "Refused (\(reason))" + (part.map { ", at \(MGSolidParser.token($0))" } ?? "") + ": " + m
        } else { line = "Refused (\(reason))." }
        return MGAnnotationAnchorIssue.bounded(line, MGAnnotationAnchorIssue.repairScalars)
    }

    /// The issue an anchor refusal names: the first issue with that reason (nil for any other reason).
    static func anchorIssue(_ reason: String, _ issues: [MGAnnotationAnchorIssue]) -> MGAnnotationAnchorIssue? {
        issues.first { $0.reason == reason }
    }

    /// The report of a refused document: `{"ok": false, "reason", "part", "repair"}`, plus `visibility` for
    /// `annotations.visible` (`MGAnnotationVisibilityDetail`), `limit` for every length, count or size limit
    /// (`MGSolidLimitDetail`), `strict` when a profile is given, `file` when a source is given and `engine`.
    public static func refused(_ issue: MGSolidIssue, profile: MGSolidProfile? = nil, source: MGSolidSource? = nil,
                               engine: MGJSON? = MGEngine.identity) -> MGSolidReport {
        if badEngine(engine) { return engineRefusal }
        var o: [String: MGJSON] = ["ok": .bool(false), "reason": .string(issue.reason), "part": str(issue.part)]
        // `annotations.visible` only: which annotation is over the limit and why (other refusals keep their exact keys).
        if let v = issue.visibility { o["visibility"] = v.json }
        // `parts.resolved` only: the resolved count, the limit and the instances that add the most parts.
        // A limit refusal: the field, the measured value and the limit (`annotations.visible` and the `annotate` counts
        // give theirs from `visibility`).
        let limit = issue.limit ?? issue.visibility?.limitDetail()
        if let limit { o["limit"] = limit.json }
        o["repair"] = .string(repair(issue.reason, part: issue.part, limit: limit, visibility: issue.visibility))
        if let profile { o["strict"] = .bool(profile == .strict) }
        if let source { o["file"] = source.json }
        if let engine { o["engine"] = engine }
        return MGSolidReport(ok: false, reason: issue.reason, part: issue.part, json: .object(o))
    }

    /// Parses and checks a document, as `marty-solid check` does. Bytes over `MGSolidLimits.bytes` are refused
    /// (`assembly.bytes`) before they are parsed or hashed, with the short refusal (no `strict`, no `file`).
    public static func check(data: Data, library: MGSolidLibrary = .builtIn, profile: MGSolidProfile = .standard,
                             engine: MGJSON? = MGEngine.identity) -> MGSolidReport {
        if badEngine(engine) { return engineRefusal }
        guard data.count <= MGSolidLimits.bytes else { return refused(MGSolidParser.bytesIssue("assembly.bytes", data.count), engine: engine) }
        let source = MGSolidSource(data: data)
        switch MGSolidParser.document(data: data, library: library) {
        case .failure(let issue): return refused(issue, profile: profile, source: source, engine: engine)
        case .success(let doc): return make(doc, profile: profile, source: source, engine: engine)
        }
    }

    /// The report of `base` with `patch` applied (`MGSolidParser.applying(data:to:)`), as
    /// `marty-solid check BASE --patch PATCH` prints it: the same fields, with `file` naming the base, plus
    /// `{"patch": {"file"?, "applied", "refusedAt"?, "fields", "changed"?}}`. `fields` lists what the patch sets
    /// (`title`, `params`, `constraints`, `steps`, `parts.<id>.<key>`), sorted; `changed` lists the fields whose value in
    /// the document source differs after the patch. `refusedAt` is `base` or `patch` when that document was refused;
    /// a patched document that compiles but fails a report check has `applied: true`.
    public static func check(data: Data, patch: Data, library: MGSolidLibrary = .builtIn, profile: MGSolidProfile = .standard,
                             engine: MGJSON? = MGEngine.identity) -> MGSolidReport {
        if badEngine(engine) { return engineRefusal }
        var info: [String: MGJSON] = ["applied": .bool(false), "fields": .array([])]
        if patch.count <= MGSolidLimits.bytes { info["file"] = MGSolidSource(data: patch).json }
        func with(_ r: MGSolidReport, _ info: [String: MGJSON]) -> MGSolidReport {
            var r = r
            if case .object(var o) = r.json { o["patch"] = .object(info); r.json = .object(o) }
            return r
        }
        guard data.count <= MGSolidLimits.bytes else {
            info["refusedAt"] = .string("base")
            return with(refused(MGSolidParser.bytesIssue("assembly.bytes", data.count), engine: engine), info)
        }
        let source = MGSolidSource(data: data)
        let base: MGSolidDocument
        switch MGSolidParser.document(data: data, library: library) {
        case .failure(let issue):
            info["refusedAt"] = .string("base")
            return with(refused(issue, profile: profile, source: source, engine: engine), info)
        case .success(let d): base = d
        }
        let paths = (try? MGSolidParser.patchJSON(patch).get()).map(patchPaths) ?? []
        info["fields"] = .array(paths.map { MGJSON.string($0.text) })
        switch MGSolidParser.applying(data: patch, to: base) {
        case .failure(let issue):
            info["refusedAt"] = .string("patch")
            return with(refused(issue, profile: profile, source: source, engine: engine), info)
        case .success(let doc):
            info["applied"] = .bool(true)
            info["changed"] = .array(paths.filter { sourceValue(base.source, $0) != sourceValue(doc.source, $0) }.map { MGJSON.string($0.text) })
            return with(make(doc, profile: profile, source: source, engine: engine), info)
        }
    }

    // MARK: Sections

    static func summary(_ doc: MGSolidDocument, checks: Checks, profile: MGSolidProfile) -> [String: MGJSON] {
        // Part meshes plus every distinct step cut: the same total the mesh budget counts.
        var cutTriangles = 0, seenCuts = Set<String>()
        for s in doc.steps { for (id, cut) in (s.section?.cuts ?? [:]).sorted(by: { $0.key < $1.key }) {
            let key = "\(id)|\(cut.plane.normal.x),\(cut.plane.normal.y),\(cut.plane.normal.z),\(cut.plane.offset)"
            if seenCuts.insert(key).inserted { cutTriangles += cut.mesh.triangleCount }
        } }
        let tris = doc.assembly.parts.reduce(0) { $0 + $1.mesh.triangleCount } + cutTriangles
        return ["title": .string(doc.title), "parts": num(doc.assembly.parts.count), "triangles": num(tris),
                "sectionTriangles": num(cutTriangles), "steps": .array(doc.steps.map { MGJSON.string($0.say) }),
                "ratios": .object(doc.ratios.mapValues { num($0) }), "checks": checks.json, "strict": .bool(profile == .strict)]
    }

    /// Warnings, facts with tiers, the tier legend, what each motion source does not check, and the plain-words
    /// read-back of every part.
    static func honesty(_ doc: MGSolidDocument) -> [String: MGJSON] {
        var facts: [String: MGJSON] = [:]
        for (name, f) in doc.facts {
            facts[name] = .object(["value": num(f.value), "unit": .string(f.unit), "text": .string(f.text), "tier": .string(f.tier.name),
                                   "source": .string(f.source)])
        }
        let legend = doc.legend
        let claims: [MGJSON] = legend.claims.map { c -> MGJSON in
            .object(["kind": .string(c.kind.rawValue), "id": .string(c.id), "tier": .string(c.tier.name), "badge": .string(c.badge),
                     "why": .string(c.why)])
        }
        var notChecked: [String: MGJSON] = [:]
        for s in Set(doc.motionSources.values) { if let list = MGSolidNotChecked.bySource[s] { notChecked[s] = .array(list.map { MGJSON.string($0) }) } }
        var legendFields: [String: MGJSON] = ["text": .string(legend.text), "solved": num(legend.solved), "built": num(legend.built),
                                              "described": num(legend.described), "note": str(legend.note), "shapes": .string(legend.shapes),
                                              "claims": .array(claims)]
        // Documents with annotations also list every legend note; other reports keep their exact keys.
        if !doc.annotations.isEmpty { legendFields["notes"] = .array(legend.notes.map { MGJSON.string($0) }) }
        return ["version": num(doc.version),
                "warnings": .array(doc.warnings.map { w -> MGJSON in .object(["reason": .string(w.reason), "part": str(w.part)]) }),
                "facts": .object(facts),
                "legend": .object(legendFields),
                "stepTiers": .array(doc.steps.map { s -> MGJSON in str(s.tier?.name) }),
                // Which fact filled each placeholder, in order, and what each step's checks proved.
                "stepFacts": .array(doc.steps.map { s -> MGJSON in
                    .object(["facts": .array(s.facts.map { MGJSON.string($0) }),
                             "checks": .array(s.checks.map { c -> MGJSON in
                                 .object(["value": .string(c.value), "comparison": .string(c.comparison.rawValue), "target": num(c.target),
                                          "tolerance": c.tolerance.map { num($0) } ?? .null, "text": .string(c.text)])
                             })])
                }),
                "notChecked": .object(notChecked),
                "readBack": .array(doc.readBack.map { MGJSON.string($0) })]
    }

    /// Engine tiers per part and per motion claim, from the tier calculus (`motionTier`, `claims`).
    ///
    /// `partTiers`, in part order: `{"part", "base", "motion", "tier", "source", "ridesOn"}`. `motion` is `own` (its
    /// own joint moves: `tier` is that motion's tier), `idle` (a joint with no drive or constraint), `rides` (static
    /// on a moving ancestor, named by `ridesOn`) or `static`; only `own` has a tier. `base` is the `repeat` base id.
    /// `motionTiers`: one entry per motion claim (once per authored part), `{"id", "tier", "badge", "source"}`.
    static func tiers(_ doc: MGSolidDocument) -> [String: MGJSON] {
        var parts: [MGJSON] = []
        for p in doc.assembly.parts {
            let tier = doc.motionTier(p.id)
            let mover = doc.movingAncestor(p.id)
            let motion = tier != nil ? "own" : p.joint != .fixed && p.drive == nil ? "idle" : mover != nil ? "rides" : "static"
            parts.append(.object(["part": .string(p.id), "base": .string(doc.copies[p.id] ?? p.id), "motion": .string(motion),
                                  "tier": str(tier?.name), "source": tier != nil ? str(doc.motionSources[p.id]) : .null,
                                  "ridesOn": motion == "rides" ? str(mover) : .null]))
        }
        var motions: [MGJSON] = []
        for c in doc.claims where c.kind == .motion {
            let pid = doc.canonicalPart(c.id) ?? c.id
            motions.append(.object(["id": .string(c.id), "tier": .string(c.tier.name), "badge": .string(c.badge),
                                    "source": str(doc.motionSources[pid])]))
        }
        return ["partTiers": .array(parts), "motionTiers": .array(motions)]
    }

    /// Assembly v2 annotations (docs/SOLID-3D.md, Annotations): `annotations` (`MGSolidDocument.annotationReport`) and
    /// `placements` (`MGSolidDocument.annotationPlacements`). Both are absent for a document without annotations.
    static func annotations(_ doc: MGSolidDocument) -> [String: MGJSON] {
        guard !doc.annotations.isEmpty else { return [:] }
        return ["annotations": doc.annotationReport, "placements": doc.annotationPlacements]
    }

    /// Per-step `pose`, `hide` and `show` (docs/SOLID-3D.md, "Step pose" and "Step visibility"): `stepViews`, one object
    /// per step, `{"step" (1-based), "posed": [part ids], "poseReadBack": [lines], "hidden": [part ids]}`
    /// (`MGSolidDocument.poseReadBack`, `hiddenParts(step:)` in part order), and `showOnly`. Absent when no step uses
    /// these keys.
    static func stepViews(_ doc: MGSolidDocument) -> [String: MGJSON] {
        guard doc.steps.contains(where: { !$0.pose.isEmpty || !$0.hide.isEmpty || !$0.show.isEmpty || $0.poseSource != nil }) else { return [:] }
        let order = doc.assembly.parts.map(\.id)
        let readBack = Dictionary(doc.poseReadBack.map { ($0.step, $0.lines) }, uniquingKeysWith: { a, _ in a })
        let steps: [MGJSON] = doc.steps.indices.map { i in
            let s = doc.steps[i], hidden = doc.hiddenParts(step: i)
            return .object(["step": num(i + 1), "posed": .array(order.filter { s.pose[$0] != nil }.map { MGJSON.string($0) }),
                            "poseReadBack": .array((readBack[i + 1] ?? []).map { MGJSON.string($0) }),
                            "hidden": .array(order.filter { hidden.contains($0) }.map { MGJSON.string($0) })])
        }
        return ["stepViews": .array(steps), "showOnly": .array(doc.showOnly.map { MGJSON.string($0) })]
    }

    // MARK: Patch fields

    struct PatchPath: Equatable {
        var key: String, id: String?, field: String?
        var text: String { [key, id, field].compactMap { $0 }.joined(separator: ".") }
    }

    /// What a patch object sets, sorted by text. Not an object: nothing.
    static func patchPaths(_ patch: MGJSON) -> [PatchPath] {
        guard case .object(let p) = patch else { return [] }
        var out: [PatchPath] = []
        for (key, value) in p {
            guard key == "parts", case .object(let edits) = value else { out.append(PatchPath(key: key, id: nil, field: nil)); continue }
            for (id, edit) in edits {
                guard case .object(let fields) = edit else { out.append(PatchPath(key: key, id: id, field: nil)); continue }
                for f in fields.keys { out.append(PatchPath(key: key, id: id, field: f)) }
            }
        }
        return out.sorted { $0.text < $1.text }
    }

    /// The value a path names in a document source; an id inside a component instance (`stage1.pinion`) reads the
    /// `set` of that `use` entry, as `applying` writes it.
    static func sourceValue(_ src: MGJSON, _ path: PatchPath) -> MGJSON? {
        guard let id = path.id else { return src[path.key] }
        guard case .array(let list)? = src["parts"] else { return nil }
        let entry: MGJSON?
        if let e = list.first(where: { $0["id"] == .string(id) }) { entry = e }
        else {
            let head = id.split(separator: ".", maxSplits: 1).map(String.init)
            guard head.count == 2, let use = list.first(where: { $0["id"] == .string(head[0]) && $0["use"] != nil }) else { return nil }
            entry = use["set"]?[head[1]]
        }
        guard let field = path.field else { return entry }
        return entry?[field]
    }
}
