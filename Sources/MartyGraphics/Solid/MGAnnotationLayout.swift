// SPDX-License-Identifier: Apache-2.0
import Foundation

// Placement of annotation text on screen: a core perspective projection, the text box metric, the safe frame, 24
// candidate positions per text, hard rules, a score, a callout list for text that cannot be placed, and hysteresis
// between frames. One pure function serves the SceneKit overlay, the CLI render and the snapshot. Also the occlusion
// ray test (with a triangle budget) and `MGSolidAnnotations.frame`, the per-frame record a clip will carry.
// Foundation only, deterministic: the same input always gives the same records, in every process.

/// A rectangle in view pixels (origin top-left, y down).
public struct MGAnnotationRect: Equatable, Sendable {
    public var x: Double, y: Double, width: Double, height: Double
    public init(x: Double, y: Double, width: Double, height: Double) { self.x = x; self.y = y; self.width = width; self.height = height }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var isFinite: Bool { x.isFinite && y.isFinite && width.isFinite && height.isFinite }
    /// True when the rectangles overlap or come closer than `gap`.
    public func intersects(_ o: MGAnnotationRect, gap: Double = 0) -> Bool {
        x < o.maxX + gap && o.x < maxX + gap && y < o.maxY + gap && o.y < maxY + gap
    }
    public func overlapArea(_ o: MGAnnotationRect) -> Double {
        max(0, min(maxX, o.maxX) - max(x, o.x)) * max(0, min(maxY, o.maxY) - max(y, o.y))
    }
    public func contains(_ o: MGAnnotationRect) -> Bool { o.x >= x && o.y >= y && o.maxX <= maxX && o.maxY <= maxY }
    /// The point of the rectangle nearest to `p`.
    public func nearest(_ p: MGVec2) -> MGVec2 { MGVec2(min(max(p.x, x), maxX), min(max(p.y, y), maxY)) }
}

/// The core perspective projection of `MGSolidCamera` (Y-up world) to view pixels (origin top-left). It matches
/// `MGSolidRenderer.project(_:width:height:)`.
public struct MGAnnotationProjection: Equatable, Sendable {
    public var camera: MGSolidCamera
    public var width: Double
    public var height: Double
    public init(camera: MGSolidCamera, width: Double, height: Double) { self.camera = camera; self.width = width; self.height = height }

    /// Pixel position of a world (Y-up) point; nil behind the camera or for non-finite input.
    public func project(_ p: MGVec3) -> MGVec2? {
        let c = camera
        guard width > 0, height > 0, width.isFinite, height.isFinite, c.target.count == 3 else { return nil }
        let aspect = width / height
        let fwd = (c.targetVector - c.position).normalized
        let right = fwd.cross(c.up).normalized, up = right.cross(fwd)
        let d = p - c.position
        let z = d.dot(fwd)
        guard z > 1e-6, z.isFinite else { return nil }
        let f = 1 / tan(c.fieldOfView * .pi / 360)
        let x = d.dot(right) / z * f / aspect, y = d.dot(up) / z * f
        let out = MGVec2((x + 1) / 2 * width, (1 - y) / 2 * height)
        return out.x.isFinite && out.y.isFinite ? out : nil
    }
}

/// Where one annotation text is drawn. Coordinates are normalised to the view (0...1, origin top-left), so a renderer
/// of any size with the same aspect draws the same layout.
public struct MGAnnotationPlacement: Codable, Equatable, Sendable {
    public var id: String
    /// `label`, `arrow` or `dimension`.
    public var kind: String
    /// The text drawn (a callout entry has no number prefix here; draw "<callout + 1>. text").
    public var text: String
    /// The text box `[x, y, width, height]`; for a callout entry, its row in the callout list.
    public var box: [Double]
    /// Where the leader meets the box; nil for a callout entry.
    public var leader: [Double]?
    /// The projected anchor (the label anchor, or the arrow or dimension midpoint); nil when it is off view.
    public var anchor: [Double]?
    /// True: the anchor is behind an opaque part (hollow dot, dashed leader). False: visible. Nil: unknown (the
    /// occlusion test ran over its budget); drawn as visible.
    public var occluded: Bool?
    /// Index in the callout list (0-based; the marker shows `callout + 1`), nil when the text is placed.
    public var callout: Int?
    /// The candidate position used (0...23), nil for a callout entry; the next frame keeps it while it stays valid.
    public var candidate: Int?
    /// True when the anchor is outside the view (the callout row ends with "(off view)").
    public var offView: Bool

