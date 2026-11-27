// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import MartyGraphics

/// Learner sliders (the scene `sliders` key; docs/PROTOCOL.md, "Learner sliders"): parse rules and reasons through the
/// shared golden cases (docs/fixtures/v1/sliders.cases.json, also checked by tools/tests), the limits, re-sampling
/// through the parser (values against the closed form), refused positions, steps, patches, lessons, the VoiceOver
/// descriptions and the repair hints.
final class SliderTests: XCTestCase {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: root.appendingPathComponent("docs/fixtures/v1/" + name))
    }
    static func cases() throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: fixture("sliders.cases.json")) as? [String: Any])
    }
    private func scene(_ json: String) throws -> MGScene { try MGParser.scene(data: Data(json.utf8)).get() }
    private func reason(_ json: String) -> String? {
        if case .failure(let e) = MGParser.scene(data: Data(json.utf8)) { return e.reason }
        return nil
    }
    /// The documentation scene: one wave `a*sin(b*x)+c` with sliders a 0…2 by 0.25, b 0.5…3 by 0.5, c −1…1 by 0.5.
    private func wave() throws -> MGScene { try MGParser.scene(data: Self.fixture("sliders.scene.json")).get() }

    static let line = #"{"id":"f","k":"func","at":[1,1],"w":10,"h":6,"xr":[-3,3],"yr":[-4,4],"y":"a*x","a":1}"#
    static let slope = #"{"param":"a","min":0,"max":2,"step":0.5,"default":1,"label":"Slope a"}"#
    /// A board for the split checks (`SliderBoardHostTests`): a floor, a graph `a*sin(x)` that one slider drives and a
    /// moving body, so the board splits while the motion plays with the graph in the base; the second step narrows the
    /// graph's y range and zooms the camera.
    static let splitBoard = #"{"v":1,"title":"Slider split","world":{"w":12,"h":8},"items":[{"id":"floor","k":"line","from":[0,1],"to":[12,1]},{"id":"g","k":"func","at":[1,2],"w":6,"h":4,"xr":[-3,3],"yr":[-4,4],"y":"a*sin(x)","a":1},{"id":"dot","k":"body","at":[8.5,5.5],"shape":"ball","size":1,"move":{"to":[11,5.5],"t":2}}],"steps":[{"say":"First step."},{"say":"Second step.","do":[{"id":"g","key":"yr","value":[-2,2]}],"cam":{"zoom":1.5}}],"sliders":[{"param":"a","min":0,"max":2,"step":0.5,"default":1,"label":"Height a"}]}"#

    // MARK: parse

    func testSharedCasesAcceptAndRefuseWithTheGoldenReasons() throws {
        let accepted = try XCTUnwrap(Self.cases()["accepted"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(accepted.count, 7)
        for c in accepted {
            let name = try XCTUnwrap(c["name"] as? String)
            let parsed = MGParser.scene(object: try XCTUnwrap(c["scene"], name))
            guard case .success(let s) = parsed else { XCTFail("refused: \(name) \(parsed)"); continue }
            let expected = try XCTUnwrap(c["sliders"] as? [[String: Any]], name)
            XCTAssertEqual(s.sliders.map(\.param), expected.map { $0["param"] as? String ?? "" }, name)
            XCTAssertEqual(s.sliders.map(\.steps), expected.map { $0["steps"] as? Int ?? -1 }, name)
            XCTAssertEqual(s.sliders.map(\.defaultStop), expected.map { $0["defaultStop"] as? Int ?? -1 }, name)
            XCTAssertEqual(s.sliders.map(\.items), expected.map { $0["items"] as? [String] ?? [] }, name)
            for slider in s.sliders {
                // The grid runs from exactly min to exactly max through exactly the default.
                XCTAssertEqual(slider.value(at: 0), slider.min, name)
                XCTAssertEqual(slider.value(at: slider.steps), slider.max, name)
                XCTAssertEqual(slider.value(at: slider.defaultStop), slider.defaultValue, name)
            }
        }
        let refused = try XCTUnwrap(Self.cases()["refused"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(refused.count, 41)
        for c in refused {
            let name = try XCTUnwrap(c["name"] as? String)
            guard case .failure(let error) = MGParser.scene(object: try XCTUnwrap(c["scene"], name)) else { XCTFail("accepted: \(name)"); continue }
            XCTAssertEqual(error.reason, c["reason"] as? String, name)
            XCTAssertNotNil(MGRepairHint.text(for: error.reason), "no repair hint for \(error.reason)")
            // The hint comes from a slider row, never from a generic row further down the table.
            let row = MGRepairHint.table.first { MGRepairHint.matches($0.0, error.reason) }?.0 ?? ""
            XCTAssertTrue(row.hasPrefix("slider"), "\(error.reason) is hinted by \(row)")
        }
    }

    func testWithoutSlidersNothingChanges() throws {
        let s = try wave()
        XCTAssertEqual(s.sliders.count, 3)
        // The same scene without the key parses to the same board: the key only adds the controls.
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Self.fixture("sliders.scene.json")) as? [String: Any])
        object["sliders"] = nil
        let plain = try MGParser.scene(object: object).get()
        XCTAssertTrue(plain.sliders.isEmpty)
        XCTAssertEqual(plain.items, s.items)
        XCTAssertEqual(plain.steps, s.steps)
        XCTAssertEqual(plain.alt, s.alt)
        // At the defaults the slider board is exactly the timeline's board, and its VoiceOver value is unchanged.
        let state = MGSliderState(scene: s)
        XCTAssertTrue(state.isAtDefaults)
        XCTAssertEqual(state.items, MGTimeline.items(s, step: 0))
        XCTAssertEqual(state.accessibilityValue(), MGDescribe.accessibilityValue(s, step: 0))
        // Every existing fixture still parses with no sliders.
        for demo in MGFixtures.all { XCTAssertTrue(try XCTUnwrap(demo.scene, demo.id).sliders.isEmpty, demo.id) }
    }

    func testLimits() throws {
        XCTAssertEqual(MGLimits.sliders, 3)
        XCTAssertEqual(MGLimits.sliderSteps, 100)
        XCTAssertEqual(MGLimits.sliderBindings, 6)
        XCTAssertEqual(MGLimits.exprParameter, 1000)
        // Ranges reach the parameter bound exactly; one more is refused.
        let wide = #"{"param":"a","min":-1000,"max":1000,"step":20,"default":0,"label":"a"}"#
        let zero = Self.line.replacingOccurrences(of: #""a":1"#, with: #""a":0"#)
        XCTAssertEqual(try scene(#"{"v":1,"items":["# + zero + #"],"sliders":["# + wide + "]}").sliders.first?.steps, 100)
        XCTAssertEqual(reason(#"{"v":1,"items":["# + zero + #"],"sliders":["# + wide.replacingOccurrences(of: "-1000", with: "-1000.5") + "]}"), "slider.min")
        // Exactly six slider-graph pairs: three graphs on two sliders, and two graphs on three sliders.
        func graphs(_ n: Int) -> String {
            (1...n).map { #"{"id":"f\#($0)","k":"func","at":[1,1],"w":10,"h":6,"xr":[-3,3],"yr":[-4,4],"y":"a*x+b+c","a":1,"b":0,"c":0}"# }
                .joined(separator: ",")
        }
        let b = #"{"param":"b","min":-1,"max":1,"step":0.5,"default":0,"label":"b"}"#
        let c = #"{"param":"c","min":-1,"max":1,"step":0.5,"default":0,"label":"c"}"#
        XCTAssertEqual(try scene(#"{"v":1,"items":["# + graphs(3) + #"],"sliders":["# + Self.slope + "," + b + "]}").sliders.count, 2)
        XCTAssertEqual(try scene(#"{"v":1,"items":["# + graphs(2) + #"],"sliders":["# + [Self.slope, b, c].joined(separator: ",") + "]}").sliders.count, 3)
        XCTAssertEqual(reason(#"{"v":1,"items":["# + graphs(4) + #"],"sliders":["# + Self.slope + "," + b + "]}"), "sliders.bindings")
    }

    func testPatchesLessonsAndTheGrammar() throws {
        let s = try scene(#"{"v":1,"items":["# + Self.line + #"],"sliders":["# + Self.slope + "]}")
        // A patch re-validates the whole scene, sliders included.
        let titled = try s.applying(MGRegression.patch(MGRegression.ops([#"{"op":"title","title":"Slope"}"#]))).get()
        XCTAssertEqual(titled.sliders, s.sliders)
        XCTAssertEqual(MGRegression.reason(s.applying(try MGRegression.patch(MGRegression.ops([#"{"op":"set","id":"f","key":"a","value":2}"#])))), "slider.default.f")
        XCTAssertEqual(MGRegression.reason(s.applying(try MGRegression.patch(MGRegression.ops([#"{"op":"remove","id":"f"}"#, #"{"op":"add","item":{"id":"n","k":"node","at":[2,2],"text":"n"}}"#])))), "slider.unbound")
        // Lessons and explainer boards have their own controls: the lesson policy drops a scene's sliders.
        XCTAssertTrue(MGLessonEngine.lessonScene(s).sliders.isEmpty)
        XCTAssertEqual(MGLessonEngine.lessonScene(s).items, s.items)
        // The grammar document lists the key and its inventory.
        let grammar = MGGrammar.document()
        XCTAssertTrue(try XCTUnwrap(grammar["sceneKeys"] as? [String]).contains("sliders"))
        let inventory = try XCTUnwrap(grammar["sliders"] as? [String: Any])
        XCTAssertEqual(inventory["keys"] as? [String], ["default", "label", "max", "min", "param", "step"])
        XCTAssertEqual(inventory["params"] as? [String], ["a", "b", "c"])
        XCTAssertEqual(inventory["kinds"] as? [String], ["func"])
        XCTAssertEqual(inventory["maxSliders"] as? Int, 3)
        XCTAssertEqual(inventory["maxSteps"] as? Int, 100)
        XCTAssertEqual(inventory["maxBindings"] as? Int, 6)
    }

    func testAStreamPreviewsTheBoardBeforeItsSlidersAndFinishesStrictly() throws {
        // Sliders first: until the graph they drive arrives, the preview shows the other items without them.
        let json = #"{"v":1,"sliders":[\#(Self.slope)],"items":[{"id":"t","k":"text","at":[6,7],"text":"Slope"},\#(Self.line)]}"#
        var parser = MGStreamParser()
        var previews: [MGScene] = []
        for chunk in MGRegression.chunks(json, seed: 7) { if let s = parser.feed(chunk) { previews.append(s) } }
        XCTAssertTrue(previews.contains { $0.items.map(\.id) == ["t"] && $0.sliders.isEmpty }, "\(previews.map { $0.items.map(\.id) })")
        XCTAssertEqual(previews.last?.sliders.map(\.param), ["a"])
        let final = try parser.finish().get()
        XCTAssertEqual(final.sliders.map(\.param), ["a"])
        XCTAssertEqual(final.items.map(\.id), ["t", "f"])
        XCTAssertEqual(final, try scene(json))
    }

    // MARK: re-sampling

    func testASliderChangeResamplesTheGraphToTheClosedForm() throws {
        let s = try wave()
        var state = MGSliderState(scene: s)
        let before = try XCTUnwrap(state.items.first { $0.id == "wave" })
        XCTAssertTrue(state.set("a", stop: 6))   // a = 0 + 6 × 0.25
        XCTAssertTrue(state.set("b", stop: 3))   // b = 0.5 + 3 × 0.5
        XCTAssertTrue(state.set("c", stop: 3))   // c = −1 + 3 × 0.5
        XCTAssertEqual(state.values, ["a": 1.5, "b": 2, "c": 0.5])
        let after = try XCTUnwrap(state.items.first { $0.id == "wave" })
        // Same grid, new values: every sample is the engine's value of 1.5 sin(2x) + 0.5, never a model's number.
        XCTAssertEqual(after.pts.count, before.pts.count)
        XCTAssertEqual(after.pts.count, 1 + MGLimits.funcIntervals + 1)
        for (p, q) in zip(before.pts.dropFirst(), after.pts.dropFirst()) {
            XCTAssertEqual(q.x, p.x)
            XCTAssertEqual(q.y, 1.5 * sin(2 * q.x) + 0.5, accuracy: 1e-12)
        }
        XCTAssertEqual(after.num["a"], 1.5)
        XCTAssertEqual(after.num["b"], 2)
        XCTAssertEqual(after.num["c"], 0.5)
        XCTAssertEqual(try XCTUnwrap(after.num["my"]), 1.5 * sin(2 * 1.5708) + 0.5, accuracy: 1e-12)
        XCTAssertEqual(after.marked, [])
        // The readout and the board description come from those engine numbers.
        XCTAssertEqual(state.caption(), ["y = a sin(bx) + c: a = 1.5, b = 2, c = 0.5, marked point (1.57, 0.5)"])
        XCTAssertEqual(state.caption(hiding: ["wave"]), [])
        // The renderer's frame uses the slider items (a still graph is not re-sampled again).
        XCTAssertEqual(MGTimeline.frame(s, items: state.items, time: 2), state.items)
        // Back at the defaults the board is the parsed board again, exactly.
        state.reset()
        XCTAssertEqual(state.items, MGTimeline.items(s, step: 0))
        XCTAssertTrue(state.set("a", stop: 6))
        XCTAssertTrue(state.set("a", stop: 4))
        XCTAssertEqual(state.items, MGTimeline.items(s, step: 0))
        XCTAssertNil(state.refusal)
    }

    func testAContinuousDragSnapsToTheGrid() throws {
        var state = MGSliderState(scene: try wave())
        XCTAssertTrue(state.set("a", nearest: 1.37))
        XCTAssertEqual(state.value("a"), 1.25)
        XCTAssertTrue(state.set("a", nearest: 9))
        XCTAssertEqual(state.value("a"), 2)
        XCTAssertTrue(state.set("a", nearest: -9))
        XCTAssertEqual(state.value("a"), 0)
        XCTAssertFalse(state.set("x", nearest: 1))
        XCTAssertFalse(state.set("a", stop: 9))
        let slider = try XCTUnwrap(state.slider("c"))
        XCTAssertEqual(slider.stop(nearest: .nan), slider.defaultStop)
        XCTAssertEqual((0...slider.steps).map(slider.value(at:)), [-1, -0.5, 0, 0.5, 1])
    }

    func testAMovingGraphFollowsTheSliderInEveryFrame() throws {
        let json = #"{"v":1,"items":[{"id":"w","k":"func","at":[1,1.5],"w":10,"h":5,"xr":[0,12.566],"yr":[-2.5,2.5],"y":"a*sin(x - 2*pi*t/4)","a":1,"period":4}],"sliders":[{"param":"a","min":0.5,"max":2,"step":0.5,"default":1,"label":"Height a"}]}"#
        let s = try scene(json)
        XCTAssertTrue(s.animates)
        var state = MGSliderState(scene: s)
        XCTAssertTrue(state.set("a", stop: 3))
        let frame = try XCTUnwrap(MGTimeline.frame(s, items: state.items, time: 1).first)
        for p in frame.pts.dropFirst() { XCTAssertEqual(p.y, 2 * sin(p.x - 2 * Double.pi / 4), accuracy: 1e-12) }
        // A moving graph's marked point moves, so the readout leaves it to the board.
        XCTAssertEqual(state.caption(), ["y = a*sin(x - 2*pi*t/4): a = 2"])
    }

    // MARK: refused positions

    /// `x/a` at a = 0 has no finite value anywhere (`func.empty`), while both ends of the range draw a line.
    static let divide = #"{"v":1,"items":[{"id":"f","k":"func","at":[1,1],"w":10,"h":6,"xr":[-3,3],"yr":[-4,4],"y":"x/a","a":1}],"sliders":[{"param":"a","min":-1,"max":1,"step":0.5,"default":1,"label":"Divisor a"}]}"#

    func testARefusedPositionKeepsTheBoardAndSaysWhy() throws {
        let s = try scene(Self.divide)
        var state = MGSliderState(scene: s)
        let shown = state.items
        XCTAssertFalse(state.set("a", stop: 2))
        XCTAssertEqual(state.items, shown)
        XCTAssertEqual(state.value("a"), 1)
        let refusal = try XCTUnwrap(state.refusal)
        XCTAssertEqual(refusal.error.reason, "func.empty")
        XCTAssertEqual(refusal.text, "a = 0 is not shown: nothing of the graph would be in view.")
        // The same position from a drag is answered from the record, not checked again.
        XCTAssertFalse(state.set("a", nearest: 0.1))
        XCTAssertEqual(state.refusal, refusal)
        // VoiceOver steps past a refused position, so the whole range stays reachable without a drag.
        XCTAssertTrue(state.set("a", stop: 3))
        XCTAssertNil(state.refusal)
        XCTAssertTrue(state.decrement("a"))
        XCTAssertEqual(state.value("a"), -0.5)
        XCTAssertEqual(state.refusal?.stop, 2)
        let line = try XCTUnwrap(state.items.first)
        for p in line.pts.dropFirst() { XCTAssertEqual(p.y, p.x / -0.5, accuracy: 1e-12) }
        XCTAssertTrue(state.decrement("a"))
        XCTAssertFalse(state.decrement("a"), "already at min")
        XCTAssertEqual(state.value("a"), -1)
    }

    func testAStepThatRefusesTheValuesSendsTheSlidersBack() throws {
        // Step 2 narrows the y range; at a = 2 its marked point (2, 4) would leave the view.
        let json = #"{"v":1,"items":[{"id":"f","k":"func","at":[1,1],"w":10,"h":6,"xr":[-3,3],"yr":[-4,4],"y":"a*x","a":1,"mark":2}],"steps":[{"say":"Wide."},{"say":"Narrow.","do":[{"id":"f","key":"yr","value":[-3,3]}]}],"sliders":[{"param":"a","min":0,"max":2,"step":1,"default":1,"label":"Slope a"}]}"#
        let s = try scene(json)
        var state = MGSliderState(scene: s)
        XCTAssertTrue(state.set("a", stop: 2))
        state.show(step: 1)
        XCTAssertTrue(state.isAtDefaults)
        XCTAssertEqual(state.items, MGTimeline.items(s, step: 1))
        XCTAssertEqual(state.refusal?.error.reason, "func.mark")
        XCTAssertEqual(state.refusal?.text, "The sliders are back at their starting values: at this step the marked point would have no value in view.")
        // A value the step accepts is kept across the step change.
        XCTAssertTrue(state.set("a", stop: 0))
        state.show(step: 0)
        XCTAssertEqual(state.value("a"), 0)
        XCTAssertNil(state.refusal)
        // A new scene revision keeps positions that are still valid, and starts over otherwise.
        XCTAssertEqual(MGSliderState(scene: s, keeping: ["a": 0]).value("a"), 0)
        XCTAssertEqual(MGSliderState(scene: s, keeping: ["a": 0.4]).value("a"), 1, "off the grid")
        XCTAssertEqual(MGSliderState(scene: s, step: 1, keeping: ["a": 2]).value("a"), 1, "refused at that step")
    }

    // MARK: accessibility

    func testTheSliderControlIsAnAdjustableElementWithLabelValueAndHint() throws {
        let s = try wave()
        var state = MGSliderState(scene: s)
        XCTAssertEqual(state.accessibility("a"), MGSliderAccessibility(label: "Height a", value: "1", hint: "From 0 to 2 in steps of 0.25.",
                                                                      identifier: "board.slider.a", adjustable: true))
        XCTAssertEqual(state.accessibility("b")?.hint, "From 0.5 to 3 in steps of 0.5.")
        XCTAssertEqual(state.accessibility("c")?.value, "0")
        XCTAssertNil(state.accessibility("x"))
        // The adjustable action moves one step per swipe and the spoken value follows.
        XCTAssertTrue(state.increment("a"))
        XCTAssertEqual(state.accessibility("a")?.value, "1.25")
        XCTAssertTrue(state.decrement("c"))
        XCTAssertEqual(state.accessibility("c")?.value, "-0.5")
        for _ in 0..<10 { state.increment("a") }
        XCTAssertEqual(state.accessibility("a")?.value, "2")
        XCTAssertFalse(state.increment("a"), "at max")
        // Every slider on the board is offered while the graph it drives is shown; none while it is concealed.
        XCTAssertEqual(state.sliders().map(\.param), ["a", "b", "c"])
        XCTAssertEqual(state.sliders(hiding: ["wave"]).map(\.param), [])
    }

    func testTheBoardIsDescribedFromTheEngineOnceASliderMoves() throws {
        let s = try wave()
        var state = MGSliderState(scene: s)
        // At the defaults: the narration, then the authored text alternative.
        XCTAssertEqual(state.accessibilityValue(), s.steps[0].say + " " + (s.alt ?? ""))
        // Moved: the authored text describes another board, so the engine describes the one drawn now.
        XCTAssertTrue(state.set("a", stop: 6))
        let value = state.accessibilityValue()
        XCTAssertTrue(value.hasPrefix(s.steps[0].say + " A graph of y = a*sin(b*x)+c"), value)
        XCTAssertTrue(value.contains("with a = 1.5, b = 1, c = 0"), value)
        XCTAssertTrue(value.contains("marking the point (1.57, 1.5)"), value)
        XCTAssertFalse(value.contains(s.alt ?? "-"), value)
        XCTAssertEqual(state.accessibilityValue(hiding: ["wave"]), s.steps[0].say + " The board is empty.")
        // The board says it from the items its evaluation read (`MGBoardFrames`), the same items it draws and charts.
        let cache = MGTimelineCache()
        let board = MGSliderState.boardFrames(s, step: 0, sliders: state, cache: cache)
        XCTAssertTrue(board.fromSliders)
        XCTAssertEqual(board.accessibilityValue(), value)
        XCTAssertEqual(board.accessibilityValue(hiding: ["wave"]), s.steps[0].say + " The board is empty.")
        state.reset()
        let back = MGSliderState.boardFrames(s, step: 0, sliders: state, cache: cache)
        XCTAssertFalse(back.fromSliders)
        XCTAssertEqual(back.accessibilityValue(), s.steps[0].say + " " + (s.alt ?? ""))
        XCTAssertEqual(back.accessibilityValue(describing: true), MGDescribe.accessibilityValue(s, step: 0, describing: true))
        XCTAssertEqual(cache.reads, 1, "only the evaluation at the defaults read the cache")
    }

    func testValuesAreWrittenWithTheSlidersOwnPrecision() throws {
        let s = try scene(#"{"v":1,"items":["# + Self.line.replacingOccurrences(of: #""a":1"#, with: #""a":100"#)
                          + #"],"sliders":[{"param":"a","min":100,"max":101,"step":0.125,"default":100,"label":"a"}]}"#)
        let slider = try XCTUnwrap(s.sliders.first)
        // MGPhysics.format would write 100.125 as "100"; the slider writes what the learner chose.
        XCTAssertEqual(slider.text(slider.value(at: 1)), "100.125")
        XCTAssertEqual(slider.text(101), "101")
        XCTAssertEqual(slider.text(-0.0), "0")
        XCTAssertEqual(MGSlider.decimals([0.1, 3]), 1)
        XCTAssertEqual(MGSlider.decimals([0.25, -1]), 2)
        XCTAssertEqual(MGSlider.decimals([1.0 / 3]), 6)
    }

    /// A slider built in code, so the formatter can be checked at ranges and steps a hand-written scene rarely uses.
    private func slider(min: Double, max: Double, step: Double) -> MGSlider {
        MGSlider(param: "a", min: min, max: max, step: step, defaultValue: min, label: "a", items: ["f"],
                 steps: Int(((max - min) / step).rounded()), defaultStop: 0, decimals: MGSlider.decimals([min, step]))
    }

    func testATinyStepIsNeverWrittenAsZero() throws {
        let s = slider(min: 0, max: 1e-5, step: 1e-7)
        // Six places would write the step, and the first stop above 0, as "0".
        XCTAssertEqual(s.decimals, 6)
        XCTAssertEqual(s.text(s.step), "0.0000001")
        XCTAssertEqual(s.text(s.value(at: 1)), "0.0000001")
        XCTAssertEqual(s.text(s.value(at: 37)), "0.0000037")
        XCTAssertEqual(s.text(s.max), "0.00001")
        XCTAssertEqual(s.text(0), "0")
        // Below 10⁻⁹ the significant digits carry an exponent.
        let tiny = slider(min: -3e-12, max: 3e-12, step: 1.5e-12)
        XCTAssertEqual(tiny.text(tiny.step), "1.5e-12")
        XCTAssertEqual(tiny.text(tiny.min), "-3e-12")
        XCTAssertEqual(tiny.text(tiny.value(at: 2)), "0")
        // Seven places past a whole number: 1.0000001 is not "1".
        let fine = slider(min: 1, max: 1.00001, step: 1e-7)
        XCTAssertEqual(fine.text(fine.value(at: 1)), "1.0000001")
        XCTAssertEqual(fine.text(fine.min), "1")

        // Through a parsed scene: the hint, the spoken and shown value and the readout use the same form.
        let parsed = try scene(#"{"v":1,"items":["# + Self.line.replacingOccurrences(of: #""a":1"#, with: #""a":0"#)
                               + #"],"sliders":[{"param":"a","min":0,"max":0.00001,"step":0.0000001,"default":0,"label":"Slope a"}]}"#)
        var state = MGSliderState(scene: parsed)
        XCTAssertEqual(state.accessibility("a")?.hint, "From 0 to 0.00001 in steps of 0.0000001.")
        XCTAssertTrue(state.increment("a"))
        XCTAssertEqual(state.accessibility("a")?.value, "0.0000001")
        XCTAssertEqual(state.caption(), ["y = a*x: a = 0.0000001"])
        // The refusal note writes its value the same way.
        let refusal = MGSliderRefusal(param: "a", stop: 3, value: try XCTUnwrap(parsed.sliders.first).text(3e-7),
                                      error: MGError("func.empty"))
        XCTAssertEqual(refusal.text, "a = 0.0000003 is not shown: nothing of the graph would be in view.")
    }

    func testNeighbouringStopsNeverShareALabel() throws {
        let sliders = [slider(min: 0, max: 1e-5, step: 1e-7), slider(min: 1, max: 1.00001, step: 1e-7),
                       slider(min: 0.1234567, max: 0.1244567, step: 0.00001), slider(min: -3e-12, max: 3e-12, step: 1.5e-12),
                       slider(min: -1, max: 1, step: 0.02), slider(min: 100, max: 101, step: 0.125),
                       slider(min: -1000, max: 1000, step: 20), slider(min: 0.5, max: 3, step: 0.5)]
        for s in sliders {
            let labels = (0...s.steps).map { s.text(s.value(at: $0)) }
            XCTAssertEqual(Set(labels).count, labels.count, "\(labels)")
            // Each label reads back as its own grid stop, and the step is never "0".
            for (k, label) in labels.enumerated() {
                XCTAssertEqual(s.stop(nearest: try XCTUnwrap(Double(label), label)), k, "\(label) in \(labels)")
            }
            let step = s.text(s.step)
            XCTAssertNotEqual(step, "0")
            XCTAssertEqual(try XCTUnwrap(Double(step)), s.step, accuracy: s.step * 1e-6, step)
        }
        // Where six places write the grid exactly, the compact form stays.
        XCTAssertEqual(slider(min: -1, max: 1, step: 0.02).text(-0.98), "-0.98")
        XCTAssertEqual(slider(min: 0.1234567, max: 0.1244567, step: 0.00001).text(0.1234567), "0.1234567")
    }

    func testStopsFinerThanTheDoublesAreRefused() throws {
        // Four steps from 1 to the third double above it: q is exactly 4, but stops 0 and 1 both evaluate to 1.
        let json = #"{"v":1,"items":[\#(Self.line)],"sliders":[{"param":"a","min":1,"max":1.0000000000000004,"step":1.1102230246251565e-16,"default":1,"label":"Slope a"}]}"#
        XCTAssertEqual(reason(json), "slider.grid")
        XCTAssertNotNil(MGRepairHint.text(for: "slider.grid"))
        let s = slider(min: 1, max: 1.0000000000000004, step: 1.1102230246251565e-16)
        XCTAssertEqual(s.steps, 4)
        XCTAssertEqual(s.value(at: 0), s.value(at: 1))
        XCTAssertFalse(s.gridIsDistinct)
        // Ordinary grids keep every stop apart.
        for g in [slider(min: 0, max: 1e-5, step: 1e-7), slider(min: -3e-12, max: 3e-12, step: 1.5e-12),
                  slider(min: -2.6, max: 2.6, step: 0.1), slider(min: -1000, max: 1000, step: 20)] {
            XCTAssertTrue(g.gridIsDistinct, "\(g.min)…\(g.max) by \(g.step)")
        }
    }

    func testANonzeroValueIsNeverWrittenAsZero() throws {
        let s = slider(min: -1, max: 1, step: 1)
        // Within a millionth of a step of 0, but not 0.
        XCTAssertEqual(s.text(1e-12), "1e-12")
        XCTAssertEqual(s.text(-1e-12), "-1e-12")
        XCTAssertEqual(s.text(0), "0")
        XCTAssertEqual(s.text(-0.0), "0")
        // The parser refuses such a default: the default is a stop, so it must read as the stop (0) does.
        let line = Self.line.replacingOccurrences(of: #""a":1"#, with: #""a":1e-12"#)
        XCTAssertEqual(reason(#"{"v":1,"items":[\#(line)],"sliders":[{"param":"a","min":-1,"max":1,"step":1,"default":1e-12,"label":"Slope a"}]}"#),
                       "slider.default")
        // A stop meant to be 0 is 0: min + (max − min) × 26 / 52 is 4.4e-16 from −2.6 to 2.6 in steps of 0.1.
        let wide = slider(min: -2.6, max: 2.6, step: 0.1)
        XCTAssertEqual(wide.value(at: 26), 0)
        XCTAssertEqual(wide.text(wide.value(at: 26)), "0")
    }

    func testAnEndTheSliderCannotShowExactlyIsRefused() throws {
        // Codex: 0 to 1.0000000002 in one step shows its last stop as `1`, so the engine would get 1.0000000002 under a
        // label of 1. At exactly 1 the graph y = 0.0000000001/(a-1) is refused (func.empty); at 1.0000000002 it is drawn.
        let s = slider(min: 0, max: 1.0000000002, step: 1)
        XCTAssertEqual(s.text(s.max), "1")
        XCTAssertEqual(s.value(at: 1), 1)
        XCTAssertFalse(s.gridIsDistinct)
        let graph = #"{"id":"f","k":"func","at":[1,1],"w":10,"h":6,"xr":[-3,3],"yr":[-4,4],"y":"0.0000000001/(a-1)","a":A}"#
        XCTAssertNil(reason(#"{"v":1,"items":["# + graph.replacingOccurrences(of: "A", with: "1.0000000002") + "]}"))
        XCTAssertEqual(reason(#"{"v":1,"items":["# + graph.replacingOccurrences(of: "A", with: "1") + "]}"), "func.empty")
        XCTAssertEqual(reason(#"{"v":1,"items":["# + graph.replacingOccurrences(of: "A", with: "0")
                              + #"],"sliders":[{"param":"a","min":0,"max":1.0000000002,"step":1,"default":0,"label":"Shift a"}]}"#),
                       "slider.grid")
        // A default of 1 shows as max does, but no longer stands in for max: the grid is refused first.
        XCTAssertEqual(reason(#"{"v":1,"items":[\#(Self.line)],"sliders":[{"param":"a","min":0,"max":1.0000000002,"step":1,"default":1,"label":"Slope a"}]}"#),
                       "slider.grid")
    }

    func testTheDefaultIsExactlyAStopAndNeverReplacesOne() throws {
        let line = Self.line.replacingOccurrences(of: #""a":1"#, with: #""a":0.30000000000000004"#)
        XCTAssertEqual(reason(#"{"v":1,"items":[\#(line)],"sliders":[{"param":"a","min":0,"max":1,"step":0.1,"default":0.30000000000000004,"label":"Slope a"}]}"#),
                       "slider.default")
        let exact = try scene(#"{"v":1,"items":["# + Self.line.replacingOccurrences(of: #""a":1"#, with: #""a":0.3"#)
                              + #"],"sliders":[{"param":"a","min":0,"max":1,"step":0.1,"default":0.3,"label":"Slope a"}]}"#)
        let parsed = try XCTUnwrap(exact.sliders.first)
        XCTAssertEqual(parsed.defaultStop, 3)
        XCTAssertEqual(parsed.value(at: 3), parsed.defaultValue)
        // value(at:) never returns the default in place of the stop's own value.
        let off = MGSlider(param: "a", min: 0, max: 1, step: 0.1, defaultValue: 0.30000000000000004, label: "a", items: ["f"],
                           steps: 10, defaultStop: 3, decimals: 1)
        XCTAssertEqual(off.value(at: 3), 0.3)
        let top = MGSlider(param: "a", min: 0, max: 1, step: 1, defaultValue: 0.9999999999, label: "a", items: ["f"],
                           steps: 1, defaultStop: 1, decimals: 0)
        XCTAssertEqual(top.value(at: 1), 1)
    }

    func testTheEngineGetsExactlyTheShownValueOnOrdinaryGrids() throws {
        // Every grid an author would write from these mins, steps and step counts (max written to six places): the
        // label read back is the engine value, the stops rise strictly from exactly min to exactly max, and the parser
        // accepts each stop as the default at its own position. tools/tests/test_mg_expr.py checks the same sample.
        var checked = 0
        for lo in [-1000, -10, -3, -2.6, -1, -0.5, -0.3, 0, 0.1, 0.25, 1, 2.5, 100] as [Double] {
            for step in [0.001, 0.01, 0.02, 0.05, 0.1, 0.125, 0.2, 0.25, 0.5, 1, 5, 20] as [Double] {
                for n in [2, 3, 4, 5, 7, 10, 13, 30, 64, 100] {
                    let hi = try XCTUnwrap(Double(String(format: "%.6f", lo + Double(n) * step)))
                    guard hi <= 1000 else { continue }
                    let name = "\(lo)…\(hi) by \(step)"
                    let s = slider(min: lo, max: hi, step: step)
                    XCTAssertEqual(s.steps, n, name)
                    XCTAssertTrue(s.gridIsDistinct, name)
                    let values = (0...s.steps).map(s.value(at:))
                    XCTAssertEqual(values.first, lo, name)
                    XCTAssertEqual(values.last, hi, name)
                    XCTAssertTrue(zip(values, values.dropFirst()).allSatisfy { $0 < $1 }, name)
                    for v in values { XCTAssertEqual(Double(s.text(v)), v, "\(s.text(v)) in \(name)") }
                    for k in [0, n / 2, n] {
                        let json = #"{"v":1,"items":[{"id":"f","k":"func","at":[1,1],"w":10,"h":6,"xr":[-3,3],"yr":[-4,4],"y":"a+x-a","a":\#(values[k])}],"sliders":[{"param":"a","min":\#(lo),"max":\#(hi),"step":\#(step),"default":\#(values[k]),"label":"a"}]}"#
                        let parsed = MGParser.scene(data: Data(json.utf8))
                        guard case .success(let sc) = parsed else { XCTFail("\(name) default \(values[k]): \(parsed)"); continue }
                        XCTAssertEqual(sc.sliders.first?.defaultStop, k, name)
                    }
                    checked += 1
                }
            }
        }
        XCTAssertGreaterThan(checked, 1000)
    }

    // MARK: audio graph

    func testTheAudioGraphIsBuiltFromTheSliderItems() throws {
        let s = try wave()
        var state = MGSliderState(scene: s)
        // At the defaults the live items are the step's items, so the chart is the authored board's chart.
        XCTAssertEqual(MGAudioGraph.chart(s, items: state.items), MGAudioGraph.chart(s, step: 0))
        XCTAssertTrue(state.set("a", stop: 6))   // a = 1.5
        let live = try XCTUnwrap(MGAudioGraph.chart(s, items: state.items))
        XCTAssertNotEqual(live, MGAudioGraph.chart(s, step: 0))
        // Every charted value is the engine's sample of the moved graph, 1.5 sin x, and the marked point is the engine's.
        let points = live.series.flatMap(\.points)
        XCTAssertFalse(points.isEmpty)
        for p in points { XCTAssertEqual(p.y, 1.5 * sin(p.x), accuracy: 1e-9, "\(p)") }
        let wave = try XCTUnwrap(state.items.first { $0.id == "wave" })
        XCTAssertEqual(points.first { $0.label == "marked point" }?.y, wave.num["my"])
        XCTAssertTrue(live.summary.contains("a = 1.5"), live.summary)
        // Concealed items stay out of it, as on the board.
        XCTAssertNil(MGAudioGraph.chart(s, items: state.items, hiding: ["wave"]))
    }

    /// At the defaults (before the first move and after a reset) each evaluation of the board takes the step items from
    /// the controller's cache (`MGTimelineCache`) with one read, and its frames and chart use them, so they are never
    /// computed again; an accepted non-default value gives the slider items, with no read (`MGSliderState.boardFrames`).
    func testAtTheDefaultsTheBoardTakesTheCachedStepItems() throws {
        let s = try wave()
        var state = MGSliderState(scene: s)
        var cache = MGTimelineCache()
        let cachedChart = MGAudioGraph.chart(s, step: 0)
        for evaluation in 0..<5 {
            let board = MGSliderState.boardFrames(s, step: 0, sliders: state, cache: cache)
            XCTAssertFalse(board.fromSliders)
            XCTAssertEqual(cache.computed, 1, "evaluation \(evaluation): computed once, through the cache")
            XCTAssertEqual(cache.reads, evaluation + 1, "evaluation \(evaluation): one read")
            XCTAssertEqual(board.items, MGTimeline.items(s, step: 0))
            XCTAssertEqual(board.chart(), cachedChart)
        }
        // A moved slider: the live items, and the cache is not asked.
        XCTAssertTrue(state.set("a", stop: 6))   // a = 1.5
        let reads = cache.reads
        let moved = MGSliderState.boardFrames(s, step: 0, sliders: state, cache: cache)
        XCTAssertTrue(moved.fromSliders)
        XCTAssertEqual(moved.items, state.items)
        XCTAssertNotEqual(moved.chart(), cachedChart)
        XCTAssertEqual(cache.computed, 1)
        XCTAssertEqual(cache.reads, reads, "the board with a moved slider read the cache")
        // After a reset the board is back on the cache (a fresh one shows it is asked, once).
        state.reset()
        XCTAssertTrue(state.isAtDefaults)
        cache = MGTimelineCache()
        for _ in 0..<5 {
            XCTAssertEqual(MGSliderState.boardFrames(s, step: 0, sliders: state, cache: cache).chart(), cachedChart)
        }
        XCTAssertEqual(cache.computed, 1)
        // A slider state for another revision or step never stands in for the shown board.
        XCTAssertTrue(state.set("a", stop: 6))
        var other = s
        other.revision = s.revision + 1
        let shown = MGSliderState.boardFrames(other, step: 0, sliders: state, cache: MGTimelineCache())
        XCTAssertFalse(shown.fromSliders)
        XCTAssertEqual(shown.items, MGTimeline.items(other, step: 0))
        XCTAssertFalse(state.movesBoard(s, step: 1))
    }

    /// A slider change settles an in-flight transition (`MGBoardMotion.settle`, as `changeSliders` does when the items
    /// change): the next frame draws exactly the items the audio graph charts, for a step blend and for keyframes.
    func testASliderChangeMidTransitionDrawsTheChartedItemsNextFrame() throws {
        let json = #"{"v":1,"items":[{"id":"w","k":"func","at":[1,1],"w":10,"h":6,"xr":[-3,3],"yr":[-4,4],"y":"a*sin(x)","a":1}],"steps":[{"say":"Wide."},{"say":"Narrow.","do":[{"id":"w","key":"yr","value":[-2,2]}]}],"sliders":[{"param":"a","min":0,"max":2,"step":0.5,"default":1,"label":"Height a"}]}"#
        let s = try scene(json)
        let t0 = Date(timeIntervalSinceReferenceDate: 1_000)
        // Early in the spring (it passes 1 at about 0.18 s, and a blend at 1 or more is the target).
        let mid = t0.addingTimeInterval(0.1), next = mid.addingTimeInterval(1.0 / 60)
        let cache = MGTimelineCache()
        var state = MGSliderState(scene: s)
        var motion = MGBoardMotion()
        var step = 0
        // An evaluation of the board: the items it shows now (`MGSliderState.boardFrames`, as `MGSceneHost.board` reads them).
        func board() -> MGBoardFrames { MGSliderState.boardFrames(s, step: step, sliders: state, cache: cache) }
        func live() -> [MGItem] { board().items }
        func drawn(_ now: Date) -> [MGItem] { motion.frame(board(), style: .spring, now: now, time: 0, hiding: [], reduceMotion: false).items }
        func phase(_ now: Date) -> MGBoardTransition.Phase { motion.phase(.spring, at: now, cameraElapsed: .infinity, drawingOn: false, reduceMotion: false) }
        func chart(_ items: [MGItem]) -> MGAudioGraph.Chart? { MGAudioGraph.chart(s, items: items) }

        // Step 0 → 1, as `go` does: blend from what step 0 drew; the step narrows the y range.
        motion.blend(from: MGTimeline.frame(s, items: live(), time: 0), at: t0)
        step = 1; state.show(step: 1)
        XCTAssertEqual(phase(mid), .moving)
        XCTAssertNotEqual(drawn(mid), MGTimeline.frame(s, items: live(), time: 0), "mid-blend")
        // The slider moves mid-blend. Left alone, the blend would keep drawing a mix of the old board and the new one.
        let shown = state.items
        XCTAssertTrue(state.set("a", stop: 3))   // a = 1.5
        XCTAssertNotEqual(state.items, shown)
        XCTAssertNotEqual(chart(drawn(next)), chart(live()), "unsettled, the canvas and the chart differ")
        motion.settle()
        XCTAssertEqual(phase(next), .settled)
        XCTAssertEqual(drawn(next), MGTimeline.frame(s, items: live(), time: 0))
        XCTAssertEqual(chart(drawn(next)), board().chart())
        XCTAssertEqual(chart(drawn(next)), chart(state.items))

        // Engine keyframes (a = 1 → 2, no sliders on the frames) in flight, then a reset back to the defaults.
        let target = try scene(#"{"v":1,"items":[{"id":"w","k":"func","at":[1,1],"w":10,"h":6,"xr":[-3,3],"yr":[-2,2],"y":"a*sin(x)","a":2}]}"#)
        let plan = MGAdoption.plan(previous: live(), next: s.items,
                                   transition: .keyframes([MGKeyframeSegment(frames: [s, target], duration: 1)]), step: step)
        XCTAssertFalse(plan.segments.isEmpty)
        motion.play(plan.segments, duration: plan.duration, at: t0)
        XCTAssertEqual(phase(mid), .moving)
        XCTAssertNotEqual(chart(drawn(mid)), chart(live()), "mid-keyframes")
        state.reset()
        XCTAssertTrue(state.isAtDefaults)
        motion.settle()
        XCTAssertEqual(motion.keyframesLeft(at: next), 0)
        XCTAssertEqual(drawn(next), MGTimeline.frame(s, items: cache.items(s, step: 1), time: 0))
        XCTAssertEqual(chart(drawn(next)), chart(live()))
        XCTAssertEqual(chart(drawn(next)), MGAudioGraph.chart(s, step: 1))
    }

    /// The board draws its frame and decides its split from one `MGBoardMotion` (`MGBoardTransition`): for both
    /// transition styles, with and without Reduce Motion and with a concealed leaving item, the frame is the style's
    /// blend of the live frame (`.spring`: a leaving item vanishes, and with Reduce Motion the board snaps; `.bounded`:
    /// it fades, a concealed one stays hidden, and with Reduce Motion the board dissolves), the phase is
    /// `MGBoardTransition.phase` of the same blend, and whenever that phase lets the board split, the frame is the live
    /// frame with nothing fading, so a base cached then is exact.
    func testTheBoardsFrameAndItsSplitComeFromOneMotionState() throws {
        let s = try scene(Self.splitBoard)
        let t0 = Date(timeIntervalSinceReferenceDate: 1_000)
        let cache = MGTimelineCache()
        let live = cache.items(s, step: 1)
        let board = MGBoardFrames(scene: s, step: 1, items: live)
        let from = MGTimeline.frame(s, items: cache.items(s, step: 0), time: 0) + [MGMake.body("old", MGPoint(2, 6.5))]
        XCTAssertNotEqual(live.first { $0.id == "g" }, from.first { $0.id == "g" }, "the step moves the graph")
        for style in MGTransitionStyle.allCases {
            for reduce in [false, true] {
                for hiding: Set<String> in [[], ["old"]] {
                    let what = "\(style.rawValue), Reduce Motion \(reduce), hiding \(hiding.sorted())"
                    var motion = MGBoardMotion()
                    motion.blend(from: from, at: t0)
                    var rest = MGTimeline.frame(s, items: live, time: 0)
                    rest.removeAll { hiding.contains($0.id) }
                    for k in 0...130 {
                        let t = Double(k) / 100, now = t0.addingTimeInterval(t), elapsed = now.timeIntervalSince(t0)
                        let frame = motion.frame(board, style: style, now: now, time: 0, hiding: hiding, reduceMotion: reduce)
                        var want = MGBoardTransition.items(style, from: from, to: rest, elapsed: elapsed, reduceMotion: reduce)
                        if style == .bounded { want.items.removeAll { hiding.contains($0.id) } }
                        XCTAssertEqual(frame, want, "\(what): the frame at \(t) s")
                        let phase = motion.phase(style, at: now, cameraElapsed: .infinity, drawingOn: false, reduceMotion: reduce)
                        XCTAssertEqual(phase, MGBoardTransition.phase(style, blendElapsed: elapsed, cameraElapsed: .infinity, keyframes: false,
                                                                      drawingOn: false, reduceMotion: reduce), "\(what): the phase at \(t) s")
                        if phase != .moving {
                            XCTAssertEqual(frame, MGStepTransition.Frame(items: rest, opacity: [:]), "\(what): split mid-transition at \(t) s")
                        }
                    }
                    let mid = motion.frame(board, style: style, now: t0.addingTimeInterval(0.3), time: 0, hiding: hiding, reduceMotion: reduce)
                    switch (style, reduce) {
                    case (.spring, false):
                        XCTAssertNil(mid.items.first { $0.id == "old" }, "\(what): a leaving item vanishes")
                        XCTAssertEqual(mid.opacity, [:], what)
                    case (.spring, true):
                        XCTAssertEqual(mid, MGStepTransition.Frame(items: rest, opacity: [:]), "\(what): the board snaps")
                    case (.bounded, _):
                        if hiding.isEmpty {
                            XCTAssertTrue((0.01...0.99).contains(mid.opacity["old"] ?? -1), "\(what): the leaving item fades: \(mid.opacity)")
                        } else {
                            XCTAssertNil(mid.items.first { $0.id == "old" }, "\(what): a concealed leaving item stays hidden")
                        }
                    }
                    // Settled, the frame is the live frame at once and only the camera can hold the split.
                    motion.settle()
                    XCTAssertEqual(motion.frame(board, style: style, now: t0.addingTimeInterval(0.3), time: 0, hiding: hiding, reduceMotion: reduce),
                                   MGStepTransition.Frame(items: rest, opacity: [:]), "\(what): settled")
                    XCTAssertEqual(motion.phase(style, at: t0.addingTimeInterval(0.3), cameraElapsed: .infinity, drawingOn: false, reduceMotion: reduce),
                                   .settled, "\(what): settled")
                }
            }
        }
    }

    /// A slider change mid-step settles the step's blend (`MGBoardMotion.settle`, as `changeSliders` does): the frame is
    /// the slider items at once, and the board may split as soon as the step's camera move ends (1.0 s), before the
    /// default spring blend's window would have (1.2 s). With no camera move left the board may split at once.
    func testASliderChangeLetsTheBoardSplitAsSoonAsTheCameraAllows() throws {
        let s = try scene(Self.splitBoard)
        let t0 = Date(timeIntervalSinceReferenceDate: 1_000)
        let cache = MGTimelineCache()
        let before = MGTimeline.frame(s, items: cache.items(s, step: 0), time: 0)
        for style in MGTransitionStyle.allCases {
            for reduce in [false, true] {
                let what = "\(style.rawValue), Reduce Motion \(reduce)"
                func phase(_ m: MGBoardMotion, _ t: Double) -> MGBoardTransition.Phase {
                    m.phase(style, at: t0.addingTimeInterval(t), cameraElapsed: t, drawingOn: false, reduceMotion: reduce)
                }
                // The step change, as `go` does: the blend and the camera move start together.
                var state = MGSliderState(scene: s)
                var motion = MGBoardMotion()
                motion.blend(from: before, at: t0)
                state.show(step: 1)
                // The slider moves mid-step; the change of the board's items settles the blend.
                XCTAssertTrue(state.set("a", nearest: 1.5))
                let unsettled = motion
                motion.settle()
                let board = MGSliderState.boardFrames(s, step: 1, sliders: state, cache: cache)
                XCTAssertTrue(board.fromSliders)
                XCTAssertEqual(board.items, state.items)
                for t in [0.3, 0.9] {
                    XCTAssertEqual(motion.frame(board, style: style, now: t0.addingTimeInterval(t), time: 0, hiding: [], reduceMotion: reduce),
                                   MGStepTransition.Frame(items: MGTimeline.frame(s, items: state.items, time: 0), opacity: [:]),
                                   "\(what): at \(t) s the frame is the slider items")
                    XCTAssertEqual(phase(motion, t), reduce ? .settled : .moving, "\(what): at \(t) s only the camera holds the split")
                }
                XCTAssertEqual(phase(motion, 1.05), .settled, "\(what): the camera move has ended, so the board splits")
                if style == .spring, !reduce {
                    XCTAssertEqual(phase(unsettled, 1.05), .moving, "unsettled, the spring blend would keep one canvas until 1.2 s")
                }
                // After the camera move, a slider change during a blend that still runs lets the board split at once.
                var late = MGBoardMotion()
                late.blend(from: before, at: t0)
                if style == .spring, !reduce { XCTAssertEqual(phase(late, 1.1), .moving, what) }
                late.settle()
                XCTAssertEqual(phase(late, 1.1), .settled, "\(what): no camera move left, so the board splits at once")
            }
        }
    }

    /// A slider change during a step while motion plays (`changeSliders`): the step's transition window (1.6 s, opened by
    /// `go`) ends with the step's camera move (`MGBoardTransition.windowEnd`), so the board splits
    /// (`MGRenderPolicy.layered` with `MGBoardTransition.phase`) as soon as that move ends at 1.0 s, not when the
    /// step's window would have ended. The window never grows, and ends at once when no camera move is left or with
    /// Reduce Motion (the camera does not move).
    func testASliderChangeDuringAStepEndsItsWindowWithTheCameraMove() throws {
        let s = try scene(Self.splitBoard)
        let t0 = Date(timeIntervalSinceReferenceDate: 1_000)
        let cache = MGTimelineCache()
        let before = MGTimeline.frame(s, items: cache.items(s, step: 0), time: 0)
        let stepWindow = t0.addingTimeInterval(MGRenderPolicy.transientSeconds)   // `go`: bumpTransient()
        let moved = t0.addingTimeInterval(0.3)
        for style in MGTransitionStyle.allCases {
            let what = style.rawValue
            // As the board decides at `t`: motion plays, the window has ended and its own transitions allow a split.
            func splits(_ motion: MGBoardMotion, window: Date, _ t: Double) -> Bool {
                let now = t0.addingTimeInterval(t)
                let state = MGRenderPolicy.State(motionPlaying: true, transientActive: now < window, visible: true, sceneActive: true,
                                                 reduceMotion: false)
                return MGRenderPolicy.layered(state)
                    && motion.phase(style, at: now, cameraElapsed: now.timeIntervalSince(t0), drawingOn: false, reduceMotion: false) != .moving
            }
            // The step change, as `go` does: the blend, the camera move and the window start together.
            var state = MGSliderState(scene: s)
            var motion = MGBoardMotion()
            motion.blend(from: before, at: t0)
            state.show(step: 1)
            // The slider moves 0.3 s into the step: the change settles the blend and ends the window with the camera move.
            XCTAssertTrue(state.set("a", nearest: 1.5))
            motion.settle()
            let window = MGBoardTransition.windowEnd(stepWindow, settledAt: moved, cameraStart: t0, reduceMotion: false)
            XCTAssertEqual(window, t0.addingTimeInterval(MGBoardTransition.cameraWindow), "\(what): the window ends with the camera move")
            for t in [0.3, 0.6, 0.95] { XCTAssertFalse(splits(motion, window: window, t), "\(what): one canvas at \(t) s, the camera moves") }
            for t in [1.05, 1.1, 1.3] { XCTAssertTrue(splits(motion, window: window, t), "\(what): split at \(t) s, the camera move has ended") }
            // The step's own window would hold one canvas until 1.6 s, although the blend is settled.
            XCTAssertFalse(splits(motion, window: stepWindow, 1.1), "\(what): the step's window would still hold the board")
            XCTAssertTrue(splits(motion, window: stepWindow, 1.65), what)
            // From the window's end on, the camera stands still.
            XCTAssertNil(MGBoardTransition.cameraProgress(style, elapsed: window.timeIntervalSince(t0), reduceMotion: false), what)
            XCTAssertNotNil(MGBoardTransition.cameraProgress(style, elapsed: window.timeIntervalSince(t0) - 0.01, reduceMotion: false), what)
        }
        // The window never grows: a window that ends before the camera move, or one already over, stays as it is.
        let early = t0.addingTimeInterval(0.5)
        XCTAssertEqual(MGBoardTransition.windowEnd(early, settledAt: moved, cameraStart: t0, reduceMotion: false), early)
        XCTAssertEqual(MGBoardTransition.windowEnd(.distantPast, settledAt: moved, cameraStart: t0, reduceMotion: false), .distantPast)
        // No camera move left (a patch's window long after the last step, or no step change yet): it ends at once.
        let late = t0.addingTimeInterval(5)
        XCTAssertEqual(MGBoardTransition.windowEnd(late.addingTimeInterval(1.6), settledAt: late, cameraStart: t0, reduceMotion: false), late)
        XCTAssertEqual(MGBoardTransition.windowEnd(stepWindow, settledAt: moved, cameraStart: .distantPast, reduceMotion: false), moved)
        // With Reduce Motion the camera does not move: the window ends at once.
        XCTAssertEqual(MGBoardTransition.windowEnd(stepWindow, settledAt: moved, cameraStart: t0, reduceMotion: true), moved)
    }

    /// The board's transition window and the task that waits for it (`MGTransientWindow`, the host's `.task(id:)`):
    /// every change gives the window a new token, and SwiftUI cancels the task of an old token only at its next update.
    /// A task that wakes in that gap neither reads the newer deadline nor closes the window, so a stale task cannot
    /// close a window that a later step opened; only the task of the current token closes it.
    func testAStaleWindowTaskNeverClosesANewerWindow() {
        let t0 = Date(timeIntervalSinceReferenceDate: 1_000)
        func at(_ t: Double) -> Date { t0.addingTimeInterval(t) }
        var window = MGTransientWindow()
        XCTAssertFalse(window.active(at: t0))
        // A step opens the window until 1.6 s (`go`); its task starts for that token.
        window.keepOpen(from: t0, for: MGRenderPolicy.transientSeconds)
        let stepTask = window.token
        XCTAssertEqual(window.deadline(for: stepTask), at(1.6))
        // A slider change ends it with the camera move (`windowEnd`): a new token, so the step's task is stale.
        XCTAssertTrue(window.end(by: at(MGBoardTransition.cameraWindow)))
        let sliderTask = window.token
        XCTAssertNotEqual(sliderTask, stepTask)
        XCTAssertNil(window.deadline(for: stepTask), "a stale task read the newer deadline")
        XCTAssertEqual(window.deadline(for: sliderTask), at(1.0))
        // The slider's task closes the window; the step's task then wakes before SwiftUI has cancelled it.
        XCTAssertTrue(window.close(sliderTask))
        XCTAssertEqual(window.until, .distantPast)
        XCTAssertFalse(window.close(stepTask))
        // The next step opens the window at 1.2 s, until 2.8 s. Both old tasks wake before SwiftUI cancels them: neither
        // reads the new deadline or closes the new window.
        window.keepOpen(from: at(1.2), for: MGRenderPolicy.transientSeconds)
        let nextTask = window.token, opened = window.until
        XCTAssertEqual(opened.timeIntervalSince(t0), 2.8, accuracy: 1e-9)
        for (what, stale) in [("step", stepTask), ("slider", sliderTask)] {
            XCTAssertNil(window.deadline(for: stale), "the \(what) task read the next step's deadline")
            XCTAssertFalse(window.close(stale), "the \(what) task closed the next step's window")
            XCTAssertEqual(window.until, opened, what)
            XCTAssertEqual(window.token, nextTask, what)
        }
        XCTAssertTrue(window.active(at: at(2.7)), "the next step's window closed early")
        // Only the next step's task closes it.
        XCTAssertEqual(window.deadline(for: nextTask), opened)
        XCTAssertTrue(window.close(nextTask))
        XCTAssertFalse(window.active(at: at(1.3)))
        // An open window never ends earlier for a shorter change; ending it later changes nothing and keeps the token,
        // so the task that waits for it is not restarted.
        window.keepOpen(from: at(3), for: 1.6)
        let long = window.until
        window.keepOpen(from: at(3), for: 0.1)
        XCTAssertEqual(window.until, long)
        let kept = window.token
        XCTAssertFalse(window.end(by: at(5)))
        XCTAssertEqual(window.token, kept)
        XCTAssertEqual(window.until, long)
    }

    /// `MGBoardMotion.frame` draws from the items one evaluation of the board read (`MGBoardFrames`), never from the
    /// controller's cache: while engine keyframes supply the frame (their sample), once they end or are settled and with
    /// Reduce Motion (no keyframes play: the board's items), every frame leaves the cache's reads where the board's
    /// evaluation left them. (Before the board's frames, the frame read the live items lazily, and a keyframe frame
    /// never asked for them; now no frame does.)
    func testNoFrameReadsTheCacheWithOrWithoutKeyframes() throws {
        let json = #"{"v":1,"items":[{"id":"w","k":"func","at":[1,1],"w":10,"h":6,"xr":[-3,3],"yr":[-4,4],"y":"a*sin(x)","a":1}],"sliders":[{"param":"a","min":0,"max":2,"step":0.5,"default":1,"label":"Height a"}]}"#
        let s = try scene(json)
        let target = try scene(#"{"v":1,"items":[{"id":"w","k":"func","at":[1,1],"w":10,"h":6,"xr":[-3,3],"yr":[-2,2],"y":"a*sin(x)","a":2}]}"#)
        let t0 = Date(timeIntervalSinceReferenceDate: 1_000)
        let plan = MGAdoption.plan(previous: s.items, next: s.items, transition: .keyframes([MGKeyframeSegment(frames: [s, target], duration: 1)]), step: 0)
        XCTAssertFalse(plan.segments.isEmpty)
        let cache = MGTimelineCache()
        let board = MGSliderState.boardFrames(s, step: 0, sliders: MGSliderState(scene: s), cache: cache)
        XCTAssertEqual(cache.reads, 1, "the evaluation reads the step once")
        let rest = MGTimeline.frame(s, items: board.items, time: 0)
        func draw(_ m: MGBoardMotion, _ t: Double, reduceMotion: Bool = false) -> [MGItem] {
            m.frame(board, style: .spring, now: t0.addingTimeInterval(t), time: 0, hiding: [], reduceMotion: reduceMotion).items
        }
        var motion = MGBoardMotion()
        motion.play(plan.segments, duration: plan.duration, at: t0)
        for k in 0..<10 {
            let now = t0.addingTimeInterval(Double(k) * 0.09)
            let sample = MGTimeline.frame(s, items: MGTween.sample(plan.segments, at: MGTransitionClock(start: t0).elapsed(at: now)), time: 0)
            XCTAssertEqual(draw(motion, Double(k) * 0.09), sample, "the keyframes at \(Double(k) * 0.09) s")
        }
        XCTAssertNotEqual(draw(motion, 0.5), rest, "mid-keyframes")
        XCTAssertEqual(draw(motion, plan.duration + 0.1), rest, "after the keyframes, the board's items")
        XCTAssertEqual(draw(motion, 0.5, reduceMotion: true), rest, "with Reduce Motion no keyframes play")
        motion.settle()
        XCTAssertEqual(draw(motion, 0.5), rest, "settled keyframes")
        XCTAssertEqual(cache.reads, 1, "a frame read the cache")
        XCTAssertEqual(cache.computed, 1)
    }

    /// The controller's cache through a blended change, read as the board reads it (`MGSliderState.boardFrames` once per
    /// evaluation, for its frames and its chart; `leavingItems` for what `adopt` blends from): the incoming step's items
    /// are computed at most once and are never evicted, and frames and charts read nothing. A step change (`go`) reads
    /// the outgoing step through the cache, which keeps both steps. A scene change reads the outgoing revision without
    /// filling the cache (`MGTimelineCache.peek`), whether the board read the incoming revision first or not; filling it
    /// with the outgoing revision would clear the incoming entries. With a slider at a non-default value the board shows
    /// the learner's items: no evaluation reads the cache, and the blend from the scene it leaves reads it neither.
    func testABlendedChangeComputesTheIncomingStepAtMostOnce() throws {
        let s = try scene(Self.splitBoard)
        let t0 = Date(timeIntervalSinceReferenceDate: 1_000)
        // Five evaluations of the board through the 1.2 s blend window, each reading the board's items once, as
        // `MGSceneHost.board` does, then drawing four frames and building the chart from them.
        func evaluations(_ scene: MGScene, step: Int, _ motion: MGBoardMotion, _ cache: MGTimelineCache, sliders: MGSliderState? = nil) {
            for e in 0..<5 {
                let board = MGSliderState.boardFrames(scene, step: step, sliders: sliders, cache: cache)
                for k in 0..<4 {
                    _ = motion.frame(board, style: .spring, now: t0.addingTimeInterval(Double(e * 4 + k) * 0.07), time: 0, hiding: [],
                                     reduceMotion: false)
                }
                _ = board.chart()
            }
        }
        // A step change with a blend (`go`): from the outgoing step's items, then evaluations of step 1.
        do {
            let cache = MGTimelineCache()
            for _ in 0..<3 { _ = MGSliderState.boardFrames(s, step: 0, sliders: nil, cache: cache) }
            XCTAssertEqual(cache.computed, 1)
            var motion = MGBoardMotion()
            motion.blend(from: MGSliderState.boardFrames(s, step: 0, sliders: nil, cache: cache).frame(time: 0), at: t0)
            evaluations(s, step: 1, motion, cache)
            XCTAssertEqual(cache.computed, 2, "the step change computed step 1 once and kept step 0")
            XCTAssertEqual(cache.kept, 2)
            XCTAssertEqual(cache.reads, 3 + 1 + 5, "one read per evaluation and one for the blend; frames and charts read nothing")
        }
        // A scene change with a blend: the incoming scene has a new revision.
        var next = s
        next.revision = s.revision + 1
        for incomingFirst in [true, false] {
            let what = incomingFirst ? "the board read the incoming scene first" : "adopt read first"
            let cache = MGTimelineCache()
            _ = MGSliderState.boardFrames(s, step: 0, sliders: nil, cache: cache)   // the outgoing scene's evaluation
            let filled = cache.computed
            if incomingFirst { _ = MGSliderState.boardFrames(next, step: 0, sliders: nil, cache: cache).chart() }
            let reads = cache.reads
            let leaving = MGSliderState.leavingItems(s, step: 0, sliders: nil, cache: cache)
            XCTAssertEqual(leaving, MGTimeline.items(s, step: 0), what)
            XCTAssertEqual(cache.reads, reads, "\(what): the outgoing read is a peek")
            var motion = MGBoardMotion()
            motion.blend(from: MGTimeline.frame(s, items: leaving, time: 0), at: t0)
            evaluations(next, step: 0, motion, cache)
            XCTAssertEqual(cache.computed - filled, 1, "\(what): the incoming step was computed once")
            XCTAssertEqual(cache.kept, 1, what)
            XCTAssertEqual(cache.items(next, step: 0), MGTimeline.items(next, step: 0), what)
            XCTAssertEqual(cache.computed - filled, 1, "\(what): the incoming step is still kept")
        }
        // Filling the cache with the outgoing revision instead clears the incoming entries: computed again.
        do {
            let cache = MGTimelineCache()
            _ = MGSliderState.boardFrames(s, step: 0, sliders: nil, cache: cache)
            let filled = cache.computed
            _ = MGSliderState.boardFrames(next, step: 0, sliders: nil, cache: cache)
            _ = MGSliderState.boardFrames(s, step: 0, sliders: nil, cache: cache)
            _ = MGSliderState.boardFrames(next, step: 0, sliders: nil, cache: cache)
            XCTAssertEqual(cache.computed - filled, 3, "an outgoing read through the cache evicts the incoming entries")
        }
        // With a moved slider the board blends from the learner's items, and the cache is not asked.
        var state = MGSliderState(scene: s)
        XCTAssertTrue(state.set("a", nearest: 1.5))
        do {
            let cache = MGTimelineCache()
            XCTAssertEqual(MGSliderState.leavingItems(s, step: 0, sliders: state, cache: cache), state.items)
            XCTAssertEqual(cache.computed, 0)
            XCTAssertEqual(cache.kept, 0)
        }
        // A scene change (a patch: a new revision of the same scene) with the slider moved. `adopt` keeps the learner's
        // value on the new revision, so its board shows the slider's items too. The board's evaluations and the blend
        // read the cache only if the board evaluated the new revision before `adopt` gave the sliders that revision
        // (once, so the incoming step is computed at most once), and never evict it. Back at the defaults, the board
        // reads the incoming step through the cache, computed at most once in all.
        for incomingFirst in [true, false] {
            let what: String = incomingFirst ? "slider moved, the board read the incoming scene first" : "slider moved, adopt read first"
            let incomingReads: Int = incomingFirst ? 1 : 0
            let cache = MGTimelineCache()
            evaluations(s, step: 0, MGBoardMotion(), cache, sliders: state)   // the outgoing scene, slider moved
            XCTAssertEqual(cache.reads, 0, "\(what): an evaluation with the slider moved read the cache")
            // Before `adopt`, the slider state is still the outgoing revision's: the incoming board reads the cache.
            if incomingFirst { _ = MGSliderState.boardFrames(next, step: 0, sliders: state, cache: cache).chart() }
            let leaving = MGSliderState.leavingItems(s, step: 0, sliders: state, cache: cache)
            XCTAssertEqual(leaving, state.items, what)
            let kept = MGSliderState(scene: next, step: 0, keeping: state.values)   // `adopt`
            XCTAssertTrue(kept.movesBoard(next, step: 0), what)
            var motion = MGBoardMotion()
            motion.blend(from: MGTimeline.frame(s, items: leaving, time: 0), at: t0)
            evaluations(next, step: 0, motion, cache, sliders: kept)
            XCTAssertEqual(cache.reads, incomingReads, "\(what): reads")
            XCTAssertEqual(cache.computed, incomingReads, "\(what): computed")
            XCTAssertEqual(MGSliderState.boardFrames(next, step: 0, sliders: kept, cache: cache).items, kept.items, what)
            var reset = kept
            reset.reset()
            evaluations(next, step: 0, motion, cache, sliders: reset)
            XCTAssertEqual(cache.computed, 1, "\(what): the incoming step is computed once in all")
            let defaultReads: Int = incomingReads + 5
            XCTAssertEqual(cache.reads, defaultReads, "\(what): one read per evaluation at the defaults")
        }
    }

    /// The board the hosted slider tests use (`SliderBoardHostTests`): its body moves, so the board splits while the
    /// motion plays, and the graph the slider drives is in the cached base below it at every step and slider value.
    func testTheSplitBoardCachesTheDrivenGraphInTheBase() throws {
        let s = try scene(Self.splitBoard)
        XCTAssertTrue(s.animates)
        XCTAssertNotNil(s.steps[1].camera, "the second step moves the camera")
        for step in s.steps.indices {
            var state = MGSliderState(scene: s, step: step)
            for value in [1.0, 1.5, 0.5] {
                if value != 1.0 { XCTAssertTrue(state.set("a", nearest: value), "step \(step), a = \(value)") }
                let items = MGTimeline.frame(s, items: state.items, time: 0)
                let live = MGCanvasLayers.live(s, items: items)
                XCTAssertEqual(live, ["dot"], "step \(step), a = \(value)")
                XCTAssertEqual(MGCanvasLayers.base(items, live: live), ["floor", "g"], "step \(step), a = \(value)")
                XCTAssertNotNil(MGAudioGraph.chart(s, items: state.items), "step \(step), a = \(value)")
            }
        }
    }

    // MARK: repair hints

    /// A slider may not drive a `func` that lists readouts (`slider.readouts`). A readout fills the scene's texts once,
    /// at parse time (`MGScene.values`), and a slider move re-parses the graph (`MGSliderState.apply`), which computes
    /// its readouts again: a text would keep the default's number beside the moved graph. A graph the slider does not
    /// drive may list readouts; they keep their numbers when the slider moves.
    func testASliderNeverDrivesAGraphWithReadouts() throws {
        let graph = #"{"id":"w","k":"func","at":[1,1],"w":10,"h":6,"xr":[-3,3],"yr":[-4,4],"y":"a*sin(x)","a":1,"mark":1,"readouts":["slope"]}"#
        let text = #"{"id":"t","k":"text","at":[8,7],"text":"Slope {w.slope}"}"#
        let slider = #""sliders":[{"param":"a","min":0,"max":2,"step":0.5,"default":1,"label":"Height a"}]"#
        XCTAssertEqual(reason(#"{"v":1,"items":[\#(graph),\#(text)],\#(slider)}"#), "slider.readouts")
        XCTAssertEqual(reason(#"{"v":1,"items":[\#(graph)],\#(slider)}"#), "slider.readouts", "with or without a text")
        // Why: without the slider the scene parses, the text holds the default's slope, and a slider's re-parse of the
        // graph moves the slope while the text stays.
        let s = try scene(#"{"v":1,"items":[\#(graph),\#(text)]}"#)
        XCTAssertEqual(s.item("t")?.text, "Slope 0.54")
        let slopeAtDefault: Double = cos(1.0)
        XCTAssertEqual(try XCTUnwrap(s.values["w.slope"]?.value), slopeAtDefault, accuracy: 1e-12)
        // The graph at a = 1.5, re-parsed from its wire form as `MGSliderState.apply` re-parses a driven graph.
        var wire = try XCTUnwrap(s.item("w")).wire()
        wire["a"] = .number(1.5)
        let ctx = MGContext(width: s.width, height: s.height, is3D: s.is3D, values: s.values)
        let moved = try MGParser.item(.object(wire), ctx)
        let slopeMoved: Double = 1.5 * cos(1.0)
        XCTAssertEqual(try XCTUnwrap(moved.num[MGReadout.slope.key]), slopeMoved, accuracy: 1e-12)
        XCTAssertEqual(s.item("t")?.text, "Slope 0.54", "the text keeps the default's number")
        // Readouts of a graph the slider does not drive: accepted, and unchanged by a slider move.
        let other = try scene(#"{"v":1,"items":[{"id":"g","k":"func","at":[1,1],"w":10,"h":6,"xr":[-3,3],"yr":[-4,4],"y":"sin(x)","#
            + #""mark":1,"readouts":["slope"]},{"id":"w","k":"func","at":[1,1],"w":10,"h":6,"xr":[-3,3],"yr":[-4,4],"y":"a*x/3","a":1},"#
            + #"{"id":"t","k":"text","at":[8,7],"text":"Slope {g.slope}"}],\#(slider)}"#)
        var state = MGSliderState(scene: other)
        XCTAssertTrue(state.set("a", nearest: 1.5))
        XCTAssertEqual(state.items.first { $0.id == "g" }?.num[MGReadout.slope.key], other.values["g.slope"]?.value)
        XCTAssertEqual(state.items.first { $0.id == "t" }?.text, "Slope 0.54")
    }

    func testRepairHintsFollowTheReasonPatterns() {
        func row(_ pattern: String) -> String? { MGRepairHint.table.first { $0.0 == pattern }?.1 }
        XCTAssertEqual(MGRepairHint.text(for: "slider.default.wave"), row("slider.default.*"))
        XCTAssertEqual(MGRepairHint.text(for: "slider.default"), row("slider.default"))
        XCTAssertEqual(MGRepairHint.text(for: "slider.label"), row("slider.label"))
        XCTAssertEqual(MGRepairHint.text(for: "slider.grid"), row("slider.grid"))
        XCTAssertEqual(MGRepairHint.text(for: "slider.readouts"), row("slider.readouts"))
        XCTAssertTrue(MGRepairHint.text(for: "slider.b.max.func.detail")?.contains("lower max") ?? false)
        XCTAssertTrue(MGRepairHint.text(for: "slider.a.min.func.mark")?.contains("raise min") ?? false)
        XCTAssertTrue(MGRepairHint.text(for: "slider.step.count")?.contains("100 steps") ?? false)
        // The slider rows come before the generic rows that would also match these reasons.
        XCTAssertEqual(MGRepairHint.text(for: "slider.label.placeholder"), row("slider.label.placeholder"))
        XCTAssertNotEqual(MGRepairHint.text(for: "slider.label.placeholder"), row("*.placeholder"))
        XCTAssertEqual(MGRepairHint.text(for: "slider.a.min.func.at"), row("slider.*.min.*"))
        XCTAssertEqual(MGRepairHint.text(for: "slider.b.max.func.w"), row("slider.*.max.*"))
        XCTAssertEqual(MGRepairHint.text(for: "func.detail"), row("func.detail"), "a func's own reason keeps its own hint")
        XCTAssertNil(MGRepairHint.text(for: "sliders.unknown"))
        XCTAssertNil(MGRepairHint.text(for: "slider.a.mid.func.detail"))
    }

    /// Each hint states the bound the parser checks.
    func testRepairHintsStateTheSliderBounds() throws {
        let sliders = try XCTUnwrap(MGRepairHint.text(for: "sliders"))
        XCTAssertTrue(sliders.contains("1 to \(MGLimits.sliders) sliders"), sliders)
        XCTAssertTrue(MGRepairHint.text(for: "slider.step.count")?.contains("at most \(MGLimits.sliderSteps) steps") ?? false)
        XCTAssertTrue(MGRepairHint.text(for: "sliders.bindings")?.hasPrefix("at most \(MGLimits.sliderBindings) pairs") ?? false)
        let bound = Int(MGLimits.exprParameter)
        XCTAssertEqual(MGRepairHint.text(for: "slider.min"), "min is a number from -\(bound) to \(bound)")
        XCTAssertEqual(MGRepairHint.text(for: "slider.max"), "max is a number from -\(bound) to \(bound)")
        XCTAssertTrue(MGRepairHint.text(for: "slider.label")?.hasPrefix("label: 1-\(MGLimits.label) characters") ?? false)
        XCTAssertEqual(MGRepairHint.text(for: "slider.missing"),
                       "a slider needs all of param, min, max, step, default and label")
        XCTAssertEqual(MGParser.sliderKeys, ["param", "min", "max", "step", "default", "label"])
        // The example shape in the hint is itself an accepted slider (with a func that sets a to its default).
        let shape = String(sliders[sliders.firstIndex(of: "{")!...])
        let json = #"{"v":1,"items":["# + Self.line + #"],"sliders":["# + shape + "]}"
        XCTAssertNil(reason(json), json)
    }
}

#if canImport(AppKit)
/// Learner sliders on a real split board (`BoardRig`: `MartyGraphicsView(controller:)` in a window, on a manual clock,
/// with a probe; `SliderTests.splitBoard`). A slider change while the board is split: the next frame draws the items
/// the audio graph charts, the base is drawn once more against them and is the current frame, and no evaluation draws
/// one canvas for it. During a step, the slider change ends the step's transition window with the camera move (the
/// probe records each new deadline, `MGBoardProbe.windows`), and the board splits as soon as that move ends. Each chart
/// is checked against what a draw renders. At the defaults a split board reads the step items only from the
/// controller's cache (`MGTimelineCache`). With a slider moved, the board's evaluations read no cache at all, and after
/// its step is dropped from the cache its ticks, frame function and tap handler read nothing either and draw the
/// slider's graph (the readouts' eviction check, `BoardTransitionHostTests`, with the learner's items).
final class SliderBoardHostTests: XCTestCase {
    /// Room for the slider panel and the caption below the board, so the board's size never follows their text.
    static let window = CGSize(width: 560, height: 900)

    /// A split board past the draw-on of its first appearance: the base caches the floor and the graph.
    @MainActor func splitRig(file: StaticString = #filePath, line: UInt = #line) throws -> BoardRig {
        let rig = BoardRig(try MGParser.scene(data: Data(SliderTests.splitBoard.utf8)).get())
        rig.resize(Self.window)
        rig.settle(2.4)
        tick(rig, 1.2)
        rig.settle(0.6)
        XCTAssertEqual(rig.probe.decisions.last, MGBoardProbe.Decision(running: true, layered: true), "the board is split", file: file, line: line)
        XCTAssertEqual(try lastBaseDraw(rig).ids, ["floor", "g"], "the base caches the floor and the graph", file: file, line: line)
        XCTAssertNotNil(rig.probe.slide, "the board shows its sliders", file: file, line: line)
        return rig
    }

    @MainActor func testASliderChangeWhileSplitDrawsTheChartedItemsAndRedrawsTheBaseOnce() throws {
        let rig = try splitRig()
        defer { rig.close() }
        let scene = try XCTUnwrap(rig.controller.scene)
        var want = MGSliderState(scene: scene)
        XCTAssertTrue(want.set("a", nearest: 1.5))
        let moved = want.items.first { $0.id == "g" }
        let base = rig.probe.baseDraws, decided = rig.probe.decisions.count, drawn = rig.probe.draws.count
        let computed = rig.controller.timeline.computed
        try XCTUnwrap(rig.probe.slide)("a", 1.5)
        rig.settle(0.3)
        // Split right away: every evaluation since the change kept the split (no one-canvas frame for a slider change).
        let since = Array(rig.probe.decisions[decided...])
        XCTAssertFalse(since.isEmpty, "the slider change did not evaluate the board")
        XCTAssertEqual(Set(since.map(\.layered)), [true], "the slider change unsplit the board: \(since)")
        // The base is repartitioned once, against the new items, and is the current frame (no stale base).
        XCTAssertEqual(rig.probe.baseDraws, base + 1, "the slider change redraws the base exactly once")
        let last = try lastBaseDraw(rig)
        XCTAssertEqual(last.ids, ["floor", "g"])
        XCTAssertEqual(last.draw.input.items.first { $0.id == "g" }, moved, "the base has the moved graph")
        try assertBaseIsCurrent(rig, "after the slider change")
        // The next frame drawn is what the audio graph charts.
        let chart = try XCTUnwrap(rig.probe.charts.last ?? nil, "the board has no audio graph")
        XCTAssertEqual(chart, MGAudioGraph.chart(scene, items: want.items))
        XCTAssertNotEqual(chart, MGAudioGraph.chart(scene, step: 0), "the chart follows the slider")
        let next = try XCTUnwrap(rig.probe.draws[drawn...].first { if case .base = $0.layer { return false }; return true },
                                 "no frame was drawn after the change")
        XCTAssertEqual(MGAudioGraph.chart(scene, items: next.input.items), chart, "the next frame draws the charted graph")
        XCTAssertEqual(next.input.items.first { $0.id == "g" }, moved)
        // The graph is in the base, so the base draw renders it: the chart is the chart of what that draw renders.
        let rendered = last.draw.input.items.filter { last.ids.contains($0.id) }
        XCTAssertEqual(MGAudioGraph.chart(scene, items: rendered), chart, "the base draws the charted graph")
        // Ticks after the change redraw only the live layer; nothing computes the step's items again.
        let after = rig.probe.baseDraws
        tick(rig, 0.6)
        XCTAssertEqual(rig.probe.baseDraws, after, "a tick redrew the base")
        try assertBaseIsCurrent(rig, "ticks after the slider change")
        XCTAssertEqual(rig.controller.timeline.computed, computed, "the slider change computed the step's items again")
    }

    @MainActor func testASliderChangeDuringAStepSplitsAsSoonAsTheCameraMoveEnds() throws {
        let rig = try splitRig()
        defer { rig.close() }
        let scene = try XCTUnwrap(rig.controller.scene)
        // The board's Next button: the step narrows the graph's y range, zooms the camera and opens the step's transition
        // window until go + 1.6 s on the board's clock (`MGRenderPolicy.transientSeconds`; its task waits on the wall
        // clock). The probe records the window's deadline whenever it changes.
        let start = rig.now
        try XCTUnwrap(rig.probe.go)(1)
        let opened = try XCTUnwrap(rig.probe.windows.last, "the step opened no transition window")
        XCTAssertEqual(opened.timeIntervalSince(start), MGRenderPolicy.transientSeconds, accuracy: 1e-6, "the step's window ends at go + 1.6 s")
        rig.settle(0.1)
        XCTAssertEqual(rig.probe.decisions.last, MGBoardProbe.Decision(running: true, layered: false), "the step: one canvas")
        // The slider moves 0.8 s into the step on the board's clock, while the step's window, its blend and its camera
        // move all still run.
        tick(rig, 0.3)
        rig.advance(0.5)
        XCTAssertEqual(rig.now.timeIntervalSince(start), 0.8, accuracy: 1e-6)
        var want = MGSliderState(scene: scene, step: 1)
        XCTAssertTrue(want.set("a", nearest: 1.5))
        let moved = want.items.first { $0.id == "g" }
        let base = rig.probe.baseDraws, windowed = rig.probe.windows.count
        XCTAssertEqual(rig.probe.windows.last, opened, "the step's window had closed before the slider moved (its wait on the wall clock ran out)")
        try XCTUnwrap(rig.probe.slide)("a", 1.5)
        // The slider change ends the step's window with the camera move: its deadline moves from go + 1.6 s to
        // go + 1.0 s on the board's clock (`MGBoardTransition.windowEnd`).
        let changes = rig.probe.windows[windowed...].map { $0.timeIntervalSince(start) }
        XCTAssertEqual(changes.first ?? .infinity, MGBoardTransition.cameraWindow, accuracy: 1e-6,
                       "the slider change ends the step's window with the camera move (deadlines since go: \(changes))")
        rig.settle(0.1)
        // The camera still moves: one canvas, which draws the slider's graph already (the change settled the blend).
        XCTAssertEqual(rig.probe.decisions.last, MGBoardProbe.Decision(running: true, layered: false), "split while the camera moves")
        XCTAssertEqual(rig.probe.baseDraws, base, "a base was drawn while the camera moves")
        let size = try XCTUnwrap(rig.probe.draws.last?.size)
        XCTAssertEqual(try rig.frame(size).items.first { $0.id == "g" }, moved, "the canvas still blends toward replaced items")
        let chart = try XCTUnwrap(rig.probe.charts.last ?? nil, "the board has no audio graph")
        XCTAssertEqual(chart, MGAudioGraph.chart(scene, items: want.items))
        let one = try XCTUnwrap(rig.probe.draws.last)
        XCTAssertEqual(one.layer, .all, "one canvas")
        XCTAssertEqual(MGAudioGraph.chart(scene, items: one.input.items), chart, "the one canvas draws the charted graph")
        // At 1.1 s on the board's clock the camera move has ended (1.0 s), while the default spring blend (1.2 s) and the
        // step's window (1.6 s) would still run: the slider change ended the window with the camera move, and nothing
        // opened it again, so the board has split once, with the slider's graph and the step's camera in the base.
        rig.advance(0.3)
        rig.settle(0.3)
        XCTAssertEqual(rig.now.timeIntervalSince(start), 1.1, accuracy: 1e-6)
        let since = rig.probe.windows[windowed...].map { $0.timeIntervalSince(start) }
        XCTAssertTrue(since.allSatisfy { $0 <= MGBoardTransition.cameraWindow + 1e-6 },
                      "the window was opened past the camera move after the slider change: \(since)")
        XCTAssertEqual(rig.probe.decisions.last, MGBoardProbe.Decision(running: true, layered: true), "the board splits once the camera move ends")
        XCTAssertEqual(rig.probe.baseDraws, base + 1, "one base draw for the split")
        let last = try lastBaseDraw(rig)
        XCTAssertEqual(last.ids, ["floor", "g"])
        XCTAssertEqual(last.draw.input.items.first { $0.id == "g" }, moved, "the base has the slider's graph")
        XCTAssertEqual(MGAudioGraph.chart(scene, items: last.draw.input.items.filter { last.ids.contains($0.id) }), chart,
                       "the base draws the charted graph")
        try assertBaseIsCurrent(rig, "after the camera move")
        let s = last.draw.size
        assertViewport(last.draw.input.viewport, MGViewport(size: s, width: scene.width, height: scene.height, camera: scene.steps[1].camera).resized(to: s),
                       "the base has the step's camera")
    }

    @MainActor func testAtTheDefaultsASplitBoardNeverComputesTheStepItemsAgain() throws {
        let rig = try splitRig()
        defer { rig.close() }
        let scene = try XCTUnwrap(rig.controller.scene)
        let computed = rig.controller.timeline.computed
        XCTAssertGreaterThan(computed, 0)
        XCTAssertEqual(rig.probe.charts.last ?? nil, MGAudioGraph.chart(scene, step: 0), "at the defaults the board charts the step's items")
        // Ticks, then an evaluation of the whole board (new markers): the frames, the base, the audio graph, the VoiceOver
        // value and the slider panel all read the step's items from the controller's cache.
        tick(rig, 0.6)
        rig.markers = ["g": 1]
        rig.rebuild()
        rig.settle(0.6)
        tick(rig, 0.3)
        XCTAssertEqual(rig.probe.decisions.last, MGBoardProbe.Decision(running: true, layered: true))
        XCTAssertEqual(rig.controller.timeline.computed, computed, "at the defaults a tick or an evaluation computed the step's items again")
        // A move and a reset back to the defaults: the board reads the cached step items again, still in the cache.
        let slide = try XCTUnwrap(rig.probe.slide), reset = try XCTUnwrap(rig.probe.resetSliders)
        slide("a", 1.5)
        rig.settle(0.3)
        reset()
        rig.settle(0.3)
        tick(rig, 0.3)
        XCTAssertEqual(rig.probe.decisions.last, MGBoardProbe.Decision(running: true, layered: true))
        XCTAssertEqual(rig.probe.charts.last ?? nil, MGAudioGraph.chart(scene, step: 0), "after the reset the board charts the step's items")
        try assertBaseIsCurrent(rig, "after the reset")
        XCTAssertEqual(rig.controller.timeline.computed, computed, "a slider move or reset computed the step's items again")
    }

    @MainActor func testAMovedSliderBoardReadsNoCacheAfterItsStepIsDropped() throws {
        let rig = try splitRig()
        defer { rig.close() }
        let scene = try XCTUnwrap(rig.controller.scene)
        var want = MGSliderState(scene: scene)
        XCTAssertTrue(want.set("a", nearest: 1.5))
        let moved = want.items.first { $0.id == "g" }
        let slid = MGAudioGraph.chart(scene, items: want.items)
        try XCTUnwrap(rig.probe.slide)("a", 1.5)
        rig.settle(0.3)
        // With the slider moved, the board's evaluations (ticks, then one of the whole board for new markers) show the
        // learner's items and read nothing from the cache.
        let reads = rig.controller.timeline.reads, evaluations = rig.probe.decisions.count
        tick(rig, 0.3)
        rig.markers = ["g": 1]
        rig.rebuild()
        rig.settle(0.3)
        XCTAssertGreaterThan(rig.probe.decisions.count, evaluations, "the board was not evaluated")
        XCTAssertEqual(rig.controller.timeline.reads, reads, "an evaluation with the slider moved read the cache")
        XCTAssertEqual(rig.probe.charts.last ?? nil, slid, "the audio graph is the slider's")
        // Another revision read through the controller's cache drops the board's step (the cache holds one revision).
        var other = scene
        other.revision = scene.revision + 1_000
        _ = rig.controller.timeline.items(other, step: 0)
        XCTAssertEqual(rig.controller.timeline.kept, 1)
        let after = rig.controller.timeline.reads, computed = rig.controller.timeline.computed
        let base = rig.probe.baseDraws, live = rig.probe.liveDraws, charts = rig.probe.charts.count
        // Ticks, then the frame function and the tap handler of the last evaluation: they read nothing, and the frame is
        // the slider's graph.
        tick(rig, 0.6)
        XCTAssertGreaterThan(rig.probe.liveDraws, live + 3, "the live layer ticks")
        XCTAssertEqual(rig.probe.baseDraws, base, "a tick evaluated the board again")
        let size = try XCTUnwrap(rig.probe.draws.last?.size, "nothing was drawn")
        let f = try rig.frame(size)
        XCTAssertEqual(f.items.first { $0.id == "g" }, moved, "the frame function draws the slider's graph")
        let tap = try XCTUnwrap(rig.probe.tap, "the board has no tap handler")
        tap(f.viewport.point(MGPoint(3, 2)), size)
        // The board has not been evaluated since the tap, so it never saw a selection: clear it.
        rig.selection = nil
        XCTAssertEqual(rig.controller.timeline.reads, after, "a draw, the frame function or a tap read the cache")
        XCTAssertEqual(rig.controller.timeline.computed, computed)
        XCTAssertEqual(rig.probe.charts.count, charts, "the board built an audio graph during the ticks")
        try assertBaseIsCurrent(rig, "after the step was dropped")
        // Back at the defaults: each evaluation reads the step exactly once, and the dropped step is filled once.
        let start = (reads: rig.controller.timeline.reads, evaluations: rig.probe.decisions.count)
        try XCTUnwrap(rig.probe.resetSliders)()
        rig.settle(0.3)
        tick(rig, 0.3)
        let n = rig.probe.decisions.count - start.evaluations
        XCTAssertGreaterThan(n, 0, "the reset did not evaluate the board")
        XCTAssertEqual(rig.controller.timeline.reads - start.reads, n, "at the defaults, one read per evaluation")
        XCTAssertEqual(rig.controller.timeline.computed, computed + 1, "the dropped step is filled once")
        XCTAssertEqual(rig.probe.charts.last ?? nil, MGAudioGraph.chart(scene, step: 0), "the audio graph is the step's again")
        try assertBaseIsCurrent(rig, "after the reset")
    }

    // MARK: helpers (as in BoardTransitionHostTests)

    /// Ticks the board's own clock on by `seconds`, 0.1 s at a time, letting the frame loop draw between steps.
    @MainActor func tick(_ rig: BoardRig, _ seconds: Double) {
        for _ in 0..<Int((seconds * 10).rounded()) { rig.advance(0.1); rig.settle(0.05) }
    }

    /// The last base draw, with the items it cached.
    @MainActor func lastBaseDraw(_ rig: BoardRig) throws -> (draw: MGBoardProbe.Draw, ids: Set<String>) {
        let found = rig.probe.draws.reversed().lazy.compactMap { d -> (draw: MGBoardProbe.Draw, ids: Set<String>)? in
            if case .base(let ids) = d.layer { return (d, ids) }
            return nil
        }.first
        return try XCTUnwrap(found, "the board never drew a base")
    }

    /// The last base draw is the frame as it now is on the board's clock: every item it cached is drawn now as it was
    /// cached, and its viewport is the current one.
    @MainActor func assertBaseIsCurrent(_ rig: BoardRig, _ what: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let (draw, ids) = try lastBaseDraw(rig)
        let now = try rig.frame(draw.size)
        for id in ids.sorted() {
            XCTAssertEqual(draw.input.items.first { $0.id == id }, now.items.first { $0.id == id }, "\(what): the base cached \(id) as it is",
                           file: file, line: line)
        }
        assertViewport(draw.input.viewport, now.viewport, "\(what): the base viewport", file: file, line: line)
    }

    func assertViewport(_ v: MGViewport, _ want: MGViewport, _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(Double(v.scale), Double(want.scale), accuracy: 1e-9, "\(what): scale", file: file, line: line)
        XCTAssertEqual(v.center.x, want.center.x, accuracy: 1e-9, "\(what): centre x", file: file, line: line)
        XCTAssertEqual(v.center.y, want.center.y, accuracy: 1e-9, "\(what): centre y", file: file, line: line)
    }
}
#endif
