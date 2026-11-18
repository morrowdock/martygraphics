// SPDX-License-Identifier: Apache-2.0
import CoreGraphics

extension MLBoard {
    func simplified(_ subtitle: String = "Simplified") {
        text(subtitle, x: panel.midX, y: panel.minY + 71, size: MLStyle.detail,
             maxWidth: panel.width, color: subtle, face: .mono)
    }

    func pixelImage(_ image: MLPixels, in rect: CGRect) {
        let scale = min(rect.width / Double(image.width), rect.height / Double(image.height))
        let origin = CGPoint(x: rect.midX - scale * Double(image.width) / 2,
                             y: rect.midY - scale * Double(image.height) / 2)
        // Snap adjoining pixel boundaries together in device space to avoid seams.
        let unit = context.ctm.a
        func snap(_ value: Double) -> Double { (value * unit).rounded() / unit }
        for y in 0..<image.height {
            for x in 0..<image.width {
                let rgb = image.pixel(x: x, y: y)
                let red = Double(rgb[rgb.startIndex]) / 255
                let green = image.channels == 1 ? red : Double(rgb[rgb.startIndex + 1]) / 255
                let blue = image.channels == 1 ? red : Double(rgb[rgb.startIndex + 2]) / 255
                let left = snap(origin.x + Double(x) * scale)
                let top = snap(origin.y + Double(y) * scale)
                let right = snap(origin.x + Double(x + 1) * scale)
                let bottom = snap(origin.y + Double(y + 1) * scale)
                fill(CGRect(x: left, y: top, width: right - left, height: bottom - top),
                     color: CGColor(srgbRed: red, green: green, blue: blue, alpha: 1))
            }
        }
    }

    func picture(_ item: MLPicture, frame: Int) {
        simplified()
        let display = item.displayed(at: frame)
        let together = item.presentation != .grid
        let split = together && panel.width >= 900
        let top = panel.minY + 104
        let gap = 26.0
        let sectionWidth = split ? (panel.width - gap) / 2 : panel.width
        let height = split ? 440 : together ? 252 : min(495, panel.height - 190)
        let input = CGRect(x: panel.minX, y: top, width: sectionWidth, height: Double(height))
        card(input)
        text(display.gridOpacity == 0 ? "Input image" : "Patch grid", x: input.midX, y: input.minY + 27,
             size: MLStyle.heading, maxWidth: input.width - 24)
        let artHeight = input.height - 100
        let scale = min((input.width - 40) / Double(item.image.width), artHeight / Double(item.image.height))
        let width = Double(item.image.width) * scale, art = Double(item.image.height) * scale
        let image = CGRect(x: input.midX - width / 2, y: input.minY + 49 + (artHeight - art) / 2,
                           width: width, height: art)
        pixelImage(item.image, in: image)
        let edge = Double(item.patchSize) * scale
        if display.gridOpacity > 0 {
            let grid = CGColor(srgbRed: 0.08, green: 0.06, blue: 0.08, alpha: 0.85 * display.gridOpacity)
            for column in 0...item.columns {
                let x = image.minX + Double(column) * edge
                line([CGPoint(x: x, y: image.minY), CGPoint(x: x, y: image.maxY)], color: grid, width: min(2, edge * 0.16))
            }
            for row in 0...item.rows {
                let y = image.minY + Double(row) * edge
                line([CGPoint(x: image.minX, y: y), CGPoint(x: image.maxX, y: y)], color: grid, width: min(2, edge * 0.16))
            }
        }
        if display.highlight {
            let selected = CGRect(x: image.minX + Double(item.column) * edge, y: image.minY + Double(item.row) * edge,
                                  width: edge, height: edge)
            context.setStrokeColor(color(.yellow))
            context.setLineWidth(min(3, edge * 0.23))
            context.stroke(selected)
        }
        let dimensions = "\(item.image.width) × \(item.image.height) px"
        let grid = "\(item.columns) × \(item.rows) patches · \(item.patchSize) px per edge"
        text(display.gridOpacity == 1 ? grid : dimensions, x: input.midX, y: input.maxY - 24,
             size: MLStyle.detail, maxWidth: input.width - 24, color: subtle, face: .mono)

        if together, let page = display.page {
            let y = split ? top : input.maxY + 22
            let x = split ? input.maxX + gap : input.minX
            let height = split ? input.height : panel.maxY - y - 80
            let table = CGRect(x: x, y: y, width: sectionWidth, height: height)
            if split {
                arrow([CGPoint(x: input.maxX + 5, y: input.midY), CGPoint(x: table.minX - 5, y: input.midY)])
            }
            pictureValues(item, page: page, flattened: display.flattened, in: table)
        }
        text(item.caption, x: panel.midX, y: panel.maxY - 35, size: MLStyle.detail,
             maxWidth: panel.width - 24, color: subtle, face: .mono)
    }

    private func pictureValues(_ item: MLPicture, page: Int, flattened: Bool, in table: CGRect) {
        card(table)
        let pageColumn = page % item.pagesPerEdge * MLPicture.pageEdge
        let pageRow = page / item.pagesPerEdge * MLPicture.pageEdge
        let across = min(MLPicture.pageEdge, item.patchSize - pageColumn)
        let down = min(MLPicture.pageEdge, item.patchSize - pageRow)
        let mode = item.image.channels == 1 ? "Grayscale" : "RGB triples"
        let pageCount = item.pagesPerEdge * item.pagesPerEdge
        let pageLabel = pageCount > 1 ? " · \(page + 1)/\(pageCount)" : ""
        text("Actual pixel values · " + mode + pageLabel, x: table.midX, y: table.minY + 27,
             size: MLStyle.heading, maxWidth: table.width - 24)
        let cellWidth = min(144, (table.width - 30) / Double(across))
        let pitch = min(44, (table.height - 102) / Double(down))
        let firstX = table.midX - Double(across - 1) * cellWidth / 2
        let firstY = table.minY + 52 + (table.height - 102 - Double(down - 1) * pitch) / 2
        for y in 0..<down {
            for x in 0..<across {
                let center = CGPoint(x: firstX + Double(x) * cellWidth, y: firstY + Double(y) * pitch)
                let numbers = item.patchPixel(x: pageColumn + x, y: pageRow + y).map(String.init).joined(separator: " ")
                let cell = CGRect(x: center.x - cellWidth / 2 + 4, y: center.y - pitch / 2 + 3,
                                  width: cellWidth - 8, height: pitch - 6)
                card(cell, role: .teal, radius: 6)
                text(numbers, x: center.x, y: center.y, size: MLStyle.detail,
                     maxWidth: cell.width - 6, face: .mono)
            }
        }
        if flattened {
            text("\(item.patchSize) × \(item.patchSize) × \(item.image.channels) = \(item.vectorLength) values",
                 x: table.midX, y: table.maxY - 38, size: MLStyle.body,
                 maxWidth: table.width - 24, color: color(.good), face: .mono)
            text("Flattened vector · row by row", x: table.midX, y: table.maxY - 15, size: MLStyle.detail,
                 maxWidth: table.width - 24, color: subtle)
        }
    }
}
