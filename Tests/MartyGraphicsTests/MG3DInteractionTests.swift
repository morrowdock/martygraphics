// SPDX-License-Identifier: Apache-2.0
import XCTest
import SwiftUI
import SceneKit
@testable import MartyGraphics

/// Opt-in 3D inspection hooks: pure selection/emphasis/camera/wiring rules, plus their wiring into a real (windowless)
/// SCNView. These tests call the coordinator directly. They are not evidence that a click/tap/drag gesture works on screen.
final class MG3DInteractionTests: XCTestCase {
    // MARK: pure rules

    func testTapSamplesProbeCentreFirstWithinTheTwoDSlop() {
        let samples = MG3DInteraction.tapSamples()
        XCTAssertEqual(samples.count, 17)
        XCTAssertEqual(samples.first, .zero)
        for p in samples { XCTAssertLessThanOrEqual((p.x * p.x + p.y * p.y).squareRoot(), MG3DInteraction.slop + 1e-6) }
        XCTAssertEqual(samples, MG3DInteraction.tapSamples(), "deterministic")
        XCTAssertEqual(samples[1], CGPoint(x: 6, y: 0))
        XCTAssertEqual(samples[9], CGPoint(x: 12, y: 0))
    }

    func testPickWalksAncestorsByIdentityAndPrefersEarlierProbesAndNearerHits() {
        // Keys stand in for node identities. 1/2/3 are item roots; 10 is a child segment of 1; 99 is an unregistered
        // node (axes, camera, or a highlight/ground line, which are never registered) and 0 is the scene root.
        let roots = [1: "spring", 2: "stem", 3: "head"]
        let seg = [10, 1, 0], stem = [2, 0], axes = [99, 0]
        // A probe whose hits are all unregistered is skipped; the next probe's nearest registered hit wins.
        XCTAssertEqual(MG3DInteraction.pick([[axes], [seg, stem]], roots: roots, selectable: nil), "spring")
        // An unregistered hit in front of a registered one falls through to it (a halo in front of its body).
        XCTAssertEqual(MG3DInteraction.pick([[axes, stem]], roots: roots, selectable: nil), "stem")
        // Within one probe, the nearer (earlier) hit wins.
        XCTAssertEqual(MG3DInteraction.pick([[stem, seg]], roots: roots, selectable: nil), "stem")
        // Earlier probes beat later ones even when the later probe hit something nearer.
        XCTAssertEqual(MG3DInteraction.pick([[stem], [seg]], roots: roots, selectable: nil), "stem")
        // Non-selectable hits fall through to the next hit, then the next probe.
        XCTAssertEqual(MG3DInteraction.pick([[stem, seg]], roots: roots, selectable: ["spring"]), "spring")
        XCTAssertEqual(MG3DInteraction.pick([[stem], [seg]], roots: roots, selectable: ["spring"]), "spring")
        XCTAssertNil(MG3DInteraction.pick([[stem]], roots: roots, selectable: ["spring"]))
        // Empty space clears; an item literally named "head" is matched by identity, not by a node name.
        XCTAssertNil(MG3DInteraction.pick([[], []], roots: roots, selectable: nil))
        XCTAssertEqual(MG3DInteraction.pick([[[3, 0]]], roots: roots, selectable: nil), "head")
    }

    func testTargetsExcludeHighlightsAxesAndGroundLinesLikeTheTwoDHitTest() throws {
        let s = try scene(inspected)
        var items = s.items
        items.append(MGMake.kind("ax", .axes, [MGPoint(1, 1)], ["w": 4, "h": 4], color: .muted))
        XCTAssertEqual(MG3DInteraction.targets(items), ["block", "rail"])
        // Same eligibility as the 2D rule in MGLayout.hit: a highlight, axes or ground item is never a 2D target either.
        for item in items where !MG3DInteraction.targets(items).contains(item.id) {
            XCTAssertTrue([.highlight, .axes].contains(item.kind) || item.has("ground"), item.id)
        }
    }

