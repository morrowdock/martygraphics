// SPDX-License-Identifier: Apache-2.0
import AppKit
import AVFoundation
import CoreText
import CryptoKit
import Foundation
import ImageIO
import SceneKit
import UniformTypeIdentifiers
import MartyGraphics

private enum Solid3DError: Error, CustomStringConvertible {
    case invalid(String)
    var description: String { switch self { case .invalid(let m): return m } }
}

// MARK: Model source

private struct Source {
    let document: MGSolidDocument
    let data: Data
    let lines: Int
    let sha256: String
}

private func loadPlanetary() throws -> Source {
    guard let url = Bundle.module.url(forResource: "planetary", withExtension: "json", subdirectory: "Models") else {
        throw Solid3DError.invalid("Missing bundled model planetary.json")
    }
    let data = try Data(contentsOf: url)
    let doc: MGSolidDocument
    switch MGSolidParser.document(data: data) {
    case .success(let d): doc = d
    case .failure(let e): throw Solid3DError.invalid("planetary.json rejected: \(e)")
    }
    let text = String(decoding: data, as: UTF8.self)
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false).count - (text.hasSuffix("\n") ? 1 : 0)
    let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    return Source(document: doc, data: data, lines: lines, sha256: hash)
}

// MARK: Verify

private func verify(_ src: Source) throws {
    let doc = src.document
    print("Parsed planetary.json: \(src.lines) lines, sha256 \(src.sha256.prefix(16))..., \(doc.assembly.parts.count) parts, \(doc.steps.count) steps.")
    guard let sun = doc.gears["sun"]?.teeth, let ring = doc.gears["ring"]?.teeth, let carrier = doc.ratios["carrier"] else {
        throw Solid3DError.invalid("model lacks sun, ring or carrier")
    }
    let expected = Double(sun) / Double(sun + ring)
    guard abs(carrier - expected) < 1e-12 else { throw Solid3DError.invalid("carrier ratio \(carrier) != \(expected)") }
    print(String(format: "Carrier ratio solved from the gear-mesh constraints: %.6f (Zs/(Zs+Zr) = %d/%d).", carrier, sun, sun + ring))
    var worstResidual = 0.0
    for k in 0..<50 { for r in doc.assembly.gearResiduals(MGPoseParameters(input: Double(k) * 0.37)) { worstResidual = max(worstResidual, abs(r)) } }
    guard worstResidual < 1e-9 else { throw Solid3DError.invalid("gear residual \(worstResidual)") }
    let report = MGSolidChecks.gearMeshes(doc, samples: 240, inputRange: 0...(2 * .pi))
    print(String(format: "Tooth sweep: %d pairs x %d sun angles, max penetration %.2e mm, min clearance %.3f mm.",
                 report.pairs, report.samples, report.maxPenetration, report.minClearance))
    guard report.maxPenetration < 1e-6, report.minClearance < 0.3 else { throw Solid3DError.invalid("gears interpenetrate or do not engage") }
    for part in doc.assembly.parts where !part.mesh.edgeReport.isClosed {
        // Parts merged from several closed primitives are still closed per shell; edge pairing holds for the union.
        throw Solid3DError.invalid("mesh not closed: \(part.id)")
    }
    let crank = try MGSolidModels.sliderCrank()
    var crankError = 0.0
    for k in 0..<72 {
        let t = Double(k) * .pi / 36
        let pose = crank.assembly.pose(MGPoseParameters(input: t))
        let pin = pose.world["crank"]!.apply(MGVec3(crank.crankRadius, 0, 0)), end = pose.world["rod"]!.apply(MGVec3(-crank.rodLength, 0, 0))
        crankError = max(crankError, (pin - end).length)
    }
    guard crankError < 1e-9 else { throw Solid3DError.invalid("slider-crank loop error \(crankError)") }
    print(String(format: "Slider-crank loop closure over 72 crank angles: max error %.1e mm.", crankError))
    print("All meshes closed (edge-manifold). Verification passed.")
}

// MARK: Overlays

private struct Label { let text: String; let anchor: CGPoint }

private func font(_ size: CGFloat, _ weight: NSFont.Weight) -> CTFont { NSFont.systemFont(ofSize: size, weight: weight) as CTFont }

