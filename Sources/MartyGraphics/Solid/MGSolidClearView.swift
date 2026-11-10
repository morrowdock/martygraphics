// SPDX-License-Identifier: Apache-2.0
import Foundation

// The unblocked-focus rule: after a step is framed on its focus, other parts must not hide the focus from the camera.
// Parts in the way are drawn as automatic ghosts; when a part of the focus context itself is in the way, a fixed list of
// other view directions is tried. Also the story rule that cuts instead of moving the camera through a part.
// Foundation only, deterministic: parts in assembly order, samples by fixed strides, a fixed direction list and a fixed
// triangle-test budget.

/// One shot after the unblocked-focus rule (`MGSolidFraming.clearView`): its camera, the view direction it uses, the
/// parts drawn as automatic ghosts, and how much of the focus is still hidden.
public struct MGSolidClearView: Equatable, Sendable {
    /// The view direction of the shot: the step's own direction (preset plus `orbit`), or one of the fixed alternatives
    /// (`MGSolidFraming.alternatives`).
    public enum Direction: String, Equatable, Sendable, CaseIterable {
        /// The step's preset and `orbit`, unchanged.
        case preset
        /// Yaw + 180°: the other side of the focus.
        case opposite
        /// Yaw + 90° and yaw − 90°.
        case quarterLeft, quarterRight
        /// Pitch 60° (10° when the preset already looks down from 45° or more), same yaw.
        case raised
    }

    public var camera: MGSolidCamera
    public var rule: MGSolidFraming.Rule
    /// True when the rule ran: the shot shows a step framed on its focus (`rule == .focus`) with sample points.
    public var tested: Bool
    public var direction: Direction
    /// Parts drawn at `MGSolidView.ghostOpacity` in this shot only, in assembly order.
    public var autoGhost: [String]
    /// Focus sample points tested, and those still hidden in the final view (after the automatic ghosts).
    public var samples: Int
    public var occludedSamples: Int
    /// For a step whose section cuts a focus part: true when the camera is on the cut-away side of that part's plane,
    /// so the cut face and the inside are seen; nil for a step without such a cut.
    public var facesCut: Bool?
    /// The force and flow arrows this shot does not draw (`MGSolidFraming.arrowDrops`): the camera cannot see the unit
    /// (component instance) each one's tail rides on. Set for every shot, whatever its rule.
    public var arrowDrops: [MGArrowDrop] = []

    public init(camera: MGSolidCamera, rule: MGSolidFraming.Rule, tested: Bool = false, direction: Direction = .preset,
                autoGhost: [String] = [], samples: Int = 0, occludedSamples: Int = 0, facesCut: Bool? = nil) {
        self.camera = camera; self.rule = rule; self.tested = tested; self.direction = direction; self.autoGhost = autoGhost
        self.samples = max(0, samples); self.occludedSamples = min(max(0, occludedSamples), max(0, samples)); self.facesCut = facesCut
    }

    /// Share of the tested focus samples still hidden (0 when none was tested).
    public var occluded: Double { samples > 0 ? Double(occludedSamples) / Double(samples) : 0 }
    /// True when at most `MGSolidFraming.clearShare` of the focus samples stay hidden.
    public var clear: Bool { occluded <= MGSolidFraming.clearShare }
    /// True when the view is clear and, for a section step, faces the cut (`facesCut` is not false).
    public var accepted: Bool { clear && facesCut != false }

    /// `base` (the step's view) with the automatic ghosts added and the dropped arrows left out
    /// (`MGSolidView.arrowDrops`). Cuts and the legend are unchanged.
    public func view(_ base: MGSolidView) -> MGSolidView {
        var v = base.ghosting(autoGhost)
        v.arrowDrops = arrowDrops
        return v
    }