    enum CodingKeys: String, CodingKey { case id, kind, text, box, leader, anchor, occluded, callout, candidate, offView }
    public init(id: String, kind: String, text: String, box: [Double], leader: [Double]?, anchor: [Double]?, occluded: Bool?,
                callout: Int?, candidate: Int?, offView: Bool) {
        self.id = id; self.kind = kind; self.text = text; self.box = box; self.leader = leader; self.anchor = anchor
        self.occluded = occluded; self.callout = callout; self.candidate = candidate; self.offView = offView
    }
    /// Every optional field is written, as `null` when absent, so other renderers read one fixed shape.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(kind, forKey: .kind); try c.encode(text, forKey: .text)
        try c.encode(box, forKey: .box); try c.encode(leader, forKey: .leader); try c.encode(anchor, forKey: .anchor)
        try c.encode(occluded, forKey: .occluded); try c.encode(callout, forKey: .callout); try c.encode(candidate, forKey: .candidate)
        try c.encode(offView, forKey: .offView)
    }
}

/// The annotation record of one frame: placements plus the posed anchor points (world, Y-up, mm) of every visible
/// annotation. A clip export carries one per frame.
public struct MGAnnotationFrame: Codable, Equatable, Sendable {
    public struct Anchors: Codable, Equatable, Sendable {
        public var id: String
        /// x, y, z per point: a label's anchor; an arrow's from and to (a turn: arc start and tip); a dimension's
        /// a, (vertex,) b.
        public var points: [[Double]]
    }
    /// View size the layout was computed for (pixels).
    public var width: Double
    public var height: Double
    /// Font size in pixels at that size (`MGAnnotationLayout.fontSize`).
    public var fontSize: Double
    public var placement: [MGAnnotationPlacement]
    public var anchors: [Anchors]
    /// Why the frame lays out nothing, or nil: `unchecked` (the view or the pose is not one the engine checked,
    /// `MGSolidDocument.checkedAnnotations`) or `viewSize` (the view size is not finite and positive).
    public var refusal: MGAnnotationFrameRefusal?
}

/// Why `MGSolidAnnotations.frame` laid out nothing.
public enum MGAnnotationFrameRefusal: String, Codable, Equatable, Sendable {
    /// The view did not come from `MGSolidDocument.view(step:)`, lists an annotation its step does not show, or the
    /// pose lies outside the poses the step shows.
    case unchecked
    /// The view size is not finite and positive (at most 100,000 pixels a side).
    case viewSize
}

/// Deterministic text placement (docs/SOLID-3D.md, Annotations, Placement).
public enum MGAnnotationLayout {
    /// Gap between boxes, anchor dot radius, view inset (pixels).
    public static let gap = 4.0, dotRadius = 6.0, inset = 12.0
    /// Candidate radii (8 directions each, 24 candidates).
    public static let radii = [24.0, 48.0, 72.0]
    /// Longest leader as a fraction of the view diagonal.
    public static let maxLeader = 0.3
    /// Caption band (bottom, when a caption shows), legend corner (top right) and title band (top, when the host
    /// draws a title) as fractions of the view.
    public static let captionBand = 0.2, legendWidth = 0.3, legendHeight = 0.1, titleBand = 0.14
    /// Size `MGSolidAnnotations.frame(…aspect:…)` and the snapshot lay out at (height in pixels; width = height × aspect).
    public static let referenceHeight = 800.0

    /// Font size f = clamp(round(0.022 × height), 11, 20) pixels.
    public static func fontSize(height: Double) -> Double {
        guard height.isFinite else { return 11 }
        return min(20, max(11, (0.022 * height).rounded()))
    }
    /// Text box: width 0.58 × f × (scalars of the longest line) + 2 × 6, height 1.3 × f × lines + 2 × 4, with the
    /// lines of `lines(_:)` (one line up to `lineScalars`, else two). So a box is at most 0.58 × f × 40 + 12 wide and
    /// 2.6 × f + 8 high for an annotation text (at most 60 scalars), and a one-line text keeps its earlier box. The
    /// renderer shrinks its font if its real text is wider, so text never overflows the box.
    public static func boxSize(_ text: String, fontSize f: Double) -> (width: Double, height: Double) {
        let l = lines(text)
        let widest = l.map { $0.unicodeScalars.count }.max() ?? 0
        return (0.58 * f * Double(widest) + 12, 1.3 * f * Double(l.count) + 8)
    }

    /// Longest text drawn on one line (Unicode scalars).
    public static let lineScalars = 40

    /// The lines a text draws on: the text itself up to `lineScalars` scalars (or when it holds a line break, which
    /// annotation text cannot); a longer text breaks at the space nearest its middle whose two halves are at most
    /// `lineScalars` each (the earlier space on a tie), or, with no such space, at the character boundary nearest the
    /// middle. The space at the break is dropped. Two lines at most. A line still over `lineScalars` (no legal break:
    /// a text over 80 scalars, or very long characters a host builds in code) is cut at a character boundary and ends in
    /// "…", so no line exceeds `lineScalars` and no box exceeds its bound. Deterministic.
    public static func lines(_ text: String) -> [String] {
        let n = text.unicodeScalars.count
        guard n > lineScalars, !text.contains("\n") else { return [text] }
        return split(text).map(bounded).filter { !$0.isEmpty }
    }

