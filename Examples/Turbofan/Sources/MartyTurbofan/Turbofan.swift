// SPDX-License-Identifier: Apache-2.0
import AppKit
import Foundation
import Metal
import simd
import MartyGraphics
import MartyGraphicsPathTracer
import MartySolidGLTF
import MartySolidRT
import TurbofanKit

// MARK: Verify

/// Runs the checks and prints them; throws when any fails.
@discardableResult
func verify(_ m: TurbofanModel, cell: Double = 1.0) throws -> TurbofanChecks.Report {
    let doc = m.document
    print("Parsed turbofan.json: \(m.lines) lines, \(m.data.count) bytes, sha256 \(m.sha256.prefix(16))..., \(doc.assembly.parts.count) parts, \(doc.steps.count) steps.")
    let t0 = Date()
    let r = TurbofanChecks.run(doc, samples: 24, cell: cell)
    var failures: [String] = []
    func check(_ ok: Bool, _ what: String) {
        print((ok ? "PASS " : "FAIL ") + what)
        if !ok { failures.append(what) }
    }
    check(r.openParts.isEmpty, "all \(r.parts) part meshes are closed and edge-manifold (\(r.triangles) triangles)" +
          (r.openParts.isEmpty ? "" : "; open: \(r.openParts.joined(separator: ", "))"))
    let n1 = r.rates["lpShaft"] ?? 0, n2 = r.rates["hpShaft"] ?? 0
    let lp = ["spinner", "fanDisk", "fan", "lpc", "lpt", "lpShaft"], hp = ["hpc", "hpt", "hpShaft"]
    check(lp.allSatisfy { abs((r.rates[$0] ?? 0) - n1) < 1e-9 }, "fan, LP compressor and LP turbine turn with the LP shaft (N1 = \(fmt(n1)) rad per input rad)")
    check(hp.allSatisfy { abs((r.rates[$0] ?? 0) - n2) < 1e-9 }, "HP compressor and HP turbine turn with the HP shaft (N2 = \(fmt(n2)) rad per input rad)")
    let statics = r.rates.filter { !lp.contains($0.key) && !hp.contains($0.key) }
    check(statics.values.allSatisfy { $0 == 0 }, "\(statics.count) casing, vane, frame and combustor parts stay fixed")
    check(r.spoolRates.count == 2, "exactly two spools (distinct spin rates: \(r.spoolRates.map(fmt).joined(separator: ", ")))")
    let a1 = m.authoredInputScale("lpShaft") ?? .nan, a2 = m.authoredInputScale("hpShaft") ?? .nan
    check(abs(n2 / n1 - a2 / a1) < 1e-9 && n1 > 0 && n2 > n1,
          "spool speed ratio N2/N1 = \(fmt(n2 / n1)) measured from the posed parts equals the authored \(fmt(a2))/\(fmt(a1)); N1 < N2")
    check(r.axisError < 1e-9, "shafts and rotors spin about the engine axis (largest axis offset \(String(format: "%.1e", r.axisError)))")
    check(r.coaxialError < 1e-6, "coaxial: over \(r.sampledAngles) sampled input angles no rotating vertex changes radius or axial position (max \(String(format: "%.1e", r.coaxialError)) mm)")
    for c in r.clearances where ["fan", "lpc", "hpc", "hpt", "lpt", "spinner", "fanDisk", "lpShaft", "hpShaft"].contains(c.part) {
        check(c.gap >= 2, String(format: "%@ clears everything that does not turn with it: gap >= %.2f mm, a lower bound (nearest: %@)",
                                 c.part, c.gap, c.nearest))
    }
    check(r.interferences.isEmpty, String(format: "no blade, vane, casing or shaft interference at any angle (smallest lower-bound gap %.2f mm)",
                                          r.minimumGap))
    // Stage counts as authored.
    func rows(_ id: String) -> Int { doc.shapes[id]?.filter { $0.kind == "bladeRow" }.count ?? 0 }
    check(rows("fan") == 1 && rows("lpc") == 3 && rows("hpc") == 6 && rows("hpt") == 2 && rows("lpt") == 4,
          "blade rows: fan 1, LP compressor \(rows("lpc")), HP compressor \(rows("hpc")), HP turbine \(rows("hpt")), LP turbine \(rows("lpt"))")
    print(String(format: "Checks took %.1f s.", Date().timeIntervalSince(t0)))
    guard failures.isEmpty else { throw Failure("\(failures.count) check(s) failed") }
    print("All checks passed.")
    return r
}

