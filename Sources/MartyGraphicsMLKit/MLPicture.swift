// SPDX-License-Identifier: Apache-2.0
import CoreGraphics
import Foundation
import ImageIO
import MartyGraphics

struct MLPixels: Equatable, Sendable {
    let width: Int
    let height: Int
    let channels: Int
    /// Top to bottom, left to right, with interleaved channels.
    let values: [UInt8]

    init(_ value: MGJSON?, invalid: MGMLIssue, size: MGMLIssue) throws {
        guard case .string(let encoded)? = value,
              let png = Data(base64Encoded: encoded), png.count >= 33,
              png.prefix(16) == Data([137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82]) else {
            throw invalid
        }
        func dimension(at offset: Int) -> Int {
            png[offset..<offset + 4].reduce(0) { ($0 << 8) | Int($1) }
        }
        let width = dimension(at: 16), height = dimension(at: 20)
        guard (1...64).contains(width), (1...64).contains(height) else { throw size }
        let grayscale = png[25] == 0
        guard png[24] == 8, grayscale || png[25] == 2,
              let source = CGImageSourceCreateWithData(png as CFData, nil),
              CGImageSourceGetCount(source) == 1,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              CGImageSourceGetStatus(source) == .statusComplete,
              image.width == width, image.height == height, image.bitsPerComponent == 8,
              image.alphaInfo == .none || image.alphaInfo == .noneSkipLast || image.alphaInfo == .noneSkipFirst,
              let space = image.colorSpace, space.model == (grayscale ? .monochrome : .rgb),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space,
                                      bitmapInfo: grayscale ? CGImageAlphaInfo.none.rawValue :
                                        CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
              let buffer = context.data?.assumingMemoryBound(to: UInt8.self) else {
            throw invalid
        }
        context.interpolationQuality = .none
        context.setBlendMode(.copy)
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        self.width = width
        self.height = height
        self.channels = grayscale ? 1 : 3
        let stride = grayscale ? 1 : 4
        var values: [UInt8] = []
        values.reserveCapacity(width * height * channels)
        for row in 0..<height {
            for column in 0..<width {
                let offset = row * context.bytesPerRow + column * stride
                values.append(contentsOf: UnsafeBufferPointer(start: buffer + offset, count: channels))
            }
        }
        self.values = values
    }

    func pixel(x: Int, y: Int) -> ArraySlice<UInt8> {
        let offset = (y * width + x) * channels
        return values[offset..<offset + channels]
    }
}

struct MLPicture: Equatable, Sendable {
    enum Presentation: String, Sendable {
        case both, grid, pixels
    }

    let caption: String
    let image: MLPixels
    let patchSize: Int
    let column: Int
    let row: Int
    let presentation: Presentation

    var columns: Int { image.width / patchSize }
    var rows: Int { image.height / patchSize }
    var vectorLength: Int { patchSize * patchSize * image.channels }
    static let pageEdge = 4
    var pagesPerEdge: Int { (patchSize + Self.pageEdge - 1) / Self.pageEdge }

    init(_ input: MLObject) throws {
        let caption = try input.text("caption", max: 100, reason: .pictureCaption)
        let image = try MLPixels(input.values["imagePNG"], invalid: input.issue(.picturePNG, "imagePNG"),
                                 size: input.issue(.pictureSize, "imagePNG"))
        let patchSize = try input.integer("patchSize", in: 1...64, reason: .picturePatch)
        guard image.width.isMultiple(of: patchSize), image.height.isMultiple(of: patchSize) else {
            throw input.issue(.picturePatch, "patchSize")
        }
        guard case .array(let highlight)? = input.values["highlight"], highlight.count == 2,
              let column = MLObject.integer(highlight[0], in: 0...(image.width / patchSize - 1)),
              let row = MLObject.integer(highlight[1], in: 0...(image.height / patchSize - 1)) else {
            throw input.issue(.pictureSelection, "highlight")
        }
        let mode = try input.optionalText("presentation", max: 6, reason: .picturePresentation) ?? "both"
        guard let presentation = Presentation(rawValue: mode) else {
            throw input.issue(.picturePresentation, "presentation")
        }
        self.caption = caption
        self.image = image
        self.patchSize = patchSize
        self.column = column
        self.row = row
        self.presentation = presentation
    }

    func patchPixel(x: Int, y: Int) -> ArraySlice<UInt8> {
        image.pixel(x: column * patchSize + x, y: row * patchSize + y)
    }

    var frameCount: Int {
        switch presentation {
        case .grid: return 150
        case .pixels, .both: return 150 + 60 * (pagesPerEdge * pagesPerEdge - 1)
        }
    }

    struct Display: Equatable {
        let gridOpacity: Double
        let page: Int?
        let highlight: Bool
        let flattened: Bool
    }

    func displayed(at frame: Int) -> Display {
        let grid = presentation == .pixels ? 1.0 : min(1, Double(max(0, frame - 30)) / 24)
        let reveal = presentation == .both ? 63 : 34
        guard presentation != .grid else {
            return Display(gridOpacity: grid, page: nil, highlight: false, flattened: false)
        }
        let page = frame >= reveal ? min(pagesPerEdge * pagesPerEdge - 1, (frame - reveal) / 60) : nil
        return Display(gridOpacity: grid, page: page, highlight: frame >= reveal - 18, flattened: frame >= reveal + 20)
    }

    func imageKey(_ frame: Int) -> Int {
        let display = displayed(at: frame)
        if display.gridOpacity > 0 && display.gridOpacity < 1 { return frame + 1 }
        let page = (display.page ?? -1) + 1
        return -1 - page * 8 - (display.gridOpacity == 1 ? 4 : 0) -
            (display.highlight ? 2 : 0) - (display.flattened ? 1 : 0)
    }

    var facts: [String: MGJSON] {
        let pixels: [MGJSON] = (0..<patchSize).flatMap { y in
            (0..<patchSize).flatMap { x in patchPixel(x: x, y: y).map { .number(Double($0)) } }
        }
        return [
            "caption": .string(caption), "presentation": .string(presentation.rawValue),
            "width": .number(Double(image.width)), "height": .number(Double(image.height)),
            "columns": .number(Double(columns)), "rows": .number(Double(rows)),
            "patchSize": .number(Double(patchSize)), "channels": .number(Double(image.channels)),
            "highlight": .array([.number(Double(column)), .number(Double(row))]),
            "patchValues": .array(pixels), "vectorLength": .number(Double(vectorLength))
        ]
    }
}
