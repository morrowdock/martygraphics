// SPDX-License-Identifier: Apache-2.0
import Foundation

/// Seamless loops of a solid document's motion (docs/ENGINE.md, "Seamless loops").
///
/// The render loop (`MGSolidRenderPlan`) plays one input turn. A part that turns a fraction of a turn per input turn
/// does not come back to where it started, so that loop jumps at the wrap: the robot-joint reducer's output carrier
/// turns 4/49 of a turn per input turn, and the 360-frame loop at 30 fps advances it 0.082° a frame, then turns it
/// 29.306° back from the last frame to the first.
///
/// `period` finds the exact number of input turns after which every part looks the same again: each driven joint's
/// rate is an exact fraction (`Ratio`), and a joint must turn a whole number of the symmetry steps of what it turns
/// (a 24-tooth gear looks the same after 1/24 of a turn; a three-arm carrier with its pins and planets after 1/3).
/// Symmetry is measured on the meshes, never assumed, and the found period is checked numerically on every moving
/// part's vertices before it is used. `plan` samples the period with frame k at k / n of it, so frame n would be frame
/// 0 again and the step from the last frame to the first is one ordinary frame step. Foundation only, deterministic.
public enum MGSolidLoop {
    /// A tessellated circle of at least this many evenly spaced vertices about a part's axis looks the same at any
    /// turn (the engine's smallest round shaft has 24 segments). Its vertices are left out of the symmetry tests and
    /// its centre stands for it.
    public static let roundSegments = 24

    // MARK: Exact fractions

    /// An exact fraction in lowest terms (`denominator` > 0).
    public struct Ratio: Hashable, Sendable, CustomStringConvertible {
        public let numerator: Int
        public let denominator: Int

        /// nil for a zero denominator.
        public init?(_ numerator: Int, _ denominator: Int) {
            guard denominator != 0, numerator != Int.min, denominator != Int.min else { return nil }
            let g = MGSolidLoop.gcd(numerator, denominator)
            let sign = denominator < 0 ? -1 : 1
            self.numerator = sign * (numerator / g)
            self.denominator = abs(denominator) / g
        }

        public var value: Double { Double(numerator) / Double(denominator) }
        /// "49/6", "-4/49", "1".
        public var description: String { denominator == 1 ? "\(numerator)" : "\(numerator)/\(denominator)" }

        /// The exact fraction p/q with q ≤ `maxDenominator` within 1e-12 × max(1, |x|) of `x` (the rule of
        /// `MGSolidFacts.fraction`); nil when there is none (for example π, or a rate an author typed as 0.123456789).
        public static func approximating(_ x: Double, maxDenominator: Int = 100_000) -> Ratio? {
            guard x.isFinite, abs(x) <= 1e6 else { return nil }
            let a = abs(x)
            var h0 = 0.0, h1 = 1.0, k0 = 1.0, k1 = 0.0, r = a
            for _ in 0..<64 {
                let f = r.rounded(.down)
                let h2 = f * h1 + h0, k2 = f * k1 + k0
                guard k2 <= Double(maxDenominator) else { break }
                h0 = h1; h1 = h2; k0 = k1; k1 = k2
                if abs(h1 / k1 - a) <= 1e-12 * max(1, a) { return Ratio(x < 0 ? -Int(h1) : Int(h1), Int(k1)) }
                let rest = r - f
                guard rest > 1e-15 else { break }
                r = 1 / rest
            }
            return nil
        }

        /// This fraction times a whole number; nil on overflow.
        public func times(_ k: Int) -> Ratio? {
            let (n, overflow) = numerator.multipliedReportingOverflow(by: k)
            return overflow ? nil : Ratio(n, denominator)
        }
    }

    static func gcd(_ a: Int, _ b: Int) -> Int {
        var x = a.magnitude, y = b.magnitude
        while y != 0 { (x, y) = (y, x % y) }
        return x == 0 ? 1 : Int(x)
    }

    /// Least common multiple of two positive numbers; nil on overflow.
    static func lcm(_ a: Int, _ b: Int) -> Int? {
        let (m, overflow) = (a / gcd(a, b)).multipliedReportingOverflow(by: b)
        return overflow ? nil : m
    }

