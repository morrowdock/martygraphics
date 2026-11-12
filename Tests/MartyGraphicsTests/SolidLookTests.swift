// SPDX-License-Identifier: Apache-2.0
import Foundation
import SceneKit
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

    /// A look scales the rig's lights; it never moves, adds, removes or renames one. It may reflect its own room.
    func testALookKeepsTheRigsShape() {
        let rig = MGStudioLighting.studio
        for look in [MGSolidLook.studio, .paper] {
            let lit = look.lighting(rig)
            XCTAssertEqual(lit.lights.map(\.name), rig.lights.map(\.name), look.name)
            XCTAssertEqual(lit.lights.map(\.direction), rig.lights.map(\.direction), look.name)
            XCTAssertEqual(lit.lights.map(\.castsShadow), rig.lights.map(\.castsShadow), look.name)
            // The room the parts reflect is the look's own; every soft box has its eight finite numbers.
            if let room = look.environment { XCTAssertEqual(lit.environment, room, look.name) }
            XCTAssertFalse(lit.environment.softboxes.isEmpty, look.name)
            for box in lit.environment.softboxes { XCTAssertTrue(box.count == 8 && box.allSatisfy(\.isFinite) && box[7] > 0, look.name) }
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

    /// A look's room is a valid environment that survives the snapshot's validating decoder (same record type).
    func testTheProductStudioIsAValidEnvironment() throws {
        for (gain, room) in [(1.0, 1.0), (2.4, 1.0), (1.5, 6.0), (1.0, 1000.0)] {
            let e = MGSolidLook.productStudio(gain: gain, room: room)
            let back = try JSONDecoder().decode(MGStudioLighting.Environment.self, from: JSONEncoder().encode(e))
            XCTAssertEqual(back, e)
            for v in e.zenith + e.horizon + e.floor { XCTAssertTrue(v >= 0 && v <= 0.9) }
        }
    }

    /// Classic materials are the presets as before; a look finishes plastics and machined metals in the renderer and
    /// leaves the exported parameters alone.
    func testALookFinishesSurfacesInTheRendererOnly() {
        let before = MGMaterialPreset.plastic(.blue).parameters
        let classic = MGSolidRenderer.scnMaterial(.plastic(.blue)), studio = MGSolidRenderer.scnMaterial(.plastic(.blue), look: .studio)
        XCTAssertEqual((classic.clearCoat.contents as? NSNumber)?.doubleValue, before.clearcoat)
        XCTAssertEqual((studio.clearCoat.contents as? NSNumber)?.doubleValue, MGSolidLook.studio.plasticCoat)
        XCTAssertEqual(MGMaterialPreset.plastic(.blue).parameters, before)
        XCTAssertNil(MGSolidRenderer.scnMaterial(.titanium).shaderModifiers)
        XCTAssertNotNil(MGSolidRenderer.scnMaterial(.titanium, look: .studio).shaderModifiers?[.surface])
        // Brushed steel keeps its classic roughness texture in `classic` and takes the per-fragment marks in a look.
        XCTAssertNil(MGSolidRenderer.scnMaterial(.brushedSteel).shaderModifiers)
        XCTAssertNotNil(MGSolidRenderer.scnMaterial(.brushedSteel, look: .studio).shaderModifiers?[.surface])
        XCTAssertTrue(MGSolidRenderer.scnMaterial(.brushedSteel, look: .studio).roughness.contents is NSNumber)
        for preset in [MGMaterialPreset.polishedSteel, .rubber, .glass, .plastic(.red), .composite, .ceramic, .blackOxide] {
            XCTAssertFalse(MGSolidRenderer.isMachined(preset), preset.id)
            XCTAssertNil(MGSolidRenderer.scnMaterial(preset, look: .studio).shaderModifiers, preset.id)
        }
    }

    /// The rig's soft boxes are unchanged by the feather parameter's default (0.25).
    func testTheEnvironmentImageKeepsItsSize() {
        let e = MGStudioLighting.studio.environment
        for feather in [0.25, 0.5, 0, 2] {
            let image = MGSolidRenderer.environmentImage(e, width: 64, height: 32, feather: feather)
            XCTAssertEqual(image?.width, 64); XCTAssertEqual(image?.height, 32)
        }
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
