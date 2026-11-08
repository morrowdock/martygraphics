// SPDX-License-Identifier: Apache-2.0
import CoreGraphics
import Foundation
import ImageIO
import MartyGraphics
import XCTest
@testable import MartySolidCLI

/// The title band keeps its text readable over any geometry: a dark backdrop (`titleBackdrop`) lies under the title, the
/// legend line and the overlay's legend corner. Measured as WCAG contrast (relative luminance, sRGB) of the brightest
/// text pixel against the brightest backdrop pixel beside the text: at least 4.5:1.
final class TitleBackdropTests: XCTestCase {
    struct Pixels {
        let width: Int, height: Int, bytes: [UInt8]
        init(_ image: CGImage) {
            width = image.width; height = image.height
            var px = [UInt8](repeating: 0, count: width * height * 4)
            let ctx = CGContext(data: &px, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            bytes = px
        }
        /// WCAG relative luminance of the pixel at column `x`, row `y` counted from the top.
        func luminance(_ x: Int, _ y: Int) -> Double {
            let i = (y * width + x) * 4
            func lin(_ b: UInt8) -> Double { let c = Double(b) / 255; return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
            return 0.2126 * lin(bytes[i]) + 0.7152 * lin(bytes[i + 1]) + 0.0722 * lin(bytes[i + 2])
        }
        /// The brightest pixel in columns `xs`, rows `ys` (from the top).
        func brightest(_ xs: Range<Int>, _ ys: Range<Int>) -> Double {
            var best = 0.0
            for y in ys { for x in xs { best = max(best, luminance(x, y)) } }
            return best
        }
    }

    static func contrast(_ a: Double, _ b: Double) -> Double { (max(a, b) + 0.05) / (min(a, b) + 0.05) }

    func white(_ w: Int, _ h: Int) -> CGImage {
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()!
    }

    /// The worst case: a pure white render under the title band. Title, legend line and legend corner keep 4.5:1.
    func testTitleLegendLineAndLegendCornerOverPureWhite() throws {
        let doc = try MGSolidParser.document(data: Data(#"{"v":2,"kind":"assembly","title":"Bright","parts":[{"id":"p","shape":{"gear":{"teeth":15,"module":2,"width":8}},"joint":{"revolute":[0,0,1]},"drive":{"input":1}}],"annotations":{"labels":[{"id":"l","at":"p","text":"Gear"}]}}"#.utf8)).get()
        XCTAssertFalse(doc.legend.text.isEmpty)
        let backed = titleBackdrop(white(1280, 800))
        let withLegend = legendOnly(backed, doc)
        let img = caption(withLegend, title: "Bright title", text: "A caption.", footer: "Solved 1 · Rendered by the MartyGraphics solid engine")
        let p = Pixels(img)
        // Backdrop beside the text, in the same rows (no text in columns 560–900).
        let titleBg = p.brightest(560..<900, 30..<72), footerBg = p.brightest(560..<900, 82..<98)
        let title = p.brightest(40..<300, 30..<72), footer = p.brightest(40..<400, 82..<98)
        XCTAssertGreaterThanOrEqual(Self.contrast(title, titleBg), 4.5, "title \(title) on \(titleBg)")
        XCTAssertGreaterThanOrEqual(Self.contrast(footer, footerBg), 4.5, "legend line \(footer) on \(footerBg)")
        let r = MGAnnotationLayout.legendRect(width: 1280, height: 800)
        let legend = p.brightest(Int(r.x)..<1279, Int(r.y)..<Int(r.y + r.height))
        let legendBg = p.brightest(Int(r.x) - 200..<Int(r.x) - 20, Int(r.y)..<Int(r.y + r.height))
        XCTAssertGreaterThanOrEqual(Self.contrast(legend, legendBg), 4.5, "legend corner \(legend) on \(legendBg)")
        // Without the backdrop the same title would be white on white (the check is not vacuous).
        let bare = Pixels(caption(white(1280, 800), title: "Bright title", text: nil, footer: "x"))
        XCTAssertLessThan(Self.contrast(bare.brightest(40..<300, 30..<72), bare.brightest(560..<900, 30..<72)), 1.1)
        // The backdrop stays inside the band and its fade: the middle of the frame is untouched.
        XCTAssertEqual(Pixels(backed).luminance(640, 400), 1, accuracy: 1e-9)
    }

    /// The legend corner scales with the frame height, so in portrait and square frames it reaches below the title
    /// band. Every legend line there keeps 4.5:1 over pure white: the brightest legend text pixel in the corner against
    /// the brightest backdrop pixel of the same corner without text.
    func testLegendCornerIsBackedAtEverySupportedShape() throws {
        let doc = try MGSolidParser.document(data: Data(#"{"v":2,"kind":"assembly","title":"Bright","parts":[{"id":"p","shape":{"gear":{"teeth":15,"module":2,"width":8}},"joint":{"revolute":[0,0,1]},"drive":{"input":1}}],"annotations":{"arrows":[{"id":"a","meaning":"pointer","from":{"world":[0,0,60]},"to":"p","text":"Gear"}]}}"#.utf8)).get()
        XCTAssertFalse(doc.legend.text.isEmpty)
        for (w, h) in [(1280, 800), (800, 1280), (1280, 1280), (640, 1280)] {
            let backed = titleBackdrop(white(w, h))
            let r = MGAnnotationLayout.legendRect(width: Double(w), height: Double(h))
            let xs = Int(r.x)..<(w - 1), ys = Int(r.y)..<Int(r.y + r.height)
            let bg = Pixels(backed).brightest(xs, ys)
            let text = Pixels(legendOnly(backed, doc)).brightest(xs, ys)
            XCTAssertGreaterThan(text, bg, "\(w)x\(h): legend drew nothing")
            XCTAssertGreaterThanOrEqual(Self.contrast(text, bg), 4.5, "\(w)x\(h): legend \(text) on \(bg)")
        }
    }

    /// The board line (an explainer beat whose board shows only text) has its own backdrop: in a tall frame it reaches
    /// below the title band into the 3D pane. Over pure white its text keeps 4.5:1 against the brightest pixel of its
    /// own row band beside the text, at every supported shape.
    func testBoardLineIsBackedAtEverySupportedShape() throws {
        for (w, h) in [(1280, 800), (800, 1280), (1280, 1280), (640, 1280)] {
            let s = Double(w) / 1280
            // No title backdrop under it: in explainer stills the bright 3D pane is drawn over the band's rows in tall
            // frames, so the line must protect itself.
            let img = caption(white(w, h), title: "T", text: nil, footer: "Solved 1", boardLine: "Given figures (not checked)")
            let p = Pixels(img)
            // Rows of the board line: baseline at 118·s from the top, 15·s font; text spans about 40·s … 240·s wide.
            let top = Int((118 - 15) * s), bottom = min(h, Int((118 + 6) * s) + 1)
            let text = p.brightest(Int(40 * s)..<Int(200 * s), top..<bottom)
            // Background: the same rows in the line's own backdrop margin, just left of the text.
            let bg = p.brightest(Int(36 * s)..<Int(39 * s), top..<bottom)
            XCTAssertLessThan(bg, 0.2, "\(w)x\(h): no backdrop beside the board line")
            XCTAssertGreaterThanOrEqual(Self.contrast(text, bg), 4.5, "\(w)x\(h): board line \(text) on \(bg)")
        }
    }

    /// A line-wide smoke test across the documented range (≥ 1280 × 720, up to 3840 wide, aspect 0.5–2.0): for each
    /// text line (title, legend line, legend corner, board line, caption) over pure white, every interior text row's
    /// brightest pixel keeps 4.5:1 against the backdrop pixel of the same row beside the text (the single anti-aliased
    /// row at each end of a run of text rows is skipped). It catches a backdrop or ink that is too weak; the per-glyph
    /// coverage criterion in SOLID-3D.md was checked by an independent audit, not by this test.
    func testEveryTextLineInTheGuaranteedRange() throws {
        let doc = try MGSolidParser.document(data: Data(#"{"v":2,"kind":"assembly","title":"Bright","parts":[{"id":"p","shape":{"gear":{"teeth":15,"module":2,"width":8}},"joint":{"revolute":[0,0,1]},"drive":{"input":1}}],"annotations":{"arrows":[{"id":"a","meaning":"pointer","from":{"world":[0,0,60]},"to":"p","text":"Gear"}]}}"#.utf8)).get()
        for (w, h) in [(1280, 800), (1280, 720), (1440, 720), (1280, 1280), (1280, 2560), (1920, 1080), (1600, 3200), (3840, 2160)] {
            let s = Double(w) / 1280
            let img = caption(legendOnly(titleBackdrop(white(w, h)), doc), title: "Bright wall, gear and dot",
                              text: "1. The wall, the gear and the dot.", footer: "Solved 1 · Rendered by the MartyGraphics solid engine",
                              boardLine: "Given figures: wall, gear (not checked)")
            let p = Pixels(img)
            func rows(_ ys: Range<Int>, _ xs: Range<Int>, _ bgx: Range<Int>, _ what: String) {
                var textRows: [(Int, Double, Double)] = []
                for y in ys {
                    let text = p.brightest(xs, y..<(y + 1)), bg = p.brightest(bgx, y..<(y + 1))
                    if text > bg + 0.02, bg < 0.5 { textRows.append((y, text, bg)) }
                }
                var checked = 0
                for (k, r) in textRows.enumerated() {
                    let interior = k > 0 && textRows[k - 1].0 == r.0 - 1 && k + 1 < textRows.count && textRows[k + 1].0 == r.0 + 1
                    guard interior else { continue }
                    XCTAssertGreaterThanOrEqual(Self.contrast(r.1, r.2), 4.5, "\(w)x\(h) \(what) row \(r.0): \(r.1) on \(r.2)")
                    checked += 1
                }
                XCTAssertGreaterThan(checked, 2, "\(w)x\(h) \(what): no text rows found")
            }
            rows(Int(30 * s)..<Int(76 * s), Int(40 * s)..<Int(700 * s), Int(20 * s)..<Int(36 * s), "title")
            rows(Int(80 * s)..<Int(97 * s), Int(40 * s)..<Int(500 * s), Int(20 * s)..<Int(36 * s), "legend line")
            rows(Int(98 * s)..<min(h, Int(128 * s)), Int(40 * s)..<Int(300 * s), Int(37 * s)..<Int(39 * s), "board line")
            let capTop = h - Int(Double(MGSolidRenderPlan.captionBandPixels) * s), capBottom = h - Int(10 * s)
            rows(capTop..<capBottom, Int(40 * s)..<Int(600 * s), Int(20 * s)..<Int(38 * s), "caption")
            let r = MGAnnotationLayout.legendRect(width: Double(w), height: Double(h))
            rows(Int(r.y)..<Int(r.y + r.height), Int(r.x + r.width * 0.3)..<(w - 1), Int(r.x + 2)..<Int(r.x + 8), "legend corner")
        }
    }

    /// A real render: a bright white wall fills the frame behind a small focus part, so geometry covers the whole title
    /// band. The still's title and legend line keep 4.5:1.
    func testRenderedStillWithABrightPartInTheTitleBand() throws {
        let binary = Bundle(for: Self.self).bundleURL.deletingLastPathComponent().appendingPathComponent("marty-solid")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("title-backdrop-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let doc = dir.appendingPathComponent("wall.json")
        try Data(#"{"v":2,"kind":"assembly","title":"Bright wall","parts":[{"id":"dot","material":"plastic.white","shape":{"box":{"size":[10,10,10]}}},{"id":"wall","material":"plastic.white","at":[0,120,0],"shape":{"box":{"size":[3000,20,3000]}}}],"steps":[{"say":"The dot.","focus":["dot"],"camera":"front"}]}"#.utf8).write(to: doc)
        let out = dir.appendingPathComponent("out")
        let p = Process()
        p.executableURL = binary
        p.arguments = ["render", doc.path, out.path, "--size", "1280x800", "--no-loop", "--no-story"]
        p.standardOutput = Pipe(); p.standardError = Pipe()
        try p.run(); p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw XCTSkip("render unavailable (no Metal device?)") }
        let src = try XCTUnwrap(CGImageSourceCreateWithURL(out.appendingPathComponent("step-1.png") as CFURL, nil))
        let px = Pixels(try XCTUnwrap(CGImageSourceCreateImageAtIndex(src, 0, nil)))
        // The wall really is bright, just under the band.
        XCTAssertGreaterThan(px.brightest(560..<900, 140..<160), 0.3)
        let title = px.brightest(40..<300, 30..<72), titleBg = px.brightest(560..<900, 30..<72)
        let footer = px.brightest(40..<400, 82..<98), footerBg = px.brightest(560..<900, 82..<98)
        XCTAssertGreaterThanOrEqual(Self.contrast(title, titleBg), 4.5, "title \(title) on \(titleBg)")
        XCTAssertGreaterThanOrEqual(Self.contrast(footer, footerBg), 4.5, "legend line \(footer) on \(footerBg)")
    }
}
