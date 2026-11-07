// SPDX-License-Identifier: Apache-2.0
import Foundation

/// Orbit camera around a target. World space is Y-up (see `MGSolidStage`).
public struct MGSolidCamera: Codable, Equatable, Sendable {
    public var target: [Double]
    /// Degrees about +Y, 0 looks from +Z toward the target.
    public var yaw: Double
    /// Degrees above the horizon.
    public var pitch: Double
    public var distance: Double
    /// Vertical field of view in degrees.
    public var fieldOfView: Double

    public init(target: MGVec3, yaw: Double, pitch: Double, distance: Double, fieldOfView: Double = 30) {
        self.target = [target.x, target.y, target.z]; self.yaw = yaw; self.pitch = pitch
        self.distance = distance; self.fieldOfView = fieldOfView
    }

    public var targetVector: MGVec3 { MGVec3(target[0], target[1], target[2]) }
    public var position: MGVec3 {
        let y = yaw * .pi / 180, p = pitch * .pi / 180
        return targetVector + MGVec3(cos(p) * sin(y), sin(p), cos(p) * cos(y)) * distance
    }
    public var up: MGVec3 { MGVec3(0, 1, 0) }

    /// Frames a bounding sphere so it fits both the vertical and horizontal field of view with `margin` (>1 adds room).
    /// Empty bounds frame a unit cube at the origin.
    public static func framing(_ bounds: MGBounds, yaw: Double, pitch: Double, aspect: Double, fieldOfView: Double = 30, margin: Double = 1.12) -> MGSolidCamera {
        let bounds = bounds.isEmpty ? MGBounds(min: MGVec3(-0.5, -0.5, -0.5), max: MGVec3(0.5, 0.5, 0.5)) : bounds
        let r = max(1e-6, bounds.radius)
        let v = fieldOfView * .pi / 180 / 2
        let h = atan(tan(v) * aspect)
        let d = r * margin / sin(min(v, h))
        return MGSolidCamera(target: bounds.center, yaw: yaw, pitch: pitch, distance: d, fieldOfView: fieldOfView)
    }

    /// Named presets for authored steps.
    public static let presets: [String: (yaw: Double, pitch: Double)] = [
        "hero": (32, 28), "front": (0, 8), "side": (90, 8), "top": (0, 88), "low": (24, 9), "back": (200, 24), "iso": (45, 35.264),
    ]
}

/// Studio light rig shared by the rasteriser and any other renderer (directions point from the light toward the scene).
public struct MGStudioLighting: Codable, Equatable, Sendable {
    public struct Light: Codable, Equatable, Sendable {
        public var name: String
        public var direction: [Double]
        public var color: [Double]
        /// Relative intensity (SceneKit lumens-equivalent for directional lights; renderers rescale).
        public var intensity: Double
        public var castsShadow: Bool
        /// Angular radius in degrees for soft shadows.
        public var softness: Double
    }
    public struct Environment: Codable, Equatable, Sendable {
        /// Procedural equirectangular studio: vertical gradient plus rectangular soft boxes.
        public var zenith: [Double]
        public var horizon: [Double]
        public var floor: [Double]
        /// Soft boxes: centre (azimuth degrees from +Z toward +X, elevation degrees), size (degrees), sRGB colour, strength.
        public var softboxes: [[Double]]
        public var intensity: Double
    }
    public var lights: [Light]
    public var environment: Environment
    public var background: [Double]
    /// Exposure bias in stops for the camera.
    public var exposure: Double

    public static let studio = MGStudioLighting(
        lights: [
            Light(name: "key", direction: MGStudioLighting.dir(azimuth: -40, elevation: 58), color: [1.0, 0.97, 0.93], intensity: 1450, castsShadow: true, softness: 4),
            Light(name: "fill", direction: MGStudioLighting.dir(azimuth: 75, elevation: 22), color: [0.80, 0.87, 1.0], intensity: 300, castsShadow: false, softness: 0),
            Light(name: "rim", direction: MGStudioLighting.dir(azimuth: 175, elevation: 30), color: [0.85, 0.92, 1.0], intensity: 1100, castsShadow: false, softness: 0),
        ],
        environment: Environment(zenith: [0.10, 0.12, 0.16], horizon: [0.20, 0.22, 0.27], floor: [0.05, 0.05, 0.06],
                                 softboxes: [[20, 55, 70, 34, 1, 0.98, 0.95, 5.0],     // large key box overhead-front
                                             [-95, 18, 26, 60, 0.85, 0.9, 1, 2.4],     // tall strip, left
                                             [100, 22, 22, 56, 1, 0.95, 0.9, 2.0],     // tall strip, right
                                             [180, 30, 80, 18, 0.8, 0.88, 1, 1.6]],    // rim band behind
                                 intensity: 1.35),
        background: [0.035, 0.045, 0.07], exposure: 0)