func fmt(_ x: Double) -> String {
    x == x.rounded() ? String(format: "%.0f", x) : String(format: "%.4g", x)
}

// MARK: Studio

/// World bounds of some parts (all when empty) of `a` at a pose. `Studio.bounds` and the glTF export use it.
func partBounds(_ a: MGAssembly, _ ids: [String], _ params: MGPoseParameters) -> MGBounds {
    let pose = a.pose(params)
    var b = MGBounds.empty
    for p in a.parts where ids.isEmpty || ids.contains(p.id) {
        let t = MGSolidStage.zUpToYUp * (pose.world[p.id] ?? .identity)
        for c in p.mesh.bounds.corners { b.include(t.apply(c)) }
    }
    return b
}

/// Camera that frames the bounds of `ids` from yaw/pitch, `zoom` < 1 moves closer (`Studio.camera`; no renderer needed).
func framedCamera(_ a: MGAssembly, aspect: Double, _ ids: [String], _ params: MGPoseParameters, yaw: Double, pitch: Double,
                  zoom: Double = 1, shift: MGVec3 = .zero, fieldOfView: Double = 28) -> MGSolidCamera {
    let b = partBounds(a, ids, params)
    var c = MGSolidCamera.framing(b, yaw: yaw, pitch: pitch, aspect: aspect, fieldOfView: fieldOfView, margin: 1.0)
    // A bounding sphere is loose around a long cylinder; sit closer than the sphere fit.
    c.distance *= 0.78 * zoom
    let t = c.targetVector + shift
    c.target = [t.x, t.y, t.z]
    return c
}

/// Label anchor in the engine frame: radius, angle (degrees about the axis, 225 = middle of the cutaway), axial position.
struct Anchor {
    let part: String; let r: Double; let phi: Double; let z: Double; let text: String
    /// False when the part is hidden in the assembled cutaway (labelled only when exploded).
    var cutaway = true
}

@MainActor final class Studio {
    let model: TurbofanModel
    let renderer: MGSolidRenderer
    let width: Int, height: Int
    var renderSeconds = 0.0, renderCount = 0

    init(_ model: TurbofanModel, width: Int = 1280, height: Int = 800, assembly: MGAssembly? = nil) {
        self.model = model
        self.width = width; self.height = height
        var options = MGStudioOptions()
        options.supersample = 2
        options.bloom = false
        var lighting = MGStudioLighting.studio
        lighting.exposure = -0.3
        renderer = MGSolidRenderer(assembly: assembly ?? model.document.assembly, lighting: lighting, options: options)
    }

    var aspect: Double { Double(width) / Double(height) }

    func render(_ params: MGPoseParameters, camera: MGSolidCamera) throws -> CGImage {
        renderer.apply(params)
        renderer.setCamera(camera)
        let t0 = Date()
        guard let img = renderer.render(width: width, height: height) else { throw Failure("render failed (no Metal device?)") }
        renderSeconds += Date().timeIntervalSince(t0); renderCount += 1
        return img
    }

    /// World bounds of some parts (all when empty) at a pose.
    func bounds(_ ids: [String], _ params: MGPoseParameters) -> MGBounds { partBounds(renderer.assembly, ids, params) }

    /// Camera that frames the bounds of `ids` from yaw/pitch, `zoom` < 1 moves closer.
    func camera(_ ids: [String], _ params: MGPoseParameters, yaw: Double, pitch: Double, zoom: Double = 1, shift: MGVec3 = .zero,
                fieldOfView: Double = 28) -> MGSolidCamera {
        framedCamera(renderer.assembly, aspect: aspect, ids, params, yaw: yaw, pitch: pitch, zoom: zoom, shift: shift, fieldOfView: fieldOfView)
    }

