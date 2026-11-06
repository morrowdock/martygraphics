// SPDX-License-Identifier: Apache-2.0
import XCTest
import MartyGraphics
@testable import KeySwitchModel

/// Deterministic checks of the example's geometry, state, selection, reset and refused updates through the public
/// engine API. They do not show that the board looks right or that any gesture works on screen, and the geometry checks
/// are drawing-level (tube clearance), not a validation of real switch mechanics.
final class KeySwitchModelTests: XCTestCase {
    override func setUpWithError() throws { try KeySwitchModel.registerPack() }

    private func scene(_ p: KeySwitchParams) throws -> MGScene { try KeySwitchModel.scene(p).get() }
    private func item(_ s: MGScene, _ id: String) throws -> MGItem { try XCTUnwrap(s.item(id), id) }

    // MARK: pack and scene

    func testPackIsValidOptInAndIdempotent() throws {
        XCTAssertTrue(MGPacks.validate(KeySwitchModel.pack).isEmpty)
        XCTAssertEqual(MGTemplates.all.map(\.name), ["bst", "two_pointers"], "core templates unchanged")
        try KeySwitchModel.registerPack()
        XCTAssertEqual(MGPacks.all.filter { $0.id == KeySwitchModel.pack.id }.count, 1)
    }

    func testRestSceneIsThreeDimensionalAndEveryComponentIsDrawn() throws {
        let s = try scene(.rest)
        XCTAssertTrue(s.is3D)
        XCTAssertEqual(s.title, "Schematic key switch")
        XCTAssertEqual(s.items.count, 9)
        XCTAssertTrue(s.items.allSatisfy { MGKind.in3D.contains($0.kind) })
        XCTAssertEqual(s.steps.count, 1)
        XCTAssertEqual(s.camera, MGCamera(zoom: 1.1, yaw: 35, pitch: 18))
        let ids = Set(s.items.map(\.id))
        let componentItems = KeySwitchModel.components.flatMap(\.items)
        XCTAssertEqual(Set(componentItems), ids, "every drawn item belongs to exactly one listed component")
        XCTAssertEqual(componentItems.count, ids.count)
        XCTAssertEqual(Set(KeySwitchModel.markers.keys), ids)
        XCTAssertEqual(Set(KeySwitchModel.components.map(\.id)).count, KeySwitchModel.components.count)
        XCTAssertLessThanOrEqual(try item(s, "spring").pts.count, MGLimits.points)
        XCTAssertEqual(try scene(.rest).items, s.items, "deterministic")
        XCTAssertEqual(KeySwitchModel.items(.rest), KeySwitchModel.items(.rest))
    }

