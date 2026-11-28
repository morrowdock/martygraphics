// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import MartyGraphics

/// Captions and transcript export (`MGCaptionExport`, `marty-solid export-captions`): golden WebVTT, SubRip and
/// transcript files for two shipped documents (`docs/fixtures/captions`), escaping, line breaking, cue durations, and
/// timing parity with the story video: every frame `story.mp4` shows (frame `i` at `i / fps` seconds, as
/// `MGMovieWriter` stamps it) is inside a cue exactly when the video's caption band shows that beat's caption.
final class CaptionExportTests: XCTestCase {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let golden = root.appendingPathComponent("docs/fixtures/captions")
    /// The fixtures: an assembly with four steps (spins, long narration) and an explainer with a board and a solid.
    static let inputs = [("slider-crank", "Examples/Solid3D/Sources/MartySolid3D/Models/slider-crank.json"),
                         ("gears-mixed", "Examples/Explainers/gears-mixed.explainer.json")]

    func data(_ path: String) throws -> Data { try Data(contentsOf: Self.root.appendingPathComponent(path)) }

    // MARK: Golden files

    /// Byte-identical to the golden files (UTF-8, no byte order mark, LF), in every run. Set `MG_WRITE_CAPTION_GOLDEN=1`
    /// to write them.
    func testOutputIsByteIdenticalToTheGoldenFiles() throws {
        let write = ProcessInfo.processInfo.environment["MG_WRITE_CAPTION_GOLDEN"] == "1"
        for (name, path) in Self.inputs {
            let input = try data(path)
            for format in MGCaptionExport.Format.allCases {
                let out = MGCaptionExport.make(data: input, format: format, engine: nil)
                XCTAssertTrue(out.ok, "\(name).\(format): \(out.text)")
                XCTAssertEqual(MGCaptionExport.make(data: input, format: format, engine: nil), out, "deterministic")
                let bytes = Data(out.text.utf8)
                XCTAssertFalse(bytes.starts(with: [0xEF, 0xBB, 0xBF]), "no byte order mark")
                XCTAssertFalse(bytes.contains(0x0D), "LF line ends")
                XCTAssertEqual(bytes.last, 0x0A)
                let url = Self.golden.appendingPathComponent("\(name).\(format.rawValue)")
                if write { try bytes.write(to: url) }
                XCTAssertEqual(out.text, try String(contentsOf: url, encoding: .utf8), "\(name).\(format)")
            }
        }
    }

    /// The fixtures exercise the rules: several cues per beat, two lines, a placeholder filled by the engine, a board
    /// description, and a routed or straight move delaying each caption.
    func testGoldenFixturesCoverTheRules() throws {
        let crank = try XCTUnwrap(try export(Self.inputs[0].1))
        XCTAssertEqual(crank.beats.count, 4)
        XCTAssertGreaterThan(crank.cues.count, 4, "a long narration takes more than one cue")
        XCTAssertTrue(crank.cues.contains { $0.lines.count == 2 })
        let gears = try XCTUnwrap(try export(Self.inputs[1].1))
        XCTAssertEqual(gears.beats.map(\.narration), ["Count the teeth: 15 and 30.", "So the big gear turns 1/2 of a turn."])
        XCTAssertNil(gears.beats[0].alt)
        XCTAssertTrue(gears.beats[0].description?.hasPrefix("A table of 3 rows") ?? false, gears.beats[0].description ?? "nil")
        XCTAssertTrue(gears.transcript.contains("\nBoard (engine description): A table"))
        for e in [crank, gears] {
            let plan = try XCTUnwrap(e.plan)
            XCTAssertGreaterThan(plan.holdStartFrame(1, cuts: plan.cuts), plan.beats[1].startFrame, "the caption waits for the move")
        }
    }

    // MARK: Escaping and encoding