    /// `line` itself when it holds at most `lineScalars` scalars; else its longest prefix of whole characters (or, for
    /// one character longer than that, of scalars) of `lineScalars` − 1 scalars, then "…".
    static func bounded(_ line: String) -> String {
        guard line.unicodeScalars.count > lineScalars else { return line }
        var out = "", used = 0
        for c in line {
            let k = c.unicodeScalars.count
            guard used + k <= lineScalars - 1 else { break }
            out.append(c); used += k
        }
        if out.isEmpty { out = String(String.UnicodeScalarView(line.unicodeScalars.prefix(lineScalars - 1))) }
        return out + "…"
    }

    /// The two-line break of `lines`, before the bound.
    static func split(_ text: String) -> [String] {
        let n = text.unicodeScalars.count
        let chars = Array(text)
        var prefix = [0]
        for c in chars { prefix.append(prefix.last! + c.unicodeScalars.count) }
        let mid = Double(n) / 2
        var best: (k: Int, d: Double)?
        for (k, c) in chars.enumerated() where c == " " {
            let left = prefix[k], right = n - prefix[k + 1]
            guard left > 0, right > 0, left <= lineScalars, right <= lineScalars else { continue }
            let d = abs(Double(prefix[k]) - mid)
            if best == nil || d < best!.d { best = (k, d) }
        }
        if let b = best { return [String(chars[..<b.k]), String(chars[(b.k + 1)...])] }
        var cut = 1, cd = Double.infinity
        for k in 1..<chars.count {
            let d = abs(Double(prefix[k]) - mid)
            if d < cd { cd = d; cut = k }
        }
        return [String(chars[..<cut]), String(chars[cut...])]
    }

    /// One text to place.
    public struct Item: Equatable, Sendable {
        public enum Kind: String, Equatable, Sendable { case label, arrow, dimension }
        public var id: String
        public var kind: Kind
        public var text: String
        /// The projected anchor (pixels); nil when it is behind the camera.
        public var attach: MGVec2?
        /// The projected direction of the arrow or dimension line; the first candidate is offset perpendicular to it.
        public var line: MGVec2?
        /// Labels draw an anchor dot, which no box may cover.
        public var dot: Bool
        public var occluded: Bool?
        public init(id: String, kind: Kind, text: String, attach: MGVec2?, line: MGVec2? = nil, dot: Bool, occluded: Bool? = false) {
            self.id = id; self.kind = kind; self.text = text; self.attach = attach; self.line = line; self.dot = dot; self.occluded = occluded
        }
    }

    public struct Input: Equatable, Sendable {
        /// At most `MGSolidAnnotationLimits.visible`, in placement order (labels, arrow texts, dimension texts).
        public var items: [Item]
        public var width: Double
        public var height: Double
        /// A caption band shows at the bottom.
        public var caption: Bool
        /// The host draws a title band at the top.
        public var title: Bool
        /// Projected screen boxes of highlighted parts (placements avoid covering them).
        public var highlight: [MGAnnotationRect]
        /// Projected centre of the model; the first candidate points away from it.
        public var centre: MGVec2?
        /// The previous frame's placements (a text keeps its candidate while it stays valid).
        public var previous: [MGAnnotationPlacement]
        public init(items: [Item], width: Double, height: Double, caption: Bool = false, title: Bool = false,
                    highlight: [MGAnnotationRect] = [], centre: MGVec2? = nil, previous: [MGAnnotationPlacement] = []) {
            self.items = items; self.width = width; self.height = height; self.caption = caption; self.title = title
            self.highlight = highlight; self.centre = centre; self.previous = previous
        }
    }

    /// The safe frame: the view inset by 12 px, minus the caption band, minus the title band. The legend corner is
    /// excluded separately (`legendRect`).
    public static func safeFrame(width w: Double, height h: Double, caption: Bool, title: Bool) -> MGAnnotationRect {
        let top = inset + (title ? titleBand * h : 0)
        let bottom = inset + (caption ? captionBand * h : 0)
        return MGAnnotationRect(x: inset, y: top, width: max(0, w - 2 * inset), height: max(0, h - top - bottom))
    }
    public static func legendRect(width w: Double, height h: Double) -> MGAnnotationRect {
        MGAnnotationRect(x: w * (1 - legendWidth), y: 0, width: w * legendWidth, height: h * legendHeight)
    }

    /// Places every item: a text box at one of 24 candidates that passes the hard rules with the lowest score, or a
    /// numbered marker with its text in the callout list. Never drops an item; boxes never overlap. Nil (a bounded
    /// refusal) for more than `MGSolidAnnotationLimits.visible` items or a view size that is not finite and positive.
    public static func place(_ input: Input) -> [MGAnnotationPlacement]? {
        var trace: [String: String] = [:]
        return place(input, trace: &trace)
    }

