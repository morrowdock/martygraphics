// SPDX-License-Identifier: Apache-2.0
import Foundation

/// Monotonic time source for lesson events. Inject `MGManualClock` in tests; hosts use `MGSystemClock`.
public protocol MGLessonClock: AnyObject, Sendable {
    /// Time since the clock's own origin. Only differences are meaningful.
    var now: Duration { get }
}

/// `ContinuousClock` time since this clock was created.
public final class MGSystemClock: MGLessonClock, @unchecked Sendable {
    private let origin = ContinuousClock.now
    public init() {}
    public var now: Duration { ContinuousClock.now - origin }
}

/// A clock that moves only when told to (tests, replays).
public final class MGManualClock: MGLessonClock, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Duration
    public init(_ start: Duration = .zero) { current = start }
    public var now: Duration { lock.lock(); defer { lock.unlock() }; return current }
    public func advance(by d: Duration) { lock.lock(); current += d; lock.unlock() }
}

/// When the next beat becomes due.
public enum MGPacing: Equatable, Sendable {
    /// Every beat as soon as it is complete and valid (tests, read-only review).
    case immediate
    /// The next beat waits for the host's `lineEnded(k)` (the host speaks each line with its own voice).
    case speech
    /// Line length = words / rate, clamped to 1–12 s (silent mode, tests with an injected clock).
    case estimate(wordsPerSecond: Double)
}

/// Session events, in order. Timestamps are kept separately (`MGLessonRecord`), so sequences compare across runs.
public enum MGLessonEvent: Equatable, Sendable {
    /// A complete statement was validated into the projected state.
    case accepted(statement: Int)
    /// A statement, command or learner value was refused; nothing changed.
    case refused(MGLessonIssue)
    /// A scene statement is on the board: the time-to-first-visible marker (core side).
    case firstPresented
    /// Beat `beat` is complete and valid; `text` is filled from the projected state (fetch speech early).
    case lineQueued(beat: Int, text: String)
    /// Beat `beat` is next: speak `text` (filled from the presented state). `changed`: differs from the queued text
    /// because the learner moved a value in between, so speech must be made again.
    case lineDue(beat: Int, text: String, changed: Bool)
    case lineStarted(beat: Int)
    case lineEnded(beat: Int)
    /// Beat `beat`'s commands are in the presented state.
    case beatPresented(beat: Int)
    /// Every statement of the stream was received and validated.
    case streamEnded
    /// The last line ended and the last transition settled (or `finishNow`).
    case lessonComplete

    /// Short name for logs and ordering tests.
    public var name: String {
        switch self {
        case .accepted: return "accepted"
        case .refused: return "refused"
        case .firstPresented: return "firstPresented"
        case .lineQueued: return "lineQueued"
        case .lineDue: return "lineDue"
        case .lineStarted: return "lineStarted"
        case .lineEnded: return "lineEnded"
        case .beatPresented: return "beatPresented"
        case .streamEnded: return "streamEnded"
        case .lessonComplete: return "lessonComplete"
        }
    }
    /// The beat index the event is about, when it has one.
    public var beat: Int? {
        switch self {
        case .lineQueued(let k, _), .lineDue(let k, _, _), .lineStarted(let k), .lineEnded(let k), .beatPresented(let k): return k
        case .refused(let issue): return issue.beat
        default: return nil
        }
    }
}

/// One event with the session clock's time.
public struct MGLessonRecord: Equatable, Sendable {
    public let event: MGLessonEvent
    public let at: Duration
}

/// One command applied to the presented state.
public struct MGLessonLogEntry: Equatable, Sendable {
    public let command: MGJSON
    public let origin: MGOrigin
    public let beat: Int?
    public let statement: Int?
}

/// The latest presented change, for a renderer: how to move there and which ids changed.
public struct MGLessonChange: Equatable, Sendable {
    /// Grows by one with every presented change.
    public let serial: Int
    public let transition: MGTransition
    public let diff: MGSceneDiff
}

