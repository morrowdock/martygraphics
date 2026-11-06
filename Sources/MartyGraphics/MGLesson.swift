// SPDX-License-Identifier: Apache-2.0
import Foundation

// Lesson layer (beat-by-beat teaching). Three layers:
//   L1 lesson intent: a lesson document or a statement stream (untrusted data, closed keys, bounded sizes, no code)
//   L2 validated commands: existing MGPatch ops plus `animate`, `bind`, `unbind` and `check`; each command is applied
//      to a copy of the state and the WHOLE scene is re-validated; a refusal leaves the state unchanged
//   L3 persistent lesson state: the validated MGScene (single source of truth) + beat cursor + bound controls
// Renderers read only L3. Every number on screen comes from engine values (`MGScene.values`, `{name}` placeholders).

/// Lesson contract limits (owner decision D5). Scene and patch limits (`MGLimits`) are unchanged.
public enum MGLessonLimits {
    public static let beats = 24, commandsPerBeat = 12, checksPerBeat = 8, controls = 4
    public static let statementBytes = 4 * 1024, lessonBytes = 32 * 1024
    /// Statements per stream, accepted or refused (bounds the work and the events of one stream).
    public static let statements = 256
    /// Size of the session's event history; older records are dropped first.
    public static let history = 4096
    public static let animateDuration: ClosedRange<Double> = 0.2...6
    public static let defaultAnimateDuration = 1.5
    /// Estimated line length for `.estimate` pacing, in seconds.
    public static let lineSeconds: ClosedRange<Double> = 1...12
}

/// Who sent a command. A learner command is gated (bound control, value in range) and then takes the SAME path as a
/// scripted one; only the transition differs (`direct` instead of `blend`).
public enum MGOrigin: String, Equatable, Sendable { case script, learner }

/// A refused statement, command or learner value. `reason` is a stable developer token, never shown to the learner.
/// Inner engine reasons pass through unchanged (`patch.set.ref`, `id.duplicate.hiA`, `template.angle`, …); the location
/// is kept in separate fields so one reason means one thing everywhere.
public struct MGLessonIssue: Error, Equatable, Sendable, CustomStringConvertible {
    public let reason: String
    /// Zero-based beat index, when the issue belongs to a beat.
    public var beat: Int?
    /// Zero-based statement index in the session's stream, when it came from a statement.
    public var statement: Int?
    /// Zero-based command index inside a batch or a beat, when it came from one.
    public var command: Int?
    public var origin: MGOrigin = .script
    /// The inner reason for wrapper reasons (`animate.frame`, `beat.refused`), else nil.
    public var detail: String?
    /// `reason` and `detail` are normalised to one token: ASCII letters, digits, `_`, `.` and `,` only (anything else
    /// becomes `_`), at most 96 characters. Author text inside a reason can never add spaces, newlines or separators.
    public init(_ reason: String, beat: Int? = nil, statement: Int? = nil, command: Int? = nil, origin: MGOrigin = .script, detail: String? = nil) {
        self.reason = Self.token(reason); self.beat = beat; self.statement = statement; self.command = command; self.origin = origin
        self.detail = detail.map(Self.token)
    }

    static func token(_ s: String) -> String {
        let t = String(s.unicodeScalars.prefix(96).map { u -> Character in
            u.isASCII && (CharacterSet.alphanumerics.contains(u) || u == "_" || u == "." || u == ",") ? Character(u) : "_"
        })
        return t.isEmpty ? "_" : t
    }

    /// One author-supplied reason segment (an id or key): like `token`, but `.` also becomes `_`, so it cannot fake
    /// extra reason segments; at most 32 characters.
    static func segment(_ s: String) -> String {
        let t = String(s.unicodeScalars.prefix(32).map { u -> Character in
            u.isASCII && (CharacterSet.alphanumerics.contains(u) || u == "_") ? Character(u) : "_"
        })
        return t.isEmpty ? "_" : t
    }
    public var description: String {
        var parts = [reason]
        if let detail { parts.append("(\(detail))") }
        if let statement { parts.append("statement \(statement)") }
        if let beat { parts.append("beat \(beat)") }
        if let command { parts.append("command \(command)") }
        return parts.joined(separator: " ")
    }
}

/// A learner control bound to one numeric template parameter. The control has no value of its own: its value is
/// always read from `scene.source.params[param]`, so a slider and a script can never disagree.
public struct MGLessonControl: Equatable, Sendable, Identifiable {
    public let id: String
    /// `slider` only in lesson v1.
    public let kind: String
    public let param: String
    public let min: Double, max: Double
    /// UI quantisation hint. The engine accepts any value in `min…max`; it never clamps or rounds.
    public let step: Double
    public let label: String
    /// Unit of the parameter as declared by the template (`°` for `rotate2d.angle`).
    public let unit: String

