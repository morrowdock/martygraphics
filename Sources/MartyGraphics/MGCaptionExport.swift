// SPDX-License-Identifier: Apache-2.0
import Foundation

// Captions and a transcript for the story video (`story.mp4`, `MGStoryPlan`): WebVTT, SubRip and plain text, timed
// from the frames the movie writer writes for the same document, size and rate (docs/EXPLAINER.md, "Captions and
// transcript export"). Read-only: it changes no check, report or render output. Foundation only, deterministic.

/// The captions of one story video: one or more cues per beat (an explainer beat or an assembly step), each inside
/// the frames where the video shows that beat's caption, with the beat's narration words exactly as written.
///
/// Timing. A beat's caption shows from the first frame of its hold (after the camera move into it,
/// `MGStoryPlan.holdStartFrame`) to the beat's last frame, as in `story.mp4`. Frame `i` is stamped at `i / fps` seconds
/// (`MGMovieWriter`), so every cue boundary is a frame boundary, written in whole milliseconds rounded down. At the
/// story rates (`MGStoryTiming.rates`, under 1000 fps) a cue's millisecond interval `[start, end)` contains exactly the
/// presentation times `i / fps` of its own frames. That is the property the tests check; how a player maps cue times
/// to the frames it shows is the player's.
///
/// Line rules. A cue has at most `maxLines` lines of at most `maxLineCharacters` characters (grapheme clusters). Lines
/// break at spaces only; a word longer than a line is cut into line-length pieces. A beat gets as many cues as its
/// words need at full line length, more when its hold is longer than `maxCueSeconds` per cue (at most one cue per
/// full-length line), and its words are spread over those cues in balanced lines. The cues share the hold by their
/// length, each lasting at least `minCueSeconds`.
///
/// Words. The cue lines hold the narration's words in order, unchanged: only the whitespace between two words becomes
/// one space or a line break. A no-break space (U+00A0, U+2007, U+202F) never breaks a line. The transcript keeps
/// the narration exactly as written.
///
/// Text rules, applied when each format is written: a timed cue payload (WebVTT and SubRip) never holds a line
/// terminator (`payloadLine`); WebVTT escapes `&`, `<` and `>` one Unicode scalar at a time (`escapeVTT`); SubRip has
/// no escapes, so writing it refuses a cue with `<`, `>` or a control character (`captions.text`). WebVTT and the
/// transcript are written for any narration.
public struct MGCaptionExport: Equatable, Sendable {
    /// `vtt` (WebVTT), `srt` (SubRip) or `txt` (the plain-text transcript).
    public enum Format: String, CaseIterable, Sendable { case vtt, srt, txt }

    /// At most this many characters per line and lines per cue.
    public static let maxLineCharacters = 42, maxLines = 2
    /// Every cue lasts at least `minCueSeconds` (when its beat's hold has room); a beat gets more cues when its hold
    /// is longer than `maxCueSeconds` per cue and its words fill more lines.
    public static let minCueSeconds = 1.0, maxCueSeconds = 7.0

    /// One beat: its narration (the caption the video shows, placeholders filled), and what the transcript adds about
    /// the board: the author's text alternative (`alt`), else the engine's description (`MGDescribe.board`).
    public struct Beat: Equatable, Sendable {
        public var narration: String
        public var alt: String?
        public var description: String?
        public init(narration: String, alt: String? = nil, description: String? = nil) {
            self.narration = narration; self.alt = alt; self.description = description
        }
    }

    /// One cue: its beat (0-based), its frames `startFrame ..< endFrame` at the plan's rate, and its lines.
    public struct Cue: Equatable, Sendable {
        public var beat: Int
        public var startFrame: Int
        public var endFrame: Int
        public var lines: [String]
    }

    /// The document's title (the transcript's first line), the story plan the cues follow (nil without beats), the
    /// beats and the cues in time order.
    public let title: String?
    public let plan: MGStoryPlan?
    public let beats: [Beat]
    public let cues: [Cue]