    func testStylesAreOptInGlowDoesNotDimAndHighlightsFollowTheirTarget() throws {
        let items = try scene(inspected).items
        let drawn = Set(items.map(\.id))
        let glowing = MG3DInteraction.Style(opacity: 1, highlighted: true)
        let dimmed = MG3DInteraction.Style(opacity: MG3DInteraction.dimmedOpacity, highlighted: false)
        func styles(_ e: Set<String>, glow: Bool, dim: Bool) -> [String: MG3DInteraction.Style] {
            MG3DInteraction.styles(items: items, drawn: drawn, emphasis: e, glow: glow, dim: dim)
        }
        let allPlain = Dictionary(uniqueKeysWithValues: drawn.map { ($0, MG3DInteraction.Style.plain) })
        // Nothing requested, nothing emphasised, or only stale ids: every item keeps its plain look.
        XCTAssertEqual(styles(["block"], glow: false, dim: false), allPlain, "emphasis alone does nothing without an opt-in")
        XCTAssertEqual(styles([], glow: true, dim: true), allPlain)
        XCTAssertEqual(styles(["ghost"], glow: true, dim: true), allPlain, "a stale or hidden id must not dim the whole board")
        // Glow only (2D parity: emphasis never dims).
        var s = styles(["block"], glow: true, dim: false)
        XCTAssertEqual(s["block"], glowing)
        XCTAssertEqual(s["halo"], glowing, "the halo of an emphasised body keeps (and strengthens) its cue")
        XCTAssertEqual(s["rail"], .plain)
        XCTAssertEqual(s["floor"], .plain)
        // Glow + dimming.
        s = styles(["block"], glow: true, dim: true)
        XCTAssertEqual(s["block"], glowing)
        XCTAssertEqual(s["halo"], glowing)
        XCTAssertEqual(s["rail"], dimmed)
        XCTAssertEqual(s["floor"], dimmed)
        // Something else emphasised: the halo dims with its target instead of staying bright on a dimmed body.
        s = styles(["rail"], glow: true, dim: true)
        XCTAssertEqual(s["halo"], s["block"])
        XCTAssertEqual(s["block"], dimmed)
        // Dimming only: emphasised items stay plain, the rest dim.
        s = styles(["rail"], glow: false, dim: true)
        XCTAssertEqual(s["rail"], .plain)
        XCTAssertEqual(s["block"], dimmed)
        // Emphasising the halo itself lights the halo only.
        s = styles(["halo"], glow: true, dim: true)
        XCTAssertEqual(s["halo"], glowing)
        XCTAssertEqual(s["block"], dimmed)
        XCTAssertEqual(s.count, drawn.count)
    }

    func testCameraPolicyKeepsLegacyBehaviourUnlessPreservingAndReframesAnotherScene() throws {
        let a = MG3DInteraction.CameraKey(camera: nil, reset: 0)
        // Legacy: exactly "every rebuild".
        XCTAssertTrue(MG3DInteraction.placesCamera(preserving: false, rebuilt: true, last: a, next: a))
        XCTAssertFalse(MG3DInteraction.placesCamera(preserving: false, rebuilt: false, last: nil, next: a))
        // Preserving: first placement, scene camera change and reset key change.
        XCTAssertTrue(MG3DInteraction.placesCamera(preserving: true, rebuilt: false, last: nil, next: a))
        XCTAssertFalse(MG3DInteraction.placesCamera(preserving: true, rebuilt: true, last: a, next: a))
        XCTAssertTrue(MG3DInteraction.placesCamera(preserving: true, rebuilt: false, last: a, next: .init(camera: nil, reset: 1)))
        XCTAssertTrue(MG3DInteraction.placesCamera(preserving: true, rebuilt: true, last: a,
                                                   next: .init(camera: MGCamera(yaw: 60), reset: 0)))
        // Scene keys: a moved part keeps the key; another world size or another scene identity changes it.
        let key = { (json: String) in MG3DInteraction.CameraKey(scene: try self.scene(json), reset: 0) }
        XCTAssertEqual(try key(twoParts), try key(twoPartsMoved))
        XCTAssertNotEqual(try key(twoParts), try key(twoPartsWider))
        XCTAssertNotEqual(try key(twoParts), try key(twoPartsRetitled))
        XCTAssertTrue(MG3DInteraction.placesCamera(preserving: true, rebuilt: true, last: try key(twoParts), next: try key(twoPartsWider)))
    }

