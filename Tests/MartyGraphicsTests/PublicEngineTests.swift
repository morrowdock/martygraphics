// SPDX-License-Identifier: Apache-2.0
import XCTest
import SwiftUI
import SceneKit
@testable import MartyGraphics

final class PublicEngineTests: XCTestCase {
    func testSyntheticFixturesAndRoundTrips() throws {
        for fixture in MGFixtures.all {
            let scene = try MGParser.scene(data: Data(fixture.json.utf8)).get()
            XCTAssertFalse(scene.items.isEmpty, fixture.id)
            let context = MGContext(width: scene.width, height: scene.height, is3D: scene.is3D, values: scene.values)
            for item in scene.items {
                XCTAssertEqual(try MGParser.item(.object(item.wire()), context), item, fixture.id)
            }
        }
    }

    func testUnknownKeysBrokenReferencesAndInvalidNumbersFail() {
        let invalid = [
            #"{"v":1,"unknown":true,"items":[{"id":"dot","k":"body","at":[3,4]}]}"#,
            #"{"v":1,"items":[{"id":"v","k":"vector","on":"missing","angle":0,"len":1}]}"#,
            #"{"v":1,"items":[{"id":"dot","k":"body","at":[true,4]}]}"#,
            #"{"v":1,"items":[{"id":"dot","k":"body","at":[300,4]}]}"#,
            #"{"v":1,"items":[{"id":"dot","k":"body","at":[3,4]},{"id":"dot","k":"body","at":[4,4]}]}"#
        ]
        for json in invalid { XCTAssertThrowsError(try MGParser.scene(data: Data(json.utf8)).get()) }
    }

