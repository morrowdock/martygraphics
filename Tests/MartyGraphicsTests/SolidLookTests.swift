// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import MartyGraphics

/// Looks and quality levels (`MGSolidLook`, `MGSolidQuality`): pixels only. The deterministic parts are tested here:
/// the rig a look lights with, the snapshot it must not touch, and the CPU backdrop.
final class SolidLookTests: XCTestCase {
    func testNamesAndLookup() {
        XCTAssertEqual(MGSolidLook.names, ["classic", "studio", "paper"])
        for n in MGSolidLook.names { XCTAssertEqual(MGSolidLook.named(n)?.name, n) }
        XCTAssertNil(MGSolidLook.named("Studio"))
        XCTAssertNil(MGSolidLook.named(""))
    }

    func testClassicLeavesTheRigAlone() {
        XCTAssertEqual(MGSolidLook.classic.lighting(.studio), .studio)
    }

    /// A look scales the rig; it never moves, adds, removes or renames a light or a soft box.
    func testALookKeepsTheRigsShape() {
        let rig = MGStudioLighting.studio
        for look in [MGSolidLook.studio, .paper] {
            let lit = look.lighting(rig)
            XCTAssertEqual(lit.lights.map(\.name), rig.lights.map(\.name), look.name)
            XCTAssertEqual(lit.lights.map(\.direction), rig.lights.map(\.direction), look.name)
            XCTAssertEqual(lit.lights.map(\.castsShadow), rig.lights.map(\.castsShadow), look.name)
            XCTAssertEqual(lit.environment.softboxes.count, rig.environment.softboxes.count, look.name)
            for (a, b) in zip(lit.environment.softboxes, rig.environment.softboxes) { XCTAssertEqual(Array(a[0..<7]), Array(b[0..<7]), look.name) }
            XCTAssertEqual(lit.background, rig.background, look.name)
            for v in lit.environment.zenith + lit.environment.horizon + lit.environment.floor { XCTAssertTrue(v.isFinite && v >= 0 && v <= 0.9, look.name) }
            for l in lit.lights { XCTAssertTrue(l.intensity.isFinite && l.intensity > 0, look.name) }
        }
    }

    /// The exported snapshot records the rig, never a look: its bytes do not depend on any look.
    func testTheSnapshotRecordsTheRig() throws {
        let text = #"{"v": 2, "kind": "assembly", "title": "Block", "parts": [{"id": "box", "shape": {"box": {"size": [10, 10, 10]}}}]}"#
        let doc = try MGSolidParser.document(data: Data(text.utf8)).get()
        let snap = MGSolidRenderPlan.snapshot(doc)
        XCTAssertEqual(snap.lighting, .studio)
    }

    func testTheBackdropIsDeterministicAndOpaque() {
        let pool = MGSolidLook.Pool(x: 160, y: 120, rx: 90, ry: 60)
        for look in [MGSolidLook.studio, .paper] {
            let a = look.backdrop(width: 320, height: 200, pool: pool), b = look.backdrop(width: 320, height: 200, pool: pool)
            XCTAssertEqual(a.count, 320 * 200 * 4, look.name)
            XCTAssertEqual(a, b, look.name)
            XCTAssertTrue(stride(from: 3, to: a.count, by: 4).allSatisfy { a[$0] == 255 }, look.name)
        }
    }

    /// The pool is the brightest place and the corners the darkest; the gradient is slow enough, with its dither, that
    /// neighbouring pixels never differ by more than three levels (no visible band edge).
    func testTheBackdropFallsOffSmoothly() {
        let w = 320, h = 200
        let pool = MGSolidLook.Pool(x: 160, y: 120, rx: 90, ry: 60)
        for look in [MGSolidLook.studio, .paper] {
            let px = look.backdrop(width: w, height: h, pool: pool)
            func mean(_ x0: Int, _ y0: Int) -> Double {
                var s = 0.0
                for y in y0..<y0 + 8 { for x in x0..<x0 + 8 { let i = (y * w + x) * 4; s += Double(px[i]) + Double(px[i + 1]) + Double(px[i + 2]) } }
                return s / (64 * 3)
            }
            let centre = mean(156, 116)
            for (x, y) in [(0, 0), (w - 8, 0), (0, h - 8), (w - 8, h - 8)] { XCTAssertGreaterThan(centre, mean(x, y) + 8, look.name) }
            var worst = 0
            for y in 0..<h { for x in 1..<w { for k in 0..<3 {
                let i = (y * w + x) * 4 + k
                worst = max(worst, abs(Int(px[i]) - Int(px[i - 4])))
            } } }
            XCTAssertLessThanOrEqual(worst, 3, look.name)
        }
    }

    func testAnEmptyOrTinyFrameStillGivesPixels() {
        XCTAssertEqual(MGSolidLook.studio.backdrop(width: 0, height: 0, pool: .centred(width: 0, height: 0)).count, 4)
        XCTAssertEqual(MGSolidLook.paper.backdrop(width: 3, height: 2, pool: MGSolidLook.Pool(x: .nan, y: 0, rx: 0, ry: 0)).count, 24)
    }

    func testQualityLevels() {
        XCTAssertEqual(MGStudioOptions(quality: .still), MGStudioOptions())
        let balanced = MGStudioOptions(quality: .balanced), interactive = MGStudioOptions(quality: .interactive)
        XCTAssertEqual(balanced.supersample, 1)
        XCTAssertTrue(balanced.ambientOcclusion && balanced.bloom && balanced.shadows)
        XCTAssertEqual(balanced.shadowMapSize, 4096)
        XCTAssertLessThan(balanced.shadowSamples, MGStudioOptions().shadowSamples)
        XCTAssertFalse(interactive.ambientOcclusion || interactive.bloom)
        XCTAssertTrue(interactive.shadows && interactive.ground)
        XCTAssertLessThan(interactive.shadowMapSize, balanced.shadowMapSize)
        XCTAssertLessThan(interactive.shadowSamples, balanced.shadowSamples)
        XCTAssertNotEqual(balanced, interactive)
    }
}
