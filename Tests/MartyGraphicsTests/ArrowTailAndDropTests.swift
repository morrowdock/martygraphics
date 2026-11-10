// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import MartyGraphics

/// Force and flow arrows stay with the part they act on (docs/SOLID-3D.md, "Arrow tails" and "Arrow drop"): a
/// suggested move keeps the arrow's tail on its part, and a still whose camera cannot see that part's unit drops the
/// arrow. Synthetic boxes, neutral names: a tall `body` box with a small `pack` box behind it.
final class ArrowTailAndDropTests: XCTestCase {
    /// `pack` sits behind `body` (the front camera looks along +Y); `packZ` is its height.
    func text(packZ: Double, steps: String = #"[{"say": "Front.", "camera": "front", "annotate": ["t"]}]"#) -> String {
        #"{"v": 2, "kind": "assembly", "parts": [{"id": "body", "shape": {"box": {"size": [300, 100, 600]}}}, {"id": "pack", "at": [0, 100, \#(packZ)], "shape": {"box": {"size": [60, 60, 60]}}}], "annotations": {"arrows": [{"id": "t", "meaning": "force", "from": {"part": "pack", "offset": [0, 0, -20]}, "to": {"part": "pack", "offset": [0, 0, -120]}}]}, "steps": \#(steps)}"#
    }
    func doc(_ t: String) throws -> MGSolidDocument { try MGSolidParser.document(data: Data(t.utf8)).get() }
    func report(_ t: String, _ p: MGSolidProfile = .strict) -> MGSolidReport { MGSolidReport.check(data: Data(t.utf8), profile: p, engine: nil) }
    func objects(_ v: MGJSON?) -> [[String: MGJSON]] {
        guard case .array(let a)? = v else { return [] }
        return a.compactMap { if case .object(let o) = $0 { return o }; return nil }
    }

    /// Before: the search moved a hidden thrust arrow k × (the blocker's size / 4) along itself or toward the camera,
    /// so a "clear" move left the arrow floating far from its part (r2j: 220–440 mm off the engines). Now no move may
    /// take the tail farther from its part; here none is left (`code` `tail`).
    func testASuggestedMoveKeepsTheTailOnItsPart() throws {
        let t = text(packZ: 300)   // the top half of the pack shows above the body; the arrow hangs behind the body
        let d = try doc(t)
        let r = try XCTUnwrap(d.annotations.arrow("t"))
        let tail = try XCTUnwrap(d.arrowTail(r))
        XCTAssertTrue(tail.from); XCTAssertEqual(tail.part, "pack"); XCTAssertEqual(tail.distance, 0)
        let rep = report(t)
        XCTAssertEqual(rep.reason, "annotation.arrow.hidden.t")
        guard case .object(let a)? = rep.json["arrow"] else { return XCTFail("arrow") }
        XCTAssertEqual(a["by"], .string("body"))
        XCTAssertEqual(a["suggest"], .null)
        guard case .object(let none)? = a["noSuggest"] else { return XCTFail("noSuggest") }
        XCTAssertEqual(none["code"], .string("tail"))
        XCTAssertEqual(rep.json["arrowDrops"], nil, "the pack shows, so the arrow is not dropped")
        if case .string(let line)? = rep.json["repair"] { XCTAssertTrue(line.contains("tail farther from its part"), line) } else { XCTFail("repair") }
    }

    /// The review's case: an arrow inside a 60 mm cube. Before this rule a 51.962 mm move cleared it and left the tail
    /// 21.962 mm outside the cube. A tail inside its part must stay inside, so there is no move (`code` `tail`).
    func testATailInsideItsPartStaysInside() throws {
        let t = #"{"v": 2, "kind": "assembly", "parts": [{"id": "pack", "shape": {"box": {"size": [60, 60, 60]}}}], "annotations": {"arrows": [{"id": "t", "meaning": "force", "from": {"part": "pack", "offset": [0, 0, -20]}, "to": {"part": "pack", "offset": [0, 0, 20]}}]}, "steps": [{"say": "Front.", "camera": "front"}]}"#
        let rep = report(t)
        XCTAssertEqual(rep.reason, "annotation.arrow.hidden.t")
        guard case .object(let a)? = rep.json["arrow"] else { return XCTFail("arrow") }
        XCTAssertEqual(a["suggest"], .null)
        guard case .object(let none)? = a["noSuggest"] else { return XCTFail("noSuggest") }
        XCTAssertEqual(none["code"], .string("tail"))
    }

