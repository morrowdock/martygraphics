// SPDX-License-Identifier: Apache-2.0
import Foundation
import SwiftUI
import XCTest
import ImageIO
import MartyGraphics
@testable import LessonDemoKit

/// Example tests. They run on macOS (`swift test`) and on an iPad simulator (`xcodebuild test`), where the demo view
/// is laid out and rendered offscreen at iPad sizes.
final class LessonDemoKitTests: XCTestCase {
    func testHeadlessVerifyPasses() {
        let result = RotationLesson.verify()
        XCTAssertTrue(result.ok, result.lines.filter { $0.hasPrefix("FAIL") }.joined(separator: "\n"))
        XCTAssertGreaterThanOrEqual(result.lines.count, 20)
    }

    func testEmbeddedLessonEqualsTheDocsFixture() throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/fixtures/v1/rotation.lesson.json")
        guard let data = try? Data(contentsOf: fixture) else { throw XCTSkip("docs fixture not readable here (simulator sandbox)") }
        XCTAssertEqual(try MGLesson.parse(data: data).get(), try RotationLesson.lesson())
    }

    @MainActor func testDemoViewRendersEveryBeatAtIPadSizes() throws {
        let model = LessonDemoModel(pacing: .speech)
        model.play()
        XCTAssertEqual(model.controller.caption, "This is triangle ABC. Each label shows a corner's coordinates.")
        for k in 0..<5 {
            for size in [CGSize(width: 1366, height: 1024), CGSize(width: 1024, height: 1366), CGSize(width: 1180, height: 820)] {
                let image = ImageRenderer(content: LessonDemoView(model: model).frame(width: size.width, height: size.height)).cgImage
                XCTAssertNotNil(image, "beat \(k) at \(size)")
            }
            if k == 3 {
                XCTAssertTrue(model.controller.control("angle", 45))
                XCTAssertEqual(model.controller.state?.scene.item("lA")?.text, "A (0.71, 2.12)")
                XCTAssertEqual(model.controller.board.transition, .direct, "a slider update adopts directly")
            }
            model.controller.lineEnded(k)
        }
        XCTAssertEqual(model.controller.state?.scene.item("lA")?.text, "A (-2, -1)")
        XCTAssertTrue(model.controller.session.isComplete || model.controller.session.nextWake != nil)
    }

    @MainActor func testSliderSnapsToItsStepAndSendsTheScriptCommand() throws {
        let model = LessonDemoModel(pacing: .immediate)
        model.play()
        XCTAssertTrue(model.controller.control("angle", 47.4))
        XCTAssertEqual(model.controller.state?.value("theta"), 45)
        XCTAssertEqual(model.controller.session.log.last?.origin, .learner)
        XCTAssertEqual(model.controller.session.log.last?.command,
                       .object(["op": .string("params"), "params": .object(["angle": .number(45)])]))
        XCTAssertFalse(model.controller.control("zoom", 1))
    }

    func testCapturePlanUsesEngineKeyframesAndThePacingClock() throws {
        let plan = try LessonCapture.plan()
        XCTAssertEqual(plan.frames.map(\.at), plan.frames.map(\.at).sorted())
        XCTAssertEqual(Set(plan.frames.map(\.beat)), [0, 1, 2, 3, 4])
        XCTAssertLessThan(plan.frames.last!.at, plan.complete)
        XCTAssertEqual(plan.lineDue.count, 5)
        for beat in [1, 4] {
            let keys = plan.frames.filter { $0.beat == beat }.compactMap { f -> MGScene? in if case .keyframe = f.kind { return f.scene }; return nil }
            // The segment's first frame is the start scene, then 18 (90°) or 27 (135°) engine keyframes at most 5° apart;
            // the last keyframe's time is the settled frame's time, so the settled state is shown there instead.
            XCTAssertEqual(keys.count, beat == 1 ? 18 : 27)
            let angles = keys.compactMap { $0.values["theta"]?.value }
            XCTAssertEqual(angles.first, beat == 1 ? 0 : 45)
            XCTAssertEqual(angles.last, beat == 1 ? 85 : 175)
            for (a, b) in zip(angles, angles.dropFirst()) { XCTAssertLessThanOrEqual(abs(b - a), 5 + 1e-9) }
            // Labels on every keyframe are engine values that match the reference rotation of that frame.
            for (scene, angle) in zip(keys, angles) {
                let triangle = [("A", (2.0, 1.0)), ("B", (4.0, 1.0)), ("C", (2.0, 3.0))]
                XCTAssertEqual(["lA", "lB", "lC"].compactMap { scene.item($0)?.text },
                               triangle.map { RotationLesson.label($0.0, RotationLesson.rotate($0.1, angle)) })
            }
            let segmentTime = plan.frames.filter { $0.beat == beat && $0.kind != .beat }.map(\.at)
            XCTAssertEqual(segmentTime.last! - segmentTime.first!, 1.5, accuracy: 1e-9, "settled when the 1.5 s animate ends")
        }
        let learner = plan.frames.compactMap { f -> Double? in if case .learner(let a) = f.kind { return a }; return nil }
        XCTAssertEqual(learner, LessonCapture.learnerAngles)
        XCTAssertTrue(plan.frames.filter { if case .learner = $0.kind { return true }; return false }.allSatisfy { $0.beat == 3 })
        XCTAssertEqual(try LessonCapture.plan(), plan, "deterministic")
    }

    func testGIFDelaysKeepTheTotalAndTheWriterLoops() throws {
        let delays = LessonCapture.gifDelays([0, 0.083, 0.167, 0.25, 1.0], end: 3.004)
        XCTAssertEqual(delays.reduce(0, +), 300)
        XCTAssertEqual(delays, [8, 9, 8, 75, 200])
        let ctx = CGContext(data: nil, width: 8, height: 6, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 6))
        let image = ctx.makeImage()!
        XCTAssertEqual(LessonCapture.scaled(image, width: 4)?.height, 3)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lesson-capture-\(UUID().uuidString).gif")
        defer { try? FileManager.default.removeItem(at: url) }
        try LessonCapture.writeGIF([image, image], delays: [8, 200], to: url)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetCount(source), 2)
        let props = CGImageSourceCopyPropertiesAtIndex(source, 1, nil) as? [CFString: Any]
        let gif = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        XCTAssertEqual(gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double ?? 0, 2.0, accuracy: 1e-6)
        XCTAssertThrowsError(try LessonCapture.writeGIF([image], delays: [], to: url))
    }
}
