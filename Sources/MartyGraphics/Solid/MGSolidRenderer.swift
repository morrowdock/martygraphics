// SPDX-License-Identifier: Apache-2.0
import Foundation
import CoreGraphics
import SceneKit
import simd
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
#if canImport(Metal)
import Metal
#endif

/// Options for the studio renderer.
public struct MGStudioOptions: Equatable, Sendable {
    public var shadows = true
    public var ambientOcclusion = true
    public var bloom = true
    /// Render at this multiple of the output size and downsample (1 = off).
    public var supersample = 2
    /// Section plane in world (Y-up) space: points with `dot(p, normal) > offset` are cut away. This is an uncapped
    /// fragment discard kept for compatibility; authored step sections (`show(_:)` with `MGSolidDocument.view(step:)`)
    /// are capped core cuts and need no option.
    public var section: (normal: MGVec3, offset: Double)?
    /// Part ids the section plane applies to (empty = all parts).
    public var sectionParts: Set<String> = []
    /// Draw the contact shadow and soft ground shadow.
    public var ground = true
    public init() {}

    public static func == (a: MGStudioOptions, b: MGStudioOptions) -> Bool {
        a.shadows == b.shadows && a.ambientOcclusion == b.ambientOcclusion && a.bloom == b.bloom && a.supersample == b.supersample
            && a.section?.normal == b.section?.normal && a.section?.offset == b.section?.offset && a.sectionParts == b.sectionParts
            && a.ground == b.ground
    }
}

/// SceneKit studio renderer for solid assemblies: PBR material presets, a procedural studio environment for image-based
/// lighting, key/fill/rim lights, soft shadows, screen-space ambient occlusion and a contact ground. Renders offscreen to
/// `CGImage`, or exposes `scene` for an interactive `SCNView`.
public final class MGSolidRenderer {
    public let scene = SCNScene()
    public private(set) var assembly: MGAssembly
    public let lighting: MGStudioLighting
    public var options: MGStudioOptions { didSet { restyleAll() } }
    public let cameraNode = SCNNode()
    private let stageNode = SCNNode()
    private var partNodes: [String: SCNNode] = [:]
    /// Current preset of every part node (kept in step with `assembly`).
    private(set) var partMaterials: [String: MGMaterialPreset] = [:]
    private var materialCache: [String: SCNMaterial] = [:]
    private var keyLight: SCNNode?
    private var groundNodes: [SCNNode] = []
    private var renderer: SCNRenderer?
    public private(set) var camera: MGSolidCamera
    private var highlighted: Set<String> = []
    private var dimOthers = true
    /// What each part shows (cuts, opacity, light); `show(_:)` sets it.
    public private(set) var view: MGSolidView
    /// Uncut geometry of every part, and the geometry of each capped cut shown so far (keyed by part and local plane).
    private var plainGeometry: [String: SCNGeometry] = [:]
    /// Keyed by part id and local plane; a part whose mesh changes drops its entries, so a hit needs only a cheap
    /// fingerprint check (triangle and vertex counts, cap area).
    private var cutGeometry: [String: (fingerprint: [Double], geometry: SCNGeometry)] = [:]

