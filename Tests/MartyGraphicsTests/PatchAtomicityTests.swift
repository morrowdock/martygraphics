// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import MartyGraphics

/// Patch parsing and all-or-nothing application: a refused patch returns a reason and no scene, the receiver keeps
/// its source, items and revision, and ops apply in order to the rewritten source before one whole-scene validation.
final class PatchAtomicityTests: XCTestCase {
    private typealias R = MGRegression
    private let title = #"{"op":"title","title":"New"}"#

    func testMalformedPatchesAreRefusedAtParseWithReason() throws {
        func check(_ json: String, _ reason: String?, line: UInt = #line) {
            XCTAssertEqual(R.patchReason(json), reason, json, line: line)
        }
        check(#"{"v":1,"#, "patch.json")
        check("[]", "patch.object")
        check(#"{"v":1,"ops":[{"op":"title","title":""# + String(repeating: "x", count: MGLimits.patchBytes) + #""}]}"#, "patch.object")
        check(#"{"v":1,"ops":[{"op":"title","title":""# + String(repeating: "x", count: MGLimits.patchBytes * 2) + #""}]}"#, "patch.json")
        check(#"{"v":1}"#, "patch.missing")
        check(#"{"v":1,"ops":["# + title + #"],"x":1}"#, "patch.unknown.x")
        check(#"{"v":2,"ops":["# + title + "]}", "patch.ops")
        check(#"{"v":1,"ops":{}}"#, "patch.ops")
        check(R.ops([]), "patch.ops")
        check(R.ops(Array(repeating: title, count: 12)), nil)
        check(R.ops(Array(repeating: title, count: 13)), "patch.ops")
        check(R.ops(["1"]), "patch.op")
        check(R.ops([#"{"title":"x"}"#]), "patch.op")
        check(R.ops([#"{"op":5}"#]), "patch.op")
        check(R.ops([#"{"op":"explode"}"#]), "patch.op.explode")
        check(R.ops([#"{"op":"title","title":"x","extra":1}"#]), "patch.title.unknown.extra")
        check(R.ops([#"{"op":"set","id":"na","key":"text"}"#]), "patch.set.missing")
        check(R.ops([#"{"op":"step","index":1.5}"#]), "patch.step")
        check(R.ops([#"{"op":"step","index":"2"}"#]), "patch.step")
        check(R.ops([#"{"op":"step","index":8}"#]), "patch.step")
        check(#"{"v":1,"rev":-1,"ops":["# + title + "]}", "patch.rev")
        check(#"{"v":1,"rev":1.5,"ops":["# + title + "]}", "patch.rev")
        check(#"{"v":1,"rev":"0","ops":["# + title + "]}", "patch.rev")
        check(#"{"v":1,"rev":1000001,"ops":["# + title + "]}", "patch.rev")
        check(#"{"v":1,"rev":1000000,"ops":["# + title + "]}", nil)
        XCTAssertEqual(try R.patch(#"{"v":1,"rev":1000000,"ops":["# + title + "]}").baseRevision, 1_000_000)
        XCTAssertNil(try R.patch(R.ops([title])).baseRevision)
    }

    func testRefusedPatchesReturnNoSceneAndLeaveTheReceiverUntouched() throws {
        let base = try R.scene(R.patchBase)
        let snapshot = (source: base.source, items: base.items, title: base.title, revision: base.revision)
        func refuse(_ ops: [String], _ reason: String, line: UInt = #line) {
            guard let patch = try? R.patch(R.ops(ops)) else { return XCTFail("patch did not parse: \(ops)", line: line) }
            let result = base.applying(patch)
            XCTAssertEqual(R.reason(result), reason, ops.joined(), line: line)
            if case .success = result { XCTFail("refused patch produced a scene: \(ops)", line: line) }
        }
        refuse([title, #"{"op":"remove","id":"ghost"}"#], "patch.remove.ref")  // op-time failure after a valid op
        refuse([title, #"{"op":"remove","id":"na"}"#], "edge.nodes")  // every op applies, whole-scene check fails
        refuse([#"{"op":"add","item":{"id":"na","k":"node","at":[1,1],"text":"Z"}}"#], "id.duplicate.na")
        refuse([#"{"op":"set","id":"na","key":"id","value":"zz"}"#], "patch.set.key")
        refuse([#"{"op":"set","id":"na","key":"radius","value":1}"#], "item.node.unknown.radius")
        refuse([#"{"op":"set","id":"nb","key":"at","value":[99,99]}"#], "node.at")
        refuse([#"{"op":"set","id":"ghost","key":"text","value":"Z"}"#], "patch.set.ref")
        refuse([#"{"op":"params","params":{"n":1}}"#], "patch.params")
        refuse([#"{"op":"step","index":5}"#], "patch.step.range")
        refuse([#"{"op":"dim","dim":"3d"}"#], "3d.kind.node")
        refuse([#"{"op":"camera","camera":{"zoom":9}}"#], "camera.zoom")
        refuse([#"{"op":"title","title":"<b>bold</b>"}"#], "title")
        refuse([#"{"op":"steps","steps":[]}"#], "steps")
        refuse([#"{"op":"steps","steps":[{"say":"Only."}]}"#, #"{"op":"step","index":1}"#], "patch.step.range")
        // A stale revision is refused before any op runs, even an op that would fail on its own.
        XCTAssertEqual(R.reason(base.applying(try R.patch(#"{"v":1,"rev":3,"ops":[{"op":"remove","id":"ghost"}]}"#))), "patch.stale")
        XCTAssertEqual(base.source, snapshot.source)
        XCTAssertEqual(base.items, snapshot.items)
        XCTAssertEqual(base.title, snapshot.title)
        XCTAssertEqual(base.revision, snapshot.revision)
    }

    func testOpsApplyInOrderToTheRewrittenSource() throws {
        let base = try R.scene(R.patchBase)
        let next = try base.applying(try R.patch(R.ops([
            #"{"op":"title","title":"Changed"}"#,
            #"{"op":"add","item":{"id":"extra","k":"text","at":[6,1],"text":"Added"}}"#,
            #"{"op":"set","id":"nb","key":"text","value":"C"}"#,
            #"{"op":"step","index":1}"#
        ]))).get()
        XCTAssertEqual(next.title, "Changed")
        XCTAssertEqual(next.items.map(\.id), ["na", "nb", "ab", "note", "extra"])
        XCTAssertEqual(next.item("nb")?.text, "C")
        XCTAssertEqual(next.startStep, 1)
        XCTAssertEqual(next.revision, 1)
        XCTAssertEqual(base.title, "Patch base")
        XCTAssertEqual(base.item("nb")?.text, "B")

        // Remove then re-add the same id replaces the item; steps that show it still resolve.
        let replaced = try base.applying(try R.patch(R.ops([
            #"{"op":"remove","id":"note"}"#, #"{"op":"add","item":{"id":"note","k":"body","at":[6,7]}}"#
        ]))).get()
        XCTAssertEqual(replaced.item("note")?.kind, .body)

        // A jump is checked against the steps the same patch installs, even when the jump comes first.
        let jumped = try base.applying(try R.patch(R.ops([
            #"{"op":"step","index":2}"#, #"{"op":"steps","steps":[{"say":"a."},{"say":"b."},{"say":"c."}]}"#
        ]))).get()
        XCTAssertEqual(jumped.steps.count, 3)
        XCTAssertEqual(jumped.startStep, 2)

        // Twelve ops are allowed; the last write wins.
        let titles = (1...12).map { #"{"op":"title","title":"T\#($0)"}"# }
        XCTAssertEqual(try base.applying(try R.patch(R.ops(titles))).get().title, "T12")
    }

    func testRevisionsChainAndStalePatchesAreRefused() throws {
        let base = try R.scene(R.patchBase)
        let first = try base.applying(try R.patch(#"{"v":1,"rev":0,"ops":[{"op":"title","title":"One"}]}"#)).get()
        let second = try first.applying(try R.patch(#"{"v":1,"rev":1,"ops":[{"op":"title","title":"Two"}]}"#)).get()
        XCTAssertEqual([base.revision, first.revision, second.revision], [0, 1, 2])
        XCTAssertEqual(R.reason(second.applying(try R.patch(#"{"v":1,"rev":0,"ops":[{"op":"title","title":"Old"}]}"#))), "patch.stale")
        // Without "rev" a patch applies to whatever revision is current.
        let free = try R.patch(R.ops([title]))
        XCTAssertEqual(try second.applying(free).get().revision, 3)
    }

    func testTemplatePatchesRewriteHideAndOverWithoutDuplicates() throws {
        let base = try R.scene(R.twoPointers)
        XCTAssertEqual(base.items.map(\.id), ["arr", "goal"])
        XCTAssertEqual(base.steps.count, 3)

        // Removing a template item hides it; removing it again finds nothing to remove.
        let hidden = try base.applying(try R.patch(R.ops([#"{"op":"remove","id":"goal"}"#]))).get()
        XCTAssertEqual(hidden.items.map(\.id), ["arr"])
        XCTAssertEqual(hidden.source["hide"], .array([.string("goal")]))
        XCTAssertEqual(hidden.template, "two_pointers")
        XCTAssertEqual(R.reason(hidden.applying(try R.patch(R.ops([#"{"op":"remove","id":"goal"}"#])))), "patch.remove.ref")

        // Setting the same key twice keeps one override.
        let once = try base.applying(try R.patch(R.ops([#"{"op":"set","id":"arr","key":"label","value":"Sorted"}"#]))).get()
        let twice = try once.applying(try R.patch(R.ops([#"{"op":"set","id":"arr","key":"label","value":"Again"}"#]))).get()
        XCTAssertEqual(twice.item("arr")?.label, "Again")
        guard case .array(let over)? = twice.source["over"] else { return XCTFail("override missing from source") }
        XCTAssertEqual(over.count, 1)

        // Set then remove: the remove drops the pending override. Remove then set: the override targets a hidden item.
        let setThenRemove = try base.applying(try R.patch(R.ops([
            #"{"op":"set","id":"goal","key":"text","value":"Moved"}"#, #"{"op":"remove","id":"goal"}"#
        ]))).get()
        XCTAssertNil(setThenRemove.item("goal"))
        XCTAssertNil(setThenRemove.source["over"])
        XCTAssertEqual(R.reason(base.applying(try R.patch(R.ops([
            #"{"op":"remove","id":"goal"}"#, #"{"op":"set","id":"goal","key":"text","value":"Moved"}"#
        ])))), "edit.ref")

        // Adding then removing an extra leaves no empty "items" member behind.
        let added = try base.applying(try R.patch(R.ops([#"{"op":"add","item":{"id":"x","k":"body","at":[1,1]}}"#]))).get()
        XCTAssertEqual(added.items.map(\.id), ["arr", "goal", "x"])
        let removed = try added.applying(try R.patch(R.ops([#"{"op":"remove","id":"x"}"#]))).get()
        XCTAssertNil(removed.source["items"])
        XCTAssertEqual(removed.items, base.items)
    }

    func testTemplateParamPatchesRebuildLocallyAndKeepEarlierEdits() throws {
        let base = try R.scene(R.twoPointers)
        let hidden = try base.applying(try R.patch(R.ops([#"{"op":"remove","id":"goal"}"#]))).get()
        let retargeted = try hidden.applying(try R.patch(R.ops([#"{"op":"params","params":{"target":6}}"#]))).get()
        XCTAssertEqual(retargeted.values["target"]?.value, 6)
        XCTAssertEqual(retargeted.steps.count, 4)            // 1+7 too big, 1+4 too small, 2+4 found
        XCTAssertNil(retargeted.item("goal"))                 // the earlier hide survives the rebuild
        XCTAssertEqual(retargeted.revision, 2)
        let shown = try base.applying(try R.patch(R.ops([#"{"op":"params","params":{"target":6}}"#]))).get()
        XCTAssertEqual(shown.item("goal")?.text, "target 6")
        XCTAssertEqual(R.reason(base.applying(try R.patch(R.ops([#"{"op":"params","params":{"target":5000}}"#])))), "template.target")
        XCTAssertEqual(R.reason(base.applying(try R.patch(R.ops([#"{"op":"params","params":{"vals":[3,1]}}"#])))), "template.check")
    }
}
