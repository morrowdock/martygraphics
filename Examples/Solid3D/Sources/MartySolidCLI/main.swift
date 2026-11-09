// SPDX-License-Identifier: Apache-2.0
// marty-solid: check or render ANY solid assembly JSON file or explainer document (for authors and for AI models that
// write them). The check reports, the render plan and the reason catalog live in the MartyGraphics library; this tool
// adds files and pixels.
import AppKit
import AVFoundation
import SwiftUI
import CoreText
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers
import MartyGraphics

enum CLIError: Error, CustomStringConvertible {
    case usage, invalid(String)
    var description: String {
        switch self {
        case .usage: return """
            Usage: marty-solid check FILE.json [--strict] [--patch PATCH.json] [--component C.json ...]
                   marty-solid render FILE.json NEW_DIR [--size WxH] [--no-loop] [--loop-fps 10|30] [--no-story] [--story-fps 10|30]
                                      [--snapshots] [--component C.json ...]
                   marty-solid snapshot check SNAPSHOT.json [--component C.json ...]
                   marty-solid components [--component C.json ...]
                   marty-solid component check C.json [--component OTHER.json ...] [--with NAME=VALUE ...]
                   marty-solid reasons
                   marty-solid version
            """
        case .invalid(let s): return s
        }
    }
}

/// A source file as read: its bytes and the report's `file` facts (lines, SHA-256).
struct Loaded { let data: Data; let source: MGSolidSource }

/// A file larger than the format allows is refused like the parser would refuse it (`assembly.bytes`).
/// A file over the format's size: its size in bytes, exact when it is the file size (not the bytes read past the limit).
struct TooLarge: Error {
    var bytes: Int
    var exact = true
    /// The limit detail of the refusal (`field: "document"`, unit bytes; at least `bytes` when only that many were read).
    func detail(limit: Int) -> MGSolidLimitDetail {
        MGSolidLimitDetail(field: "document", actual: bytes, limit: limit, unit: "bytes", bound: exact ? .exact : .atLeast)
    }
}

func load(_ path: String) throws -> Loaded {
    // Never read more than the format allows: refuse non-regular files (FIFOs, devices) and oversized files first.
    let attrs = try FileManager.default.attributesOfItem(atPath: path)
    guard (attrs[.type] as? FileAttributeType) == .typeRegular else { throw CLIError.invalid("Not a regular file: \(path)") }
    let size = (attrs[.size] as? NSNumber)?.intValue ?? 0
    guard size <= MGSolidLimits.bytes else { throw TooLarge(bytes: size) }
    let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
    defer { try? handle.close() }
    let data = try handle.read(upToCount: MGSolidLimits.bytes + 1) ?? Data()
    guard data.count <= MGSolidLimits.bytes else { throw TooLarge(bytes: data.count, exact: false) }
    return Loaded(data: data, source: MGSolidSource(data: data))
}

/// A document file as read for `check` and `render`: at most 128 KiB plus one byte (the explainer limit), regular files
/// only. The top-level `kind` picks the path: `explainer` is an explainer; `lesson` (an engine format this tool does not
/// take) is `kind.unsupported`; anything else (no `kind`, `assembly`, another value) keeps the assembly path and its
/// reasons, unchanged.
struct Document { let data: Data; let kind: String? }

/// `explainer.bytes` for a file read only to one byte past the explainer limit: the limit detail gives the file's own
/// size (the library saw only the bytes read). Nil for a file within the limit.
func explainerTooLarge(_ path: String, _ data: Data) -> MGExplainerIssue? {
    guard data.count > MGExplainerLimits.rawBytes else { return nil }
    let size = ((try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? NSNumber)?.intValue
    var e = MGExplainerIssue("explainer.bytes", view: .header)
    e.limit = MGSolidLimitDetail(field: "document", actual: size ?? data.count, limit: MGExplainerLimits.rawBytes, unit: "bytes",
                                 bound: size == nil ? .atLeast : .exact)
    return e
}

func loadDocument(_ path: String) throws -> Document {
    let attrs = try FileManager.default.attributesOfItem(atPath: path)
    guard (attrs[.type] as? FileAttributeType) == .typeRegular else { throw CLIError.invalid("Not a regular file: \(path)") }
    let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
    defer { try? handle.close() }
    let data = try handle.read(upToCount: MGExplainerLimits.rawBytes + 1) ?? Data()
    guard data.count <= MGExplainerLimits.rawBytes else {
        // Too large to parse: name the explainer limit when the text says it is one, else the assembly limit.
        return Document(data: data, kind: data.range(of: Data(#""explainer""#.utf8)) != nil ? "explainer" : nil)
    }
    var kind: String?
    switch MGExplainer.topLevelKind(data) {
    case .string(let k)?: kind = k
    case nil: kind = nil
    default: kind = "assembly"   // a `kind` that is not a string: the assembly path refuses it as before
    }
    return Document(data: data, kind: kind)
}

/// `{"ok": false, "reason": "kind.unsupported", "engine"}`.
func unsupportedKind() -> Int32 {
    print(json(stamped(["ok": .bool(false), "reason": .string("kind.unsupported")])))
    return 1
}

/// The engine identity plus the SHA-256 of this executable, so a caller can name the exact build without git.
let engine: MGJSON = {
    var o = MGEngine.identity.objectValue ?? [:]
    let exe = Bundle.main.executableURL.flatMap { try? Data(contentsOf: $0, options: .mappedIfSafe) }
    let hash: MGJSON = exe.map { MGJSON.string(SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined()) } ?? .null
    o["executableSHA256"] = hash
    return .object(o)
}()

/// Pretty-printed JSON with sorted keys (the report writer), for a value built here.
func json(_ object: MGJSON) -> String { MGSolidReport.text(object) }

/// A string, or null.
func opt(_ s: String?) -> MGJSON { s.map(MGJSON.string) ?? .null }

/// Adds the `engine` object to a JSON object.
func stamped(_ fields: [String: MGJSON]) -> MGJSON {
    var o = fields
    o["engine"] = engine
    return .object(o)
}

/// The built-in components plus extra definitions from `--component` files (each validated and compiled on its own,
/// in order, so a later file may use an earlier one). A refused file is reported like a refused model.
struct LibraryRefused: Error { let report: MGJSON }

func library(_ files: [String]) throws -> MGSolidLibrary {
    var lib = MGSolidLibrary.builtIn
    for path in files {
        let src: Loaded
        do { src = try load(path) } catch let big as TooLarge {
            let l = big.detail(limit: MGSolidComponentLimits.bytes)
            throw LibraryRefused(report: .object(["ok": .bool(false), "reason": .string("component.bytes"), "part": .null, "component": .string(path),
                                                  "limit": l.json, "repair": .string(l.repair)]))
        }
        if case .failure(let issue) = lib.register(src.data) {
            var o: [String: MGJSON] = ["ok": .bool(false), "reason": .string(issue.reason), "part": opt(issue.part), "component": .string(path)]
            o.merge(MGSolidReport.refusalDetail(issue)) { a, _ in a }
            throw LibraryRefused(report: .object(o))
        }
    }
    return lib
}

/// The check report (`MGSolidReport`): `--strict` is the model-harness profile (owner D3), whose refusals still print
/// the full report so the author can repair from it. `--patch` reports on the base with the patch applied.
func check(_ path: String, patch patchPath: String?, _ lib: MGSolidLibrary, strict: Bool = false) throws -> Int32 {
    let profile: MGSolidProfile = strict ? .strict : .standard
    let doc = try loadDocument(path)
    switch doc.kind {
    case "explainer"?:
        guard patchPath == nil else { throw CLIError.usage }
        // ONE report for both views (`MGExplainerReport`); `--strict` adds the strict set, and the report is printed in full.
        if let big = explainerTooLarge(path, doc.data) {
            print(json(MGExplainerReport.refused(big, profile: nil, source: nil, engine: engine).json)); return 1
        }
        let report = MGExplainerReport.check(data: doc.data, library: lib, profile: profile, engine: engine)
        print(report.text)
        return report.exitCode
    case "lesson"?: return unsupportedKind()
    default: break
    }
    let src: Loaded
    do { src = try load(path) } catch let big as TooLarge {
        var r = MGSolidReport.refused(MGSolidIssue("assembly.bytes", limit: big.detail(limit: MGSolidLimits.bytes)), engine: engine).json.objectValue ?? [:]
        if patchPath != nil { r["patch"] = .object(["applied": .bool(false), "fields": .array([]), "refusedAt": .string("base")]) }
        print(json(.object(r))); return 1
    }
    let report: MGSolidReport
    if let patchPath {
        // A patch over the limit is refused by the library (`patch.bytes`) without reading more than one byte past it.
        let patch: Data
        var big: TooLarge?
        do { patch = try load(patchPath).data } catch let e as TooLarge { patch = Data(count: MGSolidLimits.bytes + 1); big = e }
        report = MGSolidReport.check(data: src.data, patch: patch, library: lib, profile: profile, engine: engine)
        // The library saw only one byte past the limit: the limit detail gives the file's own size.
        if let big, report.reason == "patch.bytes", case .object(var o) = report.json {
            let l = big.detail(limit: MGSolidLimits.bytes)
            o["limit"] = l.json; o["repair"] = .string(l.repair)
            print(MGSolidReport.text(.object(o)))
            return report.exitCode
        }
    } else {
        report = MGSolidReport.check(data: src.data, library: lib, profile: profile, engine: engine)
    }
    print(report.text)
    return report.exitCode
}

/// The catalog as one line of JSON: ids, one-line descriptions, parameters with defaults and ranges, inner parts, anchors.
func components(_ lib: MGSolidLibrary) -> Int32 {
    print(lib.catalog().canonicalString)
    return 0
}

/// Validates a component definition (closed keys, parameters, expressions, references, and a compile of the component
/// on its own at its defaults), then instantiates it with `--with` values and runs the same engine checks as `check`.
func componentCheck(_ path: String, _ base: MGSolidLibrary, with values: [String: Double]) throws -> Int32 {
    let src: Loaded
    do { src = try load(path) } catch let big as TooLarge {
        let l = big.detail(limit: MGSolidComponentLimits.bytes)
        print(json(stamped(["ok": .bool(false), "reason": .string("component.bytes"), "part": .null, "limit": l.json, "repair": .string(l.repair)]))); return 1
    }
    let file: MGJSON = .object(["lines": .number(Double(src.source.lines)), "sha256": .string(src.source.sha256)])
    let withJSON = MGJSON.object(values.mapValues { MGJSON.number($0) })
    var lib = base
    let component: MGSolidComponent
    switch lib.register(src.data) {
    case .failure(let issue):
        var o: [String: MGJSON] = ["ok": .bool(false), "reason": .string(issue.reason), "part": opt(issue.part), "file": file]
        o.merge(MGSolidReport.refusalDetail(issue)) { a, _ in a }
        print(json(stamped(o)))
        return 1
    case .success(let c): component = c
    }
    switch lib.instantiate(component.id, with: values) {
    case .failure(let issue):
        var o: [String: MGJSON] = ["ok": .bool(false), "reason": .string(issue.reason), "part": opt(issue.part),
                                   "id": .string(component.id), "with": withJSON, "file": file]
        o.merge(MGSolidReport.refusalDetail(issue)) { a, _ in a }
        print(json(stamped(o)))
        return 1
    case .success(let doc):
        let c = MGSolidReport.Checks(doc)
        let tris = doc.assembly.parts.reduce(0) { $0 + $1.mesh.triangleCount }
        let reason = c.refusal
        let defaults = MGJSON.object(Dictionary(uniqueKeysWithValues: component.params.map { ($0.name, MGJSON.number(values[$0.name] ?? $0.defaultValue)) }))
        print(json(stamped(["ok": .bool(reason == nil), "reason": opt(reason), "id": .string(component.id),
                            "with": defaults, "catalogEntry": component.catalogEntry,
                            "use": .object(["id": .string("a"), "use": .string(component.id), "with": defaults]),
                            "instance": .object(["parts": .number(Double(doc.assembly.parts.count)), "triangles": .number(Double(tris)),
                                                 "ratios": .object(doc.ratios.mapValues { d -> MGJSON in d.isFinite ? .number(d) : .null }), "checks": c.json]),
                            "file": .object(["lines": .number(Double(src.source.lines)), "bytes": .number(Double(src.data.count)),
                                             "sha256": .string(src.source.sha256)])])))
        return reason == nil ? 0 : 1
    }
}

// MARK: render

/// Opacity of the dark backdrop behind the title band (title, legend line and the overlay's legend corner).
/// Chosen so that every stroke row of thin anti-aliased text keeps at least 4.5:1 over a pure white or emissive render.
/// The caption band uses `captionBackdropOpacity` for the same reason.
let captionBackdropOpacity: CGFloat = 0.84
let titleBackdropOpacity: CGFloat = 0.88
/// Height (px at 1280 wide, scaled with the width) over which the backdrop fades out below the title band.
let titleBackdropFadePixels: CGFloat = 28

/// The image with a dark backdrop over the title band, the same kind of protection the caption band has: black at
/// `titleBackdropOpacity` over the band (`MGSolidRenderPlan.titleBandPixels`, scaled with the width), then a soft fade
/// to clear over `titleBackdropFadePixels`. Drawn under every text of the band (title, legend line, the overlay's
/// legend corner, whose whole rectangle is covered also where a tall frame puts it below the band), so geometry that
/// reaches into the band never washes the text out: white title text keeps a contrast
/// of at least 4.5:1 even over a pure white render. Loop frames draw no title or legend text and get none.
func titleBackdrop(_ image: CGImage) -> CGImage {
    let w = image.width, h = image.height
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    let s = CGFloat(w) / 1280
    let band = CGFloat(MGSolidRenderPlan.titleBandPixels) * s, fade = titleBackdropFadePixels * s
    let top = CGFloat(h)
    ctx.setFillColor(CGColor(gray: 0, alpha: titleBackdropOpacity))
    ctx.fill(CGRect(x: 0, y: top - band, width: CGFloat(w), height: band))
    let colors = [CGColor(gray: 0, alpha: titleBackdropOpacity), CGColor(gray: 0, alpha: 0)] as CFArray
    if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceGray(), colors: colors, locations: [0, 1]) {
        ctx.saveGState()
        ctx.clip(to: CGRect(x: 0, y: top - band - fade, width: CGFloat(w), height: fade))
        ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: top - band), end: CGPoint(x: 0, y: top - band - fade), options: [])
        ctx.restoreGState()
    }
    // The overlay's legend corner (`MGAnnotationLayout.legendRect`) scales with the frame height, so in a tall frame it
    // reaches below the title band: its whole rectangle gets the same backdrop, then the same fade below it.
    let r = MGAnnotationLayout.legendRect(width: Double(w), height: Double(h))
    let legendBottom = CGFloat(r.y + r.height)
    if legendBottom > band {
        let x = CGFloat(r.x), lw = CGFloat(r.width)
        ctx.setFillColor(CGColor(gray: 0, alpha: titleBackdropOpacity))
        ctx.fill(CGRect(x: x, y: top - legendBottom, width: lw, height: legendBottom - band))
        if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceGray(), colors: colors, locations: [0, 1]) {
            ctx.saveGState()
            ctx.clip(to: CGRect(x: x, y: top - legendBottom - fade, width: lw, height: fade))
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: top - legendBottom), end: CGPoint(x: 0, y: top - legendBottom - fade), options: [])
            ctx.restoreGState()
        }
    }
    return ctx.makeImage()!
}