    /// Captions for `plan` (routed as the video plays it) with one entry in `beats` per plan beat. Refusal:
    /// `story.beats` (a plan without the same number of beats, or beats without a plan). The words are not refused
    /// here: each format applies its own text rules when it is written (`text(_:)`).
    public init(plan: MGStoryPlan?, beats: [Beat], title: String? = nil) throws {
        guard (plan?.beats.count ?? 0) == beats.count else { throw MGSolidIssue("story.beats") }
        self.title = title; self.plan = plan; self.beats = beats
        var cues: [Cue] = []
        if let plan {
            let cuts = plan.cuts
            for k in beats.indices {
                let b = plan.beats[k]
                cues += Self.cues(beat: k, text: beats[k].narration, start: plan.holdStartFrame(k, cuts: cuts),
                                  end: b.startFrame + b.frames, fps: plan.fps)
            }
        }
        self.cues = cues
    }

    // MARK: Line breaking and cue timing

    /// The narration's words: split at whitespace other than a no-break space.
    static func words(_ text: String) -> [Substring] {
        let noBreak: Set<Character> = ["\u{00A0}", "\u{2007}", "\u{202F}"]
        return text.split(whereSeparator: { $0.isWhitespace && !noBreak.contains($0) })
    }

    /// The narration as caption lines of at most `width` characters, filled greedily, breaking at whitespace (not at
    /// a no-break space). A word longer than `width` is cut into pieces of `width` characters.
    public static func lines(_ text: String, width: Int = maxLineCharacters) -> [String] {
        let width = max(1, width)
        var pieces: [String] = []
        for w in words(text) {
            var rest = w
            while rest.count > width { pieces.append(String(rest.prefix(width))); rest = rest.dropFirst(width) }
            pieces.append(String(rest))
        }
        var out: [String] = []
        for w in pieces {
            if let last = out.last, last.count + 1 + w.count <= width { out[out.count - 1] = last + " " + w } else { out.append(w) }
        }
        return out
    }

    /// The narration in `count` balanced lines or fewer: filled at the narrowest width (from its longest word up to
    /// `maxLineCharacters`) that needs at most `count` lines, so no line is much shorter than the others. Never cuts
    /// a word that fits a full line.
    public static func balancedLines(_ text: String, count: Int) -> [String] {
        let longest = words(text).map(\.count).max() ?? 0
        for w in max(1, min(longest, maxLineCharacters))...maxLineCharacters {
            let l = lines(text, width: w)
            if l.count <= count { return l }
        }
        return lines(text)
    }

    /// The cues of one beat whose caption shows in frames `start ..< end`. The number of cues: enough for the lines at
    /// `maxLineCharacters` in groups of `maxLines`, more when the hold is longer than `maxCueSeconds` per cue (at most
    /// one cue per such line). The words are then filled into `maxLines` balanced lines per cue (`balancedLines`) and
    /// shared out in order. Each cue lasts at least `minCueSeconds` when the hold has room; the rest of the hold is
    /// shared by the cues' lengths. Frame counts are whole: the last cue ends exactly at `end`.
    static func cues(beat: Int, text: String, start: Int, end: Int, fps: Int) -> [Cue] {
        let hold = end - start, full = lines(text)
        guard !full.isEmpty, hold > 0, fps > 0 else { return [] }
        let byLines = (full.count + maxLines - 1) / maxLines
        let byTime = Int((Double(hold) / (maxCueSeconds * Double(fps))).rounded(.up))
        // At least one frame per cue (a story beat's hold is always far longer than its line count).
        let n = max(1, min(hold, min(full.count, max(byLines, byTime))))
        let lines = full.count == 1 ? full : balancedLines(text, count: n * maxLines)
        let base = lines.count / n, extra = lines.count % n
        var groups: [[String]] = [], i = 0
        for g in 0..<n {
            let c = base + (g < extra ? 1 : 0)
            groups.append(Array(lines[i..<(i + c)])); i += c
        }
        let weights = groups.map { g in max(1, g.reduce(0) { $0 + $1.count }) }
        let total = weights.reduce(0, +)
        let minimum = min(Int((minCueSeconds * Double(fps)).rounded(.up)), hold / n)
        let spare = hold - n * minimum
        var out: [Cue] = [], sum = 0, from = start
        for (g, lines) in groups.enumerated() {
            sum += weights[g]
            let to = start + (g + 1) * minimum + spare * sum / total
            out.append(Cue(beat: beat, startFrame: from, endFrame: to, lines: lines))
            from = to
        }
        return out
    }

