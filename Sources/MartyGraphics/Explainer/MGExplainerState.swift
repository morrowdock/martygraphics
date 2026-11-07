// SPDX-License-Identifier: Apache-2.0
import Foundation

// Claims, the one legend, warnings, `describe(id)` and persistence of an explainer session. Foundation only.

extension MGExplainerSession {
    /// Beats that are kept (accepted and not refused later), in beat order.
    var keptBeats: [BeatInfo] { beats.keys.sorted().compactMap { beats[$0] }.filter { !$0.dropped } }

    /// The tier of one placeholder: a plain name is a 2D engine value (Solved, or Built when its template marks it as
    /// data); a dotted name is a 3D fact (its own tier; Described if it is unknown).
    func tier(ofPlaceholder body: String) -> MGTier {
        let name = body.split(separator: "|", omittingEmptySubsequences: false).first.map(String.init) ?? body
        if name.contains(".") {
            guard let doc = solid else { return .described }
            return MGSolidFacts.lookup(name, doc.facts, doc.aliases)?.fact.tier ?? .described
        }
        return (lesson.projected?.scene.builtValues ?? []).contains(name) ? .built : .solved
    }

    /// Every claim, in this order: 3D motion (part order), 3D annotations (PR 3a), the title, the board template, 2D
    /// items (board order, then `add` order), then per kept beat its caption and its checks.
    public var claims: [MGExplainerClaim] {
        var out: [MGExplainerClaim] = []
        if let doc = solid {
            for c in doc.claims where c.kind == .motion {
                out.append(MGExplainerClaim(kind: .motion, id: c.id, tier: c.tier, badge: c.badge, why: c.why))
            }
        }
        // SEAM (PR 3a): annotation claims (labels, arrows, dimensions in authored order) go here.
        if let t = titleTier {
            let why = t == .solved ? "Its numbers are engine facts" : t == .described ? "Title has typed numbers" : "It shows a fact below Solved"
            out.append(MGExplainerClaim(kind: .title, id: "title", tier: t, badge: t.badge(.title), why: why))
        }
        if let b = board, case .string(let name)? = b["template"] {
            let built = !(lesson.projected?.scene.builtValues ?? []).isEmpty
            out.append(MGExplainerClaim(kind: .template, id: "board.template", tier: built ? .built : .solved,
                                        badge: built ? "Data as given" : "Solved",
                                        why: built ? "The \(name) template shows some data as given" : "Computed by the \(name) template"))
        }
        out += itemClaims
        let pending = Set(pendingClaims)
        for b in keptBeats {
            let n = b.index + 1
            let t: MGTier? = pending.contains("beat.\(n)") ? nil : b.unchecked != nil ? .described : MGExplainerHonesty.placeholders(b.say).map { tier(ofPlaceholder: $0) }.min()
            if let t {
                let why: String
                if let u = b.unchecked { why = "Marked unchecked: \(u)" }
                else if t == .solved { why = "Its numbers are engine values or facts; its words are not checked" }
                else { why = "It shows a value below Solved" }
                out.append(MGExplainerClaim(kind: .caption, id: "beat.\(n)", tier: t, badge: t.badge(.caption), why: why))
            }
            var threeD = b.checks3D.makeIterator()
            for (j, name) in b.checkNames.enumerated() {
                // A 2D check of the presented beat that the state shown now breaks (a learner or host change) is not
                // current: it is left out, never kept as "Checked" (`notCurrent`).
                if !name.contains("."), b.index == presented.beat, notCurrent.contains("beat.\(n).check.\(j + 1)") { continue }
                // While the board still moves to the beat's state, its 2D checks are pending, not "Checked".
                if pending.contains("beat.\(n).check.\(j + 1)") { continue }
                let t = tier(ofPlaceholder: name)
                let text: String
                if name.contains("."), let c = threeD.next() { text = c.check.text } else { text = name }
                out.append(MGExplainerClaim(kind: .check, id: "beat.\(n).check.\(j + 1)", tier: t, badge: t.badge(.check), why: "Checked: \(text)"))
            }
        }
        return out
    }

