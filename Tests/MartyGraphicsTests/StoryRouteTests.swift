// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import MartyGraphics

/// Routed story camera moves (`MGStoryPlan.routes`, `MGStoryMove`): a blocked straight move takes a pull back, an arc
/// or both before it cuts; the hold cameras stay exactly the stills' cameras; the move view ghosts what either beat
/// ghosts; the timing and the manifest fields. Synthetic geometry with neutral names.
final class StoryRouteTests: XCTestCase {
    /// A box figure: body, head, legs, two straight arms out to the sides at `armZ`, and an engine box on its back
    /// (+Y). Step 1 shows the whole figure from `first`; step 2 frames the engine from `second`.
    static func figure(first: String = "hero", second: String = "side", armZ: Double = 1450, ghost: String = "") -> String {
        """
        {"v": 2, "kind": "assembly", "title": "Figure", "parts": [
         {"id": "body", "at": [0, 0, 1215], "shape": {"box": {"size": [400, 250, 740]}}},
         {"id": "head", "at": [0, 0, 1680], "shape": {"box": {"size": [184, 200, 218]}}},
         {"id": "armL", "at": [-550, 0, \(armZ)], "shape": {"box": {"size": [700, 120, 120]}}},
         {"id": "armR", "at": [550, 0, \(armZ)], "shape": {"box": {"size": [700, 120, 120]}}},
         {"id": "legs", "at": [0, 0, 420], "shape": {"box": {"size": [300, 200, 840]}}},
         {"id": "engine", "at": [0, 170, 1300], "shape": {"box": {"size": [90, 90, 200]}}}],
         "steps": [{"say": "The figure.", "camera": "\(first)"},
                   {"say": "The engine.", "focus": ["engine"], "camera": "\(second)"\(ghost)}]}
        """
    }

    /// Each step's still camera (`MGSolidRenderPlan.cameras` at 1280 × 800), its pose and the view its move draws.
    static func shots(_ d: MGSolidDocument, _ text: String) -> [MGStoryBeatShot] {
        let plan = MGSolidRenderPlan(d, sourceName: "t.json", source: MGSolidSource(data: Data(text.utf8)), loop: false)
        let cams = plan.cameras(d, width: 1280, height: 800)
        let hold = d.steps.indices.map { k -> MGSolidView in
            let i = plan.stills.firstIndex { $0.step == k }!
            return d.view(step: k).ghosting(cams.clear[i].autoGhost)
        }
        return d.steps.indices.map { k in
            let i = plan.stills.firstIndex { $0.step == k }!
            return MGStoryBeatShot(camera: cams.stills[i], params: MGSolidShot.step(d, k)!.params,
                                   view: k == 0 ? hold[0] : hold[k].moving(from: hold[k - 1], d.assembly))
        }
    }

    func compile(_ text: String) throws -> MGSolidDocument { try MGSolidParser.document(data: Data(text.utf8)).get() }

    /// Every part box the move draws (both poses, render frame).
    func boxes(_ d: MGSolidDocument, _ beats: [MGStoryBeatShot], _ k: Int) -> [(String, MGBounds)] {
        var out: [(String, MGBounds)] = []
        for prm in [beats[k - 1].params, beats[k].params] {
            let pose = d.assembly.pose(prm)
            for p in d.assembly.parts {
                let pv = beats[k].view!.part(p.id)
                guard !pv.hidden, pv.opacity * p.material.coverage >= MGSolidFraming.blockingOpacity else { continue }
                out.append((p.id, MGSolidFrames.worldBounds(p.mesh.bounds, MGSolidStage.zUpToYUp * (pose.world[p.id] ?? .identity))))
            }
        }
        return out
    }

    func inside(_ p: MGVec3, _ b: MGBounds, grow g: Double) -> Bool {
        p.x >= b.min.x - g && p.x <= b.max.x + g && p.y >= b.min.y - g && p.y <= b.max.y + g && p.z >= b.min.z - g && p.z <= b.max.z + g
    }