    /// `trace[id]`: `kept` (previous candidate still valid), `invalid` (previous candidate no longer valid, so it
    /// moved), `new`, `callout` or `offView`.
    static func place(_ input: Input, trace: inout [String: String]) -> [MGAnnotationPlacement]? {
        let w = input.width, h = input.height
        guard input.items.count <= MGSolidAnnotationLimits.visible, w.isFinite, h.isFinite, w > 0, h > 0, w <= 100_000, h <= 100_000 else { return nil }
        let f = fontSize(height: h)
        let safe = safeFrame(width: w, height: h, caption: input.caption, title: input.title)
        let legend = legendRect(width: w, height: h)
        let diag = (w * w + h * h).squareRoot()
        func onView(_ p: MGVec2?) -> MGVec2? {
            guard let p, p.x.isFinite, p.y.isFinite, p.x >= 0, p.y >= 0, p.x <= w, p.y <= h else { return nil }
            return p
        }
        let dots = input.items.compactMap { $0.dot ? onView($0.attach) : nil }
        let previous = Dictionary(input.previous.map { ($0.id, $0.candidate) }, uniquingKeysWith: { a, _ in a })
        let centre: MGVec2? = input.centre.flatMap { $0.x.isFinite && $0.y.isFinite ? $0 : nil }

        func callText(_ item: Item, _ off: Bool) -> String { item.text + (off ? " (off view)" : "") }
        func rowSize(_ item: Item, _ n: Int, _ off: Bool) -> (width: Double, height: Double) { boxSize("\(n). " + callText(item, off), fontSize: f) }

        struct Attempt { var boxes: [Int: (MGAnnotationRect, MGVec2, Int)] = [:]; var callouts: [Int] = []; var trace: [String: String] = [:] }
        func candidates(_ item: Item, _ p: MGVec2) -> [(MGAnnotationRect, MGVec2)] {
            let size = boxSize(item.text, fontSize: f)
            var a0 = -Double.pi / 2
            if let c = centre { let d = p - c; if d.length > 1e-9 { a0 = atan2(d.y, d.x) } }
            if let l = item.line, l.x.isFinite, l.y.isFinite, l.length > 1e-9 {
                var n = MGVec2(-l.y, l.x)
                if let c = centre, n.dot(p - c) < 0 { n = -n }
                a0 = atan2(n.y, n.x)
            }
            var out: [(MGAnnotationRect, MGVec2)] = []
            for r in radii {
                for k in 0..<8 {
                    // Screen y points down, so increasing angles turn clockwise.
                    let t = a0 + Double(k) * Double.pi / 4
                    let d = MGVec2(cos(t), sin(t))
                    let c = p + d * r + MGVec2(d.x * size.width / 2, d.y * size.height / 2)
                    let box = MGAnnotationRect(x: c.x - size.width / 2, y: c.y - size.height / 2, width: size.width, height: size.height)
                    out.append((box, box.nearest(p)))
                }
            }
            return out
        }
        func crosses(_ a: MGVec2, _ b: MGVec2, _ c: MGVec2, _ d: MGVec2) -> Bool {
            let d1 = (b - a).cross(c - a), d2 = (b - a).cross(d - a), d3 = (d - c).cross(a - c), d4 = (d - c).cross(b - c)
            return d1 * d2 < 0 && d3 * d4 < 0
        }
        func covers(_ box: MGAnnotationRect, _ p: MGVec2) -> Bool { (box.nearest(p) - p).length < dotRadius }

        func attempt(reserved: MGAnnotationRect?) -> Attempt {
            var out = Attempt()
            var leaders: [(MGVec2, MGVec2)] = []
            for (i, item) in input.items.enumerated() {
                guard let p = onView(item.attach) else { out.callouts.append(i); out.trace[item.id] = "offView"; continue }
                let cands = candidates(item, p)
                func valid(_ k: Int) -> Bool {
                    let (box, end) = cands[k]
                    guard box.isFinite, safe.contains(box), !box.intersects(legend) else { return false }
                    if let r = reserved, box.intersects(r, gap: gap) { return false }
                    for (b, _, _) in out.boxes.values where box.intersects(b, gap: gap) { return false }
                    for d in dots where covers(box, d) { return false }
                    return (end - p).length <= maxLeader * diag
                }
                var chosen: Int?
                if let pk = previous[item.id] ?? nil, (0..<cands.count).contains(pk) {
                    if valid(pk) { chosen = pk; out.trace[item.id] = "kept" } else { out.trace[item.id] = "invalid" }
                } else { out.trace[item.id] = "new" }
                if chosen == nil {
                    var best: (k: Int, score: Double)?
                    for k in cands.indices where valid(k) {
                        let (box, end) = cands[k]
                        let overlap = input.highlight.reduce(0.0) { $0 + ($1.isFinite ? box.overlapArea($1) : 0) }
                        let crossings = leaders.filter { crosses(p, end, $0.0, $0.1) }.count
                        let score = overlap + 0.5 * (end - p).length + 1000 * Double(crossings)
                        if best == nil || score < best!.score { best = (k, score) }
                    }
                    chosen = best?.k
                }
                guard let k = chosen else { out.callouts.append(i); out.trace[item.id] = "callout"; continue }
                out.boxes[i] = (cands[k].0, cands[k].1, k)
                leaders.append((p, cands[k].1))
            }
            return out
        }
        /// The callout list: rows from the bottom left of the safe frame upward, in item order.
        func rows(_ callouts: [Int]) -> [Int: MGAnnotationRect] {
            let ordered = callouts.sorted()
            var out: [Int: MGAnnotationRect] = [:]
            for (n, i) in ordered.enumerated() {
                let item = input.items[i]
                let size = rowSize(item, n + 1, onView(item.attach) == nil)
                let y = safe.maxY - Double(ordered.count - n) * (size.height + gap) + gap
                out[i] = MGAnnotationRect(x: safe.x, y: y, width: size.width, height: size.height)
            }
            return out
        }
        func area(_ r: [Int: MGAnnotationRect]) -> MGAnnotationRect? {
            guard !r.isEmpty else { return nil }
            let xs = r.values
            let x0 = xs.map(\.x).min()!, y0 = xs.map(\.y).min()!
            return MGAnnotationRect(x: x0, y: y0, width: xs.map(\.maxX).max()! - x0, height: xs.map(\.maxY).max()! - y0)
        }
        // Reserve the callout list's area and place again until the callout set stops changing (bounded).
        var result = attempt(reserved: nil)
        var reserved: MGAnnotationRect?
        for _ in 0..<MGSolidAnnotationLimits.visible {
            guard let r = area(rows(result.callouts)) else { break }
            let grown = reserved.map { MGAnnotationRect(x: min($0.x, r.x), y: min($0.y, r.y), width: max($0.maxX, r.maxX) - min($0.x, r.x),
                                                         height: max($0.maxY, r.maxY) - min($0.y, r.y)) } ?? r
            if grown == reserved { break }
            reserved = grown
            let next = attempt(reserved: reserved)
            if Set(next.callouts) == Set(result.callouts) { result = next; break }
            result = next
        }
        // A placed box that still touches the final callout list moves into it (each move shrinks the placed set).
        while let r = area(rows(result.callouts)), let i = result.boxes.keys.sorted().first(where: { result.boxes[$0]!.0.intersects(r, gap: gap) }) {
            result.boxes[i] = nil
            result.callouts.append(i)
            result.trace[input.items[i].id] = "callout"
        }
        let callRows = rows(result.callouts)
        let order = result.callouts.sorted()
        trace = result.trace
        func norm(_ r: MGAnnotationRect) -> [Double] { [r.x / w, r.y / h, r.width / w, r.height / h] }
        func norm(_ p: MGVec2) -> [Double] { [p.x / w, p.y / h] }
        return input.items.enumerated().map { i, item in
            let p = onView(item.attach)
            if let (box, end, k) = result.boxes[i] {
                return MGAnnotationPlacement(id: item.id, kind: item.kind.rawValue, text: item.text, box: norm(box), leader: norm(end),
                                             anchor: p.map(norm), occluded: item.occluded, callout: nil, candidate: k, offView: false)
            }
            return MGAnnotationPlacement(id: item.id, kind: item.kind.rawValue, text: callText(item, p == nil), box: norm(callRows[i]!),
                                         leader: nil, anchor: p.map(norm), occluded: item.occluded, callout: order.firstIndex(of: i),
                                         candidate: nil, offView: p == nil)
        }
    }
}