    func testHookDerivationIsOptInAndHonoursReadOnlyMarkersAndSelection() {
        func derive(_ inspection: MG3DInspection, hasSelection: Bool = true, selected: String? = "rail",
                    markers: [String: Int] = [:], reset: Int? = nil, readOnly: Bool = false) -> MG3DInteraction.Hooks {
            .derive(hasSelection: hasSelection, selected: selected, emphasis: ["block"], markers: markers,
                    inspection: inspection, cameraReset: reset, readOnly: readOnly)
        }
        // Compatibility: without the opt-in, existing selection/emphasis/markers modifiers do nothing in 3D.
        XCTAssertEqual(derive([], markers: ["block": 1]), .legacy)
        // Selection.
        XCTAssertTrue(derive([.selection]).selects)
        XCTAssertNil(derive([.selection]).selectable, "no markers: every target")
        XCTAssertEqual(derive([.selection], markers: ["block": 1, "rail": 2]).selectable, ["block", "rail"])
        XCTAssertFalse(derive([.selection], readOnly: true).selects, "read-only boards never select")
        XCTAssertFalse(derive([.selection], hasSelection: false).selects, "no binding, nothing to write")
        XCTAssertEqual(derive([.selection]).emphasis, [], "selection alone does not style")
        // Emphasis = host emphasis ∪ current selection, like the 2D renderer input.
        let e = derive([.emphasis])
        XCTAssertEqual(e.emphasis, ["block", "rail"])
        XCTAssertTrue(e.glows); XCTAssertFalse(e.dims); XCTAssertFalse(e.selects)
        XCTAssertEqual(derive([.emphasis], selected: nil).emphasis, ["block"])
        XCTAssertTrue(derive([.dimming]).dims)
        XCTAssertEqual(derive([.emphasis], readOnly: true).emphasis, ["block", "rail"], "read-only still shows emphasis (2D parity)")
        // The camera key is its own opt-in (preserves3DCamera) and is forwarded unchanged.
        XCTAssertEqual(derive([], reset: 4).cameraReset, 4)
        XCTAssertNil(derive([.selection, .emphasis, .dimming]).cameraReset)
    }

    // MARK: host wiring (the MGSceneHost board seam)

    private final class Box { var value: String? }
    private func binding(_ box: Box) -> Binding<String?> { Binding(get: { box.value }, set: { box.value = $0 }) }

    @MainActor func testHostWiringBuildsTheThreeDBoardFromTheTeachingModifiers() throws {
        let s = try scene(inspected), box = Box()
        box.value = "rail"
        var t = MGBoardTeaching()
        t.selection = binding(box); t.emphasis = ["block"]; t.markers = ["block": 1]; t.cameraReset = 3
        // No opt-in: legacy board even though every 2D modifier is set (only the separate camera opt-in applies).
        var v = MG3DView(scene: s, items: s.items, playing: false, teaching: t, readOnly: false)
        XCTAssertNil(v.onSelect); XCTAssertNil(v.selectable); XCTAssertEqual(v.emphasis, [])
        XCTAssertFalse(v.glowsEmphasis); XCTAssertFalse(v.dimsOthers); XCTAssertEqual(v.cameraReset, 3)
        // Opted in.
        t.inspection3D = [.selection, .emphasis, .dimming]
        v = MG3DView(scene: s, items: s.items, playing: false, teaching: t, readOnly: false)
        XCTAssertEqual(v.selectable, ["block"], "markers restrict selection")
        XCTAssertEqual(v.emphasis, ["block", "rail"], "selection is part of the emphasis")
        XCTAssertTrue(v.glowsEmphasis); XCTAssertTrue(v.dimsOthers)
        v.onSelect?("block")
        XCTAssertEqual(box.value, "block", "taps write the host's binding")
        v.onSelect?(nil)
        XCTAssertNil(box.value, "empty space clears")
        // Read-only: no selection, emphasis still drawn.
        let ro = MG3DView(scene: s, items: s.items, playing: false, teaching: t, readOnly: true)
        XCTAssertNil(ro.onSelect); XCTAssertTrue(ro.glowsEmphasis)
        // The public modifiers exist and chain (compile-level check; no view is rendered).
        _ = MartyGraphicsView(scene: s).selection(binding(box)).markers(["block": 1]).emphasis([])
            .inspects3D([.selection, .emphasis]).preserves3DCamera(resetKey: 1)
    }

    @MainActor func testAChangedSelectionBindingReachesTheCoordinator() throws {
        let s = try scene(twoParts), first = Box(), second = Box()
        var t = MGBoardTeaching(); t.inspection3D = [.selection]
        t.selection = binding(first)
        let a = MG3DView(scene: s, items: s.items, playing: false, teaching: t, readOnly: false)
        t.selection = binding(second)
        let b = MG3DView(scene: s, items: s.items, playing: false, teaching: t, readOnly: false)
        // A selecting board never compares equal, so SwiftUI cannot skip the update that swaps the closure.
        XCTAssertNotEqual(a, b)
        XCTAssertNotEqual(a, a)
        let c = a.makeCoordinator(), view = a.makeView(c)
        b.update(view, c)
        c.onSelect?("block")
        XCTAssertEqual(second.value, "block")
        XCTAssertNil(first.value, "the replaced binding is no longer written")
    }

