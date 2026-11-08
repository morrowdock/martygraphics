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
struct TooLarge: Error {}

func load(_ path: String) throws -> Loaded {
    // Never read more than the format allows: refuse non-regular files (FIFOs, devices) and oversized files first.
    let attrs = try FileManager.default.attributesOfItem(atPath: path)
    guard (attrs[.type] as? FileAttributeType) == .typeRegular else { throw CLIError.invalid("Not a regular file: \(path)") }
    guard ((attrs[.size] as? NSNumber)?.intValue ?? 0) <= MGSolidLimits.bytes else { throw TooLarge() }
    let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
    defer { try? handle.close() }
    let data = try handle.read(upToCount: MGSolidLimits.bytes + 1) ?? Data()
    guard data.count <= MGSolidLimits.bytes else { throw TooLarge() }
    return Loaded(data: data, source: MGSolidSource(data: data))
}

/// A document file as read for `check` and `render`: at most 128 KiB plus one byte (the explainer limit), regular files
/// only. The top-level `kind` picks the path: `explainer` is an explainer; `lesson` (an engine format this tool does not
/// take) is `kind.unsupported`; anything else (no `kind`, `assembly`, another value) keeps the assembly path and its
/// reasons, unchanged.
struct Document { let data: Data; let kind: String? }

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
        do { src = try load(path) } catch is TooLarge {
            throw LibraryRefused(report: .object(["ok": .bool(false), "reason": .string("component.bytes"), "part": .null, "component": .string(path)]))
        }
        if case .failure(let issue) = lib.register(src.data) {
            throw LibraryRefused(report: .object(["ok": .bool(false), "reason": .string(issue.reason), "part": opt(issue.part),
                                                  "component": .string(path)]))
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
        let report = MGExplainerReport.check(data: doc.data, library: lib, profile: profile, engine: engine)
        print(report.text)
        return report.exitCode
    case "lesson"?: return unsupportedKind()
    default: break
    }
    let src: Loaded
    do { src = try load(path) } catch is TooLarge {
        var r = MGSolidReport.refused(MGSolidIssue("assembly.bytes"), engine: engine).json.objectValue ?? [:]
        if patchPath != nil { r["patch"] = .object(["applied": .bool(false), "fields": .array([]), "refusedAt": .string("base")]) }
        print(json(.object(r))); return 1
    }
    let report: MGSolidReport
    if let patchPath {
        // A patch over the limit is refused by the library (`patch.bytes`) without reading more than one byte past it.
        let patch: Data
        do { patch = try load(patchPath).data } catch is TooLarge { patch = Data(count: MGSolidLimits.bytes + 1) }
        report = MGSolidReport.check(data: src.data, patch: patch, library: lib, profile: profile, engine: engine)
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
    do { src = try load(path) } catch is TooLarge {
        print(json(stamped(["ok": .bool(false), "reason": .string("component.bytes"), "part": .null]))); return 1
    }
    let file: MGJSON = .object(["lines": .number(Double(src.source.lines)), "sha256": .string(src.source.sha256)])
    let withJSON = MGJSON.object(values.mapValues { MGJSON.number($0) })
    var lib = base
    let component: MGSolidComponent
    switch lib.register(src.data) {
    case .failure(let issue):
        print(json(stamped(["ok": .bool(false), "reason": .string(issue.reason), "part": opt(issue.part), "file": file])))
        return 1
    case .success(let c): component = c
    }
    switch lib.instantiate(component.id, with: values) {
    case .failure(let issue):
        print(json(stamped(["ok": .bool(false), "reason": .string(issue.reason), "part": opt(issue.part),
                            "id": .string(component.id), "with": withJSON, "file": file])))
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

func caption(_ image: CGImage, title: String, text: String?, footer: String, boardLine: String? = nil) -> CGImage {
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
        ctx.setFillColor(CGColor(gray: 0, alpha: 0.55)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: Int(band * s)))
        draw(t, 20 * s, .regular, x: 40 * s, y: 30 * s, alpha: 0.95, maxWidth: CGFloat(w) - 80 * s)
    }
    draw(footer, 12 * s, .regular, x: 40 * s, y: CGFloat(h) - 92 * s, alpha: 0.6)
    // The board's text when its pane is not drawn (an explainer beat whose board shows only text): one line in the
    // title band, under the legend line, in the board's ink, truncated with an ellipsis.
    if let line = boardLine {
        let font = NSFont.systemFont(ofSize: 15 * s, weight: .medium) as CTFont
        let ink = CGColor(srgbRed: 0.72, green: 0.80, blue: 1.0, alpha: 0.95)
        let attr = NSAttributedString(string: line, attributes: [.font: font, .foregroundColor: ink])
        let dots = CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: [.font: font, .foregroundColor: ink]))
        let fitted = CTLineCreateTruncatedLine(CTLineCreateWithAttributedString(attr), Double(CGFloat(w) - 80 * s), .end, dots)
            ?? CTLineCreateWithAttributedString(attr)
        ctx.textPosition = CGPoint(x: 40 * s, y: CGFloat(h) - 118 * s); CTLineDraw(fitted, ctx)
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

