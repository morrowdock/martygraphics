// SPDX-License-Identifier: Apache-2.0
// marty-solid: check or render ANY solid assembly JSON file (for authors and for AI models that write them).
import AppKit
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
        case .usage: return "Usage: marty-solid check FILE.json | marty-solid render FILE.json NEW_DIR [--size WxH] [--no-loop]"
        case .invalid(let s): return s
        }
    }
}

struct Loaded { let data: Data; let lines: Int; let sha256: String }

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
    let text = String(decoding: data, as: UTF8.self)
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false).count - (text.hasSuffix("\n") ? 1 : 0)
    return Loaded(data: data, lines: lines, sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
}

/// Replace values JSON cannot carry (nil, NaN, infinities) with null, recursively.
func sanitized(_ v: Any?) -> Any {
    switch v {
    case nil: return NSNull()
    case let d as Double: return d.isFinite ? d : NSNull()
    case let a as [Any]: return a.map { sanitized($0) }
    case let a as [String]: return a
    case let m as [String: Any]: return m.mapValues { sanitized($0) }
    case let m as [String: Double]: return m.mapValues { sanitized($0) }
    case let o?: return o
    }
}

func json(_ object: Any) -> String {
    let clean = sanitized(object)
    guard JSONSerialization.isValidJSONObject(clean),
          let d = try? JSONSerialization.data(withJSONObject: clean, options: [.prettyPrinted, .sortedKeys]) else {
        return #"{"ok": false, "reason": "report.encoding"}"#
    }
    return String(decoding: d, as: UTF8.self)
}

/// Engine checks beyond parsing: closed meshes and a gear tooth sweep (when the model has gear meshes).
func checks(_ doc: MGSolidDocument) -> [String: Any] {
    let open = doc.assembly.parts.filter { !$0.mesh.edgeReport.isClosed }.map(\.id).sorted()
    var out: [String: Any] = ["meshesClosed": open.isEmpty, "openMeshes": open]
    let report = MGSolidChecks.gearMeshes(doc, samples: 96, inputRange: 0...(2 * .pi))
    out["gearPairs"] = report.pairs
    if report.pairs > 0 {
        // Same tolerance the compiler uses for interference: 0.01 of the smallest module in the model.
        let module = doc.gears.values.compactMap { $0.spur?.module ?? $0.ring?.module }.min() ?? 1
        let tolerance = MGSolidLimits.toothOverlap * module
        out["maxPenetrationMM"] = report.maxPenetration
        out["minClearanceMM"] = report.minClearance
        out["toleranceMM"] = tolerance
        out["gearsEngage"] = report.maxPenetration <= tolerance
    }
    return out
}