/// L2 + L3 + timing: the Foundation-only lesson session. A value type: copies are independent sessions (they share
/// only the clock). The renderer reads `state` (the presented state); statements are validated against `projected`
/// (the state after every accepted statement) as soon as each is complete.
///
/// Statement lane (one JSON object per statement, D4): partial input is ignored until a statement's closing brace;
/// a refused statement changes nothing and keeps every earlier mark; later statements continue. A beat (a `say` and
/// the commands and checks after it) is presented only when complete (the next `say`, `end`, or `endStream()`), so a
/// failing check can refuse the whole beat before the learner sees it.
public struct MGLessonSession {
    public let pacing: MGPacing
    public let clock: MGLessonClock

    /// The presented state; nil before the first scene.
    public internal(set) var state: MGLessonState?
    /// The state after every accepted statement (the script's view). Equal to `state` when no beat is waiting.
    public internal(set) var projected: MGLessonState?
    /// Events with timestamps, oldest first (at most `MGLessonLimits.history`).
    public internal(set) var history: [MGLessonRecord] = []
    /// Commands applied to the presented state, with their origin.
    public internal(set) var log: [MGLessonLogEntry] = []
    /// Host calls that were ignored (for example `lineEnded` for a line that is not open: `line.order`).
    public internal(set) var hostIssues: [MGLessonIssue] = []
    public internal(set) var lastChange: MGLessonChange?
    public internal(set) var title: String?
    /// The last due line (what a caption shows).
    public internal(set) var caption: String?
    public internal(set) var isPaused = false
    public internal(set) var isComplete = false
    /// The beat whose line is being spoken, if any.
    public internal(set) var openLine: Int?

    var scanner = MGStatementScanner()
    var nextStatement = 0
    var nextBeat = 0
    var stream = StreamStatus()
    var pending: [PendingBeat] = []
    var lineEndsAt: Duration?
    var lineRemaining: Duration?
    var settleUntil: Duration = .zero
    var fastForward = false
    var changeSerial = 0
    var outbox: [MGLessonEvent] = []

    struct StreamStatus: Equatable {
        var started = false, hasScene = false, keep = false, ended = false, blocked = false
        var beats = 0, bytes = 0
    }

    struct PendingBeat {
        let index: Int
        let say: String
        let sayStatement: Int
        var commands: [(statement: Int, json: MGJSON)] = []
        var checks: [(statement: Int, check: MGCheck, json: MGJSON)] = []
        var start: MGLessonState
        var end: MGLessonState
        var transitions: [MGTransition] = []
        var complete = false
        var refused = false
        var queuedText: String?
    }

    public init(pacing: MGPacing = .immediate, clock: MGLessonClock = MGSystemClock()) {
        self.pacing = pacing; self.clock = clock
    }

    public var events: [MGLessonEvent] { history.map(\.event) }
    /// Beats received but not presented yet (the last one may still be open).
    public var waitingBeats: Int { pending.count }

    // MARK: input

    /// Feed raw text of a statement stream. Returns the events this chunk caused.
    @discardableResult public mutating func feed(_ chunk: String) -> [MGLessonEvent] {
        outbox = []
        for byte in chunk.utf8 {
            for output in scanner.push(byte) { handle(output) }
        }
        advance()
        return outbox
    }

    /// The stream closed (same as an `{"end":true}` statement). Unfinished text is refused (`stmt.json`).
    @discardableResult public mutating func endStream() -> [MGLessonEvent] {
        outbox = []
        for output in scanner.flush() { handle(output) }
        if !stream.ended { closeOpenBeat(); stream.ended = true; emit(.streamEnded) }
        advance()
        return outbox
    }

    /// Load a whole lesson document. All-or-nothing: the document is validated statement by statement in a fresh
    /// session and refused on the first problem (with its location); on success it replaces this session's lesson.
    public mutating func load(_ lesson: MGLesson) -> Result<[MGLessonEvent], MGLessonIssue> {
        var trial = MGLessonSession(pacing: pacing, clock: clock)
        var all: [MGLessonEvent] = []
        for statement in lesson.statements {
            let events = trial.feed(statement.canonicalString + "\n")
            all += events
            if let issue = events.lazy.compactMap({ if case .refused(let i) = $0 { return i } else { return nil } }).first { return .failure(issue) }
        }
        self = trial
        return .success(all)
    }

    // MARK: commands (host / script / learner)

    /// Apply one command to the presented state. A learner command must be a `params` change of bound controls.
    @discardableResult public mutating func apply(_ command: MGJSON, origin: MGOrigin = .script) -> Result<MGLessonState, MGLessonIssue> {
        apply([command], origin: origin)
    }