    func testTwoDimensionalAndOutOfRangeScenesAreRefused() {
        func reason(_ json: String) -> String? {
            if case .failure(let e) = MGParser.scene(data: Data(json.utf8)) { return e.reason }; return nil
        }
        XCTAssertEqual(reason(#"{"v":1,"template":"key_switch","params":{}}"#), "template.build")
        XCTAssertEqual(reason(#"{"v":1,"template":"key_switch","dim":"3d","params":{"press":1.01}}"#), "template.press")
        XCTAssertEqual(reason(#"{"v":1,"template":"key_switch","dim":"3d","params":{"actuate":0.2}}"#), "template.actuate")
        XCTAssertEqual(reason(#"{"v":1,"template":"key_switch","dim":"3d","params":{"spring":2}}"#), "template.params.unknown")
        XCTAssertNil(reason(#"{"v":1,"template":"key_switch","dim":"3d","params":{}}"#), "all params default")
    }

    func testEveryParameterCombinationOnAGridParsesWithinEngineBounds() throws {
        let grid = stride(from: 0.0, through: 1.0, by: 0.2).map { $0 }
        for press in grid { for explode in grid { for actuate in [0.3, 0.4, 0.5, 0.6, 0.7, 0.8] {
            let p = KeySwitchParams(press: press, explode: explode, actuate: actuate)
            XCTAssertNoThrow(try scene(p), "\(p)")
        } } }
    }

    // MARK: kinematics

    func testContactsCloseExactlyAtTheActuationPoint() {
        for actuate in [0.3, 0.5, 0.8] {
            XCTAssertTrue(KeySwitchModel.state(.init(press: actuate, actuate: actuate)).contactClosed)
            XCTAssertFalse(KeySwitchModel.state(.init(press: actuate - 0.01, actuate: actuate)).contactClosed)
            XCTAssertTrue(KeySwitchModel.state(.init(press: 1, actuate: actuate)).contactClosed)
            XCTAssertFalse(KeySwitchModel.state(.init(press: 0, actuate: actuate)).contactClosed)
        }
        XCTAssertEqual(KeySwitchModel.state(.init(press: 0.5, actuate: 0.5)).contactGap, 0)
    }

    func testGapAndSpringShrinkMonotonicallyAndKeycapRidesOnTheStem() throws {
        var lastGap = Double.infinity, lastSpring = Double.infinity
        for k in 0...20 {
            let p = KeySwitchParams(press: Double(k) / 20)
            let st = KeySwitchModel.state(p)
            XCTAssertLessThanOrEqual(st.contactGap, lastGap + 1e-12); lastGap = st.contactGap
            XCTAssertLessThan(st.springLength, lastSpring); lastSpring = st.springLength
            XCTAssertGreaterThan(st.springLength, 0.3, "the drawn spring never collapses")
            let s = try scene(p)
            let capBottom = try item(s, "keycap").pts[0].y, stemBottom = try item(s, "stem").pts[0].y
            XCTAssertEqual(capBottom - stemBottom, KeySwitchModel.stemHeight, accuracy: 1e-3)
            XCTAssertGreaterThan(capBottom, 5.4, "keycap never enters the top housing (top at 5.4)")
        }
    }

    // MARK: drawing-level clearance (drawn tube radius 0.04 per path segment)

    /// Every slider position the example offers: press and explode on the 0.05 grid, actuate 0.30–0.80 by 0.05.
    private var fullGrid: [KeySwitchParams] {
        var out: [KeySwitchParams] = []
        for a in 0...10 { for e in 0...20 { for p in 0...20 {
            out.append(KeySwitchParams(press: Double(p) / 20, explode: Double(e) / 20, actuate: Double(6 + a) / 20))
        } } }
        return out
    }
    /// Coordinates are rounded to 4 decimals before drawing, so "touching" is checked to within this tolerance.
    private let rounding = 2e-4

    func testDrawnMechanicalPartsNeverPassThroughEachOtherOnTheFullParameterGrid() {
        let grid = fullGrid
        XCTAssertEqual(grid.count, 4_851)
        var closest = [String: Double]()
        for p in grid {
            let byID = Dictionary(KeySwitchModel.items(p).map { ($0.id, $0.pts) }, uniquingKeysWith: { a, _ in a })
            let leg = byID["stem_leg"] ?? [], moving = byID["contact_moving"] ?? [], fixed = byID["contact_fixed"] ?? []
            for (name, d) in [("leg/moving", Self.distance(leg, moving)), ("leg/fixed", Self.distance(leg, fixed)),
                              ("moving/fixed", Self.distance(moving, fixed)),
                              ("leg/moving body", Self.distance(leg, Array(moving.prefix(3))))] {
                closest[name] = min(closest[name] ?? .infinity, d)
                XCTAssertGreaterThanOrEqual(d, KeySwitchModel.touch - rounding, "\(name) at \(p)")
            }
        }
        // The leg is a plane in front of the leaf bodies; only the tab and the closed tips ever come into contact.
        XCTAssertGreaterThanOrEqual(closest["leg/moving body"] ?? 0, KeySwitchModel.legZ - 1e-9)
        XCTAssertEqual(closest["moving/fixed"] ?? 0, KeySwitchModel.touch, accuracy: rounding, "closed tips touch")
        XCTAssertEqual(closest["leg/moving"] ?? 0, KeySwitchModel.touch, accuracy: rounding, "the leg reaches the tab")
    }

    func testTheLegPushesTheTabWhileEngagedAndTheGeometryAgreesWithTheContactState() {
        var pushed = 0
        for p in fullGrid {
            let st = KeySwitchModel.state(p)
            let leg = KeySwitchModel.leg(drop: st.stemDrop, actuation: st.actuationDepth)
            let tab = KeySwitchModel.tabX(leg: leg)
            // Closed exactly when the stem has reached the actuation depth, and then the tips touch.
            XCTAssertEqual(abs(tab - KeySwitchModel.movingClosedX) < 1e-9, st.contactClosed, "\(p)")
            // Away from its open rest, the tab is held by the leg: touching it, never apart from it or inside it.
            guard tab < KeySwitchModel.movingOpenX - 1e-9 else { continue }
            pushed += 1
            let tabEnd = MGPoint(tab, KeySwitchModel.tipY, KeySwitchModel.legZ)
            let d = Self.distance(leg.map { MGPoint($0.x, $0.y, KeySwitchModel.legZ) }, [tabEnd, tabEnd])
            XCTAssertEqual(d, KeySwitchModel.touch, accuracy: 1e-9, "\(p)")
        }
        XCTAssertGreaterThan(pushed, 0)
    }

    /// Smallest distance between two 3D polylines (segment pairs, clamped closest points).
    static func distance(_ a: [MGPoint], _ b: [MGPoint]) -> Double {
        var best = Double.infinity
        for (p1, q1) in zip(a, a.dropFirst()) { for (p2, q2) in zip(b, b.dropFirst()) { best = min(best, segment(p1, q1, p2, q2)) } }
        return best
    }
    static func segment(_ p1: MGPoint, _ q1: MGPoint, _ p2: MGPoint, _ q2: MGPoint) -> Double {
        func dot(_ u: MGPoint, _ v: MGPoint) -> Double { u.x * v.x + u.y * v.y + u.z * v.z }
        let d1 = q1 - p1, d2 = q2 - p2, r = p1 - p2
        let a = dot(d1, d1), e = dot(d2, d2), f = dot(d2, r)
        var s = 0.0, t = 0.0
        if a < 1e-15 && e < 1e-15 { return dot(r, r).squareRoot() }
        if a < 1e-15 { t = min(1, max(0, f / e)) } else {
            let c = dot(d1, r)
            if e < 1e-15 { s = min(1, max(0, -c / a)) } else {
                let b = dot(d1, d2), den = a * e - b * b
                s = den > 1e-15 ? min(1, max(0, (b * f - c * e) / den)) : 0
                t = (b * s + f) / e
                if t < 0 { t = 0; s = min(1, max(0, -c / a)) } else if t > 1 { t = 1; s = min(1, max(0, (b - c) / a)) }
            }
        }
        let gap = (p1 + d1 * s) - (p2 + d2 * t)
        return dot(gap, gap).squareRoot()
    }

    func testExplodedViewSeparatesTheStackAndReleasesTheKey() throws {
        let p = KeySwitchParams(press: 1, explode: 1)
        let st = KeySwitchModel.state(p)
        XCTAssertEqual(st.effectivePress, 0)
        XCTAssertFalse(st.contactClosed)
        let s = try scene(p)
        func ys(_ id: String) throws -> [Double] { try item(s, id).pts.map(\.y) }
        XCTAssertGreaterThan(try ys("keycap").min()!, try ys("stem").max()!)
        XCTAssertGreaterThan(try ys("stem").min()!, try ys("housing_top").max()!)
        XCTAssertGreaterThan(try ys("stem").min()!, try ys("spring").max()!)
        XCTAssertEqual(try ys("housing_base"), try item(try scene(.rest), "housing_base").pts.map(\.y), "base is the fixed reference")
    }

    // MARK: session: selection, refused updates, reset

    @MainActor func testSelectionMapsItemsToComponentsAndIgnoresUnknownIds() throws {
        let s = try KeySwitchSession()
        for c in KeySwitchModel.components {
            for i in c.items { s.select(item: i); XCTAssertEqual(s.selected, c.id); XCTAssertEqual(s.emphasis, Set(c.items)) }
        }
        s.select(item: "stem_leg")
        XCTAssertEqual(s.selectionItem, "stem")
        XCTAssertTrue(s.summary.hasSuffix("Selected: Stem."))
        s.select(component: "bogus")
        XCTAssertEqual(s.selected, "stem", "unknown list ids are ignored")
        s.select(item: "bogus")
        XCTAssertNil(s.selected, "an unknown board item clears, like tapping empty space")
        s.select(component: "spring"); s.select(component: nil)
        XCTAssertNil(s.selected)
        XCTAssertTrue(s.emphasis.isEmpty)
    }

    @MainActor func testRefusedUpdatesKeepTheSceneAndParameters() throws {
        let s = try KeySwitchSession()
        XCTAssertTrue(s.set(press: 0.6))
        let shown = try XCTUnwrap(s.controller.scene)
        for bad in [KeySwitchParams(press: 1.5), KeySwitchParams(press: -0.1), KeySwitchParams(press: .nan),
                    KeySwitchParams(explode: .infinity), KeySwitchParams(actuate: 0.2), KeySwitchParams(actuate: 0.81)] {
            XCTAssertFalse(s.update(bad), "\(bad)")
            XCTAssertTrue(s.lastUpdateRefused)
            XCTAssertEqual(s.params.press, 0.6)
            XCTAssertEqual(s.controller.scene, shown, "scene untouched, revision unchanged")
        }
        XCTAssertTrue(s.set(explode: 0.5))
        XCTAssertFalse(s.lastUpdateRefused)
        // A stale revision is refused too (the session always names the current one).
        let stale = try KeySwitchModel.patch(.rest, revision: shown.revision).get()
        XCTAssertFalse(s.controller.apply(patch: stale, requireRevision: true))
        XCTAssertEqual(s.params.explode, 0.5)
        let unnamed = try KeySwitchModel.patch(.rest, revision: nil).get()
        XCTAssertFalse(s.controller.apply(patch: unnamed, requireRevision: true), "untrusted path must name a revision")
    }

    @MainActor func testResetRestoresRestClearsSelectionAndRequestsTheSceneCamera() throws {
        let s = try KeySwitchSession()
        let fresh = try scene(.rest).items
        XCTAssertTrue(s.reset())
        XCTAssertEqual(s.cameraReset, 1, "reset from rest still returns the camera")
        XCTAssertTrue(s.set(press: 0.9)); XCTAssertTrue(s.set(explode: 0.4)); XCTAssertTrue(s.set(actuate: 0.7))
        s.select(component: "spring")
        XCTAssertFalse(s.update(.init(press: 2)))
        XCTAssertTrue(s.reset())
        XCTAssertEqual(s.params, .rest)
        XCTAssertNil(s.selected)
        XCTAssertEqual(s.cameraReset, 2)
        XCTAssertFalse(s.lastUpdateRefused)
        XCTAssertEqual(s.controller.scene?.items, fresh)
        XCTAssertEqual(s.controller.scene?.steps.first?.say, KeySwitchModel.narration(.rest))
    }

    func testNarrationIsPlainWithinTheSayLimitAndMatchesTheContactState() {
        for p in fullGrid {
            let text = KeySwitchModel.narration(p), closed = KeySwitchModel.state(p).contactClosed
            XCTAssertLessThanOrEqual(text.unicodeScalars.count, MGLimits.say)
            XCTAssertFalse(text.contains("{") || text.contains("<"))
            XCTAssertEqual(text.contains("contacts closed") || text.contains("contacts stay closed"), closed, "\(p)")
            XCTAssertFalse(closed && text.contains("released"), "never 'released' while the contacts are closed: \(p)")
        }
        XCTAssertEqual(KeySwitchModel.narration(.rest),
                       "Stem down 0.00 of 1.20 units, contacts open. They close at 0.60 units (actuation 50%).")
        XCTAssertEqual(KeySwitchModel.narration(.init(press: 0.45, explode: 0.05, actuate: 0.3)),
                       "Exploded view 5%: parts lifted apart, but the stem is still down 0.41 of 1.20 units, past the 0.36 actuation depth, so the contacts stay closed.")
        XCTAssertEqual(KeySwitchModel.narration(.init(press: 0.5, explode: 0.5)),
                       "Exploded view 50%: parts lifted apart and the stem lifted clear of the contacts, so the key is released and the contacts are open.")
        XCTAssertEqual(KeySwitchModel.narration(.init(press: 1, explode: 0.1, actuate: 0.8)),
                       "Exploded view 10%: parts lifted apart; the stem is down 0.88 of 1.20 units, short of the 0.96 actuation depth, so the contacts are open.")
    }
}
