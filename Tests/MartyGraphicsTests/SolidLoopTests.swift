// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import MartyGraphics

/// Seamless loops (`MGSolidLoop`, docs/ENGINE.md "Seamless loops"): exact periods from exact rates and measured mesh
/// symmetry, a numeric check of the period, and no jump at the wrap. Numeric goldens only, no pixels.
final class SolidLoopTests: XCTestCase {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let gearbox = "docs/assets/from-a-prompt/robot-joint/robot-joint-gearbox.json"

    func document(_ path: String) throws -> MGSolidDocument {
        let data = try Data(contentsOf: Self.root.appendingPathComponent(path))
        switch MGSolidParser.document(data: data) {
        case .success(let d): return d
        case .failure(let e): XCTFail("\(path) refused: \(e)"); throw e
        }
    }

    typealias Ratio = MGSolidLoop.Ratio

    func testExactFractions() {
        XCTAssertEqual(Ratio.approximating(2.0 / 7), Ratio(2, 7))
        XCTAssertEqual(Ratio.approximating(-20.0 / 21), Ratio(-20, 21))
        XCTAssertEqual(Ratio.approximating(2.0 / 7 * 2.0 / 7)?.description, "4/49")
        XCTAssertEqual(Ratio.approximating(0), Ratio(0, 1))
        XCTAssertEqual(Ratio.approximating(3), Ratio(3, 1))
        XCTAssertNil(Ratio.approximating(.pi), "π is not an exact fraction with q ≤ 100 000")
        XCTAssertNil(Ratio.approximating(.nan))
        XCTAssertEqual(Ratio(6, -4)?.description, "-3/2")
        XCTAssertNil(Ratio(1, 0))
        XCTAssertEqual(Ratio(4, 49)?.times(3), Ratio(12, 49))
        XCTAssertNil(Ratio(Int.max / 2, 1)?.times(3), "overflow is nil, not a trap")
    }

    func testTheLatticeOfTheRobotJointConditions() {
        // Rate × symmetry per joint: sun 1 × 24, carrier 2/7 × 3, planet −20/21 × 18, carrier 4/49 × 3, planet −40/147 × 18.
        let symmetric = [Ratio(24, 1)!, Ratio(6, 7)!, Ratio(-120, 7)!, Ratio(12, 49)!, Ratio(-240, 49)!]
        XCTAssertEqual(MGSolidLoop.lattice(symmetric), Ratio(49, 6))
        // Without symmetry every joint must make whole turns: 147 input turns.
        let strict = [Ratio(1, 1)!, Ratio(2, 7)!, Ratio(-20, 21)!, Ratio(4, 49)!, Ratio(-40, 147)!]
        XCTAssertEqual(MGSolidLoop.lattice(strict), Ratio(147, 1))
        XCTAssertNil(MGSolidLoop.lattice([]))
        XCTAssertEqual(MGSolidLoop.divisors(36), [1, 2, 3, 4, 6, 9, 12, 18, 36])
        XCTAssertEqual(MGSolidLoop.divisors(1), [1])
    }

    /// The symmetry order of one driven part's mesh about its own axis.
    func order(_ mesh: MGMesh) -> Int {
        let a = MGAssembly(name: "m", parts: [MGPart(id: "p", name: "p", mesh: mesh, material: .brass, joint: .revolute(axis: .unitZ),
                                                    drive: .input(scale: 1, offset: 0))])
        let g = MGSolidLoop.Geometry(a, input: 0, tolerance: MGSolidLoop.Geometry.defaultTolerance(a, input: 0))
        return g.meshSymmetry("p")
    }