    func testWebVTTEscapesAndSubRipKeepsTheWords() throws {
        XCTAssertEqual(MGCaptionExport.escapeVTT("a<b>&c-->d"), "a&lt;b&gt;&amp;c--&gt;d")
        XCTAssertEqual(MGCaptionExport.escapeVTT("Größe – 5 kg & 3 m"), "Größe – 5 kg &amp; 3 m")
        let e = try one("Tom & Jerry say “hi” — 5\u{00A0}kg, naïve café.")
        // 42 characters: one line.
        XCTAssertTrue(e.webVTT.hasSuffix(" --> 00:00:03.866\nTom &amp; Jerry say “hi” — 5\u{00A0}kg, naïve café.\n"), e.webVTT)
        let srt = try e.subRip
        XCTAssertTrue(srt.hasSuffix(" --> 00:00:03,866\nTom & Jerry say “hi” — 5\u{00A0}kg, naïve café.\n"), srt)
        XCTAssertTrue(e.transcript.contains("1. Tom & Jerry say “hi” — 5\u{00A0}kg, naïve café.\n"), "the transcript keeps the narration")
        XCTAssertTrue(e.webVTT.hasPrefix("WEBVTT\n\n1\n00:00:00.000 --> "))
        XCTAssertTrue(srt.hasPrefix("1\n00:00:00,000 --> "))
        // No cue text can close a cue or read as a timing line.
        for text in [e.webVTT, srt] { XCTAssertFalse(text.contains("\n\n\n")) }
        // Tabs and line breaks are only spaces between words.
        XCTAssertEqual(try one("one\ttwo\nthree\r\nfour").cues.flatMap(\.lines), ["one two three four"])
    }

    /// Each format applies its own text rules when it is written: SubRip cannot escape a tag or an arrow, so writing it
    /// refuses `<`, `>` and control characters (`captions.text`); the same captions are written as WebVTT (escaped) and
    /// as the transcript (the narration exactly as written). Making the export refuses nothing.
    func testOnlySubRipRefusesWhatItCannotHold() throws {
        for bad in ["if a < b", "x > 0", "bell\u{07}", "<i>", "a --> b"] {
            let e = try one(bad)
            XCTAssertThrowsError(try e.subRip, bad) { XCTAssertEqual(($0 as? MGError)?.reason, "captions.text") }
            XCTAssertThrowsError(try e.text(.srt), bad)
            XCTAssertNoThrow(try e.text(.vtt), bad)
            XCTAssertEqual(try e.text(.vtt), e.webVTT)
            XCTAssertFalse(e.webVTT.contains("<"), bad)
            XCTAssertEqual(try e.text(.txt), e.transcript)
            XCTAssertTrue(e.transcript.hasSuffix("1. \(bad)\n"), bad)
        }
        XCTAssertEqual(try one("if a < b").webVTT.components(separatedBy: "\n").last(where: { !$0.isEmpty }), "if a &lt; b")
        XCTAssertEqual(try one("a --> b").webVTT.components(separatedBy: "\n").last(where: { !$0.isEmpty }), "a --&gt; b")
        // Format characters (a zero-width joiner, a bidi mark) are not control characters: SubRip keeps them.
        XCTAssertEqual(try MGCaptionExport.subRipPayload(["Tom & Jerry", "zero\u{200D}width, bidi\u{200E}mark"]),
                       "Tom & Jerry\nzero\u{200D}width, bidi\u{200E}mark")
    }

    /// The transcript keeps the narration exactly as written, line breaks and all; the timed cues never hold one.
    func testTheTranscriptKeepsTheNarrationAsWritten() throws {
        let narration = "Line one\nline two\u{2028}three\u{2029}four\r\nfive <b> & bell\u{07}"
        let e = try one(narration)
        XCTAssertEqual(e.beats[0].narration, narration)
        XCTAssertTrue(e.transcript.hasSuffix("] 1. \(narration)\n"), e.transcript)
        XCTAssertEqual(e.cues.flatMap(\.lines).joined(separator: " "), "Line one line two three four five <b> & bell\u{07}")
        let vtt = e.webVTT.components(separatedBy: "\n").dropFirst(4).filter { !$0.isEmpty }
        XCTAssertEqual(vtt.joined(separator: " "), "Line one line two three four five &lt;b&gt; &amp; bell\u{07}")
    }

