// SPDX-License-Identifier: Apache-2.0
import Foundation

// Explainer documents (`"kind": "explainer"`, version 1): one document that holds a 2D board (a v1 scene), a 3D solid
// (an assembly v2), or both, driven by ONE list of beats, with one id namespace and one legend. L1 intent only:
// closed keys, bounded sizes, no code. `MGExplainerSession` validates every beat against the engines.

/// Explainer limits. Scene, lesson and assembly limits are unchanged and still apply inside.
public enum MGExplainerLimits {
    /// Raw document bytes read before parsing (`explainer.bytes`, no parse).
    public static let rawBytes = 128 * 1024
    /// Size of the statement stream a document flattens to (the solid counts, owner D5), and of one received stream,
    /// every byte counted (`explainer.bytes`).
    public static let bytes = 64 * 1024
    /// Statements per stream, accepted or refused (`explainer.statements.count`).
    public static let statements = MGLessonLimits.statements
    /// Every statement except `solid` (the lesson statement limit, `stmt.bytes`). The board travels as one statement.
    public static let statementBytes = MGLessonLimits.statementBytes
    /// Beats per explainer, over all its streams (the solid step limit, `explainer.beats.count`).
    public static let beats = MGSolidLimits.steps
    /// Commands and checks per beat (lesson limits) and highlight ids per beat (`beat.highlight.count`).
    public static let commandsPerBeat = MGLessonLimits.commandsPerBeat, checksPerBeat = MGLessonLimits.checksPerBeat, highlightIDs = 16
    /// Notes: entries (`notes.count`) and text scalars (`notes.text.<id>`).
    public static let notes = 24, noteText = 60
    /// Title scalars after placeholders are filled (`explainer.title`); caption `unchecked` scalars (`beat.unchecked.<n>`).
    public static let title = 80, unchecked = 60
    /// Caption scalars as authored (the lesson limit, `stmt.say`).
    public static let say = MGLimits.say
    /// Nesting of a document (`explainer.depth`): its deepest statements are commands, which 4 containers hold, so each
    /// command fits the lesson statement cap (`MGLessonLimits.statementDepth`).
    public static let documentDepth = MGLessonLimits.statementDepth + 4
    /// Nesting of one stream statement, counted on its text (`explainer.depth`); statements other than `solid` must
    /// also fit the lesson statement cap (`lesson.depth`).
    public static let statementDepth = MGLimits.depth
    /// Seconds one input turn of a beat's `spin` takes to play (the beat settles after it).
    public static let spinSecondsPerTurn = 4.0
    /// Size of the session's event history; older records are dropped first.
    public static let history = MGLessonLimits.history
    /// Snapshot size cap (`snapshot.bytes`): the lesson snapshot and the solid source travel as JSON text, which escaping
    /// can at most double, plus the beat records, plus the records of shown claims (`shown`: at most
    /// `MGLessonLimits.ids` entries of at most 80 bytes; `shownBeats`: at most `beats` entries of at most 360 bytes;
    /// `shownAnnotations`: at most 80 entries of at most 112 bytes; `shownMotion`: at most 96 entries of at most 112 bytes).
    public static let snapshotBytes = 2 * (MGLessonLimits.snapshotBytes + MGSolidLimits.bytes) + 2 * bytes + MGShownItems.maxBytes
        + MGShownBeats.maxBytes + MGShownAnnotations.maxBytes + MGShownMotion.maxBytes
}

/// A refused statement, beat or document. `reason` is one stable token (ASCII letters, digits, `_`, `.`, `,`; at most
/// 96 characters); inner 2D, lesson and solid reasons pass through token-normalised. `beat` is 0-based (reasons that
/// name a beat number, such as `text.number.beat.<n>`, are 1-based).
public struct MGExplainerIssue: Error, Equatable, Sendable, CustomStringConvertible {
    /// Where the problem is.
    public enum View: String, Equatable, Sendable { case header, board, solid, beat, annotation, stream }
    public let reason: String
    public var view: View
    public var beat: Int?
    /// Zero-based statement index in the session's stream (for a document: in its flattened statements).
    public var statement: Int?
    public var command: Int?
    /// The id the problem concerns (a solid part), when known.
    public var id: String?
    /// The inner reason of a wrapper reason (`animate.frame`, `beat.refused`), else nil.
    public var detail: String?
    public var origin: MGOrigin = .script
    /// Repair detail of `annotations.visible` (the report's `visibility`); nil for every other reason.
    public var visibility: MGAnnotationVisibilityDetail?
    /// Repair detail of the solid's `parts.resolved` (the report's `limit`); nil for every other reason.
    public var limit: MGSolidLimitDetail?

