// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import MartyGraphics

/// The solid renderer's ground cache (`MGSolidRenderer.updateGround`, docs/ENGINE.md "Layers and caches"): the shadow
/// catcher and the contact shadow follow the default pose's bounds only, so camera updates reuse them, while the key
/// light's shadow frustum follows its own inputs (the exploded extent and the light), so a changed exploded extent with
/// the same rest bounds still refits it.
final class SolidGroundCacheTests: XCTestCase {
    /// A fixed base and an arm on it that explodes `reach` mm upwards: the same rest bounds for every reach.
    func assembly(reach: Double) -> MGAssembly {
        MGAssembly(name: "reach", parts: [
            MGPart(id: "base", name: "base", mesh: .chamferedBox(size: MGVec3(40, 40, 10), chamfer: 0.5), material: .darkSteel),
            MGPart(id: "arm", name: "arm", mesh: .chamferedBox(size: MGVec3(10, 10, 30), chamfer: 0.5), material: .brass,
                   placement: .translation(MGVec3(0, 0, 20)), explode: MGVec3(0, 0, reach)),
        ])
    }

    func corners(_ b: MGBounds) -> [Double] { [b.min.x, b.min.y, b.min.z, b.max.x, b.max.y, b.max.z] }

    func testRepeatedCameraUpdatesReuseTheGround() throws {
        let r = MGSolidRenderer(assembly: assembly(reach: 40))
        let ground = r.groundNodeIdentities
        XCTAssertEqual(ground.count, 2, "the shadow catcher and the contact shadow")
        let fit = try XCTUnwrap(r.keyLightShadowFit)
        for k in 0..<12 {
            r.setCamera(MGSolidCamera(target: .zero, yaw: Double(k) * 30, pitch: 10 + Double(k) * 3, distance: 200 + Double(k) * 15))
            XCTAssertEqual(r.groundNodeIdentities, ground, "camera update \(k) rebuilt the ground")
        }
        let again = try XCTUnwrap(r.keyLightShadowFit)
        XCTAssertEqual(again.scale, fit.scale)
        XCTAssertEqual(again.near, fit.near)
        XCTAssertEqual(again.far, fit.far)
    }

    func testAChangedExplodedExtentWithTheSameRestBoundsStillRefitsTheShadowFrustum() throws {
        let r = MGSolidRenderer(assembly: assembly(reach: 10))
        let rest = corners(r.worldBounds(MGPoseParameters()))
        let ground = r.groundNodeIdentities
        let before = try XCTUnwrap(r.keyLightShadowFit)
        let narrow = max(1, r.worldBounds(MGPoseParameters(), explodeRange: [1]).radius)
        XCTAssertEqual(before.scale, narrow * 1.25, accuracy: 1e-9, "fitted to the exploded extent")

        r.setAssembly(assembly(reach: 120))
        XCTAssertEqual(corners(r.worldBounds(MGPoseParameters())), rest, "the rest bounds did not change")
        r.setCamera(r.camera)
        let after = try XCTUnwrap(r.keyLightShadowFit)
        let wide = max(1, r.worldBounds(MGPoseParameters(), explodeRange: [1]).radius)
        XCTAssertGreaterThan(wide, narrow + 10, "the arm explodes further")
        XCTAssertEqual(after.scale, wide * 1.25, accuracy: 1e-9, "the frustum follows the new exploded extent")
        XCTAssertEqual(after.near, wide * 0.5, accuracy: 1e-9)
        XCTAssertEqual(after.far, wide * 6, accuracy: 1e-9)
        XCTAssertEqual(r.groundNodeIdentities, ground, "the rest bounds did not change, so the ground is kept")
    }
}
