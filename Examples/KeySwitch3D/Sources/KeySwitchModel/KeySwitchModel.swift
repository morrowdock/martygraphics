// SPDX-License-Identifier: Apache-2.0
import Foundation
import MartyGraphics

// HOST EXAMPLE LOGIC, not engine capability.
// An original, schematic key-switch assembly for inspection: keycap, stem with actuator leg, two housings, spring and a
// normally open contact pair. Units are arbitrary world units. This is a SCHEMATIC TEACHING MODEL, not physically
// validated mechanics: positions follow the parameters (kinematics only); no force, spring rate, deflection, timing,
// debounce, wear or electrical behaviour is modelled, and the proportions are not taken from any real product. The only
// geometric promise is drawing-level: the drawn parts that touch (leg/tab, leaf/leaf) meet without passing through each
// other at every parameter value, measured on their drawn tube radius.

/// The three things a learner can change. Values outside the template's ranges are refused by the engine, never clamped.
public struct KeySwitchParams: Equatable, Sendable {
    /// Fraction of full stem travel, 0–1.
    public var press: Double
    /// Exploded-view fraction, 0 (assembled) – 1 (fully apart).
    public var explode: Double
    /// Fraction of travel at which the contacts close, 0.3–0.8.
    public var actuate: Double
    public init(press: Double = 0, explode: Double = 0, actuate: Double = 0.5) {
        self.press = press; self.explode = explode; self.actuate = actuate
    }
    public static let rest = KeySwitchParams()
    public static let ranges: [String: ClosedRange<Double>] = ["press": 0...1, "explode": 0...1, "actuate": 0.3...0.8]
}

/// Derived, deterministic state for narration, panels and tests.
public struct KeySwitchState: Equatable, Sendable {
    /// press × (1 − explode): lifting the stack apart releases the key.
    public var effectivePress: Double
    /// How far the stem is below its rest position (negative while it is lifted for the exploded view).
    public var stemDrop: Double
    /// Stem drop at which the contacts close.
    public var actuationDepth: Double
    public var contactClosed: Bool
    /// Horizontal gap between the drawn surfaces of the contact leaves' tips (0 when closed, where the drawn leaves touch).
    public var contactGap: Double
    public var springLength: Double
}

public struct KeySwitchComponent: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    /// Scene item ids drawn for this component. The engine has no groups; the host maps items to components.
    public let items: [String]
    public let note: String
    /// Reference geometry rather than a physical part.
    public let reference: Bool
}

public enum KeySwitchModel {
    // MARK: geometry constants (world units, schematic)

    public static let travel = 1.2
    static let cx = 6.0
    static let floorY = 3.05, stemRestBottom = 4.7, stemHeight = 2.2, stemHalf = 0.35
    static let tipY = 4.1, fixedLeafX = 6.75, movingOpenX = 7.25, pinBottom = 2.2, kneeY = 3.5
    /// Drawn radius of every `path` segment on a 3D board (MG3DBuilder); two drawn parts touch at twice this distance.
    static let tube = 0.04
    static let touch = 2 * tube
    /// Closed: the drawn moving tip rests against the drawn fixed leaf (touching, not overlapping).
    static let movingClosedX = fixedLeafX + touch
    /// The actuator leg runs in this plane, in front of the contact leaves (z = 0). It meets the moving leaf only at
    /// a short side tab, so it can pass the leaf's body after closing without cutting through it.
    static let legZ = 0.25
    /// The leg's holding flat: it keeps the tab (and so the tip) against the fixed leaf after the contacts close.
    static let flatX = movingClosedX + touch
    /// The actuator foot is a slant this tall below the flat: it pushes the tab from open to closed over its height.
    static let engage = 0.3
    static let rampBottomX = movingOpenX + touch
    /// The leg's arm leaves the stem this far above the stem bottom, so it stays above the contacts at full travel.
    static let armRise = 0.9
    static let springRadius = 0.45, springCoils = 5.0, springSegments = 40
    /// Exploded-view lifts per component (world units at explode = 1). The bottom housing and contacts stay put.
    static let lift: [String: Double] = ["keycap": 2.8, "stem": 2.0, "housing_top": 1.2, "spring": 0.6]