    /// Manifest fields of a shot: for a tested shot `{"autoGhost": [ids], "occluded": share, "focusSamples": n,
    /// "view": direction, "facesCut"?: bool}`, and for any shot that drops an arrow `"arrowDrops": [{"id", "part",
    /// "by"}]`; empty otherwise.
    public var manifestFields: [String: MGJSON] {
        var o: [String: MGJSON] = [:]
        if tested {
            o = ["autoGhost": .array(autoGhost.map { .string($0) }), "occluded": .number(occluded),
                 "focusSamples": .number(Double(samples)), "view": .string(direction.rawValue)]
            if let f = facesCut { o["facesCut"] = .bool(f) }
        }
        if !arrowDrops.isEmpty {
            o["arrowDrops"] = .array(arrowDrops.map { .object(["id": .string($0.id), "part": .string($0.part), "by": .string($0.by)]) })
        }
        return o
    }
}

extension MGSolidView {
    /// This view with `ids` drawn see-through at `ghostOpacity` (a part already fainter keeps its own opacity). Ids
    /// that name no part are ignored. Cuts, light, annotations and the fingerprint are unchanged.
    public func ghosting(_ ids: [String]) -> MGSolidView {
        var v = self
        for id in ids where v.parts[id] != nil {
            let faint = min(v.part(id).opacity, MGSolidView.ghostOpacity)
            v.parts[id]?.opacity = faint
        }
        return v
    }
}

extension MGSolidFraming {
    /// Focus sample points one shot tests (docs/SOLID-3D.md, "Unblocked focus").
    public static let occlusionSamples = 48
    /// A part outside the focus context that hides more than this share of the samples becomes an automatic ghost.
    public static let ghostShare = 0.05
    /// A view is clear when at most this share of the samples stays hidden; an alternative direction must be clear.
    public static let clearShare = 0.10
    /// The step's own direction stays while at most this share of the samples stays hidden after the automatic ghosts
    /// (and, for a section step, it faces the cut): the author's direction is replaced only when much of the focus is
    /// hidden.
    public static let keepShare = 0.30
    /// Triangle tests one view direction may spend; samples after the budget are not tested (fewer `samples`).
    public static let occlusionTests = 3_000_000
    /// A part hides samples only when the view shows it at this opacity or more (as for annotation occlusion).
    public static let blockingOpacity = 0.5
    /// A section view faces its cut when the cosine between its view direction and the cut plane's normal is at least
    /// this (about 75°).
    public static let cutFacing = 0.25
    /// The alternative directions, in the order they are tried.
    public static let alternatives: [MGSolidClearView.Direction] = [.opposite, .quarterLeft, .quarterRight, .raised]

    /// The yaw and pitch of `direction` from the step's own yaw and pitch.
    public static func direction(_ d: MGSolidClearView.Direction, yaw: Double, pitch: Double) -> (yaw: Double, pitch: Double) {
        switch d {
        case .preset: return (yaw, pitch)
        case .opposite: return (yaw + 180, pitch)
        case .quarterLeft: return (yaw + 90, pitch)
        case .quarterRight: return (yaw - 90, pitch)
        case .raised: return (yaw, pitch >= 45 ? 10 : 60)
        }
    }