    /// The figure's whole view to a close-up of the engine on its back from the side: the straight move passes the
    /// right arm, so the #37 rule cut it. Now an arc around the figure clears it. The played camera, sampled densely,
    /// never comes within the renderer's near plane of a part box; it starts and ends exactly on the still cameras.
    func testABodyToEngineCloseUpThatCutNowRoutes() throws {
        let text = Self.figure()
        let d = try compile(text)
        let beats = Self.shots(d, text)
        XCTAssertEqual(MGStoryPlan.blockedMoves(d, beats: beats.map { ($0.camera, $0.params) }), [1], "the #37 rule cuts")
        let move = try XCTUnwrap(MGStoryPlan.routes(d, beats: beats)[1])
        XCTAssertEqual(move.path, .arc)
        XCTAssertEqual(move.reason, "blocked")
        XCTAssertEqual(move.blockedBy, "armR")
        XCTAssertTrue(move.routed)
        let a = try XCTUnwrap(beats[0].camera), b = try XCTUnwrap(beats[1].camera)
        XCTAssertEqual(move.keys.first, a); XCTAssertEqual(move.keys.last, b)
        XCTAssertEqual(move.camera(0), a); XCTAssertEqual(move.camera(1), b); XCTAssertEqual(move.camera(.nan), b)
        XCTAssertEqual(move.ends.last, 1)
        XCTAssertEqual(move.ends, move.ends.sorted())
        let all = boxes(d, beats, 1)
        for j in 0...4000 {
            let c = move.camera(Double(j) / 4000)
            let g = MGSolidFraming.nearPlane(distance: c.distance)
            for (id, box) in all { XCTAssertFalse(inside(c.position, box, grow: g), "t \(Double(j) / 4000) inside \(id)") }
        }
        // The straight move does meet the arm (sampled the same way).
        var hit = false
        for j in 0...4000 {
            let c = MGStoryPlan.camera(from: a, to: b, Double(j) / 4000)
            if all.contains(where: { inside(c.position, $0.1, grow: MGSolidFraming.nearPlane(distance: c.distance)) }) { hit = true; break }
        }
        XCTAssertTrue(hit)
    }

    /// The same inputs give the same moves, key cameras and leg shares, call after call; the paths are tried in a fixed
    /// order, so the first clear one is always the same.
    func testRoutesAreDeterministic() throws {
        for (first, second, armZ) in [("hero", "side", 1450.0), ("low", "side", 1300.0), ("front", "back", 1450.0)] {
            let text = Self.figure(first: first, second: second, armZ: armZ)
            let d = try compile(text)
            let beats = Self.shots(d, text)
            let one = MGStoryPlan.routes(d, beats: beats)
            for _ in 0..<3 { XCTAssertEqual(MGStoryPlan.routes(d, beats: beats), one) }
            let again = MGStoryPlan.routes(try compile(text), beats: Self.shots(try compile(text), text))
            XCTAssertEqual(again, one, "\(first) \(second)")
        }
        let a = MGSolidCamera(target: .zero, yaw: 0, pitch: 0, distance: 500), b = MGSolidCamera(target: .zero, yaw: 180, pitch: 0, distance: 500)
        let c = MGStoryPlan.candidates(a, b, centre: .zero, rho: 400)
        XCTAssertEqual(c.map(\.path), MGStoryPlan.candidates(a, b, centre: .zero, rho: 400).map(\.path))
        XCTAssertLessThanOrEqual(c.count + 1, MGStoryPlan.maxRouteCandidates)
        XCTAssertEqual(c.first?.path, .pullback)
        XCTAssertEqual(c.last?.path, .combined)
    }

