// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import MartyGraphics

/// A pointer to a part's centre (docs/SOLID-3D.md, "Pointers to a part centre"): its head is drawn on the part's surface,
/// where the segment from the pointer's start to the centre first meets the part, so the part does not hide its own
/// pointer. Another part in the way still hides it. Synthetic boxes, neutral names.
final class PointerCentreTipTests: XCTestCase {
    /// A 200 mm shell box with a 40 mm core box inside it, and a 40 mm box beside them.
    static let parts = ArrowVisibilityTests.parts

    func text(_ arrows: String) -> String {
        #"{"v": 2, "kind": "assembly", "parts": [\#(Self.parts)], "annotations": {"arrows": \#(arrows)}, "steps": [{"say": "Boxes.", "camera": "front"}]}"#
    }
    func doc(_ t: String) throws -> MGSolidDocument { try MGSolidParser.document(data: Data(t.utf8)).get() }
    func report(_ t: String) -> MGSolidReport { MGSolidReport.check(data: Data(t.utf8), profile: .strict, engine: nil) }

    /// Before: the head of a pointer to a part's centre sits inside that part, so the arrow rule refused it as hidden
    /// by the part it points at (r2j: `annotation.arrow.hidden.<id>`, by its own target part, no checked offset). Now
    /// the head ends on the part's surface on the pointer's side and the pointer passes strict.
    func testAPointerToAPartCentreEndsOnItsSurfaceAndPasses() throws {
        for to in [#"{"part": "side", "point": "centre"}"#, #"{"part": "side"}"#] {
            let t = text(#"[{"id": "p1", "meaning": "pointer", "from": {"world": [250, -200, 150]}, "to": \#(to), "text": "Side"}]"#)
            let r = report(t)
            XCTAssertTrue(r.ok, "\(to): \(r.reason ?? "")")
            let d = try doc(t)
            let prims = MGSolidAnnotations.primitives(d, "p1", params: d.defaults)
            let tip = prims[1].end
            let pose = d.assembly.pose(d.defaults)
            let box = try XCTUnwrap(d.assembly.part("side")).mesh.bounds
            let local = (pose.world["side"] ?? .identity).inverse.apply(tip)
            // On the surface: on the box (distance 0) but on a face, not at the centre.
            XCTAssertLessThan(mgBoxDistance(local, box), 1e-6)
            let c = box.center, h = box.size * 0.5
            let onFace = [abs(local.x - c.x) - h.x, abs(local.y - c.y) - h.y, abs(local.z - c.z) - h.z].contains { abs($0) < 1e-6 }
            XCTAssertTrue(onFace, "the tip lies on a face of the box: \(local)")
            // The tip lies on the segment from the start to the centre.
            let start = prims[0].start, centre = (pose.world["side"] ?? .identity).apply(c)
            let along = (tip - start).cross(centre - start).length / max(1e-9, (centre - start).length)
            XCTAssertLessThan(along, 1e-6)
        }
    }

    /// The rule counts only other parts: a pointer to the centre of a part closed inside another part is still refused,
    /// hidden by the part in front (the shell), never by its own target.
    func testAnotherPartInTheWayStillHidesIt() throws {
        let t = text(#"[{"id": "p1", "meaning": "pointer", "from": {"world": [0, -400, 150]}, "to": {"part": "core", "point": "centre"}, "text": "Core"}]"#)
        let r = report(t)
        XCTAssertFalse(r.ok)
        XCTAssertTrue(r.reason == "annotation.anchor.hidden.p1" || r.reason == "annotation.arrow.hidden.p1", r.reason ?? "")
        let by: MGJSON? = {
            if case .object(let a)? = r.json["anchor"] { return a["by"] }
            if case .object(let a)? = r.json["arrow"] { return a["by"] }
            return nil
        }()
        XCTAssertEqual(by, .string("shell"))
    }

    /// Other tips are drawn where they are: an offset tip, and a force arrow to a part's centre (its vector is the
    /// claim, so it keeps its authored end).
    func testOnlyPointersToACentreMove() throws {
        let t = text(#"[{"id": "p1", "meaning": "pointer", "from": {"world": [250, -200, 150]}, "to": {"part": "side", "offset": [0, 0, 5]}, "text": "Side"}, {"id": "f1", "meaning": "force", "from": {"world": [400, 0, 200]}, "to": {"part": "side", "point": "centre"}}]"#)
        let d = try doc(t)
        let pose = d.assembly.pose(d.defaults)
        let side = pose.world["side"] ?? .identity
        XCTAssertLessThan((MGSolidAnnotations.primitives(d, "p1", params: d.defaults)[1].end - side.apply(MGVec3(0, 0, 5))).length, 1e-9)
        XCTAssertLessThan((MGSolidAnnotations.primitives(d, "f1", params: d.defaults)[1].end - side.apply(.zero)).length, 1e-9)
    }
}
