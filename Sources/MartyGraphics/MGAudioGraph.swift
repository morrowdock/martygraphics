// SPDX-License-Identifier: Apache-2.0
import Foundation

/// The data behind a board's audio graph (docs/PROTOCOL.md, "Audio graphs"): what `MartyGraphicsView` hands VoiceOver
/// through Apple's `AXChartDescriptor`, so a learner can play a series as a tone that rises and falls with the value,
/// step from point to point and hear each x and y, and read the axes and a summary.
///
/// Written by the engine from the checked scene, never by a model: `plot` points as the scene gives them, `func`
/// samples exactly as the engine sampled them (`MGGraph.checkFunction`), `bars` values as checked. The summary is
/// `MGDescribe` text. Pure and deterministic, so the view, a test and the docs agree.
///
/// - Gate: a board gets an audio graph only while a `plot`, `func` or `bars` item is visible and not concealed;
///   `chart` is nil otherwise and the board's accessibility is exactly as before.
/// - Motion: it describes the motion's first frame (t = 0), which is the frame the board shows when Reduce Motion is
///   on and the instant the parser checked. It never moves and does not depend on Reduce Motion or playback.
/// - One chart per board: the first visible chart item in item order, together with every later `plot` or `func`
///   drawn in the same frame (same `at`, `w`, `h` and ranges). The summary counts the charts left out.
/// - Series: one per `plot` or `bars` item and one per drawn piece of a `func` (the board never joins two pieces),
///   with the item's name, numbered "piece 2 of 3" when it has several.
/// - What is charted is what the board draws: the same checks as `MGCanvasRenderer` (`MGGraph.frame`,
///   `MGGraph.plotTrace`, `MGGraph.barsOrigin`, `MGGraph.mark`).
public enum MGAudioGraph {
    /// The kinds an audio graph describes.
    public static let kinds: Set<MGKind> = [.plot, .function, .bars]

    /// The most samples a checked `func` holds: 289 = 257 grid values (`MGLimits.funcIntervals + 1`) + 32 (two for
    /// each of at most `MGLimits.funcBreaks` = 16 breaks). A gap at an interval midpoint adds its two probes; a gap at
    /// a grid value replaces that value with at most two probes; a pole adds none. See `MGGraph.curve`.
    public static let maxSamples = MGLimits.funcIntervals + 1 + 2 * MGLimits.funcBreaks
    /// The most points one item gives, over all its series (290): every sample of a checked `func` and its marked
    /// point. A `plot` holds at most `MGLimits.points` (64) points and `bars` at most `MGLimits.bars` (6), so no
    /// parsed scene is ever cut. An item built in code with more points keeps `maxPoints` of them, evenly spaced over
    /// all its pieces, its first and last point included, and the summary gives both counts.
    public static let maxPoints = maxSamples + 1

    /// One axis. A numeric axis has a `range`; the bars' category axis has `categories` instead.
    public struct Axis: Equatable, Sendable {
        public var title: String
        /// The numeric range: the item's `xr` or `yr`; for bars, 0 and every value. Nil on a category axis.
        public var range: ClosedRange<Double>?
        /// The bar labels in order (category axis only).
        public var categories: [String] = []
        /// Values of the drawn interior grid lines (numeric `plot` and `func` axes: the frame's quarters).
        public var gridlines: [Double] = []
        /// Unit read after each value (the bars' `unit`); empty for none.
        public var unit: String = ""
        /// How a value on this axis is read: `MGPhysics.format`, as the board writes it.
        public func describe(_ value: Double) -> String { MGPhysics.format(value, unit: unit) }
    }

    /// One data point. On a category axis `x` is the bar's index and `category` its label.
    public struct Point: Equatable, Sendable {
        public var x: Double
        public var category: String?
        public var y: Double
        /// Read at this point: "marked point" or nil.
        public var label: String?
        public init(x: Double, category: String? = nil, y: Double, label: String? = nil) {
            self.x = x; self.category = category; self.y = y; self.label = label
        }
    }

    /// One series: a `plot` or `bars` item, or one drawn piece of a `func`.
    public struct Series: Equatable, Sendable {
        /// The item's id (shared by the pieces of one `func`).
        public var id: String
        /// The item's label; else `y = …` for a `func`, "plot" or "bars" (numbered when several items share a name);
        /// then ", piece 2 of 3" for a `func` drawn in several pieces.
        public var name: String
        /// True for a line (`plot`, `func` piece), false for bars.
        public var isContinuous: Bool
        public var points: [Point]
    }