    /// A move whose ends are clear but whose straight path passes a post takes a pull back; one whose end camera sits
    /// inside a part cuts (no path can end there clear). A layout beat cuts with reason `layout`; cameras that are not
    /// finite stay straight and untested, as `blockedMoves` skips them.
    func testPullbackCutAndLayout() throws {
        let post = try compile("""
            {"v": 2, "kind": "assembly", "parts": [{"id": "hub", "shape": {"box": {"size": [40, 40, 40]}}},
             {"id": "post", "at": [500, 0, 0], "shape": {"box": {"size": [100, 100, 100]}}}]}
            """)
        let p = post.defaults
        let a = MGSolidCamera(target: .zero, yaw: 0, pitch: 0, distance: 500)
        let b = MGSolidCamera(target: .zero, yaw: 180, pitch: 0, distance: 500)
        XCTAssertEqual(MGStoryPlan.blockedMoves(post, beats: [(a, p), (b, p)]), [1])
        let m = try XCTUnwrap(MGStoryPlan.routes(post, beats: [MGStoryBeatShot(camera: a, params: p), MGStoryBeatShot(camera: b, params: p)])[1])
        XCTAssertEqual(m.path, .pullback)
        XCTAssertEqual(m.keys.count, 3)
        XCTAssertEqual(m.keys[1].targetVector, a.targetVector)
        XCTAssertEqual(m.keys[1].yaw, a.yaw); XCTAssertEqual(m.keys[1].pitch, a.pitch)
        // The first clear pull back: 1.5 × still meets the post's growth; 2 × clears it.
        XCTAssertEqual(m.keys[1].distance, a.distance * MGStoryPlan.pullbackFactors[1])
        XCTAssertNotEqual(MGStoryPlan.test([a, m.keys[1].with(distance: a.distance * MGStoryPlan.pullbackFactors[0]), b],
                                           post.assembly.parts.map { ($0.id, MGSolidFrames.worldBounds($0.mesh.bounds, MGSolidStage.zUpToYUp * (post.assembly.pose(p).world[$0.id] ?? .identity))) }),
                          .clear)
        // The end camera inside the post: every path ends in its box.
        let inPost = MGSolidCamera(target: MGVec3(500, 0, 0), yaw: 0, pitch: 0, distance: 10)
        let cut = try XCTUnwrap(MGStoryPlan.routes(post, beats: [MGStoryBeatShot(camera: a, params: p), MGStoryBeatShot(camera: inPost, params: p)])[1])
        XCTAssertEqual(cut.path, .cut)
        XCTAssertEqual(cut.reason, "blocked")
        XCTAssertEqual(cut.blockedBy, "post")
        XCTAssertEqual(cut.keys, [inPost])
        XCTAssertEqual(cut.camera(0.5), inPost)
        // Layout: a cut whatever the geometry.
        let shots = [MGStoryBeatShot(camera: a, params: p), MGStoryBeatShot(camera: a, params: p)]
        XCTAssertEqual(MGStoryPlan.routes(post, beats: shots, layout: [1])[1], .cut(a, reason: "layout"))
        // Not finite: straight, untested; a missing camera: no move.
        let bad = MGSolidCamera(target: MGVec3(.nan, 0, 0), yaw: 0, pitch: 0, distance: 10)
        XCTAssertEqual(MGStoryPlan.routes(post, beats: [MGStoryBeatShot(camera: a, params: p), MGStoryBeatShot(camera: bad, params: p)])[1]?.reason, "untested")
        XCTAssertNil(MGStoryPlan.routes(post, beats: [MGStoryBeatShot(camera: a, params: p), MGStoryBeatShot(camera: nil, params: p)])[1])
        XCTAssertEqual(MGStoryPlan.routes(post, beats: [MGStoryBeatShot(camera: a, params: p)]), [:])
    }

