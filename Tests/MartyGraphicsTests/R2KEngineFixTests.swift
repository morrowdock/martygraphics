// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import MartyGraphics

/// The engine failures recorded in prompt-to-3D round r2k (docs/SOLID-3D.md, "Every view of a hidden arrow", "Arrow
/// drop", "Dropped arrows that leave a caption alone", "Weight at the centre of mass", "The legend's Solved group";
/// docs/EXPLAINER.md, "Board items inside the pane"). Synthetic boxes and neutral names; each test failed before its fix.
final class R2KEngineFixTests: XCTestCase {
    func doc(_ t: String) throws -> MGSolidDocument { try MGSolidParser.document(data: Data(t.utf8)).get() }
    func report(_ t: String, _ p: MGSolidProfile = .strict) -> MGSolidReport { MGSolidReport.check(data: Data(t.utf8), profile: p, engine: nil) }
    func objects(_ v: MGJSON?) -> [[String: MGJSON]] {
        guard case .array(let a)? = v else { return [] }
        return a.compactMap { if case .object(let o) = $0 { return o }; return nil }
    }
    func warnings(_ r: MGSolidReport) -> [String] {
        objects(r.json["warnings"]).compactMap { if case .string(let s)? = $0["reason"] { return s }; return nil }
    }
    func numbers(_ v: MGJSON?) -> [Double] {
        guard case .array(let a)? = v else { return [] }
        return a.compactMap { if case .number(let n) = $0 { return n }; return nil }
    }

