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
    /// so a "clear" move left the arrow floating far from its part (r2j: 220–440 mm off the engines). Now every move
    /// that takes the tail more than its tolerance off the part is skipped; here none is left (`code` `tail`).
    func testASuggestedMoveKeepsTheTailOnItsPart() throws {
        let t = text(packZ: 300)   // the top half of the pack shows above the body; the arrow hangs behind the body
        let d = try doc(t)
        let r = try XCTUnwrap(d.annotations.arrow("t"))
        let tail = try XCTUnwrap(d.arrowTail(r))
        XCTAssertTrue(tail.from); XCTAssertEqual(tail.part, "pack"); XCTAssertEqual(tail.distance, 0)
        XCTAssertEqual(tail.tolerance, max(MGAnnotationArrowRules.tailLengthShare * 100, MGAnnotationArrowRules.tailPartShare * (3 * 3600).squareRoot()), accuracy: 1e-9)
        let rep = report(t)
        XCTAssertEqual(rep.reason, "annotation.arrow.hidden.t")
        guard case .object(let a)? = rep.json["arrow"] else { return XCTFail("arrow") }
        XCTAssertEqual(a["by"], .string("body"))
        XCTAssertEqual(a["suggest"], .null)
        guard case .object(let none)? = a["noSuggest"] else { return XCTFail("noSuggest") }
        XCTAssertEqual(none["code"], .string("tail"))
        XCTAssertEqual(rep.json["arrowDrops"], nil, "the pack shows, so the arrow is not dropped")
        if case .string(let line)? = rep.json["repair"] { XCTAssertTrue(line.contains("tail off its part"), line) } else { XCTFail("repair") }
    }

    /// A move within the tolerance is still suggested, and the moved tail stays within it.
    func testANearMoveIsStillSuggested() throws {
        // The arrow sits just inside the pack's lower edge: a short move clears it.
        let t = #"{"v": 2, "kind": "assembly", "parts": [{"id": "pack", "shape": {"box": {"size": [60, 60, 60]}}}], "annotations": {"arrows": [{"id": "t", "meaning": "force", "from": {"part": "pack", "offset": [0, 0, -20]}, "to": {"part": "pack", "offset": [0, 0, 20]}}]}, "steps": [{"say": "Front.", "camera": "front"}]}"#
        let rep = report(t)
        XCTAssertEqual(rep.reason, "annotation.arrow.hidden.t")
        guard case .object(let a)? = rep.json["arrow"], case .object(let s)? = a["suggest"], case .object(let f)? = s["from"],
              case .array(let o)? = f["offset"] else { return XCTFail("a suggestion") }
        let d = try doc(t)
        let tail = try XCTUnwrap(d.arrowTail(try XCTUnwrap(d.annotations.arrow("t"))))
        let moved = o.compactMap { v -> Double? in if case .number(let x) = v { return x }; return nil }
        XCTAssertEqual(moved.count, 3)
        let dist = mgBoxDistance(MGVec3(moved[0], moved[1], moved[2]), try XCTUnwrap(d.assembly.part("pack")).mesh.bounds)
        XCTAssertLessThanOrEqual(dist, tail.tolerance)
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