    func testPatchesRejectStaleRevisionsAndPreserveOriginal() throws {
        let scene = try XCTUnwrap(MGFixtures.all.first { $0.id == "moving_dot" }?.scene)
        let valid = try MGPatch.parse(data: Data(#"{"v":1,"rev":0,"ops":[{"op":"title","title":"Updated dot"}]}"#.utf8)).get()
        let next = try scene.applying(valid).get()
        XCTAssertEqual(next.title, "Updated dot")
        XCTAssertEqual(next.revision, 1)
        XCTAssertThrowsError(try next.applying(valid).get())
        XCTAssertEqual(scene.title, "Moving dot")
        for index in ["1e100", "-1", "0.5", "8"] {
            let json = "{\"v\":1,\"rev\":0,\"ops\":[{\"op\":\"step\",\"index\":\(index)}]}"
            XCTAssertThrowsError(try MGPatch.parse(data: Data(json.utf8)).get())
        }
    }

    func testStreamingMatchesStrictFinalScene() throws {
        for fixture in MGFixtures.all {
            var parser = MGStreamParser()
            for character in fixture.json { _ = parser.feed(String(character)) }
            XCTAssertEqual(try parser.finish().get(), try XCTUnwrap(fixture.scene), fixture.id)
        }
        var broken = MGStreamParser()
        _ = broken.feed(#"{"v":1,"items":[{"id":"dot","k":"rocket"}]}"#)
        XCTAssertThrowsError(try broken.finish().get())
    }

    func testGrammarAndProtocolExamplesMatchParser() throws {
        let grammar = MGGrammar.document()
        XCTAssertEqual((grammar["kinds"] as? [[String: Any]])?.count, MGKind.allCases.count)
        XCTAssertEqual((grammar["templates"] as? [[String: Any]])?.count, MGTemplates.all.count)
        let example = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(MGGrammar.sceneExample.utf8)) as? [String: Any])
        let scene = try MGParser.scene(object: try XCTUnwrap(example["scene"])).get()
        let patch = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(MGGrammar.patchExample.utf8)) as? [String: Any])
        XCTAssertNoThrow(try scene.applying(MGPatch.parse(object: try XCTUnwrap(patch["patch"])).get()).get())
    }

    func testGenericMechanicsAndTemplateRegistry() throws {
        XCTAssertEqual(Set(MGTemplates.all.map(\.name)), Set(MGTemplates.library.keys))
        let force = try XCTUnwrap(MGPhysics.thirdLaw(m1: 5, m2: 10, force: 20))
        XCTAssertEqual(force.a1, 4)
        XCTAssertEqual(force.a2, 2)
        let spring = try XCTUnwrap(MGPhysics.spring(mass: 2, k: 8, compression: 0.5))
        let split = MGPhysics.springSplit(energy: spring.energy, phase: 0.7)
        XCTAssertEqual(split.kinetic + split.spring, spring.energy, accuracy: 1e-12)
        XCTAssertNil(MGPhysics.circular(mass: 1, radius: 0, speed: 1))
    }

    func testEveryCoreTemplateBuildsFromSyntheticParameters() throws {
        let scenes = MGFixtures.all.filter { $0.id == "tree" || $0.id == "pointers" }.map(\.json)
        var built = Set<String>()
        for json in scenes {
            let scene = try MGParser.scene(data: Data(json.utf8)).get()
            built.insert(try XCTUnwrap(scene.template))
            XCTAssertFalse(scene.items.isEmpty)
        }
        XCTAssertEqual(built, Set(MGTemplates.all.map(\.name)))
    }

    func testSyntheticMotionReachesTargetAndReturns() throws {
        let scene = try XCTUnwrap(MGFixtures.all.first { $0.id == "moving_dot" }?.scene)
        func position(_ time: Double) throws -> MGPoint {
            let frame = MGTimeline.frame(scene, items: scene.items, time: time)
            return try XCTUnwrap(frame.first { $0.id == "dot" }?.pts.first)
        }
        XCTAssertEqual(try position(0), MGPoint(3, 4))
        XCTAssertEqual(try position(2), MGPoint(7, 4))
        XCTAssertEqual(try position(4), MGPoint(3, 4))
    }

    @MainActor func testSyntheticRenderersConstruct() throws {
        let scene = try XCTUnwrap(MGFixtures.all.first { $0.id == "moving_dot" }?.scene)
        let size = CGSize(width: 480, height: 320)
        let input = MGRenderInput(scene: scene,
                                  items: MGTimeline.frame(scene, items: scene.items, time: 1),
                                  viewport: MGViewport(size: size, width: scene.width, height: scene.height, camera: nil),
                                  focus: nil, time: 1)
        let renderer = ImageRenderer(content: Canvas { context, _ in
            MGCanvasRenderer.draw(input, in: context)
        }.frame(width: size.width, height: size.height))
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage)
        XCTAssertEqual(image.width, 480)
        XCTAssertEqual(image.height, 320)
        let scene3D = try XCTUnwrap(MGFixtures.all.first { $0.id == "dot_3d" }?.scene)
        let root = SCNNode()
        XCTAssertFalse(MG3DBuilder.build(scene3D.items, scene: scene3D, into: root).isEmpty)
    }

    func testLabelPlacementIsDeterministicAndDoesNotOverlap() {
        let requests = (0..<8).map { MGLayout.LabelRequest(id: "l\($0)", anchor: CGPoint(x: 300, y: 200), direction: CGVector(dx: 1, dy: 0), size: CGSize(width: 70, height: 22)) }
        let obstacles = [CGRect(x: 280, y: 180, width: 40, height: 40)]
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 500)
        let placed = MGLayout.place(requests, obstacles: obstacles, bounds: bounds)
        XCTAssertEqual(placed.count, 8)
        XCTAssertEqual(placed, MGLayout.place(requests, obstacles: obstacles, bounds: bounds))
        let rects = Array(placed.values)
        for a in rects.indices { for b in (a + 1)..<rects.count { XCTAssertFalse(rects[a].intersects(rects[b])) } }
    }

    func testRenderPolicyTruthTable() {
        for motion in [false, true] { for transient in [false, true] { for visible in [false, true] { for active in [false, true] { for reduce in [false, true] {
            let state = MGRenderPolicy.State(motionPlaying: motion, transientActive: transient, visible: visible, sceneActive: active, reduceMotion: reduce)
            XCTAssertEqual(MGRenderPolicy.continuous(state), visible && active && !reduce && (motion || transient))
            XCTAssertEqual(MGRenderPolicy.sceneKitPlaying(state), visible && active && !reduce && motion)
        } } } } }
    }

    @MainActor func testControllerRestoresSceneAfterInvalidStream() throws {
        let scene = try XCTUnwrap(MGFixtures.all.first { $0.id == "moving_dot" }?.scene)
        let controller = MGSceneController(scene: scene)
        let before = controller.scene
        controller.beginStream()
        controller.feed(#"{"v":1,"items":[{"id":"bad","k":"rocket"}]}"#)
        XCTAssertFalse(controller.endStream())
        XCTAssertEqual(controller.scene, before)
        XCTAssertTrue(controller.lastUpdateFailed)
    }
}
