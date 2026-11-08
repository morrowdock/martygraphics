// SPDX-License-Identifier: Apache-2.0
import Foundation

// Claims, the one legend, warnings, `describe(id)` and persistence of an explainer session. Foundation only.

/// The 2D item claims the learner was shown, frozen when each state was presented. For every item of every state that
/// became the shown state (the board, each set-up command, each presented beat, each accepted host or learner change)
/// it keeps the item id, in first-shown order, and the set of tiers its displayed numbers had at that moment: the
/// placeholders of its EFFECTIVE content (its wire entry with the scene's `over` entries for it applied in order, so a
/// superseded override never counts), each with the tier of that state (a 2D value is Built when that state's template
/// marks it as data, else Solved; a 3D fact has its own tier). Nothing is recomputed later, so a past claim never
/// changes when the board changes. It only grows; at most `MGLessonLimits.ids` ids with at most 3 tiers each. Read by
/// id only: no dictionary order reaches output.
struct MGShownItems: Equatable {
    private(set) var ids: [String] = []
    private(set) var tiers: [String: Set<MGTier>] = [:]

    /// The claims of one shown scene, with the 3D facts of `solid`.
    mutating func add(_ scene: MGScene, solid: MGSolidDocument?) {
        var wire: [String: [String: MGJSON]] = [:], over: [MGJSON] = []
        if case .array(let a)? = scene.source["items"] {
            for e in a { if let o = e.objectValue, case .string(let id)? = o["id"], wire[id] == nil { wire[id] = o } }
        }
        if case .array(let a)? = scene.source["over"] { over = a }
        for item in scene.items {
            // The effective content: the wire entry, then each `over` entry for this item in order (a later one wins).
            var shown = wire[item.id] ?? [:]
            for e in over where e["id"] == .string(item.id) {
                if case .string(let key)? = e["key"], let value = e["value"] { shown[key] = value }
            }
            var found = Set<MGTier>()
            var stack = shown.keys.sorted().compactMap { MGExplainerHonesty.nonTextKeys.contains($0) ? nil : shown[$0] }
            while let v = stack.popLast() {
                switch v {
                case .string(let s):
                    for body in MGExplainerHonesty.placeholders(s) {
                        let name = body.split(separator: "|", omittingEmptySubsequences: false).first.map(String.init) ?? body
                        found.insert(Self.tier(name, scene.builtValues, solid))
                    }
                case .array(let a): stack += a
                case .object(let o): stack += o.keys.sorted().map { o[$0]! }
                default: break
                }
            }
            add(id: item.id, tiers: found)
        }
    }

    /// The tier of one placeholder name on a scene whose template marks `built` as data: a dotted name is a 3D fact
    /// (Described if unknown); a plain name is a 2D value, Built when it is in `built`.
    static func tier(_ name: String, _ built: Set<String>, _ solid: MGSolidDocument?) -> MGTier {
        if name.contains(".") {
            guard let doc = solid else { return .described }
            return MGSolidFacts.lookup(name, doc.facts, doc.aliases)?.fact.tier ?? .described
        }
        return built.contains(name) ? .built : .solved
    }

    mutating func add(id: String, tiers new: Set<MGTier>) {
        if tiers[id] == nil { ids.append(id); tiers[id] = [] }
        tiers[id]!.formUnion(new)
    }

    /// `[{"id", "tiers"}]` in first-shown order, tiers lowest first (the explainer snapshot's `shown`).
    var json: MGJSON {
        .array(ids.map { id in .object(["id": .string(id), "tiers": .array(tiers[id]!.sorted().map { .string($0.name) })]) })
    }

    /// Canonical bytes of one entry at most: a 24-character id and all 3 tiers (73 bytes), plus room.
    static let entryBytes = 80
    /// Canonical bytes of the whole record at most (part of `MGExplainerLimits.snapshotBytes`).
    static let maxBytes = MGLessonLimits.ids * entryBytes + 16
}

