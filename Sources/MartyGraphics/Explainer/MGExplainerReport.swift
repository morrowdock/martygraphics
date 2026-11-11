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
        check(data: data, library: library, profile: profile, engine: engine, suggest: true)
    }

    /// `check` with or without anchor suggestions (`suggest: false` leaves `suggest` and `noSuggest` null; tests).
    static func check(data: Data, library: MGSolidLibrary = .builtIn, profile: MGSolidProfile = .standard,
                      engine: MGJSON? = MGEngine.identity, suggest: Bool) -> MGExplainerReport {
        if MGSolidReport.badEngine(engine) { return MGExplainerReport(ok: false, reason: "report.engine", location: nil, json: MGSolidReport.engineRefusal.json) }
        guard data.count <= MGExplainerLimits.rawBytes else {
            return refused(MGExplainer.bytesIssue(data.count, MGExplainerLimits.rawBytes), profile: nil, source: nil, engine: engine)
        }
        let source = MGSolidSource(data: data)
        let doc: MGExplainer
        switch MGExplainer.parse(data: data) {
        case .failure(let issue): return refused(issue, profile: profile, source: source, engine: engine)
        case .success(let d): doc = d
        }
        var session = MGExplainerSession(pacing: .immediate, clock: MGManualClock(), library: library)
        if case .failure(let issue) = session.load(doc) { return refused(issue, profile: profile, source: source, engine: engine) }
        return make(session, doc: doc, profile: profile, source: source, engine: engine, suggest: suggest)
    }

    /// The short report of a refused document: `{"ok": false, "reason", "location", "kind", "version", "repair"}`, plus
    /// `visibility` for the visibility reasons, `limit` for every length, count or size limit, `strict` when a profile is
    /// given, `file` when a source is given, and `engine`.
    public static func refused(_ issue: MGExplainerIssue, profile: MGSolidProfile?, source: MGSolidSource?,
                               engine: MGJSON? = MGEngine.identity) -> MGExplainerReport {
        var o: [String: MGJSON] = ["ok": .bool(false), "reason": .string(issue.reason), "location": issue.location,
                                   "kind": .string("explainer"), "version": .number(1)]
        // `annotations.visible` only: which annotation is over the limit and why (other refusals keep their exact keys).
        if let v = issue.visibility { o["visibility"] = v.json }
        // The solid's `parts.resolved` only: the resolved count, the limit and the instances that add the most parts.
        let limit = issue.limit ?? issue.visibility?.limitDetail(prefix: "solid.")
        if let limit { o["limit"] = limit.json }
        o["repair"] = .string(MGSolidReport.repair(issue.reason, part: issue.id, limit: limit, visibility: issue.visibility))
        if let c = issue.centreOfMass { o["centreOfMass"] = c.json; o["repair"] = .string(c.repair) }
        if let m = issue.dimensionMotion { o["dimensionMotion"] = m.json; o["repair"] = .string(m.repair) }
        if let profile { o["strict"] = .bool(profile == .strict) }
        if let source { o["file"] = file(source) }
        if let engine { o["engine"] = engine }
        return MGExplainerReport(ok: false, reason: issue.reason, location: issue, json: .object(o))
    }

    static func file(_ s: MGSolidSource) -> MGJSON {
        .object(["lines": .number(Double(s.lines)), "bytes": .number(Double(s.bytes)), "sha256": .string(s.sha256)])
    }

    /// The report of a loaded explainer. Refusal order: the solid's report checks (`check.meshOpen`,
    /// `check.gearsInterpenetrate`), then the strict profile (the solid's strict refusals, then `notes.unused.<id>`,
    /// then `annotation.anchor.hidden.<id>` or `annotation.anchor.untested.<id>` of the first beat whose still does not
    /// show, or did not test, a label's or pointer's anchor).
    /// A refused report still holds every field, so the author can repair from it.
    ///
    /// The beat anchor check (`MGExplainerFrame.beatAnchorIssues`) needs the document: it runs when `doc` is given (as
    /// `check(data:)` does). Its issues are warnings in both profiles and are listed, with the solid's off-part anchors,
    /// in `anchorIssues`; a refusal for an anchor reason adds `anchor`, the issue it names. The arrow visibility rule
    /// (`MGSolidDocument.arrowIssues`) runs on the same beat stills: its issues (`annotation.arrow.hidden.<id>`,
    /// `annotation.arrow.untested.<id>`) are warnings listed in `arrowIssues`, the strict profile refuses the first one
    /// after the anchor refusals, and a refusal for an arrow reason adds `arrow`.
    public static func make(_ s: MGExplainerSession, doc: MGExplainer? = nil, profile: MGSolidProfile = .standard,
                            source: MGSolidSource? = nil, engine: MGJSON? = MGEngine.identity) -> MGExplainerReport {
        make(s, doc: doc, profile: profile, source: source, engine: engine, suggest: true)
    }

    static func make(_ s: MGExplainerSession, doc: MGExplainer?, profile: MGSolidProfile, source: MGSolidSource?, engine: MGJSON?,
                     suggest: Bool) -> MGExplainerReport {
        var reason: String?, location: MGExplainerIssue?
        var solidJSON: MGJSON = .null
        var anchors = MGAnnotationAnchorReport()
        var arrows = MGAnnotationArrowReport()
        var drops: [(beat: Int?, drop: MGArrowDrop)] = []
        var dropNotes: [MGArrowDropNote] = []
        var subjects: [MGSubjectSmall] = [], small: [MGSmallUnit] = [], stillPlacements: MGJSON?
        if let d = s.solid {
            // The solid's own steps are the beats' views: the beat check below frames them as the beat stills do.
            let r = MGSolidReport.make(d, profile: profile, engine: nil, anchorViews: false)
            if !r.ok, let why = r.reason { reason = why; location = MGExplainerIssue(why, view: .solid, id: r.part) }
            if case .object(var o) = r.json {
                for k in ["ok", "reason", "part", "strict", "engine", "file", "anchorIssues", "anchorUntested", "anchor"] { o.removeValue(forKey: k) }
                solidJSON = .object(o)
            }
            // The part rule's views are the solid's steps: name the beat that shows each one.
            var beatOf: [Int: Int] = [:]
            for b in s.keptBeats { if let st = s.solidStep(forBeat: b.index), beatOf[st] == nil { beatOf[st] = b.index } }
            anchors.issues = d.offPartAnchors.map { $0.at(beat: $0.step.flatMap { beatOf[$0] }) }
            // Every beat still, framed once: the subject rule and the small-unit rule read them all (warnings, never
            // refused); the anchor checks test those that show a label or pointer, the arrow rule those that show an arrow.
            let stills = doc.map { MGExplainerFrame.beatStills($0, library: s.library) }
            if let doc, let fd = stills?.solid, let all = stills?.stills {
                if !fd.annotations.isEmpty { stillPlacements = fd.stillPlacements(all, title: false) }
                (subjects, small) = fd.stillMeasures(all) { f in
                    guard let b = f.still.beat, doc.beats.indices.contains(b), case .object(let v)? = doc.beats[b].view else { return [] }
                    return MGSolidDocument.strings(v["ghost"])
                }
            }
            if let doc, !d.annotations.isEmpty {
                // The beat stills that show a label, pointer or arrow (`MGExplainerFrame.beatCheckViews`).
                let views = stills?.stills.map(\.still) ?? []
                let checked = (solid: stills?.solid,
                               views: stills?.solid.map { fd in views.filter { fd.showsCheckedAnchor($0.view) || fd.showsArrow($0.view) } } ?? [])
                // The arrows each beat still drops (the framing's arrow drop rule): warnings, never refused.
                drops = checked.views.flatMap { v in v.view.arrowDrops.map { (v.beat, $0) } }
                // A dropped arrow that no beat draws, or whose force the beat's caption names: warnings, never refused.
                if let fd = checked.solid {
                    dropNotes = fd.arrowDropNotes(views, beats: true) { k in s.captions[k] ?? s.keptBeats.first { $0.index == k }?.say }
                }
                let framed = (solid: checked.solid, views: checked.views.filter { v in checked.solid.map { $0.showsCheckedAnchor(v.view) } ?? false })
                if let fd = framed.solid {
                    for v in framed.views { anchors.append(fd.anchorIssues(v)) }
                    if suggest {
                        // One search budget for the report, retries included.
                        let budget = MGSuggestionBudget()
                        anchors.suggest(fd, views: framed.views, budget: budget)
                        // A suggestion holds only once applied: the explainer with it is loaded and framed again.
                        anchors.verify { applied in
                            guard let solid = doc.solid else { return nil }
                            let copy = MGExplainer(title: doc.title, primary: doc.primary, notes: doc.notes, board: doc.board,
                                                   solid: MGSolidDocument.replacingAnchors(solid, applied), beats: doc.beats, names: doc.names)
                            return anchorRecheck(copy, library: s.library, budget: budget)
                        }
                    }
                    // The arrow visibility rule, its suggested moves and their re-check (`MGAnnotationArrowReport.verify`).
                    let arrowViews = checked.views.filter { fd.showsArrow($0.view) }
                    arrows.issues = arrowViews.flatMap { fd.arrowIssues($0) }
                    if suggest {
                        // One search budget for the first searches and the re-check's searches together.
                        arrows.repair(fd, views: arrowViews, anchorIssues: Set(anchors.issues.map(\.id)),
                                      budget: MGSuggestionBudget(MGAnnotationArrowRules.suggestDocumentTests)) { moves, budget in
                            guard let solid = doc.solid else { return nil }
                            let copy = MGExplainer(title: doc.title, primary: doc.primary, notes: doc.notes, board: doc.board,
                                                   solid: MGSolidDocument.replacingArrows(solid, moves), beats: doc.beats, names: doc.names)
                            return arrowRecheck(copy, library: s.library, budget: budget)
                        }
                        // Every printed suggestion, anchors and arrows together, checked once more on one copy.
                        MGSuggestionUnion.verifyTogether(anchors: &anchors, arrows: &arrows) { anchorMoves, arrowMoves in
                            guard let solid = doc.solid else { return nil }
                            let both = MGSolidDocument.replacingAnchors(MGSolidDocument.replacingArrows(solid, arrowMoves), anchorMoves)
                            let copy = MGExplainer(title: doc.title, primary: doc.primary, notes: doc.notes, board: doc.board, solid: both, beats: doc.beats, names: doc.names)
                            return arrowRecheck(copy, library: s.library, budget: MGSuggestionBudget(0))
                        }
                    }
                    // Every beat still, also those that do not list it, for each hidden arrow (one refusal names them all).
                    fd.scanHiddenArrows(&arrows.issues, views: views, beats: true)
                }
            }
        }
        if reason == nil, profile == .strict, let id = s.unusedNotes.first {
            reason = "notes.unused.\(MGLessonIssue.segment(id))"; location = MGExplainerIssue(reason!, view: .header)
        }
        let beatIssues = anchors.issues.filter { $0.cause != .offPart }
        if reason == nil, profile == .strict, let a = beatIssues.first {
            reason = a.reason
            location = MGExplainerIssue(a.reason, view: .beat, beat: a.beat, id: a.id, detail: a.cause.rawValue)
        }
        // The arrow rule's refusals follow the anchor refusals (beat order).
        if reason == nil, profile == .strict, let a = arrows.issues.first {
            reason = a.reason
            location = MGExplainerIssue(a.reason, view: .beat, beat: a.beat, id: a.id, detail: a.cause.rawValue)
        }
        // The board items each beat's board pane cuts at 1280 × 800 (`MGExplainerFrame.boardClips`): warnings, each
        // item once, at the first beat that cuts it.
        var boardClips: [MGBoardClip] = []
        if s.board != nil, let doc { boardClips = MGExplainerFrame.beatBoardClips(doc, library: s.library) }
        // The weight suggestions hold once applied: each is applied to the explainer's solid, loaded and checked again on
        // the beat stills.
        if let doc, let d = s.solid, case .object(var so) = solidJSON, so["weightPlacements"] != nil {
            so["weightPlacements"] = .array(d.weightPlacements.map { p in
                guard let solid = doc.solid else { return p.verifying("the copy is refused").json }
                let copy = MGExplainer(title: doc.title, primary: doc.primary, notes: doc.notes, board: doc.board,
                                       solid: MGSolidDocument.replacingArrows(solid, [p.id: p.suggest]), beats: doc.beats, names: doc.names)
                var session = MGExplainerSession(pacing: .immediate, clock: MGManualClock(), library: s.library)
                guard case .success = session.load(copy), let cd = session.solid else { return p.verifying("the copy is refused").json }
                if cd.weightPlacements.contains(where: { $0.id == p.id }) { return p.verifying("it still warns").json }
                guard let r = arrowRecheck(copy, library: s.library, budget: MGSuggestionBudget(0)) else { return p.verifying("the copy is refused").json }
                if let i = r.arrows.first(where: { $0.id == p.id }) { return p.verifying("it is hidden in \(i.viewName)").json }
                return p.verifying(nil).json
            })
            solidJSON = .object(so)
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
        var warnings: [MGJSON] = s.warnings.map { w in .object(["reason": .string(w.reason), "view": .string(w.view.rawValue), "id": w.id.map(MGJSON.string) ?? .null]) }
        // The beat anchor check's warnings follow (one per issue, in beat order).
        warnings += beatIssues.map { .object(["reason": .string($0.reason), "view": .string("beat"), "id": .string($0.id)]) }
        warnings += arrows.issues.map { .object(["reason": .string($0.reason), "view": .string("beat"), "id": .string($0.id)]) }
        warnings += drops.map { .object(["reason": .string($0.drop.reason), "view": .string("beat"), "id": .string($0.drop.id)]) }
        warnings += dropNotes.map { .object(["reason": .string($0.reason), "view": .string("beat"), "id": .string($0.id)]) }
        warnings += boardClips.map { .object(["reason": .string($0.reason), "view": .string("board"), "id": .string($0.id)]) }
        warnings += subjects.map { .object(["reason": .string($0.reason), "view": .string("beat"), "id": .string($0.groups[$0.small.first ?? 0].unit)]) }
        warnings += small.map { .object(["reason": .string($0.reason), "view": .string("solid"), "id": .string($0.unit)]) }
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
        // Explainers with 3D annotations only; other reports keep their exact keys.
        if let d = s.solid, !d.annotations.isEmpty {
            o["anchorIssues"] = .array(anchors.issues.map(\.json))
            o["anchorUntested"] = anchors.untestedJSON
            o["arrowIssues"] = .array(arrows.issues.map(\.json))
            // Only when a beat still drops an arrow; other reports keep their exact keys.
            if !drops.isEmpty { o["arrowDrops"] = .array(drops.map { $0.drop.json(step: nil, beat: $0.beat) }) }
            // Only when a dropped arrow leaves a caption or the story without it.
            if !dropNotes.isEmpty { o["arrowDropNotes"] = .array(dropNotes.map(\.json)) }
        }
        // Only when a beat still's subject misses a floor or a named unit is small; other reports keep their exact keys.
        if !subjects.isEmpty { o["subjectFloors"] = .array(subjects.map(\.json)) }
        // Only when a beat's board pane cuts an item; other reports keep their exact keys.
        if !boardClips.isEmpty { o["boardClips"] = .array(boardClips.map(\.json)) }
        if let stillPlacements { o["stillPlacements"] = stillPlacements }
        if !small.isEmpty { o["smallUnits"] = .array(small.map(\.json)) }
        let hit = reason.flatMap { MGSolidReport.anchorIssue($0, anchors.issues) }
        if let hit { o["anchor"] = hit.json }
        let arrowHit = reason.flatMap { r in arrows.issues.first { $0.reason == r } }
        if let arrowHit { o["arrow"] = arrowHit.json }
        if let r = reason { o["repair"] = .string(arrowHit?.repair ?? MGSolidReport.repair(r, part: location?.id, anchor: hit)) }
        if let source { o["file"] = file(source) }
        if let engine { o["engine"] = engine }
        return MGExplainerReport(ok: reason == nil, reason: reason, location: location, json: .object(o))
    }
}