    /// Apply commands atomically: all are accepted, or the first refusal is returned (with `command` = its index) and
    /// the state is unchanged.
    @discardableResult public mutating func apply(_ commands: [MGJSON], origin: MGOrigin = .script) -> Result<MGLessonState, MGLessonIssue> {
        outbox = []
        guard var s = state else { return refuseDirect(MGLessonIssue("lesson.empty", origin: origin)) }
        guard (1...MGLessonLimits.commandsPerBeat).contains(commands.count) else { return refuseDirect(MGLessonIssue("beat.ops.count", origin: origin)) }
        let before = s.scene.items
        var transitions: [MGTransition] = []
        for (i, command) in commands.enumerated() {
            do {
                let r = try MGLessonEngine.run(command, on: s, origin: origin, beat: s.beat >= 0 ? s.beat : nil)
                s = r.state; transitions.append(r.transition)
            } catch {
                var issue = Self.issue(error, origin: origin); issue.command = i
                return refuseDirect(issue)
            }
        }
        state = s
        for c in commands { appendLog(MGLessonLogEntry(command: c, origin: origin, beat: nil, statement: nil)) }
        if pending.isEmpty { projected = s }
        publish(origin == .learner ? .direct : Self.combine(transitions), from: before)
        return .success(s)
    }

    /// A learner moved control `id` to `value`: builds `{"op":"params","params":{param: value}}` and applies it with
    /// origin `learner`, the same path as a scripted command. Refused (`control.unknown.<id>`, `control.value`), never
    /// clamped. Emits no event on success (cheap enough for every drag tick).
    @discardableResult public mutating func control(_ id: String, _ value: Double) -> Result<MGLessonState, MGLessonIssue> {
        outbox = []
        guard let c = state?.control(id) else { return refuseDirect(MGLessonIssue("control.unknown.\(id)", origin: .learner)) }
        guard value.isFinite, c.min <= value, value <= c.max else { return refuseDirect(MGLessonIssue("control.value", origin: .learner)) }
        return apply([MGLessonEngine.paramsCommand(c.param, value)], origin: .learner)
    }

    // MARK: host timing calls

    /// The host started speaking line `k`.
    @discardableResult public mutating func lineStarted(_ k: Int) -> [MGLessonEvent] {
        outbox = []
        if openLine == k { emit(.lineStarted(beat: k)) } else { hostIssues.append(MGLessonIssue("line.order", beat: k)) }
        return outbox
    }

    /// The host finished speaking line `k`. Ignored (and recorded in `hostIssues` as `line.order`) unless line `k` is open.
    @discardableResult public mutating func lineEnded(_ k: Int) -> [MGLessonEvent] {
        outbox = []
        guard openLine == k else { hostIssues.append(MGLessonIssue("line.order", beat: k)); return outbox }
        emit(.lineEnded(beat: k)); openLine = nil; lineEndsAt = nil; lineRemaining = nil
        advance()
        return outbox
    }

    /// Present every remaining beat now, in order, with its events; later beats present as soon as they complete.
    @discardableResult public mutating func finishNow() -> [MGLessonEvent] {
        outbox = []
        fastForward = true; isPaused = false
        if let k = openLine { emit(.lineEnded(beat: k)); openLine = nil; lineEndsAt = nil; lineRemaining = nil }
        advance()
        return outbox
    }

    /// Stop the beat clock: no line becomes due and no beat is presented until `resume()`. Statements still validate.
    public mutating func pause() {
        guard !isPaused else { return }
        isPaused = true
        if let end = lineEndsAt { lineRemaining = max(.zero, end - clock.now); lineEndsAt = nil }
    }

    @discardableResult public mutating func resume() -> [MGLessonEvent] {
        outbox = []
        guard isPaused else { return outbox }
        isPaused = false
        if let remaining = lineRemaining { lineEndsAt = clock.now + remaining; lineRemaining = nil }
        advance()
        return outbox
    }

    /// Re-check time-based pacing (estimate line ends, settle time). Call at or after `nextWake`.
    @discardableResult public mutating func tick() -> [MGLessonEvent] {
        outbox = []
        advance()
        return outbox
    }