    /// The camera of one still with the unblocked-focus rule. The shot is first framed as `framing(_:shot:aspect:…)`
    /// frames it. Only a step framed on its focus (`rule == .focus`) is tested:
    ///
    /// 1. Sample points: at most `occlusionSamples` triangle centroids of the focus parts (a cut part gives its capped
    ///    cut mesh), split evenly over the parts, by a fixed stride, posed at the shot's pose.
    /// 2. From the camera, a segment runs to each sample. A sample is hidden by a part when the part's triangles cross the
    ///    segment before the first focus surface on it. Only parts the step view shows at `blockingOpacity` or more
    ///    hide samples. The focus group never hides samples: the focus parts, every part attached below one of them
    ///    (`parent` chain), and every part whose posed box lies inside the focus parts' box (the inside of a cutaway).
    ///    A part does not hide a sample that lies inside it (an odd number of crossings of its surface up to the
    ///    sample, as for a pin in its hole): no direction would show that sample past it.
    /// 3. Every part outside the focus context that hides more than `ghostShare` of the samples is drawn as an automatic
    ///    ghost (`autoGhost`). The focus context is the focus group, plus, for a step with an explicit `focus` list, the
    ///    parts whose posed box touches a focus part (the same touch rule as `focusParts`).
    /// 4. The step's own direction stays when at most `keepShare` of the samples stay hidden after the ghosts and, when
    ///    the step's section cuts a focus-group part, the view faces the cut (`facesCut`): the camera on the cut-away
    ///    side of the first such part's plane (assembly order), looking within about 75° of its normal (`cutFacing`), so
    ///    the cut face is seen, not the outside of the kept half.
    /// 5. Otherwise the `alternatives` are tried in order, each framed on the same focus, and the first that is clear
    ///    (at most `clearShare` hidden) and faces the cut is taken with its own automatic ghosts. When none is, the first
    ///    clear one is taken (the preset first); when none is clear, the step's own direction stays.
    ///
    /// Last, for every shot (any rule), the arrow drop rule runs at the chosen camera (`arrowDrops`).
    public static func clearView(_ doc: MGSolidDocument, shot s: MGSolidShot, aspect: Double, fieldOfView: Double = 30,
                                 titleBand: Double? = nil, captionBand: Double? = nil,
                                 stage: MGTransform = MGSolidStage.zUpToYUp) -> MGSolidClearView {
        clearView(doc, shot: s, aspect: aspect, fieldOfView: fieldOfView, titleBand: titleBand, captionBand: captionBand, stage: stage, drops: true)
    }

    /// `clearView`, with the arrow drop rule only when `drops` (an explainer beat takes its drops from its canonical
    /// framing instead, `MGExplainerFrame.beatArrowDrops`).
    static func clearView(_ doc: MGSolidDocument, shot s: MGSolidShot, aspect: Double, fieldOfView: Double = 30,
                          titleBand: Double?, captionBand: Double?, stage: MGTransform, drops: Bool) -> MGSolidClearView {
        var c = clearCamera(doc, shot: s, aspect: aspect, fieldOfView: fieldOfView, titleBand: titleBand, captionBand: captionBand, stage: stage)
        if drops { c.arrowDrops = arrowDrops(doc, shot: s, camera: c.camera, autoGhost: c.autoGhost, aspect: aspect, stage: stage) }
        return c
    }

    /// The force and flow arrows a shot at `camera` does not draw (`MGSolidDocument.arrowDrops`): the shot's step view
    /// (`MGSolidDocument.view(step:)`) with its automatic ghosts, at the shot's pose, in a view of the shot's aspect.
    public static func arrowDrops(_ doc: MGSolidDocument, shot s: MGSolidShot, camera: MGSolidCamera, autoGhost: [String], aspect: Double,
                                  stage: MGTransform = MGSolidStage.zUpToYUp) -> [MGArrowDrop] {
        guard !doc.annotations.isEmpty, s.step.map({ doc.steps.indices.contains($0) }) ?? true else { return [] }
        let view = doc.view(step: s.step).ghosting(autoGhost)
        guard doc.annotations.arrows.contains(where: { view.annotations.contains($0.id) }) else { return [] }
        let a = aspect.isFinite && aspect > 0 ? aspect : 1.6
        return doc.arrowDrops(MGAnnotationAnchorView(view: view, params: s.params, camera: camera, width: 800 * a, height: 800,
                                                     step: s.step, beat: nil, stage: stage))
    }

