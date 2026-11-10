// SPDX-License-Identifier: Apache-2.0
import Foundation

// Two rules of the check report that read each still as `marty-solid render` frames it: the subject rule (the subject
// of a step or beat is whole and large enough to read at its closest framing) and the small-unit rule (a unit that a
// label, an arrow or a highlight names covers enough pixels in at least one still). Both measure visible pixels on one
// depth raster (`MGStillRaster`). Foundation only, deterministic: steps and beats in order, parts in assembly order, a
// fixed raster.

/// One still as `marty-solid render` frames it (its camera, its view with the automatic ghosts and dropped arrows, its
/// pose and pixel size), with its shot and the safe window its framing used.
public struct MGFramedStill: Sendable {
    public let still: MGAnnotationAnchorView
    /// The shot the framing read (`MGSolidFraming.subjectParts` reads its highlight and step).
    public let shot: MGSolidShot
    /// The safe window of the framing: the view minus the title and caption bands of a step still; a beat still's
    /// whole solid pane.
    public let window: MGSolidFraming.Window
    /// The rule that framed the still: `focus` when it was framed on its subject.
    public let rule: MGSolidFraming.Rule
    /// The instances the step or beat names whole, by instance id, in `focus` or `highlight` (`subjectGroups`).
    public let wholeInstances: Set<String>

    public init(still: MGAnnotationAnchorView, shot: MGSolidShot, window: MGSolidFraming.Window, rule: MGSolidFraming.Rule,
                wholeInstances: Set<String> = []) {
        self.still = still; self.shot = shot; self.window = window; self.rule = rule; self.wholeInstances = wholeInstances
    }
}

/// Exact repairs: ids are written as JSON strings, never shortened, and a JSON fragment is never cut. The explanatory
/// prose is bounded on its own; when prose and fragment together pass `MGAnnotationAnchorIssue.repairScalars`, the
/// repair keeps the fragment whole and the prose short, or, when the fragment alone is too long, names the report's
/// structured field that holds it.
public enum MGExactRepair {
    /// A JSON string literal of `s`.
    public static func json(_ s: String) -> String {
        var out = "\""
        for u in s.unicodeScalars {
            switch u {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if u.value < 0x20 { out += String(format: "\\u%04x", u.value) } else { out.unicodeScalars.append(u) }
            }
        }
        return out + "\""
    }

    /// A JSON array literal of strings.
    public static func list(_ ids: [String]) -> String { "[" + ids.map(json).joined(separator: ", ") + "]" }

    /// `prose` then `fragment`, within `limit` scalars: the fragment is kept whole; the prose is bounded to fit it. When
    /// the fragment alone does not fit with a minimal prose, the repair is the bounded prose plus `fallback` (which names
    /// the structured field that holds the exact fragment).
    public static func line(prose: String, fragment: String, fallback: String, limit: Int = MGAnnotationAnchorIssue.repairScalars) -> String {
        let p = prose.unicodeScalars.count, f = fragment.unicodeScalars.count
        if p + f <= limit { return prose + fragment }
        if f + 40 <= limit { return MGAnnotationAnchorIssue.bounded(prose, limit - f) + fragment }
        return MGAnnotationAnchorIssue.bounded(prose, limit - fallback.unicodeScalars.count) + fallback
    }
}

/// A step or beat whose subject misses a floor at the closest framing that keeps it whole
/// (`framing.subject.small.step.<n>`, `framing.subject.small.beat.<n>`; docs/SOLID-3D.md, "Subject first").
public struct MGSubjectSmall: Equatable, Sendable {
    /// One subject group: the subject parts of one unit, with its visible measure and the floors.
    public struct Group: Equatable, Sendable {
        public var unit: String
        public var parts: [String]
        /// Visible pixels, and the shorter side of the visible pixels' box (px), in the still.
        public var pixels: Int, extent: Double
        /// The units outside the subject whose surface covers this group most (assembly order of the unit's first part).
        public var hiddenBy: [String]
        /// The id the repairs use for this group: its unit when the group is every part of the unit, else nil (its parts).
        public var whole: Bool
        var ids: [String] { whole ? [unit] : parts }
    }
    /// The 0-based step and explainer beat of the still (a beat still has both when its beat shows a step).
    public var step: Int?, beat: Int?
    /// Every subject group, in order, and which of them miss a floor.
    public var groups: [Group]
    public var small: [Int]
    /// Subject parts the still cuts (`MGSolidFraming.cutParts`): empty unless a fit sampled the subject (over
    /// `MGSolidFraming.pointBudget` vertices).
    public var cut: [String]
    /// The subject's fill (`MGSolidFraming.filled`) and the floors: `minimumPixels` (`subjectAreaShare` of the safe
    /// window) and `minimumExtent` (`subjectExtentPixels`, scaled with the frame height).
    public var fill: Double, minimumPixels: Int, minimumExtent: Double
    /// The view's own `ghost` list as written; the `ghost` repair keeps it.
    public var existingGhost: [String] = []
    /// The annotations the still draws whose targets lie off the subject (a world point, or a part outside it): they
    /// widen the framing, and the `annotate` repair moves them to a view of their own. `keepAnnotations`: the rest.
    public var farAnnotations: [String] = [], keepAnnotations: [String] = []

