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
        case .usage: return """
            Usage: marty-solid check FILE.json [--strict] [--component C.json ...]
                   marty-solid render FILE.json NEW_DIR [--size WxH] [--no-loop] [--component C.json ...]
                   marty-solid components [--component C.json ...]
                   marty-solid component check C.json [--component OTHER.json ...] [--with NAME=VALUE ...]
            """
        case .invalid(let s): return s
        }
    }
}

struct Loaded { let data: Data; let lines: Int; let sha256: String }

/// "53 lines"; a minified document on one line is described by its size instead ("812 bytes on one line").
func sourceSize(_ src: Loaded) -> String {
    src.lines > 1 ? "\(src.lines) lines" : "\(src.data.count) bytes on one line"
}

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

/// Engine checks beyond parsing: closed meshes (step section cuts included, as `step.<n>.<part>`) and a gear tooth
/// sweep (when the model has gear meshes).
func checks(_ doc: MGSolidDocument) -> [String: Any] {
    var open = doc.assembly.parts.filter { !$0.mesh.edgeReport.isClosed }.map(\.id).sorted()
    var sections: [[String: Any]] = []
    for (i, step) in doc.steps.enumerated() {
        guard let sec = step.section else { continue }
        var parts: [[String: Any]] = []
        for id in sec.parts {
            guard let cut = sec.cuts[id] else { continue }
            let closed = cut.mesh.edgeReport.isClosed && cut.mesh.signedVolume > 0
            if !closed { open.append("step.\(i + 1).\(id)") }
            parts.append(["part": id, "closed": closed, "triangles": cut.mesh.triangleCount, "capTriangles": cut.capTriangleCount,
                          "capLoops": cut.loops])
        }
        sections.append(["step": i + 1, "normal": [sec.plane.normal.x, sec.plane.normal.y, sec.plane.normal.z], "offset": sec.plane.offset,
                         "parts": parts])
    }
    var out: [String: Any] = ["meshesClosed": open.isEmpty, "openMeshes": open]
    if !sections.isEmpty { out["sections"] = sections }
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

/// The built-in components plus extra definitions from `--component` files (each validated and compiled on its own,
/// in order, so a later file may use an earlier one). A refused file is reported like a refused model.
struct LibraryRefused: Error { let report: [String: Any] }

func library(_ files: [String]) throws -> MGSolidLibrary {
    var lib = MGSolidLibrary.builtIn
    for path in files {
        let src: Loaded
        do { src = try load(path) } catch is TooLarge {
            throw LibraryRefused(report: ["ok": false, "reason": "component.bytes", "part": NSNull(), "component": path])
        }
        if case .failure(let issue) = lib.register(src.data) {
            throw LibraryRefused(report: ["ok": false, "reason": issue.reason, "part": issue.part as Any, "component": path])
        }
    }
    return lib
}

/// Honesty data for the repair loop: warnings, facts with tiers, the tier legend, what each motion source does not
/// check, and the plain-words read-back of every part.
func honesty(_ doc: MGSolidDocument) -> [String: Any] {
    var facts: [String: Any] = [:]
    for (name, f) in doc.facts {
        facts[name] = ["value": f.value, "unit": f.unit, "text": f.text, "tier": f.tier.name, "source": f.source]
    }
    let legend = doc.legend
    let claims: [[String: Any]] = legend.claims.map { ["kind": $0.kind.rawValue, "id": $0.id, "tier": $0.tier.name, "badge": $0.badge, "why": $0.why] }
    var notChecked: [String: Any] = [:]
    for s in Set(doc.motionSources.values) { if let list = MGSolidNotChecked.bySource[s] { notChecked[s] = list } }
    return ["version": doc.version,
            "warnings": doc.warnings.map { ["reason": $0.reason, "part": $0.part as Any] },
            "facts": facts,
            "legend": ["text": legend.text, "solved": legend.solved, "built": legend.built, "described": legend.described,
                       "note": legend.note as Any, "shapes": legend.shapes, "claims": claims],
            "stepTiers": doc.steps.map { $0.tier?.name as Any },
            // Which fact filled each placeholder, in order, and what each step's checks proved: a grader or a model
            // can see that "3 times slower" came from `count.stage.planet`, not from a speed.
            "stepFacts": doc.steps.map { s in
                ["facts": s.facts,
                 "checks": s.checks.map { c -> [String: Any] in
                     ["value": c.value, "comparison": c.comparison.rawValue, "target": c.target, "tolerance": c.tolerance as Any, "text": c.text]
                 }] as [String: Any]
            },
            "notChecked": notChecked,
            "readBack": doc.readBack]
}

/// `--strict` is the model-harness profile (owner D3): the warnings it lists refuse the document. The report is still
/// printed in full, so the author can repair from it.
func check(_ path: String, _ lib: MGSolidLibrary, strict: Bool = false) throws -> Int32 {
    let src: Loaded
    do { src = try load(path) } catch is TooLarge {
        print(json(["ok": false, "reason": "assembly.bytes", "part": NSNull()])); return 1
    }
    switch MGSolidParser.document(data: src.data, library: lib) {
    case .failure(let issue):
        print(json(["ok": false, "reason": issue.reason, "part": issue.part as Any, "strict": strict, "file": ["lines": src.lines, "sha256": src.sha256]]))
        return 1
    case .success(let doc):
        let c = checks(doc)
        let tris = doc.assembly.parts.reduce(0) { $0 + $1.mesh.triangleCount }
        var reason: String? = nil, part: String? = nil
        if (c["meshesClosed"] as? Bool) != true { reason = "check.meshOpen" }
        else if (c["gearsEngage"] as? Bool) == false { reason = "check.gearsInterpenetrate" }
        else if let refusal = (strict ? MGSolidProfile.strict : .standard).refusal(doc) { reason = refusal.reason; part = refusal.part }
        let ok = reason == nil
        var report: [String: Any] = ["ok": ok, "reason": reason as Any, "title": doc.title, "parts": doc.assembly.parts.count, "triangles": tris,
                                     "steps": doc.steps.map(\.say), "ratios": doc.ratios, "checks": c, "strict": strict,
                                     "file": ["lines": src.lines, "sha256": src.sha256]]
        if part != nil { report["part"] = part as Any }
        report.merge(honesty(doc)) { a, _ in a }
        print(json(report))
        return ok ? 0 : 1
    }
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
        print(json(["ok": false, "reason": "component.bytes", "part": NSNull()])); return 1
    }
    var lib = base
    let component: MGSolidComponent
    switch lib.register(src.data) {
    case .failure(let issue):
        print(json(["ok": false, "reason": issue.reason, "part": issue.part as Any, "file": ["lines": src.lines, "sha256": src.sha256]]))
        return 1
    case .success(let c): component = c
    }
    switch lib.instantiate(component.id, with: values) {
    case .failure(let issue):
        print(json(["ok": false, "reason": issue.reason, "part": issue.part as Any, "id": component.id, "with": values,
                    "file": ["lines": src.lines, "sha256": src.sha256]]))
        return 1
    case .success(let doc):
        let c = checks(doc)
        let tris = doc.assembly.parts.reduce(0) { $0 + $1.mesh.triangleCount }
        var reason: String? = nil
        if (c["meshesClosed"] as? Bool) != true { reason = "check.meshOpen" }
        else if (c["gearsEngage"] as? Bool) == false { reason = "check.gearsInterpenetrate" }
        let defaults = Dictionary(uniqueKeysWithValues: component.params.map { ($0.name, values[$0.name] ?? $0.defaultValue) })
        print(json(["ok": reason == nil, "reason": reason as Any, "id": component.id, "with": defaults,
                    "catalogEntry": component.catalogEntry.any,
                    "use": ["id": "a", "use": component.id, "with": defaults],
                    "instance": ["parts": doc.assembly.parts.count, "triangles": tris, "ratios": doc.ratios, "checks": c],
                    "file": ["lines": src.lines, "bytes": src.data.count, "sha256": src.sha256]]))
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

@MainActor func render(_ path: String, _ outPath: String, width: Int, height: Int, loop: Bool, library lib: MGSolidLibrary) throws -> Int32 {
    let src: Loaded
    do { src = try load(path) } catch is TooLarge {
        print(json(["ok": false, "reason": "assembly.bytes", "part": NSNull()])); return 1
    }
    let doc: MGSolidDocument
    switch MGSolidParser.document(data: src.data, library: lib) {
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
    let footer = "Rendered by the MartyGraphics solid engine from \(URL(fileURLWithPath: path).lastPathComponent) (\(sourceSize(src)))"
    var files: [[String: Any]] = []
    var seconds = 0.0, frames = 0
    func shot(_ params: MGPoseParameters, preset: String, orbit: Double = 0, highlight: [String] = [], margin: Double = 0.8,
              step: Int? = nil) throws -> CGImage {
        let p = MGSolidCamera.presets[preset] ?? MGSolidCamera.presets["hero"]!
        // Each step shows its own section cuts and ghosts; other shots show the plain scene.
        r.show(doc.view(step: step))
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
        let img = try shot(params, preset: step.camera ?? "hero", orbit: step.orbit, highlight: step.highlight, step: i)
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
    // v1 documents keep the v1 snapshot; v2 documents export format v2 (part opacity, emission).
    let snap = doc.version >= 2 ? MGSolidSnapshot.make(doc, step: nil, params: doc.defaults) : MGSolidSnapshot.make(doc.assembly, params: doc.defaults)
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
            do { lib = try library(files) } catch let e as LibraryRefused { print(json(e.report)); exit(1) }
            switch a.first {
            case "check"? where a.count >= 2:
                let rest = Array(a.dropFirst())
                let paths = rest.filter { $0 != "--strict" }
                guard paths.count == 1, !paths[0].hasPrefix("--"), rest.count - paths.count <= 1 else { throw CLIError.usage }
                exit(try check(paths[0], lib, strict: rest.contains("--strict")))
            case "components"? where a.count == 1: exit(components(lib))
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
                exit(try render(a[1], a[2], width: w, height: h, loop: loop, library: lib))
            default: throw CLIError.usage
            }
        } catch {
            FileHandle.standardError.write(Data("\(error)\n".utf8)); exit(2)
        }
    }
}
