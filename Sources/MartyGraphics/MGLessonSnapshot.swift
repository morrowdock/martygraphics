// SPDX-License-Identifier: Apache-2.0
import Foundation

// Boundary: a snapshot covers complete statements only. A statement that has started but not finished is not stored;
// the host replays `unfinishedInput` into the restored session before the rest of the stream.
// Persistence for a lesson session: engine data only (scene source, beat cursor, controls, id history, beats that were
// received but not presented yet, pacing position). No learner identity, no audio, no model text beyond accepted
// statements. `restore` re-validates everything strictly and refuses a snapshot that no longer validates (for example
// a scene whose template is not registered: `template.unknown`), never loading part of it.

extension MGLessonSession {
    public func snapshot() -> MGJSON {
        func seconds(_ d: Duration) -> MGJSON { .number(Double(d.components.seconds) + Double(d.components.attoseconds) * 1e-18) }
        var o: [String: MGJSON] = ["v": .number(1), "kind": .string("lessonSnapshot")]
        if let title { o["title"] = .string(title) }
        if let caption { o["caption"] = .string(caption) }
        if let s = state { for (k, v) in Self.wire(s) { o[k] = v } }
        // Queued beats were validated on the script's projection, not on what the learner did since. Keep that
        // baseline, so restoring rebuilds the same projection, queued text and checks.
        if let first = pending.first { o["baseline"] = .object(Self.wire(first.start)) }
        o["next"] = .object(["statement": .number(Double(nextStatement)), "beat": .number(Double(nextBeat))])
        o["stream"] = .object(["started": .bool(stream.started), "scene": .bool(stream.hasScene), "keep": .bool(stream.keep),
                               "ended": .bool(stream.ended), "header": .bool(stream.header), "exhausted": .bool(stream.exhausted),
                               "beats": .number(Double(stream.beats)), "statements": .number(Double(stream.statements)),
                               "bytes": .number(Double(stream.bytes - unfinishedInput.count))])
        o["pending"] = .array(pending.map(Self.wire))
        if let openLine { o["line"] = .number(Double(openLine)) }
        let now = clock.now
        if let end = lineEndsAt { o["lineLeft"] = seconds(max(.zero, end - now)) } else if let r = lineRemaining { o["lineLeft"] = seconds(r) }
        o["settleLeft"] = seconds(settleRemaining ?? max(.zero, settleUntil - now))
        o["paused"] = .bool(isPaused); o["fast"] = .bool(fastForward); o["complete"] = .bool(isComplete)
        return .object(o)
    }

    /// Rebuild a session from `snapshot()`. Every part is re-validated with the engine; the first problem refuses the
    /// whole snapshot (`snapshot.<field>` or the engine's own reason). Event history and the command log start empty.
    /// Size, non-finite numbers and depth are checked first (`checkBounds`). Line timing follows `pacing`, which may
    /// differ from the saved session's: `.estimate` keeps an open line's saved remaining time or estimates it again
    /// from the caption, `.speech` waits for `lineEnded(k)`, `.immediate` holds no line open.
    public static func restore(_ snapshot: MGJSON, pacing: MGPacing, clock: MGLessonClock = MGSystemClock()) -> Result<MGLessonSession, MGLessonIssue> {
        do { return .success(try restoring(snapshot, pacing: pacing, clock: clock)) } catch { return .failure(issue(error)) }
    }

    /// Engine fields of a lesson state (scene source, revision, beat, controls, id history).
    static func wire(_ s: MGLessonState) -> [String: MGJSON] {
        ["scene": s.scene.source, "rev": .number(Double(s.scene.revision)), "beat": .number(Double(s.beat)),
         "controls": .array(s.controls.map(\.wire)), "kinds": .object(s.kinds.mapValues { .string($0.rawValue) }),
         "introduced": .object(s.introduced.mapValues { .number(Double($0)) })]
    }