    public init(_ reason: String, view: View, beat: Int? = nil, statement: Int? = nil, command: Int? = nil, id: String? = nil,
                detail: String? = nil, origin: MGOrigin = .script) {
        self.reason = MGLessonIssue.token(reason); self.view = view; self.beat = beat; self.statement = statement
        self.command = command; self.id = id.map { String($0.unicodeScalars.prefix(64)) }; self.detail = detail.map(MGLessonIssue.token)
        self.origin = origin
    }

    init(_ issue: MGLessonIssue, view: View) {
        self.init(issue.reason, view: issue.beat != nil ? .beat : view, beat: issue.beat, statement: issue.statement,
                  command: issue.command, detail: issue.detail, origin: issue.origin)
    }

    public var description: String {
        var parts = [reason, "(\(view.rawValue))"]
        if let detail { parts.append("(\(detail))") }
        if let statement { parts.append("statement \(statement)") }
        if let beat { parts.append("beat \(beat)") }
        if let command { parts.append("command \(command)") }
        if let id { parts.append("id \(id)") }
        return parts.joined(separator: " ")
    }

    /// `{"view", "beat", "statement", "command", "id", "detail"}` (the check report's `location`).
    public var location: MGJSON {
        func n(_ i: Int?) -> MGJSON { i.map { .number(Double($0)) } ?? .null }
        return .object(["view": .string(view.rawValue), "beat": n(beat), "statement": n(statement), "command": n(command),
                        "id": id.map(MGJSON.string) ?? .null, "detail": detail.map(MGJSON.string) ?? .null])
    }
}

/// A parsed explainer document (L1): `{"v":1,"kind":"explainer","title"?,"primary"?,"notes"?,"board"?,"solid"?,"beats":[…]}`.
/// Parsing checks the shape and limits; `MGExplainerSession.load` validates every statement against the engines and
/// refuses the whole document on the first problem.
public struct MGExplainer: Equatable, Sendable {
    /// A 2D honesty note: the item shows numbers the author typed. `basis`: data with a source (Built, "Data as
    /// given"); `unchecked`: numbers the engine does not check (Described, "Not checked").
    public struct Note: Equatable, Sendable {
        public enum Kind: String, Equatable, Sendable { case basis, unchecked }
        public let kind: Kind
        public let text: String
        var json: MGJSON { .object([kind.rawValue: .string(text)]) }
    }
    public struct Beat: Equatable, Sendable {
        public let say: String
        public let unchecked: String?
        public let ops: [MGJSON]
        public let checks: [MGJSON]
        public let highlight: [MGJSON]?
        public let view: MGJSON?
    }
    public let title: String?
    public let primary: String?
    public let notes: [String: Note]
    public let board: MGJSON?
    public let solid: MGJSON?
    public let beats: [Beat]

    static let keys: Set<String> = ["v", "kind", "title", "primary", "notes", "board", "solid", "beats"]
    static let beatKeys: Set<String> = ["say", "unchecked", "ops", "check", "highlight", "view"]
    /// Keys of a beat `view`: the v2 step view keys, `annotate` included (PR 3a).
    static let viewKeys: Set<String> = ["focus", "explode", "camera", "orbit", "spin", "section", "ghost", "annotate", "pose", "hide", "show"]

    /// The top-level `kind` value of a JSON document, for a tool that dispatches between formats. Read with the engine's
    /// guards first (at most `MGExplainerLimits.rawBytes`, UTF-8 only, nesting at most `MGLimits.depth`); nil when the
    /// text is not such an object or has no `kind`.
    public static func topLevelKind(_ data: Data) -> MGJSON? {
        guard data.count <= MGExplainerLimits.rawBytes, MGJSON.dataRefusal(data, json: "j", depth: "d") == nil,
              let object = try? JSONSerialization.jsonObject(with: data), let json = MGJSON(any: object) else { return nil }
        return json["kind"]
    }

    /// Counts `parse` calls that reached the JSON parser (tests: an oversized input never does).
    static let parses = MGExplainerCounter()

    public static func parse(data: Data) -> Result<MGExplainer, MGExplainerIssue> {
        guard data.count <= MGExplainerLimits.rawBytes else { return .failure(bytesIssue(data.count, MGExplainerLimits.rawBytes)) }
        if let r = MGJSON.dataRefusal(data, maxDepth: MGExplainerLimits.documentDepth, json: "explainer.json", depth: "explainer.depth") {
            return .failure(.init(r, view: .header))   // UTF-8 only, nesting counted before the system parser
        }
        parses.increment()
        guard let object = try? JSONSerialization.jsonObject(with: data), let json = MGJSON(any: object) else {
            return .failure(.init("explainer.json", view: .header))
        }
        return parse(json: json)
    }