    static func clearCamera(_ doc: MGSolidDocument, shot s: MGSolidShot, aspect: Double, fieldOfView: Double,
                            titleBand: Double?, captionBand: Double?, stage: MGTransform) -> MGSolidClearView {
        let first = framing(doc, shot: s, aspect: aspect, fieldOfView: fieldOfView, titleBand: titleBand, captionBand: captionBand, stage: stage)
        guard first.rule == .focus, let step = s.step, doc.steps.indices.contains(step) else {
            return MGSolidClearView(camera: first.camera, rule: first.rule)
        }
        let probe = OcclusionProbe(doc, step: step, params: s.params, stage: stage)
        guard !probe.samples.isEmpty else { return MGSolidClearView(camera: first.camera, rule: first.rule) }
        func result(_ camera: MGSolidCamera, _ d: MGSolidClearView.Direction) -> MGSolidClearView {
            let e = probe.evaluate(camera)
            return MGSolidClearView(camera: camera, rule: .focus, tested: true, direction: d, autoGhost: e.ghost, samples: e.samples,
                                    occludedSamples: e.occluded, facesCut: probe.facesCut(camera))
        }
        let preset = result(first.camera, .preset)
        if preset.occluded <= keepShare && preset.facesCut != false { return preset }
        let base = direction(s)
        let aspect = aspect.isFinite && aspect > 0 ? aspect : 1.6
        var tried = [preset]
        for d in alternatives {
            let (yaw, pitch) = direction(d, yaw: base.yaw, pitch: base.pitch)
            let r = choose(doc, shot: s, aspect: aspect, fieldOfView: fov(fieldOfView), titleBand: titleBand, captionBand: captionBand,
                           stage: stage, direction: (yaw, min(89, max(-89, pitch))))
            guard r.rule == .focus, finite(r.camera) else { continue }
            let v = result(r.camera, d)
            if v.accepted { return v }
            tried.append(v)
        }
        return tried.first(where: \.clear) ?? preset
    }

    /// The parts, samples and focus context of one tested step, in the kernel frame (Z up, mm).
    struct OcclusionProbe {
        struct Solid { let id: String; let mesh: MGMesh; let inverse: MGTransform; let bounds: MGBounds; let focus: Bool; let group: Bool }
        var solids: [Solid] = []
        var samples: [MGVec3] = []
        var context: Set<String> = []
        /// The cut plane of the first cut focus-group part, in the kernel world at the shot's pose.
        var cut: (normal: MGVec3, point: MGVec3)?
        var tol = 0.0
        let stage: MGTransform