private func drawText(_ ctx: CGContext, _ s: String, at p: CGPoint, size: CGFloat, weight: NSFont.Weight, color: CGColor, tracking: CGFloat = 0) {
    let attrs: [NSAttributedString.Key: Any] = [.init(kCTFontAttributeName as String): font(size, weight), .init(kCTForegroundColorAttributeName as String): color,
                                                .init(kCTKernAttributeName as String): tracking]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: attrs))
    ctx.textPosition = p
    CTLineDraw(line, ctx)
}

private func textWidth(_ s: String, size: CGFloat, weight: NSFont.Weight) -> CGFloat {
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: [.init(kCTFontAttributeName as String): font(size, weight)]))
    return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
}

/// Draws captions and leader-line labels over a rendered frame. Coordinates of `labels` are top-left pixel space.
private func overlay(_ image: CGImage, title: String?, subtitle: String?, footer: String?, labels: [Label], labelAlpha: Double, caption: String? = nil) -> CGImage {
    let w = image.width, h = image.height
    let scale = CGFloat(w) / 1280
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    let white = CGColor(srgbRed: 0.95, green: 0.96, blue: 1, alpha: 1)
    let soft = CGColor(srgbRed: 0.70, green: 0.76, blue: 0.90, alpha: 1)
    let accent = CGColor(srgbRed: 0.49, green: 0.61, blue: 1.0, alpha: 1)
    if let t = title {
        drawText(ctx, "MARTYGRAPHICS · SOLID ENGINE", at: CGPoint(x: 40 * scale, y: CGFloat(h) - 52 * scale), size: 12 * scale, weight: .bold, color: accent, tracking: 2 * scale)
        drawText(ctx, t, at: CGPoint(x: 40 * scale, y: CGFloat(h) - 86 * scale), size: 28 * scale, weight: .semibold, color: white)
        if let s = subtitle { drawText(ctx, s, at: CGPoint(x: 40 * scale, y: CGFloat(h) - 112 * scale), size: 15 * scale, weight: .regular, color: soft) }
    }
    if let c = caption {
        let size = 19 * scale, tw = textWidth(c, size: size, weight: .medium)
        let box = CGRect(x: (CGFloat(w) - tw) / 2 - 22 * scale, y: 34 * scale, width: tw + 44 * scale, height: 44 * scale)
        ctx.setFillColor(CGColor(srgbRed: 0.02, green: 0.03, blue: 0.06, alpha: 0.72))
        ctx.addPath(CGPath(roundedRect: box, cornerWidth: 12 * scale, cornerHeight: 12 * scale, transform: nil)); ctx.fillPath()
        drawText(ctx, c, at: CGPoint(x: box.minX + 22 * scale, y: box.minY + 15 * scale), size: size, weight: .medium, color: white)
    }
    if let f = footer {
        let size = 11.5 * scale, tw = textWidth(f, size: size, weight: .regular)
        drawText(ctx, f, at: CGPoint(x: CGFloat(w) - tw - 28 * scale, y: 22 * scale), size: size, weight: .regular,
                 color: CGColor(srgbRed: 0.6, green: 0.65, blue: 0.78, alpha: 0.9))
    }
    if labelAlpha > 0.01 {
        // Keep label boxes on each side at least 32 px apart vertically.
        var placed: [(Label, CGFloat)] = []
        for side in [false, true] {
            var ys: [(Label, CGFloat)] = labels.filter { ($0.anchor.x >= CGFloat(w) * 0.5) == side }
                .map { ($0, CGFloat(h) - $0.anchor.y + 26 * scale) }.sorted { $0.1 > $1.1 }
            for i in ys.indices.dropFirst() where ys[i - 1].1 - ys[i].1 < 32 * scale { ys[i].1 = ys[i - 1].1 - 32 * scale }
            placed += ys
        }
        for (l, labelY) in placed {
            let a = CGPoint(x: l.anchor.x, y: CGFloat(h) - l.anchor.y)
            let right = a.x >= CGFloat(w) * 0.5
            let size = 14 * scale, tw = textWidth(l.text, size: size, weight: .semibold)
            let elbow = CGPoint(x: a.x + (right ? 46 : -46) * scale, y: labelY)
            let end = CGPoint(x: elbow.x + (right ? 28 : -28) * scale, y: elbow.y)
            ctx.setStrokeColor(CGColor(srgbRed: 0.9, green: 0.93, blue: 1, alpha: 0.75 * labelAlpha)); ctx.setLineWidth(1.4 * scale)
            ctx.move(to: a); ctx.addLine(to: elbow); ctx.addLine(to: end); ctx.strokePath()
            ctx.setFillColor(CGColor(srgbRed: 1, green: 0.72, blue: 0.35, alpha: labelAlpha))
            ctx.fillEllipse(in: CGRect(x: a.x - 3.5 * scale, y: a.y - 3.5 * scale, width: 7 * scale, height: 7 * scale))
            let box = CGRect(x: right ? end.x + 4 * scale : end.x - tw - 20 * scale, y: end.y - 13 * scale, width: tw + 16 * scale, height: 26 * scale)
            ctx.setFillColor(CGColor(srgbRed: 0.03, green: 0.04, blue: 0.08, alpha: 0.78 * labelAlpha))
            ctx.addPath(CGPath(roundedRect: box, cornerWidth: 7 * scale, cornerHeight: 7 * scale, transform: nil)); ctx.fillPath()
            drawText(ctx, l.text, at: CGPoint(x: box.minX + 8 * scale, y: box.minY + 8 * scale), size: size, weight: .semibold,
                     color: CGColor(srgbRed: 0.96, green: 0.97, blue: 1, alpha: labelAlpha))
        }
    }
    return ctx.makeImage() ?? image
}