    /// The rule itself: equal or nearer passes, farther by more than the precision epsilon fails.
    func testTheTailRule() {
        XCTAssertTrue(MGAnnotationArrowRules.keepsTail(authored: 0, moved: 0))
        XCTAssertTrue(MGAnnotationArrowRules.keepsTail(authored: 0, moved: mgPrecision(.zero)))
        XCTAssertFalse(MGAnnotationArrowRules.keepsTail(authored: 0, moved: 0.001))
        XCTAssertTrue(MGAnnotationArrowRules.keepsTail(authored: 14.4, moved: 3))
        XCTAssertFalse(MGAnnotationArrowRules.keepsTail(authored: 14.4, moved: 43.789))
        XCTAssertFalse(MGAnnotationArrowRules.keepsTail(authored: 0, moved: .nan))
    }

    /// A reduction of r2j sonnet-2 `tb2` (a thrust arrow from a back engine's exhaust whose tail lies 14.4 mm off the
    /// nozzle, hidden in a back view by its own nozzle): before, the suggested move took the tail 43.789 mm off. Every
    /// printed move now keeps the tail at most as far from its part as authored; here no move is left.
    func testABackEngineThrustArrowKeepsItsTail() throws {
        let t = #"{"v": 2, "kind": "assembly", "parts": [{"id": "body", "shape": {"box": {"size": [300, 100, 500]}}}, {"id": "b2", "use": "microTurbojet", "with": {"diameter": 90, "length": 240}, "at": [0, 100, 60], "rot": [1, 0, 0, 180]}], "annotations": {"arrows": [{"id": "tb2", "meaning": "force", "from": {"part": "b2.exhaust", "offset": [0, 0, 40]}, "to": {"part": "b2.exhaust", "offset": [0, 0, -60]}}]}, "steps": [{"say": "Back.", "camera": "back"}]}"#
        let d = try doc(t)
        let r = try XCTUnwrap(d.annotations.arrow("tb2"))
        let tail = try XCTUnwrap(d.arrowTail(r))
        XCTAssertEqual(tail.part, "b2.nozzle")
        XCTAssertEqual(tail.distance, 14.4, accuracy: 1e-6)
        let rep = report(t, .standard)
        XCTAssertTrue(objects(rep.json["arrowIssues"]).contains { $0["id"] == .string("tb2") }, "its own nozzle hides it")
        for issue in objects(rep.json["arrowIssues"]) where issue["id"] == .string("tb2") {
            if case .object(let s)? = issue["suggest"], case .object(let f)? = s["from"], case .array(let o)? = f["offset"] {
                let v = o.compactMap { x -> Double? in if case .number(let n) = x { return n }; return nil }
                let box = try XCTUnwrap(d.assembly.part(tail.part)).mesh.bounds
                XCTAssertLessThanOrEqual(mgBoxDistance(MGVec3(v[0], v[1], v[2]), box), tail.distance + mgPrecision(.zero))
            } else {
                guard case .object(let none)? = issue["noSuggest"] else { return XCTFail("noSuggest") }
                XCTAssertEqual(none["code"], .string("tail"))
            }
        }
    }