    /// The smallest positive L with L × c a whole number for every c: lcm of the denominators over gcd of the
    /// numerators (the intersection of the lattices (q/p)ℤ). nil when no condition has a non-zero numerator, or on
    /// overflow.
    static func lattice(_ conditions: [Ratio]) -> Ratio? {
        var l = 1, g = 0
        for c in conditions where c.numerator != 0 {
            guard let m = lcm(l, c.denominator) else { return nil }
            l = m
            g = g == 0 ? abs(c.numerator) : gcd(g, c.numerator)
        }
        guard g > 0 else { return nil }
        return Ratio(l, g)
    }

    static func divisors(_ n: Int) -> [Int] {
        guard n > 0 else { return [] }
        var small: [Int] = [], large: [Int] = []
        var k = 1
        while k * k <= n {
            if n % k == 0 {
                small.append(k)
                if k * k != n { large.append(n / k) }
            }
            k += 1
        }
        return small + large.reversed()
    }

    // MARK: Results

    /// What `period` and `plan` may change.
    public struct Options: Equatable, Sendable {
        /// The loop plays the smallest whole multiple of the period that is at least this many input turns (1: the
        /// pace of the render loop for a mechanism whose period is a fraction of a turn).
        public var targetTurns = 1.0
        /// A longer period is refused (`period`).
        public var maxTurns = 64
        /// The loop lasts at least this long (seconds) ...
        public var minSeconds = 12.0
        /// ... and at most this long; a period that needs more frames is refused (`frames`).
        public var maxSeconds = 60.0
        /// Largest advance per frame, in symmetry steps of a part's own mesh: below 0.5 no pattern can seem to turn
        /// backwards (the wagon-wheel effect); 0.4 leaves a margin.
        public var maxStepsPerFrame = 0.4
        /// The frame count is rounded up to a multiple of this (3 at 30 fps keeps every third frame a GIF frame).
        public var frameMultiple = 1
        /// One camera orbit over the loop, and the explode-and-reassemble beat of the render loop.
        public var orbit = true
        public var explode = true
        public init() {}
    }

    /// One driven joint of the period analysis.
    public struct Joint: Equatable, Sendable {
        public var part: String
        /// Turns (revolute) or millimetres (prismatic) per input turn, exact; nil for a joint a crank drives (it
        /// repeats when its crank does).
        public var rate: Ratio?
        /// Symmetry order of what the joint turns (its part and everything carried by it), used for the period: the
        /// joint must turn a whole number of 1/`symmetry` turns. 0: round (any turn looks the same); 1 for a slide.
        public var symmetry: Int
        /// Symmetry order of the part's own mesh about its axis, used for the frame bound (0: round).
        public var meshSymmetry: Int
    }

    /// The period of a document's motion.
    public struct Period: Equatable, Sendable {
        /// Input turns of the loop: the smallest whole multiple of `fundamental` that is at least
        /// `Options.targetTurns`.
        public var turns: Ratio
        /// Input turns after which every part first looks the same again.
        public var fundamental: Ratio
        /// Every driven joint, in part order.
        public var joints: [Joint]
        /// True when the measured symmetries did not pass the numeric check and every symmetry was taken as 1: each
        /// part then returns to its own transform.
        public var strict: Bool

        /// Symmetry order per part id (`wrap(_:poses:symmetry:)`).
        public var symmetry: [String: Int] { Dictionary(joints.map { ($0.part, $0.symmetry) }, uniquingKeysWith: { a, _ in a }) }
    }

    /// Why a document has no seamless loop.
    public struct Refusal: Error, Equatable, Sendable, CustomStringConvertible {
        public enum Reason: String, Sendable {
            /// A joint rate is not an exact fraction (q ≤ 100 000).
            case ratio
            /// A slide moves steadily with the input, so it never comes back.
            case slide
            /// A joint mixes steady turning with crank motion; its period is not analysed.
            case mixed
            /// The period is longer than `Options.maxTurns` input turns (or does not fit an Int).
            case period
            /// The period needs more frames than `Options.maxSeconds` allows at this frame rate.
            case frames
            /// The found period did not pass the numeric check.
            case check
            /// An option is out of range (fps 1...240, finite positive seconds and turns).
            case options
        }
        public var reason: Reason
        public var part: String?
        /// The loop's input turns, when `period` or `frames` refused it.
        public var turns: Ratio?
        public init(_ reason: Reason, part: String? = nil, turns: Ratio? = nil) { self.reason = reason; self.part = part; self.turns = turns }
        public var description: String {
            var s = reason.rawValue
            if let part { s += " (" + part + ")" }
            if let turns { s += ", " + turns.description + " input turns" }
            return s
        }
    }