    public init(assembly: MGAssembly, lighting: MGStudioLighting = .studio, options: MGStudioOptions = MGStudioOptions()) {
        self.assembly = assembly; self.lighting = lighting; self.options = options
        view = MGSolidView(assembly)
        camera = MGSolidCamera(target: .zero, yaw: 30, pitch: 25, distance: 300)
        scene.rootNode.addChildNode(stageNode)
        stageNode.simdTransform = MGSolidRenderer.matrix(MGSolidStage.zUpToYUp)
        buildEnvironment()
        buildLights()
        let cam = SCNCamera()
        cam.wantsHDR = true
        cam.exposureOffset = CGFloat(lighting.exposure)
        cam.wantsExposureAdaptation = false
        cam.bloomIntensity = options.bloom ? 0.22 : 0
        cam.bloomThreshold = 0.92
        cam.bloomBlurRadius = 10
        cam.vignettingIntensity = 0.35
        cam.vignettingPower = 1.2
        cam.projectionDirection = .vertical
        if options.ambientOcclusion {
            cam.screenSpaceAmbientOcclusionIntensity = 0.9
            cam.screenSpaceAmbientOcclusionRadius = 5
            cam.screenSpaceAmbientOcclusionBias = 0.03
            cam.screenSpaceAmbientOcclusionDepthThreshold = 0.2
            cam.screenSpaceAmbientOcclusionNormalThreshold = 0.3
        }
        cameraNode.camera = cam
        scene.rootNode.addChildNode(cameraNode)
        rebuildParts()
        frame(MGPoseParameters(), yaw: 32, pitch: 28, aspect: 1.6)
    }

    // MARK: Assembly and pose

