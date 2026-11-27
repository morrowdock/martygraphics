// SPDX-License-Identifier: Apache-2.0
import Accessibility
import SwiftUI

/// A board's audio graph (`MGAudioGraph.Chart`) as Apple's `AXChartDescriptor`: VoiceOver plays each series as a tone
/// and reads the chart details (title, summary, axes, series). Numeric axes read values with
/// `MGAudioGraph.Axis.describe`, so VoiceOver says the numbers the board draws.
struct MGChartDescriptor: AXChartDescriptorRepresentable {
    let chart: MGAudioGraph.Chart

    func makeChartDescriptor() -> AXChartDescriptor {
        AXChartDescriptor(title: chart.title, summary: chart.summary, xAxis: Self.axis(chart.x), yAxis: Self.numeric(chart.y),
                          additionalAxes: [], series: chart.series.map(Self.series))
    }

    /// SwiftUI keeps one descriptor per board and calls this when the chart changes (a step, a patch, a concealed item).
    func updateChartDescriptor(_ descriptor: AXChartDescriptor) {
        descriptor.title = chart.title
        descriptor.summary = chart.summary
        descriptor.xAxis = Self.axis(chart.x)
        descriptor.yAxis = Self.numeric(chart.y)
        descriptor.series = chart.series.map(Self.series)
    }

    /// A category axis for bars, else a numeric axis.
    static func axis(_ a: MGAudioGraph.Axis) -> any AXDataAxisDescriptor {
        guard a.range != nil else { return AXCategoricalDataAxisDescriptor(title: a.title, categoryOrder: a.categories) }
        return numeric(a)
    }

    static func numeric(_ a: MGAudioGraph.Axis) -> AXNumericDataAxisDescriptor {
        AXNumericDataAxisDescriptor(title: a.title, range: a.range ?? 0...1, gridlinePositions: a.gridlines) { a.describe($0) }
    }

    static func series(_ s: MGAudioGraph.Series) -> AXDataSeriesDescriptor {
        let points = s.points.map { p -> AXDataPoint in
            if let category = p.category { return AXDataPoint(x: category, y: p.y, additionalValues: [], label: p.label) }
            return AXDataPoint(x: p.x, y: p.y, additionalValues: [], label: p.label)
        }
        return AXDataSeriesDescriptor(name: s.name, isContinuous: s.isContinuous, dataPoints: points)
    }
}

/// Gives the board its audio graph while `chart` is non-nil (`MGAudioGraph.chart`). With nil the board is returned
/// unchanged, so a board without a visible `plot`, `func` or `bars` item reads exactly as before.
struct MGAudioGraphModifier: ViewModifier {
    let chart: MGAudioGraph.Chart?

    @ViewBuilder func body(content: Content) -> some View {
        if let chart {
            content.accessibilityChartDescriptor(MGChartDescriptor(chart: chart))
        } else {
            content
        }
    }
}
