// SPDX-License-Identifier: Apache-2.0
// marty-solid: check or render ANY solid assembly JSON file or explainer document (for authors and for AI models that
// write them). The check reports, the render plan and the reason catalog live in the MartyGraphics library; this tool
// adds files and pixels.
import AppKit
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
                   marty-solid render FILE.json NEW_DIR [--size WxH] [--no-loop] [--snapshots] [--component C.json ...]
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

func caption(_ image: CGImage, title: String, text: String?, footer: String) -> CGImage {
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
        ctx.setFillColor(CGColor(gray: 0, alpha: 0.55)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: Int(120 * s)))
        draw(t, 20 * s, .regular, x: 40 * s, y: 30 * s, alpha: 0.95, maxWidth: CGFloat(w) - 80 * s)
    }
    draw(footer, 12 * s, .regular, x: 40 * s, y: CGFloat(h) - 92 * s, alpha: 0.6)
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, _ url: URL) throws {
    guard let d = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { throw CLIError.invalid("png") }
    CGImageDestinationAddImage(d, image, nil)
    guard CGImageDestinationFinalize(d) else { throw CLIError.invalid("png finalize") }
}

func scaled(_ image: CGImage, width: Int) -> CGImage {
    let h = Int((Double(image.height) * Double(width) / Double(image.width)).rounded())
    let ctx = CGContext(data: nil, width: width, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.interpolationQuality = .high; ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: h))
    return ctx.makeImage()!
}

func sha(_ url: URL) throws -> String { SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined() }

