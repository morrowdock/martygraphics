// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import MartyGraphics

/// The presented-only legend for 3D annotations: whenever the beats choose their labels (some beat has `annotate`, or
/// more than 12 annotations), an annotation claim counts only once a presented beat displayed it, frozen at
/// presentation, kept after later beats and across restore. The counted set always equals the set the overlay
/// displayed. The show-all rule (no list, 12 or fewer) counts every annotation, as before.
final class ExplainerAnnotationLegendTests: ExplainerTestCase {
    /// Gears with `n` fact-bearing labels on the small gear (`l1` … `ln`).
    static func solid(labels n: Int) -> String {
        let labels = (1...n).map { #"{"id":"l\#($0)","at":"p","text":"Teeth {p.teeth}"}"# }.joined(separator: ",")
        return String(XFix.gears.dropLast()) + #","annotations":{"labels":[\#(labels)]}}"#
    }
    static func list(_ r: ClosedRange<Int>) -> String { r.map { #""l\#($0)""# }.joined(separator: ",") }

    func annotationClaims(_ s: MGExplainerSession) -> [String] { s.claims.filter { $0.kind == .annotation }.map(\.id) }

    /// 13 fact-bearing labels and no `annotate` list: no beat shows any, so none counts.
    func testNeverShownAnnotationsMakeNoClaim() throws {
        let s = try XFix.load(XFix.doc(solid: Self.solid(labels: 13), beats: #"[{"say":"One."},{"say":"Two.","view":{"orbit":30}}]"#))
        XCTAssertEqual(s.solid?.visibleAnnotations(step: nil), [])
        XCTAssertEqual(annotationClaims(s), [])
        XCTAssertFalse(s.legend.text.contains("14"), s.legend.text)
        // The motion claims stay (two gears): only the annotations left the count.
        XCTAssertEqual(s.claims.filter { $0.kind == .motion }.count, 2)
        let r = MGExplainerReport.check(data: Data(XFix.doc(solid: Self.solid(labels: 13), beats: #"[{"say":"One."}]"#).utf8), engine: nil)
        XCTAssertEqual(r.json["legend"]?["text"], .string(s.legend.text))
    }

    /// Beat 1 shows l1–l3: only they count while it is presented; beat 2 adds l4–l5; beat 3 lists nothing and keeps all
    /// five (frozen, never removed).
    func testShownBeatsCountAndLaterBeatsKeepTheClaims() throws {
        let doc = XFix.doc(solid: Self.solid(labels: 14), beats: """
            [{"say":"One.","view":{"annotate":[\(Self.list(1...3))]}},{"say":"Two.","view":{"annotate":[\(Self.list(4...5))]}},{"say":"Three."}]
            """)
        let clock = MGManualClock()
        var s = try XFix.load(doc, pacing: .speech, clock: clock)
        var seen: [[String]] = []
        var k = 0
        while let beat = s.presented.beat, beat == k {
            clock.advance(by: s.motionRemaining)
            _ = s.tick()
            seen.append(annotationClaims(s))
            _ = s.lineEnded(k)
            k += 1
        }
        XCTAssertEqual(seen, [["l1", "l2", "l3"], ["l1", "l2", "l3", "l4", "l5"], ["l1", "l2", "l3", "l4", "l5"]])
        // Every beat presented at once (`finishNow`, the check report): the same five.
        XCTAssertEqual(annotationClaims(try XFix.load(doc)), ["l1", "l2", "l3", "l4", "l5"])
    }

    /// A snapshot keeps the record; restore checks it against the presented beats.
    func testRestoreKeepsAndChecksTheRecord() throws {
        let doc = XFix.doc(solid: Self.solid(labels: 13), beats: """
            [{"say":"One.","view":{"annotate":[\(Self.list(1...2))]}},{"say":"Two.","view":{"annotate":["l13"]}}]
            """)
        let clock = MGManualClock()
        var s = try XFix.load(doc, pacing: .speech, clock: clock)
        clock.advance(by: s.motionRemaining); _ = s.tick()
        let snap = s.snapshot()
        XCTAssertEqual(snap["shownAnnotations"], .array([.object(["id": .string("l1"), "tier": .string("solved")]),
                                                         .object(["id": .string("l2"), "tier": .string("solved")])]))
        func restore(_ v: MGJSON) -> Result<MGExplainerSession, MGExplainerIssue> {
            MGExplainerSession.restore(data: Data(v.canonicalString.utf8), pacing: .speech, clock: MGManualClock())
        }
        let back = try restore(snap).get()
        XCTAssertEqual(annotationClaims(back), ["l1", "l2"])
        XCTAssertEqual(back.legend, s.legend)
        func with(_ value: MGJSON?) -> MGJSON {
            guard case .object(var o) = snap else { return snap }
            o["shownAnnotations"] = value
            return .object(o)
        }
        // Without the field (an older snapshot), the record is rebuilt from the presented beats.
        XCTAssertEqual(annotationClaims(try restore(with(nil)).get()), ["l1", "l2"])
        // A stream may have displayed more before its solid became stepped, so an extra annotation of the solid at its
        // claim's tier is kept.
        XCTAssertEqual(annotationClaims(try restore(with(.array([.object(["id": .string("l1"), "tier": .string("solved")]),
                                                                  .object(["id": .string("l2"), "tier": .string("solved")]),
                                                                  .object(["id": .string("l13"), "tier": .string("solved")])]))).get()),
                       ["l1", "l2", "l13"])
        // A missing displayed one, an id that is no annotation, a wrong tier, a duplicate or extra keys are refused.
        let bad: [MGJSON] = [
            .array([.object(["id": .string("l1"), "tier": .string("solved")])]),
            .array([.object(["id": .string("l1"), "tier": .string("solved")]), .object(["id": .string("l2"), "tier": .string("solved")]),
                    .object(["id": .string("zz"), "tier": .string("solved")])]),
            .array([.object(["id": .string("l1"), "tier": .string("described")]), .object(["id": .string("l2"), "tier": .string("solved")])]),
            .array([.object(["id": .string("l1"), "tier": .string("solved")]), .object(["id": .string("l1"), "tier": .string("solved")])]),
            .array([.object(["id": .string("l1"), "tier": .string("solved"), "x": .number(1)]), .object(["id": .string("l2"), "tier": .string("solved")])]),
            .string("l1"),
            .array(Array(repeating: .object(["id": .string("l1"), "tier": .string("solved")]), count: MGShownAnnotations.maxCount + 1)),
        ]
        for v in bad {
            guard case .failure(let e) = restore(with(v)) else { XCTFail("accepted \(v.canonicalString.prefix(80))"); continue }
            XCTAssertEqual(e.reason, "snapshot.shown")
        }
    }

    /// The overlay's list for each presented beat (what the renderer and the SwiftUI pane draw).
    func displayed(_ s: MGExplainerSession) -> [String] { s.presented.solid?.annotations ?? [] }

    /// 12 fact-bearing labels and a beat with `annotate: []`: the beats choose their labels, none is displayed, and only
    /// the motion claims count.
    func testEmptyListShowsAndCountsNothing() throws {
        let s = try XFix.load(XFix.doc(solid: Self.solid(labels: 12), beats: #"[{"say":"One.","view":{"annotate":[]}},{"say":"Two."}]"#))
        XCTAssertTrue(s.solid?.annotations.stepped ?? false)
        XCTAssertEqual(displayed(s), [])
        XCTAssertEqual(s.displayedAnnotations(beat: 0), [])
        XCTAssertEqual(s.displayedAnnotations(beat: 1), [])
        XCTAssertEqual(annotationClaims(s), [])
        XCTAssertEqual(s.claims.map(\.kind).filter { $0 == .motion }.count, s.claims.count - s.claims.filter { $0.kind != .motion }.count)
        XCTAssertEqual(s.claims.filter { $0.kind == .annotation }.count, 0)
        XCTAssertFalse(s.legend.text.contains("13"), s.legend.text)
    }

    /// Listed and unlisted beats mixed (12 labels): the counted set equals the union of what each presented beat
    /// displayed, beat by beat, through the one function the overlay uses.
    func testMixedBeatsCountExactlyWhatWasDisplayed() throws {
        let doc = XFix.doc(solid: Self.solid(labels: 12), beats: """
            [{"say":"One.","view":{"annotate":["l1","l2"]}},{"say":"Two."},{"say":"Three.","view":{"orbit":30}},{"say":"Four.","view":{"annotate":["l5"]}},{"say":"Five."}]
            """)
        let clock = MGManualClock()
        var s = try XFix.load(doc, pacing: .speech, clock: clock)
        var union: [String] = [], counted: [[String]] = []
        var k = 0
        while let beat = s.presented.beat, beat == k {
            clock.advance(by: s.motionRemaining); _ = s.tick()
            XCTAssertEqual(displayed(s), s.displayedAnnotations(beat: k), "beat \(k + 1)")
            for id in displayed(s) where !union.contains(id) { union.append(id) }
            counted.append(annotationClaims(s))
            XCTAssertEqual(Set(annotationClaims(s)), Set(union), "beat \(k + 1)")
            _ = s.lineEnded(k); k += 1
        }
        XCTAssertEqual(counted, [["l1", "l2"], ["l1", "l2"], ["l1", "l2"], ["l1", "l2", "l5"], ["l1", "l2", "l5"]])
    }

    /// A stream does not know its later beats: beats shown with the show-all rule display every label; when a later
    /// beat brings `annotate`, the solid becomes stepped and the labels already displayed keep counting. The counted set
    /// equals everything the presented views displayed over the session.
    func testStreamedFlipKeepsWhatWasDisplayed() throws {
        let lines = [XFix.header(), #"{"solid":\#(Self.solid(labels: 3))}"#, #"{"say":"One."}"#, #"{"say":"Two."}"#,
                     #"{"view":{"annotate":["l1"]}}"#, #"{"say":"Three."}"#]
        var s = MGExplainerSession(pacing: .immediate, clock: MGManualClock())
        var union = Set<String>()
        for l in lines { _ = s.feed(l + "\n"); if s.presented.beat != nil { union.formUnion(displayed(s)) } }
        _ = s.endStream(); union.formUnion(displayed(s))
        XCTAssertTrue(s.solid?.annotations.stepped ?? false)
        XCTAssertEqual(Set(annotationClaims(s)), union)
        XCTAssertTrue(union.contains("l1"))
    }

    /// A stepped explainer with 12 or fewer annotations restores its record.
    func testSteppedTwelveRestores() throws {
        let doc = XFix.doc(solid: Self.solid(labels: 12), beats: #"[{"say":"One.","view":{"annotate":["l3"]}},{"say":"Two.","view":{"annotate":[]}}]"#)
        let s = try XFix.load(doc)
        XCTAssertEqual(annotationClaims(s), ["l3"])
        let snap = s.snapshot()
        XCTAssertEqual(snap["shownAnnotations"], .array([.object(["id": .string("l3"), "tier": .string("solved")])]))
        let back = try MGExplainerSession.restore(data: Data(snap.canonicalString.utf8), pacing: .immediate, clock: MGManualClock()).get()
        XCTAssertEqual(annotationClaims(back), ["l3"])
        XCTAssertEqual(back.legend, s.legend)
    }

    /// The sole beat with a list is refused at presentation (a host change breaks its 2D check). Document: 12 labels on
    /// the solid, a rotate board; beat 2 lists `l1` and checks `theta == 0`.
    static let dropDoc = XFix.doc(board: XFix.rotate, solid: solid(labels: 12), beats: """
        [{"say":"One."},{"say":"Two.","view":{"annotate":["l1"]},"check":[{"value":"theta","eq":0}]},{"say":"Three."}]
        """)

    /// Breaks beat 2's check and moves on, so beat 2 is refused when it would be presented.
    func dropBeatTwo(_ s: inout MGExplainerSession, _ clock: MGManualClock) throws {
        _ = try s.apply([XFix.json(#"{"op":"params","params":{"angle":30}}"#)]).get()
        _ = s.lineEnded(0)
        clock.advance(by: .seconds(20)); _ = s.tick()
    }

    /// Timing 1: the snapshot is taken after the refusal. The live session stays stepped (it was loaded with a list),
    /// displays and counts no label; the untouched snapshot restores to the same.
    func testModeSurvivesRestoreAfterTheListedBeatIsRefused() throws {
        let clock = MGManualClock()
        var s = try XFix.load(Self.dropDoc, pacing: .speech, clock: clock)
        try dropBeatTwo(&s, clock)
        XCTAssertEqual(s.beats[1]?.dropped, true)
        XCTAssertTrue(s.solid?.annotations.stepped ?? false)
        XCTAssertEqual(displayed(s), [])
        XCTAssertEqual(annotationClaims(s), [])
        let snap = s.snapshot()
        XCTAssertEqual(snap["chooseLabels"], .bool(true))
        let back = try MGExplainerSession.restore(snap, pacing: .speech, clock: clock).get()
        XCTAssertTrue(back.solid?.annotations.stepped ?? false)
        XCTAssertEqual(displayed(back), displayed(s))
        XCTAssertEqual(annotationClaims(back), annotationClaims(s))
        XCTAssertEqual(back.legend, s.legend)
    }

    /// Timing 2: restore before the refusal, then continue. The restored session keeps the mode, so after the refusal
    /// it displays and counts exactly what the live session does.
    func testModeSurvivesRestoreBeforeTheListedBeatIsRefused() throws {
        let clock = MGManualClock()
        var live = try XFix.load(Self.dropDoc, pacing: .speech, clock: clock)
        var back = try MGExplainerSession.restore(live.snapshot(), pacing: .speech, clock: clock).get()
        XCTAssertTrue(back.beatsChooseLabels)
        try dropBeatTwo(&live, clock)
        try dropBeatTwo(&back, clock)
        XCTAssertEqual(back.beats[1]?.dropped, true)
        XCTAssertTrue(back.solid?.annotations.stepped ?? false)
        XCTAssertEqual(displayed(back), displayed(live))
        XCTAssertEqual(displayed(back), [])
        XCTAssertEqual(annotationClaims(back), annotationClaims(live))
        XCTAssertEqual(annotationClaims(back), [])
    }

    /// Timing 3: an older snapshot without `chooseLabels`, restored before beat 2 and continued past the refusal. The
    /// mode is derived from every beat the snapshot knows (beat 2's list is among them) and kept, so the restored
    /// session displays and counts what the live session does.
    func testOldSnapshotDerivesTheModeFromEveryKnownBeat() throws {
        let clock = MGManualClock()
        var live = try XFix.load(Self.dropDoc, pacing: .speech, clock: clock)
        guard case .object(var o) = live.snapshot() else { return XCTFail("snapshot") }
        o.removeValue(forKey: "chooseLabels")
        var back = try MGExplainerSession.restore(.object(o), pacing: .speech, clock: clock).get()
        XCTAssertTrue(back.beatsChooseLabels)
        try dropBeatTwo(&live, clock)
        try dropBeatTwo(&back, clock)
        XCTAssertEqual(back.beats[1]?.dropped, true)
        XCTAssertTrue(back.beatsChooseLabels)
        XCTAssertEqual(displayed(back), displayed(live))
        XCTAssertEqual(displayed(back), [])
        XCTAssertEqual(annotationClaims(back), annotationClaims(live))
        XCTAssertEqual(annotationClaims(back), [])
        // A document without any list derives the show-all mode.
        let plain = try XFix.load(XFix.doc(solid: Self.solid(labels: 3), beats: #"[{"say":"One."}]"#))
        XCTAssertFalse(try MGExplainerSession.restore(plain.snapshot(), pacing: .immediate, clock: MGManualClock()).get().beatsChooseLabels)
    }

    /// `chooseLabels` is `true` or absent: any other value, `false` included, is `snapshot.labels`. A document without
    /// any list writes none.
    func testChooseLabelsIsTrueOrAbsent() throws {
        let s = try XFix.load(Self.dropDoc, pacing: .speech, clock: MGManualClock())
        guard case .object(var o) = s.snapshot() else { return XCTFail("snapshot") }
        for bad: MGJSON in [.string("yes"), .bool(false), .number(1), .null] {
            o["chooseLabels"] = bad
            guard case .failure(let e) = MGExplainerSession.restore(.object(o), pacing: .speech, clock: MGManualClock()) else {
                XCTFail("accepted \(bad.canonicalString)"); continue
            }
            XCTAssertEqual(e.reason, "snapshot.labels")
        }
        let plain = try XFix.load(XFix.doc(solid: Self.solid(labels: 3), beats: #"[{"say":"One."}]"#))
        XCTAssertNil(plain.snapshot()["chooseLabels"])
    }

    /// A stream takes the mode when it accepts a view with `annotate` and keeps it after that beat is refused (as after
    /// `load`); its snapshot saves it.
    func testStreamKeepsTheModeAfterItsListedBeatIsRefused() throws {
        let lines = [XFix.header(), #"{"solid":\#(Self.solid(labels: 3))}"#, #"{"say":"One."}"#, #"{"say":"Two."}"#,
                     #"{"view":{"annotate":["l1"]}}"#, #"{"check":{"value":"p.speed","eq":5}}"#, #"{"say":"Three."}"#]
        let (s, ev) = XFix.stream(lines)
        XCTAssertEqual(XFix.reasons(ev), ["check.failed.p.speed"])
        XCTAssertTrue(s.beatsChooseLabels)
        XCTAssertTrue(s.solid?.annotations.stepped ?? false)
        XCTAssertEqual(s.snapshot()["chooseLabels"], .bool(true))
        let back = try MGExplainerSession.restore(s.snapshot(), pacing: .immediate, clock: MGManualClock()).get()
        XCTAssertTrue(back.solid?.annotations.stepped ?? false)
        XCTAssertEqual(annotationClaims(back), annotationClaims(s))
    }

    /// The mode belongs to one explainer: a new header in the same session starts from no mode, so a later explainer
    /// without lists shows and counts every label, exactly like the same stream in a fresh session. Both a refused and
    /// an accepted listed beat in the replaced explainer are covered.
    func testNewExplainerDoesNotInheritTheMode() throws {
        let solid = #"{"solid":\#(Self.solid(labels: 3))}"#
        let second = [XFix.header(), solid, #"{"say":"Plain."}"#]
        let (fresh, _) = XFix.stream(second)
        XCTAssertFalse(fresh.beatsChooseLabels)
        XCTAssertEqual(displayed(fresh), ["l1", "l2", "l3"])
        for first in [[#"{"say":"A.","view":{"annotate":[]}}"#, #"{"check":{"value":"p.speed","eq":5}}"#],
                      [#"{"say":"A.","view":{"annotate":[]}}"#]] {
            var s = MGExplainerSession(pacing: .immediate, clock: MGManualClock())
            for l in [XFix.header(), solid] + first + [#"{"end":true}"#] + second { _ = s.feed(l + "\n") }
            _ = s.endStream()
            s.finishNow()
            XCTAssertFalse(s.beatsChooseLabels, "\(first)")
            XCTAssertEqual(displayed(s), displayed(fresh), "\(first)")
            XCTAssertEqual(annotationClaims(s), annotationClaims(fresh), "\(first)")
        }
    }

    /// `chooseLabels` is checked in every snapshot, also one without a solid.
    func testChooseLabelsIsCheckedWithoutASolid() throws {
        let s = try XFix.load(XFix.doc(board: #"{"v":1,"items":[{"id":"cap","k":"text","at":[6,7],"text":"Hello"}]}"#, beats: #"[{"say":"One."}]"#))
        guard case .object(var o) = s.snapshot() else { return XCTFail("snapshot") }
        XCTAssertNil(o["chooseLabels"])
        for bad: MGJSON in [.bool(false), .string("yes"), .number(1), .null, .array([]), .object([:])] {
            o["chooseLabels"] = bad
            guard case .failure(let e) = MGExplainerSession.restore(.object(o), pacing: .immediate, clock: MGManualClock()) else {
                XCTFail("accepted \(bad.canonicalString)"); continue
            }
            XCTAssertEqual(e.reason, "snapshot.labels")
        }
    }

    /// The show-all rule (no list, at most 12): every annotation is displayed and claims, as before, and snapshots carry
    /// no `shownAnnotations`.
    func testTwelveOrFewerAreUnchanged() throws {
        let s = try XFix.load(XFix.doc(solid: Self.solid(labels: 12), beats: #"[{"say":"One."}]"#))
        XCTAssertEqual(annotationClaims(s), (1...12).map { "l\($0)" })
        XCTAssertEqual(displayed(s), (1...12).map { "l\($0)" })
        XCTAssertNil(s.snapshot()["shownAnnotations"])
        // A `shownAnnotations` in such a snapshot is refused.
        guard case .object(var o) = s.snapshot() else { return XCTFail("snapshot") }
        o["shownAnnotations"] = .array([])
        guard case .failure(let e) = MGExplainerSession.restore(data: Data(MGJSON.object(o).canonicalString.utf8), pacing: .speech,
                                                               clock: MGManualClock()) else { return XCTFail("accepted") }
        XCTAssertEqual(e.reason, "snapshot.shown")
    }
}
