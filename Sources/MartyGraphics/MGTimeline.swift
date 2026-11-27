// SPDX-License-Identifier: Apache-2.0
import Foundation

/// Step state, motion frames and patch blending. Pure functions of (scene, step, time) so renderers and tests agree.
public enum MGTimeline {
    public static func videoFrame(_ index: Int, in plan: MGCheckedVideoPlan) throws -> [MGVideoElement] {
        guard (0..<plan.durationFrames).contains(index) else { throw MGError("video2d.frame") }
        return plan.elements.map { element in
            guard let track = plan.tracks.first(where: { $0.target == element.id }) else { return element }
            var result = element
            let positions = track.keyframes.filter { $0.at != nil }
            let opacities = track.keyframes.filter { $0.opacity != nil }
            let highlights = track.keyframes.filter { $0.highlightLine != nil }
            func pair(_ keys: [MGVideoKeyframe]) -> (MGVideoKeyframe, MGVideoKeyframe, Double)? {
                guard let first = keys.first, index >= first.frame else { return nil }
                let left = keys.last(where: { $0.frame <= index }) ?? first
                let right = keys.first(where: { $0.frame > index }) ?? left
                let progress = track.interpolation == "hold" || left.frame == right.frame ? 0 : Double(index - left.frame) / Double(right.frame - left.frame)
                return (left, right, progress)
            }
            if let (left, right, progress) = pair(positions), let start = left.at, let end = right.at {
                result.at = zip(start, end).map { $0 + ($1 - $0) * progress }
            }
            if let (left, right, progress) = pair(opacities), let start = left.opacity, let end = right.opacity {
                result.opacity = start + (end - start) * progress
            }
            if let key = highlights.last(where: { $0.frame <= index }) { result.highlightLine = key.highlightLine }
            return result
        }
    }
    /// Index of the first step that lists each item in `show`. Items never listed are always visible.
    public static func firstShown(_ scene: MGScene) -> [String: Int] {
        var out: [String: Int] = [:]
        for (i, s) in scene.steps.enumerated() { for id in s.show where out[id] == nil { out[id] = i } }
        return out
    }

    /// Items visible at `step` with step edits 0...step applied. A scene without steps shows everything.
    public static func items(_ scene: MGScene, step: Int) -> [MGItem] {
        let ctx = MGContext(width: scene.width, height: scene.height, is3D: scene.is3D, values: scene.values)
        var items = scene.items
        if !scene.steps.isEmpty {
            let last = min(max(step, 0), scene.steps.count - 1)
            for s in scene.steps[0...last] { for e in s.edits { items = (try? MGParser.apply(e, to: items, ctx)) ?? items } }
            let first = firstShown(scene)
            items = items.filter { (first[$0.id] ?? 0) <= last }
        }
        // A vector, highlight or edge whose anchor is hidden is hidden too, transitively (a highlight of a hidden
        // highlight is hidden). Repeat until nothing more is removed; each pass shrinks the list, so this terminates.
        while true {
            let ids = Set(items.map(\.id))
            let kept = items.filter { i in
                switch i.kind {
                case .vector: return i.ref.map(ids.contains) ?? true
                case .highlight: return ids.contains(i.ref ?? "")
                case .edge: return ids.contains(i.ref ?? "") && ids.contains(i.ref2 ?? "")
                default: return true
                }
            }
            if kept.count == items.count { return kept }
            items = kept
        }
    }

