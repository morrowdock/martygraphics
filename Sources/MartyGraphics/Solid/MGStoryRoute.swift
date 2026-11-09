// SPDX-License-Identifier: Apache-2.0
import Foundation

// Routed story camera moves (docs/SOLID-3D.md, "Story video", "Routed moves"). When the straight camera move between
// two beats would pass through a part the move draws, a few fixed alternative paths are tried before the story cuts: a
// pull back along the start camera's view, an arc around the model's centre, and the two together. Each path is a chain
// of key cameras played leg by leg with `MGStoryPlan.camera(from:to:_:)`, and each leg is tested with the exact
// segment-versus-box slab test of `MGStoryPlan.blockedMoves` (bounded chords, each grown by the near plane and the
// proven chord error). The first clear path in a fixed order is taken. Foundation only, deterministic.

/// How a story beat's camera move plays: the path, its key cameras and why.
public struct MGStoryMove: Equatable, Sendable {
    /// `straight`: the move of `MGStoryPlan.camera(from:to:_:)`. `pullback`, `arc`, `combined`: a routed path (the
    /// straight move was blocked). `cut`: no move; the beat starts at its own camera.
    public enum Path: String, Equatable, Sendable, CaseIterable { case straight, pullback, arc, combined, cut }
    public let path: Path
    /// The key cameras in play order: the previous beat's camera first and this beat's camera last, exactly (a cut has
    /// one key, this beat's camera).
    public let keys: [MGSolidCamera]
    /// Where each leg ends, as a share of the move (0...1, increasing; the last is exactly 1). One per leg.
    public let ends: [Double]
    /// Why the path was chosen: `clear` (the straight move is clear), `blocked` (the straight move meets a part: a
    /// routed path, or a cut when every path is blocked), `layout` (a cut because the beat's solid pane changed size)
    /// or `untested` (a camera is not finite; the move stays straight, as in `blockedMoves`).
    public let reason: String
    /// `blocked`: the first part the straight move meets (chords in play order, then parts in assembly order, the
    /// previous beat's pose first).
    public let blockedBy: String?

    /// True for `pullback`, `arc` and `combined`.
    public var routed: Bool { path == .pullback || path == .arc || path == .combined }

    /// A straight move from `a` to `b`.
    public static func straight(_ a: MGSolidCamera, _ b: MGSolidCamera) -> MGStoryMove {
        MGStoryMove(path: .straight, keys: [a, b], ends: [1], reason: "clear", blockedBy: nil)
    }

    /// A cut to `b` for `reason` (`layout` or `blocked`).
    public static func cut(_ b: MGSolidCamera, reason: String, blockedBy: String? = nil) -> MGStoryMove {
        MGStoryMove(path: .cut, keys: [b], ends: [], reason: reason, blockedBy: blockedBy)
    }

    /// The camera `t` of the way along the move (0: the first key, 1: the last key, exactly). Each leg plays from its
    /// start share to its end share with `MGStoryPlan.camera(from:to:_:)`; a leg ends exactly on its key camera. A cut
    /// returns its one key.
    public func camera(_ t: Double) -> MGSolidCamera {
        guard let last = keys.last else { return MGSolidCamera(target: .zero, yaw: 0, pitch: 0, distance: 1) }
        guard keys.count >= 2, ends.count == keys.count - 1 else { return last }
        guard t.isFinite, t < 1 else { return last }
        guard t > 0 else { return keys[0] }
        var start = 0.0
        for i in 0..<ends.count {
            let end = ends[i]
            if t < end || i == ends.count - 1 {
                let u = end > start ? (t - start) / (end - start) : 1
                return MGStoryPlan.camera(from: keys[i], to: keys[i + 1], min(1, max(0, u)))
            }
            start = end
        }
        return last
    }

    /// `{"path", "pathReason", "blockedBy"?}` for the story manifest's beat records.
    public var manifestFields: [String: MGJSON] {
        var o: [String: MGJSON] = ["path": .string(path.rawValue), "pathReason": .string(reason)]
        if let blockedBy { o["blockedBy"] = .string(blockedBy) }
        return o
    }
}

/// One beat as the move router sees it: its camera (its still's camera; nil without a solid), its end pose and the view
/// its camera move draws (nil: every part blocks).
public struct MGStoryBeatShot: Sendable {
    public var camera: MGSolidCamera?
    public var params: MGPoseParameters
    public var view: MGSolidView?
    public init(camera: MGSolidCamera?, params: MGPoseParameters, view: MGSolidView? = nil) {
        self.camera = camera; self.params = params; self.view = view
    }
}