    // MARK: Output

    /// Frame `frame` at `fps` as `HH:MM:SS.mmm` (`separator` `.` for WebVTT, `,` for SubRip), in whole milliseconds
    /// rounded down, so the time never passes the frame's own presentation time.
    public static func timestamp(frame: Int, fps: Int, separator: Character = ".") -> String {
        let ms = max(0, frame) * 1000 / max(1, fps)
        func two(_ v: Int) -> String { v < 10 ? "0\(v)" : "\(v)" }
        let milli = ms % 1000
        let m3 = milli < 10 ? "00\(milli)" : milli < 100 ? "0\(milli)" : "\(milli)"
        return "\(two(ms / 3_600_000)):\(two((ms / 60_000) % 60)):\(two((ms / 1000) % 60))\(separator)\(m3)"
    }

    /// WebVTT cue text: `&`, `<` and `>` as character references, so no text reads as a tag, a character reference or
    /// a `-->` arrow. Escaped one Unicode scalar at a time: a `<` followed by a combining mark (one grapheme cluster)
    /// is still escaped, and the mark is kept.
    public static func escapeVTT(_ s: String) -> String {
        var out = String.UnicodeScalarView()
        for u in s.unicodeScalars {
            switch u {
            case "&": out.append(contentsOf: "&amp;".unicodeScalars)
            case "<": out.append(contentsOf: "&lt;".unicodeScalars)
            case ">": out.append(contentsOf: "&gt;".unicodeScalars)
            default: out.append(u)
            }
        }
        return String(out)
    }

    /// The line terminators a timed cue payload never holds: LF, CR, VT, FF, NEL, U+2028 LINE SEPARATOR and U+2029
    /// PARAGRAPH SEPARATOR. In a payload one would start a new payload line, or end the cue at a blank line.
    public static let payloadBreaks: Set<Unicode.Scalar> = ["\n", "\r", "\u{0B}", "\u{0C}", "\u{85}", "\u{2028}", "\u{2029}"]

    /// One payload line of a timed cue (WebVTT, SubRip): every run of line terminators (`payloadBreaks`; CR LF is one
    /// run) becomes one space. Line breaks in the narration already end words, so a cue line built from the narration
    /// never holds one; this rule keeps every written cue to its own lines whatever its text.
    public static func payloadLine(_ s: String) -> String {
        var out = String.UnicodeScalarView(), breaking = false
        for u in s.unicodeScalars {
            if payloadBreaks.contains(u) {
                if !breaking { out.append(" ") }
                breaking = true
            } else {
                out.append(u); breaking = false
            }
        }
        return String(out)
    }

    /// A WebVTT cue payload: each line with its line terminators normalised (`payloadLine`), then escaped (`escapeVTT`).
    public static func webVTTPayload(_ lines: [String]) -> String {
        lines.map { escapeVTT(payloadLine($0)) }.joined(separator: "\n")
    }

