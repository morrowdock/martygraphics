// SPDX-License-Identifier: Apache-2.0
import Foundation
import SwiftUI
import SceneKit
import XCTest
@testable import MartyGraphics

/// Regression tests for the PR #32 review (findings P1-1 … P2-8 and the 3D highlight cue). Rule: a claim holds at every
/// state its beat can show (learner changes, pause and restore included), or it is not shown as a claim.
final class ExplainerReviewFixTests: ExplainerTestCase {
    static let rotateBind = #"{"op":"bind","control":{"id":"slider","k":"slider","param":"angle","min":0,"max":360,"step":5,"label":"Angle"}}"#

    func mixedSnapshot() throws -> [String: MGJSON] {
        var s = MGExplainerSession(pacing: .speech, clock: MGManualClock())
        _ = try s.load(MGExplainer.parse(data: Data(try XFix.example("gears-mixed").utf8)).get()).get()
        return s.snapshot().objectValue!
    }
    func lessonObject(_ o: [String: MGJSON]) -> [String: MGJSON] {
        guard case .string(let t)? = o["lesson"] else { return [:] }
        return XFix.json(t).objectValue!
    }

    // P1-1: every restored part is checked with the explainer's rules; nothing invented shows under a claim.
    func testP1RestoreRevalidatesEveryPart() throws {
        let clean = try mixedSnapshot()
        guard case .success(let ok) = MGExplainerSession.restore(.object(clean), pacing: .speech) else { return XCTFail("clean snapshot") }
        XCTAssertEqual(ok.legend.text, "Solved 4 (2 animation ratios)", "at beat 1: beat 2's caption and check are not presented yet")
        // A typed number in the restored scene (the review's probe): refused by rule N1.
        var o = clean, lesson = lessonObject(clean)
        var scene = lesson["scene"]!.objectValue!
        guard case .array(var items)? = scene["items"] else { return XCTFail() }
        var table = items[0].objectValue!
        table["cells"] = XFix.json(#"[["gear","teeth","turns"],["small",999,999],["big",999,999]]"#)
        items[0] = .object(table); scene["items"] = .array(items); lesson["scene"] = .object(scene)
        lesson["caption"] = .string("The answer is 999.")
        o["lesson"] = .string(MGJSON.object(lesson).canonicalString)
        XCTAssertEqual(MGExplainerSession.restore(.object(o), pacing: .speech).failureIssue?.reason, "text.number.item.t")
        // A saved caption is never shown: the caption is the beat's line on the restored state.
        o = clean; lesson = lessonObject(clean)
        lesson["caption"] = .string("The answer is 999.")
        o["lesson"] = .string(MGJSON.object(lesson).canonicalString)
        guard case .success(let r) = MGExplainerSession.restore(.object(o), pacing: .speech) else { return XCTFail("caption only") }
        XCTAssertEqual(r.caption, "Count the teeth: 15 and 30.")
        XCTAssertEqual(r.lesson.caption, "Count the teeth: 15 and 30.")
        // A past beat's check that its script never proved: the replay refuses it.
        o = clean
        guard case .array(var beats)? = o["beats"] else { return XCTFail() }
        var b0 = beats[0].objectValue!
        b0["checkSpecs"] = .array([.string(#"{"eq":3,"value":"nope"}"#)])
        beats[0] = .object(b0); o["beats"] = .array(beats)
        XCTAssertEqual(MGExplainerSession.restore(.object(o), pacing: .speech).failureIssue?.reason, "check.unknown.nope")
        // A command with a typed number added to a past beat: rule N1 in the replay.
        o = clean; beats = clean["beats"]!.arrayValue!
        b0 = beats[0].objectValue!
        b0["ops"] = .array([.string(#"{"item":{"at":[2,2],"id":"x","k":"text","text":"42"},"op":"add"}"#)])
        beats[0] = .object(b0); o["beats"] = .array(beats)
        XCTAssertEqual(MGExplainerSession.restore(.object(o), pacing: .speech).failureIssue?.reason, "text.number.item.x")
        // A caption with a typed number (no `unchecked`): refused.
        o = clean; beats = clean["beats"]!.arrayValue!
        b0 = beats[0].objectValue!
        b0["say"] = .string("Count 99 teeth.")
        beats[0] = .object(b0); o["beats"] = .array(beats)
        XCTAssertEqual(MGExplainerSession.restore(.object(o), pacing: .speech).failureIssue?.reason, "text.number.beat.1")
    }

    func learnerSession(clock: MGManualClock = MGManualClock()) -> MGExplainerSession {
        var s = MGExplainerSession(pacing: .speech, clock: clock)
        _ = s.feed([XFix.header(), #"{"board":\#(XFix.rotate)}"#, Self.rotateBind, #"{"say":"Angle {theta}."}"#,
                    #"{"check":{"value":"theta","eq":0}}"#].joined(separator: "\n") + "\n")
        _ = s.endStream()
        return s
    }

    // P1-2: after a learner or host change the caption shows the live value and a check that no longer holds is not a claim.
    func testP1LearnerChangeUpdatesCaptionAndClaims() throws {
        let clock = MGManualClock()
        var s = learnerSession(clock: clock)
        XCTAssertEqual(s.caption, "Angle 0°.")
        XCTAssertEqual(s.legend.text, "Solved 3")
        XCTAssertNotNil(try? s.control("slider", 30).get())
        XCTAssertEqual(s.caption, "Angle 30°.", "the caption shows the live engine value")
        XCTAssertEqual(s.notCurrent, ["beat.1.check.1"])
        XCTAssertFalse(s.claims.contains { $0.id == "beat.1.check.1" }, "never 'Checked' on a false state")
        XCTAssertEqual(s.legend.text, "Solved 2")
        XCTAssertNotNil(try? s.control("slider", 0).get())
        XCTAssertTrue(s.notCurrent.isEmpty)
        XCTAssertEqual(s.legend.text, "Solved 3")
        // A host change takes the same path. It blends the board, so its 2D number shows once the blend has played.
        XCTAssertNotNil(try? s.apply([XFix.json(#"{"op":"params","params":{"angle":45}}"#)]).get())
        XCTAssertEqual(s.caption, "Angle ….")
        clock.advance(by: .milliseconds(1200))
        XCTAssertEqual(s.caption, "Angle 45°.")
        XCTAssertEqual(s.notCurrent, ["beat.1.check.1"])
    }

    // P1-3: the solid's spin plays over time from the beat's start; pause freezes the pose; resume continues.
    @MainActor func testP1SpinPlaysOverTimeAndPauseFreezesIt() throws {
        let clock = MGManualClock()
        let c = MGExplainerController(pacing: .speech, clock: clock)
        c.begin()
        let doc = XFix.doc(solid: XFix.gears, beats: #"[{"say":"Turn.","view":{"spin":0.25,"camera":"top","orbit":45}}]"#)
        XCTAssertTrue(c.load(try MGExplainer.parse(data: Data(doc.utf8)).get()))
        let quarter = 2 * Double.pi * 0.25   // the whole spin; 0.25 turn plays in 1 s
        XCTAssertEqual(c.spinProgress(at: clock.now), 0)
        XCTAssertEqual(c.solidParams.input, 0, accuracy: 1e-12, "the beat starts at its start pose, not its end")
        clock.advance(by: .milliseconds(500))
        XCTAssertEqual(c.solidPose(at: clock.now).input, quarter / 2, accuracy: 1e-9)
        c.pause()
        let held = c.solidParams.input
        XCTAssertEqual(held, quarter / 2, accuracy: 1e-9, "pause shows the pose it froze, not the default pose")
        clock.advance(by: .seconds(3))
        XCTAssertEqual(c.solidPose(at: clock.now).input, held, accuracy: 1e-12, "paused: the pose holds")
        c.resume()
        XCTAssertEqual(c.solidParams.input, held, accuracy: 1e-9)
        clock.advance(by: .milliseconds(250))
        XCTAssertEqual(c.solidPose(at: clock.now).input, quarter * 0.75, accuracy: 1e-9)
        clock.advance(by: .seconds(5))
        XCTAssertEqual(c.solidPose(at: clock.now).input, quarter, accuracy: 1e-9)
    }

    // P2-4: the host applies the beat's camera preset and orbit, offers bound controls and shows the legend notes.
    @MainActor func testP2HostAppliesCameraAndControls() throws {
        let clock = MGManualClock()
        let c = MGExplainerController(pacing: .speech, clock: clock)
        c.begin()
        let doc = XFix.doc(board: XFix.rotate, solid: XFix.wheelGears,
                           beats: #"[{"say":"Turn.","ops":[\#(Self.rotateBind)],"view":{"camera":"top","orbit":45}}]"#)
        XCTAssertTrue(c.load(try MGExplainer.parse(data: Data(doc.utf8)).get()))
        let r = try XCTUnwrap(c.renderer)
        XCTAssertEqual(r.camera.yaw, MGSolidCamera.presets["top"]!.yaw + 45, accuracy: 1e-9)
        XCTAssertEqual(r.camera.pitch, MGSolidCamera.presets["top"]!.pitch, accuracy: 1e-9)
        XCTAssertEqual(r.emphasis, .strong)
        XCTAssertEqual(c.controls.map(\.id), ["slider"])
        XCTAssertTrue(c.control("slider", 90))
        XCTAssertEqual(c.session.caption, "Turn.")
        XCTAssertEqual(c.board.scene?.values["theta"]?.value, 90, "the board pane shows the learner's state")
        XCTAssertTrue(c.session.legend.notes.contains("Shapes and drawings as authored"))
        let image = ImageRenderer(content: MartyGraphicsExplainerView(controller: c).frame(width: 900, height: 600)).cgImage
        XCTAssertNotNil(image)
    }

    // P2-5: a note on a template-built item is a claim like a note on an authored item.
    func testP2NoteOnTemplateItem() throws {
        let t = MGTemplate(name: "raw_value", summary: "One value drawn as text.", paramsDoc: "value:number", sample: XFix.json(#"{"value":7}"#)) { p, _ in
            guard case .number(let v)? = p["value"] else { return nil }
            var item = MGItem(id: "data", kind: .text, color: .white)
            item.pts = [MGPoint(6, 4)]; item.text = MGPhysics.format(v, unit: "")
            return MGTemplateBuild(title: "", items: [item])
        }
        try MGPacks.register(MGPack(id: "rawpack", title: "Raw", summary: "test", templates: [t],
                                    fixtures: [.init(id: "raw_value", title: "Raw", json: #"{"v":1,"template":"raw_value","params":{"value":7}}"#)]))
        let s = try XFix.load(XFix.doc(notes: #"{"data":{"unchecked":"author supplied data"}}"#,
                                       board: #"{"v":1,"template":"raw_value","params":{"value":999}}"#, beats: #"[{"say":"Hi."}]"#))
        XCTAssertEqual(s.state?.scene.item("data")?.text, "999")
        XCTAssertEqual(s.claims.map(\.id), ["board.template", "item.data"])
        XCTAssertEqual(s.claims.last?.tier, .described)
        XCTAssertEqual(s.legend.text, "Solved 1 · Not checked 1")
    }

    // P2-6: a refused beat leaves no 2D claim behind (the review's DROP_CLAIM probe), also for a `set` on an older item.
    func testP2RefusedBeatLeavesNoClaim() {
        let (s, ev) = XFix.stream([XFix.header(), #"{"board":\#(XFix.rotate)}"#, #"{"say":"Look."}"#, #"{"say":"Now."}"#,
                                   #"{"op":"add","item":{"id":"ghostclaim","k":"text","at":[1,7],"text":"{theta}"}}"#,
                                   #"{"op":"set","id":"ltheta","key":"text","value":"now {theta}"}"#,
                                   #"{"check":{"value":"theta","eq":90}}"#])
        XCTAssertEqual(XFix.reasons(ev), ["check.theta"])
        XCTAssertEqual(s.claims.map(\.id), ["board.template"])
        XCTAssertEqual(s.legend.text, "Solved 1")
    }

    // P2-7: restore revalidates in beat order, then statement order (the same first reason every time).
    func testP2RestoreOrder() throws {
        var o = try mixedSnapshot()
        guard case .array(var beats)? = o["beats"] else { return XCTFail() }
        for k in beats.indices {
            var b = beats[k].objectValue!
            let spec = (k == 0 ? #"{"eq":99,"value":"p.speed"}"# : #"{"eq":88,"value":"w.speed"}"#)
            b["checkSpecs"] = .array([.string(spec)])
            b["checks"] = .array([.object(["i": .number(Double(k + 4)), "s": .string(spec)])])
            beats[k] = .object(b)
        }
        o["beats"] = .array(beats)
        for _ in 0..<20 {
            let copy = MGJSON(any: try JSONSerialization.jsonObject(with: MGJSON.object(o).canonicalData))!
            XCTAssertEqual(MGExplainerSession.restore(copy, pacing: .speech).failureIssue?.reason, "check.failed.p.speed")
        }
    }

    // P2-8: every reason the explainer renames resolves in the catalog, with the explainer format.
    func testP2RenamedReasonsAreCatalogued() {
        let views = [#"{"camera":"nowhere"}"#, #"{"spin":99}"#, #"{"explode":2}"#, #"{"orbit":999}"#, #"{"ghost":[]}"#,
                     #"{"section":1}"#, #"{"section":{"normal":[0,0,0],"parts":["p"]}}"#, #"{"section":{"normal":[0,0,1],"offset":99999,"parts":["p"]}}"#,
                     #"{"section":{"normal":[0,0,1],"parts":[]}}"#, #"{"section":{"parts":["p"]}}"#,
                     #"{"section":{"normal":[0,0,1],"parts":["p"],"x":1}}"#, #"{"focus":"p"}"#]
        var seen: [String] = []
        for v in views {
            let (_, ev) = XFix.stream([XFix.header(), #"{"solid":\#(XFix.gears)}"#, #"{"say":"Hi."}"#, #"{"view":\#(v)}"#])
            guard let r = XFix.reasons(ev).first else { XCTFail(v); continue }
            seen.append(r)
            XCTAssertTrue(r.hasPrefix("view."), "\(v): \(r)")
            XCTAssertEqual(MGSolidReasons.lookup(r)?.formats.contains(.explainer), true, "\(r) is not catalogued for explainers")
        }
        XCTAssertEqual(Set(seen).count, views.count, "each probe names its own reason")
        let (_, ev) = XFix.stream([XFix.header(), #"{"solid":\#(XFix.gears)}"#, #"{"say":"Hi."}"#, #"{"check":{"value":"w.speed","lt":0,"wat":1}}"#])
        XCTAssertEqual(XFix.reasons(ev), ["check.unknown.wat"])
        XCTAssertEqual(MGSolidReasons.lookup("check.unknown.wat")?.formats.contains(.explainer), true)
        // Every step pattern a beat view can reach has its `view.` twin in the catalog.
        let patterns = Set(MGSolidReasons.catalog.map(\.pattern))
        for p in patterns where p.hasPrefix("step.") {
            let key = p.dropFirst(5).split(separator: ".").first.map(String.init) ?? ""
            guard MGExplainer.viewKeys.contains(key) || key == "<list>" else { continue }
            let twin = key == "<list>" ? "view.focus" : "view." + p.dropFirst(5)
            XCTAssertTrue(patterns.contains(twin), "\(p) has no explainer twin \(twin)")
        }
    }

    // The 3D highlight is a clear cue: the strong emphasis glows in the 2D emphasis colour and dims the others further.
    func testStrongHighlightIsVisible() throws {
        let doc = try MGSolidParser.document(json: XFix.json(String(XFix.gears.dropLast()) + #","kind":"assembly"}"#)).get()
        let r = MGSolidRenderer(assembly: doc.assembly)
        r.emphasis = .strong
        r.highlight(["w"], dimOthers: true)
        func material(_ id: String) -> SCNMaterial? { r.scene.rootNode.childNode(withName: id, recursively: true)?.geometry?.firstMaterial }
        XCTAssertEqual(Double(try XCTUnwrap(material("w")).emission.intensity), 0.32, accuracy: 1e-6)
        XCTAssertNotNil(material("p")?.multiply.contents, "the other part is dimmed")
        // Both parts highlighted: no dimming, both glow.
        r.highlight(["p", "w"], dimOthers: true)
        XCTAssertEqual(Double(try XCTUnwrap(material("p")).emission.intensity), 0.32, accuracy: 1e-6)
        // The default stays subtle (existing renders are unchanged).
        let plain = MGSolidRenderer(assembly: doc.assembly)
        plain.highlight(["w"], dimOthers: true)
        XCTAssertEqual(Double(plain.scene.rootNode.childNode(withName: "w", recursively: true)?.geometry?.firstMaterial?.emission.intensity ?? 0), 0.05, accuracy: 1e-6)
    }
}