    /// `explainer.bytes` for a raw document of `bytes` bytes over `limit`.
    static func bytesIssue(_ bytes: Int, _ limit: Int) -> MGExplainerIssue {
        var e = MGExplainerIssue("explainer.bytes", view: .header)
        e.limit = MGSolidLimitDetail(field: "document", actual: bytes, limit: limit, unit: "bytes")
        return e
    }

    public static func parse(json: MGJSON) -> Result<MGExplainer, MGExplainerIssue> {
        var view = MGExplainerIssue.View.header
        var beat: Int?
        do {
            guard let o = json.objectValue else { throw MGError("explainer.object") }
            try json.checkEntry(maxDepth: MGExplainerLimits.documentDepth, maxBytes: MGExplainerLimits.rawBytes,
                                number: "explainer.number", depth: "explainer.depth", bytes: "explainer.bytes")
            if MGSolidParser.hasTierKey(json) { throw MGError("tier.key") }
            let extra = Set(o.keys).subtracting(keys)
            guard extra.isEmpty else { throw MGError("explainer.unknown.\(MGLessonEngine.segments(extra))") }
            guard o["v"] == .number(1) else { throw MGError("explainer.version") }
            guard o["kind"] == .string("explainer") else { throw MGError("explainer.kind") }
            let header = try Self.header(o)
            let board = o["board"], solid = o["solid"]
            guard board != nil || solid != nil else { throw MGError("explainer.empty") }
            if let b = board { view = .board; try checkBoardShape(b) }
            if let s = solid { view = .solid; try checkSolidShape(s) }
            view = .header
            if let p = header.primary, (p == "board" && board == nil) || (p == "solid" && solid == nil) { throw MGError("explainer.primary") }
            guard case .array(let list)? = o["beats"], !list.isEmpty else { throw MGError("explainer.beats") }
            guard list.count <= MGExplainerLimits.beats else {
                throw MGError("explainer.beats.count", limit: MGSolidLimitDetail(field: "beats", actual: list.count, limit: MGExplainerLimits.beats, unit: "beats"))
            }
            view = .beat
            var beats: [Beat] = []
            for (k, entry) in list.enumerated() {
                beat = k
                guard let b = entry.objectValue else { throw MGError("beat.object") }
                try closedKeys(b, required: ["say"], optional: beatKeys, "beat")
                guard case .string(let say)? = b["say"] else { throw MGError("stmt.say") }
                var unchecked: String?
                if let u = b["unchecked"] {
                    guard case .string(let s) = u else { throw MGError("beat.unchecked.\(k + 1)") }
                    unchecked = s
                }
                var ops: [MGJSON] = [], checks: [MGJSON] = []
                if let raw = b["ops"] {
                    guard case .array(let l) = raw else { throw MGError("beat.ops") }
                    guard l.count <= MGExplainerLimits.commandsPerBeat else {
                        throw MGError("beat.ops.count", limit: MGSolidParser.countDetail("beats[\(k)].ops", l.count, 0...MGExplainerLimits.commandsPerBeat,
                                                                                         unit: "commands"))
                    }
                    if !l.isEmpty, board == nil { throw MGError("explainer.board.missing") }
                    for op in l {
                        if case .string("title")? = op["op"] { throw MGError("explainer.op.title") }
                        try MGLessonEngine.refuseForbidden(op)
                    }
                    ops = l
                }
                if let raw = b["check"] {
                    guard case .array(let l) = raw else { throw MGError("beat.check") }
                    guard l.count <= MGExplainerLimits.checksPerBeat else {
                        throw MGError("beat.checks.count", limit: MGSolidParser.countDetail("beats[\(k)].check", l.count, 0...MGExplainerLimits.checksPerBeat,
                                                                                            unit: "checks"))
                    }
                    checks = l
                }
                var highlight: [MGJSON]?
                if let raw = b["highlight"] {
                    guard case .array(let l) = raw, l.allSatisfy({ if case .string = $0 { return true }; return false }) else { throw MGError("beat.highlight") }
                    if let d = MGSolidParser.countDetail("beats[\(k)].highlight", l.count, 1...MGExplainerLimits.highlightIDs, unit: "ids") {
                        throw MGError("beat.highlight.count", limit: d)
                    }
                    highlight = l
                }
                var v: MGJSON?
                if let raw = b["view"] {
                    guard solid != nil else { throw MGError("explainer.solid.missing") }
                    guard raw.objectValue != nil else { throw MGError("view.object") }
                    v = raw
                }
                beats.append(Beat(say: say, unchecked: unchecked, ops: ops, checks: checks, highlight: highlight, view: v))
            }
            beat = nil; view = .stream
            let doc = MGExplainer(title: header.title, primary: header.primary, notes: header.notes, board: board, solid: solid, beats: beats)
            // A document's size is the size of the statement stream it becomes (the solid counts, owner D5).
            let streamBytes = doc.statementStream.utf8.count
            guard streamBytes <= MGExplainerLimits.bytes else {
                throw MGError("explainer.bytes", limit: MGSolidLimitDetail(field: "document", actual: streamBytes, limit: MGExplainerLimits.bytes, unit: "bytes"))
            }
            return .success(doc)
        } catch let e as MGError {
            var issue = MGExplainerIssue(e.reason, view: view, beat: beat)
            issue.limit = e.limit
            return .failure(issue)
        } catch { return .failure(MGExplainerIssue("unknown", view: view)) }
    }