// MARK: Writers

private func writePNG(_ image: CGImage, to url: URL) throws {
    guard let d = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { throw Solid3DError.invalid("PNG \(url.lastPathComponent)") }
    CGImageDestinationAddImage(d, image, nil)
    guard CGImageDestinationFinalize(d) else { throw Solid3DError.invalid("PNG finalize") }
}

private func scaled(_ image: CGImage, width: Int, height: Int) -> CGImage? {
    guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return ctx.makeImage()
}

private final class MovieWriter {
    let writer: AVAssetWriter
    let input: AVAssetWriterInput
    let adaptor: AVAssetWriterInputPixelBufferAdaptor
    let fps: Int32
    let width: Int, height: Int
    var frame: Int64 = 0

    init(url: URL, width: Int, height: Int, fps: Int32, bitrate: Int) throws {
        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: bitrate, AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                                              AVVideoMaxKeyFrameIntervalKey: Int(fps) * 2],
        ])
        input.expectsMediaDataInRealTime = false
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(input)
        self.fps = fps; self.width = width; self.height = height
        guard writer.startWriting() else { throw Solid3DError.invalid("AVAssetWriter: \(writer.error.map { "\($0)" } ?? "start failed")") }
        writer.startSession(atSourceTime: .zero)
    }

    func append(_ image: CGImage) throws {
        while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.002) }
        var buffer: CVPixelBuffer?
        guard let pool = adaptor.pixelBufferPool, CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let pb = buffer else {
            throw Solid3DError.invalid("pixel buffer")
        }
        CVPixelBufferLockBaseAddress(pb, [])
        let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pb), width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: CVPixelBufferGetBytesPerRow(pb), space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        ctx?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        CVPixelBufferUnlockBaseAddress(pb, [])
        guard adaptor.append(pb, withPresentationTime: CMTime(value: frame, timescale: fps)) else { throw Solid3DError.invalid("append frame \(frame)") }
        frame += 1
    }

    func finish() throws {
        input.markAsFinished()
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        guard writer.status == .completed else { throw Solid3DError.invalid("MP4 writer: \(writer.error.map { "\($0)" } ?? "failed")") }
    }
}

private final class GIFWriter {
    let destination: CGImageDestination
    let delay: Double
    init(url: URL, frames: Int, delay: Double) throws {
        guard let d = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frames, nil) else { throw Solid3DError.invalid("GIF") }
        CGImageDestinationSetProperties(d, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        destination = d; self.delay = delay
    }
    func append(_ image: CGImage) {
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary)
    }
    func finish() throws { guard CGImageDestinationFinalize(destination) else { throw Solid3DError.invalid("GIF finalize") } }
}

// MARK: Studio shots

@MainActor private final class Studio {
    let src: Source
    let renderer: MGSolidRenderer
    let width = 1280, height = 800
    let aspect: Double
    let assembled: MGBounds, exploded: MGBounds
    var renderSeconds = 0.0, renderCount = 0

    init(_ src: Source) {
        self.src = src
        renderer = MGSolidRenderer(assembly: src.document.assembly)
        aspect = Double(width) / Double(height)
        assembled = renderer.worldBounds(MGPoseParameters(explode: 0))
        exploded = renderer.worldBounds(MGPoseParameters(explode: 1))
    }