    /// World point of an engine-frame anchor, following the part's explode offset.
    func project(_ a: Anchor, _ params: MGPoseParameters) -> CGPoint? {
        let phi = a.phi * .pi / 180
        let local = MGVec3(a.r * cos(phi), a.r * sin(phi), a.z)
        var p = renderer.worldPoint(part: "plug", local: local, params: MGPoseParameters(input: 0, explode: 0))
        let moved = renderer.worldPoint(part: a.part, local: .zero, params: params)
        let rest = renderer.worldPoint(part: a.part, local: .zero, params: MGPoseParameters(input: params.input, explode: 0))
        p = p + (moved - rest)
        return renderer.project(p, width: width, height: height)
    }

    static let anchors: [Anchor] = [
        Anchor(part: "spinner", r: 150, phi: 225, z: -190, text: "Spinner"),
        Anchor(part: "fan", r: 700, phi: 225, z: 150, text: "Fan · 20 blades"),
        Anchor(part: "nacelle", r: 1036, phi: 178, z: 250, text: "Nacelle"),
        Anchor(part: "ogv", r: 690, phi: 228, z: 470, text: "Bypass duct and guide vanes"),
        Anchor(part: "lpc", r: 372, phi: 225, z: 420, text: "LP compressor · 3 stages"),
        Anchor(part: "lpShaft", r: 45, phi: 225, z: 630, text: "LP shaft (N1)", cutaway: false),
        Anchor(part: "hpc", r: 272, phi: 225, z: 930, text: "HP compressor · 6 stages"),
        Anchor(part: "combustor", r: 318, phi: 181, z: 1340, text: "Annular combustor"),
        Anchor(part: "hpShaft", r: 78, phi: 225, z: 1380, text: "HP shaft (N2 = 3 × N1)"),
        Anchor(part: "hpt", r: 305, phi: 225, z: 1590, text: "HP turbine · 2 stages"),
        Anchor(part: "lpt", r: 335, phi: 225, z: 1850, text: "LP turbine · 4 stages"),
        Anchor(part: "plug", r: 190, phi: 225, z: 2290, text: "Exhaust cone"),
    ]

    func labels(_ params: MGPoseParameters, only: Set<String> = []) -> [Label] {
        Studio.anchors.filter { (only.isEmpty || only.contains($0.part)) && ($0.cutaway || params.explode > 0.5) }.compactMap { a in
            project(a, params).map { Label(text: a.text, anchor: $0) }
        }
    }

    var footer: String {
        "Schematic teaching model, not a real engine design · rendered by the MartyGraphics solid engine from turbofan.json (\(model.lines) lines)"
    }
}

private func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
    let t = min(1, max(0, (x - a) / (b - a))); return t * t * (3 - 2 * t)
}

struct Record: Encodable {
    var file: String; var bytes: Int; var sha256: String; var width: Int; var height: Int
    var frames: Int; var seconds: Double; var note: String
}

func record(_ url: URL, _ w: Int, _ h: Int, frames: Int = 1, seconds: Double = 0, note: String) throws -> Record {
    Record(file: url.lastPathComponent, bytes: Media.bytes(url), sha256: try Media.sha256(url), width: w, height: h,
           frames: frames, seconds: seconds, note: note)
}

/// Loop timing: LP spool one turn, HP spool three turns in 12 s, so every blade row returns to its start pose.
enum Loop {
    static let seconds = 12.0, fps = 30
    static func input(_ u: Double) -> Double { 2 * .pi * u }
    static func yaw(_ u: Double) -> Double { -38 + 24 * sin(2 * .pi * u) }
    static func pitch(_ u: Double) -> Double { 20 + 6 * cos(2 * .pi * u) }
    static func zoom(_ u: Double) -> Double { 0.92 - 0.05 * cos(2 * .pi * u) }
}

