// SPDX-License-Identifier: Apache-2.0
import Foundation

// The explainer session: ONE beat timeline for a 2D board and a 3D solid. It wraps one lesson session (pacing, lines,
// pause, the persistent 2D state) and attaches to each lesson beat a 3D view, a highlight list and 3D checks.
// Foundation only, deterministic, a value type (copies are independent sessions that share only the clock).

/// Session events, in order. Times are kept separately (`MGExplainerRecord`).
public enum MGExplainerEvent: Equatable, Sendable {
    case accepted(statement: Int)
    case refused(MGExplainerIssue)
    /// The board statement is on the 2D state (core time to first visible of the board).
    case boardPresented
    /// The solid statement compiled (parse, meshes, cut budget).
    case solidCompiled
    /// The compiled solid is the 3D state a renderer shows (core time to first visible of the solid).
    case solidPresented
    case lineQueued(beat: Int, text: String)
    case lineDue(beat: Int, text: String, changed: Bool)
    case lineStarted(beat: Int)
    case lineEnded(beat: Int)
    /// Beat `beat` is presented in both views: its 2D commands, its 3D view and its highlight.
    case beatPresented(beat: Int)
    case streamEnded
    /// The last line ended and the last 2D transition and 3D spin settled (or `finishNow`).
    case explainerComplete

    public var name: String {
        switch self {
        case .accepted: return "accepted"
        case .refused: return "refused"
        case .boardPresented: return "boardPresented"
        case .solidCompiled: return "solidCompiled"
        case .solidPresented: return "solidPresented"
        case .lineQueued: return "lineQueued"
        case .lineDue: return "lineDue"
        case .lineStarted: return "lineStarted"
        case .lineEnded: return "lineEnded"
        case .beatPresented: return "beatPresented"
        case .streamEnded: return "streamEnded"
        case .explainerComplete: return "explainerComplete"
        }
    }
}

/// One event with the session clock's time.
public struct MGExplainerRecord: Equatable, Sendable {
    public let event: MGExplainerEvent
    public let at: Duration
}

/// Core time marks of one explainer (session clock). The view adds the frame marks (TE2, TE4) in
/// `MGExplainerController.timing`.
public struct MGExplainerTiming: Equatable, Sendable {
    public internal(set) var boardStatementAt: Duration?
    public internal(set) var boardPresentedAt: Duration?
    public internal(set) var solidStatementAt: Duration?
    public internal(set) var solidCompiledAt: Duration?
    public internal(set) var solidPresentedAt: Duration?
    public internal(set) var streamEndedAt: Duration?
    public internal(set) var completeAt: Duration?
    /// TE1: board statement complete → `boardPresented`.
    public var boardCore: Duration? { boardPresentedAt.flatMap { a in boardStatementAt.map { a - $0 } } }
    /// TE3: solid statement complete → `solidCompiled`.
    public var solidCore: Duration? { solidCompiledAt.flatMap { a in solidStatementAt.map { a - $0 } } }
}

/// What a renderer shows for the presented beat in both views.
public struct MGExplainerBeatView: Equatable, Sendable {
    /// The presented beat (0-based), nil before the first beat.
    public var beat: Int?
    /// The 3D view of this beat: cuts, ghosts and part light (nil without a solid).
    public var solid: MGSolidView?
    /// The beat's solid step (focus, explode, camera, orbit, spin); nil means the default view.
    public var step: MGSolidStep?
    /// Highlighted 2D items (canvas emphasis).
    public var boardEmphasis: Set<String> = []
    /// Highlighted table rows and cells (cell index = row × columns + column), by table id.
    public var tableRows: [String: Set<Int>] = [:]
    public var tableCells: [String: Set<Int>] = [:]
    /// Highlighted 3D parts (resolved part ids, in highlight order).
    public var solidHighlight: [String] = []
    /// SEAM (PR 3a): highlighted annotation ids (drawn bold).
    public var annotations: [String] = []

    /// An empty view (no beat, no highlight): what a pane shows before the first beat.
    public init(beat: Int? = nil) { self.beat = beat }
}

/// The Foundation-only explainer session. Statements are validated as soon as each is complete; a refused statement
/// changes nothing (2D state, 3D views, cut cache, budget counters, legend, timers).
public struct MGExplainerSession {
    public let pacing: MGPacing
    public let clock: MGLessonClock
    /// Components that `use` entries in the solid resolve against.
    public let library: MGSolidLibrary

