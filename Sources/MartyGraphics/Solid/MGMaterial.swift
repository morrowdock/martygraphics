// SPDX-License-Identifier: Apache-2.0
import Foundation

/// Renderer-independent physically based material parameters (metallic/roughness workflow).
///
/// Colours are sRGB-encoded components in 0...1. A renderer converts to its own working space.
public struct MGMaterialParameters: Codable, Equatable, Sendable {
    public var baseColor: [Double]
    public var metallic: Double
    public var roughness: Double
    /// Clear lacquer layer strength (0 = none) and its roughness.
    public var clearcoat: Double
    public var clearcoatRoughness: Double
    /// 0 = opaque, 1 = fully transmissive dielectric (glass).
    public var transmission: Double
    public var ior: Double
    /// Coverage for alpha-blended rasterisers; path tracers should prefer `transmission`.
    public var opacity: Double

    public init(baseColor: [Double], metallic: Double, roughness: Double, clearcoat: Double = 0, clearcoatRoughness: Double = 0.1,
                transmission: Double = 0, ior: Double = 1.5, opacity: Double = 1) {
        self.baseColor = baseColor; self.metallic = metallic; self.roughness = roughness
        self.clearcoat = clearcoat; self.clearcoatRoughness = clearcoatRoughness
        self.transmission = transmission; self.ior = ior; self.opacity = opacity
    }
}

/// Material presets for mechanical teaching models.
public enum MGMaterialPreset: Hashable, Sendable {
    case brushedSteel, polishedSteel, darkSteel, blackOxide, brass, bronze, aluminum
    /// Coloured anodised aluminium in an engine colour role.
    case anodized(MGColorRole)
    /// Matte injection-moulded plastic in an engine colour role.
    case plastic(MGColorRole)
    case rubber, glass

    /// Stable identifier (used by snapshots and renderers to share materials).
    public var id: String {
        switch self {
        case .brushedSteel: return "brushedSteel"
        case .polishedSteel: return "polishedSteel"
        case .darkSteel: return "darkSteel"
        case .blackOxide: return "blackOxide"
        case .brass: return "brass"
        case .bronze: return "bronze"
        case .aluminum: return "aluminum"
        case .anodized(let r): return "anodized." + r.rawValue
        case .plastic(let r): return "plastic." + r.rawValue
        case .rubber: return "rubber"
        case .glass: return "glass"
        }
    }

    public var parameters: MGMaterialParameters {
        switch self {
        case .brushedSteel: return MGMaterialParameters(baseColor: [0.80, 0.81, 0.83], metallic: 1, roughness: 0.32)
        case .polishedSteel: return MGMaterialParameters(baseColor: [0.86, 0.87, 0.89], metallic: 1, roughness: 0.14)
        case .darkSteel: return MGMaterialParameters(baseColor: [0.42, 0.44, 0.48], metallic: 1, roughness: 0.38)
        case .blackOxide: return MGMaterialParameters(baseColor: [0.10, 0.10, 0.11], metallic: 0.85, roughness: 0.42)
        case .brass: return MGMaterialParameters(baseColor: [0.93, 0.74, 0.40], metallic: 1, roughness: 0.26)
        case .bronze: return MGMaterialParameters(baseColor: [0.80, 0.52, 0.32], metallic: 1, roughness: 0.34)
        case .aluminum: return MGMaterialParameters(baseColor: [0.78, 0.80, 0.83], metallic: 1, roughness: 0.36)
        case .anodized(let r):
            let c = MGSolidPalette.srgb(r)
            return MGMaterialParameters(baseColor: c.map { $0 * 0.92 }, metallic: 0.75, roughness: 0.30, clearcoat: 0.25, clearcoatRoughness: 0.2)
        case .plastic(let r):
            return MGMaterialParameters(baseColor: MGSolidPalette.srgb(r), metallic: 0, roughness: 0.48, clearcoat: 0.15, clearcoatRoughness: 0.35)
        case .rubber: return MGMaterialParameters(baseColor: [0.06, 0.06, 0.07], metallic: 0, roughness: 0.88)
        case .glass: return MGMaterialParameters(baseColor: [0.92, 0.96, 1.0], metallic: 0, roughness: 0.03, transmission: 0.95, ior: 1.5, opacity: 0.22)
        }
    }
}

/// sRGB values of the engine colour roles. These mirror `MGTheme.board` (kept here as plain numbers so the solid
/// kernel stays Foundation-only).
public enum MGSolidPalette {
    static let hex: [MGColorRole: UInt32] = [
        .force: 0xFF5D73, .normal: 0x4FC3F7, .friction: 0xFFB74D, .gravity: 0xB388FF,
        .tension: 0x64FFDA, .velocity: 0x69F0AE, .accel: 0xFFD54F, .energy: 0xFFD54F,
        .kinetic: 0x69F0AE, .potential: 0x4FC3F7, .accent: 0x7C9CFF, .muted: 0x8A94B8,
        .good: 0x69F0AE, .warn: 0xFFB74D, .blue: 0x5B8CFF, .red: 0xFF5D73, .green: 0x4ADE80,
        .orange: 0xFF9F43, .purple: 0xB388FF, .yellow: 0xFFE066, .teal: 0x2DD4BF, .white: 0xEEF2FF,
    ]
    public static func srgb(_ role: MGColorRole) -> [Double] {
        let v = hex[role] ?? 0xEEF2FF
        return [Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255]
    }
}
