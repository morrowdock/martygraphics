// SPDX-License-Identifier: Apache-2.0
import SwiftUI
import SceneKit
import simd
#if canImport(UIKit)
import UIKit
typealias MGPlatformColor = UIColor
typealias MGBezier = UIBezierPath
#else
import AppKit
typealias MGPlatformColor = NSColor
typealias MGBezier = NSBezierPath
#endif

/// SceneKit renderer for 3D scenes (body, incline, line, vector, axes, orbit, text, highlight, path).
/// Drag to orbit, pinch to zoom. Motion runs on SceneKit's render loop with the same `MGTimeline.frame` as 2D.
struct MG3DView {
    let scene: MGScene
    let items: [MGItem]
    /// Real motion is playing on a visible board in an active app (MGRenderPolicy.sceneKitPlaying).
    let playing: Bool

    /// Never render continuously. SceneKit advances only while motion plays; otherwise it redraws on
    /// demand, which still includes camera gestures (allowsCameraControl), so orbiting a static scene stays live.
    static func configure(_ view: SCNView, playing: Bool, animates: Bool) {
        view.rendersContinuously = false
        view.isPlaying = playing && animates
    }

    final class Coordinator: NSObject, SCNSceneRendererDelegate {
        let lock = NSLock()
        var scene: MGScene?
        var items: [MGItem] = []
        var playing = true
        var start: TimeInterval?
        var paused: TimeInterval = 0
        var nodes: [String: SCNNode] = [:]
        var builtSignature = ""
        let root = SCNNode()

        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            lock.lock(); let scene = self.scene, items = self.items, playing = self.playing; lock.unlock()
            guard let scene, scene.animates else { return }
            if start == nil { start = time }
            let t = playing ? time - (start ?? time) : paused
            if playing { paused = t } else { start = time - paused }
            let frame = MGTimeline.frame(scene, items: items, time: t)
            MG3DBuilder.update(frame, scene: scene, nodes: nodes)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeView(_ c: Coordinator) -> SCNView {
        let view = SCNView()
        let s = SCNScene()
        s.rootNode.addChildNode(c.root)
        view.scene = s
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        view.antialiasingMode = .multisampling4X
        view.backgroundColor = MGPlatformColor(red: 0.04, green: 0.06, blue: 0.12, alpha: 1)
        view.delegate = c
        MG3DView.configure(view, playing: playing, animates: scene.animates)
        let ambient = SCNNode(); ambient.light = SCNLight(); ambient.light!.type = .ambient; ambient.light!.intensity = 350
        s.rootNode.addChildNode(ambient)
        let key = SCNNode(); key.light = SCNLight(); key.light!.type = .directional; key.light!.intensity = 900
        key.eulerAngles = SCNVector3(-0.9, 0.5, 0); s.rootNode.addChildNode(key)
        let camera = SCNNode(); camera.camera = SCNCamera(); camera.camera!.fieldOfView = 40
        camera.name = "camera"; s.rootNode.addChildNode(camera)
        view.pointOfView = camera
        update(view, c)
        return view
    }

    func update(_ view: SCNView, _ c: Coordinator) {
        MG3DView.configure(view, playing: playing, animates: scene.animates)
        c.lock.lock(); c.scene = scene; c.items = items; c.playing = playing; c.lock.unlock()
        let signature = scene.source.canonicalString + "|" + items.map(\.id).joined(separator: ",")
        guard signature != c.builtSignature else { return }
        c.builtSignature = signature
        c.root.childNodes.forEach { $0.removeFromParentNode() }
        c.nodes = MG3DBuilder.build(items, scene: scene, into: c.root)
        if let camera = view.scene?.rootNode.childNode(withName: "camera", recursively: false) {
            let cam = scene.camera ?? MGCamera()
            let distance = Float(max(scene.width, scene.height) * 1.25 / cam.zoom)
            let yaw = Float(cam.yaw * .pi / 180), pitch = Float(cam.pitch * .pi / 180)
            camera.position = SCNVector3(distance * cos(pitch) * sin(yaw), distance * sin(pitch), distance * cos(pitch) * cos(yaw))
            camera.look(at: SCNVector3(0, 0, 0))
        }
    }
}

#if canImport(UIKit)
extension MG3DView: UIViewRepresentable {
    func makeUIView(context: Context) -> SCNView { makeView(context.coordinator) }
    func updateUIView(_ view: SCNView, context: Context) { update(view, context.coordinator) }
}
#else
extension MG3DView: NSViewRepresentable {
    func makeNSView(context: Context) -> SCNView { makeView(context.coordinator) }
    func updateNSView(_ view: SCNView, context: Context) { update(view, context.coordinator) }
}
#endif

enum MG3DBuilder {
    static func color(_ role: MGColorRole) -> MGPlatformColor {
        let c = MGTheme.board.color(role)
        #if canImport(UIKit)
        return UIColor(c)
        #else
        return NSColor(c)
        #endif
    }
    static func material(_ role: MGColorRole, glow: Double = 0.25) -> SCNMaterial {
        let m = SCNMaterial(); let c = color(role)
        m.diffuse.contents = c; m.emission.contents = c.withAlphaComponent(CGFloat(glow))
        m.lightingModel = .physicallyBased; m.roughness.contents = 0.45; m.metalness.contents = 0.1
        return m
    }
    /// World → SceneKit, centred on the world box.
    static func v(_ p: MGPoint, _ s: MGScene) -> SCNVector3 { SCNVector3(Float(p.x - s.width / 2), Float(p.y - s.height / 2), Float(p.z)) }