    var wire: MGJSON {
        .object(["id": .string(id), "k": .string(kind), "param": .string(param), "min": .number(min), "max": .number(max),
                 "step": .number(step), "label": .string(label)])
    }
}

/// L3: the persistent lesson state. Equatable, Foundation-only and fully determined by validated commands.
public struct MGLessonState: Equatable, Sendable {
    /// The validated scene. Its canonical `source` is the single source of truth for every item, value and control.
    public internal(set) var scene: MGScene
    /// Last presented (or, in the projected state, last accepted) beat index; −1 before the first beat.
    public internal(set) var beat: Int = -1
    public internal(set) var controls: [MGLessonControl] = []
    /// Every id that was ever on the board in this lesson, with its kind (stable-id rule: a removed id may come back
    /// only with the same kind, `lesson.id.kind.<id>`).
    public internal(set) var kinds: [String: MGKind] = [:]
    /// The beat in which an id was first added by a command (template and scene ids are absent).
    public internal(set) var introduced: [String: Int] = [:]

    init(scene: MGScene) {
        self.scene = scene
        for item in scene.items { kinds[item.id] = item.kind }
    }

    /// Engine value by name (`MGScene.values`).
    public func value(_ name: String) -> Double? { scene.values[name]?.value }
    public func control(_ id: String) -> MGLessonControl? { controls.first { $0.id == id } }
    /// The current value of a bound control, read from the scene source (or the template default).
    public func value(of control: MGLessonControl) -> Double? {
        if case .number(let d)? = scene.source["params"]?[control.param] { return d }
        return MGTween.numericSpec(scene, control.param)?.defaultValue.flatMap { $0.isFinite ? $0 : nil }
    }

    /// Canonical bytes of scene source + revision + beat + controls (determinism checks and fingerprints).
    public var canonical: Data {
        let object: MGJSON = .object(["scene": scene.source, "rev": .number(Double(scene.revision)), "beat": .number(Double(beat)),
                                      "controls": .array(controls.map(\.wire))])
        return object.canonicalData
    }
}

/// A claim the engine proves before the learner sees it: `{"value":"ax","eq":-1}` (or `lt` / `gt`, optional `tol`).
public struct MGCheck: Equatable, Sendable {
    public enum Comparison: String, Equatable, Sendable { case eq, lt, gt }
    public let value: String
    public let comparison: Comparison
    public let target: Double
    /// With `eq`: numeric tolerance. Without it, `eq` compares what the learner sees (`MGPhysics.format` text).
    public let tolerance: Double?

    static func parse(_ json: MGJSON) throws -> MGCheck {
        guard let o = json.objectValue else { throw MGError("check.object") }
        try MGParser.closed(o, required: ["value"], optional: ["eq", "lt", "gt", "tol"], "check")
        guard case .string(let name)? = o["value"], (1...16).contains(name.count),
              name.unicodeScalars.allSatisfy({ $0.isASCII && CharacterSet.alphanumerics.contains($0) }) else { throw MGError("check.value") }
        let present = [Comparison.eq, .lt, .gt].filter { o[$0.rawValue] != nil }
        guard present.count == 1, let comparison = present.first else { throw MGError("check.comparison") }
        let target = try MGParser.num(o[comparison.rawValue], -1e6...1e6, "check.\(comparison.rawValue)")
        var tolerance: Double?
        if let t = o["tol"] {
            guard comparison == .eq else { throw MGError("check.tol") }
            tolerance = try MGParser.num(t, 0...1e6, "check.tol")
        }
        return MGCheck(value: name, comparison: comparison, target: target, tolerance: tolerance)
    }

    /// nil when the claim holds; otherwise the stable reason (`check.unknown.<name>` or `check.<name>`).
    public func failure(in scene: MGScene) -> String? {
        guard let v = scene.values[value]?.value else { return "check.unknown.\(value)" }
        let holds: Bool
        switch comparison {
        case .eq: holds = tolerance.map { abs(v - target) <= $0 } ?? (MGPhysics.format(v, unit: "") == MGPhysics.format(target, unit: ""))
        case .lt: holds = v < target
        case .gt: holds = v > target
        }
        return holds ? nil : "check.\(value)"
    }
}