    public init(step: Int?, beat: Int?, groups: [Group], small: [Int], cut: [String], fill: Double, minimumPixels: Int,
                minimumExtent: Double, existingGhost: [String] = [], farAnnotations: [String] = [], keepAnnotations: [String] = []) {
        self.step = step; self.beat = beat; self.groups = groups; self.small = small; self.cut = cut; self.fill = fill
        self.minimumPixels = minimumPixels; self.minimumExtent = minimumExtent; self.existingGhost = existingGhost
        self.farAnnotations = farAnnotations; self.keepAnnotations = keepAnnotations
    }

    public var reason: String {
        if let beat { return "framing.subject.small.beat.\(beat + 1)" }
        return "framing.subject.small.step.\((step ?? 0) + 1)"
    }

    /// One `focus` list per group: the split repair (a step per group), when the subject has more than one group.
    public var split: [[String]] { groups.count > 1 ? groups.map(\.ids) : [] }
    /// The `focus` list of the first small group alone: the subset repair (more than one group only).
    public var subset: [String] { groups.count > 1 ? small.first.map { groups[$0].ids } ?? [] : [] }
    /// The complete `ghost` list of the repair: the view's own ghosts as written, then the context units that cover the
    /// small groups (first-seen order), without repeats. Empty when no new unit is needed.
    public var ghost: [String] {
        var added: [String] = []
        for k in small { for u in groups[k].hiddenBy where !existingGhost.contains(u) && !added.contains(u) { added.append(u) } }
        return added.isEmpty ? [] : existingGhost + added
    }

    /// One exact line: the measure, then every repair that applies, as complete JSON.
    public var repair: String {
        let what = beat.map { "Beat \($0 + 1)" } ?? "Step \((step ?? 0) + 1)"
        let at = beat != nil ? "in its \"view\"" : "in the step"
        var prose = "\(what): at the closest framing that keeps its subject whole, "
        prose += small.map { k in
            let g = groups[k]
            return "\(g.unit) shows \(g.pixels) px, shorter side \(Int(g.extent.rounded())) px"
        }.joined(separator: "; ")
        if !cut.isEmpty { prose += (small.isEmpty ? "" : "; ") + "\(cut.count) subject part\(cut.count == 1 ? " is" : "s are") cut" }
        if fill < MGSolidFraming.subjectFill { prose += (small.isEmpty && cut.isEmpty ? "" : "; ") + "the subject fills \(Int((fill * 100).rounded())) %" }
        prose += " (minimum \(minimumPixels) px and \(Int(minimumExtent.rounded())) px per group). "
        var options: [String] = []
        if !split.isEmpty {
            options.append("split it into one step per subject: " + split.map { "\"focus\": \(MGExactRepair.list($0))" }.joined(separator: " then "))
        }
        if !subset.isEmpty { options.append("focus a subset \(at): \"focus\": \(MGExactRepair.list(subset))") }
        if !ghost.isEmpty { options.append("set the whole ghost list \(at): \"ghost\": \(MGExactRepair.list(ghost))") }
        if !farAnnotations.isEmpty {
            options.append("set \"annotate\": \(MGExactRepair.list(keepAnnotations)) \(at), and show \(MGExactRepair.list(farAnnotations)) in a view of their own (their targets lie off the subject and widen this framing)")
        }
        if options.isEmpty { options.append("make the subject larger, or show fewer subject parts in this view") }
        let fragment = "Repair (any one): " + options.joined(separator: "; or ") + "."
        return MGExactRepair.line(prose: prose, fragment: fragment,
                                  fallback: "Repair: split it (`split`), focus a subset (`subset`), set the ghost list (`ghost`) or move far annotations (`annotate`), exact lists in the report.")
    }