@MainActor func export(_ m: TurbofanModel, to dir: URL, quick: Bool, loopOnly: Bool) throws {
    let studio = Studio(m)
    var out: [Record] = []
    let w = studio.width, h = studio.height
    let started = Date()
    let doc = m.document
    let all: [String] = []

    // 1. Hero cutaway.
    let heroParams = MGPoseParameters(input: 0.2)
    let heroCam = studio.camera(all, heroParams, yaw: -32, pitch: 20, zoom: 0.88)
    if !loopOnly {
        let hero = try studio.render(heroParams, camera: heroCam)
        try Media.png(hero, to: dir.appendingPathComponent("hero-clean.png"))
        out.append(try record(dir.appendingPathComponent("hero-clean.png"), w, h, note: "cutaway hero, no overlay"))
        try Media.png(Overlay.apply(hero, title: "How a turbofan works",
                                    subtitle: "Two-spool high-bypass turbofan, cut away to show the core · LP spool at N1, HP spool at N2 = 3 × N1",
                                    footer: studio.footer), to: dir.appendingPathComponent("hero.png"))
        out.append(try record(dir.appendingPathComponent("hero.png"), w, h, note: "cutaway hero with title"))
        print(String(format: "Hero rendered (%.2f s per frame).", studio.renderSeconds))

        // 2. Labelled cutaway.
        let labCam = studio.camera(all, heroParams, yaw: -30, pitch: 24, zoom: 0.98)
        let lab = try studio.render(heroParams, camera: labCam)
        try Media.png(Overlay.apply(lab, title: "Turbofan cutaway", subtitle: "Every label points at a part built from turbofan.json",
                                    footer: studio.footer, labels: studio.labels(heroParams), labelBand: (0.2, 0.9)),
                      to: dir.appendingPathComponent("labelled.png"))
        out.append(try record(dir.appendingPathComponent("labelled.png"), w, h, note: "labelled cutaway"))

        // 3. Authored steps.
        for (i, step) in doc.steps.enumerated() {
            let preset = MGSolidCamera.presets[step.camera ?? "hero"] ?? (32, 28)
            let e = step.explode ?? 0
            let params = MGPoseParameters(input: 0.2 + Double(i) * 0.37, explode: e)
            studio.renderer.highlight(Set(step.highlight))
            let yaw = preset.yaw + step.orbit
            var cam = studio.camera(e > 0 ? step.focus : all, params, yaw: yaw, pitch: preset.pitch, zoom: e > 0 ? 1.08 : 0.95)
            if e == 0, !step.focus.isEmpty {
                // Aim at the focus parts from a little closer than the whole-engine framing.
                let f = studio.bounds(step.focus, params).center
                cam.target = [f.x, f.y, f.z]
                cam.distance *= 0.7
            }
            var img = try studio.render(params, camera: cam)
            let labels = e > 0 ? studio.labels(params, only: Set(step.focus)) : []
            img = Overlay.apply(img, footer: studio.footer, labels: labels, caption: step.say, corner: "Step \(i + 1) of \(doc.steps.count)",
                                labelBand: (0.1, 0.62))
            let name = "step-\(i + 1).png"
            try Media.png(img, to: dir.appendingPathComponent(name))
            out.append(try record(dir.appendingPathComponent(name), w, h, note: step.say))
        }
        studio.renderer.highlight([])
    }

    // 4. Seamless loop: slow orbit swing, LP spool one turn, HP spool three turns.
    let fps = Loop.fps, frames = quick ? 30 : Int(Loop.seconds) * fps
    let movie = try MovieWriter(url: dir.appendingPathComponent("turbofan-loop.mp4"), width: w, height: h, fps: Int32(fps), bitrate: 9_000_000)
    let gifW = 640, gifH = 400, gifStep = 3
    let gifDelay = Double(gifStep) / Double(fps)  // 0.10 s = 10 hundredths, exact in GIF
    let gif = try GIFWriter(url: dir.appendingPathComponent("turbofan-loop.gif"), frames: frames / gifStep, delay: gifDelay)
    for f in 0..<frames {
        let u = Double(f) / Double(frames)
        let params = MGPoseParameters(input: Loop.input(u))
        let cam = studio.camera(all, MGPoseParameters(), yaw: Loop.yaw(u), pitch: Loop.pitch(u), zoom: Loop.zoom(u))
        var img = try studio.render(params, camera: cam)
        img = Overlay.apply(img, footer: studio.footer, corner: "Fan and LP spool: N1 · HP spool: N2 = 3 × N1")
        try movie.append(img)
        if f % gifStep == 0, let small = Media.scaled(img, width: gifW, height: gifH) { gif.append(small) }
        if f == 0 { try Media.png(img, to: dir.appendingPathComponent("loop-poster.png")) }
        if f % 60 == 0 { print("loop frame \(f)/\(frames)") }
    }
    try movie.finish(); try gif.finish()
    out.append(try record(dir.appendingPathComponent("turbofan-loop.mp4"), w, h, frames: frames, seconds: Double(frames) / Double(fps),
                          note: "H.264, \(fps) fps"))
    let gifURL = dir.appendingPathComponent("turbofan-loop.gif")
    let delays = GIFWriter.delays(gifURL)
    out.append(try record(gifURL, gifW, gifH, frames: delays.count, seconds: delays.reduce(0, +),
                          note: "every \(gifStep)rd frame, delay \(gifDelay) s; stored delays sum \(delays.reduce(0, +)) s"))
    out.append(try record(dir.appendingPathComponent("loop-poster.png"), w, h, note: "loop frame 0"))

    // 5. Snapshot of the hero pose for other renderers.
    let snap = MGSolidSnapshot.make(doc.assembly, params: heroParams, camera: heroCam, aspect: studio.aspect)
    try snap.jsonData().write(to: dir.appendingPathComponent("hero-snapshot.json"))
    try m.data.write(to: dir.appendingPathComponent("turbofan.json"))
    let manifest: [String: Any] = [
        "renderer": "MartyGraphics solid engine (SceneKit studio renderer, 2x supersampling, bloom off, exposure -0.3)",
        "source": ["file": "turbofan.json", "lines": m.lines, "bytes": m.data.count, "sha256": m.sha256],
        "renderSecondsPerFrame": studio.renderSeconds / Double(max(1, studio.renderCount)),
        "framesRendered": studio.renderCount, "totalSeconds": Date().timeIntervalSince(started),
        "snapshot": ["vertices": snap.vertexCount, "triangles": snap.triangleCount, "materials": snap.materials.count],
        "outputs": try out.map { try JSONSerialization.jsonObject(with: JSONEncoder().encode($0)) },
    ]
    try Media.writeJSON(manifest, to: dir.appendingPathComponent("manifest.json"))
    print(String(format: "Exported %d outputs in %.0f s (%.3f s per rendered frame).", out.count, Date().timeIntervalSince(started),
                 studio.renderSeconds / Double(max(1, studio.renderCount))))
}