    // MARK: wiring into SceneKit (no window, no gesture)

    private func scene(_ json: String) throws -> MGScene { try MGParser.scene(data: Data(json.utf8)).get() }
    private let twoParts = #"{"v":1,"dim":"3d","world":{"w":12,"h":12},"items":[{"id":"block","k":"body","at":[6,6],"size":2},{"id":"rail","k":"path","pts":[[2,2],[10,2]]}]}"#
    private let twoPartsMoved = #"{"v":1,"dim":"3d","world":{"w":12,"h":12},"items":[{"id":"block","k":"body","at":[6,7],"size":2},{"id":"rail","k":"path","pts":[[2,2],[10,2]]}]}"#
    private let twoPartsWider = #"{"v":1,"dim":"3d","world":{"w":16,"h":12},"items":[{"id":"block","k":"body","at":[6,6],"size":2},{"id":"rail","k":"path","pts":[[2,2],[10,2]]}]}"#
    private let twoPartsRetitled = #"{"v":1,"dim":"3d","title":"Another board","world":{"w":12,"h":12},"items":[{"id":"block","k":"body","at":[6,6],"size":2},{"id":"rail","k":"path","pts":[[2,2],[10,2]]}]}"#
    /// A body with a highlight halo and, between it and the default camera (yaw 25, pitch 20), a line through the view
    /// centre 3 units in front of the body. `floorStyle` "ground" makes it a ground line.
    private func inspectedScene(floorStyle: String) -> String {
        #"{"v":1,"dim":"3d","world":{"w":12,"h":12},"items":[{"id":"block","k":"body","at":[6,6],"size":2},"#
            + #"{"id":"halo","k":"highlight","target":"block"},{"id":"rail","k":"path","pts":[[2,2],[10,2]]},"#
            + #"{"id":"floor","k":"line","from":[2,7.0261,2.555],"to":[11,7.0261,2.555],"style":""# + floorStyle + #""}]}"#
    }
    private var inspected: String { inspectedScene(floorStyle: "ground") }

    private func board(_ s: MGScene, onSelect: ((String?) -> Void)? = nil, selectable: Set<String>? = nil,
                       emphasis: Set<String> = [], glows: Bool = false, dims: Bool = false, reset: Int? = nil) -> MG3DView {
        MG3DView(scene: s, items: MGTimeline.items(s, step: 0), playing: false, selectable: selectable, onSelect: onSelect,
                 emphasis: emphasis, glowsEmphasis: glows, dimsOthers: dims, cameraReset: reset)
    }
    private func recognisers(_ view: SCNView) -> [AnyObject] {
        #if canImport(UIKit)
        return view.gestureRecognizers ?? []   // Optional on UIKit
        #else
        return view.gestureRecognizers
        #endif
    }
    private func onScreen(_ view: SCNView) {
        view.frame = CGRect(x: 0, y: 0, width: 600, height: 600)
        // A windowless view has no projection until the implicit SceneKit transaction commits (the run loop does
        // this on screen); without the flush every hit test is empty (observed while writing the first revision).
        SCNTransaction.flush()
    }

    func testDefaultsInstallNoTapAndLeaveNodesPlain() throws {
        let s = try scene(twoParts)
        let v = board(s), c = v.makeCoordinator(), view = v.makeView(c)
        XCTAssertNil(c.tap)
        for node in c.nodes.values { XCTAssertEqual(node.opacity, 1) }
        // Platform-neutral: SceneKit may install its own camera recognisers (notably on iOS), so compare against a
        // selecting board instead of expecting an empty list. Selecting adds exactly the coordinator's recogniser.
        let sv = board(s, onSelect: { _ in }), sc = sv.makeCoordinator(), selecting = sv.makeView(sc)
        let tap = try XCTUnwrap(sc.tap)
        XCTAssertEqual(recognisers(selecting).count, recognisers(view).count + 1)
        XCTAssertTrue(recognisers(selecting).contains { $0 === tap })
    }