    /// Unit vector from the light toward the origin for a light placed at azimuth/elevation (degrees) in Y-up world.
    public static func dir(azimuth: Double, elevation: Double) -> [Double] {
        let a = azimuth * .pi / 180, e = elevation * .pi / 180
        let from = MGVec3(cos(e) * sin(a), sin(e), cos(e) * cos(a))
        return [-from.x, -from.y, -from.z]
    }
}

/// Maps kernel space (Z-up, millimetres) to the Y-up render world.
public enum MGSolidStage {
    /// Rotation of -90 degrees about X: kernel +Z becomes world +Y, kernel +Y becomes world -Z.
    public static let zUpToYUp = MGTransform.rotation(axis: .unitX, angle: -.pi / 2)
}

/// Renderer-independent export of one posed assembly: world-space triangles, per-triangle material ids, material
/// parameters, camera and light rig. Everything is plain numbers so other renderers (for example a path tracer) can
/// reproduce the same frame. World is Y-up, millimetres.
public struct MGSolidSnapshot: Codable, Equatable, Sendable {
    public struct Material: Codable, Equatable, Sendable {
        public var id: String
        public var parameters: MGMaterialParameters
        /// v2: the part's own light, nil for none.
        public var emission: Emission?
    }
    /// v2: emitted light as an sRGB colour and an intensity (0...4); renderers scale it into their own units.
    public struct Emission: Codable, Equatable, Sendable {
        public var color: [Double]
        public var intensity: Double
    }
    public struct PartRange: Codable, Equatable, Sendable {
        public var id: String
        public var name: String
        public var firstTriangle: Int
        public var triangleCount: Int
        public var material: Int
        /// v2: coverage 0.1...1 that renderers multiply with the material's opacity (always present in v2).
        public var opacity: Double?
        /// v2: the cap triangles of a section cut (`firstTriangle ≤ capFirstTriangle`, inside the part's range).
        public var capFirstTriangle: Int?
        public var capTriangleCount: Int?
    }
    /// v2: the section of the exported step, in the snapshot's world frame (Y up, mm). The plane is placed at the
    /// document's default input; a cut part carries its cut as it moves. Points with `normal · p > offset` are cut away.
    public struct Section: Codable, Equatable, Sendable {
        public var normal: [Double]
        public var offset: Double
        public var parts: [String]
    }
    /// v2: the annotations a step shows. Arrow and dimension triangles come after every part triangle (so part ranges
    /// never move), in authored order: arrows, then dimensions. Labels are anchor points and filled text; `placement`
    /// is the layout of every text for this snapshot's camera and aspect (`MGSolidAnnotations.frame`).
    public struct Annotations: Codable, Equatable, Sendable {
        public struct Arrow: Codable, Equatable, Sendable {
            public var id: String
            /// `force`, `flow`, `motion` or `pointer`; `style` is `line` or `turn`.
            public var meaning: String
            public var style: String
            /// World (Y-up, mm): a line arrow's tail and tip; a turn arrow's arc start and tip.
            public var from: [Double]
            public var to: [Double]
            /// Unit vector: a line arrow points along it; a turn arrow turns counter-clockwise about it.
            public var direction: [Double]
            /// `warn`, `accent`, `good` or `ink`.
            public var colorRole: String
            public var tier: String?
            public var text: String?
            public var firstTriangle: Int
            public var triangleCount: Int
            public func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(id, forKey: .id); try c.encode(meaning, forKey: .meaning); try c.encode(style, forKey: .style)
                try c.encode(from, forKey: .from); try c.encode(to, forKey: .to); try c.encode(direction, forKey: .direction)
                try c.encode(colorRole, forKey: .colorRole); try c.encode(tier, forKey: .tier); try c.encode(text, forKey: .text)
                try c.encode(firstTriangle, forKey: .firstTriangle); try c.encode(triangleCount, forKey: .triangleCount)
            }
        }
        public struct Dimension: Codable, Equatable, Sendable {
            public var id: String
            /// `distance` or `angle`.
            public var kind: String
            /// World (Y-up, mm): a, b (distance) or a, vertex, b (angle), posed.
            public var points: [[Double]]
            /// The fact `dim.<id>` (measured at the default input, or the range with `over`).
            public var value: Double
            public var unit: String
            public var text: String
            public var tier: String
            public var firstTriangle: Int
            public var triangleCount: Int
        }
        public struct Label: Codable, Equatable, Sendable {
            public var id: String
            public var anchor: [Double]
            public var text: String
            public var tier: String?
            /// The tier chip text, nil when the label makes no claim.
            public var chip: String?
            public func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(id, forKey: .id); try c.encode(anchor, forKey: .anchor); try c.encode(text, forKey: .text)
                try c.encode(tier, forKey: .tier); try c.encode(chip, forKey: .chip)
            }
        }
        public var arrows: [Arrow]
        public var dimensions: [Dimension]
        public var labels: [Label]
        public var placement: [MGAnnotationPlacement]
    }
    public static let formatV1 = "martygraphics.solid.snapshot/1", formatV2 = "martygraphics.solid.snapshot/2"
    public var format = MGSolidSnapshot.formatV1
    public var title: String
    /// x, y, z per vertex.
    public var positions: [Float]
    /// Unit normal per vertex.
    public var normals: [Float]
    /// Three vertex indices per triangle.
    public var indices: [UInt32]
    /// Index into `materials` for each triangle.
    public var triangleMaterials: [UInt16]
    public var materials: [Material]
    public var parts: [PartRange]
    public var camera: MGSolidCamera
    public var aspect: Double
    public var lighting: MGStudioLighting
    /// Ground plane height (world Y) where contact shadows land.
    public var groundY: Double
    public var boundsMin: [Double]
    public var boundsMax: [Double]
    /// v2: the step's section, nil when nothing is cut.
    public var section: Section?
    /// v2: the step's annotations, nil when it shows none.
    public var annotations: Annotations?
    /// v2: highlighted part ids, nil when none.
    public var highlight: [String]?

    public var vertexCount: Int { positions.count / 3 }
    public var triangleCount: Int { indices.count / 3 }

    /// Format v1: the plain posed assembly (byte-identical to earlier releases).
    public static func make(_ assembly: MGAssembly, params: MGPoseParameters, camera: MGSolidCamera? = nil, aspect: Double = 16.0 / 10,
                            lighting: MGStudioLighting = .studio, stage: MGTransform = MGSolidStage.zUpToYUp) -> MGSolidSnapshot {
        build(assembly, view: nil, params: params, camera: camera, aspect: aspect, lighting: lighting, stage: stage)
    }

    /// Format v2: one step of a compiled document (`step` 0-based; nil for the plain scene) with its section cuts and
    /// cap ranges, part opacity (ghosts included) and material emission.
    public static func make(_ document: MGSolidDocument, step: Int?, params: MGPoseParameters, camera: MGSolidCamera? = nil,
                            aspect: Double = 16.0 / 10, lighting: MGStudioLighting = .studio,
                            stage: MGTransform = MGSolidStage.zUpToYUp) -> MGSolidSnapshot {
        make(document, step: step, params: params, highlight: [], camera: camera, aspect: aspect, lighting: lighting, stage: stage)
    }

    /// Format v2 with highlighted parts (recorded in `highlight`; placements avoid covering them). The step's
    /// annotations are exported with their triangles and a placement for this camera and aspect; a step snapshot
    /// assumes a caption band shows (`step` non-nil). Annotation geometry does not change the bounds or the framing.
    public static func make(_ document: MGSolidDocument, step: Int?, params: MGPoseParameters, highlight: [String],
                            camera: MGSolidCamera? = nil, aspect: Double = 16.0 / 10, lighting: MGStudioLighting = .studio,
                            stage: MGTransform = MGSolidStage.zUpToYUp) -> MGSolidSnapshot {
        let view = document.view(step: step)
        var snap = build(document.assembly, view: view, params: params, camera: camera, aspect: aspect, lighting: lighting, stage: stage)
        if !view.annotations.isEmpty { addAnnotations(&snap, document, view: view, step: step, params: params, highlight: highlight, stage: stage) }
        let known = Set(document.assembly.parts.map(\.id))
        let lit = MGSolidParser.unique(highlight.filter { known.contains($0) })
        if !lit.isEmpty { snap.highlight = lit }
        return snap
    }

    static func addAnnotations(_ snap: inout MGSolidSnapshot, _ doc: MGSolidDocument, view: MGSolidView, step: Int?,
                               params: MGPoseParameters, highlight: [String], stage: MGTransform) {
        let a = doc.annotations
        let pose = doc.assembly.pose(params)
        let visible = Set(view.annotations)
        func xyz(_ p: MGVec3) -> [Double] { let q = stage.apply(p); return [q.x, q.y, q.z] }
        func unit(_ v: MGVec3) -> [Double] { let q = stage.applyVector(v).normalized; return [q.x, q.y, q.z] }
        var materialIndex: [String: Int] = [:]
        for (i, m) in snap.materials.enumerated() { materialIndex[m.id] = i }
        func append(_ prims: [MGAnnotationPrimitive], role: String) -> (Int, Int) {
            let key = "annotation." + role
            let mid: Int
            if let m = materialIndex[key] { mid = m } else {
                mid = snap.materials.count; materialIndex[key] = mid
                let color = MGSolidAnnotations.srgb(role)
                snap.materials.append(Material(id: key, parameters: MGMaterialParameters(baseColor: color, metallic: 0, roughness: 0.45),
                                               emission: Emission(color: color, intensity: 0.6)))
            }
            let first = snap.indices.count / 3
            for p in prims {
                let rm = p.renderMesh
                let base = UInt32(snap.positions.count / 3)
                for v in rm.positions { let w = stage.apply(v); snap.positions += [Float(w.x), Float(w.y), Float(w.z)] }
                for n in rm.normals { let w = stage.applyVector(n); snap.normals += [Float(w.x), Float(w.y), Float(w.z)] }
                snap.indices += rm.indices.map { $0 + base }
                snap.triangleMaterials += [UInt16](repeating: UInt16(mid), count: rm.indices.count / 3)
            }
            return (first, snap.indices.count / 3 - first)
        }
        var out = Annotations(arrows: [], dimensions: [], labels: [], placement: [])
        for r in a.arrows where visible.contains(r.id) {
            let prims = MGSolidAnnotations.primitives(doc, r.id, params: params, sense: view.motionSense)
            let (first, count) = append(prims, role: r.colorRole)
            let from = prims[0].start
            var to = prims[1].end, dir = to - from
            if r.style == .turn, let on = r.on, case .revolute(let axis)? = doc.assembly.part(on)?.joint {
                to = prims[MGSolidAnnotations.arcChords].end
                dir = MGSolidAnnotations.jointFrame(doc, on, pose).applyVector(axis) * (r.turnSign ?? 1) * view.motionSense
            } else if dir.length < 1e-12 { dir = (r.direction ?? .unitZ) * view.motionSense }
            out.arrows.append(Annotations.Arrow(id: r.id, meaning: r.meaning.rawValue, style: r.style.rawValue, from: xyz(from), to: xyz(to),
                                                direction: unit(dir), colorRole: r.colorRole, tier: r.tier?.name, text: r.text,
                                                firstTriangle: first, triangleCount: count))
        }
        for d in a.dimensions where visible.contains(d.id) {
            let (first, count) = append(MGSolidAnnotations.primitives(doc, d.id, params: params, sense: view.motionSense), role: MGSolidAnnotations.dimensionRole)
            out.dimensions.append(Annotations.Dimension(id: d.id, kind: d.kind.rawValue,
                                                        points: [d.a, d.vertex, d.b].compactMap { $0 }.map { xyz($0.world(pose)) },
                                                        value: d.value, unit: d.unit, text: d.text, tier: d.tier.name,
                                                        firstTriangle: first, triangleCount: count))
        }
        for l in a.labels where visible.contains(l.id) {
            out.labels.append(Annotations.Label(id: l.id, anchor: xyz(l.at.world(pose)), text: l.text, tier: l.tier?.name,
                                                chip: l.tier?.badge(.annotation)))
        }
        out.placement = MGSolidAnnotations.frame(document: doc, view: view, params: params, camera: snap.camera, aspect: snap.aspect,
                                                 highlight: highlight, caption: step != nil, stage: stage).placement
        snap.annotations = out
    }

    static func build(_ assembly: MGAssembly, view: MGSolidView?, params: MGPoseParameters, camera: MGSolidCamera?, aspect: Double,
                      lighting: MGStudioLighting, stage: MGTransform) -> MGSolidSnapshot {
        let pose = assembly.pose(params)
        var pos: [Float] = [], nor: [Float] = [], idx: [UInt32] = [], triMat: [UInt16] = []
        var materials: [Material] = [], materialIndex: [String: Int] = [:], ranges: [PartRange] = []
        var bounds = MGBounds.empty
        for part in assembly.parts {
            let t = stage * (pose.world[part.id] ?? .identity)
            let pv = view?.part(part.id)
            let rm = pv?.cut?.renderMesh(creaseAngle: part.creaseAngle) ?? part.mesh.renderMesh(creaseAngle: part.creaseAngle)
            let mid: Int
            let emission = pv?.emission.flatMap { $0.intensity > 0 ? $0 : nil }
            let key = part.material.id + (emission.map { "+" + $0.id } ?? "")
            if let m = materialIndex[key] { mid = m } else {
                mid = materials.count; materialIndex[key] = mid
                materials.append(Material(id: key, parameters: part.material.parameters,
                                          emission: emission.map { Emission(color: $0.color, intensity: $0.intensity) }))
            }
            let base = UInt32(pos.count / 3)
            for p in rm.positions {
                let w = t.apply(p); bounds.include(w)
                pos += [Float(w.x), Float(w.y), Float(w.z)]
            }
            for n in rm.normals { let w = t.applyVector(n); nor += [Float(w.x), Float(w.y), Float(w.z)] }
            var range = PartRange(id: part.id, name: part.name, firstTriangle: idx.count / 3, triangleCount: rm.indices.count / 3, material: mid)
            if let pv {
                range.opacity = pv.opacity
                if let cut = pv.cut { range.capFirstTriangle = range.firstTriangle + cut.capFirstTriangle; range.capTriangleCount = cut.capTriangleCount }
            }
            ranges.append(range)
            idx += rm.indices.map { $0 + base }
            triMat += [UInt16](repeating: UInt16(mid), count: rm.indices.count / 3)
        }
        let cam = camera ?? MGSolidCamera.framing(bounds, yaw: 32, pitch: 28, aspect: aspect)
        // An empty assembly exports zero bounds (JSON has no infinities).
        if bounds.isEmpty { bounds = MGBounds(min: .zero, max: .zero) }
        var snap = MGSolidSnapshot(title: assembly.name, positions: pos, normals: nor, indices: idx, triangleMaterials: triMat,
                                   materials: materials, parts: ranges, camera: cam, aspect: aspect, lighting: lighting,
                                   groundY: bounds.min.y,
                                   boundsMin: [bounds.min.x, bounds.min.y, bounds.min.z], boundsMax: [bounds.max.x, bounds.max.y, bounds.max.z])
        if let view {
            snap.format = formatV2
            if let sec = view.section {
                let n = stage.applyVector(sec.plane.normal)
                // Stage transforms may translate: offset is measured along the normal from the stage origin.
                snap.section = Section(normal: [n.x, n.y, n.z], offset: sec.plane.offset + n.dot(stage.translation), parts: sec.parts)
            }
        }
        return snap
    }

    /// JSON encoding (sorted keys) for interchange.
    public func jsonData() throws -> Data {
        let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]
        return try e.encode(self)
    }

    /// Largest snapshot text `decode(data:)` reads: 256 MiB. A document at the mesh budget (1.5 million triangles)
    /// exports about 150 MB.
    public static let maxBytes = 256 * 1024 * 1024
    /// Longest number literal `decode(data:)` reads; the encoder writes at most about 25 characters.
    public static let maxNumberLength = 64

    /// Decodes snapshot JSON text. Guards run before the system decoder sees the bytes, so hostile text cannot exhaust
    /// a small thread stack (iOS secondary threads have 512 KiB): `solidSnapshot.bytes` (over `maxBytes`),
    /// `solidSnapshot.json` (not valid UTF-8, or a raw NUL byte), `solidSnapshot.depth` (nesting deeper than
    /// `MGLimits.depth`, 64), `solidSnapshot.number` (a number literal longer than `maxNumberLength` or one that is not
    /// finite as a `Double`, such as `1e999`). Then `JSONDecoder` and the validating initialisers run; anything they
    /// refuse is `solidSnapshot.invalid`. Use this, not `JSONDecoder` directly, for text from outside the process.
    public static func decode(data: Data) throws -> MGSolidSnapshot {
        if let reason = guardRefusal(data) { throw MGSolidIssue(reason) }
        do { return try JSONDecoder().decode(MGSolidSnapshot.self, from: data) } catch { throw MGSolidIssue("solidSnapshot.invalid") }
    }

    /// The first guard `decode(data:)` refuses, or nil. One pass over the bytes after the UTF-8 check; no recursion.
    static func guardRefusal(_ data: Data) -> String? {
        guard data.count <= maxBytes else { return "solidSnapshot.bytes" }
        if let r = MGJSON.dataRefusal(data, json: "solidSnapshot.json", depth: "solidSnapshot.depth") { return r }
        var inString = false, escape = false
        var token: [UInt8] = []
        func numberRefusal() -> Bool {
            defer { token.removeAll(keepingCapacity: true) }
            guard !token.isEmpty else { return false }
            guard token.count <= maxNumberLength, let d = Double(String(decoding: token, as: UTF8.self)) else { return true }
            return !d.isFinite
        }
        for b in data {
            if inString {
                if escape { escape = false } else if b == UInt8(ascii: "\\") { escape = true } else if b == UInt8(ascii: "\"") { inString = false }
                continue
            }
            let digit = b >= UInt8(ascii: "0") && b <= UInt8(ascii: "9")
            if token.isEmpty {
                // A number starts with a digit or `-`; the letters of `true`, `false` and `null` never start one.
                if digit || b == UInt8(ascii: "-") { token.append(b) } else if b == UInt8(ascii: "\"") { inString = true }
                continue
            }
            if digit || b == UInt8(ascii: "-") || b == UInt8(ascii: "+") || b == UInt8(ascii: ".") || b == UInt8(ascii: "e") || b == UInt8(ascii: "E") {
                guard token.count < maxNumberLength else { return "solidSnapshot.number" }
                token.append(b)
                continue
            }
            if numberRefusal() { return "solidSnapshot.number" }
            if b == UInt8(ascii: "\"") { inString = true }
        }
        return numberRefusal() ? "solidSnapshot.number" : nil
    }
}

