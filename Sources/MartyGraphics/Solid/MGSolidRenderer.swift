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
    /// The key light's shadow map (pixels per side) and its soft-shadow samples. Read when the renderer is made.
    public var shadowMapSize = 4096
    public var shadowSamples = 24
    public init() {}

    /// The options of a quality level (`MGSolidQuality`): `still` is `MGStudioOptions()`.
    public init(quality: MGSolidQuality) {
        switch quality {
        case .still: break
        case .balanced: supersample = 1; shadowSamples = 16
        case .interactive: supersample = 1; shadowSamples = 8; shadowMapSize = 2048; ambientOcclusion = false; bloom = false
        }
    }

    public static func == (a: MGStudioOptions, b: MGStudioOptions) -> Bool {
        a.shadows == b.shadows && a.ambientOcclusion == b.ambientOcclusion && a.bloom == b.bloom && a.supersample == b.supersample
            && a.section?.normal == b.section?.normal && a.section?.offset == b.section?.offset && a.sectionParts == b.sectionParts
            && a.ground == b.ground && a.shadowMapSize == b.shadowMapSize && a.shadowSamples == b.shadowSamples
    }
}

/// How much the renderer spends on a frame. `interactive` keeps a live view smooth on an iPad (a smaller shadow map
/// with fewer samples, no ambient occlusion, no bloom, no supersampling); `balanced` suits a live view on a Mac or a
/// recent iPad; `still` is the offline quality of `marty-solid render` and the default of `MGStudioOptions()`.
/// A level changes pixels only. See docs/VISUAL-STYLE.md.
public enum MGSolidQuality: String, CaseIterable, Sendable { case interactive, balanced, still }

/// How a solid renderer draws highlighted parts (`MGSolidRenderer.emphasis`).
public enum MGSolidEmphasis: Equatable, Sendable { case subtle, strong }

/// SceneKit studio renderer for solid assemblies: PBR material presets, a procedural studio environment for image-based
/// lighting, key/fill/rim lights, soft shadows, screen-space ambient occlusion and a contact ground. Renders offscreen to
/// `CGImage`, or exposes `scene` for an interactive `SCNView`.
public final class MGSolidRenderer {
    public let scene = SCNScene()
    public private(set) var assembly: MGAssembly
    public let lighting: MGStudioLighting
    /// The presentation (backdrop, tone, fill, shadow strength); pixels only. See `MGSolidLook`.
    public let look: MGSolidLook
    /// The rig as the look lights it (the same lights and directions, scaled).
    private let lit: MGStudioLighting
    private var backdropCache: (key: [Double], image: CGImage)?
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
    /// How highlighted parts look. `.subtle` (the default, unchanged) adds a faint cool glow and dims the others;
    /// `.strong` (explainers) gives highlighted parts the 2D board's emphasis colour as a clear glow and dims the others
    /// further, so a highlight reads at a glance in a still, also when every part is highlighted.
    public var emphasis: MGSolidEmphasis = .subtle { didSet { restyleAll() } }
    /// What each part shows (cuts, opacity, light); `show(_:)` sets it.
    public private(set) var view: MGSolidView
    /// Uncut geometry of every part, and the geometry of each capped cut shown so far (keyed by part and local plane).
    private var plainGeometry: [String: SCNGeometry] = [:]
    /// Keyed by part id and local plane. A hit must hold an equal cut (full content); arrays compare by storage first,
    /// so showing the same cut again (the steps of one document share it) costs O(1), and a different cut is rebuilt.
    private var cutGeometry: [String: (cut: MGSectionCut, geometry: SCNGeometry)] = [:]
    /// Arrow and dimension pieces: one node per piece under one `annotations` node, built once per document. Pose
    /// changes set node transforms only; geometry is never rebuilt. They show only through `show(document:view:)`, and
    /// only when this renderer was loaded from that same compiled document (`init(document:)`, `setDocument(_:)`).
    private let annotationsNode = SCNNode()
    private var annotationDocument: MGSolidDocument?
    /// The fingerprint of the compiled document whose assembly this renderer shows; nil after `init(assembly:)` or
    /// `setAssembly(_:)`, so annotations never show against an assembly that did not come from their document.
    private var loadedFingerprint: String?
    /// True after a `show(document:view:)` that passed; any other `show(_:)` turns annotations off.
    private var annotationsOn = false
    /// A renderer-level switch that hides annotation pieces without changing what the engine checked.
    public var annotationsHidden = false { didSet { updateAnnotations() } }
    private var annotationNodes: [String: [SCNNode]] = [:]
    private var annotationMaterials: [String: SCNMaterial] = [:]
    private var emphasisedAnnotations: Set<String> = []
    private var posed = MGPoseParameters()
    private lazy var unitCylinder = MGSolidRenderer.geometry(MGAnnotationPrimitive(shape: .cylinder, start: .zero, end: .unitZ, radius: 1, hidden: false).renderMesh)
    private lazy var unitCone = MGSolidRenderer.geometry(MGAnnotationPrimitive(shape: .cone, start: .zero, end: .unitZ, radius: 1, hidden: false).renderMesh)