    /// A seamless loop: frame k (0 ≤ k < `frames`) shows k / `frames` of the period.
    public struct Plan: Equatable, Sendable {
        public var period: Period
        public var fps: Int
        public var frames: Int
        public var shots: [MGSolidShot]
        /// The shot one whole period on (k = `frames`): the same scene as shot 0, with the motion continued. An
        /// offline renderer keys it so that motion blur on the last frame samples real motion.
        public var closing: MGSolidShot
        /// Largest advance per frame of any part's own pattern, in symmetry steps (at most `Options.maxStepsPerFrame`).
        public var stepsPerFrame: Double
        public var seconds: Double { Double(frames) / Double(fps) }
    }

    // MARK: Period

    /// How a joint value depends on the input.
    enum Motion: Equatable {
        case still, linear, mixed
        /// A function of the angles of these cranks (crank-slider and crank-rod drives, and what follows them).
        case periodic(Set<String>)
    }

    static func motions(_ a: MGAssembly) -> [String: Motion] {
        let byID = Dictionary(a.parts.map { ($0.id, $0) }, uniquingKeysWith: { x, _ in x })
        var out: [String: Motion] = [:]
        var visiting = Set<String>()
        func combine(_ x: Motion, _ y: Motion) -> Motion {
            switch (x, y) {
            case (.mixed, _), (_, .mixed): return .mixed
            case (.still, let o), (let o, .still): return o
            case (.linear, .linear): return .linear
            case (.periodic(let p), .periodic(let q)): return .periodic(p.union(q))
            default: return .mixed
            }
        }
        func motion(_ id: String) -> Motion {
            if let v = out[id] { return v }
            guard let p = byID[id], visiting.insert(id).inserted else { return .mixed }
            defer { visiting.remove(id) }
            let v: Motion
            switch p.drive {
            case .none: v = .still
            case .input?: v = .linear
            case .follow(let s, _, _)?: v = motion(s)
            case .gear(let d, _, let c, _)?: v = combine(motion(d), c.map(motion) ?? .still)
            case .crankSlider(let c, _, _, _)?, .crankRod(let c, _, _)?:
                switch motion(c) {
                case .still: v = .still
                case .linear: v = .periodic([c])
                case .periodic(let set): v = .periodic(set)
                case .mixed: v = .mixed
                }
            }
            out[id] = v
            return v
        }
        for p in a.parts { _ = motion(p.id) }
        return out
    }

    /// The period of a document's loop: its default input, with the parts the plain view hides left out of the check.
    public static func period(_ doc: MGSolidDocument, options: Options = Options()) -> Result<Period, Refusal> {
        period(doc.assembly, input: doc.defaults.input, hidden: doc.hiddenParts(step: nil), options: options)
    }