    /// The wrapped lesson session: pacing, lines and the persistent 2D state (an empty built-in scene in a 3D-only
    /// explainer).
    public internal(set) var lesson: MGLessonSession
    /// The title as shown (3D facts filled), set when the views are fixed (the first beat).
    public internal(set) var title: String?
    public internal(set) var titleTier: MGTier?
    public internal(set) var primary: String?
    public internal(set) var notes: [String: MGExplainer.Note] = [:]
    /// The accepted board (wire), nil without one.
    public internal(set) var board: MGJSON?
    /// The accepted solid as authored (with `kind`), nil without one.
    public internal(set) var solidSource: MGJSON?
    /// The compiled solid, with every kept beat's `view` as a step (so cuts are budgeted with the document).
    public internal(set) var solid: MGSolidDocument?
    /// What both views show now.
    public internal(set) var presented = MGExplainerBeatView()
    public internal(set) var history: [MGExplainerRecord] = []
    /// Host calls or presentation-time problems that changed nothing (`line.order`, `beat.highlight.stale.<id>`).
    public internal(set) var hostIssues: [MGExplainerIssue] = []
    public internal(set) var timing = MGExplainerTiming()

    struct BeatInfo: Equatable {
        var index: Int
        var sayStatement: Int
        var say: String
        var unchecked: String?
        var view: MGJSON?
        var highlight: [String]?
        /// 3D checks, in statement order.
        var checks3D: [(statement: Int, check: MGSolidClaimCheck, json: MGJSON)] = []
        /// Every accepted check (2D and 3D) as written, in statement order: the claim order.
        var checkSpecs: [MGJSON] = []
        var checkNames: [String] { checkSpecs.map { if case .string(let s)? = $0["value"] { return s }; return "" } }
        /// Canonical 3D fact names shown with `abs` (each needs a sign-proving check of this beat).
        var absNames: [String] = []
        var dropped = false
        static func == (a: BeatInfo, b: BeatInfo) -> Bool {
            a.index == b.index && a.sayStatement == b.sayStatement && a.say == b.say && a.unchecked == b.unchecked && a.view == b.view
                && a.highlight == b.highlight && a.checks3D.map(\.json) == b.checks3D.map(\.json) && a.checkSpecs == b.checkSpecs
                && a.absNames == b.absNames && a.dropped == b.dropped
        }
    }
    struct StreamStatus: Equatable {
        var started = false, header = false, keep = false, ended = false, exhausted = false
        var bytes = 0, statements = 0
    }

    var beats: [Int: BeatInfo] = [:]
    /// Beat index → step index in `solid`.
    var stepOf: [Int: Int] = [:]
    var presentedBeats = Set<Int>()
    /// The last due line of each beat (what its caption showed).
    public internal(set) var captions: [Int: String] = [:]
    var ids3D: [String] = []
    var set3D = Set<String>()
    var titleTemplate: String?
    /// True after the first accepted beat: the views and the title are fixed.
    var frozen = false
    var beatCount = 0
    var scanner = MGStatementScanner()
    var stream = StreamStatus()
    var nextStatement = 0
    var outbox: [MGExplainerEvent] = []
    /// Where a refusal of the statement being handled belongs.
    var current = MGExplainerIssue.View.stream
    var completedAt: Duration = .zero
    /// Author item wires (board items, then `add` items) and values `set` on them: the input of 2D item claims.
    var itemOrder: [String] = []
    var itemWires: [String: [MGJSON]] = [:]

    public init(pacing: MGPacing = .immediate, clock: MGLessonClock = MGSystemClock(), library: MGSolidLibrary = .builtIn) {
        self.pacing = pacing; self.clock = clock; self.library = library
        lesson = Self.freshLesson(pacing: pacing, clock: clock)
        scanner.cap = MGExplainerLimits.bytes
    }

    static func freshLesson(pacing: MGPacing, clock: MGLessonClock) -> MGLessonSession {
        var l = MGLessonSession(pacing: pacing, clock: clock)
        l.env = MGParseEnvironment()
        return l
    }

    // MARK: read

    public var events: [MGExplainerEvent] { history.map(\.event) }
    /// The presented 2D state (an empty scene in a 3D-only explainer), nil before the board.
    public var state: MGLessonState? { lesson.state }
    public var caption: String? { lesson.caption }
    public var isPaused: Bool { lesson.isPaused }
    public var isComplete: Bool { lesson.isComplete }
    public var openLine: Int? { lesson.openLine }
    public var nextWake: Duration? { lesson.nextWake }
    /// True when the explainer has no board (a 3D-only explainer, once its views are fixed).
    public var isBoardless: Bool { lesson.boardless }
    /// Bytes of a statement that has started but not completed (replay after `restore`).
    public var unfinishedInput: Data { scanner.depth > 0 && !scanner.overflow && !stream.exhausted ? Data(scanner.buffer) : Data() }
    /// The step index of beat `k`'s view in `solid` (for `MGSolidSnapshot.make(_:step:…)`), nil for the default view.
    public func solidStep(forBeat k: Int) -> Int? { stepOf[k] }
    /// The ids of each view in canonical order.
    public var ids: (board: [String], controls: [String], solid: [String]) {
        (lesson.state.map { $0.scene.items.map(\.id) } ?? [], lesson.state.map { $0.controls.map(\.id) } ?? [], ids3D)
    }

    // MARK: input