/// Draws the title, the caption band, the footer (legend) line and the board line over `image`. Callers pass an image
/// that already has its title backdrop (`titleBackdrop`), drawn before any overlay text. `boardLineOpacity`: the board
/// line's opacity (with its backdrop); below 1 only while a story's board pane opens (`MGPaneSlide`).
func caption(_ image: CGImage, title: String, text: String?, footer: String, boardLine: String? = nil, boardLineOpacity: CGFloat = 1) -> CGImage {
    let w = image.width, h = image.height
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    func draw(_ s: String, _ size: CGFloat, _ weight: NSFont.Weight, x: CGFloat, y: CGFloat, alpha: CGFloat, maxWidth: CGFloat? = nil) {
        let font = NSFont.systemFont(ofSize: size, weight: weight) as CTFont
        let attr = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: NSColor(white: 1, alpha: alpha).cgColor])
        if let mw = maxWidth {
            let setter = CTFramesetterCreateWithAttributedString(attr)
            let path = CGPath(rect: CGRect(x: x, y: y, width: mw, height: size * 4), transform: nil)
            CTFrameDraw(CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), path, nil), ctx)
        } else {
            ctx.textPosition = CGPoint(x: x, y: y); CTLineDraw(CTLineCreateWithAttributedString(attr), ctx)
        }
    }
    let s = CGFloat(w) / 1280
    let band = CGFloat(MGSolidRenderPlan.captionBandPixels)
    // Titles stay on one line; a long title is truncated with an ellipsis instead of running off the edge.
    do {
        let font = NSFont.systemFont(ofSize: 28 * s, weight: .semibold) as CTFont
        let attr = NSAttributedString(string: title, attributes: [.font: font, .foregroundColor: NSColor.white.cgColor])
        let line = CTLineCreateWithAttributedString(attr)
        let dots = CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: [.font: font, .foregroundColor: NSColor.white.cgColor]))
        let fitted = CTLineCreateTruncatedLine(line, Double(CGFloat(w) - 80 * s), .end, dots) ?? line
        ctx.textPosition = CGPoint(x: 40 * s, y: CGFloat(h) - 64 * s); CTLineDraw(fitted, ctx)
    }
    if let t = text {
        ctx.setFillColor(CGColor(gray: 0, alpha: captionBackdropOpacity)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: Int(band * s)))
        draw(t, 20 * s, .regular, x: 40 * s, y: 30 * s, alpha: 0.95, maxWidth: CGFloat(w) - 80 * s)
    }
    draw(footer, 12 * s, .medium, x: 40 * s, y: CGFloat(h) - 92 * s, alpha: 0.85)
    // The board's text when its pane is not drawn (an explainer beat whose board shows only text): one line in the
    // title band, under the legend line, in the board's ink, truncated with an ellipsis.
    if let line = boardLine, boardLineOpacity > 0 {
        ctx.saveGState(); defer { ctx.restoreGState() }
        if boardLineOpacity < 1 { ctx.setAlpha(boardLineOpacity) }
        // Semibold and full ink: the thin lower stems of a medium weight anti-alias below 4.5:1 at small sizes.
        let font = NSFont.systemFont(ofSize: 15 * s, weight: .semibold) as CTFont
        let ink = CGColor(srgbRed: 0.80, green: 0.86, blue: 1.0, alpha: 1)
        let attr = NSAttributedString(string: line, attributes: [.font: font, .foregroundColor: ink])
        let dots = CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: [.font: font, .foregroundColor: ink]))
        let fitted = CTLineCreateTruncatedLine(CTLineCreateWithAttributedString(attr), Double(CGFloat(w) - 80 * s), .end, dots)
            ?? CTLineCreateWithAttributedString(attr)
        // Its own backdrop: in a tall frame the line can reach below the title band into a bright 3D pane, so the
        // line's typographic bounds (plus a small margin) get the title backdrop's darkness before the text is drawn.
        let base = CGPoint(x: 40 * s, y: CGFloat(h) - 118 * s)
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(fitted, &ascent, &descent, &leading))
        let pad = 6 * s
        ctx.setFillColor(CGColor(gray: 0, alpha: titleBackdropOpacity))
        ctx.fill(CGRect(x: base.x - pad, y: base.y - descent - pad, width: width + 2 * pad, height: ascent + descent + 2 * pad))
        ctx.textPosition = base; CTLineDraw(fitted, ctx)
    }
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, _ url: URL) throws {
    guard let d = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { throw CLIError.invalid("png") }
    CGImageDestinationAddImage(d, image, nil)
    guard CGImageDestinationFinalize(d) else { throw CLIError.invalid("png finalize") }
}

