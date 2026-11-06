// SPDX-License-Identifier: Apache-2.0
import Foundation
import simd
import MartyGraphics
import MartyGraphicsPathTracer

/// Bridge from a solid-engine snapshot (`MGSolidSnapshot`, plain world-space arrays) to a path-tracer scene
/// (`MGRTScene`). Every part becomes one mesh and one instance, so a caller can animate parts by instance transform.
/// Units: the snapshot is in millimetres; `scale` converts to scene units (default metres).
public enum MGSolidRT {
    public struct Options: Sendable {
        /// Snapshot units to scene units (0.001: millimetres to metres).
        public var scale: Float = 0.001
        /// Studio directional lights become rectangular area lights; this scales their irradiance.
        public var lightScale: Float = 0.7
        /// Convert the studio's directional lights (otherwise only the environment lights the scene).
        public var includeStudioLights = true
        /// Environment map size.
        public var environmentSize = (width: 1024, height: 512)
        public init() {}
    }

    /// sRGB-encoded component to linear light.
    public static func linear(_ c: Double) -> Float {
        let x = min(max(c, 0), 1)
        return Float(x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4))
    }

    public static func linear(_ rgb: [Double]) -> SIMD3<Float> {
        SIMD3(linear(rgb.count > 0 ? rgb[0] : 0), linear(rgb.count > 1 ? rgb[1] : 0), linear(rgb.count > 2 ? rgb[2] : 0))
    }

    /// Maps renderer-independent PBR parameters (metallic/roughness, sRGB colour) to a path-tracer material.
    /// Transmissive presets become glass, metallic ones (metallic >= 0.5) GGX metals with the base colour as F0, and
    /// the rest dielectric plastic. Clear coat carries over. `brushedSteel` gets anisotropy.
    public static func material(id: String, _ p: MGMaterialParameters) -> MGRTMaterial {
        let base = linear(p.baseColor)
        let rough = Float(min(max(p.roughness, 0), 1))
        if p.transmission >= 0.5 {
            return .glass(ior: Float(max(p.ior, 1.0001)), roughness: rough, tint: base)
        }
        let coat = Float(min(max(p.clearcoat, 0), 1)), coatRough = Float(min(max(p.clearcoatRoughness, 0), 1))
        if p.metallic >= 0.5 {
            return .metal(base, roughness: rough, anisotropy: id == "brushedSteel" ? 0.6 : 0, coat: coat, coatRoughness: coatRough)
        }
        return .plastic(base, roughness: rough, specular: 1, coat: coat, coatRoughness: coatRough)
    }

    /// One mesh per part (world space, scaled), with per-triangle material ids into `snapshot.materials`.
    public static func meshes(_ s: MGSolidSnapshot, scale: Float = 0.001) -> [MGRTMesh] {
        s.parts.map { part in
            let firstIndex = part.firstTriangle * 3, end = firstIndex + part.triangleCount * 3
            let slice = s.indices[firstIndex..<end]
            guard let lo = slice.min(), let hi = slice.max() else {
                return MGRTMesh(positions: [], normals: [], indices: [], materialIDs: [])
            }
            let start = Int(lo), count = Int(hi) - start + 1
            var positions = [SIMD3<Float>](), normals = [SIMD3<Float>]()
            positions.reserveCapacity(count); normals.reserveCapacity(count)
            for v in start..<(start + count) {
                positions.append(SIMD3(s.positions[3 * v], s.positions[3 * v + 1], s.positions[3 * v + 2]) * scale)
                normals.append(SIMD3(s.normals[3 * v], s.normals[3 * v + 1], s.normals[3 * v + 2]))
            }
            let materialIDs = (part.firstTriangle..<(part.firstTriangle + part.triangleCount)).map { UInt32(s.triangleMaterials[$0]) }
            return MGRTMesh(positions: positions, normals: normals, indices: slice.map { $0 - lo }, materialIDs: materialIDs)
        }
    }

    public static func camera(_ c: MGSolidCamera, scale: Float = 0.001, aperture: Float = 0, focusDistance: Float = 0) -> MGRTCamera {
        let p = c.position, t = c.targetVector
        return MGRTCamera(position: SIMD3(Float(p.x), Float(p.y), Float(p.z)) * scale, target: SIMD3(Float(t.x), Float(t.y), Float(t.z)) * scale,
                          verticalFOVDegrees: Float(c.fieldOfView), apertureRadius: aperture, focusDistance: focusDistance)
    }

    /// Direction toward the light from azimuth (degrees from +Z toward +X) and elevation, as in `MGStudioLighting`.
    static func direction(azimuth: Double, elevation: Double) -> SIMD3<Float> {
        let a = azimuth * .pi / 180, e = elevation * .pi / 180
        return SIMD3(Float(cos(e) * sin(a)), Float(sin(e)), Float(cos(e) * cos(a)))
    }

    /// The studio's procedural environment (gradient plus soft boxes) as a path-tracer environment.
    public static func environment(_ l: MGStudioLighting, width: Int = 1024, height: Int = 512) -> MGRTEnvironment {
        let e = l.environment
        let boxes: [MGRTEnvironment.Softbox] = e.softboxes.compactMap { b in
            guard b.count >= 8 else { return nil }
            let half = SIMD2(Float(tan(min(b[2], 160) * .pi / 360)), Float(tan(min(b[3], 160) * .pi / 360)))
            return MGRTEnvironment.Softbox(direction: direction(azimuth: b[0], elevation: b[1]), halfSize: half,
                                           radiance: linear([b[4], b[5], b[6]]) * Float(b[7]), softness: 0.25)
        }
        return MGRTEnvironment.studio(width: width, height: height, softboxes: boxes, zenith: linear(e.zenith), horizon: linear(e.horizon),
                                      nadir: linear(e.floor), intensity: Float(e.intensity))
    }

    /// Directional studio lights as rectangular area lights at a distance of `distance` (scene units) from `center`,
    /// sized by each light's shadow softness, with radiance set so the irradiance at `center` is
    /// `intensity / 1000 * lightScale`.
    public static func areaLights(_ l: MGStudioLighting, center: SIMD3<Float>, distance: Float, lightScale: Float = 0.7) -> [MGRTAreaLight] {
        l.lights.map { light in
            let d = simd_normalize(SIMD3(Float(light.direction[0]), Float(light.direction[1]), Float(light.direction[2])))
            let size = max(0.2 * distance, 2 * distance * Float(tan(max(light.softness, 1) * .pi / 180)))
            let irradiance = Float(light.intensity) / 1000 * lightScale
            let radiance = linear(light.color) * (irradiance * distance * distance / (size * size))
            return .softbox(center: center - d * distance, toward: center, size: SIMD2(size, size), radiance: radiance, visibleToCamera: false)
        }
    }

    /// A complete scene: meshes, one identity instance per part, mapped materials, camera, studio lights and environment.
    public static func scene(_ s: MGSolidSnapshot, options: Options = Options()) -> MGRTScene {
        let meshes = meshes(s, scale: options.scale)
        let materials = s.materials.map { material(id: $0.id, $0.parameters) }
        let lo = SIMD3(Float(s.boundsMin[0]), Float(s.boundsMin[1]), Float(s.boundsMin[2])) * options.scale
        let hi = SIMD3(Float(s.boundsMax[0]), Float(s.boundsMax[1]), Float(s.boundsMax[2])) * options.scale
        let center = (lo + hi) / 2, radius = max(simd_length(hi - lo) / 2, 1e-3)
        let lights = options.includeStudioLights ? areaLights(s.lighting, center: center, distance: 4 * radius, lightScale: options.lightScale) : []
        return MGRTScene(meshes: meshes, instances: meshes.indices.map { MGRTInstance(mesh: $0) }, materials: materials,
                         camera: camera(s.camera, scale: options.scale), areaLights: lights,
                         environment: environment(s.lighting, width: options.environmentSize.width, height: options.environmentSize.height))
    }

    /// Instance transform that moves a part from its snapshot pose `from` to pose `to` (both kernel-space part
    /// transforms; the stage maps kernel space to the Y-up world), in scaled scene units.
    public static func motion(from: MGTransform, to: MGTransform, stage: MGTransform = MGSolidStage.zUpToYUp, scale: Float = 0.001) -> simd_float4x4 {
        let delta = stage * to * from.inverse * stage.inverse
        let v = delta.columnMajor.map(Float.init)
        return simd_float4x4(columns: (SIMD4(v[0], v[1], v[2], 0), SIMD4(v[4], v[5], v[6], 0), SIMD4(v[8], v[9], v[10], 0),
                                       SIMD4(v[12] * scale, v[13] * scale, v[14] * scale, 1)))
    }
}
