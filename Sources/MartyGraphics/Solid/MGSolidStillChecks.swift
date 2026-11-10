// SPDX-License-Identifier: Apache-2.0
import Foundation

// Two rules of the check report that read each still as `marty-solid render` frames it: the framing rule (a solid part
// a still shows is never cut by the frame edge, the title band or the caption band) and the small-unit rule (a unit that
// a label, an arrow or a highlight names covers enough pixels in at least one still). Foundation only, deterministic:
// steps and beats in order, parts in assembly order, a fixed raster.

/// One still as `marty-solid render` frames it (its camera, its view with the automatic ghosts and dropped arrows, its
/// pose and pixel size), with the safe window its framing used and what its step or beat names.
public struct MGFramedStill: Sendable {
    public let still: MGAnnotationAnchorView
    /// The safe window of the framing: the view minus the title and caption bands of a step still; a beat still's
    /// whole solid pane.
    public let window: MGSolidFraming.Window
    /// The parts the step or beat highlights (resolved ids): the parts its caption is about.
    public let highlight: [String]
    /// The step's or beat's explicit `focus` (resolved ids; empty without one).
    public let focus: [String]

    public init(still: MGAnnotationAnchorView, window: MGSolidFraming.Window, highlight: [String], focus: [String]) {
        self.still = still; self.window = window; self.highlight = highlight; self.focus = focus
    }
}

/// A still that cuts a solid part (`framing.cut.step.<n>`, `framing.cut.beat.<n>`): only an explicit `focus` whose
/// widening would pass the minimum zoom (`MGSolidFraming.minimumFocusFill`) keeps such a close-up.
public struct MGFramingCut: Equatable, Sendable {
    /// The 0-based step and explainer beat of the still (a beat still has both when its beat shows a step).
    public var step: Int?, beat: Int?
    /// The solid parts the still cuts, in assembly order.
    public var parts: [String]
    /// The ids the repair adds to the view's `ghost` list: the unit of each cut part (`MGSolidDocument.unitID`) when no
    /// part of that unit is in the still's focus or highlight, else the part itself; first-seen order.
    public var ghost: [String]
    /// The view's `ghost` list after the repair (the existing ids, then `ghost`).
    public var ghostAfter: [String]
    /// True when the view has an explicit `focus`.
    public var explicitFocus: Bool

    /// `framing.cut.beat.<n>` for a beat still, else `framing.cut.step.<n>` (1-based).
    public var reason: String {
        if let beat { return "framing.cut.beat.\(beat + 1)" }
        return "framing.cut.step.\((step ?? 0) + 1)"
    }

    /// One exact line: the still, the parts it cuts and the `ghost` list that makes every one see-through context.
    public var repair: String {
        let what = beat.map { "Beat \($0 + 1)" } ?? "Step \((step ?? 0) + 1)"
        let key = beat != nil ? "its \"view\"" : "the step"
        let list = "[" + ghostAfter.map { "\"\(MGSolidParser.token($0))\"" }.joined(separator: ", ") + "]"
        let cut = parts.prefix(4).map { MGSolidParser.token($0) }.joined(separator: ", ") + (parts.count > 4 ? " and \(parts.count - 4) more" : "")
        var line = "\(what) cuts \(cut) at the frame edge or under a band"
        if explicitFocus {
            line += ", and widening its close-up would make the focus fill less than \(Int((MGSolidFraming.minimumFocusFill * 100).rounded())) % of the safe window"
        }
        line += ". Set \"ghost\": \(list) in \(key) (see-through context may leave the frame)"
        if explicitFocus { line += ", or remove its \"focus\" so the whole model is framed" }
        return MGAnnotationAnchorIssue.bounded(line + ".", MGAnnotationAnchorIssue.repairScalars)
    }

