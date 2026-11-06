// SPDX-License-Identifier: Apache-2.0
import simd

/// A physically based surface description for the path tracer.
///
/// All colours are linear-light RGB. `baseColor` is the diffuse albedo for
/// `.diffuse` and `.plastic`, the normal-incidence reflectance (F0) for `.metal`,
/// and the transmission tint for `.glass`.
public struct MGRTMaterial: Sendable, Equatable {
    public enum Kind: UInt32, Sendable {
        case diffuse = 0, metal = 1, plastic = 2, glass = 3, emissive = 4
    }

    public var kind: Kind
    public var baseColor: SIMD3<Float>
    /// Perceptual roughness in 0...1 (GGX alpha = roughness squared).
    public var roughness: Float
    /// Anisotropy in 0...0.95, stretched along the mesh tangent (brushed metal).
    public var anisotropy: Float
    /// Index of refraction for `.plastic` specular and `.glass`.
    public var ior: Float
    /// Weight of the dielectric specular layer of `.plastic` (0...1).
    public var specular: Float
    /// Clear-coat weight (0...1), a smooth dielectric GGX layer over any opaque kind.
    public var coat: Float
    public var coatRoughness: Float
    /// Emitted radiance (linear RGB). Hit by BSDF sampling only; use area lights for sampled light.
    public var emission: SIMD3<Float>

    public init(kind: Kind, baseColor: SIMD3<Float>, roughness: Float = 0.5, anisotropy: Float = 0,
                ior: Float = 1.5, specular: Float = 1, coat: Float = 0, coatRoughness: Float = 0.05,
                emission: SIMD3<Float> = .zero) {
        self.kind = kind
        self.baseColor = baseColor
        self.roughness = roughness
        self.anisotropy = anisotropy
        self.ior = ior
        self.specular = specular
        self.coat = coat
        self.coatRoughness = coatRoughness
        self.emission = emission
    }

    public static func diffuse(_ color: SIMD3<Float>) -> MGRTMaterial {
        MGRTMaterial(kind: .diffuse, baseColor: color, roughness: 1)
    }

    public static func metal(_ f0: SIMD3<Float>, roughness: Float, anisotropy: Float = 0,
                             coat: Float = 0, coatRoughness: Float = 0.05) -> MGRTMaterial {
        MGRTMaterial(kind: .metal, baseColor: f0, roughness: roughness, anisotropy: anisotropy,
                     coat: coat, coatRoughness: coatRoughness)
    }

    public static func plastic(_ color: SIMD3<Float>, roughness: Float, specular: Float = 1,
                               coat: Float = 0, coatRoughness: Float = 0.05) -> MGRTMaterial {
        MGRTMaterial(kind: .plastic, baseColor: color, roughness: roughness, specular: specular,
                     coat: coat, coatRoughness: coatRoughness)
    }

    public static func glass(ior: Float = 1.5, roughness: Float = 0, tint: SIMD3<Float> = .one) -> MGRTMaterial {
        MGRTMaterial(kind: .glass, baseColor: tint, roughness: roughness, ior: ior)
    }

    public static func emissive(_ radiance: SIMD3<Float>) -> MGRTMaterial {
        MGRTMaterial(kind: .emissive, baseColor: .zero, emission: radiance)
    }

    /// Normal-incidence reflectance of common metals (linear sRGB, approximate published values).
    public static let steel = SIMD3<Float>(0.56, 0.57, 0.58)
    public static let aluminium = SIMD3<Float>(0.91, 0.92, 0.92)
    public static let brass = SIMD3<Float>(0.91, 0.78, 0.42)
    public static let copper = SIMD3<Float>(0.95, 0.64, 0.54)
    public static let chrome = SIMD3<Float>(0.55, 0.56, 0.55)