    /// Feed raw text of a statement stream. Every received byte counts toward the stream's 64 KiB, and a stream holds
    /// at most 256 statements; past either the session emits one terminal refusal and ignores the rest until
    /// `endStream()`.
    @discardableResult public mutating func feed(_ chunk: String) -> [MGExplainerEvent] { feed(bytes: chunk.utf8) }
    @discardableResult public mutating func feed(_ data: Data) -> [MGExplainerEvent] { feed(bytes: data) }

    mutating func feed<S: Sequence>(bytes chunk: S) -> [MGExplainerEvent] where S.Element == UInt8 {
        outbox = []
        for byte in chunk {
            if stream.ended, !MGLessonSession.isSpace(byte) { startStream() }
            stream.bytes += 1
            if stream.exhausted { continue }
            if stream.bytes > MGExplainerLimits.bytes { exhaust("explainer.bytes"); continue }
            for output in scanner.push(byte) { handle(output) }
        }
        absorb(lesson.tick())
        return outbox
    }

    /// The stream closed (same as `{"end":true}`). Unfinished text is refused (`stmt.json`).
    @discardableResult public mutating func endStream() -> [MGExplainerEvent] {
        outbox = []
        if !stream.exhausted { for output in scanner.flush() { handle(output) } } else { resetScanner() }
        if !stream.ended {
            current = .stream
            absorb(lesson.endStream())
            stream.ended = true
        }
        return outbox
    }

    /// Load a whole document. All-or-nothing: the document is validated statement by statement in a fresh session and
    /// refused on the first problem (with its location); on success it replaces this session's explainer.
    public mutating func load(_ doc: MGExplainer) -> Result<[MGExplainerEvent], MGExplainerIssue> {
        var trial = MGExplainerSession(pacing: pacing, clock: clock, library: library)
        var all: [MGExplainerEvent] = []
        for (index, statement) in doc.statements.enumerated() {
            guard statement.isEncodable else { return .failure(MGExplainerIssue("explainer.number", view: .stream, statement: index)) }
            let events = trial.feed(statement.canonicalString + "\n")
            all += events
            if let issue = events.lazy.compactMap({ if case .refused(let i) = $0 { return i } else { return nil } }).first { return .failure(issue) }
        }
        self = trial
        return .success(all)
    }

    mutating func startStream() { stream = StreamStatus(); resetScanner() }
    mutating func resetScanner() { scanner = MGStatementScanner(); scanner.cap = MGExplainerLimits.bytes }

    mutating func exhaust(_ reason: String) {
        stream.exhausted = true
        resetScanner()
        refuse(MGExplainerIssue(reason, view: .stream, statement: nextStatement))
    }

    // MARK: host calls

    @discardableResult public mutating func lineStarted(_ k: Int) -> [MGExplainerEvent] { host { $0.lineStarted(k) } }
    @discardableResult public mutating func lineEnded(_ k: Int) -> [MGExplainerEvent] { host { $0.lineEnded(k) } }
    @discardableResult public mutating func finishNow() -> [MGExplainerEvent] { host { $0.finishNow() } }
    @discardableResult public mutating func tick() -> [MGExplainerEvent] { host { $0.tick() } }
    @discardableResult public mutating func resume() -> [MGExplainerEvent] { host { $0.resume() } }
    /// Stop the beat clock: no line becomes due and no beat is presented; the 2D transition and the 3D spin hold.
    public mutating func pause() { lesson.pause() }

    mutating func host(_ call: (inout MGLessonSession) -> [MGLessonEvent]) -> [MGExplainerEvent] {
        outbox = []
        current = .beat
        let before = lesson.hostIssues.count
        let events = call(&lesson)
        for i in lesson.hostIssues.dropFirst(before) { hostIssues.append(MGExplainerIssue(i, view: .beat)) }
        absorb(events)
        return outbox
    }

    /// A learner moved control `id` to `value` (the lesson path: refused, never clamped).
    @discardableResult public mutating func control(_ id: String, _ value: Double) -> Result<MGLessonState, MGExplainerIssue> {
        outbox = []
        current = .board
        let r = lesson.control(id, value)
        absorb(lesson.outbox)
        return r.mapError { MGExplainerIssue($0, view: .board) }
    }

    /// Apply host commands to the presented 2D state, with the explainer's rules (N1, one namespace).
    @discardableResult public mutating func apply(_ commands: [MGJSON], origin: MGOrigin = .script) -> Result<MGLessonState, MGExplainerIssue> {
        outbox = []
        current = .board
        // The lesson refuses a batch of the wrong size (`beat.ops.count`) before any command is read.
        for (i, c) in commands.enumerated() where commands.count <= MGExplainerLimits.commandsPerBeat {
            if let reason = commandRefusal(c) {
                let issue = MGExplainerIssue(reason, view: .board, command: i, origin: origin)
                refuse(issue)
                return .failure(issue)
            }
        }
        let r = lesson.apply(commands, origin: origin)
        absorb(lesson.outbox)
        if case .success = r { for c in commands { recordWire(c) } }
        return r.mapError { MGExplainerIssue($0, view: .board) }
    }