    public static let components: [KeySwitchComponent] = [
        .init(id: "keycap", name: "Keycap", items: ["keycap"],
              note: "The surface the finger presses. It sits on the stem, so it moves exactly as far as the stem does.", reference: false),
        .init(id: "stem", name: "Stem", items: ["stem", "stem_leg"],
              note: "The guided slider under the keycap. Its side leg runs just in front of the contacts: a slanted foot pushes the moving contact's tab closed, then a straight flat holds it there.", reference: false),
        .init(id: "housing_top", name: "Top housing", items: ["housing_top"],
              note: "Upper guide that keeps the stem moving straight. It does not move while the switch is assembled.", reference: false),
        .init(id: "spring", name: "Spring", items: ["spring"],
              note: "Pushes the stem back up. Here its drawn length only follows the stem; spring force is not modelled.", reference: false),
        .init(id: "contact_fixed", name: "Fixed contact", items: ["contact_fixed"],
              note: "A stationary contact leaf whose lower end is a terminal pin. Both leaves turn from grey to green while they touch.", reference: false),
        .init(id: "contact_moving", name: "Moving contact", items: ["contact_moving"],
              note: "A leaf that is normally open. A small side tab meets the stem's leg, which presses the leaf against the fixed leaf at the actuation point. How it bends is drawn, not simulated.", reference: false),
        .init(id: "housing_base", name: "Bottom housing", items: ["housing_base"],
              note: "Holds the spring seat and both contacts. The exploded view keeps it in place as the reference frame.", reference: false),
        .init(id: "actuation_mark", name: "Actuation level", items: ["actuation_mark"],
              note: "Not a part: the height the stem's bottom must reach before the contacts close. Move it with the Actuation slider.", reference: true)
    ]

    public static func component(id: String) -> KeySwitchComponent? { components.first { $0.id == id } }
    public static func component(containing item: String) -> KeySwitchComponent? { components.first { $0.items.contains(item) } }
    /// Every selectable item mapped to its component's list number (1-based), for `MartyGraphicsView.markers`.
    public static var markers: [String: Int] {
        var out: [String: Int] = [:]
        for (n, c) in components.enumerated() { for item in c.items { out[item] = n + 1 } }
        return out
    }

    // MARK: kinematics

    public static func state(_ p: KeySwitchParams) -> KeySwitchState {
        let effective = p.press * (1 - p.explode)
        let drop = effective * travel - (lift["stem"] ?? 0) * p.explode
        let actuation = p.actuate * travel
        let tip = tabX(leg: leg(drop: drop, actuation: actuation))
        let closed = drop >= actuation - 1e-9
        return KeySwitchState(effectivePress: effective, stemDrop: drop, actuationDepth: actuation, contactClosed: closed,
                              contactGap: closed ? 0 : round4(tip - movingClosedX), springLength: round4(stemRestBottom - effective * travel - floorY))
    }

    /// The actuator leg in its own plane (x, y): arm, holding flat, then the slanted foot. The flat's lower end
    /// reaches the tab height exactly when the stem has dropped by the actuation depth.
    static func leg(drop: Double, actuation: Double) -> [(x: Double, y: Double)] {
        let stemBottom = stemRestBottom - drop, armY = stemBottom + armRise
        let junction = tipY + actuation - drop
        return [(cx + stemHalf, armY), (flatX, armY), (flatX, junction), (rampBottomX, junction - engage)]
    }

    /// Where the moving tip (and its tab) sits: the leaf springs open (`movingOpenX`) unless the leg's drawn surface
    /// is in the way, in which case the tab rests exactly against it; the fixed leaf stops it at `movingClosedX`.
    /// So the tab touches the leg while pushed and is never inside it.
    static func tabX(leg: [(x: Double, y: Double)]) -> Double {
        min(movingOpenX, max(movingClosedX, leftmostX(within: touch, of: leg, atY: tipY)))
    }