    func render(_ params: MGPoseParameters, camera: MGSolidCamera) throws -> CGImage {
        renderer.apply(params)
        renderer.setCamera(camera)
        let t0 = Date()
        guard let img = renderer.render(width: width, height: height) else { throw Solid3DError.invalid("render failed (no Metal device?)") }
        renderSeconds += Date().timeIntervalSince(t0); renderCount += 1
        return img
    }

    /// Camera framing that blends the assembled and exploded bounds by the explode amount.
    func camera(yaw: Double, pitch: Double, explode e: Double, zoom: Double = 1, lift: Double = 0) -> MGSolidCamera {
        let a = MGSolidCamera.framing(assembled, yaw: yaw, pitch: pitch, aspect: aspect, margin: 1.02)
        let b = MGSolidCamera.framing(exploded, yaw: yaw, pitch: pitch, aspect: aspect, margin: 0.96)
        let k = e * e * (3 - 2 * e)
        let t = a.targetVector * (1 - k) + b.targetVector * k + MGVec3(0, lift, 0)
        // Bounding spheres are loose around a flat gearbox: assembled shots sit closer than the sphere fit.
        let tighten = 0.66 * (1 - k) + 0.94 * k
        return MGSolidCamera(target: t, yaw: yaw, pitch: pitch, distance: (a.distance * (1 - k) + b.distance * k) * zoom * tighten, fieldOfView: a.fieldOfView)
    }

    /// Label anchors per part (part-local, Z-up). The candidate nearest the camera is used so leaders stay visible.
    var labelParts: [(id: String, locals: [MGVec3])] {
        func rim(_ r: Double, _ z: Double, _ n: Int = 8) -> [MGVec3] { (0..<n).map { MGVec3(r * cos(Double($0) * 2 * .pi / Double(n)), r * sin(Double($0) * 2 * .pi / Double(n)), z) } }
        return [("outputShaft", rim(9, 48)), ("carrier", rim(42, 23, 3)), ("planet2", [MGVec3(0, 0, 13.6)]), ("sun", rim(18, 14)),
                ("ring", rim(66, 14, 12)), ("base", rim(82, -1.5, 12))]
    }

    func labels(_ params: MGPoseParameters) -> [Label] {
        let doc = src.document
        let eye = renderer.camera.position
        var out: [Label] = []
        for item in labelParts {
            guard let part = doc.assembly.part(item.id) else { continue }
            let worlds = item.locals.map { renderer.worldPoint(part: item.id, local: $0, params: params) }
            guard let best = worlds.min(by: { ($0 - eye).length < ($1 - eye).length }),
                  let p = renderer.project(best, width: width, height: height) else { continue }
            let copies = doc.assembly.parts.filter { $0.name == part.name }.count
            out.append(Label(text: copies > 1 ? "\(part.name) ×\(copies)" : part.name, anchor: CGPoint(x: p.x, y: p.y)))
        }
        return out
    }

    var subtitle: String {
        let d = src.document
        let zs = d.gears["sun"]?.teeth ?? 0, zp = d.gears["planet1"]?.teeth ?? 0, zr = d.gears["ring"]?.teeth ?? 0
        return "Sun \(zs)T input · \(d.assembly.parts.filter { $0.id.hasPrefix("planet") }.count) planets \(zp)T · ring \(zr)T fixed · carrier output turns \(zs)/\(zs + zr) of the sun"
    }
    var footer: String { "Schematic teaching model rendered by the MartyGraphics solid engine from planetary.json (\(src.lines) lines)" }
}

private func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
    let t = min(1, max(0, (x - a) / (b - a))); return t * t * (3 - 2 * t)
}

private struct Output: Encodable {
    var file: String; var bytes: Int; var sha256: String; var width: Int; var height: Int; var frames: Int; var seconds: Double; var fps: Double
}

private func describe(_ url: URL, width: Int, height: Int, frames: Int, fps: Double) throws -> Output {
    let data = try Data(contentsOf: url)
    return Output(file: url.lastPathComponent, bytes: data.count, sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
                  width: width, height: height, frames: frames, seconds: fps > 0 ? Double(frames) / fps : 0, fps: fps)
}