    /// The 2D items' claims, from the scenes themselves (the projected state, then items only the presented state has),
    /// so a refused beat or a removed item leaves no claim, and a restored scene is the claim source. A noted item
    /// (wire or template-built) is a `data` claim; an author item whose numbers all come from placeholders (its wire
    /// item and `over` values) takes their lowest tier; a template item without a note is covered by `board.template`.
    var itemClaims: [MGExplainerClaim] {
        guard board != nil else { return [] }
        var ids: [String] = [], seen = Set<String>(), sources: [MGJSON] = []
        for st in [lesson.projected, lesson.state].compactMap({ $0 }) {
            for i in st.scene.items where seen.insert(i.id).inserted { ids.append(i.id) }
            sources.append(st.scene.source)
        }
        var out: [MGExplainerClaim] = []
        for id in ids {
            if let note = notes[id] {
                let t: MGTier = note.kind == .basis ? .built : .described
                out.append(MGExplainerClaim(kind: .data, id: "item.\(id)", tier: t, badge: note.kind == .basis ? "Data as given" : "Not checked",
                                            why: note.kind == .basis ? "Data as given: \(note.text)" : "Marked unchecked: \(note.text)"))
                continue
            }
            var stack: [MGJSON] = []
            for src in sources {
                if case .array(let items)? = src["items"] { stack += items.filter { $0["id"] == .string(id) } }
                if case .array(let over)? = src["over"] { stack += over.filter { $0["id"] == .string(id) }.compactMap { $0["value"] } }
            }
            var tiers: [MGTier] = []
            while let v = stack.popLast() {
                switch v {
                case .string(let s): tiers += MGExplainerHonesty.placeholders(s).map { tier(ofPlaceholder: $0) }
                case .array(let a): stack += a
                case .object(let o): stack += o.keys.sorted().map { o[$0]! }
                default: break
                }
            }
            if let t = tiers.min() {
                out.append(MGExplainerClaim(kind: .caption, id: "item.\(id)", tier: t, badge: t.badge(.caption),
                                            why: t == .solved ? "Its numbers are engine values or facts" : "It shows a value below Solved"))
            }
        }
        return out
    }

    /// Claims of the presented beat that wait for the board to settle (`boardSettled`): its caption when it shows a 2D
    /// value, and its 2D checks. They are left out of `claims` and the legend until the board shows the beat's state.
    public var pendingClaims: [String] {
        guard !boardSettled, let k = presented.beat, let b = beats[k] else { return [] }
        var out: [String] = []
        if b.unchecked == nil, MGExplainerHonesty.placeholders(b.say).contains(where: { !($0.split(separator: "|").first ?? "").contains(".") }) {
            out.append("beat.\(k + 1)")
        }
        for (j, name) in b.checkNames.enumerated() where !name.contains(".") { out.append("beat.\(k + 1).check.\(j + 1)") }
        return out
    }

    /// Check claims of the presented beat that no longer hold on the state shown now (after a learner or host change),
    /// by claim id. Such a claim is left out of `claims` and the legend; the caption shows the live values.
    public var notCurrent: [String] {
        guard let k = presented.beat, let b = beats[k], let scene = lesson.state?.scene else { return [] }
        var out: [String] = []
        for (j, spec) in b.checkSpecs.enumerated() {
            guard case .string(let name)? = spec["value"], !name.contains(".") else { continue }
            if (try? MGCheck.parse(spec))?.failure(in: scene) != nil { out.append("beat.\(k + 1).check.\(j + 1)") }
        }
        return out
    }

    /// The one legend (owner D4).
    public var legend: MGExplainerLegend { MGExplainerLegend(claims) }

    /// Note keys that name no 2D item that was ever on the board (`notes.unused.<id>`), sorted.
    public var unusedNotes: [String] {
        let seen = Set((lesson.state?.kinds.keys).map(Array.init) ?? []).union((lesson.projected?.kinds.keys).map(Array.init) ?? [])
        return notes.keys.sorted().filter { !seen.contains($0) }
    }

