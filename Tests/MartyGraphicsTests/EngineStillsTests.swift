// SPDX-License-Identifier: Apache-2.0
import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import XCTest
@_spi(Experimental) @testable import MartyGraphics

/// Comparison stills for the intentional default output changes of the engine-quality pass (docs/ENGINE.md,
/// "Default output changes"): label placement, arrow shafts (board vectors while they draw on, and 2D video arrows),
/// pixel alignment of hairlines and dots at 1x, 2x and 3x, and the cleared pooled buffer of the movie writer.
///
/// The file uses only API that `main` at 5e4952e also has, so the same file renders the legacy stills in a checkout of
/// that commit (the Mac command list in docs/ENGINE.md copies it there). With `MG_STILLS_DIR` set, the PNGs are written
/// to that folder for a person to compare side by side; without it the stills are only rendered. Nothing here asserts
/// on the pixels: the comparison is a human review.
final class EngineStillsTests: XCTestCase {
    static let labels = #"{"v":1,"world":{"w":12,"h":8},"items":[{"id":"a","k":"body","at":[5,4],"size":1,"label":"Cart A"},{"id":"b","k":"body","at":[6.3,4.4],"size":1,"label":"Cart B"},{"id":"push","k":"vector","on":"a","angle":0,"len":2,"label":"Push"},{"id":"lift","k":"vector","on":"a","angle":90,"len":2,"label":"Normal"},{"id":"weight","k":"vector","on":"a","angle":270,"len":2,"label":"Weight"},{"id":"drag","k":"vector","on":"a","angle":180,"len":1.5,"label":"Friction"},{"id":"pull","k":"vector","on":"b","angle":60,"len":1.8,"label":"Pull"},{"id":"note","k":"text","at":[5.6,5.6],"text":"Two carts"}]}"#

    static let arrows = #"{"v":1,"world":{"w":12,"h":8},"items":[{"id":"long","k":"vector","from":[1.5,1.5],"angle":30,"len":4,"label":"Long"},{"id":"short","k":"vector","from":[7,1.5],"angle":0,"len":0.6,"label":"Short"},{"id":"thin","k":"vector","from":[9,4],"angle":120,"len":2.5,"dashed":true},{"id":"dash","k":"vector","from":[1.5,6],"angle":-10,"len":4.3,"dashed":true,"label":"Dashed"}]}"#

    static let hairlines = #"{"v":1,"world":{"w":12,"h":8},"items":[{"id":"t","k":"table","at":[3.3,5.1],"header":true,"cells":[["Gear","Teeth"],["sun","24"],["planet","18"]]},{"id":"p","k":"plot","at":[6.7,1.3],"w":4.6,"h":3.1,"xr":[0,10],"yr":[0,5],"pts":[[0,0.5],[3,2.2],[6,3.1],[10,4.6]],"label":"Output"},{"id":"c","k":"body","at":[2.2,1.9],"size":1,"label":"Label border"}]}"#

    /// Where to write the stills (`MG_STILLS_DIR`), nil to only render them.
    var folder: URL? {
        guard let path = ProcessInfo.processInfo.environment["MG_STILLS_DIR"], !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    func save(_ image: CGImage, _ name: String) throws {
        guard let folder else { return }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name + ".png")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination), name)
    }

    @MainActor func board(_ json: String, size: CGSize, scale: CGFloat, appear: [String: Double] = [:]) throws -> CGImage {
        let scene = try MGParser.scene(data: Data(json.utf8)).get()
        let items = MGTimeline.frame(scene, items: MGTimeline.items(scene, step: 0), time: 0)
        let input = MGRenderInput(scene: scene, items: items, viewport: MGViewport(size: size, width: scene.width, height: scene.height, camera: nil),
                                  theme: .classic, appear: appear)
        let r = ImageRenderer(content: Canvas { ctx, _ in MGCanvasRenderer.draw(input, in: ctx) }.frame(width: size.width, height: size.height))
        r.scale = scale
        return try XCTUnwrap(r.cgImage)
    }

    @MainActor func testBoardStills() throws {
        let size = CGSize(width: 480, height: 320)
        // Label placement and leader lines.
        for scale: CGFloat in [1, 2] { try save(try board(Self.labels, size: size, scale: scale), "labels@\(Int(scale))x") }
        // Arrow shafts while vectors draw on (draw-on progress 0.1, 0.3, 0.6) and at rest.
        for p in [0.1, 0.3, 0.6, 1.0] {
            let appear = p < 1 ? ["long": p, "short": p, "thin": p, "dash": p] : [:]
            try save(try board(Self.arrows, size: size, scale: 2, appear: appear), "arrows-\(Int(p * 100))@2x")
        }
        // Hairlines, dots and label borders at 1x, 2x and 3x.
        for scale: CGFloat in [1, 2, 3] { try save(try board(Self.hairlines, size: size, scale: scale), "hairlines@\(Int(scale))x") }
    }

    /// 2D video arrows (`MGVideoDrawing`): the end of the shaft at the arrowhead's tip, for three stroke widths.
    func testVideoArrowStill() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("docs/examples/programmatic-video/sorting.json"))) as? [String: Any])
        var layer = try XCTUnwrap(object["layer2d"] as? [String: Any])
        let elements: [[String: Any]] = [
            ["id": "thin", "kind": "arrow", "at": [200, 200], "to": [420, 300], "color": "#FFD54F", "strokeWidth": 2],
            ["id": "mid", "kind": "arrow", "at": [200, 400], "to": [520, 420], "color": "#64FFDA", "strokeWidth": 4],
            ["id": "wide", "kind": "arrow", "at": [700, 250], "to": [900, 520], "color": "#FF5D73", "strokeWidth": 6],
        ]
        layer["elements"] = elements
        layer["tracks"] = []
        layer["captions"] = []
        layer["durationFrames"] = 1
        object["layer2d"] = layer
        let data = try JSONSerialization.data(withJSONObject: object)
        let plan = try MGProgrammaticVideo.check(try MGParser.scene(data: data, programmaticVideo: true).get(), programmaticVideo: true)
        try save(try MGProgrammaticVideo.frame(0, in: plan, burnCaptions: false), "video-arrows")
    }

    /// The engine's own H.264 writer over a pooled buffer: frame 0 is opaque red, frame 1 is clear except a blue
    /// square. The legacy writer drew frame 1 over whatever the pooled buffer held; the writer now clears it first.
    func testPooledBufferStill() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mg-stills-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("pool.mp4")
        let movie = try MGMovieWriter(url: url, width: 160, height: 96, fps: 30, maxBufferedFrames: 1)
        func image(_ fill: (CGContext) -> Void) throws -> CGImage {
            let ctx = try XCTUnwrap(CGContext(data: nil, width: 160, height: 96, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            fill(ctx)
            return try XCTUnwrap(ctx.makeImage())
        }
        let red = try image { $0.setFillColor(CGColor(srgbRed: 0.9, green: 0.1, blue: 0.1, alpha: 1)); $0.fill(CGRect(x: 0, y: 0, width: 160, height: 96)) }
        let square = try image { $0.setFillColor(CGColor(srgbRed: 0.1, green: 0.3, blue: 0.9, alpha: 1)); $0.fill(CGRect(x: 56, y: 24, width: 48, height: 48)) }
        for frame in [red, square, square, square] { try movie.append(frame) }
        try movie.finish()
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        for k in [1, 3] {
            let still = try generator.copyCGImage(at: CMTime(value: CMTimeValue(k), timescale: 30), actualTime: nil)
            try save(still, "pooled-buffer-frame\(k)")
        }
    }
}