extension MGExplainerReport {
    /// The anchor issues of an explainer as `make` lists them (off part with the beat that shows each, then every beat
    /// still), and a suggestion search in its framing; nil when it does not load.
    static func anchorRecheck(_ doc: MGExplainer, library: MGSolidLibrary, budget: MGSuggestionBudget = MGSuggestionBudget()) -> MGAnchorRecheck? {
        var session = MGExplainerSession(pacing: .immediate, clock: MGManualClock(), library: library)
        guard case .success = session.load(doc), let d = session.solid else { return nil }
        var beatOf: [Int: Int] = [:]
        for b in session.keptBeats { if let st = session.solidStep(forBeat: b.index), beatOf[st] == nil { beatOf[st] = b.index } }
        var r = MGAnnotationAnchorReport()
        r.issues = d.offPartAnchors.map { $0.at(beat: $0.step.flatMap { beatOf[$0] }) }
        let framed = MGExplainerFrame.beatAnchorViews(doc, library: library)
        guard let fd = framed.solid else { return nil }
        for v in framed.views { r.append(fd.anchorIssues(v)) }
        return MGAnchorRecheck(issues: r.issues,
                               shown: framed.views.map { ($0.step, $0.beat, Set(fd.checkedAnnotations($0.view, params: $0.params) ?? [])) },
                               search: { fd.anchorSuggestions(ids: $0, views: framed.views, shared: budget, excluding: $1) })
    }
}

extension MGExplainerReport {
    /// The arrow and anchor issues of an explainer copy as `make` lists them (every beat still), for the re-check of
    /// suggested arrow moves, and a search in its framing; nil when it does not load.
    static func arrowRecheck(_ doc: MGExplainer, library: MGSolidLibrary, budget: MGSuggestionBudget) -> MGArrowRecheck? {
        guard let a = anchorRecheck(doc, library: library) else { return nil }
        let checked = MGExplainerFrame.beatCheckViews(doc, library: library)
        guard let fd = checked.solid else { return nil }
        let arrowViews = checked.views.filter { fd.showsArrow($0.view) }
        return MGArrowRecheck(arrows: arrowViews.flatMap { fd.arrowIssues($0) }, anchors: a.issues,
                              shown: checked.views.map { ($0.step, $0.beat, Set(fd.checkedAnnotations($0.view, params: $0.params) ?? [])) },
                              search: { fd.arrowSuggestions(for: $0, views: arrowViews, shared: budget, excluding: $1) })
    }
}

private func num(_ d: Double) -> MGJSON { d.isFinite ? .number(d) : .null }
private func num(_ i: Int) -> MGJSON { .number(Double(i)) }
