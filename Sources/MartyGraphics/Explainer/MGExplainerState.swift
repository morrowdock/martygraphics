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
        for id in itemOrder {
            if let note = notes[id] {
                let t: MGTier = note.kind == .basis ? .built : .described
                out.append(MGExplainerClaim(kind: .data, id: "item.\(id)", tier: t, badge: note.kind == .basis ? "Data as given" : "Not checked",
                                            why: note.kind == .basis ? "Data as given: \(note.text)" : "Marked unchecked: \(note.text)"))
                continue
            }
            var tiers: [MGTier] = []
            var stack = itemWires[id] ?? []
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
        for b in keptBeats {
            let n = b.index + 1
            let t: MGTier? = b.unchecked != nil ? .described : MGExplainerHonesty.placeholders(b.say).map { tier(ofPlaceholder: $0) }.min()
            if let t {
                let why: String
                if let u = b.unchecked { why = "Marked unchecked: \(u)" }
                else if t == .solved { why = "Its numbers are engine values or facts; its words are not checked" }
                else { why = "It shows a value below Solved" }
                out.append(MGExplainerClaim(kind: .caption, id: "beat.\(n)", tier: t, badge: t.badge(.caption), why: why))
            }
            var threeD = b.checks3D.makeIterator()
            for (j, name) in b.checkNames.enumerated() {
                let t = tier(ofPlaceholder: name)
                let text: String
                if name.contains("."), let c = threeD.next() { text = c.check.text } else { text = name }
                out.append(MGExplainerClaim(kind: .check, id: "beat.\(n).check.\(j + 1)", tier: t, badge: t.badge(.check), why: "Checked: \(text)"))
            }
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
    /// Engine data only: the header, the views as authored, the beats' 3D parts, the lesson snapshot (as JSON text, so
    /// its nesting never adds to this one) and the stream position. `restore` validates everything again.
    public func snapshot() -> MGJSON {
        var o: [String: MGJSON] = ["v": .number(1), "kind": .string("explainerSnapshot"), "frozen": .bool(frozen),
                                   "beatCount": .number(Double(beatCount)), "next": .number(Double(nextStatement))]
        var h: [String: MGJSON] = ["v": .number(1)]
        if let t = titleTemplate { h["title"] = .string(t) }
        if let p = primary { h["primary"] = .string(p) }
        if !notes.isEmpty { h["notes"] = .object(notes.mapValues(\.json)) }
        o["header"] = .object(h)
        if let board { o["board"] = .string(board.canonicalString) }
        if let solidSource { o["solid"] = .string(solidSource.canonicalString) }
        o["beats"] = .array(beats.keys.sorted().map { k -> MGJSON in
            let b = beats[k]!
            var e: [String: MGJSON] = ["beat": .number(Double(k)), "sayAt": .number(Double(b.sayStatement)), "say": .string(b.say),
                                       "dropped": .bool(b.dropped), "checkSpecs": .array(b.checkSpecs.map { .string($0.canonicalString) }),
                                       "checks": .array(b.checks3D.map { .object(["i": .number(Double($0.statement)), "s": .string($0.json.canonicalString)]) })]
            if let u = b.unchecked { e["unchecked"] = .string(u) }
            if let v = b.view { e["view"] = .string(v.canonicalString) }
            if let hl = b.highlight { e["highlight"] = .array(hl.map { .string($0) }) }
            return .object(e)
        })
        o["presented"] = .array(presentedBeats.sorted().map { .number(Double($0)) })
        o["captions"] = .array(captions.keys.sorted().map { .object(["beat": .number(Double($0)), "text": .string(captions[$0]!)]) })
        if let k = presented.beat { o["beat"] = .number(Double(k)) }
        o["items"] = .array(itemOrder.map { id in .object(["id": .string(id), "wires": .string(MGJSON.array(itemWires[id] ?? []).canonicalString)]) })
        o["stream"] = .object(["started": .bool(stream.started), "header": .bool(stream.header), "keep": .bool(stream.keep),
                               "ended": .bool(stream.ended), "exhausted": .bool(stream.exhausted),
                               "bytes": .number(Double(stream.bytes - unfinishedInput.count)), "statements": .number(Double(stream.statements))])
        o["lesson"] = .string(lesson.snapshot().canonicalString)
        return .object(o)
    }

    /// Rebuild a session from `snapshot()`. The solid compiles again (with the kept beats' views), the lesson restores
    /// with the explainer environment, and every 3D check is proved again; the first problem refuses the whole snapshot
    /// with its reason (for example the solid's own reason when it no longer compiles). Never loaded in part.
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
            view = .beat
            guard case .array(let entries)? = o["beats"], entries.count <= MGExplainerLimits.beats else { throw MGError("snapshot.beats") }
            for e in entries {
                guard let eo = e.objectValue, case .string(let say)? = eo["say"], case .array(let names)? = eo["checkSpecs"],
                      case .array(let checks)? = eo["checks"], checks.count <= MGExplainerLimits.checksPerBeat,
                      names.count <= MGExplainerLimits.checksPerBeat else { throw MGError("snapshot.beats") }
                let k = try int(eo["beat"], "snapshot.beats")
                var info = BeatInfo(index: k, sayStatement: try int(eo["sayAt"], "snapshot.beats"), say: say)
                info.dropped = try flag(eo["dropped"], "snapshot.beats")
                if case .string(let u)? = eo["unchecked"] { info.unchecked = u }
                if eo["view"] != nil { info.view = try text(eo["view"], "snapshot.beats") }
                if case .array(let hl)? = eo["highlight"] {
                    info.highlight = try hl.map { guard case .string(let x) = $0 else { throw MGError("snapshot.beats") }; return x }
                }
                info.checkSpecs = try names.map { try text($0, "snapshot.beats") }
                for c in checks {
                    let json = try text(c["s"], "snapshot.beats")
                    info.checks3D.append((try int(c["i"], "snapshot.beats"), try MGSolidClaimCheck.parse(json), json))
                }
                s.beats[k] = info
            }
            if o["solid"] != nil {
                view = .solid
                let src = try text(o["solid"], "snapshot.solid")
                try MGExplainer.checkSolidShape(src)
                s.solidSource = src
                let (doc, map) = try s.compileSolid().get()
                s.solid = doc; s.stepOf = map
                s.ids3D = MGExplainerHonesty.ids3D(doc); s.set3D = Set(s.ids3D)
                for b in s.beats.values {
                    for c in b.checks3D {
                        let t = MGSolidParser.token(c.check.value)
                        guard let (_, f) = MGSolidFacts.lookup(c.check.value, doc.facts, doc.aliases) else { throw MGError("check.fact.\(t)") }
                        guard c.check.holds(f.value) else { throw MGError("check.failed.\(t)") }
                    }
                }
                for k in s.beats.keys.sorted() {
                    // `abs` placeholders and their sign proofs, from the caption.
                    var abs: [String] = []
                    for body in MGExplainerHonesty.placeholders(s.beats[k]!.say) {
                        let pieces = body.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
                        if pieces.count > 1, pieces.dropFirst().contains("abs"), let (name, _) = MGSolidFacts.lookup(pieces[0], doc.facts, doc.aliases),
                           !abs.contains(name) { abs.append(name) }
                    }
                    s.beats[k]!.absNames = abs
                }
                let notesClash = s.notes.keys.sorted().first { s.set3D.contains($0) }
                if let key = notesClash { throw MGError("notes.view.\(MGLessonIssue.segment(key))") }
            } else if s.beats.values.contains(where: { $0.view != nil || !$0.checks3D.isEmpty }) {
                throw MGError("snapshot.solid")
            }
            view = .stream
            let lessonJSON = try text(o["lesson"], "snapshot.lesson")
            let env = MGParseEnvironment(facts: s.solid?.facts ?? [:], aliases: s.solid?.aliases ?? [:], reserved: s.set3D)
            switch MGLessonSession.restore(lessonJSON, pacing: pacing, clock: clock, env: env, boardless: s.frozen && s.board == nil) {
            case .failure(let issue): throw MGError(issue.reason)
            case .success(let l): s.lesson = l
            }
            if let st = s.lesson.state, s.board != nil || !s.frozen {
                let twoD = Set(st.scene.items.map(\.id)).union(st.controls.map(\.id))
                if let clash = s.ids3D.first(where: { twoD.contains($0) }) { throw MGError("explainer.id.duplicate.\(MGLessonIssue.segment(clash))") }
            }
            if s.board == nil, s.frozen != s.lesson.boardless { throw MGError("snapshot.board") }
            if case .array(let items)? = o["items"] {
                for i in items {
                    guard case .string(let id)? = i["id"], (try? MGParser.identifier(.string(id), "")) != nil else { throw MGError("snapshot.items") }
                    guard case .array(let wires) = try text(i["wires"], "snapshot.items") else { throw MGError("snapshot.items") }
                    s.itemOrder.append(id); s.itemWires[id] = wires
                }
            }
            guard case .array(let presented)? = o["presented"] else { throw MGError("snapshot.presented") }
            s.presentedBeats = Set(try presented.map { try int($0, "snapshot.presented") })
            if case .array(let caps)? = o["captions"] {
                guard caps.count <= MGExplainerLimits.beats else { throw MGError("snapshot.presented") }
                for c in caps {
                    guard case .string(let t)? = c["text"], MGJSON.string(t).canonicalByteCount <= MGLessonLimits.lineBytes else { throw MGError("snapshot.presented") }
                    s.captions[try int(c["beat"], "snapshot.presented")] = t
                }
            }
            for k in s.beats.keys.sorted() where !s.beats[k]!.dropped { s.updateSignRefusal(k) }
            if o["beat"] != nil {
                let k = try int(o["beat"], "snapshot.beat")
                guard s.beats[k] != nil else { throw MGError("snapshot.beat") }
                s.presented = s.beatView(k, recordStale: true)
            } else if let doc = s.solid {
                s.presented.solid = doc.view(step: nil)
            }
            if s.frozen, let (t, tier) = try s.filledTitle() { s.title = t; s.titleTier = tier }
            guard let st = o["stream"]?.objectValue else { throw MGError("snapshot.stream") }
            s.stream = StreamStatus(started: try flag(st["started"], "snapshot.stream"), header: try flag(st["header"], "snapshot.stream"),
                                    keep: try flag(st["keep"], "snapshot.stream"), ended: try flag(st["ended"], "snapshot.stream"),
                                    exhausted: try flag(st["exhausted"], "snapshot.stream"),
                                    bytes: try int(st["bytes"], "snapshot.stream"), statements: try int(st["statements"], "snapshot.stream"))
            return .success(s)
        } catch {
            return .failure(MGExplainerIssue(reason(error), view: view))
        }
    }
}