    /// `{"step", "beat", "parts", "ghost", "repair"}` (1-based step and beat, null when absent).
    public var json: MGJSON {
        .object(["step": step.map { .number(Double($0 + 1)) } ?? .null, "beat": beat.map { .number(Double($0 + 1)) } ?? .null,
                 "parts": .array(parts.map { .string($0) }), "ghost": .array(ghost.map { .string($0) }), "repair": .string(repair)])
    }
}

/// A named unit too small to read in every still that shows it (`unit.small.<id>`).
public struct MGSmallUnit: Equatable, Sendable {
    /// The unit (`MGSolidDocument.unitID`).
    public var unit: String
    /// The most pixels the unit covers in a still that shows it, and that still (0-based step and beat).
    public var pixels: Int
    public var step: Int?, beat: Int?
    /// The stills that show the unit (solid, not hidden).
    public var stills: Int
    /// The pixel minimum (`MGSmallUnitRules.minimumPixels`).
    public var minimum: Int
    /// The frame size the minimum is measured against.
    public var width: Int, height: Int

    public var reason: String { "unit.small.\(unit)" }

    /// One exact line: the measure, the minimum and three repairs (a focused view, a larger size, a closer camera).
    public var repair: String {
        let u = MGSolidParser.token(unit)
        let best = beat.map { "beat \($0 + 1)" } ?? step.map { "step \($0 + 1)" } ?? "the plain view"
        let share = MGSmallUnitRules.minimumShare * 100
        let focus = beat != nil ? "a beat whose \"view\" has \"focus\": [\"\(u)\"]" : "a step with \"focus\": [\"\(u)\"]"
        let line = "Unit \(u) covers at most \(pixels) px (\(best)) in the \(stills) still\(stills == 1 ? "" : "s") that show it, under "
            + "the \(minimum) px minimum (\(MGSmallUnitRules.format(share)) % of a \(width) × \(height) frame). Show it in \(focus), "
            + "make it larger (its shape size, or its component's size in \"with\"), or bring the camera closer to it."
        return MGAnnotationAnchorIssue.bounded(line, MGAnnotationAnchorIssue.repairScalars)
    }

    /// `{"unit", "pixels", "minimum", "stills", "step", "beat", "repair"}` (1-based step and beat, null when absent).
    public var json: MGJSON {
        .object(["unit": .string(unit), "pixels": .number(Double(pixels)), "minimum": .number(Double(minimum)),
                 "stills": .number(Double(stills)), "step": step.map { .number(Double($0 + 1)) } ?? .null,
                 "beat": beat.map { .number(Double($0 + 1)) } ?? .null, "repair": .string(repair)])
    }
}

/// The constants of the small-unit rule (docs/SOLID-3D.md, "Small named units").
public enum MGSmallUnitRules {
    /// A named unit must cover at least this share of the frame's pixels in at least one still that shows it:
    /// 0.05 % of a 1280 × 800 frame is 512 px, about a 23 × 23 px square. Below it a part reads as a speck or a
    /// thin ring, not as a thing a label can name. (Measured on the r2j jet-suit lessons: wrist rings that did not read
    /// as engines covered at most 172 px; arm engines that did read covered 1,080 px or more in their best still.)
    public static let minimumShare = 0.0005
    /// The raster of the coverage measure: this share of the still's size on each axis (a 1280 × 800 still is measured
    /// on 640 × 400 cells, each standing for 4 pixels).
    public static let rasterScale = 0.5
    /// Most triangles one still's raster reads; parts after the budget are not drawn (a still over it is skipped).
    public static let triangleBudget = 600_000

    /// The pixel minimum for a `width` × `height` frame.
    public static func minimumPixels(width: Int, height: Int) -> Int {
        Int((minimumShare * Double(max(0, width)) * Double(max(0, height))).rounded())
    }

    static func format(_ x: Double) -> String {
        x == x.rounded() ? String(Int(x)) : String(format: "%.2f", x).replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
    }
}