// MARK: Validating decoders

/// Decoding checks the fixed-size slots that renderers index directly, so malformed input fails to decode
/// instead of trapping later.
extension KeyedDecodingContainer {
    func numbers(_ key: Key, count: Int) throws -> [Double] {
        let v = try decode([Double].self, forKey: key)
        guard v.count == count, v.allSatisfy(\.isFinite) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "expected \(count) finite numbers")
        }
        return v
    }
    func finite(_ key: Key) throws -> Double {
        let v = try decode(Double.self, forKey: key)
        guard v.isFinite else { throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "expected a finite number") }
        return v
    }
}

extension MGSolidCamera {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        target = try c.numbers(.target, count: 3)
        yaw = try c.finite(.yaw); pitch = try c.finite(.pitch); distance = try c.finite(.distance)
        fieldOfView = try c.finite(.fieldOfView)
        guard distance > 0, fieldOfView > 0, fieldOfView < 180 else {
            throw DecodingError.dataCorruptedError(forKey: .distance, in: c, debugDescription: "camera distance and field of view must be positive")
        }
    }
}

extension MGStudioLighting.Light {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        direction = try c.numbers(.direction, count: 3)
        color = try c.numbers(.color, count: 3)
        intensity = try c.finite(.intensity)
        castsShadow = try c.decode(Bool.self, forKey: .castsShadow)
        softness = try c.finite(.softness)
    }
}

