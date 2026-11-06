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
    }
    public struct PartRange: Codable, Equatable, Sendable {
        public var id: String
        public var name: String
        public var firstTriangle: Int
        public var triangleCount: Int
        public var material: Int
    }
    public var format = "martygraphics.solid.snapshot/1"
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

    public var vertexCount: Int { positions.count / 3 }
    public var triangleCount: Int { indices.count / 3 }

    public static func make(_ assembly: MGAssembly, params: MGPoseParameters, camera: MGSolidCamera? = nil, aspect: Double = 16.0 / 10,
                            lighting: MGStudioLighting = .studio, stage: MGTransform = MGSolidStage.zUpToYUp) -> MGSolidSnapshot {
        let pose = assembly.pose(params)
        var pos: [Float] = [], nor: [Float] = [], idx: [UInt32] = [], triMat: [UInt16] = []
        var materials: [Material] = [], materialIndex: [String: Int] = [:], ranges: [PartRange] = []
        var bounds = MGBounds.empty
        for part in assembly.parts {
            let t = stage * (pose.world[part.id] ?? .identity)
            let rm = part.mesh.renderMesh(creaseAngle: part.creaseAngle)
            let mid: Int
            if let m = materialIndex[part.material.id] { mid = m } else {
                mid = materials.count; materialIndex[part.material.id] = mid
                materials.append(Material(id: part.material.id, parameters: part.material.parameters))
            }
            let base = UInt32(pos.count / 3)
            for p in rm.positions {
                let w = t.apply(p); bounds.include(w)
                pos += [Float(w.x), Float(w.y), Float(w.z)]
            }
            for n in rm.normals { let w = t.applyVector(n); nor += [Float(w.x), Float(w.y), Float(w.z)] }
            ranges.append(PartRange(id: part.id, name: part.name, firstTriangle: idx.count / 3, triangleCount: rm.indices.count / 3, material: mid))
            idx += rm.indices.map { $0 + base }
            triMat += [UInt16](repeating: UInt16(mid), count: rm.indices.count / 3)
        }
        let cam = camera ?? MGSolidCamera.framing(bounds, yaw: 32, pitch: 28, aspect: aspect)
        // An empty assembly exports zero bounds (JSON has no infinities).
        if bounds.isEmpty { bounds = MGBounds(min: .zero, max: .zero) }
        return MGSolidSnapshot(title: assembly.name, positions: pos, normals: nor, indices: idx, triangleMaterials: triMat,
                               materials: materials, parts: ranges, camera: cam, aspect: aspect, lighting: lighting,
                               groundY: bounds.min.y,
                               boundsMin: [bounds.min.x, bounds.min.y, bounds.min.z], boundsMax: [bounds.max.x, bounds.max.y, bounds.max.z])
    }

    /// JSON encoding (sorted keys) for interchange.
    public func jsonData() throws -> Data {
        let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]
        return try e.encode(self)
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
        guard format == "martygraphics.solid.snapshot/1" else { throw bad(.format, "unknown snapshot format") }
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
    }
}