    func testMeshSymmetryIsMeasuredNotAssumed() {
        XCTAssertEqual(order(.extrude(MGSpurGear(teeth: 18, module: 2).profile(bore: 4.3), to: 10, chamfer: 0.5)), 18)
        // The 72-segment bore is round, so a 23-tooth gear is 23-fold although 23 does not divide 72.
        XCTAssertEqual(order(.extrude(MGSpurGear(teeth: 23, module: 2).profile(bore: 5), to: 10, chamfer: 0.5)), 23)
        XCTAssertEqual(order(.hexPrism(acrossFlats: 10, to: 5)), 6)
        XCTAssertEqual(order(.chamferedBox(size: MGVec3(20, 8, 4), chamfer: 0.5)), 2)
        XCTAssertEqual(order(.cylinder(radius: 6, to: 20, chamfer: 0.5, segments: 24)), 0, "a round shaft looks the same at any turn")
        // A keyway breaks the symmetry of the bore: only a whole turn repeats.
        XCTAssertEqual(order(.extrude(MGSpurGear(teeth: 18, module: 2).profile(bore: 6, keyway: (width: 2, depth: 1)), to: 10)), 1)
    }

    func testTheRenderLoopOfTheRobotJointJumpsAtTheWrap() throws {
        let doc = try document(Self.gearbox)
        let period = try MGSolidLoop.period(doc).get()
        let render = MGSolidRenderPlan(doc, sourceName: "robot-joint-gearbox.json", source: MGSolidSource(data: Data()), loop: true, loopRate: 30)
        XCTAssertEqual(render.loop.count, 360)
        let rows = MGSolidLoop.wrap(doc.assembly, poses: render.loop.map(\.params), symmetry: period.symmetry)
        let carrier = try XCTUnwrap(rows.first { $0.part == "carrier2" })
        // The reported seam: the output carrier (4/49 of a turn per input turn) advances 0.082° a frame over one input
        // turn, then turns 29.306° back from the last frame to the first.
        XCTAssertEqual(carrier.step, 4.0 / 49, accuracy: 1e-9)
        XCTAssertEqual(carrier.jump, -360.0 * 4 / 49 * 359 / 360, accuracy: 1e-9)
        XCTAssertEqual(carrier.step, 0.082, accuracy: 5e-4)
        XCTAssertEqual(carrier.jump, -29.306, accuracy: 5e-4)
        XCTAssertGreaterThan(MGSolidLoop.worst(rows)?.error ?? 0, 29)
    }

    func testTheRobotJointRepeatsAfterFortyNineSixthsOfAnInputTurn() throws {
        let doc = try document(Self.gearbox)
        let period = try MGSolidLoop.period(doc).get()
        XCTAssertFalse(period.strict, "the measured symmetries pass the numeric check")
        // 49/6 input turns: the output carrier turns 2/3 of a turn (two arms on), the sun 8 1/6 turns (4 teeth on).
        XCTAssertEqual(period.fundamental, Ratio(49, 6))
        XCTAssertEqual(period.turns, Ratio(49, 6))
        let byPart = Dictionary(period.joints.map { ($0.part, $0) }, uniquingKeysWith: { a, _ in a })
        XCTAssertEqual(byPart["sun1"]?.rate, Ratio(1, 1)); XCTAssertEqual(byPart["sun1"]?.symmetry, 24)
        XCTAssertEqual(byPart["carrier1"]?.rate, Ratio(2, 7)); XCTAssertEqual(byPart["carrier1"]?.symmetry, 3)
        XCTAssertEqual(byPart["carrier2"]?.rate, Ratio(4, 49)); XCTAssertEqual(byPart["carrier2"]?.symmetry, 3)
        let planets = period.joints.filter { $0.part.hasPrefix("planet") }
        XCTAssertEqual(planets.count, 6)
        for j in planets { XCTAssertEqual(j.symmetry, 18, j.part); XCTAssertEqual(j.meshSymmetry, 18, j.part) }
        // The analysis is deterministic.
        XCTAssertEqual(try MGSolidLoop.period(doc).get(), period)
    }

