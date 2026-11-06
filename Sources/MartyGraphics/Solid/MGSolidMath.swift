// SPDX-License-Identifier: Apache-2.0
import Foundation

// Small, Foundation-only vector and rigid-transform types for the solid geometry kernel.
// They avoid `simd` so the kernel stays platform independent; renderers convert at the edge.

/// A 2D point or vector (profiles live in the XY plane; lathe profiles use x = radius, y = height).
public struct MGVec2: Hashable, Sendable, CustomStringConvertible {
    public var x: Double
    public var y: Double
    public init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
    public static let zero = MGVec2(0, 0)
    public static func + (a: MGVec2, b: MGVec2) -> MGVec2 { MGVec2(a.x + b.x, a.y + b.y) }
    public static func - (a: MGVec2, b: MGVec2) -> MGVec2 { MGVec2(a.x - b.x, a.y - b.y) }
    public static func * (a: MGVec2, s: Double) -> MGVec2 { MGVec2(a.x * s, a.y * s) }
    public static prefix func - (a: MGVec2) -> MGVec2 { MGVec2(-a.x, -a.y) }
    public var length: Double { (x * x + y * y).squareRoot() }
    public var normalized: MGVec2 { let l = length; return l > 0 ? MGVec2(x / l, y / l) : .zero }
    /// Counter-clockwise perpendicular (the left normal of a direction).
    public var perpendicular: MGVec2 { MGVec2(-y, x) }
    public var angle: Double { atan2(y, x) }
    public func dot(_ b: MGVec2) -> Double { x * b.x + y * b.y }
    /// z component of the 3D cross product.
    public func cross(_ b: MGVec2) -> Double { x * b.y - y * b.x }
    public static func polar(_ r: Double, _ angle: Double) -> MGVec2 { MGVec2(r * cos(angle), r * sin(angle)) }
    public func rotated(by angle: Double) -> MGVec2 {
        let c = cos(angle), s = sin(angle)
        return MGVec2(c * x - s * y, s * x + c * y)
    }
    public var description: String { "(\(x), \(y))" }
}

public struct MGVec3: Hashable, Sendable, CustomStringConvertible {
    public var x: Double
    public var y: Double
    public var z: Double
    public init(_ x: Double, _ y: Double, _ z: Double) { self.x = x; self.y = y; self.z = z }
    public static let zero = MGVec3(0, 0, 0)
    public static let unitX = MGVec3(1, 0, 0)
    public static let unitY = MGVec3(0, 1, 0)
    public static let unitZ = MGVec3(0, 0, 1)
    public static func + (a: MGVec3, b: MGVec3) -> MGVec3 { MGVec3(a.x + b.x, a.y + b.y, a.z + b.z) }
    public static func - (a: MGVec3, b: MGVec3) -> MGVec3 { MGVec3(a.x - b.x, a.y - b.y, a.z - b.z) }
    public static func * (a: MGVec3, s: Double) -> MGVec3 { MGVec3(a.x * s, a.y * s, a.z * s) }
    public static prefix func - (a: MGVec3) -> MGVec3 { MGVec3(-a.x, -a.y, -a.z) }
    public static func += (a: inout MGVec3, b: MGVec3) { a = a + b }
    public var length: Double { (x * x + y * y + z * z).squareRoot() }
    public var normalized: MGVec3 { let l = length; return l > 0 ? self * (1 / l) : .zero }
    public func dot(_ b: MGVec3) -> Double { x * b.x + y * b.y + z * b.z }
    public func cross(_ b: MGVec3) -> MGVec3 { MGVec3(y * b.z - z * b.y, z * b.x - x * b.z, x * b.y - y * b.x) }
    public func componentMin(_ b: MGVec3) -> MGVec3 { MGVec3(Swift.min(x, b.x), Swift.min(y, b.y), Swift.min(z, b.z)) }
    public func componentMax(_ b: MGVec3) -> MGVec3 { MGVec3(Swift.max(x, b.x), Swift.max(y, b.y), Swift.max(z, b.z)) }
    public var description: String { "(\(x), \(y), \(z))" }
}

