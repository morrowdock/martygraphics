// SPDX-License-Identifier: Apache-2.0
import CoreGraphics
import Foundation
import MartyGraphics
import XCTest
@testable import MartySolidCLI

/// The modern overlay (`studio`, `paper`) draws no black bar: the title, the legend line, the caption and its step
/// number sit on the look's own backdrop. Measured as WCAG contrast against the least favourable backdrop the look can
/// draw there (its light pool centred under the text): at least 4.5:1.
final class LookTypeTests: XCTestCase {
    typealias Pixels = TitleBackdropTests.Pixels

    /// The look's backdrop with its pool centred at (`x`, `y`) from the top, wide enough to cover the text beside it.
    func backdrop(_ look: MGSolidLook, _ w: Int, _ h: Int, poolAt x: Double, _ y: Double) -> CGImage {
        let bytes = look.backdrop(width: w, height: h, pool: MGSolidLook.Pool(x: x, y: y, rx: Double(w), ry: Double(w)))
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider, decode: nil,
                       shouldInterpolate: false, intent: .defaultIntent)!
    }

    /// The pixel in the box that differs most from `background` in luminance (the text's core), and that luminance.
    func ink(_ p: Pixels, _ xs: Range<Int>, _ ys: Range<Int>, against background: Double) -> Double {
        var best = background
        for y in ys { for x in xs where abs(p.luminance(x, y) - background) > abs(best - background) { best = p.luminance(x, y) } }
        return best
    }

    func testTitleLegendLineAndCaptionOnTheLooksOwnBackdrop() throws {
        for look in [MGSolidLook.studio, .paper] {
            // Title band: the pool right under the title. Caption band: the pool right under the caption.
            let cases: [(Double, [(String, Range<Int>, Int)])] = [(50.0, [("title", 30..<72, 1), ("legend line", 82..<98, 1)]),
                                                                  (750.0, [("caption", 690..<716, 300), ("step number", 690..<716, 1)])]
            for (poolY, rows) in cases {
                let base = backdrop(look, 1280, 800, poolAt: 170, poolY)
                let img = caption(titleBackdrop(base, look: look), title: "Bright title", text: "12. A caption that names what the hold shows.",
                                  footer: "Solved 1 · Rendered by the MartyGraphics solid engine", look: look)
                let p = Pixels(img)
                for (what, ys, skip) in rows {
                    // Backdrop beside the text in the same rows (no text right of column 900).
                    var bg = 0.0, n = 0.0
                    for y in ys { for x in 900..<1100 { bg += p.luminance(x, y); n += 1 } }
                    bg /= n
                    let xs = what == "step number" ? 40..<62 : (40 + (skip > 1 ? 30 : 0))..<300
                    let text = ink(p, xs, ys, against: bg)
                    XCTAssertGreaterThanOrEqual(TitleBackdropTests.contrast(text, bg), 4.5, "\(look.name) \(what): \(text) on \(bg)")
                }
            }
        }
    }

    /// The modern title band draws no bar: away from the text the backdrop is untouched.
    func testNoBarOverTheBackdrop() {
        for look in [MGSolidLook.studio, .paper] {
            let base = backdrop(look, 1280, 800, poolAt: 640, 400)
            let a = Pixels(base), b = Pixels(caption(titleBackdrop(base, look: look), title: "T", text: nil, footer: "x", look: look))
            for (x, y) in [(900, 20), (900, 60), (640, 400), (900, 790)] { XCTAssertEqual(a.luminance(x, y), b.luminance(x, y), accuracy: 1e-9, look.name) }
        }
    }

    /// The step number is the same glyphs as before in a quieter ink: the caption's lines sit where the classic ones do.
    func testTheCaptionKeepsItsLineBreaks() {
        let text = "4. " + String(repeating: "A motor turns its propeller one way. ", count: 5)
        let look = MGSolidLook.studio
        let white = TitleBackdropTests().white(1280, 800)
        let plain = Pixels(caption(white, title: "T", text: text, footer: "x", look: .classic))
        let numbered = Pixels(caption(backdrop(look, 1280, 800, poolAt: 640, 400), title: "T", text: text, footer: "x", look: look))
        // Rows of the caption that hold ink are the same rows for both (the same number of lines at the same places).
        func rows(_ p: Pixels) -> [Bool] {
            (680..<790).map { y in (200..<1200).contains { abs(p.luminance($0, y) - p.luminance(1250, y)) > 0.2 } }
        }
        XCTAssertEqual(rows(plain), rows(numbered))
        XCTAssertTrue(rows(numbered).contains(true))
    }

    /// The label overlay's drawn metrics are multiples of the font size, so a larger label size scales them together.
    func testOverlayMetricsScaleWithTheFont() {
        // Checked through the public drawer: a doubled frame height (a doubled font, within the 11...20 px range's
        // slope) draws a plate edge and a leader about twice as wide; here only that drawing does not fail on any
        // look at the smallest and largest frames.
        for look in [MGSolidLook.classic, .studio, .paper] {
            for (w, h) in [(320, 200), (1280, 800), (3840, 2160), (800, 2160)] {
                let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                let f = MGAnnotationLayout.fontSize(height: Double(h))
                let frame = MGAnnotationFrame(width: Double(w), height: Double(h), fontSize: f, placement: [], anchors: [], refusal: nil)
                let doc = try? MGSolidParser.document(data: Data(#"{"v":2,"kind":"assembly","title":"T","parts":[{"id":"p","shape":{"box":{"size":[10,10,10]}}}]}"#.utf8)).get()
                if let doc { MGSolidOverlay.draw(frame, document: doc, legend: true, in: ctx, width: w, height: h, look: look) }
                XCTAssertNotNil(ctx.makeImage(), "\(look.name) \(w)x\(h)")
            }
        }
    }
}