    /// Motion applied at `time` seconds. Vectors with `on` get an absolute tail at their body's current centre.
    /// Callers that draw every frame pass the cached step items (`MGTimelineCache`), not a fresh `items(_:step:)`.
    public static func frame(_ scene: MGScene, items: [MGItem], time: Double) -> [MGItem] {
        var offsets: [String: MGPoint] = [:]
        var vectorOverride: [String: (angle: Double, len: Double)] = [:]
        var rotate: [String: Double] = [:]
        var barValues: [String: [Double]] = [:]
        let t = max(0, time)
        switch scene.motion {
        case .none: break
        case .slide(let entries, let travel, let hold):
            let tau = min(t.truncatingRemainder(dividingBy: travel + hold), travel)
            for e in entries { offsets[e.id] = e.dir * (0.5 * e.accel * tau * tau) }
        case .orbit(let id, let center, let period, let rotating):
            if let ball = scene.item(id), let start = ball.pts.first {
                let rel = start - center, r = rel.length, phase0 = atan2(rel.y, rel.x)
                let phi = 2 * .pi * t / period
                offsets[id] = center + MGPoint(cos(phase0 + phi) * r, sin(phase0 + phi) * r, rel.z) - start
                for v in rotating { rotate[v] = phi * 180 / .pi }
            }
        case .projectile(let id, let vx, let vy0, let g, let flight, let visual, let hold, let vxID, let vyID, let vScale):
            let tau = min(t.truncatingRemainder(dividingBy: visual + hold), visual)
            let tp = tau / visual * flight
            // World-scaled position; the physical time mapping keeps the shape exact.
            offsets[id] = MGPoint(vx * tp, vy0 * tp - 0.5 * g * tp * tp)
            let ratio = vx != 0 ? (scene.motionVX ?? 0) / vx : 0
            if let vxID, let v = scene.item(vxID) { vectorOverride[vxID] = (0, v.n("len")) }
            if let vyID {
                // vy in m/s = (vy0 − g t) in world/s divided by the world scale; vector length uses the template's m/s scale.
                let vyPhysical = (vy0 - g * tp) * (ratio == 0 ? 1 : ratio)
                vectorOverride[vyID] = (vyPhysical >= 0 ? 90 : 270, abs(vyPhysical) * vScale)
            }
        case .oscillate(let id, let amplitude, let period, let energy, let bars, let vector, let length):
            let phase = 2 * .pi * t / period
            offsets[id] = MGPoint(amplitude - amplitude * cos(phase), 0)
            let split = MGPhysics.springSplit(energy: energy, phase: phase)
            if let bars { barValues[bars] = [split.kinetic, split.spring, energy] }
            if let vector {
                let c = cos(phase)
                vectorOverride[vector] = (c >= 0 ? 0 : 180, abs(c) < 1e-3 ? 0 : max(0.2, abs(c) * length))
            }
        }
        // Model-written bodies with `move` glide to their target and back (ease in-out), forever.
        for i in items where i.kind == .body && i.pts.count > 1 {
            let period = i.n("moveT", 1)
            let cycle = (t / period).truncatingRemainder(dividingBy: 2)
            let x = cycle <= 1 ? cycle : 2 - cycle
            let ease = x * x * (3 - 2 * x)
            offsets[i.id] = (offsets[i.id] ?? .zero) + (i.pts[1] - i.pts[0]) * ease
        }
        var centers: [String: MGPoint] = [:]
        var out = items.map { item -> MGItem in
            var i = item
            if let o = offsets[i.id], !i.pts.isEmpty { i.pts[0] = i.pts[0] + o }
            if i.kind == .body && i.pts.count > 1 { i.pts.removeLast() }  // the move target is not drawn
            if let body = scene.attachments[i.id], let o = offsets[body], !i.pts.isEmpty { i.pts[i.pts.count - 1] = i.pts[i.pts.count - 1] + o }
            if let v = barValues[i.id], v.count == i.bars.count { for k in v.indices { i.bars[k].value = v[k] } }
            if let r = rotate[i.id] { i.num["angle"] = i.n("angle") + r }
            if let o = vectorOverride[i.id] { i.num["angle"] = o.angle; i.num["len"] = o.len }
            if i.kind == .body || i.kind == .node { centers[i.id] = i.pts.first }
            return i
        }
        for k in out.indices where out[k].kind == .vector {
            if let on = out[k].ref, let c = centers[on] { out[k].pts = [c] }
        }
        // A moving function graph (`period`) is sampled again at its own loop time, so t runs 0…period and repeats.
        for k in out.indices where out[k].kind == .function {
            guard let period = out[k].num["period"], period.isFinite, period > 0 else { continue }
            out[k] = MGGraph.animated(out[k], at: t.truncatingRemainder(dividingBy: period))
        }
        return out
    }

    // MARK: patch blending

    /// Damped spring from 0 to 1 over about 0.8 s with a little overshoot. Game feel, not physics. A negative elapsed
    /// time (a frame stamped before the transition started) counts as 0, so the curve never runs backward past its start.
    public static func spring(_ elapsed: Double) -> Double {
        guard elapsed < 1.2 else { return 1 }   // first, so NaN still settles at 1
        let elapsed = blendProgress(elapsed)
        return 1 - exp(-6.5 * elapsed) * cos(8.5 * elapsed)
    }

    /// Lower clamp for blend progress and elapsed time: a value below 0 counts as the start. Callers check the upper
    /// bound first (`t < 1`, `elapsed < 1.2`), which also sends NaN to the settled result as before.
    static func blendProgress(_ t: Double) -> Double { max(0, t) }