/// Only the document legend (text and notes) in the legend corner, with no labels.
func legendOnly(_ image: CGImage, _ doc: MGSolidDocument) -> CGImage {
    let w = image.width, h = image.height
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    MGSolidOverlay.drawLegend(document: doc, in: ctx, width: w, height: h)
    return ctx.makeImage()!
}

/// The annotation overlay (labels, leaders, value texts, callouts, legend) drawn over a rendered frame.
func overlaid(_ image: CGImage, _ frame: MGAnnotationFrame, _ doc: MGSolidDocument) -> CGImage {
    let w = image.width, h = image.height
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    MGSolidOverlay.draw(frame, document: doc, legend: true, in: ctx, width: w, height: h)
    return ctx.makeImage()!
}

func scaled(_ image: CGImage, width: Int) -> CGImage {
    let h = Int((Double(image.height) * Double(width) / Double(image.width)).rounded())
    let ctx = CGContext(data: nil, width: width, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.interpolationQuality = .high; ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: h))
    return ctx.makeImage()!
}

/// H.264 MP4 writer (AVFoundation, no installs): frames at a fixed rate, presentation time = frame index / rate.
final class MovieWriter {
    let writer: AVAssetWriter
    let input: AVAssetWriterInput
    let adaptor: AVAssetWriterInputPixelBufferAdaptor
    let width: Int, height: Int, fps: Int32
    private(set) var frames: Int64 = 0

    /// H.264 4:2:0 needs even sizes: an odd width or height is written one pixel smaller (the frame is scaled).
    static func evenSize(_ w: Int, _ h: Int) -> (width: Int, height: Int) { (w - w % 2, h - h % 2) }

    init(url: URL, width: Int, height: Int, fps: Int32) throws {
        (self.width, self.height) = MovieWriter.evenSize(width, height)
        self.fps = fps
        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        // About 0.2 bits per pixel per frame, at least 2 Mbit/s: sharp edges on dark studio backgrounds.
        let bitrate = max(2_000_000, min(40_000_000, Int(Double(self.width * self.height) * Double(fps) * 0.2)))
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: self.width, AVVideoHeightKey: self.height,
            // No frame reordering (no B-frames): every sample's presentation time is its decode time, frame k at k / fps.
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: bitrate, AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                                              AVVideoMaxKeyFrameIntervalKey: Int(fps) * 2, AVVideoAllowFrameReorderingKey: false],
        ])
        input.expectsMediaDataInRealTime = false
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: self.width,
            kCVPixelBufferHeightKey as String: self.height,
        ])
        writer.add(input)
        guard writer.startWriting() else { throw CLIError.invalid("mp4: \(writer.error.map { "\($0)" } ?? "start failed")") }
        writer.startSession(atSourceTime: .zero)
    }

    /// Longest wait for the encoder to take a frame (seconds).
    static let readyTimeout = 60.0

    /// Waits until `ready()`; throws as soon as `status()` is `.failed` or `.cancelled` (disk full, a cancel) and after
    /// `timeout` seconds, so a stopped writer never hangs the render.
    static func waitUntilReady(timeout: Double = MovieWriter.readyTimeout, ready: () -> Bool, status: () -> AVAssetWriter.Status,
                               error: () -> Error? = { nil }) throws {
        let start = Date()
        while !ready() {
            switch status() {
            case .failed: throw CLIError.invalid("mp4: writer failed: \(error().map { "\($0)" } ?? "no error given")")
            case .cancelled: throw CLIError.invalid("mp4: writer cancelled")
            default: break
            }
            guard Date().timeIntervalSince(start) < timeout else { throw CLIError.invalid("mp4: writer not ready after \(timeout) s") }
            Thread.sleep(forTimeInterval: 0.002)
        }
    }

    /// Stops the file (no partial MP4 is finished) and returns the error to throw; the render then removes its directory.
    private func abandon(_ e: Error) -> Error {
        if writer.status == .writing { writer.cancelWriting() }
        return e
    }

    func append(_ image: CGImage) throws {
        do {
            try MovieWriter.waitUntilReady(ready: { input.isReadyForMoreMediaData }, status: { writer.status }, error: { writer.error })
        } catch { throw abandon(error) }
        var buffer: CVPixelBuffer?
        guard let pool = adaptor.pixelBufferPool, CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let pb = buffer else {
            throw abandon(CLIError.invalid("mp4 pixel buffer"))
        }
        CVPixelBufferLockBaseAddress(pb, [])
        let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pb), width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: CVPixelBufferGetBytesPerRow(pb), space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        ctx?.interpolationQuality = .high
        ctx?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        CVPixelBufferUnlockBaseAddress(pb, [])
        guard adaptor.append(pb, withPresentationTime: CMTime(value: frames, timescale: fps)) else {
            throw abandon(CLIError.invalid("mp4 frame \(frames): \(writer.error.map { "\($0)" } ?? "\(writer.status.rawValue)")"))
        }
        frames += 1
    }

    /// Ends the file: the last frame lasts one frame period, so the movie is exactly frames / fps seconds long.
    func finish() throws {
        guard writer.status == .writing else { throw abandon(CLIError.invalid("mp4: writer stopped before the end (\(writer.status.rawValue))")) }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(value: frames, timescale: fps))
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        guard writer.status == .completed else { throw CLIError.invalid("mp4: \(writer.error.map { "\($0)" } ?? "failed")") }
    }
}

/// The story manifest's per-beat records with the hold camera (the camera of the beat's last frame), the number of
/// annotations off view in that frame plus the focus samples still hidden (absent when the beat draws no annotation and
/// has no tested focus), whether the beat cut instead of moving (`cut`, with `cutReason` `blocked` or `motion`; the
/// move's `path`, `pathReason`, `blockedBy` and `moveSeconds` come from `MGStoryPlan.manifestFields`), the pane layout
/// change into the beat (`layout`, `MGPaneSlide.manifestJSON`; only where the layout changes), and the unblocked-focus
/// fields of the beat (`autoGhost`, `occluded`, `focusSamples`, `view`; only for a tested focus).
func storyBeats(_ beats: MGJSON?, _ cameras: [Int: MGSolidCamera], _ offView: [Int: Int], clear: [Int: MGSolidClearView] = [:],
                cuts: [Int: String] = [:], layout: [Int: MGJSON] = [:]) -> MGJSON? {
    guard case .array(let list)? = beats else { return beats }
    return .array(list.enumerated().map { k, v -> MGJSON in
        guard case .object(var o) = v else { return v }
        if let c = cameras[k] { o["camera"] = c.manifestJSON }
        if let n = offView[k] { o["offView"] = .number(Double(n)) }
        o["cut"] = .bool(cuts[k] != nil)
        if let why = cuts[k] { o["cutReason"] = .string(why) }
        if let l = layout[k] { o["layout"] = l }
        if let c = clear[k] { o.merge(c.manifestFields) { a, _ in a } }
        return .object(o)
    })
}

/// A still's manifest `offView`: annotations whose anchor is outside the view, plus the focus samples still hidden
/// behind another part (`MGSolidClearView.occludedSamples`). Nil when the still draws no annotation and has no tested focus.
func offViewCount(annotations: Int?, clear: MGSolidClearView?) -> Int? {
    let hidden = clear.flatMap { $0.tested ? $0.occludedSamples : nil }
    guard annotations != nil || hidden != nil else { return nil }
    return (annotations ?? 0) + (hidden ?? 0)
}

func sha(_ url: URL) throws -> String { SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined() }