@MainActor private func export(_ src: Source, to output: URL, quick: Bool) throws {
    let fm = FileManager.default
    guard !fm.fileExists(atPath: output.path) else { throw Solid3DError.invalid("Output directory already exists; choose a new directory") }
    try fm.createDirectory(at: output, withIntermediateDirectories: true)
    let studio = Studio(src)
    var outputs: [Output] = []
    let w = studio.width, h = studio.height
    let started = Date()

    // 1. Hero still: low three-quarter view, assembled, gears mid-mesh.
    let heroParams = MGPoseParameters(input: 0.35, explode: 0)
    let hero = try studio.render(heroParams, camera: studio.camera(yaw: 34, pitch: 17, explode: 0, zoom: 1.0, lift: 2))
    try writePNG(hero, to: output.appendingPathComponent("hero-clean.png"))
    outputs.append(try describe(output.appendingPathComponent("hero-clean.png"), width: w, height: h, frames: 1, fps: 0))
    try writePNG(overlay(hero, title: src.document.title, subtitle: studio.subtitle, footer: studio.footer, labels: [], labelAlpha: 0),
                 to: output.appendingPathComponent("hero.png"))
    outputs.append(try describe(output.appendingPathComponent("hero.png"), width: w, height: h, frames: 1, fps: 0))
    print(String(format: "Hero rendered (%.2f s per frame at 2x supersampling).", studio.renderSeconds))

    // 2. Exploded, labelled still.
    let exParams = MGPoseParameters(input: 0.35, explode: 1)
    let ex = try studio.render(exParams, camera: studio.camera(yaw: 38, pitch: 22, explode: 1))
    try writePNG(overlay(ex, title: src.document.title, subtitle: "Exploded along the shaft axis", footer: studio.footer,
                         labels: studio.labels(exParams), labelAlpha: 1), to: output.appendingPathComponent("exploded-labelled.png"))
    outputs.append(try describe(output.appendingPathComponent("exploded-labelled.png"), width: w, height: h, frames: 1, fps: 0))

    // 3. Authored steps from the JSON, each with its own caption.
    for (i, step) in src.document.steps.enumerated() {
        let preset = MGSolidCamera.presets[step.camera ?? "hero"] ?? (32, 28)
        let e = step.explode ?? 0
        let params = MGPoseParameters(input: 0.35 + Double(i) * 0.9, explode: e)
        studio.renderer.highlight(Set(step.highlight))
        let img = try studio.render(params, camera: studio.camera(yaw: preset.yaw + step.orbit, pitch: preset.pitch, explode: e, zoom: 1.08))
        let name = "step-\(i + 1).png"
        try writePNG(overlay(img, title: nil, subtitle: nil, footer: studio.footer, labels: [], labelAlpha: 0, caption: step.say),
                     to: output.appendingPathComponent(name))
        outputs.append(try describe(output.appendingPathComponent(name), width: w, height: h, frames: 1, fps: 0))
    }
    studio.renderer.highlight([])

    // 4. Seamless 12 s loop: orbit 360 degrees, low-angle swing, push-in, explode and reassemble, gears running.
    //    Sun turns 3.5 times (24 teeth x 3.5 = 84 whole tooth pitches) while the carrier turns exactly once.
    let fps = 30, seconds = quick ? 2 : 12, frames = fps * seconds
    let loopDir = output.appendingPathComponent("frames-loop"); try fm.createDirectory(at: loopDir, withIntermediateDirectories: true)
    let movie = try MovieWriter(url: output.appendingPathComponent("planetary-loop.mp4"), width: w, height: h, fps: Int32(fps), bitrate: 4_800_000)
    let gifW = 480, gifH = 300, gifStep = 3
    let gif = try GIFWriter(url: output.appendingPathComponent("planetary-loop.gif"), frames: frames / gifStep, delay: Double(gifStep) / Double(fps))
    for f in 0..<frames {
        let u = Double(f) / Double(frames)
        let e = smoothstep(0.30, 0.46, u) * (1 - smoothstep(0.60, 0.78, u))
        let params = MGPoseParameters(input: 3.5 * 2 * .pi * u, explode: e)
        let cam = studio.camera(yaw: 30 + 360 * u, pitch: 22 - 9 * sin(2 * .pi * u) + 4 * cos(4 * .pi * u), explode: e,
                                zoom: 1.0 - 0.07 * cos(2 * .pi * u))
        var img = try studio.render(params, camera: cam)
        let labelAlpha = smoothstep(0.44, 0.49, u) * (1 - smoothstep(0.57, 0.62, u))
        img = overlay(img, title: nil, subtitle: nil, footer: studio.footer, labels: studio.labels(params), labelAlpha: labelAlpha)
        try writePNG(img, to: loopDir.appendingPathComponent(String(format: "loop-%04d.png", f)))
        try movie.append(img)
        if f % gifStep == 0, let small = scaled(img, width: gifW, height: gifH) { gif.append(small) }
        if f % 60 == 0 { print("loop frame \(f)/\(frames)") }
    }
    try movie.finish(); try gif.finish()
    outputs.append(try describe(output.appendingPathComponent("planetary-loop.mp4"), width: w, height: h, frames: frames, fps: Double(fps)))
    outputs.append(try describe(output.appendingPathComponent("planetary-loop.gif"), width: gifW, height: gifH, frames: frames / gifStep, fps: Double(fps) / Double(gifStep)))

    // 5. Explode sequence: 0 -> 1 -> 0 with a slow drift and labels at full explode.
    let exFrames = quick ? 30 : 180
    let exDir = output.appendingPathComponent("frames-explode"); try fm.createDirectory(at: exDir, withIntermediateDirectories: true)
    let exMovie = try MovieWriter(url: output.appendingPathComponent("planetary-explode.mp4"), width: w, height: h, fps: Int32(fps), bitrate: 4_800_000)
    for f in 0..<exFrames {
        let u = Double(f) / Double(exFrames - 1)
        let e = smoothstep(0.05, 0.42, u) * (1 - smoothstep(0.62, 0.97, u))
        let params = MGPoseParameters(input: 0.35 + 1.2 * u, explode: e)
        var img = try studio.render(params, camera: studio.camera(yaw: 24 + 40 * u, pitch: 20, explode: e))
        img = overlay(img, title: nil, subtitle: nil, footer: studio.footer, labels: studio.labels(params),
                      labelAlpha: smoothstep(0.40, 0.46, u) * (1 - smoothstep(0.58, 0.64, u)))
        try writePNG(img, to: exDir.appendingPathComponent(String(format: "explode-%04d.png", f)))
        try exMovie.append(img)
    }
    try exMovie.finish()
    outputs.append(try describe(output.appendingPathComponent("planetary-explode.mp4"), width: w, height: h, frames: exFrames, fps: Double(fps)))

    // 6. Slider-crank cutaway (section plane through the cylinder).
    let crank = try MGSolidModels.sliderCrank()
    var options = MGStudioOptions()
    options.section = (normal: MGVec3(0, 0, 1), offset: 0)
    options.sectionParts = ["cylinder"]
    let crankRenderer = MGSolidRenderer(assembly: crank.assembly, options: options)
    let crankParams = MGPoseParameters(input: 0.9)
    crankRenderer.apply(crankParams)
    crankRenderer.frame(crankParams, explodeRange: [], yaw: 28, pitch: 24, aspect: Double(w) / Double(h), margin: 1.05)
    if let img = crankRenderer.render(width: w, height: h) {
        try writePNG(overlay(img, title: "Slider-crank", subtitle: "Crank radius 18 mm · rod 62 mm · cylinder shown as a section cut",
                             footer: "Schematic teaching model rendered by the MartyGraphics solid engine (Swift model builder)", labels: [], labelAlpha: 0),
                     to: output.appendingPathComponent("slider-crank-section.png"))
        outputs.append(try describe(output.appendingPathComponent("slider-crank-section.png"), width: w, height: h, frames: 1, fps: 0))
    }

    // 7. Renderer-independent snapshot of the hero pose for other renderers.
    let snap = MGSolidSnapshot.make(src.document.assembly, params: heroParams, camera: studio.camera(yaw: 34, pitch: 17, explode: 0, zoom: 1.0, lift: 2),
                                    aspect: Double(w) / Double(h))
    try snap.jsonData().write(to: output.appendingPathComponent("hero-snapshot.json"))
    try src.data.write(to: output.appendingPathComponent("planetary.json"))

    let manifest: [String: Any] = [
        "source": ["file": "planetary.json", "lines": src.lines, "sha256": src.sha256],
        "renderSecondsPerFrame": studio.renderSeconds / Double(max(1, studio.renderCount)),
        "framesRendered": studio.renderCount, "totalSeconds": Date().timeIntervalSince(started),
        "snapshot": ["vertices": snap.vertexCount, "triangles": snap.triangleCount, "materials": snap.materials.count],
        "outputs": try outputs.map { try JSONSerialization.jsonObject(with: JSONEncoder().encode($0)) },
    ]
    try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("manifest.json"))
    print(String(format: "Exported %d outputs in %.0f s (%.3f s per rendered frame).", outputs.count, Date().timeIntervalSince(started),
                 studio.renderSeconds / Double(max(1, studio.renderCount))))
}