extension MGSolidDocument {
    /// The unit of a part: its first id segment (the text before the first "."), so a component instance's parts share
    /// their instance id and a plain part is its own unit (`unitParts`).
    public static func unitID(_ part: String) -> String { String(part.prefix { $0 != "." }) }

    /// Every step still as `marty-solid render` frames it at `width` × `height` (`MGSolidRenderPlan.cameras`: the
    /// step's shot, its title and caption bands, the unblocked-focus rule with its automatic ghosts and arrow drops), at
    /// the still's pose, in step order. A document without steps gives its plain view (`hero.png`).
    public func framedStills(width: Int = MGAnnotationAnchorRules.width, height: Int = MGAnnotationAnchorRules.height) -> [MGFramedStill] {
        let w = Double(width), h = Double(height)
        let aspect = w > 0 && h > 0 ? w / h : 1.6
        let bands = MGSolidRenderPlan.bands(width: w, height: h)
        var shots: [(Int?, MGSolidShot)] = steps.indices.compactMap { i in MGSolidShot.step(self, i).map { (i, $0) } }
        if steps.isEmpty {
            let plan = MGSolidRenderPlan(self, sourceName: "", source: MGSolidSource(data: Data()), loop: false)
            if let hero = plan.stills.first { shots = [(nil, hero)] }
        }
        return shots.map { i, shot in
            let title = shot.title != nil ? bands.title : 0, caption = shot.caption != nil ? bands.caption : 0
            let clear = MGSolidFraming.clearView(self, shot: shot, aspect: aspect, titleBand: title, captionBand: caption)
            let still = MGAnnotationAnchorView(view: clear.view(view(step: i)), params: shot.params, camera: clear.camera,
                                               width: w, height: h, step: i, beat: nil)
            let s = i.map { steps[$0] }
            return MGFramedStill(still: still, window: MGSolidFraming.Window(titleBand: title, captionBand: caption),
                                 highlight: s?.highlight ?? [], focus: s?.focus ?? [])
        }
    }

    /// The framing rule at each still: the solid parts (`MGSolidFraming.solidParts`, with the still's automatic ghosts)
    /// that the still's camera cuts (`MGSolidFraming.cutParts`), one issue per still that cuts any, in still order.
    /// `ghosts(still)` gives the view's own `ghost` list (resolved ids) for the repair.
    public func framingCuts(_ stills: [MGFramedStill], ghosts: (MGFramedStill) -> [String]) -> [MGFramingCut] {
        stills.compactMap { f in
            let v = f.still
            let aspect = v.width > 0 && v.height > 0 ? v.width / v.height : 1.6
            let cut = MGSolidFraming.cutParts(self, view: v.view, params: v.params, camera: v.camera, aspect: aspect, window: f.window,
                                              stage: v.stage)
            guard !cut.isEmpty else { return nil }
            let named = Set((f.focus + f.highlight).map(MGSolidDocument.unitID))
            var ghost: [String] = []
            for p in cut {
                let u = MGSolidDocument.unitID(p)
                let id = named.contains(u) ? p : u
                if !ghost.contains(id) { ghost.append(id) }
            }
            var after = ghosts(f)
            for id in ghost where !after.contains(id) { after.append(id) }
            return MGFramingCut(step: v.step, beat: v.beat, parts: cut, ghost: ghost, ghostAfter: after, explicitFocus: !f.focus.isEmpty)
        }
    }

    /// The strings of a JSON array (other values skipped); empty for anything else. The repair of `framingCuts` reads the
    /// authored `ghost` list with it (before component expansion).
    static func strings(_ j: MGJSON?) -> [String] {
        guard case .array(let a)? = j else { return [] }
        return a.compactMap { if case .string(let s) = $0 { return s } else { return nil } }
    }

