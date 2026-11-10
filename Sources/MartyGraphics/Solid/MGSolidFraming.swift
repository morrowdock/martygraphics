// SPDX-License-Identifier: Apache-2.0
import Foundation

// Camera framing of the render plan: which points a shot must show, and the camera that shows them inside the part
// of the view that no title or caption covers. Foundation only, deterministic (no dictionary or set iteration decides
// a result; parts are read in assembly order).

/// The framing rule of `marty-solid render` and of any host that shows a step (`MGSolidRenderer.frame(_:document:aspect:)`).
///
/// * **Subject first.** A shot with a subject frames the subject (`subjectParts`): the step's explicit `focus`, or else
///   its highlighted parts, its section parts and the parts that the labels and arrows it shows ride on, plus, in a
///   posed step, every chain the pose moves. The camera keeps the step's preset direction (`camera` plus `orbit`) and
///   takes the closest framing that keeps the subject whole inside the safe window together with every target the shot
///   draws (label anchors, pointer tips, arrow tails and heads): they fill `fill` of it. No touching context joins.
///   Context may be cut at the safe window's edges; the renderer clips the model to the safe window
///   (`MGSolidRenderer.render(width:height:clip:)`), so nothing is drawn under the title or caption band. An inferred
///   subject whose box diagonal is more than `focusShare` of the whole model's is a whole-model shot. The check report
///   measures each subject group against the floors (`subjectFill`, `subjectAreaShare`, `subjectExtentPixels`) and
///   warns `framing.subject.small.step.<n>` (`.beat.<n>`) with exact repairs. The unblocked-focus rule
///   (`clearView`) then tests the same subject, and keeps the main-rule camera (`mainRule`) for a still whose subject
///   camera would hide a label, pointer or arrow that the main-rule camera shows.
/// * **Whole model.** Other shots keep the bounding-sphere framing of earlier releases unless a part or an annotation
///   anchor would leave the safe window (the title band included); only then is the shot fitted like a focus.
/// * **Safe window.** The view minus the title band (shots with a title) and minus the caption band (shots with a
///   caption), as `MGSolidRenderPlan.bands(width:height:)` gives them. Neither band covers a solid part.
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
    /// Subject floors (docs/SOLID-3D.md, "Subject first"). The subject's projected extent fills at least this share of
    /// the safe window (on its larger axis, as `fill` measures it).
    public static let subjectFill = 0.25
    /// Each subject group (its subject parts in one unit) covers at least this share of the safe window's pixels.
    public static let subjectAreaShare = 0.005
    /// Each subject group's shorter screen extent is at least this many pixels at a frame 800 px high (scaled with the
    /// frame height: 24 px at 1280 × 800, 65 px at 3840 × 2160).
    public static let subjectExtentPixels = 24.0

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
        return context(doc, core: core, ghost: Set(s.ghost), hidden: doc.hiddenParts(step: step), params: params, stage: stage)
    }

    /// `core` with its touching context, in assembly order: every part not in `ghost` whose posed box touches the box of
    /// a `core` part (one level, within 0.5 % of the model's box diagonal). `focusParts` and the unblocked-focus rule
    /// (`clearView`) share this one rule. `hidden` (the view's hidden parts) are left out entirely.
    static func context(_ doc: MGSolidDocument, core: Set<String>, ghost: Set<String>, hidden: Set<String> = [], params: MGPoseParameters,
                        stage: MGTransform) -> [String] {
        let order = doc.assembly.parts.map(\.id).filter { !hidden.contains($0) }
        let samples = Samples(doc.assembly, ids: nil, exclude: hidden), pose = doc.assembly.pose(params)
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

        /// `exclude`: parts left out (the view's hidden parts).
        init(_ assembly: MGAssembly, ids: [String]?, exclude: Set<String> = []) {
            let wanted = ids.map(Set.init)
            let chosen = assembly.parts.filter { (wanted?.contains($0.id) ?? true) && !exclude.contains($0.id) }
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

        /// The points of each part in the render world (Y up) at a pose, in assembly order.
        func perPart(_ assembly: MGAssembly, _ params: MGPoseParameters, stage: MGTransform) -> [(id: String, points: [MGVec3])] {
            let pose = assembly.pose(params)
            return parts.map { id, local in
                let t = stage * (pose.world[id] ?? .identity)
                return (id, local.map(t.apply).filter { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite })
            }
        }

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
                let prims = MGSolidAnnotations.primitives(doc, id, params: params, sense: view.motionSense, step: view.step)
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

    // MARK: Subject

    /// The parts `view` draws solid, in assembly order: not hidden, at a view opacity of at least `blockingOpacity`.
    /// A step's `ghost` and the automatic ghosts are see-through context, not solid.
    public static func solidParts(_ doc: MGSolidDocument, view: MGSolidView) -> [String] {
        doc.assembly.parts.compactMap { p in
            let v = view.part(p.id)
            return !v.hidden && v.opacity >= blockingOpacity ? p.id : nil
        }
    }

    /// The subject of a shot (resolved part ids, assembly order, hidden parts left out): the step's explicit `focus`
    /// (`explicit`), or else the shot's highlighted parts, the step's section parts and the parts that the labels and
    /// arrows the shot shows ride on (a world-point anchor names no part). `moved`: for an inferred subject of a posed
    /// step, every other part the pose moves (the posed joints' parts and everything attached below them, found by
    /// comparing each part's world placement with and without the pose), so a raised arm stays in view with its jet.
    /// The moved chain joins the fit but is not measured by the subject floors. Empty for a shot with none of these.
    public static func subjectParts(_ doc: MGSolidDocument, shot s: MGSolidShot) -> (parts: [String], explicit: Bool, moved: [String]) {
        let step = s.step.flatMap { doc.steps.indices.contains($0) ? doc.steps[$0] : nil }
        let hidden = doc.hiddenParts(step: s.step)
        let order = doc.assembly.parts.map(\.id).filter { !hidden.contains($0) }
        if let f = step?.focus, !f.isEmpty { let want = Set(f); return (order.filter { want.contains($0) }, true, []) }
        var want = Set(s.highlight).union(step?.section?.parts ?? [])
        if s.showsAnnotations {
            let view = doc.view(step: s.step), a = doc.annotations
            for id in doc.checkedAnnotations(view, params: s.params) ?? [] where a.label(id) != nil || a.arrow(id) != nil {
                want.formUnion(MGSolidAnnotationEngine.anchors(a, id).compactMap(\.part))
            }
        }
        let parts = order.filter { want.contains($0) }
        guard !parts.isEmpty, !s.params.placements.isEmpty else { return (parts, false, []) }
        let posed = doc.assembly.pose(s.params).world
        let base = doc.assembly.pose(MGPoseParameters(input: s.params.input, explode: s.params.explode)).world
        let moved = order.filter { id in
            guard !want.contains(id), let p = posed[id], let q = base[id] else { return false }
            return zip(p.columnMajor, q.columnMajor).contains { abs($0 - $1) > 1e-6 * max(1, abs($0), abs($1)) }
        }
        return (parts, false, moved)
    }

    /// The subject's groups, the units of the floors: a unit (`MGSolidDocument.unitID`) whose every part is a subject
    /// part is one group (a highlighted or focused component instance); otherwise each subject part is its own group
    /// (a separately named part is measured on its own, never paid for by a larger part of its instance). Assembly order.
    public static func subjectGroups(_ doc: MGSolidDocument, _ parts: [String]) -> [(unit: String, parts: [String])] {
        let set = Set(parts)
        var out: [(unit: String, parts: [String])] = [], done = Set<String>()
        for p in parts {
            let u = MGSolidDocument.unitID(p)
            let unit = doc.unitParts(of: p).map(\.id)
            if unit.count > 1, unit.allSatisfy(set.contains) {
                if done.insert(u).inserted { out.append((u, unit.filter(set.contains))) }
            } else {
                out.append((p, [p]))
            }
        }
        return out
    }

    /// The projected box of `pts` with `camera` in normalised device units (width, height); nil when no point lies in
    /// front of the camera.
    static func projectedBox(_ pts: [MGVec3], camera c: MGSolidCamera, aspect: Double) -> (w: Double, h: Double)? {
        guard finite(c), aspect.isFinite, aspect > 0 else { return nil }
        let b = Basis(yaw: c.yaw, pitch: c.pitch), f = focal(c.fieldOfView), t = c.targetVector
        var lo = (x: Double.infinity, y: Double.infinity), hi = (x: -Double.infinity, y: -Double.infinity)
        for p in pts {
            let r = p - t, depth = c.distance + r.dot(b.fwd)
            guard depth > 0 else { continue }
            let x = r.dot(b.right) * f / aspect / depth, y = r.dot(b.up) * f / depth
            guard x.isFinite, y.isFinite else { continue }
            lo = (min(lo.x, x), min(lo.y, y)); hi = (max(hi.x, x), max(hi.y, y))
        }
        guard lo.x <= hi.x else { return nil }
        return (hi.x - lo.x, hi.y - lo.y)
    }

    /// The share of `window` that the projected extent of `pts` fills with `camera`, on the larger axis (the measure of
    /// `fill`: a fitted subject fills `fill`). 0 for no point in front of the camera.
    static func filled(_ pts: [MGVec3], camera c: MGSolidCamera, aspect: Double, window: Window) -> Double {
        guard let box = projectedBox(pts, camera: c, aspect: aspect) else { return 0 }
        let w = window.usable
        return max(box.w / (w.right - w.left), box.h / (w.top - w.bottom))
    }

    /// `c` moved back along its view line until its eye lies outside the posed box of every part of `view` that is
    /// solid (`solidParts`) and not in `subject`, by at least the near plane plus 10 %, so a subject inside a closed or
    /// hollow part (a core in a shell, a gear in a ring) is never framed from inside that part. A ghost is not solid,
    /// so ghosting the part lets the camera in. At most one move per part; deterministic (assembly order).
    static func outsideContext(_ c: MGSolidCamera, _ doc: MGSolidDocument, view: MGSolidView, params: MGPoseParameters,
                               subject: Set<String>, stage: MGTransform) -> MGSolidCamera {
        guard finite(c) else { return c }
        let pose = doc.assembly.pose(params)
        let boxes: [MGBounds] = doc.assembly.parts.compactMap { p in
            let v = view.part(p.id)
            guard !subject.contains(p.id), !v.hidden, v.opacity >= blockingOpacity else { return nil }
            let b = MGSolidFrames.worldBounds((v.cut?.mesh ?? p.mesh).bounds, stage * (pose.world[p.id] ?? .identity))
            return b.isEmpty ? nil : b
        }
        guard !boxes.isEmpty else { return c }
        var cam = c
        for _ in 0..<boxes.count {
            let back = (cam.position - cam.targetVector).normalized
            var moved = false
            for box in boxes {
                let near = nearPlane(distance: cam.distance) * 1.1
                let e = cam.position
                let lo = box.min - MGVec3(near, near, near), hi = box.max + MGVec3(near, near, near)
                guard e.x > lo.x, e.x < hi.x, e.y > lo.y, e.y < hi.y, e.z > lo.z, e.z < hi.z else { continue }
                // Leave the grown box along the view line, backwards (slab exit), then keep the near plane clear of it.
                var exit = Double.infinity
                for (pe, pb, l, h) in [(e.x, back.x, lo.x, hi.x), (e.y, back.y, lo.y, hi.y), (e.z, back.z, lo.z, hi.z)] where abs(pb) > 1e-12 {
                    exit = min(exit, ((pb > 0 ? h : l) - pe) / pb)
                }
                guard exit.isFinite, exit >= 0 else { continue }
                let d = cam.distance + exit
                cam.distance = max(cam.distance, (d + nearMinimum) / (1 - 1.1 * nearShare) + 1e-6)
                moved = true
            }
            if !moved { break }
        }
        return cam
    }

    // MARK: Crops

    /// The parts of `ids` (default: the solid parts of `view`, `solidParts`) that a still at `camera` cuts at pose
    /// `params`, for a view of width over height `aspect` whose safe window is `window`; assembly order. A part is cut
    /// when the view shows some of it and not all of it inside the window. The test reads every triangle of the posed
    /// mesh (a cut part's cut mesh) in camera space, without dividing by depth, so a face that crosses the view with
    /// every vertex outside it, or that straddles the near plane, counts: a triangle is in view unless all three
    /// vertices lie outside one of the five view planes (left, right, bottom, top, near), which is conservative (a
    /// triangle near a frustum corner may count); the part is outside the window when any vertex lies outside a window
    /// plane or nearer than the near plane (exact for a triangle, whose projection is convex). Context cut at the edges
    /// is allowed and clipped by the renderer; the render manifest lists it, and tests use it to prove that no subject
    /// part is ever cut.
    public static func cutParts(_ doc: MGSolidDocument, view: MGSolidView, params: MGPoseParameters, camera c: MGSolidCamera,
                                aspect: Double, window: Window, ids: [String]? = nil, stage: MGTransform = MGSolidStage.zUpToYUp) -> [String] {
        guard finite(c), aspect.isFinite, aspect > 0 else { return [] }
        let want = Set(ids ?? solidParts(doc, view: view))
        let w = window.usable, b = Basis(yaw: c.yaw, pitch: c.pitch), f = focal(c.fieldOfView), t = c.targetVector
        let near = nearPlane(distance: c.distance)
        let pose = doc.assembly.pose(params)
        var out: [String] = []
        for p in doc.assembly.parts where want.contains(p.id) {
            let pv = view.part(p.id)
            guard !pv.hidden else { continue }
            let mesh = pv.cut?.mesh ?? p.mesh
            let m = stage * (pose.world[p.id] ?? .identity)
            // Camera-space coordinates scaled so the view planes are |X| = Z and |Y| = Z.
            let q: [(x: Double, y: Double, z: Double)] = mesh.positions.map { v in
                let r = m.apply(v) - t
                return (r.dot(b.right) * f / aspect, r.dot(b.up) * f, c.distance + r.dot(b.fwd))
            }
            var outside = false
            for v in q where !(v.z >= near && v.x <= w.right * v.z && v.x >= w.left * v.z && v.y <= w.top * v.z && v.y >= w.bottom * v.z) {
                outside = true; break
            }
            guard outside else { continue }
            var shown = false
            for i in 0..<mesh.triangleCount {
                let (i0, i1, i2) = mesh.triangle(i)
                guard i0 < q.count, i1 < q.count, i2 < q.count else { continue }
                let tri = [q[i0], q[i1], q[i2]]
                if tri.allSatisfy({ $0.z < near }) || tri.allSatisfy({ $0.x > $0.z }) || tri.allSatisfy({ $0.x < -$0.z })
                    || tri.allSatisfy({ $0.y > $0.z }) || tri.allSatisfy({ $0.y < -$0.z }) { continue }
                shown = true; break
            }
            if shown { out.append(p.id) }
        }
        return out
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
    /// `hidden`: parts the shot's view does not draw (left out of the bounds).
    static func legacy(_ assembly: MGAssembly, _ s: MGSolidShot, yaw: Double, pitch: Double, aspect: Double, fieldOfView: Double,
                       stage: MGTransform, hidden: Set<String> = []) -> MGSolidCamera {
        var b = MGBounds.empty
        for e in [s.params.explode, 0, s.params.explode] {
            let pose = assembly.pose(MGPoseParameters(input: s.params.input, explode: e, placements: s.params.placements))
            for p in assembly.parts where !hidden.contains(p.id) {
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
        /// The shot's subject, fitted (`subjectParts`; with the annotation anchors when the subject keeps its floors).
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
        let hidden = doc.hiddenParts(step: s.step)
        let anchors = s.showsAnnotations ? annotationPoints(doc, view: view, params: s.params, stage: stage) : []
        let all = Samples(a, ids: nil, exclude: hidden).world(a, s.params, stage: stage) + anchors
        let subject = subjectParts(doc, shot: s)
        if !subject.parts.isEmpty {
            // The subject, its moved chain, and every target the shot draws: label anchors, pointer tips, arrow tails and
            // heads all lie inside the safe window (a framing never leaves a label "off view").
            let parts = Samples(a, ids: subject.parts + subject.moved).world(a, s.params, stage: stage) + anchors
            var sb = MGBounds.empty, wb = MGBounds.empty
            for p in parts { sb.include(p) }
            for p in all { wb.include(p) }
            // An explicit `focus` is always framed; an inferred subject that spans most of the model is a whole-model shot.
            if !sb.isEmpty, subject.explicit || sb.size.length <= focusShare * wb.size.length {
                let c = fit(parts, yaw: yaw, pitch: pitch, aspect: aspect, fieldOfView: fieldOfView, window: window)
                return (outsideContext(c, doc, view: view, params: s.params, subject: Set(subject.parts + subject.moved), stage: stage), .focus)
            }
        }
        let old = legacy(a, s, yaw: yaw, pitch: pitch, aspect: aspect, fieldOfView: fieldOfView, stage: stage, hidden: hidden)
        // The earlier framing stays when nothing is cut by the frame or covered by the title or caption band; otherwise
        // the shot is fitted inside the safe window.
        if contains(all, camera: old, aspect: aspect, window: window) { return (old, .model) }
        return (fit(all, yaw: yaw, pitch: pitch, aspect: aspect, fieldOfView: fieldOfView, window: window), .modelFitted)
    }

    /// The framing rule of main (a13f1f1) before subject-first framing, kept as the fallback of `clearView`: a step's
    /// focus (`focusParts`: its `focus`, or its highlight and section parts with their touching context) plus the shown
    /// annotation anchors, fitted when explicit or at most `focusShare` of the model; else the earlier bounding-sphere
    /// framing, which may reach into the title band (the renderer now clips it there), or the whole-model fit.
    static func mainRule(_ doc: MGSolidDocument, shot s: MGSolidShot, aspect: Double, fieldOfView: Double, titleBand: Double?,
                         captionBand: Double?, stage: MGTransform, direction override: (yaw: Double, pitch: Double)? = nil)
        -> (camera: MGSolidCamera, rule: Rule) {
        let aspect = aspect.isFinite && aspect > 0 ? aspect : 1.6, fieldOfView = fov(fieldOfView)
        let bands = MGSolidRenderPlan.bands(width: MGSolidRenderPlan.referenceHeight * aspect, height: MGSolidRenderPlan.referenceHeight)
        let window = Window(titleBand: titleBand ?? (s.title != nil ? bands.title : 0),
                            captionBand: captionBand ?? (s.caption != nil ? bands.caption : 0))
        let (yaw, pitch) = override ?? direction(s)
        let a = doc.assembly
        let view = doc.view(step: s.step)
        let hidden = doc.hiddenParts(step: s.step)
        let anchors = s.showsAnnotations ? annotationPoints(doc, view: view, params: s.params, stage: stage) : []
        let all = Samples(a, ids: nil, exclude: hidden).world(a, s.params, stage: stage) + anchors
        if let step = s.step {
            let ids = focusParts(doc, step: step, params: s.params, stage: stage)
            if !ids.isEmpty {
                let focus = Samples(a, ids: ids).world(a, s.params, stage: stage) + anchors
                var fb = MGBounds.empty, wb = MGBounds.empty
                for p in focus { fb.include(p) }
                for p in all { wb.include(p) }
                let explicit = doc.steps.indices.contains(step) && !doc.steps[step].focus.isEmpty
                if !fb.isEmpty, explicit || fb.size.length <= focusShare * wb.size.length {
                    return (fit(focus, yaw: yaw, pitch: pitch, aspect: aspect, fieldOfView: fieldOfView, window: window), .focus)
                }
            }
        }
        let old = legacy(a, s, yaw: yaw, pitch: pitch, aspect: aspect, fieldOfView: fieldOfView, stage: stage, hidden: hidden)
        var kept = window
        if s.file != "hero.png" { kept.top = 1 }
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
        let hidden = doc.hiddenParts(step: nil)
        let a = doc.assembly, samples = Samples(a, ids: nil, exclude: hidden), window = Window(titleBand: 0, captionBand: 0)
        let f = focal(fieldOfView)
        var cams: [MGSolidCamera] = [], k = 1.0
        for s in shots {
            let (yaw, pitch) = direction(s)
            let c = legacy(a, s, yaw: yaw, pitch: pitch, aspect: aspect, fieldOfView: fieldOfView, stage: stage, hidden: hidden)
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