    /// Before: an arrow on a part the camera cannot see was kept (and a suggested move put it in front of the part in
    /// the way). Now the still drops it: no refusal, a warning, `arrowDrops`, and the framed view leaves it out. The
    /// same arrow in a view that sees the part is kept.
    func testAnArrowOnAHiddenPartIsDropped() throws {
        let steps = #"[{"say": "Front.", "camera": "front", "annotate": ["t"]}, {"say": "Back.", "camera": "back", "annotate": ["t"]}]"#
        let t = text(packZ: 0, steps: steps)
        let rep = report(t)
        XCTAssertTrue(rep.ok, rep.reason ?? "")
        let warnings = objects(rep.json["warnings"]).compactMap { o -> String? in if case .string(let s)? = o["reason"] { return s }; return nil }
        XCTAssertEqual(warnings, ["annotation.arrow.dropped.t"])
        let drops = objects(rep.json["arrowDrops"])
        XCTAssertEqual(drops.count, 1)
        XCTAssertEqual(drops.first?["id"], .string("t")); XCTAssertEqual(drops.first?["part"], .string("pack"))
        XCTAssertEqual(drops.first?["by"], .string("body")); XCTAssertEqual(drops.first?["step"], .number(1))
        XCTAssertEqual(drops.first?["reason"], .string("annotation.arrow.dropped.t"))
        XCTAssertEqual(objects(rep.json["arrowIssues"]).count, 0)
        // The framing drops it from the still; the back view keeps it.
        let d = try doc(t)
        for (k, dropped) in [(0, true), (1, false)] {
            let shot = try XCTUnwrap(MGSolidShot.step(d, k))
            let clear = MGSolidFraming.clearView(d, shot: shot, aspect: 1.6, titleBand: 0, captionBand: 0)
            XCTAssertEqual(clear.arrowDrops.map(\.id), dropped ? ["t"] : [])
            let shown = d.checkedAnnotations(clear.view(d.view(step: k)), params: shot.params)
            XCTAssertEqual(shown, dropped ? [] : ["t"])
            XCTAssertEqual(d.checkedAnnotations(d.view(step: k), params: shot.params), ["t"], "the step's own view still lists it")
            XCTAssertEqual(clear.manifestFields["arrowDrops"] != nil, dropped)
        }
        // The standard profile gives the same warning.
        XCTAssertTrue(report(t, .standard).ok)
    }