    /// The next clock time at which `tick()` can change something, or nil.
    public var nextWake: Duration? {
        guard !isPaused else { return nil }
        if let end = lineEndsAt { return end }
        if stream.ended, pending.isEmpty, !isComplete, openLine == nil { return settleUntil }
        return nil
    }

    // MARK: questions

    /// Facts about one item for "ask about this part": id, kind, label/text, first point, the beat that added it and
    /// every engine value. Nil for an unknown id.
    public func describe(_ id: String) -> MGJSON? {
        guard let s = state, let item = s.scene.item(id) else { return nil }
        var o: [String: MGJSON] = ["id": .string(item.id), "kind": .string(item.kind.rawValue)]
        if let l = item.label { o["label"] = .string(l) }
        if let t = item.text { o["text"] = .string(t) }
        if let p = item.pts.first { o["at"] = .array([.number(p.x), .number(p.y)]) }
        if let k = s.introduced[id] { o["introducedInBeat"] = .number(Double(k)) }
        o["values"] = .object(s.scene.values.mapValues { .number($0.value) })
        return .object(o)
    }

    // MARK: statements

    mutating func handle(_ output: MGStatementScanner.Output) {
        let index = nextStatement; nextStatement += 1
        if stream.ended { stream = StreamStatus(); isComplete = false; fastForward = false }
        switch output {
        case .garbage: refuse("stmt.json", index)
        case .tooLong: refuse("stmt.bytes", index)
        case .statement(let raw):
            stream.bytes += raw.count
            guard stream.bytes <= MGLessonLimits.lessonBytes else { return refuse("lesson.bytes", index) }
            guard let object = try? JSONSerialization.jsonObject(with: Data(raw)), let json = MGJSON(any: object) else { return refuse("stmt.json", index) }
            statement(json, index)
        }
        advance()
    }

    mutating func statement(_ json: MGJSON, _ index: Int) {
        guard let o = json.objectValue else { return refuse("stmt.kind", index) }
        if o["op"] != nil { return command(json, index) }
        guard o.count == 1, let (key, value) = o.first else { return refuse("stmt.kind", index) }
        switch key {
        case "lesson": header(value, index)
        case "scene": scene(value, index)
        case "keep":
            guard value == .bool(true) else { return refuse("stmt.kind", index) }
            guard !stream.started, state != nil else { return refuse("stmt.order", index) }
            stream.started = true; stream.keep = true
            if pending.isEmpty { projected = state }
            emit(.accepted(statement: index))
        case "say": say(value, index)
        case "check": check(value, index)
        case "end":
            guard value == .bool(true) else { return refuse("stmt.kind", index) }
            closeOpenBeat(); stream.ended = true
            emit(.accepted(statement: index)); emit(.streamEnded)
        default: refuse("stmt.kind", index)
        }
    }

    mutating func header(_ value: MGJSON, _ index: Int) {
        guard !stream.started else { return refuse("stmt.order", index) }
        do {
            guard let o = value.objectValue else { throw MGError("lesson.object") }
            try MGParser.closed(o, required: ["v"], optional: ["title"], "lesson")
            guard o["v"] == .number(1) else { throw MGError("lesson.version") }
            if MGLessonEngine.hasDecimalLiteral(value) { throw MGError("text.literal") }
            let empty = MGContext(width: 12, height: 8, is3D: false, values: [:])
            let t = try o["title"].map { try MGParser.text($0, MGLimits.title, empty, "lesson.title") }
            if let t { title = t }
            emit(.accepted(statement: index))
        } catch { refuse(Self.issue(error, statement: index)) }
    }

    mutating func scene(_ value: MGJSON, _ index: Int) {
        guard !stream.keep, !stream.hasScene else { return refuse("stmt.order", index) }
        guard value.objectValue != nil else { return refuse("scene.object", index) }
        if value["steps"] != nil { return refuse("lesson.scene.steps", index) }
        if MGLessonEngine.hasDecimalLiteral(value) { return refuse("text.literal", index) }
        switch MGParser.scene(json: value) {
        case .failure(let e): refuse(e.reason, index)
        case .success(let scene):
            let before = state?.scene.items ?? []
            let fresh = MGLessonState(scene: scene)
            state = fresh; projected = fresh
            pending = []; nextBeat = 0; openLine = nil; lineEndsAt = nil; lineRemaining = nil; caption = nil
            stream.started = true; stream.hasScene = true
            emit(.accepted(statement: index))
            publish(.blend, from: before)
            emit(.firstPresented)
        }
    }

