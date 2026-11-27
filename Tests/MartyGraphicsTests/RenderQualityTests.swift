// SPDX-License-Identifier: Apache-2.0
import AVFoundation
import CoreGraphics
import Foundation
import SwiftUI
import XCTest
@_spi(Experimental) @testable import MartyGraphics

/// The render-quality layer (docs/ENGINE.md): bounded easing and the opt-in step transitions with a reduced-motion
/// dissolve (`MGTransitionStyle.bounded`; the default board keeps its spring, `BoardTransitionTests`), label placement
/// with leader lines, arrowhead geometry, the cached base layer, and the export presets. Numeric goldens; the one pixel
/// check here compares the two layers with the one-Canvas frame they replace for one input (the hosted multi-tick check
/// is `BoardTransitionHostTests`).
final class RenderQualityTests: XCTestCase {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    // MARK: Easing and transitions

    func testEveryCurveIsBoundedMonotoneAndExactAtTheEnds() {
        for curve in MGEasing.Curve.allCases {
            XCTAssertEqual(curve.at(0), 0, accuracy: 1e-12, curve.rawValue)
            XCTAssertEqual(curve.at(1), 1, accuracy: 1e-12, curve.rawValue)
            XCTAssertEqual(curve.at(-3), 0, curve.rawValue)
            XCTAssertEqual(curve.at(7), 1, curve.rawValue)
            XCTAssertEqual(curve.at(.nan), 0, curve.rawValue)
            XCTAssertEqual(curve(0.25), curve.at(0.25), curve.rawValue)
            var previous = 0.0
            for k in 0...1000 {
                let v = curve.at(Double(k) / 1000)
                XCTAssertGreaterThanOrEqual(v, previous - 1e-15, "\(curve.rawValue) turns back at \(k)")
                XCTAssertTrue((0...1).contains(v), "\(curve.rawValue) leaves 0...1 at \(k)")
                previous = v
            }
        }
        XCTAssertEqual(MGEasing.Curve.smooth.at(0.5), 0.5, accuracy: 1e-12)
        XCTAssertEqual(MGEasing.Curve.smoother.at(0.5), 0.5, accuracy: 1e-12)
        XCTAssertEqual(MGEasing.Curve.easeOut.at(0.5), 0.875, accuracy: 1e-12)
        XCTAssertEqual(MGEasing.Curve.settle.at(0.48), 0.9, accuracy: 0.01)
        // What the board used before: the spring overshoots its target by about 12 %.
        XCTAssertGreaterThan((0...120).map { MGTimeline.spring(Double($0) / 100) }.max() ?? 0, 1.1)
    }

    func vectors() -> (MGItem, MGItem) {
        var a = MGItem(id: "v", kind: .vector, color: .force)
        a.pts = [MGPoint(0, 0)]; a.num = ["angle": 350, "len": 2]
        var b = a
        b.pts = [MGPoint(4, 2)]; b.num = ["angle": 20, "len": 6]
        return (a, b)
    }

    func testStepTransitionsStayBetweenTheTwoStates() throws {
        let (a, b) = vectors()
        let leaving = MGMake.body("old", MGPoint(1, 1)), entering = MGMake.body("new", MGPoint(5, 5))
        let t = MGStepTransition()
        XCTAssertEqual(t.duration, 0.6)
        for k in 0...60 {
            let elapsed = Double(k) / 60 * t.duration
            let f = t.frame(from: [a, leaving], to: [b, entering], elapsed: elapsed)
            let v = try XCTUnwrap(f.items.first { $0.id == "v" })
            XCTAssertTrue((2...6).contains(v.n("len")), "length \(v.n("len")) left 2...6 at \(elapsed) s")
            XCTAssertTrue((0...4).contains(v.pts[0].x) && (0...2).contains(v.pts[0].y), "position left the box at \(elapsed) s")
            XCTAssertTrue((350...380).contains(v.n("angle")), "angle \(v.n("angle")) overshot or took the long way at \(elapsed) s")
            XCTAssertEqual(f.opacity["old"] ?? 0, 1 - t.progress(elapsed), accuracy: 1e-12, "the leaving item fades out")
            XCTAssertNil(f.opacity["new"], "an entering item draws on instead")
        }
        let done = t.frame(from: [a, leaving], to: [b, entering], elapsed: t.duration)
        XCTAssertEqual(done.items, [b, entering])
        XCTAssertTrue(done.opacity.isEmpty)
        XCTAssertEqual(t.progress(-1), 0); XCTAssertEqual(t.progress(.nan), 0); XCTAssertEqual(t.progress(10), 1)
        XCTAssertEqual(t.progress(t.duration / 2), 0.5, accuracy: 1e-12)
    }

