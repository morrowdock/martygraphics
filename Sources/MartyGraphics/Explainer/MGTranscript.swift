// SPDX-License-Identifier: Apache-2.0
import Foundation

// The transcript of a checked document: every caption, every shown label, arrow and dimension text, and every board
// table, per beat (an explainer) or per step (an assembly), as plain reflowable text for screen readers, large text
// and a static equivalent (docs/EXPLAINER.md, "Transcript"). Read-only: it changes no check, report or render output.

/// `marty-solid transcript FILE.json` as a library API. The document is checked first; a refused document gives its
/// check report (the same object `marty-solid check` prints, with the same profile) and no transcript.
public struct MGTranscript: Equatable, Sendable {
    /// The output format: the hand-written course transcripts' format, so they and the engine's output share one shape.
    public static let format = "morrowdock-explainer-transcript"
    public static let version = 1
    public static let about = "Every caption, every on-screen label and arrow text, and the table rows, as plain text. "
        + "Generated from the explainer JSON; the words are the document's own."

    /// True when the document passed its check and `json` is the transcript; false when `json` is the check report.
    public let ok: Bool
    public let json: MGJSON

    public var exitCode: Int32 { ok ? 0 : 1 }
    /// Pretty-printed JSON with sorted keys, as `marty-solid` prints it.
    public var text: String { MGSolidReport.text(json) }

    /// The transcript of an explainer (`"kind": "explainer"`) or an assembly (any other kind), named `file` in the
    /// output. A lesson document is not a transcript input; the caller refuses it (`kind.unsupported`).
    public static func make(data: Data, file: String, library: MGSolidLibrary = .builtIn, profile: MGSolidProfile = .standard,
                            engine: MGJSON? = MGEngine.identity) -> MGTranscript {
        if case .string("explainer")? = MGExplainer.topLevelKind(data) {
            return explainer(data: data, file: file, library: library, profile: profile, engine: engine)
        }
        return assembly(data: data, file: file, library: library, profile: profile, engine: engine)
    }

    /// An explainer's transcript: one entry per kept beat, in beat order, with the board as each beat leaves it.
    public static func explainer(data: Data, file: String, library: MGSolidLibrary = .builtIn, profile: MGSolidProfile = .standard,
                                 engine: MGJSON? = MGEngine.identity) -> MGTranscript {
        // The gate is the check itself; its suggestions only matter when it refuses, so the printed refusal is the full
        // report (`MGExplainerReport.check`), exactly what `marty-solid check` prints.
        let gate = MGExplainerReport.check(data: data, library: library, profile: profile, engine: engine, suggest: false)
        guard gate.ok, case .success(let doc) = MGExplainer.parse(data: data) else {
            return MGTranscript(ok: false, json: MGExplainerReport.check(data: data, library: library, profile: profile, engine: engine).json)
        }
        let clock = MGManualClock()
        var s = MGExplainerSession(pacing: .speech, clock: clock, library: library)
        guard case .success = s.load(doc) else { return MGTranscript(ok: false, json: gate.json) }
        var beats: [MGJSON] = []
        var k = 0
        // Present each beat in turn, as the beat stills are made (`MGExplainerFrame.beatPanes`): the board settles, the
        // caption is due, and the beat's view is the one the learner sees.
        while k < MGExplainerLimits.beats, let beat = s.presented.beat, beat == k {
            clock.advance(by: s.motionRemaining)
            _ = s.tick()
            if let info = s.beats[k] {
                let shown = s.solid.map { d in s.displayedAnnotations(beat: k).compactMap { onScreen($0, d) } } ?? []
                beats.append(entry(beat: k + 1, caption: s.captions[k] ?? s.caption ?? info.say, note: info.unchecked, onScreen: shown,
                                   tables: tables(s.state?.scene, notes: s.notes), highlight: info.highlight ?? []))
            }
            _ = s.lineEnded(k)
            k += 1
        }
        return MGTranscript(ok: true, json: document(file: file, title: s.title, beats: beats))
    }

