// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import MartyGraphics

/// The unblocked-focus rule (`MGSolidFraming.clearView`): automatic ghosts for parts outside the focus context, the
/// fixed alternative directions when a context part is in the way, a section step that must face its cut, the hidden
/// share in the manifest fields; the story rule that cuts a camera move through a part (`MGStoryPlan.blockedMoves`); and
/// the board pane width that fits the board's content (`MGExplainerFrame.boardShare`).
final class UnblockedFocusTests: ExplainerTestCase {
    func compile(_ text: String) throws -> MGSolidDocument { try MGSolidParser.document(data: Data(text.utf8)).get() }

    /// A 60 mm block (`target`) and other parts around it, with one focus step (`front`: the camera is on the −Y side).
    func doc(_ others: String, step: String = #""focus": ["target"], "camera": "front""#) -> String {
        """
        {"v": 2, "kind": "assembly", "title": "Blocked", "parts": [
         {"id": "target", "shape": {"box": {"size": [60, 60, 60]}}}\(others.isEmpty ? "" : ", " + others)],
         "steps": [{"say": "The block.", \(step)}]}
        """
    }

    func clear(_ d: MGSolidDocument, step: Int = 0) throws -> MGSolidClearView {
        let shot = try XCTUnwrap(MGSolidShot.step(d, step))
        return MGSolidFraming.clearView(d, shot: shot, aspect: 1.6)
    }