    /// WebVTT escapes one Unicode scalar at a time: an escapable scalar followed by a combining mark (one grapheme
    /// cluster, so not equal to the bare character) is still escaped, and the mark is kept after the reference.
    func testWebVTTEscapesScalarsInsideGraphemeClusters() throws {
        XCTAssertEqual(MGCaptionExport.escapeVTT("<\u{0338}"), "&lt;\u{0338}")
        XCTAssertEqual(MGCaptionExport.escapeVTT(">\u{0301}x"), "&gt;\u{0301}x")
        XCTAssertEqual(MGCaptionExport.escapeVTT("&\u{20DD}"), "&amp;\u{20DD}")
        XCTAssertEqual(MGCaptionExport.escapeVTT("--\u{0300}>"), "--\u{0300}&gt;")
        XCTAssertEqual(MGCaptionExport.escapeVTT("-->\u{0301}"), "--&gt;\u{0301}")
        // Characters that only look alike are not escaped: only U+0026, U+003C and U+003E are.
        XCTAssertEqual(MGCaptionExport.escapeVTT("\u{FF1C}\u{2039}\u{FE64}"), "\u{FF1C}\u{2039}\u{FE64}")
        XCTAssertEqual(MGCaptionExport.escapeVTT(""), "")
        let e = try one("a <\u{0338} b")
        XCTAssertTrue(e.webVTT.hasSuffix("\na &lt;\u{0338} b\n"), e.webVTT)
        XCTAssertFalse(e.webVTT.unicodeScalars.contains("<"))
    }

    /// Timed cue payloads (WebVTT and SubRip) never hold a line terminator: every run of LF, CR, VT, FF, NEL, U+2028 and
    /// U+2029 (CR LF is one run) becomes one space, so a written cue always keeps its own lines and never ends early.
    func testCuePayloadsNormaliseLineTerminators() throws {
        XCTAssertEqual(MGCaptionExport.payloadLine("a\nb"), "a b")
        XCTAssertEqual(MGCaptionExport.payloadLine("a\r\nb"), "a b")
        XCTAssertEqual(MGCaptionExport.payloadLine("a\rb"), "a b")
        XCTAssertEqual(MGCaptionExport.payloadLine("a\u{2028}b\u{2029}c"), "a b c")
        XCTAssertEqual(MGCaptionExport.payloadLine("a\u{85}b\u{0B}c\u{0C}d"), "a b c d")
        XCTAssertEqual(MGCaptionExport.payloadLine("a\n\n\u{2028}\r\nb"), "a b", "a run is one space")
        XCTAssertEqual(MGCaptionExport.payloadLine("\na"), " a")
        XCTAssertEqual(MGCaptionExport.payloadLine("a\tb c"), "a\tb c", "other whitespace stays")
        XCTAssertEqual(MGCaptionExport.webVTTPayload(["a\n\nb <", "c\u{2028}&"]), "a b &lt;\nc &amp;")
        XCTAssertEqual(try MGCaptionExport.subRipPayload(["a\n\nb", "c\u{2029}d"]), "a b\nc d")
        XCTAssertThrowsError(try MGCaptionExport.subRipPayload(["a\n<b"]))
        for payload in [MGCaptionExport.webVTTPayload(["x\r\n\r\ny", "z\u{2028}\u{2028}w"]), try MGCaptionExport.subRipPayload(["x\r\n\r\ny", "z\u{2028}\u{2028}w"])] {
            XCTAssertEqual(payload.components(separatedBy: "\n").count, 2, payload)
            XCTAssertFalse(payload.unicodeScalars.contains { MGCaptionExport.payloadBreaks.contains($0) && $0 != "\n" }, payload)
        }
    }

