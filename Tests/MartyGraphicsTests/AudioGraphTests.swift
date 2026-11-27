// SPDX-License-Identifier: Apache-2.0
import XCTest
@testable import MartyGraphics
#if canImport(Accessibility) && canImport(SwiftUI)
import Accessibility
#endif

/// Audio graphs (docs/PROTOCOL.md, "Audio graphs"): the chart VoiceOver gets for `plot`, `func` and `bars` items comes
/// from the engine's own values, follows the step, never moves, is bounded, and no other board gets one.
final class AudioGraphTests: XCTestCase {
    private func scene(_ json: String) throws -> MGScene { try MGParser.scene(data: Data(json.utf8)).get() }
    private func fixture(_ id: String) throws -> MGScene { try XCTUnwrap(MGFixtures.all.first { $0.id == id }?.scene) }
    private func xy(_ points: [MGAudioGraph.Point]) -> [MGPoint] { points.map { MGPoint($0.x, $0.y) } }
    private func board(_ items: [MGItem]) -> MGScene {
        MGScene(source: .object([:]), template: nil, title: "", is3D: false, width: 12, height: 8, items: items, steps: [],
                camera: nil, values: [:], motion: .none, attachments: [:])
    }

    static let plot = #"""
    {"v":1,"title":"Speed","items":[{"id":"v","k":"plot","at":[1,1],"w":8,"h":5,"xr":[0,4],"yr":[0,12],
     "pts":[[0,0],[1,3],[2,5.5],[4,11]],"xl":"t (s)","yl":"v (m/s)","label":"speed"}]}
    """#
    static let bars = #"""
    {"v":1,"items":[{"id":"e","k":"bars","at":[2,1],"w":6,"h":4,"unit":"J","label":"Energy",
     "bars":[{"label":"KE","value":12},{"label":"PE","value":-3.5},{"label":"Total","value":8.5}]}]}
    """#

    func testAPlotGivesItsRangesTitlesAndPointsAsGiven() throws {
        let s = try scene(Self.plot)
        let chart = try XCTUnwrap(MGAudioGraph.chart(s))
        XCTAssertEqual(chart.title, "speed")
        XCTAssertEqual(chart.x.title, "t (s)")
        XCTAssertEqual(chart.y.title, "v (m/s)")
        XCTAssertEqual(chart.x.range, 0...4)
        XCTAssertEqual(chart.y.range, 0...12)
        XCTAssertEqual(chart.x.gridlines, [1, 2, 3], "the drawn grid: the frame's quarters")
        XCTAssertEqual(chart.y.gridlines, [3, 6, 9])
        XCTAssertEqual(chart.x.describe(2.5), "2.5")
        XCTAssertEqual(chart.series.count, 1)
        let series = chart.series[0]
        XCTAssertEqual(series.id, "v")
        XCTAssertEqual(series.name, "speed")
        XCTAssertTrue(series.isContinuous)
        XCTAssertEqual(xy(series.points), Array(try XCTUnwrap(s.item("v")).pts.dropFirst()))
        XCTAssertEqual(series.points.map(\.y), [0, 3, 5.5, 11])
        XCTAssertTrue(series.points.allSatisfy { $0.label == nil && $0.category == nil })
        XCTAssertEqual(MGAudioGraph.trace(try XCTUnwrap(s.item("v")))?.sourceCount, 4)
        // The summary is MGDescribe's text for the charted items.
        XCTAssertEqual(chart.summary, "A plot of 4 points labelled “speed” for x from 0 to 4 and y from 0 to 12.")
        XCTAssertEqual(chart.summary, MGDescribe.board(s))
    }

    func testAFuncSeriesIsTheEnginesSamplesAndItsMarkedPoint() throws {
        let s = try fixture("graphs")
        let expr = try MGExpression.compile("a*sin(x)", allowed: Set(MGExpression.Variable.allCases), reason: "func.y")
        for step in s.steps.indices {
            let chart = try XCTUnwrap(MGAudioGraph.chart(s, step: step), "step \(step)")
            let wave = try XCTUnwrap(MGTimeline.items(s, step: step).first { $0.id == "wave" })
            XCTAssertEqual(chart.series.map(\.id), ["wave"], "a vector field is not charted")
            XCTAssertEqual(chart.title, "y = a sin x")
            XCTAssertEqual(chart.series[0].name, "y = a sin x")
            XCTAssertEqual(chart.x.title, "x")
            XCTAssertEqual(chart.y.title, "y")
            XCTAssertEqual(chart.x.range, -3.2...3.2)
            XCTAssertEqual(chart.y.range, -1.6...1.6)
            XCTAssertTrue(chart.summary.hasPrefix("A graph of y = a*sin(x) labelled “y = a sin x” for x from -3.2 to 3.2"), chart.summary)
            XCTAssertFalse(chart.summary.contains("vector field"))
            var points = chart.series[0].points
            // The marked point is the engine's value at the mark, read as "marked point".
            let mark = try XCTUnwrap(points.firstIndex { $0.label == "marked point" })
            XCTAssertEqual(points[mark].x, 1.5708)
            XCTAssertEqual(points[mark].y, try XCTUnwrap(wave.num["my"]))
            points.remove(at: mark)
            XCTAssertTrue(points.allSatisfy { $0.label == nil }, "one piece")
            // Every other point is a sample the engine took (and stored at parse time), never a model's number.
            XCTAssertEqual(xy(points), Array(wave.pts.dropFirst()))
            XCTAssertEqual(points.count, MGLimits.funcIntervals + 1)
            let curve = MGGraph.curve({ expr.value(MGGraph.inputs(wave).with(x: $0)) }, x0: -3.2, x1: 3.2, y0: -1.6, y1: 1.6, measure: false)
            XCTAssertEqual(xy(points), curve.samples)
        }
        // The step's edit (a = 1.5) changes every value.
        let stretched = try XCTUnwrap(MGAudioGraph.chart(s, step: 1)).series[0].points
        XCTAssertEqual(try XCTUnwrap(stretched.map(\.y).max()), 1.5, accuracy: 1e-3)
    }

    func testAFuncWithBreaksGivesOneSeriesPerDrawnPiece() throws {
        // 1/x with 0 exactly on the midpoint of interval 127: two probes beside the gap, one break (GraphKindTests).
        let s = try scene(#"{"v":1,"items":[{"id":"f","k":"func","at":[1,1],"w":6,"h":4,"xr":[-0.99609375,1.00390625],"yr":[-300,300],"y":"1/x"}]}"#)
        let f = try XCTUnwrap(s.items.first)
        let samples = Array(f.pts.dropFirst())
        XCTAssertEqual(f.marked, [129])
        let series = try XCTUnwrap(MGAudioGraph.chart(s)).series
        XCTAssertEqual(series.map(\.id), ["f", "f"])
        XCTAssertEqual(series.map(\.name), ["y = 1/x, piece 1 of 2", "y = 1/x, piece 2 of 2"])
        XCTAssertTrue(series.allSatisfy(\.isContinuous), "each piece is a line; the two are never joined")
        XCTAssertEqual(xy(series[0].points), Array(samples[0..<129]))
        XCTAssertEqual(xy(series[1].points), Array(samples[129...]))
        XCTAssertTrue(series[0].points.allSatisfy { $0.x < 0 } && series[1].points.allSatisfy { $0.x > 0 })
        XCTAssertEqual(series.map(\.points.count).reduce(0, +), 259)
        XCTAssertTrue(series.allSatisfy { $0.points.allSatisfy { $0.label == nil } })

        // tan(x): four poles, five pieces, each its own series with exactly the samples the board draws for it.
        let tan = try scene(#"{"v":1,"items":[{"id":"f","k":"func","at":[1,1],"w":10,"h":6,"xr":[-6.2832,6.2832],"yr":[-4,4],"y":"tan(x)","label":"tan x"}]}"#)
        let t = try XCTUnwrap(tan.items.first)
        let tanSamples = Array(t.pts.dropFirst())
        let ranges = MGGraph.pieces(tanSamples.count, starts: t.marked)
        XCTAssertEqual(t.marked.count, 4)
        XCTAssertEqual(ranges.count, 5)
        XCTAssertTrue(ranges.allSatisfy { $0.count >= 2 })
        let pieces = try XCTUnwrap(MGAudioGraph.chart(tan)).series
        XCTAssertEqual(pieces.map(\.name), (1...5).map { "tan x, piece \($0) of 5" })
        XCTAssertEqual(pieces.map { xy($0.points) }, ranges.map { Array(tanSamples[$0]) })
        XCTAssertEqual(pieces.map(\.points.count).reduce(0, +), tanSamples.count)
        for k in 1..<pieces.count {
            XCTAssertLessThan(try XCTUnwrap(pieces[k - 1].points.last).x, try XCTUnwrap(pieces[k].points.first).x)
        }

        // With a mark, the marked point sits inside the piece that holds it (-π/2 < 1 < π/2: the third), at its x.
        let marked = try scene(#"{"v":1,"items":[{"id":"f","k":"func","at":[1,1],"w":10,"h":6,"xr":[-6.2832,6.2832],"yr":[-4,4],"y":"tan(x)","label":"tan x","mark":1}]}"#)
        let m = try XCTUnwrap(marked.items.first)
        let withMark = try XCTUnwrap(MGAudioGraph.chart(marked)).series
        XCTAssertEqual(withMark.count, 5)
        XCTAssertEqual(withMark.map(\.points.count).reduce(0, +), tanSamples.count + 1)
        XCTAssertEqual(withMark.indices.filter { withMark[$0].points.contains { $0.label != nil } }, [2])
        let dot = try XCTUnwrap(withMark[2].points.first { $0.label == "marked point" })
        XCTAssertEqual(dot.x, 1)
        XCTAssertEqual(dot.y, try XCTUnwrap(m.num["my"]), "the engine's value, as printed beside the dot")
        XCTAssertEqual(withMark[2].points.map(\.x), withMark[2].points.map(\.x).sorted())
    }

    func testTheMarkedPointFollowsTheBoardsDot() throws {
        // MGGraph.mark is the one check: the renderer draws the dot exactly when it gives a mark.
        let s = try scene(#"{"v":1,"items":[{"id":"f","k":"func","at":[1,1],"w":6,"h":4,"xr":[-0.99609375,1.00390625],"yr":[-300,300],"y":"1/x","mark":0.5}]}"#)
        var f = try XCTUnwrap(s.items.first)
        let shown = try XCTUnwrap(MGGraph.mark(f))
        XCTAssertEqual(shown.x, 0.5)
        XCTAssertEqual(shown.value, 2)
        XCTAssertEqual(shown.piece, 129..<259)
        let trace = try XCTUnwrap(MGAudioGraph.trace(f))
        XCTAssertEqual(trace.pieces[1].filter { $0.label == "marked point" }.map(\.y), [2])
        XCTAssertEqual(trace.count, 260)
        // An item built in code: the printed value stays the engine's (`my`), never the drawn curve's.
        f.num["my"] = 2.5
        XCTAssertEqual(try XCTUnwrap(MGAudioGraph.trace(f)).points.filter { $0.label != nil }.map(\.y), [2.5])
        // No dot, no marked point: a mark in the gap at 0 ...
        f.num["mark"] = 0
        XCTAssertNil(MGGraph.mark(f))
        XCTAssertEqual(try XCTUnwrap(MGAudioGraph.trace(f)).points.filter { $0.label != nil }.count, 0)
        XCTAssertEqual(try XCTUnwrap(MGAudioGraph.trace(f)).count, 259)
        // ... where the drawn curve is above the y range (just right of the pole), though `my` is inside it ...
        f.num["mark"] = 0.001
        XCTAssertNil(MGGraph.mark(f))
        XCTAssertEqual(try XCTUnwrap(MGAudioGraph.trace(f)).count, 259)
        // ... or a value that is missing or outside the y range.
        f.num["mark"] = 0.5
        f.num["my"] = 301
        XCTAssertNil(MGGraph.mark(f))
        f.num["my"] = nil
        XCTAssertNil(MGGraph.mark(f))
        XCTAssertEqual(try XCTUnwrap(MGAudioGraph.trace(f)).count, 259)
    }

    func testOnlyWhatTheBoardDrawsIsCharted() throws {
        // Bars without an anchor: the board draws nothing, so no audio graph.
        let parsedBars = try XCTUnwrap(try scene(Self.bars).items.first)
        XCTAssertNotNil(MGAudioGraph.trace(parsedBars))
        var bars = MGItem(id: "unanchored", kind: .bars, color: parsedBars.color)
        bars.num = parsedBars.num
        bars.bars = parsedBars.bars
        XCTAssertNil(MGGraph.barsOrigin(bars))
        XCTAssertNil(MGAudioGraph.trace(bars))
        XCTAssertNil(MGAudioGraph.chart(board([bars])))
        // A plot that mixes finite and non-finite points: the board draws its frame without the line, so no audio graph.
        let parsedPlot = try XCTUnwrap(try scene(Self.plot).items.first)
        XCTAssertNotNil(MGAudioGraph.trace(parsedPlot))
        var plot = MGItem(id: "lineless", kind: .plot, color: parsedPlot.color)
        plot.num = parsedPlot.num
        plot.pts = [MGPoint(1, 1), MGPoint(0, 1), MGPoint(.nan, 2), MGPoint(2, .infinity), MGPoint(3, 4)]
        XCTAssertNil(MGGraph.plotTrace(plot))
        XCTAssertNil(MGAudioGraph.trace(plot))
        XCTAssertNil(MGAudioGraph.chart(board([plot])))
        // The next chart item the board draws is charted instead.
        XCTAssertEqual(MGAudioGraph.chart(board([bars, plot, try XCTUnwrap(try scene(Self.bars).items.first)]))?.series.map(\.id), ["e"])
        // A plot without an anchor, and a func whose frame is not finite.
        var lost = try XCTUnwrap(try scene(Self.plot).items.first)
        lost.pts = []
        XCTAssertNil(MGAudioGraph.trace(lost))
        var f = try XCTUnwrap(try fixture("graphs").items.first { $0.kind == .function })
        XCTAssertNotNil(MGAudioGraph.trace(f))
        f.num["w"] = .infinity
        XCTAssertNil(MGGraph.frame(f))
        XCTAssertNil(MGAudioGraph.trace(f))
    }

    func testBarsGiveTheirLabelsValuesAndUnit() throws {
        let s = try scene(Self.bars)
        let chart = try XCTUnwrap(MGAudioGraph.chart(s))
        XCTAssertEqual(chart.title, "Energy")
        XCTAssertEqual(chart.x.title, "Bar")
        XCTAssertNil(chart.x.range)
        XCTAssertEqual(chart.x.categories, ["KE", "PE", "Total"])
        XCTAssertEqual(chart.y.title, "Value (J)")
        XCTAssertEqual(chart.y.range, -3.5...12, "0 and every value")
        XCTAssertEqual(chart.y.gridlines, [])
        XCTAssertEqual(chart.y.describe(12), "12 J")
        let series = try XCTUnwrap(chart.series.first)
        XCTAssertFalse(series.isContinuous)
        XCTAssertEqual(series.name, "Energy")
        XCTAssertEqual(series.points.map(\.category), ["KE", "PE", "Total"])
        XCTAssertEqual(series.points.map(\.x), [0, 1, 2])
        XCTAssertEqual(series.points.map(\.y), [12, -3.5, 8.5])
        XCTAssertEqual(chart.summary, MGDescribe.board(s))
        // Without a unit or a label, and with every value 0: the range is 0 to 1, never empty.
        let plain = try scene(#"{"v":1,"items":[{"id":"z","k":"bars","at":[2,1],"w":6,"h":4,"bars":[{"label":"a","value":0},{"label":"b","value":0}]}]}"#)
        let zero = try XCTUnwrap(MGAudioGraph.chart(plain))
        XCTAssertEqual(zero.y.range, 0...1)
        XCTAssertEqual(zero.y.title, "Value")
        XCTAssertEqual(zero.title, "Bar chart")
        XCTAssertEqual(zero.series[0].name, "bars")
    }

    func testTheAudioGraphIsTheFirstFrameAndNeverMoves() throws {
        // A moving func: the samples at t = 0, which is also the frame shown with Reduce Motion on.
        let wave = try fixture("wave")
        let item = try XCTUnwrap(wave.items.first)
        let chart = try XCTUnwrap(MGAudioGraph.chart(wave))
        XCTAssertEqual(xy(chart.series[0].points), Array(item.pts.dropFirst()))
        XCTAssertNotEqual(xy(chart.series[0].points), Array(try XCTUnwrap(MGTimeline.frame(wave, items: wave.items, time: 1).first).pts.dropFirst()))
        XCTAssertTrue(chart.summary.contains("moving and repeating every 4 s"), chart.summary)
        // Energy bars driven by spring motion: the values of the first frame (all potential), not the parsed ones.
        var bars = MGMake.kind("e", .bars, [MGPoint(7, 2)], ["w": 3, "h": 3], label: "Energy")
        bars.bars = [MGBar(label: "KE", value: 5, color: .kinetic), MGBar(label: "PE", value: 5, color: .potential),
                     MGBar(label: "Total", value: 10, color: .energy)]
        let energy = bars
        let template = MGTemplate(name: "demo_spring_bars", summary: "spring energy bars", params: [], make: { _, _ in
            MGTemplateBuild(title: "Spring", items: [MGMake.body("b", MGPoint(3, 4)), energy],
                            motion: .oscillate(id: "b", amplitude: 1, period: 2, energy: 10, bars: "e", vector: nil, vectorLength: 1))
        })
        let json = MGJSON.object(["v": .number(1), "template": .string("demo_spring_bars"), "params": .object([:])])
        let spring = try MGParser.scene(json: json, extraTemplates: [template]).get()
        let values = try XCTUnwrap(MGAudioGraph.chart(spring)).series[0].points.map(\.y)
        XCTAssertEqual(values, [0, 10, 10])
        XCTAssertEqual(values, try XCTUnwrap(MGTimeline.frame(spring, items: spring.items, time: 0).first { $0.id == "e" }).bars.map(\.value))
        XCTAssertNotEqual(values, try XCTUnwrap(MGTimeline.frame(spring, items: spring.items, time: 0.5).first { $0.id == "e" }).bars.map(\.value))
    }

    /// The board charts the step items it keeps between frames (`MGTimelineCache`): the same chart as from the scene
    /// and step, at every step, with and without concealed items, and the items are computed once per step.
    func testTheChartFromTheBoardsCachedItemsIsTheStepChart() throws {
        let json = #"""
        {"v":1,"items":[{"id":"g","k":"func","at":[1,1],"w":10,"h":6,"xr":[-3,3],"yr":[-4,4],"y":"a*x","a":1},
          {"id":"b","k":"bars","at":[7,1],"w":6,"h":6,"bars":[{"label":"A","value":2}]}],
         "steps":[{"say":"One."},{"say":"Two.","do":[{"id":"g","key":"a","value":2}]},{"say":"Three.","show":["b"]}]}
        """#
        let s = try scene(json)
        let cache = MGTimelineCache()
        for step in s.steps.indices {
            for hiding in [Set<String>(), ["g"]] {
                XCTAssertEqual(MGAudioGraph.chart(s, items: cache.items(s, step: step), hiding: hiding),
                               MGAudioGraph.chart(s, step: step, hiding: hiding), "step \(step) hiding \(hiding)")
            }
        }
        XCTAssertEqual(cache.computed, s.steps.count)
        XCTAssertNotEqual(MGAudioGraph.chart(s, step: 0), MGAudioGraph.chart(s, step: 1), "the step edit moves the graph")
        XCTAssertNil(MGAudioGraph.chart(s, items: [], hiding: []))
    }

    func testBoardsWithoutAVisibleChartItemHaveNoAudioGraph() throws {
        XCTAssertNil(MGAudioGraph.chart(try scene(MGRegression.items(MGRegression.dot))))
        XCTAssertNil(MGAudioGraph.chart(try scene(MGRegression.allKinds3D)))
        // A vector field alone is not a chart, and a concealed graph is never charted.
        XCTAssertNil(MGAudioGraph.chart(try fixture("graphs"), hiding: ["wave"]))
        // A plot shown from the second step on.
        let later = try scene(#"{"v":1,"items":[{"id":"dot","k":"body","at":[3,4]},{"id":"p","k":"plot","at":[5,1],"w":5,"h":4,"xr":[0,1],"yr":[0,1],"pts":[[0,0],[1,1]]}],"steps":[{"say":"A dot."},{"say":"Now the plot.","show":["p"]}]}"#)
        XCTAssertNil(MGAudioGraph.chart(later, step: 0))
        XCTAssertEqual(MGAudioGraph.chart(later, step: 1)?.series.map(\.id), ["p"])
        // Every built-in fixture, at every step: an audio graph exactly when a chart item is visible.
        var charted = 0
        for f in MGFixtures.all {
            let s = try XCTUnwrap(f.scene, f.id)
            for step in 0..<Swift.max(1, s.steps.count) {
                let visible = MGTimeline.items(s, step: step).contains { MGAudioGraph.kinds.contains($0.kind) }
                XCTAssertEqual(MGAudioGraph.chart(s, step: step) != nil, visible, "\(f.id) step \(step)")
                if visible { charted += 1 }
            }
        }
        XCTAssertGreaterThan(charted, 0)
    }

    func testGraphsInOneFrameShareTheChartAndTheRestAreCounted() throws {
        let frame = #""at":[1,1],"w":5,"h":4,"xr":[-3,3],"yr":[-1.5,1.5]"#
        let s = try scene(#"{"v":1,"items":["#
                          + #"{"id":"s","k":"func","# + frame + #","y":"sin(x)","xl":"x"},"#
                          + #"{"id":"c","k":"func","# + frame + #","y":"cos(x)","label":"cosine"},"#
                          + #"{"id":"p","k":"plot","# + frame + #","pts":[[-3,0],[3,1]]},"#
                          + #"{"id":"far","k":"func","at":[7,1],"w":4,"h":3,"xr":[-3,3],"yr":[-1.5,1.5],"y":"x/2"},"#
                          + #"{"id":"b","k":"bars","at":[7,5],"w":4,"h":2.5,"bars":[{"label":"a","value":1}]}]}"#)
        let chart = try XCTUnwrap(MGAudioGraph.chart(s))
        XCTAssertEqual(chart.series.map(\.id), ["s", "c", "p"])
        XCTAssertEqual(chart.series.map(\.name), ["y = sin(x)", "cosine", "plot"])
        XCTAssertEqual(chart.title, "cosine", "the first label")
        XCTAssertEqual(chart.x.title, "x")
        XCTAssertEqual(chart.y.title, "y")
        let items = MGTimeline.items(s, step: 0)
        let described = ["s", "c", "p"].map { id in MGDescribe.item(items.first { $0.id == id }!, in: items) }
        XCTAssertEqual(chart.summary, MGDescribe.capitalized(described.joined(separator: "; ")) + "."
                       + " 2 more charts on the board are not in this audio graph.")
        XCTAssertTrue(try XCTUnwrap(MGAudioGraph.chart(s, hiding: ["far"])).summary.hasSuffix(" One more chart on the board is not in this audio graph."))
        // A bar chart first is charted alone.
        XCTAssertEqual(MGAudioGraph.chart(s, hiding: ["s", "c", "p"])?.series.map(\.id), ["far"])
        XCTAssertEqual(MGAudioGraph.chart(s, hiding: ["s", "c", "p", "far"])?.series.map(\.id), ["b"])
        // Unlabelled series with the same name are numbered.
        let twins = try scene(#"{"v":1,"items":[{"id":"p1","k":"plot","# + frame + #","pts":[[-3,0],[3,1]]},{"id":"p2","k":"plot","# + frame + #","pts":[[-3,1],[3,0]]}]}"#)
        XCTAssertEqual(try XCTUnwrap(MGAudioGraph.chart(twins)).series.map(\.name), ["plot 1", "plot 2"])
    }

    func testTheLimitsBoundEverySeries() throws {
        XCTAssertEqual(MGAudioGraph.maxSamples, 289)
        XCTAssertEqual(MGAudioGraph.maxPoints, 290)
        XCTAssertLessThan(MGLimits.points, MGAudioGraph.maxPoints)
        XCTAssertLessThan(MGLimits.bars, MGAudioGraph.maxPoints)
        // The sampler's worst case: a gap at the first grid value whose right probe opens the curve and a gap at 16
        // interval midpoints: 256 grid values, 1 probe and 16 × 2 probes.
        let grid = (0...MGLimits.funcIntervals).map { MGGraph.gridX($0, -1, 1) }
        let gaps = Set(stride(from: 8, to: 8 + 16 * 15, by: 15).map { (grid[$0] + grid[$0 + 1]) / 2 })
        let worst = MGGraph.curve({ $0 == grid[0] || gaps.contains($0) ? .nan : 0.5 * sin(3 * $0) },
                                  x0: -1, x1: 1, y0: -1, y1: 1, measure: false)
        XCTAssertEqual(worst.starts.count, MGLimits.funcBreaks)
        XCTAssertEqual(worst.samples.count, MGAudioGraph.maxSamples)
        // With its marked point that fills one series exactly, and nothing is cut.
        var f = MGItem(id: "f", kind: .function, color: .accent)
        f.text = "0.5*sin(3*x)"
        f.pts = [MGPoint(1, 1)] + worst.samples
        f.marked = worst.starts
        f.num = ["w": 6, "h": 4, "x0": -1, "x1": 1, "y0": -1, "y1": 1, "mark": 0.3, "my": 0.5 * sin(0.9)]
        let full = try XCTUnwrap(MGAudioGraph.trace(f))
        XCTAssertEqual(full.pieces.count, MGLimits.funcBreaks + 1)
        XCTAssertEqual(full.count, MGAudioGraph.maxPoints, "289 samples and the marked point, over 17 series")
        XCTAssertEqual(full.sourceCount, MGAudioGraph.maxPoints)
        XCTAssertEqual(full.points.filter { $0.label != nil }.count, 1)
        // A parsed plot at its own limit keeps every point.
        let most = (0..<MGLimits.points).map { "[\($0),\($0 % 5)]" }.joined(separator: ",")
        let plot = try scene(#"{"v":1,"items":[{"id":"p","k":"plot","at":[1,1],"w":8,"h":5,"xr":[0,63],"yr":[0,4],"pts":["# + most + "]}]}")
        XCTAssertEqual(try XCTUnwrap(MGAudioGraph.chart(plot)).series[0].points.count, MGLimits.points)
        // An item built in code with more points keeps maxPoints, evenly spaced, first and last included.
        var big = MGItem(id: "big", kind: .plot, color: .accent)
        big.pts = [MGPoint(1, 1)] + (0..<1000).map { MGPoint(Double($0), Double($0 % 7)) }
        big.num = ["w": 6, "h": 4, "x0": 0, "x1": 999, "y0": 0, "y1": 6]
        let cut = try XCTUnwrap(MGAudioGraph.trace(big))
        XCTAssertEqual(cut.points.count, MGAudioGraph.maxPoints)
        XCTAssertEqual(cut.sourceCount, 1000)
        XCTAssertEqual(cut.points.first?.x, 0)
        XCTAssertEqual(cut.points.last?.x, 999)
        XCTAssertEqual(Set(cut.points.map(\.x)).count, MGAudioGraph.maxPoints)
        XCTAssertEqual(cut.points.map(\.x), cut.points.map(\.x).sorted())
        // The cut runs over all pieces of a func: 1000 samples in two pieces keep 290, first and last included.
        var long = MGItem(id: "long", kind: .function, color: .accent)
        long.pts = [MGPoint(1, 1)] + (0..<1000).map { MGPoint(Double($0) / 1000, 0.5) }
        long.marked = [400]
        long.num = ["w": 6, "h": 4, "x0": 0, "x1": 1, "y0": 0, "y1": 1]
        let thin = try XCTUnwrap(MGAudioGraph.trace(long))
        XCTAssertEqual(thin.pieces.count, 2)
        XCTAssertEqual(thin.count, MGAudioGraph.maxPoints)
        XCTAssertEqual(thin.sourceCount, 1000)
        XCTAssertEqual(thin.points.first?.x, 0)
        XCTAssertEqual(thin.points.last?.x, 0.999)
        XCTAssertTrue(thin.pieces[0].allSatisfy { $0.x < 0.4 } && thin.pieces[1].allSatisfy { $0.x >= 0.4 })
        // Ranges that are not finite and increasing leave a plot out (an audio graph axis needs a range).
        var odd = big
        odd.num["x1"] = -1
        XCTAssertNotNil(MGGraph.plotTrace(odd), "the board draws it mirrored")
        XCTAssertNil(MGAudioGraph.trace(odd))
        odd.num["x1"] = .nan
        XCTAssertNil(MGAudioGraph.trace(odd))
    }

    func testTheSummarySaysWhenASeriesOfAnItemBuiltInCodeIsCut() throws {
        var big = MGItem(id: "big", kind: .plot, color: .accent)
        big.pts = [MGPoint(1, 1)] + (0..<1000).map { MGPoint(Double($0), Double($0 % 7)) }
        big.num = ["w": 6, "h": 4, "x0": 0, "x1": 999, "y0": 0, "y1": 6]
        big.label = "many"
        let chart = try XCTUnwrap(MGAudioGraph.chart(board([big])))
        XCTAssertTrue(chart.summary.hasSuffix(" The audio graph of “many” plays 290 of its 1000 points."), chart.summary)
        // A func cut over its pieces: the summary gives the kept and the original count of the item.
        var long = MGItem(id: "long", kind: .function, color: .accent)
        long.pts = [MGPoint(1, 1)] + (0..<1000).map { MGPoint(Double($0) / 1000, 0.5) }
        long.marked = [400]
        long.num = ["w": 6, "h": 4, "x0": 0, "x1": 1, "y0": 0, "y1": 1]
        long.text = "0.5"
        let split = try XCTUnwrap(MGAudioGraph.chart(board([long])))
        XCTAssertEqual(split.series.map(\.name), ["y = 0.5, piece 1 of 2", "y = 0.5, piece 2 of 2"])
        XCTAssertEqual(split.series.map(\.points.count).reduce(0, +), MGAudioGraph.maxPoints)
        XCTAssertTrue(split.summary.hasSuffix(" The audio graph of “y = 0.5” plays 290 of its 1000 points."), split.summary)
    }

    #if canImport(Accessibility) && canImport(SwiftUI)
    /// Apple documents `AXDataPointValue`'s `number` (double) and `category` (NSString) for Objective-C only; its
    /// Swift page lists no members. The value is an NSObject, so the test reads both by key.
    private static func number(_ v: AXDataPointValue?) -> Double? { v?.value(forKey: "number") as? Double }
    private static func category(_ v: AXDataPointValue?) -> String? { v?.value(forKey: "category") as? String }

    @MainActor func testTheChartDescriptorCarriesTheChart() throws {
        let plot = try XCTUnwrap(MGAudioGraph.chart(try scene(Self.plot)))
        let d = MGChartDescriptor(chart: plot).makeChartDescriptor()
        XCTAssertEqual(d.title, "speed")
        XCTAssertEqual(d.summary, plot.summary)
        let x = try XCTUnwrap(d.xAxis as? AXNumericDataAxisDescriptor)
        XCTAssertEqual(x.title, "t (s)")
        XCTAssertEqual(x.range, 0...4)
        XCTAssertEqual(x.gridlinePositions, [1, 2, 3])
        XCTAssertEqual(x.valueDescriptionProvider(2.5), "2.5")
        let y = try XCTUnwrap(d.yAxis)
        XCTAssertEqual(y.title, "v (m/s)")
        XCTAssertEqual(y.range, 0...12)
        XCTAssertEqual(d.series.count, 1)
        XCTAssertEqual(d.series[0].name, "speed")
        XCTAssertTrue(d.series[0].isContinuous)
        XCTAssertEqual(d.series[0].dataPoints.map { Self.number($0.xValue) }, plot.series[0].points.map { Optional($0.x) })
        XCTAssertEqual(d.series[0].dataPoints.map { Self.number($0.yValue) }, plot.series[0].points.map { Optional($0.y) })

        let bars = try XCTUnwrap(MGAudioGraph.chart(try scene(Self.bars)))
        let b = MGChartDescriptor(chart: bars).makeChartDescriptor()
        let categories = try XCTUnwrap(b.xAxis as? AXCategoricalDataAxisDescriptor)
        XCTAssertEqual(categories.categoryOrder, ["KE", "PE", "Total"])
        XCTAssertEqual(b.yAxis?.range, -3.5...12)
        XCTAssertEqual(b.yAxis?.valueDescriptionProvider(12), "12 J")
        XCTAssertFalse(b.series[0].isContinuous)
        XCTAssertEqual(b.series[0].dataPoints.map { Self.category($0.xValue) }, ["KE", "PE", "Total"])
        XCTAssertEqual(b.series[0].dataPoints.map { Self.number($0.yValue) }, [12, -3.5, 8.5])

        // A func drawn in two pieces: two continuous series, never one line across the gap.
        let split = try XCTUnwrap(MGAudioGraph.chart(try scene(#"{"v":1,"items":[{"id":"f","k":"func","at":[1,1],"w":6,"h":4,"xr":[-0.99609375,1.00390625],"yr":[-300,300],"y":"1/x"}]}"#)))
        let pieces = MGChartDescriptor(chart: split).makeChartDescriptor()
        XCTAssertEqual(pieces.series.map(\.name), ["y = 1/x, piece 1 of 2", "y = 1/x, piece 2 of 2"])
        XCTAssertTrue(pieces.series.allSatisfy(\.isContinuous))
        XCTAssertEqual(pieces.series.map(\.dataPoints.count), split.series.map(\.points.count))

        // Point labels reach VoiceOver; an update replaces everything (one descriptor per board).
        let wave = try XCTUnwrap(MGAudioGraph.chart(try fixture("graphs")))
        let w = MGChartDescriptor(chart: wave).makeChartDescriptor()
        XCTAssertEqual(w.series[0].dataPoints.compactMap(\.label), ["marked point"])
        XCTAssertEqual(w.series[0].dataPoints.count, wave.series[0].points.count)
        MGChartDescriptor(chart: bars).updateChartDescriptor(w)
        XCTAssertEqual(w.title, "Energy")
        XCTAssertEqual(w.summary, bars.summary)
        XCTAssertEqual((w.xAxis as? AXCategoricalDataAxisDescriptor)?.categoryOrder, ["KE", "PE", "Total"])
        XCTAssertEqual(w.yAxis?.range, -3.5...12)
        XCTAssertEqual(w.series.count, 1)
        XCTAssertEqual(w.series[0].dataPoints.map { Self.number($0.yValue) }, [12, -3.5, 8.5])
    }
    #endif
}