    /// Only parts the move draws solid block it: a ghost or a hidden part does not, glass does not; the move view
    /// ghosts what the previous beat ghosts, so a camera leaving a close-up through a ghosted body does not start
    /// inside a solid one.
    func testOnlyPartsTheMoveDrawsSolidBlock() throws {
        let post = try compile("""
            {"v": 2, "kind": "assembly", "parts": [{"id": "hub", "shape": {"box": {"size": [40, 40, 40]}}},
             {"id": "post", "at": [500, 0, 0], "shape": {"box": {"size": [100, 100, 100]}}},
             {"id": "pane", "at": [-500, 0, 0], "material": "glass", "shape": {"box": {"size": [100, 100, 100]}}}],
             "steps": [{"say": "One."}, {"say": "Two.", "ghost": ["post"]}, {"say": "Three.", "hide": ["post"]}]}
            """)
        let p = post.defaults
        let a = MGSolidCamera(target: .zero, yaw: 0, pitch: 0, distance: 500)
        let b = MGSolidCamera(target: .zero, yaw: 180, pitch: 0, distance: 500)
        func move(_ view: MGSolidView?) -> MGStoryMove? {
            MGStoryPlan.routes(post, beats: [MGStoryBeatShot(camera: a, params: p), MGStoryBeatShot(camera: b, params: p, view: view)])[1]
        }
        XCTAssertEqual(move(post.view(step: 0))?.path, .pullback)
        XCTAssertEqual(move(post.view(step: 1))?.path, .straight)
        XCTAssertEqual(move(post.view(step: 2))?.path, .straight)
        // Glass (coverage 0.22) does not block: the mirrored move past the pane stays straight.
        let a2 = MGSolidCamera(target: .zero, yaw: 0, pitch: 0, distance: 500), b2 = MGSolidCamera(target: .zero, yaw: -180, pitch: 0, distance: 500)
        let mirrored = MGStoryPlan.routes(post, beats: [MGStoryBeatShot(camera: a2, params: p), MGStoryBeatShot(camera: b2, params: p, view: post.view(step: 1))])
        XCTAssertEqual(mirrored[1]?.path, .straight)
        // The move view: step 1's view arriving from step 2 (which ghosts the post) draws the post as a ghost.
        let v = post.view(step: 0).moving(from: post.view(step: 1), post.assembly)
        XCTAssertEqual(v.part("post").opacity, MGSolidView.ghostOpacity)
        XCTAssertEqual(v.part("hub").opacity, 1)
        // A hidden part in the previous view is not a ghost; a ghost of this view stays one.
        XCTAssertEqual(post.view(step: 0).moving(from: post.view(step: 2), post.assembly), post.view(step: 0))
        XCTAssertEqual(post.view(step: 1).moving(from: post.view(step: 0), post.assembly), post.view(step: 1))
        // The glass pane's own opacity is not a ghost.
        XCTAssertEqual(v.part("pane").opacity, post.view(step: 0).part("pane").opacity)
    }