    func testEmptyAndUnequalInputs() throws {
        let empty = try MGCaptionExport(plan: nil, beats: [], title: "T")
        let emptySRT = try empty.subRip
        XCTAssertEqual(empty.webVTT, "WEBVTT\n"); XCTAssertEqual(emptySRT, ""); XCTAssertEqual(empty.transcript, "T\n")
        let plan = try MGStoryPlan(captions: ["1. A."], spins: [0])
        XCTAssertThrowsError(try MGCaptionExport(plan: plan, beats: [])) { XCTAssertEqual(($0 as? MGSolidIssue)?.reason, "story.beats") }
        XCTAssertThrowsError(try MGCaptionExport(plan: nil, beats: [.init(narration: "A.")]))
        let refused = MGCaptionExport.make(data: Data(#"{"v":2,"kind":"assembly","parts":[]}"#.utf8), format: .vtt, engine: nil)
        XCTAssertFalse(refused.ok); XCTAssertEqual(refused.exitCode, 1)
    }

    // MARK: Line breaking and durations

    func testLinesBreakAtSpacesWithinTheLimits() {
        XCTAssertEqual(MGCaptionExport.lines("A slider-crank turns spinning motion into back-and-forth motion."),
                       ["A slider-crank turns spinning motion into", "back-and-forth motion."])
        XCTAssertEqual(MGCaptionExport.lines(String(repeating: "x", count: 90)).map(\.count), [42, 42, 6])
        XCTAssertEqual(MGCaptionExport.lines("  "), [])
        // A no-break space keeps a number with its unit.
        let unit = MGCaptionExport.lines(String(repeating: "a", count: 38) + " 12\u{00A0}mm")
        XCTAssertEqual(unit, [String(repeating: "a", count: 38), "12\u{00A0}mm"])
        // Characters are grapheme clusters: 42 accented letters and emoji fit one line.
        XCTAssertEqual(MGCaptionExport.lines(String(repeating: "é", count: 42)).count, 1)
        XCTAssertEqual(MGCaptionExport.lines(String(repeating: "👍🏽", count: 43)).map(\.count), [42, 1])
    }

    /// Words in order and unchanged, at most 2 lines of 42 characters per cue, every cue at least 1 s, cues back to
    /// back inside the beat's caption frames, for narrations from one word to the 200-character limit.
    func testCueRulesHoldForEveryNarrationLength() throws {
        let words = "The quick brown fox jumps over the lazy dog while a gear of fifteen teeth drives one of thirty, 2× slower; tooth-counts matter"
            .split(separator: " ").map(String.init)
        for fps in MGStoryTiming.rates {
            var text = ""
            for w in words.cycled(200) {
                text = text.isEmpty ? w : text + " " + w
                guard text.unicodeScalars.count <= 200 else { break }
                let e = try one(text, fps: fps)
                let plan = try XCTUnwrap(e.plan)
                let cueLines: [String] = e.cues.flatMap(\.lines)
                let exportedWords: [Substring] = cueLines.joined(separator: " ").split(separator: " ")
                let originalWords: [Substring] = text.split(separator: " ")
                XCTAssertEqual(exportedWords, originalWords, "words unchanged")
                var at = plan.holdStartFrame(0)
                for c in e.cues {
                    XCTAssertTrue((1...MGCaptionExport.maxLines).contains(c.lines.count))
                    XCTAssertTrue(c.lines.allSatisfy { $0.count <= MGCaptionExport.maxLineCharacters })
                    XCTAssertEqual(c.startFrame, at); at = c.endFrame
                    XCTAssertGreaterThanOrEqual(Double(c.endFrame - c.startFrame) / Double(fps), MGCaptionExport.minCueSeconds, text)
                }
                XCTAssertEqual(at, plan.frameCount)
            }
        }
    }

    /// A short caption held long keeps one cue; a beat held longer than 7 s per cue gets a cue per full-length line,
    /// its words spread over them in balanced lines.
    func testLongHoldsSplitAsFarAsTheLinesAllow() throws {
        let spin = try MGStoryPlan(captions: ["1. Turn."], spins: [3])
        XCTAssertEqual(spin.beats[0].frames, 270)
        XCTAssertEqual(try MGCaptionExport(plan: spin, beats: [.init(narration: "Turn.")]).cues.count, 1)
        let two = String(repeating: "word ", count: 14).trimmingCharacters(in: .whitespaces)   // 69 characters: 2 full lines
        let e = try MGCaptionExport(plan: try MGStoryPlan(captions: ["1. " + two], spins: [3]), beats: [.init(narration: two)])
        XCTAssertEqual(e.cues.map(\.lines), [["word word word word", "word word word word"], ["word word word word", "word word"]])
        XCTAssertTrue(e.cues.allSatisfy { Double($0.endFrame - $0.startFrame) / 30 <= MGCaptionExport.maxCueSeconds })
        // Without the long hold the same words take one cue of two balanced lines.
        let short = try one(two)
        XCTAssertEqual(short.cues.map(\.lines), [["word word word word word word word", "word word word word word word word"]])
    }

    /// Balanced lines: the narrowest fill that needs no more lines; a word is never cut to balance.
    func testBalancedLines() {
        let text = "A slider-crank turns spinning motion into back-and-forth motion, as in an engine or a pump."
        let b = MGCaptionExport.balancedLines(text, count: 4)
        XCTAssertEqual(b.count, 4)
        XCTAssertEqual(b.joined(separator: " "), text)
        XCTAssertLessThanOrEqual(b.map(\.count).max()! - b.map(\.count).min()!, 10, "\(b)")
        XCTAssertEqual(MGCaptionExport.balancedLines("Supercalifragilistic word", count: 9), ["Supercalifragilistic", "word"])
        XCTAssertEqual(MGCaptionExport.balancedLines("", count: 2), [])
    }

    /// `--size WxH` (`render`, `export-captions`, `export-gltf`): exactly two fields of ASCII digits around one `x`,
    /// both parsed before the bounds are checked.
    func testFrameSizeIsExactlyTwoIntegers() {
        XCTAssertEqual(MGStoryShots.size("640x400").map { [$0.width, $0.height] }, [640, 400])
        XCTAssertEqual(MGStoryShots.size("1280x800").map { [$0.width, $0.height] }, [1280, 800])
        XCTAssertEqual(MGStoryShots.size("320x200").map { [$0.width, $0.height] }, [320, 200])
        XCTAssertEqual(MGStoryShots.size("3840x2160").map { [$0.width, $0.height] }, [3840, 2160])
        XCTAssertEqual(MGStoryShots.size("0640x0400").map { [$0.width, $0.height] }, [640, 400], "leading zeros are digits")
        for bad in ["640xx400", "640x400x", "x640x400", "640x", "x400", "x", "", "640", "640x400x1", "640X400", "+640x400", "640x-400",
                    " 640x400", "640x400 ", "640 x 400", "6４0x400", "640x400\n", "319x400", "640x199", "3841x400", "640x2161",
                    "99999999999999999999x400", "640.0x400", "0x0"] {
            XCTAssertNil(MGStoryShots.size(bad), bad)
        }
    }

    func testTimestamps() {
        XCTAssertEqual(MGCaptionExport.timestamp(frame: 0, fps: 30), "00:00:00.000")
        XCTAssertEqual(MGCaptionExport.timestamp(frame: 2, fps: 30), "00:00:00.066")   // 66.7 ms, rounded down
        XCTAssertEqual(MGCaptionExport.timestamp(frame: 3600, fps: 30, separator: ","), "00:02:00,000")
        XCTAssertEqual(MGCaptionExport.timestamp(frame: 37, fps: 10), "00:00:03.700")
        XCTAssertEqual(MGCaptionExport.timestamp(frame: 30 * 3661 + 1, fps: 30), "01:01:01.033")
    }

    // MARK: Timing parity with the story video

    /// For both fixtures, at both rates and three sizes: the plan is the one `marty-solid render` builds for `story.mp4`
    /// (the same beats, still cameras and routed moves, rebuilt here as the render tool builds it), and every frame
    /// the movie writer writes (frame `i` at `i / fps` s) falls inside a cue of the printed WebVTT and SubRip exactly
    /// when the frame's caption band shows a caption, and that cue belongs to the frame's beat. Each beat's first cue
    /// starts at the `holdStart` and its last cue ends at `start + seconds` of the `story.mp4` manifest record.
    func testCueBoundariesMatchTheStoryVideoFrames() throws {
        for (name, path) in Self.inputs {
            for fps in MGStoryTiming.rates {
                for (w, h) in [(1280, 800), (640, 400), (800, 1000)] {
                    let label = "\(name) \(fps) fps \(w)x\(h)"
                    let input = try data(path)
                    let e = try XCTUnwrap(try export(path, width: w, height: h, fps: fps), label)
                    let plan = try XCTUnwrap(e.plan)
                    XCTAssertEqual(plan, try shared(input, width: w, height: h, fps: fps), "\(label): the plan the render tool plays")
                    XCTAssertEqual(plan, try reference(input, width: w, height: h, fps: fps), "\(label): an independent rebuild of the plan")
                    let format = MGCaptionExport.make(data: input, format: .vtt, width: w, height: h, fps: fps, engine: nil)
                    XCTAssertEqual(format.text, e.webVTT, label)
                    for (text, sep) in [(e.webVTT, "."), (try e.subRip, ",")] {
                        let cues = parse(text, separator: sep)
                        XCTAssertEqual(cues.count, e.cues.count, label)
                        for i in 0..<plan.frameCount {
                            let shown = plan.caption(frame: i, cuts: plan.cuts) != nil
                            let hit = cues.indices.filter { cues[$0].start * fps <= i * 1000 && i * 1000 < cues[$0].end * fps }
                            XCTAssertEqual(hit.count, shown ? 1 : 0, "\(label) frame \(i)")
                            if let c = hit.first {
                                XCTAssertEqual(e.cues[c].beat, plan.frame(i).beat, "\(label) frame \(i)")
                                // The one cue whose interval holds this frame's time is the cue planned for this frame.
                                XCTAssertTrue((e.cues[c].startFrame..<e.cues[c].endFrame).contains(i), "\(label) frame \(i) cue \(c + 1)")
                            }
                        }
                    }
                    guard case .array(let beats)? = plan.manifestFields(cuts: plan.cuts)["beats"] else { return XCTFail(label) }
                    for (k, b) in beats.enumerated() {
                        let o = try XCTUnwrap(b.objectValue)
                        let hold = try XCTUnwrap(number(o["holdStart"])), start = try XCTUnwrap(number(o["start"]))
                        let seconds = try XCTUnwrap(number(o["seconds"]))
                        let mine = e.cues.filter { $0.beat == k }
                        let first = try XCTUnwrap(mine.first), last = try XCTUnwrap(mine.last)
                        XCTAssertEqual(Double(first.startFrame) / Double(fps), hold, accuracy: 1e-9, "\(label) beat \(k + 1)")
                        XCTAssertEqual(Double(last.endFrame) / Double(fps), start + seconds, accuracy: 1e-9, "\(label) beat \(k + 1)")
                    }
                }
            }
        }
    }

    /// The story video, the caption export and the transcript read the same settled beats
    /// (`MGExplainerSession.settledBeats`): for shipped explainers (a board and a solid; a board only) the story's beat
    /// captions are the transcript's captions, in order, and the export's narration is the story's.
    func testTheStoryAndTheTranscriptReadTheSameBeats() throws {
        for path in [Self.inputs[1].1, "Examples/Explainers/planets-2d.explainer.json"] {
            let input = try data(path)
            let story = try XCTUnwrap(try MGExplainerStory(try MGExplainer.parse(data: input).get()), path)
            let t = MGTranscript.make(data: input, file: "x.json", engine: nil)
            XCTAssertTrue(t.ok, t.text)
            guard case .array(let beats)? = t.json.objectValue?["beats"] else { return XCTFail(path) }
            let captions = beats.map { b -> String in if case .string(let c)? = b.objectValue?["caption"] { return c }; return "" }
            XCTAssertFalse(captions.isEmpty, path)
            XCTAssertEqual(captions, story.beats.map(\.caption), path)
            XCTAssertEqual(try XCTUnwrap(try export(path)).beats.map(\.narration), captions, path)
        }
    }

    // MARK: Helpers

    func number(_ v: MGJSON?) -> Double? { if case .number(let x)? = v { return x }; return nil }

    func export(_ path: String, width: Int = 1280, height: Int = 800, fps: Int = 30) throws -> MGCaptionExport? {
        let input = try data(path)
        if case .string("explainer")? = MGExplainer.topLevelKind(input) {
            return try MGCaptionExport(explainer: try MGExplainer.parse(data: input).get(), width: width, height: height, fps: fps)
        }
        return try MGCaptionExport(assembly: try MGSolidParser.document(data: input).get(), source: MGSolidSource(data: input),
                                   width: width, height: height, fps: fps)
    }

    /// One beat with this narration, timed as a story plan times it.
    func one(_ narration: String, fps: Int = 30) throws -> MGCaptionExport {
        try MGCaptionExport(plan: try MGStoryPlan(captions: ["1. " + narration], spins: [0], fps: fps), beats: [.init(narration: narration)])
    }

    /// Cue times in milliseconds from printed WebVTT or SubRip.
    func parse(_ text: String, separator: String) -> [(start: Int, end: Int)] {
        func ms(_ s: Substring) -> Int {
            let p = s.split(whereSeparator: { $0 == ":" || String($0) == separator }).compactMap { Int($0) }
            return p.count == 4 ? ((p[0] * 60 + p[1]) * 60 + p[2]) * 1000 + p[3] : -1
        }
        return text.components(separatedBy: "\n").compactMap { line -> (Int, Int)? in
            let parts = line.components(separatedBy: " --> ")
            guard parts.count == 2 else { return nil }
            return (ms(Substring(parts[0])), ms(Substring(parts[1])))
        }
    }

    /// The story plan `marty-solid render` plays (main.swift, `render` and `renderExplainer`): `MGStoryShots` from the
    /// render plan's stills and cameras (with its loop, as `render` builds it), or `MGExplainerStory`.
    func shared(_ data: Data, width w: Int, height h: Int, fps: Int) throws -> MGStoryPlan {
        if case .string("explainer")? = MGExplainer.topLevelKind(data) {
            let story = try XCTUnwrap(try MGExplainerStory(try MGExplainer.parse(data: data).get(), width: w, height: h, fps: fps))
            return try XCTUnwrap(story.story?.plan)
        }
        let doc = try MGSolidParser.document(data: data).get()
        let plan = MGSolidRenderPlan(doc, sourceName: "x.json", source: MGSolidSource(data: data), loop: true, loopRate: 10)
        let shots = try MGStoryShots(assembly: doc, stills: plan, cameras: plan.cameras(doc, width: Double(w), height: Double(h)), fps: fps)
        return try XCTUnwrap(shots?.plan)
    }

    /// The story plan built the way `marty-solid render` built it before the shared builder (`MGStoryShots`,
    /// `MGExplainerStory`), written out separately here from the engine pieces: an independent check of the builder.
    func reference(_ data: Data, width w: Int, height h: Int, fps: Int) throws -> MGStoryPlan {
        if case .string("explainer")? = MGExplainer.topLevelKind(data) {
            let doc = try MGExplainer.parse(data: data).get()
            let dryClock = MGManualClock()
            var dry = MGExplainerSession(pacing: .speech, clock: dryClock)
            _ = dry.load(doc)
            var captions: [String] = [], spins: [Double] = []
            while let beat = dry.presented.beat, beat == captions.count {
                dryClock.advance(by: dry.motionRemaining)
                _ = dry.tick()
                captions.append("\(beat + 1). \(dry.caption ?? "")"); spins.append(dry.presented.step?.spin ?? 0)
                _ = dry.lineEnded(beat)
            }
            let unrouted = try MGStoryPlan(captions: captions, spins: spins, fps: fps)
            let clock = MGManualClock()
            var s = MGExplainerSession(pacing: .speech, clock: clock)
            _ = s.load(doc)
            let d = try XCTUnwrap(s.solid)
            let primary = (s.primary ?? "solid") == "solid"
            var shots: [(view: MGExplainerBeatView, camera: MGSolidCamera?, clear: MGSolidClearView?)] = []
            while let k = s.presented.beat, k == shots.count {
                clock.advance(by: s.motionRemaining)
                _ = s.tick()
                let pane = s.boardPane
                let share = pane.shown ? MGExplainerFrame.boardShare(scene: s.state?.scene, width: w, height: h, primarySolid: primary) : nil
                let rects = MGExplainerFrame.panes(width: w, height: h, board: pane.shown, solid: true, primarySolid: primary, boardShare: share)
                let clear = MGExplainerFrame.solidClearView(d, view: s.presented, stepIndex: s.solidStep(forBeat: k), pane: try XCTUnwrap(rects.solid))
                shots.append((s.presented, clear.camera, clear))
                _ = s.lineEnded(k)
            }
            let hold = shots.map { $0.clear?.view($0.view.solid ?? d.view(step: nil)) ?? ($0.view.solid ?? d.view(step: nil)) }
            let route = shots.indices.map { k in
                MGStoryBeatShot(camera: shots[k].camera, params: MGExplainerFrame.pose(d, view: shots[k].view),
                                view: k == 0 ? hold[0] : hold[k].moving(from: hold[k - 1], d.assembly), step: shots[k].view.step)
            }
            return unrouted.routed(MGStoryPlan.routes(d, beats: route, plan: unrouted))
        }
        let doc = try MGSolidParser.document(data: data).get()
        let unrouted = try MGStoryPlan(captions: doc.steps.indices.map { "\($0 + 1). \(doc.steps[$0].say)" }, spins: doc.steps.map(\.spin), fps: fps)
        let plan = MGSolidRenderPlan(doc, sourceName: "x.json", source: MGSolidSource(data: data), loop: true, loopRate: 10)
        let cameras = plan.cameras(doc, width: Double(w), height: Double(h))
        let stepStill = Dictionary(uniqueKeysWithValues: plan.stills.indices.compactMap { k in plan.stills[k].step.map { ($0, k) } })
        let beatCameras: [MGSolidCamera?] = doc.steps.indices.map { k in stepStill[k].map { cameras.stills[$0] } }
        let beatClear: [Int: MGSolidClearView] = Dictionary(uniqueKeysWithValues: doc.steps.indices.compactMap { k in stepStill[k].map { (k, cameras.clear[$0]) } })
        let holdViews = doc.steps.indices.map { k in beatClear[k]?.view(doc.view(step: k)) ?? doc.view(step: k) }
        let moveViews = doc.steps.indices.map { k in k == 0 ? holdViews[0] : holdViews[k].moving(from: holdViews[k - 1], doc.assembly) }
        let shots = doc.steps.indices.map { k in
            MGStoryBeatShot(camera: beatCameras[k], params: MGSolidShot.step(doc, k)?.params ?? doc.defaults, view: moveViews[k], step: doc.steps[k])
        }
        return unrouted.routed(MGStoryPlan.routes(doc, beats: shots, plan: unrouted))
    }
}

private extension Array {
    /// The elements repeated until there are `count`.
    func cycled(_ count: Int) -> [Element] { isEmpty ? [] : (0..<count).map { self[$0 % self.count] } }
}