/// The beat claims the learner was shown, frozen the same way: for each presented beat (0-based), the set of tiers its
/// caption had and, per check (in check order), the set of tiers that check's value had, on every state shown while it
/// was the presented beat (its presentation, then each accepted host or learner change). A past beat's caption and
/// checks read only these frozen tiers (their lowest); the presented beat's stay live. At most `MGExplainerLimits.beats`
/// beats, each with a caption and at most `MGExplainerLimits.checksPerBeat` checks, at most 3 tiers each.
struct MGShownBeats: Equatable {
    private(set) var caption: [Int: Set<MGTier>] = [:]
    private(set) var checks: [Int: [Set<MGTier>]] = [:]

    /// The caption tier and check tiers of beat `k` on `scene` (a caption with no placeholder and no `unchecked` adds
    /// no tier; it makes no claim).
    mutating func add(_ k: Int, say: String, unchecked: Bool, checkNames: [String], scene: MGScene, solid: MGSolidDocument?) {
        let names = MGExplainerHonesty.placeholders(say).map { $0.split(separator: "|", omittingEmptySubsequences: false).first.map(String.init) ?? $0 }
        let t: MGTier? = unchecked ? .described : names.map { MGShownItems.tier($0, scene.builtValues, solid) }.min()
        set(k, caption: t.map { [$0] } ?? [], checks: checkNames.map { [MGShownItems.tier($0, scene.builtValues, solid)] })
    }

    /// Adds tiers to beat `k` (restore, and `add`).
    mutating func set(_ k: Int, caption new: Set<MGTier>, checks list: [Set<MGTier>]) {
        caption[k, default: []].formUnion(new)
        var c = checks[k] ?? Array(repeating: [], count: list.count)
        for (j, t) in list.enumerated() where j < c.count { c[j].formUnion(t) }
        checks[k] = c
    }

    /// `[{"beat", "caption", "checks"}]` by beat, tiers lowest first (the explainer snapshot's `shownBeats`).
    var json: MGJSON {
        func tiers(_ t: Set<MGTier>) -> MGJSON { .array(t.sorted().map { .string($0.name) }) }
        return .array(caption.keys.sorted().map { k in
            .object(["beat": .number(Double(k)), "caption": tiers(caption[k]!), "checks": .array((checks[k] ?? []).map(tiers))])
        })
    }