/// Renders the library's render plan (`MGSolidRenderPlan`): captioned stills, the loop GIF and MP4, the snapshot and the
/// manifest. Cameras come from the plan (`MGSolidRenderPlan.cameras`, the `MGSolidFraming` rule).
@MainActor func render(_ path: String, _ outPath: String, width: Int, height: Int, loop: Bool, loopRate: Int = 10,
                       story: Bool = true, storyRate: Int = MGStoryTiming.defaultRate,
                       snapshots: Bool = false, library lib: MGSolidLibrary) throws -> Int32 {
    let document = try loadDocument(path)
    switch document.kind {
    case "explainer"?: return try renderExplainer(path, document.data, outPath, width: width, height: height, loop: loop, loopRate: loopRate,
                                                  story: story, storyRate: storyRate, snapshots: snapshots, library: lib)
    case "lesson"?: return unsupportedKind()
    default: break
    }
    let src: Loaded
    do { src = try load(path) } catch let big as TooLarge {
        print(json(MGSolidReport.refused(MGSolidIssue("assembly.bytes", limit: big.detail(limit: MGSolidLimits.bytes)), engine: engine).json)); return 1
    }
    let doc: MGSolidDocument
    switch MGSolidParser.document(data: src.data, library: lib) {
    case .failure(let issue): print(json(MGSolidReport.refused(issue, engine: engine).json)); return 1
    case .success(let d): doc = d
    }
    // The story video's plan (one beat per step), before anything is written: a story over the frame cap is refused
    // and no directory is made.
    var storyPlan: MGStoryPlan?
    if story, !doc.steps.isEmpty {
        do { storyPlan = try MGStoryPlan(captions: doc.steps.indices.map { "\($0 + 1). \(doc.steps[$0].say)" }, spins: doc.steps.map(\.spin), fps: storyRate) }
        catch let e as MGSolidIssue { print(json(stamped(["ok": .bool(false), "reason": .string(e.reason)]))); return 1 }
    }
    let out = URL(fileURLWithPath: outPath, isDirectory: true)
    // Atomic "must not exist": creation fails if the directory appears in the meantime. The parent must exist.
    do { try FileManager.default.createDirectory(at: out, withIntermediateDirectories: false) }
    catch { throw CLIError.invalid("Cannot create a NEW output directory at \(out.path) (it exists, or its parent is missing)") }
    var finished = false
    defer { if !finished { try? FileManager.default.removeItem(at: out) } }  // never leave a half-written result
    _ = NSApplication.shared
    let r = MGSolidRenderer(document: doc)
    let sourceName = URL(fileURLWithPath: path).lastPathComponent
    let plan = MGSolidRenderPlan(doc, sourceName: sourceName, source: src.source, loop: loop, loopRate: loopRate)
    let cameras = plan.cameras(doc, width: Double(width), height: Double(height))
    var files: [MGJSON] = []
    var names: [String] = []
    var seconds = 0.0, frames = 0
    var previousFrame: MGAnnotationFrame?
    func shot(_ s: MGSolidShot, _ camera: MGSolidCamera, ghost: [String] = []) throws -> CGImage {
        // Each step shows its own section cuts, ghosts and annotations; other shots show the plain scene. Annotations
        // show on hero.png and the step stills only (`MGSolidShot.showsAnnotations`), and only where the engine
        // checked the pose (`checkedAnnotations`, inside the renderer and the frame). `ghost`: the still's automatic
        // ghosts (the unblocked-focus rule, `MGSolidFraming.clearView`).
        let view = doc.view(step: s.step).ghosting(ghost)
        if s.showsAnnotations { r.show(document: doc, view: view) } else { r.show(view) }
        r.highlight(Set(s.highlight), dimOthers: !s.highlight.isEmpty)
        r.apply(s.params)
        r.setCamera(camera)
        let t0 = Date()
        guard let raw = r.render(width: width, height: height) else { throw CLIError.invalid("render failed (no Metal device?)") }
        seconds += Date().timeIntervalSince(t0); frames += 1
        // A shot with a title (every still) gets the title backdrop under its overlay text; loop frames have no text.
        let img = s.title != nil ? titleBackdrop(raw) : raw
        guard s.showsAnnotations, !view.annotations.isEmpty else { return img }
        // The same placement function as the snapshot and the SwiftUI overlay; frames of one loop keep their places.
        let frame = MGSolidAnnotations.frame(document: doc, view: view, params: s.params, camera: r.camera, width: Double(width),
                                             height: Double(height), previous: previousFrame, highlight: s.highlight,
                                             caption: s.caption != nil, title: true)
        previousFrame = frame
        return overlaid(img, frame, doc)
    }
    func record(_ name: String, _ fields: [String: MGJSON]) throws {
        let u = out.appendingPathComponent(name)
        var o = fields
        o["file"] = .string(name)
        o["bytes"] = .number(Double((try Data(contentsOf: u)).count))
        o["sha256"] = .string(try sha(u))
        files.append(.object(o)); names.append(name)
    }
    for (k, s) in plan.stills.enumerated() {
        previousFrame = nil
        try autoreleasepool {
            let clear = cameras.clear[k]
            let img = caption(try shot(s, cameras.stills[k], ghost: clear.autoGhost), title: s.title ?? doc.title, text: s.caption, footer: plan.footer)
            try writePNG(img, out.appendingPathComponent(s.file))
            var fields: [String: MGJSON] = ["width": .number(Double(img.width)), "height": .number(Double(img.height)),
                                            "framing": .string(cameras.rules[k].rawValue)]
            // Step stills also record their camera (the story's hold camera for that step), the annotations off view plus
            // the focus samples still hidden, and the unblocked-focus fields.
            if s.step != nil {
                fields["camera"] = cameras.stills[k].manifestJSON
                var labels: Int?
                if s.showsAnnotations, !doc.view(step: s.step).annotations.isEmpty, let f = previousFrame {
                    labels = f.placement.filter(\.offView).count
                }
                if let n = offViewCount(annotations: labels, clear: clear) { fields["offView"] = .number(Double(n)) }
                fields.merge(clear.manifestFields) { a, _ in a }
            }
            try record(s.file, fields)
        }
    }
    if !plan.loop.isEmpty {
        previousFrame = nil
        // One render per loop frame: the MP4 gets every frame at full size, the GIF every (rate / 10)-th frame at 640 px.
        let gifFrames = Set(plan.gifFrameIndices), n = plan.gifFrameIndices.count
        let gifURL = out.appendingPathComponent("loop.gif"), mp4URL = out.appendingPathComponent("loop.mp4")
        let delay = MGSolidRenderPlan.loopDelaySeconds
        guard let gif = CGImageDestinationCreateWithURL(gifURL as CFURL, UTType.gif.identifier as CFString, n, nil) else { throw CLIError.invalid("gif") }
        CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        let movie = try MovieWriter(url: mp4URL, width: width, height: height, fps: Int32(plan.loopRate))
        for (k, s) in plan.loop.enumerated() {
            // One pool per frame (render, encode, GIF): SceneKit and CoreGraphics objects are freed every frame, so a
            // 360-frame loop does not grow memory.
            try autoreleasepool {
                let img = try shot(s, cameras.loop[k])
                try movie.append(img)
                guard gifFrames.contains(k) else { return }
                CGImageDestinationAddImage(gif, scaled(img, width: MGSolidRenderPlan.loopWidth),
                                           [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay, kCGImagePropertyGIFUnclampedDelayTime: delay]] as CFDictionary)
            }
        }
        guard CGImageDestinationFinalize(gif) else { throw CLIError.invalid("gif finalize") }
        try movie.finish()
        try record("loop.gif", ["width": .number(Double(MGSolidRenderPlan.loopWidth)), "frames": .number(Double(n)), "delaySeconds": .number(delay),
                                "loopSeconds": .number(MGSolidRenderPlan.loopSeconds), "framingScale": .number(cameras.loopScale)])
        try record("loop.mp4", ["codec": .string("h264"), "width": .number(Double(movie.width)), "height": .number(Double(movie.height)),
                                "frames": .number(Double(movie.frames)), "fps": .number(Double(plan.loopRate)),
                                "loopSeconds": .number(Double(movie.frames) / Double(plan.loopRate)), "framingScale": .number(cameras.loopScale)])
    }
    if let unrouted = storyPlan {
        // The steps in order, each with its caption, view (cuts, ghosts), highlight, annotations and camera; the camera
        // moves from the previous step's camera at the start of each step, and the step's spin plays as in the view.
        let stepStill = Dictionary(uniqueKeysWithValues: plan.stills.indices.compactMap { k in plan.stills[k].step.map { ($0, k) } })
        // The legend shows in every frame: for a document with annotations, in the overlay corner with its notes (also
        // during camera moves, while arrows are drawn and labels are not); otherwise in the footer line.
        let annotated = !doc.annotations.isEmpty
        let footer = annotated ? plan.footer : "\(doc.legend.text) · \(plan.footer)"
        let movie = try MovieWriter(url: out.appendingPathComponent("story.mp4"), width: width, height: height, fps: Int32(unrouted.fps))
        // During a step's hold the camera is exactly the step still's camera; only the move at the start of a step is in
        // between, and labels are hidden during that move.
        let beatCameras: [MGSolidCamera?] = doc.steps.indices.map { k in stepStill[k].map { cameras.stills[$0] } }
        let beatClear: [Int: MGSolidClearView] = Dictionary(uniqueKeysWithValues: doc.steps.indices.compactMap { k in
            stepStill[k].map { (k, cameras.clear[$0]) }
        })
        // Each step's view with its still's automatic ghosts (the hold), and the view its camera move draws: the same,
        // with the parts the previous step ghosts drawn as ghosts too (`MGSolidView.moving(from:_:)`).
        let holdViews = doc.steps.indices.map { k in doc.view(step: k).ghosting(beatClear[k]?.autoGhost ?? []) }
        let moveViews = doc.steps.indices.map { k in k == 0 ? holdViews[0] : holdViews[k].moving(from: holdViews[k - 1], doc.assembly) }
        // A camera move that would pass through a part the move draws takes a routed path (pull back, arc, both), or
        // cuts when no path is clear (`MGStoryPlan.routes`).
        // The move frames' poses come from the same shots (`MGStoryPlan.movePose`), so the router tests the parts
        // where the frames draw them.
        let routeShots = doc.steps.indices.map { k in
            MGStoryBeatShot(camera: beatCameras[k], params: MGSolidShot.step(doc, k)?.params ?? doc.defaults, view: moveViews[k], step: doc.steps[k])
        }
        let moves = MGStoryPlan.routes(doc, beats: routeShots, plan: unrouted)
        let story = unrouted.routed(moves)
        let cuts = story.cuts
        var shownView: MGSolidView?, settledStep: Int?
        var holdCamera: [Int: MGSolidCamera] = [:], holdOffView: [Int: Int] = [:]
        for i in 0..<story.frameCount {
            try autoreleasepool {
                let f = story.frame(i)
                guard let base = MGSolidShot.step(doc, f.beat), let camera = story.camera(frame: i, beatCameras: beatCameras, cuts: cuts) else {
                    throw CLIError.invalid("story step")
                }
                let step = doc.steps[f.beat]
                var s = base
                s.params = step.poseParameters(defaults: doc.defaults, spin: f.spin)
                // The camera move into a step also moves the parts from the previous step's pose to this one (real
                // renders at each blended pose, `MGStoryPlan.movePose`); a cut jumps. The hold shows the step's own pose.
                let moving = f.camera < 1 && f.beat > 0 && !cuts.contains(f.beat)
                if moving { s.params = MGStoryPlan.movePose(doc, beats: routeShots, f.beat, spin: f.spin, blend: f.camera) }
                // The step's view with its still's automatic ghosts in the hold; during the move, the move's view.
                let view = moving ? moveViews[f.beat] : holdViews[f.beat]
                if shownView != view {
                    shownView = view
                    r.show(document: doc, view: view)
                    r.highlight(Set(s.highlight), dimOthers: !s.highlight.isEmpty)
                }
                // A step's caption, labels and claims appear when its hold starts (after the camera move); labels keep
                // their places for the rest of the step.
                let holding = story.holds(frame: i, cuts: cuts)
                if !holding || settledStep != f.beat { previousFrame = nil }
                settledStep = holding ? f.beat : nil
                r.apply(s.params)
                r.setCamera(camera)
                let t0 = Date()
                guard let raw = r.render(width: width, height: height) else { throw CLIError.invalid("render failed (no Metal device?)") }
                seconds += Date().timeIntervalSince(t0); frames += 1
                var img = titleBackdrop(raw)   // under the legend corner, the labels and the title
                if holding { holdCamera[f.beat] = camera }
                if holding, !view.annotations.isEmpty {
                    let frame = MGSolidAnnotations.frame(document: doc, view: view, params: s.params, camera: r.camera, width: Double(width),
                                                         height: Double(height), previous: previousFrame, highlight: s.highlight,
                                                         caption: true, title: true)
                    previousFrame = frame
                    holdOffView[f.beat] = frame.placement.filter(\.offView).count
                    img = overlaid(img, frame, doc)   // labels and the legend corner
                } else if annotated {
                    img = legendOnly(img, doc)        // the legend and its notes, no labels
                }
                // During the move the caption band is empty: the caption names what the hold shows.
                try movie.append(caption(img, title: s.title ?? doc.title, text: story.caption(frame: i, cuts: cuts) ?? "", footer: footer))
            }
        }
        try movie.finish()
        var fields = story.manifestFields(cuts: cuts)
        // `offView` per beat: annotations off view in the hold plus the focus samples its still's camera leaves hidden.
        var beatOffView: [Int: Int] = [:]
        for k in doc.steps.indices {
            if let n = offViewCount(annotations: holdOffView[k], clear: beatClear[k]) { beatOffView[k] = n }
        }
        fields["beats"] = storyBeats(fields["beats"], holdCamera, beatOffView, clear: beatClear.filter { $0.value.tested },
                                     cuts: Dictionary(uniqueKeysWithValues: cuts.sorted().map { ($0, moves[$0]?.reason ?? "blocked") }))
        fields["codec"] = .string("h264"); fields["width"] = .number(Double(movie.width)); fields["height"] = .number(Double(movie.height))
        try record("story.mp4", fields)
    }
    try MGSolidRenderPlan.snapshot(doc).jsonData().write(to: out.appendingPathComponent("snapshot.json"))
    try record("snapshot.json", [:])
    let manifest = try MGSolidRenderPlan.manifest(doc, sourceName: sourceName, source: src.source, framesRendered: frames,
                                              secondsPerFrame: frames > 0 ? seconds / Double(frames) : 0, outputs: files, engine: engine)
    try Data(json(manifest).utf8).write(to: out.appendingPathComponent("manifest.json"))
    finished = true
    print(json(stamped(["ok": .bool(true), "output": .string(out.path), "files": .array(names.map { .string($0) })])))
    return 0
}