    // MARK: statements

    mutating func handle(_ output: MGStatementScanner.Output) {
        if stream.ended { startStream() }
        guard stream.statements < MGExplainerLimits.statements else { return exhaust("explainer.statements.count") }
        let index = nextStatement; nextStatement += 1
        stream.statements += 1
        completedAt = clock.now
        current = .stream
        switch output {
        case .garbage: refuse("stmt.json", index)
        case .tooLong: refuse("explainer.bytes", index)
        case .statement(let raw):
            if let r = MGJSON.dataRefusal(Data(raw), maxDepth: MGExplainerLimits.statementDepth, json: "stmt.json", depth: "explainer.depth") {
                return refuse(r, index)
            }
            guard let object = try? JSONSerialization.jsonObject(with: Data(raw)), let json = MGJSON(any: object) else { return refuse("stmt.json", index) }
            statement(json, index, bytes: raw.count)
        }
    }

    mutating func statement(_ json: MGJSON, _ index: Int, bytes: Int) {
        guard let o = json.objectValue else { return refuse("stmt.kind", index) }
        let single = o.count == 1 ? o.first : nil
        let key = o["op"] != nil ? "op" : o["say"] != nil ? "say" : single?.key ?? ""
        current = ["explainer": .header, "board": .board, "solid": .solid][key] ?? (lesson.openBeat != nil ? .beat : key == "op" ? .board : .stream)
        // The first statement of a stream is a header (a new explainer) or `keep` (a follow-up).
        if !stream.started, key != "explainer", key != "keep" { return refuse(MGExplainerIssue("explainer.header", view: .header, statement: index)) }
        if key != "solid" {
            guard bytes <= MGExplainerLimits.statementBytes else { return refuse("stmt.bytes", index) }
            guard json.measure().depth <= MGLessonLimits.statementDepth else { return refuse("lesson.depth", index) }
        }
        if MGSolidParser.hasTierKey(json) { return refuse("tier.key", index) }
        switch key {
        case "explainer": header(single!.value, index)
        case "keep": keep(single!.value, index)
        case "board": boardStatement(single!.value, index)
        case "solid": solidStatement(single!.value, index)
        case "say": say(o, index)
        case "op": op(json, o, index)
        case "check": check(single!.value, index)
        case "view": viewStatement(single!.value, index)
        case "highlight": highlight(single!.value, index)
        case "end":
            guard single?.value == .bool(true) else { return refuse("stmt.kind", index) }
            absorb(lesson.forward(json, index: index))
            stream.ended = true
            if timing.streamEndedAt == nil { timing.streamEndedAt = clock.now }
        default: refuse("stmt.kind", index)
        }
    }

    mutating func header(_ value: MGJSON, _ index: Int) {
        guard !stream.started else { return refuse("stmt.order", index) }
        do {
            guard let o = value.objectValue else { throw MGError("explainer.object") }
            try MGExplainer.closedKeys(o, required: ["v"], optional: ["title", "primary", "notes"], "explainer")
            guard o["v"] == .number(1) else { throw MGError("explainer.version") }
            let h = try MGExplainer.header(o)
            // A header starts a new explainer: everything of the old one goes.
            let paused = lesson.isPaused
            lesson = Self.freshLesson(pacing: pacing, clock: clock)
            if paused { lesson.pause() }
            title = nil; titleTier = nil; titleTemplate = h.title; primary = h.primary; notes = h.notes
            board = nil; solidSource = nil; solid = nil; ids3D = []; set3D = []
            beats = [:]; stepOf = [:]; presentedBeats = []; presented = MGExplainerBeatView(); frozen = false; beatCount = 0
            itemOrder = []; itemWires = [:]; timing = MGExplainerTiming(); captions = [:]
            stream.started = true; stream.header = true
            emit(.accepted(statement: index))
        } catch { refuse(Self.reason(error), index) }
    }

    mutating func keep(_ value: MGJSON, _ index: Int) {
        guard value == .bool(true) else { return refuse("stmt.kind", index) }
        guard !stream.started, lesson.state != nil || solid != nil else { return refuse("stmt.order", index) }
        if lesson.state != nil {
            let events = lesson.forward(.object(["keep": .bool(true)]), index: index)
            absorb(events)
            guard events.contains(.accepted(statement: index)) else { return }
        } else {
            emit(.accepted(statement: index))
        }
        stream.started = true; stream.keep = true
    }