    public init(assembly: MGAssembly, lighting: MGStudioLighting = .studio, options: MGStudioOptions = MGStudioOptions(),
                look: MGSolidLook = .classic) {
        self.assembly = assembly; self.lighting = lighting; self.options = options
        self.look = look; lit = look.lighting(lighting)
        view = MGSolidView(assembly)
        camera = MGSolidCamera(target: .zero, yaw: 30, pitch: 25, distance: 300)
        scene.rootNode.addChildNode(stageNode)
        stageNode.simdTransform = MGSolidRenderer.matrix(MGSolidStage.zUpToYUp)
        annotationsNode.name = "annotations"
        stageNode.addChildNode(annotationsNode)
        buildEnvironment()
        buildLights()
        let cam = SCNCamera()
        cam.wantsHDR = true
        cam.exposureOffset = CGFloat(lighting.exposure + look.exposure)
        cam.wantsExposureAdaptation = false
        cam.bloomIntensity = options.bloom ? CGFloat(look.bloom) : 0
        cam.bloomThreshold = 0.92
        cam.bloomBlurRadius = 10
        if look == .classic {
            cam.vignettingIntensity = 0.35
            cam.vignettingPower = 1.2
        } else {
            // The backdrop carries the vignette; the subject keeps its exposure to the frame's edge.
            cam.whitePoint = CGFloat(look.whitePoint)
            cam.contrast = CGFloat(look.contrast)
            cam.saturation = CGFloat(look.saturation)
        }
        cam.projectionDirection = .vertical
        if options.ambientOcclusion {
            cam.screenSpaceAmbientOcclusionIntensity = CGFloat(look.occlusion)
            cam.screenSpaceAmbientOcclusionRadius = 5
            cam.screenSpaceAmbientOcclusionBias = 0.03
            cam.screenSpaceAmbientOcclusionDepthThreshold = 0.2
            cam.screenSpaceAmbientOcclusionNormalThreshold = 0.3
        }
        cameraNode.camera = cam
        scene.rootNode.addChildNode(cameraNode)
        rebuildParts()
        poseNodes()
        frame(MGPoseParameters(), yaw: 32, pitch: 28, aspect: 1.6)
    }

    // MARK: Assembly and pose