    /// Replaces the assembly. Parts keep their nodes when id, mesh and material are unchanged (a patch that only
    /// changes kinematics or one part's material does not rebuild the others).
    /// The view resets to the new assembly's plain view (parts' own opacity and light, nothing cut).
    public func setAssembly(_ new: MGAssembly) {
        let old = Dictionary(assembly.parts.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        assembly = new
        view = MGSolidView(new)
        let ids = Set(new.parts.map(\.id))
        for (id, node) in partNodes where !ids.contains(id) {
            node.removeFromParentNode(); partNodes[id] = nil; plainGeometry[id] = nil
            cutGeometry = cutGeometry.filter { !$0.key.hasPrefix(id + "|") }
        }
        for p in new.parts {
            if let o = old[p.id], o.mesh == p.mesh, o.creaseAngle == p.creaseAngle, let node = partNodes[p.id] {
                if partMaterials[p.id] != p.material { style(node, p) }
                continue
            }
            partNodes[p.id]?.removeFromParentNode()
            cutGeometry = cutGeometry.filter { !$0.key.hasPrefix(p.id + "|") }
            partNodes[p.id] = makeNode(p)
        }
        partMaterials = partMaterials.filter { ids.contains($0.key) }
        applyGeometry()
        restyleAll()
    }

    private func rebuildParts() {
        partNodes.values.forEach { $0.removeFromParentNode() }
        partNodes = [:]
        for p in assembly.parts { partNodes[p.id] = makeNode(p) }
        restyleAll()
    }

    private func makeNode(_ p: MGPart) -> SCNNode {
        let g = MGSolidRenderer.geometry(p.mesh.renderMesh(creaseAngle: p.creaseAngle))
        plainGeometry[p.id] = g
        let node = SCNNode(geometry: g)
        node.name = p.id
        partNodes[p.id] = node
        style(node, p)
        stageNode.addChildNode(node)
        return node
    }

    /// Gives a part node its preset's material (shared unless the part is modified) and records the preset.
    private func style(_ node: SCNNode, _ p: MGPart) {
        partMaterials[p.id] = p.material
        restyle(p.id)
    }

    /// Shows a view: each cut part swaps in its capped cut geometry (built once per cut and kept), and every part
    /// takes its opacity and light. Pass `document.view(step:)` for an authored step, `MGSolidView(assembly)` for none.
    public func show(_ view: MGSolidView) {
        self.view = view
        applyGeometry()
        restyleAll()
    }

    private func applyGeometry() {
        for (id, node) in partNodes {
            let g: SCNGeometry?
            if let cut = view.part(id).cut, let p = assembly.part(id) {
                let key = "\(id)|\(cut.plane.normal.x),\(cut.plane.normal.y),\(cut.plane.normal.z),\(cut.plane.offset)"
                let print = [Double(cut.mesh.triangleCount), Double(cut.mesh.positions.count), Double(cut.capTriangleCount), cut.capArea]
                if let hit = cutGeometry[key], hit.fingerprint == print { g = hit.geometry } else {
                    let made = MGSolidRenderer.geometry(cut.renderMesh(creaseAngle: p.creaseAngle))
                    cutGeometry[key] = (print, made); g = made
                }
            } else { g = plainGeometry[id] }
            guard let geometry = g, node.geometry !== geometry else { continue }
            let materials = node.geometry?.materials ?? []
            node.geometry = geometry
            geometry.materials = materials
        }
    }

    /// Moves every part to the pose for `params` (pure kinematics, no geometry rebuild).
    public func apply(_ params: MGPoseParameters) {
        let pose = assembly.pose(params)
        SCNTransaction.begin(); SCNTransaction.disableActions = true
        for (id, node) in partNodes { node.simdTransform = MGSolidRenderer.matrix(pose.world[id] ?? .identity) }
        SCNTransaction.commit()
    }

    /// Emphasises some parts: the others are dimmed (still opaque, so depth and shadows stay readable).
    public func highlight(_ ids: Set<String>, dimOthers: Bool = true) {
        highlighted = ids; self.dimOthers = dimOthers
        restyleAll()
    }

    private func restyleAll() { for id in partNodes.keys { restyle(id) } }

    /// Material and node settings of one part from its preset, its view (opacity, light), the highlight and the legacy
    /// section option. Unmodified parts share the cached preset material.
    private func restyle(_ id: String) {
        guard let node = partNodes[id] else { return }
        let preset = partMaterials[id] ?? .brushedSteel
        let pv = view.part(id)
        let light = pv.emission.flatMap { $0.intensity > 0 ? $0 : nil }
        let base = material(for: preset, emission: light)
        let dim = !highlighted.isEmpty && dimOthers && !highlighted.contains(id)
        let emphasise = highlighted.contains(id)
        let seeThrough = pv.opacity < 1
        var m = base
        if !highlighted.isEmpty || seeThrough || sectionApplies(id) { m = base.copy() as! SCNMaterial }
        if dim {
            m.multiply.contents = CGColor(srgbRed: 0.30, green: 0.32, blue: 0.38, alpha: 1)
        } else if emphasise && light == nil {
            m.emission.contents = CGColor(srgbRed: 0.55, green: 0.66, blue: 1.0, alpha: 1)
            m.emission.intensity = 0.05
        }
        if seeThrough {
            // A ghost lets the parts behind it show: blend, sort after opaque parts, and keep its own faces from
            // hiding each other. A rough, non-metal finish keeps its highlights from blooming into a glowing slab.
            m.metalness.contents = NSNumber(value: 0.0)
            m.roughness.contents = NSNumber(value: 0.85)
            m.clearCoat.contents = NSNumber(value: 0.0)
            m.blendMode = .alpha
            m.transparencyMode = .dualLayer
            m.writesToDepthBuffer = false
        }
        applySection(to: m, id: id)
        node.geometry?.materials = [m]
        node.opacity = CGFloat(pv.opacity)
        node.castsShadow = preset != .glass && pv.opacity >= 0.5
        node.renderingOrder = preset == .glass || seeThrough ? 10 : 0
    }

    // MARK: Camera

    /// Frames the posed assembly (union of the given poses' bounds if several explode values are passed).
    public func frame(_ params: MGPoseParameters, explodeRange: [Double] = [], yaw: Double, pitch: Double, aspect: Double,
                      fieldOfView: Double = 30, margin: Double = 1.08) {
        let b = worldBounds(params, explodeRange: explodeRange)
        setCamera(MGSolidCamera.framing(b, yaw: yaw, pitch: pitch, aspect: aspect, fieldOfView: fieldOfView, margin: margin))
    }

    public func worldBounds(_ params: MGPoseParameters, explodeRange: [Double] = []) -> MGBounds {
        var b = MGBounds.empty
        for e in [params.explode] + explodeRange {
            let pose = assembly.pose(MGPoseParameters(input: params.input, explode: e))
            for p in assembly.parts {
                let t = MGSolidStage.zUpToYUp * (pose.world[p.id] ?? .identity)
                for c in p.mesh.bounds.corners { b.include(t.apply(c)) }
            }
        }
        return b
    }

    public func setCamera(_ c: MGSolidCamera) {
        camera = c
        let pos = c.position, tgt = c.targetVector
        cameraNode.simdPosition = simd_float3(Float(pos.x), Float(pos.y), Float(pos.z))
        cameraNode.simdLook(at: simd_float3(Float(tgt.x), Float(tgt.y), Float(tgt.z)), up: simd_float3(0, 1, 0), localFront: simd_float3(0, 0, -1))
        cameraNode.camera?.fieldOfView = CGFloat(c.fieldOfView)
        cameraNode.camera?.zNear = max(0.5, c.distance * 0.05)
        cameraNode.camera?.zFar = c.distance * 6
        cameraNode.camera?.screenSpaceAmbientOcclusionRadius = CGFloat(max(2, c.distance * 0.012))
        updateGround()
    }

    // MARK: Offscreen rendering

    /// Renders the current pose and camera to an sRGB image of `width` x `height` pixels, composited over the studio
    /// backdrop. Returns nil when no Metal device is available.
    public func render(width: Int, height: Int) -> CGImage? {
        #if canImport(Metal)
        if renderer == nil {
            guard let device = MTLCreateSystemDefaultDevice() else { return nil }
            let r = SCNRenderer(device: device, options: nil)
            r.scene = scene
            r.autoenablesDefaultLighting = false
            renderer = r
        }
        guard let r = renderer else { return nil }
        r.pointOfView = cameraNode
        // Offscreen exports never return to the run loop, so commit implicit scene-graph changes explicitly.
        SCNTransaction.flush()
        let ss = max(1, options.supersample)
        let size = CGSize(width: width * ss, height: height * ss)
        let snapshot = r.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)
        #if canImport(UIKit)
        guard let raw = snapshot.cgImage else { return nil }
        #else
        guard let raw = snapshot.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        #endif
        return MGSolidRenderer.composite(raw, width: width, height: height, background: lighting.background)
        #else
        return nil
        #endif
    }

