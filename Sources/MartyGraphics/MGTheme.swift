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

    public func color(_ role: MGColorRole) -> Color { palette[role] ?? ink }

    static func hex(_ v: UInt32) -> Color {
        Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    public static let board = MGTheme(
        backgroundTop: hex(0x111A33), backgroundBottom: hex(0x0A0F1F), grid: Color.white.opacity(0.06),
        ink: hex(0xEEF2FF), subtleInk: hex(0x9AA4C7), labelFill: hex(0x0A0F1F).opacity(0.82),
        palette: [
            .force: hex(0xFF5D73), .normal: hex(0x4FC3F7), .friction: hex(0xFFB74D), .gravity: hex(0xB388FF),
            .tension: hex(0x64FFDA), .velocity: hex(0x69F0AE), .accel: hex(0xFFD54F), .energy: hex(0xFFD54F),
            .kinetic: hex(0x69F0AE), .potential: hex(0x4FC3F7), .accent: hex(0x7C9CFF), .muted: hex(0x8A94B8),
            .good: hex(0x69F0AE), .warn: hex(0xFFB74D), .blue: hex(0x5B8CFF), .red: hex(0xFF5D73), .green: hex(0x4ADE80),
            .orange: hex(0xFF9F43), .purple: hex(0xB388FF), .yellow: hex(0xFFE066), .teal: hex(0x2DD4BF), .white: hex(0xEEF2FF),
        ])
}

private struct MGThemeKey: EnvironmentKey { static let defaultValue = MGTheme.board }
extension EnvironmentValues {
    public var mgTheme: MGTheme { get { self[MGThemeKey.self] } set { self[MGThemeKey.self] = newValue } }
}