        init(_ doc: MGSolidDocument, step: Int, params: MGPoseParameters, stage: MGTransform) {
            self.stage = stage
            let s = doc.steps[step], view = doc.view(step: step), pose = doc.assembly.pose(params)
            let focus = MGSolidFraming.focusParts(doc, step: step, params: params, stage: stage)
            let fset = Set(focus)
            var shown: [(part: MGPart, mesh: MGMesh, t: MGTransform, box: MGBounds)] = []
            var whole = MGBounds.empty, focusBox = MGBounds.empty
            // A hidden part is not drawn: it neither hides samples nor joins the focus group.
            for p in doc.assembly.parts where !view.part(p.id).hidden {
                let mesh = view.part(p.id).cut?.mesh ?? p.mesh
                let t = pose.world[p.id] ?? .identity
                let b = MGSolidFrames.worldBounds(mesh.bounds, t)
                whole = whole.union(b)
                if fset.contains(p.id) { focusBox = focusBox.union(b) }
                shown.append((p, mesh, t, b))
            }
            tol = max(1e-6, 1e-3 * (whole.isEmpty ? 0 : whole.size.length))
            // The focus group: the focus, the parts attached below it (parent chain, bounded by the part count) and the
            // parts inside the focus box (grown by 0.5 % of the model's box diagonal).
            let grow = 0.005 * (whole.isEmpty ? 0 : whole.size.length)
            let parent = Dictionary(doc.assembly.parts.map { ($0.id, $0.parent) }, uniquingKeysWith: { a, _ in a })
            func below(_ id: String) -> Bool {
                var cur = parent[id] ?? nil
                for _ in 0..<doc.assembly.parts.count {
                    guard let c = cur else { return false }
                    if fset.contains(c) { return true }
                    cur = parent[c] ?? nil
                }
                return false
            }
            func inside(_ b: MGBounds) -> Bool {
                !b.isEmpty && !focusBox.isEmpty && b.min.x >= focusBox.min.x - grow && b.max.x <= focusBox.max.x + grow
                    && b.min.y >= focusBox.min.y - grow && b.max.y <= focusBox.max.y + grow
                    && b.min.z >= focusBox.min.z - grow && b.max.z <= focusBox.max.z + grow
            }
            var group = fset
            for x in shown where below(x.part.id) || inside(x.box) { group.insert(x.part.id) }
            context = s.focus.isEmpty ? group
                : group.union(MGSolidFraming.context(doc, core: fset, ghost: Set(s.ghost), hidden: doc.hiddenParts(step: step), params: params, stage: stage))
            for x in shown {
                let pv = view.part(x.part.id)
                guard pv.opacity >= MGSolidFraming.blockingOpacity || fset.contains(x.part.id) else { continue }
                solids.append(Solid(id: x.part.id, mesh: x.mesh, inverse: x.t.inverse, bounds: x.box, focus: fset.contains(x.part.id),
                                    group: group.contains(x.part.id)))
            }
            if let sec = s.section, let id = doc.assembly.parts.map(\.id).first(where: { group.contains($0) && view.part($0).cut != nil }),
               let c = view.part(id).cut, sec.parts.contains(id) {
                let t = pose.world[id] ?? .identity
                cut = (t.applyVector(c.plane.normal), t.apply(c.plane.normal * c.plane.offset))
            }
            // Samples split evenly over the focus parts (assembly order): the centroids of mid-stride triangles of each
            // part's shown mesh (points on its faces, not on its edges, where a neighbouring part may cover them).
            let n = MGSolidFraming.occlusionSamples
            let quota = max(1, n / max(1, focus.count))
            var pts: [MGVec3] = []
            for id in focus {
                guard let part = doc.assembly.part(id) else { continue }
                let mesh = view.part(id).cut?.mesh ?? part.mesh
                let count = mesh.triangleCount
                guard count > 0 else { continue }
                let t = pose.world[id] ?? .identity, q = min(quota, count)
                for j in 0..<q {
                    let (a, b, c) = mesh.triangle((2 * j + 1) * count / (2 * q))
                    guard a < mesh.positions.count, b < mesh.positions.count, c < mesh.positions.count else { continue }
                    let p = t.apply((mesh.positions[a] + mesh.positions[b] + mesh.positions[c]) * (1.0 / 3))
                    if p.x.isFinite, p.y.isFinite, p.z.isFinite { pts.append(p) }
                }
            }
            samples = pts.count > n ? (0..<n).map { pts[$0 * pts.count / n] } : pts
        }