    /// The period of an assembly's motion from input `input` (radians). `hidden` parts are left out of the numeric
    /// check (they are not drawn). Refusals: `ratio`, `slide`, `mixed`, `period`, `check`, `options`.
    public static func period(_ a: MGAssembly, input: Double = 0, hidden: Set<String> = [], options: Options = Options()) -> Result<Period, Refusal> {
        guard input.isFinite, options.targetTurns.isFinite, options.targetTurns > 0, options.maxTurns >= 1 else { return .failure(Refusal(.options)) }
        let byPart = MGSolidLoop.motions(a)
        let v0 = a.jointValues(MGPoseParameters(input: 0)), v1 = a.jointValues(MGPoseParameters(input: 1))
        let geometry = Geometry(a, input: input, tolerance: Geometry.defaultTolerance(a, input: input))
        var joints: [Joint] = []
        var strictConditions: [Ratio] = [], conditions: [Ratio] = []
        var cranks = Set<String>()
        for p in a.parts where p.drive != nil && p.joint != .fixed {
            let m = byPart[p.id] ?? .mixed
            switch m {
            case .still: continue
            case .mixed: return .failure(Refusal(.mixed, part: p.id))
            case .periodic(let set):
                cranks.formUnion(set)
                joints.append(Joint(part: p.id, rate: nil, symmetry: 1, meshSymmetry: 1))
            case .linear:
                let slope = (v1[p.id] ?? 0) - (v0[p.id] ?? 0)
                guard let rate = Ratio.approximating(slope) else { return .failure(Refusal(.ratio, part: p.id)) }
                guard rate.numerator != 0 else { continue }
                if case .prismatic = p.joint { return .failure(Refusal(.slide, part: p.id)) }
                let symmetry = geometry.subtreeSymmetry(p.id), own = geometry.meshSymmetry(p.id)
                joints.append(Joint(part: p.id, rate: rate, symmetry: symmetry, meshSymmetry: own))
                strictConditions.append(rate)
                if symmetry != 0 {
                    guard let c = rate.times(symmetry) else { return .failure(Refusal(.period, part: p.id)) }
                    conditions.append(c)
                }
            }
        }
        // A crank must come back to its own angle (its slider and rod follow it), whatever its symmetry.
        for c in cranks.sorted() {
            guard let k = joints.first(where: { $0.part == c }), let rate = k.rate else { continue }
            strictConditions.append(rate); conditions.append(rate)
        }
        let check = { (turns: Ratio) -> Bool in geometry.repeats(after: turns, hidden: hidden) }
        for (strict, list) in [(false, conditions), (true, strictConditions)] {
            // No condition: nothing that moves can be told apart at any turn; one input turn keeps the render pace.
            let fundamental: Ratio
            if list.isEmpty { fundamental = Ratio(1, 1)! }
            else if let l = lattice(list) { fundamental = l }
            else { return .failure(Refusal(.period)) }
            guard fundamental.value <= Double(options.maxTurns) else { return .failure(Refusal(.period, turns: fundamental)) }
            let multiple = max(1, Int((options.targetTurns / fundamental.value - 1e-9).rounded(.up)))
            guard let turns = fundamental.times(multiple), turns.value <= Double(options.maxTurns) else {
                return .failure(Refusal(.period, turns: fundamental))
            }
            guard check(fundamental) else { continue }
            var out = joints
            if strict { for k in out.indices where out[k].rate != nil { out[k].symmetry = 1 } }
            return .success(Period(turns: turns, fundamental: fundamental, joints: out, strict: strict))
        }
        return .failure(Refusal(.check))
    }

    // MARK: Plan

    /// The seamless loop of `doc` at `fps` frames per second: the period, its frame count (the most of the minimum
    /// duration and the frame bound, rounded up to `frameMultiple`), the shots and the closing shot.
    public static func plan(_ doc: MGSolidDocument, fps: Int, options: Options = Options()) -> Result<Plan, Refusal> {
        guard (1...240).contains(fps), options.minSeconds.isFinite, options.maxSeconds.isFinite, options.minSeconds >= 0,
              options.maxSeconds > 0, options.maxStepsPerFrame.isFinite, options.maxStepsPerFrame > 0,
              options.frameMultiple >= 1 else { return .failure(Refusal(.options)) }
        let period: Period
        switch MGSolidLoop.period(doc, options: options) {
        case .success(let p): period = p
        case .failure(let r): return .failure(r)
        }
        let steps = maxSteps(period)
        // The frame count is checked as a Double before any conversion, so no option can overflow it.
        let need = max(Double(fps) * options.minSeconds, steps / options.maxStepsPerFrame)
        let limit = min(14_400, Int((Double(fps) * min(options.maxSeconds, 1e6) + 1e-9).rounded(.down)))
        guard need.isFinite, need <= Double(limit) + 1e-9 else { return .failure(Refusal(.frames, turns: period.turns)) }
        var n = max(1, Int((need - 1e-9).rounded(.up)))
        n = (n + options.frameMultiple - 1) / options.frameMultiple * options.frameMultiple
        guard n <= limit else { return .failure(Refusal(.frames, turns: period.turns)) }
        let all = shots(doc.defaults.input, turns: period.turns, frames: n, orbit: options.orbit, explode: options.explode, closing: true)
        return .success(Plan(period: period, fps: fps, frames: n, shots: Array(all.dropLast()), closing: all[n],
                             stepsPerFrame: steps / Double(n)))
    }