/// A parsed lesson document (L1): `{"v":1,"kind":"lesson","title"?,"scene":{…},"beats":[{"say","ops"?,"check"?}]}`.
/// Parsing checks the document's shape and limits; `MGLessonSession.load` then validates every beat against the engine
/// and refuses the whole document on the first problem (a document is all-or-nothing, like a scene).
public struct MGLesson: Equatable, Sendable {
    public struct Beat: Equatable, Sendable {
        public let say: String
        public let ops: [MGJSON]
        public let checks: [MGJSON]
    }
    public let title: String?
    public let scene: MGJSON
    public let beats: [Beat]

    static let keys: Set<String> = ["v", "kind", "title", "scene", "beats"]
    static let beatKeys: Set<String> = ["say", "ops", "check"]

    public static func parse(data: Data) -> Result<MGLesson, MGLessonIssue> {
        guard data.count <= MGLessonLimits.lessonBytes * 2 else { return .failure(.init("lesson.bytes")) }
        guard let object = try? JSONSerialization.jsonObject(with: data), let json = MGJSON(any: object) else { return .failure(.init("lesson.json")) }
        return parse(json: json)
    }

    public static func parse(json: MGJSON) -> Result<MGLesson, MGLessonIssue> {
        do {
            guard let o = json.objectValue else { throw MGError("lesson.object") }
            guard json.canonicalData.count <= MGLessonLimits.lessonBytes else { throw MGError("lesson.bytes") }
            let extra = Set(o.keys).subtracting(keys)
            guard extra.isEmpty else { throw MGError("lesson.unknown.\(extra.sorted().joined(separator: ","))") }
            guard o["v"] == .number(1) else { throw MGError("lesson.version") }
            guard o["kind"] == .string("lesson") else { throw MGError("lesson.kind") }
            var title: String?
            if let t = o["title"] {
                guard case .string(let s) = t else { throw MGError("lesson.title") }
                title = s
            }
            guard let scene = o["scene"], scene.objectValue != nil else { throw MGError("lesson.scene") }
            if scene["steps"] != nil { throw MGError("lesson.scene.steps") }
            guard case .array(let list)? = o["beats"], !list.isEmpty else { throw MGError("lesson.beats") }
            guard list.count <= MGLessonLimits.beats else { throw MGError("lesson.beats.count") }
            let beats = try list.map { entry -> Beat in
                guard let b = entry.objectValue else { throw MGError("beat.object") }
                try MGParser.closed(b, required: ["say"], optional: beatKeys, "beat")
                guard case .string(let say)? = b["say"] else { throw MGError("stmt.say") }
                var ops: [MGJSON] = [], checks: [MGJSON] = []
                if let raw = b["ops"] {
                    guard case .array(let l) = raw else { throw MGError("beat.ops") }
                    guard l.count <= MGLessonLimits.commandsPerBeat else { throw MGError("beat.ops.count") }
                    for op in l { try MGLessonEngine.refuseForbidden(op) }
                    ops = l
                }
                if let raw = b["check"] {
                    guard case .array(let l) = raw else { throw MGError("beat.check") }
                    guard l.count <= MGLessonLimits.checksPerBeat else { throw MGError("beat.checks.count") }
                    checks = l
                }
                return Beat(say: say, ops: ops, checks: checks)
            }
            let lesson = MGLesson(title: title, scene: scene, beats: beats)
            // A document's size is the size of the statement stream it becomes (the stream budget is what `load` feeds).
            guard lesson.statementStream.utf8.count <= MGLessonLimits.lessonBytes else { throw MGError("lesson.bytes") }
            return .success(lesson)
        } catch let e as MGError { return .failure(.init(e.reason)) } catch { return .failure(.init("lesson")) }
    }

    /// The same lesson as a statement stream (lane B surface): header, scene, then per beat `say`, its commands and its
    /// checks, then `end`. Feeding these statements gives exactly the state that `load` gives.
    public var statements: [MGJSON] {
        var out: [MGJSON] = []
        var header: [String: MGJSON] = ["v": .number(1)]
        if let title { header["title"] = .string(title) }
        out.append(.object(["lesson": .object(header)]))
        out.append(.object(["scene": scene]))
        for b in beats {
            out.append(.object(["say": .string(b.say)]))
            out += b.ops
            out += b.checks.map { .object(["check": $0]) }
        }
        out.append(.object(["end": .bool(true)]))
        return out
    }

    /// Newline-delimited canonical statements (one JSON object per line).
    public var statementStream: String { statements.map(\.canonicalString).joined(separator: "\n") + "\n" }
}

/// The result of one accepted command: the new state and how a board should move to it.
struct MGCommandResult {
    var state: MGLessonState
    var transition: MGTransition
}