// MARK: Occlusion

enum MGAnnotationOcclusion {
    /// For each kernel-world point: is the segment from the eye to it blocked by a part that the view shows at opacity
    /// 0.5 or more (cut parts test their cut mesh)? Each part's posed bounds are tested first. Nil once the triangle
    /// tests of this call would pass `budget`, for that point and every later one.
    static func test(_ points: [MGVec3], eye: MGVec3, document doc: MGSolidDocument, view: MGSolidView, pose: MGPose,
                     budget: Int = MGSolidAnnotationLimits.occlusionTests) -> [Bool?] {
        let tol = max(1e-6, 1e-3 * doc.annotations.diagonal)
        struct Solid { let mesh: MGMesh; let transform: MGTransform; let inverse: MGTransform; let bounds: MGBounds }
        var solids: [Solid] = []
        for p in doc.assembly.parts {
            let pv = view.part(p.id)
            // A part the view hides is not drawn, so it hides no anchor.
            guard pv.opacity >= 0.5, !pv.hidden else { continue }
            let mesh = pv.cut?.mesh ?? p.mesh
            let t = pose.world[p.id] ?? .identity
            solids.append(Solid(mesh: mesh, transform: t, inverse: t.inverse, bounds: MGSolidFrames.worldBounds(mesh.bounds, t)))
        }
        var used = 0, over = false
        return points.map { x -> Bool? in
            guard !over else { return nil }
            let d = x - eye, len = d.length
            guard len > tol, len.isFinite else { return false }
            for s in solids where segmentHits(eye, x, s.bounds) {
                if used + s.mesh.triangleCount > budget { over = true; return nil }
                used += s.mesh.triangleCount
                let a = s.inverse.apply(eye), b = s.inverse.apply(x)
                if blocked(a, b, s.mesh, before: 1 - tol / len, after: 1e-9) { return true }
            }
            return false
        }
    }