    /// The authored `ghost` list of step `step` (0-based) in the source (before component expansion); empty without one.
    func authoredGhost(step: Int?) -> [String] {
        guard let step, case .object(let o) = source, case .array(let steps)? = o["steps"], steps.indices.contains(step),
              case .object(let s) = steps[step] else { return [] }
        return MGSolidDocument.strings(s["ghost"])
    }

    /// The units that a still names, in assembly order: the units of the parts that the labels and arrows it shows
    /// (not dropped) ride on, and of the parts its step or beat highlights.
    func namedUnits(_ f: MGFramedStill) -> Set<String> {
        var parts = f.highlight
        let dropped = Set(f.still.view.arrowDrops.map(\.id))
        for id in checkedAnnotations(f.still.view, params: f.still.params) ?? [] where !dropped.contains(id) {
            guard annotations.label(id) != nil || annotations.arrow(id) != nil else { continue }
            parts += MGSolidAnnotationEngine.anchors(annotations, id).compactMap(\.part)
        }
        return Set(parts.map(MGSolidDocument.unitID))
    }

    /// The small-unit rule over `stills` (docs/SOLID-3D.md, "Small named units"): a unit that some still names
    /// (`namedUnits`) and that covers fewer than `MGSmallUnitRules.minimumPixels` of a `width` × `height` frame in every
    /// still that shows it solid (`unitPixels`). One issue per unit, in assembly order. A unit no still shows solid is
    /// not tested.
    public func smallUnits(_ stills: [MGFramedStill], width: Int = MGAnnotationAnchorRules.width,
                           height: Int = MGAnnotationAnchorRules.height) -> [MGSmallUnit] {
        var named = Set<String>()
        for f in stills { named.formUnion(namedUnits(f)) }
        guard !named.isEmpty else { return [] }
        let minimum = MGSmallUnitRules.minimumPixels(width: width, height: height)
        var best: [String: (px: Int, step: Int?, beat: Int?)] = [:], shown: [String: Int] = [:], over = Set<String>()
        for f in stills {
            guard let px = unitPixels(f.still, units: named) else { continue }
            for (u, n) in px {
                shown[u, default: 0] += 1
                if n >= minimum { over.insert(u) }
                if n > (best[u]?.px ?? -1) { best[u] = (n, f.still.step, f.still.beat) }
            }
        }
        var order: [String] = []
        for p in assembly.parts { let u = MGSolidDocument.unitID(p.id); if !order.contains(u) { order.append(u) } }
        return order.compactMap { u in
            guard named.contains(u), !over.contains(u), let b = best[u], let n = shown[u] else { return nil }
            return MGSmallUnit(unit: u, pixels: b.px, step: b.step, beat: b.beat, stills: n, minimum: minimum, width: width, height: height)
        }
    }