    func testCoordinatorTapResolvesARealSceneKitHitAndClearsOnEmptySpace() throws {
        let s = try scene(twoParts)
        var picked: [String?] = []
        let v = board(s, onSelect: { picked.append($0) }), c = v.makeCoordinator(), view = v.makeView(c)
        onScreen(view)
        XCTAssertNotNil(c.tap)
        XCTAssertEqual(c.tap?.isEnabled, true)
        // The block sits at the world centre, which the default camera looks at: the view centre must hit it.
        c.select(at: CGPoint(x: 300, y: 300))
        c.select(at: CGPoint(x: 2, y: 2))
        XCTAssertEqual(picked, ["block", nil])
        // Markers restrict the selectable set: the same tap then finds nothing selectable.
        board(s, onSelect: { picked.append($0) }, selectable: ["rail"]).update(view, c)
        c.select(at: CGPoint(x: 300, y: 300))
        XCTAssertEqual(picked.last, .some(nil))
        // Turning selection off disables (never removes) the recogniser; a direct call is then a no-op.
        board(s).update(view, c)
        XCTAssertEqual(c.tap?.isEnabled, false)
        let count = picked.count
        c.select(at: CGPoint(x: 300, y: 300))
        XCTAssertEqual(picked.count, count)
    }

    func testTapPassesThroughAHighlightHaloAndAGroundLineToTheBody() throws {
        let centre = CGPoint(x: 300, y: 300)
        var picked: [String?] = []
        // Control: as a plain line the floor is hit in front of the body, so the fixture really puts it in the way.
        let plain = try scene(inspectedScene(floorStyle: "solid"))
        let pv = board(plain, onSelect: { picked.append($0) }), pc = pv.makeCoordinator(), pview = pv.makeView(pc)
        onScreen(pview)
        pc.select(at: centre)
        XCTAssertEqual(picked.last, "floor")
        // Control: the halo is hit before the body along the centre ray.
        let order = pview.hitTest(centre, options: [.searchMode: SCNHitTestSearchMode.all.rawValue]).map(\.node)
        let haloIndex = try XCTUnwrap(order.firstIndex { $0 === pc.nodes["halo"] })
        let blockIndex = try XCTUnwrap(order.firstIndex { $0 === pc.nodes["block"] })
        XCTAssertLessThan(haloIndex, blockIndex)
        // As a ground line, and with the halo, the tap reaches the body (2D parity: neither is ever a target).
        let s = try scene(inspected)
        let v = board(s, onSelect: { picked.append($0) }), c = v.makeCoordinator(), view = v.makeView(c)
        onScreen(view)
        c.select(at: centre)
        XCTAssertEqual(picked.last, "block")
        board(s, onSelect: { picked.append($0) }, selectable: ["block", "halo", "floor"]).update(view, c)
        c.select(at: centre)
        XCTAssertEqual(picked.last, "block", "markers cannot make a highlight or ground line selectable")
    }