    func testReduceMotionDissolvesWithoutMoving() throws {
        let (a, b) = vectors()
        let leaving = MGMake.body("old", MGPoint(1, 1)), entering = MGMake.body("new", MGPoint(5, 5))
        let t = MGStepTransition(reduceMotion: true)
        for elapsed in [0.0, 0.1, 0.3, 0.45] {
            let f = t.frame(from: [a, leaving], to: [b, entering], elapsed: elapsed)
            XCTAssertEqual(f.items.first { $0.id == "v" }, b, "nothing moves with Reduce Motion")
            XCTAssertEqual(f.opacity["new"] ?? -1, t.progress(elapsed), accuracy: 1e-12)
            XCTAssertEqual(f.opacity["old"] ?? -1, 1 - t.progress(elapsed), accuracy: 1e-12)
            XCTAssertNil(f.opacity["v"])
        }
        // The 2D loop runs for the dissolve only, and never for motion.
        let s = MGRenderPolicy.State(motionPlaying: true, transientActive: true, visible: true, sceneActive: true, reduceMotion: true)
        XCTAssertFalse(MGRenderPolicy.continuous(s))
        XCTAssertTrue(MGRenderPolicy.dissolving(s))
        var settled = s
        settled.transientActive = false
        XCTAssertFalse(MGRenderPolicy.dissolving(settled))
    }

    func testDissolveAndLayerPolicyTruthTable() {
        for motion in [false, true] { for transient in [false, true] { for visible in [false, true] { for active in [false, true] { for reduce in [false, true] {
            let s = MGRenderPolicy.State(motionPlaying: motion, transientActive: transient, visible: visible, sceneActive: active, reduceMotion: reduce)
            XCTAssertEqual(MGRenderPolicy.dissolving(s), visible && active && reduce && transient)
            XCTAssertEqual(MGRenderPolicy.layered(s), visible && active && !reduce && motion && !transient)
        } } } } }
    }

    // MARK: Labels

    func testAFreeLabelSitsInItsOwnDirectionWithoutALeader() {
        let r = MGLayout.LabelRequest(id: "a", anchor: CGPoint(x: 100, y: 100), direction: CGVector(dx: 1, dy: 0), size: CGSize(width: 40, height: 20))
        let placed = MGLabelLayout.place([r], obstacles: [], bounds: CGRect(x: 0, y: 0, width: 400, height: 300))
        XCTAssertEqual(placed["a"]?.box, CGRect(x: 108, y: 90, width: 40, height: 20))
        XCTAssertNil(placed["a"]?.leader)
    }