    /// An assembly's transcript: one entry per step (a step is a beat of the story), with the annotations the step shows
    /// (`MGSolidDocument.visibleAnnotations(step:)`). An assembly has no board, so `tables` is empty.
    public static func assembly(data: Data, file: String, library: MGSolidLibrary = .builtIn, profile: MGSolidProfile = .standard,
                                engine: MGJSON? = MGEngine.identity) -> MGTranscript {
        let report = MGSolidReport.check(data: data, library: library, profile: profile, engine: engine)
        guard report.ok, case .success(let d) = MGSolidParser.document(data: data, library: library, profile: profile) else {
            return MGTranscript(ok: false, json: report.json)
        }
        let beats = d.steps.indices.map { i in
            entry(beat: i + 1, caption: d.steps[i].say, note: d.steps[i].unchecked,
                  onScreen: d.visibleAnnotations(step: i).compactMap { onScreen($0, d) }, tables: .object([:]), highlight: d.steps[i].highlight)
        }
        return MGTranscript(ok: true, json: document(file: file, title: d.title, beats: beats))
    }

    // MARK: Pieces

    static func document(file: String, title: String?, beats: [MGJSON]) -> MGJSON {
        .object(["format": .string(format), "version": .number(Double(version)), "explainer": .string(file),
                 "title": title.map(MGJSON.string) ?? .null, "about": .string(about), "beats": .array(beats)])
    }

    static func entry(beat: Int, caption: String, note: String?, onScreen: [MGJSON], tables: MGJSON, highlight: [String]) -> MGJSON {
        var o: [String: MGJSON] = ["beat": .number(Double(beat)), "caption": .string(caption), "onScreen": .array(onScreen),
                                   "tables": tables, "highlight": .array(highlight.map(MGJSON.string))]
        // The author's reason when the caption's words are not engine facts (`unchecked`), shown as "Not checked".
        if let note { o["captionNote"] = .string(note) }
        return .object(o)
    }

    /// One shown annotation as words: `{"id", "kind", "text", "note"?}` with the filled text (placeholders replaced by
    /// the engine's values) and the author's `unchecked` reason as `note`. An arrow without text has no words and is left
    /// out.
    static func onScreen(_ id: String, _ d: MGSolidDocument) -> MGJSON? {
        func item(_ kind: String, _ text: String, _ note: String?) -> MGJSON? {
            guard !text.isEmpty else { return nil }
            var o: [String: MGJSON] = ["id": .string(id), "kind": .string(kind), "text": .string(text)]
            if let note { o["note"] = .string(note) }
            return .object(o)
        }
        let a = d.annotations
        if let l = a.labels.first(where: { $0.id == id }) { return item("label", l.text, l.unchecked) }
        if let r = a.arrows.first(where: { $0.id == id }) { return item("arrow", r.text ?? "", r.unchecked) }
        if let m = a.dimensions.first(where: { $0.id == id }) { return item("dimension", m.text, nil) }
        return nil
    }

    /// Every board table with a data row (`MGItem.isEmptyTable` is false), keyed by id: `{"header", "rows", "source"?,
    /// "note"?}`. `header` is the first row when the table sets `header`, else empty. The table's note gives `source`
    /// (a `basis` note) or `note` (an `unchecked` note).
    static func tables(_ scene: MGScene?, notes: [String: MGExplainer.Note]) -> MGJSON {
        var out: [String: MGJSON] = [:]
        for item in scene?.items ?? [] where item.kind == .table && !item.isEmptyTable {
            let rows = item.n("rows", 1), cols = item.n("cols", 1)
            guard rows.isFinite, cols.isFinite, rows >= 1, cols >= 1, rows.rounded() == rows, cols.rounded() == cols,
                  Double(item.list.count) == rows * cols else { continue }
            let c = Int(cols)
            let grid = stride(from: 0, to: item.list.count, by: c).map { Array(item.list[$0..<($0 + c)]) }
            let header = item.has("header") ? grid[0] : []
            let body = item.has("header") ? Array(grid.dropFirst()) : grid
            var t: [String: MGJSON] = ["header": .array(header.map(MGJSON.string)),
                                       "rows": .array(body.map { .array($0.map(MGJSON.string)) })]
            if let note = notes[item.id] { t[note.kind == .basis ? "source" : "note"] = .string(note.text) }
            out[item.id] = .object(t)
        }
        return .object(out)
    }
}