    /// A tall `body` box with a small `pack` box behind it (the front camera looks along +Y): the pack's top half shows
    /// above the body; the arrow hangs from the pack behind the body.
    func packText(steps: String, cause: Bool = false, text: String? = nil, packZ: Double = 300) -> String {
        let extra = (cause ? #", "cause": "gravity""# : "") + (text.map { #", "text": "\#($0)""# } ?? "")
        return #"{"v": 2, "kind": "assembly", "parts": [{"id": "body", "shape": {"box": {"size": [300, 100, 600]}}}, {"id": "pack", "at": [0, 100, \#(packZ)], "shape": {"box": {"size": [60, 60, 60]}}}], "annotations": {"arrows": [{"id": "t", "meaning": "force", "from": {"part": "pack", "offset": [0, 0, -20]}, "to": {"part": "pack", "offset": [0, 0, -120]}\#(extra)}]}, "steps": \#(steps)}"#
    }

    // MARK: 1. One refusal lists every hidden view

    /// Before: the refusal named step 1 only; a model that moved the arrow to step 2 was refused again there (r2k: three
    /// tries, three beats). Now the hidden issue tests every step still, also those that do not list it.
    func testOneRefusalNamesEveryStillThatHidesTheArrow() throws {
        let t = packText(steps: #"[{"say": "Front.", "camera": "front", "annotate": ["t"]}, {"say": "Front again.", "camera": "front", "annotate": []}, {"say": "Back.", "camera": "back", "annotate": []}]"#)
        let rep = report(t)
        XCTAssertEqual(rep.reason, "annotation.arrow.hidden.t")
        guard case .object(let a)? = rep.json["arrow"], case .object(let v)? = a["views"] else { return XCTFail("arrow.views") }
        XCTAssertEqual(numbers(v["hidden"]), [1, 2])
        XCTAssertEqual(numbers(v["clear"]), [3])
        XCTAssertEqual(v["every"], .bool(false))
        XCTAssertEqual(v["hiddenCameras"], .array([.string("front")]))
        XCTAssertEqual(objects(v["tested"]).map { $0["listed"] }, [.bool(true), .bool(false), .bool(false)])
        guard case .string(let line)? = rep.json["repair"] else { return XCTFail("repair") }
        XCTAssertTrue(line.contains("It is also hidden in step 2; hidden in every `front` view; shown in step 3."), line)
    }

    /// Hidden in every still: the summary says no camera of the document shows it.
    func testHiddenInEveryStillSaysSo() throws {
        let t = packText(steps: #"[{"say": "Front.", "camera": "front", "annotate": ["t"]}, {"say": "Front again.", "camera": "front", "annotate": []}]"#)
        let rep = report(t)
        guard case .object(let a)? = rep.json["arrow"], case .object(let v)? = a["views"] else { return XCTFail("arrow.views") }
        XCTAssertEqual(v["every"], .bool(true))
        guard case .string(let line)? = rep.json["repair"] else { return XCTFail("repair") }
        XCTAssertTrue(line.contains("It is hidden in every step still (steps 1 and 2): no camera of this document shows it there."), line)
    }

    // MARK: 2. A fully hidden arrow on a hidden tail part is dropped

    /// A unit (`eng`, a jet engine component) whose casing shows (a label on it keeps it in the frame), and a `sleeve` box
    /// over its nozzle end; the thrust arrow runs from the nozzle's centre into the sleeve. Before: strict refused it with `noSuggest` code `tail` (no
    /// move keeps the tail on the hidden nozzle). Now the still drops it (`annotation.arrow.dropped.t`, cause `part`).
    func sleeveText() -> String {
        #"{"v": 2, "kind": "assembly", "parts": [{"id": "eng", "use": "microTurbojet", "with": {"diameter": 90, "length": 200}}, {"id": "sleeve", "at": [0, 0, 230], "shape": {"box": {"size": [160, 160, 140]}}}], "annotations": {"labels": [{"id": "lc", "at": {"part": "eng.casing", "offset": [0, -46, 40]}, "text": "Casing"}], "arrows": [{"id": "t", "meaning": "force", "from": {"part": "eng.nozzle", "point": "centre"}, "to": {"world": [0, 0, 280]}}]}, "steps": [{"say": "Front.", "camera": "front", "annotate": ["t", "lc"]}]}"#
    }

    func testAFullyHiddenArrowOnAHiddenTailPartIsDropped() throws {
        let d = try doc(sleeveText())
        let r = try XCTUnwrap(d.annotations.arrow("t"))
        XCTAssertEqual(d.arrowTail(r)?.part, "eng.nozzle")
        let rep = report(sleeveText())
        XCTAssertTrue(rep.ok, "\(rep.reason ?? "")")
        let drops = objects(rep.json["arrowDrops"])
        XCTAssertEqual(drops.count, 1)
        XCTAssertEqual(drops.first?["cause"], .string("part"))
        XCTAssertEqual(drops.first?["part"], .string("eng.nozzle"))
        XCTAssertEqual(drops.first?["by"], .string("sleeve"))
        XCTAssertTrue(warnings(rep).contains("annotation.arrow.dropped.t"))
    }

    func testAnArrowWhoseTailPartShowsIsStillRefused() throws {
        // The mount sits on the casing's front face, outside the sleeve; the arrow runs into the sleeve.
        let t = #"{"v": 2, "kind": "assembly", "parts": [{"id": "eng", "shape": {"box": {"size": [80, 80, 80]}}}, {"id": "mount", "parent": "eng", "at": [60, -50, 0], "shape": {"box": {"size": [20, 20, 20]}}}, {"id": "sleeve", "at": [200, -50, 0], "shape": {"box": {"size": [200, 200, 300]}}}], "annotations": {"arrows": [{"id": "t", "meaning": "force", "from": {"part": "mount", "offset": [80, 50, 0]}, "to": {"part": "mount", "offset": [80, 50, 100]}}]}, "steps": [{"say": "Front.", "camera": "front", "annotate": ["t"]}]}"#
        let rep = report(t)
        XCTAssertEqual(rep.reason, "annotation.arrow.hidden.t")
        XCTAssertNil(rep.json["arrowDrops"])
    }

    // MARK: 3. The off-part test skips parts the view hides

    /// A label on a `shaft` inside a `sleeve`. Before: "lands on sleeve (0.0 mm)" also in the step that hides the
    /// sleeve. Now a part the view hides is skipped; a step that shows the sleeve still finds it nearer.
    func testTheOffPartTestSkipsAHiddenPart() throws {
        func text(hide: Bool) -> String {
            let h = hide ? #", "hide": ["sleeve"]"# : ""
            return #"{"v": 2, "kind": "assembly", "parts": [{"id": "shaft", "shape": {"box": {"size": [10, 10, 200]}}}, {"id": "sleeve", "shape": {"box": {"size": [40, 40, 100]}}}], "annotations": {"labels": [{"id": "l", "at": {"part": "shaft", "offset": [8, 0, 0]}, "text": "Shaft"}]}, "steps": [{"say": "One.", "camera": "front", "annotate": ["l"]\#(h)}]}"#
        }
        XCTAssertEqual(try doc(text(hide: false)).offPartAnchors.first?.closer, "sleeve")
        XCTAssertEqual(try doc(text(hide: true)).offPartAnchors.count, 0)
        XCTAssertFalse(warnings(report(text(hide: true), .standard)).contains("annotation.anchor.off.l"))
    }

    // MARK: 4. Dropped arrows that leave the story without them

    /// The pack sits wholly behind the body: the only still that lists the arrow drops it (orphan), and its caption
    /// names the weight (caption). Before: one `annotation.arrow.dropped.t` warning only.
    func testAnOrphanArrowAndACaptionThatNamesItWarn() throws {
        let t = packText(steps: #"[{"say": "Weight pulls the pack down.", "camera": "front", "annotate": ["t"]}]"#, cause: true, packZ: 0)
        let rep = report(t)
        XCTAssertTrue(rep.ok, "\(rep.reason ?? "")")
        let w = warnings(rep)
        XCTAssertTrue(w.contains("annotation.arrow.dropped.t"), "\(w)")
        XCTAssertTrue(w.contains("annotation.arrow.orphan.t"), "\(w)")
        XCTAssertTrue(w.contains("annotation.arrow.caption.t"), "\(w)")
        let notes = objects(rep.json["arrowDropNotes"])
        XCTAssertEqual(notes.map { $0["kind"] }, [.string("orphan"), .string("caption")])
        XCTAssertEqual(notes.last?["word"], .string("weight"))
        XCTAssertEqual(numbers(notes.last?["steps"]), [1])
    }

    /// Shown in another still: no orphan; a caption that does not name the force: no caption note.
    func testAnArrowShownElsewhereIsNoOrphan() throws {
        let t = packText(steps: #"[{"say": "The pack hangs behind.", "camera": "front", "annotate": ["t"]}, {"say": "From behind.", "camera": "back", "annotate": ["t"]}]"#, text: "Thrust", packZ: 0)
        let rep = report(t)
        let w = warnings(rep)
        XCTAssertTrue(w.contains("annotation.arrow.dropped.t"), "\(w)")
        XCTAssertFalse(w.contains("annotation.arrow.orphan.t"), "\(w)")
        XCTAssertFalse(w.contains("annotation.arrow.caption.t"), "\(w)")
        XCTAssertNil(rep.json["arrowDropNotes"])
    }

    func testForceWordsMatch() throws {
        let d = try doc(packText(steps: #"[{"say": "x", "camera": "back"}]"#, text: "Thrusts of the pack"))
        let r = try XCTUnwrap(d.annotations.arrow("t"))
        XCTAssertEqual(MGArrowDropNote.names(r), ["thrust"])
        XCTAssertEqual(MGArrowDropNote.named("Each engine's thrust pushes up.", ["thrust"]), "thrust")
        XCTAssertEqual(MGArrowDropNote.named("The thrusts balance.", ["thrust"]), "thrust")
        XCTAssertNil(MGArrowDropNote.named("Thrustless.", ["thrust"]))
    }

    // MARK: 5. Weight at the centre of mass

    /// Two boxes: `a` (100 mm cube at the origin) and `b` (200 × 100 × 100 at x = 300): uniform density puts the centre
    /// of mass at x = (0 × 1 + 300 × 2) / 3 = 200.
    func comText(arrow: String) -> String {
        #"{"v": 2, "kind": "assembly", "parts": [{"id": "a", "shape": {"box": {"size": [100, 100, 100]}}}, {"id": "b", "at": [300, 0, 0], "shape": {"box": {"size": [200, 100, 100]}}}], "annotations": {"arrows": [\#(arrow)]}, "steps": [{"say": "Front.", "camera": "front"}]}"#
    }

    func testTheCentreOfMassAnchor() throws {
        let d = try doc(comText(arrow: #"{"id": "w", "meaning": "force", "cause": "gravity", "from": {"point": "centreOfMass"}, "to": {"point": "centreOfMass", "offset": [0, 0, -150]}}"#))
        let r = try XCTUnwrap(d.annotations.arrow("w"))
        let pose = d.assembly.pose(d.defaults)
        let p = try XCTUnwrap(r.from).world(pose), q = try XCTUnwrap(r.to).world(pose)
        XCTAssertEqual(p.x, 200, accuracy: 1e-6); XCTAssertEqual(p.y, 0, accuracy: 1e-6); XCTAssertEqual(p.z, 0, accuracy: 1e-6)
        XCTAssertEqual((q - p).z, -150, accuracy: 1e-9)
        XCTAssertEqual(MGAnnotationArrowSuggestion.point(try XCTUnwrap(r.to)), .object(["point": .string("centreOfMass"), "offset": .array([.number(0), .number(0), .number(-150)])]))
        XCTAssertTrue(d.weightPlacements.isEmpty)
        // Only at a force arrow's ends.
        for bad in [#"{"id": "f", "meaning": "flow", "from": {"point": "centreOfMass"}, "to": "a"}"#] {
            guard case .failure(let e) = MGSolidParser.document(data: Data(comText(arrow: bad).utf8)) else { return XCTFail("accepted") }
            XCTAssertEqual(e.reason, "anchor.point")
        }
        let label = #"{"v": 2, "kind": "assembly", "parts": [{"id": "a", "shape": {"box": {"size": [100, 100, 100]}}}], "annotations": {"labels": [{"id": "l", "at": {"point": "centreOfMass"}, "text": "Centre"}]}, "steps": [{"say": "Front.", "camera": "front"}]}"#
        guard case .failure(let e) = MGSolidParser.document(data: Data(label.utf8)) else { return XCTFail("label accepted") }
        XCTAssertEqual(e.reason, "anchor.point")
    }

    /// A weight arrow off the body whose start lies off the centre across the view warns, with centre-of-mass anchors
    /// that keep its vector and its depth; one on its own part (a hanging load's weight), or in front of the centre
    /// (depth only), does not. The step uses the `front` camera (it looks along +Y).
    func testAWeightArrowOffTheCentreWarns() throws {
        let off = comText(arrow: #"{"id": "w", "meaning": "force", "cause": "gravity", "from": {"world": [-200, -300, 0]}, "to": {"world": [-200, -300, -150]}}"#)
        let d = try doc(off)
        let w = try XCTUnwrap(d.weightPlacements.first)
        XCTAssertEqual(w.id, "w"); XCTAssertEqual(w.step, 0); XCTAssertEqual(w.camera, "front")
        XCTAssertGreaterThan(w.distance, 400)   // 400 mm across x, plus the depth the front camera's 8° pitch shows
        XCTAssertTrue(d.warnings.contains { $0.reason == "annotation.arrow.weight.w" })
        let rep = report(off, .standard)
        let wp = objects(rep.json["weightPlacements"])
        guard case .object(let sug)? = wp.first?["suggest"], case .object(let from)? = sug["from"], case .object(let to)? = sug["to"] else { return XCTFail("suggest") }
        XCTAssertEqual(from["point"], .string("centreOfMass"))
        let fo = numbers(from["offset"]), to3 = numbers(to["offset"])
        XCTAssertEqual(fo.count, 3); XCTAssertEqual(to3.count, 3)
        XCTAssertEqual(fo[0], 0, accuracy: 0.01)
        XCTAssertLessThan(fo[1], -250, "the depth in front of the body is kept")
        XCTAssertEqual(to3[2] - fo[2], -150, accuracy: 0.002)
        XCTAssertTrue(report(off).ok, "a warning, never refused")
        // In front of the centre (depth only): reads right.
        let front = comText(arrow: #"{"id": "w", "meaning": "force", "cause": "gravity", "from": {"world": [200, -100, 0]}, "to": {"world": [200, -100, -150]}}"#)
        XCTAssertTrue(try doc(front).weightPlacements.isEmpty)
        // On its own part: that part's weight.
        let onPart = comText(arrow: #"{"id": "w", "meaning": "force", "cause": "gravity", "from": "a", "to": {"part": "a", "offset": [0, 0, -150]}}"#)
        XCTAssertTrue(try doc(onPart).weightPlacements.isEmpty)
    }

    /// The centre moves with the pose: each part's centroid is posed.
    func testTheVolumeCentroid() throws {
        let d = try doc(#"{"v": 2, "kind": "assembly", "parts": [{"id": "a", "shape": {"box": {"size": [20, 40, 60]}}}], "steps": [{"say": "One."}]}"#)
        let box = MGMassProperties.volume(try XCTUnwrap(d.assembly.part("a")).mesh)
        XCTAssertEqual(box.volume, 48_000, accuracy: 1e-6)
        XCTAssertEqual(box.centroid.length, 0, accuracy: 1e-9)
    }

    // MARK: 6. Board items inside the pane

    /// Three stacked tables filled in the last beat, the top one above the board's viewport. Before: no warning; the
    /// still cut the top table's header under the pane edge. Now `board.clip.<id>` with the exact move of its `at`.
    func testABoardTableThePaneCutsWarnsWithAnExactMove() throws {
        let board = #"{"v":1,"items":[{"id":"t4","k":"table","at":[6,4],"header":true,"cells":[["Item","Value"]]},{"id":"t5","k":"table","at":[6,7],"header":true,"cells":[["Item","Value"]]},{"id":"t6","k":"table","at":[6,10],"header":true,"cells":[["Item","Value"]]}]}"#
        let fill = ["t4", "t5", "t6"].map { #"{"op":"set","id":"\#($0)","key":"cells","value":[["Item","Value"],["Row","A"]]}"# }.joined(separator: ",")
        let doc = XFix.doc(board: board, solid: XFix.gears, beats: #"[{"say":"One."},{"say":"Two.","ops":[\#(fill)]}]"#)
        let rep = MGExplainerReport.check(data: Data(doc.utf8), profile: .strict, engine: nil)
        XCTAssertTrue(rep.ok, "\(rep.reason ?? "")")
        let clips = objects(rep.json["boardClips"])
        XCTAssertEqual(clips.map { $0["id"] }, [.string("t6")])
        let c = try XCTUnwrap(clips.first)
        XCTAssertEqual(c["beat"], .number(2))
        guard case .object(let over)? = c["overflow"], case .number(let top)? = over["top"] else { return XCTFail("overflow") }
        XCTAssertGreaterThan(top, 0.5)
        let move = numbers(c["move"]), at = numbers(c["at"])
        XCTAssertEqual(move.count, 2); XCTAssertEqual(move[0], 0); XCTAssertLessThan(move[1], 0)
        XCTAssertEqual(at, [6, 10])
        guard case .string(let line)? = c["repair"] else { return XCTFail("repair") }
        XCTAssertTrue(line.contains("\"at\": [6, \(MGAnnotationAnchorIssue.number(10 + move[1]))]"), line)
        let w = objects(rep.json["warnings"]).compactMap { o -> String? in if case .string(let s)? = o["reason"] { return s }; return nil }
        XCTAssertTrue(w.contains("board.clip.t6"), "\(w)")
        // The move holds: with t6 moved, nothing is cut.
        let moved = board.replacingOccurrences(of: #""at":[6,10]"#, with: #""at":[6,\#(MGAnnotationAnchorIssue.number(10 + move[1]))]"#)
        let again = MGExplainerReport.check(data: Data(XFix.doc(board: moved, solid: XFix.gears, beats: #"[{"say":"One."},{"say":"Two.","ops":[\#(fill)]}]"#).utf8),
                                            profile: .strict, engine: nil)
        XCTAssertNil(again.json["boardClips"])
    }

    // MARK: 8. The legend's Solved group

    func testTheSolvedGroupNamesAnimationRatios() {
        XCTAssertEqual(MGLegendText.solved(18, ratios: 18), "Solved 18 (animation ratios)")
        XCTAssertEqual(MGLegendText.solved(1, ratios: 1), "Solved 1 (animation ratio)")
        XCTAssertEqual(MGLegendText.solved(18, ratios: 15), "Solved 18 (15 animation ratios)")
        XCTAssertEqual(MGLegendText.solved(2, ratios: 1), "Solved 2 (1 animation ratio)")
        XCTAssertEqual(MGLegendText.solved(3, ratios: 0), "Solved 3")
    }
}