    /// Closed keys for explainer-owned objects (the lesson rule): `<what>.missing`, `<what>.unknown.<keys>` with every
    /// unknown key as an author segment.
    static func closedKeys(_ o: [String: MGJSON], required: Set<String>, optional: Set<String>, _ what: String) throws {
        let keys = Set(o.keys)
        guard required.isSubset(of: keys) else { throw MGError("\(what).missing") }
        let extra = keys.subtracting(required.union(optional))
        guard extra.isEmpty else { throw MGError("\(what).unknown.\(MGLessonEngine.segments(extra))") }
    }

    // MARK: header

    struct Header: Equatable { var title: String?; var primary: String?; var notes: [String: Note] }

    /// `title`, `primary` and `notes` of a document or a header statement. The title's placeholders must name 3D facts
    /// (they fill once the views are fixed, at the first beat).
    static func header(_ o: [String: MGJSON]) throws -> Header {
        var h = Header(title: nil, primary: nil, notes: [:])
        if let t = o["title"] {
            guard case .string(let s) = t else { throw MGError("explainer.title") }
            if let d = MGSolidParser.countDetail("title", s.unicodeScalars.count, 1...(4 * MGExplainerLimits.title), unit: "characters") {
                throw MGError("explainer.title", limit: d)
            }
            do { _ = try MGSolidParser.text(t, 4 * MGExplainerLimits.title, "explainer.title", field: "title") }
            catch let e as MGSolidIssue {
                // A blank title: 1–80 characters (the filled rule), not the raw cap of the text check.
                throw MGError("explainer.title", limit: e.limit.map {
                    $0.actual == 0 ? MGSolidLimitDetail(field: "title", actual: 0, limit: MGExplainerLimits.title, unit: "characters", minimum: 1) : $0
                })
            }
            catch { throw MGError("explainer.title") }
            for body in MGExplainerHonesty.placeholders(s) {
                let name = body.split(separator: "|", omittingEmptySubsequences: false).first.map(String.init) ?? ""
                guard name.contains(".") else { throw MGError("explainer.title") }
            }
            h.title = s
        }
        if let p = o["primary"] {
            guard p == .string("board") || p == .string("solid") else { throw MGError("explainer.primary") }
            if case .string(let s) = p { h.primary = s }
        }
        if let n = o["notes"] {
            guard case .object(let entries) = n else { throw MGError("notes.object") }
            if let d = MGSolidParser.countDetail("notes", entries.count, 1...MGExplainerLimits.notes, unit: "notes") { throw MGError("notes.count", limit: d) }
            for key in entries.keys.sorted() {
                let seg = MGLessonIssue.segment(key)
                guard (try? MGParser.identifier(.string(key), "")) != nil, let e = entries[key]!.objectValue, e.count == 1,
                      let (kind, value) = e.first, let k = Note.Kind(rawValue: kind) else { throw MGError("notes.entry.\(seg)") }
                guard case .string(let text) = value else { throw MGError("notes.text.\(seg)") }
                if let d = MGSolidParser.countDetail("notes.\(seg).\(kind)", text.unicodeScalars.count, 1...MGExplainerLimits.noteText, unit: "characters") {
                    throw MGError("notes.text.\(seg)", limit: d)
                }
                guard (try? MGSolidParser.text(value, MGExplainerLimits.noteText, "")) != nil else {
                    throw MGError("notes.text.\(seg)", limit: (text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? MGSolidLimitDetail(field: "notes.\(seg).\(kind)", actual: 0, limit: MGExplainerLimits.noteText, unit: "characters", minimum: 1) : nil))
                }
                h.notes[key] = Note(kind: k, text: text)
            }
        }
        return h
    }

