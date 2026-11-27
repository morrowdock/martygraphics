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

    /// At the defaults (before the first move and after a reset) the board and its chart take the step items from the
    /// controller's cache (`MGTimelineCache`), so frames never compute them again; an accepted non-default value gives
    /// the slider items.
    func testAtTheDefaultsTheBoardTakesTheCachedStepItems() throws {
        let s = try wave()
        var state = MGSliderState(scene: s)
        var cache = MGTimelineCache()
        let cachedChart = MGAudioGraph.chart(s, step: 0)
        for frame in 0..<5 {
            let items = MGSliderState.boardItems(s, step: 0, sliders: state, cache: cache)
            XCTAssertEqual(cache.computed, 1, "frame \(frame): computed once, through the cache")
            XCTAssertEqual(items, cache.items(s, step: 0))
            XCTAssertEqual(MGAudioGraph.chart(s, items: items), cachedChart)
        }
        // A moved slider: the live items, and the cache is not asked.
        XCTAssertTrue(state.set("a", stop: 6))   // a = 1.5
        let moved = MGSliderState.boardItems(s, step: 0, sliders: state, cache: cache)
        XCTAssertEqual(moved, state.items)
        XCTAssertNotEqual(MGAudioGraph.chart(s, items: moved), cachedChart)
        XCTAssertEqual(cache.computed, 1)
        // After a reset the board is back on the cache (a fresh one shows it is asked, once).
        state.reset()
        XCTAssertTrue(state.isAtDefaults)
        cache = MGTimelineCache()
        for _ in 0..<5 {
            XCTAssertEqual(MGAudioGraph.chart(s, items: MGSliderState.boardItems(s, step: 0, sliders: state, cache: cache)), cachedChart)
        }
        XCTAssertEqual(cache.computed, 1)
        // A slider state for another revision or step never stands in for the shown board.
        XCTAssertTrue(state.set("a", stop: 6))
        var other = s
        other.revision = s.revision + 1
        XCTAssertEqual(MGSliderState.boardItems(other, step: 0, sliders: state, cache: MGTimelineCache()), MGTimeline.items(other, step: 0))
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
        func live() -> [MGItem] { MGSliderState.boardItems(s, step: step, sliders: state, cache: cache) }
        func drawn(_ now: Date) -> [MGItem] { motion.frame(s, live: live(), style: .spring, now: now, time: 0, hiding: [], reduceMotion: false).items }
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
        XCTAssertEqual(chart(drawn(next)), chart(live()))
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

    // MARK: repair hints

    func testRepairHintsFollowTheReasonPatterns() {
        func row(_ pattern: String) -> String? { MGRepairHint.table.first { $0.0 == pattern }?.1 }
        XCTAssertEqual(MGRepairHint.text(for: "slider.default.wave"), row("slider.default.*"))
        XCTAssertEqual(MGRepairHint.text(for: "slider.default"), row("slider.default"))
        XCTAssertEqual(MGRepairHint.text(for: "slider.label"), row("slider.label"))
        XCTAssertEqual(MGRepairHint.text(for: "slider.grid"), row("slider.grid"))
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