/// The story manifest's per-beat records with the hold camera (the camera of the beat's last frame) and the number of
/// annotations off view in that frame (absent when the beat draws none).
func storyBeats(_ beats: MGJSON?, _ cameras: [Int: MGSolidCamera], _ offView: [Int: Int]) -> MGJSON? {
    guard case .array(let list)? = beats else { return beats }
    return .array(list.enumerated().map { k, v -> MGJSON in
        guard case .object(var o) = v else { return v }
        if let c = cameras[k] { o["camera"] = c.manifestJSON }
        if let n = offView[k] { o["offView"] = .number(Double(n)) }
        return .object(o)
    })
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
    do { src = try load(path) } catch is TooLarge {
        print(json(MGSolidReport.refused(MGSolidIssue("assembly.bytes"), engine: engine).json)); return 1
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
    func shot(_ s: MGSolidShot, _ camera: MGSolidCamera) throws -> CGImage {
        // Each step shows its own section cuts, ghosts and annotations; other shots show the plain scene. Annotations
        // show on hero.png and the step stills only (`MGSolidShot.showsAnnotations`), and only where the engine
        // checked the pose (`checkedAnnotations`, inside the renderer and the frame).
        let view = doc.view(step: s.step)
        if s.showsAnnotations { r.show(document: doc, view: view) } else { r.show(view) }
        r.highlight(Set(s.highlight), dimOthers: !s.highlight.isEmpty)
        r.apply(s.params)
        r.setCamera(camera)
        let t0 = Date()
        guard let img = r.render(width: width, height: height) else { throw CLIError.invalid("render failed (no Metal device?)") }
        seconds += Date().timeIntervalSince(t0); frames += 1
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
            let img = caption(try shot(s, cameras.stills[k]), title: s.title ?? doc.title, text: s.caption, footer: plan.footer)
            try writePNG(img, out.appendingPathComponent(s.file))
            var fields: [String: MGJSON] = ["width": .number(Double(img.width)), "height": .number(Double(img.height)),
                                            "framing": .string(cameras.rules[k].rawValue)]
            // Step stills also record their camera (the story's hold camera for that step) and the annotations off view.
            if s.step != nil {
                fields["camera"] = cameras.stills[k].manifestJSON
                if s.showsAnnotations, !doc.view(step: s.step).annotations.isEmpty, let f = previousFrame {
                    fields["offView"] = .number(Double(f.placement.filter(\.offView).count))
                }
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
    if let story = storyPlan {
        // The steps in order, each with its caption, view (cuts, ghosts), highlight, annotations and camera; the camera
        // moves from the previous step's camera at the start of each step, and the step's spin plays as in the view.
        let stepStill = Dictionary(uniqueKeysWithValues: plan.stills.indices.compactMap { k in plan.stills[k].step.map { ($0, k) } })
        // The legend shows in every frame: for a document with annotations, in the overlay corner with its notes (also
        // during camera moves, while arrows are drawn and labels are not); otherwise in the footer line.
        let annotated = !doc.annotations.isEmpty
        let footer = annotated ? plan.footer : "\(doc.legend.text) · \(plan.footer)"
        let movie = try MovieWriter(url: out.appendingPathComponent("story.mp4"), width: width, height: height, fps: Int32(story.fps))
        // During a step's hold the camera is exactly the step still's camera; only the move at the start of a step is in
        // between, and labels are hidden during that move.
        let beatCameras: [MGSolidCamera?] = doc.steps.indices.map { k in stepStill[k].map { cameras.stills[$0] } }
        var shownStep: Int?, settledStep: Int?
        var holdCamera: [Int: MGSolidCamera] = [:], holdOffView: [Int: Int] = [:]
        for i in 0..<story.frameCount {
            try autoreleasepool {
                let f = story.frame(i)
                guard let base = MGSolidShot.step(doc, f.beat), let camera = story.camera(frame: i, beatCameras: beatCameras) else {
                    throw CLIError.invalid("story step")
                }
                let step = doc.steps[f.beat]
                var s = base
                s.params = MGPoseParameters(input: doc.defaults.input + step.spin * 2 * .pi * f.spin, explode: base.params.explode)
                let view = doc.view(step: f.beat)
                if shownStep != f.beat {
                    shownStep = f.beat
                    r.show(document: doc, view: view)
                    r.highlight(Set(s.highlight), dimOthers: !s.highlight.isEmpty)
                }
                // A step's caption, labels and claims appear when its hold starts (after the camera move); labels keep
                // their places for the rest of the step.
                let holding = story.holds(frame: i)
                if !holding || settledStep != f.beat { previousFrame = nil }
                settledStep = holding ? f.beat : nil
                r.apply(s.params)
                r.setCamera(camera)
                let t0 = Date()
                guard var img = r.render(width: width, height: height) else { throw CLIError.invalid("render failed (no Metal device?)") }
                seconds += Date().timeIntervalSince(t0); frames += 1
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
                try movie.append(caption(img, title: s.title ?? doc.title, text: story.caption(frame: i) ?? "", footer: footer))
            }
        }
        try movie.finish()
        var fields = story.manifestFields()
        fields["beats"] = storyBeats(fields["beats"], holdCamera, holdOffView)
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
/// SwiftUI explainer view draws).
@MainActor func boardImage(_ scene: MGScene, _ view: MGExplainerBeatView, width: Int, height: Int) -> CGImage? {
    let size = CGSize(width: width, height: height)
    let r = ImageRenderer(content: Canvas { ctx, sz in MGCanvasRenderer.draw(MGExplainerBoard.input(scene, view: view, size: sz), in: ctx) }
        .frame(width: size.width, height: size.height))
    r.scale = 1
    return r.cgImage
}

/// The panes of one composite frame (`MGExplainerFrame.panes`): the `primary` view gets 55 % (side by side when wider
/// than tall, else stacked). `board` is false in a beat whose shown board has no non-text item
/// (`MGExplainerSession.boardPane`): the solid then takes the whole area.
func paneRects(width w: Int, height h: Int, board: Bool, solid: Bool, primarySolid: Bool) -> (board: CGRect?, solid: CGRect?) {
    let p = MGExplainerFrame.panes(width: w, height: h, board: board, solid: solid, primarySolid: primarySolid)
    func cg(_ r: MGFrameRect?) -> CGRect? { r.map { CGRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height) } }
    return (cg(p.board), cg(p.solid))
}

/// A pane rect as the engine's whole-pixel rect (`MGExplainerFrame.panes` gives whole pixels).
func frameRect(_ r: CGRect) -> MGFrameRect { MGFrameRect(x: Int(r.minX), y: Int(r.minY), width: Int(r.width), height: Int(r.height)) }

/// One composite: the panes on a dark board, then the title, the caption band and the legend line (`caption`).
/// `boardLine`: the board's text when its pane is not drawn (`MGExplainerBoardPane.line`), shown in the title band.
func composite(width w: Int, height h: Int, board: CGImage?, solid: CGImage?, rects: (board: CGRect?, solid: CGRect?),
               title: String, caption text: String?, footer: String, boardLine: String? = nil) -> CGImage {
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: 0.05, green: 0.07, blue: 0.10, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    for (img, rect) in [(board, rects.board), (solid, rects.solid)] {
        guard let img, let rect else { continue }
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 14, cornerHeight: 14, transform: nil)); ctx.clip()
        ctx.draw(img, in: rect)
        ctx.restoreGState()
    }
    return caption(ctx.makeImage()!, title: title, text: text, footer: footer, boardLine: boardLine)
}

/// One beat of an explainer as the stills show it, kept for the story video: the view, the caption line, the board
/// image and pane layout, the board text that moved to the title band, the solid step and its framed camera.
struct ExplainerBeatShot {
    var view: MGExplainerBeatView
    var caption: String
    var board: CGImage?
    var rects: (board: CGRect?, solid: CGRect?)
    var boardLine: String?
    var stepIndex: Int?
    var camera: MGSolidCamera?
}

/// `render` for an explainer: `beat-<n>.png` (one composite per beat), `board-0.png` and `solid-0.png` (the views before
/// the first beat), `loop.gif` and `loop.mp4` (the solid's loop), `story.mp4` (the beats in order), `snapshot-beat-<n>.json`
/// with `--snapshots`, and `manifest.json`.
@MainActor func renderExplainer(_ path: String, _ data: Data, _ outPath: String, width: Int, height: Int, loop: Bool, loopRate: Int = 10,
                                story: Bool = true, storyRate: Int = MGStoryTiming.defaultRate,
                                snapshots: Bool, library lib: MGSolidLibrary) throws -> Int32 {
    let source = MGSolidSource(data: data)
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
    var shownView: MGSolidView?
    var previousFrame: MGAnnotationFrame?
    /// `stepIndex`: the solid step the beat shows (its focus frames the pane, `MGSolidFraming`); nil for the plain view.
    /// `spin`: the played fraction of the beat's spin (1: the beat's end pose, as in a still). `camera`: the story
    /// video's camera for this frame (`MGStoryPlan.camera(frame:beatCameras:)`); without it the pane is framed by
    /// `MGExplainerFrame.solidCamera` for the pane's own pixels, as in a still. `labels`: draw the annotation overlay
    /// (the story hides it while the camera moves). `stable`: keep label places from the last frame.
    func solidImage(_ view: MGExplainerBeatView, _ rect: CGRect, spin: Double = 1, stepIndex: Int? = nil, camera: MGSolidCamera? = nil,
                    labels: Bool = true, stable: Bool = false) throws -> CGImage? {
        guard let r = renderer, let d = solidDoc else { return nil }
        let pane = frameRect(rect)
        let shown = view.solid ?? d.view(step: nil)
        let params = MGExplainerFrame.pose(d, view: view, spin: spin)
        r.apply(params)
        if !stable || shownView != shown {
            r.show(document: d, view: shown)
            r.highlight(Set(view.solidHighlight), dimOthers: !view.solidHighlight.isEmpty)
            r.highlightAnnotations(Set(view.annotations))
            shownView = shown; previousFrame = nil
        }
        if let camera {
            r.setCamera(camera)
        } else {
            let framed = MGExplainerFrame.solidCamera(d, view: view, stepIndex: stepIndex, pane: pane)
            r.setCamera(framed.camera)
            lastFraming = framed.rule; lastCamera = framed.camera
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
        let rects = paneRects(width: width, height: height, board: pane.shown, solid: solidDoc != nil, primarySolid: primarySolid)
        let b = rects.board.flatMap { r in session.state.map { boardImage($0.scene, view, width: Int(r.width), height: Int(r.height)) } } ?? nil
        lastFraming = nil; lastCamera = nil; lastOffView = nil
        let step = session.solidStep(forBeat: k)
        let sImg = try rects.solid.flatMap { try solidImage(view, $0, stepIndex: step) }
        let line = "\(k + 1). \(caption)"
        var extra: [String: MGJSON] = ["boardPane": .bool(rects.board != nil)]
        if let c = lastCamera { extra["camera"] = c.manifestJSON }
        if let n = lastOffView { extra["offView"] = .number(Double(n)) }
        try write(composite(width: width, height: height, board: b, solid: sImg, rects: rects, title: title, caption: line, footer: footer,
                            boardLine: pane.shown ? nil : pane.line),
                  "beat-\(k + 1).png", framing: lastFraming, fields: extra)
        shots.append(ExplainerBeatShot(view: view, caption: line, board: b, rects: rects, boardLine: pane.shown ? nil : pane.line,
                                       stepIndex: step, camera: lastCamera))
        if snapshots, let d = solidDoc {
            let params = MGPoseParameters(input: d.defaults.input + (view.step?.spin ?? 0) * 2 * .pi, explode: view.step?.explode ?? d.defaults.explode)
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
    if let story = storyPlan {
        // The dry run and the stills run the same session rules on the same document, so they present the same beats.
        guard story.beats.count == shots.count, zip(story.beats, shots).allSatisfy({ $0.caption == $1.caption }) else {
            throw CLIError.invalid("story: the beats differ from the stills")
        }
        // The beats in order: each frame is a real composite of the beat's board (its settled state, as in its still),
        // the solid at the beat's view, highlight and annotations, the caption and the legend line. During a beat's hold
        // the camera is exactly the beat's still camera (same layout, same pane pixels); only in the camera move at the
        // start of a beat is it in between, and labels are hidden during that move. The beat's spin plays.
        let movie = try MovieWriter(url: out.appendingPathComponent("story.mp4"), width: width, height: height, fps: Int32(story.fps))
        let beatCameras = shots.map(\.camera)
        // A beat whose solid pane has another size than the previous beat's (the board pane appeared or went) cuts to
        // its own camera instead of moving: the previous camera was fitted for the other pane.
        let cuts = Set(shots.indices.dropFirst().filter { shots[$0].rects.solid != shots[$0 - 1].rects.solid })
        shownView = nil
        var settled: Int?   // the beat whose camera has arrived (its labels keep their places from frame to frame)
        var holdCamera: [Int: MGSolidCamera] = [:], holdOffView: [Int: Int] = [:]
        for i in 0..<story.frameCount {
            try autoreleasepool {
                let f = story.frame(i)
                let b = shots[f.beat]
                let camera = story.camera(frame: i, beatCameras: beatCameras, cuts: cuts)
                let holding = story.holds(frame: i, cuts: cuts)
                let sImg = try b.rects.solid.flatMap { try solidImage(b.view, $0, spin: f.spin, stepIndex: b.stepIndex, camera: camera,
                                                                      labels: holding, stable: settled == f.beat) }
                settled = holding ? f.beat : nil
                if holding, let camera { holdCamera[f.beat] = camera; if let n = lastOffView { holdOffView[f.beat] = n } }
                // A beat's caption, labels and board claims appear when its hold starts. During the camera move the
                // caption band is empty and the board still shows the previous beat's state (the layout is the same:
                // a layout change cuts, with no move).
                let board = holding || f.beat == 0 ? b : shots[f.beat - 1]
                try movie.append(composite(width: width, height: height, board: board.board, solid: sImg, rects: b.rects, title: title,
                                           caption: story.caption(frame: i, cuts: cuts) ?? "", footer: footer, boardLine: board.boardLine))
            }
        }
        try movie.finish()
        var fields = story.manifestFields(cuts: cuts)
        fields["beats"] = storyBeats(fields["beats"], holdCamera, holdOffView)
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