    func testTheSeamlessPlanHasNoJumpAtTheWrap() throws {
        let doc = try document(Self.gearbox)
        let plan = try MGSolidLoop.plan(doc, fps: 30).get()
        // The 24-tooth sun passes 49/6 × 24 = 196 tooth steps; at most 0.4 a frame gives 490 frames (16.33 s at 30 fps).
        XCTAssertEqual(plan.frames, 490)
        XCTAssertEqual(plan.shots.count, 490)
        XCTAssertEqual(plan.seconds, 490.0 / 30, accuracy: 1e-12)
        XCTAssertEqual(plan.stepsPerFrame, 0.4, accuracy: 1e-12)
        let rows = MGSolidLoop.wrap(doc.assembly, poses: plan.shots.map(\.params), closing: plan.closing.params, symmetry: plan.period.symmetry)
        XCTAssertEqual(rows.count, plan.period.joints.count)
        for r in rows { XCTAssertEqual(r.jump, r.step, accuracy: 1e-7, r.part) }
        XCTAssertLessThan(MGSolidLoop.worst(rows)?.error ?? 1, 1e-7)
        // The closing shot is shot 0 one period on: the same scene, with the motion, the orbit and the explode beat done.
        XCTAssertEqual(plan.closing.params.input, doc.defaults.input + 2 * .pi * 49 / 6, accuracy: 1e-9)
        XCTAssertEqual(plan.closing.orbit, 360)
        XCTAssertEqual(plan.closing.params.explode, 0)
        XCTAssertEqual(plan.shots[0].params.explode, 0)
        let g = MGSolidLoop.Geometry(doc.assembly, input: doc.defaults.input,
                                     tolerance: MGSolidLoop.Geometry.defaultTolerance(doc.assembly, input: doc.defaults.input))
        XCTAssertTrue(g.repeats(after: plan.period.turns, hidden: []))
        XCTAssertFalse(g.repeats(after: Ratio(1, 1)!, hidden: []), "one input turn does not repeat the scene")
        // The loop camera repeats with the loop: the closing frame's camera is the first frame's.
        let cams = MGSolidLoop.cameras(doc, shots: plan.shots + [plan.closing], aspect: 1.6).cameras
        XCTAssertEqual(cams.count, 491)
        XCTAssertLessThan((cams[490].position - cams[0].position).length, 1e-6 * max(1, cams[0].position.length))
        XCTAssertLessThan((cams[490].targetVector - cams[0].targetVector).length, 1e-9 * max(1, cams[0].targetVector.length))
        XCTAssertEqual(cams[490].distance, cams[0].distance, accuracy: 1e-9 * cams[0].distance)
        XCTAssertEqual(try MGSolidLoop.plan(doc, fps: 30).get(), plan)
        // At 10 fps the same 490 frames take 49 s; a 30 s cap refuses instead of aliasing the teeth.
        var short = MGSolidLoop.Options(); short.maxSeconds = 30
        if case .failure(let r) = MGSolidLoop.plan(doc, fps: 10, options: short) { XCTAssertEqual(r.reason, .frames) }
        else { XCTFail("a 49 s loop fits no 30 s cap") }
    }

    func testAOneTurnLoopKeepsTheRenderPace() throws {
        // The slider-crank repeats after one crank turn; its render loop is already seamless, crank motion included.
        let doc = try document("Examples/Solid3D/Sources/MartySolid3D/Models/slider-crank.json")
        let period = try MGSolidLoop.period(doc).get()
        XCTAssertEqual(period.turns, Ratio(1, 1))
        let render = MGSolidRenderPlan(doc, sourceName: "", source: MGSolidSource(data: Data()), loop: true, loopRate: 30)
        let closing = MGPoseParameters(input: doc.defaults.input + 2 * .pi)
        let rows = MGSolidLoop.wrap(doc.assembly, poses: render.loop.map(\.params), closing: closing, symmetry: period.symmetry)
        XCTAssertFalse(rows.isEmpty)
        for r in rows { XCTAssertEqual(r.jump, r.step, accuracy: 1e-7, r.part) }
        let plan = try MGSolidLoop.plan(doc, fps: 30).get()
        XCTAssertEqual(plan.frames, 360)
        XCTAssertEqual(plan.shots, render.loop, "a period of one turn at the render pace is the render loop")
    }