// MARK: Preview

@MainActor private final class PreviewController: NSObject {
    let renderer: MGSolidRenderer
    let view = SCNView()
    var explode = 0.0, input = 0.0, playing = true
    var timer: Timer?
    init(_ doc: MGSolidDocument) {
        renderer = MGSolidRenderer(assembly: doc.assembly)
        super.init()
        view.scene = renderer.scene
        view.pointOfView = renderer.cameraNode
        view.allowsCameraControl = true
        view.antialiasingMode = .multisampling4X
        view.backgroundColor = NSColor(srgbRed: 0.05, green: 0.06, blue: 0.09, alpha: 1)
        renderer.frame(MGPoseParameters(), explodeRange: [1], yaw: 32, pitch: 24, aspect: 1.5)
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }
    func tick() {
        if playing { input += 1.2 / 60 }
        renderer.apply(MGPoseParameters(input: input, explode: explode))
    }
    @objc func slider(_ s: NSSlider) { explode = s.doubleValue }
    @objc func toggle(_ b: NSButton) { playing.toggle(); b.title = playing ? "Pause" : "Play" }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@MainActor private func preview(_ src: Source) {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    let controller = PreviewController(src.document)
    let slider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: controller, action: #selector(PreviewController.slider(_:)))
    let button = NSButton(title: "Pause", target: controller, action: #selector(PreviewController.toggle(_:)))
    let label = NSTextField(labelWithString: "Explode")
    let bar = NSStackView(views: [button, label, slider])
    bar.orientation = .horizontal; bar.spacing = 12; bar.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
    let stack = NSStackView(views: [controller.view, bar])
    stack.orientation = .vertical; stack.spacing = 0
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760), styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
    window.title = "MartyGraphics solid engine · \(src.document.title)"
    window.isReleasedWhenClosed = false
    window.contentView = stack
    window.center(); window.makeKeyAndOrderFront(nil)
    app.activate(ignoringOtherApps: true)
    withExtendedLifetime((delegate, window, controller)) { app.run() }
}

// MARK: Entry

@main struct Solid3D {
    @MainActor static func main() throws {
        let args = Array(CommandLine.arguments.dropFirst())
        let usage = "Usage: marty-solid3d --verify | --preview | --export NEW_DIR [--quick] | --snapshot FILE.json | --diagnose FILE.png"
        let src = try loadPlanetary()
        switch args.first {
        case "--verify"?: try verify(src)
        case "--preview"?: try verify(src); preview(src)
        case "--export"? where args.count >= 2:
            try verify(src)
            _ = NSApplication.shared
            try export(src, to: URL(fileURLWithPath: args[1], isDirectory: true), quick: args.contains("--quick"))
        case "--diagnose"? where args.count == 2:
            // Renderer smoke test: one chamfered block on the studio ground (shadow and contact shadow visible).
            let box = MGPart(id: "box", name: "Block", mesh: .chamferedBox(size: MGVec3(40, 40, 40), chamfer: 2).transformed(.translation(MGVec3(0, 0, 20))),
                             material: .brushedSteel)
            let r = MGSolidRenderer(assembly: MGAssembly(name: "Block", parts: [box]))
            r.apply(MGPoseParameters())
            r.frame(MGPoseParameters(), yaw: 30, pitch: 30, aspect: 1.6, margin: 2.5)
            guard let img = r.render(width: 640, height: 400) else { throw Solid3DError.invalid("render failed") }
            try writePNG(img, to: URL(fileURLWithPath: args[1]))
        case "--snapshot"? where args.count == 2:
            let snap = MGSolidSnapshot.make(src.document.assembly, params: src.document.defaults)
            try snap.jsonData().write(to: URL(fileURLWithPath: args[1]))
            print("Wrote snapshot: \(snap.vertexCount) vertices, \(snap.triangleCount) triangles, \(snap.materials.count) materials.")
        default: throw Solid3DError.invalid(usage)
        }
    }
}
