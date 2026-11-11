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
        XCTAssertTrue(line.contains("\"at\": [6, \(MGAnnotationAnchorIssue.exact(10 + move[1]))]"), line)
        let w = objects(rep.json["warnings"]).compactMap { o -> String? in if case .string(let s)? = o["reason"] { return s }; return nil }
        XCTAssertTrue(w.contains("board.clip.t6"), "\(w)")
        // The move holds: with t6 moved, nothing is cut.
        let moved = board.replacingOccurrences(of: #""at":[6,10]"#, with: #""at":[6,\#(MGAnnotationAnchorIssue.exact(10 + move[1]))]"#)
        let again = MGExplainerReport.check(data: Data(XFix.doc(board: moved, solid: XFix.gears, beats: #"[{"say":"One."},{"say":"Two.","ops":[\#(fill)]}]"#).utf8),
                                            profile: .strict, engine: nil)
        XCTAssertNil(again.json["boardClips"])
    }

    // MARK: Review of c69245b

    /// An off-axis rotor (its 20 mm cube centred `x` mm from the joint axis): the centre of mass turns with it.
    func rotorText(from: String, to: String, spin: Double, x: Double = 100) -> String {
        let at = "\(x)"
        let off = x == 0 ? "" : #", "offAxis": true"#
        return #"{"v": 2, "kind": "assembly", "parts": [{"id": "rotor", "shape": {"box": {"size": [20, 20, 20], "at": [\#(at), 0, 0]}}, "joint": {"revolute": [0, 0, 1]}, "drive": {"input": 1}\#(off)}], "annotations": {"arrows": [{"id": "w", "meaning": "force", "cause": "gravity", "from": \#(from), "to": \#(to)}]}, "steps": [{"say": "Weight points down.", "camera": "front", "spin": \#(spin), "annotate": ["w"]}]}"#
    }

    func refusal(_ t: String) -> MGSolidIssue? {
        if case .failure(let e) = MGSolidParser.document(data: Data(t.utf8)) { return e }
        return nil
    }

    /// Before: an off-axis rotor's gravity arrow from its centre to a world point was accepted as Solved, although a
    /// quarter turn later it is 54.7° from downward; then a sampled proof missed a 63.25° turn in a 64-joint chain and a
    /// turn just beyond the epsilon between samples. Now an exact rule decides it: a moving centre is refused
    /// (`annotation.pose.w`) with the part and joint that move it, a fixed centre (on the axis) or a still step passes.
    func testAMovingCentreOfMassIsNeverASolvedDirection() throws {
        let com = #"{"point": "centreOfMass", "offset": [0, -100, 0]}"#
        // The single off-axis rotor: refused, with its detail.
        let mixed = rotorText(from: com, to: #"{"world": [100, -100, -100]}"#, spin: 0.25)
        let e = try XCTUnwrap(refusal(mixed), "a turning weight arrow was accepted")
        XCTAssertEqual(e.reason, "annotation.pose.w")
        let c = try XCTUnwrap(e.centreOfMass)
        XCTAssertEqual(c.part, "rotor"); XCTAssertEqual(c.joint, "rotor"); XCTAssertEqual(c.step, 0)
        XCTAssertEqual(try XCTUnwrap(c.distance), 100, accuracy: 1e-6)
        XCTAssertGreaterThan(c.bound, c.tolerance)
        let rep = report(mixed, .standard)
        XCTAssertEqual(rep.reason, "annotation.pose.w")
        guard case .object(let detail)? = rep.json["centreOfMass"], case .string(let line)? = rep.json["repair"] else { return XCTFail("centreOfMass") }
        XCTAssertNotNil(detail["bound"]); XCTAssertNotNil(detail["extraAngle"])
        XCTAssertTrue(line.contains("off the axis of joint `rotor`"), line)
        XCTAssertTrue(line.contains("\"spin\": 0"), line)
        XCTAssertLessThan(line.unicodeScalars.count, MGAnnotationAnchorIssue.repairScalars, "the whole line fits")
        // The review's epsilon case: 0.000100004 mm off the axis, 1.1 turns. Exact: refused, whatever the samples.
        XCTAssertEqual(refusal(rotorText(from: com, to: #"{"world": [0.000100004, -100, -100]}"#, spin: 1.1, x: 0.000100004))?.reason, "annotation.pose.w")
        // Both ends on a moving centre: never a Solved direction either.
        XCTAssertEqual(refusal(rotorText(from: com, to: #"{"point": "centreOfMass", "offset": [0, -100, -100]}"#, spin: 1))?.reason, "annotation.pose.w")
        // The centroid on the axis: the centre is fixed, so the mixed arrow passes.
        XCTAssertNil(refusal(rotorText(from: com, to: #"{"world": [0, -100, -100]}"#, spin: 1, x: 0)))
        // A still step shows one pose: the off-axis arrow passes there.
        let still = rotorText(from: com, to: #"{"world": [100, -100, -100]}"#, spin: 0)
        XCTAssertNil(refusal(still))
        XCTAssertTrue(report(still).ok, "\(report(still).reason ?? "")")
    }

    /// The review's near-axis chain: 64 joints with alternating rates ±1, each centroid 0.0000018 mm from every axis
    /// above it (under the world-fixed epsilon), and an arrow at 9.99° from down. A per-joint yes/no passed it, though
    /// half a turn later it is 10.0155° from down. The bound sums the composed offsets: refused.
    func testANearAxisChainIsJudgedByItsBound() throws {
        var segment: [String] = []
        for k in 1...16 {
            let parent = k == 1 ? "" : #", "parent": "p\#(k - 1)""#
            let sign = k % 2 == 1 ? 1.0 : -1.0
            segment.append(#"{"id": "p\#(k)", "shape": {"box": {"size": [1, 1, 1], "at": [\#(1.8e-06 * sign), 0, 0]}}, "joint": {"revolute": [0, 0, 1]}, "drive": {"input": \#(Int(sign))}, "at": [\#(-3.6e-06 * sign), 0, 0]\#(parent)}"#)
        }
        let component = #"{"v": 1, "kind": "component", "id": "epsilonChain", "title": "Near axes", "about": "Synthetic.", "anchors": {"end": "p16"}, "parts": [\#(segment.joined(separator: ", "))]}"#
        var library = MGSolidLibrary.builtIn
        guard case .success = library.register(Data(component.utf8)) else { return XCTFail("component") }
        let t = #"{"v": 2, "kind": "assembly", "parts": [{"id": "s1", "use": "epsilonChain", "set": {"p1": {"at": [-1.8e-06, 0, 0]}}}, {"id": "s2", "use": "epsilonChain", "parent": "s1.end"}, {"id": "s3", "use": "epsilonChain", "parent": "s2.end"}, {"id": "s4", "use": "epsilonChain", "parent": "s3.end", "set": {"p16": {"shape": {"box": {"size": [20, 20, 20], "at": [-1.8e-06, 0, 0]}}, "offAxis": true}}}, {"id": "distant", "shape": {"box": {"size": [0.05, 0.05, 0.05]}}, "at": [4000, 0, 0]}], "annotations": {"arrows": [{"id": "w", "meaning": "force", "cause": "gravity", "from": {"point": "centreOfMass", "offset": [0, -100, 0]}, "to": {"world": [0.08813552509757477, -100, -0.5]}}]}, "steps": [{"say": "Weight points down.", "camera": "front", "spin": 1, "annotate": ["w"]}]}"#
        guard case .failure(let e) = MGSolidParser.document(data: Data(t.utf8), library: library) else { return XCTFail("a near-axis chain that turns the arrow past 10° was accepted") }
        XCTAssertEqual(e.reason, "annotation.pose.w")
        let c = try XCTUnwrap(e.centreOfMass)
        XCTAssertGreaterThan(c.bound, c.tolerance)
        XCTAssertEqual(c.angle, 9.99, accuracy: 0.001)
        // The same chain without spin passes.
        let still = t.replacingOccurrences(of: #""spin": 1"#, with: #""spin": 0"#)
        guard case .success = MGSolidParser.document(data: Data(still.utf8), library: library) else { return XCTFail("still") }
    }

    /// The re-check's counterexample: an eight-joint chain with alternating rates whose axes lie 0.0000018 mm around one
    /// point (each under the world-fixed epsilon), an arrow from the centre of mass to an offset on its last part at
    /// 9.999999° from down. Bounding the centre alone accepted it, though it turns to 10.0032°. Both ends are bounded
    /// now: refused, with `endBound` over the tolerance. The same arrow to a world point passes; an arrow from a world
    /// point to the chain (no centre of mass) is refused too.
    func chainEndText(to: String, from: String = #"{"point": "centreOfMass", "offset": [0, -100, 0]}"#) -> String {
        var parts = [#"{"id": "body", "shape": {"box": {"size": [20, 20, 20]}}}"#,
                     #"{"id": "dust", "shape": {"box": {"size": [0.05, 0.05, 0.05], "at": [0.001, 0, 0]}}, "joint": {"revolute": [0, 0, 1]}, "drive": {"input": 1}, "offAxis": true}"#]
        for k in 1...8 {
            let sign = k % 2 == 1 ? 1.0 : -1.0
            let at = k == 1 ? "[-0.08810279236302726, -100.00001249999961, -0.5000000624999981]" : "[\(-3.6e-06 * sign), 0, 0]"
            let parent = k == 1 ? "" : #", "parent": "t\#(k - 1)""#
            parts.append(#"{"id": "t\#(k)", "shape": {"box": {"size": [0.05, 0.05, 0.05], "at": [\#(1.8e-06 * sign), 0, 0]}}, "at": \#(at), "joint": {"revolute": [0, 0, 1]}, "drive": {"input": \#(Int(sign))}, "offAxis": true\#(parent)}"#)
        }
        parts.append(#"{"id": "distant", "shape": {"box": {"size": [0.05, 0.05, 0.05]}}, "at": [4000, 0, 0]}"#)
        return #"{"v": 2, "kind": "assembly", "parts": [\#(parts.joined(separator: ", "))], "annotations": {"arrows": [{"id": "w", "meaning": "force", "cause": "gravity", "from": \#(from), "to": \#(to)}]}, "steps": [{"say": "Weight points down.", "camera": "front", "spin": 1, "annotate": ["w"]}]}"#
    }

    func testBothEndsOfAGravityArrowAreBounded() throws {
        let t = chainEndText(to: #"{"part": "t8", "offset": [-1.8e-06, 0, 0]}"#)
        let e = try XCTUnwrap(refusal(t), "the arrow that turns past 10° through its part-mounted end was accepted")
        XCTAssertEqual(e.reason, "annotation.pose.w")
        let c = try XCTUnwrap(e.centreOfMass)
        XCTAssertGreaterThan(c.bound + c.endBound, c.tolerance)
        XCTAssertGreaterThan(c.endBound, c.bound)
        XCTAssertEqual(c.angle, 9.999999, accuracy: 1e-5)
        XCTAssertTrue(c.part.hasPrefix("t"), c.part)
        // The world-point control passes.
        XCTAssertNil(refusal(chainEndText(to: "[-0.08810099236302726, -100.00001249999961, -0.5000000624999981]".replacingOccurrences(of: "[", with: #"{"world": ["#).replacingOccurrences(of: "]", with: "]}"))))
        // Without a centre of mass: a world point to the chain's end is bounded the same way.
        let plain = chainEndText(to: #"{"part": "t8", "offset": [-1.8e-06, 0, 0]}"#, from: #"{"world": [0, -100, 0]}"#)
        XCTAssertEqual(refusal(plain)?.reason, "annotation.pose.w")
    }

    /// The re-check's contributor control: two centre-of-mass parts add about 0.01 mm each (D about 0.02 mm), the end's
    /// part adds 0.015 mm. The report must name the end's part, because it adds the most: the comparison is per
    /// contributor (the centre's largest single weighted term), not against the total `D`.
    func testTheTopContributorIsComparedPerPartNotAgainstTheTotal() throws {
        let t = #"{"v":2,"kind":"assembly","parts":[{"id":"a","shape":{"box":{"size":[2,2,2],"at":[0.01,0,0]}},"joint":{"revolute":[0,0,1]},"drive":{"input":1},"offAxis":true},{"id":"b","shape":{"box":{"size":[2,2,2],"at":[0.01,0,0]}},"joint":{"revolute":[0,0,1]},"drive":{"input":1},"offAxis":true},{"id":"end","shape":{"box":{"size":[0.05,0.05,0.05]}},"at":[0,-100,-1],"joint":{"revolute":[0,0,1]},"drive":{"input":1}}],"annotations":{"arrows":[{"id":"w","meaning":"force","cause":"gravity","from":{"point":"centreOfMass","offset":[0,-100,0]},"to":{"part":"end","offset":[0.0075,0,0]}}]},"steps":[{"say":"Weight points down.","camera":"front","spin":1,"annotate":["w"]}]}"#
        let e = try XCTUnwrap(refusal(t), "the contributor control was accepted")
        XCTAssertEqual(e.reason, "annotation.pose.w")
        let c = try XCTUnwrap(e.centreOfMass)
        XCTAssertGreaterThan(c.bound, c.endBound, "the total D is larger than E in this control")
        XCTAssertEqual(c.part, "end")
        XCTAssertEqual(c.joint, "end")
    }

    // MARK: Executable repairs pass when applied

    /// The review's 9.999° arrow on an off-axis rotor: refused for the motion. Its fixed-point repair at full precision,
    /// applied, passes strict (rounded to 0.001 mm it turned the arrow to 10.0096° and failed `arrow.gravity.w`).
    func testTheFixedPointRepairPassesWhenApplied() throws {
        let t = rotorText(from: #"{"point": "centreOfMass", "offset": [0, -100, 0]}"#, to: #"{"world": [100.35261796965489, -100, -2]}"#, spin: 0.25)
        let rep = report(t, .standard)
        XCTAssertEqual(rep.reason, "annotation.pose.w")
        guard case .object(let detail)? = rep.json["centreOfMass"], case .object(let fixed)? = detail["fixed"],
              case .string(let line)? = rep.json["repair"] else { return XCTFail("centreOfMass") }
        XCTAssertTrue(line.contains("100.35261796965489"), line)
        let d = try doc(rotorText(from: #"{"point": "centreOfMass", "offset": [0, -100, 0]}"#, to: #"{"world": [100.35261796965489, -100, -2]}"#, spin: 0))
        let applied = MGSolidDocument.replacingArrows(d.source, ["w": .object(fixed)])
        guard case .success(let a) = MGSolidParser.document(json: applied) else { return XCTFail("the applied repair does not compile") }
        let r = MGSolidReport.make(a, profile: .strict, engine: nil)
        XCTAssertTrue(r.ok, "\(r.reason ?? "")")
        // The text gives the same numbers.
        XCTAssertTrue(line.contains("[100.35261796965489, -100, -2]"), line)
    }

    /// The weight suggestion, applied, compiles, warns no more and shows the arrow (`verified`).
    func testTheWeightSuggestionPassesWhenApplied() throws {
        let off = comText(arrow: #"{"id": "w", "meaning": "force", "cause": "gravity", "from": {"world": [-200, -300, 0]}, "to": {"world": [-200, -300, -150]}}"#)
        let rep = report(off, .standard)
        let wp = try XCTUnwrap(objects(rep.json["weightPlacements"]).first)
        XCTAssertEqual(wp["verified"], .bool(true))
        guard case .object(let sug)? = wp["suggest"] else { return XCTFail("suggest") }
        let applied = MGSolidDocument.replacingArrows(try doc(off).source, ["w": .object(sug)])
        guard case .success(let a) = MGSolidParser.document(json: applied) else { return XCTFail("compile") }
        XCTAssertTrue(a.weightPlacements.isEmpty)
        let r = MGSolidReport.make(a, profile: .strict, engine: nil)
        XCTAssertTrue(r.ok, "\(r.reason ?? "")")
        XCTAssertFalse(warnings(r).contains("annotation.arrow.weight.w"))
    }

    /// A suggested move of a hidden arrow (a world-anchored force arrow behind a wall), applied, passes strict.
    func testASuggestedArrowMovePassesWhenApplied() throws {
        let t = #"{"v": 2, "kind": "assembly", "parts": [{"id": "wall", "shape": {"box": {"size": [300, 20, 300]}}}, {"id": "post", "at": [0, 100, -200], "shape": {"box": {"size": [20, 20, 20]}}}], "annotations": {"arrows": [{"id": "t", "meaning": "force", "from": {"world": [0, 100, 50]}, "to": {"world": [0, 100, -50]}}]}, "steps": [{"say": "Front.", "camera": "front", "annotate": ["t"]}]}"#
        let rep = report(t)
        XCTAssertEqual(rep.reason, "annotation.arrow.hidden.t")
        guard case .object(let a)? = rep.json["arrow"], case .object(let move)? = a["suggest"] else { return XCTFail("suggest") }
        let applied = MGSolidDocument.replacingArrows(try doc(t).source, ["t": .object(move)])
        guard case .success(let d) = MGSolidParser.document(json: applied) else { return XCTFail("compile") }
        let r = MGSolidReport.make(d, profile: .strict, engine: nil)
        XCTAssertTrue(r.ok, "\(r.reason ?? "")")
    }

    /// The review's 64-joint chain: four copies of a 16-part component, each part a unit cube on one axis turning on its
    /// parent at the input rate; the last part a 20 mm cube 100 mm off the axis. Its world rate is 64 turns per input
    /// turn. A sampled proof missed its 63.25° turn; the bound refuses it, naming the last part.
    func testAComposedChainThatCarriesTheCentreOffTheAxisIsRefused() throws {
        var segment: [String] = []
        for k in 1...16 {
            let parent = k == 1 ? "" : #", "parent": "p\#(k - 1)""#
            segment.append(#"{"id": "p\#(k)", "shape": {"box": {"size": [1, 1, 1]}}, "joint": {"revolute": [0, 0, 1]}, "drive": {"input": 1}\#(parent)}"#)
        }
        let component = #"{"v": 1, "kind": "component", "id": "chainSegment", "title": "Chain segment", "anchors": {"end": "p16"}, "about": "Sixteen coaxial driven boxes.", "parts": [\#(segment.joined(separator: ", "))]}"#
        var library = MGSolidLibrary.builtIn
        guard case .success = library.register(Data(component.utf8)) else { return XCTFail("component") }
        let t = #"{"v": 2, "kind": "assembly", "parts": [{"id": "s1", "use": "chainSegment"}, {"id": "s2", "use": "chainSegment", "parent": "s1.end"}, {"id": "s3", "use": "chainSegment", "parent": "s2.end"}, {"id": "s4", "use": "chainSegment", "parent": "s3.end", "set": {"p16": {"shape": {"box": {"size": [20, 20, 20], "at": [100, 0, 0]}}, "offAxis": true}}}], "annotations": {"arrows": [{"id": "w", "meaning": "force", "cause": "gravity", "from": {"point": "centreOfMass", "offset": [0, -200, 0]}, "to": {"world": [99.21865310678407, -200, -100]}}]}, "steps": [{"say": "Weight points down.", "camera": "front", "spin": 1, "annotate": ["w"]}]}"#
        guard case .failure(let e) = MGSolidParser.document(data: Data(t.utf8), library: library) else { return XCTFail("a 64-joint chain turning the centre was accepted") }
        XCTAssertEqual(e.reason, "annotation.pose.w")
        // The last part adds the most; in the composed bound its base joint adds the largest term.
        XCTAssertEqual(e.centreOfMass?.part, "s4.p16"); XCTAssertEqual(e.centreOfMass?.joint, "s1.p1")
    }

    /// A document without steps has only its plain view. Before: the report skipped it, so an arrow its hero drops had no
    /// `annotation.arrow.dropped` or `orphan` warning. Now the plain view counts (step null).
    func testThePlainViewCountsInTheDropAccounting() throws {
        let t = #"{"v": 2, "kind": "assembly", "parts": [{"id": "body", "shape": {"box": {"size": [300, 300, 600]}}}, {"id": "pack", "shape": {"box": {"size": [60, 60, 60]}}}], "annotations": {"arrows": [{"id": "t", "meaning": "force", "cause": "gravity", "from": {"part": "pack", "offset": [0, 0, -20]}, "to": {"part": "pack", "offset": [0, 0, -120]}, "text": "Weight"}]}}"#
        let rep = report(t)
        XCTAssertTrue(rep.ok, "\(rep.reason ?? "")")
        let w = warnings(rep)
        XCTAssertTrue(w.contains("annotation.arrow.dropped.t"), "\(w)")
        XCTAssertTrue(w.contains("annotation.arrow.orphan.t"), "\(w)")
        let drop = try XCTUnwrap(objects(rep.json["arrowDrops"]).first)
        XCTAssertEqual(drop["step"], .null); XCTAssertEqual(drop["by"], .string("body"))
        let note = try XCTUnwrap(objects(rep.json["arrowDropNotes"]).first)
        XCTAssertEqual(note["steps"], .array([.null]))
        guard case .string(let line)? = note["repair"] else { return XCTFail("repair") }
        XCTAssertTrue(line.contains("the plain view (hero.png)"), line)
    }

    /// A six-column table with `cw` 4 in a board-only explainer is 1560 px wide in a 1216 px safe area. Before: the
    /// report moved it from one side to the other. Now no move is given (`move` null) and `fit` gives exact sizes; the
    /// table resized and placed by `fit` is not cut.
    func testABoardItemLargerThanThePaneGetsSizesNotAMove() throws {
        func text(cw: String, at: String) -> String {
            #"{"v": 1, "kind": "explainer", "title": "Board", "board": {"v": 1, "items": [{"id": "t", "k": "table", "at": \#(at), "cw": \#(cw), "header": true, "cells": [["A","B","C","D","E","F"],["a","b","c","d","e","f"]]}]}, "beats": [{"say": "Look."}]}"#
        }
        let rep = MGExplainerReport.check(data: Data(text(cw: "4", at: "[10, 4]").utf8), profile: .strict, engine: nil)
        let c = try XCTUnwrap(objects(rep.json["boardClips"]).first)
        XCTAssertEqual(c["move"], .null)
        XCTAssertEqual(numbers(c["safe"]).first, 1216)
        XCTAssertGreaterThan(numbers(c["size"]).first ?? 0, 1216)
        guard case .object(let fit)? = c["fit"], case .number(let cw)? = fit["cw"], case .number(let cols)? = fit["columns"] else { return XCTFail("fit") }
        XCTAssertLessThan(cw, 4); XCTAssertLessThan(cols, 6)
        let at = numbers(fit["at"])
        XCTAssertEqual(at.count, 2); XCTAssertEqual(at[1], 4)
        guard case .string(let line)? = c["repair"] else { return XCTFail("repair") }
        XCTAssertTrue(line.contains("no move fits it"), line)
        XCTAssertTrue(line.contains("\"cw\" to at most \(MGAnnotationAnchorIssue.number(cw))"), line)
        // Applied, the sizes fit.
        let fixed = text(cw: MGAnnotationAnchorIssue.number(cw), at: "[\(MGAnnotationAnchorIssue.exact(at[0])), 4]")
        XCTAssertNil(MGExplainerReport.check(data: Data(fixed.utf8), profile: .strict, engine: nil).json["boardClips"])
        // The zoom alternative, applied with the same `at`, fits too.
        guard case .number(let zoom)? = fit["zoom"] else { return XCTFail("zoom") }
        let zoomed = text(cw: "4", at: "[\(MGAnnotationAnchorIssue.exact(at[0])), 4]")
            .replacingOccurrences(of: #""board": {"v": 1, "items""#, with: #""board": {"v": 1, "camera": {"zoom": \#(MGAnnotationAnchorIssue.number(zoom))}, "items""#)
        let zr = MGExplainerReport.check(data: Data(zoomed.utf8), profile: .strict, engine: nil)
        XCTAssertTrue(zr.ok, "\(zr.reason ?? "")")
        XCTAssertNil(zr.json["boardClips"])
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