/// L2: command validation and application. Pure functions of (state, command); nothing here keeps state.
enum MGLessonEngine {
    static let patchOps: Set<String> = ["add", "set", "remove", "params", "camera", "title"]
    static let lessonOps: Set<String> = ["animate", "bind", "unbind"]
    /// Scene-walkthrough ops have no meaning in a lesson: a lesson has one beat system.
    static let forbidden: Set<String> = ["steps", "step", "dim"]

    static func refuseForbidden(_ op: MGJSON) throws {
        if case .string(let name)? = op["op"], forbidden.contains(name) { throw MGError("lesson.op.\(name)") }
    }

    /// D3: a lesson's own text may not contain a decimal number literal such as `1.23`. Decimals must come from
    /// engine values (`{name}`). Integers ("90°", "3 teeth") stay allowed. Engine-filled text is not affected.
    static func hasDecimalLiteral(_ json: MGJSON) -> Bool {
        switch json {
        case .string(let s):
            // Refused forms: `1.5`, `.5` / `-.5` (a dot before a digit, not after a letter or digit), and exponent
            // notation `2e3` / `2E-3` (a digit run not glued to a letter, then e, an optional sign and a digit).
            let u = Array(s.unicodeScalars)
            func digit(_ i: Int) -> Bool { u.indices.contains(i) && CharacterSet.decimalDigits.contains(u[i]) }
            func word(_ i: Int) -> Bool { u.indices.contains(i) && (CharacterSet.letters.contains(u[i]) || CharacterSet.decimalDigits.contains(u[i])) }
            for i in u.indices {
                if u[i] == "." && digit(i + 1) && (digit(i - 1) || !word(i - 1)) { return true }
                if (u[i] == "e" || u[i] == "E") && digit(i - 1) && (digit(i + 1) || ((u.indices.contains(i + 1) && (u[i + 1] == "-" || u[i + 1] == "+")) && digit(i + 2))) {
                    var j = i - 1
                    while digit(j) { j -= 1 }
                    if !(u.indices.contains(j) && CharacterSet.letters.contains(u[j])) { return true }
                }
            }
            return false
        case .array(let a): return a.contains(where: hasDecimalLiteral)
        case .object(let o): return o.values.contains(where: hasDecimalLiteral)
        default: return false
        }
    }

    /// Validates and applies one command. Throws an `MGError` with the stable reason; `state` is never modified.
    static func run(_ command: MGJSON, on state: MGLessonState, origin: MGOrigin, beat: Int?) throws -> MGCommandResult {
        guard let o = command.objectValue, case .string(let name)? = o["op"] else { throw MGError("patch.op") }
        if forbidden.contains(name) { throw MGError("lesson.op.\(name)") }
        if origin == .learner { try learnerGate(o, name, state) }
        if hasDecimalLiteral(command) { throw MGError("text.literal") }
        switch name {
        case "animate": return try animate(o, state)
        case "bind": return try bind(o, state)
        case "unbind":
            try MGParser.closed(o, required: ["op", "id"], optional: [], "unbind")
            guard case .string(let id)? = o["id"] else { throw MGError("unbind.id") }
            guard state.control(id) != nil else { throw MGError("control.unknown.\(MGLessonIssue.segment(id))") }
            var next = state; next.controls.removeAll { $0.id == id }
            return MGCommandResult(state: next, transition: .blend)
        default:
            if name == "set", case .string(let key)? = o["key"], key == "id" || key == "k" { throw MGError("patch.set.key") }
            if name == "add", let item = o["item"]?.objectValue, case .string(let id)? = item["id"],
               case .string(let k)? = item["k"], let kind = MGKind(rawValue: k),
               state.scene.item(id) == nil, let previous = state.kinds[id], previous != kind {
                throw MGError("lesson.id.kind.\(MGLessonIssue.segment(id))")
            }
            let patch = try MGPatch.parse(json: .object(["v": .number(1), "ops": .array([command])])).get()
            let scene = lessonScene(try state.scene.applying(patch).get())
            var next = state
            next.scene = scene
            for item in scene.items where next.kinds[item.id] == nil {
                next.kinds[item.id] = item.kind
                if let beat { next.introduced[item.id] = beat }
            }
            return MGCommandResult(state: next, transition: origin == .learner ? .direct : .blend)
        }
    }