    /// Slab test of the segment from `a` to `b` against a box.
    static func segmentHits(_ a: MGVec3, _ b: MGVec3, _ box: MGBounds) -> Bool {
        guard !box.isEmpty else { return false }
        var lo = 0.0, hi = 1.0
        let d = b - a
        for (o, v, mn, mx) in [(a.x, d.x, box.min.x, box.max.x), (a.y, d.y, box.min.y, box.max.y), (a.z, d.z, box.min.z, box.max.z)] {
            if abs(v) < 1e-12 { if o < mn || o > mx { return false }; continue }
            let t1 = (mn - o) / v, t2 = (mx - o) / v
            lo = max(lo, min(t1, t2)); hi = min(hi, max(t1, t2))
            if lo > hi { return false }
        }
        return true
    }

    /// True when a triangle of `mesh` crosses the segment `a + t (b − a)` with `after < t < before` (Möller–Trumbore).
    static func blocked(_ a: MGVec3, _ b: MGVec3, _ mesh: MGMesh, before: Double, after: Double) -> Bool {
        let d = b - a
        for i in 0..<mesh.triangleCount {
            let (i0, i1, i2) = mesh.triangle(i)
            guard i0 < mesh.positions.count, i1 < mesh.positions.count, i2 < mesh.positions.count else { continue }
            let p0 = mesh.positions[i0], e1 = mesh.positions[i1] - p0, e2 = mesh.positions[i2] - p0
            let pv = d.cross(e2), det = e1.dot(pv)
            guard abs(det) > 1e-15 else { continue }
            let inv = 1 / det, s = a - p0
            let u = s.dot(pv) * inv
            guard u >= 0, u <= 1 else { continue }
            let q = s.cross(e1), v = d.dot(q) * inv
            guard v >= 0, u + v <= 1 else { continue }
            let t = e2.dot(q) * inv
            if t > after, t < before { return true }
        }
        return false
    }
}

// MARK: Frames

extension MGSolidAnnotations {
    /// The annotation record of one frame at the reference size (`MGAnnotationLayout.referenceHeight`, width = height ×
    /// aspect): placements of every visible text plus the posed anchor points. The snapshot `placement` uses this
    /// function, so a clip frame and a snapshot of the same camera agree.
    public static func frame(document: MGSolidDocument, view: MGSolidView, params: MGPoseParameters, camera: MGSolidCamera,
                             aspect: Double, previous: MGAnnotationFrame? = nil, highlight: [String] = [], caption: Bool = false,
                             stage: MGTransform = MGSolidStage.zUpToYUp) -> MGAnnotationFrame {
        let h = MGAnnotationLayout.referenceHeight
        let w = (aspect.isFinite && aspect > 0 ? min(aspect, 100) : 1.6) * h
        return frame(document: document, view: view, params: params, camera: camera, width: w, height: h, previous: previous,
                     highlight: highlight, caption: caption, stage: stage)
    }

    /// The same record for a view of `width` × `height` pixels. `title`: the host draws a title band at the top.
    public static func frame(document doc: MGSolidDocument, view: MGSolidView, params: MGPoseParameters, camera: MGSolidCamera,
                             width: Double, height: Double, previous: MGAnnotationFrame? = nil, highlight: [String] = [],
                             caption: Bool = false, title: Bool = false, stage: MGTransform = MGSolidStage.zUpToYUp,
                             occlusionBudget: Int = MGSolidAnnotationLimits.occlusionTests) -> MGAnnotationFrame {
        // The one gate: a view or pose the engine did not check shows nothing.
        guard let shown = doc.checkedAnnotations(view, params: params) else {
            return MGAnnotationFrame(width: width, height: height, fontSize: MGAnnotationLayout.fontSize(height: height), placement: [], anchors: [],
                                     refusal: .unchecked)
        }
        let input = layoutInput(document: doc, view: view, params: params, camera: camera, width: width, height: height, previous: previous,
                                highlight: highlight, caption: caption, title: title, stage: stage, occlusionBudget: occlusionBudget)
        let placement = MGAnnotationLayout.place(input)
        let a = doc.annotations, pose = doc.assembly.pose(params)
        func xyz(_ p: MGVec3) -> [Double] { let q = stage.apply(p); return [q.x, q.y, q.z] }
        let anchors = shown.map { id -> MGAnnotationFrame.Anchors in
            var pts: [MGVec3]
            if let r = a.arrow(id) {
                let prims = primitives(doc, id, params: params, sense: view.motionSense, step: view.step)
                pts = r.style == .turn ? [prims[0].start, prims[arcChords].end] : [prims[0].start, prims[1].end]
            } else {
                pts = MGSolidAnnotationEngine.anchors(a, id).map { $0.world(pose) }
            }
            return .init(id: id, points: pts.map(xyz))
        }
        return MGAnnotationFrame(width: width, height: height, fontSize: MGAnnotationLayout.fontSize(height: height), placement: placement ?? [],
                                 anchors: anchors, refusal: placement == nil ? .viewSize : nil)
    }