        /// The automatic ghosts, the samples tested and the samples still hidden after the ghosts, seen from `camera`.
        func evaluate(_ camera: MGSolidCamera) -> (ghost: [String], samples: Int, occluded: Int) {
            let eye = stage.inverse.apply(camera.position)
            guard eye.x.isFinite, eye.y.isFinite, eye.z.isFinite else { return ([], 0, 0) }
            var counts = [Int](repeating: 0, count: solids.count), hidden: [[Int]] = []
            var used = 0
            sampling: for x in samples {
                let d = x - eye, len = d.length
                guard len > tol, len.isFinite else { hidden.append([]); continue }
                let before = 1 - tol / len
                // The first focus surface on the segment: parts behind it cannot hide this sample.
                var front = before
                for s in solids where s.focus && MGAnnotationOcclusion.segmentHits(eye, x, s.bounds) {
                    guard used + s.mesh.triangleCount <= MGSolidFraming.occlusionTests else { break sampling }
                    used += s.mesh.triangleCount
                    if let t = OcclusionProbe.firstHit(s.inverse.apply(eye), s.inverse.apply(x), s.mesh, after: 1e-9, before: front) { front = t }
                }
                let end = eye + d * front
                var by: [Int] = []
                for (i, s) in solids.enumerated() where !s.group && MGAnnotationOcclusion.segmentHits(eye, end, s.bounds) {
                    guard used + s.mesh.triangleCount <= MGSolidFraming.occlusionTests else { break sampling }
                    used += s.mesh.triangleCount
                    // A part hides the sample when it crosses the segment before the first focus surface, unless the
                    // sample lies inside the part (an odd number of crossings up to the sample): no direction shows it.
                    let c = OcclusionProbe.crossings(s.inverse.apply(eye), s.inverse.apply(x), s.mesh, after: 1e-9, before: before)
                    if let t = c.first, t < front, c.count % 2 == 0 { by.append(i) }
                }
                for i in by { counts[i] += 1 }
                hidden.append(by)
            }
            let n = hidden.count
            var ghost = Set<Int>()
            for (i, s) in solids.enumerated() where !context.contains(s.id) && Double(counts[i]) > MGSolidFraming.ghostShare * Double(n) {
                ghost.insert(i)
            }
            let occluded = hidden.filter { $0.contains { !ghost.contains($0) } }.count
            return (ghost.sorted().map { solids[$0].id }, n, occluded)
        }

        /// For a step that cuts a focus-group part: does `camera` look at the cut face? True when the camera is on the
        /// cut-away side of the plane and its view direction is within about 75° of the plane normal (the cosine is at
        /// least `MGSolidFraming.cutFacing`). Nil without such a cut.
        func facesCut(_ camera: MGSolidCamera) -> Bool? {
            guard let cut else { return nil }
            let eye = stage.inverse.apply(camera.position), target = stage.inverse.apply(camera.targetVector)
            let look = (eye - target).normalized
            return (eye - cut.point).dot(cut.normal) > 0 && look.dot(cut.normal) >= MGSolidFraming.cutFacing
        }

        /// How many times the surface of `mesh` crosses `a + t (b − a)` with `after < t < before`, and the smallest such
        /// `t`. Each crossing counts once, also through a shared edge or vertex (`watertightHit`), so an odd count means
        /// that `b` lies inside a closed mesh when `a` lies outside it.
        static func crossings(_ a: MGVec3, _ b: MGVec3, _ mesh: MGMesh, after: Double, before: Double) -> (count: Int, first: Double?) {
            guard let ray = WatertightRay(a, b - a) else { return (0, nil) }
            var n = 0, best: Double?
            for i in 0..<mesh.triangleCount {
                let (i0, i1, i2) = mesh.triangle(i)
                guard i0 < mesh.positions.count, i1 < mesh.positions.count, i2 < mesh.positions.count else { continue }
                guard let t = ray.hit(mesh.positions[i0], mesh.positions[i1], mesh.positions[i2]), t > after, t < before else { continue }
                n += 1; best = min(best ?? t, t)
            }
            return (n, best)
        }

        /// The smallest `t` with `after < t < before` at which a triangle of `mesh` crosses `a + t (b − a)`
        /// (`watertightHit`), or nil.
        static func firstHit(_ a: MGVec3, _ b: MGVec3, _ mesh: MGMesh, after: Double, before: Double) -> Double? {
            crossings(a, b, mesh, after: after, before: before).first
        }
    }
}

/// A watertight ray–triangle test (Woop, Benthin and Wald, "Watertight Ray/Triangle Intersection", JCGT 2013) with a
/// half-open tie rule. The ray is sheared so it runs along +Z through the origin; each triangle edge gives a 2D edge
/// function. The two triangles that share an edge compute the same value with opposite sign (exactly, in floating
/// point, from the same vertex coordinates), so a ray through the edge is inside one of them, never both and never
/// neither: when an edge function is exactly 0 the edge belongs to the triangle only if its direction, oriented
/// counter-clockwise, points down (or left when horizontal). The same rule settles a ray through a shared vertex: one
/// triangle of the fan takes it. No epsilon.
struct WatertightRay {
    let origin: MGVec3, kx: Int, ky: Int, kz: Int, sx: Double, sy: Double, sz: Double