    /// One item's points, before naming: one list per series.
    struct Trace: Equatable {
        var id: String
        var name: String
        var isContinuous: Bool
        var pieces: [[Point]]
        /// Points before the `maxPoints` cut; equal to `count` for every parsed scene.
        var sourceCount: Int
        /// Points kept, over all pieces.
        var count: Int { pieces.reduce(0) { $0 + $1.count } }
        var points: [Point] { pieces.flatMap { $0 } }
    }

    public struct Chart: Equatable, Sendable {
        public var title: String
        public var summary: String
        public var x: Axis
        public var y: Axis
        public var series: [Series]
    }

    /// The audio graph of the board at `step` (with that step's edits) without the `hiding` items (concealed practice
    /// values), or nil when no `plot`, `func` or `bars` item is visible. Items the board does not draw (only items
    /// built in code, never parsed ones) are left out: see `trace`.
    public static func chart(_ scene: MGScene, step: Int = 0, hiding: Set<String> = []) -> Chart? {
        // Cheap gate: a board that can never show a chart item costs nothing more than this scan.
        guard !scene.is3D, scene.items.contains(where: { kinds.contains($0.kind) })
                || scene.steps.contains(where: { $0.edits.contains { $0.key == "k" } }) else { return nil }
        return chart(scene, items: MGTimeline.items(scene, step: step), hiding: hiding)
    }

    /// The audio graph of `items`, the board's items now (`MGTimeline.items(scene, step:)`, or `MGSliderState.items`
    /// with the learner's slider values), without the `hiding` items. `MartyGraphicsView` passes the items it draws
    /// (the step items it keeps between frames, `MGTimelineCache`, or the slider state's), so the chart follows the
    /// sliders and never computes the items again; the scene gives the 3D flag and the title.
    public static func chart(_ scene: MGScene, items: [MGItem], hiding: Set<String> = []) -> Chart? {
        guard !scene.is3D, items.contains(where: { kinds.contains($0.kind) }) else { return nil }
        let visible = items.filter { !hiding.contains($0.id) }
        let charted = MGTimeline.frame(scene, items: visible.filter { kinds.contains($0.kind) }, time: 0)
            .compactMap { item in trace(item).map { (item: item, trace: $0) } }
        guard let first = charted.first?.item else { return nil }
        let chosen = first.kind == .bars ? [charted[0]] : charted.filter { $0.item.kind != .bars && sharesFrame($0.item, first) }
        let members = chosen.map(\.item)

        let x: Axis, y: Axis
        if first.kind == .bars {
            let values = first.bars.map(\.value).filter(\.isFinite)
            let lo = Swift.min(0, values.min() ?? 0), hi = Swift.max(0, values.max() ?? 0)
            let unit = first.text ?? ""
            x = Axis(title: "Bar", range: nil, categories: first.bars.map(\.label))
            y = Axis(title: unit.isEmpty ? "Value" : "Value (\(unit))", range: lo...(hi > lo ? hi : lo + 1), unit: unit)
        } else {
            let x0 = first.n("x0"), x1 = first.n("x1"), y0 = first.n("y0"), y1 = first.n("y1")
            func title(_ k: Int, _ fallback: String) -> String {
                members.lazy.compactMap { $0.list.count > k && !$0.list[k].isEmpty ? $0.list[k] : nil }.first ?? fallback
            }
            func quarters(_ a: Double, _ b: Double) -> [Double] { (1...3).map { a + (b - a) * Double($0) / 4 } }
            x = Axis(title: title(0, "x"), range: x0...x1, gridlines: quarters(x0, x1))
            y = Axis(title: title(1, "y"), range: y0...y1, gridlines: quarters(y0, y1))
        }

        var traces = chosen.map(\.trace)
        let names = traces.map(\.name)
        var seen: [String: Int] = [:]
        for k in traces.indices where names.filter({ $0 == names[k] }).count > 1 {
            let n = (seen[names[k]] ?? 0) + 1
            seen[names[k]] = n
            traces[k].name += " \(n)"
        }
        let series = traces.flatMap { t in
            t.pieces.enumerated().map { k, points in
                Series(id: t.id, name: t.pieces.count > 1 ? "\(t.name), piece \(k + 1) of \(t.pieces.count)" : t.name,
                       isContinuous: t.isContinuous, points: points)
            }
        }

        var summary = MGDescribe.capitalized(members.map { MGDescribe.item($0, in: visible) }.joined(separator: "; ")) + "."
        for t in traces where t.sourceCount > t.count {
            summary += " The audio graph of “\(t.name)” plays \(t.count) of its \(t.sourceCount) points."
        }
        let others = charted.count - members.count
        if others == 1 { summary += " One more chart on the board is not in this audio graph." }
        if others > 1 { summary += " \(others) more charts on the board are not in this audio graph." }

        let fallback = first.kind == .bars ? "Bar chart" : "Graph"
        let title = members.lazy.compactMap(\.label).first ?? (scene.title.isEmpty ? fallback : scene.title)
        return Chart(title: title, summary: summary, x: x, y: y, series: series)
    }

