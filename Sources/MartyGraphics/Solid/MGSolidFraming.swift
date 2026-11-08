// SPDX-License-Identifier: Apache-2.0
import Foundation

// Camera framing of the render plan: which points a shot must show, and the camera that shows them inside the part
// of the view that no title or caption covers. Foundation only, deterministic (no dictionary or set iteration decides
// a result; parts are read in assembly order).

/// The framing rule of `marty-solid render` and of any host that shows a step (`MGSolidRenderer.frame(_:document:aspect:)`).
///
/// * **Focus.** A step frames its focus: the step's `focus` parts, or else its `highlight` and section parts with the
///   parts that touch them (`focusParts`), plus the anchors of the annotations the step shows. The camera keeps the step's preset direction (`camera`
///   plus `orbit`) and moves its target and distance so the focus fills `fill` of the safe window. An explicit `focus`
///   is always fitted; an inferred focus whose box is larger than `focusShare` of the whole model's box keeps the
///   whole-model rule.
/// * **Whole model.** Other shots keep the bounding-sphere framing of earlier releases unless a part or an annotation
///   anchor would leave the view or enter the caption band; only then is the shot fitted like a focus (inside the
///   safe window, title band included).
/// * **Safe window.** The view minus the title band (shots with a title) and minus the caption band (shots with a
///   caption), as `MGSolidRenderPlan.bands(width:height:)` gives them. The caption band never covers the model.
/// * **Loop.** Loop frames keep the earlier per-frame framing; when any frame would cut the model, every frame moves
///   back by the same factor, so the orbit does not jump.
///
/// The fit reads the posed mesh vertices (at most `pointBudget`; larger assemblies are sampled with a stride plus each
/// part's extreme points along 26 directions), not the box corners, so round parts are not framed by their corners.
public enum MGSolidFraming {
    /// Share of the safe window (each axis, about its centre) a fitted model fills, leaving room for labels.
    public static let fill = 0.88
    /// A focus frames a step only when its box diagonal is at most this share of the whole model's box diagonal.
    public static let focusShare = 0.75
    /// Share of the view a loop that had to move back fills.
    public static let loopFill = 0.94
    /// Most mesh points one framing reads.
    public static let pointBudget = 200_000
    /// The renderer's near plane: `max(nearMinimum, nearShare × distance)` from the camera (mm). The fit keeps every
    /// framed point at least 10 % beyond it, so a sub-millimetre detail is never cut by the near plane.
    public static let nearMinimum = 0.5, nearShare = 0.05
    /// The near-plane distance for a camera at `distance` from its target.
    public static func nearPlane(distance: Double) -> Double { max(nearMinimum, nearShare * distance) }

    /// A rectangle in normalised device coordinates (x right, y up, both −1...1).
    public struct Window: Equatable, Sendable {
        public var left: Double, right: Double, bottom: Double, top: Double
        public init(left: Double, right: Double, bottom: Double, top: Double) {
            self.left = left; self.right = right; self.bottom = bottom; self.top = top
        }
        /// The view minus a title band at the top and a caption band at the bottom (fractions of the height, each
        /// limited to 0...0.45 so the window always holds the view centre).
        public init(titleBand: Double, captionBand: Double) {
            func clamp(_ x: Double) -> Double { x.isFinite ? min(0.45, max(0, x)) : 0 }
            self.init(left: -1, right: 1, bottom: -1 + 2 * clamp(captionBand), top: 1 - 2 * clamp(titleBand))
        }
        /// This window when it is finite and holds the view centre strictly inside the view, else the whole view.
        var usable: Window {
            let v = [left, right, bottom, top]
            guard v.allSatisfy(\.isFinite), left >= -1, right <= 1, bottom >= -1, top <= 1, left < 0, right > 0, bottom < 0, top > 0 else {
                return Window(left: -1, right: 1, bottom: -1, top: 1)
            }
            return self
        }
        /// The window shrunk about its centre to `share` of its size.
        func scaled(_ share: Double) -> Window {
            let cx = (left + right) / 2, cy = (bottom + top) / 2
            return Window(left: cx + (left - cx) * share, right: cx + (right - cx) * share,
                          bottom: cy + (bottom - cy) * share, top: cy + (top - cy) * share)
        }
    }

