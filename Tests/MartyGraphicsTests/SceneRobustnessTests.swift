// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import MartyGraphics

final class SceneRobustnessTests: XCTestCase {
    func testPatchOperationReasonUsesClosedKeyFormatting() {
        let name = "change_style"
        XCTAssertThrowsError(try MGParser.closed([name: .null], required: [], optional: [], "patch")) { error in
            XCTAssertEqual((error as? MGError)?.reason, "patch.unknown.\(name)")
            XCTAssertEqual(MGPatch.unsupportedOperation(name).reason,
                           (error as? MGError)?.reason.replacingOccurrences(of: ".unknown.", with: ".op."))
        }
    }

    func testFilledPlaceholderAcceptsTitleAtLimit() throws {
        let prefix = String(repeating: "A", count: MGLimits.title - "125 mm".unicodeScalars.count)
        let template = MGTemplate(name: "measurement", summary: "Measurement", params: []) { _, _ in
            MGTemplateBuild(title: "\(prefix){n}", items: [MGMake.body("dot", MGPoint(3, 4))],
                            values: ["n": MGValue(value: 125, unit: "mm")])
        }
        let scene = try MGParser.scene(data: Data(#"{"v":1,"template":"measurement","params":{}}"#.utf8),
                                       extraTemplates: [template]).get()
        XCTAssertEqual(scene.title, "\(prefix)125 mm")
        XCTAssertEqual(scene.title.unicodeScalars.count, MGLimits.title)
    }

    func testPlainTextKeepsUnicodeScalarsAndCodeComparisons() throws {
        let context = MGContext(width: 12, height: 8, is3D: false, values: ["n": MGValue(value: 3, unit: "")])
        let text = "Cafe\u{301} uses {n} steps"
        let parsed = try MGParser.text(.string(text), MGLimits.text, context, "text.text")
        XCTAssertEqual(Array(parsed.unicodeScalars), Array("Cafe\u{301} uses 3 steps".unicodeScalars))
        let code = "  if x < y && y > 0"
        XCTAssertEqual(try MGParser.text(.string(code), MGLimits.text, context, "text.text", code: true), code)
    }

    func testTemplatePreviewsOnceItsVersionIsKnown() throws {
        let first = #"{"template":"two_pointers","params":{"vals":[2,5],"target":7},"#
        let last = #""v":1}"#
        var parser = MGStreamParser()
        XCTAssertNil(parser.feed(first))
        let preview = try XCTUnwrap(parser.feed(last))
        XCTAssertEqual(preview.template, "two_pointers")
        XCTAssertEqual(preview, try parser.finish().get())
    }

    func testOrdinaryTemplateMotionBuildsAndAdvances() throws {
        let time = 2.0
        let start = MGPoint(3, 4)
        let cases: [(MGMotion, Double)] = [
            (.slide([.init(id: "dot", dir: MGPoint(1, 0), accel: 1)], travel: time, hold: 1), 3),
            (.orbit(id: "dot", center: MGPoint(2, 4), period: time, rotating: []), 2),
            (.projectile(id: "dot", vx: 1, vy0: 2, g: 2, flight: time, visual: time, hold: 1,
                         vxVector: nil, vyVector: nil, vectorScale: 1), 3),
            (.oscillate(id: "dot", amplitude: 1, period: time, energy: 2, bars: nil, vector: nil, vectorLength: 1), 2)
        ]
        let data = Data(#"{"v":1,"template":"motion","params":{}}"#.utf8)
        for (motion, cycle) in cases {
            let template = MGTemplate(name: "motion", summary: "Motion", params: []) { _, _ in
                MGTemplateBuild(title: "Motion", items: [MGMake.body("dot", start)], motion: motion)
            }
            let scene = try MGParser.scene(data: data, extraTemplates: [template]).get()
            XCTAssertEqual(scene.motion, motion)
            XCTAssertEqual(MGTimeline.cycle(scene), cycle)
            let frame = MGTimeline.frame(scene, items: scene.items, time: time / 2)
            XCTAssertNotEqual(frame.first?.pts.first, start)
        }
    }
}