    /// Projects a world (Y-up) point to output pixel coordinates (origin top-left) for overlays.
    public func project(_ p: MGVec3, width: Int, height: Int) -> CGPoint? {
        let c = camera, aspect = Double(width) / Double(height)
        let fwd = (c.targetVector - c.position).normalized
        let right = fwd.cross(c.up).normalized, up = right.cross(fwd)
        let d = p - c.position
        let z = d.dot(fwd)
        guard z > 1e-6 else { return nil }
        let f = 1 / tan(c.fieldOfView * .pi / 360)
        let x = d.dot(right) / z * f / aspect, y = d.dot(up) / z * f
        return CGPoint(x: (x + 1) / 2 * Double(width), y: (1 - y) / 2 * Double(height))
    }

    /// World position (Y-up) of a point given in a part's local frame, for the current pose parameters.
    public func worldPoint(part id: String, local: MGVec3, params: MGPoseParameters) -> MGVec3 {
        let t = MGSolidStage.zUpToYUp * (assembly.pose(params).world[id] ?? .identity)
        return t.apply(local)
    }

    // MARK: Materials

    private func material(for preset: MGMaterialPreset, emission: MGEmission?) -> SCNMaterial {
        let key = preset.id + (emission.map { "+" + $0.id } ?? "")
        if let m = materialCache[key] { return m }
        let m = MGSolidRenderer.scnMaterial(preset)
        if let e = emission {
            // HDR emission that the camera's bloom picks up above intensity 1.
            m.emission.contents = CGColor(srgbRed: e.color[0], green: e.color[1], blue: e.color[2], alpha: 1)
            m.emission.intensity = CGFloat(e.intensity)
        }
        materialCache[key] = m
        return m
    }

