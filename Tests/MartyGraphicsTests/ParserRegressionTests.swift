// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import MartyGraphics

/// Malformed-input regressions for the strict scene parser: every violation rejects the whole scene with a
/// stable developer reason, never a partial scene or a trap.
final class ParserRegressionTests: XCTestCase {
    private typealias R = MGRegression

    /// One statement per case keeps the type checker fast and failures pointing at their own line.
    private func check(_ json: String, _ reason: String?, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(R.reason(json), reason, json, file: file, line: line)
    }

    func testBytesAndEnvelopeFailClosed() {
        XCTAssertEqual(R.reason(data: Data([0x7B, 0xFF, 0x7D])), "json")              // not UTF-8 JSON
        let oversized = #"{"v":1,"title":""# + String(repeating: "x", count: MGLimits.sceneBytes * 2) + #""}"#
        // Canonical size is checked before the closed key set, so the unknown key is never reached.
        let canonicalTooLarge = #"{"v":1,"pad":""# + String(repeating: "x", count: MGLimits.sceneBytes + 16) + #""}"#
        check(#"{"v":1,"#, "json")
        check(oversized, "json")
        check(canonicalTooLarge, "scene.bytes")
        check("[]", "scene.object")
        check(#"{"items":[{"id":"dot","k":"body","at":[3,4]}]}"#, "scene.missing")
        check(#"{"v":2,"items":[{"id":"dot","k":"body","at":[3,4]}]}"#, "scene.version")
        check(#"{"v":"1","items":[{"id":"dot","k":"body","at":[3,4]}]}"#, "scene.version")
        check(#"{"v":true,"items":[{"id":"dot","k":"body","at":[3,4]}]}"#, "scene.version")
        check(R.withDot(#""dim":"4d""#), "scene.dim")
        check(R.withDot(#""dim":3"#), "scene.dim")
        check(R.withDot(#""params":{}"#), "scene.params.without.template")
        check(R.withDot(#""hide":[]"#), "scene.hide.without.template")
        check(R.withDot(#""over":[]"#), "scene.over.without.template")
        check(#"{"v":1}"#, "scene.items.required")
        check(#"{"v":1,"items":{}}"#, "items")
        check(#"{"v":1,"items":[]}"#, "items.count")
        check(R.withDot(#""world":[12,8]"#), "world")
        check(R.withDot(#""world":{"w":12}"#), "world.missing")
        check(R.withDot(#""world":{"w":12,"h":8,"d":1}"#), "world.unknown.d")
        check(R.withDot(#""world":{"w":1,"h":8}"#), "world.w")
        check(R.withDot(#""world":{"w":12,"h":101}"#), "world.h")
        check(R.withDot(#""camera":{"pitch":90}"#), "camera.pitch")
        check(R.withDot(#""camera":{"roll":1}"#), "camera.unknown.roll")
        let many = (0..<25).map { #"{"id":"d\#($0)","k":"body","at":[3,4]}"# }
        XCTAssertEqual(R.reason(#"{"v":1,"items":["# + many.joined(separator: ",") + "]}"), "items.count")
        XCTAssertNil(R.reason(#"{"v":1,"items":["# + many.dropLast().joined(separator: ",") + "]}"))
    }

    func testIdentifiersAreShortAsciiAndStartWithALetter() {
        func id(_ raw: String) -> String { R.items(#"{"id":"# + raw + #","k":"body","at":[3,4]}"#) }
        check(id(#""a""#), nil)
        check(id(#""a_b1""#), nil)
        check(id("\"" + String(repeating: "a", count: 24) + "\""), nil)
        check(id("\"" + String(repeating: "a", count: 25) + "\""), "item.id")
        check(id("\"\""), "item.id")
        check(id(#""1a""#), "item.id")
        check(id(#""_a""#), "item.id")
        check(id(#""a-b""#), "item.id")
        check(id(#""\u00e9""#), "item.id")
        check(id("5"), "item.id")
        check(R.items(R.dot, R.dot), "id.duplicate.dot")
    }

    func testEveryKindRejectsItsOwnMalformedSlots() {
        let na = #"{"id":"na","k":"node","at":[1,1],"text":"A"}"#
        check(R.items(#"{"id":"a","k":"rocket"}"#), "item.kind")
        check(R.items(#"{"id":"a","at":[3,4]}"#), "item.kind")
        check(R.items(#"{"id":"dot","k":"body"}"#), "item.body.missing")
        check(R.items(#"{"id":"dot","k":"body","at":[3,4],"radius":1}"#), "item.body.unknown.radius")
        check(R.items(#"{"id":"dot","k":"body","at":[3,4],"color":"pink"}"#), "item.color")
        check(R.items(#"{"id":"dot","k":"body","at":[true,4]}"#), "body.at")
        check(R.items(#"{"id":"dot","k":"body","at":[300,4]}"#), "body.at")
        check(R.items(#"{"id":"dot","k":"body","at":[3]}"#), "body.at")
        check(R.items(#"{"id":"dot","k":"body","at":[3,4,1]}"#), "body.at")  // z only in 3D
        check(R.items(#"{"id":"dot","k":"body","at":[3,4],"size":0}"#), "body.size")
        check(R.items(#"{"id":"dot","k":"body","at":[3,4],"size":true}"#), "body.size")
        check(R.items(#"{"id":"dot","k":"body","at":[3,4],"shape":"cone"}"#), "body.shape")
        check(R.items(#"{"id":"dot","k":"body","at":[3,4],"move":"x"}"#), "body.move")
        check(R.items(#"{"id":"dot","k":"body","at":[3,4],"move":{"to":[5,4]}}"#), "body.move.missing")
        check(R.items(#"{"id":"dot","k":"body","at":[3,4],"move":{"to":[5,4],"t":0.2}}"#), "body.move.t")
        check(R.items(#"{"id":"r","k":"incline","at":[1,1],"base":4,"angle":81}"#), "incline.angle")
        check(R.items(#"{"id":"l","k":"line","from":[0,0],"to":[1,1],"style":"dotted"}"#), "line.style")
        check(R.items(R.dot, #"{"id":"v","k":"vector","from":[1,1],"on":"dot","angle":0,"len":1}"#), "vector.anchor")
        check(R.items(#"{"id":"v","k":"vector","angle":0,"len":1}"#), "vector.anchor")
        check(R.items(#"{"id":"v","k":"vector","from":[1,1],"dir":[1,0,0],"len":1}"#), "vector.dir")
        check(R.items(#"{"id":"v","k":"vector","from":[1,1],"len":1}"#), "vector.angle")
        check(R.items(#"{"id":"v","k":"vector","from":[1,1],"angle":0,"len":13}"#), "vector.len")
        check(R.items(#"{"id":"t","k":"text","at":[1,1],"text":"x"}"#, #"{"id":"v","k":"vector","on":"t","angle":0,"len":1}"#), "vector.on")
        check(R.items(#"{"id":"p","k":"plot","at":[1,1],"w":4,"h":3,"xr":[1,1],"yr":[0,1],"pts":[[0,0],[1,1]]}"#), "plot.xr")
        check(R.items(#"{"id":"p","k":"plot","at":[1,1],"w":4,"h":3,"xr":[0,1],"yr":[0,1],"pts":[[0,0]]}"#), "plot.pts")
        check(R.items(#"{"id":"s","k":"spring","from":[1,1],"to":[3,1],"coils":3.5}"#), "spring.coils")
        check(R.items(#"{"id":"s","k":"spring","from":[1,1],"to":[3,1],"coils":2}"#), "spring.coils")
        check(R.items(#"{"id":"p","k":"pulley","at":[1,1],"r":4}"#), "pulley.r")
        check(R.items(#"{"id":"r","k":"rope","pts":[[1,1],[2,1],[3,1],[4,1],[5,1],[6,1],[7,1]]}"#), "rope.pts")
        check(R.items(#"{"id":"p","k":"path","pts":[[1,1]]}"#), "path.pts")
        check(R.items(#"{"id":"t","k":"text","at":[1,1]}"#), "item.text.missing")
        check(R.items(#"{"id":"t","k":"text","at":[1,1],"text":"x","style":"huge"}"#), "text.style")
        check(R.items(#"{"id":"h","k":"highlight","target":"ghost"}"#), "highlight.target")
        check(R.items(#"{"id":"b","k":"bars","at":[1,1],"w":2,"h":2,"bars":[{"label":"a","value":1},{"label":"b","value":1},{"label":"c","value":1},{"label":"d","value":1},{"label":"e","value":1},{"label":"f","value":1},{"label":"g","value":1}]}"#), "bars.bars")
        check(R.items(#"{"id":"b","k":"bars","at":[1,1],"w":2,"h":2,"bars":[{"label":"a","value":1,"x":1}]}"#), "bars.bar.unknown.x")
        check(R.items(#"{"id":"b","k":"bars","at":[1,1],"w":2,"h":2,"bars":[{"label":"a","value":100000000}]}"#), "bars.value")
        check(R.items(#"{"id":"b","k":"bars","at":[1,1],"w":2,"h":2,"bars":[{"label":"a","value":1,"color":"pink"}]}"#), "bars.color")
        check(R.items(#"{"id":"b","k":"bars","at":[1,1],"w":2,"h":2,"bars":[{"label":"a","value":1}],"unit":"ninechars"}"#), "bars.unit")
        check(R.items(#"{"id":"a","k":"array","at":[6,4],"vals":[]}"#), "array.vals")
        check(R.items(#"{"id":"a","k":"array","at":[6,4],"vals":[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17]}"#), "array.vals")
        check(R.items(#"{"id":"a","k":"array","at":[6,4],"vals":[true]}"#), "array.val")
        check(R.items(#"{"id":"a","k":"array","at":[6,4],"vals":["1234567"]}"#), "array.val")
        check(R.items(#"{"id":"a","k":"array","at":[6,4],"vals":[1000000]}"#), "array.val")
        check(R.items(#"{"id":"a","k":"array","at":[6,4],"vals":[1,2],"ptrs":[{"i":2,"label":"p"}]}"#), "array.ptr.i")
        check(R.items(#"{"id":"a","k":"array","at":[6,4],"vals":[1,2],"ptrs":[{"i":0.5,"label":"p"}]}"#), "array.ptr.i")
        check(R.items(#"{"id":"a","k":"array","at":[6,4],"vals":[1,2],"ptrs":[{"i":0,"label":"toolonglabel"}]}"#), "array.ptr.label")
        check(R.items(#"{"id":"a","k":"array","at":[6,4],"vals":[1,2],"ptrs":[{"i":0,"label":"a"},{"i":0,"label":"b"},{"i":0,"label":"c"},{"i":0,"label":"d"},{"i":0,"label":"e"}]}"#), "array.ptrs")
        check(R.items(#"{"id":"a","k":"array","at":[6,4],"vals":[1,2],"marked":[1.5]}"#), "array.marked")
        check(R.items(#"{"id":"n","k":"node","at":[1,1],"text":"A","r":3}"#), "node.r")
        check(R.items(#"{"id":"n","k":"node","at":[1,1],"text":"ninechars"}"#), "node.text")
        check(R.items(#"{"id":"e","k":"edge","a":"n","b":"n"}"#), "edge.self")
        check(R.items(na, R.dot, #"{"id":"e","k":"edge","a":"na","b":"dot"}"#), "edge.nodes")
        check(R.items(na, #"{"id":"e","k":"edge","a":"na","b":"ghost"}"#), "edge.nodes")
    }

    func testThreeDimensionalScenesRejectFlatOnlyKindsAndBadDirections() {
        check(#"{"v":1,"dim":"3d","items":[{"id":"n","k":"node","at":[1,1,1],"text":"A"}]}"#, "3d.kind.node")
        check(#"{"v":1,"dim":"3d","items":[{"id":"v","k":"vector","from":[1,1,1],"dir":[0,0,0],"len":1}]}"#, "vector.dir")
        check(#"{"v":1,"dim":"3d","items":[{"id":"v","k":"vector","from":[1,1,1],"dir":[0,1,0],"angle":0,"len":1}]}"#, "vector.dir")
        check(#"{"v":1,"dim":"3d","items":[{"id":"dot","k":"body","at":[1,1,13]}]}"#, "body.at")
        check(R.allKinds3D, nil)
    }

    func testStepsCamerasAndEditsAreValidatedCumulatively() {
        func step(_ body: String) -> String { R.withDot(#""steps":["# + body + "]") }
        let seventeen = "[" + Array(repeating: #""dot""#, count: 17).joined(separator: ",") + "]"
        let edit = #"{"id":"dot","key":"size","value":2}"#
        check(R.withDot(#""steps":[]"#), "steps")
        check(R.withDot(#""steps":["# + Array(repeating: #"{"say":"x"}"#, count: 9).joined(separator: ",") + "]"), "steps")
        check(R.withDot(#""steps":["# + Array(repeating: #"{"say":"x"}"#, count: 8).joined(separator: ",") + "]"), nil)
        check(step("5"), "step")
        check(step(#"{"show":[]}"#), "step.missing")
        check(step(#"{"say":"x","wait":1}"#), "step.unknown.wait")
        check(step(#"{"say":"<b>x</b>"}"#), "step.say")
        check(step(#"{"say":"x","show":["ghost"]}"#), "step.show")
        check(step(#"{"say":"x","show":"# + seventeen + "}"), "step.show")
        check(step(#"{"say":"x","focus":"ghost"}"#), "step.focus")
        check(step(#"{"say":"x","cam":{"zoom":5}}"#), "camera.zoom")
        check(step(#"{"say":"x","cam":{"x":13}}"#), "camera.x")
        check(step(#"{"say":"x","do":[]}"#), "step.do")
        check(step(#"{"say":"x","do":["# + Array(repeating: edit, count: 7).joined(separator: ",") + "]}"), "step.do")
        check(step(#"{"say":"x","do":["# + Array(repeating: edit, count: 6).joined(separator: ",") + "]}"), nil)
        check(step(#"{"say":"x","do":[{"id":"dot","key":"id","value":"x"}]}"#), "edit.key")
        check(step(#"{"say":"x","do":[{"id":"dot","key":"k","value":"node"}]}"#), "edit.key")
        check(step(#"{"say":"x","do":[{"id":"dot","key":"size","value":2,"x":1}]}"#), "edit.unknown.x")
        check(step(#"{"say":"x","do":[{"id":"dot","key":"size"}]}"#), "edit.missing")
        check(step(#"{"say":"x","do":[{"id":"ghost","key":"size","value":2}]}"#), "edit.ref")
        check(step(#"{"say":"x","do":[{"id":"dot","key":"radius","value":2}]}"#), "edit.key.radius")
        check(step(#"{"say":"x","do":[{"id":"dot","key":"at","value":[99,99]}]}"#), "body.at")
        // An edit valid against the original item is re-checked against the item as left by every earlier step:
        // marking cell 2 is fine on three cells, but not after an earlier step shrank the array to one cell.
        func cells(_ steps: String) -> String { #"{"v":1,"items":[{"id":"a","k":"array","at":[6,4],"vals":[1,2,3]}],"steps":["# + steps + "]}" }
        let mark = #"{"say":"b","do":[{"id":"a","key":"marked","value":[2]}]}"#
        check(cells(mark), nil)
        check(cells(#"{"say":"a","do":[{"id":"a","key":"vals","value":[1]}]},"# + mark), "array.marked")
    }

    func testPlainTextSanitizerAndPlaceholders() {
        func title(_ raw: String) -> String { R.withDot(#""title":"# + raw) }
        check(title("\"" + String(repeating: "a", count: MGLimits.title) + "\""), nil)
        check(title("\"" + String(repeating: "a", count: MGLimits.title + 1) + "\""), "title")
        check(title("\" " + String(repeating: "a", count: MGLimits.title) + "\""), "title")  // length counts untrimmed text
        check(title(#""<b>""#), "title")
        check(title(#""a > b""#), "title")
        check(title(#""see https://example.invalid""#), "title")
        check(title(#""```""#), "title")
        check(title(#""   ""#), "title")
        check(title(#""a\u0007b""#), "title")
        check(title(#""a\tb""#), "title")
        check(title(#""line\nbreak""#), nil)
        check(title(#""{x}""#), "title.placeholder.x")
        check(title(#""a}""#), "title.brace")
        check(title(#""{a""#), "title.brace")
        check(title(#""{a-b}""#), "title.placeholder")
        check(title("5"), "title")
        XCTAssertEqual(try R.scene(title(#""  padded  ""#)).title, "padded")
        XCTAssertEqual(try R.scene(title(#""line\nbreak""#)).title, "line\nbreak")
    }

    func testTemplateEnvelopeParamsHideAndOverFailClosed() {
        let tp = #"{"v":1,"template":"two_pointers","params":{"vals":[1,2,4,7],"target":9}"#
        let seventeenHides = "[" + Array(repeating: #""goal""#, count: 17).joined(separator: ",") + "]"
        let overEntry = #"{"id":"goal","key":"label","value":"x"}"#
        let extras = (0..<11).map { #"{"id":"x\#($0)","k":"body","at":[1,1]}"# }
        let fullTree = #"{"v":1,"template":"bst","params":{"values":[8,4,12,2,6,10,14,1,3,5,7,9,11,13,15],"find":15},"items":["#
        check(#"{"v":1,"template":"nope","params":{}}"#, "template.unknown")
        check(#"{"v":1,"template":5,"params":{}}"#, "template.unknown")
        check(#"{"v":1,"template":"bst","params":{"values":[1]},"world":{"w":12,"h":8}}"#, "template.world")
        check(#"{"v":1,"template":"bst"}"#, "template.params")
        check(#"{"v":1,"template":"bst","params":{"values":[1],"x":1}}"#, "template.params.unknown")
        check(#"{"v":1,"template":"bst","params":{"values":[1,1]}}"#, "template.check")
        check(#"{"v":1,"template":"bst","params":{"values":[1.5]}}"#, "template.values.integer")
        check(#"{"v":1,"template":"bst","params":{"values":[]}}"#, "template.values")
        check(#"{"v":1,"template":"bst","params":{"values":[1000]}}"#, "template.values")
        check(#"{"v":1,"template":"bst","params":{"values":[1,2,3,4,5,6,7,8]}}"#, "template.build")  // depth 7 > 6
        check(#"{"v":1,"template":"two_pointers","params":{"vals":[3,1],"target":4}}"#, "template.check")
        check(#"{"v":1,"template":"two_pointers","params":{"vals":[1,3]}}"#, "template.target.missing")
        check(#"{"v":1,"dim":"3d","template":"two_pointers","params":{"vals":[1,2,4,7],"target":9}}"#, "3d.kind.array")
        check(tp + #","hide":["nope"]}"#, "hide.ref")
        check(tp + #","hide":[5]}"#, "hide.ref")
        check(tp + #","hide":"# + seventeenHides + "}", "hide")
        check(tp + #","over":{}}"#, "over")
        check(tp + #","over":["# + Array(repeating: overEntry, count: 17).joined(separator: ",") + "]}", "over")
        check(tp + #","over":[{"id":"ghost","key":"label","value":"x"}]}"#, "over.ref")
        check(tp + #","over":[{"id":"goal","key":"text","value":"<x>"}]}"#, "text.text")
        check(tp + #","items":[]}"#, nil)
        check(tp + #","items":["# + extras.joined(separator: ",") + "]}", "items.count")
        check(tp + #","items":["# + extras.dropLast().joined(separator: ",") + "]}", nil)
        check(#"{"v":1,"template":"bst","params":{"values":[5]},"hide":["n0"]}"#, "items.total")
        // 15 nodes + 14 edges + 4 find highlights + 10 extras = 43 > 40 resolved items.
        check(fullTree + extras.dropLast().joined(separator: ",") + "]}", "items.total")
    }

    func testEveryKindRoundTripsThroughItsWireForm() throws {
        for json in [R.allKinds, R.allKinds3D] {
            let scene = try R.scene(json)
            let ctx = MGContext(width: scene.width, height: scene.height, is3D: scene.is3D, values: scene.values)
            for item in scene.items {
                XCTAssertEqual(try MGParser.item(.object(item.wire()), ctx), item, item.id)
            }
            let rebuilt: [String: Any] = ["v": 1, "dim": scene.is3D ? "3d" : "2d",
                                          "items": scene.items.map { MGJSON.object($0.wire()).any }]
            XCTAssertEqual(try MGParser.scene(object: rebuilt).get().items, scene.items)
        }
        XCTAssertEqual(Set(try R.scene(R.allKinds).items.map(\.kind)), Set(MGKind.allCases))
    }
}