    // MARK: Focus

    /// The parts a step frames at a pose (resolved ids, assembly order). A step's `focus` list is used as written.
    /// Without one, the step's `highlight` and section parts are taken with their context: every part the step does
    /// not ghost whose posed box touches the box of one of them (one level, within 0.5 % of the model's box diagonal).
    /// So a gear inside a gearbox brings its housing and the whole mechanism stays in view, while a cutaway that stands
    /// apart from the rest is framed on its own. Empty for a step without these lists, or an index outside the steps.
    public static func focusParts(_ doc: MGSolidDocument, step: Int, params: MGPoseParameters,
                                  stage: MGTransform = MGSolidStage.zUpToYUp) -> [String] {
        guard doc.steps.indices.contains(step) else { return [] }
        let s = doc.steps[step]
        let order = doc.assembly.parts.map(\.id)
        if !s.focus.isEmpty { let wanted = Set(s.focus); return order.filter { wanted.contains($0) } }
        let core = Set(s.highlight + (s.section?.parts ?? []))
        guard !core.isEmpty else { return [] }
        return context(doc, core: core, ghost: Set(s.ghost), params: params, stage: stage)
    }

    /// `core` with its touching context, in assembly order: every part not in `ghost` whose posed box touches the box of
    /// a `core` part (one level, within 0.5 % of the model's box diagonal). `focusParts` and the unblocked-focus rule
    /// (`clearView`) share this one rule.
    static func context(_ doc: MGSolidDocument, core: Set<String>, ghost: Set<String>, params: MGPoseParameters,
                        stage: MGTransform) -> [String] {
        let order = doc.assembly.parts.map(\.id)
        let samples = Samples(doc.assembly, ids: nil), pose = doc.assembly.pose(params)
        var boxes: [String: MGBounds] = [:], whole = MGBounds.empty
        for (id, local) in samples.parts {
            let t = stage * (pose.world[id] ?? .identity)
            var b = MGBounds.empty
            for p in local { b.include(t.apply(p)) }
            boxes[id] = b; whole = whole.union(b)
        }
        let tol = 0.005 * (whole.isEmpty ? 0 : whole.size.length)
        func touches(_ a: MGBounds, _ b: MGBounds) -> Bool {
            !a.isEmpty && !b.isEmpty && a.min.x <= b.max.x + tol && b.min.x <= a.max.x + tol && a.min.y <= b.max.y + tol
                && b.min.y <= a.max.y + tol && a.min.z <= b.max.z + tol && b.min.z <= a.max.z + tol
        }
        let coreBoxes = order.filter { core.contains($0) }.compactMap { boxes[$0] }
        return order.filter { id in
            core.contains(id) || (!ghost.contains(id) && coreBoxes.contains { touches($0, boxes[id] ?? .empty) })
        }
    }

    // MARK: Points

    /// Part-local sample points: every vertex, or (over `pointBudget`) a stride sample plus each part's extreme
    /// vertices along 26 directions.
    struct Samples {
        var parts: [(id: String, local: [MGVec3])]

        init(_ assembly: MGAssembly, ids: [String]?) {
            let wanted = ids.map(Set.init)
            let chosen = assembly.parts.filter { wanted?.contains($0.id) ?? true }
            let total = chosen.reduce(0) { $0 + $1.mesh.positions.count }
            let stride = max(1, (total + MGSolidFraming.pointBudget - 1) / MGSolidFraming.pointBudget)
            parts = chosen.map { p in
                let v = p.mesh.positions
                guard stride > 1, !v.isEmpty else { return (p.id, v) }
                var out = Swift.stride(from: 0, to: v.count, by: stride).map { v[$0] }
                for d in Samples.directions {
                    var best = v[0], score = best.dot(d)
                    for q in v { let s = q.dot(d); if s > score { score = s; best = q } }
                    out.append(best)
                }
                return (p.id, out)
            }
        }

