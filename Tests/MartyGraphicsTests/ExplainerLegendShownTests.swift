// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import MartyGraphics

/// The legend is presented-only: it counts the claims of exactly the 2D items of the states the learner was shown (the
/// board, each set-up command, each presented beat, each accepted host or learner change), not only the final board's,
/// and the captions and checks of presented beats only. Nothing waiting, open, refused or replayed counts, and a
/// restored session gives the same legend.
final class ExplainerLegendShownTests: ExplainerTestCase {
    static let notes = #"{"t":{"basis":"Survey data"},"u":{"basis":"Survey data"},"v":{"basis":"Survey data"}}"#
    static func table(_ id: String) -> String {
        #"{"id":"\#(id)","k":"table","at":[6,4],"header":true,"cells":[["Planet","km"],["Earth",12756]]}"#
    }
    static func add(_ item: String) -> String { #"{"op":"add","item":\#(item)}"# }
    static func remove(_ id: String) -> String { #"{"op":"remove","id":"\#(id)"}"# }

    /// The reported case: a noted table that beat 1 adds and beat 2 removes.
    static let addThenRemove = XFix.doc(notes: #"{"t":{"basis":"Survey data"}}"#, board: XFix.rotate, beats: """
        [{"say":"Here are the sizes.","ops":[\(add(table("t")))]},
         {"say":"Turned {theta}.","ops":[\(remove("t")),{"op":"params","params":{"angle":30}}]}]
        """)

    func testItemThatALaterBeatRemovesIsCounted() throws {
        let s = try XFix.load(Self.addThenRemove)
        XCTAssertNil(s.state?.scene.item("t"), "the final board has no table")
        XCTAssertEqual(s.claims.map(\.id), ["board.template", "item.t", "beat.2"])
        XCTAssertEqual(s.claims.first { $0.id == "item.t" }?.badge, "Data as given")
        XCTAssertEqual(s.legend.text, "Solved 2 · Given 1")
        XCTAssertEqual(s.legend.given, 1)
        // The check report (what `marty-solid check` prints) reads the same legend.
        let report = MGExplainerReport.check(data: Data(Self.addThenRemove.utf8))
        XCTAssertTrue(report.ok, report.text)
        XCTAssertEqual(report.json["legend"]?["text"], .string("Solved 2 · Given 1"))
        XCTAssertEqual(report.json["legend"]?["groups"]?["given"], .number(1))
        guard case .array(let items)? = report.json["views"]?["board"]?["items"] else { return XCTFail("board items") }
        XCTAssertFalse(items.contains(.string("t")), "the board view lists the final items; the legend lists the shown ones")
    }

    func testLiveSessionCountsTheItemOnceItsBeatIsShown() throws {
        let clock = MGManualClock()
        var s = try XFix.load(Self.addThenRemove, pacing: .speech, clock: clock)
        XCTAssertEqual(s.presented.beat, 0)
        XCTAssertEqual(s.legend.text, "Solved 1 · Given 1", "beat 1 shows the table; beat 2's caption waits")
        // The render path: a copy that finishes now has the legend of the whole explainer.
        var whole = s
        _ = whole.finishNow()
        XCTAssertEqual(whole.legend, try XFix.load(Self.addThenRemove).legend)
        _ = s.lineEnded(0)
        clock.advance(by: s.motionRemaining)
        _ = s.tick()
        XCTAssertEqual(s.presented.beat, 1)
        XCTAssertNil(s.state?.scene.item("t"))
        XCTAssertEqual(s.legend.text, "Solved 2 · Given 1", "the table stays counted after beat 2 removes it")
        XCTAssertEqual(s.legend, try XFix.load(Self.addThenRemove).legend, "live and immediate give one legend")
    }

    /// An item that no presented state showed has no claim: one that a beat adds and removes again, and one that only
    /// a refused beat adds.
    func testItemNoBeatShowedIsNotCounted() {
        let (s, ev) = XFix.stream([XFix.header(#","notes":\#(Self.notes)"#), #"{"board":\#(XFix.rotate)}"#,
                                   #"{"say":"One."}"#, Self.add(Self.table("t")),
                                   #"{"say":"Two."}"#, Self.add(Self.table("u")), Self.remove("u"),
                                   #"{"say":"Three."}"#, Self.remove("t"), Self.add(Self.table("v")),
                                   #"{"check":{"value":"theta","eq":90}}"#])
        XCTAssertEqual(XFix.reasons(ev), ["check.theta"], "beat 3 is refused")
        XCTAssertNotNil(s.state?.scene.item("t"), "the refused beat's remove is undone")
        XCTAssertNil(s.state?.scene.item("v"))
        XCTAssertEqual(s.claims.map(\.id), ["board.template", "item.t"])
        XCTAssertEqual(s.legend.text, "Solved 1 · Given 1")
        XCTAssertTrue(s.recordedShown.ids.contains("t"))
        XCTAssertFalse(s.recordedShown.ids.contains("u"), "only the middle of beat 2 had it")
        XCTAssertFalse(s.recordedShown.ids.contains("v"), "only the refused beat had it")
    }

    /// A refused beat, a refused host batch and a refused learner change add no claim and leave the record unchanged.
    func testRefusalsLeaveTheRecordUnchanged() throws {
        var (s, _) = XFix.stream([XFix.header(#","notes":\#(Self.notes)"#), #"{"board":\#(XFix.rotate)}"#,
                                  #"{"op":"bind","control":{"id":"angle","k":"slider","param":"angle","min":0,"max":360,"step":5,"label":"Angle"}}"#,
                                  #"{"say":"One."}"#, Self.add(Self.table("t"))], end: false)
        _ = s.feed(#"{"say":"Two."}"# + "\n")
        let record = s.recordedShown, legend = s.legend
        XCTAssertTrue(record.ids.contains("t"))
        // A beat that adds a noted item and then fails its check.
        let ev = s.feed([Self.add(Self.table("v")), Self.remove("t"), #"{"check":{"value":"theta","eq":90}}"#, #"{"say":"Three."}"#]
            .joined(separator: "\n") + "\n")
        XCTAssertEqual(XFix.reasons(ev), ["check.theta"])
        XCTAssertEqual(s.recordedShown, record)
        XCTAssertEqual(s.legend, legend)
        // A host batch with a typed number on an item without a note is refused whole.
        let host = s.apply([XFix.json(Self.add(#"{"id":"w","k":"text","at":[1,1],"text":"7 km"}"#))])
        XCTAssertEqual(host.failureIssue?.reason, "text.number.item.w")
        XCTAssertEqual(s.recordedShown, record)
        XCTAssertEqual(s.legend, legend)
        // A learner value outside the control's range is refused.
        XCTAssertNotNil(s.control("angle", 9999).failureIssue)
        XCTAssertEqual(s.recordedShown, record)
        XCTAssertEqual(s.legend, legend)
    }

    /// Restore mid-lesson (before and after the beat that removes the item) gives the live session's legend, and a
    /// restored session that goes on gives the legend of a fresh run.
    func testRestoreMidLessonGivesTheSameLegend() throws {
        let doc = XFix.doc(notes: Self.notes, board: XFix.rotate, beats: """
            [{"say":"One.","ops":[\(Self.add(Self.table("t")))]},
             {"say":"Two {theta}.","ops":[\(Self.remove("t")),\(Self.add(Self.table("u"))),{"op":"params","params":{"angle":30}}]},
             {"say":"Three.","ops":[\(Self.remove("u"))]}]
            """)
        let clock = MGManualClock()
        var s = try XFix.load(doc, pacing: .speech, clock: clock)
        func restored(_ s: MGExplainerSession) throws -> MGExplainerSession {
            let back = MGJSON(any: try JSONSerialization.jsonObject(with: Data(s.snapshot().canonicalString.utf8)))!
            switch MGExplainerSession.restore(back, pacing: .speech, clock: clock) {
            case .success(let r): return r
            case .failure(let issue): XCTFail("\(issue)"); throw issue
            }
        }
        let fresh = try XFix.load(doc).legend
        for beat in 0..<3 {
            XCTAssertEqual(s.presented.beat, beat)
            var r = try restored(s)
            XCTAssertEqual(r.legend, s.legend, "restore at beat \(beat + 1)")
            XCTAssertEqual(r.recordedShown, s.recordedShown, "restore at beat \(beat + 1)")
            // The restored session goes on to the end: the same legend as the live one and as a fresh run.
            var live = s
            _ = live.finishNow(); _ = r.finishNow()
            XCTAssertEqual(r.legend, live.legend)
            XCTAssertEqual(r.legend, fresh)
            _ = s.lineEnded(beat)
            clock.advance(by: s.motionRemaining)
            _ = s.tick()
        }
        XCTAssertEqual(s.legend.text, "Solved 2 · Given 2", "board.template, beat 2's caption, t and u")
        XCTAssertEqual(s.legend, fresh)
        XCTAssertNil(s.state?.scene.item("t")); XCTAssertNil(s.state?.scene.item("u"))
    }

    /// Several items added and removed in several beats: claims in first-shown order (never id or dictionary order),
    /// each with the lowest tier it showed, the same in every run. `MartySolidCLITests` runs the same document in fresh
    /// processes.
    func testSeveralItemsInFirstShownOrder() throws {
        let doc = XFix.doc(notes: #"{"zz":{"basis":"Survey data"},"mm":{"unchecked":"from memory"}}"#,
                           board: #"{"v":1,"items":[{"id":"keep","k":"text","at":[1,7],"text":"Gears"},{"id":"bb","k":"text","at":[1,1],"text":"Teeth {p.teeth}"}]}"#,
                           solid: XFix.gears, beats: """
            [{"say":"One.","ops":[\(Self.add(Self.table("zz")))]},
             {"say":"Two.","ops":[\(Self.add(Self.table("mm"))),\(Self.remove("bb"))]},
             {"say":"Three.","ops":[\(Self.remove("zz")),\(Self.add(#"{"id":"aa","k":"text","at":[1,2],"text":"Rate {w.speed}"}"#))]},
             {"say":"Four.","ops":[\(Self.remove("mm")),\(Self.remove("aa"))]}]
            """)
        let first = try XFix.load(doc)
        XCTAssertEqual(first.state?.scene.items.map(\.id), ["keep"])
        XCTAssertEqual(first.claims.map(\.id), ["p", "w", "item.bb", "item.zz", "item.mm", "item.aa"])
        XCTAssertEqual(first.claims.filter { $0.id.hasPrefix("item.") }.map(\.tier), [.solved, .built, .described, .solved])
        XCTAssertEqual(first.legend.text, "Solved 4 · Given 1 · Not checked 1")
        let report = MGExplainerReport.check(data: Data(doc.utf8)).text
        for _ in 0..<2 {
            XCTAssertEqual(try XFix.load(doc).legend, first.legend)
            XCTAssertEqual(MGExplainerReport.check(data: Data(doc.utf8)).text, report)
        }
    }

    // MARK: Presented-only (review of PR #35)

    /// Presents the next beat of a `.speech` session: the open line ends, the board settles.
    static func next(_ s: inout MGExplainerSession, _ clock: MGManualClock, _ beat: Int) -> [MGExplainerEvent] {
        var ev = s.lineEnded(beat)
        clock.advance(by: s.motionRemaining)
        ev += s.tick()
        return ev
    }

    /// A queued beat adds nothing: beat 2 adds the noted table, but only its presentation counts it.
    func testQueuedBeatIsNotCounted() throws {
        let doc = XFix.doc(notes: #"{"t":{"basis":"Survey data"}}"#, board: XFix.rotate, beats: """
            [{"say":"Look."},{"say":"Turned {theta}.","ops":[\(Self.add(Self.table("t"))),{"op":"params","params":{"angle":30}}]}]
            """)
        let clock = MGManualClock()
        var s = try XFix.load(doc, pacing: .speech, clock: clock)
        XCTAssertEqual(s.presented.beat, 0)
        XCTAssertNotNil(s.lesson.projected?.scene.item("t"), "the projection already has the table")
        XCTAssertEqual(s.claims.map(\.id), ["board.template"])
        XCTAssertEqual(s.legend.text, "Solved 1")
        _ = Self.next(&s, clock, 0)
        XCTAssertEqual(s.presented.beat, 1)
        XCTAssertEqual(s.claims.map(\.id), ["board.template", "item.t", "beat.2"])
        XCTAssertEqual(s.legend.text, "Solved 2 · Given 1")
    }

    /// Paused before any beat: no beat is presented, so no beat caption or beat item counts; resume presents it.
    func testPausedBeforeAnyBeat() {
        let clock = MGManualClock()
        var s = MGExplainerSession(pacing: .speech, clock: clock)
        s.pause()
        _ = s.feed([XFix.header(#","notes":{"t":{"basis":"Survey data"}}"#), #"{"board":\#(XFix.rotate)}"#,
                    #"{"say":"Turned {theta}."}"#, Self.add(Self.table("t")), #"{"op":"params","params":{"angle":30}}"#]
            .joined(separator: "\n") + "\n")
        _ = s.endStream()
        XCTAssertNil(s.presented.beat)
        XCTAssertEqual(s.claims.map(\.id), ["board.template"])
        XCTAssertEqual(s.legend.text, "Solved 1")
        _ = s.resume()
        XCTAssertEqual(s.presented.beat, 0)
        clock.advance(by: s.motionRemaining)
        _ = s.tick()
        XCTAssertEqual(s.legend.text, "Solved 2 · Given 1")
    }

    /// An open (streaming) beat is not presented: its `add` does not count while it is open, and an `add` then `remove`
    /// inside it never counts.
    func testOpenBeatIsNotCounted() {
        var s = MGExplainerSession(pacing: .immediate, clock: MGManualClock())
        _ = s.feed([XFix.header(#","notes":\#(Self.notes)"#), #"{"board":\#(XFix.rotate)}"#, #"{"say":"One."}"#, Self.add(Self.table("t"))]
            .joined(separator: "\n") + "\n")
        XCTAssertNil(s.presented.beat, "beat 1 is still open")
        XCTAssertNotNil(s.lesson.projected?.scene.item("t"))
        XCTAssertEqual(s.legend.text, "Solved 1")
        _ = s.feed(Self.remove("t") + "\n" + #"{"say":"Two."}"# + "\n")
        XCTAssertEqual(s.presented.beat, 0)
        XCTAssertEqual(s.legend.text, "Solved 1", "the table was never on a presented state")
        XCTAssertFalse(s.recordedShown.ids.contains("t"))
    }

    static let qBoard = #"{"v":1,"items":[{"id":"keep","k":"text","at":[1,7],"text":"Gears"},{"id":"q","k":"text","at":[1,1],"text":"A gear"}]}"#

    /// Repro A: the host removes `q`; queued beat 2 sets `q` to a fact text and beat 3 removes it. At presentation both
    /// commands are refused alone (`q` is gone), so `q` never shows the fact: the legend stays at the motion claims.
    func testRefusedCommandAtPresentationAddsNoClaim() throws {
        let doc = XFix.doc(board: Self.qBoard, solid: XFix.gears, beats: """
            [{"say":"One."},{"say":"Two.","ops":[{"op":"set","id":"q","key":"text","value":"Teeth {p.teeth}"}]},
             {"say":"Three.","ops":[\(Self.remove("q"))]}]
            """)
        let clock = MGManualClock()
        var s = try XFix.load(doc, pacing: .speech, clock: clock)
        XCTAssertEqual(s.legend.text, "Solved 2")
        XCTAssertNotNil(try? s.apply([XFix.json(Self.remove("q"))]).get())
        XCTAssertEqual(s.legend.text, "Solved 2")
        let ev = Self.next(&s, clock, 0)
        XCTAssertEqual(s.presented.beat, 1)
        XCTAssertTrue(XFix.reasons(ev).contains("patch.set.ref"), "\(XFix.reasons(ev))")
        XCTAssertEqual(s.legend.text, "Solved 2")
        _ = Self.next(&s, clock, 1)
        XCTAssertEqual(s.presented.beat, 2)
        XCTAssertFalse(s.claims.contains { $0.id == "item.q" })
        XCTAssertEqual(s.legend.text, "Solved 2")
    }

    /// Repro B: a host change gives `q` a fact text; that shown state counts, and stays counted after beat 3 removes
    /// `q`, also after a restore.
    func testHostChangeThatWasShownKeepsItsClaim() throws {
        let doc = XFix.doc(board: Self.qBoard, solid: XFix.gears, beats: """
            [{"say":"One."},{"say":"Two."},{"say":"Three.","ops":[\(Self.remove("q"))]}]
            """)
        let clock = MGManualClock()
        var s = try XFix.load(doc, pacing: .speech, clock: clock)
        XCTAssertEqual(s.legend.text, "Solved 2")
        XCTAssertNotNil(try? s.apply([XFix.json(#"{"op":"set","id":"q","key":"text","value":"Teeth {p.teeth}"}"#)]).get())
        XCTAssertEqual(s.claims.first { $0.id == "item.q" }?.tier, .solved)
        XCTAssertEqual(s.legend.text, "Solved 3")
        _ = Self.next(&s, clock, 0)
        _ = Self.next(&s, clock, 1)
        XCTAssertEqual(s.presented.beat, 2)
        XCTAssertNil(s.state?.scene.item("q"))
        XCTAssertEqual(s.legend.text, "Solved 3", "q showed the fact before beat 3 removed it")
        guard case .success(let r) = MGExplainerSession.restore(s.snapshot(), pacing: .speech, clock: clock) else { return XCTFail("restore") }
        XCTAssertEqual(r.legend, s.legend)
        XCTAssertEqual(r.recordedShown, s.recordedShown)
    }

    /// A tampered snapshot: a queued, future or unknown beat in `presented` is refused (`snapshot.presented`), and so is
    /// a `shown` record that names an item no shown state had, an unknown tier, a tier twice, extra keys, or misses an
    /// item shown now (`snapshot.shown`). An old snapshot without `shown` restores with the state shown now as the record.
    func testTamperedSnapshotIsRefused() throws {
        let doc = XFix.doc(notes: #"{"t":{"basis":"Survey data"}}"#, board: XFix.rotate, beats: """
            [{"say":"Look."},{"say":"Turned {theta}.","ops":[\(Self.add(Self.table("t"))),{"op":"params","params":{"angle":30}}]}]
            """)
        let s = try XFix.load(doc, pacing: .speech)
        let clean = s.snapshot().objectValue!
        guard case .success(let ok) = MGExplainerSession.restore(.object(clean), pacing: .speech) else { return XCTFail("clean") }
        XCTAssertEqual(ok.legend, s.legend)
        XCTAssertEqual(ok.legend.text, "Solved 1")
        func restore(_ edit: (inout [String: MGJSON]) -> Void) -> String? {
            var o = clean
            edit(&o)
            return MGExplainerSession.restore(.object(o), pacing: .speech).failureIssue?.reason
        }
        XCTAssertEqual(restore { $0["presented"] = .array([.number(0), .number(1)]) }, "snapshot.presented", "beat 2 is still queued")
        XCTAssertEqual(restore { $0["presented"] = .array([.number(0), .number(5)]) }, "snapshot.presented", "no such beat")
        XCTAssertEqual(restore { $0["presented"] = .array([.number(-1)]) }, "snapshot.presented")
        guard case .array(let shown)? = clean["shown"] else { return XCTFail("shown") }
        let tEntry: MGJSON = .object(["id": .string("t"), "tiers": .array([])])
        XCTAssertEqual(restore { $0["shown"] = .array(shown + [tEntry]) }, "snapshot.shown", "t was never on a shown state")
        XCTAssertEqual(restore { $0["shown"] = .array(Array(shown.dropFirst())) }, "snapshot.shown", "misses an item shown now")
        if case .object(var first)? = shown.first {
            first["tiers"] = .array([.string("checked")])
            XCTAssertEqual(restore { $0["shown"] = .array([.object(first)] + shown.dropFirst()) }, "snapshot.shown", "unknown tier")
            first["tiers"] = .array([.string("solved"), .string("solved")])
            XCTAssertEqual(restore { $0["shown"] = .array([.object(first)] + shown.dropFirst()) }, "snapshot.shown", "a tier twice")
            first["tiers"] = .array([.string("solved")])
            first["extra"] = .bool(true)
            XCTAssertEqual(restore { $0["shown"] = .array([.object(first)] + shown.dropFirst()) }, "snapshot.shown")
        } else { XCTFail("entry") }
        XCTAssertEqual(restore { $0["shown"] = .array(shown + shown) }, "snapshot.shown", "an id twice")
        XCTAssertEqual(restore { $0["shown"] = .string("x") }, "snapshot.shown")
        var old = clean
        old.removeValue(forKey: "shown")
        guard case .success(let r) = MGExplainerSession.restore(.object(old), pacing: .speech) else { return XCTFail("old") }
        XCTAssertEqual(r.legend, s.legend)
    }

    // MARK: Frozen claims (re-check of PR #35)

    /// A superseded `over` entry was never displayed: only the winning text counts.
    func testSupersededOverrideIsNotCounted() throws {
        let board = #"{"v":1,"template":"rotate2d","params":{"pts":[[2,1],[4,1],[2,3]],"angle":0},"over":[{"id":"ltheta","key":"text","value":"Teeth {p.teeth}"},{"id":"ltheta","key":"text","value":"Plain"}]}"#
        let s = try XFix.load(XFix.doc(board: board, solid: XFix.gears, beats: #"[{"say":"Look."}]"#))
        XCTAssertEqual(s.state?.scene.item("ltheta")?.text, "Plain")
        XCTAssertNil(s.claims.first { $0.id == "item.ltheta" }, "the superseded fact text was never shown")
        XCTAssertEqual(s.legend.text, "Solved 3", "2 motion claims and the template")
        // The winning override counts when it shows a fact.
        let shown = board.replacingOccurrences(of: #""value":"Teeth {p.teeth}"},{"id":"ltheta","key":"text","value":"Plain"}"#,
                                               with: #""value":"Plain"},{"id":"ltheta","key":"text","value":"Teeth {p.teeth}"}"#)
        let t = try XFix.load(XFix.doc(board: shown, solid: XFix.gears, beats: #"[{"say":"Look."}]"#))
        XCTAssertEqual(t.claims.first { $0.id == "item.ltheta" }?.tier, .solved)
    }

    /// A past claim keeps the tier it had when it was shown: removing the item and changing the template so the value
    /// is no longer Built does not raise it to Solved (also after a restore).
    func testRemovedItemKeepsItsShownTier() throws {
        let template = MGTemplate(name: "tierflip", summary: "Synthetic tier transition", params: [MGParamSpec(name: "given", unit: "", range: 0...1)]) { params, _ in
            var item = MGItem(id: "dot", kind: .body, color: .blue)
            item.pts = [MGPoint(6, 4)]
            var build = MGTemplateBuild(title: "", items: [item], values: ["v": MGValue(value: 3, unit: "")])
            build.builtValues = params["given"] == 1 ? ["v"] : []
            return build
        }
        try MGPacks.register(MGPack(id: "tierpack", title: "Tier", summary: "Synthetic", templates: [template],
                                    fixtures: [.init(id: "tierflip", title: "Tier", json: #"{"v":1,"template":"tierflip","params":{"given":1}}"#)]))
        let board = #"{"v":1,"template":"tierflip","params":{"given":1},"items":[{"id":"q","k":"text","at":[1,1],"text":"Value {v}"}]}"#
        var s = try XFix.load(XFix.doc(board: board, beats: #"[{"say":"Look."}]"#))
        XCTAssertEqual(s.claims.first { $0.id == "item.q" }?.tier, .built)
        _ = try s.apply([XFix.json(Self.remove("q")), XFix.json(#"{"op":"params","params":{"given":0}}"#)]).get()
        XCTAssertEqual(s.claims.first { $0.id == "item.q" }?.tier, .built, "q was not shown again, so its Built claim stays")
        guard case .success(let r) = MGExplainerSession.restore(s.snapshot(), pacing: .immediate) else { return XCTFail("restore") }
        XCTAssertEqual(r.claims.first { $0.id == "item.q" }?.tier, .built)
        XCTAssertEqual(r.legend, s.legend)
    }

    /// A valid past claim never makes its own snapshot unrestorable: `q` showed `{dx}`, then a batch removed `q` and
    /// shrank the polygon so `dx` is gone; restore checks structure only and gives the same legend.
    func testPastClaimWhoseValueIsGoneRestores() throws {
        let board = #"{"v":1,"template":"rotate2d","params":{"pts":[[1,1],[2,1],[2,2],[1,2]],"angle":0},"items":[{"id":"q","k":"text","at":[1,1],"text":"Coordinate {dx}"}]}"#
        var s = try XFix.load(XFix.doc(board: board, beats: #"[{"say":"Look."}]"#))
        XCTAssertNotNil(s.claims.first { $0.id == "item.q" })
        _ = try s.apply([XFix.json(Self.remove("q")), XFix.json(#"{"op":"params","params":{"pts":[[1,1],[2,1],[1,2]]}}"#)]).get()
        XCTAssertNil(s.state?.scene.values["dx"])
        switch MGExplainerSession.restore(s.snapshot(), pacing: .immediate) {
        case .success(let r):
            XCTAssertEqual(r.legend, s.legend)
            XCTAssertEqual(r.recordedShown, s.recordedShown)
        case .failure(let issue): XCTFail("a valid accepted history fails restore: \(issue.reason)")
        }
    }

    /// The record does not grow with value namespaces: ids reused over many generations keep one entry each, and the
    /// snapshot stays the same size and restores.
    func testRecordDoesNotGrowWithReusedIds() throws {
        func valueName(_ generation: Int, _ index: Int) -> String { "v" + String(generation, radix: 36) + "x" + String(index, radix: 36) }
        let template = MGTemplate(name: "namesweep", summary: "Synthetic value namespace", params: [MGParamSpec(name: "generation", unit: "", range: 0...1000)]) { params, _ in
            var item = MGItem(id: "dot", kind: .body, color: .blue)
            item.pts = [MGPoint(6, 4)]
            let generation = Int(params["generation"])
            let values = Dictionary(uniqueKeysWithValues: (0..<600).map { (valueName(generation, $0), MGValue(value: 1, unit: "")) })
            return MGTemplateBuild(title: "", items: [item], values: values)
        }
        try MGPacks.register(MGPack(id: "sweeppack", title: "Sweep", summary: "Synthetic", templates: [template],
                                    fixtures: [.init(id: "namesweep", title: "Sweep", json: #"{"v":1,"template":"namesweep","params":{"generation":0}}"#)]))
        var s = try XFix.load(XFix.doc(board: #"{"v":1,"template":"namesweep","params":{"generation":0}}"#, beats: #"[{"say":"Look."}]"#))
        var sizes: [Int] = []
        for generation in 0..<24 {
            if generation > 0 { _ = try s.apply((0..<10).map { XFix.json(Self.remove("q\($0)")) }).get() }
            _ = try s.apply([XFix.json(#"{"op":"params","params":{"generation":\#(generation)}}"#)]).get()
            let additions = (0..<10).map { k -> MGJSON in
                let text = (0..<60).map { "{" + valueName(generation, k * 60 + $0) + "}" }.joined()
                return .object(["op": .string("add"), "item": .object(["id": .string("q\(k)"), "k": .string("text"), "at": .array([.number(1), .number(1)]), "text": .string(text)])])
            }
            _ = try s.apply(additions).get()
            sizes.append(s.recordedShown.json.canonicalByteCount)
        }
        XCTAssertEqual(Set(sizes.dropFirst()).count, 1, "\(sizes)")
        XCTAssertEqual(s.recordedShown.ids.count, 11, "dot and q0…q9")
        let snap = s.snapshot()
        XCTAssertLessThanOrEqual(snap.canonicalByteCount, MGExplainerLimits.snapshotBytes)
        guard case .success(let r) = MGExplainerSession.restore(snap, pacing: .immediate) else { return XCTFail("restore") }
        XCTAssertEqual(r.legend, s.legend)
    }

    /// The record at its cap (1024 ids of 24 characters, each with all 3 tiers) fits `MGShownItems.maxBytes`, and a
    /// snapshot that holds it round-trips under `MGExplainerLimits.snapshotBytes`.
    func testFullRecordRoundTripsUnderTheByteLimit() throws {
        let s = try XFix.load(XFix.doc(board: XFix.rotate, beats: #"[{"say":"Look."}]"#))
        var o = s.snapshot().objectValue!
        guard case .string(let lessonText)? = o["lesson"], var lesson = XFix.json(lessonText).objectValue,
              var kinds = lesson["kinds"]?.objectValue else { return XCTFail("lesson") }
        let current = s.state!.scene.items.map(\.id)
        let filler = (0..<(MGLessonLimits.ids - current.count)).map { String(format: "i%023d", $0) }
        XCTAssertTrue(filler.allSatisfy { $0.count == 24 })
        for id in filler { kinds[id] = .string("text") }
        XCTAssertEqual(kinds.count, MGLessonLimits.ids)
        lesson["kinds"] = .object(kinds)
        o["lesson"] = .string(MGJSON.object(lesson).canonicalString)
        let all: MGJSON = .array(MGTier.allCases.map { .string($0.name) })
        let record: MGJSON = .array((current + filler).map { .object(["id": .string($0), "tiers": all]) })
        XCTAssertLessThanOrEqual(record.canonicalByteCount, MGShownItems.maxBytes)
        o["shown"] = record
        let snap = MGJSON.object(o)
        XCTAssertLessThanOrEqual(snap.canonicalByteCount, MGExplainerLimits.snapshotBytes)
        guard case .success(let r) = MGExplainerSession.restore(data: Data(snap.canonicalString.utf8), pacing: .immediate) else {
            return XCTFail("\(MGExplainerSession.restore(snap, pacing: .immediate))")
        }
        XCTAssertEqual(r.recordedShown.json, record)
        let again = r.snapshot()
        XCTAssertLessThanOrEqual(again.canonicalByteCount, MGExplainerLimits.snapshotBytes)
        guard case .success(let r2) = MGExplainerSession.restore(again, pacing: .immediate) else { return XCTFail("round trip") }
        XCTAssertEqual(r2.legend, r.legend)
        // One more entry is over the id cap.
        o["shown"] = .array(record.arrayValue! + [.object(["id": .string("extra"), "tiers": .array([])])])
        XCTAssertEqual(MGExplainerSession.restore(.object(o), pacing: .immediate).failureIssue?.reason, "snapshot.shown")
    }

    // MARK: Frozen beat claims (second re-check of PR #35)

    func registerClaimFlip() throws {
        let template = MGTemplate(name: "claimflip", summary: "Synthetic frozen claims", params: [MGParamSpec(name: "given", unit: "", range: 0...1)]) { params, _ in
            var item = MGItem(id: "dot", kind: .body, color: .blue)
            item.pts = [MGPoint(6, 4)]
            var build = MGTemplateBuild(title: "", items: [item], values: ["v": MGValue(value: 3, unit: "")])
            build.builtValues = params["given"] == 1 ? ["v"] : []
            return build
        }
        try MGPacks.register(MGPack(id: "claimpack", title: "Claims", summary: "Synthetic", templates: [template],
                                    fixtures: [.init(id: "claimflip", title: "Claims", json: #"{"v":1,"template":"claimflip","params":{"given":1}}"#)]))
    }
    static let flipBoard = #"{"v":1,"template":"claimflip","params":{"given":1},"items":[{"id":"q","k":"text","at":[1,1],"text":"Value {v}"}]}"#
    static let flipDoc = XFix.doc(board: flipBoard, beats: #"[{"say":"Value {v}.","check":[{"value":"v","eq":3}]},{"say":"Next."}]"#)
    static let unflip = [XFix.json(#"{"op":"remove","id":"q"}"#), XFix.json(#"{"op":"params","params":{"given":0}}"#)]

    /// The re-check's repro: beat 1 showed Built `v` in its caption and check; after beat 2 a host batch makes `v`
    /// Solved. Beat 1 is not presented again, so its caption and check stay Built ("Checked" with the Built tier).
    func testPastBeatClaimsKeepTheirShownTier() throws {
        try registerClaimFlip()
        let clock = MGManualClock()
        var s = try XFix.load(Self.flipDoc, pacing: .speech, clock: clock)
        XCTAssertEqual(s.claims.first { $0.id == "beat.1" }?.tier, .built)
        XCTAssertEqual(s.claims.first { $0.id == "beat.1.check.1" }?.tier, .built)
        _ = Self.next(&s, clock, 0)
        XCTAssertEqual(s.presented.beat, 1)
        _ = try s.apply(Self.unflip).get()
        XCTAssertEqual(s.claims.first { $0.id == "item.q" }?.tier, .built)
        XCTAssertEqual(s.claims.first { $0.id == "beat.1" }?.tier, .built, "the past caption never showed a Solved value")
        let check = s.claims.first { $0.id == "beat.1.check.1" }
        XCTAssertEqual(check?.tier, .built, "the past check was Built")
        XCTAssertEqual(check?.badge, MGTier.built.badge(.check))
        XCTAssertEqual(s.legend.text, "Solved 1 · Schematic 3")
    }

    /// Restore keeps the frozen beat claims; a tampered `shownBeats` is refused (`snapshot.shown`); a snapshot without
    /// it freezes each presented beat on the state shown now.
    func testFrozenBeatClaimsRestore() throws {
        try registerClaimFlip()
        let clock = MGManualClock()
        var s = try XFix.load(Self.flipDoc, pacing: .speech, clock: clock)
        _ = Self.next(&s, clock, 0)
        _ = try s.apply(Self.unflip).get()
        let clean = s.snapshot().objectValue!
        guard case .success(let r) = MGExplainerSession.restore(.object(clean), pacing: .speech, clock: clock) else { return XCTFail("restore") }
        XCTAssertEqual(r.legend, s.legend)
        XCTAssertEqual(r.recordedBeats, s.recordedBeats)
        XCTAssertEqual(r.claims.first { $0.id == "beat.1" }?.tier, .built)
        guard case .array(let beats)? = clean["shownBeats"], beats.count == 2 else { return XCTFail("shownBeats \(clean["shownBeats"] ?? .null)") }
        func restore(_ list: [MGJSON]) -> String? {
            var o = clean
            o["shownBeats"] = .array(list)
            return MGExplainerSession.restore(.object(o), pacing: .speech, clock: clock).failureIssue?.reason
        }
        func entry(_ i: Int, _ edit: (inout [String: MGJSON]) -> Void) -> [MGJSON] {
            var list = beats, e = list[i].objectValue!
            edit(&e)
            list[i] = .object(e)
            return list
        }
        XCTAssertEqual(restore(Array(beats.dropFirst())), "snapshot.shown", "a presented beat has no entry")
        XCTAssertEqual(restore(beats + [beats[0]]), "snapshot.shown", "a beat twice")
        XCTAssertEqual(restore(entry(0) { $0["beat"] = .number(5) }), "snapshot.shown", "not a presented beat")
        XCTAssertEqual(restore(entry(0) { $0["beat"] = .number(0.5) }), "snapshot.shown")
        XCTAssertEqual(restore(entry(0) { $0["checks"] = .array([]) }), "snapshot.shown", "wrong check count")
        XCTAssertEqual(restore(entry(0) { $0["caption"] = .array([.string("checked")]) }), "snapshot.shown", "unknown tier")
        XCTAssertEqual(restore(entry(0) { $0["caption"] = .array([.string("built"), .string("built")]) }), "snapshot.shown", "a tier twice")
        XCTAssertEqual(restore(entry(0) { $0["x"] = .bool(true) }), "snapshot.shown", "extra key")
        XCTAssertEqual(restore(entry(0) { $0["checks"] = .array([.array([.string("described")])]) }), "snapshot.shown",
                       "a 2D check value is Built or Solved")
        XCTAssertEqual(restore(entry(0) { $0["caption"] = .array([]) }), "snapshot.shown", "a shown caption claim has a tier")
        XCTAssertEqual(restore(entry(1) { $0["caption"] = .array([.string("built")]) }), "snapshot.shown",
                       "the presented beat's entry must hold what it shows now (no caption claim)")
        var o = clean
        o["shownBeats"] = .string("x")
        XCTAssertEqual(MGExplainerSession.restore(.object(o), pacing: .speech).failureIssue?.reason, "snapshot.shown")
        // A snapshot made before `shownBeats`: each presented beat is frozen on the state shown now.
        o.removeValue(forKey: "shownBeats")
        guard case .success(let old) = MGExplainerSession.restore(.object(o), pacing: .speech) else { return XCTFail("old") }
        XCTAssertEqual(old.claims.first { $0.id == "beat.1" }?.tier, .solved, "frozen on the restored state")
        XCTAssertEqual(old.recordedBeats.caption.keys.sorted(), [0, 1])
    }

    /// The presented beat stays live: its caption and check follow the board (a false check leaves the legend), and
    /// once a later beat is presented it keeps the lowest tier it showed.
    func testCurrentBeatStaysLive() throws {
        try registerClaimFlip()
        let clock = MGManualClock()
        var s = try XFix.load(Self.flipDoc, pacing: .speech, clock: clock)
        XCTAssertEqual(s.presented.beat, 0)
        _ = try s.apply([XFix.json(#"{"op":"params","params":{"given":0}}"#)]).get()
        XCTAssertEqual(s.claims.first { $0.id == "beat.1" }?.tier, .solved, "the presented beat follows the board")
        XCTAssertEqual(s.claims.first { $0.id == "beat.1.check.1" }?.tier, .solved)
        _ = Self.next(&s, clock, 0)
        XCTAssertEqual(s.presented.beat, 1)
        XCTAssertEqual(s.claims.first { $0.id == "beat.1" }?.tier, .built, "past: the lowest tier it showed")
        XCTAssertEqual(s.claims.first { $0.id == "beat.1.check.1" }?.tier, .built)
        // A false check of the presented beat leaves the legend.
        var r = try XFix.load(XFix.doc(board: XFix.rotate, beats: #"[{"say":"Angle {theta}.","check":[{"value":"theta","eq":0}]}]"#))
        XCTAssertTrue(r.claims.contains { $0.id == "beat.1.check.1" && $0.badge == "Checked" })
        _ = try r.apply([XFix.json(#"{"op":"params","params":{"angle":90}}"#)]).get()
        XCTAssertEqual(r.caption, "Angle 90°.")
        XCTAssertEqual(r.notCurrent, ["beat.1.check.1"])
        XCTAssertFalse(r.claims.contains { $0.id == "beat.1.check.1" })
    }

    /// The beat record at its cap (16 beats, a caption and 8 checks each, all 3 tiers) fits `MGShownBeats.maxBytes`.
    func testFullBeatRecordFitsItsBudget() {
        var record = MGShownBeats()
        for k in 0..<MGExplainerLimits.beats {
            record.set(k, caption: Set(MGTier.allCases), checks: Array(repeating: Set(MGTier.allCases), count: MGExplainerLimits.checksPerBeat))
        }
        XCTAssertLessThanOrEqual(record.json.canonicalByteCount, MGShownBeats.maxBytes)
        XCTAssertEqual(MGExplainerLimits.snapshotBytes,
                       2 * (MGLessonLimits.snapshotBytes + MGSolidLimits.bytes) + 2 * MGExplainerLimits.bytes + MGShownItems.maxBytes + MGShownBeats.maxBytes
                       + MGShownAnnotations.maxBytes + MGShownMotion.maxBytes)
        // The annotation record at its cap (80 entries, 64-character ids, the longest tier name) fits its budget too.
        var a = MGShownAnnotations()
        for i in 0..<MGShownAnnotations.maxCount { a.add(id: String(format: "a%063d", i), tier: .described) }
        XCTAssertLessThanOrEqual(a.json.canonicalByteCount, MGShownAnnotations.maxBytes)
        // So does the motion record (96 entries, 64-character ids).
        var m = MGShownMotion()
        for i in 0..<MGShownMotion.maxCount { m.add(id: String(format: "m%063d", i), tier: .described) }
        XCTAssertLessThanOrEqual(m.json.canonicalByteCount, MGShownMotion.maxBytes)
    }
}