func check(_ path: String) throws -> Int32 {
    let src: Loaded
    do { src = try load(path) } catch is TooLarge {
        print(json(["ok": false, "reason": "assembly.bytes", "part": NSNull()])); return 1
    }
    switch MGSolidParser.document(data: src.data) {
    case .failure(let issue):
        print(json(["ok": false, "reason": issue.reason, "part": issue.part as Any, "file": ["lines": src.lines, "sha256": src.sha256]]))
        return 1
    case .success(let doc):
        let c = checks(doc)
        let tris = doc.assembly.parts.reduce(0) { $0 + $1.mesh.triangleCount }
        var reason: String? = nil
        if (c["meshesClosed"] as? Bool) != true { reason = "check.meshOpen" }
        else if (c["gearsEngage"] as? Bool) == false { reason = "check.gearsInterpenetrate" }
        let ok = reason == nil
        print(json(["ok": ok, "reason": reason as Any, "title": doc.title, "parts": doc.assembly.parts.count, "triangles": tris, "steps": doc.steps.map(\.say),
                    "ratios": doc.ratios, "checks": c, "file": ["lines": src.lines, "sha256": src.sha256]]))
        return ok ? 0 : 1
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

@MainActor func render(_ path: String, _ outPath: String, width: Int, height: Int, loop: Bool) throws -> Int32 {
    let src: Loaded
    do { src = try load(path) } catch is TooLarge {
        print(json(["ok": false, "reason": "assembly.bytes", "part": NSNull()])); return 1
    }
    let doc: MGSolidDocument
    switch MGSolidParser.document(data: src.data) {
    case .failure(let issue): print(json(["ok": false, "reason": issue.reason, "part": issue.part as Any])); return 1
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
    let footer = "Rendered by the MartyGraphics solid engine from \(URL(fileURLWithPath: path).lastPathComponent) (\(src.lines) lines)"
    var files: [[String: Any]] = []
    var seconds = 0.0, frames = 0
    func shot(_ params: MGPoseParameters, preset: String, orbit: Double = 0, highlight: [String] = [], margin: Double = 0.8) throws -> CGImage {
        let p = MGSolidCamera.presets[preset] ?? MGSolidCamera.presets["hero"]!
        r.highlight(Set(highlight), dimOthers: !highlight.isEmpty)
        r.apply(params)
        // Bounding spheres are loose around flat or long assemblies; a margin below 1 fills the frame.
        r.frame(params, explodeRange: [0, params.explode], yaw: p.yaw + orbit, pitch: p.pitch, aspect: aspect, margin: margin)
        let t0 = Date()
        guard let img = r.render(width: width, height: height) else { throw CLIError.invalid("render failed (no Metal device?)") }
        seconds += Date().timeIntervalSince(t0); frames += 1
        return img
    }
    func save(_ img: CGImage, _ name: String) throws {
        let u = out.appendingPathComponent(name); try writePNG(img, u)
        files.append(["file": name, "bytes": (try Data(contentsOf: u)).count, "sha256": try sha(u), "width": img.width, "height": img.height])
    }
    try save(caption(try shot(doc.defaults, preset: "hero"), title: doc.title, text: nil, footer: footer), "hero.png")
    try save(caption(try shot(MGPoseParameters(input: doc.defaults.input, explode: 1), preset: "hero", margin: 0.92),
                     title: doc.title + " · exploded", text: nil, footer: footer), "exploded.png")
    for (i, step) in doc.steps.enumerated() {
        let params = MGPoseParameters(input: doc.defaults.input + step.spin * 2 * .pi, explode: step.explode ?? doc.defaults.explode)
        let img = try shot(params, preset: step.camera ?? "hero", orbit: step.orbit, highlight: step.highlight)
        try save(caption(img, title: doc.title, text: "\(i + 1). \(step.say)", footer: footer), "step-\(i + 1).png")
    }
    if loop {
        // 120 frames x 0.10 s = 12.00 s: one full orbit, one input turn, and an explode-and-reassemble beat.
        let n = 120, gifURL = out.appendingPathComponent("loop.gif")
        guard let gif = CGImageDestinationCreateWithURL(gifURL as CFURL, UTType.gif.identifier as CFString, n, nil) else { throw CLIError.invalid("gif") }
        CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for k in 0..<n {
            let t = Double(k) / Double(n)
            let e = t > 0.4 && t < 0.9 ? 0.5 - 0.5 * cos((t - 0.4) / 0.5 * 2 * .pi) : 0
            let img = try shot(MGPoseParameters(input: doc.defaults.input + t * 2 * .pi, explode: e), preset: "hero", orbit: t * 360, margin: 0.86)
            CGImageDestinationAddImage(gif, scaled(img, width: 640),
                                       [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1, kCGImagePropertyGIFUnclampedDelayTime: 0.1]] as CFDictionary)
        }
        guard CGImageDestinationFinalize(gif) else { throw CLIError.invalid("gif finalize") }
        files.append(["file": "loop.gif", "bytes": (try Data(contentsOf: gifURL)).count, "sha256": try sha(gifURL), "width": 640, "frames": n, "delaySeconds": 0.1, "loopSeconds": 12.0])
    }
    let snap = MGSolidSnapshot.make(doc.assembly, params: doc.defaults)
    let snapURL = out.appendingPathComponent("snapshot.json"); try snap.jsonData().write(to: snapURL)
    files.append(["file": "snapshot.json", "bytes": (try Data(contentsOf: snapURL)).count, "sha256": try sha(snapURL)])
    let manifest: [String: Any] = ["source": ["file": URL(fileURLWithPath: path).lastPathComponent, "lines": src.lines, "sha256": src.sha256],
                                   "title": doc.title, "parts": doc.assembly.parts.count, "steps": doc.steps.count, "checks": checks(doc),
                                   "framesRendered": frames, "renderSecondsPerFrame": frames > 0 ? seconds / Double(frames) : 0, "outputs": files]
    try Data(json(manifest).utf8).write(to: out.appendingPathComponent("manifest.json"))
    finished = true
    print(json(["ok": true, "output": out.path, "files": files.map { $0["file"]! }]))
    return 0
}

@main struct MartySolidCLI {
    @MainActor static func main() {
        let a = Array(CommandLine.arguments.dropFirst())
        do {
            switch a.first {
            case "check"? where a.count == 2: exit(try check(a[1]))
            case "render"? where a.count >= 3 && !a[1].hasPrefix("--") && !a[2].hasPrefix("--"):
                var w = 1280, h = 800, loop = true
                var rest = Array(a.dropFirst(3))
                while let flag = rest.first {
                    rest.removeFirst()
                    switch flag {
                    case "--no-loop": loop = false
                    case "--size":
                        guard let v = rest.first else { throw CLIError.usage }
                        rest.removeFirst()
                        let p = v.split(separator: "x").compactMap { Int($0) }
                        guard p.count == 2, (320...3840).contains(p[0]), (200...2160).contains(p[1]) else { throw CLIError.usage }
                        w = p[0]; h = p[1]
                    default: throw CLIError.usage
                    }
                }
                exit(try render(a[1], a[2], width: w, height: h, loop: loop))
            default: throw CLIError.usage
            }
        } catch {
            FileHandle.standardError.write(Data("\(error)\n".utf8)); exit(2)
        }
    }
}