    /// Loop cameras that repeat with the loop (`MGSolidFraming.loopFraming`'s rule with one change). The render loop
    /// frames each frame on the bounding-box corners of its turned parts, so its camera breathes a little as the parts
    /// turn, and a turned part's box differs from its unturned box: at a seamless wrap the camera would jump. Here each
    /// frame is framed at the first shot's input (with the frame's own orbit and explode), so a camera depends only on
    /// the orbit and the explode beat, which repeat; then, as there, every camera moves back by one factor until every
    /// frame's real pose fits. The closing shot gets the first shot's camera.
    public static func cameras(_ doc: MGSolidDocument, shots: [MGSolidShot], aspect: Double, fieldOfView: Double = 30) -> (cameras: [MGSolidCamera], scale: Double) {
        let aspect = aspect.isFinite && aspect > 0 ? aspect : 1.6, fov = MGSolidFraming.fov(fieldOfView)
        let hidden = doc.hiddenParts(step: nil), stage = MGSolidStage.zUpToYUp
        let a = doc.assembly, samples = MGSolidFraming.Samples(a, ids: nil, exclude: hidden)
        let window = MGSolidFraming.Window(titleBand: 0, captionBand: 0)
        let f = MGSolidFraming.focal(fov)
        let input = shots.first?.params.input ?? doc.defaults.input
        var cams: [MGSolidCamera] = [], k = 1.0
        for s in shots {
            var still = s
            still.params.input = input
            let (yaw, pitch) = MGSolidFraming.direction(s)
            let c = MGSolidFraming.legacy(a, still, yaw: yaw, pitch: pitch, aspect: aspect, fieldOfView: fov, stage: stage, hidden: hidden)
            cams.append(c)
            let pts = samples.world(a, s.params, stage: stage)
            guard !MGSolidFraming.contains(pts, camera: c, aspect: aspect, window: window), c.distance > 0 else { continue }
            let need = MGSolidFraming.distance(pts, target: c.targetVector, basis: MGSolidFraming.Basis(yaw: yaw, pitch: pitch), focal: f,
                                               aspect: aspect, window: window.scaled(MGSolidFraming.loopFill))
            k = max(k, need / c.distance)
        }
        guard k > 1, k.isFinite else { return (cams, 1) }
        return (cams.map { var c = $0; c.distance *= k; return c }, k)
    }

    /// Symmetry steps of the fastest own pattern over one loop (`Joint.meshSymmetry` × turns of the joint).
    static func maxSteps(_ p: Period) -> Double {
        var steps = 0.0
        for j in p.joints {
            guard let rate = j.rate, j.meshSymmetry > 0 else { continue }
            steps = max(steps, abs(rate.value) * p.turns.value * Double(j.meshSymmetry))
        }
        return steps
    }

    /// The loop shots: frame k at k / `frames` of `turns` input turns from `input`, one orbit and the render loop's
    /// explode beat (`MGSolidRenderPlan`) when asked; `closing` adds the shot at k = `frames`.
    public static func shots(_ input: Double, turns: Ratio, frames n: Int, orbit: Bool = true, explode: Bool = true,
                             closing: Bool = false) -> [MGSolidShot] {
        guard n > 0 else { return [] }
        return (0..<(closing ? n + 1 : n)).map { k -> MGSolidShot in
            let t = Double(k) / Double(n)
            let e = explode && t > 0.4 && t < 0.9 ? 0.5 - 0.5 * cos((t - 0.4) / 0.5 * 2 * .pi) : 0
            return MGSolidShot(file: "", params: MGPoseParameters(input: input + t * 2 * .pi * turns.value, explode: e), preset: "hero",
                               orbit: orbit ? t * 360 : 0, highlight: [], margin: 0.86, step: nil, title: nil, caption: nil)
        }
    }

    // MARK: Wrap

    /// One driven joint at the wrap of a loop.
    public struct WrapRow: Equatable, Sendable {
        public var part: String
        /// True for a turn (degrees), false for a slide (millimetres).
        public var turns: Bool
        public var symmetry: Int
        /// The motion's own step out of the last frame: to the closing pose when one is given, else the step into the
        /// last frame (exact for steady turning; a crank's motion curves, so give its closing pose).
        public var step: Double
        /// What the loop shows instead: the change from the last frame to the first, for a turn the equivalent turn
        /// nearest `step` (whole symmetry steps apart; a round part shows no jump).
        public var jump: Double
        /// How far the wrap is from the motion's own step (0 for a seamless loop).
        public var error: Double { abs(jump - step) }
    }

