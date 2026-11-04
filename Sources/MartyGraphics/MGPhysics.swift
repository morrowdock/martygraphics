// SPDX-License-Identifier: Apache-2.0
import Foundation

/// Local physics for templates. The model only picks parameters; every number on screen comes from here.
/// Closed-form mechanics with standard gravity g = 9.81 m/s².
public enum MGPhysics {
    public static let g = 9.81

    public struct Incline: Equatable, Sendable {
        public let weight, normal, weightAlong, friction, applied, net, acceleration: Double
        /// Friction along the slope, positive pointing UP the slope.
        public let frictionSigned: Double
        public let isStatic: Bool
    }
    /// Starts at rest. Parallel axis positive up the slope; the applied pull is parallel to the surface, up the slope.
    /// Static friction takes only the value needed to hold the block, not its maximum.
    public static func incline(mass m: Double, angleDegrees: Double, muStatic: Double, muKinetic: Double, applied: Double) -> Incline? {
        guard [m, angleDegrees, muStatic, muKinetic, applied].allSatisfy(\.isFinite), m > 0, (0...89).contains(angleDegrees),
              muStatic >= 0, (0...muStatic).contains(muKinetic), applied >= 0 else { return nil }
        let a = angleDegrees * .pi / 180
        let normal = m * g * cos(a)
        let along = -m * g * sin(a)
        let driving = applied + along
        let friction: Double
        let isStatic = abs(driving) <= muStatic * normal + 1e-10
        if isStatic { friction = -driving } else { friction = -(driving > 0 ? 1.0 : -1.0) * muKinetic * normal }
        let net = driving + friction
        return .init(weight: m * g, normal: normal, weightAlong: abs(along), friction: abs(friction), applied: applied,
                     net: isStatic ? 0 : net, acceleration: isStatic ? 0 : net / m, frictionSigned: friction, isStatic: isStatic)
    }

    public struct Atwood: Equatable, Sendable { public let acceleration, tension, weight1, weight2: Double }
    /// Ideal rope and pulley. Positive acceleration means mass 2 moves down.
    public static func atwood(m1: Double, m2: Double) -> Atwood? {
        guard m1.isFinite, m2.isFinite, m1 > 0, m2 > 0 else { return nil }
        return .init(acceleration: (m2 - m1) * g / (m1 + m2), tension: 2 * m1 * m2 * g / (m1 + m2), weight1: m1 * g, weight2: m2 * g)
    }

    public struct Circular: Equatable, Sendable { public let centripetal, force, period, omega: Double }
    public static func circular(mass: Double, radius: Double, speed: Double) -> Circular? {
        guard [mass, radius, speed].allSatisfy({ $0.isFinite && $0 > 0 }) else { return nil }
        let ac = speed * speed / radius
        return .init(centripetal: ac, force: mass * ac, period: 2 * .pi * radius / speed, omega: speed / radius)
    }

    public struct Projectile: Equatable, Sendable {
        public let vx, vy0, flightTime, range, maxHeight, impactSpeed: Double
    }
    /// Launch from height h0 to level ground, no air resistance.
    public static func projectile(speed: Double, angleDegrees: Double, height: Double) -> Projectile? {
        guard [speed, angleDegrees, height].allSatisfy(\.isFinite), speed > 0, height >= 0 else { return nil }
        let th = angleDegrees * .pi / 180
        let vx = speed * cos(th), vy = speed * sin(th)
        let t = (vy + (vy * vy + 2 * g * height).squareRoot()) / g
        guard t.isFinite, t > 0 else { return nil }
        let vyEnd = vy - g * t
        return .init(vx: vx, vy0: vy, flightTime: t, range: vx * t, maxHeight: vy > 0 ? height + vy * vy / (2 * g) : height,
                     impactSpeed: (vx * vx + vyEnd * vyEnd).squareRoot())
    }

    public struct Spring: Equatable, Sendable { public let energy, maxSpeed, omega, period, maxForce: Double }
    /// Frictionless block released from rest at compression x: E = ½kx², v_max = x√(k/m).
    public static func spring(mass: Double, k: Double, compression x: Double) -> Spring? {
        guard [mass, k, x].allSatisfy({ $0.isFinite && $0 > 0 }) else { return nil }
        let w = (k / mass).squareRoot()
        return .init(energy: 0.5 * k * x * x, maxSpeed: x * w, omega: w, period: 2 * .pi / w, maxForce: k * x)
    }
    /// Kinetic / spring energy at phase ωt after release.
    public static func springSplit(energy: Double, phase: Double) -> (kinetic: Double, spring: Double) {
        let c = cos(phase); return (energy * (1 - c * c), energy * c * c)
    }

    public struct ThirdLaw: Equatable, Sendable { public let force, a1, a2: Double }
    /// Two bodies push apart on frictionless ice with equal and opposite forces of size F.
    public static func thirdLaw(m1: Double, m2: Double, force: Double) -> ThirdLaw? {
        guard [m1, m2, force].allSatisfy({ $0.isFinite && $0 > 0 }) else { return nil }
        return .init(force: force, a1: force / m1, a2: force / m2)
    }

    /// Plain label numbers: about 3 significant figures, no scientific notation, no trailing zeros.
    public static func format(_ v: Double, unit: String) -> String {
        guard v.isFinite else { return "—" }
        let a = abs(v)
        let digits = a >= 100 ? 0 : a >= 10 ? 1 : 2
        var s = String(format: "%.\(digits)f", v)
        if s.contains(".") { while s.hasSuffix("0") { s.removeLast() }; if s.hasSuffix(".") { s.removeLast() } }
        if s == "-0" { s = "0" }
        return unit.isEmpty ? s : unit == "°" ? s + unit : s + " " + unit
    }
}