    /// GPU layout: five float4 rows (80 bytes), mirrored by `Material` in the shader.
    var packed: [SIMD4<Float>] {
        [SIMD4(baseColor, Float(kind.rawValue)),
         SIMD4(min(max(roughness, 0), 1), min(max(anisotropy, 0), 0.95), max(ior, 1.0001), min(max(coat, 0), 1)),
         SIMD4(min(max(coatRoughness, 0), 1), min(max(specular, 0), 1), 0, 0),
         SIMD4(emission, 0),
         SIMD4(0, 0, 0, 0)]
    }
}

/// An indexed triangle mesh in object space. Indices are local to the mesh.
public struct MGRTMesh: Sendable {
    public var positions: [SIMD3<Float>]
    public var normals: [SIMD3<Float>]
    /// Optional per-vertex tangents for anisotropic materials; empty means "derive from the normal".
    public var tangents: [SIMD3<Float>]
    public var indices: [UInt32]
    /// One material index per triangle.
    public var materialIDs: [UInt32]

    public init(positions: [SIMD3<Float>], normals: [SIMD3<Float>], tangents: [SIMD3<Float>] = [],
                indices: [UInt32], materialIDs: [UInt32]) {
        self.positions = positions
        self.normals = normals
        self.tangents = tangents
        self.indices = indices
        self.materialIDs = materialIDs
    }

    /// Convenience for a single-material mesh.
    public init(positions: [SIMD3<Float>], normals: [SIMD3<Float>], tangents: [SIMD3<Float>] = [],
                indices: [UInt32], material: UInt32) {
        self.init(positions: positions, normals: normals, tangents: tangents, indices: indices,
                  materialIDs: Array(repeating: material, count: indices.count / 3))
    }

    public var triangleCount: Int { indices.count / 3 }

    /// Signed volume by the divergence theorem; positive for a closed mesh wound outward.
    public var signedVolume: Float {
        var v: Float = 0
        for t in 0..<triangleCount {
            let a = positions[Int(indices[3 * t])], b = positions[Int(indices[3 * t + 1])], c = positions[Int(indices[3 * t + 2])]
            v += simd_dot(a, simd_cross(b, c)) / 6
        }
        return v
    }
}

/// A placed copy of a mesh. Animation updates only instance transforms.
public struct MGRTInstance: Sendable {
    public var mesh: Int
    public var transform: simd_float4x4
    public init(mesh: Int, transform: simd_float4x4 = matrix_identity_float4x4) {
        self.mesh = mesh
        self.transform = transform
    }
}

/// Thin-lens perspective camera. `apertureRadius` 0 is a pinhole.
public struct MGRTCamera: Sendable, Equatable {
    public var position: SIMD3<Float>
    public var target: SIMD3<Float>
    public var up: SIMD3<Float>
    public var verticalFOVDegrees: Float
    public var apertureRadius: Float
    /// Distance to the plane in focus; 0 or less means "distance to target".
    public var focusDistance: Float

    public init(position: SIMD3<Float>, target: SIMD3<Float>, up: SIMD3<Float> = SIMD3(0, 1, 0),
                verticalFOVDegrees: Float = 30, apertureRadius: Float = 0, focusDistance: Float = 0) {
        self.position = position
        self.target = target
        self.up = up
        self.verticalFOVDegrees = verticalFOVDegrees
        self.apertureRadius = apertureRadius
        self.focusDistance = focusDistance
    }

    /// Orthonormal basis: right, true up, forward.
    public var basis: (right: SIMD3<Float>, up: SIMD3<Float>, forward: SIMD3<Float>) {
        let w = simd_normalize(target - position)
        let u = simd_normalize(simd_cross(w, up))
        let v = simd_cross(u, w)
        return (u, v, w)
    }

    public var resolvedFocusDistance: Float {
        focusDistance > 0 ? focusDistance : simd_length(target - position)
    }