    /// Learner commands: only `params` on bound parameters, each value inside its control's range. Refused, never clamped.
    static func learnerGate(_ o: [String: MGJSON], _ name: String, _ state: MGLessonState) throws {
        guard name == "params", let params = o["params"]?.objectValue, !params.isEmpty else { throw MGError("control.op") }
        for (param, value) in params.sorted(by: { $0.key < $1.key }) {
            let bound = state.controls.filter { $0.param == param }
            guard !bound.isEmpty else { throw MGError("control.unknown.\(MGLessonIssue.segment(param))") }
            guard case .number(let v) = value, v.isFinite, bound.contains(where: { $0.min <= v && v <= $0.max }) else { throw MGError("control.value") }
        }
    }

    static func animate(_ o: [String: MGJSON], _ state: MGLessonState) throws -> MGCommandResult {
        try MGParser.closed(o, required: ["op", "param", "to"], optional: ["dur"], "animate")
        guard case .string(let param)? = o["param"] else { throw MGError("animate.param") }
        guard case .number(let to)? = o["to"] else { throw MGError("animate.to") }
        var duration = MGLessonLimits.defaultAnimateDuration
        if let d = o["dur"] { duration = try MGParser.num(d, MGLessonLimits.animateDuration, "animate.dur") }
        switch MGTween.keyframes(state.scene, param: param, to: to) {
        case .failure(let e): throw e
        case .success(let frames):
            let lessonFrames = frames.map(lessonScene)
            guard let last = lessonFrames.last else { throw MGError("animate.frame") }
            var next = state; next.scene = last
            return MGCommandResult(state: next, transition: .keyframes([MGKeyframeSegment(frames: [state.scene] + lessonFrames, duration: duration)]))
        }
    }

    static func bind(_ o: [String: MGJSON], _ state: MGLessonState) throws -> MGCommandResult {
        try MGParser.closed(o, required: ["op", "control"], optional: [], "bind")
        guard let c = o["control"]?.objectValue else { throw MGError("control.object") }
        try MGParser.closed(c, required: ["id", "k", "param", "min", "max", "step", "label"], optional: [], "control")
        let id = try MGParser.identifier(c["id"]!, "control.id")
        guard c["k"] == .string("slider") else { throw MGError("control.kind") }
        guard case .string(let param)? = c["param"], let spec = MGTween.numericSpec(state.scene, param) else { throw MGError("control.param") }
        let lo = try MGParser.num(c["min"], -1e6...1e6, "control.range"), hi = try MGParser.num(c["max"], -1e6...1e6, "control.range")
        guard lo < hi, spec.range.contains(lo), spec.range.contains(hi) else { throw MGError("control.range") }
        let step = try MGParser.num(c["step"], 1e-6...(hi - lo), "control.step")
        if spec.integer { guard lo.rounded() == lo, hi.rounded() == hi, step.rounded() == step else { throw MGError("control.step") } }
        let ctx = MGContext(width: state.scene.width, height: state.scene.height, is3D: state.scene.is3D, values: state.scene.values)
        // A control label is fixed text: an engine number filled in once would go stale when the value changes.
        if case .string(let raw)? = c["label"], raw.contains("{") || raw.contains("}") { throw MGError("control.label.placeholder") }
        let label = try MGParser.text(c["label"], MGLimits.label, ctx, "control.label")
        guard state.control(id) == nil else { throw MGError("control.duplicate.\(id)") }
        guard state.controls.count < MGLessonLimits.controls else { throw MGError("control.count") }
        var next = state
        next.controls.append(MGLessonControl(id: id, kind: "slider", param: param, min: lo, max: hi, step: step, label: label, unit: spec.unit))
        return MGCommandResult(state: next, transition: .direct)
    }

    /// Lesson policy for template walkthroughs: a lesson has one beat system, so a resolved scene's own `steps`
    /// (a template's built-in walkthrough) are dropped. Every resolved item is on the board from the start, and no step
    /// edit applies, so the lesson state and the drawn board always hold the same items. Scenes outside lessons keep v1
    /// behaviour; the scene `source` is unchanged.
    static func lessonScene(_ scene: MGScene) -> MGScene {
        guard !scene.steps.isEmpty || scene.startStep != 0 else { return scene }
        var out = MGScene(source: scene.source, template: scene.template, title: scene.title, is3D: scene.is3D, width: scene.width,
                          height: scene.height, items: scene.items, steps: [], camera: scene.camera, values: scene.values,
                          motion: scene.motion, attachments: scene.attachments)
        out.revision = scene.revision
        return out
    }

    /// `{"op":"params","params":{param: value}}`: the one command a learner control sends.
    static func paramsCommand(_ param: String, _ value: Double) -> MGJSON {
        .object(["op": .string("params"), "params": .object([param: .number(value)])])
    }
}