// MARK: Path tracing

/// A dark satin floor under the engine (path tracer only; scene units).
func floorMesh(y: Float, half: Float, material: UInt32) -> MGRTMesh {
    let p: [SIMD3<Float>] = [SIMD3(-half, y, -half), SIMD3(half, y, -half), SIMD3(half, y, half), SIMD3(-half, y, half)]
    return MGRTMesh(positions: p, normals: Array(repeating: SIMD3(0, 1, 0), count: 4), indices: [0, 2, 1, 0, 3, 2], material: material)
}

/// The adapted scene plus the example's own floor, studio lights and environment (scene units: metres).
func pathTraceScene(_ snap: MGSolidSnapshot) -> MGRTScene {
    var options = MGSolidRT.Options()
    options.includeStudioLights = false
    var scene = MGSolidRT.scene(snap, options: options)
    let s: Float = options.scale
    let lo = SIMD3(Float(snap.boundsMin[0]), Float(snap.boundsMin[1]), Float(snap.boundsMin[2])) * s
    let hi = SIMD3(Float(snap.boundsMax[0]), Float(snap.boundsMax[1]), Float(snap.boundsMax[2])) * s
    let c = (lo + hi) / 2
    // Floor just below the nacelle.
    scene.materials.append(.plastic(SIMD3(0.018, 0.018, 0.021), roughness: 0.22, specular: 0.7))
    scene.meshes.append(floorMesh(y: lo.y - 0.004, half: 40, material: UInt32(scene.materials.count - 1)))
    scene.instances.append(MGRTInstance(mesh: scene.meshes.count - 1))
    // Lighting: a large soft key above front-left, a cool rim behind, a warm kicker low right, a broad top fill and a front strip.
    scene.areaLights = [
        .softbox(center: c + SIMD3(-3.0, 5.2, 4.2), toward: c, size: SIMD2(4.4, 3.0), radiance: SIMD3(1.0, 0.97, 0.92) * 9.0, visibleToCamera: false),
        .softbox(center: c + SIMD3(3.2, 3.2, -5.2), toward: c + SIMD3(0, 0.3, 0), size: SIMD2(1.2, 4.6), radiance: SIMD3(0.80, 0.90, 1.0) * 12.0, visibleToCamera: false),
        .softbox(center: c + SIMD3(5.2, 1.0, 3.0), toward: c, size: SIMD2(0.9, 3.0), radiance: SIMD3(1.0, 0.84, 0.66) * 7.0, visibleToCamera: false),
        .softbox(center: c + SIMD3(0.5, 7.0, 1.5), toward: c, size: SIMD2(7.0, 5.0), radiance: SIMD3(0.9, 0.93, 1.0) * 1.6, visibleToCamera: false),
        .softbox(center: c + SIMD3(-1.0, 1.4, 6.5), toward: c, size: SIMD2(5.0, 1.6), radiance: SIMD3(0.95, 0.97, 1.0) * 2.2, visibleToCamera: false),
    ]
    var env = MGRTEnvironment.studio()
    env.intensity = 1.1
    scene.environment = env
    return scene
}