    /// The plan with routed moves: a routed beat moves for `routedTransitionSeconds`, a straight one for
    /// `transitionSeconds`, a cut not at all; beat lengths and frame counts do not change; hold frames show exactly
    /// the beat's camera; move frames lie on the route; the caption, labels and claims wait for the hold; the manifest
    /// gives each move's path.
    func testRoutedPlanTimingAndManifest() throws {
        let text = Self.figure()
        let d = try compile(text)
        let beats = Self.shots(d, text) + [Self.shots(d, text)[0]]
        let cams = beats.map(\.camera)
        var moves = MGStoryPlan.routes(d, beats: beats)
        XCTAssertEqual(moves[1]?.path, .arc)
        moves[2] = .straight(cams[1]!, cams[2]!)
        moves[3] = .cut(cams[0]!, reason: "layout")
        let base = try MGStoryPlan(captions: ["1. The figure.", "2. The engine.", "3. Back.", "4. Again."], spins: [0, 0, 0, 0], fps: 30)
        let plan = base.routed(moves.merging([7: .cut(cams[0]!, reason: "layout"), 0: .cut(cams[0]!, reason: "layout")]) { a, _ in a })
        XCTAssertEqual(plan.frameCount, base.frameCount)
        XCTAssertEqual(plan.beats.map(\.frames), base.beats.map(\.frames))
        XCTAssertEqual(plan.beats[1].transitionFrames, 30)
        XCTAssertEqual(plan.beats[2].transitionFrames, 18)
        XCTAssertEqual(plan.moves.keys.sorted(), [1, 2, 3], "moves for the first beat or beats the plan lacks are ignored")
        XCTAssertEqual(plan.cuts, [3])
        let four = cams + [cams[0]]
        for i in 0..<plan.frameCount {
            let f = plan.frame(i)
            let c = try XCTUnwrap(plan.camera(frame: i, beatCameras: four))
            if plan.holds(frame: i) {
                XCTAssertEqual(c, four[f.beat], "frame \(i)")
                XCTAssertNotNil(plan.caption(frame: i))
            } else {
                XCTAssertNil(plan.caption(frame: i))
                if f.beat == 1 { XCTAssertEqual(c, moves[1]!.camera(f.camera)) }
                if f.beat == 2 { XCTAssertEqual(c, MGStoryPlan.camera(from: four[1]!, to: four[2]!, f.camera)) }
                XCTAssertNotEqual(f.beat, 3, "a cut has no move frames")
            }
        }
        XCTAssertEqual(plan.holdStartFrame(1), plan.beats[1].startFrame + 30)
        XCTAssertEqual(plan.holdStartFrame(3), plan.beats[3].startFrame)
        let fields = plan.manifestFields()
        XCTAssertEqual(fields["routedTransitionSeconds"], .number(MGStoryTiming.routedTransitionSeconds))
        guard case .array(let list)? = fields["beats"] else { return XCTFail("beats") }
        XCTAssertNil(list[0]["path"])
        XCTAssertEqual(list[1]["path"], .string("arc")); XCTAssertEqual(list[1]["pathReason"], .string("blocked"))
        XCTAssertEqual(list[1]["blockedBy"], .string("armR")); XCTAssertEqual(list[1]["moveSeconds"], .number(1))
        XCTAssertEqual(list[2]["path"], .string("straight")); XCTAssertEqual(list[2]["pathReason"], .string("clear"))
        XCTAssertNil(list[2]["blockedBy"]); XCTAssertEqual(list[2]["moveSeconds"], .number(0.6))
        XCTAssertEqual(list[3]["path"], .string("cut")); XCTAssertEqual(list[3]["moveSeconds"], .number(0))
        XCTAssertEqual(list[3]["holdStart"], list[3]["start"])
        // Without moves the plan and its manifest beats are those of the release before (plus `routedTransitionSeconds`).
        guard case .array(let plain)? = base.manifestFields()["beats"] else { return XCTFail("beats") }
        for b in plain { if case .object(let o) = b { XCTAssertEqual(Set(o.keys), ["beat", "start", "holdStart", "seconds"]) } }
        // A short beat bounds the routed move to half the beat.
        let short = try MGStoryPlan(captions: ["1. A.", "2. B."], spins: [0, 0], fps: 10).routed([1: moves[1]!])
        XCTAssertEqual(short.beats[1].transitionFrames, min(10, short.beats[1].frames / 2))
    }