    func testAPeriodOfAFractionOfATurnPlaysAWholeMultiple() throws {
        // 16 and 32 teeth, 1:2: one tooth step (1/16 input turn) repeats the scene; the loop plays 16 of them.
        let small = MGMesh.extrude(MGSpurGear(teeth: 16, module: 2).profile(bore: 4), to: 8)
        let large = MGMesh.extrude(MGSpurGear(teeth: 32, module: 2).profile(bore: 4), to: 8)
        let a = MGAssembly(name: "pair", parts: [
            MGPart(id: "pinion", name: "pinion", mesh: small, material: .brass, joint: .revolute(axis: .unitZ), drive: .input(scale: 1, offset: 0)),
            MGPart(id: "wheel", name: "wheel", mesh: large, material: .brushedSteel, placement: .translation(MGVec3(48, 0, 0)),
                   joint: .revolute(axis: .unitZ), drive: .gear(driver: "pinion", ratio: -0.5, carrier: nil, offset: 0)),
        ])
        let period = try MGSolidLoop.period(a).get()
        XCTAssertEqual(period.fundamental, Ratio(1, 16))
        XCTAssertEqual(period.turns, Ratio(1, 1))
        var longer = MGSolidLoop.Options(); longer.targetTurns = 2.5
        XCTAssertEqual(try MGSolidLoop.period(a, options: longer).get().turns, Ratio(5, 2))
    }

    func testWhatCannotLoopIsRefusedWithAReason() {
        let shaft = MGMesh.cylinder(radius: 3, to: 10, segments: 24)
        let slide = MGAssembly(name: "rack", parts: [
            MGPart(id: "rack", name: "rack", mesh: .chamferedBox(size: MGVec3(40, 4, 4), chamfer: 0), material: .darkSteel,
                   joint: .prismatic(axis: .unitX), drive: .input(scale: 5, offset: 0))])
        XCTAssertEqual(refusal(slide), .slide)
        let irrational = MGAssembly(name: "pi", parts: [
            MGPart(id: "a", name: "a", mesh: .hexPrism(acrossFlats: 6, to: 4), material: .brass, joint: .revolute(axis: .unitZ),
                   drive: .input(scale: 1 / Double.pi, offset: 0))])
        XCTAssertEqual(refusal(irrational), .ratio)
        let slow = MGAssembly(name: "slow", parts: [
            MGPart(id: "a", name: "a", mesh: .hexPrism(acrossFlats: 6, to: 4), material: .brass, joint: .revolute(axis: .unitZ),
                   drive: .input(scale: 1.0 / 97, offset: 0)),
            MGPart(id: "b", name: "b", mesh: shaft, material: .brass, joint: .revolute(axis: .unitZ), drive: .input(scale: 1, offset: 0))])
        // A hexagon at 1/97 of a turn per input turn repeats after 97/6 turns; a 12-turn cap refuses it.
        var cap = MGSolidLoop.Options(); cap.maxTurns = 12
        if case .failure(let r) = MGSolidLoop.period(slow, options: cap) {
            XCTAssertEqual(r.reason, .period); XCTAssertEqual(r.turns, Ratio(97, 6))
        } else { XCTFail("97/6 turns exceed the cap") }
        XCTAssertEqual(try MGSolidLoop.period(slow).get().turns, Ratio(97, 6))
    }

    func refusal(_ a: MGAssembly) -> MGSolidLoop.Refusal.Reason? {
        if case .failure(let r) = MGSolidLoop.period(a) { return r.reason }
        return nil
    }
}