    /// `{"step", "beat", "groups": [{"unit", "parts", "pixels", "extent", "small", "hiddenBy"}], "cut", "fill",
    /// "minimumPixels", "minimumExtent", "split", "subset", "ghost", "annotate": null | {"keep", "move"}, "repair"}`
    /// (1-based step and beat, null when absent).
    public var json: MGJSON {
        .object(["step": step.map { .number(Double($0 + 1)) } ?? .null, "beat": beat.map { .number(Double($0 + 1)) } ?? .null,
                 "groups": .array(groups.enumerated().map { k, g in
                     .object(["unit": .string(g.unit), "parts": .array(g.parts.map { .string($0) }), "pixels": .number(Double(g.pixels)),
                              "extent": .number((g.extent * 10).rounded() / 10), "small": .bool(small.contains(k)),
                              "hiddenBy": .array(g.hiddenBy.map { .string($0) })])
                 }),
                 "cut": .array(cut.map { .string($0) }), "fill": .number((fill * 1000).rounded() / 1000),
                 "minimumPixels": .number(Double(minimumPixels)), "minimumExtent": .number((minimumExtent * 10).rounded() / 10),
                 "split": .array(split.map { .array($0.map { .string($0) }) }), "subset": .array(subset.map { .string($0) }),
                 "ghost": .array(ghost.map { .string($0) }),
                 "annotate": farAnnotations.isEmpty ? .null : .object(["keep": .array(keepAnnotations.map { .string($0) }),
                                                                       "move": .array(farAnnotations.map { .string($0) })]),
                 "repair": .string(repair)])
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

    public var reason: String { "unit.small.\(MGSolidParser.token(unit))" }

    /// One exact line: the measure, the minimum and three repairs (a focused view, a larger size, a closer camera).
    public var repair: String {
        let best = beat.map { "beat \($0 + 1)" } ?? step.map { "step \($0 + 1)" } ?? "the plain view"
        let share = MGSmallUnitRules.minimumShare * 100
        let prose = "Unit \(unit) covers at most \(pixels) px (\(best)) in the \(stills) still\(stills == 1 ? "" : "s") that show it, under "
            + "the \(minimum) px minimum (\(MGSmallUnitRules.format(share)) % of a \(width) × \(height) frame). "
        let focus = beat != nil ? "a beat whose \"view\" has \"focus\": \(MGExactRepair.list([unit]))" : "a step with \"focus\": \(MGExactRepair.list([unit]))"
        let fragment = "Show it in \(focus), make it larger (its shape size, or its component's size in \"with\"), or bring the camera closer to it."
        return MGExactRepair.line(prose: prose, fragment: fragment, fallback: "Show it in a step whose \"focus\" is the report's `unit`.")
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
    /// on 320 × 200 cells, each standing for 16 pixels).
    public static let rasterScale = 0.25
    /// Most triangles one still's raster reads; a still over it is not measured.
    public static let triangleBudget = 600_000

    /// The pixel minimum for a `width` × `height` frame.
    public static func minimumPixels(width: Int, height: Int) -> Int {
        Int((minimumShare * Double(max(0, width)) * Double(max(0, height))).rounded())
    }

    static func format(_ x: Double) -> String {
        x == x.rounded() ? String(Int(x)) : String(format: "%.2f", x).replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
    }
}

/// A depth raster of one still on `MGSmallUnitRules.rasterScale` of its size (one raster per still serves the subject
/// rule and the small-unit rule): for each cell the nearest solid part
/// (not hidden, view opacity at least `MGSolidFraming.blockingOpacity`; a cut part draws its cut mesh), and for each
/// group of parts the cells its triangles cover at any depth. Ghosts neither count nor hide.
struct MGStillRaster {
    let gw: Int, gh: Int
    /// Pixels one cell stands for (1 / scale²) and the scale itself.
    let perCell: Double, scale: Double
    /// Nearest solid part per cell (index into `parts`, -1 empty), and per cell a bit per group whose parts cover it.
    var owner: [Int32], cover: [UInt64]
    let parts: [String]
    /// The groups each part index belongs to (a bit per group; a part may be in several groups).
    let groupBits: [UInt64]

    /// Nil when the still's camera is not usable or its triangles pass `MGSmallUnitRules.triangleBudget`. At most 64
    /// groups are measured.
    init?(_ doc: MGSolidDocument, _ v: MGAnnotationAnchorView, groups: [[String]]) {
        let c = v.camera
        guard MGSolidFraming.finite(c), v.width > 0, v.height > 0, v.width.isFinite, v.height.isFinite else { return nil }
        let k = MGSmallUnitRules.rasterScale
        gw = max(1, Int((v.width * k).rounded())); gh = max(1, Int((v.height * k).rounded()))
        scale = k; perCell = 1 / (k * k)
        let aspect = v.width / v.height
        let b = MGSolidFraming.Basis(yaw: c.yaw, pitch: c.pitch), f = MGSolidFraming.focal(c.fieldOfView), t = c.targetVector
        let near = MGSolidFraming.nearPlane(distance: c.distance)
        let pose = doc.assembly.pose(v.params)
        var g: [String: UInt64] = [:]
        for (i, set) in groups.prefix(64).enumerated() { for p in set { g[p, default: 0] |= 1 << UInt64(i) } }
        var drawn: [(id: String, mesh: MGMesh, solid: Bool)] = []
        var triangles = 0
        for p in doc.assembly.parts {
            let pv = v.view.part(p.id)
            guard !pv.hidden else { continue }
            let solid = pv.opacity >= MGSolidFraming.blockingOpacity
            guard solid || g[p.id] != nil else { continue }
            let mesh = pv.cut?.mesh ?? p.mesh
            triangles += mesh.triangleCount
            guard triangles <= MGSmallUnitRules.triangleBudget else { return nil }
            drawn.append((p.id, mesh, solid))
        }
        parts = drawn.map(\.id)
        groupBits = drawn.map { g[$0.id] ?? 0 }
        var depth = [Double](repeating: 0, count: gw * gh)
        owner = [Int32](repeating: -1, count: gw * gh); cover = [UInt64](repeating: 0, count: gw * gh)
        let W = Double(gw), H = Double(gh)
        for (pi, d) in drawn.enumerated() {
            let m = MGSolidStage.zUpToYUp * (pose.world[d.id] ?? .identity)
            // Camera-space vertices (x, y scaled so the view planes are |x| = z, |y| = z), clipped to the near plane per
            // triangle (Sutherland–Hodgman on z >= near, then a fan): a face across the near plane keeps its visible part.
            let cam: [(x: Double, y: Double, z: Double)] = d.mesh.positions.map { q in
                let r = m.apply(q) - t
                return (r.dot(b.right) * f / aspect, r.dot(b.up) * f, c.distance + r.dot(b.fwd))
            }
            let bit = groupBits[pi]
            func project(_ v: (x: Double, y: Double, z: Double)) -> (x: Double, y: Double, w: Double) {
                ((v.x / v.z + 1) / 2 * W, (1 - v.y / v.z) / 2 * H, 1 / v.z)
            }
            for i in 0..<d.mesh.triangleCount {
                let (i0, i1, i2) = d.mesh.triangle(i)
                guard i0 < cam.count, i1 < cam.count, i2 < cam.count else { continue }
                var poly = [cam[i0], cam[i1], cam[i2]]
                guard poly.allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }) else { continue }
                if poly.contains(where: { $0.z < near }) {
                    var out: [(x: Double, y: Double, z: Double)] = []
                    for k in 0..<poly.count {
                        let a = poly[k], e = poly[(k + 1) % poly.count]
                        let ain = a.z >= near, ein = e.z >= near
                        if ain { out.append(a) }
                        if ain != ein {
                            let u = (near - a.z) / (e.z - a.z)
                            out.append((a.x + (e.x - a.x) * u, a.y + (e.y - a.y) * u, near))
                        }
                    }
                    poly = out
                }
                guard poly.count >= 3 else { continue }
                let sp = poly.map(project)
                for k in 1..<(sp.count - 1) {
                    let a = sp[0], bb = sp[k], cc = sp[k + 1]
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
                            let cell = py * gw + px
                            cover[cell] |= bit
                            guard d.solid else { continue }
                            let inv = w0 * a.w + w1 * bb.w + w2 * cc.w
                            if inv > depth[cell] { depth[cell] = inv; owner[cell] = Int32(pi) }
                        }
                    }
                }
            }
        }
    }

    /// The visible pixels of group `k` (cells whose nearest solid part is in the group), and the shorter side of their
    /// box in pixels (0 when none).
    func visible(_ k: Int) -> (pixels: Int, extent: Double) {
        guard k < 64 else { return (0, 0) }
        let bit: UInt64 = 1 << UInt64(k)
        var n = 0, x0 = Int.max, x1 = Int.min, y0 = Int.max, y1 = Int.min
        for cell in 0..<owner.count {
            let o = Int(owner[cell])
            guard o >= 0, groupBits[o] & bit != 0 else { continue }
            n += 1
            let x = cell % gw, y = cell / gw
            x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y)
        }
        guard n > 0 else { return (0, 0) }
        return (Int((Double(n) * perCell).rounded()), Double(min(x1 - x0 + 1, y1 - y0 + 1)) / scale)
    }

    /// The ids to ghost so group `k` shows where it lies behind another solid surface, most cells first (ties: part
    /// order); at most `limit`. A covering part is named by its unit (a component instance), unless that unit holds a
    /// part of `subject`: then the covering part itself, so a repair never ghosts the subject.
    func coveredBy(_ k: Int, subject: Set<String>, limit: Int = 4) -> [String] {
        guard k < 64 else { return [] }
        let bit: UInt64 = 1 << UInt64(k)
        let subjectUnits = Set(subject.map(MGSolidDocument.unitID))
        var counts: [String: Int] = [:], first: [String: Int] = [:]
        for cell in 0..<owner.count where cover[cell] & bit != 0 {
            let o = Int(owner[cell])
            guard o >= 0, groupBits[o] & bit == 0, !subject.contains(parts[o]) else { continue }
            let u = MGSolidDocument.unitID(parts[o])
            let id = subjectUnits.contains(u) ? parts[o] : u
            counts[id, default: 0] += 1
            if first[id] == nil { first[id] = o }
        }
        return counts.keys.sorted { counts[$0]! != counts[$1]! ? counts[$0]! > counts[$1]! : first[$0]! < first[$1]! }.prefix(limit).map { $0 }
    }
}