    /// Each routed leg is split so the camera distance changes by at most 10 % per chord; every played camera lies
    /// within the leg's chord error of its chord, and the renderer's near plane there is within that chord's growth
    /// less the error. A pure pull back is a straight dolly.
    func testLegChordsBoundThePlayedPath() throws {
        let legs: [(MGSolidCamera, MGSolidCamera)] = [
            (MGSolidCamera(target: .zero, yaw: 0, pitch: 10, distance: 400), MGSolidCamera(target: MGVec3(50, 0, 0), yaw: 170, pitch: 40, distance: 1600)),
            (MGSolidCamera(target: MGVec3(0, 900, 0), yaw: 32, pitch: 28, distance: 447), MGSolidCamera(target: MGVec3(0, 900, 0), yaw: 32, pitch: 28, distance: 1790)),
            (MGSolidCamera(target: MGVec3(10, 20, 30), yaw: -170, pitch: -60, distance: 4000), MGSolidCamera(target: .zero, yaw: 170, pitch: 85, distance: 300)),
        ]
        for (a, b) in legs {
            let leg = try XCTUnwrap(MGStoryPlan.legChords(a, b))
            let n = leg.points.count - 1
            XCTAssertLessThanOrEqual(n, MGStoryPlan.maxMoveChords)
            XCTAssertGreaterThanOrEqual(Double(n), abs(log(b.distance / a.distance)) / log(1 + MGStoryPlan.routeDistanceStep) - 1e-9)
            XCTAssertEqual(leg.points.first, a.position); XCTAssertEqual(leg.points.last, b.position)
            let path = try XCTUnwrap(MGStoryPlan.movePath(a, b, minChords: n))
            let error = path.grow - MGSolidFraming.nearPlane(distance: max(a.distance, b.distance))
            for j in 0...4000 {
                let t = Double(j) / 4000
                let c = MGStoryPlan.camera(from: a, to: b, t)
                let k = min(n - 1, Int(t * Double(n)))
                let q0 = leg.points[k], q1 = leg.points[k + 1], dir = q1 - q0
                let u = max(0, min(1, (c.position - q0).dot(dir) / max(1e-12, dir.dot(dir))))
                XCTAssertLessThanOrEqual((c.position - (q0 + dir * u)).length, error + 1e-9, "t \(t)")
                XCTAssertLessThanOrEqual(MGSolidFraming.nearPlane(distance: c.distance), leg.grows[k] - error + 1e-9, "t \(t)")
            }
        }
        XCTAssertNil(MGStoryPlan.legChords(legs[0].0, MGSolidCamera(target: .zero, yaw: .nan, pitch: 0, distance: 10)))
        // Shares: one per leg, increasing, the last exactly 1; equal shares for a chain that does not move.
        let s = MGStoryPlan.shares([legs[0].0, legs[0].1, legs[2].1])
        XCTAssertEqual(s.count, 2); XCTAssertEqual(s.last, 1); XCTAssertLessThan(s[0], 1); XCTAssertGreaterThan(s[0], 0)
        XCTAssertEqual(MGStoryPlan.shares([legs[0].0, legs[0].0, legs[0].0]), [0.5, 1])
        XCTAssertEqual(MGStoryPlan.shares([legs[0].0]), [])
    }
}

// MARK: Review fixes (PR #44): parts that move during the move