        /// The 26 directions of a cube's faces, edges and corners.
        static let directions: [MGVec3] = {
            var out: [MGVec3] = []
            for x in -1...1 { for y in -1...1 { for z in -1...1 where x != 0 || y != 0 || z != 0 {
                out.append(MGVec3(Double(x), Double(y), Double(z)).normalized)
            } } }
            return out
        }()

        /// The points in the render world (Y up) at a pose.
        func world(_ assembly: MGAssembly, _ params: MGPoseParameters, stage: MGTransform) -> [MGVec3] {
            let pose = assembly.pose(params)
            var out: [MGVec3] = []
            for (id, local) in parts {
                let t = stage * (pose.world[id] ?? .identity)
                for p in local {
                    let q = t.apply(p)
                    if q.x.isFinite, q.y.isFinite, q.z.isFinite { out.append(q) }
                }
            }
            return out
        }
    }

    /// Render-world anchor points of the annotations a view shows at a pose (none when the engine did not check the
    /// view): a label's anchor, an arrow's two ends (a turn arrow's arc ends), a dimension's points.
    public static func annotationPoints(_ doc: MGSolidDocument, view: MGSolidView, params: MGPoseParameters,
                                        stage: MGTransform = MGSolidStage.zUpToYUp) -> [MGVec3] {
        guard let shown = doc.checkedAnnotations(view, params: params), !shown.isEmpty else { return [] }
        let a = doc.annotations, pose = doc.assembly.pose(params)
        var out: [MGVec3] = []
        for id in shown {
            if let r = a.arrow(id) {
                let prims = MGSolidAnnotations.primitives(doc, id, params: params, sense: view.motionSense)
                guard !prims.isEmpty else { continue }
                let end = r.style == .turn && prims.count > MGSolidAnnotations.arcChords ? prims[MGSolidAnnotations.arcChords].end
                    : prims[min(1, prims.count - 1)].end
                out += [prims[0].start, end].map(stage.apply)
            } else {
                out += MGSolidAnnotationEngine.anchors(a, id).map { stage.apply($0.world(pose)) }
            }
        }
        return out.filter { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }
    }

    // MARK: Projection

    struct Basis {
        let right: MGVec3, up: MGVec3, fwd: MGVec3
        /// The camera axes of `MGSolidCamera` (and `MGSolidRenderer.project`) for a yaw and pitch.
        init(yaw: Double, pitch: Double) {
            let c = MGSolidCamera(target: .zero, yaw: yaw, pitch: pitch, distance: 1)
            fwd = (c.targetVector - c.position).normalized
            right = fwd.cross(c.up).normalized
            up = right.cross(fwd)
        }
    }

    static func focal(_ fieldOfView: Double) -> Double { 1 / tan(fov(fieldOfView) * .pi / 360) }
    /// A usable vertical field of view: 1...170 degrees, else 30.
    static func fov(_ x: Double) -> Double { x.isFinite && x >= 1 && x <= 170 ? x : 30 }
    static func finite(_ c: MGSolidCamera) -> Bool { c.target.allSatisfy(\.isFinite) && c.distance.isFinite && c.distance > 0 }

    /// The smallest camera distance from `target` that keeps every point inside `w` and in front of the near plane.
    static func distance(_ pts: [MGVec3], target: MGVec3, basis b: Basis, focal f: Double, aspect: Double, window w: Window) -> Double {
        var d = 0.0
        for p in pts {
            let r = p - target
            let x = r.dot(b.right) * f / aspect, y = r.dot(b.up) * f, z = r.dot(b.fwd)
            if x > 0 { d = max(d, x / w.right - z) } else if x < 0 { d = max(d, x / w.left - z) }
            if y > 0 { d = max(d, y / w.top - z) } else if y < 0 { d = max(d, y / w.bottom - z) }
            // Depth d + z must stay 10 % beyond the renderer's near plane, max(nearMinimum, nearShare × d).
            d = max(d, 1.1 * nearMinimum - z, -z / (1 - 1.1 * nearShare))
        }
        return d
    }

