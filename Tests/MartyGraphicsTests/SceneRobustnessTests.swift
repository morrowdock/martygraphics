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
            (.slide([.init(id: "dot", dir: MGPoint(1, 0), accel: 1)], travel: time, hold: 10), 12),
            (.orbit(id: "dot", center: MGPoint(2, 4), period: time, rotating: []), 2),
            (.projectile(id: "dot", vx: 1, vy0: 2, g: 2, flight: time, visual: time, hold: 0,
                         vxVector: nil, vyVector: nil, vectorScale: 1), 2),
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

    func testRendererConversionsMatchParsedItems() throws {
        let source = #"{"v":1,"items":[{"id":"b","k":"body","at":[3,3]},"# +
            #"{"id":"up","k":"vector","on":"b","angle":-90,"len":1},{"id":"down","k":"vector","on":"b","angle":270,"len":1},"# +
            #"{"id":"s","k":"spring","from":[1,6],"to":[5,6],"coils":12},{"id":"d","k":"spring","from":[1,7],"to":[5,7]},"# +
            #"{"id":"a","k":"array","at":[8,4],"vals":[1,2,3],"ptrs":[{"i":0,"label":"lo"},{"i":2,"label":"hi"}]}]}"#
        let scene = try MGParser.scene(data: Data(source.utf8)).get()
        let byID = Dictionary(uniqueKeysWithValues: scene.items.map { ($0.id, $0) })
        let up = try XCTUnwrap(byID["up"]), down = try XCTUnwrap(byID["down"])
        XCTAssertEqual(MGCanvasRenderer.fanAngle(up.n("angle")), 270)
        XCTAssertEqual(MGCanvasRenderer.fanAngle(down.n("angle")), 270)
        XCTAssertEqual(MGCanvasRenderer.fanAngle(0), 0)
        XCTAssertEqual(MGCanvasRenderer.coilCount(try XCTUnwrap(byID["s"])), 12)
        XCTAssertEqual(MGCanvasRenderer.coilCount(try XCTUnwrap(byID["d"])), 8)
        XCTAssertEqual(try XCTUnwrap(byID["a"]).pointers.map { MGCanvasRenderer.pointerSlot($0.index) }, [0, 2])
        XCTAssertEqual(MGCanvasRenderer.hatchCount(length: 140), 10)
        XCTAssertEqual(MGCanvasRenderer.hatchCount(length: 13), 0)
    }

    func testRendererCoilCountUsesTheParserRange() {
        func spring(_ coils: Double?) -> MGItem {
            var item = MGItem(id: "s", kind: .spring, color: .blue)
            item.pts = [MGPoint(1, 1), MGPoint(4, 1)]
            if let coils { item.num["coils"] = coils }
            return item
        }
        XCTAssertEqual(MGCanvasRenderer.coilCount(spring(nil)), 8)
        XCTAssertEqual(MGCanvasRenderer.coilCount(spring(MGLimits.springCoils.lowerBound)), 3)
        XCTAssertEqual(MGCanvasRenderer.coilCount(spring(MGLimits.springCoils.upperBound)), 24)
        XCTAssertEqual(MGCanvasRenderer.coilCount(spring(10.5)), 10, "a blended count is truncated as before")
        XCTAssertNil(MGCanvasRenderer.coilCount(spring(MGLimits.springCoils.upperBound + 1)))
        XCTAssertNil(MGCanvasRenderer.coilCount(spring(MGLimits.springCoils.lowerBound - 1)))
        XCTAssertEqual(MGCanvasRenderer.pointerSlot(1.4), 1, "a blended pointer rounds as before")
    }
}