    /// The pixels each unit of `units` covers in a still, for the units the still shows solid (a part not hidden, at a
    /// view opacity of at least `MGSolidFraming.blockingOpacity`): a depth raster of every solid part (a cut part draws
    /// its cut mesh) on `MGSmallUnitRules.rasterScale` of the still's size; a cell counts for the unit whose surface is
    /// nearest there, and stands for 1 / scale² pixels. Ghosts neither count nor hide. Nil when the still's triangles
    /// exceed `MGSmallUnitRules.triangleBudget` or its camera is not usable.
    func unitPixels(_ v: MGAnnotationAnchorView, units: Set<String>) -> [String: Int]? {
        let c = v.camera
        guard MGSolidFraming.finite(c), v.width > 0, v.height > 0, v.width.isFinite, v.height.isFinite else { return nil }
        let k = MGSmallUnitRules.rasterScale
        let gw = max(1, Int((v.width * k).rounded())), gh = max(1, Int((v.height * k).rounded()))
        let aspect = v.width / v.height
        let b = MGSolidFraming.Basis(yaw: c.yaw, pitch: c.pitch), f = MGSolidFraming.focal(c.fieldOfView), t = c.targetVector
        let near = MGSolidFraming.nearPlane(distance: c.distance)
        let pose = assembly.pose(v.params)
        var solid: [(part: MGPart, mesh: MGMesh, unit: Int)] = []
        var unitIndex: [String: Int] = [:], unitNames: [String] = []
        var triangles = 0
        for p in assembly.parts {
            let pv = v.view.part(p.id)
            guard !pv.hidden, pv.opacity >= MGSolidFraming.blockingOpacity else { continue }
            let mesh = pv.cut?.mesh ?? p.mesh
            triangles += mesh.triangleCount
            guard triangles <= MGSmallUnitRules.triangleBudget else { return nil }
            let u = MGSolidDocument.unitID(p.id)
            var idx = -1
            if units.contains(u) {
                if let i = unitIndex[u] { idx = i } else { idx = unitNames.count; unitIndex[u] = idx; unitNames.append(u) }
            }
            solid.append((p, mesh, idx))
        }
        guard !unitNames.isEmpty else { return [:] }
        // Nearest inverse depth per cell (0: empty) and the unit index there (-1: another part).
        var depth = [Double](repeating: 0, count: gw * gh), owner = [Int](repeating: -1, count: gw * gh)
        let W = Double(gw), H = Double(gh)
        for s in solid {
            let m = MGSolidStage.zUpToYUp * (pose.world[s.part.id] ?? .identity)
            let screen: [(x: Double, y: Double, w: Double)?] = s.mesh.positions.map { q in
                let r = m.apply(q) - t
                let z = c.distance + r.dot(b.fwd)
                guard z >= near, z.isFinite else { return nil }
                let x = r.dot(b.right) * f / aspect / z, y = r.dot(b.up) * f / z
                guard x.isFinite, y.isFinite else { return nil }
                return ((x + 1) / 2 * W, (1 - y) / 2 * H, 1 / z)
            }
            for i in 0..<s.mesh.triangleCount {
                let (i0, i1, i2) = s.mesh.triangle(i)
                guard i0 < screen.count, i1 < screen.count, i2 < screen.count,
                      let a = screen[i0], let bb = screen[i1], let cc = screen[i2] else { continue }
                let area = (bb.x - a.x) * (cc.y - a.y) - (bb.y - a.y) * (cc.x - a.x)
                guard abs(area) > 1e-12 else { continue }
                let x0 = max(0, Int(floor(min(a.x, bb.x, cc.x)))), x1 = min(gw - 1, Int(ceil(max(a.x, bb.x, cc.x))))
                let y0 = max(0, Int(floor(min(a.y, bb.y, cc.y)))), y1 = min(gh - 1, Int(ceil(max(a.y, bb.y, cc.y))))
                guard x0 <= x1, y0 <= y1 else { continue }
                for py in y0...y1 {
                    let sy = Double(py) + 0.5
                    for px in x0...x1 {
                        let sx = Double(px) + 0.5
                        // Barycentric weights at the cell centre; the inverse depth is linear on the screen.
                        let w0 = ((bb.x - sx) * (cc.y - sy) - (bb.y - sy) * (cc.x - sx)) / area
                        let w1 = ((cc.x - sx) * (a.y - sy) - (cc.y - sy) * (a.x - sx)) / area
                        let w2 = 1 - w0 - w1
                        guard w0 >= 0, w1 >= 0, w2 >= 0 else { continue }
                        let inv = w0 * a.w + w1 * bb.w + w2 * cc.w
                        let cell = py * gw + px
                        if inv > depth[cell] { depth[cell] = inv; owner[cell] = s.unit }
                    }
                }
            }
        }
        var counts = [Int](repeating: 0, count: unitNames.count)
        for o in owner where o >= 0 { counts[o] += 1 }
        let perCell = 1 / (k * k)
        var out: [String: Int] = [:]
        for (i, u) in unitNames.enumerated() { out[u] = Int((Double(counts[i]) * perCell).rounded()) }
        return out
    }
}