    func testCrowdedLabelsNeverOverlapAndFarOnesPointBack() throws {
        let requests = (0..<8).map {
            MGLayout.LabelRequest(id: "l\($0)", anchor: CGPoint(x: 300, y: 200), direction: CGVector(dx: 1, dy: 0), size: CGSize(width: 70, height: 22))
        }
        let obstacle = CGRect(x: 280, y: 180, width: 40, height: 40)
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 500)
        let placed = MGLabelLayout.place(requests, obstacles: [obstacle], bounds: bounds)
        XCTAssertEqual(placed.count, 8)
        XCTAssertEqual(placed, MGLabelLayout.place(requests, obstacles: [obstacle], bounds: bounds), "deterministic")
        let boxes = try requests.map { try XCTUnwrap(placed[$0.id]).box }
        for i in boxes.indices { for j in boxes.indices where j > i {
            XCTAssertFalse(boxes[i].insetBy(dx: -1, dy: -1).intersects(boxes[j]), "labels \(i) and \(j) touch")
        } }
        var leaders: [MGLabelLayout.Leader] = []
        for (r, box) in zip(requests, boxes) {
            XCTAssertTrue(bounds.contains(box), r.id)
            XCTAssertFalse(box.intersects(obstacle), "\(r.id) covers the body it names")
            XCTAssertEqual(box.minX, box.minX.rounded(), "\(r.id) is off the point grid")
            XCTAssertEqual(box.minY, box.minY.rounded(), "\(r.id) is off the point grid")
            let near = MGLabelLayout.nearest(r.anchor, on: box)
            let gap = hypot(near.x - r.anchor.x, near.y - r.anchor.y)
            let p = try XCTUnwrap(placed[r.id])
            if gap > MGLabelLayout.Options().leaderDistance {
                let l = try XCTUnwrap(p.leader, "\(r.id) sits \(gap) pt from its anchor without a leader")
                XCTAssertEqual(l.from, r.anchor)
                XCTAssertEqual(l.to, near)
                leaders.append(l)
            } else {
                XCTAssertNil(p.leader)
            }
        }
        // The anchor is inside the obstacle, so no position is clean without a leader.
        XCTAssertEqual(leaders.count, 8)
        for (k, l) in leaders.enumerated() {
            for (j, box) in boxes.enumerated() where j != k { XCTAssertFalse(MGLabelLayout.crosses(l, box), "leader \(k) crosses label \(j)") }
            for (j, other) in leaders.enumerated() where j != k { XCTAssertFalse(MGLabelLayout.crosses(l, other), "leaders \(k) and \(j) cross") }
        }
    }

    func testSegmentTests() {
        let box = CGRect(x: 10, y: 10, width: 20, height: 20)
        XCTAssertTrue(MGLabelLayout.crosses(.init(from: CGPoint(x: 0, y: 20), to: CGPoint(x: 40, y: 20)), box))
        XCTAssertFalse(MGLabelLayout.crosses(.init(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 40, y: 0)), box))
        XCTAssertFalse(MGLabelLayout.crosses(.init(from: CGPoint(x: 0, y: 20), to: CGPoint(x: 10, y: 20)), box), "ending on the edge is not crossing")
        let a = MGLabelLayout.Leader(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 10, y: 10))
        XCTAssertTrue(MGLabelLayout.crosses(a, .init(from: CGPoint(x: 0, y: 10), to: CGPoint(x: 10, y: 0))))
        XCTAssertFalse(MGLabelLayout.crosses(a, .init(from: CGPoint(x: 0, y: 0), to: CGPoint(x: -10, y: 5))), "a shared anchor is not a crossing")
        XCTAssertEqual(MGLabelLayout.snapped(CGRect(x: 10.4, y: 7.6, width: 33.3, height: 20), 1), CGRect(x: 10, y: 8, width: 33.3, height: 20))
    }

    // MARK: Arrows

    func testArrowHeadsKeepTheirProportions() throws {
        let long = try XCTUnwrap(MGArrowGeometry.make(from: .zero, to: CGPoint(x: 100, y: 0), width: 3.2))
        XCTAssertEqual(long.headLength, 14.2, accuracy: 1e-9)
        XCTAssertEqual(long.tip, CGPoint(x: 100, y: 0))
        XCTAssertEqual(long.left.x, 100 - 14.2, accuracy: 1e-9)
        XCTAssertEqual(long.right.x, 100 - 14.2, accuracy: 1e-9)
        XCTAssertEqual(abs(long.left.y), 14.2 * 0.55, accuracy: 1e-9)
        XCTAssertEqual(long.left.y, -long.right.y, accuracy: 1e-12)
        XCTAssertEqual(long.shaftEnd.x, 100 - 14.2 + 1.6, accuracy: 1e-9, "the shaft ends under the head")
        XCTAssertTrue(long.drawsShaft)
        XCTAssertEqual(MGArrowGeometry.headLength(width: 1, length: 1000), 7, "at least 7 points")
        XCTAssertEqual(MGArrowGeometry.headLength(width: 10, length: 1000), 16, "at most 16 points")
        // While an arrow draws on from length 0, its head never reaches behind the tail and never shrinks as it grows.
        var previous: CGFloat = 0
        for k in 1...200 {
            let d = CGFloat(k) * 0.5
            guard let g = MGArrowGeometry.make(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 10 + d * 0.6, y: 10 + d * 0.8), width: 3.2) else {
                XCTAssertLessThanOrEqual(d, 0.5); continue
            }
            XCTAssertLessThanOrEqual(g.headLength, d * 0.45 + 1e-9)
            XCTAssertGreaterThanOrEqual(g.headLength, previous - 1e-9)
            previous = g.headLength
            let along = (g.shaftEnd.x - 10) * 0.6 + (g.shaftEnd.y - 10) * 0.8
            XCTAssertGreaterThanOrEqual(along, 0, "the shaft points backwards at length \(d)")
            XCTAssertLessThanOrEqual(along, d)
        }
        XCTAssertNil(MGArrowGeometry.make(from: .zero, to: CGPoint(x: 0.3, y: 0), width: 2))
        // A dashed shaft ends on the end of a whole dash, so the head never floats after a gap.
        for length in stride(from: CGFloat(1), through: 200, by: 7.3) {
            let phase = MGArrowGeometry.dashPhase(length: length, dash: 7, gap: 5)
            XCTAssertGreaterThanOrEqual(phase, 0)
            XCTAssertLessThan(phase, 12)
            XCTAssertEqual((length + phase).truncatingRemainder(dividingBy: 12), 7, accuracy: 1e-9)
        }
    }

    // MARK: Layers

    static let layered = #"{"v":1,"world":{"w":12,"h":8},"items":[{"id":"zone","k":"region","pts":[[1,1],[5,1],[5,4],[1,4]]},{"id":"floor","k":"line","from":[0,1],"to":[12,1]},{"id":"dot","k":"body","at":[3,4],"shape":"ball","size":1,"move":{"to":[7,4],"t":2}},{"id":"push","k":"vector","on":"dot","angle":0,"len":2,"label":"Push"},{"id":"note","k":"text","at":[6,7],"text":"Synthetic motion"}]}"#

    func testTheBaseLayerIsTheStaticPrefixOfTheDrawOrder() throws {
        let scene = try MGParser.scene(data: Data(Self.layered.utf8)).get()
        let items = MGTimeline.frame(scene, items: scene.items, time: 0.5)
        let live = MGCanvasLayers.live(scene, items: items)
        XCTAssertEqual(live, ["dot", "push"], "the moving body and the vector on it")
        let base = MGCanvasLayers.base(items, live: live)
        XCTAssertEqual(base, ["zone", "floor"], "the text draws above the body, so it stays live")
        let order = MGCanvasRenderer.ordered(items).map(\.id)
        XCTAssertEqual(order, ["zone", "floor", "dot", "push", "note"])
        XCTAssertEqual(order.filter { base.contains($0) } + order.filter { !base.contains($0) }, order, "two layers keep one frame's order")
        XCTAssertTrue(MGCanvasLayer.base(base).draws("zone")); XCTAssertFalse(MGCanvasLayer.base(base).draws("dot"))
        XCTAssertFalse(MGCanvasLayer.live(base).draws("zone")); XCTAssertTrue(MGCanvasLayer.live(base).draws("note"))
        XCTAssertTrue(MGCanvasLayer.all.drawsBoard && MGCanvasLayer.all.drawsOverlays)
        XCTAssertFalse(MGCanvasLayer.live(base).drawsBoard); XCTAssertFalse(MGCanvasLayer.base(base).drawsOverlays)
    }

    /// RGBA bytes of an image drawn into an sRGB context of its size, with `over` drawn first when given.
    func bytes(_ image: CGImage, over: CGImage? = nil) throws -> [UInt8] {
        let w = image.width, h = image.height
        var out = [UInt8](repeating: 0, count: w * h * 4)
        try out.withUnsafeMutableBytes { buf in
            let ctx = try XCTUnwrap(CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            if let over { ctx.draw(over, in: CGRect(x: 0, y: 0, width: w, height: h)) }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return out
    }

    @MainActor func testTheTwoLayersCompositeToTheOneCanvasFrame() throws {
        let scene = try MGParser.scene(data: Data(Self.layered.utf8)).get()
        let size = CGSize(width: 480, height: 320)
        let items = MGTimeline.frame(scene, items: scene.items, time: 0.5)
        let input = MGRenderInput(scene: scene, items: items, viewport: MGViewport(size: size, width: scene.width, height: scene.height, camera: nil),
                                  time: 0.5)
        let base = MGCanvasLayers.base(items, live: MGCanvasLayers.live(scene, items: items))
        func render(_ layer: MGCanvasLayer) throws -> CGImage {
            let r = ImageRenderer(content: Canvas { ctx, _ in MGCanvasRenderer.draw(input, in: ctx, layer: layer) }.frame(width: size.width, height: size.height))
            r.scale = 1
            return try XCTUnwrap(r.cgImage)
        }
        let one = try bytes(try render(.all)), two = try bytes(try render(.live(base)), over: try render(.base(base)))
        XCTAssertEqual(one.count, two.count)
        var worst = 0, total = 0
        for (x, y) in zip(one, two) { let d = abs(Int(x) - Int(y)); worst = max(worst, d); total += d }
        XCTAssertLessThanOrEqual(worst, 6, "a layer differs from the frame by more than rounding")
        XCTAssertLessThan(Double(total) / Double(one.count), 0.5)
        XCTAssertNotEqual(try bytes(try render(.base(base))), one, "the base alone is not the frame")
    }

    @MainActor func testStepItemsAreCachedPerSceneRevisionAndStep() throws {
        let scene = try XCTUnwrap(MGFixtures.all.first { $0.id == "cells" }?.scene)
        let controller = MGSceneController(scene: scene)
        let cache = MGStepItemsCache()
        let first = try XCTUnwrap(controller.scene)
        XCTAssertEqual(cache.items(first, step: 0, controller: controller), MGTimeline.items(first, step: 0))
        XCTAssertEqual(cache.items(first, step: 1, controller: controller), MGTimeline.items(first, step: 1))
        XCTAssertEqual(cache.items(first, step: 1, controller: controller), MGTimeline.items(first, step: 1))
        let patch = try MGPatch.parse(data: Data(#"{"v":1,"ops":[{"op":"set","id":"grid","key":"marked","value":[[1,1]]}]}"#.utf8)).get()
        XCTAssertTrue(controller.apply(patch: patch))
        let next = try XCTUnwrap(controller.scene)
        XCTAssertNotEqual(next.revision, first.revision)
        XCTAssertEqual(cache.items(next, step: 1, controller: controller), MGTimeline.items(next, step: 1), "a new revision is not served stale")
    }

    // MARK: Export presets

    func testPresetsAreWritableAndTaggedForTheirDestination() {
        for p in MGExportPreset.all { XCTAssertEqual(p.problems, [], p.name) }
        XCTAssertEqual([MGExportPreset.shorts.width, MGExportPreset.shorts.height], [1080, 1920])
        XCTAssertEqual([MGExportPreset.x.width, MGExportPreset.x.height], [1920, 1080])
        XCTAssertEqual([MGExportPreset.lesson.width, MGExportPreset.lesson.height], [1920, 1200])
        XCTAssertEqual(MGExportPreset.shorts.keyframeInterval, 15)
        XCTAssertEqual(MGExportPreset.x.keyframeInterval, 30)
        XCTAssertEqual(MGExportPreset.lesson.keyframeInterval, 60)
        XCTAssertEqual(MGExportPreset.lessonAlpha.keyframeInterval, 1)
        XCTAssertEqual(MGExportPreset.named("x"), MGExportPreset.x)
        XCTAssertNil(MGExportPreset.named("tiktok"))
        XCTAssertEqual(MGExportPreset.shorts.colorProperties[AVVideoTransferFunctionKey] as? String, AVVideoTransferFunction_ITU_R_709_2)
        XCTAssertEqual(MGExportPreset.lesson.colorProperties[AVVideoTransferFunctionKey] as? String, MGExportPreset.srgbTransferFunction)
        // AVFoundation's documented sRGB constant (macOS 15, iOS 18) is the same tag as Core Video's.
        XCTAssertEqual(MGExportPreset.srgbTransferFunction, kCVImageBufferTransferFunction_sRGB as String)
        // Source buffers say what was drawn: sRGB (BT.709 primaries, sRGB transfer) for `srgb` and `rec709`.
        let source = MGExportPreset.shorts.sourceAttachments
        XCTAssertEqual(source[kCVImageBufferColorPrimariesKey as String] as? String, kCVImageBufferColorPrimaries_ITU_R_709_2 as String)
        XCTAssertEqual(source[kCVImageBufferTransferFunctionKey as String] as? String, kCVImageBufferTransferFunction_sRGB as String)
        XCTAssertNil(source[kCVImageBufferAlphaChannelModeKey as String], "an opaque preset says nothing about alpha")
        XCTAssertEqual(MGExportPreset.lessonAlpha.sourceAttachments[kCVImageBufferAlphaChannelModeKey as String] as? String,
                       kCVImageBufferAlphaChannelMode_StraightAlpha as String)
        var p3 = MGExportPreset.lesson
        p3.colorSpace = .displayP3
        XCTAssertEqual(p3.colorProperties[AVVideoColorPrimariesKey] as? String, AVVideoColorPrimaries_P3_D65)
        XCTAssertEqual(p3.drawingSpace.name as String?, CGColorSpace.displayP3 as String)
        XCTAssertEqual(p3.sourceAttachments[kCVImageBufferColorPrimariesKey as String] as? String, kCVImageBufferColorPrimaries_P3_D65 as String,
                       "P3 frames are drawn in P3 and their buffers say so")
        let compression = MGExportPreset.x.outputSettings[AVVideoCompressionPropertiesKey] as? [String: Any]
        XCTAssertEqual(compression?[AVVideoAverageBitRateKey] as? Int, 16_000_000)
        XCTAssertEqual(compression?[AVVideoMaxKeyFrameIntervalKey] as? Int, 30)
        XCTAssertEqual(compression?[AVVideoAllowFrameReorderingKey] as? Bool, false)
        XCTAssertNil(MGExportPreset.lessonAlpha.outputSettings[AVVideoCompressionPropertiesKey], "ProRes is constant quality")
        XCTAssertEqual(MGExportPreset.lessonAlpha.fileExtension, "mov")
        XCTAssertEqual(MGExportPreset.shorts.fileExtension, "mp4")
        var odd = MGExportPreset.shorts
        odd.width = 1079
        XCTAssertEqual(odd.problems, ["evenSize"])
        var alpha = MGExportPreset.x
        alpha.alpha = .straight
        XCTAssertEqual(alpha.problems, ["alpha"], "H.264 carries no alpha")
        var covered = MGExportPreset.x
        covered.safeArea = .init(top: 0.5, left: 0, bottom: 0.5, right: 0)
        XCTAssertEqual(covered.problems, ["safeArea"])
    }

    func testFramesFitThePresetAndTheSafeAreaIsOnWholePixels() {
        XCTAssertEqual(MGExportPreset.shorts.fit(CGSize(width: 1280, height: 720)), CGRect(x: 0, y: 656, width: 1080, height: 608))
        XCTAssertEqual(MGExportPreset.x.fit(CGSize(width: 1280, height: 720)), CGRect(x: 0, y: 0, width: 1920, height: 1080))
        XCTAssertEqual(MGExportPreset.lesson.fit(CGSize(width: 1280, height: 720)), CGRect(x: 0, y: 60, width: 1920, height: 1080))
        XCTAssertEqual(MGExportPreset.lesson.fit(CGSize(width: 1280, height: 800)), CGRect(x: 0, y: 0, width: 1920, height: 1200))
        XCTAssertEqual(MGExportPreset.shorts.safeRect, CGRect(x: 65, y: 423, width: 820, height: 1305))
        XCTAssertEqual(MGExportPreset.lesson.safeRect, CGRect(x: 0, y: 0, width: 1920, height: 1200))
    }

    func testStraightAlphaUndoesPremultiplication() {
        var px: [UInt8] = [64, 32, 16, 128, 10, 20, 30, 255, 7, 7, 7, 0, 255, 255, 255, 255]
        px.withUnsafeMutableBufferPointer { MGVideoPixels.unpremultiply($0.baseAddress!, width: 2, height: 2, bytesPerRow: 8) }
        XCTAssertEqual(Array(px[0..<4]), [128, 64, 32, 128])
        XCTAssertEqual(Array(px[4..<8]), [10, 20, 30, 255], "opaque pixels are unchanged")
        XCTAssertEqual(Array(px[8..<12]), [0, 0, 0, 0], "transparent pixels carry no colour")
        XCTAssertEqual(Array(px[12..<16]), [255, 255, 255, 255])
    }

    func temporaryFolder() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mg-preset-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    func testAPresetWriterWritesItsFrameRateAndTags() throws {
        let url = try temporaryFolder().appendingPathComponent("shorts.mp4")
        var preset = MGExportPreset.shorts
        preset.width = 216; preset.height = 384           // the Shorts settings at a small frame, to stay fast
        let movie = try MGMovieWriter(url: url, preset: preset)
        let ctx = try XCTUnwrap(CGContext(data: nil, width: 128, height: 72, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(CGColor(srgbRed: 0.9, green: 0.2, blue: 0.1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 128, height: 72))
        let frame = try XCTUnwrap(ctx.makeImage())
        for _ in 0..<6 { try movie.append(frame) }
        try movie.finish()
        let track = try XCTUnwrap(AVURLAsset(url: url).tracks(withMediaType: .video).first)
        XCTAssertEqual(track.naturalSize, CGSize(width: 216, height: 384))
        XCTAssertEqual(CMTimeGetSeconds(track.timeRange.duration), 6.0 / 30, accuracy: 1e-9)
        let description = track.formatDescriptions.first as! CMFormatDescription
        XCTAssertEqual(CMFormatDescriptionGetExtension(description, extensionKey: kCMFormatDescriptionExtension_TransferFunction) as? String,
                       kCMFormatDescriptionTransferFunction_ITU_R_709_2 as String)
        var bad = preset
        bad.width = 215
        XCTAssertThrowsError(try MGMovieWriter(url: url.deletingLastPathComponent().appendingPathComponent("bad.mp4"), preset: bad))
    }

    func testA2DVideoExportsWithAPreset() async throws {
        let json = try Data(contentsOf: Self.root.appendingPathComponent("docs/examples/programmatic-video/sorting.json"))
        let plan = try MGProgrammaticVideo.check(try MGParser.scene(data: json, programmaticVideo: true).get(), programmaticVideo: true)
        let folder = try temporaryFolder()
        var preset = MGExportPreset.shorts
        preset.width = 270; preset.height = 480
        let receipt = try await MGProgrammaticVideo.export(plan, to: folder.appendingPathComponent("sorting.mp4"),
                                                           options: .init(format: .mp4, preset: preset), programmaticVideo: true)
        XCTAssertEqual([receipt.width, receipt.height, receipt.fps, receipt.frameCount], [270, 480, 30, plan.durationFrames])
        XCTAssertEqual(receipt.durationSeconds, Double(plan.durationFrames) / 30, accuracy: 1e-9)
        var fast = preset
        fast.fps = 60
        do { _ = try await MGProgrammaticVideo.export(plan, to: folder.appendingPathComponent("fast.mp4"), options: .init(preset: fast), programmaticVideo: true); XCTFail("60 fps") }
        catch { XCTAssertEqual((error as? MGError)?.reason, "video2d.export.presetRate") }
        var short = preset
        short.maxSeconds = 1
        do { _ = try await MGProgrammaticVideo.export(plan, to: folder.appendingPathComponent("short.mp4"), options: .init(preset: short), programmaticVideo: true); XCTFail("too long") }
        catch { XCTAssertEqual((error as? MGError)?.reason, "video2d.export.presetDuration") }
    }
}