    mutating func say(_ value: MGJSON, _ index: Int) {
        guard stream.hasScene || stream.keep, let p = projected else { return refuse("stmt.order", index) }
        stream.started = true
        closeOpenBeat()
        stream.blocked = true   // until this say is accepted, later commands have no beat
        guard case .string(let raw) = value else { return refuse("stmt.say", index) }
        let ctx = MGContext(width: p.scene.width, height: p.scene.height, is3D: p.scene.is3D, values: p.scene.values)
        do { _ = try MGParser.text(value, MGLimits.say, ctx, "stmt.say") } catch { return refuse(Self.issue(error, statement: index)) }
        if MGLessonEngine.hasDecimalLiteral(value) { return refuse("text.literal", index) }
        guard stream.beats < MGLessonLimits.beats else { return refuse("lesson.beats.count", index) }
        stream.blocked = false; stream.beats += 1
        var end = p; end.beat = nextBeat
        pending.append(PendingBeat(index: nextBeat, say: raw, sayStatement: index, start: p, end: end))
        projected = end
        nextBeat += 1
        emit(.accepted(statement: index))
    }

    /// The beat that statements currently attach to (the last pending beat if it is still open).
    var openBeat: Int? { pending.indices.last.flatMap { pending[$0].complete ? nil : $0 } }

    mutating func command(_ json: MGJSON, _ index: Int) {
        guard stream.hasScene || stream.keep, let p = projected else { return refuse("stmt.order", index) }
        stream.started = true
        if stream.blocked { return refuse(MGLessonIssue("beat.refused", statement: index)) }
        if let b = openBeat {
            let k = pending[b].index
            guard !pending[b].refused else { return refuse(MGLessonIssue("beat.refused", beat: k, statement: index)) }
            guard pending[b].commands.count < MGLessonLimits.commandsPerBeat else { return refuse(MGLessonIssue("beat.ops.count", beat: k, statement: index)) }
            do {
                let r = try MGLessonEngine.run(json, on: pending[b].end, origin: .script, beat: k)
                pending[b].end = r.state; pending[b].commands.append((index, json)); pending[b].transitions.append(r.transition)
                projected = r.state
                emit(.accepted(statement: index))
            } catch {
                var issue = Self.issue(error, statement: index); issue.beat = k; issue.command = pending[b].commands.count
                refuse(issue)
            }
        } else if stream.hasScene && stream.beats == 0 {
            // Setup commands between the scene and the first `say` are presented with the scene.
            do {
                let before = p.scene.items
                let r = try MGLessonEngine.run(json, on: p, origin: .script, beat: nil)
                state = r.state; projected = r.state
                appendLog(MGLessonLogEntry(command: json, origin: .script, beat: nil, statement: index))
                emit(.accepted(statement: index))
                publish(r.transition, from: before)
            } catch { refuse(Self.issue(error, statement: index)) }
        } else {
            refuse("stmt.order", index)
        }
    }

    mutating func check(_ value: MGJSON, _ index: Int) {
        guard stream.hasScene || stream.keep else { return refuse("stmt.order", index) }
        stream.started = true
        if stream.blocked { return refuse(MGLessonIssue("beat.refused", statement: index)) }
        guard let b = openBeat else { return refuse("stmt.order", index) }
        let k = pending[b].index
        guard !pending[b].refused else { return refuse(MGLessonIssue("beat.refused", beat: k, statement: index)) }
        guard pending[b].checks.count < MGLessonLimits.checksPerBeat else { return refuse(MGLessonIssue("beat.checks.count", beat: k, statement: index)) }
        do {
            let c = try MGCheck.parse(value)
            if let why = c.failure(in: pending[b].end.scene) {
                // The claim is false: the whole beat is refused and the projected state returns to the beat's start.
                pending[b].refused = true
                projected = pending[b].start
                return refuse(MGLessonIssue(why, beat: k, statement: index))
            }
            pending[b].checks.append((index, c, value))
            emit(.accepted(statement: index))
        } catch {
            var issue = Self.issue(error, statement: index); issue.beat = k
            refuse(issue)
        }
    }