    /// A wall between the camera and the focus, not touching it: drawn as an automatic ghost; the preset direction stays.
    func testAPartInFrontOfTheFocusBecomesAnAutomaticGhost() throws {
        let d = try compile(doc(#"{"id": "wall", "at": [0, -100, 0], "shape": {"box": {"size": [400, 20, 400]}}}"#))
        let c = try clear(d)
        XCTAssertTrue(c.tested)
        XCTAssertEqual(c.rule, .focus)
        XCTAssertEqual(c.direction, .preset)
        XCTAssertEqual(c.autoGhost, ["wall"])
        // One sample per triangle of the box (fewer than `occlusionSamples`).
        let triangles = try XCTUnwrap(d.assembly.part("target")).mesh.triangleCount
        XCTAssertEqual(c.samples, min(triangles, MGSolidFraming.occlusionSamples))
        XCTAssertEqual(c.occludedSamples, 0)
        XCTAssertTrue(c.clear)
        XCTAssertNil(c.facesCut)
        // The camera is the one the framing rule gives (the rule only adds ghosts here).
        XCTAssertEqual(c.camera, MGSolidFraming.camera(d, shot: try XCTUnwrap(MGSolidShot.step(d, 0)), aspect: 1.6))
        // The shot's view draws the wall at the ghost opacity; the step view and the legend are unchanged.
        let v = c.view(d.view(step: 0))
        XCTAssertEqual(v.part("wall").opacity, MGSolidView.ghostOpacity)
        XCTAssertEqual(v.part("target").opacity, 1)
        XCTAssertEqual(d.view(step: 0).part("wall").opacity, 1)
        XCTAssertEqual(c.manifestFields["autoGhost"], .array([.string("wall")]))
        XCTAssertEqual(c.manifestFields["occluded"], .number(0))
        XCTAssertEqual(c.manifestFields["view"], .string("preset"))
        XCTAssertEqual(c.manifestFields["focusSamples"], .number(Double(c.samples)))
    }

    /// Without the wall nothing is ghosted.
    func testAFreeViewHasNoGhost() throws {
        let c = try clear(try compile(doc(#"{"id": "far", "at": [0, 400, 0], "shape": {"box": {"size": [40, 40, 40]}}}"#)))
        XCTAssertTrue(c.tested)
        XCTAssertEqual(c.autoGhost, [])
        XCTAssertEqual(c.occludedSamples, 0)
        XCTAssertEqual(c.direction, .preset)
    }

    /// A wall that touches the focus is its context (explicit `focus`): it is never ghosted, so the first clear
    /// alternative direction (the other side) is taken and recorded.
    func testAContextPartInTheWayTurnsTheCamera() throws {
        let d = try compile(doc(#"{"id": "wall", "at": [0, -40, 0], "shape": {"box": {"size": [400, 20, 400]}}}"#))
        let c = try clear(d)
        XCTAssertTrue(c.tested)
        XCTAssertEqual(c.direction, .opposite)
        XCTAssertEqual(c.autoGhost, [])
        XCTAssertEqual(c.occludedSamples, 0)
        let base = MGSolidCamera.presets["front"]!
        XCTAssertEqual(c.camera.yaw, base.yaw + 180)
        XCTAssertEqual(c.camera.pitch, base.pitch)
        XCTAssertEqual(c.manifestFields["view"], .string("opposite"))
    }

    /// A focus enclosed on every side by its context (a closed box of plates that touch it): no direction is clear, the
    /// preset stays, and the hidden samples are reported (the case that used to report `offView` 0).
    func testAnEnclosedFocusReportsItsHiddenSamples() throws {
        // Plates 1 mm off each face (within the 0.5 % touch tolerance, so they are context, but not coplanar).
        let plates = [("px", "[101, 0, 0]", "[20, 222, 222]"), ("nx", "[-101, 0, 0]", "[20, 222, 222]"),
                      ("py", "[0, 101, 0]", "[222, 20, 222]"), ("ny", "[0, -101, 0]", "[222, 20, 222]"),
                      ("pz", "[0, 0, 101]", "[222, 222, 20]"), ("nz", "[0, 0, -101]", "[222, 222, 20]")]
        let others = plates.map { #"{"id": "\#($0.0)", "at": \#($0.1), "shape": {"box": {"size": \#($0.2)}}}"# }.joined(separator: ", ")
        // The target grows to 180 mm, so every plate touches it within the tolerance (its context).
        let d = try compile(doc(others).replacingOccurrences(of: "[60, 60, 60]", with: "[180, 180, 180]"))
        let c = try clear(d)
        XCTAssertTrue(c.tested)
        XCTAssertEqual(c.direction, .preset)
        XCTAssertEqual(c.autoGhost, [])
        XCTAssertFalse(c.clear)
        XCTAssertEqual(c.occludedSamples, c.samples)
        XCTAssertGreaterThan(c.occludedSamples, 0)
        XCTAssertEqual(c.occluded, 1)
    }

    /// A part that only holds the end of a focus part inside it (like a piston round a rod end) is not a blocker: no
    /// direction would show the embedded end, so it is not ghosted (inferred focus: `a` and its touching `b`).
    func testAPartAroundAnEmbeddedEndIsNotGhosted() throws {
        let d = try compile("""
            {"v": 2, "kind": "assembly", "parts": [
             {"id": "a", "shape": {"box": {"size": [40, 40, 40]}}},
             {"id": "b", "shape": {"shaft": {"radius": 5, "length": 100, "z0": 20}}},
             {"id": "c", "at": [0, 0, 110], "shape": {"box": {"size": [30, 30, 40]}}},
             {"id": "far", "at": [1000, 0, 0], "shape": {"box": {"size": [10, 10, 10]}}}],
             "steps": [{"say": "The block.", "highlight": ["a"], "camera": "front"}]}
            """)
        XCTAssertEqual(MGSolidFraming.focusParts(d, step: 0, params: d.defaults), ["a", "b"])
        let c = try clear(d)
        XCTAssertTrue(c.tested)
        XCTAssertEqual(c.autoGhost, [])
        XCTAssertEqual(c.direction, .preset)
    }

    /// A cutaway: a section step must look at the cut face. The `front` preset sees the outside of the kept half, so the
    /// first alternative on the cut-away side (+X here: yaw + 90) is taken.
    func testASectionStepFacesItsCut() throws {
        let d = try compile("""
            {"v": 2, "kind": "assembly", "title": "Cutaway", "parts": [
             {"id": "case", "shape": {"tube": {"inner": 40, "outer": 50, "length": 200, "z0": -100}}},
             {"id": "core", "shape": {"shaft": {"radius": 20, "length": 160, "z0": -80}}}],
             "steps": [{"say": "Inside.", "focus": ["case", "core"], "camera": "front",
                        "section": {"normal": [1, 0, 0], "offset": 0, "parts": ["case"]}}]}
            """)
        let c = try clear(d)
        XCTAssertTrue(c.tested)
        XCTAssertEqual(c.facesCut, true)
        XCTAssertEqual(c.direction, .quarterLeft)
        XCTAssertEqual(c.camera.yaw, MGSolidCamera.presets["front"]!.yaw + 90)
        XCTAssertTrue(c.clear)
        XCTAssertEqual(c.manifestFields["facesCut"], .bool(true))
        // The camera is on the cut-away side (+X) of the plane.
        let eye = MGSolidStage.zUpToYUp.inverse.apply(c.camera.position)
        XCTAssertGreaterThan(eye.x, 0)
    }

    /// Only a step framed on its focus is tested; whole-model shots keep their camera and give no fields.
    func testWholeModelShotsAreNotTested() throws {
        let d = try compile(doc(#"{"id": "wall", "at": [0, -100, 0], "shape": {"box": {"size": [400, 20, 400]}}}"#,
                                step: #""camera": "front""#))
        let c = try clear(d)
        XCTAssertFalse(c.tested)
        XCTAssertEqual(c.autoGhost, [])
        XCTAssertEqual(c.manifestFields, [:])
        let hero = MGSolidShot(file: "hero.png", params: d.defaults, preset: "hero", orbit: 0, highlight: [], margin: 0.8, step: nil,
                               title: d.title, caption: nil)
        XCTAssertFalse(MGSolidFraming.clearView(d, shot: hero, aspect: 1.6).tested)
    }

    /// The render plan, the explainer pane camera and repeated runs all give the same result (one function).
    func testOneFunctionForThePlanTheExplainerAndRepeatedRuns() throws {
        let text = doc(#"{"id": "wall", "at": [0, -100, 0], "shape": {"box": {"size": [400, 20, 400]}}}"#)
        let d = try compile(text)
        let plan = MGSolidRenderPlan(d, sourceName: "b.json", source: MGSolidSource(data: Data(text.utf8)), loop: false)
        let cams = plan.cameras(d, width: 1280, height: 800)
        XCTAssertEqual(cams.clear.count, plan.stills.count)
        XCTAssertEqual(cams.clear.map(\.camera), cams.stills)
        XCTAssertEqual(cams.clear.map(\.rule), cams.rules)
        let stepStill = try XCTUnwrap(plan.stills.firstIndex { $0.step == 0 })
        XCTAssertEqual(cams.clear[stepStill].autoGhost, ["wall"])
        for _ in 0..<3 { XCTAssertEqual(try compile(text).steps.count, 1); XCTAssertEqual(plan.cameras(try compile(text), width: 1280, height: 800), cams) }
        // The explainer pane: `solidCamera` is `solidClearView`'s camera and rule.
        let ex = XFix.doc(solid: #"{"v":2,"parts":[{"id":"target","shape":{"box":{"size":[60,60,60]}}},{"id":"wall","at":[0,-100,0],"shape":{"box":{"size":[400,20,400]}}}]}"#,
                          beats: #"[{"say":"The block.","view":{"focus":["target"],"camera":"front"}}]"#)
        let clock = MGManualClock()
        var s = try XFix.load(ex, pacing: .speech, clock: clock)
        clock.advance(by: s.motionRemaining); _ = s.tick()
        let sd = try XCTUnwrap(s.solid)
        let pane = MGFrameRect(x: 0, y: 0, width: 800, height: 500)
        let cv = MGExplainerFrame.solidClearView(sd, view: s.presented, stepIndex: s.solidStep(forBeat: 0), pane: pane)
        let cam = MGExplainerFrame.solidCamera(sd, view: s.presented, stepIndex: s.solidStep(forBeat: 0), pane: pane)
        XCTAssertEqual(cv.camera, cam.camera); XCTAssertEqual(cv.rule, cam.rule)
        XCTAssertEqual(cv.autoGhost, ["wall"])
    }

    /// Hostile numbers built in code (a NaN pose, a zero or NaN aspect) give a finite camera and never trap.
    func testHostileNumbers() throws {
        let d = try compile(doc(#"{"id": "wall", "at": [0, -100, 0], "shape": {"box": {"size": [400, 20, 400]}}}"#))
        var shot = try XCTUnwrap(MGSolidShot.step(d, 0))
        for aspect in [0, -1, Double.nan, .infinity] {
            let c = MGSolidFraming.clearView(d, shot: shot, aspect: aspect)
            XCTAssertTrue(c.camera.distance.isFinite && c.camera.target.allSatisfy(\.isFinite))
        }
        shot.params = MGPoseParameters(input: .nan, explode: .nan)
        let c = MGSolidFraming.clearView(d, shot: shot, aspect: 1.6)
        XCTAssertTrue(c.camera.distance.isFinite && c.camera.target.allSatisfy(\.isFinite))
        XCTAssertLessThanOrEqual(c.occludedSamples, c.samples)
        let bad = MGSolidCamera(target: MGVec3(.nan, 0, 0), yaw: .nan, pitch: 0, distance: .nan)
        XCTAssertEqual(MGStoryPlan.blockedMoves(d, beats: [(bad, d.defaults), (bad, d.defaults)]), [])
    }

    /// `ghosting` lowers opacity to the ghost value, keeps fainter parts, and ignores unknown ids.
    func testGhostingAView() throws {
        let d = try compile("""
            {"v": 2, "kind": "assembly", "parts": [{"id": "a", "shape": {"box": {"size": [10, 10, 10]}}},
             {"id": "b", "opacity": 0.15, "at": [20, 0, 0], "shape": {"box": {"size": [10, 10, 10]}}}]}
            """)
        let v = d.view(step: nil).ghosting(["a", "b", "nope"])
        XCTAssertEqual(v.part("a").opacity, MGSolidView.ghostOpacity)
        XCTAssertEqual(v.part("b").opacity, 0.15)
        XCTAssertNil(v.parts["nope"])
        XCTAssertEqual(d.view(step: nil).ghosting([]), d.view(step: nil))
    }

    // MARK: Story moves

    /// A move whose path passes inside a part's box cuts; a move that stays clear of every part does not; beats without a
    /// camera are skipped.
    func testACameraMoveThroughAPartCuts() throws {
        // A post 500 mm out on +X: a yaw 0 → 180 move at 500 mm passes through yaw 90, inside the post.
        let post = try compile("""
            {"v": 2, "kind": "assembly", "parts": [{"id": "hub", "shape": {"box": {"size": [40, 40, 40]}}},
             {"id": "post", "at": [500, 0, 0], "shape": {"box": {"size": [100, 100, 100]}}}]}
            """)
        let a = MGSolidCamera(target: .zero, yaw: 0, pitch: 0, distance: 500)
        let b = MGSolidCamera(target: .zero, yaw: 180, pitch: 0, distance: 500)
        let p = post.defaults
        XCTAssertEqual(MGStoryPlan.blockedMoves(post, beats: [(a, p), (b, p)]), [1])
        // The same move with the post on −X (the path never goes there) is not cut.
        let away = try compile("""
            {"v": 2, "kind": "assembly", "parts": [{"id": "hub", "shape": {"box": {"size": [40, 40, 40]}}},
             {"id": "post", "at": [-500, 0, 0], "shape": {"box": {"size": [100, 100, 100]}}}]}
            """)
        XCTAssertEqual(MGStoryPlan.blockedMoves(away, beats: [(a, p), (b, p)]), [])
        XCTAssertEqual(MGStoryPlan.blockedMoves(post, beats: [(a, p), (nil, p), (b, p)]), [])
        XCTAssertEqual(MGStoryPlan.blockedMoves(post, beats: [(a, p)]), [])
        // Deterministic, and the plan honours the cut: every frame of beat 2 has its own camera.
        let plan = try MGStoryPlan(captions: ["1. A.", "2. B."], spins: [0, 0], fps: 10)
        let cuts = MGStoryPlan.blockedMoves(post, beats: [(a, p), (b, p)])
        for i in 0..<plan.frameCount where plan.frame(i).beat == 1 {
            XCTAssertEqual(plan.camera(frame: i, beatCameras: [a, b], cuts: cuts), b)
            XCTAssertTrue(plan.holds(frame: i, cuts: cuts))
        }
        guard case .array(let beats)? = plan.manifestFields(cuts: cuts)["beats"] else { return XCTFail("beats") }
        XCTAssertEqual(beats[1]["holdStart"], beats[1]["start"])
    }

    /// Review repro: a camera moving in a straight line passes through a 1 mm part between two focus cubes 1,000 mm
    /// apart. The exact segment test cuts the move; without the obstacle nothing cuts.
    func testATinyPartOnAStraightMoveCuts() throws {
        func doc(_ post: Bool) -> String {
            let p = post ? #",{"id":"post","at":[8.916323731138545,-3.663388602844842,0.40375422998458826],"shape":{"box":{"size":[1,1,1]}}}"# : ""
            return #"{"v":2,"kind":"assembly","parts":[{"id":"first","shape":{"box":{"size":[1,1,1]}}},{"id":"last","at":[1000,0,0],"shape":{"box":{"size":[1,1,1]}}}\#(p)],"steps":[{"say":"First.","focus":["first"],"camera":"front"},{"say":"Last.","focus":["last"],"camera":"front"}]}"#
        }
        for post in [false, true] {
            let text = doc(post)
            let d = try compile(text)
            XCTAssertTrue(MGSolidReport.check(data: Data(text.utf8), profile: .strict).ok)
            let plan = MGSolidRenderPlan(d, sourceName: "t.json", source: MGSolidSource(data: Data(text.utf8)), loop: false)
            let cams = plan.cameras(d, width: 1280, height: 800)
            let beats = d.steps.indices.map { k in (cams.stills[plan.stills.firstIndex { $0.step == k }!] as MGSolidCamera?, MGSolidShot.step(d, k)!.params) }
            // The move only translates: one straight chord.
            let path = try XCTUnwrap(MGStoryPlan.movePath(beats[0].0!, beats[1].0!))
            XCTAssertEqual(path.points.count, 2)
            XCTAssertEqual(MGStoryPlan.blockedMoves(d, beats: beats), post ? [1] : [], "post \(post)")
            if post {
                // The played camera of the second move frame at 30 fps lies inside the post.
                let story = try MGStoryPlan(captions: ["1. First.", "2. Last."], spins: [0, 0], fps: 30)
                let i = story.beats[1].startFrame + 1
                let c = try XCTUnwrap(story.camera(frame: i, beatCameras: beats.map(\.0)))
                let box = MGSolidFrames.worldBounds(try XCTUnwrap(d.assembly.part("post")).mesh.bounds,
                                                    MGSolidStage.zUpToYUp * (d.assembly.pose(d.defaults).world["post"] ?? .identity))
                let p = c.position
                XCTAssertTrue(p.x >= box.min.x && p.x <= box.max.x && p.y >= box.min.y && p.y <= box.max.y && p.z >= box.min.z && p.z <= box.max.z)
            }
        }
    }

    /// A curved move (a turn and a zoom) is split into chords with a proven error bound, never more than the cap.
    func testCurvedMovesUseBoundedChords() throws {
        let a = MGSolidCamera(target: .zero, yaw: 0, pitch: 10, distance: 400)
        let b = MGSolidCamera(target: MGVec3(50, 0, 0), yaw: 170, pitch: 40, distance: 1600)
        let path = try XCTUnwrap(MGStoryPlan.movePath(a, b))
        XCTAssertGreaterThan(path.points.count, 2)
        XCTAssertLessThanOrEqual(path.points.count, MGStoryPlan.maxMoveChords + 1)
        XCTAssertEqual(path.points.first, a.position); XCTAssertEqual(path.points.last, b.position)
        // Every played camera lies within the growth of its chord (sampled densely here as a check of the bound).
        let n = path.points.count - 1
        for j in 0...4000 {
            let t = Double(j) / 4000
            let p = MGStoryPlan.camera(from: a, to: b, t).position
            let k = min(n - 1, Int(t * Double(n)))
            let q0 = path.points[k], q1 = path.points[k + 1], dir = q1 - q0
            let u = max(0, min(1, (p - q0).dot(dir) / max(1e-12, dir.dot(dir))))
            XCTAssertLessThanOrEqual((p - (q0 + dir * u)).length, path.grow, "t \(t)")
        }
        XCTAssertNil(MGStoryPlan.movePath(a, MGSolidCamera(target: .zero, yaw: .nan, pitch: 0, distance: 10)))
    }

    // MARK: Watertight crossings

    /// A 60 mm cube (12 triangles): rays through a face diagonal (both diagonals, one of them the shared triangle
    /// edge), through a cube edge and through two corners each cross the surface exactly twice; a ray that ends at the
    /// centre crosses once (inside).
    func testEdgeAndVertexHitsCountOnce() throws {
        let mesh = try XCTUnwrap(try compile(#"{"v":2,"kind":"assembly","parts":[{"id":"c","shape":{"box":{"size":[60,60,60]}}}]}"#).assembly.part("c")).mesh
        XCTAssertEqual(mesh.triangleCount, 12)
        func count(_ a: MGVec3, _ b: MGVec3) -> Int { MGSolidFraming.OcclusionProbe.crossings(a, b, mesh, after: 1e-9, before: 1).count }
        // Face diagonals of the face y = −30, both directions of travel.
        for (x, z) in [(10.0, 10.0), (10.0, -10.0), (-7.5, 7.5), (0.0, 0.0)] {
            XCTAssertEqual(count(MGVec3(x, -200, z), MGVec3(x, 200, z)), 2, "diagonal \(x) \(z)")
            XCTAssertEqual(count(MGVec3(x, 200, z), MGVec3(x, -200, z)), 2, "diagonal back \(x) \(z)")
        }
        // Through a cube edge (x = −30, y = −30) at an angle, and through two opposite corners along the main diagonal.
        XCTAssertEqual(count(MGVec3(-130, -130, 7), MGVec3(170, 170, 7)), 2, "edge")
        XCTAssertEqual(count(MGVec3(-100, -100, -100), MGVec3(100, 100, 100)), 2, "corners")
        XCTAssertEqual(count(MGVec3(100, -100, 100), MGVec3(-100, 100, -100)), 2, "corners 2")
        // Ending inside: odd.
        XCTAssertEqual(count(MGVec3(10, -200, 10), .zero), 1)
        XCTAssertEqual(count(MGVec3(-100, -100, -100), .zero), 1)
        // A ray that misses.
        XCTAssertEqual(count(MGVec3(31, -200, 0), MGVec3(31, 200, 0)), 0)
    }

    /// Review repro: a 1 mm wall in front of the target whose focus ray crosses the wall through a shared triangle edge
    /// is a blocker (it used to count three crossings, look like it held the sample inside it, and stay opaque).
    func testAWallHitOnASharedEdgeIsGhosted() throws {
        let d = try compile(#"{"v":2,"kind":"assembly","parts":[{"id":"target","shape":{"box":{"size":[60,60,60]}}},{"id":"wall","at":[8,-67.46066323413808,-3.1549492401849406],"shape":{"box":{"size":[1,1,1]}}}],"steps":[{"say":"Target.","focus":["target"],"camera":"front"}]}"#)
        let c = try clear(d)
        XCTAssertTrue(c.tested)
        XCTAssertEqual(c.autoGhost, ["wall"])
        XCTAssertEqual(c.occludedSamples, 0)
        XCTAssertEqual(c.samples, 12)
    }

    // MARK: Board pane width

    func scene(_ json: String) throws -> MGScene { try MGParser.scene(json: XFix.json(json)).get() }

    /// A small table takes much less than the old 45 %, never under the minimum; a wide board takes the maximum; a board
    /// with nothing measurable keeps the maximum. Deterministic and the same for a still and for points (SwiftUI).
    func testBoardShareFitsTheContent() throws {
        let small = try scene(#"{"v":1,"items":[{"id":"cap","k":"text","at":[6,7],"text":"Given figures"},{"id":"t","k":"table","at":[6,4],"header":true,"cells":[["Item","About"],["Thrust kgf",144],["Mass kg",100],["Engines",5]]}]}"#)
        let share = MGExplainerFrame.boardShare(scene: small, width: 1280, height: 800, primarySolid: true)
        XCTAssertGreaterThanOrEqual(share, MGExplainerFrame.boardMinShare)
        XCTAssertLessThan(share, 0.40)
        for _ in 0..<3 { XCTAssertEqual(MGExplainerFrame.boardShare(scene: small, width: 1280, height: 800, primarySolid: true), share) }
        // The same rule on a SwiftUI area in points (unit 1) gives a share in the same bounds.
        let pts = MGExplainerFrame.boardShare(scene: small, areaWidth: 1100, areaHeight: 600, gap: 12, primarySolid: true)
        XCTAssertGreaterThanOrEqual(pts, MGExplainerFrame.boardMinShare); XCTAssertLessThanOrEqual(pts, MGExplainerFrame.boardMaxShare)
        // A line across the whole board: the maximum (50 %, or 55 % for a primary board).
        let wide = try scene(#"{"v":1,"items":[{"id":"l","k":"line","from":[0,5],"to":[12,5]}]}"#)
        XCTAssertEqual(MGExplainerFrame.boardShare(scene: wide, width: 1280, height: 800, primarySolid: true), MGExplainerFrame.boardMaxShare)
        XCTAssertEqual(MGExplainerFrame.boardShare(scene: wide, width: 1280, height: 800, primarySolid: false), MGExplainerFrame.boardPrimaryMaxShare)
        // One tiny item: the minimum.
        let dot = try scene(#"{"v":1,"items":[{"id":"n","k":"text","at":[6,4],"text":"x"}]}"#)
        XCTAssertEqual(MGExplainerFrame.boardShare(scene: dot, width: 1280, height: 800, primarySolid: true), MGExplainerFrame.boardMinShare)
        XCTAssertEqual(MGExplainerFrame.boardShare(scene: nil, width: 1280, height: 800, primarySolid: true), MGExplainerFrame.boardMaxShare)
        XCTAssertEqual(MGExplainerFrame.boardShare(scene: small, areaWidth: .nan, areaHeight: 600, gap: 12, primarySolid: true),
                       MGExplainerFrame.boardMaxShare)
    }

    /// The panes take the share: the board pane is that share of the split width, whole pixels, inside the frame, and
    /// the board is drawn at its reference pane's scale (a narrower pane crops only empty board).
    func testPanesUseTheShare() throws {
        for (w, h) in [(1280, 800), (641, 401), (3840, 2160)] {
            let area = MGExplainerFrame.contentArea(width: w, height: h)
            let total = area.width - Int(MGExplainerFrame.paneGap(width: w))
            for share in [0.28, 0.33, 0.5] {
                let p = MGExplainerFrame.panes(width: w, height: h, board: true, solid: true, primarySolid: true, boardShare: share)
                let b = try XCTUnwrap(p.board), s = try XCTUnwrap(p.solid)
                XCTAssertEqual(b.width, Int(Double(total) * share))
                XCTAssertEqual(b.width + s.width, total)
                XCTAssertLessThanOrEqual(s.x + s.width, w)
                XCTAssertLessThanOrEqual(b.x + b.width, s.x)
            }
            // Without a share the old split stays (45 % board with a primary solid).
            let old = MGExplainerFrame.panes(width: w, height: h, board: true, solid: true, primarySolid: true)
            XCTAssertEqual(old.board?.width, total - Int((Double(area.width) - MGExplainerFrame.paneGap(width: w)) * 0.55))
            // Shares outside the bounds are clamped.
            let low = MGExplainerFrame.panes(width: w, height: h, board: true, solid: true, primarySolid: true, boardShare: 0.01)
            XCTAssertEqual(low.board?.width, Int(Double(total) * MGExplainerFrame.boardMinShare))
        }
        let small = try scene(#"{"v":1,"items":[{"id":"t","k":"table","at":[6,4],"header":true,"cells":[["Item","About"],["A",1]]}]}"#)
        let ref = MGExplainerFrame.boardReferenceSize(areaWidth: 1232, areaHeight: 556, gap: 16, primarySolid: true)
        let narrow = CGSize(width: 400, height: 556)
        let fitted = MGExplainerBoard.input(small, view: MGExplainerBeatView(), size: narrow, fit: ref)
        let wideIn = MGExplainerBoard.input(small, view: MGExplainerBeatView(), size: ref)
        XCTAssertEqual(fitted.viewport.scale, wideIn.viewport.scale)
        XCTAssertEqual(fitted.viewport.size, narrow)
    }
}
