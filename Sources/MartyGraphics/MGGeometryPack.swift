// SPDX-License-Identifier: Apache-2.0
import Foundation

/// Opt-in geometry pack. It is NOT built in: hosts call `try MGPacks.register(MGGeometryPack.pack)` once per process
/// (a second call throws `duplicatePack`), so the default registry, grammar document and existing scenes are unchanged.
/// Until it is registered, scenes naming `rotate2d` are refused with `template.unknown`.
///
/// `rotate2d` turns a polygon about a pivot. Every coordinate on the board comes from this code:
/// x′ = px + (x − px)·cos θ − (y − py)·sin θ, y′ = py + (x − px)·sin θ + (y − py)·cos θ, in Double, shown with
/// `MGPhysics.format`. A lesson binds a slider to `angle` and the labels follow; a scene author never types a coordinate.
///
/// Board: world 14 × 10 with the origin O at world (7, 5); one maths unit is one world unit.
///
/// Parameters (refused, never clamped): `pts` 3–6 vertices `[x, y]` with x, y in −4.5…4.5; `angle` in degrees
/// −360…360 (default 0); pivot `px`, `py` in −2…2 (default 0); `ghost` 0 or 1 (default 1, draws the original dashed).
/// Rejections: `template.pts.radius` (a vertex's circle about the pivot would leave the board: |px| + r ≤ 6.5 and
/// |py| + r ≤ 4.5), `template.pts.area` (area below 0.25), `template.pts.gap` (two vertices closer than 0.6),
/// `template.pts.count` (fewer than 3 or more than 6). Self-intersecting polygons are not detected.
///
/// Item ids depend only on the vertex count and `ghost`, never on the angle: `xaxis`, `yaxis`, `ghost` (when
/// `ghost` = 1), `shape`, `vA`…, `lA`… (coordinate labels "A (x, y)"), `pivot`, `arc`, `ltheta` ("θ = …").
/// Values: `theta` (°), `ax ay bx by …` (turned), `ax0 ay0 …` (original), `ra rb …` (distance to the pivot), `px`, `py`.
public enum MGGeometryPack {
    public static let width = 14.0, height = 10.0
    /// World position of the maths origin O.
    public static let origin = MGPoint(7, 5)
    public static let letters = ["A", "B", "C", "D", "E", "F"]
    static let colors: [MGColorRole] = [.blue, .orange, .green, .purple, .teal, .red]
    static let minGap = 0.6, minArea = 0.25, arcRadius = 0.8
    static let thetaAt = MGPoint(1.7, 9.3)

    /// Axis-aligned label box in world units.
    struct Box {
        let center: MGPoint, halfWidth: Double, halfHeight: Double
        func intersects(_ o: Box) -> Bool {
            abs(center.x - o.center.x) < halfWidth + o.halfWidth && abs(center.y - o.center.y) < halfHeight + o.halfHeight
        }
        var inside: Bool {
            center.x - halfWidth >= 0.1 && center.x + halfWidth <= width - 0.1 && center.y - halfHeight >= 0.1 && center.y + halfHeight <= height - 0.1
        }
    }

    /// Conservative world-size estimate of a drawn label: the renderer's text box (`MGLayout.textSize`, 14 pt) at the
    /// smallest supported board (1024 × 768 pt, about 70 pt per world unit).
    static func labelBox(text: String, center: MGPoint, callout: Bool = false) -> Box {
        let points = Double(text.count) * 14 * 0.56 + 14 + (callout ? 24 : 0)
        return Box(center: center, halfWidth: points / 70 / 2, halfHeight: (callout ? 0.5 : 0.36) / 2)
    }

    /// Deterministic label placement: outward from the shape's centre first, then turned ±30°, ±60°, … until the box
    /// clears every vertex dot, the pivot, earlier labels and the board edge. Depends only on geometry, never on ids.
    static func placeLabel(_ text: String, at p: MGPoint, outward: MGPoint, avoiding: [Box]) -> Box {
        let base = outward.length > 1e-9 ? atan2(outward.y, outward.x) * 180 / .pi : 90
        var fallback: Box?
        for ring in [0.0, 0.35] {
            for turn in [0.0, 30, -30, 60, -60, 90, -90, 120, -120, 150, -150, 180] {
                let d = MGPoint.polar(base + turn)
                let probe = labelBox(text: text, center: p)
                let box = labelBox(text: text, center: p + MGPoint(d.x * (probe.halfWidth + 0.26 + ring), d.y * (probe.halfHeight + 0.26 + ring)))
                if fallback == nil { fallback = box }
                if box.inside, !avoiding.contains(where: box.intersects) { return box }
            }
        }
        return fallback!
    }

    public static let rotate2d = MGTemplate(
        name: "rotate2d",
        summary: "turn a 3–6 vertex polygon about a pivot; every rotated coordinate and the angle computed locally",
        params: [
            .records("pts", count: 3...6, fields: [.init("x", -4.5...4.5), .init("y", -4.5...4.5)]),
            .init(name: "angle", unit: "°", range: -360...360, defaultValue: 0),
            .init(name: "px", unit: "", range: -2...2, defaultValue: 0),
            .init(name: "py", unit: "", range: -2...2, defaultValue: 0),
            .init(name: "ghost", unit: "", range: 0...1, defaultValue: 1, integer: true),
        ],
        reject: { p in problem(p) },
        make: { p, is3D in is3D || problem(p) != nil ? nil : build(p) })