extension MGStoryPlan {
    /// Pull-back distances tried, as multiples of the start camera's distance (`pullback`), plus the distance that
    /// takes the start camera outside the model's bounding sphere (radius plus `routeClearance`), when it is at most
    /// `maxPullback` times the start distance. Ascending.
    public static let pullbackFactors: [Double] = [1.5, 2, 3, 4]
    public static let maxPullback = 8.0
    /// Arc radii tried (`arc`), from the model's bounds centre: `r0 + c`, `1.25 × max(r0, ρ) + c` and
    /// `1.75 × max(r0, ρ) + c`, where `r0` is the larger of the two cameras' distances from that centre, `ρ` the
    /// bounding sphere radius (half the box diagonal) and `c = routeClearance × ρ`. Ascending, duplicates dropped.
    public static let arcFactors: [Double] = [1, 1.25, 1.75]
    /// The clearance margin of a routed path, as a share of the model's bounding sphere radius.
    public static let routeClearance = 0.1
    /// Largest pitch (degrees, either sign) of an arc key camera: the orbit stays clear of looking straight down or up,
    /// where the camera's up vector is undefined.
    public static let arcPitchLimit = 85.0
    /// Largest change of the camera distance along one chord of a routed path's leg, as a share (`legChords`).
    public static let routeDistanceStep = 0.1
    /// Paths tried per move, at most: straight, 5 pull backs, 3 arcs, 15 combined.
    public static let maxRouteCandidates = 24

    /// The camera move of each beat after the first (by 0-based beat index). For each beat whose camera and the
    /// previous beat's camera are known, paths are tried in this fixed order and the first clear one is taken:
    ///
    /// 1. `straight`: the move of `camera(from:to:_:)`.
    /// 2. `pullback`, for each pull-back distance `D` (`pullbackFactors`, ascending): the start camera moves straight
    ///    out along its view to distance `D` (same target, yaw, pitch and field of view), then moves to the end camera.
    /// 3. `arc`, for each radius `R` (`arcFactors`): from the start camera to a key camera that looks at the model's
    ///    bounds centre from the start camera's direction at distance `R`, an orbit about that centre at distance `R`
    ///    (yaw the shorter way, pitch linear) to the end camera's direction, then to the end camera.
    /// 4. `combined`, for each pull back `D` and then each radius `R`: the pull back, then the arc from there.
    ///
    /// A path is clear when no leg meets a part box. Each leg is split into chords as `blockedMoves` splits a curved
    /// move (at most `maxMoveChords`, proven chord error), and each chord is tested with the exact segment-versus-box
    /// slab test against every blocking part's posed box (render frame, at the previous beat's pose and at this beat's
    /// pose), grown by the renderer's near plane at the larger camera distance of that chord plus the leg's chord
    /// error. The blocking parts are the parts the move draws solid: with a `view`, the parts it does not hide whose
    /// drawn coverage (view opacity times `MGMaterialPreset.coverage`) is at least `MGSolidFraming.blockingOpacity`, the
    /// coverage rule of the anchor checks (a ghost does not block); without one, every part. The model's bounds centre
    /// and bounding sphere are those of the blocking boxes.
    ///
    /// A beat in `layout` cuts with reason `layout`. When no path is clear, the beat cuts with reason `blocked`. The
    /// hold cameras are never changed: every path starts exactly at the previous beat's camera and ends exactly at
    /// this beat's camera. Deterministic; at most `maxRouteCandidates` paths per move, each at most 4 legs of
    /// `maxMoveChords` chords against 2 × 96 boxes.
    public static func routes(_ doc: MGSolidDocument, beats: [MGStoryBeatShot], layout: Set<Int> = [],
                              stage: MGTransform = MGSolidStage.zUpToYUp) -> [Int: MGStoryMove] {
        guard beats.count > 1 else { return [:] }
        // Each beat's posed part boxes, once (render frame), with the part ids.
        let poses = beats.map { doc.assembly.pose($0.params) }
        var out: [Int: MGStoryMove] = [:]
        for k in 1..<beats.count {
            guard let from = beats[k - 1].camera, let to = beats[k].camera else { continue }
            if layout.contains(k) { out[k] = .cut(to, reason: "layout"); continue }
            var boxes: [(id: String, box: MGBounds)] = []
            for pose in [poses[k - 1], poses[k]] {
                for p in doc.assembly.parts {
                    if let v = beats[k].view {
                        let pv = v.part(p.id)
                        guard !pv.hidden, pv.opacity * p.material.coverage >= MGSolidFraming.blockingOpacity else { continue }
                    }
                    let b = MGSolidFrames.worldBounds(p.mesh.bounds, stage * (pose.world[p.id] ?? .identity))
                    guard !b.isEmpty, [b.min.x, b.min.y, b.min.z, b.max.x, b.max.y, b.max.z].allSatisfy(\.isFinite) else { continue }
                    boxes.append((p.id, b))
                }
            }
            out[k] = route(from, to, boxes: boxes)
        }
        return out
    }