    mutating func boardStatement(_ value: MGJSON, _ index: Int) {
        guard !stream.keep, board == nil, !frozen else { return refuse("stmt.order", index) }
        do {
            try MGExplainer.checkBoardShape(value)
            try MGExplainerHonesty.checkBoard(value.objectValue!, notes: notes)
            // Parsed with the explainer environment (3D facts must already be there), then checked against the 3D
            // namespace in resolved item order (after template build and `hide`).
            let scene = try MGParser.scene(json: value, extraTemplates: [], env: lesson.env).get()
            for item in scene.items where set3D.contains(item.id) { throw MGError("explainer.id.duplicate.\(MGLessonIssue.segment(item.id))") }
        } catch { return refuse(Self.reason(error), index) }
        let events = lesson.forward(.object(["scene": value]), index: index)
        let ok = events.contains(.accepted(statement: index))
        if ok {
            board = value
            timing.boardStatementAt = completedAt
            if case .array(let items)? = value["items"] { for i in items { recordItem(i) } }
            if case .array(let over)? = value["over"] { for e in over { if case .string(let id)? = e["id"], let v = e["value"] { recordSet(id, v) } } }
        }
        absorb(events)
    }

    mutating func solidStatement(_ value: MGJSON, _ index: Int) {
        guard !stream.keep, solidSource == nil, !frozen else { return refuse("stmt.order", index) }
        do { try MGExplainer.checkSolidShape(value) } catch { return refuse(Self.reason(error), index) }
        var src = value.objectValue!
        if src["kind"] == nil { src["kind"] = .string("assembly") }
        let doc: MGSolidDocument
        switch MGSolidParser.document(json: .object(src), library: library) {
        case .failure(let issue): return refuse(MGExplainerIssue(issue.reason, view: .solid, statement: index, id: issue.part))
        case .success(let d): doc = d
        }
        let ids = MGExplainerHonesty.ids3D(doc)
        let set = Set(ids)
        // The arriving view's ids in canonical order against the other view.
        if let s = lesson.projected {
            let twoD = Set(s.scene.items.map(\.id)).union(s.controls.map(\.id))
            if let clash = ids.first(where: { twoD.contains($0) }) {
                return refuse(MGExplainerIssue("explainer.id.duplicate.\(MGLessonIssue.segment(clash))", view: .solid, statement: index))
            }
        }
        if let key = notes.keys.sorted().first(where: { set.contains($0) }) {
            return refuse(MGExplainerIssue("notes.view.\(MGLessonIssue.segment(key))", view: .header, statement: index))
        }
        solidSource = .object(src); solid = doc; ids3D = ids; set3D = set
        lesson.env = MGParseEnvironment(facts: doc.facts, aliases: doc.aliases, reserved: set)
        presented.solid = doc.view(step: nil)
        timing.solidStatementAt = completedAt
        emit(.accepted(statement: index))
        timing.solidCompiledAt = clock.now; emit(.solidCompiled)
        timing.solidPresentedAt = clock.now; emit(.solidPresented)
    }

    /// The title filled from 3D facts, when the views are fixed: (text, tier).
    func filledTitle() throws -> (String, MGTier?)? {
        guard let t = titleTemplate else { return nil }
        do {
            let f = try MGSolidFacts.fill(t, where: "title", n1: false, solid?.facts ?? [:], solid?.aliases ?? [:])
            guard !f.text.isEmpty, f.text.unicodeScalars.count <= MGExplainerLimits.title else { throw MGError("explainer.title") }
            for (name, mods) in zip(f.facts, f.modifiers) where mods.contains("abs") { throw MGError("text.sign.\(MGSolidParser.token(name))") }
            let tier = MGSolidTiers.text(facts: f.facts.compactMap { solid?.facts[$0] }, unchecked: false, typedNumbers: f.typedNumbers)
            return (f.text, tier)
        } catch let e as MGSolidIssue { throw MGError(e.reason) }
    }