extension MGStudioLighting.Environment {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        zenith = try c.numbers(.zenith, count: 3)
        horizon = try c.numbers(.horizon, count: 3)
        floor = try c.numbers(.floor, count: 3)
        softboxes = try c.decode([[Double]].self, forKey: .softboxes)
        guard softboxes.allSatisfy({ $0.count == 8 && $0.allSatisfy(\.isFinite) }) else {
            throw DecodingError.dataCorruptedError(forKey: .softboxes, in: c, debugDescription: "each soft box has 8 finite numbers")
        }
        intensity = try c.finite(.intensity)
    }
}

extension MGStudioLighting {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lights = try c.decode([Light].self, forKey: .lights)
        environment = try c.decode(Environment.self, forKey: .environment)
        background = try c.numbers(.background, count: 3)
        exposure = try c.finite(.exposure)
    }
}

extension MGSolidSnapshot {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func bad(_ key: CodingKeys, _ why: String) -> DecodingError { .dataCorruptedError(forKey: key, in: c, debugDescription: why) }
        format = try c.decode(String.self, forKey: .format)
        guard format == MGSolidSnapshot.formatV1 || format == MGSolidSnapshot.formatV2 else { throw bad(.format, "unknown snapshot format") }
        title = try c.decode(String.self, forKey: .title)
        positions = try c.decode([Float].self, forKey: .positions)
        normals = try c.decode([Float].self, forKey: .normals)
        indices = try c.decode([UInt32].self, forKey: .indices)
        triangleMaterials = try c.decode([UInt16].self, forKey: .triangleMaterials)
        materials = try c.decode([Material].self, forKey: .materials)
        parts = try c.decode([PartRange].self, forKey: .parts)
        camera = try c.decode(MGSolidCamera.self, forKey: .camera)
        aspect = try c.finite(.aspect)
        lighting = try c.decode(MGStudioLighting.self, forKey: .lighting)
        groundY = try c.finite(.groundY)
        boundsMin = try c.numbers(.boundsMin, count: 3)
        boundsMax = try c.numbers(.boundsMax, count: 3)
        guard positions.count % 3 == 0, positions.allSatisfy(\.isFinite) else { throw bad(.positions, "three finite numbers per vertex") }
        guard normals.count == positions.count, normals.allSatisfy(\.isFinite) else { throw bad(.normals, "one finite normal per vertex") }
        guard indices.count % 3 == 0, indices.allSatisfy({ Int($0) < positions.count / 3 }) else { throw bad(.indices, "three vertex indices per triangle") }
        guard triangleMaterials.count == indices.count / 3, triangleMaterials.allSatisfy({ Int($0) < materials.count }) else {
            throw bad(.triangleMaterials, "one material index per triangle")
        }
        guard parts.allSatisfy({ $0.firstTriangle >= 0 && $0.triangleCount >= 0 && $0.firstTriangle <= indices.count / 3 - $0.triangleCount
                                 && $0.material >= 0 && $0.material < materials.count }) else { throw bad(.parts, "part ranges must lie inside the triangles") }
        guard aspect > 0 else { throw bad(.aspect, "aspect must be positive") }
        section = try c.decodeIfPresent(Section.self, forKey: .section)
        annotations = try c.decodeIfPresent(Annotations.self, forKey: .annotations)
        highlight = try c.decodeIfPresent([String].self, forKey: .highlight)
        // v2 fields are legal only in v2; a v1 file keeps exactly its v1 meaning.
        let v2Fields = section != nil || annotations != nil || highlight != nil || materials.contains { $0.emission != nil }
            || parts.contains { $0.opacity != nil || $0.capFirstTriangle != nil || $0.capTriangleCount != nil }
        if format == MGSolidSnapshot.formatV1 {
            guard !v2Fields else { throw bad(.format, "snapshot/1 has no section, opacity, cap, emission, annotation or highlight fields") }
            return
        }
        guard parts.allSatisfy({ ($0.opacity.map { MGSolidView.opacityRange.contains($0) } ?? false) }) else {
            throw bad(.parts, "every v2 part has an opacity in 0.1...1")
        }
        for p in parts {
            switch (p.capFirstTriangle, p.capTriangleCount) {
            case (nil, nil): continue
            case (let f?, let n?):
                guard f >= p.firstTriangle, n >= 0, f <= p.firstTriangle + p.triangleCount - n else { throw bad(.parts, "cap ranges must lie inside their part") }
            default: throw bad(.parts, "a cap range needs its first triangle and its count")
            }
        }
        guard materials.allSatisfy({ m in m.emission.map { $0.color.count == 3 && $0.color.allSatisfy(\.isFinite) && MGEmission.intensityRange.contains($0.intensity) } ?? true }) else {
            throw bad(.materials, "emission needs three finite colour numbers and an intensity in 0...4")
        }
        if let s = section {
            guard s.normal.count == 3, s.normal.allSatisfy(\.isFinite), s.offset.isFinite,
                  (s.normal[0] * s.normal[0] + s.normal[1] * s.normal[1] + s.normal[2] * s.normal[2] - 1).magnitude < 1e-6,
                  s.parts.allSatisfy({ id in parts.contains { $0.id == id } }) else { throw bad(.section, "section needs a unit normal, a finite offset and known parts") }
        }
        if let h = highlight {
            guard h.allSatisfy({ id in parts.contains { $0.id == id } }) else { throw bad(.highlight, "highlight names known parts") }
        }
        if let a = annotations, let why = MGSolidSnapshot.annotationProblem(a, partsEnd: parts.map { $0.firstTriangle + $0.triangleCount }.max() ?? 0,
                                                                           triangles: indices.count / 3) {
            throw bad(.annotations, why)
        }
    }

    /// Why an annotations record is malformed, or nil: finite points, unit directions, known roles and tiers, triangle
    /// ranges after every part triangle, in order and inside the list, unique ids, placements of known ids.
    static func annotationProblem(_ a: Annotations, partsEnd: Int, triangles: Int) -> String? {
        func point(_ p: [Double], _ n: Int = 3) -> Bool { p.count == n && p.allSatisfy(\.isFinite) }
        let tiers: Set<String> = ["solved", "built", "described"]
        var cursor = partsEnd
        func range(_ first: Int, _ count: Int) -> Bool {
            guard first >= cursor, count >= 0, first <= triangles - count else { return false }
            cursor = first + count
            return true
        }
        var ids = Set<String>()
        for r in a.arrows {
            guard ids.insert(r.id).inserted, MGSolidArrow.Meaning(rawValue: r.meaning) != nil, MGSolidArrow.Style(rawValue: r.style) != nil,
                  point(r.from), point(r.to), point(r.direction), ["warn", "accent", "good", "ink"].contains(r.colorRole),
                  r.tier.map(tiers.contains) ?? true else { return "arrow fields" }
            let len = (r.direction[0] * r.direction[0] + r.direction[1] * r.direction[1] + r.direction[2] * r.direction[2]).squareRoot()
            guard abs(len - 1) < 1e-6 else { return "arrow direction must be a unit vector" }
            guard range(r.firstTriangle, r.triangleCount) else { return "arrow triangles must follow the parts, in order" }
        }
        for d in a.dimensions {
            guard ids.insert(d.id).inserted, MGSolidDimension.Kind(rawValue: d.kind) != nil, d.points.count == (d.kind == "angle" ? 3 : 2),
                  d.points.allSatisfy({ point($0) }), d.value.isFinite, tiers.contains(d.tier), d.unit == (d.kind == "angle" ? "°" : "mm") else {
                return "dimension fields"
            }
            guard range(d.firstTriangle, d.triangleCount) else { return "dimension triangles must follow the parts, in order" }
        }
        for l in a.labels {
            guard ids.insert(l.id).inserted, point(l.anchor), l.tier.map(tiers.contains) ?? true else { return "label fields" }
        }
        var placed = Set<String>()
        for p in a.placement {
            guard ids.contains(p.id), placed.insert(p.id).inserted, point(p.box, 4), p.box[2] >= 0, p.box[3] >= 0,
                  p.leader.map({ point($0, 2) }) ?? true, p.anchor.map({ point($0, 2) }) ?? true, (p.callout ?? 0) >= 0,
                  (p.candidate ?? 0) >= 0, (p.callout == nil) != (p.candidate == nil) else { return "placement fields" }
        }
        return nil
    }
}