// MARK: explainer render

/// The board pane at `size` pixels: the presented 2D state with the beat's emphasis and table rows (the same input the
/// SwiftUI explainer view draws). `fit`: the reference pane the viewport is fitted for (a narrowed pane keeps its scale).
@MainActor func boardImage(_ scene: MGScene, _ view: MGExplainerBeatView, width: Int, height: Int, fit: CGSize? = nil) -> CGImage? {
    let size = CGSize(width: width, height: height)
    let r = ImageRenderer(content: Canvas { ctx, sz in MGCanvasRenderer.draw(MGExplainerBoard.input(scene, view: view, size: sz, fit: fit), in: ctx) }
        .frame(width: size.width, height: size.height))
    r.scale = 1
    return r.cgImage
}

/// The panes of one composite frame (`MGExplainerFrame.panes`): side by side, the board takes `boardShare` of the width
/// (`MGExplainerFrame.boardShare`, fitted to its content); stacked, the `primary` view gets 55 %. `board` is false in a
/// beat whose shown board has no non-text item (`MGExplainerSession.boardPane`): the solid then takes the whole area.
func paneRects(width w: Int, height h: Int, board: Bool, solid: Bool, primarySolid: Bool, boardShare: Double? = nil) -> (board: CGRect?, solid: CGRect?) {
    let p = MGExplainerFrame.panes(width: w, height: h, board: board, solid: solid, primarySolid: primarySolid, boardShare: boardShare)
    func cg(_ r: MGFrameRect?) -> CGRect? { r.map { CGRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height) } }
    return (cg(p.board), cg(p.solid))
}

/// A pane rect as the engine's whole-pixel rect (`MGExplainerFrame.panes` gives whole pixels).
func frameRect(_ r: CGRect) -> MGFrameRect { MGFrameRect(x: Int(r.minX), y: Int(r.minY), width: Int(r.width), height: Int(r.height)) }

/// One composite: the panes on a dark board, then the title, the caption band and the legend line (`caption`).
/// `boardLine`: the board's text when its pane is not drawn (`MGExplainerBoardPane.line`), shown in the title band.
/// An image whose size differs from its pane (a board during a story's pane slide, `MGPaneSlide`) is drawn at its own
/// size, centred in the pane and clipped to it; `boardOpacity` and `boardLineOpacity` fade the board and the board line.
func composite(width w: Int, height h: Int, board: CGImage?, solid: CGImage?, rects: (board: CGRect?, solid: CGRect?),
               title: String, caption text: String?, footer: String, boardLine: String? = nil,
               boardOpacity: CGFloat = 1, boardLineOpacity: CGFloat = 1) -> CGImage {
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: 0.05, green: 0.07, blue: 0.10, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    for (img, rect, opacity) in [(board, rects.board, boardOpacity), (solid, rects.solid, 1)] {
        guard let img, let rect, rect.width > 0, rect.height > 0, opacity > 0 else { continue }
        ctx.saveGState()
        // The corner radius never exceeds half the pane (a sliding pane can be a few pixels wide).
        let radius = min(14, rect.width / 2, rect.height / 2)
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)); ctx.clip()
        if opacity < 1 { ctx.setAlpha(opacity) }
        let iw = CGFloat(img.width), ih = CGFloat(img.height)
        ctx.draw(img, in: iw == rect.width && ih == rect.height ? rect
                 : CGRect(x: (rect.midX - iw / 2).rounded(), y: (rect.midY - ih / 2).rounded(), width: iw, height: ih))
        ctx.restoreGState()
    }
    return caption(titleBackdrop(ctx.makeImage()!), title: title, text: text, footer: footer, boardLine: boardLine,
                   boardLineOpacity: boardLineOpacity)
}

/// A pane rect as a CoreGraphics rect.
func cgRect(_ r: MGFrameRect?) -> CGRect? { r.map { CGRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height) } }

/// One beat of an explainer as the stills show it, kept for the story video: the view, the caption line, the board
/// image and pane layout, the board text that moved to the title band, the solid step and its framed camera.
struct ExplainerBeatShot {
    var view: MGExplainerBeatView
    var caption: String
    var board: CGImage?
    var rects: (board: CGRect?, solid: CGRect?)
    var boardLine: String?
    /// The beat's shown board state and the reference pane its board is drawn for (`boardImage`'s `fit`): a pane that
    /// opens in the next beat shows this state during the move (`MGPaneSlide`).
    var scene: MGScene?
    var fit: CGSize?
    var stepIndex: Int?
    var camera: MGSolidCamera?
    /// The beat's unblocked-focus result (automatic ghosts, hidden share); nil without a solid pane.
    var clear: MGSolidClearView?
}