    /// A SubRip cue payload: each line with its line terminators normalised (`payloadLine`). SubRip has no escapes, so
    /// a line with `<`, `>` (a tag, or a `-->` arrow) or a control character (general category Cc) is refused
    /// (`captions.text`). The engine's checked captions never have them.
    public static func subRipPayload(_ lines: [String]) throws -> String {
        let out = lines.map(payloadLine)
        for line in out where line.unicodeScalars.contains(where: { $0 == "<" || $0 == ">" || $0.properties.generalCategory == .control }) {
            throw MGError("captions.text")
        }
        return out.joined(separator: "\n")
    }

    /// The export in `format`: UTF-8 text without a byte order mark, `\n` line ends, ending in one line break (an
    /// empty SubRip file is empty). Byte-identical in every run. Each format's text rules apply here; only SubRip
    /// refuses (`captions.text`, `subRip`).
    public func text(_ format: Format) throws -> String {
        switch format {
        case .vtt: return webVTT
        case .srt: return try subRip
        case .txt: return transcript
        }
    }

    /// `WEBVTT`, then per cue its number, `start --> end` and its payload (`webVTTPayload`), each block after a blank
    /// line.
    public var webVTT: String {
        let fps = plan?.fps ?? 1
        var out = "WEBVTT\n"
        for (i, c) in cues.enumerated() {
            out += "\n\(i + 1)\n\(Self.timestamp(frame: c.startFrame, fps: fps)) --> \(Self.timestamp(frame: c.endFrame, fps: fps))\n"
            out += Self.webVTTPayload(c.lines) + "\n"
        }
        return out
    }

    /// Per cue its number, `start --> end` (comma before the milliseconds) and its payload (`subRipPayload`), blocks
    /// separated by a blank line. SubRip has no escapes: the lines are the narration's words as they are, and a cue
    /// SubRip cannot hold is refused (`captions.text`).
    public var subRip: String {
        get throws {
            let fps = plan?.fps ?? 1
            return try cues.enumerated().map { i, c in
                "\(i + 1)\n\(Self.timestamp(frame: c.startFrame, fps: fps, separator: ",")) --> \(Self.timestamp(frame: c.endFrame, fps: fps, separator: ","))\n"
                    + (try Self.subRipPayload(c.lines)) + "\n"
            }.joined(separator: "\n")
        }
    }

    /// The plain-text transcript: the title, then per beat `[time] n. narration` (the time its caption appears; the
    /// narration exactly as written) and, when the beat has a board, `Text alternative: …` (the author's `alt`) or
    /// `Board (engine description): …`. Blocks are separated by a blank line.
    public var transcript: String {
        var blocks: [String] = []
        if let title, !title.isEmpty { blocks.append(title) }
        for (k, b) in beats.enumerated() {
            let time = plan.map { p in Self.timestamp(frame: p.holdStartFrame(k, cuts: p.cuts), fps: p.fps) } ?? Self.timestamp(frame: 0, fps: 1)
            var block = "[\(time)] \(k + 1). \(b.narration)"
            if let alt = b.alt { block += "\nText alternative: \(alt)" } else if let d = b.description { block += "\nBoard (engine description): \(d)" }
            blocks.append(block)
        }
        return blocks.isEmpty ? "" : blocks.joined(separator: "\n\n") + "\n"
    }
}

// MARK: The story of a document

extension MGCaptionExport {
    /// Captions of an assembly's story video at `width` × `height` and `fps`: the story `marty-solid render` plays as
    /// `story.mp4` (`MGStoryShots`: one beat per step, caption `n. say`, the step stills' cameras, the routed camera
    /// moves, which decide when each caption appears). An assembly without steps has no story and no cues. Throws the
    /// plan's refusals (`story.rate`, `story.beats`, `story.frames`).
    public init(assembly doc: MGSolidDocument, source: MGSolidSource, width: Int = 1280, height: Int = 800,
                fps: Int = MGStoryTiming.defaultRate) throws {
        let story = try MGStoryShots(assembly: doc, source: source, width: width, height: height, fps: fps)
        try self.init(plan: story?.plan, beats: story == nil ? [] : doc.steps.map { Beat(narration: $0.say) }, title: doc.title)
    }