    public static func scnMaterial(_ preset: MGMaterialPreset) -> SCNMaterial {
        let p = preset.parameters
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = CGColor(srgbRed: p.baseColor[0], green: p.baseColor[1], blue: p.baseColor[2], alpha: 1)
        m.metalness.contents = NSNumber(value: p.metallic)
        m.roughness.contents = NSNumber(value: p.roughness)
        if p.clearcoat > 0 {
            m.clearCoat.contents = NSNumber(value: p.clearcoat)
            m.clearCoatRoughness.contents = NSNumber(value: p.clearcoatRoughness)
        }
        switch preset {
        case .brushedSteel:
            // Fine anisotropic-looking streaks via a procedural roughness variation.
            m.roughness.contents = brushedRoughness(base: p.roughness)
            m.roughness.wrapS = .repeat; m.roughness.wrapT = .repeat
        default: break
        }
        if p.transmission > 0 {
            m.transparency = CGFloat(p.opacity)
            m.blendMode = .alpha
            m.transparencyMode = .dualLayer
            m.isDoubleSided = true
            m.writesToDepthBuffer = false
            m.fresnelExponent = 1.5
        }
        return m
    }

    private static func brushedRoughness(base: Double) -> CGImage? {
        let w = 256, h = 256
        var px = [UInt8](repeating: 0, count: w * h)
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func rnd() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 33) / Double(1 << 31) }
        var rows = [Double](repeating: 0, count: h)
        for y in 0..<h { rows[y] = rnd() }
        for y in 0..<h {
            for x in 0..<w {
                let streak = 0.6 * rows[y] + 0.4 * rows[(y + 1) % h]
                let r = min(1, max(0, base + (streak - 0.5) * 0.07))
                px[y * w + x] = UInt8(r * 255)
            }
        }
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        return ctx.makeImage()
    }

    // MARK: Legacy section plane (uncapped fragment discard)

    private func sectionApplies(_ id: String) -> Bool {
        options.section != nil && (options.sectionParts.isEmpty || options.sectionParts.contains(id))
    }

    private func applySection(to m: SCNMaterial, id: String) {
        guard let s = options.section, sectionApplies(id) else {
            if m.shaderModifiers != nil {
                m.shaderModifiers = nil
                m.isDoubleSided = (partMaterials[id]?.parameters.transmission ?? 0) > 0
            }
            return
        }
        m.shaderModifiers = [.fragment: """
            #pragma arguments
            float4 mgSection;
            #pragma body
            float4 mgWorld = scn_frame.inverseViewTransform * float4(_surface.position, 1.0);
            if (dot(mgWorld.xyz, mgSection.xyz) > mgSection.w) { discard_fragment(); }
            """]
        m.isDoubleSided = true
        m.setValue(NSValue(scnVector4: SCNVector4(Float(s.normal.x), Float(s.normal.y), Float(s.normal.z), Float(s.offset))), forKey: "mgSection")
    }


    // MARK: Environment, lights, ground

    private func buildEnvironment() {
        scene.lightingEnvironment.contents = MGSolidRenderer.environmentImage(lighting.environment, width: 1024, height: 512)
        scene.lightingEnvironment.intensity = CGFloat(lighting.environment.intensity)
        scene.background.contents = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0)
    }

    private func buildLights() {
        for l in lighting.lights {
            let light = SCNLight()
            light.type = .directional
            light.color = CGColor(srgbRed: l.color[0], green: l.color[1], blue: l.color[2], alpha: 1)
            light.intensity = CGFloat(l.intensity)
            if l.castsShadow && options.shadows {
                light.castsShadow = true
                light.shadowMode = .forward
                light.shadowSampleCount = 24
                light.shadowRadius = CGFloat(l.softness * 1.6)
                light.shadowMapSize = CGSize(width: 4096, height: 4096)
                light.shadowColor = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.62)
                light.automaticallyAdjustsShadowProjection = false
                light.forcesBackFaceCasters = true
            }
            let node = SCNNode()
            node.light = light
            node.name = l.name
            let d = simd_normalize(simd_float3(Float(l.direction[0]), Float(l.direction[1]), Float(l.direction[2])))
            node.simdOrientation = simd_quatf(from: simd_float3(0, 0, -1), to: d)
            scene.rootNode.addChildNode(node)
            if l.castsShadow { keyLight = node }
        }
    }

    private func updateGround() {
        groundNodes.forEach { $0.removeFromParentNode() }
        groundNodes = []
        guard options.ground else { return }
        let b = worldBounds(MGPoseParameters())
        guard !b.isEmpty else { return }
        let r = max(b.size.x, b.size.z)
        let y = Float(b.min.y - 0.05)
        // Fit the key light's orthographic shadow frustum around the model (exploded extent included).
        if let key = keyLight, let light = key.light {
            let wide = worldBounds(MGPoseParameters(), explodeRange: [1])
            let radius = max(1, wide.radius)
            let dir = key.simdWorldFront
            let c = simd_float3(Float(wide.center.x), Float(wide.center.y), Float(wide.center.z))
            key.simdPosition = c - dir * Float(radius * 3)
            light.orthographicScale = CGFloat(radius * 1.25)
            light.zNear = CGFloat(radius * 0.5); light.zFar = CGFloat(radius * 6)
        }
        // Shadow catcher: only the key light's soft shadow shows, composited over the backdrop.
        let plane = SCNPlane(width: CGFloat(r * 8), height: CGFloat(r * 8))
        let sm = SCNMaterial(); sm.lightingModel = .shadowOnly; sm.writesToDepthBuffer = false
        plane.materials = [sm]
        let ground = SCNNode(geometry: plane)
        ground.eulerAngles.x = -.pi / 2
        ground.simdPosition = simd_float3(Float(b.center.x), y, Float(b.center.z))
        ground.castsShadow = false
        scene.rootNode.addChildNode(ground); groundNodes.append(ground)
        // Contact occlusion: a soft dark ellipse right under the model.
        let blob = SCNPlane(width: CGFloat(b.size.x * 1.7), height: CGFloat(b.size.z * 1.7))
        let bm = SCNMaterial()
        bm.lightingModel = .constant
        bm.diffuse.contents = MGSolidRenderer.radialAlpha(size: 256)
        bm.transparent.contents = MGSolidRenderer.radialAlpha(size: 256)
        bm.transparencyMode = .aOne
        bm.blendMode = .alpha
        bm.writesToDepthBuffer = false
        blob.materials = [bm]
        let blobNode = SCNNode(geometry: blob)
        blobNode.eulerAngles.x = -.pi / 2
        blobNode.simdPosition = simd_float3(Float(b.center.x), y + 0.02, Float(b.center.z))
        blobNode.castsShadow = false
        blobNode.renderingOrder = 5
        scene.rootNode.addChildNode(blobNode); groundNodes.append(blobNode)
    }

    // MARK: Image helpers

    /// Procedural equirectangular studio environment (float RGBA, linear-ish values above 1 for soft boxes).
    public static func environmentImage(_ e: MGStudioLighting.Environment, width w: Int, height h: Int) -> CGImage? {
        var px = [Float](repeating: 0, count: w * h * 4)
        func mix(_ a: [Double], _ b: [Double], _ t: Double) -> [Double] { (0..<3).map { a[$0] + (b[$0] - a[$0]) * t } }
        func smooth(_ x: Double) -> Double { let t = min(1, max(0, x)); return t * t * (3 - 2 * t) }
        for y in 0..<h {
            let el = (0.5 - (Double(y) + 0.5) / Double(h)) * 180
            let base = el >= 0 ? mix(e.horizon, e.zenith, pow(el / 90, 0.55)) : mix(e.horizon, e.floor, smooth(-el / 12))
            for x in 0..<w {
                let az = ((Double(x) + 0.5) / Double(w) - 0.5) * 360
                var c = base
                for s in e.softboxes where s.count >= 8 {
                    var daz = abs(az - s[0]); if daz > 180 { daz = 360 - daz }
                    let del = abs(el - s[1])
                    let fx = 1 - smooth((daz - s[2] / 2 * 0.75) / (s[2] / 2 * 0.25 + 1e-6))
                    let fy = 1 - smooth((del - s[3] / 2 * 0.75) / (s[3] / 2 * 0.25 + 1e-6))
                    let f = fx * fy * s[7]
                    if f > 0 { c = (0..<3).map { c[$0] + s[4 + $0] * f } }
                }
                let i = (y * w + x) * 4
                px[i] = Float(c[0]); px[i + 1] = Float(c[1]); px[i + 2] = Float(c[2]); px[i + 3] = 1
            }
        }
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.floatComponents.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        guard let space = CGColorSpace(name: CGColorSpace.extendedLinearSRGB) else { return nil }
        return px.withUnsafeMutableBytes { buf -> CGImage? in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 32, bytesPerRow: w * 16,
                                      space: space, bitmapInfo: info.rawValue) else { return nil }
            return ctx.makeImage()
        }
    }

    static func radialAlpha(size: Int) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let colors = [0.72, 0.62, 0.34, 0.12, 0].map { CGColor(srgbRed: 0, green: 0, blue: 0, alpha: $0) } as CFArray
        guard let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.52, 0.66, 0.82, 1]) else { return nil }
        let c = CGPoint(x: size / 2, y: size / 2)
        ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: CGFloat(size) / 2, options: [])
        return ctx.makeImage()
    }

    /// Downsamples the supersampled render and composites it over a soft radial studio backdrop.
    static func composite(_ img: CGImage, width: Int, height: Int, background bg: [Double]) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        let inner = CGColor(srgbRed: min(1, bg[0] * 2.6), green: min(1, bg[1] * 2.5), blue: min(1, bg[2] * 2.3), alpha: 1)
        let outer = CGColor(srgbRed: bg[0] * 0.55, green: bg[1] * 0.55, blue: bg[2] * 0.6, alpha: 1)
        ctx.setFillColor(outer); ctx.fill(rect)
        if let g = CGGradient(colorsSpace: space, colors: [inner, outer] as CFArray, locations: [0, 1]) {
            let c = CGPoint(x: Double(width) * 0.5, y: Double(height) * 0.58)
            ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: CGFloat(max(width, height)) * 0.72,
                                   options: [.drawsAfterEndLocation])
        }
        ctx.interpolationQuality = .high
        ctx.draw(img, in: rect)
        return ctx.makeImage()
    }

    // MARK: Conversions

    static func matrix(_ t: MGTransform) -> simd_float4x4 {
        let v = t.columnMajor.map(Float.init)
        return simd_float4x4(columns: (simd_float4(v[0], v[1], v[2], v[3]), simd_float4(v[4], v[5], v[6], v[7]),
                                       simd_float4(v[8], v[9], v[10], v[11]), simd_float4(v[12], v[13], v[14], v[15])))
    }

    public static func geometry(_ m: MGRenderMesh) -> SCNGeometry {
        let verts = m.positions.map { SCNVector3(Float($0.x), Float($0.y), Float($0.z)) }
        let norms = m.normals.map { SCNVector3(Float($0.x), Float($0.y), Float($0.z)) }
        // Texture coordinates: v follows the radius about the part's local Z axis, so streaked textures read as
        // concentric turning marks on gear faces.
        let uv = m.positions.map { p in CGPoint(x: atan2(p.y, p.x) * 8, y: (p.x * p.x + p.y * p.y).squareRoot() / 40) }
        let element = SCNGeometryElement(indices: m.indices, primitiveType: .triangles)
        return SCNGeometry(sources: [SCNGeometrySource(vertices: verts), SCNGeometrySource(normals: norms), SCNGeometrySource(textureCoordinates: uv)],
                           elements: [element])
    }
}
