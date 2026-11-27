// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
import MartyGraphics
@testable import MartySolidGLTF

/// `marty-solid export-gltf --seamless` (`MGSolidGLTF.seamlessLoop`, docs/ENGINE.md "Seamless loops") on the
/// robot-joint gearbox: the default export's output carrier advances 0.082° a frame and then jumps 29.306° back at the
/// wrap; the seamless export plays the exact period (49/6 input turns) with no jump, keys a closing frame and records
/// the loop for the render path.
final class SeamlessLoopExportTests: XCTestCase {
    func checked() throws -> MGSolidGLTF.Checked {
        let data = try Data(contentsOf: MartySolidGLTFTests.gearbox)
        guard case .success(let c) = MGSolidGLTF.check(data: data) else {
            XCTFail("the gearbox must pass the strict check")
            throw MGSolidGLTF.Refusal("test.check")
        }
        return c
    }

    func testTheSeamlessExportHasNoJumpAtTheWrap() throws {
        let c = try checked()
        let a = c.document.assembly
        let period = try MGSolidLoop.period(c.document).get()

        // The default export: one input turn in 360 frames.
        let plain = try MGSolidGLTF.renderLoop(c, fps: 30)
        XCTAssertNil(plain.loop)
        XCTAssertEqual(plain.poses.count, 360)
        let carrier = try XCTUnwrap(MGSolidLoop.wrap(a, poses: plain.poses, symmetry: period.symmetry).first { $0.part == "carrier2" })
        XCTAssertEqual(carrier.step, 4.0 / 49, accuracy: 1e-9, "0.082° a frame")
        XCTAssertEqual(carrier.jump, -4.0 / 49 * 359, accuracy: 1e-9, "29.306° back at the wrap")

        // The seamless export: 49/6 input turns over 490 frames, then the closing frame.
        let t = try MGSolidGLTF.seamlessLoop(c, fps: 30)
        let loop = try XCTUnwrap(t.loop)
        XCTAssertEqual(loop.inputTurns, "49/6")
        XCTAssertEqual(loop.frames, 490)
        XCTAssertEqual(t.poses.count, 491, "the loop frames and the closing frame")
        XCTAssertEqual(t.cameras.count, 491)
        let rows = MGSolidLoop.wrap(a, poses: Array(t.poses.prefix(loop.frames)), closing: t.poses[loop.frames], symmetry: period.symmetry)
        XCTAssertFalse(rows.isEmpty)
        XCTAssertLessThan(MGSolidLoop.worst(rows)?.error ?? 1, 1e-7)
        // The animated camera closes the loop too.
        XCTAssertLessThan((t.cameras[loop.frames].position - t.cameras[0].position).length, 1e-6 * max(1, t.cameras[0].position.length))

        // The manifest tells the render path: frameCount counts the closing frame, `loop` names the loop frames.
        let o = try MGSolidGLTF.export(c, timeline: t, sourceID: "robot-joint-gearbox", glbName: "robot-joint-gearbox.glb",
                                       engineCommit: MartySolidGLTFTests.commit)
        let m = o.manifest
        XCTAssertEqual(m["frameCount"], .number(491))
        XCTAssertEqual(m["loop"]?["seamless"], .bool(true))
        XCTAssertEqual(m["loop"]?["frames"], .number(490))
        XCTAssertEqual(m["loop"]?["closingFrame"], .number(490))
        XCTAssertEqual(m["loop"]?["inputTurns"], .string("49/6"))
        XCTAssertNil(try MGSolidGLTF.export(c, timeline: plain, sourceID: "robot-joint-gearbox", glbName: "robot-joint-gearbox.glb",
                                            engineCommit: MartySolidGLTFTests.commit).manifest["loop"], "the default export is unchanged")
        // Deterministic.
        let again = try MGSolidGLTF.export(c, timeline: try MGSolidGLTF.seamlessLoop(c, fps: 30), sourceID: "robot-joint-gearbox",
                                           glbName: "robot-joint-gearbox.glb", engineCommit: MartySolidGLTFTests.commit)
        XCTAssertEqual(again.glb, o.glb)
        XCTAssertEqual(again.manifestText, o.manifestText)
    }

    func testASeamlessLoopThatCannotFitIsRefusedWithAReason() throws {
        let c = try checked()
        var options = MGSolidLoop.Options()
        options.maxTurns = 4                               // the gearbox needs 49/6
        XCTAssertThrowsError(try MGSolidGLTF.seamlessLoop(c, fps: 30, options: options)) {
            XCTAssertEqual(($0 as? MGSolidGLTF.Refusal)?.reason, "gltf.loop.period")
        }
        XCTAssertThrowsError(try MGSolidGLTF.seamlessLoop(c, fps: 24)) { XCTAssertEqual(($0 as? MGSolidGLTF.Refusal)?.reason, "gltf.fps") }
    }
}
