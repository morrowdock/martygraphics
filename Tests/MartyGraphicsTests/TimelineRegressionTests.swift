// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import MartyGraphics

/// Timeline invariants: step state is a pure, clamped function of (scene, step); motion of (scene, time); blending of
/// (from, to, t). Renderers and tests must agree on these without any hidden state.
final class TimelineRegressionTests: XCTestCase {
    private typealias R = MGRegression

    func testStepGatingAnchorHidingAndCumulativeEdits() throws {
        let scene = try R.scene(R.timeline)
        XCTAssertEqual(MGTimeline.firstShown(scene), ["ball": 1, "nb": 2, "mark": 2])
        func ids(_ step: Int) -> [String] { MGTimeline.items(scene, step: step).map(\.id) }
        // Step 0: the ball (and the vector on it), node B (and the edge to it) and the marker are not shown yet.
        XCTAssertEqual(ids(0), ["na", "arr"])
        XCTAssertEqual(ids(1), ["ball", "push", "na", "arr"])
        XCTAssertEqual(ids(2), ["ball", "push", "na", "nb", "ab", "mark", "arr"])
        func array(_ step: Int) -> MGItem? { MGTimeline.items(scene, step: step).first { $0.id == "arr" } }
        XCTAssertEqual(array(0)?.pointers.map(\.index), [0])
        XCTAssertEqual(array(1)?.pointers.map(\.index), [1])
        XCTAssertEqual(array(1)?.marked, [])
        XCTAssertEqual(array(2)?.pointers.map(\.index), [1])          // step 1's edit carries forward
        XCTAssertEqual(array(2)?.marked, [1])
        // Out-of-range steps clamp; the scene itself never changes.
        XCTAssertEqual(MGTimeline.items(scene, step: -5), MGTimeline.items(scene, step: 0))
        XCTAssertEqual(MGTimeline.items(scene, step: 99), MGTimeline.items(scene, step: 2))
        XCTAssertEqual(scene, try R.scene(R.timeline))
    }

    func testSceneWithoutStepsShowsEverythingAtAnyStep() throws {
        let scene = try R.scene(R.allKinds)
        XCTAssertTrue(scene.steps.isEmpty)
        for step in [-1, 0, 3] { XCTAssertEqual(MGTimeline.items(scene, step: step), scene.items) }
    }

    func testFrameIsPureClampsNegativeTimeAndCarriesAttachedVectors() throws {
        let dot = try XCTUnwrap(MGFixtures.all.first { $0.id == "moving_dot" }?.scene)
        XCTAssertEqual(MGTimeline.frame(dot, items: dot.items, time: -3), MGTimeline.frame(dot, items: dot.items, time: 0))
        XCTAssertEqual(MGTimeline.frame(dot, items: dot.items, time: 1.25), MGTimeline.frame(dot, items: dot.items, time: 1.25))
        let mid = MGTimeline.frame(dot, items: dot.items, time: 1).first { $0.id == "dot" }
        XCTAssertEqual(mid?.pts, [MGPoint(5, 4)])                    // eased halfway; the move target is not drawn

        let glide = try R.scene(R.glide)
        func vectorTail(_ time: Double) -> [MGPoint]? { MGTimeline.frame(glide, items: glide.items, time: time).first { $0.id == "f" }?.pts }
        XCTAssertEqual(vectorTail(0), [MGPoint(2, 4)])
        XCTAssertEqual(vectorTail(2), [MGPoint(6, 4)])
        XCTAssertEqual(vectorTail(4), [MGPoint(2, 4)])
    }

    func testCycleAndRestTime() throws {
        let dot = try XCTUnwrap(MGFixtures.all.first { $0.id == "moving_dot" }?.scene)
        XCTAssertTrue(dot.animates)
        XCTAssertEqual(MGTimeline.cycle(dot), 4)                     // there and back at t = 2 s
        XCTAssertEqual(MGTimeline.restTime(dot, loops: 3), 12)
        XCTAssertEqual(MGTimeline.restTime(dot, loops: 0), 4)        // at least one loop
        for id in ["graph", "tree", "pointers"] {
            let scene = try XCTUnwrap(MGFixtures.all.first { $0.id == id }?.scene)
            XCTAssertFalse(scene.animates, id)
            XCTAssertNil(MGTimeline.cycle(scene), id)
            XCTAssertNil(MGTimeline.restTime(scene, loops: 2), id)
        }
    }

    func testBlendInterpolatesSharedGeometryAndTakesTheShortestTurn() {
        let a = MGMake.vector("v", from: MGPoint(0, 0), angle: 350, len: 2, label: nil, color: .force)
        var b = a
        b.num["angle"] = 10; b.num["len"] = 4; b.pts = [MGPoint(2, 0)]
        let mid = MGTimeline.blend(from: [a], to: [b], t: 0.5).first
        XCTAssertEqual(mid?.num["angle"], 360)                       // 350 -> 10 turns +20, not -340
        XCTAssertEqual(mid?.num["len"], 3)
        XCTAssertEqual(mid?.pts, [MGPoint(1, 0)])
        XCTAssertEqual(MGTimeline.blend(from: [b], to: [a], t: 0.5).first?.num["angle"], 0)
        XCTAssertEqual(MGTimeline.blend(from: [a], to: [b], t: 0).first?.pts, a.pts)
        XCTAssertEqual(MGTimeline.blend(from: [a], to: [b], t: 1), [b])
        XCTAssertEqual(MGTimeline.blend(from: [a], to: [b], t: 1.4), [b])

        var node = MGItem(id: "v", kind: .node, color: .blue)       // same id, different kind: no blending
        node.pts = [MGPoint(5, 5)]; node.text = "N"
        XCTAssertEqual(MGTimeline.blend(from: [a], to: [node], t: 0.5), [node])
        let fresh = MGMake.body("new", MGPoint(1, 1))               // new items arrive as-is
        XCTAssertEqual(MGTimeline.blend(from: [a], to: [fresh], t: 0.5), [fresh])

        var cells = MGItem(id: "arr", kind: .array, color: .blue)
        cells.pts = [MGPoint(6, 4)]; cells.list = ["1", "2", "3"]; cells.pointers = [MGPointer(index: 0, label: "p")]
        var moved = cells
        moved.pointers = [MGPointer(index: 2, label: "p")]
        XCTAssertEqual(MGTimeline.blend(from: [cells], to: [moved], t: 0.25).first?.pointers.first?.index, 0.5)
    }

    func testSpringSettlesExactly() {
        XCTAssertEqual(MGTimeline.spring(0), 0)
        XCTAssertEqual(MGTimeline.spring(1.2), 1)
        XCTAssertEqual(MGTimeline.spring(10), 1)
        XCTAssertGreaterThan(MGTimeline.spring(0.4), 1)              // a little overshoot before settling
    }
}