    /// Geometry of `to`, starting from `from` where the same id and kind exist. New items come in as-is (they draw on).
    public static func blend(from: [MGItem], to: [MGItem], t: Double) -> [MGItem] {
        guard t < 1 else { return to }   // first, so NaN still returns the target
        let t = blendProgress(t)
        let old = Dictionary(from.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return to.map { target in
            guard let prev = old[target.id], prev.kind == target.kind else { return target }
            var i = target
            if prev.pts.count == target.pts.count { i.pts = zip(prev.pts, target.pts).map { $0.lerp($1, t) } }
            for (k, v) in target.num {
                // A table's or a vector field's row and column counts are structure, not geometry: never draw a
                // fractional grid.
                if target.kind == .table || target.kind == .field, k == "rows" || k == "cols" { continue }
                guard let p = prev.num[k] else { continue }
                if k == "angle" {
                    var d = (v - p).truncatingRemainder(dividingBy: 360); if d > 180 { d -= 360 }; if d < -180 { d += 360 }
                    i.num[k] = p + d * t
                } else { i.num[k] = p + (v - p) * t }
            }
            if prev.bars.count == target.bars.count { for k in i.bars.indices { i.bars[k].value = prev.bars[k].value + (target.bars[k].value - prev.bars[k].value) * t } }
            if prev.pointers.count == target.pointers.count {
                for k in i.pointers.indices { i.pointers[k].index = prev.pointers[k].index + (target.pointers[k].index - prev.pointers[k].index) * t }
            }
            if let a = prev.dir, let b = target.dir { i.dir = a.lerp(b, t) }
            return i
        }
    }
}

extension MGScene {
    /// Physical horizontal speed for the projectile template, so live vy can be shown in m/s.
    var motionVX: Double? { values["vx"]?.value }
}

extension MGTimeline {
    /// Length of one motion loop in seconds, or nil when nothing moves.
    public static func cycle(_ scene: MGScene) -> Double? {
        if let plan = scene.layer2d { return Double(plan.durationFrames) / 30 }
        switch scene.motion {
        case .slide(_, let travel, let hold): return travel + hold
        case .orbit(_, _, let period, _): return period
        case .projectile(_, _, _, _, _, let visual, let hold, _, _, _): return visual + hold
        case .oscillate(_, _, let period, _, _, _, _): return period
        case .none:
            // Body moves go there and back (2 × t); a moving graph repeats every `period`. The longest one is the loop.
            let loops = scene.items.compactMap { $0.num["moveT"].map { 2 * $0 } }
                + scene.items.filter { $0.kind == .function }.compactMap { $0.num["period"] }
            return loops.max()
        }
    }

    /// Where finite motion rests after `loops` cycles: the end of the last movement (a slide or a flight finished), not
    /// the start of the next loop. Periodic motion (orbit, spring) rests where it began, a full number of periods later.
    public static func restTime(_ scene: MGScene, loops: Int) -> Double? {
        guard let cycle = cycle(scene) else { return nil }
        let before = cycle * Double(max(1, loops) - 1)
        switch scene.motion {
        case .slide(_, let travel, _): return before + travel
        case .projectile(_, _, _, _, _, let visual, _, _, _, _): return before + visual
        default: return cycle * Double(max(1, loops))
        }
    }
}

/// The visible items of one (scene revision, step), kept between frames. `MGTimeline.items` applies every edit of steps
/// `0...step` again, and an edit of a `func` or `field` item checks the whole graph again, so a view that draws many
/// frames of one step asks this cache instead. `items` is a pure function of the scene and the step; the key is the
/// scene's `revision` and the step, so a cache may only be shared by scenes whose revisions name them uniquely.
/// `MGSceneController` stamps every scene it holds with a revision it never reuses and owns one cache for its views.
/// It keeps the last `capacity` steps read, least recently used out first, so views that share a controller and show
/// different steps (two boards, or a board changing step) each compute a step's items once, then every frame reuses
/// them. All entries share one revision: a read of another revision (a new scene) drops them all.
final class MGTimelineCache {
    /// Most steps kept. A board reads only its shown step every frame (a step change also reads the step it leaves,
    /// once), so two boards on one controller need 2; 4 leaves room for a third view, or for a board changing step,
    /// without evicting a step another board still draws every frame. Each entry is one array of at most
    /// `MGLimits.resolvedItems` (40) items, and an item the step's edits left alone shares its points, lists and values
    /// with the scene's own item (copy on write): 4 entries cost at most 160 item values plus the points of the items
    /// those steps' edits rebuilt (a `func` or `field` edit samples its graph again).
    static let capacity = 4
    private var revision: Int?
    /// Least recently used first.
    private var entries: [(step: Int, items: [MGItem])] = []
    /// How often `items` computed the items (tests).
    private(set) var computed = 0
    /// Steps kept now (tests).
    var kept: Int { entries.count }

    func items(_ scene: MGScene, step: Int) -> [MGItem] {
        if revision != scene.revision { entries.removeAll(); revision = scene.revision }
        if let i = entries.firstIndex(where: { $0.step == step }) {
            if i != entries.count - 1 { entries.append(entries.remove(at: i)) }
            return entries[entries.count - 1].items
        }
        let items = MGTimeline.items(scene, step: step)
        if entries.count == Self.capacity { entries.removeFirst() }
        entries.append((step, items))
        computed += 1
        return items
    }
}