/// Axis-aligned bounds.
public struct MGBounds: Equatable, Sendable {
    public var min: MGVec3
    public var max: MGVec3
    public init(min: MGVec3, max: MGVec3) { self.min = min; self.max = max }
    public static let empty = MGBounds(min: MGVec3(.infinity, .infinity, .infinity), max: MGVec3(-.infinity, -.infinity, -.infinity))
    public var isEmpty: Bool { min.x > max.x || min.y > max.y || min.z > max.z }
    public var center: MGVec3 { (min + max) * 0.5 }
    public var size: MGVec3 { max - min }
    /// Radius of the bounding sphere around `center`.
    public var radius: Double { size.length / 2 }
    public mutating func include(_ p: MGVec3) { min = min.componentMin(p); max = max.componentMax(p) }
    public func union(_ b: MGBounds) -> MGBounds {
        if isEmpty { return b }
        if b.isEmpty { return self }
        return MGBounds(min: min.componentMin(b.min), max: max.componentMax(b.max))
    }
    public var corners: [MGVec3] {
        [MGVec3(min.x, min.y, min.z), MGVec3(max.x, min.y, min.z), MGVec3(min.x, max.y, min.z), MGVec3(max.x, max.y, min.z),
         MGVec3(min.x, min.y, max.z), MGVec3(max.x, min.y, max.z), MGVec3(min.x, max.y, max.z), MGVec3(max.x, max.y, max.z)]
    }
}

/// A rigid transform: rotation (orthonormal columns) followed by translation.
public struct MGTransform: Equatable, Sendable {
    /// Rotation matrix columns (images of the unit X, Y and Z axes).
    public var c0: MGVec3
    public var c1: MGVec3
    public var c2: MGVec3
    public var translation: MGVec3

    public init(c0: MGVec3, c1: MGVec3, c2: MGVec3, translation: MGVec3) {
        self.c0 = c0; self.c1 = c1; self.c2 = c2; self.translation = translation
    }
    public static let identity = MGTransform(c0: .unitX, c1: .unitY, c2: .unitZ, translation: .zero)

    public static func translation(_ t: MGVec3) -> MGTransform {
        var m = MGTransform.identity; m.translation = t; return m
    }
    /// Right-handed rotation by `angle` radians about a unit `axis` through the origin (Rodrigues).
    public static func rotation(axis: MGVec3, angle: Double) -> MGTransform {
        let a = axis.normalized, c = cos(angle), s = sin(angle), t = 1 - c
        func col(_ e: MGVec3) -> MGVec3 { e * c + a.cross(e) * s + a * (a.dot(e) * t) }
        return MGTransform(c0: col(.unitX), c1: col(.unitY), c2: col(.unitZ), translation: .zero)
    }
    /// Rotation about an axis passing through `point`.
    public static func rotation(axis: MGVec3, angle: Double, about point: MGVec3) -> MGTransform {
        .translation(point) * .rotation(axis: axis, angle: angle) * .translation(-point)
    }

    public func applyVector(_ v: MGVec3) -> MGVec3 { c0 * v.x + c1 * v.y + c2 * v.z }
    public func apply(_ p: MGVec3) -> MGVec3 { applyVector(p) + translation }

    /// Composition: `(a * b).apply(p) == a.apply(b.apply(p))`.
    public static func * (a: MGTransform, b: MGTransform) -> MGTransform {
        MGTransform(c0: a.applyVector(b.c0), c1: a.applyVector(b.c1), c2: a.applyVector(b.c2), translation: a.apply(b.translation))
    }
    /// Inverse of a rigid transform (transpose rotation).
    public var inverse: MGTransform {
        let r0 = MGVec3(c0.x, c1.x, c2.x), r1 = MGVec3(c0.y, c1.y, c2.y), r2 = MGVec3(c0.z, c1.z, c2.z)
        let t = MGVec3(-c0.dot(translation), -c1.dot(translation), -c2.dot(translation))
        return MGTransform(c0: r0, c1: r1, c2: r2, translation: t)
    }
    /// Column-major 4x4 matrix values (16 numbers), for renderer adapters.
    public var columnMajor: [Double] {
        [c0.x, c0.y, c0.z, 0, c1.x, c1.y, c1.z, 0, c2.x, c2.y, c2.z, 0, translation.x, translation.y, translation.z, 1]
    }
}