    /// True when every point projects inside `w` with `camera`.
    public static func contains(_ pts: [MGVec3], camera c: MGSolidCamera, aspect: Double, window w: Window) -> Bool {
        guard finite(c), aspect.isFinite, aspect > 0 else { return false }
        let b = Basis(yaw: c.yaw, pitch: c.pitch), f = focal(c.fieldOfView), t = c.targetVector
        let tol = 1e-9
        for p in pts {
            let r = p - t
            let depth = c.distance + r.dot(b.fwd)
            // A point nearer than the renderer's near plane is cut, so it is not in view.
            guard depth >= nearPlane(distance: c.distance) else { return false }
            let x = r.dot(b.right) * f / aspect / depth, y = r.dot(b.up) * f / depth
            guard x.isFinite, y.isFinite else { return false }
            if x > w.right + tol || x < w.left - tol || y > w.top + tol || y < w.bottom - tol { return false }
        }
        return true
    }

    /// The camera from `yaw` and `pitch` that fits every point into `fill` of `window`, centred in it.
    public static func fit(_ pts: [MGVec3], yaw: Double, pitch: Double, aspect: Double, fieldOfView: Double = 30,
                           window: Window, fill: Double = MGSolidFraming.fill) -> MGSolidCamera {
        let finite = pts.filter { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }
        let yaw = yaw.isFinite ? yaw : 32, pitch = pitch.isFinite ? min(89, max(-89, pitch)) : 28, fieldOfView = fov(fieldOfView)
        guard !finite.isEmpty, aspect.isFinite, aspect > 0 else {
            return MGSolidCamera.framing(.empty, yaw: yaw, pitch: pitch, aspect: aspect.isFinite && aspect > 0 ? aspect : 1.6, fieldOfView: fieldOfView)
        }
        let share = fill.isFinite ? min(1, max(0.1, fill)) : MGSolidFraming.fill
        let b = Basis(yaw: yaw, pitch: pitch), f = focal(fieldOfView), w = window.usable.scaled(share)
        var box = MGBounds.empty
        for p in finite { box.include(p) }
        let floor = max(1e-3, box.radius * 1e-3)
        var t = box.center
        // Centre the projected extent in the window: four fixed passes (the perspective shift is small after one).
        for _ in 0..<4 {
            let d = max(floor, distance(finite, target: t, basis: b, focal: f, aspect: aspect, window: w))
            var lo = (x: Double.infinity, y: Double.infinity), hi = (x: -Double.infinity, y: -Double.infinity)
            for p in finite {
                let r = p - t
                let depth = d + r.dot(b.fwd)
                guard depth > 0 else { continue }
                let x = r.dot(b.right) * f / aspect / depth, y = r.dot(b.up) * f / depth
                lo = (min(lo.x, x), min(lo.y, y)); hi = (max(hi.x, x), max(hi.y, y))
            }
            guard lo.x <= hi.x else { break }
            let dx = (w.left + w.right) / 2 - (lo.x + hi.x) / 2, dy = (w.bottom + w.top) / 2 - (lo.y + hi.y) / 2
            // Moving the target by s along `right` moves a point at the target depth by -s f / (aspect d) in x.
            t = t - b.right * (dx * aspect * d / f) - b.up * (dy * d / f)
        }
        let d = max(floor, distance(finite, target: t, basis: b, focal: f, aspect: aspect, window: w))
        return MGSolidCamera(target: t, yaw: yaw, pitch: pitch, distance: d, fieldOfView: fieldOfView)
    }

