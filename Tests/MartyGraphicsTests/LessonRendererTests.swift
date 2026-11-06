// SPDX-License-Identifier: Apache-2.0
import Foundation
import CoreGraphics
import SceneKit
import SwiftUI
import XCTest
@testable import MartyGraphics

/// Acceptance group R (renderer). Adoption decisions, keyframe sampling and hit tests are pure functions shared with
/// the SwiftUI host, so they are tested here without a window; offscreen images use `ImageRenderer`.
final class LessonRendererTests: LessonTestCase {
    typealias F = LessonFixture
    let viewport = MGViewport(size: CGSize(width: 1024, height: 768), width: MGGeometryPack.width, height: MGGeometryPack.height, camera: nil)

    // MARK: R1 direct transition

    func testR1LearnerControlAdoptsDirectlyWithoutBlendOrDrawOnReplay() throws {
        var s = try F.through(beat: 3)
        let shown = s.state!.scene.items
        _ = try s.control("angle", 30).get()
        let change = try XCTUnwrap(s.lastChange)
        XCTAssertEqual(change.transition, .direct)
        let plan = MGAdoption.plan(previous: shown, next: s.state!.scene.items, transition: change.transition)
        XCTAssertFalse(plan.blends)
        XCTAssertTrue(plan.appear.isEmpty, "no draw-on replay for ids already shown")
        XCTAssertTrue(plan.keyframes.isEmpty)
        // With no blend the first frame already shows the committed vertex.
        let v = try XCTUnwrap(s.state!.scene.item("vA")?.pts.first)
        let ref = F.rotate(F.triangle[0], 30)
        let expected = viewport.point(MGGeometryPack.origin + MGPoint(ref.0, ref.1))
        let drawn = viewport.point(v)
        XCTAssertLessThanOrEqual(hypot(drawn.x - expected.x, drawn.y - expected.y), 0.5)
        // The old blend path, kept for scripted changes, is unchanged.
        let blend = MGAdoption.plan(previous: shown, next: s.state!.scene.items, transition: .blend)
        XCTAssertTrue(blend.blends); XCTAssertTrue(blend.appear.isEmpty)
        let first = MGAdoption.plan(previous: nil, next: shown, transition: .direct)
        XCTAssertEqual(Set(first.appear.keys), Set(shown.map(\.id)), "a first appearance still draws everything on")
    }

