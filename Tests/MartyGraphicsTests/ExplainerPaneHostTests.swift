// SPDX-License-Identifier: Apache-2.0
#if canImport(AppKit)
import AppKit
import SceneKit
import simd
import SwiftUI
import XCTest
@testable import MartyGraphics

/// The real `MartyGraphicsExplainerView` in an `NSHostingView`: a learner's camera gesture in the solid pane's
/// `SCNView` (SceneKit's own camera control switching to a free camera and orbiting it, and moving the orbit pivot)
/// is dropped at the next beat, and the pane shows that beat's framed camera again (docs/EXPLAINER.md, "The solid
/// pane in SwiftUI"). This is what `.id(cameraReset)` on the pane's `SceneView` does.
final class ExplainerPaneHostTests: XCTestCase {
    /// Lets SwiftUI apply pending updates (published changes, layout, `onAppear`).
    @MainActor func settle(_ host: NSView) {
        for _ in 0..<5 {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
    }

    func scnViews(in view: NSView) -> [SCNView] {
        (view as? SCNView).map { [$0] } ?? view.subviews.flatMap(scnViews(in:))
    }

    /// The camera the pane's `SCNView` shows, as world position and unit view direction (Y up).
    func shown(_ v: SCNView) -> (position: simd_float3, forward: simd_float3)? {
        guard let pov = v.pointOfView else { return nil }
        let t = pov.presentation.simdWorldTransform
        return (simd_float3(t.columns.3.x, t.columns.3.y, t.columns.3.z), -simd_normalize(simd_float3(t.columns.2.x, t.columns.2.y, t.columns.2.z)))
    }

    func assertShows(_ c: MGSolidCamera, _ v: SCNView, _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        guard let s = shown(v) else { return XCTFail("\(what): no point of view", file: file, line: line) }
        let p = c.position, t = c.targetVector
        let want = simd_float3(Float(p.x), Float(p.y), Float(p.z))
        let look = simd_normalize(simd_float3(Float(t.x - p.x), Float(t.y - p.y), Float(t.z - p.z)))
        XCTAssertLessThan(simd_distance(s.position, want), Float(c.distance) * 1e-4, "\(what): camera position", file: file, line: line)
        XCTAssertGreaterThan(simd_dot(s.forward, look), 0.99999, "\(what): view direction", file: file, line: line)
    }

    @MainActor func testALearnerGestureIsDroppedAtTheNextBeat() throws {
        let doc = try ExplainerPaneFramingTests.parse(ExplainerPaneFramingTests.backTower)
        let c = MGExplainerController(pacing: .speech, clock: MGManualClock())
        XCTAssertTrue(c.load(doc))
        XCTAssertTrue(c.session.solid?.annotations.isEmpty ?? false, "no annotations: the learner has camera control")
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
        let host = NSHostingView(rootView: MartyGraphicsExplainerView(controller: c))
        host.frame = window.contentLayoutRect
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        settle(host)

        let r = try XCTUnwrap(c.renderer)
        let first = try XCTUnwrap(scnViews(in: host).first, "the solid pane's SCNView")
        XCTAssertTrue(first.allowsCameraControl)
        XCTAssertGreaterThan(c.cameraReset, 0, "the pane framed beat 1 for its size")
        XCTAssertEqual(c.session.presented.beat, 0)
        assertShows(r.camera, first, "beat 1 before the gesture")

        // The learner's gesture, as SceneKit's camera control makes it: the view switches to its own free camera at
        // the current pose, and the controller orbits it about a moved pivot.
        let free = SCNNode()
        free.camera = r.cameraNode.camera?.copy() as? SCNCamera
        free.simdWorldTransform = r.cameraNode.simdWorldTransform
        r.scene.rootNode.addChildNode(free)
        defer { free.removeFromParentNode() }
        first.pointOfView = free
        let controller = first.defaultCameraController
        controller.pointOfView = free
        controller.target = SCNVector3(250, 400, -100)
        controller.rotateBy(x: 70, y: 35)
        controller.dolly(by: 300, onScreenPoint: CGPoint(x: 450, y: 300), viewport: first.bounds.size)
        settle(host)
        let moved = try XCTUnwrap(shown(first))
        let p1 = r.camera.position
        XCTAssertGreaterThan(simd_distance(moved.position, simd_float3(Float(p1.x), Float(p1.y), Float(p1.z))), Float(r.camera.distance) * 0.05,
                             "the gesture moved the camera the pane shows")

        // The next beat: the pane shows that beat's framed camera, not the learner's camera.
        c.lineEnded(0)
        settle(host)
        XCTAssertEqual(c.session.presented.beat, 1)
        let framed = try XCTUnwrap(c.paneClear?.camera)
        XCTAssertEqual(r.camera, framed)
        let pane = try XCTUnwrap(scnViews(in: host).first, "the solid pane's SCNView")
        XCTAssertTrue(pane.pointOfView === r.cameraNode, "the pane is back on the framed camera node, not the free camera")
        assertShows(framed, pane, "beat 2 after the gesture")
    }
}
#endif