/// `render` for an explainer: `beat-<n>.png` (one composite per beat), `board-0.png` and `solid-0.png` (the views before
/// the first beat), `loop.gif` and `loop.mp4` (the solid's loop), `story.mp4` (the beats in order), `snapshot-beat-<n>.json`
/// with `--snapshots`, and `manifest.json`.
@MainActor func renderExplainer(_ path: String, _ data: Data, _ outPath: String, width: Int, height: Int, loop: Bool, loopRate: Int = 10,
                                story: Bool = true, storyRate: Int = MGStoryTiming.defaultRate,
                                snapshots: Bool, library lib: MGSolidLibrary) throws -> Int32 {
    let source = MGSolidSource(data: data)
    if let big = explainerTooLarge(path, data) {
        print(json(MGExplainerReport.refused(big, profile: nil, source: nil, engine: engine).json)); return 1
    }
    let doc: MGExplainer
    switch MGExplainer.parse(data: data) {
    case .failure(let issue): print(json(MGExplainerReport.refused(issue, profile: nil, source: nil, engine: engine).json)); return 1
    case .success(let d): doc = d
    }
    let clock = MGManualClock()
    var session = MGExplainerSession(pacing: .speech, clock: clock, library: lib)
    if case .failure(let issue) = session.load(doc) {
        print(json(MGExplainerReport.refused(issue, profile: nil, source: nil, engine: engine).json)); return 1
    }
    // The story video's plan, before anything is written: a dry run of the beats on a separate session and clock gives
    // each beat's caption and spin; a story over the frame cap is refused and no directory is made.
    var storyPlan: MGStoryPlan?
    if story {
        let dryClock = MGManualClock()
        var dry = MGExplainerSession(pacing: .speech, clock: dryClock, library: lib)
        _ = dry.load(doc)
        var captions: [String] = [], spins: [Double] = []
        while let beat = dry.presented.beat, beat == captions.count {
            dryClock.advance(by: dry.motionRemaining)
            _ = dry.tick()
            captions.append("\(beat + 1). \(dry.caption ?? "")"); spins.append(dry.presented.step?.spin ?? 0)
            _ = dry.lineEnded(beat)
        }
        if !captions.isEmpty {
            do { storyPlan = try MGStoryPlan(captions: captions, spins: spins, fps: storyRate) }
            catch let e as MGSolidIssue { print(json(stamped(["ok": .bool(false), "reason": .string(e.reason)]))); return 1 }
        }
    }
    // The views before the first beat: every statement up to the first `say`.
    var before = MGExplainerSession(pacing: .speech, clock: MGManualClock(), library: lib)
    for st in doc.statements { if st["say"] != nil { break }; _ = before.feed(st.canonicalString + "\n") }
    let out = URL(fileURLWithPath: outPath, isDirectory: true)
    do { try FileManager.default.createDirectory(at: out, withIntermediateDirectories: false) }
    catch { throw CLIError.invalid("Cannot create a NEW output directory at \(out.path) (it exists, or its parent is missing)") }
    var finished = false
    defer { if !finished { try? FileManager.default.removeItem(at: out) } }
    _ = NSApplication.shared
    let sourceName = URL(fileURLWithPath: path).lastPathComponent
    // The legend of the whole explainer (every beat presented: a copy finishes now), the same legend `check` reports.
    // The session itself is at its first beat here, so its own legend would not yet hold the later beats' items.
    var whole = session
    _ = whole.finishNow()
    let legend = whole.legend
    // The legend line and its notes ("Arrow lengths are not to scale"), in every still and every story frame.
    let footer = (([legend.text] + legend.notes) + ["Rendered by the MartyGraphics engine from \(sourceName) (\(source.sizeText))"]).joined(separator: " · ")
    let title = session.title ?? ""
    let solidDoc = session.solid
    let renderer = solidDoc.map { d -> MGSolidRenderer in
        let r = MGSolidRenderer(document: d)   // annotations draw only for this document, through the one gate
        r.emphasis = .strong   // a highlight must read at a glance in a still, as on the 2D board
        return r
    }
    let primarySolid = (session.primary ?? (solidDoc != nil ? "solid" : "board")) == "solid"
    var files: [MGJSON] = [], names: [String] = []
    var seconds = 0.0, frames = 0
    var lastFraming: MGSolidFraming.Rule?
    var lastCamera: MGSolidCamera?
    var lastOffView: Int?   // annotations of the last solid image whose anchor was outside the pane (nil: none drawn)
    var lastClear: MGSolidClearView?   // the unblocked-focus result of the last framed solid image
    var shownView: MGSolidView?
    var previousFrame: MGAnnotationFrame?
    /// `stepIndex`: the solid step the beat shows (its focus frames the pane, `MGSolidFraming`); nil for the plain view.
    /// `spin`: the played fraction of the beat's spin (1: the beat's end pose, as in a still). `camera`: the story
    /// video's camera for this frame (`MGStoryPlan.camera(frame:beatCameras:)`); without it the pane is framed by
    /// `MGExplainerFrame.solidCamera` for the pane's own pixels, as in a still. `labels`: draw the annotation overlay
    /// (the story hides it while the camera moves). `stable`: keep label places from the last frame. `ghost`: the
    /// beat's automatic ghosts when `camera` is given (a still frames itself and takes its own, `lastClear`).
    /// `from`, `blend`: in a story camera move, the previous beat's pose placements and the move's progress (0...1);
    /// the parts move from that pose to this beat's pose with the camera.
    func solidImage(_ view: MGExplainerBeatView, _ rect: CGRect, spin: Double = 1, stepIndex: Int? = nil, camera: MGSolidCamera? = nil,
                    labels: Bool = true, stable: Bool = false, ghost: [String] = [], from: [String: MGTransform]? = nil,
                    blend: Double = 1, moveFrom: MGSolidView? = nil, movePose: MGPoseParameters? = nil) throws -> CGImage? {
        guard let r = renderer, let d = solidDoc else { return nil }
        let pane = frameRect(rect)
        var params = MGExplainerFrame.pose(d, view: view, spin: spin)
        if let from, blend < 1 { params.placements = MGStoryPlan.placements(d.assembly, from: from, to: params.placements, blend) }
        // A story move frame: the pose the move router tested (`MGStoryPlan.movePose`).
        if let movePose { params = movePose }
        var framed: MGSolidClearView?
        if camera == nil { framed = MGExplainerFrame.solidClearView(d, view: view, stepIndex: stepIndex, pane: pane) }
        // The beat's view with the automatic ghosts of the unblocked-focus rule (`MGSolidFraming.clearView`).
        var shown = (view.solid ?? d.view(step: nil)).ghosting(framed?.autoGhost ?? ghost)
        // A story camera move also draws the parts the previous beat ghosts as ghosts (`MGSolidView.moving(from:_:)`).
        if let moveFrom { shown = shown.moving(from: moveFrom, d.assembly) }
        r.apply(params)
        if !stable || shownView != shown {
            r.show(document: d, view: shown)
            r.highlight(Set(view.solidHighlight), dimOthers: !view.solidHighlight.isEmpty)
            r.highlightAnnotations(Set(view.annotations))
            shownView = shown; previousFrame = nil
        }
        if let camera {
            r.setCamera(camera)
        } else if let framed {
            r.setCamera(framed.camera)
            lastFraming = framed.rule; lastCamera = framed.camera; lastClear = framed
        }
        let t0 = Date()
        guard let img = r.render(width: pane.width, height: pane.height) else { throw CLIError.invalid("render failed (no Metal device?)") }
        seconds += Date().timeIntervalSince(t0); frames += 1
        lastOffView = nil
        guard labels, !shown.annotations.isEmpty else { previousFrame = nil; return img }
        // Labels, value texts and callouts from the same placement function as the snapshot and the SwiftUI overlay.
        let frame = MGSolidAnnotations.frame(document: d, view: shown, params: params, camera: r.camera, width: Double(img.width),
                                             height: Double(img.height), previous: stable ? previousFrame : nil, highlight: view.solidHighlight)
        previousFrame = frame
        lastOffView = frame.placement.filter(\.offView).count
        let ctx = CGContext(data: nil, width: img.width, height: img.height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
        MGSolidOverlay.draw(frame, document: d, legend: false, in: ctx, width: img.width, height: img.height)
        return ctx.makeImage()!
    }
    func record(_ name: String, _ fields: [String: MGJSON]) throws {
        let u = out.appendingPathComponent(name)
        var o = fields
        o["file"] = .string(name)
        o["bytes"] = .number(Double((try Data(contentsOf: u)).count))
        o["sha256"] = .string(try sha(u))
        files.append(.object(o)); names.append(name)
    }
    /// `framing`: the rule that framed the solid pane of this image, if it has one.
    func write(_ img: CGImage, _ name: String, framing: MGSolidFraming.Rule? = nil, fields extra: [String: MGJSON] = [:]) throws {
        try writePNG(img, out.appendingPathComponent(name))
        var fields: [String: MGJSON] = ["width": .number(Double(img.width)), "height": .number(Double(img.height))]
        if let framing { fields["framing"] = .string(framing.rawValue) }
        fields.merge(extra) { a, _ in a }
        try record(name, fields)
    }
    if doc.board != nil, let scene = before.state?.scene {
        let alone = paneRects(width: width, height: height, board: true, solid: false, primarySolid: false)
        let r = alone.board!
        try write(composite(width: width, height: height, board: boardImage(scene, MGExplainerBeatView(), width: Int(r.width), height: Int(r.height)),
                            solid: nil, rects: alone, title: title, caption: nil, footer: footer), "board-0.png")
    }
    if solidDoc != nil {
        let alone = paneRects(width: width, height: height, board: false, solid: true, primarySolid: true)
        lastFraming = nil
        try write(composite(width: width, height: height, board: nil, solid: try solidImage(MGExplainerBeatView(), alone.solid!, spin: 0),
                            rects: alone, title: title, caption: nil, footer: footer), "solid-0.png", framing: lastFraming)
    }
    var captions: [MGJSON] = []
    var shots: [ExplainerBeatShot] = []
    var k = 0
    while let beat = session.presented.beat, beat == k {
        // Each still shows the beat's settled state: the caption's 2D numbers appear once the board's motion has played.
        clock.advance(by: session.motionRemaining)
        _ = session.tick()
        let view = session.presented
        let caption = session.caption ?? ""
        captions.append(.string(caption))
        // The adaptive board pane: a beat whose shown board has only text gives the solid the whole frame, and the
        // board's text moves to the title band.
        let pane = session.boardPane
        // Side by side, the board pane's width fits the shown board's content (`MGExplainerFrame.boardShare`), drawn at
        // the scale of its reference pane.
        let both = pane.shown && solidDoc != nil
        let share = both ? MGExplainerFrame.boardShare(scene: session.state?.scene, width: width, height: height, primarySolid: primarySolid) : nil
        let area = MGExplainerFrame.contentArea(width: width, height: height)
        let fit = both && width >= height
            ? MGExplainerFrame.boardReferenceSize(areaWidth: Double(area.width), areaHeight: Double(area.height),
                                                  gap: MGExplainerFrame.paneGap(width: width), primarySolid: primarySolid) : nil
        let rects = paneRects(width: width, height: height, board: pane.shown, solid: solidDoc != nil, primarySolid: primarySolid, boardShare: share)
        let b = rects.board.flatMap { r in session.state.map { boardImage($0.scene, view, width: Int(r.width), height: Int(r.height), fit: fit) } } ?? nil
        lastFraming = nil; lastCamera = nil; lastOffView = nil; lastClear = nil
        let step = session.solidStep(forBeat: k)
        let sImg = try rects.solid.flatMap { try solidImage(view, $0, stepIndex: step) }
        let line = "\(k + 1). \(caption)"
        var extra: [String: MGJSON] = ["boardPane": .bool(rects.board != nil)]
        if let r = rects.board, rects.solid != nil { extra["boardShare"] = .number(Double(r.width) / Double(area.width - Int(MGExplainerFrame.paneGap(width: width)))) }
        if let c = lastCamera { extra["camera"] = c.manifestJSON }
        if let n = offViewCount(annotations: lastOffView, clear: lastClear) { extra["offView"] = .number(Double(n)) }
        if let c = lastClear { extra.merge(c.manifestFields) { a, _ in a } }
        try write(composite(width: width, height: height, board: b, solid: sImg, rects: rects, title: title, caption: line, footer: footer,
                            boardLine: pane.shown ? nil : pane.line),
                  "beat-\(k + 1).png", framing: lastFraming, fields: extra)
        shots.append(ExplainerBeatShot(view: view, caption: line, board: b, rects: rects, boardLine: pane.shown ? nil : pane.line,
                                       scene: session.state?.scene, fit: fit, stepIndex: step, camera: lastCamera, clear: lastClear))
        if snapshots, let d = solidDoc {
            let params = MGExplainerFrame.pose(d, view: view)
            let name = "snapshot-beat-\(k + 1).json"
            try MGSolidSnapshot.make(d, step: session.solidStep(forBeat: k), params: params).jsonData().write(to: out.appendingPathComponent(name))
            try record(name, [:])
        }
        _ = session.lineEnded(k)
        k += 1
    }
    if loop, let d = solidDoc, let r = renderer {
        // The solid's loop, framed and written like an assembly's: the GIF and the full-size MP4 from one render per frame.
        let plan = MGSolidRenderPlan(d, sourceName: sourceName, source: source, loop: true, loopRate: loopRate)
        let cameras = plan.cameras(d, width: Double(width), height: Double(height))
        let gifFrames = Set(plan.gifFrameIndices), n = plan.gifFrameIndices.count, gifURL = out.appendingPathComponent("loop.gif")
        let delay = MGSolidRenderPlan.loopDelaySeconds
        guard let gif = CGImageDestinationCreateWithURL(gifURL as CFURL, UTType.gif.identifier as CFString, n, nil) else { throw CLIError.invalid("gif") }
        CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        let movie = try MovieWriter(url: out.appendingPathComponent("loop.mp4"), width: width, height: height, fps: Int32(plan.loopRate))
        r.show(d.view(step: nil)); r.highlight([], dimOthers: false); shownView = nil
        for (k, shot) in plan.loop.enumerated() {
            // One pool per frame (render, encode, GIF), as for an assembly loop.
            try autoreleasepool {
                r.apply(shot.params)
                r.setCamera(cameras.loop[k])
                let t0 = Date()
                guard let img = r.render(width: width, height: height) else { throw CLIError.invalid("render failed (no Metal device?)") }
                seconds += Date().timeIntervalSince(t0); frames += 1
                try movie.append(img)
                guard gifFrames.contains(k) else { return }
                CGImageDestinationAddImage(gif, scaled(img, width: MGSolidRenderPlan.loopWidth),
                                           [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay, kCGImagePropertyGIFUnclampedDelayTime: delay]] as CFDictionary)
            }
        }
        guard CGImageDestinationFinalize(gif) else { throw CLIError.invalid("gif finalize") }
        try movie.finish()
        try record("loop.gif", ["width": .number(Double(MGSolidRenderPlan.loopWidth)), "frames": .number(Double(n)), "delaySeconds": .number(delay),
                                "framingScale": .number(cameras.loopScale)])
        try record("loop.mp4", ["codec": .string("h264"), "width": .number(Double(movie.width)), "height": .number(Double(movie.height)),
                                "frames": .number(Double(movie.frames)), "fps": .number(Double(plan.loopRate)),
                                "loopSeconds": .number(Double(movie.frames) / Double(plan.loopRate)), "framingScale": .number(cameras.loopScale)])
    }
    if let unrouted = storyPlan {
        // The dry run and the stills run the same session rules on the same document, so they present the same beats.
        guard unrouted.beats.count == shots.count, zip(unrouted.beats, shots).allSatisfy({ $0.caption == $1.caption }) else {
            throw CLIError.invalid("story: the beats differ from the stills")
        }
        // The beats in order: each frame is a real composite of the beat's board (its settled state, as in its still),
        // the solid at the beat's view, highlight and annotations, the caption and the legend line. During a beat's hold
        // the camera is exactly the beat's still camera (same layout, same pane pixels); only in the camera move at the
        // start of a beat is it in between, and labels are hidden during that move. The beat's spin plays.
        let movie = try MovieWriter(url: out.appendingPathComponent("story.mp4"), width: width, height: height, fps: Int32(unrouted.fps))
        let beatCameras = shots.map(\.camera)
        // A beat whose pane layout differs from the previous beat's (the board pane opens, closes or changes width)
        // slides the pane boundary between the two layouts over its camera move (`MGPaneSlide`): the solid pane eases
        // between its two rects, the camera is fitted to the current pane on every frame, and the board fades in or
        // out in its sliding pane. Only a move with no clear path still cuts (`MGStoryPlan.routes`).
        var slides: [Int: MGPaneSlide] = [:]
        for k in shots.indices.dropFirst() {
            let a = shots[k - 1].rects, b = shots[k].rects
            slides[k] = MGPaneSlide(from: (a.board.map(frameRect), a.solid.map(frameRect)), to: (b.board.map(frameRect), b.solid.map(frameRect)))
        }
        // A camera move that would pass through a part the move draws takes a routed path (pull back, arc, both), or
        // cuts when no path is clear (`MGStoryPlan.routes`). The move draws the beat's view with its automatic ghosts.
        // Each beat's solid view with its still's automatic ghosts (the hold); the move into a beat draws it with the
        // previous beat's ghosts too (`MGSolidView.moving(from:_:)`).
        let holdViews = solidDoc.map { d in shots.map { ($0.view.solid ?? d.view(step: nil)).ghosting($0.clear?.autoGhost ?? []) } } ?? []
        let routeShots = solidDoc.map { d in
            shots.indices.map { k in
                MGStoryBeatShot(camera: shots[k].camera, params: MGExplainerFrame.pose(d, view: shots[k].view),
                                view: k == 0 ? holdViews[0] : holdViews[k].moving(from: holdViews[k - 1], d.assembly), step: shots[k].view.step)
            }
        } ?? []
        let moves = solidDoc.map { d in MGStoryPlan.routes(d, beats: routeShots, plan: unrouted) } ?? [:]
        let story = unrouted.routed(moves)
        let cuts = story.cuts
        // An opening board pane shows the previous beat's board state during the move, as every move does (the beat's
        // own board and its claims appear when its hold starts), drawn for the new pane at the new layout's scale.
        var openingBoards: [Int: CGImage] = [:]
        for k in slides.keys.sorted() where slides[k]?.change == .open {
            guard let r = slides[k]?.toBoard, let scene = shots[k - 1].scene else { continue }
            openingBoards[k] = boardImage(scene, shots[k - 1].view, width: r.width, height: r.height, fit: shots[k].fit)
        }
        shownView = nil
        var settled: Int?   // the beat whose camera has arrived (its labels keep their places from frame to frame)
        var holdCamera: [Int: MGSolidCamera] = [:], holdOffView: [Int: Int] = [:]
        for i in 0..<story.frameCount {
            try autoreleasepool {
                let f = story.frame(i)
                let b = shots[f.beat]
                let holding = story.holds(frame: i, cuts: cuts)
                let moving = f.camera < 1 && f.beat > 0 && !cuts.contains(f.beat)
                // A pane slide: the panes at the move's share, and the move's camera fitted to the current solid pane.
                // Hold frames (share 1) keep the beat's own layout and its still's camera exactly.
                let slide = moving ? slides[f.beat] : nil
                let slid = slide.map { $0.panes(f.camera) }
                let rects: (board: CGRect?, solid: CGRect?) = slid.map { (cgRect($0.board), cgRect($0.solid)) } ?? b.rects
                var camera = story.camera(frame: i, beatCameras: beatCameras, cuts: cuts)
                if let slide, let c = camera { camera = slide.camera(c, f.camera) }
                let sImg = try rects.solid.flatMap { try solidImage(b.view, $0, spin: f.spin, stepIndex: b.stepIndex, camera: camera,
                                                                      labels: holding, stable: settled == f.beat, ghost: b.clear?.autoGhost ?? [],
                                                                      from: moving ? (shots[f.beat - 1].view.step?.pose ?? [:]) : nil,
                                                                      blend: f.camera, moveFrom: moving ? holdViews[f.beat - 1] : nil,
                                                                      movePose: moving ? solidDoc.map { MGStoryPlan.movePose($0, beats: routeShots, f.beat, spin: f.spin, blend: f.camera) } : nil) }
                settled = holding ? f.beat : nil
                if holding, let camera { holdCamera[f.beat] = camera; if let n = lastOffView { holdOffView[f.beat] = n } }
                // A beat's caption, labels and board claims appear when its hold starts. During the camera move the
                // caption band is empty and the board still shows the previous beat's state: in a pane slide, the
                // closing pane fades it out, and an opening pane fades it in (drawn for the new pane) while the board
                // line it replaces in the title band fades out.
                let board = holding || f.beat == 0 ? b : shots[f.beat - 1]
                var boardImg = board.board, boardOpacity = 1.0, lineOpacity = 1.0
                if let slide {
                    boardOpacity = slide.boardOpacity(f.camera)
                    if slide.change == .open { boardImg = openingBoards[f.beat]; lineOpacity = 1 - f.camera }
                }
                try movie.append(composite(width: width, height: height, board: boardImg, solid: sImg, rects: rects, title: title,
                                           caption: story.caption(frame: i, cuts: cuts) ?? "", footer: footer, boardLine: board.boardLine,
                                           boardOpacity: CGFloat(boardOpacity), boardLineOpacity: CGFloat(lineOpacity)))
            }
        }
        try movie.finish()
        var fields = story.manifestFields(cuts: cuts)
        var beatOffView: [Int: Int] = [:], beatClear: [Int: MGSolidClearView] = [:], why: [Int: String] = [:], layout: [Int: MGJSON] = [:]
        for k in shots.indices {
            if let n = offViewCount(annotations: holdOffView[k], clear: shots[k].clear) { beatOffView[k] = n }
            if let c = shots[k].clear, c.tested { beatClear[k] = c }
            if let m = moves[k], m.path == .cut { why[k] = m.reason }
            if let s = slides[k] {
                layout[k] = s.manifestJSON(cut: cuts.contains(k), seconds: Double(story.beats[k].transitionFrames) / Double(story.fps))
            }
        }
        fields["beats"] = storyBeats(fields["beats"], holdCamera, beatOffView, clear: beatClear, cuts: why, layout: layout)
        fields["codec"] = .string("h264"); fields["width"] = .number(Double(movie.width)); fields["height"] = .number(Double(movie.height))
        try record("story.mp4", fields)
    }
    let manifest: MGJSON = .object([
        "source": .object(["file": .string(sourceName), "lines": .number(Double(source.lines)), "sha256": .string(source.sha256)]),
        "kind": .string("explainer"), "title": .string(title), "legend": .string(legend.text), "captions": .array(captions),
        "framesRendered": .number(Double(frames)), "renderSecondsPerFrame": frames > 0 ? .number(seconds / Double(frames)) : .number(0),
        "outputs": .array(files), "engine": engine])
    try Data(json(manifest).utf8).write(to: out.appendingPathComponent("manifest.json"))
    finished = true
    print(json(stamped(["ok": .bool(true), "output": .string(out.path), "files": .array(names.map { .string($0) })])))
    return 0
}