    public static let pack = MGPack(
        id: "geometry", title: "Geometry: transformations", summary: "rotations with engine-computed coordinates",
        templates: [rotate2d],
        fixtures: [.init(id: "rotate_triangle", title: "Triangle turned by 30°", json: triangleFixture)])

    /// Original synthetic example: triangle A(2, 1), B(4, 1), C(2, 3) turned 30° about the origin.
    public static let triangleFixture = #"{"v":1,"template":"rotate2d","params":{"pts":[[2,1],[4,1],[2,3]],"angle":30}}"#

    /// x′, y′ of `p` turned by `degrees` about `pivot` (maths coordinates).
    public static func rotate(_ p: MGPoint, degrees: Double, pivot: MGPoint) -> MGPoint {
        let a = degrees * .pi / 180, c = cos(a), s = sin(a), d = p - pivot
        return MGPoint(pivot.x + d.x * c - d.y * s, pivot.y + d.x * s + d.y * c)
    }

    static func points(_ p: MGParams) -> [MGPoint] { (p.records["pts"] ?? []).map { MGPoint($0[0], $0[1]) } }

    static func problem(_ p: MGParams) -> String? {
        let pts = points(p), pivot = MGPoint(p["px"], p["py"])
        for v in pts {
            let r = (v - pivot).length
            if abs(pivot.x) + r > 6.5 + 1e-9 || abs(pivot.y) + r > 4.5 + 1e-9 { return "pts.radius" }
        }
        var twice = 0.0
        for (k, a) in pts.enumerated() { let b = pts[(k + 1) % pts.count]; twice += a.x * b.y - b.x * a.y }
        if abs(twice) / 2 < minArea { return "pts.area" }
        for i in pts.indices { for j in pts.indices where j > i && (pts[i] - pts[j]).length < minGap - 1e-9 { return "pts.gap" } }
        return nil
    }

    static func build(_ p: MGParams) -> MGTemplateBuild {
        let theta = p["angle"], pivot = MGPoint(p["px"], p["py"])
        let original = points(p)
        let turned = original.map { rotate($0, degrees: theta, pivot: pivot) }
        func world(_ m: MGPoint) -> MGPoint { origin + m }
        var values: [String: MGValue] = ["theta": .init(value: theta, unit: "°"),
                                         "px": .init(value: pivot.x, unit: ""), "py": .init(value: pivot.y, unit: "")]
        var items: [MGItem] = [
            MGMake.line("xaxis", MGPoint(0.4, origin.y), MGPoint(width - 0.4, origin.y)),
            MGMake.line("yaxis", MGPoint(origin.x, 0.4), MGPoint(origin.x, height - 0.4)),
        ]
        if p["ghost"] == 1 {
            var ghost = MGMake.kind("ghost", .path, (original + [original[0]]).map(world), color: .muted); ghost.flags.insert("dashed")
            items.append(ghost)
        }
        items.append(MGMake.kind("shape", .path, (turned + [turned[0]]).map(world), color: .accent))
        let centroid = turned.reduce(MGPoint.zero, +) * (1 / Double(turned.count))
        var placed: [Box] = [labelBox(text: "θ = " + MGPhysics.format(theta, unit: "°"), center: thetaAt, callout: true)]
        let dots = (turned + [pivot]).map { Box(center: world($0), halfWidth: 0.24, halfHeight: 0.24) }
        for (k, v) in turned.enumerated() {
            let letter = letters[k], lower = letter.lowercased()
            values[lower + "x"] = .init(value: v.x, unit: ""); values[lower + "y"] = .init(value: v.y, unit: "")
            values[lower + "x0"] = .init(value: original[k].x, unit: ""); values[lower + "y0"] = .init(value: original[k].y, unit: "")
            values["r" + lower] = .init(value: (original[k] - pivot).length, unit: "")
            items.append(MGMake.body("v" + letter, world(v), size: 0.32, ball: true, color: colors[k]))
            let shown = "\(letter) (\(MGPhysics.format(v.x, unit: "")), \(MGPhysics.format(v.y, unit: "")))"
            let box = placeLabel(shown, at: world(v), outward: v - centroid, avoiding: dots + placed)
            placed.append(box)
            items.append(MGMake.text("l" + letter, box.center, "\(letter) ({\(lower)x}, {\(lower)y})", color: colors[k]))
        }
        items.append(MGMake.body("pivot", world(pivot), size: 0.22, ball: true, label: "O", color: .white))
        let start = atan2(original[0].y - pivot.y, original[0].x - pivot.x) * 180 / .pi
        let count = min(25, max(2, Int((abs(theta) / 15).rounded(.up)) + 1))
        let arc = (0..<count).map { k in world(pivot + MGPoint.polar(start + theta * Double(k) / Double(count - 1), arcRadius)) }
        items.append(MGMake.kind("arc", .path, arc, color: .yellow))
        items.append(MGMake.text("ltheta", thetaAt, "θ = {theta}", style: "callout", color: .yellow))
        return MGTemplateBuild(title: "Rotation about a point", width: width, height: height, items: items, values: values)
    }
}