    /// The review's case: a one-beat explainer whose front view drops the arrow `t`. Before, the legend counted it
    /// ("Not checked 1") although no view drew it. Now the session's presentation record holds only what the beat
    /// draws, the claims leave `t` out, and the still, the story and the SwiftUI pane all get the same drop set.
    func testADroppedArrowIsNotAPresentedClaim() throws {
        let solid = #"{"v": 2, "parts": [{"id": "body", "shape": {"box": {"size": [300, 100, 600]}}}, {"id": "pack", "at": [0, 100, 0], "shape": {"box": {"size": [60, 60, 60]}}}], "annotations": {"arrows": [{"id": "t", "meaning": "force", "from": {"part": "pack", "offset": [0, 0, -20]}, "to": {"part": "pack", "offset": [0, 0, -120]}}]}}"#
        for annotate in [true, false] {
            let view = annotate ? #"{"camera": "front", "annotate": ["t"]}"# : #"{"camera": "front"}"#
            let doc = #"{"v": 1, "kind": "explainer", "solid": \#(solid), "beats": [{"say": "Front.", "view": \#(view)}]}"#
            let s = try XFix.load(doc)
            XCTAssertEqual(s.droppedArrows(beat: 0), ["t"])
            XCTAssertEqual(s.displayedAnnotations(beat: 0), [])
            XCTAssertFalse(s.claims.contains { $0.id == "t" }, "annotate \(annotate)")
            XCTAssertFalse(s.legend.text.contains("Not checked"), s.legend.text)
            // Every view of the beat applies the same set, whatever its pane.
            let d = try XCTUnwrap(s.solid)
            for aspect in [0.6, 1.0, 1.6, 2.4] {
                let c = MGExplainerFrame.solidClearView(d, view: s.presented, stepIndex: s.solidStep(forBeat: 0), aspect: aspect)
                XCTAssertEqual(c.arrowDrops.map(\.id), ["t"], "aspect \(aspect)")
            }
            let r = MGExplainerReport.check(data: Data(doc.utf8), profile: .strict, engine: nil)
            XCTAssertTrue(r.ok, r.reason ?? "")
            if case .object(let legend)? = r.json["legend"] { XCTAssertNotEqual(legend["text"], .string("Not checked 1")) } else { XCTFail("legend") }
        }
        // An assembly whose only still drops the arrow claims nothing for it; one whose back view draws it does.
        let front = try doc(text(packZ: 0))
        XCTAssertEqual(front.undrawnArrows, ["t"])
        XCTAssertFalse(front.legend.claims.contains { $0.id == "t" })
        let both = try doc(text(packZ: 0, steps: #"[{"say": "Front.", "camera": "front", "annotate": ["t"]}, {"say": "Back.", "camera": "back", "annotate": ["t"]}]"#))
        XCTAssertEqual(both.undrawnArrows, [])
        XCTAssertTrue(both.legend.claims.contains { $0.id == "t" })
    }

    /// The unit's own parts never hide it: an engine whose casing wraps another part (a grip inside it) is seen as the
    /// casing, so its arrow is kept.
    func testAUnitSeenThroughItsOwnCasingIsKept() throws {
        let t = #"{"v": 2, "kind": "assembly", "parts": [{"id": "e", "use": "microTurbojet", "with": {"diameter": 70, "length": 200}}, {"id": "grip", "at": [0, 0, 100], "shape": {"box": {"size": [20, 20, 60]}}}], "annotations": {"arrows": [{"id": "t", "meaning": "force", "from": {"part": "e.casing", "offset": [0, 0, 0]}, "to": {"part": "e.casing", "offset": [0, 0, -150]}}]}, "steps": [{"say": "Front.", "camera": "front"}]}"#
        let d = try doc(t)
        // The grip lies inside the casing's box, so it is in front of most of the engine's inner parts.
        let pose = d.assembly.pose(d.defaults)
        func box(_ id: String) throws -> MGBounds {
            MGSolidFrames.worldBounds(try XCTUnwrap(d.assembly.part(id)).mesh.bounds, pose.world[id] ?? .identity)
        }
        let casing = try box("e.casing"), grip = try box("grip")
        XCTAssertTrue(casing.union(grip) == casing, "the grip is inside the casing box")
        let shot = try XCTUnwrap(MGSolidShot.step(d, 0))
        XCTAssertEqual(MGSolidFraming.clearView(d, shot: shot, aspect: 1.6, titleBand: 0, captionBand: 0).arrowDrops, [])
        let unit = d.unitParts(of: "e.casing").map(\.id)
        XCTAssertTrue(unit.contains("e.casing")); XCTAssertFalse(unit.contains("grip"))
        XCTAssertTrue(unit.allSatisfy { $0 == "e" || $0.hasPrefix("e.") })
    }

    /// Pointers and motion arrows are never dropped; the drop needs an arrow end on a part.
    func testOnlyForceAndFlowArrowsAreDropped() throws {
        let t = #"{"v": 2, "kind": "assembly", "parts": [{"id": "body", "shape": {"box": {"size": [300, 100, 600]}}}, {"id": "pack", "at": [0, 100, 0], "shape": {"box": {"size": [60, 60, 60]}}}], "annotations": {"arrows": [{"id": "w", "meaning": "force", "from": {"world": [0, 100, -100]}, "to": {"world": [0, 100, -200]}}]}, "steps": [{"say": "Front.", "camera": "front"}]}"#
        let d = try doc(t)
        XCTAssertNil(d.arrowTail(try XCTUnwrap(d.annotations.arrow("w"))))
        let shot = try XCTUnwrap(MGSolidShot.step(d, 0))
        XCTAssertEqual(MGSolidFraming.clearView(d, shot: shot, aspect: 1.6, titleBand: 0, captionBand: 0).arrowDrops, [])
    }
}
