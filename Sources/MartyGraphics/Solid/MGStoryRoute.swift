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
    /// routed path, or a cut when every path is blocked), `layout` (a cut because the host listed the beat in `routes`'s
    /// `layout`; `marty-solid render` lists none and slides the panes instead, `MGPaneSlide`),
    /// `motion` (a cut because parts move during the move and their swept boxes could not be computed) or `untested`
    /// (a camera is not finite; the move stays straight, as in `blockedMoves`).
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

/// One beat as the move router sees it: its camera (its still's camera; nil without a solid), its end pose, the view
/// its camera move draws (nil: every part blocks) and the solid step it shows (nil: the plain view, or a host that
/// gives only `params`). The frames of the move into a beat show that step's pose at the played share of its spin,
/// with the placements blended from the previous beat's (`MGStoryPlan.movePose`).
public struct MGStoryBeatShot: Sendable {
    public var camera: MGSolidCamera?
    public var params: MGPoseParameters
    public var view: MGSolidView?
    public var step: MGSolidStep?
    public init(camera: MGSolidCamera?, params: MGPoseParameters, view: MGSolidView? = nil, step: MGSolidStep? = nil) {
        self.camera = camera; self.params = params; self.view = view; self.step = step
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
    /// slab test against every blocking part's box (render frame), grown by the renderer's near plane at the larger
    /// camera distance of that chord plus the leg's chord error. The blocking parts are the parts the move draws
    /// solid: with a `view`, the parts it does not hide whose drawn coverage (view opacity times
    /// `MGMaterialPreset.coverage`) is at least `MGSolidFraming.blockingOpacity`, the coverage rule of the anchor checks
    /// (a ghost does not block); without one, every part. The model's bounds centre and bounding sphere are those of
    /// the blocking boxes.
    ///
    /// A part's box is its swept box over the move (`sweptBoxes`): the union of its world boxes at the previous beat's
    /// end pose, at every frame of the move as `plan` plays it (`movePose`: the beat's spin share and placement blend
    /// of each frame) and at this beat's end pose, grown by the largest distance any corner of its box moves between
    /// two of those poses in a row. A straight path is tested with the frames of a straight move
    /// (`MGStoryTiming.transitionSeconds`), a routed path with those of a routed move (`routedTransitionSeconds`). A
    /// part that does not move keeps its one box. Without `plan`, the frames are not known: when the two end poses
    /// differ or the beat spins, the beat cuts with reason `motion`; so does a beat whose swept boxes are not finite.
    ///
    /// A beat in `layout` cuts with reason `layout` (for hosts that cut on a pane layout change; `marty-solid render`
    /// passes none: a layout change moves like any beat and slides its panes, `MGPaneSlide`). When no path is clear,
    /// the beat cuts with reason `blocked`. The
    /// hold cameras are never changed: every path starts exactly at the previous beat's camera and ends exactly at
    /// this beat's camera. Deterministic; at most `maxRouteCandidates` paths per move, each at most 4 legs of
    /// `maxMoveChords` chords against 96 boxes; at most 2 × (`MGStoryTiming` frames of a routed move + 2) poses.
    public static func routes(_ doc: MGSolidDocument, beats: [MGStoryBeatShot], plan: MGStoryPlan? = nil, layout: Set<Int> = [],
                              stage: MGTransform = MGSolidStage.zUpToYUp) -> [Int: MGStoryMove] {
        guard beats.count > 1 else { return [:] }
        var out: [Int: MGStoryMove] = [:]
        for k in 1..<beats.count {
            guard let from = beats[k - 1].camera, let to = beats[k].camera else { continue }
            if layout.contains(k) { out[k] = .cut(to, reason: "layout"); continue }
            let still = beats[k - 1].params == beats[k].params && (beats[k].step?.spin ?? 0) == 0
                && (beats[k].step == nil || beats[k].step?.poseParameters(defaults: doc.defaults, spin: 0) == beats[k].params)
            let straight: [(id: String, box: MGBounds)]?, routed: [(id: String, box: MGBounds)]?
            if still {
                straight = sweptBoxes(doc, beats: beats, k, frames: [], stage: stage); routed = straight
            } else if let plan, plan.beats.indices.contains(k) {
                straight = sweptBoxes(doc, beats: beats, k, frames: moveFrames(plan, k, routed: false), stage: stage)
                routed = sweptBoxes(doc, beats: beats, k, frames: moveFrames(plan, k, routed: true), stage: stage)
            } else {
                straight = nil; routed = nil
            }
            guard let straight, let routed else { out[k] = .cut(to, reason: "motion"); continue }
            out[k] = route(from, to, boxes: straight, routedBoxes: routed)
        }
        return out
    }

    /// The parameters of a frame of the move into beat `k`: the beat's step pose at the played share `spin` of its
    /// spin (`MGSolidStep.poseParameters`; without a step, its `params`), with every placement blended by `blend`
    /// from the previous beat's step pose (without a step, its `params` placements) with `placements`. `blend` 1 gives
    /// the beat's own placements. The render tool draws every move frame with this pose.
    public static func movePose(_ doc: MGSolidDocument, beats: [MGStoryBeatShot], _ k: Int, spin: Double, blend: Double) -> MGPoseParameters {
        guard beats.indices.contains(k) else { return doc.defaults }
        var p = beats[k].step?.poseParameters(defaults: doc.defaults, spin: spin) ?? beats[k].params
        guard k > 0, blend < 1 else { return p }
        let previous = beats[k - 1].step?.pose ?? beats[k - 1].params.placements
        p.placements = placements(doc.assembly, from: previous, to: p.placements, blend)
        return p
    }

    /// The spin share and placement blend of every frame of beat `k`'s move as `plan` (the plan before routing)
    /// plays it, straight or routed (`frame(_:)` of the plan, with a routed move's timing for `routed`).
    static func moveFrames(_ plan: MGStoryPlan, _ k: Int, routed: Bool) -> [(spin: Double, blend: Double)] {
        var p = plan
        if routed {
            let c = MGSolidCamera(target: .zero, yaw: 0, pitch: 0, distance: 1)
            p = plan.routed([k: MGStoryMove(path: .arc, keys: [c, c], ends: [1], reason: "blocked", blockedBy: nil)])
        }
        let b = p.beats[k]
        return (0..<b.transitionFrames).map { j in let f = p.frame(b.startFrame + j); return (f.spin, f.camera) }
    }

    /// Each blocking part's swept box over the move into beat `k` (render frame, assembly order): the union of its
    /// world boxes at the previous beat's end pose, at each of `frames` (`movePose`) and at this beat's end pose, grown
    /// by the largest distance a corner of its mesh box moves between two poses in a row (0 for a part that does not
    /// move). Nil when a pose is not finite.
    static func sweptBoxes(_ doc: MGSolidDocument, beats: [MGStoryBeatShot], _ k: Int, frames: [(spin: Double, blend: Double)],
                           stage: MGTransform) -> [(id: String, box: MGBounds)]? {
        var params = [beats[k - 1].params]
        params += frames.map { movePose(doc, beats: beats, k, spin: $0.spin, blend: $0.blend) }
        params.append(beats[k].params)
        var unique: [MGPoseParameters] = []
        for p in params where unique.last != p { unique.append(p) }
        let poses = unique.map { doc.assembly.pose($0) }
        var out: [(id: String, box: MGBounds)] = []
        for p in doc.assembly.parts {
            if let v = beats[k].view {
                let pv = v.part(p.id)
                guard !pv.hidden, pv.opacity * p.material.coverage >= MGSolidFraming.blockingOpacity else { continue }
            }
            let local = p.mesh.bounds
            guard !local.isEmpty else { continue }
            var box = MGBounds.empty, step = 0.0
            var last: [MGVec3]?
            for pose in poses {
                let t = stage * (pose.world[p.id] ?? .identity)
                let corners = local.corners.map { t.apply($0) }
                for c in corners { box.include(c) }
                if let last { for (a, b) in zip(last, corners) { step = max(step, (b - a).length) } }
                last = corners
            }
            let g = MGVec3(step, step, step)
            box = MGBounds(min: box.min - g, max: box.max + g)
            guard [box.min.x, box.min.y, box.min.z, box.max.x, box.max.y, box.max.z, step].allSatisfy(\.isFinite) else { return nil }
            out.append((p.id, box))
        }
        return out
    }

    /// The first clear path from `a` to `b` among the candidates of `routes`, or a cut: the straight path against
    /// `boxes`, the routed paths against `routedBoxes` (the same parts swept over a routed move's frames).
    static func route(_ a: MGSolidCamera, _ b: MGSolidCamera, boxes: [(id: String, box: MGBounds)],
                      routedBoxes: [(id: String, box: MGBounds)]? = nil) -> MGStoryMove {
        let first: String
        switch test([a, b], boxes) {
        case .clear: return .straight(a, b)
        // A camera that is not finite is not tested (as `blockedMoves`): the move stays straight.
        case .invalid: return MGStoryMove(path: .straight, keys: [a, b], ends: [1], reason: "untested", blockedBy: nil)
        case .blocked(let id): first = id
        }
        let swept = routedBoxes ?? boxes
        var whole = MGBounds.empty
        for x in swept { whole = whole.union(x.box) }
        let centre = whole.isEmpty ? (a.targetVector + b.targetVector) * 0.5 : whole.center
        let rho = whole.isEmpty ? 0 : whole.radius
        for c in candidates(a, b, centre: centre, rho: rho) {
            guard test(c.keys, swept) == .clear else { continue }
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