    /// Primary ray for a film point in normalised device coordinates (-1...1, +y up) and a
    /// lens sample in [0,1)^2. The Metal kernel implements the same mapping.
    public func ray(ndc: SIMD2<Float>, lens: SIMD2<Float>, aspect: Float) -> (origin: SIMD3<Float>, direction: SIMD3<Float>) {
        let (u, v, w) = basis
        let tanHalf = tan(verticalFOVDegrees * .pi / 360)
        let d = simd_normalize(w + ndc.x * tanHalf * aspect * u + ndc.y * tanHalf * v)
        guard apertureRadius > 0 else { return (position, d) }
        let focus = position + d * (resolvedFocusDistance / simd_dot(d, w))
        let disk = MGRTSampling.concentricDisk(lens) * apertureRadius
        let origin = position + disk.x * u + disk.y * v
        return (origin, simd_normalize(focus - origin))
    }
}

/// A one-sided rectangular emitter: points `corner + s*edgeU + t*edgeV`, emitting along cross(edgeU, edgeV).
public struct MGRTAreaLight: Sendable, Equatable {
    public var corner: SIMD3<Float>
    public var edgeU: SIMD3<Float>
    public var edgeV: SIMD3<Float>
    public var radiance: SIMD3<Float>
    /// When false, camera rays pass through the emitter (it still lights the scene and shows in
    /// reflections), like a studio light placed just outside the frame.
    public var visibleToCamera: Bool

    public init(corner: SIMD3<Float>, edgeU: SIMD3<Float>, edgeV: SIMD3<Float>, radiance: SIMD3<Float>,
                visibleToCamera: Bool = true) {
        self.corner = corner
        self.edgeU = edgeU
        self.edgeV = edgeV
        self.radiance = radiance
        self.visibleToCamera = visibleToCamera
    }

    /// A rectangle of `size` centred at `center`, facing `toward`.
    public static func softbox(center: SIMD3<Float>, toward: SIMD3<Float>, size: SIMD2<Float>,
                               radiance: SIMD3<Float>, visibleToCamera: Bool = true) -> MGRTAreaLight {
        let n = simd_normalize(toward - center)
        let helper: SIMD3<Float> = abs(n.y) > 0.95 ? SIMD3(1, 0, 0) : SIMD3(0, 1, 0)
        let a = simd_normalize(simd_cross(helper, n))
        let b = simd_cross(n, a)
        // cross(edgeU, edgeV) must point along n: cross(a, b) = n.
        let eu = a * size.x, ev = b * size.y
        return MGRTAreaLight(corner: center - eu / 2 - ev / 2, edgeU: eu, edgeV: ev, radiance: radiance,
                             visibleToCamera: visibleToCamera)
    }

    public var area: Float { simd_length(simd_cross(edgeU, edgeV)) }
    public var normal: SIMD3<Float> { simd_normalize(simd_cross(edgeU, edgeV)) }
    public var power: Float { MGRTSampling.luminance(radiance) * area * .pi }
}

/// Everything one frame needs.
public struct MGRTScene: Sendable {
    public var meshes: [MGRTMesh]
    public var instances: [MGRTInstance]
    public var materials: [MGRTMaterial]
    public var camera: MGRTCamera
    public var areaLights: [MGRTAreaLight]
    public var environment: MGRTEnvironment

    public init(meshes: [MGRTMesh], instances: [MGRTInstance], materials: [MGRTMaterial], camera: MGRTCamera,
                areaLights: [MGRTAreaLight] = [], environment: MGRTEnvironment) {
        self.meshes = meshes
        self.instances = instances
        self.materials = materials
        self.camera = camera
        self.areaLights = areaLights
        self.environment = environment
    }

    public enum ValidationError: Error, Equatable, CustomStringConvertible {
        case empty, mesh(Int, String), instance(Int), lights
        public var description: String {
            switch self {
            case .empty: return "Scene needs at least one mesh, instance and material"
            case let .mesh(i, why): return "Mesh \(i): \(why)"
            case let .instance(i): return "Instance \(i) references a missing mesh"
            case .lights: return "Area light has zero area or negative radiance"
            }
        }
    }