    /// The layout input `frame` places: projected text anchors with occlusion, highlight boxes and the model centre.
    static func layoutInput(document doc: MGSolidDocument, view: MGSolidView, params: MGPoseParameters, camera: MGSolidCamera,
                            width: Double, height: Double, previous: MGAnnotationFrame?, highlight: [String], caption: Bool, title: Bool,
                            stage: MGTransform, occlusionBudget: Int) -> MGAnnotationLayout.Input {
        let a = doc.annotations
        let pose = doc.assembly.pose(params)
        let proj = MGAnnotationProjection(camera: camera, width: width, height: height)
        let visible = doc.checkedAnnotations(view, params: params) ?? []
        // Placement order: labels (view order), then arrow texts, then dimension texts.
        let ordered = visible.filter { a.kind($0) == "label" } + visible.filter { a.arrow($0)?.text != nil } + visible.filter { a.kind($0) == "dimension" }
        var points: [(id: String, point: MGVec3, line: (MGVec3, MGVec3)?)] = []
        for id in ordered { if let t = attach(doc, id, pose, params, sense: view.motionSense, step: view.step) { points.append((id, t.point, t.line)) } }
        let eye = stage.inverse.apply(camera.position)
        let occluded = MGAnnotationOcclusion.test(points.map(\.point), eye: eye, document: doc, view: view, pose: pose, budget: occlusionBudget)
        var items: [MGAnnotationLayout.Item] = []
        for (k, t) in points.enumerated() {
            let p = proj.project(stage.apply(t.point))
            var line: MGVec2?
            if let (s, e) = t.line, let ps = proj.project(stage.apply(s)), let pe = proj.project(stage.apply(e)) { line = pe - ps }
            let kind: MGAnnotationLayout.Item.Kind = a.kind(t.id) == "label" ? .label : a.kind(t.id) == "arrow" ? .arrow : .dimension
            let text = a.label(t.id)?.text ?? a.arrow(t.id)?.text ?? a.dimension(t.id)?.text ?? ""
            items.append(.init(id: t.id, kind: kind, text: text, attach: p, line: line, dot: kind == .label, occluded: occluded[k]))
        }
        var boxes: [MGAnnotationRect] = []
        for id in highlight {
            guard let part = doc.assembly.part(id), !part.mesh.positions.isEmpty else { continue }
            let t = stage * (pose.world[id] ?? .identity)
            let pts = part.mesh.bounds.corners.map { proj.project(t.apply($0)) }
            guard pts.allSatisfy({ $0 != nil }) else { continue }
            let xs = pts.map { $0!.x }, ys = pts.map { $0!.y }
            boxes.append(MGAnnotationRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!))
        }
        let bounds = doc.assembly.bounds(pose)
        let centre = bounds.isEmpty ? nil : proj.project(stage.apply(bounds.center))
        return MGAnnotationLayout.Input(items: items, width: width, height: height, caption: caption, title: title, highlight: boxes,
                                        centre: centre, previous: previous?.placement ?? [])
    }
}

// MARK: Report

extension MGSolidAnnotations {
    /// The camera a snapshot uses when none is given: the posed bounds (Y-up) framed from yaw 32°, pitch 28°.
    public static func defaultCamera(_ doc: MGSolidDocument, params: MGPoseParameters, aspect: Double = 16.0 / 10,
                                     stage: MGTransform = MGSolidStage.zUpToYUp) -> MGSolidCamera {
        let pose = doc.assembly.pose(params)
        var b = MGBounds.empty
        for p in doc.assembly.parts {
            let t = stage * (pose.world[p.id] ?? .identity)
            for c in p.mesh.bounds.corners { b.include(t.apply(c)) }
        }
        return MGSolidCamera.framing(b, yaw: 32, pitch: 28, aspect: aspect)
    }