    @MainActor func testR1ControllerPublishesTheTransition() throws {
        let scene = try MGParser.scene(data: Data(MGGeometryPack.triangleFixture.utf8)).get()
        let controller = MGSceneController(scene: scene)
        XCTAssertEqual(controller.transition, .blend)
        let patch = try MGPatch.parse(json: F.json(#"{"v":1,"ops":[{"op":"params","params":{"angle":40}}]}"#)).get()
        XCTAssertTrue(controller.apply(patch: patch, transition: .direct))
        XCTAssertEqual(controller.transition, .direct)
        XCTAssertTrue(controller.apply(patch: patch))
        XCTAssertEqual(controller.transition, .blend, "existing entry points keep the blend")
    }

    // MARK: R2 scripted add draws on only the new item

    func testR2ScriptedAddDrawsOnOnlyTheNewItem() throws {
        var s = try F.through(beat: 0)
        let shown = s.state!.scene.items
        _ = try s.apply(F.json(#"{"op":"add","item":{"id":"hiB","k":"highlight","target":"vB"}}"#)).get()
        let plan = MGAdoption.plan(previous: shown, next: s.state!.scene.items, transition: s.lastChange!.transition)
        XCTAssertEqual(Array(plan.appear.keys), ["hiB"])
        XCTAssertTrue(plan.blends)
    }

    // MARK: R3 keyframe playback stays on the circle

    func testR3KeyframePlaybackKeepsVerticesOnTheirCircles() throws {
        var s = try F.through(beat: 0)
        let shown = s.state!.scene.items
        _ = try s.apply(F.json(#"{"op":"animate","param":"angle","to":90,"dur":1.5}"#)).get()
        let plan = MGAdoption.plan(previous: shown, next: s.state!.scene.items, transition: s.lastChange!.transition)
        XCTAssertEqual(plan.keyframes.count, 19)
        XCTAssertEqual(plan.duration, 1.5)
        let o = viewport.point(MGGeometryPack.origin)
        for fraction in [0.25, 0.5, 0.75] {
            let items = MGTween.sample(plan.keyframes, at: fraction)
            for (k, letter) in ["A", "B", "C"].enumerated() {
                let p = viewport.point(try XCTUnwrap(items.first { $0.id == "v\(letter)" }?.pts.first))
                let r = viewport.length(hypot(F.triangle[k].0, F.triangle[k].1))
                XCTAssertEqual(hypot(p.x - o.x, p.y - o.y), r, accuracy: 0.5, "\(letter) at \(fraction)")
            }
            // Labels show a number some keyframe computed, never a blend of two.
            let label = try XCTUnwrap(items.first { $0.id == "ltheta" }?.text)
            let theta = try XCTUnwrap(F.numbers(label).first)
            XCTAssertEqual(theta.truncatingRemainder(dividingBy: 5), 0, label)
        }
        // A highlight added after the turn in the same beat draws on once the turn is over.
        var t = try F.through(beat: 3)
        let before = t.state!.scene.items
        _ = try t.apply([F.json(#"{"op":"animate","param":"angle","to":180,"dur":1.5}"#),
                         F.json(#"{"op":"add","item":{"id":"hiShape","k":"highlight","target":"shape"}}"#)]).get()
        let late = MGAdoption.plan(previous: before, next: t.state!.scene.items, transition: t.lastChange!.transition)
        XCTAssertEqual(late.appear, ["hiShape": 1.5])
    }

    // MARK: R4 selection by stable id

    func testR4TappingAVertexSelectsItsStableId() throws {
        var s = try F.through(beat: 0)
        for angle in [0.0, 90, 180] {
            _ = try s.apply(MGLessonEngine.paramsCommand("angle", angle)).get()
            let items = MGTimeline.items(s.state!.scene, step: 0)
            let point = viewport.point(try XCTUnwrap(s.state!.scene.item("vA")?.pts.first))
            XCTAssertEqual(MGLayout.hit(point, items: items, viewport: viewport)?.id, "vA", "angle \(angle)")
        }
        var learner = try F.through(beat: 3)
        for angle in [15.0, 200, 355] {
            _ = try learner.control("angle", angle).get()
            let point = viewport.point(try XCTUnwrap(learner.state!.scene.item("vB")?.pts.first))
            XCTAssertEqual(MGLayout.hit(point, items: learner.state!.scene.items, viewport: viewport)?.id, "vB")
        }
        XCTAssertEqual(learner.describe("vB")?["id"], .string("vB"))
        XCTAssertEqual(learner.describe("vB")?["values"]?["bx"], .number(learner.state!.value("bx")!))
        XCTAssertNil(learner.describe("nope"))
    }

    // MARK: R5 labels do not overlap; beat images

    func testR5CoordinateLabelsNeverOverlapAtAnyAngle() throws {
        var s = try F.through(beat: 3)
        for size in [CGSize(width: 1024, height: 768), CGSize(width: 1366, height: 1024)] {
            let vp = MGViewport(size: size, width: MGGeometryPack.width, height: MGGeometryPack.height, camera: nil)
            for angle in stride(from: 0.0, through: 360, by: 5) {
                _ = try s.control("angle", angle).get()
                let items = s.state!.scene.items
                let labels = ["lA", "lB", "lC", "ltheta"].compactMap { id in items.first { $0.id == id }.flatMap { MGLayout.bounds($0, in: items, vp) } }
                XCTAssertEqual(labels.count, 4)
                for i in labels.indices { for j in labels.indices where j > i {
                    XCTAssertFalse(labels[i].intersects(labels[j]), "labels \(i) and \(j) overlap at \(angle)° on \(size)")
                } }
                // Each coordinate label stays clear of every vertex dot.
                let dots = ["vA", "vB", "vC"].compactMap { id in items.first { $0.id == id }.flatMap { MGLayout.bounds($0, in: items, vp) } }
                for l in labels.prefix(3) { for d in dots { XCTAssertFalse(l.intersects(d), "label over a dot at \(angle)°") } }
            }
        }
    }

    @MainActor func testR5BeatImagesRenderOffscreen() throws {
        var s = F.session(.speech)
        s.feed(try F.stream())
        var receipts: [String] = []
        for k in 0..<5 {
            let scene = s.state!.scene
            for size in [CGSize(width: 1024, height: 768), CGSize(width: 1366, height: 1024)] {
                let vp = MGViewport(size: size, width: scene.width, height: scene.height, camera: nil)
                let input = MGRenderInput(scene: scene, items: MGTimeline.items(scene, step: 0), viewport: vp)
                let renderer = ImageRenderer(content: Canvas { ctx, _ in MGCanvasRenderer.draw(input, in: ctx) }.frame(width: size.width, height: size.height))
                let image = try XCTUnwrap(renderer.cgImage, "beat \(k) \(size)")
                XCTAssertEqual(image.width, Int(size.width))
                receipts.append("beat\(k)@\(Int(size.width))")
            }
            s.lineEnded(k)
        }
        print("R5 offscreen beat images: \(receipts.joined(separator: " "))")
    }

    // MARK: R6 solid regression

    func testR6SolidMaterialOnlyChangeKeepsNodeIdentity() {
        let mesh = MGMesh.cylinder(radius: 2, to: 2, segments: 16)
        let a = MGAssembly(name: "m", parts: [
            MGPart(id: "a", name: "a", mesh: mesh, material: .brass),
            MGPart(id: "b", name: "b", mesh: mesh, material: .brass, placement: .translation(MGVec3(10, 0, 0))),
        ])
        let r = MGSolidRenderer(assembly: a)
        let before = ["a", "b"].map { ObjectIdentifier(r.scene.rootNode.childNode(withName: $0, recursively: true)!) }
        var next = a
        next.parts[1].material = .bronze
        r.setAssembly(next)
        let after = ["a", "b"].map { ObjectIdentifier(r.scene.rootNode.childNode(withName: $0, recursively: true)!) }
        XCTAssertEqual(before, after)
    }
}