    /// The wrap of a loop given by its poses (frame k = `poses[k]`) and, when known, its closing pose (one frame after
    /// the last: `Plan.closing`, or for a one-turn loop the default input plus one turn). `symmetry` per part id
    /// (`Period.symmetry`); missing ids count as 1. A joint that does not move is left out.
    public static func wrap(_ a: MGAssembly, poses: [MGPoseParameters], closing: MGPoseParameters? = nil,
                            symmetry: [String: Int] = [:]) -> [WrapRow] {
        guard poses.count >= 2 else { return [] }
        let first = a.jointValues(poses[0]), before = a.jointValues(poses[poses.count - 2]), last = a.jointValues(poses[poses.count - 1])
        let next = closing.map { a.jointValues($0) }
        var rows: [WrapRow] = []
        for p in a.parts where p.drive != nil && p.joint != .fixed {
            let q0 = first[p.id] ?? 0, qb = before[p.id] ?? 0, ql = last[p.id] ?? 0
            guard q0 != ql || qb != ql else { continue }
            let own = next.map { ($0[p.id] ?? 0) - ql } ?? (ql - qb)
            if case .prismatic = p.joint {
                rows.append(WrapRow(part: p.id, turns: false, symmetry: 1, step: own, jump: q0 - ql))
                continue
            }
            let s = symmetry[p.id] ?? 1
            let step = own * 180 / .pi
            guard s > 0 else { rows.append(WrapRow(part: p.id, turns: true, symmetry: 0, step: step, jump: step)); continue }
            let unit = 360 / Double(s)
            var jump = (q0 - ql) * 180 / .pi
            jump -= unit * ((jump - step) / unit).rounded()
            rows.append(WrapRow(part: p.id, turns: true, symmetry: s, step: step, jump: jump))
        }
        return rows
    }

    /// The row with the largest `error` (the first on a tie); nil for none.
    public static func worst(_ rows: [WrapRow]) -> WrapRow? {
        var best: WrapRow?
        for r in rows where best == nil || r.error > best!.error { best = r }
        return best
    }

    // MARK: Geometry

    /// The meshes of an assembly reduced to the points a turn can change, and the symmetry tests on them.
    struct Geometry {
        let assembly: MGAssembly
        let input: Double
        let tolerance: Double
        /// Per part: feature points in the part frame (`features`), and the vertex counts of its rings that are not round.
        var points: [String: [MGVec3]] = [:]
        var ringCounts: [String: [Int]] = [:]
        var children: [String: [String]] = [:]
        var materials: [String: Int] = [:]
        let world: [String: MGTransform]

        /// 1e-6 of the assembly's diagonal at `input`, at least 1e-9 (millimetres).
        static func defaultTolerance(_ a: MGAssembly, input: Double) -> Double {
            let b = a.bounds(a.pose(MGPoseParameters(input: input)))
            let d = b.isEmpty ? 0 : b.size.length
            return max(1e-9, d.isFinite ? d * 1e-6 : 1e-9)
        }

        init(_ a: MGAssembly, input: Double, tolerance: Double) {
            assembly = a; self.input = input; self.tolerance = tolerance
            world = a.pose(MGPoseParameters(input: input)).world
            var names: [String: Int] = [:]
            for p in a.parts {
                let f = Geometry.features(p.mesh.positions, axis: Geometry.axis(p), tolerance: tolerance)
                points[p.id] = f.points
                ringCounts[p.id] = f.ringCounts
                if let parent = p.parent { children[parent, default: []].append(p.id) }
                let key = p.material.id
                if names[key] == nil { names[key] = names.count }
                materials[p.id] = names[key]
            }
        }

        /// A part's own axis: its joint axis, else its local Z (shapes are built about local Z).
        static func axis(_ p: MGPart) -> MGVec3 {
            switch p.joint {
            case .revolute(let axis), .prismatic(let axis): return axis.normalized.length > 0 ? axis.normalized : .unitZ
            case .fixed: return .unitZ
            }
        }

        /// Two unit vectors perpendicular to `n` and to each other.
        static func basis(_ n: MGVec3) -> (MGVec3, MGVec3) {
            let u = n.cross(abs(n.x) < 0.9 ? MGVec3.unitX : MGVec3.unitY).normalized
            return (u, n.cross(u).normalized)
        }

