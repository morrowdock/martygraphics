// SPDX-License-Identifier: Apache-2.0
import CoreGraphics
import CoreText
import Foundation
import Metal
import simd
import MartyGraphicsPathTracer

struct Options {
    var command = ""
    var output: URL?
    var width = 1920
    var height = 1080
    var spp = 256
    var fps = 24
    var seconds = Gearbox.loopSeconds
    var views = ["hero", "exploded", "macro"]
    var times: [Double] = []
    var seed: UInt32 = 1
    var denoise = true
    var label = ""
    var debugFlags: UInt32 = 0
    var denoiseStrength: Float = 6

    static let usage = """
    Usage:
      marty-pathtrace --verify
      marty-pathtrace --still NEW_DIR [--size 1920x1080] [--spp 256] [--views hero,exploded,macro] [--no-denoise]
      marty-pathtrace --loop NEW_DIR [--size 1280x720] [--spp 48] [--fps 24]
      marty-pathtrace --frames NEW_DIR --times 0,5,8.3 [--size 960x540] [--spp 32]
      marty-pathtrace --sidebyside NEW_DIR [--size 1920x1080] [--spp 256]
    Common: [--seed N] [--label TEXT] [--no-denoise] [--denoise-strength 6]
            [--debug-flags N]  (4 = shading normals, 8 = geometric normals, 16 = no path regularisation)
    --label is copied into the JSON metadata (e.g. a commit id).
    """

    init(_ args: [String]) throws {
        var i = 0
        func value() throws -> String {
            i += 1
            guard i < args.count else { throw ExportError.failed(Self.usage) }
            return args[i]
        }
        while i < args.count {
            let a = args[i]
            switch a {
            case "--verify": command = "verify"
            case "--still", "--loop", "--frames", "--sidebyside":
                command = String(a.dropFirst(2))
                output = URL(fileURLWithPath: try value(), isDirectory: true)
            case "--size":
                let parts = try value().split(separator: "x").compactMap { Int($0) }
                guard parts.count == 2, parts[0] > 0, parts[1] > 0 else { throw ExportError.failed("--size WxH") }
                width = parts[0]; height = parts[1]
            case "--spp": spp = max(1, Int(try value()) ?? 1)
            case "--fps": fps = max(1, Int(try value()) ?? 24)
            case "--views": views = try value().split(separator: ",").map(String.init)
            case "--times": times = try value().split(separator: ",").compactMap { Double($0) }
            case "--seed": seed = UInt32(try value()) ?? 1
            case "--label": label = try value()
            case "--no-denoise": denoise = false
            case "--debug-flags": debugFlags = UInt32(try value()) ?? 0
            case "--denoise-strength": denoiseStrength = Float(try value()) ?? 6
            default: throw ExportError.failed("Unknown argument \(a)\n" + Self.usage)
            }
            i += 1
        }
        guard !command.isEmpty else { throw ExportError.failed(Self.usage) }
    }
}

@main struct PathTraceCLI {
    static func main() {
        do {
            let options = try Options(Array(CommandLine.arguments.dropFirst()))
            switch options.command {
            case "verify": try verify()
            case "still": try stills(options)
            case "loop": try loop(options)
            case "frames": try frames(options)
            case "sidebyside": try sideBySide(options)
            default: throw ExportError.failed(Options.usage)
            }
        } catch {
            FileHandle.standardError.write(Data("error: \(error)\n".utf8))
            exit(1)
        }
    }