    // MARK: Shots

    /// The bounding-sphere framing of earlier releases: the union of the posed boxes at the shot's explode value and
    /// at 0, with the shot's margin.
    static func legacy(_ assembly: MGAssembly, _ s: MGSolidShot, yaw: Double, pitch: Double, aspect: Double, fieldOfView: Double,
                       stage: MGTransform) -> MGSolidCamera {
        var b = MGBounds.empty
        for e in [s.params.explode, 0, s.params.explode] {
            let pose = assembly.pose(MGPoseParameters(input: s.params.input, explode: e))
            for p in assembly.parts {
                let t = stage * (pose.world[p.id] ?? .identity)
                for c in p.mesh.bounds.corners { b.include(t.apply(c)) }
            }
        }
        return MGSolidCamera.framing(b, yaw: yaw, pitch: pitch, aspect: aspect, fieldOfView: fieldOfView, margin: s.margin)
    }

    static func direction(_ s: MGSolidShot) -> (yaw: Double, pitch: Double) {
        let p = MGSolidCamera.presets[s.preset] ?? MGSolidCamera.presets["hero"]!
        return (p.yaw + s.orbit, p.pitch)
    }

    /// Which rule framed a still (`marty-solid render` writes it into each still's manifest record).
    public enum Rule: String, Equatable, Sendable {
        /// The step's focus, fitted.
        case focus
        /// The whole model with the bounding-sphere framing of earlier releases (nothing left the safe window).
        case model
        /// The whole model, fitted because the earlier framing cut a part or an annotation anchor.
        case modelFitted
    }

    /// The camera of one still: the focus rule for a step with a focus, else the whole-model rule. `titleBand` and
    /// `captionBand` default to `MGSolidRenderPlan.bands` at the reference size for a shot with a title or caption.
    public static func camera(_ doc: MGSolidDocument, shot s: MGSolidShot, aspect: Double, fieldOfView: Double = 30,
                              titleBand: Double? = nil, captionBand: Double? = nil,
                              stage: MGTransform = MGSolidStage.zUpToYUp) -> MGSolidCamera {
        framing(doc, shot: s, aspect: aspect, fieldOfView: fieldOfView, titleBand: titleBand, captionBand: captionBand, stage: stage).camera
    }

    /// `camera(_:shot:aspect:…)` and the rule that chose it.
    public static func framing(_ doc: MGSolidDocument, shot s: MGSolidShot, aspect: Double, fieldOfView: Double = 30,
                               titleBand: Double? = nil, captionBand: Double? = nil,
                               stage: MGTransform = MGSolidStage.zUpToYUp) -> (camera: MGSolidCamera, rule: Rule) {
        let r = choose(doc, shot: s, aspect: aspect, fieldOfView: fieldOfView, titleBand: titleBand, captionBand: captionBand, stage: stage)
        if finite(r.camera) { return r }
        // Only a shot built in code with non-finite numbers gets here: frame a unit cube rather than return NaN.
        let (yaw, pitch) = direction(s)
        return (MGSolidCamera.framing(.empty, yaw: yaw.isFinite ? yaw : 32, pitch: pitch, aspect: 1.6), .modelFitted)
    }