    /// Replaces the assembly. Parts keep their nodes when id, mesh and material are unchanged (a patch that only
    /// changes kinematics or one part's material does not rebuild the others).
    /// The view resets to the new assembly's plain view (parts' own opacity and light, nothing cut).
    public func setAssembly(_ new: MGAssembly) {
        // Annotations belong to a document; an assembly set on its own has none.
        buildAnnotations(nil)
        loadedFingerprint = nil
        annotationsOn = false
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
        // Kept and new nodes take the new assembly's placements at the current pose.
        SCNTransaction.begin(); SCNTransaction.disableActions = true
        poseNodes()
        SCNTransaction.commit()
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
    /// This shows no annotations; use `show(document:view:)` for them.
    public func show(_ view: MGSolidView) {
        self.view = view
        annotationsOn = false
        applyGeometry()
        restyleAll()
        updateAnnotations()
    }

    /// The renderer shows a document: its assembly, with no step view (`setAssembly`), and it remembers the document's
    /// fingerprint so `show(document:view:)` can draw its annotations.
    /// The parts start at the document's default pose.
    public convenience init(document: MGSolidDocument, lighting: MGStudioLighting = .studio, options: MGStudioOptions = MGStudioOptions(),
                            look: MGSolidLook = .classic) {
        self.init(assembly: document.assembly, lighting: lighting, options: options, look: look)
        loadedFingerprint = document.checkedFingerprint
        apply(document.defaults)
    }

    /// Replaces the assembly with a document's and remembers the document, as `init(document:)` does; the parts move to
    /// the document's default pose.
    public func setDocument(_ document: MGSolidDocument) {
        setAssembly(document.assembly)
        loadedFingerprint = document.checkedFingerprint
        apply(document.defaults)
    }

    /// Shows a document's view with its annotations. They draw only when this renderer was loaded from the same
    /// compiled document (`init(document:)` or `setDocument(_:)`), and only for poses the engine checked
    /// (`MGSolidDocument.checkedAnnotations`); otherwise the view shows without annotations.
    /// Part nodes are posed at the current pose first, and the annotations attach after them, in one SceneKit
    /// transaction.
    public func show(document: MGSolidDocument, view: MGSolidView) {
        SCNTransaction.begin(); SCNTransaction.disableActions = true
        self.view = view
        applyGeometry()
        restyleAll()
        poseNodes()
        annotationsOn = loadedFingerprint != nil && loadedFingerprint == document.checkedFingerprint
        if annotationsOn, annotationDocument?.checkedFingerprint != document.checkedFingerprint { buildAnnotations(document) }
        updateAnnotations()
        SCNTransaction.commit()
    }

    private func applyGeometry() {
        for (id, node) in partNodes {
            let g: SCNGeometry?
            if let cut = view.part(id).cut, let p = assembly.part(id) {
                let key = "\(id)|\(cut.plane.normal.x),\(cut.plane.normal.y),\(cut.plane.normal.z),\(cut.plane.offset)"
                if let hit = cutGeometry[key], hit.cut == cut { g = hit.geometry } else {
                    let made = MGSolidRenderer.geometry(cut.renderMesh(creaseAngle: p.creaseAngle))
                    cutGeometry[key] = (cut, made); g = made
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
        posed = params
        SCNTransaction.begin(); SCNTransaction.disableActions = true
        poseNodes()
        updateAnnotations()
        SCNTransaction.commit()
    }

    /// Moves every part node to the current pose (`posed`). Every path that loads geometry or shows annotations calls
    /// it first, so annotation pieces never show beside part nodes in another pose.
    private func poseNodes() {
        let pose = assembly.pose(posed)
        for (id, node) in partNodes { node.simdTransform = MGSolidRenderer.matrix(pose.world[id] ?? .identity) }
    }

    // MARK: Annotations

    /// Builds the arrow and dimension pieces of a compiled document (nil removes them). Which ones show follows the
    /// view (`show(document:view:)`); where they are follows the pose (`apply(_:)`). Labels are drawn by the overlay
    /// (`MGSolidOverlayView`), not in the scene. Pieces are not cut, not ghosted and cast no shadow.
    private func buildAnnotations(_ document: MGSolidDocument?) {
        annotationsNode.childNodes.forEach { $0.removeFromParentNode() }
        annotationNodes = [:]; annotationMaterials = [:]; emphasisedAnnotations = []
        annotationDocument = document
        guard let doc = document, !doc.annotations.isEmpty else { return }
        for id in doc.annotations.ids where doc.annotations.kind(id) != "label" {
            let role = doc.annotations.arrow(id)?.colorRole ?? MGSolidAnnotations.dimensionRole
            let m = SCNMaterial()
            m.lightingModel = .physicallyBased
            let c = MGSolidAnnotations.srgb(role)
            m.diffuse.contents = CGColor(srgbRed: c[0], green: c[1], blue: c[2], alpha: 1)
            m.emission.contents = CGColor(srgbRed: c[0], green: c[1], blue: c[2], alpha: 1)
            m.emission.intensity = 0.6
            m.metalness.contents = NSNumber(value: 0.0)
            m.roughness.contents = NSNumber(value: 0.45)
            annotationMaterials[id] = m
            let cylinder = unitCylinder.copy() as! SCNGeometry, cone = unitCone.copy() as! SCNGeometry
            cylinder.materials = [m]; cone.materials = [m]
            let pieces = MGSolidAnnotations.primitives(doc, id, params: posed, sense: view.motionSense, step: view.step)
            annotationNodes[id] = pieces.map { p in
                let node = SCNNode(geometry: p.shape == .cone ? cone : cylinder)
                node.name = "annotation.\(id)"
                node.castsShadow = false
                annotationsNode.addChildNode(node)
                return node
            }
        }
        updateAnnotations()
    }

    /// Brightens some annotations (a beat or step emphasis).
    public func highlightAnnotations(_ ids: Set<String>) {
        emphasisedAnnotations = ids
        for (id, m) in annotationMaterials { m.emission.intensity = ids.contains(id) ? 1.6 : 0.6 }
    }

    /// Visibility from the view, transforms from the pose: no geometry is built here.
    private func updateAnnotations() {
        guard let doc = annotationDocument else { return }
        // The one gate: annotations only for the loaded document, a view and a pose the engine checked.
        let bound = annotationsOn && !annotationsHidden && loadedFingerprint == doc.checkedFingerprint
        let visible = bound ? Set(doc.checkedAnnotations(view, params: posed) ?? []) : []
        SCNTransaction.begin(); SCNTransaction.disableActions = true
        for (id, nodes) in annotationNodes {
            guard visible.contains(id) else { nodes.forEach { $0.isHidden = true }; continue }
            let pieces = MGSolidAnnotations.primitives(doc, id, params: posed, sense: view.motionSense, step: view.step)
            for (node, p) in zip(nodes, pieces) {
                let d = p.end - p.start
                node.isHidden = p.hidden || d.length < 1e-9
                guard !node.isHidden else { continue }
                node.simdTransform = MGSolidRenderer.pieceMatrix(p)
            }
        }
        SCNTransaction.commit()
    }

    /// Maps the unit piece (radius 1, from z = 0 to z = 1) onto a piece: a scaled, non-rigid transform.
    static func pieceMatrix(_ p: MGAnnotationPrimitive) -> simd_float4x4 {
        let d = p.end - p.start
        let w = d.normalized
        let (u, v) = MGSolidAnnotations.basis(w)
        let a = u * p.radius, b = v * p.radius
        return simd_float4x4(columns: (simd_float4(Float(a.x), Float(a.y), Float(a.z), 0), simd_float4(Float(b.x), Float(b.y), Float(b.z), 0),
                                       simd_float4(Float(d.x), Float(d.y), Float(d.z), 0),
                                       simd_float4(Float(p.start.x), Float(p.start.y), Float(p.start.z), 1)))
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
            m.multiply.contents = emphasis == .strong ? CGColor(srgbRed: 0.20, green: 0.21, blue: 0.25, alpha: 1)
                                                      : CGColor(srgbRed: 0.30, green: 0.32, blue: 0.38, alpha: 1)
        } else if emphasise && light == nil {
            if emphasis == .strong {
                // The 2D emphasis colour (`MGColorRole.yellow`, #FFE066), as a glow and a warm tint.
                m.emission.contents = CGColor(srgbRed: 1.0, green: 0.88, blue: 0.40, alpha: 1)
                m.emission.intensity = 0.32
                m.multiply.contents = CGColor(srgbRed: 1.0, green: 0.93, blue: 0.70, alpha: 1)
            } else {
                m.emission.contents = CGColor(srgbRed: 0.55, green: 0.66, blue: 1.0, alpha: 1)
                m.emission.intensity = 0.05
            }
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
        // A part the view hides (step `hide`, a show-only part outside its steps) is not drawn and casts no shadow.
        node.isHidden = pv.hidden
        node.castsShadow = preset != .glass && pv.opacity >= 0.5
        node.renderingOrder = preset == .glass || seeThrough ? 10 : 0
    }

    // MARK: Camera

    /// Frames the posed assembly (union of the given poses' bounds if several explode values are passed).
    public func frame(_ params: MGPoseParameters, explodeRange: [Double] = [], yaw: Double, pitch: Double, aspect: Double,
                      fieldOfView: Double = 30, margin: Double = 1.08, hidden: Set<String> = []) {
        let b = worldBounds(params, explodeRange: explodeRange, hidden: hidden)
        setCamera(MGSolidCamera.framing(b, yaw: yaw, pitch: pitch, aspect: aspect, fieldOfView: fieldOfView, margin: margin))
    }

    /// Frames one render-plan shot with the library's framing rule (`MGSolidFraming.framing`): the still's effective
    /// camera, the same one `marty-solid render`, the check report, the story and the SwiftUI pane use (subject first,
    /// the unblocked-focus rule and the main-rule fallback included). A SwiftUI or `SCNView` host that shows step `i` calls `frame(MGSolidShot.step(document, i)!, document:
    /// document, aspect:)`; it passes `titleBand: 0, captionBand: 0` when it draws no title or caption over the view.
    public func frame(_ shot: MGSolidShot, document: MGSolidDocument, aspect: Double, fieldOfView: Double = 30,
                      titleBand: Double? = nil, captionBand: Double? = nil) {
        setCamera(MGSolidFraming.camera(document, shot: shot, aspect: aspect, fieldOfView: fieldOfView, titleBand: titleBand,
                                        captionBand: captionBand))
    }

    /// `hidden`: parts left out (a view's hidden parts, `MGSolidView.hiddenParts`).
    public func worldBounds(_ params: MGPoseParameters, explodeRange: [Double] = [], hidden: Set<String> = []) -> MGBounds {
        var b = MGBounds.empty
        for e in [params.explode] + explodeRange {
            let pose = assembly.pose(MGPoseParameters(input: params.input, explode: e, placements: params.placements))
            for p in assembly.parts where !hidden.contains(p.id) {
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
        cameraNode.camera?.zNear = MGSolidFraming.nearPlane(distance: c.distance)
        // A close focus must not cut the rest of the posed model at the far plane: reach its farthest box corner.
        var far = c.distance * 6
        let b = worldBounds(posed)
        if !b.isEmpty { for p in b.corners { far = max(far, (p - pos).length * 1.05) } }
        cameraNode.camera?.zFar = far
        cameraNode.camera?.screenSpaceAmbientOcclusionRadius = CGFloat(max(2, c.distance * 0.012))
        updateGround()
    }

    // MARK: Offscreen rendering

    /// Renders the current pose and camera to an sRGB image of `width` x `height` pixels, composited over the studio
    /// backdrop. Returns nil when no Metal device is available.
    public func render(width: Int, height: Int) -> CGImage? { render(width: width, height: height, clip: nil) }

    /// `render(width:height:)` with the model clipped to `clip`, a safe window in normalised device coordinates
    /// (`MGSolidFraming.Window`): outside it only the studio backdrop is drawn, so no geometry (or its shadow) sits under
    /// a title or caption band. Context that a subject framing cuts ends at the window's edge (docs/SOLID-3D.md,
    /// "Subject first"). Nil `clip`, or a window that is the whole view, draws everything.
    public func render(width: Int, height: Int, clip: MGSolidFraming.Window?) -> CGImage? {
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
        guard look != .classic else {
            return MGSolidRenderer.composite(raw, width: width, height: height, background: lighting.background, clip: clip)
        }
        return MGSolidRenderer.composite(raw, over: backdrop(width: width, height: height), width: width, height: height, clip: clip)
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

    // MARK: Backdrop

    /// The look's light pool for the current camera: centred where the ground under the subject projects, as wide as
    /// `look.poolRadius` projected subject radii, and flattened as the camera lowers (a floor seen at a low angle).
    public func backdropPool(width: Int, height: Int) -> MGSolidLook.Pool {
        let b = worldBounds(MGPoseParameters())
        guard !b.isEmpty, let c = project(MGVec3(b.center.x, b.min.y, b.center.z), width: width, height: height),
              c.x.isFinite, c.y.isFinite else { return .centred(width: width, height: height) }
        let f = 1 / tan(camera.fieldOfView * .pi / 360)
        let r = max(1e-6, b.radius) / max(1e-6, camera.distance) * f * Double(height) / 2
        let rx = max(r * look.poolRadius, Double(max(width, height)) * 0.26)
        let flat = max(0.42, min(1, sin(abs(camera.pitch) * .pi / 180) + 0.25))
        return MGSolidLook.Pool(x: Double(c.x), y: Double(c.y), rx: rx, ry: rx * flat)
    }

    /// The look's backdrop for the current camera (kept until the size or the pool changes).
    private func backdrop(width: Int, height: Int) -> CGImage? {
        let p = backdropPool(width: width, height: height)
        let key = [Double(width), Double(height), p.x.rounded(), p.y.rounded(), p.rx.rounded(), p.ry.rounded()]
        if let hit = backdropCache, hit.key == key { return hit.image }
        let q = MGSolidLook.Pool(x: key[2], y: key[3], rx: key[4], ry: key[5])
        let bytes = look.backdrop(width: width, height: height, pool: q)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB), let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: space,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider,
                                  decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { return nil }
        backdropCache = (key, image)
        return image
    }

    /// Downsamples the supersampled render and composites it over a look's backdrop.
    static func composite(_ img: CGImage, over backdrop: CGImage?, width: Int, height: Int, clip: MGSolidFraming.Window? = nil) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        if let backdrop {
            ctx.interpolationQuality = .none
            ctx.draw(backdrop, in: rect)
        }
        ctx.interpolationQuality = .high
        if let r = MGSolidRenderer.clipRect(clip, width: width, height: height) { ctx.clip(to: r) }
        ctx.draw(img, in: rect)
        return ctx.makeImage()
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
        scene.lightingEnvironment.contents = MGSolidRenderer.environmentImage(lit.environment, width: 1024, height: 512)
        scene.lightingEnvironment.intensity = CGFloat(lit.environment.intensity)
        scene.background.contents = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0)
    }

    private func buildLights() {
        for l in lit.lights {
            let light = SCNLight()
            light.type = .directional
            light.color = CGColor(srgbRed: l.color[0], green: l.color[1], blue: l.color[2], alpha: 1)
            light.intensity = CGFloat(l.intensity)
            if l.castsShadow && options.shadows {
                light.castsShadow = true
                light.shadowMode = .forward
                light.shadowSampleCount = max(1, options.shadowSamples)
                light.shadowRadius = CGFloat(l.softness * 1.6 * look.shadowSoftness)
                light.shadowMapSize = CGSize(width: max(256, options.shadowMapSize), height: max(256, options.shadowMapSize))
                light.shadowColor = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: CGFloat(look.shadow))
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
        if look != .classic { blobNode.opacity = CGFloat(look.contact) }
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
    static func composite(_ img: CGImage, width: Int, height: Int, background bg: [Double], clip: MGSolidFraming.Window? = nil) -> CGImage? {
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
        if let r = MGSolidRenderer.clipRect(clip, width: width, height: height) { ctx.clip(to: r) }
        ctx.draw(img, in: rect)
        return ctx.makeImage()
    }

    /// The pixel rectangle (Core Graphics coordinates, origin at the bottom left) of a safe window in a `width` ×
    /// `height` image; nil for no window or the whole view.
    public static func clipRect(_ w: MGSolidFraming.Window?, width: Int, height: Int) -> CGRect? {
        guard let w = w?.usable, w != MGSolidFraming.Window(left: -1, right: 1, bottom: -1, top: 1) else { return nil }
        let W = Double(width), H = Double(height)
        return CGRect(x: (w.left + 1) / 2 * W, y: (w.bottom + 1) / 2 * H, width: (w.right - w.left) / 2 * W, height: (w.top - w.bottom) / 2 * H)
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