/// `snapshot check`: restores an explainer snapshot (`MGExplainerSession.snapshot()` as JSON text) with every check
/// of `MGExplainerSession.restore` and prints `{"ok", "reason", "location", "legend"?, "caption"?, "engine"}`.
func snapshotCheck(_ path: String, _ lib: MGSolidLibrary) throws -> Int32 {
    let attrs = try FileManager.default.attributesOfItem(atPath: path)
    guard (attrs[.type] as? FileAttributeType) == .typeRegular else { throw CLIError.invalid("Not a regular file: \(path)") }
    let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
    defer { try? handle.close() }
    let data = try handle.read(upToCount: MGExplainerLimits.snapshotBytes + 1) ?? Data()
    switch MGExplainerSession.restore(data: data, pacing: .speech, clock: MGManualClock(), library: lib) {
    case .failure(let issue):
        print(json(stamped(["ok": .bool(false), "reason": .string(issue.reason), "location": issue.location]))); return 1
    case .success(let s):
        print(json(stamped(["ok": .bool(true), "reason": .null, "location": .null, "legend": .string(s.legend.text),
                            "caption": s.caption.map(MGJSON.string) ?? .null]))); return 0
    }
}

/// Splits `--component FILE` pairs (repeatable) out of an argument list.
func componentFiles(_ args: [String]) throws -> (files: [String], rest: [String]) {
    var files: [String] = [], rest: [String] = []
    var i = 0
    while i < args.count {
        if args[i] == "--component" {
            guard i + 1 < args.count else { throw CLIError.usage }
            files.append(args[i + 1]); i += 2
        } else { rest.append(args[i]); i += 1 }
    }
    return (files, rest)
}