    static func build(_ items: [MGItem], scene: MGScene, into root: SCNNode) -> [String: SCNNode] {
        var nodes: [String: SCNNode] = [:]
        let span = max(scene.width, scene.height)
        for item in items {
            let node = SCNNode(); node.name = item.id
            switch item.kind {
            case .body:
                let size = CGFloat(item.n("size", 1))
                node.geometry = item.has("ball") ? SCNSphere(radius: size / 2) : SCNBox(width: size, height: size, length: size, chamferRadius: size * 0.1)
                node.geometry?.materials = [material(item.color)]
                node.simdEulerAngles.z = Float(item.n("angle") * .pi / 180)
                if let label = item.label { node.addChildNode(text(label, at: SCNVector3(0, Float(size) * 0.8, 0), role: .white)) }
            case .incline:
                let b = item.n("base"), h = b * tan(item.n("angle") * .pi / 180)
                let path = MGBezier()
                path.move(to: .zero)
                #if canImport(UIKit)
                path.addLine(to: CGPoint(x: b, y: 0)); path.addLine(to: CGPoint(x: b, y: h))
                #else
                path.line(to: CGPoint(x: b, y: 0)); path.line(to: CGPoint(x: b, y: h))
                #endif
                path.close()
                let shape = SCNShape(path: path, extrusionDepth: CGFloat(min(4, span * 0.3)))
                shape.materials = [material(item.color, glow: 0.05)]
                node.geometry = shape
            case .line, .path:
                for (k, pair) in zip(item.pts, item.pts.dropFirst()).enumerated() {
                    let seg = segment(radius: item.kind == .line ? 0.03 : 0.04, role: item.color)
                    seg.name = "\(item.id)#\(k)"; place(seg, from: v(pair.0, scene), to: v(pair.1, scene)); node.addChildNode(seg)
                }
                root.addChildNode(node); nodes[item.id] = node; continue
            case .vector:
                for part in arrow(role: item.color).childNodes { node.addChildNode(part) }
                if let label = item.label { let t = text(label, at: SCNVector3(0, 1.15, 0), role: item.color); t.name = "label"; node.addChildNode(t) }
            case .axes:
                let o = item.pts.first ?? .zero
                for (dir, len, name) in [(MGPoint(1, 0, 0), item.n("w"), "x"), (MGPoint(0, 1, 0), item.n("h"), "y"), (MGPoint(0, 0, 1), (item.n("w") + item.n("h")) / 2, "z")] {
                    let a = arrow(role: .muted)
                    let t = text(name, at: SCNVector3(0, 0, 0), role: .muted); t.name = "label"; a.addChildNode(t)
                    orient(a, from: v(o, scene), dir: dir, length: len); root.addChildNode(a)
                }
                continue
            case .orbit:
                let torus = SCNTorus(ringRadius: CGFloat(item.n("r")), pipeRadius: 0.025)
                torus.materials = [material(item.color, glow: 0.6)]
                node.geometry = torus; node.eulerAngles.x = .pi / 2
            case .text:
                node.addChildNode(text(item.text ?? "", at: SCNVector3(0, 0, 0), role: item.color, size: item.has("title") ? 0.5 : 0.36))
            case .highlight:
                guard let target = items.first(where: { $0.id == item.ref }) else { continue }
                let r = CGFloat(max(0.4, target.n("size", 1) * 0.85))
                let halo = SCNSphere(radius: r); let m = material(item.color, glow: 0.9); m.transparency = 0.22; m.isDoubleSided = true
                halo.materials = [m]; node.geometry = halo
                // Static halo: no endless pulse (it would need continuous rendering and ignores Reduce Motion).
            default: continue
            }
            root.addChildNode(node); nodes[item.id] = node
        }
        update(MGTimeline.frame(scene, items: items, time: 0), scene: scene, nodes: nodes)
        return nodes
    }

