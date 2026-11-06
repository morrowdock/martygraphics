// SPDX-License-Identifier: Apache-2.0
import Foundation

/// How a part moves relative to its parent.
public enum MGJoint: Equatable, Sendable {
    case fixed
    /// Rotation by the joint value (radians) about `axis` through the part's placement origin.
    case revolute(axis: MGVec3)
    /// Translation by the joint value along `axis`.
    case prismatic(axis: MGVec3)
}

/// Where a joint value comes from. Drives form a dependency graph that must be acyclic.
public enum MGDrive: Equatable, Sendable {
    /// `q = offset + scale * input`.
    case input(scale: Double, offset: Double)
    /// `q = offset + ratio * q(source)`.
    case follow(source: String, ratio: Double, offset: Double)
    /// Gear mesh: `q = offset + ratio * (q(driver) - q(carrier))`. Use the signed tooth ratio: `-zDriver/zDriven`
    /// for an external mesh, `+zRing/zPlanet` for a planet driven by a ring. `carrier` is the frame both centres
    /// are fixed in (nil for a fixed frame); the driven part is expected to be a child of that carrier.
    case gear(driver: String, ratio: Double, carrier: String?, offset: Double)
    /// Slider displacement of an in-line slider-crank: `x = r cos(t) + sqrt(l^2 - r^2 sin^2(t)) - offset`, with
    /// `t = q(crank)`. The slider axis passes through the crank centre.
    case crankSlider(crank: String, crankRadius: Double, rodLength: Double, offset: Double)
    /// Angle of a connecting rod hinged on the slider and pointing back (local -X) at the crank pin.
    case crankRod(crank: String, crankRadius: Double, rodLength: Double)
}

public struct MGPart: Equatable, Sendable {
    public var id: String
    public var name: String
    public var mesh: MGMesh
    public var material: MGMaterialPreset
    /// Placement in the parent frame (the joint acts after it, in the part's own frame).
    public var placement: MGTransform
    public var parent: String?
    public var joint: MGJoint
    public var drive: MGDrive?
    /// Offset in the parent frame applied at full explode.
    public var explode: MGVec3
    /// Portion of the global explode parameter (0...1) over which this part moves; staggers the sequence.
    public var explodeWindow: ClosedRange<Double>
    /// Faces meeting at more than this angle (radians) render with a hard edge.
    public var creaseAngle: Double

    public init(id: String, name: String, mesh: MGMesh, material: MGMaterialPreset, placement: MGTransform = .identity,
                parent: String? = nil, joint: MGJoint = .fixed, drive: MGDrive? = nil, explode: MGVec3 = .zero,
                explodeWindow: ClosedRange<Double> = 0...1, creaseAngle: Double = 0.6) {
        self.id = id; self.name = name; self.mesh = mesh; self.material = material; self.placement = placement
        self.parent = parent; self.joint = joint; self.drive = drive; self.explode = explode
        self.explodeWindow = explodeWindow; self.creaseAngle = creaseAngle
    }
}

/// A gear mesh that `MGAssembly.gearResiduals` checks: `zA * relA + sign * zB * relB` stays constant, where
/// `rel` is the angle relative to `carrier` (sign +1 external, -1 internal). For internal meshes `a` is the ring.
public struct MGGearPair: Equatable, Sendable {
    public var a: String
    public var b: String
    public var teethA: Int
    public var teethB: Int
    public var isInternal: Bool
    public var carrier: String?
    public init(a: String, b: String, teethA: Int, teethB: Int, isInternal: Bool = false, carrier: String? = nil) {
        self.a = a; self.b = b; self.teethA = teethA; self.teethB = teethB; self.isInternal = isInternal; self.carrier = carrier
    }
}

public struct MGPoseParameters: Equatable, Sendable {
    /// Primary input (for example the input shaft angle in radians).
    public var input: Double
    /// 0 = assembled, 1 = fully exploded.
    public var explode: Double
    public init(input: Double = 0, explode: Double = 0) { self.input = input; self.explode = explode }
}

public struct MGPose: Equatable, Sendable {
    public var values: [String: Double]
    public var world: [String: MGTransform]
}

/// A kinematic assembly of rigid parts. Evaluation is pure: the same parameters always give the same pose.
public struct MGAssembly: Equatable, Sendable {
    public var name: String
    public var parts: [MGPart]
    public var gearPairs: [MGGearPair]

    public init(name: String, parts: [MGPart], gearPairs: [MGGearPair] = []) {
        self.name = name; self.parts = parts; self.gearPairs = gearPairs
    }

    public func part(_ id: String) -> MGPart? { parts.first { $0.id == id } }