extension StoryRouteTests {
    /// Review repro: a 20 mm cube on a pivot turns from −90° to +90° during the move. Its boxes at the two beat poses
    /// clear the pull back, but at the middle frame the camera is inside it. The router now tests every part's swept
    /// box over the move's actual frames, so that path is refused; without the frames (no plan) the beat cuts
    /// (`motion`). Every frame of the move the router gives shows the camera outside every part's box at that frame.
    func testAPartThatMovesDuringTheMoveIsSwept() throws {
        let a = MGSolidCamera(target: .zero, yaw: 0, pitch: 0, distance: 500), b = MGSolidCamera(target: .zero, yaw: 180, pitch: 0, distance: 500)
        // The pivot sits so that the pull back's middle camera (t = 0.5, distance 1000 leg) meets the cube's middle pose.
        let mid = MGStoryPlan.route(a, b, boxes: [("post", MGBounds(min: MGVec3(450, -50, -50), max: MGVec3(550, 50, 50)))]).camera(0.5).position
        let pivot = mid - MGVec3(1200, 0, 0)
        let text = """
            {"v":2,"kind":"assembly","parts":[{"id":"post","at":[500,0,0],"shape":{"box":{"size":[100,100,100]}}},{"id":"pivot","at":[\(pivot.x),\(pivot.y),\(pivot.z)],"shape":{"box":{"size":[1,1,1]}}},{"id":"moving","parent":"pivot","at":[1200,0,0],"shape":{"box":{"size":[20,20,20]}}}],"steps":[{"say":"Before.","pose":{"pivot":{"rot":[0,0,1,-90]}}},{"say":"After.","pose":{"pivot":{"rot":[0,0,1,90]}}}]}
            """
        let d = try compile(text)
        let shots = d.steps.indices.map { k in MGStoryBeatShot(camera: k == 0 ? a : b, params: MGSolidShot.step(d, k)!.params, step: d.steps[k]) }
        // The endpoint boxes alone (the rule this replaces) accept a pull back that crosses the cube.
        var ends: [(id: String, box: MGBounds)] = []
        for k in 0..<2 {
            let pose = d.assembly.pose(shots[k].params)
            for p in d.assembly.parts { ends.append((p.id, MGSolidFrames.worldBounds(p.mesh.bounds, pose.world[p.id] ?? .identity))) }
        }
        let old = MGStoryPlan.route(a, b, boxes: ends)
        XCTAssertEqual(old.path, .pullback)
        let plan = try MGStoryPlan(captions: ["1. Before.", "2. After."], spins: [0, 0], fps: 30)
        var crossed = false
        let routedPlan = plan.routed([1: old])
        for i in routedPlan.beats[1].startFrame..<routedPlan.holdStartFrame(1) {
            let f = routedPlan.frame(i)
            let pose = d.assembly.pose(MGStoryPlan.movePose(d, beats: shots, 1, spin: f.spin, blend: f.camera))
            let box = MGSolidFrames.worldBounds(d.assembly.part("moving")!.mesh.bounds, pose.world["moving"] ?? .identity)
            if inside(old.camera(f.camera).position, box, grow: 0) { crossed = true }
        }
        XCTAssertTrue(crossed, "the old route puts the camera inside the moving cube at a frame")
        // Without the frames: a cut, reason `motion`.
        let blind = try XCTUnwrap(MGStoryPlan.routes(d, beats: shots, stage: .identity)[1])
        XCTAssertEqual(blind.path, .cut); XCTAssertEqual(blind.reason, "motion")
        // With the frames: the pull back is refused; the arc the router takes keeps the camera outside every part at
        // every frame it plays (grown by the near plane there).
        let move = try XCTUnwrap(MGStoryPlan.routes(d, beats: shots, plan: plan, stage: .identity)[1])
        XCTAssertEqual(move.path, .arc)
        XCTAssertEqual(MGStoryPlan.routes(d, beats: shots, plan: plan, stage: .identity)[1], move, "deterministic")
        let played = plan.routed([1: move])
        for i in played.beats[1].startFrame..<played.holdStartFrame(1) {
            let f = played.frame(i), c = move.camera(f.camera)
            let pose = d.assembly.pose(MGStoryPlan.movePose(d, beats: shots, 1, spin: f.spin, blend: f.camera))
            for part in d.assembly.parts {
                let box = MGSolidFrames.worldBounds(part.mesh.bounds, pose.world[part.id] ?? .identity)
                XCTAssertFalse(inside(c.position, box, grow: MGSolidFraming.nearPlane(distance: c.distance)), "frame \(i) \(part.id)")
            }
        }
        // The swept box holds the cube at every frame of a routed move.
        let swept = try XCTUnwrap(MGStoryPlan.sweptBoxes(d, beats: shots, 1, frames: MGStoryPlan.moveFrames(plan, 1, routed: true), stage: .identity))
        let cube = try XCTUnwrap(swept.first { $0.id == "moving" }).box
        for (spin, blend) in MGStoryPlan.moveFrames(plan, 1, routed: true) {
            let pose = d.assembly.pose(MGStoryPlan.movePose(d, beats: shots, 1, spin: spin, blend: blend))
            let box = MGSolidFrames.worldBounds(d.assembly.part("moving")!.mesh.bounds, pose.world["moving"] ?? .identity)
            XCTAssertTrue(inside(box.min, cube, grow: 0) && inside(box.max, cube, grow: 0))
        }
        XCTAssertEqual(MGStoryPlan.moveFrames(plan, 1, routed: true).count, 30)
        XCTAssertEqual(MGStoryPlan.moveFrames(plan, 1, routed: false).count, 18)
        // A part that does not move keeps its one box; a still beat needs no plan.
        let post = try XCTUnwrap(swept.first { $0.id == "post" }).box
        XCTAssertEqual(post, MGBounds(min: MGVec3(450, -50, -50), max: MGVec3(550, 50, 50)))
        let still = MGStoryPlan.routes(d, beats: [shots[0], MGStoryBeatShot(camera: b, params: shots[0].params, step: d.steps[0])], stage: .identity)
        XCTAssertNotEqual(still[1]?.reason, "motion")
    }

