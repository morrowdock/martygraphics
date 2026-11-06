// SPDX-License-Identifier: Apache-2.0
import Foundation

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
        if let s = state {
            o["scene"] = s.scene.source
            o["rev"] = .number(Double(s.scene.revision))
            o["beat"] = .number(Double(s.beat))
            o["controls"] = .array(s.controls.map(\.wire))
            o["kinds"] = .object(s.kinds.mapValues { .string($0.rawValue) })
            o["introduced"] = .object(s.introduced.mapValues { .number(Double($0)) })
        }
        o["next"] = .object(["statement": .number(Double(nextStatement)), "beat": .number(Double(nextBeat))])
        o["stream"] = .object(["started": .bool(stream.started), "scene": .bool(stream.hasScene), "keep": .bool(stream.keep),
                               "ended": .bool(stream.ended), "blocked": .bool(stream.blocked),
                               "beats": .number(Double(stream.beats)), "bytes": .number(Double(stream.bytes))])
        o["pending"] = .array(pending.map { b in
            var p: [String: MGJSON] = ["beat": .number(Double(b.index)), "say": .string(b.say), "sayAt": .number(Double(b.sayStatement)),
                                       "complete": .bool(b.complete), "refused": .bool(b.refused)]
            if !b.refused {
                p["commands"] = .array(b.commands.map { .object(["i": .number(Double($0.statement)), "s": $0.json]) })
                p["checks"] = .array(b.checks.map { .object(["i": .number(Double($0.statement)), "s": $0.json]) })
            }
            return .object(p)
        })
        if let openLine { o["line"] = .number(Double(openLine)) }
        let now = clock.now
        if let end = lineEndsAt { o["lineLeft"] = seconds(max(.zero, end - now)) } else if let r = lineRemaining { o["lineLeft"] = seconds(r) }
        o["settleLeft"] = seconds(max(.zero, settleUntil - now))
        o["paused"] = .bool(isPaused); o["fast"] = .bool(fastForward); o["complete"] = .bool(isComplete)
        return .object(o)
    }

    /// Rebuild a session from `snapshot()`. Every part is re-validated with the engine; the first problem refuses the
    /// whole snapshot (`snapshot.<field>` or the engine's own reason). Event history and the command log start empty.
    public static func restore(_ snapshot: MGJSON, pacing: MGPacing, clock: MGLessonClock = MGSystemClock()) -> Result<MGLessonSession, MGLessonIssue> {
        do { return .success(try restoring(snapshot, pacing: pacing, clock: clock)) } catch { return .failure(issue(error)) }
    }

    static func restoring(_ snapshot: MGJSON, pacing: MGPacing, clock: MGLessonClock) throws -> MGLessonSession {
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
        if let source = o["scene"] {
            var scene = try MGParser.scene(json: source).get()
            scene.revision = try int(o["rev"], "snapshot.rev")
            var s = MGLessonState(scene: scene)
            s.beat = try int(o["beat"], "snapshot.beat")
            guard let kinds = o["kinds"]?.objectValue, let introduced = o["introduced"]?.objectValue else { throw MGError("snapshot.kinds") }
            s.kinds = try kinds.mapValues { guard case .string(let k) = $0, let kind = MGKind(rawValue: k) else { throw MGError("snapshot.kinds") }; return kind }
            s.introduced = try introduced.mapValues { try int($0, "snapshot.introduced") }
            guard case .array(let controls)? = o["controls"] else { throw MGError("snapshot.controls") }
            for c in controls {
                // Re-bind through the engine so a control that no longer fits its template is refused.
                s = try MGLessonEngine.bind(["op": .string("bind"), "control": c], s).state
            }
            session.state = s; session.projected = s
        }
        guard let next = o["next"]?.objectValue, let st = o["stream"]?.objectValue else { throw MGError("snapshot.stream") }
        session.nextStatement = try int(next["statement"], "snapshot.next")
        session.nextBeat = try int(next["beat"], "snapshot.next")
        session.stream = StreamStatus(started: try flag(st["started"], "snapshot.stream"), hasScene: try flag(st["scene"], "snapshot.stream"),
                                      keep: try flag(st["keep"], "snapshot.stream"), ended: try flag(st["ended"], "snapshot.stream"),
                                      blocked: try flag(st["blocked"], "snapshot.stream"),
                                      beats: try int(st["beats"], "snapshot.stream"), bytes: try int(st["bytes"], "snapshot.stream"))
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
                guard case .array(let commands)? = p["commands"], case .array(let checks)? = p["checks"] else { throw MGError("snapshot.pending") }
                for c in commands {
                    let r = try MGLessonEngine.run(c["s"] ?? .null, on: beat.end, origin: .script, beat: k)
                    beat.end = r.state; beat.commands.append((try int(c["i"], "snapshot.pending"), c["s"]!)); beat.transitions.append(r.transition)
                }
                for c in checks {
                    let check = try MGCheck.parse(c["s"] ?? .null)
                    if let why = check.failure(in: beat.end.scene) { throw MGError(why) }
                    beat.checks.append((try int(c["i"], "snapshot.pending"), check, c["s"]!))
                }
                if beat.complete { beat.queuedText = try MGParser.fill(beat.say, beat.end.scene.values, "stmt.say") }
                session.projected = beat.end
            }
            session.pending.append(beat)
        }
        if let line = o["line"] { session.openLine = try int(line, "snapshot.line") }
        session.isPaused = try flag(o["paused"], "snapshot.paused")
        session.fastForward = try flag(o["fast"], "snapshot.fast")
        session.isComplete = try flag(o["complete"], "snapshot.complete")
        let now = clock.now
        if let left = o["lineLeft"] {
            if session.isPaused { session.lineRemaining = try duration(left) } else if case .estimate = pacing { session.lineEndsAt = now + (try duration(left)) }
        }
        session.settleUntil = now + (try duration(o["settleLeft"]))
        return session
    }
}