        /// Rings of `points` about the line through the origin along `axis`: points at the same height along it and the
        /// same distance from it, within `tolerance`. Consecutive values after sorting are grouped, so no bin edge splits
        /// a ring. Each ring lists point indices; deterministic.
        static func rings(_ points: [MGVec3], axis: MGVec3, tolerance: Double) -> [[Int]] {
            let n = axis.normalized
            let zr = points.map { p -> (z: Double, r: Double) in
                let z = p.dot(n)
                return (z, (p - n * z).length)
            }
            let sortedIndices = points.indices.sorted { i, j in
                if zr[i].z != zr[j].z { return zr[i].z < zr[j].z }
                if zr[i].r != zr[j].r { return zr[i].r < zr[j].r }
                return i < j
            }
            var out: [[Int]] = []
            var k = 0
            while k < sortedIndices.count {
                var level = [sortedIndices[k]]
                var j = k + 1
                while j < sortedIndices.count, zr[sortedIndices[j]].z - zr[sortedIndices[j - 1]].z <= tolerance {
                    level.append(sortedIndices[j]); j += 1
                }
                k = j
                level.sort { a, b in zr[a].r != zr[b].r ? zr[a].r < zr[b].r : a < b }
                var ring = [level[0]]
                for idx in level.dropFirst() {
                    if zr[idx].r - zr[ring[ring.count - 1]].r <= tolerance { ring.append(idx) } else { out.append(ring); ring = [idx] }
                }
                out.append(ring)
            }
            return out
        }

        /// True for a ring of at least `roundSegments` points evenly spaced about the axis (a tessellated circle).
        static func isRound(_ ring: [Int], _ points: [MGVec3], axis n: MGVec3, radius: Double, tolerance: Double) -> Bool {
            guard ring.count >= MGSolidLoop.roundSegments, radius > tolerance else { return false }
            let (u, v) = basis(n)
            let angles = ring.map { i -> Double in atan2(points[i].dot(v), points[i].dot(u)) }.sorted()
            let step = 2 * Double.pi / Double(angles.count)
            let slack = max(1e-9, tolerance / radius)
            for k in angles.indices {
                let gap = k + 1 < angles.count ? angles[k + 1] - angles[k] : angles[0] + 2 * .pi - angles[k]
                if abs(gap - step) > slack { return false }
            }
            return true
        }

        /// The points of a mesh that a turn about `axis` can change: every vertex off the round rings, each round
        /// ring's centre in its place, and the vertices on the axis. `ringCounts`: sizes of the rings off the axis that
        /// are not round.
        static func features(_ positions: [MGVec3], axis: MGVec3, tolerance: Double) -> (points: [MGVec3], ringCounts: [Int]) {
            let n = axis.normalized
            var out: [MGVec3] = [], counts: [Int] = []
            for ring in rings(positions, axis: n, tolerance: tolerance) {
                let p = positions[ring[0]]
                let z = p.dot(n), r = (p - n * z).length
                if r <= tolerance {
                    out.append(contentsOf: ring.map { positions[$0] })
                } else if isRound(ring, positions, axis: n, radius: r, tolerance: tolerance) {
                    out.append(n * z)
                } else {
                    out.append(contentsOf: ring.map { positions[$0] })
                    counts.append(ring.count)
                }
            }
            return (out, counts)
        }

        /// The largest order d dividing `candidates` such that turning `points` by 2π/d about `axis` maps every point
        /// onto a point of the same group within the tolerance. 0 when `candidates` is 0 (no point off the axis: any
        /// turn maps the set onto itself), 1 when no turn does. The true order divides `candidates` (every ring of an
        /// order-s set holds a multiple of s points), so the first divisor that passes, largest first, is the order.
        func order(_ points: [MGVec3], groups: [Int], axis: MGVec3, candidates g: Int) -> Int {
            guard g > 0 else { return 0 }
            guard g > 1 else { return 1 }
            let index = PointIndex(points, groups: groups, tolerance: tolerance)
            let n = axis.normalized
            for d in MGSolidLoop.divisors(g).reversed() where d > 1 {
                let turn = MGTransform.rotation(axis: n, angle: 2 * .pi / Double(d))
                if index.containsAll(points.map { turn.apply($0) }, groups: groups) { return d }
            }
            return 1
        }

        /// Symmetry order of a part's own mesh about its own axis (0: round).
        func meshSymmetry(_ id: String) -> Int {
            guard let p = assembly.part(id), let pts = points[id] else { return 1 }
            var g = 0
            for c in ringCounts[id] ?? [] { g = g == 0 ? c : MGSolidLoop.gcd(g, c) }
            return order(pts, groups: [Int](repeating: 0, count: pts.count), axis: Geometry.axis(p), candidates: g)
        }