    mutating func say(_ o: [String: MGJSON], _ index: Int) {
        current = .beat
        let extra = Set(o.keys).subtracting(["say", "unchecked"])
        guard extra.isEmpty else { return refuse("beat.unknown.\(MGLessonEngine.segments(extra))", index) }
        guard case .string(let raw)? = o["say"], (1...MGExplainerLimits.say).contains(raw.unicodeScalars.count) else { return refuse("stmt.say", index) }
        // The views and the title are fixed at the first beat.
        var fixedTitle: (String, MGTier?)?
        if !frozen {
            guard board != nil || solidSource != nil else { return refuse(MGExplainerIssue("explainer.empty", view: .header, statement: index)) }
            if let p = primary, (p == "board" && board == nil) || (p == "solid" && solidSource == nil) {
                return refuse(MGExplainerIssue("explainer.primary", view: .header, statement: index))
            }
            do { fixedTitle = try filledTitle() } catch { return refuse(MGExplainerIssue(Self.reason(error), view: .header, statement: index)) }
        }
        let k = frozen || board != nil ? lesson.nextBeat : 0, n = k + 1
        guard beatCount < MGExplainerLimits.beats else { return refuse(MGExplainerIssue("explainer.beats.count", view: .beat, beat: k, statement: index)) }
        var unchecked: String?
        if let u = o["unchecked"] {
            guard case .string(let s) = u, (try? MGSolidParser.text(u, MGExplainerLimits.unchecked, "")) != nil else {
                return refuse(MGExplainerIssue("beat.unchecked.\(n)", view: .beat, beat: k, statement: index))
            }
            unchecked = s
        }
        if unchecked == nil, MGExplainerHonesty.typedNumber(raw) {
            return refuse(MGExplainerIssue("text.number.beat.\(n)", view: .beat, beat: k, statement: index))
        }
        var absNames: [String] = []
        for body in MGExplainerHonesty.placeholders(raw) {
            let pieces = body.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard pieces.count > 1, pieces.dropFirst().contains("abs"), pieces[0].contains("."),
                  let doc = solid, let (name, _) = MGSolidFacts.lookup(pieces[0], doc.facts, doc.aliases) else { continue }
            if !absNames.contains(name) { absNames.append(name) }
        }
        let before = lesson
        if !frozen, board == nil { lesson.startBoardless() }
        let events = lesson.forward(.object(["say": .string(raw)]), index: index)
        guard events.contains(.accepted(statement: index)) else {
            if !frozen { lesson = before }
            return absorb(events)
        }
        if !frozen {
            frozen = true
            if let t = fixedTitle { title = t.0; titleTier = t.1 }
        }
        beatCount += 1
        beats[k] = BeatInfo(index: k, sayStatement: index, say: raw, unchecked: unchecked, absNames: absNames)
        updateSignRefusal(k)
        absorb(events)
    }

    /// The open beat's `abs` placeholders each need a check of the same beat that proves the fact's sign; otherwise
    /// the beat is refused when it closes (`text.sign.<name>`, the #21 rule).
    mutating func updateSignRefusal(_ k: Int) {
        guard let info = beats[k] else { return }
        let proven = Set(info.checks3D.filter { $0.check.provesSign }.compactMap { c -> String? in
            guard let doc = solid else { return nil }
            return MGSolidFacts.lookup(c.check.value, doc.facts, doc.aliases)?.name
        })
        if let missing = info.absNames.first(where: { !proven.contains($0) }) {
            lesson.closeRefusals[k] = MGLessonIssue("text.sign.\(MGSolidParser.token(missing))", beat: k, statement: info.sayStatement)
        } else {
            lesson.closeRefusals[k] = nil
        }
    }

    /// The explainer's own refusal of one 2D command (before the lesson sees it), or nil.
    func commandRefusal(_ json: MGJSON) -> String? {
        guard let o = json.objectValue else { return nil }
        if case .string("title")? = o["op"] { return "explainer.op.title" }
        do { try MGExplainerHonesty.checkCommand(o, notes: notes) } catch { return Self.reason(error) }
        switch o["op"] {
        case .string("set")?, .string("remove")?:
            if case .string(let id)? = o["id"], set3D.contains(id) { return "explainer.id.view.\(MGLessonIssue.segment(id))" }
        case .string("add")?:
            if case .string(let id)? = o["item"]?["id"], set3D.contains(id) { return "explainer.id.duplicate.\(MGLessonIssue.segment(id))" }
        default: break
        }
        return nil
    }

    mutating func op(_ json: MGJSON, _ o: [String: MGJSON], _ index: Int) {
        guard board != nil else { return refuse("explainer.board.missing", index) }
        if let reason = commandRefusal(json) {
            var issue = MGExplainerIssue(reason, view: current, statement: index)
            if let b = lesson.openBeat { issue.beat = lesson.pending[b].index; issue.command = lesson.pending[b].commands.count }
            return refuse(issue)
        }
        let events = lesson.forward(json, index: index)
        if events.contains(.accepted(statement: index)) { recordWire(json) }
        absorb(events)
    }

    mutating func check(_ value: MGJSON, _ index: Int) {
        current = .beat
        let dotted: Bool
        if case .string(let name)? = value["value"], name.contains(".") { dotted = true } else { dotted = false }
        guard let b = lesson.openBeat, stream.started else {
            if dotted { return refuse("stmt.order", index) }
            return absorb(lesson.forward(.object(["check": value]), index: index))
        }
        let k = lesson.pending[b].index
        func fail(_ r: String) { refuse(MGExplainerIssue(r, view: .beat, beat: k, statement: index)) }
        guard !lesson.pending[b].refused else { return fail("beat.refused") }
        let used = lesson.pending[b].checks.count + (beats[k]?.checks3D.count ?? 0)
        guard used < MGExplainerLimits.checksPerBeat else { return fail("beat.checks.count") }
        guard dotted else {
            let events = lesson.forward(.object(["check": value]), index: index)
            if events.contains(.accepted(statement: index)) { beats[k]?.checkSpecs.append(value) }
            return absorb(events)
        }
        let c: MGSolidClaimCheck
        do { c = try MGSolidClaimCheck.parse(value) } catch {
            let r = Self.reason(error)
            return fail(r.hasPrefix("step.check.") ? "check." + r.dropFirst("step.check.".count) : r)
        }
        let t = MGSolidParser.token(c.value)
        guard let doc = solid, let (_, fact) = MGSolidFacts.lookup(c.value, doc.facts, doc.aliases) else { return fail("check.fact.\(t)") }
        guard c.holds(fact.value) else {
            // A false 3D claim refuses the whole beat: the #20 rollback path.
            return absorb(lesson.refuseOpenBeat(MGLessonIssue("check.failed.\(t)", beat: k, statement: index)))
        }
        beats[k]?.checks3D.append((index, c, value))
        beats[k]?.checkSpecs.append(value)
        updateSignRefusal(k)
        emit(.accepted(statement: index))
    }