    static func newDirectory(_ url: URL?) throws -> URL {
        guard let url else { throw ExportError.failed(Options.usage) }
        guard !FileManager.default.fileExists(atPath: url.path) else {
            throw ExportError.failed("Output directory already exists; choose a new directory")
        }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func settings(_ o: Options, spp: Int? = nil, seed: UInt32? = nil) -> MGRTSettings {
        var s = MGRTSettings(width: o.width, height: o.height, samplesPerPixel: spp ?? o.spp, maxBounces: 8, seed: seed ?? o.seed,
                             exposure: 0.35, denoise: o.denoise, clampIndirect: 4, environmentSelectProbability: 0.45,
                             tileSize: 512, vignette: 0.22, bloom: 0.06)
        s.debugFlags = o.debugFlags
        s.denoiseStrength = o.denoiseStrength
        if o.debugFlags & 12 != 0 { s.exposure = 0; s.vignette = 0; s.bloom = 0; s.denoise = false }
        return s
    }

    static func describe(_ s: MGRTSettings, _ stats: MGRTRenderer.Stats) -> [String: Any] {
        ["width": stats.width, "height": stats.height, "samplesPerPixel": stats.samplesPerPixel,
         "maxBounces": s.maxBounces, "seed": Int(s.seed), "denoise": s.denoise, "clampIndirect": Double(s.clampIndirect),
         "exposureStops": Double(s.exposure), "vignette": Double(s.vignette), "glare": Double(s.bloom),
         "traceGPUms": stats.traceMilliseconds.rounded(), "postGPUms": stats.postMilliseconds.rounded(),
         "wallms": stats.wallMilliseconds.rounded(), "triangles": stats.triangles, "instances": stats.instances]
    }

    // MARK: verify

    static func verify() throws {
        var failures: [String] = []
        func check(_ ok: Bool, _ what: String) {
            print((ok ? "PASS " : "FAIL ") + what)
            if !ok { failures.append(what) }
        }
        let specs = [(Gearbox.sunTeeth, Gearbox.planetModule), (Gearbox.planetTeeth, Gearbox.planetModule),
                     (Gearbox.spurTeeth, Gearbox.spurModule), (Gearbox.pinionTeeth, Gearbox.spurModule)]
        for (z, m) in specs {
            check(Involute.isAngularlyMonotonic(Involute.external(Involute.Spec(teeth: z, module: m))),
                  "external \(z)-tooth outline is star-shaped (polar angle strictly increases)")
        }
        check(Involute.isAngularlyMonotonic(Involute.internal(Involute.Spec(teeth: Gearbox.ringTeeth, module: Gearbox.planetModule))),
              "internal \(Gearbox.ringTeeth)-tooth outline is star-shaped")
        check((Gearbox.sunTeeth + Gearbox.ringTeeth) % Gearbox.planets == 0, "planet assembly condition (Zs + Zr) / 3 is an integer")
        check(Gearbox.ringTeeth == Gearbox.sunTeeth + 2 * Gearbox.planetTeeth, "coaxial condition Zr = Zs + 2 Zp")

        let box = Gearbox()
        for part in Gearbox.Part.allCases where part != .floor {
            let v = box.meshes[box.partMesh[part]!].signedVolume
            check(v > 0, "\(part) mesh is closed and wound outward (signed volume \(String(format: "%.4f", v)))")
        }
        var worst = 0.0
        for i in 0...600 {
            let pose = Gearbox.pose(carrier: Double(i) * 0.01)
            worst = max(worst, Gearbox.ringResidual(pose).map(abs).max() ?? 0)
        }
        check(worst < 1e-9, "planet/ring mesh phase residual over 600 poses < 1e-9 tooth (max \(worst))")
        let p0 = Gearbox.pose(carrier: 0), p1 = Gearbox.pose(carrier: Gearbox.carrierPerLoop)
        func pitches(_ a: Double, _ z: Int) -> Double { a * Double(z) / (2 * .pi) }
        func isInteger(_ x: Double) -> Bool { abs(x - x.rounded()) < 1e-9 }
        check(isInteger(pitches(p1.sun - p0.sun, Gearbox.sunTeeth)), "sun advances a whole number of pitches per loop")
        check(isInteger(pitches(p1.spur - p0.spur, Gearbox.spurTeeth)), "spur gear advances whole pitches per loop")
        check(isInteger(pitches(p1.pinion - p0.pinion, Gearbox.pinionTeeth)), "pinion advances whole pitches per loop")
        check(isInteger(pitches(p1.planet[0] - p0.planet[1], Gearbox.planetTeeth)), "planet 0 ends in planet 1's pose (mod pitch)")
        let ratio = (p1.pinion - p0.pinion) / (p1.carrier - p0.carrier)
        check(abs(abs(ratio) - Gearbox.stage1Ratio * Gearbox.stage2Ratio) < 1e-9,
              "overall reduction pinion:carrier = \(String(format: "%.3f", abs(ratio))):1 (expected 7:1)")
        check(Gearbox.explode(0, layer: 4) == 0 && Gearbox.explode(Gearbox.loopSeconds, layer: 0) == 0,
              "explode beat starts and ends assembled")
        let c0 = Gearbox.camera(at: 0, explode: 0), c1 = Gearbox.camera(at: Gearbox.loopSeconds, explode: 0)
        check(simd_distance(c0.position, c1.position) < 1e-4, "camera path is periodic")

        let env = MGRTEnvironment.studio(width: 256, height: 128)
        let dist = env.makeDistribution()
        let mass = dist.pdfUV.reduce(0.0) { $0 + Double($1) } / Double(dist.pdfUV.count)
        check(abs(mass - 1) < 1e-4, "environment importance distribution sums to 1 (\(mass))")
        let scene = box.scene(camera: c0)
        do { try scene.validate(); check(true, "scene validates (\(box.triangleCount) triangles, \(scene.instances.count) instances)") }
        catch { check(false, "scene validates: \(error)") }

        if MGRTRenderer.isSupported {
            let r = try MGRTRenderer(scene: scene)
            let out = try r.render(settings: MGRTSettings(width: 96, height: 54, samplesPerPixel: 4), camera: c0,
                                   transforms: box.frame(at: 0).transforms)
            let luma = stride(from: 0, to: out.rgba8.count, by: 4).map { Int(out.rgba8[$0 + 1]) }
            check((luma.max() ?? 0) > 60 && (luma.min() ?? 255) < 40, "GPU smoke render 96x54 @ 4 spp has highlights and shadows")
        } else {
            print("SKIP GPU smoke render: no Metal ray-tracing device")
        }
        guard failures.isEmpty else { throw ExportError.failed("\(failures.count) check(s) failed") }
        print("All checks passed.")
    }

    // MARK: stills

    struct View { var name: String; var camera: MGRTCamera; var transforms: [simd_float4x4]; var note: String }

    static func views(_ box: Gearbox) -> [String: View] {
        let assembled = box.transforms(Gearbox.pose(carrier: 0.35), lift: [:])
        let heroTarget = SIMD3<Float>(0.15, 0.9, -0.1)
        let heroYaw: Float = -38 * .pi / 180, heroElevation: Float = 25 * .pi / 180
        let heroPos = heroTarget + 11.6 * SIMD3(cos(heroElevation) * sin(heroYaw), sin(heroElevation), cos(heroElevation) * cos(heroYaw))
        let hero = MGRTCamera(position: heroPos, target: heroTarget, verticalFOVDegrees: 26,
                              apertureRadius: 0.05, focusDistance: simd_distance(heroPos, heroTarget) - 1.2)
        let tPeak = 0.5 * Gearbox.loopSeconds
        let peak = box.frame(at: tPeak)
        let exploded = Gearbox.camera(at: tPeak, explode: peak.explode, aperture: 0.04)
        // Macro: the planet/ring mesh nearest the camera, shallow depth of field.
        let carrier = 1.92
        let macroPose = Gearbox.pose(carrier: carrier)
        let beta = macroPose.planetCentre[0]
        let contact = SIMD3<Float>(2.36 * Float(cos(beta)), 0.86, 2.36 * Float(sin(beta)))
        let side = beta + 0.55
        let out = SIMD3<Float>(Float(cos(side)), 0, Float(sin(side)))
        let macroPos = contact + 2.5 * (0.86 * out + 0.5 * SIMD3(0, 1, 0)) + SIMD3(0, 0.2, 0)
        let macro = MGRTCamera(position: macroPos, target: contact - SIMD3(0, 0.08, 0), verticalFOVDegrees: 32,
                               apertureRadius: 0.07, focusDistance: simd_distance(macroPos, contact))
        return [
            "hero": View(name: "hero", camera: hero, transforms: assembled, note: "assembled gearbox, three-quarter view"),
            "exploded": View(name: "exploded", camera: exploded, transforms: peak.transforms,
                             note: "loop frame at t = \(tPeak) s (exploded beat)"),
            "macro": View(name: "macro", camera: macro, transforms: box.transforms(macroPose, lift: [:]),
                          note: "planet/ring mesh close-up, shallow depth of field"),
        ]
    }

    static func stills(_ o: Options) throws {
        let dir = try newDirectory(o.output)
        let box = Gearbox()
        let all = views(box)
        let renderer = try MGRTRenderer(scene: box.scene(camera: all["hero"]!.camera))
        var records: [[String: Any]] = []
        for name in o.views {
            guard let view = all[name] else { throw ExportError.failed("Unknown view \(name)") }
            let s = settings(o)
            let out = try renderer.render(settings: s, camera: view.camera, transforms: view.transforms)
            guard let image = out.cgImage() else { throw ExportError.failed("No image") }
            let url = dir.appendingPathComponent("\(name).png")
            try Export.png(image, to: url)
            var rec = describe(s, out.stats)
            rec["file"] = url.lastPathComponent
            rec["sha256"] = try Export.sha256(url)
            rec["bytes"] = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            rec["view"] = view.note
            records.append(rec)
            print("\(name): \(out.width)x\(out.height) \(out.stats.samplesPerPixel) spp, trace \(Int(out.stats.traceMilliseconds)) ms GPU, wall \(Int(out.stats.wallMilliseconds)) ms")
        }
        try Export.writeJSON(["renderer": "MartyGraphicsPathTracer (Metal ray tracing, compute)", "label": o.label,
                              "stills": records], to: dir.appendingPathComponent("stills.json"))
    }

    // MARK: loop

    static func loop(_ o: Options) throws {
        let dir = try newDirectory(o.output)
        let box = Gearbox()
        let count = Int((o.seconds * Double(o.fps)).rounded())
        let first = box.frame(at: 0)
        let renderer = try MGRTRenderer(scene: box.scene(camera: Gearbox.camera(at: 0, explode: 0)))
        let video = try VideoWriter(url: dir.appendingPathComponent("gearbox-loop.mp4"), width: o.width, height: o.height,
                                    fps: o.fps, bitsPerSecond: o.width * o.height * 12)
        let gifStep = max(1, o.fps / 12)
        let gifW = 480, gifH = Int((Double(gifW) * Double(o.height) / Double(o.width)).rounded())
        let gif = try GIFWriter(url: dir.appendingPathComponent("gearbox-loop.gif"), frameCount: (count + gifStep - 1) / gifStep,
                                delay: Double(gifStep) / Double(o.fps))
        var frameRecords: [[String: Any]] = []
        let started = Date()
        _ = first
        for i in 0..<count {
            let t = Double(i) / Double(o.fps)
            let f = box.frame(at: t)
            let cam = Gearbox.camera(at: t, explode: f.explode)
            let s = settings(o, seed: o.seed &+ UInt32(i) &* 7919)
            let out = try renderer.render(settings: s, camera: cam, transforms: f.transforms)
            try video.append(rgba: out.rgba8)
            guard let image = out.cgImage() else { throw ExportError.failed("No image") }
            if i % gifStep == 0, let small = Export.scaled(image, width: gifW, height: gifH) { gif.add(small) }
            if i == 0 { try Export.png(image, to: dir.appendingPathComponent("poster.png")) }
            if i % (o.fps * 2) == 0 { try Export.png(image, to: dir.appendingPathComponent(String(format: "frame-%04d.png", i))) }
            frameRecords.append(["frame": i, "t": t, "spp": out.stats.samplesPerPixel,
                                 "traceGPUms": out.stats.traceMilliseconds.rounded(), "wallms": out.stats.wallMilliseconds.rounded()])
            let elapsed = Date().timeIntervalSince(started)
            print(String(format: "frame %d/%d t=%.3f s: %d spp, %.0f ms wall (elapsed %.0f s, eta %.0f s)", i + 1, count, t,
                         out.stats.samplesPerPixel, out.stats.wallMilliseconds, elapsed,
                         elapsed / Double(i + 1) * Double(count - i - 1)))
        }
        try video.finish()
        try gif.finish()
        let total = Date().timeIntervalSince(started)
        var files: [[String: Any]] = []
        for name in ["gearbox-loop.mp4", "gearbox-loop.gif", "poster.png"] {
            let url = dir.appendingPathComponent(name)
            files.append(["file": name, "sha256": try Export.sha256(url),
                          "bytes": (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0])
        }
        let s = settings(o)
        try Export.writeJSON(["renderer": "MartyGraphicsPathTracer (Metal ray tracing, compute)", "label": o.label,
                              "width": o.width, "height": o.height, "fps": o.fps, "frames": count, "seconds": o.seconds,
                              "samplesPerPixelPerFrame": o.spp, "denoise": s.denoise, "gifWidth": gifW, "gifFPS": Double(o.fps) / Double(gifStep),
                              "totalWallSeconds": total.rounded(), "files": files, "frameTimings": frameRecords],
                             to: dir.appendingPathComponent("loop.json"))
        print(String(format: "Loop done: %d frames in %.0f s (%.2f s/frame).", count, total, total / Double(count)))
    }

    static func frames(_ o: Options) throws {
        let dir = try newDirectory(o.output)
        let box = Gearbox()
        let renderer = try MGRTRenderer(scene: box.scene(camera: Gearbox.camera(at: 0, explode: 0)))
        for t in o.times.isEmpty ? [0] : o.times {
            let f = box.frame(at: t)
            let out = try renderer.render(settings: settings(o), camera: Gearbox.camera(at: t, explode: f.explode),
                                          transforms: f.transforms)
            guard let image = out.cgImage() else { throw ExportError.failed("No image") }
            try Export.png(image, to: dir.appendingPathComponent(String(format: "t%06.3f.png", t)))
            print(String(format: "t=%.3f: %d spp, trace %.0f ms GPU, wall %.0f ms", t, out.stats.samplesPerPixel,
                         out.stats.traceMilliseconds, out.stats.wallMilliseconds))
        }
    }

    // MARK: side by side

    /// The gear-train lines of Gearbox.swift, read from the source file this binary was built from.
    static func gearTrainSource() throws -> (lines: [String], first: Int, last: Int) {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Gearbox.swift")
        let all = try String(contentsOf: url, encoding: .utf8).components(separatedBy: "\n")
        guard let b = all.firstIndex(where: { $0.contains("GEAR TRAIN BEGIN") }),
              let e = all.firstIndex(where: { $0.contains("GEAR TRAIN END") }), e > b + 1 else {
            throw ExportError.failed("Gear train markers not found in \(url.path)")
        }
        let lines = Array(all[(b + 1)..<e])
        // Guard the claim: the quoted lines must be exactly the values this binary uses.
        // Whole-token match, so `pinionTeeth = 150` on disk cannot pass for a built value of 15.
        let tokens = lines.joined(separator: " ").replacingOccurrences(of: ",", with: " ").split(separator: " ").map(String.init)
        func quoted(_ name: String, _ value: String) -> Bool {
            tokens.indices.contains { i in tokens[i] == name && i + 2 < tokens.count && tokens[i + 1] == "=" && tokens[i + 2] == value }
        }
        let expected: [(String, String)] = [("pinionTeeth", "\(Gearbox.pinionTeeth)"), ("spurTeeth", "\(Gearbox.spurTeeth)"),
                                            ("sunTeeth", "\(Gearbox.sunTeeth)"), ("planetTeeth", "\(Gearbox.planetTeeth)"),
                                            ("ringTeeth", "\(Gearbox.ringTeeth)"), ("spurModule", "\(Gearbox.spurModule)"),
                                            ("planetModule", "\(Gearbox.planetModule)"), ("planets", "\(Gearbox.planets)")]
        for (name, value) in expected where !quoted(name, value) {
            throw ExportError.failed("Source on disk differs from the built binary (\(name) = \(value)); rebuild first")
        }
        return (lines, b + 2, e)  // 1-based line numbers
    }

    /// The GPU this render actually ran on, for the caption (never a hard-coded model name).
    static func gpuName() -> String {
        guard let name = MTLCreateSystemDefaultDevice()?.name, !name.isEmpty else { return "this Mac's GPU" }
        return "the " + name + " GPU"
    }

    static func drawText(_ ctx: CGContext, _ text: String, x: CGFloat, y: CGFloat, size: CGFloat, font: String,
                         color: CGColor, highlightNumbers: CGColor? = nil) {
        let f = CTFontCreateWithName(font as CFString, size, nil)
        let attr = NSMutableAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): f,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color])
        if let num = highlightNumbers, let re = try? NSRegularExpression(pattern: "(?<![A-Za-z_])[0-9]+(\\.[0-9]+)?") {
            for m in re.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length)) {
                attr.addAttribute(NSAttributedString.Key(kCTForegroundColorAttributeName as String), value: num, range: m.range)
            }
        }
        let line = CTLineCreateWithAttributedString(attr)
        ctx.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(line, ctx)
    }

    static func sideBySide(_ o: Options) throws {
        // The left panel is 780 px wide; the render needs some width of its own.
        guard o.width > 780 + 64, o.height > 64 else {
            throw ExportError.failed("--sidebyside needs a size wider than 844 pixels (the code panel is 780 wide)")
        }
        let dir = try newDirectory(o.output)
        let source = try gearTrainSource()
        let box = Gearbox()
        let panel = 780
        let renderW = o.width - panel, renderH = o.height
        let all = views(box)
        var cam = all["hero"]!.camera
        cam.verticalFOVDegrees = 36  // the right panel is nearly square; keep the whole assembly in frame
        let renderer = try MGRTRenderer(scene: box.scene(camera: cam))
        var s = settings(o)
        s.width = renderW
        s.height = renderH
        let out = try renderer.render(settings: s, camera: cam, transforms: all["hero"]!.transforms)
        guard let render = out.cgImage() else { throw ExportError.failed("No image") }

        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: o.width, height: o.height, bitsPerComponent: 8, bytesPerRow: o.width * 4,
                                  space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            throw ExportError.failed("No context")
        }
        ctx.setFillColor(CGColor(srgbRed: 0.035, green: 0.038, blue: 0.045, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: o.width, height: o.height))
        ctx.draw(render, in: CGRect(x: panel, y: 0, width: renderW, height: renderH))
        ctx.setFillColor(CGColor(srgbRed: 0.2, green: 0.21, blue: 0.24, alpha: 1))
        ctx.fill(CGRect(x: panel - 1, y: 0, width: 1, height: o.height))

        let grey = CGColor(srgbRed: 0.55, green: 0.57, blue: 0.62, alpha: 1)
        let light = CGColor(srgbRed: 0.88, green: 0.89, blue: 0.92, alpha: 1)
        let amber = CGColor(srgbRed: 0.98, green: 0.76, blue: 0.36, alpha: 1)
        let H = CGFloat(o.height)
        let left: CGFloat = 64
        drawText(ctx, "TOOTH COUNTS AND MODULES", x: left, y: H - 150, size: 20, font: "Helvetica-Bold", color: grey)
        drawText(ctx, "Gearbox.swift, lines \(source.first)–\(source.last), verbatim (indentation trimmed)", x: left, y: H - 182,
                 size: 18, font: "Helvetica", color: grey)
        var y = H - 262
        for line in source.lines {
            drawText(ctx, line.trimmingCharacters(in: .whitespaces), x: left, y: y, size: 19, font: "Menlo", color: light,
                     highlightNumbers: amber)
            y -= 40
        }
        y -= 40
        let s1 = Gearbox.stage1Ratio, s2 = Gearbox.stage2Ratio
        func row(_ a: String, _ b: String, _ r: Double) -> String {
            a.padding(toLength: 9, withPad: " ", startingAt: 0) + b.padding(toLength: 22, withPad: " ", startingAt: 0)
                + String(format: "%.1f : 1", r)
        }
        let facts = [
            "Computed at run time from those values:",
            row("spur", "\(Gearbox.spurTeeth) / \(Gearbox.pinionTeeth)", s1),
            row("planet", "1 + \(Gearbox.ringTeeth) / \(Gearbox.sunTeeth)", s2),
            row("overall", "", s1 * s2),
            "+ involute flanks, root fillets and the",
            "  meshing phase of every gear",
        ]
        for (i, f) in facts.enumerated() {
            drawText(ctx, f, x: left, y: y, size: i == 0 ? 18 : 18, font: i == 0 ? "Helvetica" : "Menlo",
                     color: i == 0 ? grey : light, highlightNumbers: i == 0 ? nil : amber)
            y -= 34
        }
        let minutes = out.stats.wallMilliseconds / 60000
        let caption = [
            "Right: path traced by MartyGraphicsPathTracer on \(gpuName()).",
            String(format: "%dx%d, %d samples per pixel, %.1f min; %d triangles (%d unique).", renderW, renderH,
                   out.stats.samplesPerPixel, minutes, box.triangleCount, out.stats.triangles),
            "Procedural geometry and studio lighting; no images, models or stock assets.",
        ]
        y = 150
        for c in caption {
            drawText(ctx, c, x: left, y: y, size: 16, font: "Helvetica", color: grey)
            y -= 26
        }
        guard let image = ctx.makeImage() else { throw ExportError.failed("No image") }
        let url = dir.appendingPathComponent("side-by-side.png")
        try Export.png(image, to: url)
        var rec = describe(s, out.stats)
        rec["file"] = url.lastPathComponent
        rec["sha256"] = try Export.sha256(url)
        rec["quotedLines"] = source.lines
        rec["quotedLineRange"] = [source.first, source.last]
        rec["label"] = o.label
        try Export.writeJSON(rec, to: dir.appendingPathComponent("side-by-side.json"))
        print("side-by-side: render \(renderW)x\(renderH) \(out.stats.samplesPerPixel) spp, \(Int(out.stats.wallMilliseconds)) ms; quoted lines \(source.first)-\(source.last)")
    }
}