func pathTraceSettings(_ width: Int, _ height: Int, spp: Int, seed: UInt32) -> MGRTSettings {
    var settings = MGRTSettings(width: width, height: height, samplesPerPixel: spp, maxBounces: 7, seed: seed, exposure: 0.7, denoise: true,
                                clampIndirect: 4, environmentSelectProbability: 0.35, tileSize: 512, vignette: 0.2, bloom: 0.05)
    settings.denoiseStrength = 5
    return settings
}

/// Path-traced seamless loop: the same scene, rotors moved by instance transforms (LP one turn, HP three turns).
@MainActor func pathTraceLoop(_ m: TurbofanModel, to dir: URL, width: Int, height: Int, spp: Int, fps: Int, seconds: Double, seed: UInt32) throws {
    guard MGRTRenderer.isSupported else { throw Failure("No Metal ray-tracing device") }
    let studio = Studio(m, width: width, height: height)
    let a = m.document.assembly
    func camera(_ u: Double) -> MGSolidCamera {
        var c = studio.camera([], MGPoseParameters(), yaw: Loop.yaw(u), pitch: Loop.pitch(u), zoom: Loop.zoom(u))
        c.fieldOfView = 28
        return c
    }
    let base = MGPoseParameters(input: 0)
    let snap = MGSolidSnapshot.make(a, params: base, camera: camera(0), aspect: Double(width) / Double(height))
    let renderer = try MGRTRenderer(scene: pathTraceScene(snap))
    let pose0 = a.pose(base)
    let frames = Int((seconds * Double(fps)).rounded())
    let movie = try MovieWriter(url: dir.appendingPathComponent("turbofan-pathtraced-loop.mp4"), width: width, height: height, fps: Int32(fps),
                                bitrate: width * height * 10)
    let started = Date()
    var timings: [[String: Any]] = []
    for f in 0..<frames {
        let u = Double(f) / Double(frames)
        let pose = a.pose(MGPoseParameters(input: Loop.input(u)))
        let transforms = a.parts.map { MGSolidRT.motion(from: pose0.world[$0.id] ?? .identity, to: pose.world[$0.id] ?? .identity) }
            + [matrix_identity_float4x4]
        let c = camera(u)
        let out = try renderer.render(settings: pathTraceSettings(width, height, spp: spp, seed: seed &+ UInt32(f) &* 7919),
                                      camera: MGSolidRT.camera(c, aperture: 0.01, focusDistance: Float(c.distance) * 0.001 * 0.93),
                                      transforms: transforms)
        guard let img = out.cgImage() else { throw Failure("No image") }
        let framed = Overlay.apply(img, footer: "Schematic teaching model · path traced by MartyGraphicsPathTracer from turbofan.json",
                                   corner: "Fan and LP spool: N1 · HP spool: N2 = 3 × N1")
        try movie.append(framed)
        if f == 0 { try Media.png(framed, to: dir.appendingPathComponent("pathtraced-loop-poster.png")) }
        timings.append(["frame": f, "wallms": out.stats.wallMilliseconds.rounded()])
        if f % 24 == 0 {
            let el = Date().timeIntervalSince(started)
            print(String(format: "pt frame %d/%d: %.1f s (elapsed %.0f s, eta %.0f s)", f, frames, out.stats.wallMilliseconds / 1000, el,
                         el / Double(f + 1) * Double(frames - f - 1)))
        }
    }
    try movie.finish()
    let mp4 = dir.appendingPathComponent("turbofan-pathtraced-loop.mp4"), poster = dir.appendingPathComponent("pathtraced-loop-poster.png")
    try Media.writeJSON(["renderer": "MartyGraphicsPathTracer via MartySolidRT", "width": width, "height": height, "fps": fps, "frames": frames,
                         "seconds": Double(frames) / Double(fps), "samplesPerPixelPerFrame": spp, "totalWallSeconds": Date().timeIntervalSince(started).rounded(),
                         "source": ["file": "turbofan.json", "sha256": m.sha256],
                         "files": [["file": mp4.lastPathComponent, "sha256": try Media.sha256(mp4), "bytes": Media.bytes(mp4)],
                                   ["file": poster.lastPathComponent, "sha256": try Media.sha256(poster), "bytes": Media.bytes(poster)]],
                         "frameTimings": timings], to: dir.appendingPathComponent("pathtrace-loop.json"))
    print(String(format: "Path-traced loop: %d frames in %.0f s.", frames, Date().timeIntervalSince(started)))
}

