// SPDX-License-Identifier: Apache-2.0
import CoreGraphics

extension MLBoard {
    func meaningMap(_ item: MLMeaningMap, frame: Int) {
        simplified()
        let top = panel.minY + 109
        let plot = CGRect(x: panel.minX, y: top, width: panel.width, height: panel.height - 190)
        card(plot)
        let labels = meaningLabels(item, in: plot.insetBy(dx: 12, dy: 12))
        let count = min(item.points.count, 1 + max(0, frame - 12) / 4)
        let visible = labels.prefix(count)
        let clustered = item.points.indices.filter { item.cluster.contains(item.points[$0].label) && $0 < count }
        if let first = clustered.first {
            let bounds = clustered.dropFirst().reduce(labels[first].marker) { $0.union(labels[$1].marker) }
            card(bounds.insetBy(dx: -13, dy: -13), role: .good, radius: 11)
        }
        if frame >= 63 {
            for edge in item.neighbors {
                let reverse = item.neighbors[edge.to].to == edge.from
                if reverse && edge.to < edge.from { continue }
                let good = item.cluster.contains(item.points[edge.from].label) && item.cluster.contains(item.points[edge.to].label)
                line([labels[edge.from].center, labels[edge.to].center],
                     color: good ? color(.good) : subtle.copy(alpha: 0.63) ?? subtle, width: 2.6)
            }
        }
        for (index, label) in visible.enumerated() {
            let point = item.points[index]
            let highlight = item.cluster.contains(point.label)
            let markerTint = highlight ? color(.good) : color(.accent)
            if let box = label.box {
                line([label.center, CGPoint(x: box.midX, y: box.midY)],
                     color: markerTint.copy(alpha: 0.70) ?? markerTint, width: 1)
            }
            if let image = point.image {
                card(label.marker, role: highlight ? .good : .accent, emphasized: true, radius: 7)
                pixelImage(image, in: label.marker.insetBy(dx: 3, dy: 3))
            } else {
                fill(label.marker, color: markerTint, radius: label.marker.width / 2)
            }
        }
        for (index, label) in visible.enumerated() {
            guard let box = label.box else { continue }
            let point = item.points[index]
            let highlight = item.cluster.contains(point.label)
            text(point.label, x: box.midX, y: box.midY, size: MLStyle.body, maxWidth: box.width,
                 color: highlight ? color(.good) : ink)
        }
        text(item.label, x: panel.midX, y: panel.maxY - 56, size: MLStyle.body, maxWidth: panel.width)
        let source = item.dimension == 2 ? "Words and image placement are illustrative"
            : item.citation ?? "Illustrative vectors"
        text(source, x: panel.midX, y: panel.maxY - 29, size: MLStyle.detail,
             maxWidth: panel.width - 20, color: subtle, face: .mono)
    }

    private struct MeaningLabel {
        let center: CGPoint
        let marker: CGRect
        let box: CGRect?
    }

    private func meaningLabels(_ item: MLMeaningMap, in plot: CGRect) -> [MeaningLabel] {
        let xs = item.points.map { $0.position[0] }, ys = item.points.map { $0.position[1] }
        let lowX = xs.min()!, highX = xs.max()!, lowY = ys.min()!, highY = ys.max()!
        let units = min((plot.width - 205) / max(highX - lowX, Double.leastNormalMagnitude),
                        (plot.height - 172) / max(highY - lowY, Double.leastNormalMagnitude))
        // Identical authored positions stay identical on the canvas.
        let scale = units.isFinite ? units : 0
        let centers = item.points.map { point in
            CGPoint(x: plot.midX + (point.position[0] - (lowX + highX) / 2) * scale,
                    y: plot.midY - (point.position[1] - (lowY + highY) / 2) * scale)
        }
        let markers = zip(centers, item.points).map { center, point in
            let edge = point.image == nil ? 13.0 : 63.0
            return CGRect(x: center.x - edge / 2, y: center.y - edge / 2, width: edge, height: edge)
        }
        var boxes: [Int: CGRect] = [:]
        for (index, point) in item.points.enumerated() where point.image == nil {
            let marker = markers[index], center = centers[index]
            let width = min(188, ceil(textWidth(point.label, size: MLStyle.body, face: .label)) + 14)
            let height = width == 188 ? 52.0 : 28.0
            let margin = 8.0
            let side = marker.width / 2 + margin + width / 2
            let vertical = marker.height / 2 + margin + height / 2
            let options = [
                CGPoint(x: center.x, y: center.y - vertical), CGPoint(x: center.x, y: center.y + vertical),
                CGPoint(x: center.x + side, y: center.y), CGPoint(x: center.x - side, y: center.y),
                CGPoint(x: center.x + side, y: center.y - vertical), CGPoint(x: center.x - side, y: center.y + vertical)
            ].map { self.labelBox($0, width: width, height: height, in: plot) }
            let fallback = proportionedLabelBoxes(width: width, height: height, in: plot, around: center)
            let occupied = Array(boxes.values) + markers.map { $0.insetBy(dx: -4, dy: -4) }
            let box = (options + fallback).first { candidate in !occupied.contains { $0.intersects(candidate) } }
                ?? options[0]
            boxes[index] = box
        }
        return centers.indices.map { MeaningLabel(center: centers[$0], marker: markers[$0], box: boxes[$0]) }
    }

    private func labelBox(_ center: CGPoint, width: Double, height: Double, in plot: CGRect) -> CGRect {
        CGRect(x: min(plot.maxX - width, max(plot.minX, center.x - width / 2)),
               y: min(plot.maxY - height, max(plot.minY, center.y - height / 2)), width: width, height: height)
    }

    private func proportionedLabelBoxes(width: Double, height: Double, in plot: CGRect, around point: CGPoint) -> [CGRect] {
        var options: [CGRect] = []
        for row in 1..<8 {
            for column in 1..<8 {
                let center = CGPoint(x: plot.minX + plot.width * Double(column) / 8,
                                     y: plot.minY + plot.height * Double(row) / 8)
                options.append(labelBox(center, width: width, height: height, in: plot))
            }
        }
        return options.enumerated().sorted {
            let a = hypot($0.element.midX - point.x, $0.element.midY - point.y)
            let b = hypot($1.element.midX - point.x, $1.element.midY - point.y)
            return a == b ? $0.offset < $1.offset : a < b
        }.map(\.element)
    }
}