    /// Leftmost x on the horizontal line `y` that lies within `r` of the polyline (infinity when none does): the
    /// smallest x over each segment's end discs and the two offset lines of its side band.
    static func leftmostX(within r: Double, of pts: [(x: Double, y: Double)], atY y: Double) -> Double {
        var best = Double.infinity
        for (a, b) in zip(pts, pts.dropFirst()) {
            for p in [a, b] where abs(y - p.y) <= r { best = min(best, p.x - (r * r - (y - p.y) * (y - p.y)).squareRoot()) }
            let dx = b.x - a.x, dy = b.y - a.y, length = (dx * dx + dy * dy).squareRoot()
            guard length > 1e-12, abs(dy) > 1e-12 else { continue }
            let nx = -dy / length, ny = dx / length
            for side in [1.0, -1.0] {
                let t = (y - a.y - side * r * ny) / dy
                if t >= -1e-12, t <= 1 + 1e-12 { best = min(best, a.x + t * dx + side * r * nx) }
            }
        }
        return best
    }

    static func round4(_ x: Double) -> Double { (x * 10_000).rounded() / 10_000 }
    static func pt(_ x: Double, _ y: Double, _ z: Double = 0) -> MGPoint { MGPoint(round4(x), round4(y), round4(z)) }

    /// A wireframe box (or frustum) as one 16-point polyline: bottom loop, then each vertical edge and the top loop.
    static func frame(y0: Double, y1: Double, bottom: Double, top: Double, x: Double = cx) -> [MGPoint] {
        func ring(_ y: Double, _ h: Double) -> [MGPoint] { [pt(x - h, y, -h), pt(x + h, y, -h), pt(x + h, y, h), pt(x - h, y, h)] }
        let b = ring(y0, bottom), t = ring(y1, top)
        return [b[0], b[1], b[2], b[3], b[0], t[0], t[1], b[1], t[1], t[2], b[2], t[2], t[3], b[3], t[3], t[0]]
    }

    static func path(_ id: String, _ pts: [MGPoint], _ color: MGColorRole) -> MGItem { MGMake.kind(id, .path, pts, color: color) }

    /// All scene items for one parameter set. Pure and deterministic.
    public static func items(_ p: KeySwitchParams) -> [MGItem] {
        let st = state(p), e = p.explode
        let effectiveDrop = st.effectivePress * travel
        let stemBottom = stemRestBottom - st.stemDrop
        let keycapBottom = stemBottom + stemHeight + ((lift["keycap"] ?? 0) - (lift["stem"] ?? 0)) * e
        let springBottom = floorY + (lift["spring"] ?? 0) * e
        let springTop = springBottom + (stemRestBottom - effectiveDrop - floorY)
        // Open contacts are drawn muted and closed ones green; the panel text and narration carry the same state.
        let contact: MGColorRole = st.contactClosed ? .good : .muted

        let actuator = leg(drop: st.stemDrop, actuation: st.actuationDepth)
        let tipX = tabX(leg: actuator)

        var helix: [MGPoint] = []
        for i in 0...springSegments {
            let f = Double(i) / Double(springSegments), a = 2 * Double.pi * springCoils * f
            helix.append(pt(cx + springRadius * cos(a), springBottom + (springTop - springBottom) * f, springRadius * sin(a)))
        }
        let markY = stemRestBottom - st.actuationDepth
        return [
            path("housing_base", frame(y0: 3.0, y1: 4.4, bottom: 1.7, top: 1.7), .purple),
            path("housing_top", frame(y0: 4.4 + (lift["housing_top"] ?? 0) * e, y1: 5.4 + (lift["housing_top"] ?? 0) * e, bottom: 1.5, top: 1.5), .teal),
            path("spring", helix, .green),
            path("stem", frame(y0: stemBottom, y1: stemBottom + stemHeight, bottom: stemHalf, top: stemHalf), .orange),
            path("stem_leg", actuator.map { pt($0.x, $0.y, legZ) }, .orange),
            path("keycap", frame(y0: keycapBottom, y1: keycapBottom + 0.9, bottom: 1.6, top: 1.3), .blue),
            path("contact_fixed", [pt(fixedLeafX, pinBottom), pt(fixedLeafX, tipY)], contact),
            path("contact_moving", [pt(movingOpenX, pinBottom), pt(movingOpenX, kneeY), pt(tipX, tipY), pt(tipX, tipY, legZ)], contact),
            path("actuation_mark", [pt(cx - 1.7, markY, 1.7), pt(cx + 1.7, markY, 1.7)], .red)
        ]
    }