    /// Rebuilds a state from `wire`, validating every part with the engine.
    static func state(_ o: [String: MGJSON]) throws -> MGLessonState {
        func int(_ v: MGJSON?, _ what: String) throws -> Int {
            let d = try MGParser.num(v, -1...1e9, what); guard d.rounded() == d else { throw MGError(what) }; return Int(d)
        }
        guard let source = o["scene"] else { throw MGError("snapshot.scene") }
        var scene = MGLessonEngine.lessonScene(try MGParser.scene(json: source).get())
        scene.revision = try int(o["rev"], "snapshot.rev")
        var s = MGLessonState(scene: scene)
        s.beat = try int(o["beat"], "snapshot.beat")
        guard let kinds = o["kinds"]?.objectValue, let introduced = o["introduced"]?.objectValue else { throw MGError("snapshot.kinds") }
        s.kinds = try kinds.mapValues { guard case .string(let k) = $0, let kind = MGKind(rawValue: k) else { throw MGError("snapshot.kinds") }; return kind }
        s.introduced = try introduced.mapValues { try int($0, "snapshot.introduced") }
        guard s.kinds.count <= MGLessonLimits.ids, s.introduced.count <= MGLessonLimits.ids else { throw MGError("snapshot.kinds") }
        guard case .array(let controls)? = o["controls"] else { throw MGError("snapshot.controls") }
        for c in controls {
            // Re-bind through the engine so a control that no longer fits its template is refused.
            s = try MGLessonEngine.bind(["op": .string("bind"), "control": c], s).state
        }
        return s
    }

    /// Size, numbers and depth, checked by one bounded walk before any field is read and before anything is encoded.
    /// The walk keeps a lower bound of the canonical JSON size (strings, keys, brackets, commas; every other value
    /// counts at least one byte) and stops once it passes the cap, so its work is bounded. It uses an explicit stack, so
    /// no input depth can exhaust the call stack. Reasons, in this order: the lower bound is over
    /// `MGLessonLimits.snapshotBytes` (`snapshot.bytes`); a number is NaN or infinite (`snapshot.number`); the value nests
    /// deeper than `MGLessonLimits.snapshotDepth` (`snapshot.depth`); the exact canonical size is over the cap
    /// (`snapshot.bytes`). The first test does not depend on dictionary order: the full walk visits every node.
    static func checkBounds(_ snapshot: MGJSON) throws {
        let limit = MGLessonLimits.snapshotBytes
        var total = 0, deep = false, nonFinite = false
        var stack: [(value: MGJSON, depth: Int)] = [(snapshot, 0)]
        while total <= limit, let item = stack.popLast() {
            let depth = item.depth
            if depth > MGLessonLimits.snapshotDepth { deep = true }
            switch item.value {
            case .null, .bool: total += 4
            case .number(let d): total += 1; if !d.isFinite { nonFinite = true }
            case .string(let s): total += s.utf8.count + 2
            case .array(let a):
                total += 1 + max(1, a.count)   // brackets and commas
                if total <= limit { for v in a { stack.append((v, depth + 1)) } }
            case .object(let o):
                total += 1 + max(1, o.count)
                for (k, v) in o {
                    if total > limit { break }
                    total += k.utf8.count + 3; stack.append((v, depth + 1))
                }
            }
        }
        guard total <= limit else { throw MGError("snapshot.bytes") }
        guard !nonFinite else { throw MGError("snapshot.number") }
        guard !deep else { throw MGError("snapshot.depth") }
        // Encodable (finite) and at most `snapshotDepth` deep here, so encoding is safe and bounded.
        guard snapshot.canonicalByteCount <= limit else { throw MGError("snapshot.bytes") }
    }

