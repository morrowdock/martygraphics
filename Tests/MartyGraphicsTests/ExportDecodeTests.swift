// SPDX-License-Identifier: Apache-2.0
import AVFoundation
import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import XCTest
@_spi(Experimental) @testable import MartyGraphics

/// Decoded checks of the export presets (docs/ENGINE.md, "Export presets"). A ProRes 4444 alpha master of a 2D video
/// is decoded and checked for its codec, a fully clear region, a half-transparent shape and antialiased edges
/// composited over light and dark. Colour patches written with the BT.709, sRGB and Display P3 presets are decoded and
/// the track's colour tags read; one P3 patch lies outside sRGB. Until these run on a Mac, the docs say "tags
/// requested; decoded check pending".
final class ExportDecodeTests: XCTestCase {
    func temporaryFolder() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mg-decode-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    /// One decoded frame as BGRA bytes: the decoder's own YCbCr to RGB with the file's matrix, no colour matching.
    struct Frame {
        let width: Int, height: Int, bytesPerRow: Int
        let bytes: [UInt8]
        /// The decoder says its colours are multiplied by alpha (`kCVImageBufferAlphaChannelModeKey`).
        let premultiplied: Bool

        /// The pixel at canvas point (x, y), y counted up from the bottom as the drawing was (buffer rows run down).
        func pixel(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
            let o = (height - 1 - y) * bytesPerRow + 4 * x
            return (Int(bytes[o + 2]), Int(bytes[o + 1]), Int(bytes[o]), Int(bytes[o + 3]))
        }

        /// The pixel with straight (not premultiplied) colour.
        func straight(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
            let p = pixel(x, y)
            guard premultiplied, p.a > 0, p.a < 255 else { return p }
            func u(_ c: Int) -> Int { min(255, (c * 255 + p.a / 2) / p.a) }
            return (u(p.r), u(p.g), u(p.b), p.a)
        }
    }