@main struct MartySolidCLI {
    @MainActor static func main() {
        do {
            let (files, a) = try componentFiles(Array(CommandLine.arguments.dropFirst()))
            let lib: MGSolidLibrary
            do { lib = try library(files) } catch let e as LibraryRefused { print(json(stamped(e.report.objectValue ?? [:]))); exit(1) }
            switch a.first {
            case "check"? where a.count >= 2:
                var rest = Array(a.dropFirst())
                var patch: String?
                if let k = rest.firstIndex(of: "--patch") {
                    guard k + 1 < rest.count, !rest[k + 1].hasPrefix("--") else { throw CLIError.usage }
                    patch = rest[k + 1]
                    rest.removeSubrange(k...(k + 1))
                    guard !rest.contains("--patch") else { throw CLIError.usage }
                }
                let paths = rest.filter { $0 != "--strict" }
                guard paths.count == 1, !paths[0].hasPrefix("--"), rest.count - paths.count <= 1 else { throw CLIError.usage }
                exit(try check(paths[0], patch: patch, lib, strict: rest.contains("--strict")))
            case "components"? where a.count == 1: exit(components(lib))
            case "snapshot"? where a.count == 3 && a[1] == "check" && !a[2].hasPrefix("--"): exit(try snapshotCheck(a[2], lib))
            case "reasons"? where a.count == 1 && files.isEmpty: print(json(MGSolidReasons.json)); exit(0)
            case "version"? where a.count == 1 && files.isEmpty: print(json(engine)); exit(0)
            case "component"? where a.count >= 3 && a[1] == "check" && !a[2].hasPrefix("--"):
                var values: [String: Double] = [:]
                var rest = Array(a.dropFirst(3))
                while let flag = rest.first {
                    rest.removeFirst()
                    guard flag == "--with", let v = rest.first else { throw CLIError.usage }
                    rest.removeFirst()
                    let kv = v.split(separator: "=", maxSplits: 1).map(String.init)
                    guard kv.count == 2, let d = Double(kv[1]), d.isFinite else { throw CLIError.usage }
                    values[kv[0]] = d
                }
                exit(try componentCheck(a[2], lib, with: values))
            case "render"? where a.count >= 3 && !a[1].hasPrefix("--") && !a[2].hasPrefix("--"):
                var w = 1280, h = 800, loop = true, rate = 10, snapshots = false, story = true, storyRate = MGStoryTiming.defaultRate
                var rest = Array(a.dropFirst(3))
                while let flag = rest.first {
                    rest.removeFirst()
                    switch flag {
                    case "--no-loop": loop = false
                    case "--no-story": story = false
                    case "--story-fps":
                        guard let v = rest.first, let r = Int(v), MGStoryTiming.rates.contains(r) else { throw CLIError.usage }
                        rest.removeFirst()
                        storyRate = r
                    case "--snapshots": snapshots = true
                    case "--loop-fps":
                        guard let v = rest.first, let r = Int(v), MGSolidRenderPlan.loopRates.contains(r) else { throw CLIError.usage }
                        rest.removeFirst()
                        rate = r
                    case "--size":
                        guard let v = rest.first else { throw CLIError.usage }
                        rest.removeFirst()
                        let p = v.split(separator: "x").compactMap { Int($0) }
                        guard p.count == 2, (320...3840).contains(p[0]), (200...2160).contains(p[1]) else { throw CLIError.usage }
                        w = p[0]; h = p[1]
                    default: throw CLIError.usage
                    }
                }
                exit(try render(a[1], a[2], width: w, height: h, loop: loop, loopRate: rate, story: story, storyRate: storyRate,
                                snapshots: snapshots, library: lib))
            default: throw CLIError.usage
            }
        } catch {
            FileHandle.standardError.write(Data("\(error)\n".utf8)); exit(2)
        }
    }
}