    static func percent(_ x: Double) -> String { "\(Int((x * 100).rounded()))%" }
    static func units(_ x: Double) -> String { String(format: "%.2f", x) }

    /// One-sentence narration (engine caption and default VoiceOver value). In the exploded view it is worded from the
    /// same state as the panel (stem drop and contact state), never assumed: a small explode can leave the stem pressed
    /// past the actuation depth with the contacts still closed.
    public static func narration(_ p: KeySwitchParams) -> String {
        let st = state(p)
        let contacts = st.contactClosed ? "contacts closed" : "contacts open"
        if p.explode > 0 {
            let view = "Exploded view \(percent(p.explode)): parts lifted apart"
            if st.contactClosed {
                return "\(view), but the stem is still down \(units(st.stemDrop)) of \(units(travel)) units, past the \(units(st.actuationDepth)) actuation depth, so the contacts stay closed."
            }
            if st.stemDrop > 0 {
                return "\(view); the stem is down \(units(st.stemDrop)) of \(units(travel)) units, short of the \(units(st.actuationDepth)) actuation depth, so the contacts are open."
            }
            return "\(view) and the stem lifted clear of the contacts, so the key is released and the contacts are open."
        }
        return "Stem down \(units(max(0, st.stemDrop))) of \(units(travel)) units, \(contacts). They close at \(units(st.actuationDepth)) units (actuation \(percent(p.actuate)))."
    }

    // MARK: engine integration through the public API

    public static let template = MGTemplate(
        name: "key_switch",
        summary: "schematic key switch (3D only): press and explode are 0–1, contacts close at actuate (fraction of travel)",
        params: [.init(name: "press", unit: "", range: 0...1, defaultValue: 0),
                 .init(name: "explode", unit: "", range: 0...1, defaultValue: 0),
                 .init(name: "actuate", unit: "", range: 0.3...0.8, defaultValue: 0.5)],
        make: { p, is3D in
            guard is3D else { return nil }
            let params = KeySwitchParams(press: p["press"], explode: p["explode"], actuate: p["actuate"])
            return MGTemplateBuild(title: "Schematic key switch", width: 12, height: 12, items: items(params),
                                   steps: [MGStep(say: narration(params))], camera: MGCamera(zoom: 1.1, yaw: 35, pitch: 18))
        })

    public static let restFixture = #"{"v":1,"template":"key_switch","dim":"3d","params":{"press":0,"explode":0,"actuate":0.5}}"#

    /// Opt-in example pack. It is not built into the engine and is registered only by this example.
    public static let pack = MGPack(id: "key_switch_example", title: "Example: schematic key switch",
                                    summary: "host example of an inspectable 3D assembly", templates: [template],
                                    fixtures: [.init(id: "key_switch_rest", title: "Schematic key switch", json: restFixture)])

    /// Idempotent: registering twice (tests, repeated launches in one process) is not an error.
    public static func registerPack() throws {
        if MGPacks.all.contains(where: { $0.id == pack.id }) { return }
        do { try MGPacks.register(pack) } catch MGPackError.duplicatePack(_) { }
    }

    public static func sceneObject(_ p: KeySwitchParams) -> [String: Any] {
        ["v": 1, "template": "key_switch", "dim": "3d", "params": ["press": p.press, "explode": p.explode, "actuate": p.actuate]]
    }

    public static func scene(_ p: KeySwitchParams) -> Result<MGScene, MGError> { MGParser.scene(object: sceneObject(p)) }

    /// A params patch against `revision`. Non-finite numbers cannot be encoded and fail here, before the engine.
    public static func patch(_ p: KeySwitchParams, revision: Int?) -> Result<MGPatch, MGError> {
        var root: [String: Any] = ["v": 1, "ops": [["op": "params", "params": ["press": p.press, "explode": p.explode, "actuate": p.actuate]]]]
        if let revision { root["rev"] = revision }
        return MGPatch.parse(object: root)
    }
}