    func testEmphasisLookIsOptInGlowKeepsOthersAndHighlightsFollowTheirTarget() throws {
        let s = try scene(inspected)
        let v = board(s), c = v.makeCoordinator(), view = v.makeView(c)
        func emission(_ id: String) -> CGFloat? {
            let n = c.nodes[id]
            return (n?.geometry ?? n?.childNodes.first?.geometry)?.firstMaterial?.emission.intensity
        }
        func opacity(_ id: String) -> CGFloat { c.nodes[id]?.opacity ?? -1 }
        // Emphasis without an opt-in leaves every node untouched.
        board(s, emphasis: ["block"]).update(view, c)
        for id in c.nodes.keys { XCTAssertEqual(opacity(id), 1); XCTAssertEqual(emission(id) ?? 1, 1) }
        // Glow only: the body and its halo glow, nothing dims.
        board(s, emphasis: ["block"], glows: true).update(view, c)
        XCTAssertEqual(emission("block") ?? 0, CGFloat(MG3DInteraction.highlightEmission), accuracy: 1e-6)
        XCTAssertEqual(emission("halo") ?? 0, CGFloat(MG3DInteraction.highlightEmission), accuracy: 1e-6)
        XCTAssertEqual(opacity("rail"), 1)
        XCTAssertEqual(opacity("halo"), 1)
        // Glow + dimming: others dim, the halo stays with its emphasised body.
        board(s, emphasis: ["block"], glows: true, dims: true).update(view, c)
        XCTAssertEqual(opacity("rail"), CGFloat(MG3DInteraction.dimmedOpacity), accuracy: 1e-6)
        XCTAssertEqual(opacity("floor"), CGFloat(MG3DInteraction.dimmedOpacity), accuracy: 1e-6)
        XCTAssertEqual(opacity("halo"), 1)
        // Another part emphasised: the halo dims together with its body.
        board(s, emphasis: ["rail"], glows: true, dims: true).update(view, c)
        XCTAssertEqual(opacity("halo"), opacity("block"), accuracy: 1e-6)
        XCTAssertEqual(opacity("block"), CGFloat(MG3DInteraction.dimmedOpacity), accuracy: 1e-6)
        // A rebuild (patched geometry) re-applies the same look to the new nodes; clearing returns to plain.
        let moved = try scene(inspected.replacingOccurrences(of: #""at":[6,6]"#, with: #""at":[6,7]"#))
        board(moved, emphasis: ["rail"], glows: true, dims: true).update(view, c)
        XCTAssertEqual(opacity("block"), CGFloat(MG3DInteraction.dimmedOpacity), accuracy: 1e-6)
        board(moved).update(view, c)
        for id in c.nodes.keys { XCTAssertEqual(opacity(id), 1) }
        XCTAssertEqual(emission("rail"), 1)
    }

    func testCameraIsKeptAcrossRebuildsOnlyWhenPreservingAndResetSettlesTheController() throws {
        let s = try scene(twoParts), moved = try scene(twoPartsMoved)
        func camera(_ view: SCNView) throws -> SCNNode { try XCTUnwrap(view.scene?.rootNode.childNode(withName: "camera", recursively: false)) }
        let orbited = SCNVector3(3, 4, 5), pivot = SCNVector3(1, 2, 3)

        // Legacy: a rebuild returns to the scene camera and leaves the built-in controller alone (as before).
        let legacy = board(s), lc = legacy.makeCoordinator(), lv = legacy.makeView(lc)
        let home = try camera(lv).position
        try camera(lv).position = orbited
        lv.defaultCameraController.target = pivot
        board(moved).update(lv, lc)
        XCTAssertEqual(try camera(lv).position.x, home.x, accuracy: 1e-5)
        XCTAssertEqual(lv.defaultCameraController.target.x, pivot.x, accuracy: 1e-5)

        // Preserving: the same rebuild keeps the (simulated) orbit; a new reset key restores the scene camera,
        // makes it the point of view again and re-centres the controller's orbit pivot.
        let keep = board(s, reset: 0), kc = keep.makeCoordinator(), kv = keep.makeView(kc)
        XCTAssertEqual(try camera(kv).position.x, home.x, accuracy: 1e-5)
        try camera(kv).position = orbited
        board(moved, reset: 0).update(kv, kc)
        XCTAssertEqual(try camera(kv).position.x, orbited.x, accuracy: 1e-5)
        XCTAssertEqual(try camera(kv).position.z, orbited.z, accuracy: 1e-5)
        kv.pointOfView = SCNNode()   // stand-in for a free camera a controller might switch to
        kv.defaultCameraController.target = pivot
        board(moved, reset: 1).update(kv, kc)
        XCTAssertEqual(try camera(kv).position.x, home.x, accuracy: 1e-5)
        XCTAssertTrue(kv.pointOfView === (try camera(kv)))
        for v in [kv.defaultCameraController.target.x, kv.defaultCameraController.target.y, kv.defaultCameraController.target.z] {
            XCTAssertEqual(v, 0, accuracy: 1e-6)
        }

        // Preserving, same reset key: a different scene (identity) or world size re-frames instead of keeping the orbit.
        try camera(kv).position = orbited
        board(try scene(twoPartsRetitled), reset: 1).update(kv, kc)
        XCTAssertEqual(try camera(kv).position.x, home.x, accuracy: 1e-5)
        try camera(kv).position = orbited
        board(try scene(twoPartsWider), reset: 1).update(kv, kc)
        XCTAssertNotEqual(try camera(kv).position.x, orbited.x, accuracy: 1e-3)
    }

    func testEquatableSeesTheHooks() throws {
        let s = try scene(twoParts)
        XCTAssertEqual(board(s), board(s))
        XCTAssertNotEqual(board(s), board(s, emphasis: ["rail"]))
        XCTAssertNotEqual(board(s, emphasis: ["rail"]), board(s, emphasis: ["rail"], glows: true))
        XCTAssertNotEqual(board(s, emphasis: ["rail"]), board(s, emphasis: ["rail"], dims: true))
        XCTAssertNotEqual(board(s), board(s, reset: 0))
        XCTAssertNotEqual(board(s), board(s, onSelect: { _ in }))
        XCTAssertNotEqual(board(s, onSelect: { _ in }), board(s, onSelect: { _ in }, selectable: ["rail"]))
    }
}