    /// The first clear path from `a` to `b` among the candidates of `routes`, or a cut.
    static func route(_ a: MGSolidCamera, _ b: MGSolidCamera, boxes: [(id: String, box: MGBounds)]) -> MGStoryMove {
        let first: String
        switch test([a, b], boxes) {
        case .clear: return .straight(a, b)
        // A camera that is not finite is not tested (as `blockedMoves`): the move stays straight.
        case .invalid: return MGStoryMove(path: .straight, keys: [a, b], ends: [1], reason: "untested", blockedBy: nil)
        case .blocked(let id): first = id
        }
        var whole = MGBounds.empty
        for x in boxes { whole = whole.union(x.box) }
        let centre = whole.isEmpty ? (a.targetVector + b.targetVector) * 0.5 : whole.center
        let rho = whole.isEmpty ? 0 : whole.radius
        for c in candidates(a, b, centre: centre, rho: rho) {
            guard test(c.keys, boxes) == .clear else { continue }
            return MGStoryMove(path: c.path, keys: c.keys, ends: shares(c.keys), reason: "blocked", blockedBy: first)
        }
        return .cut(b, reason: "blocked", blockedBy: first)
    }

    /// The routed candidates in the fixed order of `routes`, after the straight path.
    static func candidates(_ a: MGSolidCamera, _ b: MGSolidCamera, centre: MGVec3, rho: Double) -> [(path: MGStoryMove.Path, keys: [MGSolidCamera])] {
        let clearance = routeClearance * rho
        func with(_ c: MGSolidCamera, distance d: Double) -> MGSolidCamera {
            MGSolidCamera(target: c.targetVector, yaw: c.yaw, pitch: c.pitch, distance: d, fieldOfView: c.fieldOfView)
        }
        // Pull-back distances: the fixed factors, and the distance that leaves the bounding sphere (when bounded).
        var pulls = pullbackFactors.map { a.distance * $0 }
        let dir = a.position - a.targetVector
        if a.distance > 0, rho > 0 {
            let u = dir * (1 / a.distance), w = a.targetVector - centre, need = rho + clearance
            // |w + D u| = need: D = −w·u + sqrt((w·u)² − |w|² + need²).
            let wu = w.dot(u), disc = wu * wu - w.dot(w) + need * need
            if disc >= 0 {
                let d = -wu + disc.squareRoot()
                if d > a.distance, d <= maxPullback * a.distance { pulls.append(d) }
            }
        }
        pulls = Array(Set(pulls.filter { $0.isFinite && $0 > a.distance })).sorted()
        func orbitKey(_ c: MGSolidCamera, radius r: Double) -> MGSolidCamera {
            var d = c.position - centre
            if d.length < 1e-9 || !d.length.isFinite { d = c.position - c.targetVector }
            let l = d.length
            guard l > 1e-9, l.isFinite else { return MGSolidCamera(target: centre, yaw: c.yaw, pitch: c.pitch, distance: r, fieldOfView: c.fieldOfView) }
            let n = d * (1 / l)
            let pitch = max(-arcPitchLimit, min(arcPitchLimit, asin(max(-1, min(1, n.y))) * 180 / .pi))
            let yaw = abs(n.x) < 1e-12 && abs(n.z) < 1e-12 ? c.yaw : atan2(n.x, n.z) * 180 / .pi
            return MGSolidCamera(target: centre, yaw: yaw, pitch: pitch, distance: r, fieldOfView: c.fieldOfView)
        }
        func radii(_ start: MGSolidCamera) -> [Double] {
            let r0 = max((start.position - centre).length, (b.position - centre).length)
            let big = max(r0, rho)
            let list = arcFactors.enumerated().map { k, f in (k == 0 ? r0 : f * big) + clearance }
            return Array(Set(list.filter { $0.isFinite && $0 > 0 })).sorted()
        }
        func arc(_ start: MGSolidCamera, _ r: Double) -> [MGSolidCamera] { [orbitKey(start, radius: r), orbitKey(b, radius: r)] }
        var out: [(MGStoryMove.Path, [MGSolidCamera])] = []
        for d in pulls { out.append((.pullback, [a, with(a, distance: d), b])) }
        for r in radii(a) { out.append((.arc, [a] + arc(a, r) + [b])) }
        for d in pulls {
            let p = with(a, distance: d)
            for r in radii(p) { out.append((.combined, [a, p] + arc(p, r) + [b])) }
        }
        return out.map { (path: $0.0, keys: $0.1) }
    }