    /// Per-frame transforms only; geometry is built once per scene/step.
    static func update(_ frame: [MGItem], scene: MGScene, nodes: [String: SCNNode]) {
        let byID = Dictionary(frame.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for item in frame {
            guard let node = nodes[item.id] else { continue }
            switch item.kind {
            case .body, .incline, .text, .orbit: if let p = item.pts.first { node.position = v(p, scene) }
            case .highlight: if let t = item.ref.flatMap({ byID[$0] }), let p = t.pts.first { node.position = v(p, scene) }
            case .vector:
                guard let from = item.pts.first else { continue }
                let dir = item.dir ?? MGPoint.polar(item.n("angle"))
                orient(node, from: v(from, scene), dir: dir, length: item.n("len"))
            case .line, .path:
                for (k, pair) in zip(item.pts, item.pts.dropFirst()).enumerated() {
                    if let seg = node.childNode(withName: "\(item.id)#\(k)", recursively: false) { place(seg, from: v(pair.0, scene), to: v(pair.1, scene)) }
                }
            default: break
            }
        }
    }

    /// Arrow along local +y: a shaft stretched to length and a fixed-size head (and label) at the tip.
    /// The parent is only rotated, never scaled, so billboard labels stay undistorted.
    static func arrow(role: MGColorRole) -> SCNNode {
        let n = SCNNode()
        let shaft = SCNCylinder(radius: 0.035, height: 1); shaft.materials = [material(role, glow: 0.7)]
        let s = SCNNode(geometry: shaft); s.name = "shaft"; n.addChildNode(s)
        let cone = SCNCone(topRadius: 0, bottomRadius: 0.1, height: 0.2); cone.materials = [material(role, glow: 0.7)]
        let c = SCNNode(geometry: cone); c.name = "head"; n.addChildNode(c)
        return n
    }
    static func orient(_ node: SCNNode, from: SCNVector3, dir: MGPoint, length: Double) {
        node.position = from
        let d = simd_normalize(simd_float3(Float(dir.x), Float(dir.y), Float(dir.z)))
        node.simdOrientation = simd_quatf(from: simd_float3(0, 1, 0), to: d)
        let len = Float(max(0.001, length)), head: Float = min(0.2, len)
        if let shaft = node.childNode(withName: "shaft", recursively: false) {
            let body = max(0.001, len - head)
            shaft.isHidden = len <= head; shaft.simdScale = simd_float3(1, body, 1); shaft.simdPosition = simd_float3(0, body / 2, 0)
        }
        if let h = node.childNode(withName: "head", recursively: false) { h.simdPosition = simd_float3(0, len - head / 2, 0); h.simdScale = simd_float3(1, head / 0.2, 1) }
        if let label = node.childNode(withName: "label", recursively: false) { label.simdPosition = simd_float3(0, len + 0.3, 0) }
    }
    static func segment(radius: CGFloat, role: MGColorRole) -> SCNNode {
        let c = SCNCylinder(radius: radius, height: 1); c.materials = [material(role, glow: 0.5)]; return SCNNode(geometry: c)
    }
    static func place(_ node: SCNNode, from a: SCNVector3, to b: SCNVector3) {
        let pa = simd_float3(Float(a.x), Float(a.y), Float(a.z)), pb = simd_float3(Float(b.x), Float(b.y), Float(b.z))
        let d = pb - pa, len = simd_length(d)
        guard len > 1e-4 else { node.isHidden = true; return }
        node.isHidden = false
        node.simdPosition = (pa + pb) / 2
        node.simdOrientation = simd_quatf(from: simd_float3(0, 1, 0), to: d / len)
        node.scale = SCNVector3(1, len, 1)
    }
    static func text(_ s: String, at p: SCNVector3, role: MGColorRole, size: CGFloat = 0.3) -> SCNNode {
        let t = SCNText(string: s, extrusionDepth: 0.01)
        t.font = .systemFont(ofSize: 1, weight: .semibold); t.flatness = 0.05
        t.materials = [material(role, glow: 0.9)]
        let n = SCNNode(geometry: t)
        let (minB, maxB) = n.boundingBox
        n.pivot = SCNMatrix4MakeTranslation((maxB.x - minB.x) / 2 + minB.x, 0, 0)
        n.scale = SCNVector3(Float(size), Float(size), Float(size))
        let holder = SCNNode(); holder.position = p; holder.addChildNode(n)
        let bb = SCNBillboardConstraint(); bb.freeAxes = .all; holder.constraints = [bb]
        return holder
    }
}

extension MG3DView: Equatable {
    static func == (a: MG3DView, b: MG3DView) -> Bool { a.scene == b.scene && a.items == b.items && a.playing == b.playing }
}