    init?(_ origin: MGVec3, _ d: MGVec3) {
        let c = [d.x, d.y, d.z]
        guard c.allSatisfy(\.isFinite), origin.x.isFinite, origin.y.isFinite, origin.z.isFinite else { return nil }
        var kz = 0
        if abs(c[1]) > abs(c[kz]) { kz = 1 }
        if abs(c[2]) > abs(c[kz]) { kz = 2 }
        guard c[kz] != 0 else { return nil }
        var kx = (kz + 1) % 3, ky = (kx + 1) % 3
        if c[kz] < 0 { swap(&kx, &ky) }   // keep the winding
        self.origin = origin; self.kx = kx; self.ky = ky; self.kz = kz
        sx = c[kx] / c[kz]; sy = c[ky] / c[kz]; sz = 1 / c[kz]
    }

    static func component(_ v: MGVec3, _ k: Int) -> Double { k == 0 ? v.x : k == 1 ? v.y : v.z }

    /// The ray parameter `t` (origin + t · direction) of the hit, or nil (no hit, or a triangle seen edge-on).
    func hit(_ p0: MGVec3, _ p1: MGVec3, _ p2: MGVec3) -> Double? {
        func sheared(_ p: MGVec3) -> (x: Double, y: Double, z: Double) {
            let r = p - origin
            let z = WatertightRay.component(r, kz)
            return (WatertightRay.component(r, kx) - sx * z, WatertightRay.component(r, ky) - sy * z, sz * z)
        }
        let A = sheared(p0), B = sheared(p1), C = sheared(p2)
        // Edge functions: u for edge p1 → p2, v for p2 → p0, w for p0 → p1 (value = end × start in 2D).
        var u = C.x * B.y - C.y * B.x, v = A.x * C.y - A.y * C.x, w = B.x * A.y - B.y * A.x
        let det = u + v + w
        guard det != 0, det.isFinite else { return nil }
        let sign: Double = det > 0 ? 1 : -1
        u *= sign; v *= sign; w *= sign
        // Half-open rule for an edge whose function is exactly 0: owned when its counter-clockwise direction points
        // down, or left when horizontal. Reversing the edge flips the answer, so one of two neighbours owns it.
        func owns(_ start: (x: Double, y: Double, z: Double), _ end: (x: Double, y: Double, z: Double)) -> Bool {
            var dx = end.x - start.x, dy = end.y - start.y
            if sign < 0 { dx = -dx; dy = -dy }
            return dy < 0 || (dy == 0 && dx < 0)
        }
        guard u > 0 || (u == 0 && owns(B, C)), v > 0 || (v == 0 && owns(C, A)), w > 0 || (w == 0 && owns(A, B)) else { return nil }
        let t = (u * A.z + v * B.z + w * C.z) / (det * sign)
        return t.isFinite ? t : nil
    }
}

// MARK: Story camera moves

extension MGStoryPlan {
    /// Most straight chords one curved move is split into (`blockedMoves`).
    public static let maxMoveChords = 1024

