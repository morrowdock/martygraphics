// SPDX-License-Identifier: Apache-2.0
import Foundation
import SwiftUI
import XCTest
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
}