    /// Warnings in order: unused notes, then the solid's warnings. The strict profile refuses `notes.unused.<id>`.
    public var warnings: [MGExplainerIssue] {
        unusedNotes.map { MGExplainerIssue("notes.unused.\(MGLessonIssue.segment($0))", view: .header) }
            + (solid?.warnings ?? []).map { MGExplainerIssue($0.reason, view: .solid, id: $0.part) }
    }

    /// Facts about one member of the namespace: a 2D id (the lesson's describe), a table sub-address (the table plus
    /// `row`), a 3D part, anchor or `repeat` base (the solid's describe), an instance (its parts). nil for an unknown id.
    public func describe(_ id: String) -> MGJSON? {
        if let scene = lesson.state?.scene {
            if scene.item(id) != nil { return lesson.describe(id) }
            if let sub = MGExplainerHonesty.subAddress(id, scene), case .object(var o)? = lesson.describe(sub.table) {
                o["row"] = .number(Double(sub.row))
                if let c = sub.column { o["column"] = .number(Double(c)) }
                return .object(o)
            }
        }
        guard let doc = solid, set3D.contains(id) else { return nil }
        if let d = doc.describe(id) { return d }
        guard let parts = MGExplainerHonesty.parts3D(id, doc) else { return nil }
        return .object(["id": .string(id), "kind": .string("instance"), "parts": .array(parts.map { .string($0) })])
    }
}

// MARK: persistence

extension MGExplainerSession {
    /// Engine data only: the header, the views as authored, the set-up commands, each beat's caption, commands, checks,
    /// view and highlight, the lesson snapshot (as JSON text, so its nesting never adds to this one) and the stream
    /// position. Captions and claims are not stored: `restore` derives them again.
    public func snapshot() -> MGJSON {
        func text(_ v: MGJSON) -> MGJSON { .string(v.canonicalString) }
        var o: [String: MGJSON] = ["v": .number(1), "kind": .string("explainerSnapshot"), "frozen": .bool(frozen),
                                   "beatCount": .number(Double(beatCount)), "next": .number(Double(nextStatement))]
        var h: [String: MGJSON] = ["v": .number(1)]
        if let t = titleTemplate { h["title"] = .string(t) }
        if let p = primary { h["primary"] = .string(p) }
        if !notes.isEmpty { h["notes"] = .object(notes.mapValues(\.json)) }
        o["header"] = .object(h)
        if let board { o["board"] = text(board) }
        if let solidSource { o["solid"] = text(solidSource) }
        o["setup"] = .array(setupOps.map(text))
        o["hostBinds"] = .array(hostBinds.map(text))
        o["beats"] = .array(beats.keys.sorted().map { k -> MGJSON in
            let b = beats[k]!
            var e: [String: MGJSON] = ["beat": .number(Double(k)), "sayAt": .number(Double(b.sayStatement)), "say": .string(b.say),
                                       "dropped": .bool(b.dropped), "checkSpecs": .array(b.checkSpecs.map(text)), "ops": .array(b.ops.map(text)),
                                       "checks": .array(b.checks3D.map { .object(["i": .number(Double($0.statement)), "s": text($0.json)]) })]
            if let u = b.unchecked { e["unchecked"] = .string(u) }
            if let v = b.view { e["view"] = text(v) }
            if let hl = b.highlight { e["highlight"] = .array(hl.map { .string($0) }) }
            return .object(e)
        })
        o["presented"] = .array(presentedBeats.sorted().map { .number(Double($0)) })
        if let k = presented.beat { o["beat"] = .number(Double(k)) }
        o["stream"] = .object(["started": .bool(stream.started), "header": .bool(stream.header), "keep": .bool(stream.keep),
                               "ended": .bool(stream.ended), "exhausted": .bool(stream.exhausted),
                               "bytes": .number(Double(stream.bytes - unfinishedInput.count)), "statements": .number(Double(stream.statements))])
        o["lesson"] = .string(lesson.snapshot().canonicalString)
        return .object(o)
    }