    mutating func closeOpenBeat() {
        guard let b = openBeat else { return }
        pending[b].complete = true
        guard !pending[b].refused else { return }
        do {
            let text = try MGParser.fill(pending[b].say, pending[b].end.scene.values, "stmt.say")
            pending[b].queuedText = text
            emit(.lineQueued(beat: pending[b].index, text: text))
        } catch {
            pending[b].refused = true; projected = pending[b].start
            var issue = Self.issue(error, statement: pending[b].sayStatement); issue.beat = pending[b].index
            refuse(issue)
        }
    }

    // MARK: presentation

    mutating func advance() {
        let now = clock.now
        if case .estimate = pacing, !isPaused, let k = openLine, let end = lineEndsAt, now >= end {
            emit(.lineEnded(beat: k)); openLine = nil; lineEndsAt = nil
        }
        while !isPaused, let first = pending.first, first.complete {
            if first.refused { pending.removeFirst(); continue }
            guard fastForward || pacing == .immediate || openLine == nil else { break }
            pending.removeFirst()
            present(first, at: now)
        }
        if stream.ended, pending.isEmpty, !isComplete, !isPaused,
           fastForward || pacing == .immediate || (openLine == nil && now >= settleUntil) {
            isComplete = true; emit(.lessonComplete)
        }
    }

    mutating func present(_ beat: PendingBeat, at now: Duration) {
        guard var s = state else { return }
        let k = beat.index
        var transitions: [MGTransition] = []
        var applied: [MGLessonLogEntry] = []
        if s == beat.start {
            s = beat.end; transitions = beat.transitions
            applied = beat.commands.map { MGLessonLogEntry(command: $0.json, origin: .script, beat: k, statement: $0.statement) }
        } else {
            // The learner changed something since this beat was validated: re-apply its commands to what is shown.
            // A command that no longer validates is refused alone; a check that no longer holds refuses the beat.
            for (i, c) in beat.commands.enumerated() {
                do {
                    let r = try MGLessonEngine.run(c.json, on: s, origin: .script, beat: k)
                    s = r.state; transitions.append(r.transition)
                    applied.append(MGLessonLogEntry(command: c.json, origin: .script, beat: k, statement: c.statement))
                } catch {
                    var issue = Self.issue(error, statement: c.statement); issue.beat = k; issue.command = i
                    refuse(issue)
                }
            }
            for c in beat.checks {
                if let why = c.check.failure(in: s.scene) { return refuse(MGLessonIssue(why, beat: k, statement: c.statement)) }
            }
            s.beat = k
        }
        let text: String
        do { text = try MGParser.fill(beat.say, s.scene.values, "stmt.say") } catch {
            var issue = Self.issue(error, statement: beat.sayStatement); issue.beat = k
            return refuse(issue)
        }
        let before = state?.scene.items ?? []
        state = s
        for entry in applied { appendLog(entry) }
        if pending.isEmpty { projected = s }
        caption = text
        emit(.lineDue(beat: k, text: text, changed: text != beat.queuedText))
        emit(.beatPresented(beat: k))
        let transition = Self.combine(transitions)
        publish(transition, from: before)
        settleUntil = now + .milliseconds(Int64((Self.settle(transition) * 1000).rounded()))
        if !(fastForward || pacing == .immediate) {
            openLine = k
            if case .estimate(let rate) = pacing { lineEndsAt = now + Self.lineDuration(text, wordsPerSecond: rate) }
        }
    }

    /// `.estimate` line length: words / rate, clamped to 1–12 s.
    public static func lineDuration(_ text: String, wordsPerSecond: Double) -> Duration {
        let words = text.split(whereSeparator: { $0.isWhitespace }).count
        let seconds = min(MGLessonLimits.lineSeconds.upperBound, max(MGLessonLimits.lineSeconds.lowerBound, Double(words) / max(0.1, wordsPerSecond)))
        return .milliseconds(Int64((seconds * 1000).rounded()))
    }

    /// Seconds until a transition settles on screen: keyframes their duration, a blend 1.2 s (`MGTimeline.spring`).
    static func settle(_ t: MGTransition) -> Double {
        switch t { case .direct: return 0; case .blend: return 1.2; case .keyframes(_, let d): return d }
    }