    static func restoring(_ snapshot: MGJSON, pacing: MGPacing, clock: MGLessonClock) throws -> MGLessonSession {
        // Size and depth first, before any field is read: a bounded walk, then the exact canonical size.
        try checkBounds(snapshot)
        guard let o = snapshot.objectValue, o["kind"] == .string("lessonSnapshot") else { throw MGError("snapshot.kind") }
        guard o["v"] == .number(1) else { throw MGError("snapshot.version") }
        func int(_ v: MGJSON?, _ what: String) throws -> Int {
            let d = try MGParser.num(v, -1...1e9, what); guard d.rounded() == d else { throw MGError(what) }; return Int(d)
        }
        func flag(_ v: MGJSON?, _ what: String) throws -> Bool { guard case .bool(let b)? = v else { throw MGError(what) }; return b }
        func duration(_ v: MGJSON?) throws -> Duration { .milliseconds(Int64((try MGParser.num(v, 0...1e6, "snapshot.time") * 1000).rounded())) }
        func string(_ v: MGJSON?, _ what: String) throws -> String { guard case .string(let s)? = v else { throw MGError(what) }; return s }

        var session = MGLessonSession(pacing: pacing, clock: clock)
        if let t = o["title"] { session.title = try string(t, "snapshot.title") }
        if let c = o["caption"] { session.caption = try string(c, "snapshot.caption") }
        if o["scene"] != nil {
            let s = try state(o)
            session.state = s
            session.projected = try o["baseline"].map { b -> MGLessonState in
                guard let bo = b.objectValue else { throw MGError("snapshot.baseline") }
                return try state(bo)
            } ?? s
        }
        guard let next = o["next"]?.objectValue, let st = o["stream"]?.objectValue else { throw MGError("snapshot.stream") }
        session.nextStatement = try int(next["statement"], "snapshot.next")
        session.nextBeat = try int(next["beat"], "snapshot.next")
        session.stream = StreamStatus(started: try flag(st["started"], "snapshot.stream"), hasScene: try flag(st["scene"], "snapshot.stream"),
                                      keep: try flag(st["keep"], "snapshot.stream"), ended: try flag(st["ended"], "snapshot.stream"),
                                      header: try flag(st["header"], "snapshot.stream"),
                                      beats: try int(st["beats"], "snapshot.stream"), statements: try int(st["statements"], "snapshot.stream"),
                                      bytes: try int(st["bytes"], "snapshot.stream"), exhausted: try flag(st["exhausted"], "snapshot.stream"))
        guard case .array(let pending)? = o["pending"] else { throw MGError("snapshot.pending") }
        for entry in pending {
            guard let p = entry.objectValue, let start = session.projected else { throw MGError("snapshot.pending") }
            let k = try int(p["beat"], "snapshot.pending")
            var beat = PendingBeat(index: k, say: try string(p["say"], "snapshot.pending"), sayStatement: try int(p["sayAt"], "snapshot.pending"),
                                   start: start, end: start)
            beat.complete = try flag(p["complete"], "snapshot.pending")
            beat.refused = try flag(p["refused"], "snapshot.pending")
            if !beat.refused {
                beat.end.beat = k
                guard case .array(let commands)? = p["commands"], case .array(let checks)? = p["checks"],
                      commands.count <= MGLessonLimits.commandsPerBeat, checks.count <= MGLessonLimits.checksPerBeat else { throw MGError("snapshot.pending") }
                for c in commands {
                    let r = try MGLessonEngine.run(c["s"] ?? .null, on: beat.end, origin: .script, beat: k)
                    beat.end = r.state; beat.commands.append((try int(c["i"], "snapshot.pending"), c["s"]!)); beat.transitions.append(r.transition)
                }
                for c in checks {
                    let check = try MGCheck.parse(c["s"] ?? .null)
                    if let why = check.failure(in: beat.end.scene) { throw MGError(why) }
                    beat.checks.append((try int(c["i"], "snapshot.pending"), check, c["s"]!))
                }
                if beat.complete {
                    let text = try fillLine(beat.say, beat.end.scene.values)
                    guard p["queued"] == .string(text) else { throw MGError("snapshot.queued") }
                    beat.queuedText = text
                }
                session.projected = beat.end
            }
            session.pending.append(measured(beat))
            // The live queue budget holds for a restored session too (and bounds the work of a restore).
            guard session.queueUsage <= MGLessonLimits.queueBytes else { throw MGError("snapshot.pending") }
        }
        if let line = o["line"] { session.openLine = try int(line, "snapshot.line") }
        session.isPaused = try flag(o["paused"], "snapshot.paused")
        session.fastForward = try flag(o["fast"], "snapshot.fast")
        session.isComplete = try flag(o["complete"], "snapshot.complete")
        let now = clock.now
        // Line timing follows the restoring pacing, not the saved one. `.estimate`: an open line keeps its saved
        // remaining time, or gets a fresh estimate from the caption when the snapshot came from another pacing.
        // `.speech`: an open line waits for `lineEnded(k)`; no time is kept. `.immediate`: no line is held open.
        let lineLeft = try o["lineLeft"].map { try duration($0) }
        switch pacing {
        case .estimate(let rate):
            if session.openLine != nil {
                let left = lineLeft ?? lineDuration(session.caption ?? "", wordsPerSecond: rate)
                if session.isPaused { session.lineRemaining = left } else { session.lineEndsAt = now + left }
            }
        case .speech: break
        case .immediate: session.openLine = nil
        }
        if session.isPaused { session.settleRemaining = try duration(o["settleLeft"]) } else { session.settleUntil = now + (try duration(o["settleLeft"])) }
        return session
    }
}
