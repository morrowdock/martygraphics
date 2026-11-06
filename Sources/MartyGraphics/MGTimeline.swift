// SPDX-License-Identifier: Apache-2.0
import Foundation

/// Step state, motion frames and patch blending. Pure functions of (scene, step, time) so renderers and tests agree.
public enum MGTimeline {
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
        return out
    }

    // MARK: patch blending

    /// Damped spring from 0 to 1 over about 0.8 s with a little overshoot. Game feel, not physics.
    public static func spring(_ elapsed: Double) -> Double {
        guard elapsed < 1.2 else { return 1 }
        return 1 - exp(-6.5 * elapsed) * cos(8.5 * elapsed)
    }

    /// Geometry of `to`, starting from `from` where the same id and kind exist. New items come in as-is (they draw on).
    public static func blend(from: [MGItem], to: [MGItem], t: Double) -> [MGItem] {
        guard t < 1 else { return to }
        let old = Dictionary(from.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return to.map { target in
            guard let prev = old[target.id], prev.kind == target.kind else { return target }
            var i = target
            if prev.pts.count == target.pts.count { i.pts = zip(prev.pts, target.pts).map { $0.lerp($1, t) } }
            for (k, v) in target.num {
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
        switch scene.motion {
        case .slide(_, let travel, let hold): return travel + hold
        case .orbit(_, _, let period, _): return period
        case .projectile(_, _, _, _, _, let visual, let hold, _, _, _): return visual + hold
        case .oscillate(_, _, let period, _, _, _, _): return period
        case .none:
            let moves = scene.items.compactMap { $0.num["moveT"] }
            return moves.isEmpty ? nil : 2 * (moves.max() ?? 1)
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