    /// `restore` for snapshot JSON text: over `MGExplainerLimits.snapshotBytes` is `snapshot.bytes`; text that is not
    /// UTF-8 JSON is `snapshot.json` and nesting over 64 levels `snapshot.depth`, both before the system parser.
    public static func restore(data: Data, pacing: MGPacing, clock: MGLessonClock = MGSystemClock(),
                               library: MGSolidLibrary = .builtIn) -> Result<MGExplainerSession, MGExplainerIssue> {
        guard data.count <= MGExplainerLimits.snapshotBytes else { return .failure(MGExplainerIssue("snapshot.bytes", view: .stream)) }
        if let r = MGJSON.dataRefusal(data, json: "snapshot.json", depth: "snapshot.depth") { return .failure(MGExplainerIssue(r, view: .stream)) }
        guard let object = try? JSONSerialization.jsonObject(with: data), let json = MGJSON(any: object) else {
            return .failure(MGExplainerIssue("snapshot.json", view: .stream))
        }
        return restore(json, pacing: pacing, clock: clock, library: library)
    }

    /// Rebuild a session from `snapshot()`. Nothing in it is trusted as proof. The views are checked and compiled again
    /// (the solid with the kept beats' views); the script is replayed from the board with the explainer's rules (rule
    /// N1, one namespace, every set-up and beat command, every 2D and 3D check, every caption), which also gives each
    /// beat's caption again; the lesson restores with the explainer's environment; then every scene it holds (state and
    /// baseline) passes rule N1 and the namespace again, and every queued command the explainer's command rules. All of
    /// it runs in beat order, then statement order. The first problem refuses the whole snapshot with its reason (for
    /// example the solid's own reason when it no longer compiles); it is never loaded in part.
    public static func restore(_ snapshot: MGJSON, pacing: MGPacing, clock: MGLessonClock = MGSystemClock(),
                               library: MGSolidLibrary = .builtIn) -> Result<MGExplainerSession, MGExplainerIssue> {
        var view = MGExplainerIssue.View.stream
        do {
            let m = snapshot.measure(stopAbove: MGExplainerLimits.snapshotBytes)
            guard !m.stopped else { throw MGError("snapshot.bytes") }
            guard m.finite else { throw MGError("snapshot.number") }
            guard m.depth <= MGLimits.depth else { throw MGError("snapshot.depth") }
            guard snapshot.canonicalByteCount <= MGExplainerLimits.snapshotBytes else { throw MGError("snapshot.bytes") }
            guard let o = snapshot.objectValue, o["kind"] == .string("explainerSnapshot") else { throw MGError("snapshot.kind") }
            guard o["v"] == .number(1) else { throw MGError("snapshot.version") }
            func int(_ v: MGJSON?, _ what: String) throws -> Int {
                let d = try MGParser.num(v, -1...1e9, what); guard d.rounded() == d else { throw MGError(what) }; return Int(d)
            }
            func flag(_ v: MGJSON?, _ what: String) throws -> Bool { guard case .bool(let b)? = v else { throw MGError(what) }; return b }
            func text(_ v: MGJSON?, _ what: String) throws -> MGJSON {
                guard case .string(let s)? = v, let d = s.data(using: .utf8), MGJSON.dataRefusal(d, json: what, depth: what) == nil,
                      let any = try? JSONSerialization.jsonObject(with: d, options: [.fragmentsAllowed]), let j = MGJSON(any: any) else { throw MGError(what) }
                return j
            }
            func commands(_ v: MGJSON?, _ what: String) throws -> [MGJSON] {
                guard case .array(let list)? = v, list.count <= MGLessonLimits.statements else { throw MGError(what) }
                return try list.map { try text($0, what) }
            }
            var s = MGExplainerSession(pacing: pacing, clock: clock, library: library)
            view = .header
            guard let ho = o["header"]?.objectValue else { throw MGError("snapshot.header") }
            try MGExplainer.closedKeys(ho, required: ["v"], optional: ["title", "primary", "notes"], "snapshot.header")
            let h = try MGExplainer.header(ho)
            s.titleTemplate = h.title; s.primary = h.primary; s.notes = h.notes
            s.frozen = try flag(o["frozen"], "snapshot.frozen")
            s.beatCount = try int(o["beatCount"], "snapshot.beats")
            guard (0...MGExplainerLimits.beats).contains(s.beatCount) else { throw MGError("snapshot.beats") }
            s.nextStatement = try int(o["next"], "snapshot.next")
            if o["board"] != nil {
                view = .board
                let b = try text(o["board"], "snapshot.board")
                try MGExplainer.checkBoardShape(b)
                try MGExplainerHonesty.checkBoard(b.objectValue!, notes: s.notes)
                s.board = b
            }
            s.setupOps = try commands(o["setup"], "snapshot.setup")
            s.hostBinds = try commands(o["hostBinds"], "snapshot.controls")
            guard s.hostBinds.allSatisfy({ $0["op"] == .string("bind") }) else { throw MGError("snapshot.controls") }
            view = .beat
            guard case .array(let entries)? = o["beats"], entries.count <= MGExplainerLimits.beats else { throw MGError("snapshot.beats") }
            for e in entries {
                guard let eo = e.objectValue, case .string(let say)? = eo["say"], case .array(let specs)? = eo["checkSpecs"],
                      case .array(let checks)? = eo["checks"], checks.count <= MGExplainerLimits.checksPerBeat,
                      specs.count <= MGExplainerLimits.checksPerBeat else { throw MGError("snapshot.beats") }
                let k = try int(eo["beat"], "snapshot.beats")
                guard (0..<MGExplainerLimits.beats).contains(k), s.beats[k] == nil else { throw MGError("snapshot.beats") }
                var info = BeatInfo(index: k, sayStatement: try int(eo["sayAt"], "snapshot.beats"), say: say)
                info.dropped = try flag(eo["dropped"], "snapshot.beats")
                if case .string(let u)? = eo["unchecked"] { info.unchecked = u }
                if eo["view"] != nil { info.view = try text(eo["view"], "snapshot.beats") }
                if case .array(let hl)? = eo["highlight"] {
                    guard (1...MGExplainerLimits.highlightIDs).contains(hl.count) else { throw MGError("beat.highlight.count") }
                    info.highlight = try hl.map { guard case .string(let x) = $0 else { throw MGError("snapshot.beats") }; return x }
                }
                info.checkSpecs = try specs.map { try text($0, "snapshot.beats") }
                // Every saved check with the authored check rules (closed keys, a name, one comparison): a spec that
                // is not a check can never become a claim.
                for spec in info.checkSpecs {
                    if case .string(let name)? = spec["value"], name.contains(".") {
                        do { _ = try MGSolidClaimCheck.parse(spec) } catch {
                            let r = reason(error)
                            throw MGError(r.hasPrefix("step.check.") ? "check.\(r.dropFirst(11))" : r)
                        }
                    } else {
                        _ = try MGCheck.parse(spec)
                    }
                }
                info.ops = try commands(eo["ops"], "snapshot.beats")
                guard info.ops.count <= MGExplainerLimits.commandsPerBeat else { throw MGError("snapshot.beats") }
                for c in checks {
                    let json = try text(c["s"], "snapshot.beats")
                    info.checks3D.append((try int(c["i"], "snapshot.beats"), try MGSolidClaimCheck.parse(json), json))
                }
                // The 3D checks are exactly the dotted check specs, in the same order.
                guard info.checks3D.map(\.json) == info.checkSpecs.filter({ if case .string(let n)? = $0["value"] { return n.contains(".") }; return false })
                else { throw MGError("snapshot.beats") }
                s.beats[k] = info
            }
            let order = s.beats.keys.sorted()
            if o["solid"] != nil {
                view = .solid
                let src = try text(o["solid"], "snapshot.solid")
                try MGExplainer.checkSolidShape(src)
                s.solidSource = src
                let (doc, map) = try s.compileSolid().get()
                s.solid = doc; s.stepOf = map
                s.ids3D = MGExplainerHonesty.ids3D(doc); s.set3D = Set(s.ids3D)
                if let key = s.notes.keys.sorted().first(where: { s.set3D.contains($0) }) { throw MGError("notes.view.\(MGLessonIssue.segment(key))") }
                // Every 3D check again, in beat order, then statement order.
                for k in order where !s.beats[k]!.dropped {
                    for c in s.beats[k]!.checks3D.sorted(by: { $0.statement < $1.statement }) {
                        let t = MGSolidParser.token(c.check.value)
                        guard let (_, f) = MGSolidFacts.lookup(c.check.value, doc.facts, doc.aliases) else { throw MGError("check.fact.\(t)") }
                        guard c.check.holds(f.value) else { throw MGError("check.failed.\(t)") }
                    }
                }
                for k in order {
                    // `abs` placeholders and their sign proofs, from the caption.
                    var abs: [String] = []
                    for body in MGExplainerHonesty.placeholders(s.beats[k]!.say) {
                        let pieces = body.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
                        if pieces.count > 1, pieces.dropFirst().contains("abs"), let (name, _) = MGSolidFacts.lookup(pieces[0], doc.facts, doc.aliases),
                           !abs.contains(name) { abs.append(name) }
                    }
                    s.beats[k]!.absNames = abs
                }
            } else if s.beats.values.contains(where: { $0.view != nil || !$0.checks3D.isEmpty }) {
                throw MGError("snapshot.solid")
            }
            let env = MGParseEnvironment(facts: s.solid?.facts ?? [:], aliases: s.solid?.aliases ?? [:], reserved: s.set3D)
            // The script again, from the board, with the explainer's rules: proves every kept beat's 2D checks and
            // captions, and gives the captions.
            view = .beat
            try s.replayScript(env: env)
            view = .stream
            let lessonJSON = try text(o["lesson"], "snapshot.lesson")
            switch MGLessonSession.restore(lessonJSON, pacing: pacing, clock: clock, env: env, boardless: s.frozen && s.board == nil) {
            case .failure(let issue): throw MGError(issue.reason)
            case .success(let l): s.lesson = l
            }
            if s.board == nil, s.frozen != s.lesson.boardless { throw MGError("snapshot.board") }
            // Every scene the lesson holds (shown and baseline), and every queued command, with the explainer's rules.
            view = .board
            var held = [s.lesson.state, s.lesson.projected].compactMap { $0 }
            held += s.lesson.pending.flatMap { [$0.start, $0.end] }
            for st in held where !s.lesson.boardless {
                if let src = st.scene.source.objectValue { try MGExplainerHonesty.checkBoard(src, notes: s.notes) }
                try MGLessonEngine.guardIDs(st, env)
                // A saved control (its label is text the learner reads) must be one a checked `bind` made.
                for c in st.controls where !s.scriptControls.contains(c.wire) { throw MGError("snapshot.controls") }
            }
            view = .beat
            for p in s.lesson.pending {
                guard let info = s.beats[p.index], info.say == p.say else { throw MGError("snapshot.pending") }
                for c in p.commands { if let r = s.commandRefusal(c.json) { throw MGError(r) } }
                if p.refused { s.beats[p.index]!.dropped = true }
            }
            guard case .array(let presented)? = o["presented"] else { throw MGError("snapshot.presented") }
            s.presentedBeats = Set(try presented.map { try int($0, "snapshot.presented") })
            let shown = s.lesson.state?.beat ?? -1
            for k in order where !s.beats[k]!.dropped {
                // A kept beat is shown (at or before the lesson's beat) or queued in the lesson; nothing else.
                let queued = s.lesson.pending.contains { $0.index == k && !$0.refused }
                guard queued != (s.presentedBeats.contains(k) && k <= shown) else { throw MGError("snapshot.beats") }
            }
            for k in order where !s.beats[k]!.dropped {
                s.updateSignRefusal(k)
                // A closed beat (shown, or queued and complete) needs its sign proofs now, not at a later close.
                let closed = s.presentedBeats.contains(k) || s.lesson.pending.contains { $0.index == k && $0.complete }
                if closed, let issue = s.lesson.closeRefusals[k] { throw MGError(issue.reason) }
            }
            if o["beat"] != nil {
                let k = try int(o["beat"], "snapshot.beat")
                guard s.beats[k] != nil, !s.beats[k]!.dropped, k == shown else { throw MGError("snapshot.beat") }
                s.presented = s.beatView(k, recordStale: true)
            } else if let doc = s.solid {
                guard shown < 0 else { throw MGError("snapshot.beat") }
                s.presented.solid = doc.view(step: nil)
            }
            // The lesson's caption is the presented beat's line on the restored state, never the saved text.
            s.lesson.caption = s.caption
            if s.frozen, let (t, tier) = try s.filledTitle() { s.title = t; s.titleTier = tier }
            guard let st = o["stream"]?.objectValue else { throw MGError("snapshot.stream") }
            for key in ["bytes", "statements"] {
                let v = try int(o["stream"]?[key], "snapshot.stream")
                guard v >= 0, v <= (key == "bytes" ? MGExplainerLimits.bytes : MGExplainerLimits.statements) else { throw MGError("snapshot.stream") }
            }
            s.stream = StreamStatus(started: try flag(st["started"], "snapshot.stream"), header: try flag(st["header"], "snapshot.stream"),
                                    keep: try flag(st["keep"], "snapshot.stream"), ended: try flag(st["ended"], "snapshot.stream"),
                                    exhausted: try flag(st["exhausted"], "snapshot.stream"),
                                    bytes: try int(st["bytes"], "snapshot.stream"), statements: try int(st["statements"], "snapshot.stream"))
            return .success(s)
        } catch {
            return .failure(MGExplainerIssue(reason(error), view: view))
        }
    }