extension MGSolidDocument {
    /// The unit of a part: its first id segment (the text before the first "."), so a component instance's parts share
    /// their instance id and a plain part is its own unit (`unitParts`).
    public static func unitID(_ part: String) -> String { String(part.prefix { $0 != "." }) }

    /// The units in assembly order of their first part.
    var unitOrder: [String] {
        var out: [String] = [], seen = Set<String>()
        for p in assembly.parts { let u = MGSolidDocument.unitID(p.id); if seen.insert(u).inserted { out.append(u) } }
        return out
    }

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
            return MGFramedStill(still: still, shot: shot, window: MGSolidFraming.Window(titleBand: title, captionBand: caption), rule: clear.rule,
                                 wholeInstances: authoredInstances(step: i))
        }
    }

    /// The subject rule (`subjectIssues`) and the small-unit rule (`smallUnits`) over `stills`, on one raster per still.
    public func stillMeasures(_ stills: [MGFramedStill], width: Int = MGAnnotationAnchorRules.width, height: Int = MGAnnotationAnchorRules.height,
                              ghosts: ((MGFramedStill) -> [String])? = nil) -> (subjects: [MGSubjectSmall], small: [MGSmallUnit]) {
        var named = Set<String>()
        for f in stills { named.formUnion(namedUnits(f)) }
        let rasters = stills.map { f -> MGStillRaster? in
            let subject = MGSolidFraming.subjectParts(self, shot: f.shot)
            var groups = MGSolidFraming.subjectGroups(self, subject.parts, whole: f.wholeInstances).map(\.parts)
            groups += unitsShown(f.still, named).map { u in unitParts(of: u).map(\.id) }
            guard !groups.isEmpty else { return nil }
            return MGStillRaster(self, f.still, groups: groups)
        }
        return (subjectIssues(stills, rasters: rasters, ghosts: ghosts), smallUnits(stills, rasters: rasters, width: width, height: height))
    }

    /// The named units a still shows solid, in unit order (the small-unit groups of its raster, after the subject groups).
    func unitsShown(_ v: MGAnnotationAnchorView, _ units: Set<String>) -> [String] {
        unitOrder.filter { u in
            units.contains(u) && unitParts(of: u).contains { !v.view.part($0.id).hidden && v.view.part($0.id).opacity >= MGSolidFraming.blockingOpacity }
        }
    }

    /// The subject rule at each still (docs/SOLID-3D.md, "Subject first"): the still's subject
    /// (`MGSolidFraming.subjectParts`) by group (`subjectGroups`), each group's visible pixels and the shorter side of
    /// their box on the still's raster (`MGStillRaster`), against `subjectAreaShare` of the safe window's pixels and
    /// `subjectExtentPixels` × height / 800; the subject's fill against `subjectFill`; and no subject part cut
    /// (`MGSolidFraming.cutParts`). One issue per still that misses any, in still order. A still whose raster is over
    /// budget is not measured.
    /// `ghosts(still)` gives the view's own `ghost` list as written; by default the compiled source's step list
    /// (`authoredGhost(step:)`; an explainer's solid holds its beats' views as steps).
    public func subjectIssues(_ stills: [MGFramedStill], ghosts: ((MGFramedStill) -> [String])? = nil) -> [MGSubjectSmall] {
        subjectIssues(stills, rasters: nil, ghosts: ghosts)
    }

    /// `subjectIssues` reading `rasters[k]` (subject groups first) for still `k` when given.
    func subjectIssues(_ stills: [MGFramedStill], rasters: [MGStillRaster?]?, ghosts: ((MGFramedStill) -> [String])?) -> [MGSubjectSmall] {
        let ghosts = ghosts ?? { self.authoredGhost(step: $0.still.step) }
        return stills.enumerated().compactMap { index, f in
            let subject = MGSolidFraming.subjectParts(self, shot: f.shot)
            // Every still with a subject, whatever its rule (a far target can make it a whole-model still).
            guard !subject.parts.isEmpty else { return nil }
            let v = f.still
            let aspect = v.width / v.height
            let groups = MGSolidFraming.subjectGroups(self, subject.parts, whole: f.wholeInstances)
            guard let raster = rasters.map({ $0[index] }) ?? MGStillRaster(self, v, groups: groups.map(\.parts)) else { return nil }
            let w = f.window.usable
            let windowPixels = (w.right - w.left) / 2 * v.width * (w.top - w.bottom) / 2 * v.height
            let minPixels = Int((MGSolidFraming.subjectAreaShare * windowPixels).rounded())
            let minExtent = MGSolidFraming.subjectExtentPixels * v.height / MGSolidRenderPlan.referenceHeight
            var out: [MGSubjectSmall.Group] = [], small: [Int] = []
            for (k, g) in groups.enumerated() {
                let m = raster.visible(k)
                let whole = g.unit == MGSolidDocument.unitID(g.parts[0]) && Set(unitParts(of: g.parts[0]).map(\.id)) == Set(g.parts)
                let isSmall = m.pixels < minPixels || m.extent < minExtent
                if isSmall { small.append(k) }
                out.append(.init(unit: g.unit, parts: g.parts, pixels: m.pixels, extent: m.extent,
                                 hiddenBy: isSmall ? raster.coveredBy(k, subject: Set(subject.parts)) : [], whole: whole))
            }
            let pts = MGSolidFraming.Samples(assembly, ids: subject.parts).world(assembly, v.params, stage: v.stage)
            let fill = MGSolidFraming.filled(pts, camera: v.camera, aspect: aspect, window: f.window)
            let cut = MGSolidFraming.cutParts(self, view: v.view, params: v.params, camera: v.camera, aspect: aspect, window: f.window,
                                              ids: subject.parts, stage: v.stage)
            guard !small.isEmpty || !cut.isEmpty || fill < MGSolidFraming.subjectFill else { return nil }
            // The drawn annotations whose targets lie off the subject widen the framing: the `annotate` repair.
            let dropped = Set(v.view.arrowDrops.map(\.id)), inSubject = Set(subject.parts)
            let drawn = (checkedAnnotations(v.view, params: v.params) ?? []).filter { !dropped.contains($0) }
            let far = drawn.filter { id in
                guard annotations.label(id) != nil || annotations.arrow(id) != nil else { return false }
                return !MGSolidAnnotationEngine.anchors(annotations, id).contains { $0.part.map(inSubject.contains) ?? false }
            }
            return MGSubjectSmall(step: v.step, beat: v.beat, groups: out, small: small, cut: cut, fill: fill, minimumPixels: minPixels,
                                  minimumExtent: minExtent, existingGhost: ghosts(f), farAnnotations: far,
                                  keepAnnotations: drawn.filter { !far.contains($0) })
        }
    }

    /// The strings of a JSON array (other values skipped); empty for anything else.
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

    /// The instance ids that step `step` names whole in its authored `focus` or `highlight` (an id that is a unit with
    /// more than one part).
    func authoredInstances(step: Int?) -> Set<String> {
        guard let step, case .object(let o) = source, case .array(let steps)? = o["steps"], steps.indices.contains(step),
              case .object(let s) = steps[step] else { return [] }
        return instances(MGSolidDocument.strings(s["focus"]) + MGSolidDocument.strings(s["highlight"]))
    }

    /// The ids of `selectors` that name a whole instance (a unit with more than one part).
    func instances(_ selectors: [String]) -> Set<String> {
        Set(selectors.filter { MGSolidDocument.unitID($0) == $0 && unitParts(of: $0).count > 1 })
    }

    /// The units that a still names: the units of the parts that the labels and arrows it shows (not dropped) ride on,
    /// and of the parts its shot highlights.
    func namedUnits(_ f: MGFramedStill) -> Set<String> {
        var parts = f.shot.highlight
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
        smallUnits(stills, rasters: nil, width: width, height: height)
    }

    /// `smallUnits` reading `rasters[k]` for still `k` when given (its unit groups follow the still's subject groups).
    func smallUnits(_ stills: [MGFramedStill], rasters: [MGStillRaster?]?, width: Int, height: Int) -> [MGSmallUnit] {
        var named = Set<String>()
        for f in stills { named.formUnion(namedUnits(f)) }
        guard !named.isEmpty else { return [] }
        let minimum = MGSmallUnitRules.minimumPixels(width: width, height: height)
        var best: [String: (px: Int, step: Int?, beat: Int?)] = [:], shown: [String: Int] = [:], over = Set<String>()
        for (index, f) in stills.enumerated() {
            let px: [String: Int]
            if let rasters {
                let shown = unitsShown(f.still, named)
                if shown.isEmpty { px = [:] } else {
                    guard let r = rasters[index] else { continue }
                    let offset = MGSolidFraming.subjectGroups(self, MGSolidFraming.subjectParts(self, shot: f.shot).parts, whole: f.wholeInstances).count
                    var out: [String: Int] = [:]
                    for (k, u) in shown.enumerated() where offset + k < 64 { out[u] = r.visible(offset + k).pixels }
                    px = out
                }
            } else {
                guard let p = unitPixels(f.still, units: named) else { continue }
                px = p
            }
            for u in unitOrder {
                guard let n = px[u] else { continue }
                shown[u, default: 0] += 1
                if n >= minimum { over.insert(u) }
                if n > (best[u]?.px ?? -1) { best[u] = (n, f.still.step, f.still.beat) }
            }
        }
        return unitOrder.compactMap { u in
            guard named.contains(u), !over.contains(u), let b = best[u], let n = shown[u] else { return nil }
            return MGSmallUnit(unit: u, pixels: b.px, step: b.step, beat: b.beat, stills: n, minimum: minimum, width: width, height: height)
        }
    }

    /// The pixels each unit of `units` covers in a still, for the units the still shows solid (a part not hidden, at a
    /// view opacity of at least `MGSolidFraming.blockingOpacity`), on the still's raster (`MGStillRaster`): a cell
    /// counts for the unit whose surface is nearest there. Nil when the raster is over budget or the camera is not usable.
    func unitPixels(_ v: MGAnnotationAnchorView, units: Set<String>) -> [String: Int]? {
        let shown = unitsShown(v, units)
        guard !shown.isEmpty else { return [:] }
        guard let r = MGStillRaster(self, v, groups: shown.map { u in unitParts(of: u).map(\.id) }) else { return nil }
        var out: [String: Int] = [:]
        for (k, u) in shown.prefix(64).enumerated() { out[u] = r.visible(k).pixels }
        return out
    }
}
