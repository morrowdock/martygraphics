// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import MartyGraphics

/// Work bounds of the 2D engine: graph checks per scene (`items.expr` counts graph edits, and a graph with readouts
/// weighs more), the timeline items cache, readouts on the frame path and the stream preview. Ordinary scenes at and
/// just over each limit.
final class EngineBoundsTests: XCTestCase {
    static func json(_ s: String) -> MGJSON { MGJSON(any: try! JSONSerialization.jsonObject(with: Data(s.utf8)))! }

    /// One `func` item `g`, a text item `t`, and one step per edit of `g` (and of `t`) after a first step without edits.
    static func scene(graphEdits: Int, textEdits: Int = 0) -> String {
        let items = #"{"id":"g","k":"func","at":[1,1],"w":6,"h":4,"xr":[-3,3],"yr":[-2,2],"y":"a*x/10","a":1},"#
            + #"{"id":"t","k":"text","at":[8,6],"text":"Slope"}"#
        let edits = (0..<graphEdits).map { #"{"id":"g","key":"a","value":\#($0 + 2)}"# }
            + (0..<textEdits).map { #"{"id":"t","key":"text","value":"Slope \#($0 + 2)"}"# }
        let steps = [#"{"say":"Start."}"#] + edits.enumerated().map { #"{"say":"Step \#($0.offset + 1).","do":[\#($0.element)]}"# }
        return #"{"v":1,"items":["# + items + #"],"steps":["# + steps.joined(separator: ",") + "]}"
    }

    static func reason(_ s: String) -> String? {
        if case .failure(let e) = MGParser.scene(data: Data(s.utf8)) { return e.reason }
        return nil
    }

    // MARK: graph checks per scene

    func testStepEditsOfAGraphCountAgainstTheGraphBudget() throws {
        // One graph and five edits of it: six checks, the limit.
        let atLimit = try MGParser.scene(data: Data(Self.scene(graphEdits: MGLimits.exprItems - 1).utf8)).get()
        let last = atLimit.steps.count - 1
        XCTAssertEqual(MGTimeline.items(atLimit, step: last).first { $0.id == "g" }?.num["a"], Double(MGLimits.exprItems))
        // One more edit of the graph is over it.
        XCTAssertEqual(Self.reason(Self.scene(graphEdits: MGLimits.exprItems)), "items.expr")
        // Edits of other items do not count.
        XCTAssertNoThrow(try MGParser.scene(data: Data(Self.scene(graphEdits: MGLimits.exprItems - 1, textEdits: 2).utf8)).get())
    }

    func testGraphEditsCountsStepAndOverEditsThatNameAGraph() {
        let o = Self.json(#"{"v":1,"items":[{"id":"w","k":"field"},{"id":"b","k":"body"}],"#
            + #""over":[{"id":"tg","key":"a","value":2},{"id":"w","key":"a","value":2},{"id":"tb","key":"label","value":"B"}],"#
            + #""steps":[{"say":"A.","do":[{"id":"w","key":"a","value":3},{"id":"tg","key":"a","value":3},{"id":"b","key":"at","value":[1,1]}]}]}"#)
            .objectValue!
        // `over` counts only template graphs (it may name only template items); steps count every graph.
        XCTAssertEqual(MGParser.graphEdits(o, templateGraphs: ["tg"], templateSteps: []), 3)
        XCTAssertEqual(MGParser.graphEdits(o, templateGraphs: [], templateSteps: []), 1)
        // Without wire steps, the template's own step edits count.
        var withoutSteps = o; withoutSteps["steps"] = nil
        var step = MGStep(say: "A."); step.edits = [MGEdit(id: "tg", key: "a", value: .number(4)), MGEdit(id: "x", key: "a", value: .number(4))]
        XCTAssertEqual(MGParser.graphEdits(withoutSteps, templateGraphs: ["tg"], templateSteps: [step]), 2)
    }

    // MARK: timeline items cache

    func testTimelineCacheComputesTheItemsOncePerRevisionAndStep() throws {
        var scene = try MGParser.scene(data: Data(Self.scene(graphEdits: 3).utf8)).get()
        let cache = MGTimelineCache()
        for _ in 0..<20 { XCTAssertEqual(cache.items(scene, step: 3), MGTimeline.items(scene, step: 3)) }
        XCTAssertEqual(cache.computed, 1)
        XCTAssertEqual(cache.items(scene, step: 1), MGTimeline.items(scene, step: 1))
        XCTAssertEqual(cache.computed, 2)
        scene.revision += 1
        XCTAssertEqual(cache.items(scene, step: 1), MGTimeline.items(scene, step: 1))
        XCTAssertEqual(cache.computed, 3, "another revision is another scene")
        XCTAssertEqual(MGDescribe.board(stepItems: cache.items(scene, step: 1), hiding: []), MGDescribe.board(scene, step: 1))
    }

    func testTimelineCacheKeepsTheLastFewStepsOfTheNewestRevision() throws {
        var scene = try MGParser.scene(data: Data(Self.scene(graphEdits: 5).utf8)).get()
        let cache = MGTimelineCache(), n = MGTimelineCache.capacity
        XCTAssertEqual(n, 4)
        for step in 0..<n { XCTAssertEqual(cache.items(scene, step: step), MGTimeline.items(scene, step: step)) }
        XCTAssertEqual(cache.computed, n)
        // Step 0 read again becomes the most recent, so the next new step evicts step 1, the least recently used.
        XCTAssertEqual(cache.items(scene, step: 0), MGTimeline.items(scene, step: 0))
        XCTAssertEqual(cache.items(scene, step: n), MGTimeline.items(scene, step: n))
        XCTAssertEqual(cache.computed, n + 1)
        XCTAssertEqual(cache.kept, n, "the cache never holds more than its bound")
        for step in [0, 2, 3, n] { XCTAssertEqual(cache.items(scene, step: step), MGTimeline.items(scene, step: step)) }
        XCTAssertEqual(cache.computed, n + 1, "the kept steps are served without computing")
        XCTAssertEqual(cache.items(scene, step: 1), MGTimeline.items(scene, step: 1))
        XCTAssertEqual(cache.computed, n + 2, "the least recently used step was evicted")
        // A new revision drops every entry of the old one.
        scene.revision += 1
        XCTAssertEqual(cache.items(scene, step: 2), MGTimeline.items(scene, step: 2))
        XCTAssertEqual(cache.computed, n + 3)
        XCTAssertEqual(cache.kept, 1, "the old revision's steps were dropped")
    }

    // MARK: stream preview

    func testStreamPreviewIsNotParsedAgainWhileNothingNewCompletes() throws {
        let json = #"{"v":1,"items":[{"id":"b","k":"body","at":[3,4]}],"steps":[{"say":"One."},{"say":"Two."}]}"#
        var parser = MGStreamParser()
        XCTAssertEqual(parser.feed(String(json.dropLast()))?.steps.count, 2, "steps join once complete")
        let count = parser.previewValidationCount
        for _ in 0..<64 { XCTAssertNil(parser.feed(" ")) }
        XCTAssertNil(parser.feed("}"))
        XCTAssertEqual(parser.previewValidationCount, count)
        XCTAssertEqual(try parser.finish().get(), try MGParser.scene(data: Data(json.utf8)).get())
    }

    func testStreamStepsTrialRunsAgainOnlyWhenItsRootChanges() throws {
        var parser = MGStreamParser()
        let head = #"{"v":1,"steps":[{"say":"One.","show":["c"]}],"items":[{"id":"b","k":"body","at":[3,4]},"#
        let first = try XCTUnwrap(parser.feed(head))
        XCTAssertEqual(first.steps, [], "the steps name an item that has not arrived")
        let count = parser.previewValidationCount
        for _ in 0..<64 { XCTAssertNil(parser.feed(" ")) }
        XCTAssertEqual(parser.previewValidationCount, count)
        let second = try XCTUnwrap(parser.feed(#"{"id":"c","k":"body","at":[6,4]}]}"#))
        XCTAssertEqual(second.steps.count, 1)
        XCTAssertEqual(Set(second.items.map(\.id)), ["b", "c"])
    }

    // MARK: readouts

    /// A `func` item `g` with every readout, `plain` more graphs without readouts, a text naming `g`'s slope, one step
    /// per edit after a first step without edits, then `quiet` more steps without edits.
    static func readoutScene(edits: [String] = [], plain: Int = 0, quiet: Int = 0) -> String {
        let g = #"{"id":"g","k":"func","at":[1,1],"w":6,"h":4,"xr":[-3,3],"yr":[-2,2],"y":"sin(x)","mark":1,"shade":[0,1.5],"#
            + #""readouts":["value","slope","area"]}"#
        let others = (0..<plain).map { #",{"id":"p\#($0)","k":"func","at":[1,1],"w":6,"h":4,"xr":[-3,3],"yr":[-2,2],"y":"x/\#($0 + 2)"}"# }
        let text = #",{"id":"t","k":"text","at":[8,6],"text":"Slope {g.slope}"}"#
        let steps = [#"{"say":"Start."}"#] + edits.enumerated().map { #"{"say":"Step \#($0.offset + 1).","do":[\#($0.element)]}"# }
            + (0..<quiet).map { #"{"say":"Quiet \#($0 + 1)."}"# }
        return #"{"v":1,"items":["# + g + others.joined() + text + #"],"steps":["# + steps.joined(separator: ",") + "]}"
    }

    static let colour = #"{"id":"g","key":"color","value":"red"}"#
    /// An edit of a readout input (`MGReadout.inputKeys`) that leaves every readout as it was.
    static let range = #"{"id":"g","key":"yr","value":[-3,3]}"#

    func testAGraphWithReadoutsAndEachEditThatCanChangeThemWeighTwoGraphChecks() throws {
        XCTAssertEqual(MGLimits.readoutWeight, 2)
        // The graph and two edits of a readout input, 2 each: six checks, the limit. One more edit is over it.
        XCTAssertNoThrow(try MGParser.scene(data: Data(Self.readoutScene(edits: [Self.range, Self.range]).utf8)).get())
        XCTAssertEqual(Self.reason(Self.readoutScene(edits: [Self.range, Self.range, Self.colour])), "items.expr")
        // A colour edit keeps the readouts and weighs 1: the graph and four of them are six, five are over.
        XCTAssertNoThrow(try MGParser.scene(data: Data(Self.readoutScene(edits: Array(repeating: Self.colour, count: 4)).utf8)).get())
        XCTAssertEqual(Self.reason(Self.readoutScene(edits: Array(repeating: Self.colour, count: 5))), "items.expr")
        // The graph (2) and four plain graphs (1 each) are six; five plain graphs are over.
        XCTAssertNoThrow(try MGParser.scene(data: Data(Self.readoutScene(plain: 4).utf8)).get())
        XCTAssertEqual(Self.reason(Self.readoutScene(plain: 5)), "items.expr")
        // Without readouts the same scenes fit (1 + 3 edits; 1 + 5 graphs).
        let bare = { (s: String) in s.replacingOccurrences(of: #","readouts":["value","slope","area"]"#, with: "")
            .replacingOccurrences(of: "Slope {g.slope}", with: "Slope") }
        XCTAssertNoThrow(try MGParser.scene(data: Data(bare(Self.readoutScene(edits: [Self.range, Self.range, Self.colour])).utf8)).get())
        XCTAssertNoThrow(try MGParser.scene(data: Data(bare(Self.readoutScene(plain: 5)).utf8)).get())
        // Every key a `func` allows: the ones the readouts read weigh 2, the others 1, and a graph without readouts 1.
        for key in MGParser.allowedKeys(.function) {
            XCTAssertEqual(MGParser.editWeight("g", key: key, readouts: ["g"]), MGReadout.inputKeys.contains(key) ? 2 : 1, key)
            XCTAssertEqual(MGParser.editWeight("g", key: key, readouts: []), 1, key)
        }
        XCTAssertEqual(MGParser.editWeight("g", key: nil, readouts: ["g"]), 2, "a key that is not a string counts as an input")
        // The refusal comes with a repair hint that states the weight.
        let hint = try XCTUnwrap(MGRepairHint.text(for: "items.expr"))
        XCTAssertTrue(hint.contains("a func with readouts counts 2"), hint)
    }

    func testReadoutGraphsAndExprWeightReadTheRawScene() {
        let o = Self.json(#"{"v":1,"items":[{"id":"g","k":"func","readouts":["value"]},{"id":"p","k":"func"},"#
            + #"{"id":"q","k":"func"},{"id":"w","k":"field"},{"id":"b","k":"body"}],"#
            + #""steps":[{"say":"A.","do":[{"id":"p","key":"readouts","value":["area"]},{"id":"w","key":"readouts","value":["area"]},"#
            + #"{"id":"q","key":"color","value":"red"},{"id":"g","key":"label","value":"G"}]}]}"#).objectValue!
        // `g` lists readouts and an edit gives `p` them; a field never has readouts.
        let ids = MGParser.readoutGraphs(o, templateItems: [], templateSteps: [])
        XCTAssertEqual(ids, ["g", "p"])
        guard case .array(let items)? = o["items"] else { return XCTFail("items") }
        XCTAssertEqual(items.map { MGParser.exprWeight($0, readouts: ids) }, [2, 2, 1, 1, 0])
        // An edit weighs 2 when its graph computes readouts and its key can change one: p's readouts 2, w 1, q 1 and
        // g's label 1 (a label keeps the readouts).
        XCTAssertEqual(MGParser.graphEdits(o, templateGraphs: [], templateSteps: []) { MGParser.editWeight($0, key: $1, readouts: ids) }, 5)
        XCTAssertEqual(MGParser.graphEdits(o, templateGraphs: [], templateSteps: []), 4)
        // A template `func` item that requests readouts, and one a template step edit gives them.
        var withReadouts = MGItem(id: "tg", kind: .function, color: .accent); withReadouts.flags.insert(MGReadout.area.key)
        var step = MGStep(say: "A."); step.edits = [MGEdit(id: "tf", key: "readouts", value: .array([.string("value")]))]
        XCTAssertEqual(MGParser.readoutGraphs([:], templateItems: [withReadouts, MGItem(id: "tf", kind: .function, color: .accent)], templateSteps: [step]),
                       ["tg", "tf"])
        // `over` names template items only, as `graphEdits` counts it.
        let over = Self.json(#"{"over":[{"id":"tf","key":"readouts","value":["value"]},{"id":"g","key":"readouts","value":["value"]}],"#
            + #""items":[{"id":"g","k":"func"}]}"#).objectValue!
        XCTAssertEqual(MGParser.readoutGraphs(over, templateItems: [MGItem(id: "tf", kind: .function, color: .accent)], templateSteps: []),
                       ["tf"])
    }

    /// The view draws every frame from `MGSceneController.timelineItems`: the step's items, and so its readouts, are
    /// computed once per cache fill. A revisit of one of the last 4 steps read of the same revision hits the cache; a
    /// step pushed out by 4 newer steps is computed again. Never per frame.
    @MainActor
    func testTheFramePathComputesReadoutsOncePerCacheFill() throws {
        let probe = MGReadout.Probe()
        try MGReadout.$probe.withValue(probe) {
            // Steps 0 (no edit), 1 (the yr edit) and 2–5 (no edit of their own): every fill of steps 1–5 applies the yr
            // edit, so it computes the readouts once; a fill of step 0 computes none.
            let parsed = try MGParser.scene(data: Data(Self.readoutScene(edits: [Self.range], quiet: 4).utf8)).get()
            XCTAssertEqual(probe.count, 2, "the graph, then the yr edit (a readout input) when the steps are checked")
            let controller = MGSceneController(scene: parsed)
            let scene = try XCTUnwrap(controller.scene)
            var slopes = Set<Double>()
            for frame in 0..<120 {
                let items = MGTimeline.frame(scene, items: controller.timelineItems(scene, step: 1), time: Double(frame) / 60)
                slopes.insert(try XCTUnwrap(items.first { $0.id == "g" }?.num[MGReadout.slope.key]))
            }
            XCTAssertEqual(slopes, [cos(1)])
            XCTAssertEqual(controller.timeline.computed, 1)
            XCTAssertEqual(probe.count, 3, "one cache fill applies the yr edit; 120 frames compute nothing")
            for frame in 0..<60 { _ = MGTimeline.frame(scene, items: controller.timelineItems(scene, step: 0), time: Double(frame) / 60) }
            XCTAssertEqual(controller.timeline.computed, 2)
            XCTAssertEqual(probe.count, 3, "step 0 applies no edit")
            // 1 -> 0 -> 1: the revisit of step 1 hits the cache.
            _ = controller.timelineItems(scene, step: 1)
            XCTAssertEqual(controller.timeline.computed, 2)
            XCTAssertEqual(probe.count, 3, "the revisit of step 1 computes nothing")
            // Kept, least recently used first: 0, 1. Steps 2–5 are 4 new fills, one readout computation each, and
            // push out 0 and 1: kept 2, 3, 4, 5.
            for step in 2...5 { _ = controller.timelineItems(scene, step: step) }
            XCTAssertEqual(controller.timeline.computed, 6)
            XCTAssertEqual(controller.timeline.kept, MGTimelineCache.capacity)
            XCTAssertEqual(probe.count, 7, "4 fills, 1 readout computation each")
            // Step 1 was pushed out: it is computed again, and pushes out step 2 (kept 3, 4, 5, 1).
            _ = controller.timelineItems(scene, step: 1)
            XCTAssertEqual(controller.timeline.computed, 7)
            XCTAssertEqual(probe.count, 8, "an evicted step computes its readouts again")
            // Step 5 is still kept; step 2 is not.
            _ = controller.timelineItems(scene, step: 5)
            XCTAssertEqual(controller.timeline.computed, 7)
            XCTAssertEqual(probe.count, 8, "a kept step computes nothing")
            _ = controller.timelineItems(scene, step: 2)
            XCTAssertEqual(controller.timeline.computed, 8)
            // Every fill of steps 1–5 (7 of the 8 fills) computed the readouts once, plus the parse's 2.
            XCTAssertEqual(probe.count, 2 + 7)
            XCTAssertEqual(try XCTUnwrap(controller.timelineItems(scene, step: 2).first { $0.id == "g" }?.num[MGReadout.slope.key]),
                           cos(1))
        }
    }

    func testAColourEditKeepsTheReadoutsWithoutComputingThem() throws {
        let probe = MGReadout.Probe()
        try MGReadout.$probe.withValue(probe) {
            let scene = try MGParser.scene(data: Data(Self.readoutScene(edits: [Self.colour]).utf8)).get()
            XCTAssertEqual(probe.count, 1, "the graph's own check; the colour edit computes no readout")
            let cache = MGTimelineCache()
            for _ in 0..<60 { _ = cache.items(scene, step: 1) }
            XCTAssertEqual(cache.computed, 1)
            XCTAssertEqual(probe.count, 1, "nor does the cache fill that applies it")
            // The kept readouts are exactly what a full check of the edited item gives.
            let edited = try XCTUnwrap(cache.items(scene, step: 1).first { $0.id == "g" })
            XCTAssertEqual(edited.color, .red)
            var wire = try XCTUnwrap(scene.item("g")).wire()
            wire["color"] = .string("red")
            let ctx = MGContext(width: scene.width, height: scene.height, is3D: scene.is3D, values: scene.values)
            XCTAssertEqual(edited, try MGParser.item(.object(wire), ctx))
            XCTAssertEqual(probe.count, 2, "the full check computes them")
            // Every key outside `MGReadout.inputKeys` keeps them; every input key computes them again.
            let original = try XCTUnwrap(scene.item("g"))
            for key in MGParser.allowedKeys(.function) {
                XCTAssertEqual(MGReadout.kept(original, editing: key) == nil, MGReadout.inputKeys.contains(key), key)
            }
            XCTAssertEqual(MGReadout.inputKeys.subtracting(MGParser.allowedKeys(.function)), [])
        }
    }

    func testAWholePowerAboveTheSquaringLimitTakesTheLibraryBound() {
        let n = 0x1p60
        XCTAssertGreaterThan(n, MGExpression.squaringLimit)
        // 0 and 1 stay exact; an overflow is not finite, as for repeated squaring.
        XCTAssertEqual(MGExpression.wholePower(0, n, up: true), 0)
        XCTAssertEqual(MGExpression.wholePower(1, n, up: false), 1)
        XCTAssertEqual(MGExpression.wholePower(1.5, n, up: true), .infinity)
        // A bound on each side of pow, at most `libraryUlps` doubles from it, never below 0.
        for u in [0.5, 1 - 0x1p-52, 1 + 0x1p-52] {
            let p = pow(u, n), lo = MGExpression.wholePower(u, n, up: false), hi = MGExpression.wholePower(u, n, up: true)
            XCTAssertLessThanOrEqual(lo, p); XCTAssertGreaterThanOrEqual(hi, p); XCTAssertGreaterThanOrEqual(lo, 0)
            XCTAssertEqual(hi, MGExpression.widened(p, up: true))
        }
        // Up to the limit, repeated squaring as before: exact bounds stay exact.
        XCTAssertEqual(MGExpression.wholePower(2, 1000, up: false), 0x1p1000)
        XCTAssertEqual(MGExpression.wholePower(2, 1000, up: true), 0x1p1000)
        XCTAssertEqual(MGExpression.wholePower(0.5, 3, up: false), 0.125)
        XCTAssertEqual(MGExpression.wholePower(0.5, 3, up: true), 0.125)
        // An enclosure of x^(2^60) over [0.3, 0.31] holds 0 and is finite.
        let e = try? MGExpression.compile("x^(2^60)", allowed: [.x], reason: "func.y")
        let bounds = e?.enclosure(MGExpression.Inputs(), 0.3, 0.31)
        XCTAssertEqual(bounds?.lo, 0)
        XCTAssertEqual(bounds.map { $0.hi.isFinite && $0.hi >= 0 }, true)
    }

    /// Independent of `pow`: for large even exponents, on both sides of the squaring limit, an enclosure of x^n holds
    /// the powers that are exact doubles: 0ⁿ = 0, 1ⁿ = 1 and (−1)ⁿ = 1, alone and inside wider ranges.
    func testWholePowerEnclosuresHoldTheExactPowersOfLargeEvenExponents() throws {
        // 2⁵² + 2 squares; the others take the library bound. Each exponent is an exact double, even, and its own
        // enclosure is that one double.
        let exponents: [(text: String, n: Double)] = [
            ("(2^52+2)", 0x1p52 + 2), ("2^54", 0x1p54), ("2^60", 0x1p60),
            ("(2^60+2^8)", 0x1p60 + 256), ("10^17", 1e17),
        ]
        for (text, n) in exponents {
            XCTAssertEqual(n.truncatingRemainder(dividingBy: 2), 0, text)
            let exponent = try MGExpression.compile(text, allowed: [], reason: "func.y")
            XCTAssertEqual(exponent.enclosure(MGExpression.Inputs(), 0, 0)?.lo, n, text)
            XCTAssertEqual(exponent.enclosure(MGExpression.Inputs(), 0, 0)?.hi, n, text)
            let e = try MGExpression.compile("x^" + text, allowed: [.x], reason: "func.y")
            // (range of x, exact powers it must hold)
            let cases: [(Double, Double, [Double])] = [
                (0, 0, [0]), (1, 1, [1]), (-1, -1, [1]), (-1, 1, [0, 1]), (-1, 0, [0, 1]), (0, 1, [0, 1]),
                (-0.5, 0.5, [0]), (0.5, 1, [1]), (-1, -0.5, [1]),
            ]
            for (a, b, exact) in cases {
                let bounds = try XCTUnwrap(e.enclosure(MGExpression.Inputs(), a, b), "\(text) over [\(a), \(b)]")
                for v in exact {
                    XCTAssertLessThanOrEqual(bounds.lo, v, "\(text) over [\(a), \(b)]")
                    XCTAssertGreaterThanOrEqual(bounds.hi, v, "\(text) over [\(a), \(b)]")
                }
                XCTAssertGreaterThanOrEqual(bounds.lo, 0, "an even power is never negative")
            }
            // A base above 1 overflows: no enclosure, so the graph is refused rather than drawn from a wrong bound.
            XCTAssertNil(e.enclosure(MGExpression.Inputs(), 1, 2), text)
        }
    }
}

/// The lesson `animate` caps (per beat, per stream, per `apply` batch, in snapshots) and waiting beats without keyframes.
final class LessonAnimateBoundsTests: LessonTestCase {
    typealias F = LessonFixture
    static let scene0 = #"{"scene":{"v":1,"template":"rotate2d","params":{"pts":[[2,1],[4,1],[2,3]],"angle":0}}}"#
    static func animate(_ to: Int) -> String { #"{"op":"animate","param":"angle","to":\#(to),"dur":1}"# }

    func feed(_ s: inout MGLessonSession, _ lines: [String]) -> [MGLessonEvent] { lines.flatMap { s.feed($0 + "\n") } }
    func with(_ o: MGJSON, _ key: String, _ value: MGJSON?) -> MGJSON {
        guard case .object(var d) = o else { return o }
        d[key] = value
        return .object(d)
    }

    func testAnimatesPerBeatAtAndOverTheCap() {
        var s = F.session()
        let events = feed(&s, [Self.scene0, #"{"say":"Turn."}"#, Self.animate(5), Self.animate(10), Self.animate(15), #"{"end":true}"#])
        let refused = F.refusals(events)
        XCTAssertEqual(refused.map(\.reason), ["lesson.animate.count"])
        XCTAssertEqual(refused.first?.beat, 0)
        XCTAssertEqual(refused.first?.command, MGLessonLimits.animatesPerBeat)
        XCTAssertEqual(s.state?.value("theta"), 10, "the refused command changed nothing")
    }

    func testAnimatesPerStreamAtAndOverTheCap() {
        var s = F.session()
        var lines = [Self.scene0, Self.animate(5)]   // a set-up animate counts too
        var angle = 5
        for beat in 0..<12 {
            lines.append(#"{"say":"Beat \#(beat + 1)."}"#)
            for _ in 0..<MGLessonLimits.animatesPerBeat { angle += 5; lines.append(Self.animate(angle)) }
        }
        let refused = F.refusals(feed(&s, lines + [#"{"end":true}"#]))
        XCTAssertEqual(refused.map(\.reason), ["lesson.animate.count"], "the 25th animate of the stream")
        XCTAssertEqual(refused.first?.beat, 11)
        XCTAssertEqual(s.state?.value("theta"), Double(angle - 5))
        // A new stream has its own budget.
        let next = F.refusals(feed(&s, [#"{"keep":true}"#, #"{"say":"Again."}"#, Self.animate(0), #"{"end":true}"#]))
        XCTAssertEqual(next, [])
        XCTAssertEqual(s.state?.value("theta"), 0)
    }

    func testApplyBatchHoldsAtMostOneBeatOfAnimates() {
        var s = F.session()
        _ = feed(&s, [Self.scene0, #"{"end":true}"#])
        let over = s.apply([Self.animate(5), Self.animate(10), Self.animate(15)].map(F.json))
        XCTAssertEqual(over.failureReason, "lesson.animate.count")
        if case .failure(let issue) = over { XCTAssertEqual(issue.command, 2) }
        XCTAssertEqual(s.state?.value("theta"), 0)
        XCTAssertNoThrow(try s.apply([Self.animate(5), Self.animate(10)].map(F.json)).get())
        XCTAssertEqual(s.state?.value("theta"), 10)
    }

    func testWaitingBeatKeepsNoKeyframesAndBuildsThemWhenPresented() throws {
        let lines = [Self.scene0, #"{"say":"One."}"#, #"{"op":"params","params":{"angle":45}}"#, #"{"say":"Two."}"#,
                     Self.animate(135), #"{"end":true}"#]
        var waiting = F.session(.speech)
        _ = feed(&waiting, lines)
        XCTAssertEqual(waiting.waitingBeats, 1)
        for t in waiting.pending.flatMap(\.transitions) {
            if case .keyframes = t { XCTFail("a waiting beat holds no keyframe scenes") }
        }
        waiting.lineEnded(0)
        guard case .keyframes(let built)? = waiting.lastChange?.transition else { return XCTFail("the animate plays keyframes") }
        // The same keyframes as a session that presents the beat at once (the engine is deterministic).
        var direct = F.session()
        _ = feed(&direct, lines)
        guard case .keyframes(let expected)? = direct.lastChange?.transition else { return XCTFail("the animate plays keyframes") }
        XCTAssertEqual(built, expected)
        XCTAssertEqual(built.first?.frames.count, 1 + 90 / 5, "the start scene and one keyframe per 5°")
        XCTAssertEqual(waiting.state?.value("theta"), 135)
        XCTAssertEqual(waiting.state, direct.state)
    }

    func testSnapshotKeepsTheStreamAnimateCount() throws {
        var s = F.session(.speech)
        _ = feed(&s, [Self.scene0, #"{"say":"One."}"#, Self.animate(5), Self.animate(10), #"{"say":"Two."}"#, Self.animate(15)])
        let snap = s.snapshot()
        XCTAssertEqual(snap["stream"]?["animates"], .number(3))
        let restored = try MGLessonSession.restore(snap, pacing: .speech, clock: MGManualClock()).get()
        XCTAssertEqual(restored.stream.animates, 3)
        XCTAssertEqual(restored.snapshot(), snap)
        // A snapshot without an animate is unchanged (no `animates` key).
        var plain = F.session(.speech)
        _ = feed(&plain, [Self.scene0, #"{"say":"One."}"#])
        XCTAssertNil(plain.snapshot()["stream"]?["animates"])

        let stream = try XCTUnwrap(snap["stream"])
        let over = with(snap, "stream", with(stream, "animates", .number(Double(MGLessonLimits.animatesPerStream + 1))))
        XCTAssertEqual(MGLessonSession.restore(over, pacing: .speech, clock: MGManualClock()).failureReason, "snapshot.stream")
        guard case .array(var pending)? = snap["pending"], case .array(let commands)? = pending[0]["commands"] else { return XCTFail("no waiting beat") }
        pending[0] = with(pending[0], "commands", .array(Array(repeating: commands[0], count: MGLessonLimits.animatesPerBeat + 1)))
        XCTAssertEqual(MGLessonSession.restore(with(snap, "pending", .array(pending)), pacing: .speech, clock: MGManualClock()).failureReason,
                       "snapshot.pending")
    }

    func testRefusedAnimateKeepsItsPlaceInTheStreamCount() {
        // The beat's check holds theta at 0, so each `animate` builds its keyframes and is then refused by the check.
        var s = F.session()
        var lines = [Self.scene0, #"{"say":"Hold."}"#, #"{"check":{"value":"theta","eq":0}}"#]
        lines += (1...MGLessonLimits.animatesPerStream).map { Self.animate(5 * $0) }
        lines.append(Self.animate(5))
        let refused = F.refusals(feed(&s, lines))
        XCTAssertEqual(refused.count, MGLessonLimits.animatesPerStream + 1)
        XCTAssertEqual(Set(refused.prefix(MGLessonLimits.animatesPerStream).map(\.reason)), ["check.theta"])
        XCTAssertEqual(refused.last?.reason, "lesson.animate.count", "the 25th is refused before it runs")
        XCTAssertEqual(s.stream.animates, MGLessonLimits.animatesPerStream)
        XCTAssertEqual(s.projected?.value("theta"), 0)
    }

    func testKeepStreamCountsTheAnimatesStillWaiting() {
        var s = F.session(.speech)
        _ = feed(&s, [Self.scene0, #"{"say":"Intro."}"#, #"{"say":"One."}"#, Self.animate(5), Self.animate(10), #"{"end":true}"#])
        XCTAssertEqual(s.waitingBeats, 1, "the intro's line is open, so beat 1 waits")
        _ = feed(&s, [#"{"keep":true}"#])
        XCTAssertEqual(s.stream.animates, 2, "the waiting beat's animates count toward the new stream")
        var lines: [String] = []
        var angle = 10
        for beat in 0..<11 {
            lines.append(#"{"say":"More \#(beat + 1)."}"#)
            for _ in 0..<MGLessonLimits.animatesPerBeat { angle += 5; lines.append(Self.animate(angle)) }
        }
        lines += [#"{"say":"Last."}"#, Self.animate(angle + 5)]
        let refused = F.refusals(feed(&s, lines))
        XCTAssertEqual(refused.map(\.reason), ["lesson.animate.count"], "24 wait; the 25th is refused")
        XCTAssertEqual(s.queuedAnimates, MGLessonLimits.animatesPerStream)
    }

    /// A `.speech` session whose waiting beats hold `pairs` beats of 2 `animate` commands and a last beat with one
    /// `params` command (the intro's line stays open, so nothing after it is shown). `end`: the stream ends (the last
    /// beat closes).
    func waitingQueue(pairs: Int, end: Bool = true) -> MGLessonSession {
        var s = F.session(.speech)
        var lines = [Self.scene0, #"{"say":"Intro."}"#]
        var angle = 0
        for beat in 0..<pairs {
            lines.append(#"{"say":"Beat \#(beat + 1)."}"#)
            for _ in 0..<MGLessonLimits.animatesPerBeat { angle += 5; lines.append(Self.animate(angle)) }
        }
        lines += [#"{"say":"Last."}"#, #"{"op":"params","params":{"angle":\#(angle + 5)}}"#] + (end ? [#"{"end":true}"#] : [])
        XCTAssertEqual(F.refusals(feed(&s, lines)), [])
        XCTAssertEqual(s.waitingBeats, pairs + 1)
        return s
    }

    /// `snap` with the last waiting beat's `params` command made an `animate` to the same angle.
    func lastCommandAnimates(_ snap: MGJSON) -> MGJSON {
        guard case .array(var pending)? = snap["pending"], case .array(var commands)? = pending.last?["commands"],
              case .number(let to)? = commands.first?["s"]?["params"]?["angle"] else { XCTFail("no waiting params command"); return snap }
        commands[0] = with(commands[0], "s", F.json(Self.animate(Int(to))))
        pending[pending.count - 1] = with(pending[pending.count - 1], "commands", .array(commands))
        return with(snap, "pending", .array(pending))
    }

    func testRestoreCountsTheWaitingAnimatesTogether() throws {
        let clock = MGManualClock()
        // At the cap: 24 waiting animates restore, and the stream count stays 24.
        let full = waitingQueue(pairs: 12).snapshot()
        XCTAssertEqual(full["stream"]?["animates"], .number(24))
        XCTAssertEqual(try MGLessonSession.restore(full, pacing: .speech, clock: clock).get().stream.animates, 24)
        // One more waiting `animate` in a later beat: 25 together, each beat within its own cap.
        XCTAssertEqual(MGLessonSession.restore(lastCommandAnimates(full), pacing: .speech, clock: clock).failureReason, "snapshot.pending")
        // The same edit with room left restores, and the count covers the queue (23) though the snapshot stores 22.
        let room = waitingQueue(pairs: 11).snapshot()
        let edited = try MGLessonSession.restore(lastCommandAnimates(room), pacing: .speech, clock: clock).get()
        XCTAssertEqual(edited.stream.animates, 23)
        XCTAssertEqual(edited.queuedAnimates, 23)
    }

    func testLegacySnapshotTakesTheCountFromTheQueue() throws {
        let s = waitingQueue(pairs: 2, end: false)
        let snap = s.snapshot()
        let stream = try XCTUnwrap(snap["stream"])
        XCTAssertEqual(stream["animates"], .number(4))
        let legacy = with(snap, "stream", with(stream, "animates", nil))   // written before the count was kept
        var restored = try MGLessonSession.restore(legacy, pacing: .speech, clock: MGManualClock()).get()
        XCTAssertEqual(restored.stream.animates, 4, "at least the animates the waiting beats hold")
        XCTAssertEqual(restored.snapshot(), snap)
        // The same stream goes on with the rest of its budget: 20 more, then the 25th is refused.
        var lines: [String] = []
        var angle = 25
        for beat in 0..<10 {
            lines.append(#"{"say":"More \#(beat + 1)."}"#)
            for _ in 0..<MGLessonLimits.animatesPerBeat { angle += 5; lines.append(Self.animate(angle)) }
        }
        lines += [#"{"say":"Last."}"#, Self.animate(angle + 5)]
        XCTAssertEqual(F.refusals(feed(&restored, lines)).map(\.reason), ["lesson.animate.count"])
    }

    func testReplayedScriptKeepsTheCaps() {
        let a = F.json(Self.animate(5)), other = F.json(#"{"op":"params","params":{"angle":10}}"#)
        XCTAssertNoThrow(try MGLessonEngine.checkReplayAnimates(setup: [a, other], beats: [[a, a, other]]))
        XCTAssertThrowsError(try MGLessonEngine.checkReplayAnimates(setup: [], beats: [[a, other, a, a]]))
        let setup = Array(repeating: a, count: MGLessonLimits.animatesPerStream + 1)
        XCTAssertThrowsError(try MGLessonEngine.checkReplayAnimates(setup: setup, beats: []))
        XCTAssertEqual(MGLessonEngine.excessAnimate([a, other, a, a]), 3)
        XCTAssertEqual(MGLessonEngine.excessAnimate([a], used: MGLessonLimits.animatesPerStream), 0)
        XCTAssertNil(MGLessonEngine.excessAnimate([a, a], used: MGLessonLimits.animatesPerStream - 2))
    }
}