    /// The script from the board: the set-up commands, then each kept beat's commands, its 2D checks on the beat's end
    /// state and its caption, with the explainer's rules (rule N1, one namespace) and the lesson engine. Sets `captions`.
    mutating func replayScript(env: MGParseEnvironment) throws {
        var st: MGLessonState
        if let b = board {
            st = MGLessonState(scene: MGLessonEngine.lessonScene(try MGParser.scene(json: b, extraTemplates: [], env: env).get()))
            try MGLessonEngine.guardIDs(st, env)
        } else {
            guard setupOps.isEmpty, beats.values.allSatisfy({ $0.ops.isEmpty }) else { throw MGError("explainer.board.missing") }
            st = MGLessonState(scene: MGScene(source: MGLessonSession.boardlessSource, template: nil, title: "", is3D: false, width: 12, height: 8,
                                              items: [], steps: [], camera: nil, values: [:], motion: .none, attachments: [:]))
        }
        var made = Set<MGJSON>()
        func run(_ op: MGJSON, _ beat: Int?) throws {
            if let r = commandRefusal(op) { throw MGError(r) }
            st = try MGLessonEngine.run(op, on: st, origin: .script, beat: beat, env: env).state
            for c in st.controls { made.insert(c.wire) }
        }
        let initial = st
        for op in setupOps { try run(op, nil) }
        captions = [:]
        for k in beats.keys.sorted() where !beats[k]!.dropped {
            let info = beats[k]!
            guard (1...MGExplainerLimits.say).contains(info.say.unicodeScalars.count) else { throw MGError("stmt.say") }
            if let u = info.unchecked, (try? MGSolidParser.text(.string(u), MGExplainerLimits.unchecked, "")) == nil { throw MGError("beat.unchecked.\(k + 1)") }
            if info.unchecked == nil, MGExplainerHonesty.typedNumber(info.say) { throw MGError("text.number.beat.\(k + 1)") }
            for op in info.ops { try run(op, k) }
            for spec in info.checkSpecs {
                guard case .string(let name)? = spec["value"], !name.contains(".") else { continue }
                if let why = try MGCheck.parse(spec).failure(in: st.scene) { throw MGError(why) }
            }
            captions[k] = try MGLessonSession.fillLine(info.say, st.scene.values, env: env)
        }
        // Host binds, each checked with the explainer's command rules on the board.
        for c in hostBinds {
            if let r = commandRefusal(c) { throw MGError(r) }
            let r = try MGLessonEngine.run(c, on: initial, origin: .script, beat: nil, env: env).state
            for control in r.controls { made.insert(control.wire) }
        }
        scriptControls = made
    }
}