    /// The board may not have its own walkthrough, title or 3D dimension; it must be an object.
    static func checkBoardShape(_ b: MGJSON) throws {
        guard let o = b.objectValue else { throw MGError("explainer.board") }
        if o["steps"] != nil { throw MGError("explainer.board.steps") }
        if o["title"] != nil { throw MGError("explainer.board.title") }
        if o["dim"] == .string("3d") { throw MGError("explainer.board.dim") }
    }

    /// The solid must be an assembly v2 object without steps (beats replace them) or a title (the explainer has one).
    static func checkSolidShape(_ s: MGJSON) throws {
        guard let o = s.objectValue else { throw MGError("explainer.solid") }
        guard o["v"] == .number(2) else { throw MGError("explainer.solid.version") }
        if o["steps"] != nil { throw MGError("explainer.solid.steps") }
        if o["title"] != nil { throw MGError("explainer.solid.title") }
    }

    // MARK: statements

    /// The header statement's object.
    var headerObject: MGJSON {
        var h: [String: MGJSON] = ["v": .number(1)]
        if let title { h["title"] = .string(title) }
        if let primary { h["primary"] = .string(primary) }
        if !notes.isEmpty { h["notes"] = .object(notes.mapValues(\.json)) }
        return .object(h)
    }

    /// The document as a statement stream: header, the views (the board first, unless it shows a 3D fact, which needs
    /// the solid first), then per beat `say` (with `unchecked`), its commands, checks, view and highlight, then `end`.
    /// Feeding these statements gives exactly the state that `MGExplainerSession.load` gives.
    public var statements: [MGJSON] {
        var out: [MGJSON] = [.object(["explainer": headerObject])]
        let boardFirst = board.map { !MGExplainerHonesty.usesFacts($0) } ?? false
        if boardFirst, let board { out.append(.object(["board": board])) }
        if let solid { out.append(.object(["solid": solid])) }
        if !boardFirst, let board { out.append(.object(["board": board])) }
        for b in beats {
            var say: [String: MGJSON] = ["say": .string(b.say)]
            if let u = b.unchecked { say["unchecked"] = .string(u) }
            out.append(.object(say))
            out += b.ops
            out += b.checks.map { .object(["check": $0]) }
            if let v = b.view { out.append(.object(["view": v])) }
            if let h = b.highlight { out.append(.object(["highlight": .array(h)])) }
        }
        out.append(.object(["end": .bool(true)]))
        return out
    }

    /// Newline-delimited canonical statements (one JSON object per line).
    public var statementStream: String { statements.map(\.canonicalString).joined(separator: "\n") + "\n" }

    // MARK: conversions (tests: B5, B6, T9)

    /// A lesson document as an explainer: `kind` becomes `explainer`, `scene` becomes `board`, beats stay.
    static func fromLesson(_ lesson: MGJSON) -> MGJSON? {
        guard var o = lesson.objectValue else { return nil }
        o["kind"] = .string("explainer")
        o["board"] = o.removeValue(forKey: "scene")
        return .object(o)
    }

    /// An assembly v2 with steps as an explainer: the steps leave the solid and become beats (`say`, `check`,
    /// `unchecked` and `highlight` stay beat keys; the other step keys go into `view`); the title moves up.
    static func fromAssembly(_ assembly: MGJSON) -> MGJSON? {
        guard var solid = assembly.objectValue else { return nil }
        let steps = solid.removeValue(forKey: "steps")
        let title = solid.removeValue(forKey: "title")
        var beats: [MGJSON] = []
        if case .array(let list)? = steps {
            for s in list {
                guard let so = s.objectValue else { return nil }
                var beat: [String: MGJSON] = [:], view: [String: MGJSON] = [:]
                for (k, v) in so {
                    if ["say", "check", "unchecked", "highlight"].contains(k) { beat[k] = v } else { view[k] = v }
                }
                if !view.isEmpty { beat["view"] = .object(view) }
                beats.append(.object(beat))
            }
        }
        var o: [String: MGJSON] = ["v": .number(1), "kind": .string("explainer"), "solid": .object(solid), "beats": .array(beats)]
        if let title { o["title"] = title }
        return .object(o)
    }
}

/// A thread-safe counter (test probes).
final class MGExplainerCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func increment() { lock.lock(); n += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return n }
}
