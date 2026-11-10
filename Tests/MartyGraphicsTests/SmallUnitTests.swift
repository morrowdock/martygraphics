// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import MartyGraphics

/// The small-unit rule (docs/SOLID-3D.md, "Small named units"): a unit that a shown label or arrow rides on, or that a
/// step or beat highlights, must cover at least `MGSmallUnitRules.minimumPixels` (0.05 % of a 1280 × 800 frame) in at
/// least one still that shows it. A generic reduction of r2j sonnet-1: arm engines that sat inside the hands and showed
/// as thin rings in every whole-figure view.
final class SmallUnitTests: XCTestCase {
    /// A figure (Z up, mm) with an engine at the hand, beyond the arm's end: `size` is its [length, width, height];
    /// the default is a thin ring (12 mm long, 30 mm across), the r2j wrist ring.
    static func figure(ring size: [Double] = [12, 30, 30], focusStep: Bool = false) -> String {
        let focus = focusStep ? #", {"say": "The ring engine.", "focus": ["ring"], "camera": "front", "annotate": ["lRing"]}"# : ""
        return """
        {"v": 2, "kind": "assembly", "title": "Figure", "parts": [
          {"id": "legs", "shape": {"box": {"size": [200, 120, 900], "at": [0, 0, 450]}}},
          {"id": "torso", "shape": {"box": {"size": [400, 200, 600], "at": [0, 0, 1220]}}},
          {"id": "head", "shape": {"box": {"size": [180, 180, 220], "at": [0, 0, 1650]}}},
          {"id": "arm", "shape": {"box": {"size": [500, 100, 100], "at": [450, 0, 1450]}}},
          {"id": "ring", "shape": {"box": {"size": [\(size[0]), \(size[1]), \(size[2])], "at": [\(706 + size[0] / 2), 0, 1450]}}}],
         "annotations": {"labels": [{"id": "lRing", "at": {"part": "ring", "point": "centre"}, "text": "Arm engine"}]},
         "steps": [{"say": "The figure.", "highlight": ["legs", "torso", "head", "arm", "ring"], "camera": "front", "annotate": ["lRing"]},
                   {"say": "From the side.", "highlight": ["legs", "torso", "head", "arm", "ring"], "camera": "iso", "annotate": ["lRing"]}\(focus)]}
        """
    }

    func report(_ t: String) -> (ok: Bool, o: [String: MGJSON]) {
        let r = MGSolidReport.check(data: Data(t.utf8), profile: .strict)
        guard case .object(let o) = r.json else { return (r.ok, [:]) }
        return (r.ok, o)
    }

    func testASmallNamedUnitWarnsWithTheMeasureAndARepair() throws {
        let (ok, o) = report(Self.figure())
        XCTAssertTrue(ok, "a warning, not a refusal: \(o["reason"] ?? .null)")
        guard case .array(let small)? = o["smallUnits"], case .object(let s)? = small.first, case .array(let warnings)? = o["warnings"] else {
            return XCTFail("smallUnits")
        }
        XCTAssertEqual(small.count, 1)
        XCTAssertEqual(s["unit"], .string("ring"))
        XCTAssertEqual(s["minimum"], .number(512))
        XCTAssertEqual(s["stills"], .number(2))
        guard case .number(let px)? = s["pixels"], case .string(let repair)? = s["repair"] else { return XCTFail("fields") }
        XCTAssertLessThan(px, 512)
        XCTAssertTrue(repair.hasPrefix("Unit ring covers at most \(Int(px)) px"), repair)
        XCTAssertTrue(repair.contains(#"Show it in a step with "focus": ["ring"]"#), repair)
        XCTAssertTrue(repair.contains("make it larger"), repair)
        XCTAssertTrue(repair.contains("bring the camera closer"), repair)
        XCTAssertTrue(warnings.contains(.object(["reason": .string("unit.small.ring"), "part": .string("ring")])))
        XCTAssertEqual(MGSolidReasons.lookup("unit.small.ring")?.kind, .warning)
        XCTAssertEqual(MGSolidReasons.lookup("unit.small.ring")?.strict, false)
    }

    /// Each repair clears the warning: a larger unit, or a focused view of it.
    func testEachRepairClearsTheWarning() {
        XCTAssertNil(report(Self.figure(ring: [120, 150, 150])).o["smallUnits"], "larger")
        XCTAssertNil(report(Self.figure(focusStep: true)).o["smallUnits"], "a focused view")
    }

    /// Only named units are measured: without the label the small ring is not named, so there is no warning; the big
    /// figure parts are never small.
    func testOnlyNamedUnitsAreMeasured() {
        let unnamed = Self.figure().replacingOccurrences(of: #""annotate": ["lRing"]"#, with: #""annotate": []"#)
            .replacingOccurrences(of: #""arm", "ring"]"#, with: #""arm"]"#)
        XCTAssertNil(report(unnamed).o["smallUnits"])
        XCTAssertEqual(MGSmallUnitRules.minimumPixels(width: 1280, height: 800), 512)
        XCTAssertEqual(MGSmallUnitRules.minimumPixels(width: 1920, height: 1080), 1037)
    }

    /// The measure counts visible pixels: a unit hidden inside another part covers nothing in that still.
    func testTheMeasureCountsOnlyVisiblePixels() throws {
        let inside = Self.figure().replacingOccurrences(of: #""at": [712.0, 0, 1450]}}}]"#, with: #""at": [450, 0, 1450]}}}]"#)
        XCTAssertNotEqual(inside, Self.figure())
        let doc = try MGSolidParser.document(data: Data(inside.utf8)).get()
        for f in doc.framedStills() {
            XCTAssertEqual(doc.unitPixels(f.still, units: ["ring"])?["ring"], 0, "step \((f.still.step ?? 0) + 1)")
            XCTAssertGreaterThan(doc.unitPixels(f.still, units: ["torso"])?["torso"] ?? 0, 10_000)
        }
    }
}