    /// Structural checks done before any GPU work.
    public func validate() throws {
        guard !meshes.isEmpty, !instances.isEmpty, !materials.isEmpty else { throw ValidationError.empty }
        for (i, m) in meshes.enumerated() {
            guard !m.indices.isEmpty, m.indices.count % 3 == 0 else { throw ValidationError.mesh(i, "index count") }
            guard m.normals.count == m.positions.count else { throw ValidationError.mesh(i, "normal count") }
            guard m.tangents.isEmpty || m.tangents.count == m.positions.count else { throw ValidationError.mesh(i, "tangent count") }
            guard m.materialIDs.count == m.triangleCount else { throw ValidationError.mesh(i, "material id count") }
            guard m.indices.allSatisfy({ Int($0) < m.positions.count }) else { throw ValidationError.mesh(i, "index range") }
            guard m.materialIDs.allSatisfy({ Int($0) < materials.count }) else { throw ValidationError.mesh(i, "material range") }
            guard m.positions.allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }) else {
                throw ValidationError.mesh(i, "non-finite position")
            }
        }
        for (i, inst) in instances.enumerated() where !(0..<meshes.count).contains(inst.mesh) {
            throw ValidationError.instance(i)
        }
        for l in areaLights where l.area <= 0 || simd_reduce_min(l.radiance) < 0 {
            throw ValidationError.lights
        }
    }
}

/// Render controls. Every sample is a function of (`seed`, pixel, sample index), so equal
/// settings and scene give equal pixels on the same device and toolchain.
public struct MGRTSettings: Sendable, Equatable {
    public var width: Int
    public var height: Int
    public var samplesPerPixel: Int
    public var maxBounces: Int
    public var seed: UInt32
    /// Exposure in stops applied before the filmic curve.
    public var exposure: Float
    /// Edge-aware à-trous filter guided by albedo, normal and depth (5 passes).
    public var denoise: Bool
    /// Luminance edge-stopping width of the filter in standard deviations (higher = smoother).
    public var denoiseStrength: Float
    /// Luminance clamp for indirect (bounce >= 1) contributions; 0 disables. Trades a small bias for no fireflies.
    public var clampIndirect: Float
    /// Probability of sampling the environment rather than an area light (when both exist).
    public var environmentSelectProbability: Float
    /// Tile edge in pixels per dispatch (keeps individual GPU submissions short).
    public var tileSize: Int
    /// Strength of a subtle filmic vignette (0 = none).
    public var vignette: Float
    /// Strength of a small physically motivated glare around hot highlights (0 = none).
    public var bloom: Float
    /// Also copy the linear HDR frame back to the CPU.
    public var returnLinear: Bool
    /// Diagnostic switches: bit 0 = BSDF sampling only, bit 1 = light sampling only,
    /// bit 2 = show first-hit shading normals, bit 3 = show geometric normals, bit 4 = no path regularisation.
    public var debugFlags: UInt32 = 0

    public init(width: Int, height: Int, samplesPerPixel: Int, maxBounces: Int = 8, seed: UInt32 = 1,
                exposure: Float = 0, denoise: Bool = true, clampIndirect: Float = 12,
                environmentSelectProbability: Float = 0.5, tileSize: Int = 512, vignette: Float = 0,
                bloom: Float = 0, returnLinear: Bool = false) {
        self.width = width
        self.height = height
        self.samplesPerPixel = samplesPerPixel
        self.maxBounces = maxBounces
        self.seed = seed
        self.exposure = exposure
        self.denoise = denoise
        self.denoiseStrength = 4
        self.clampIndirect = clampIndirect
        self.environmentSelectProbability = environmentSelectProbability
        self.tileSize = tileSize
        self.vignette = vignette
        self.bloom = bloom
        self.returnLinear = returnLinear
    }
}
