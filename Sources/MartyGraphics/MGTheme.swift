// SPDX-License-Identifier: Apache-2.0
import SwiftUI

/// Colours per semantic class on a dark "lab board". The board stays dark in light mode too, like a game screen,
/// so neon vectors keep their contrast everywhere. Swap `MGTheme.board` for a different look.
public struct MGTheme: Sendable {
    public var backgroundTop: Color
    public var backgroundBottom: Color
    public var grid: Color
    public var ink: Color
    public var subtleInk: Color
    public var labelFill: Color
    public var palette: [MGColorRole: Color]

    var v2: V2? = nil
    var textScale: CGFloat = 1

    public func color(_ role: MGColorRole) -> Color { palette[role] ?? ink }

    static func hex(_ v: UInt32) -> Color {
        Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    public static let classic = MGTheme(
        backgroundTop: hex(0x111A33), backgroundBottom: hex(0x0A0F1F), grid: Color.white.opacity(0.06),
        ink: hex(0xEEF2FF), subtleInk: hex(0x9AA4C7), labelFill: hex(0x0A0F1F).opacity(0.82),
        palette: [
            .force: hex(0xFF5D73), .normal: hex(0x4FC3F7), .friction: hex(0xFFB74D), .gravity: hex(0xB388FF),
            .tension: hex(0x64FFDA), .velocity: hex(0x69F0AE), .accel: hex(0xFFD54F), .energy: hex(0xFFD54F),
            .kinetic: hex(0x69F0AE), .potential: hex(0x4FC3F7), .accent: hex(0x7C9CFF), .muted: hex(0x8A94B8),
            .good: hex(0x69F0AE), .warn: hex(0xFFB74D), .blue: hex(0x5B8CFF), .red: hex(0xFF5D73), .green: hex(0x4ADE80),
            .orange: hex(0xFF9F43), .purple: hex(0xB388FF), .yellow: hex(0xFFE066), .teal: hex(0x2DD4BF), .white: hex(0xEEF2FF),
        ])
    /// The original board palette, retained for existing hosts.
    public static let board = classic

    struct V2: Sendable {
        let surface: Color
        let rule: Color
        let objectFill: Color
        let dim: Double
        static let regular: CGFloat = 4
        static let heavy: CGFloat = 8
        let highlight: Color
        let highlightRing: Color
        let highlightWash: Color
    }

    static func modern(stage: UInt32, surface: UInt32, surface2: UInt32, line: UInt32, rule: UInt32,
                       objectFill: UInt32, dim: Double, ink: UInt32,
                       secondary: UInt32, muted: UInt32, focus: UInt32, ring: UInt32, wash: UInt32,
                       hues: [UInt32]) -> MGTheme {
        let roles: [[MGColorRole]] = [
            [.accent, .normal, .potential, .blue], [.friction, .warn, .orange],
            [.tension, .teal], [.accel, .energy], [.velocity, .kinetic, .good, .green],
            [.gravity, .purple], [.force, .red],
        ]
        var palette: [MGColorRole: Color] = [.muted: hex(muted), .white: hex(ink), .yellow: hex(ink)]
        for (group, hue) in zip(roles, hues) {
            for role in group { palette[role] = hex(hue) }
        }
        let background = hex(stage)
        return MGTheme(backgroundTop: background, backgroundBottom: background, grid: hex(line),
                       ink: hex(ink), subtleInk: hex(secondary), labelFill: hex(surface2), palette: palette,
                       v2: V2(surface: hex(surface), rule: hex(rule), objectFill: hex(objectFill), dim: dim,
                              highlight: hex(focus), highlightRing: hex(ring), highlightWash: hex(wash)))
    }

    public static let studio = modern(
        stage: 0x0B0C10, surface: 0x15171C, surface2: 0x1E2128, line: 0x2B2F38, rule: 0x6B7180,
        objectFill: 0x24354E, dim: 0.34,
        ink: 0xF4EFEA, secondary: 0xB9B2AC, muted: 0x5B606C,
        focus: 0xFFBE2E, ring: 0xFFBE2E, wash: 0x483C20,
        hues: [0x5A9FFF, 0xEA8402, 0x12D6D6, 0xE25BB0, 0x5FE87C, 0x9665E7, 0xE24947])

    public static let paper = modern(
        stage: 0xF5F1EC, surface: 0xFFFDFA, surface2: 0xECE6DF, line: 0xDCD4CB, rule: 0x857B73,
        objectFill: 0xDEE9F6, dim: 0.38,
        ink: 0x1B1716, secondary: 0x544B47, muted: 0xA39A92,
        focus: 0xF5B400, ring: 0x1B1716, wash: 0xFBDE91,
        hues: [0x1170E0, 0xCC7200, 0x009494, 0x9A0A70, 0x006E29, 0x632BAB, 0xC2272D])

}

private struct MGThemeKey: EnvironmentKey { static let defaultValue = MGTheme.studio }
extension EnvironmentValues {
    public var mgTheme: MGTheme { get { self[MGThemeKey.self] } set { self[MGThemeKey.self] = newValue } }
}