    /// Structural problems: duplicate ids, missing parents or drive sources, cycles. Empty when valid.
    public func validate() -> [String] {
        var issues: [String] = []
        var ids = Set<String>()
        for p in parts where !ids.insert(p.id).inserted { issues.append("duplicate part id \(p.id)") }
        let byID = Dictionary(parts.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for p in parts {
            if let parent = p.parent, byID[parent] == nil { issues.append("\(p.id): missing parent \(parent)") }
            for d in MGAssembly.dependencies(p.drive) where byID[d] == nil { issues.append("\(p.id): missing drive source \(d)") }
            if p.joint == .fixed, p.drive != nil { issues.append("\(p.id): drive on a fixed joint") }
            if p.explodeWindow.lowerBound < 0 || p.explodeWindow.upperBound > 1 || p.explodeWindow.upperBound <= p.explodeWindow.lowerBound {
                issues.append("\(p.id): explode window must lie in 0...1")
            }
        }
        // Cycles in parent or drive graphs.
        func cyclic(_ next: (MGPart) -> [String]) -> Bool {
            var state: [String: Int] = [:]
            func visit(_ id: String) -> Bool {
                if state[id] == 1 { return true }
                if state[id] == 2 { return false }
                state[id] = 1
                if let p = byID[id] { for n in next(p) where visit(n) { return true } }
                state[id] = 2
                return false
            }
            return parts.contains { visit($0.id) }
        }
        if cyclic({ $0.parent.map { [$0] } ?? [] }) { issues.append("parent cycle") }
        if cyclic({ MGAssembly.dependencies($0.drive) }) { issues.append("drive cycle") }
        for g in gearPairs where byID[g.a] == nil || byID[g.b] == nil { issues.append("gear pair \(g.a)-\(g.b): missing part") }
        return issues
    }

    static func dependencies(_ drive: MGDrive?) -> [String] {
        switch drive {
        case .none, .input?: return []
        case .follow(let s, _, _)?: return [s]
        case .gear(let d, _, let c, _)?: return [d] + (c.map { [$0] } ?? [])
        case .crankSlider(let c, _, _, _)?, .crankRod(let c, _, _)?: return [c]
        }
    }

    /// Smoothstep easing of the global explode value into a part's window.
    public static func explodeAmount(_ e: Double, window: ClosedRange<Double>) -> Double {
        let t = min(1, max(0, (e - window.lowerBound) / (window.upperBound - window.lowerBound)))
        return t * t * (3 - 2 * t)
    }

    /// Joint values for every part (0 for fixed joints and undriven joints).
    public func jointValues(_ params: MGPoseParameters) -> [String: Double] {
        let byID = Dictionary(parts.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var values: [String: Double] = [:]
        var visiting = Set<String>()
        func q(_ id: String) -> Double {
            if let v = values[id] { return v }
            guard let p = byID[id], visiting.insert(id).inserted else { return 0 }
            defer { visiting.remove(id) }
            let v: Double
            switch p.drive {
            case .none: v = 0
            case .input(let scale, let offset)?: v = offset + scale * params.input
            case .follow(let s, let ratio, let offset)?: v = offset + ratio * q(s)
            case .gear(let d, let ratio, let c, let offset)?: v = offset + ratio * (q(d) - (c.map(q) ?? 0))
            case .crankSlider(let c, let r, let l, let offset)?:
                let t = q(c)
                v = r * cos(t) + max(0, l * l - r * r * sin(t) * sin(t)).squareRoot() - offset
            case .crankRod(let c, let r, let l)?:
                let t = q(c)
                let x = r * cos(t) + max(0, l * l - r * r * sin(t) * sin(t)).squareRoot()
                // Direction from the wrist pin (x, 0) to the crank pin, relative to local -X.
                v = atan2(r * sin(t), r * cos(t) - x) - .pi
            }
            values[id] = v
            return v
        }
        for p in parts { _ = q(p.id) }
        return values
    }

    /// Full pose: joint values and world transforms. Pure.
    public func pose(_ params: MGPoseParameters) -> MGPose {
        let values = jointValues(params)
        let byID = Dictionary(parts.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var world: [String: MGTransform] = [:]
        var visiting = Set<String>()
        func w(_ id: String) -> MGTransform {
            if let t = world[id] { return t }
            guard let p = byID[id], visiting.insert(id).inserted else { return .identity }
            defer { visiting.remove(id) }
            let parentWorld = p.parent.map(w) ?? .identity
            let e = MGAssembly.explodeAmount(params.explode, window: p.explodeWindow)
            let q = values[id] ?? 0
            let jointT: MGTransform
            switch p.joint {
            case .fixed: jointT = .identity
            case .revolute(let axis): jointT = .rotation(axis: axis, angle: q)
            case .prismatic(let axis): jointT = .translation(axis.normalized * q)
            }
            let t = parentWorld * .translation(p.explode * e) * p.placement * jointT
            world[id] = t
            return t
        }
        for p in parts { _ = w(p.id) }
        return MGPose(values: values, world: world)
    }

    /// World-space bounds of the posed assembly (transformed bounding-box corners; conservative).
    public func bounds(_ pose: MGPose) -> MGBounds {
        var b = MGBounds.empty
        for p in parts {
            let t = pose.world[p.id] ?? .identity
            for c in p.mesh.bounds.corners { b.include(t.apply(c)) }
        }
        return b
    }

    /// Mesh-constraint residuals in tooth-arc units (radians times teeth), minus their value at input 0.
    /// Zero for every pair means the driven gears turn at the tooth ratio for this pose.
    public func gearResiduals(_ params: MGPoseParameters) -> [Double] {
        let v = jointValues(params), v0 = jointValues(MGPoseParameters(input: 0, explode: params.explode))
        func rel(_ values: [String: Double], _ id: String, _ carrier: String?) -> Double {
            guard let c = carrier else { return values[id] ?? 0 }
            return part(id)?.parent == c ? (values[id] ?? 0) : (values[id] ?? 0) - (values[c] ?? 0)
        }
        return gearPairs.map { g in
            let sign: Double = g.isInternal ? -1 : 1
            func f(_ values: [String: Double]) -> Double {
                Double(g.teethA) * rel(values, g.a, g.carrier) + sign * Double(g.teethB) * rel(values, g.b, g.carrier)
            }
            return f(v) - f(v0)
        }
    }
}