    /// The open beat, or the refusal: `stmt.order` (no beat), `beat.refused` (a cascade).
    mutating func openBeat(_ index: Int) -> Int? {
        guard let b = lesson.openBeat, stream.started else { refuse("stmt.order", index); return nil }
        let k = lesson.pending[b].index
        guard !lesson.pending[b].refused else { refuse(MGExplainerIssue("beat.refused", view: .beat, beat: k, statement: index)); return nil }
        return k
    }

    mutating func viewStatement(_ value: MGJSON, _ index: Int) {
        current = .beat
        guard solidSource != nil else { return refuse("explainer.solid.missing", index) }
        guard let k = openBeat(index) else { return }
        func fail(_ r: String, _ id: String? = nil) { refuse(MGExplainerIssue(r, view: .beat, beat: k, statement: index, id: id)) }
        guard beats[k]?.view == nil else { return fail("stmt.view.twice") }
        guard let o = value.objectValue else { return fail("view.object") }
        let extra = Set(o.keys).subtracting(MGExplainer.viewKeys)
        guard extra.isEmpty else { return fail("view.unknown.\(MGLessonEngine.segments(extra))") }
        switch compileSolid(adding: (k, value)) {
        case .failure(let issue):
            let r = issue.reason.hasPrefix("step.") ? "view." + issue.reason.dropFirst("step.".count) : issue.reason
            fail(r, issue.part)
        case .success(let (doc, map)):
            solid = doc; stepOf = map
            beats[k]?.view = value
            emit(.accepted(statement: index))
        }
    }

    /// The solid compiled with every kept beat's view (and `adding`) as steps, in beat order. Nothing changes here.
    func compileSolid(adding: (Int, MGJSON)? = nil) -> Result<(MGSolidDocument, [Int: Int]), MGSolidIssue> {
        guard var src = solidSource?.objectValue else { return .failure(MGSolidIssue("explainer.solid.missing")) }
        var views = beats.values.filter { $0.view != nil && !$0.dropped }.map { ($0.index, $0.view!) }
        if let a = adding { views.append(a) }
        views.sort { $0.0 < $1.0 }
        var steps: [MGJSON] = [], map: [Int: Int] = [:]
        for (i, (k, v)) in views.enumerated() {
            var s = v.objectValue ?? [:]
            s["say"] = .string("Beat")
            steps.append(.object(s)); map[k] = i
        }
        if !steps.isEmpty { src["steps"] = .array(steps) }
        return MGSolidParser.document(json: .object(src), reusing: solid, library: library).map { ($0, map) }
    }

    mutating func highlight(_ value: MGJSON, _ index: Int) {
        current = .beat
        guard let k = openBeat(index) else { return }
        func fail(_ r: String) { refuse(MGExplainerIssue(r, view: .beat, beat: k, statement: index)) }
        guard beats[k]?.highlight == nil else { return fail("stmt.highlight.twice") }
        guard case .array(let list) = value else { return fail("beat.highlight") }
        var ids: [String] = []
        for v in list { guard case .string(let s) = v else { return fail("beat.highlight") }; ids.append(s) }
        guard (1...MGExplainerLimits.highlightIDs).contains(ids.count) else { return fail("beat.highlight.count") }
        let scene = lesson.projectedIfClosed.scene
        let controls = Set(lesson.projectedIfClosed.controls.map(\.id))
        for id in ids where !resolves(id, scene, controls) { return fail("beat.highlight.ref.\(MGLessonIssue.segment(id))") }
        beats[k]?.highlight = ids
        emit(.accepted(statement: index))
    }

    /// True when a highlight id names a member of the one namespace (a 2D item or control, a 3D member) or a table
    /// sub-address of `scene`.
    func resolves(_ id: String, _ scene: MGScene, _ controls: Set<String>) -> Bool {
        set3D.contains(id) || scene.item(id) != nil || controls.contains(id) || MGExplainerHonesty.subAddress(id, scene) != nil
    }

    // MARK: lesson events