    func decode(_ url: URL) async throws -> (frames: [Frame], description: CMFormatDescription) {
        let asset = AVURLAsset(url: url)
        // `XCTUnwrap` takes a synchronous autoclosure: await first, then unwrap.
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first, "no video track")
        let descriptions = try await track.load(.formatDescriptions)
        let description = try XCTUnwrap(descriptions.first, "no format description")
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(output)
        XCTAssertTrue(reader.startReading())
        var frames: [Frame] = []
        while let sample = output.copyNextSampleBuffer() {
            guard let pb = CMSampleBufferGetImageBuffer(sample) else { continue }
            CVPixelBufferLockBaseAddress(pb, .readOnly)
            let w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb), row = CVPixelBufferGetBytesPerRow(pb)
            var bytes: [UInt8] = []
            if let base = CVPixelBufferGetBaseAddress(pb) {
                bytes = Array(UnsafeBufferPointer(start: base.assumingMemoryBound(to: UInt8.self), count: row * h))
            }
            CVPixelBufferUnlockBaseAddress(pb, .readOnly)
            let attachments = CVBufferCopyAttachments(pb, .shouldPropagate) as? [String: Any]
            let mode = attachments?[kCVImageBufferAlphaChannelModeKey as String] as? String
            XCTAssertEqual(bytes.count, row * h, "frame \(frames.count) has no pixels")
            frames.append(Frame(width: w, height: h, bytesPerRow: row, bytes: bytes,
                                premultiplied: mode == kCVImageBufferAlphaChannelMode_PremultipliedAlpha as String))
        }
        XCTAssertEqual(reader.status, .completed)
        return (frames, description)
    }

    // MARK: Alpha

    /// A 320 × 180 plan (the preset's frame, so nothing is scaled): an opaque ellipse with antialiased edges and a
    /// rectangle at 50 % opacity; the rest of the canvas is empty.
    static let alphaPlan = ##"{"v":1,"dim":"2d","title":"Alpha check","items":[],"layer2d":{"status":"proposed","version":"0.1.0-draft","fps":30,"durationFrames":3,"canvas":{"width":320,"height":180},"elements":[{"id":"solid","kind":"shape","at":[90,130],"color":"#E03C28","shape":"ellipse","size":[61,41]},{"id":"glass","kind":"shape","at":[230,130],"color":"#2878F0","shape":"rect","size":[60,40],"opacity":0.5}],"tracks":[],"captions":[],"generatedMediaLabel":"Generated educational animation"}}"##

    func alphaCheckPlan() throws -> MGCheckedVideoPlan {
        let scene = try MGParser.scene(data: Data(Self.alphaPlan.utf8), programmaticVideo: true).get()
        return try MGProgrammaticVideo.check(scene, programmaticVideo: true)
    }

    /// `lesson-alpha` at the plan's 320 × 180 frame, so nothing is scaled.
    var smallAlpha: MGExportPreset {
        var preset = MGExportPreset.lessonAlpha
        preset.width = 320; preset.height = 180
        return preset
    }

    func testTheAlphaMasterIsClearWhereNothingIsDrawn() async throws {
        let plan = try alphaCheckPlan()
        let preset = smallAlpha
        let url = try temporaryFolder().appendingPathComponent("alpha.mov")
        let options = MGVideoExportOptions(burnCaptions: false, writeSRT: false, preset: preset)
        let receipt = try await MGProgrammaticVideo.export(plan, to: url, options: options, programmaticVideo: true)
        XCTAssertEqual(receipt.frameCount, 3)
        let (frames, description) = try await decode(url)
        XCTAssertEqual(CMFormatDescriptionGetMediaSubType(description), kCMVideoCodecType_AppleProRes4444, "the codec is ap4h")
        XCTAssertEqual(frames.count, 3)
        let f = try XCTUnwrap(frames.first)
        XCTAssertEqual([f.width, f.height], [320, 180])

        // Fully clear where nothing is drawn: no board colour behind the elements.
        for (x, y) in [(10, 170), (300, 170), (20, 130), (160, 130), (300, 60)] {
            XCTAssertEqual(f.pixel(x, y).a, 0, "(\(x), \(y)) must be fully clear")
        }
        // Opaque: the ellipse's centre in its own colour.
        let solid = f.straight(90, 130)
        XCTAssertEqual(solid.a, 255)
        assertNear(solid, (0xE0, 0x3C, 0x28), 4, "the opaque ellipse")
        // Partly transparent: the 50 % rectangle keeps its own colour (straight alpha) at half alpha.
        let glass = f.straight(230, 130)
        XCTAssertEqual(Double(glass.a), 127.5, accuracy: 3, "the 50 % rectangle")
        assertNear(glass, (0x28, 0x78, 0xF0), 5, "the 50 % rectangle's straight colour")

        // Antialiased edges along the ellipse's middle row: the straight colour is the shape's colour (not darkened by
        // the coverage, not brightened twice), and composited over white and over black each edge pixel lies between
        // the shape's colour and the background, with no dark or light fringe.
        var edges = 0
        for x in 50..<70 {
            let p = f.straight(x, 130)
            guard p.a > 0, p.a < 255 else { continue }
            edges += 1
            let a = Double(p.a) / 255
            if p.a >= 64 { assertNear(p, (0xE0, 0x3C, 0x28), 12, "edge pixel \(x) (alpha \(p.a))") }
            for (c, s) in [(p.r, 0xE0), (p.g, 0x3C), (p.b, 0x28)] {
                for background in [255.0, 0.0] {
                    let over = a * Double(c) + (1 - a) * background
                    let lo = min(Double(s), background) - 4, hi = max(Double(s), background) + 4
                    XCTAssertTrue(lo <= over && over <= hi, "edge pixel \(x) over \(background): \(over) leaves \(lo)...\(hi)")
                }
            }
        }
        XCTAssertGreaterThan(edges, 0, "the ellipse has antialiased edge pixels on its middle row")
    }

    func assertNear(_ p: (r: Int, g: Int, b: Int, a: Int), _ want: (Int, Int, Int), _ tolerance: Int, _ what: String,
                    file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertLessThanOrEqual(abs(p.r - want.0), tolerance, "\(what): red \(p.r), want \(want.0)", file: file, line: line)
        XCTAssertLessThanOrEqual(abs(p.g - want.1), tolerance, "\(what): green \(p.g), want \(want.1)", file: file, line: line)
        XCTAssertLessThanOrEqual(abs(p.b - want.2), tolerance, "\(what): blue \(p.b), want \(want.2)", file: file, line: line)
    }

    // MARK: Colour

    static let srgbPatches: [[Double]] = [[0.5, 0.5, 0.5], [0.8, 0.3, 0.15], [0.15, 0.55, 0.85], [0.95, 0.85, 0.2]]

    /// Four 64 × 128 patches. `wide`: drawn in Display P3, the first three as the sRGB colours and the fourth as P3
    /// pure red, which lies outside sRGB.
    func patches(wide: Bool) throws -> CGImage {
        let space = try XCTUnwrap(CGColorSpace(name: wide ? CGColorSpace.displayP3 : CGColorSpace.sRGB))
        let ctx = try XCTUnwrap(CGContext(data: nil, width: 256, height: 128, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        for (k, c) in Self.srgbPatches.enumerated() {
            var colour = CGColor(srgbRed: c[0], green: c[1], blue: c[2], alpha: 1)
            if wide, k == 3 { colour = try XCTUnwrap(CGColor(colorSpace: space, components: [1, 0, 0, 1])) }
            ctx.setFillColor(colour)
            ctx.fill(CGRect(x: 64 * k, y: 0, width: 64, height: 128))
        }
        return try XCTUnwrap(ctx.makeImage())
    }

    static func srgbToLinear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
    /// The BT.709 transfer function as Apple's colour management applies it when the writer converts sRGB-tagged
    /// source buffers for a file tagged BT.709: a 1.961 power curve, not the BT.709 camera curve (1.099 L^0.45 − 0.099
    /// with a linear toe). Mac run #23 decoded sRGB 0.3 as 68, 0.15 as 34 and 35, and 0.2 as 46 (1.961 power: 67, 34
    /// and 45; camera curve: 61, 23 and 35).
    static func apple709(_ l: Double) -> Double { pow(max(0, l), 1 / 1.961) }

    func testColourPatchesDecodeAsTheirTagsSay() async throws {
        let p3 = try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3))
        // The fourth P3 patch is truly wide gamut: in extended sRGB it needs components outside 0...1.
        let red = try XCTUnwrap(CGColor(colorSpace: p3, components: [1, 0, 0, 1])?
            .converted(to: try XCTUnwrap(CGColorSpace(name: CGColorSpace.extendedSRGB)), intent: .relativeColorimetric, options: nil)?.components)
        XCTAssertTrue(red[0] > 1.01 || red[1] < -0.01 || red[2] < -0.01, "P3 red \(red) fits in sRGB")

        for space in [MGExportPreset.ColorSpace.rec709, .srgb, .displayP3] {
            var preset = MGExportPreset.lesson
            preset.colorSpace = space
            preset.width = 256; preset.height = 128
            let url = try temporaryFolder().appendingPathComponent("\(space.rawValue).mp4")
            let movie = try MGMovieWriter(url: url, preset: preset)
            let frame = try patches(wide: space == .displayP3)
            for _ in 0..<4 { try movie.append(frame) }
            try movie.finish()
            let (frames, description) = try await decode(url)
            XCTAssertEqual(frames.count, 4)
            // The track carries the tags each colour space stands for. The values are written out here (the Core Video
            // and Core Media tag strings), not read from `colorProperties`, so a preset regression fails this test.
            let expected: (primaries: String, transfer: String, matrix: String)
            switch space {
            case .srgb: expected = ("ITU_R_709_2", "IEC_sRGB", "ITU_R_709_2")
            case .rec709: expected = ("ITU_R_709_2", "ITU_R_709_2", "ITU_R_709_2")
            case .displayP3: expected = ("P3_D65", "IEC_sRGB", "ITU_R_709_2")
            }
            XCTAssertEqual(CMFormatDescriptionGetExtension(description, extensionKey: kCMFormatDescriptionExtension_ColorPrimaries) as? String,
                           expected.primaries, "\(space.rawValue): colour primaries")
            XCTAssertEqual(CMFormatDescriptionGetExtension(description, extensionKey: kCMFormatDescriptionExtension_TransferFunction) as? String,
                           expected.transfer, "\(space.rawValue): transfer function")
            XCTAssertEqual(CMFormatDescriptionGetExtension(description, extensionKey: kCMFormatDescriptionExtension_YCbCrMatrix) as? String,
                           expected.matrix, "\(space.rawValue): YCbCr matrix")
            // The decoded patches are what those tags say: sRGB values for `srgb`, P3 values for `displayP3` (the sRGB
            // colours converted, and the wide red kept), and for `rec709` the drawn sRGB colours re-encoded with the
            // BT.709 transfer function as Apple's colour management applies it (`apple709`). A `rec709` file whose
            // samples are the sRGB values carries BT.709 tags over sRGB samples and fails here; the planned resolution
            // is to draw `rec709` frames in `CGColorSpace.itur_709`.
            let f = try XCTUnwrap(frames.last)
            for (k, c) in Self.srgbPatches.enumerated() {
                let want: [Double]
                switch space {
                case .srgb: want = c
                case .rec709: want = c.map { Self.apple709(Self.srgbToLinear($0)) }
                case .displayP3:
                    if k == 3 { want = [1, 0, 0] } else {
                        let converted = try XCTUnwrap(CGColor(srgbRed: c[0], green: c[1], blue: c[2], alpha: 1)
                            .converted(to: p3, intent: .relativeColorimetric, options: nil)?.components)
                        want = Array(converted.prefix(3)).map(Double.init)
                    }
                }
                let got = f.pixel(32 + 64 * k, 64)
                assertNear(got, (Int((want[0] * 255).rounded()), Int((want[1] * 255).rounded()), Int((want[2] * 255).rounded())),
                           space == .rec709 ? 6 : 5, "\(space.rawValue) patch \(k)")
            }
            if space == .rec709 {
                // Mid grey tells the two apart: sRGB 128, BT.709-encoded 116. Samples within 6 of 128 are sRGB samples
                // under BT.709 tags.
                let grey = f.pixel(32, 64)
                XCTAssertEqual(Int((Self.apple709(Self.srgbToLinear(0.5)) * 255).rounded()), 116)
                XCTAssertGreaterThan(abs(grey.g - 128), 6, "rec709: BT.709 tags over sRGB samples (grey \(grey.g), sRGB 128, BT.709 116)")
            }
        }
    }
}