    /// The item's points as the board draws them, cut to `maxPoints`; nil when the board does not draw the item or it
    /// has no point to chart. The checks are the renderer's own:
    /// - `bars`: an anchor and at least one bar (`MGGraph.barsOrigin`); bars whose value is not finite are left out.
    /// - `plot`: every point has a finite place in the frame (`MGGraph.plotTrace`), and the ranges are finite and
    ///   increasing (an audio graph axis needs a range; the parser's rule).
    /// - `func`: a finite frame (`MGGraph.frame`); one list per piece the board draws (two samples or more), in order;
    ///   the marked point only where the board shows its dot (`MGGraph.mark`), inside the piece that holds it, with
    ///   the engine's value (the printed value).
    static func trace(_ item: MGItem) -> Trace? {
        var pieces: [[Point]]
        switch item.kind {
        case .bars:
            guard MGGraph.barsOrigin(item) != nil else { return nil }
            pieces = [item.bars.enumerated().map { Point(x: Double($0.offset), category: $0.element.label, y: $0.element.value) }]
        case .function:
            guard MGGraph.frame(item) != nil else { return nil }
            // The engine's samples (never recomputed), split where the board splits them.
            let samples = Array(item.pts.dropFirst())
            let mark = MGGraph.mark(item)
            pieces = MGGraph.pieces(samples.count, starts: item.marked).filter { $0.count >= 2 || $0 == mark?.piece }.map { r -> [Point] in
                var points = samples[r].map { Point(x: $0.x, y: $0.y) }
                guard let mark, r == mark.piece else { return points }
                if let i = points.firstIndex(where: { $0.x == mark.x }) {
                    points[i].y = mark.value
                    points[i].label = "marked point"
                } else {
                    points.insert(Point(x: mark.x, y: mark.value, label: "marked point"), at: points.firstIndex { $0.x > mark.x } ?? points.endIndex)
                }
                return points
            }
        default:
            let x0 = item.n("x0"), x1 = item.n("x1"), y0 = item.n("y0"), y1 = item.n("y1")
            guard MGGraph.plotTrace(item) != nil, [x0, x1, y0, y1].allSatisfy(\.isFinite), x1 > x0, y1 > y0 else { return nil }
            pieces = [item.pts.dropFirst().map { Point(x: $0.x, y: $0.y) }]
        }
        pieces = pieces.map { $0.filter { $0.x.isFinite && $0.y.isFinite } }.filter { !$0.isEmpty }
        let count = pieces.reduce(0) { $0 + $1.count }
        guard count > 0 else { return nil }
        if count > maxPoints {
            // Evenly spaced over all pieces and strictly increasing (the step is above 1), first and last kept.
            let step = Double(count - 1) / Double(maxPoints - 1)
            let keep = Set((0..<maxPoints).map { Int((Double($0) * step).rounded()) })
            var k = 0
            pieces = pieces.map { piece in
                piece.filter { _ in
                    defer { k += 1 }
                    return keep.contains(k)
                }
            }.filter { !$0.isEmpty }
        }
        let name = item.label ?? (item.kind == .function ? "y = \(item.text ?? "")" : item.kind == .bars ? "bars" : "plot")
        return Trace(id: item.id, name: name, isContinuous: item.kind != .bars, pieces: pieces, sourceCount: count)
    }

    /// Two `plot` or `func` items drawn in one frame: the same anchor, size and ranges.
    static func sharesFrame(_ a: MGItem, _ b: MGItem) -> Bool {
        a.pts.first == b.pts.first && ["w", "h", "x0", "x1", "y0", "y1"].allSatisfy { a.num[$0] == b.num[$0] }
    }
}
