// SPDX-License-Identifier: Apache-2.0
import CoreGraphics

extension MLBoard {
    func attention(_ item: MLAttention, frame: Int) {
        simplified(MLAttention.label)
        let progress = item.displayed(at: frame)
        let layout = CGRect(x: panel.minX, y: panel.minY + 107, width: panel.width, height: panel.height - 195)
        card(layout)
        let art = layout.insetBy(dx: 35, dy: 79)
        let scale = min(art.width / Double(item.image.width), art.height / Double(item.image.height))
        let edge = Double(item.patchSize) * scale
        let image = CGRect(x: art.midX - Double(item.columns) * edge / 2,
                           y: art.midY - Double(item.rows) * edge / 2,
                           width: Double(item.columns) * edge, height: Double(item.rows) * edge)
        pixelImage(item.image, in: image)
        fill(image, color: CGColor(srgbRed: 0.07, green: 0.04, blue: 0.07, alpha: 0.62))
        func rect(_ cell: MLAttention.Cell) -> CGRect {
            CGRect(x: image.minX + Double(cell.column) * edge, y: image.minY + Double(cell.row) * edge,
                   width: edge, height: edge)
        }
        let query = rect(item.query)
        let tint = color(.accent)
        let grid = tint.copy(alpha: 0.60) ?? tint
        for column in 0...item.columns {
            let x = image.minX + Double(column) * edge
            line([CGPoint(x: x, y: image.minY), CGPoint(x: x, y: image.maxY)], color: grid, width: min(1.5, edge * 0.1))
        }
        for row in 0...item.rows {
            let y = image.minY + Double(row) * edge
            line([CGPoint(x: image.minX, y: y), CGPoint(x: image.maxX, y: y)], color: grid, width: min(1.5, edge * 0.1))
        }
        let focus = color(.good)
        for (target, weight) in zip(item.targets, item.distribution.probabilities) where weight > 0 && progress > 0 {
            let cell = rect(target)
            let opacity = weight / item.strongest * progress
            fill(cell.insetBy(dx: 1.2, dy: 1.2), color: focus.copy(alpha: opacity * 0.43) ?? focus)
            let destination = CGPoint(x: query.midX + (cell.midX - query.midX) * progress,
                                      y: query.midY + (cell.midY - query.midY) * progress)
            line([CGPoint(x: query.midX, y: query.midY), destination],
                 color: focus.copy(alpha: opacity) ?? focus, width: min(3.5, edge * 0.15))
        }
        let queryTint = color(.yellow)
        context.setStrokeColor(queryTint)
        context.setLineWidth(min(3.4, edge * 0.16))
        context.stroke(query.insetBy(dx: 1, dy: 1))
        let marker = min(17, edge * 0.38)
        fill(CGRect(x: query.midX - marker / 2, y: query.midY - marker / 2, width: marker, height: marker),
             color: queryTint, radius: marker / 2)
        text("Query patch", x: layout.midX, y: layout.minY + 36, size: MLStyle.heading,
             maxWidth: layout.width - 26, color: queryTint)
        text("Links brighten with weight", x: layout.midX, y: layout.maxY - 33, size: MLStyle.body,
             maxWidth: layout.width - 26, color: focus)
        if progress == 1 {
            let total = Self.number(item.distribution.sum, precision: "%.2f")
            let strongest = Self.number(item.strongest * 100, precision: "%.2f")
            text("Softmax total \(total) · strongest \(strongest)%", x: panel.midX, y: panel.maxY - 46,
                 size: MLStyle.body, maxWidth: panel.width - 24, face: .mono)
        }
    }
}