    /// The result of testing a chain of key cameras.
    enum PathTest: Equatable { case clear, blocked(String), invalid }

    /// For a chain of key cameras: `invalid` when a leg has a camera that is not finite; else the first part a leg
    /// meets (legs and chords in play order, boxes in the given order), or `clear`.
    static func test(_ keys: [MGSolidCamera], _ boxes: [(id: String, box: MGBounds)]) -> PathTest {
        for (a, b) in zip(keys, keys.dropFirst()) {
            guard let leg = legChords(a, b) else { return .invalid }
            for j in 0..<(leg.points.count - 1) {
                let p = leg.points[j], q = leg.points[j + 1], g = leg.grows[j]
                for x in boxes where MGAnnotationOcclusion.segmentHits(p, q, MGBounds(min: x.box.min - MGVec3(g, g, g), max: x.box.max + MGVec3(g, g, g))) {
                    return .blocked(x.id)
                }
            }
        }
        return .clear
    }

    /// One leg as chords (render frame) with each chord's box growth: the near plane at the larger camera distance of
    /// the chord's two ends (the distance moves monotonically along a leg) plus the leg's proven chord error
    /// (`movePath` gives the bound). The chord count is `movePath`'s, raised so the camera distance changes by at most
    /// `routeDistanceStep` (10 %) per chord, so the growth near a close camera stays close to its own near plane (at
    /// most `maxMoveChords`). Nil for cameras that are not finite.
    static func legChords(_ a: MGSolidCamera, _ b: MGSolidCamera) -> (points: [MGVec3], grows: [Double])? {
        var minChords = 1
        if a.distance > 0, b.distance > 0, a.distance.isFinite, b.distance.isFinite {
            let k = (abs(log(b.distance / a.distance)) / log(1 + routeDistanceStep)).rounded(.up)
            if k.isFinite { minChords = Int(min(Double(maxMoveChords), max(1, k))) }
        }
        guard let path = movePath(a, b, minChords: minChords) else { return nil }
        let n = path.points.count - 1
        guard n >= 1 else { return nil }
        let error = path.grow - MGSolidFraming.nearPlane(distance: max(a.distance, b.distance))
        let dist = (0...n).map { MGStoryPlan.camera(from: a, to: b, Double($0) / Double(n)).distance }
        let grows = (0..<n).map { MGSolidFraming.nearPlane(distance: max(dist[$0], dist[$0 + 1])) + max(0, error) }
        return (path.points, grows)
    }

    /// Where each leg of a chain ends, as a share of the move: each leg's weight is its camera path length (chords)
    /// plus its target travel plus its turn (yaw plus pitch change, radians) times its mean distance, so the camera
    /// moves at about one pace; equal shares when every weight is 0.
    static func shares(_ keys: [MGSolidCamera]) -> [Double] {
        let legs = Array(zip(keys, keys.dropFirst()))
        guard !legs.isEmpty else { return [] }
        let weights: [Double] = legs.map { a, b in
            guard let path = movePath(a, b) else { return 0 }
            var length = 0.0
            for (p, q) in zip(path.points, path.points.dropFirst()) { length += (q - p).length }
            var dy = (b.yaw - a.yaw).truncatingRemainder(dividingBy: 360)
            if dy > 180 { dy -= 360 } else if dy < -180 { dy += 360 }
            let turn = (abs(dy) + abs(b.pitch - a.pitch)) * .pi / 180
            let w = length + (b.targetVector - a.targetVector).length + turn * (a.distance + b.distance) / 2
            return w.isFinite ? w : 0
        }
        let total = weights.reduce(0, +)
        var out: [Double] = [], acc = 0.0
        for (k, w) in weights.enumerated() {
            acc += total > 0 ? w : 1
            out.append(k == weights.count - 1 ? 1 : acc / (total > 0 ? total : Double(weights.count)))
        }
        return out
    }
}

extension MGSolidView {
    /// The view a story camera move draws when it leaves a beat that shows `previous` and arrives at a beat that shows
    /// this view: this view, with every part that `previous` draws fainter than the part's own opacity (a step
    /// `ghost`, or an automatic ghost of the unblocked-focus rule) drawn as a ghost too (`ghosting`). A camera that
    /// leaves a close-up through a ghosted body does not start inside a solid one; the part turns solid when the hold
    /// starts, with the caption and labels. Hidden parts, cuts, light and annotations are this view's.
    public func moving(from previous: MGSolidView, _ assembly: MGAssembly) -> MGSolidView {
        let faint = assembly.parts.filter { p in
            let pv = previous.part(p.id)
            return !pv.hidden && pv.opacity < MGSolidView.clamp(opacity: p.opacity) - 1e-9
        }.map(\.id)
        return ghosting(faint)
    }
}