        /// Ids of a part and every part carried by it, in a fixed order.
        func subtree(_ id: String) -> [String] {
            var out: [String] = [], stack = [id], seen = Set<String>()
            while let c = stack.popLast() {
                guard seen.insert(c).inserted else { continue }
                out.append(c)
                stack.append(contentsOf: (children[c] ?? []).reversed())
            }
            return out
        }

        /// Symmetry order of what a revolute joint turns (its part and everything carried by it), about the joint
        /// axis in the part's frame, at the analysed input (0: round).
        func subtreeSymmetry(_ id: String) -> Int {
            guard let p = assembly.part(id), case .revolute(let axis) = p.joint else { return 1 }
            let base = (world[id] ?? .identity).inverse
            var pts: [MGVec3] = [], groups: [Int] = []
            for c in subtree(id) {
                let t = base * (world[c] ?? .identity), group = materials[c] ?? 0
                for x in points[c] ?? [] { pts.append(t.apply(x)); groups.append(group) }
            }
            let n = axis.normalized
            var g = 0
            for ring in Geometry.rings(pts, axis: n, tolerance: tolerance) {
                let q = pts[ring[0]]
                if (q - n * q.dot(n)).length > tolerance { g = g == 0 ? ring.count : MGSolidLoop.gcd(g, ring.count) }
            }
            return order(pts, groups: groups, axis: n, candidates: g)
        }

        /// True when every drawn moving part's feature points `turns` input turns on lie on same-material feature
        /// points at the analysed input, within the tolerance (the two frames show the same scene).
        func repeats(after turns: Ratio, hidden: Set<String>) -> Bool {
            let later = assembly.pose(MGPoseParameters(input: input + 2 * .pi * turns.value)).world
            var a: [MGVec3] = [], ga: [Int] = [], b: [MGVec3] = [], gb: [Int] = []
            for p in assembly.parts where !hidden.contains(p.id) {
                let t0 = world[p.id] ?? .identity, t1 = later[p.id] ?? .identity
                let g = materials[p.id] ?? 0
                for x in points[p.id] ?? [] {
                    a.append(t0.apply(x)); ga.append(g)
                    if t0 != t1 { b.append(t1.apply(x)); gb.append(g) }
                }
            }
            return PointIndex(a, groups: ga, tolerance: tolerance).containsAll(b, groups: gb)
        }
    }

    /// Points hashed by a cubic grid of twice the tolerance: a point within the tolerance of a query lies in one of
    /// the 27 cells around the query's cell.
    struct PointIndex {
        struct Key: Hashable { var g: Int; var x: Int; var y: Int; var z: Int }
        let cell: Double
        let tolerance: Double
        private var table: [Key: [MGVec3]] = [:]

        init(_ points: [MGVec3], groups: [Int], tolerance: Double) {
            self.tolerance = tolerance
            cell = max(2 * tolerance, 1e-12)
            for (p, g) in zip(points, groups) {
                guard let k = PointIndex.key(p, g, cell) else { continue }
                table[k, default: []].append(p)
            }
        }

        static func key(_ p: MGVec3, _ g: Int, _ cell: Double) -> Key? {
            let x = (p.x / cell).rounded(.down), y = (p.y / cell).rounded(.down), z = (p.z / cell).rounded(.down)
            guard x.isFinite, y.isFinite, z.isFinite, abs(x) < 1e15, abs(y) < 1e15, abs(z) < 1e15 else { return nil }
            return Key(g: g, x: Int(x), y: Int(y), z: Int(z))
        }

        func contains(_ p: MGVec3, group g: Int) -> Bool {
            guard let k = PointIndex.key(p, g, cell) else { return false }
            for dx in -1...1 {
                for dy in -1...1 {
                    for dz in -1...1 {
                        guard let list = table[Key(g: g, x: k.x + dx, y: k.y + dy, z: k.z + dz)] else { continue }
                        for q in list where (q - p).length <= tolerance { return true }
                    }
                }
            }
            return false
        }

        func containsAll(_ points: [MGVec3], groups: [Int]) -> Bool {
            for (p, g) in zip(points, groups) where !contains(p, group: g) { return false }
            return true
        }
    }
}