    static func choose(_ doc: MGSolidDocument, shot s: MGSolidShot, aspect: Double, fieldOfView: Double, titleBand: Double?,
                       captionBand: Double?, stage: MGTransform, direction override: (yaw: Double, pitch: Double)? = nil)
        -> (camera: MGSolidCamera, rule: Rule) {
        let aspect = aspect.isFinite && aspect > 0 ? aspect : 1.6, fieldOfView = fov(fieldOfView)
        let bands = MGSolidRenderPlan.bands(width: MGSolidRenderPlan.referenceHeight * aspect, height: MGSolidRenderPlan.referenceHeight)
        let window = Window(titleBand: titleBand ?? (s.title != nil ? bands.title : 0),
                            captionBand: captionBand ?? (s.caption != nil ? bands.caption : 0))
        let (yaw, pitch) = override ?? direction(s)
        let a = doc.assembly
        let view = doc.view(step: s.step)
        let anchors = s.showsAnnotations ? annotationPoints(doc, view: view, params: s.params, stage: stage) : []
        let all = Samples(a, ids: nil).world(a, s.params, stage: stage) + anchors
        if let step = s.step {
            let ids = focusParts(doc, step: step, params: s.params, stage: stage)
            if !ids.isEmpty {
                let focus = Samples(a, ids: ids).world(a, s.params, stage: stage) + anchors
                var fb = MGBounds.empty, wb = MGBounds.empty
                for p in focus { fb.include(p) }
                for p in all { wb.include(p) }
                // An explicit `focus` is always framed exactly; only inferred context (highlight, section) falls back
                // to the whole model when it spans most of it.
                let explicit = doc.steps.indices.contains(step) && !doc.steps[step].focus.isEmpty
                if !fb.isEmpty, explicit || fb.size.length <= focusShare * wb.size.length {
                    return (fit(focus, yaw: yaw, pitch: pitch, aspect: aspect, fieldOfView: fieldOfView, window: window), .focus)
                }
            }
        }
        let old = legacy(a, s, yaw: yaw, pitch: pitch, aspect: aspect, fieldOfView: fieldOfView, stage: stage)
        // The earlier framing stays when nothing is cut by the frame or covered by the caption band. It may reach into
        // the title band (title text over the model, as in earlier releases); a fitted camera keeps that band free.
        var kept = window
        kept.top = 1
        if contains(all, camera: old, aspect: aspect, window: kept) { return (old, .model) }
        return (fit(all, yaw: yaw, pitch: pitch, aspect: aspect, fieldOfView: fieldOfView, window: window), .modelFitted)
    }

    /// The cameras of a loop (frames without title or caption): each frame's earlier framing, all moved back by the
    /// one factor that keeps the model inside every frame (1 when nothing was cut).
    public static func loopCameras(_ doc: MGSolidDocument, shots: [MGSolidShot], aspect: Double, fieldOfView: Double = 30,
                                   stage: MGTransform = MGSolidStage.zUpToYUp) -> [MGSolidCamera] {
        loopFraming(doc, shots: shots, aspect: aspect, fieldOfView: fieldOfView, stage: stage).cameras
    }

    /// `loopCameras` and the factor every frame moved back by (1: the earlier framing kept every frame whole).
    public static func loopFraming(_ doc: MGSolidDocument, shots: [MGSolidShot], aspect: Double, fieldOfView: Double = 30,
                                   stage: MGTransform = MGSolidStage.zUpToYUp) -> (cameras: [MGSolidCamera], scale: Double) {
        let aspect = aspect.isFinite && aspect > 0 ? aspect : 1.6, fieldOfView = fov(fieldOfView)
        let a = doc.assembly, samples = Samples(a, ids: nil), window = Window(titleBand: 0, captionBand: 0)
        let f = focal(fieldOfView)
        var cams: [MGSolidCamera] = [], k = 1.0
        for s in shots {
            let (yaw, pitch) = direction(s)
            let c = legacy(a, s, yaw: yaw, pitch: pitch, aspect: aspect, fieldOfView: fieldOfView, stage: stage)
            cams.append(c)
            let pts = samples.world(a, s.params, stage: stage)
            guard !contains(pts, camera: c, aspect: aspect, window: window), c.distance > 0 else { continue }
            let need = distance(pts, target: c.targetVector, basis: Basis(yaw: yaw, pitch: pitch), focal: f, aspect: aspect,
                                window: window.scaled(loopFill))
            k = max(k, need / c.distance)
        }
        guard k > 1, k.isFinite else { return (cams, 1) }
        return (cams.map { var c = $0; c.distance *= k; return c }, k)
    }
}