    /// A routed move that was clear only because a moving part sits elsewhere at both beat poses: a 20 mm cube on a
    /// pivot turns from 60° to 120° about X and passes through the start camera's place at the middle frame. The post
    /// blocks the straight move, and the endpoint boxes alone accept a pull back; the swept box holds the start camera,
    /// so every path is refused and the engine now cuts.
    func testARouteClearOnlyBecauseOfAMovingPartNowCuts() throws {
        let a = MGSolidCamera(target: .zero, yaw: 0, pitch: 0, distance: 500), b = MGSolidCamera(target: .zero, yaw: 180, pitch: 0, distance: 500)
        let text = #"{"v":2,"kind":"assembly","parts":[{"id":"post","at":[500,0,0],"shape":{"box":{"size":[100,100,100]}}},{"id":"pivot","at":[0,0,200],"shape":{"box":{"size":[1,1,1]}}},{"id":"moving","parent":"pivot","at":[0,300,0],"shape":{"box":{"size":[20,20,20]}}}],"steps":[{"say":"Before.","pose":{"pivot":{"rot":[1,0,0,60]}}},{"say":"After.","pose":{"pivot":{"rot":[1,0,0,120]}}}]}"#
        let d = try compile(text)
        let shots = d.steps.indices.map { k in MGStoryBeatShot(camera: k == 0 ? a : b, params: MGSolidShot.step(d, k)!.params, step: d.steps[k]) }
        var ends: [(id: String, box: MGBounds)] = []
        for k in 0..<2 {
            let pose = d.assembly.pose(shots[k].params)
            for p in d.assembly.parts { ends.append((p.id, MGSolidFrames.worldBounds(p.mesh.bounds, pose.world[p.id] ?? .identity))) }
        }
        let old = MGStoryPlan.route(a, b, boxes: ends)
        XCTAssertTrue(old.routed, "the endpoint boxes alone route it: \(old.path)")
        let plan = try MGStoryPlan(captions: ["1. Before.", "2. After."], spins: [0, 0], fps: 30)
        // The cube's middle frame holds the start camera's place.
        let f = plan.routed([1: old]).frame(plan.beats[1].startFrame + 15)
        let pose = d.assembly.pose(MGStoryPlan.movePose(d, beats: shots, 1, spin: f.spin, blend: f.camera))
        let cube = MGSolidFrames.worldBounds(d.assembly.part("moving")!.mesh.bounds, pose.world["moving"] ?? .identity)
        XCTAssertTrue(inside(a.position, cube, grow: MGSolidFraming.nearPlane(distance: a.distance)))
        let move = try XCTUnwrap(MGStoryPlan.routes(d, beats: shots, plan: plan, stage: .identity)[1])
        XCTAssertEqual(move.path, .cut)
        XCTAssertEqual(move.reason, "blocked")
        XCTAssertEqual(move.blockedBy, "moving")
    }
}

extension MGSolidCamera {
    func with(distance d: Double) -> MGSolidCamera { MGSolidCamera(target: targetVector, yaw: yaw, pitch: pitch, distance: d, fieldOfView: fieldOfView) }
}