@MainActor func pathTrace(_ m: TurbofanModel, to dir: URL, width: Int, height: Int, spp: Int, seed: UInt32, label: String) throws {
    guard MGRTRenderer.isSupported else { throw Failure("No Metal ray-tracing device") }
    let studio = Studio(m, width: width, height: height)
    let params = MGPoseParameters(input: 0.2)
    // Engine a little right of and below centre, leaving room for the title block.
    var cam = studio.camera([], params, yaw: -32, pitch: 20, zoom: 0.8, shift: MGVec3(-110, 165, -70))
    cam.fieldOfView = 28
    let snap = MGSolidSnapshot.make(m.document.assembly, params: params, camera: cam, aspect: Double(width) / Double(height))
    var scene = pathTraceScene(snap)
    let s: Float = 0.001
    let rtCam = MGSolidRT.camera(cam, scale: s, aperture: 0.012, focusDistance: Float(cam.distance) * s * 0.93)
    scene.camera = rtCam
    let t0 = Date()
    let renderer = try MGRTRenderer(scene: scene)
    let setup = Date().timeIntervalSince(t0)
    let settings = pathTraceSettings(width, height, spp: spp, seed: seed)
    let res = try renderer.render(settings: settings)
    guard let image = res.cgImage() else { throw Failure("No image") }
    let url = dir.appendingPathComponent("pathtraced-hero-clean.png")
    try Media.png(image, to: url)
    let gpu = MTLCreateSystemDefaultDevice()?.name ?? "GPU"
    let titled = Overlay.apply(image, title: "How a turbofan works",
                               subtitle: "Path traced from the same turbofan.json · LP spool at N1, HP spool at N2 = 3 × N1",
                               footer: String(format: "Schematic teaching model, not a real engine design · MartyGraphicsPathTracer on %@, %d spp, %.1f min",
                                              gpu, spp, res.stats.wallMilliseconds / 60000),
                               kicker: "MARTYGRAPHICS · PATH TRACER")
    let url2 = dir.appendingPathComponent("pathtraced-hero.png")
    try Media.png(titled, to: url2)
    let rec: [String: Any] = [
        "renderer": "MartyGraphicsPathTracer via MartySolidRT (snapshot adapter)", "gpu": gpu, "label": label,
        "width": width, "height": height, "samplesPerPixel": spp, "maxBounces": settings.maxBounces, "seed": Int(seed),
        "denoise": settings.denoise, "setupSeconds": setup, "traceGPUms": res.stats.traceMilliseconds.rounded(),
        "wallms": res.stats.wallMilliseconds.rounded(), "triangles": res.stats.triangles, "instances": res.stats.instances,
        "source": ["file": "turbofan.json", "sha256": m.sha256],
        "files": [["file": url.lastPathComponent, "sha256": try Media.sha256(url), "bytes": Media.bytes(url)],
                  ["file": url2.lastPathComponent, "sha256": try Media.sha256(url2), "bytes": Media.bytes(url2)]],
    ]
    try Media.writeJSON(rec, to: dir.appendingPathComponent("pathtrace.json"))
    print(String(format: "Path traced %dx%d at %d spp: %.0f s wall (%.0f s GPU trace), %d triangles, setup %.1f s.", width, height, spp,
                 res.stats.wallMilliseconds / 1000, res.stats.traceMilliseconds / 1000, res.stats.triangles, setup))
}