    /// Captions of an explainer's story video at `width` × `height` and `fps`: the beats and story `marty-solid render`
    /// plays as `story.mp4` (`MGExplainerStory`: each beat settled, its panes and solid camera, the routed camera
    /// moves). Each beat's board text: the board's `alt`, else `MGDescribe.board` of the settled board. Nil when the
    /// document does not load; an explainer without beats has no cues. Throws the plan's refusals.
    public init?(explainer doc: MGExplainer, library: MGSolidLibrary = .builtIn, width: Int = 1280, height: Int = 800,
                 fps: Int = MGStoryTiming.defaultRate) throws {
        guard let e = try MGExplainerStory(doc, library: library, width: width, height: height, fps: fps) else { return nil }
        let beats = e.beats.map { b -> Beat in
            guard doc.board != nil, let scene = b.scene else { return Beat(narration: b.caption) }
            return Beat(narration: b.caption, alt: scene.alt, description: scene.alt == nil ? MGDescribe.board(scene) : nil)
        }
        try self.init(plan: e.story?.plan, beats: beats, title: e.title)
    }
}

// MARK: Checked files

extension MGCaptionExport {
    /// The export of a document file, or its refusal: the text to print and whether it is the export.
    public struct Output: Equatable, Sendable {
        /// True when `text` is the export; false when it is a refusal report (JSON).
        public let ok: Bool
        public let text: String
        public var exitCode: Int32 { ok ? 0 : 1 }
    }

    /// `marty-solid export-captions FILE.json --format vtt|srt|txt` as a library API. The document is checked first,
    /// with `profile`, as `marty-solid transcript` checks it: a refused document gives its check report (the same
    /// object `marty-solid check` prints) and no captions. An explainer (`"kind": "explainer"`) or an assembly (any
    /// other kind; a lesson is the caller's `kind.unsupported`) is then planned as `marty-solid render` plans its story
    /// at `width` × `height` and `fps` (the same `--size` and `--story-fps` give the same timing). A story the render
    /// tool would refuse gives the same `{"ok": false, "reason": "story.…"}` object.
    public static func make(data: Data, format: Format, library: MGSolidLibrary = .builtIn, profile: MGSolidProfile = .standard,
                            width: Int = 1280, height: Int = 800, fps: Int = MGStoryTiming.defaultRate,
                            engine: MGJSON? = MGEngine.identity) -> Output {
        func refused(_ json: MGJSON) -> Output { Output(ok: false, text: MGSolidReport.text(json)) }
        func story(_ reason: String) -> Output {
            var o: [String: MGJSON] = ["ok": .bool(false), "reason": .string(reason)]
            if let engine { o["engine"] = engine }
            return refused(.object(o))
        }
        do {
            if case .string("explainer")? = MGExplainer.topLevelKind(data) {
                let gate = MGExplainerReport.check(data: data, library: library, profile: profile, engine: engine, suggest: false)
                guard gate.ok, case .success(let doc) = MGExplainer.parse(data: data) else {
                    return refused(MGExplainerReport.check(data: data, library: library, profile: profile, engine: engine).json)
                }
                guard let e = try MGCaptionExport(explainer: doc, library: library, width: width, height: height, fps: fps) else { return refused(gate.json) }
                return Output(ok: true, text: try e.text(format))
            }
            let report = MGSolidReport.check(data: data, library: library, profile: profile, engine: engine)
            guard report.ok, case .success(let doc) = MGSolidParser.document(data: data, library: library) else { return refused(report.json) }
            return Output(ok: true, text: try MGCaptionExport(assembly: doc, source: MGSolidSource(data: data), width: width, height: height, fps: fps)
                .text(format))
        } catch let e as MGSolidIssue {
            return story(e.reason)
        } catch let e as MGError {
            return story(e.reason)
        } catch {
            return story("story.beats")
        }
    }
}