    /// Beats whose camera move would pass through a part. For each beat after the first whose camera and the previous
    /// beat's camera are known, the camera path as `camera(from:to:_:)` plays it is tested against every part's posed
    /// box (render frame, at the previous beat's pose and at this beat's pose), grown by the near-plane distance at the
    /// larger camera distance (`MGSolidFraming.nearPlane`). The test is an exact segment-versus-box slab test, the whole
    /// move including its ends:
    ///
    /// * A move that keeps yaw, pitch and distance (only the target moves) is a straight segment: one slab test per box.
    /// * A move that turns or zooms is a curve. It is split into `K` equal chords of the played path, and each box is
    ///   also grown by the proven chord error `M / (8 K²)`, where `M = dmax (|ln(d1 / d0)| + ω)²` bounds the path's
    ///   second derivative (`ω`: yaw plus pitch change in radians; a linear distance blend uses `2 |Δd| ω + dmax ω²`).
    ///   `K` is the smallest count that keeps that error within the near-plane distance at the smaller camera distance,
    ///   at most `maxMoveChords` (over the cap the error grows the boxes instead). So no collision is missed; a move
    ///   that only passes close to a part may cut too.
    ///
    /// A blocked beat cuts to its own camera instead of moving. `beats` gives each beat's camera (its still's camera;
    /// nil without a solid) and end pose. Deterministic; at most 2 × 96 boxes × `maxMoveChords` slab tests per move.
    public static func blockedMoves(_ doc: MGSolidDocument, beats: [(camera: MGSolidCamera?, params: MGPoseParameters)],
                                    stage: MGTransform = MGSolidStage.zUpToYUp) -> Set<Int> {
        guard beats.count > 1 else { return [] }
        // Each beat's posed part boxes, once (render frame).
        let boxes: [[MGBounds]] = beats.map { b in
            let pose = doc.assembly.pose(b.params)
            return doc.assembly.parts.map { MGSolidFrames.worldBounds($0.mesh.bounds, stage * (pose.world[$0.id] ?? .identity)) }
        }
        var out = Set<Int>()
        for k in 1..<beats.count {
            guard let from = beats[k - 1].camera, let to = beats[k].camera, let path = movePath(from, to) else { continue }
            let all = boxes[k - 1] + boxes[k]
            let g = path.grow
            let grown = all.filter { !$0.isEmpty && $0.min.x.isFinite && $0.max.x.isFinite }.map {
                MGBounds(min: $0.min - MGVec3(g, g, g), max: $0.max + MGVec3(g, g, g))
            }
            chords: for (a, b) in zip(path.points, path.points.dropFirst()) {
                for box in grown where MGAnnotationOcclusion.segmentHits(a, b, box) { out.insert(k); break chords }
            }
        }
        return out
    }

    /// The played path of a move as chord end points (render frame) and the box growth that makes the chord test
    /// conservative: the near plane at the larger distance plus the proven chord error. Nil for non-finite cameras.
    /// `minChords` (routed moves, `legChords`) raises the chord count; the error bound only shrinks.
    static func movePath(_ a: MGSolidCamera, _ b: MGSolidCamera, minChords: Int = 1) -> (points: [MGVec3], grow: Double)? {
        guard MGSolidFraming.finite(a), MGSolidFraming.finite(b), a.yaw.isFinite, b.yaw.isFinite, a.pitch.isFinite, b.pitch.isFinite else {
            return nil
        }
        var dy = (b.yaw - a.yaw).truncatingRemainder(dividingBy: 360)
        if dy > 180 { dy -= 360 } else if dy < -180 { dy += 360 }
        let omega = (abs(dy) + abs(b.pitch - a.pitch)) * .pi / 180
        let dmax = max(a.distance, b.distance), dmin = min(a.distance, b.distance)
        let bound: Double
        if a.distance > 0 && b.distance > 0 {
            let lr = abs(log(b.distance / a.distance))
            bound = dmax * (lr + omega) * (lr + omega)
        } else {
            bound = 2 * abs(b.distance - a.distance) * omega + dmax * omega * omega
        }
        let tol = MGSolidFraming.nearPlane(distance: dmin)
        guard bound.isFinite, tol > 0 else { return nil }
        let need = bound > 0 ? (bound / (8 * tol)).squareRoot().rounded(.up) : 1
        let chords = Int(min(Double(maxMoveChords), max(Double(max(1, minChords)), need)))
        let error = bound / (8 * Double(chords * chords))
        let points = (0...chords).map { MGStoryPlan.camera(from: a, to: b, Double($0) / Double(chords)).position }
        guard points.allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }) else { return nil }
        return (points, MGSolidFraming.nearPlane(distance: dmax) + error)
    }
}