    /// Canonical bytes of one entry at most: beat 15, a caption and 8 checks with all 3 tiers (312 bytes), plus room.
    static let entryBytes = 360
    /// Canonical bytes of the whole record at most (part of `MGExplainerLimits.snapshotBytes`).
    static let maxBytes = MGExplainerLimits.beats * entryBytes + 16
}

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
        return ((lesson.state ?? lesson.projected)?.scene.builtValues ?? []).contains(name) ? .built : .solved
    }

    /// Every claim, in this order: 3D motion (part order), 3D annotations (PR 3a), the title, the board template, 2D
    /// items the learner was shown (first-shown order), then per presented kept beat its caption and its checks. A beat
    /// that waits to be shown, or is still open, adds no claim yet.
    public var claims: [MGExplainerClaim] {
        var out: [MGExplainerClaim] = []
        if let doc = solid {
            for c in doc.claims where c.kind == .motion {
                out.append(MGExplainerClaim(kind: .motion, id: c.id, tier: c.tier, badge: c.badge, why: c.why))
            }
            // 3D annotation claims (PR 3a), in authored order: labels, arrows, dimensions.
            for c in doc.claims where c.kind == .annotation {
                out.append(MGExplainerClaim(kind: .annotation, id: c.id, tier: c.tier, badge: c.badge, why: c.why))
            }
        }
        if let t = titleTier {
            let why = t == .solved ? "Its numbers are engine facts" : t == .described ? "Title has typed numbers" : "It shows a fact below Solved"
            out.append(MGExplainerClaim(kind: .title, id: "title", tier: t, badge: t.badge(.title), why: why))
        }
        if let b = board, case .string(let name)? = b["template"] {
            let built = !((lesson.state ?? lesson.projected)?.scene.builtValues ?? []).isEmpty
            out.append(MGExplainerClaim(kind: .template, id: "board.template", tier: built ? .built : .solved,
                                        badge: built ? "Data as given" : "Solved",
                                        why: built ? "The \(name) template shows some data as given" : "Computed by the \(name) template"))
        }
        out += itemClaims
        let pending = Set(pendingClaims)
        let frozen = recordedBeats
        for b in keptBeats where presentedBeats.contains(b.index) {
            let n = b.index + 1
            // A past beat reads the tiers frozen while it was shown; the presented beat's claims are live.
            let past = b.index != presented.beat ? b.index : nil
            let t: MGTier?
            if let k = past, let c = frozen.caption[k] { t = c.min() }
            else { t = pending.contains("beat.\(n)") ? nil : b.unchecked != nil ? .described : MGExplainerHonesty.placeholders(b.say).map { tier(ofPlaceholder: $0) }.min() }
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
                let t = past.flatMap { frozen.checks[$0].flatMap { j < $0.count ? $0[j].min() : nil } } ?? tier(ofPlaceholder: name)
                let text: String
                if name.contains("."), let c = threeD.next() { text = c.check.text } else { text = name }
                out.append(MGExplainerClaim(kind: .check, id: "beat.\(n).check.\(j + 1)", tier: t, badge: t.badge(.check), why: "Checked: \(text)"))
            }
        }
        return out
    }

    /// The record of shown 2D item claims, with the states the lesson showed in the current call that `absorb` has not
    /// read yet (their claims are frozen with the same facts).
    var recordedShown: MGShownItems {
        var r = shownItems
        for (_, scene) in lesson.shownScenes { r.add(scene, solid: solid) }
        return r
    }

    /// The record of shown beat claims, with the states `absorb` has not read yet.
    var recordedBeats: MGShownBeats {
        var r = shownBeats
        freezeBeats(lesson.shownScenes, into: &r)
        return r
    }

    /// Freezes the beat claims of shown scenes in order: a scene that presents beat `k` makes `k` the presented beat;
    /// every scene adds the tiers of the presented beat's caption and checks on that scene.
    func freezeBeats(_ scenes: [(beat: Int?, scene: MGScene)], into r: inout MGShownBeats) {
        var current = presented.beat
        for (k, scene) in scenes {
            if let k { current = k }
            guard let c = current, let b = beats[c] else { continue }
            r.add(c, say: b.say, unchecked: b.unchecked != nil, checkNames: b.checkNames, scene: scene, solid: solid)
        }
    }

    /// The 2D items' claims: exactly the items of the states the learner was shown (`MGShownItems`), in first-shown
    /// order. An item that a later beat removes keeps its claim; an item that only a refused beat, a waiting or open
    /// beat, a refused command, a superseded override or the middle of one beat had was never shown and has none. A
    /// noted item (wire or template-built) is a `data` claim; an item whose displayed numbers all come from
    /// placeholders takes the lowest tier it showed, as frozen when it was shown; a template item without a note is
    /// covered by `board.template`.
    var itemClaims: [MGExplainerClaim] {
        guard board != nil else { return [] }
        let shown = recordedShown
        var out: [MGExplainerClaim] = []
        for id in shown.ids {
            if let note = notes[id] {
                let t: MGTier = note.kind == .basis ? .built : .described
                out.append(MGExplainerClaim(kind: .data, id: "item.\(id)", tier: t, badge: note.kind == .basis ? "Data as given" : "Not checked",
                                            why: note.kind == .basis ? "Data as given: \(note.text)" : "Marked unchecked: \(note.text)"))
                continue
            }
            if let t = shown.tiers[id]?.min() {
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
    public var legend: MGExplainerLegend { MGExplainerLegend(claims, solidNotes: solid?.legend.notes ?? []) }

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
    /// view and highlight, the lesson snapshot (as JSON text, so its nesting never adds to this one), the stream
    /// position and the record of shown 2D items (`shown`). Captions and claims are not stored: `restore` derives them
    /// again (the record is checked by `restoreShown`).
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
        if board != nil { o["shown"] = recordedShown.json }
        o["shownBeats"] = recordedBeats.json
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
            if let doc = s.solid, let r = s.poseRefusal(doc, stepOf: s.stepOf) { throw MGError(r) }
            // Every scene the lesson holds (shown and baseline), and every queued command, with the explainer's rules.
            view = .board
            var held = [s.lesson.state, s.lesson.projected].compactMap { $0 }
            held += s.lesson.pending.flatMap { [$0.start, $0.end] }
            for st in held where !s.lesson.boardless {
                // The board rules too: a held scene has no wire `title` (a heading), `steps` or 3D dimension; a
                // template's own computed title stays.
                try MGExplainer.checkBoardShape(st.scene.source)
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
            // A presented beat is a kept beat at or before the lesson's beat that the lesson does not still queue.
            for k in s.presentedBeats.sorted() {
                let queued = s.lesson.pending.contains { $0.index == k && !$0.refused }
                guard let b = s.beats[k], !b.dropped, k <= shown, !queued else { throw MGError("snapshot.presented") }
            }
            try s.restoreShown(o["shown"])
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
            try s.restoreShownBeats(o["shownBeats"])
            // The lesson's caption is the presented beat's line on the restored state, never the saved text; an
            // explainer's lesson has no title of its own (the explainer's title is filled from its header below).
            s.lesson.caption = s.caption
            s.lesson.title = nil
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

    /// The record of shown 2D item claims from a snapshot's `shown`. Restore checks its structure only: an array of at
    /// most `MGLessonLimits.ids` entries `{"id", "tiers"}` (closed keys); each id once, an item identifier that the
    /// shown board's id history (`kinds`) holds and not a 3D id; each tier once, one of `described`, `built`, `solved`;
    /// and the record holds every item of the state shown now with the tiers that state shows. It does not recompute
    /// past claims (the board may have changed since). Anything else is `snapshot.shown`. Without `shown` (a snapshot
    /// made before the record), the record is the state shown now. Without a board, `shown` must be absent or empty.
    mutating func restoreShown(_ v: MGJSON?) throws {
        var record = MGShownItems()
        guard let st = lesson.state, board != nil else {
            if let v, v != .array([]) { throw MGError("snapshot.shown") }
            shownItems = record
            return
        }
        if let v {
            guard case .array(let entries) = v, entries.count <= MGLessonLimits.ids else { throw MGError("snapshot.shown") }
            for e in entries {
                guard let eo = e.objectValue, eo.count == 2, case .string(let id)? = eo["id"], case .array(let list)? = eo["tiers"],
                      (try? MGParser.identifier(.string(id), "snapshot.shown")) != nil, record.tiers[id] == nil, st.kinds[id] != nil,
                      !set3D.contains(id), list.count <= MGTier.allCases.count else { throw MGError("snapshot.shown") }
                var tiers = Set<MGTier>()
                for t in list {
                    guard case .string(let name) = t, let tier = MGTier.allCases.first(where: { $0.name == name }),
                          tiers.insert(tier).inserted else { throw MGError("snapshot.shown") }
                }
                record.add(id: id, tiers: tiers)
            }
            var probe = record
            probe.add(st.scene, solid: solid)
            guard probe == record else { throw MGError("snapshot.shown") }
        } else {
            record.add(st.scene, solid: solid)
        }
        shownItems = record
    }

    /// The record of shown beat claims from a snapshot's `shownBeats`, with structure checks only (`snapshot.shown`): an
    /// array of at most `MGExplainerLimits.beats` entries `{"beat", "caption", "checks"}` (closed keys); each beat once
    /// and a presented kept beat; `caption` a list of tiers, `checks` one list of tiers per check of that beat; each tier
    /// once, one of `described`, `built`, `solved`; every presented kept beat has an entry; and the presented beat's
    /// entry holds the tiers it shows on the state shown now. Past tiers are not recomputed. Without `shownBeats` (a
    /// snapshot made before it), each presented beat's tiers are frozen on the state shown now.
    mutating func restoreShownBeats(_ v: MGJSON?) throws {
        var record = MGShownBeats()
        let presentedKept = presentedBeats.sorted().filter { beats[$0].map { !$0.dropped } ?? false }
        let scene = lesson.state?.scene
        guard let v else {
            if let scene {
                for k in presentedKept {
                    let b = beats[k]!
                    record.add(k, say: b.say, unchecked: b.unchecked != nil, checkNames: b.checkNames, scene: scene, solid: solid)
                }
            }
            shownBeats = record
            return
        }
        func tiers(_ v: MGJSON?) throws -> Set<MGTier> {
            guard case .array(let list)? = v, list.count <= MGTier.allCases.count else { throw MGError("snapshot.shown") }
            var out = Set<MGTier>()
            for t in list {
                guard case .string(let name) = t, let tier = MGTier.allCases.first(where: { $0.name == name }),
                      out.insert(tier).inserted else { throw MGError("snapshot.shown") }
            }
            return out
        }
        guard case .array(let entries) = v, entries.count <= MGExplainerLimits.beats else { throw MGError("snapshot.shown") }
        for e in entries {
            guard let eo = e.objectValue, eo.count == 3, case .number(let d)? = eo["beat"], d.isFinite, d.rounded() == d,
                  d >= 0, d < Double(MGExplainerLimits.beats), case .array(let list)? = eo["checks"] else { throw MGError("snapshot.shown") }
            let k = Int(d)
            guard presentedKept.contains(k), record.caption[k] == nil, let b = beats[k], list.count == b.checkNames.count else {
                throw MGError("snapshot.shown")
            }
            let caption = try tiers(eo["caption"]), checks = try list.map { try tiers($0) }
            // Only tiers the beat's text can have: an `unchecked` caption is Described; a caption without placeholders
            // has none; a 3D fact has its own tier; a 2D value is Built or Solved.
            let names = MGExplainerHonesty.placeholders(b.say).map { $0.split(separator: "|", omittingEmptySubsequences: false).first.map(String.init) ?? $0 }
            func possible(_ name: String) -> Set<MGTier> {
                name.contains(".") ? [MGShownItems.tier(name, [], solid)] : [.built, .solved]
            }
            let captionOK: Bool
            if b.unchecked != nil { captionOK = caption == [.described] }
            else if names.isEmpty { captionOK = caption.isEmpty }
            else {
                // The lowest 3D fact tier (fixed), with Built or Solved for the 2D values when the caption has any.
                let fixed = names.filter { $0.contains(".") }.map { MGShownItems.tier($0, [], solid) }.min() ?? .solved
                let allowed: Set<MGTier> = names.contains { !$0.contains(".") } ? [min(fixed, .built), min(fixed, .solved)] : [fixed]
                captionOK = !caption.isEmpty && caption.isSubset(of: allowed)
            }
            guard captionOK, zip(b.checkNames, checks).allSatisfy({ !$1.isEmpty && $1.isSubset(of: possible($0)) }) else {
                throw MGError("snapshot.shown")
            }
            record.set(k, caption: caption, checks: checks)
        }
        guard record.caption.count == presentedKept.count else { throw MGError("snapshot.shown") }
        if let k = presented.beat, let b = beats[k], let scene {
            var probe = record
            probe.add(k, say: b.say, unchecked: b.unchecked != nil, checkNames: b.checkNames, scene: scene, solid: solid)
            guard probe == record else { throw MGError("snapshot.shown") }
        }
        shownBeats = record
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