/// Renders the library's render plan (`MGSolidRenderPlan`): captioned stills, the loop GIF, the snapshot and the manifest.
@MainActor func render(_ path: String, _ outPath: String, width: Int, height: Int, loop: Bool, snapshots: Bool = false,
                       library lib: MGSolidLibrary) throws -> Int32 {
    let document = try loadDocument(path)
    switch document.kind {
    case "explainer"?: return try renderExplainer(path, document.data, outPath, width: width, height: height, loop: loop, snapshots: snapshots, library: lib)
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
    let out = URL(fileURLWithPath: outPath, isDirectory: true)
    // Atomic "must not exist": creation fails if the directory appears in the meantime. The parent must exist.
    do { try FileManager.default.createDirectory(at: out, withIntermediateDirectories: false) }
    catch { throw CLIError.invalid("Cannot create a NEW output directory at \(out.path) (it exists, or its parent is missing)") }
    var finished = false
    defer { if !finished { try? FileManager.default.removeItem(at: out) } }  // never leave a half-written result
    _ = NSApplication.shared
    let r = MGSolidRenderer(assembly: doc.assembly)
    let aspect = Double(width) / Double(height)
    let sourceName = URL(fileURLWithPath: path).lastPathComponent
    let plan = MGSolidRenderPlan(doc, sourceName: sourceName, source: src.source, loop: loop)
    var files: [MGJSON] = []
    var names: [String] = []
    var seconds = 0.0, frames = 0
    func shot(_ s: MGSolidShot) throws -> CGImage {
        let p = MGSolidCamera.presets[s.preset] ?? MGSolidCamera.presets["hero"]!
        // Each step shows its own section cuts and ghosts; other shots show the plain scene.
        r.show(doc.view(step: s.step))
        r.highlight(Set(s.highlight), dimOthers: !s.highlight.isEmpty)
        r.apply(s.params)
        // Bounding spheres are loose around flat or long assemblies; a margin below 1 fills the frame.
        r.frame(s.params, explodeRange: [0, s.params.explode], yaw: p.yaw + s.orbit, pitch: p.pitch, aspect: aspect, margin: s.margin)
        let t0 = Date()
        guard let img = r.render(width: width, height: height) else { throw CLIError.invalid("render failed (no Metal device?)") }
        seconds += Date().timeIntervalSince(t0); frames += 1
        return img
    }
    func record(_ name: String, _ fields: [String: MGJSON]) throws {
        let u = out.appendingPathComponent(name)
        var o = fields
        o["file"] = .string(name)
        o["bytes"] = .number(Double((try Data(contentsOf: u)).count))
        o["sha256"] = .string(try sha(u))
        files.append(.object(o)); names.append(name)
    }
    for s in plan.stills {
        let img = caption(try shot(s), title: s.title ?? doc.title, text: s.caption, footer: plan.footer)
        try writePNG(img, out.appendingPathComponent(s.file))
        try record(s.file, ["width": .number(Double(img.width)), "height": .number(Double(img.height))])
    }
    if !plan.loop.isEmpty {
        let n = plan.loop.count, gifURL = out.appendingPathComponent("loop.gif")
        let delay = MGSolidRenderPlan.loopDelaySeconds
        guard let gif = CGImageDestinationCreateWithURL(gifURL as CFURL, UTType.gif.identifier as CFString, n, nil) else { throw CLIError.invalid("gif") }
        CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for s in plan.loop {
            CGImageDestinationAddImage(gif, scaled(try shot(s), width: MGSolidRenderPlan.loopWidth),
                                       [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay, kCGImagePropertyGIFUnclampedDelayTime: delay]] as CFDictionary)
        }
        guard CGImageDestinationFinalize(gif) else { throw CLIError.invalid("gif finalize") }
        try record("loop.gif", ["width": .number(Double(MGSolidRenderPlan.loopWidth)), "frames": .number(Double(n)), "delaySeconds": .number(delay),
                                "loopSeconds": .number(MGSolidRenderPlan.loopSeconds)])
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

/// The panes of one composite frame: the `primary` view gets 55 % (side by side when wider than tall, else stacked).
func paneRects(width w: Int, height h: Int, board: Bool, solid: Bool, primarySolid: Bool) -> (board: CGRect?, solid: CGRect?) {
    let s = CGFloat(w) / 1280, gap = 16 * s
    let area = CGRect(x: 24 * s, y: 132 * s, width: CGFloat(w) - 48 * s, height: CGFloat(h) - 132 * s - 112 * s)
    guard board && solid else { return (board ? area : nil, solid ? area : nil) }
    var first = area, second = area
    if w >= h {
        let a = (area.width - gap) * 0.55, b = area.width - gap - a
        first.size.width = primarySolid ? b : a
        second.origin.x = first.maxX + gap; second.size.width = primarySolid ? a : b
    } else {
        let a = (area.height - gap) * 0.55, b = area.height - gap - a
        // CoreGraphics y grows upward: the first pane is the top one.
        second.size.height = primarySolid ? a : b
        first.origin.y = second.maxY + gap; first.size.height = primarySolid ? b : a
    }
    return (first, second)
}

/// One composite: the panes on a dark board, then the title, the caption band and the legend line (`caption`).
func composite(width w: Int, height h: Int, board: CGImage?, solid: CGImage?, rects: (board: CGRect?, solid: CGRect?),
               title: String, caption text: String?, footer: String) -> CGImage {
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
    return caption(ctx.makeImage()!, title: title, text: text, footer: footer)
}

/// `render` for an explainer: `beat-<n>.png` (one composite per beat), `board-0.png` and `solid-0.png` (the views before
/// the first beat), `loop.gif` (the solid's loop), `snapshot-beat-<n>.json` with `--snapshots`, and `manifest.json`.
@MainActor func renderExplainer(_ path: String, _ data: Data, _ outPath: String, width: Int, height: Int, loop: Bool, snapshots: Bool,
                                library lib: MGSolidLibrary) throws -> Int32 {
    let source = MGSolidSource(data: data)
    let doc: MGExplainer
    switch MGExplainer.parse(data: data) {
    case .failure(let issue): print(json(MGExplainerReport.refused(issue, profile: nil, source: nil, engine: engine).json)); return 1
    case .success(let d): doc = d
    }
    var session = MGExplainerSession(pacing: .speech, clock: MGManualClock(), library: lib)
    if case .failure(let issue) = session.load(doc) {
        print(json(MGExplainerReport.refused(issue, profile: nil, source: nil, engine: engine).json)); return 1
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
    let legend = session.legend
    let footer = "\(legend.text) · Rendered by the MartyGraphics engine from \(sourceName) (\(source.sizeText))"
    let title = session.title ?? ""
    let solidDoc = session.solid
    let renderer = solidDoc.map { d -> MGSolidRenderer in
        let r = MGSolidRenderer(assembly: d.assembly)
        r.emphasis = .strong   // a highlight must read at a glance in a still, as on the 2D board
        return r
    }
    let primarySolid = (session.primary ?? (solidDoc != nil ? "solid" : "board")) == "solid"
    let rects = paneRects(width: width, height: height, board: doc.board != nil, solid: solidDoc != nil, primarySolid: primarySolid)
    var files: [MGJSON] = [], names: [String] = []
    var seconds = 0.0, frames = 0
    func solidImage(_ view: MGExplainerBeatView, _ rect: CGRect, spin: Bool = true) throws -> CGImage? {
        guard let r = renderer, let d = solidDoc else { return nil }
        let step = view.step
        r.show(view.solid ?? d.view(step: nil))
        r.highlight(Set(view.solidHighlight), dimOthers: !view.solidHighlight.isEmpty)
        let params = MGPoseParameters(input: d.defaults.input + (spin ? (step?.spin ?? 0) : 0) * 2 * .pi, explode: step?.explode ?? d.defaults.explode)
        r.apply(params)
        let p = MGSolidCamera.presets[step?.camera ?? "hero"] ?? MGSolidCamera.presets["hero"]!
        r.frame(params, explodeRange: [0, params.explode], yaw: p.yaw + (step?.orbit ?? 0), pitch: p.pitch,
                aspect: Double(rect.width / rect.height), margin: 0.8)
        let t0 = Date()
        guard let img = r.render(width: Int(rect.width), height: Int(rect.height)) else { throw CLIError.invalid("render failed (no Metal device?)") }
        seconds += Date().timeIntervalSince(t0); frames += 1
        return img
    }
    func record(_ name: String, _ fields: [String: MGJSON]) throws {
        let u = out.appendingPathComponent(name)
        var o = fields
        o["file"] = .string(name)
        o["bytes"] = .number(Double((try Data(contentsOf: u)).count))
        o["sha256"] = .string(try sha(u))
        files.append(.object(o)); names.append(name)
    }
    func write(_ img: CGImage, _ name: String) throws {
        try writePNG(img, out.appendingPathComponent(name))
        try record(name, ["width": .number(Double(img.width)), "height": .number(Double(img.height))])
    }
    if doc.board != nil, let scene = before.state?.scene {
        let alone = paneRects(width: width, height: height, board: true, solid: false, primarySolid: false)
        let r = alone.board!
        try write(composite(width: width, height: height, board: boardImage(scene, MGExplainerBeatView(), width: Int(r.width), height: Int(r.height)),
                            solid: nil, rects: alone, title: title, caption: nil, footer: footer), "board-0.png")
    }
    if solidDoc != nil {
        let alone = paneRects(width: width, height: height, board: false, solid: true, primarySolid: true)
        try write(composite(width: width, height: height, board: nil, solid: try solidImage(MGExplainerBeatView(), alone.solid!, spin: false),
                            rects: alone, title: title, caption: nil, footer: footer), "solid-0.png")
    }
    var captions: [MGJSON] = []
    var k = 0
    while let beat = session.presented.beat, beat == k {
        let view = session.presented
        let caption = session.caption ?? ""
        captions.append(.string(caption))
        let b = rects.board.flatMap { r in session.state.map { boardImage($0.scene, view, width: Int(r.width), height: Int(r.height)) } } ?? nil
        let sImg = try rects.solid.flatMap { try solidImage(view, $0) }
        try write(composite(width: width, height: height, board: b, solid: sImg, rects: rects, title: title, caption: "\(k + 1). \(caption)", footer: footer),
                  "beat-\(k + 1).png")
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
        let plan = MGSolidRenderPlan(d, sourceName: sourceName, source: source, loop: true)
        let n = plan.loop.count, gifURL = out.appendingPathComponent("loop.gif")
        let delay = MGSolidRenderPlan.loopDelaySeconds
        guard let gif = CGImageDestinationCreateWithURL(gifURL as CFURL, UTType.gif.identifier as CFString, n, nil) else { throw CLIError.invalid("gif") }
        CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        r.show(d.view(step: nil)); r.highlight([], dimOthers: false)
        for shot in plan.loop {
            let p = MGSolidCamera.presets[shot.preset] ?? MGSolidCamera.presets["hero"]!
            r.apply(shot.params)
            r.frame(shot.params, explodeRange: [0, shot.params.explode], yaw: p.yaw + shot.orbit, pitch: p.pitch, aspect: Double(width) / Double(height), margin: shot.margin)
            let t0 = Date()
            guard let img = r.render(width: width, height: height) else { throw CLIError.invalid("render failed (no Metal device?)") }
            seconds += Date().timeIntervalSince(t0); frames += 1
            CGImageDestinationAddImage(gif, scaled(img, width: MGSolidRenderPlan.loopWidth),
                                       [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay, kCGImagePropertyGIFUnclampedDelayTime: delay]] as CFDictionary)
        }
        guard CGImageDestinationFinalize(gif) else { throw CLIError.invalid("gif finalize") }
        try record("loop.gif", ["width": .number(Double(MGSolidRenderPlan.loopWidth)), "frames": .number(Double(n)), "delaySeconds": .number(delay)])
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
                var w = 1280, h = 800, loop = true, snapshots = false
                var rest = Array(a.dropFirst(3))
                while let flag = rest.first {
                    rest.removeFirst()
                    switch flag {
                    case "--no-loop": loop = false
                    case "--snapshots": snapshots = true
                    case "--size":
                        guard let v = rest.first else { throw CLIError.usage }
                        rest.removeFirst()
                        let p = v.split(separator: "x").compactMap { Int($0) }
                        guard p.count == 2, (320...3840).contains(p[0]), (200...2160).contains(p[1]) else { throw CLIError.usage }
                        w = p[0]; h = p[1]
                    default: throw CLIError.usage
                    }
                }
                exit(try render(a[1], a[2], width: w, height: h, loop: loop, snapshots: snapshots, library: lib))
            default: throw CLIError.usage
            }
        } catch {
            FileHandle.standardError.write(Data("\(error)\n".utf8)); exit(2)
        }
    }
}