    /// For each annotation of `view`: is its text anchor (a label's anchor, an arrow's or dimension line's midpoint)
    /// behind a part the view shows at opacity 0.5 or more, seen from `camera`? Nil when the test ran over its budget.
    public static func occlusion(document doc: MGSolidDocument, view: MGSolidView, params: MGPoseParameters, camera: MGSolidCamera,
                                 stage: MGTransform = MGSolidStage.zUpToYUp,
                                 budget: Int = MGSolidAnnotationLimits.occlusionTests) -> [(id: String, occluded: Bool?)] {
        let pose = doc.assembly.pose(params)
        let ids = view.annotations.filter { doc.annotations.kind($0) != nil }
        let points = ids.map { attach(doc, $0, pose, params, sense: view.motionSense, step: view.step)?.point ?? .zero }
        // Report data, not a display: it tests every requested annotation at the given pose.
        let result = MGAnnotationOcclusion.test(points, eye: stage.inverse.apply(camera.position), document: doc, view: view, pose: pose, budget: budget)
        return Array(zip(ids, result)).map { (id: $0.0, occluded: $0.1) }
    }
}

extension MGSolidDocument {
    /// The check report's `placements`: for the plain view and each step that shows annotations, the placement at the
    /// view's first pose (the default input at the view's explode value) with the snapshot default camera, aspect 16:10
    /// and a caption band on steps, so a model sees which texts fell into the callout list.
    /// `[{"step": n | null, "placement": [...]}]`.
    public var annotationPlacements: MGJSON {
        guard !annotations.isEmpty else { return .array([]) }
        var out: [MGJSON] = []
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        for step in [nil] + steps.indices.map({ Optional($0) }) {
            let view = view(step: step)
            guard !view.annotations.isEmpty else { continue }
            // The view's first pose: the default input at the view's explode value.
            let params = MGPoseParameters(input: defaults.input, explode: MGSolidAnnotationEngine.domain(self, step: step).explode,
                                          placements: MGSolidAnnotationEngine.placements(self, step: step))
            let frame = MGSolidAnnotations.frame(document: self, view: view, params: params,
                                                 camera: MGSolidAnnotations.defaultCamera(self, params: params), aspect: 16.0 / 10,
                                                 highlight: step.map { steps[$0].highlight } ?? [], caption: step != nil)
            guard let data = try? enc.encode(frame.placement), let any = try? JSONSerialization.jsonObject(with: data),
                  let placement = MGJSON(any: any) else { continue }
            out.append(.object(["step": step.map { .number(Double($0 + 1)) } ?? .null, "placement": placement]))
        }
        return .array(out)
    }

    /// The check report's `stillPlacements`: for each still that draws annotations, the placement at the still's
    /// effective camera and pixel size (`framedStills`, `MGExplainerFrame.beatStills`: the camera `marty-solid render`
    /// draws with), `[{"step": n | null, "beat": n | null, "placement": [...]}]` (1-based). `placements` above keeps the
    /// legacy snapshot default camera; this is what each still shows.
    public func stillPlacements(_ stills: [MGFramedStill], title: Bool) -> MGJSON {
        guard !annotations.isEmpty else { return .array([]) }
        var out: [MGJSON] = []
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        for f in stills {
            let v = f.still
            guard !v.view.annotations.isEmpty else { continue }
            let frame = MGSolidAnnotations.frame(document: self, view: v.view, params: v.params, camera: v.camera, width: v.width,
                                                 height: v.height, highlight: f.shot.highlight, caption: f.shot.caption != nil, title: title)
            guard let data = try? enc.encode(frame.placement), let any = try? JSONSerialization.jsonObject(with: data),
                  let placement = MGJSON(any: any) else { continue }
            out.append(.object(["step": v.step.map { .number(Double($0 + 1)) } ?? .null, "beat": v.beat.map { .number(Double($0 + 1)) } ?? .null,
                                "placement": placement]))
        }
        return .array(out)
    }

    /// The check report's `annotations`: one object per annotation in authored order, `{"id", "kind", "meaning",
    /// "tier", "text", "value", "anchorsWorld", "occludedAtDefaultCamera"}`. Anchors are kernel world points (Z up,
    /// mm) at the default input with explode 0; occlusion uses the snapshot's default camera and the plain view of
    /// every part. Empty for a document without annotations.
    public var annotationReport: MGJSON {
        guard !annotations.isEmpty else { return .array([]) }
        let params = MGPoseParameters(input: defaults.input, explode: 0)
        var all = MGSolidView(assembly)
        all.annotations = annotations.ids
        let occluded = Dictionary(MGSolidAnnotations.occlusion(document: self, view: all, params: params,
                                                               camera: MGSolidAnnotations.defaultCamera(self, params: params)).map { ($0.id, $0.occluded) },
                                  uniquingKeysWith: { a, _ in a })
        return .array(annotations.ids.map { id -> MGJSON in
            guard case .object(var o) = describeAnnotation(id, annotations.kind(id) ?? "") else { return .null }
            o["anchorsWorld"] = o.removeValue(forKey: "anchors")
            if o["value"] == nil { o["value"] = .null }
            if annotations.arrow(id)?.style == .line, annotations.arrow(id)?.meaning == .motion, let l = annotations.arrow(id)?.length {
                o["length"] = .number(l)
            }
            o["occludedAtDefaultCamera"] = (occluded[id] ?? nil).map { .bool($0) } ?? .null
            return .object(o)
        })
    }
}
