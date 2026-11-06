// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import MartyGraphics

/// Controller rollback: a refused patch or stream leaves the shown scene, the change counter and the revision
/// allocator exactly as they were; accepted changes always get a fresh, strictly increasing scene revision.
final class ControllerRollbackTests: XCTestCase {
    private typealias R = MGRegression

    @MainActor func testRefusedPatchLeavesEveryObservableStateUntouched() throws {
        let controller = MGSceneController(scene: try R.scene(R.patchBase))
        let before = controller.scene, changes = controller.revision, allocator = controller.nextSceneRevision
        let partial = try R.patch(#"{"v":1,"rev":0,"ops":[{"op":"title","title":"Changed"},{"op":"remove","id":"ghost"}]}"#)
        XCTAssertFalse(controller.apply(patch: partial))
        XCTAssertEqual(controller.scene, before)
        XCTAssertEqual(controller.revision, changes)
        XCTAssertEqual(controller.nextSceneRevision, allocator)
        XCTAssertTrue(controller.lastUpdateFailed)

        XCTAssertTrue(controller.apply(patch: try R.patch(#"{"v":1,"rev":0,"ops":[{"op":"title","title":"Changed"}]}"#)))
        XCTAssertFalse(controller.lastUpdateFailed)
        XCTAssertEqual(controller.revision, changes + 1)
        XCTAssertEqual(controller.scene?.revision, allocator)
        XCTAssertEqual(controller.scene?.title, "Changed")
    }

    @MainActor func testRevisionRequirementAndMalformedPatchObjects() throws {
        let controller = MGSceneController(scene: try R.scene(R.patchBase))
        let before = controller.scene
        XCTAssertFalse(controller.apply(patch: try R.patch(R.ops([#"{"op":"title","title":"No rev"}"#])), requireRevision: true))
        let noOps: [String: Any] = ["v": 1, "ops": [Any]()]
        XCTAssertFalse(controller.apply(patchObject: noOps))
        XCTAssertFalse(controller.apply(patchObject: "not a patch"))
        XCTAssertEqual(controller.scene, before)
        XCTAssertTrue(controller.lastUpdateFailed)
        XCTAssertFalse(MGSceneController().apply(patch: try R.patch(R.ops([#"{"op":"title","title":"Nothing"}"#]))))
    }

    @MainActor func testSuccessfulStreamEndsOnTheStrictScene() throws {
        let controller = MGSceneController(scene: try R.scene(R.patchBase))
        controller.beginStream()
        XCTAssertTrue(controller.isStreaming)
        for chunk in R.chunks(R.allKinds, seed: 3) { controller.feed(chunk) }
        XCTAssertTrue(controller.endStream())
        XCTAssertFalse(controller.isStreaming)
        XCTAssertFalse(controller.lastUpdateFailed)
        let strict = try R.scene(R.allKinds)
        XCTAssertEqual(controller.scene?.source, strict.source)
        XCTAssertEqual(controller.scene?.items, strict.items)
    }

    @MainActor func testFailedStreamRestoresTheExactPreStreamScene() throws {
        let controller = MGSceneController(scene: try R.scene(R.patchBase))
        let before = controller.scene
        controller.beginStream()
        controller.feed(#"{"v":1,"items":[{"id":"dot","k":"body","at":[3,4]},"#)
        XCTAssertNotNil(controller.scene?.item("dot"), "a preview replaced the scene while streaming")
        controller.feed(#"{"id":"bad","k":"rocket"}]}"#)
        XCTAssertFalse(controller.endStream())
        XCTAssertEqual(controller.scene, before)                     // same items, source and revision
        XCTAssertTrue(controller.lastUpdateFailed)
        XCTAssertFalse(controller.isStreaming)
        // The restored scene is the one earlier patches were written against.
        XCTAssertTrue(controller.apply(patch: try R.patch(#"{"v":1,"rev":0,"ops":[{"op":"title","title":"After"}]}"#)))
    }

    @MainActor func testFeedAndEndWithoutAStreamAreInert() throws {
        let controller = MGSceneController(scene: try R.scene(R.patchBase))
        let before = controller.scene, changes = controller.revision
        controller.feed(R.allKinds)
        XCTAssertFalse(controller.endStream())
        XCTAssertEqual(controller.scene, before)
        XCTAssertEqual(controller.revision, changes)
        XCTAssertFalse(controller.lastUpdateFailed)
    }

    @MainActor func testAcceptedChangesGetStrictlyIncreasingSceneRevisions() throws {
        let base = try R.scene(R.patchBase)
        let controller = MGSceneController(scene: base)
        var seen: [Int] = []
        func record() { if let r = controller.scene?.revision, r != seen.last { seen.append(r) } }
        record()
        XCTAssertTrue(controller.apply(patch: try R.patch(R.ops([#"{"op":"title","title":"Patched"}"#]))))
        record()
        controller.show(base)
        record()
        controller.beginStream()
        for character in R.edgeFirst { controller.feed(String(character)); record() }
        XCTAssertTrue(controller.endStream())
        record()
        XCTAssertGreaterThanOrEqual(seen.count, 5)
        XCTAssertTrue(zip(seen, seen.dropFirst()).allSatisfy { $0 < $1 }, "\(seen)")
    }
}