    mutating func absorb(_ events: [MGLessonEvent]) {
        for e in events {
            switch e {
            case .accepted(let i): emit(.accepted(statement: i))
            case .refused(let issue): emit(.refused(MGExplainerIssue(issue, view: current)))
            case .firstPresented: timing.boardPresentedAt = clock.now; emit(.boardPresented)
            case .lineQueued(let k, let t): emit(.lineQueued(beat: k, text: t))
            case .lineDue(let k, let t, let c): captions[k] = t; emit(.lineDue(beat: k, text: t, changed: c))
            case .lineStarted(let k): emit(.lineStarted(beat: k))
            case .lineEnded(let k): emit(.lineEnded(beat: k))
            case .beatPresented(let k):
                presentedBeats.insert(k)
                presented = beatView(k, recordStale: true)
                if let spin = presented.step?.spin, spin != 0, pacing != .immediate, !lesson.fastForward {
                    lesson.extendSettle(seconds: abs(spin) * MGExplainerLimits.spinSecondsPerTurn)
                }
                emit(.beatPresented(beat: k))
            case .streamEnded:
                if timing.streamEndedAt == nil { timing.streamEndedAt = clock.now }
                emit(.streamEnded)
            case .lessonComplete: timing.completeAt = clock.now; emit(.explainerComplete)
            }
        }
        syncDrops()
    }

    /// Beats the lesson refused (a failed 2D check, the queue budget, a check that fails at presentation) lose their 3D
    /// view, highlight and checks; a dropped view releases its cut budget.
    mutating func syncDrops() {
        var rebuild = false
        for k in beats.keys.sorted() where !beats[k]!.dropped {
            let refused: Bool
            if let p = lesson.pending.first(where: { $0.index == k }) { refused = p.refused } else { refused = !presentedBeats.contains(k) }
            guard refused else { continue }
            beats[k]!.dropped = true
            lesson.closeRefusals[k] = nil
            if beats[k]!.view != nil { rebuild = true }
        }
        if rebuild, case .success(let (doc, map)) = compileSolid() { solid = doc; stepOf = map }
    }

    /// The view of beat `k` on the presented state. Highlight ids resolve again; one that no longer resolves is
    /// dropped (and, when `recordStale`, recorded as `beat.highlight.stale.<id>`).
    mutating func beatView(_ k: Int, recordStale: Bool) -> MGExplainerBeatView {
        var v = MGExplainerBeatView(beat: k)
        if let doc = solid {
            let step = stepOf[k]
            v.solid = doc.view(step: step)
            v.step = step.map { doc.steps[$0] }
        }
        guard let info = beats[k], let scene = lesson.state?.scene else { return v }
        let controls = Set(lesson.state?.controls.map(\.id) ?? [])
        for id in info.highlight ?? [] {
            if let doc = solid, set3D.contains(id), let parts = MGExplainerHonesty.parts3D(id, doc) {
                for p in parts where !v.solidHighlight.contains(p) { v.solidHighlight.append(p) }
            } else if set3D.contains(id) {
                v.annotations.append(id)   // SEAM (PR 3a): annotation ids
            } else if scene.item(id) != nil {
                v.boardEmphasis.insert(id)
            } else if let sub = MGExplainerHonesty.subAddress(id, scene) {
                if let c = sub.column { v.tableCells[sub.table, default: []].insert(sub.row * Int(scene.item(sub.table)!.n("cols", 1)) + c) }
                else { v.tableRows[sub.table, default: []].insert(sub.row) }
            } else if !controls.contains(id), recordStale {
                hostIssues.append(MGExplainerIssue("beat.highlight.stale.\(MGLessonIssue.segment(id))", view: .beat, beat: k))
            }
        }
        return v
    }

    // MARK: helpers

    mutating func recordItem(_ item: MGJSON) {
        guard case .string(let id)? = item["id"] else { return }
        if itemWires[id] == nil { itemOrder.append(id) }
        itemWires[id, default: []].append(item)
    }
    mutating func recordSet(_ id: String, _ value: MGJSON) {
        guard itemWires[id] != nil else { return }
        itemWires[id]!.append(value)
    }
    mutating func recordWire(_ command: MGJSON) {
        switch command["op"] {
        case .string("add")?: if let item = command["item"] { recordItem(item) }
        case .string("set")?: if case .string(let id)? = command["id"], let v = command["value"] { recordSet(id, v) }
        default: break
        }
    }

    mutating func emit(_ event: MGExplainerEvent) {
        outbox.append(event)
        history.append(MGExplainerRecord(event: event, at: clock.now))
        if history.count > MGExplainerLimits.history { history.removeFirst(history.count - MGExplainerLimits.history) }
    }
    mutating func refuse(_ reason: String, _ statement: Int) { refuse(MGExplainerIssue(reason, view: current, statement: statement)) }
    mutating func refuse(_ issue: MGExplainerIssue) { emit(.refused(issue)) }

    static func reason(_ error: Error) -> String {
        if let e = error as? MGError { return e.reason }
        if let e = error as? MGSolidIssue { return e.reason }
        return "unknown"
    }
}