// MARK: Entry

@main struct TurbofanCLI {
    @MainActor static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        let usage = """
        Usage: marty-turbofan --verify [--cell MM]
               marty-turbofan --export NEW_DIR [--quick] [--loop-only]
               marty-turbofan --export-gltf NEW_DIR --engine-commit SHA [--fps 30]
               marty-turbofan --pathtrace NEW_DIR [--size 1920x1080] [--spp 256] [--seed N] [--label TEXT]
               marty-turbofan --ptloop NEW_DIR [--size 960x540] [--spp 48] [--fps 24] [--seconds 10]
               marty-turbofan --view FILE.png [--yaw D] [--pitch D] [--zoom Z] [--explode E] [--focus ids] [--only ids]
        """
        func value(_ flag: String) -> String? { args.firstIndex(of: flag).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } }
        do {
            let m = try TurbofanModel.load()
            switch args.first {
            case "--verify"?: try verify(m, cell: value("--cell").flatMap(Double.init) ?? 1.0)
            case "--export"? where args.count >= 2:
                try verify(m)
                _ = NSApplication.shared
                try export(m, to: try Media.newDirectory(args[1]), quick: args.contains("--quick"), loopOnly: args.contains("--loop-only"))
            case "--export-gltf"? where args.count >= 2 && !args[1].hasPrefix("--"):
                try verify(m)
                let fps = try value("--fps").map { v -> Int in
                    guard let f = Int(v), MGSolidGLTF.fpsRange.contains(f) else { throw Failure("--fps 1...240") }
                    return f
                } ?? Loop.fps
                guard let commit = value("--engine-commit") else { throw Failure("--export-gltf needs --engine-commit SHA (40 hex digits)") }
                try exportGLTF(m, to: args[1], fps: fps, engineCommit: commit)
            case "--view"? where args.count >= 2:
                // Debug view: --view FILE.png [--yaw D] [--pitch D] [--zoom Z] [--explode E] [--input A] [--focus a,b] [--only a,b]
                _ = NSApplication.shared
                let only = value("--only").map { Set($0.split(separator: ",").map(String.init)) }
                let asm = only.map { o in MGAssembly(name: m.document.assembly.name, parts: m.document.assembly.parts.filter { o.contains($0.id) }) }
                let studio = Studio(m, assembly: asm)
                let params = MGPoseParameters(input: Double(value("--input") ?? "") ?? 0.2, explode: Double(value("--explode") ?? "") ?? 0)
                let focus = value("--focus").map { $0.split(separator: ",").map(String.init) } ?? []
                let cam = studio.camera(focus, params, yaw: Double(value("--yaw") ?? "") ?? -40, pitch: Double(value("--pitch") ?? "") ?? 24,
                                        zoom: Double(value("--zoom") ?? "") ?? 1)
                try Media.png(try studio.render(params, camera: cam), to: URL(fileURLWithPath: args[1]))
            case "--ptloop"? where args.count >= 2:
                let size = (value("--size") ?? "960x540").split(separator: "x").compactMap { Int($0) }
                guard size.count == 2, size[0] > 0, size[1] > 0 else { throw Failure("--size WxH") }
                try pathTraceLoop(m, to: try Media.newDirectory(args[1]), width: size[0], height: size[1], spp: Int(value("--spp") ?? "") ?? 48,
                                  fps: Int(value("--fps") ?? "") ?? 24, seconds: Double(value("--seconds") ?? "") ?? 10,
                                  seed: UInt32(value("--seed") ?? "") ?? 1)
            case "--pathtrace"? where args.count >= 2:
                let size = (value("--size") ?? "1920x1080").split(separator: "x").compactMap { Int($0) }
                guard size.count == 2, size[0] > 0, size[1] > 0 else { throw Failure("--size WxH") }
                try pathTrace(m, to: try Media.newDirectory(args[1]), width: size[0], height: size[1], spp: Int(value("--spp") ?? "") ?? 256,
                              seed: UInt32(value("--seed") ?? "") ?? 1, label: value("--label") ?? "")
            default: throw Failure(usage)
            }
        } catch {
            FileHandle.standardError.write(Data("error: \(error)\n".utf8))
            exit(1)
        }
    }
}