    /// One transition for several commands: their keyframes in order (durations add up), else a blend.
    static func combine(_ list: [MGTransition]) -> MGTransition {
        var frames: [MGScene] = [], duration = 0.0
        for t in list { if case .keyframes(let f, let d) = t { frames += f; duration += d } }
        if !frames.isEmpty { return .keyframes(frames, duration: duration) }
        return list.contains(.blend) || list.isEmpty ? .blend : .direct
    }

    // MARK: helpers

    mutating func publish(_ transition: MGTransition, from before: [MGItem]) {
        guard let s = state else { return }
        changeSerial += 1
        lastChange = MGLessonChange(serial: changeSerial, transition: transition, diff: MGSceneDiff(from: before, to: s.scene.items))
    }

    mutating func emit(_ event: MGLessonEvent) {
        outbox.append(event)
        history.append(MGLessonRecord(event: event, at: clock.now))
        if history.count > MGLessonLimits.history { history.removeFirst(history.count - MGLessonLimits.history) }
    }

    mutating func appendLog(_ entry: MGLessonLogEntry) {
        log.append(entry)
        if log.count > MGLessonLimits.history { log.removeFirst(log.count - MGLessonLimits.history) }
    }

    mutating func refuse(_ reason: String, _ statement: Int) { refuse(MGLessonIssue(reason, statement: statement)) }
    mutating func refuse(_ issue: MGLessonIssue) { emit(.refused(issue)) }
    mutating func refuseDirect(_ issue: MGLessonIssue) -> Result<MGLessonState, MGLessonIssue> { emit(.refused(issue)); return .failure(issue) }

    /// An engine error as an issue. `animate.frame:<inner>` becomes reason `animate.frame` with `detail` = inner.
    static func issue(_ error: Error, statement: Int? = nil, origin: MGOrigin = .script) -> MGLessonIssue {
        let reason = (error as? MGError)?.reason ?? "unknown"
        if let colon = reason.firstIndex(of: ":") {
            return MGLessonIssue(String(reason[..<colon]), statement: statement, origin: origin, detail: String(reason[reason.index(after: colon)...]))
        }
        return MGLessonIssue(reason, statement: statement, origin: origin)
    }
}

/// Incremental statement scanner: one pass over the bytes, tracking nesting, strings and escapes. A statement is
/// complete exactly at the closing bracket of a top-level `{…}` or `[…]` value; braces and escaped quotes inside strings
/// never end it. Text between statements that is not whitespace is skipped up to the next `{` or `[` and reported once.
struct MGStatementScanner: Equatable {
    enum Output: Equatable { case statement([UInt8]), garbage, tooLong }
    var buffer: [UInt8] = []
    var depth = 0, inString = false, escape = false, inGarbage = false, overflow = false

    mutating func push(_ b: UInt8) -> [Output] {
        if depth == 0 {
            switch b {
            case 0x20, 0x0A, 0x0D, 0x09: return []
            case UInt8(ascii: "{"), UInt8(ascii: "["):
                var out: [Output] = []
                if inGarbage { out.append(.garbage); inGarbage = false }
                buffer = [b]; depth = 1; inString = false; escape = false; overflow = false
                return out
            default:
                inGarbage = true; return []
            }
        }
        if !overflow {
            if buffer.count < MGLessonLimits.statementBytes { buffer.append(b) } else { overflow = true; buffer = [] }
        }
        if inString {
            if escape { escape = false } else if b == UInt8(ascii: "\\") { escape = true } else if b == UInt8(ascii: "\"") { inString = false }
            return []
        }
        switch b {
        case UInt8(ascii: "\""): inString = true
        case UInt8(ascii: "{"), UInt8(ascii: "["): depth += 1
        case UInt8(ascii: "}"), UInt8(ascii: "]"):
            depth -= 1
            if depth == 0 {
                let out: Output = overflow ? .tooLong : .statement(buffer)
                buffer = []; overflow = false
                return [out]
            }
        default: break
        }
        return []
    }

    /// End of input: an unfinished statement or trailing garbage is reported once.
    mutating func flush() -> [Output] {
        defer { self = MGStatementScanner() }
        if depth > 0 { return [overflow ? .tooLong : .garbage] }
        return inGarbage ? [.garbage] : []
    }
}
