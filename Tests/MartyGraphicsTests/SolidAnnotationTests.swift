// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import MartyGraphics

/// Assembly v2 annotations (open vocabulary 3a): labels, arrows, dimensions, visibility, warnings, budget and hostile
/// input. Test names carry the acceptance ids A1–A26 of the PR 3 spec (§11 A).
final class SolidAnnotationTests: XCTestCase {
    func parse(_ text: String, profile: MGSolidProfile = .standard) -> Result<MGSolidDocument, MGSolidIssue> {
        MGSolidParser.document(data: Data(text.utf8), profile: profile)
    }
    func doc(_ text: String, file: StaticString = #filePath, line: UInt = #line) throws -> MGSolidDocument {
        switch parse(text) {
        case .success(let d): return d
        case .failure(let e): XCTFail("refused: \(e)", file: file, line: line); throw e
        }
    }
    func reason(_ text: String, profile: MGSolidProfile = .standard) -> String? {
        if case .failure(let e) = parse(text, profile: profile) { return e.reason }
        return nil
    }

    /// A 15:30 external pair, centres 45 mm apart (the PR 3 card example).
    static let pair = #"{"id": "p", "shape": {"gear": {"teeth": 15, "module": 2, "width": 8}}, "joint": {"revolute": [0, 0, 1]}, "drive": {"input": 1}}, {"id": "w", "at": [45, 0, 0], "shape": {"gear": {"teeth": 30, "module": 2, "width": 8}}, "joint": {"revolute": [0, 0, 1]}}"#
    func gears(_ annotations: String, extraParts: String = "", steps: String = #"[{"say": "Two gears."}]"#, v: Int = 2) -> String {
        #"{"v": \#(v), "kind": "assembly", "parts": [\#(Self.pair)\#(extraParts)], "constraints": [{"gearMesh": {"a": "p", "b": "w"}}], "annotations": \#(annotations), "steps": \#(steps)}"#
    }
    /// The shipped slider-crank (crank radius 18, rod 62), as v2. Input 0 is top dead centre.
    static let slider = #"{"id": "frame", "material": "darkSteel", "shape": {"box": {"size": [150, 60, 6], "chamfer": 1}}, "at": [30, 0, -14]}, {"id": "crank", "shape": [{"shaft": {"radius": 6, "length": 16, "z0": -10}}, {"box": {"size": [30, 12, 6], "chamfer": 1, "at": [9, 0, -3]}}, {"shaft": {"radius": 4, "length": 10, "z0": 0, "at": [18, 0, 0]}}], "joint": {"revolute": [0, 0, 1]}, "drive": {"input": 1}}, {"id": "piston", "shape": {"shaft": {"radius": 14, "length": 24, "z0": -12, "rot": [0, 1, 0, 90]}}, "joint": {"prismatic": [1, 0, 0]}, "drive": {"crankSlider": {"crank": "crank", "radius": 18, "rod": 62}}}, {"id": "rod", "parent": "piston", "shape": {"box": {"size": [62, 8, 4], "chamfer": 1, "at": [-31, 0, 5]}}, "joint": {"revolute": [0, 0, 1]}, "drive": {"crankRod": {"crank": "crank", "radius": 18, "rod": 62}}}"#
    func slider(_ annotations: String, steps: String = #"[{"say": "A slider-crank."}]"#) -> String {
        #"{"v": 2, "kind": "assembly", "parts": [\#(Self.slider)], "annotations": \#(annotations), "steps": \#(steps)}"#
    }
    func stage(_ annotations: String, steps: String = #"[{"say": "A planetary stage."}]"#) -> String {
        #"{"v": 2, "kind": "assembly", "parts": [{"id": "stage", "use": "planetaryStage", "with": {"sunTeeth": 24, "planetTeeth": 18, "planets": 3}}], "annotations": \#(annotations), "steps": \#(steps)}"#
    }
    func rest(_ d: MGSolidDocument) -> MGPose { d.assembly.pose(MGPoseParameters(input: d.defaults.input, explode: 0)) }
    func claim(_ d: MGSolidDocument, _ id: String) -> MGSolidClaim? { d.claims.first { $0.kind == .annotation && $0.id == id } }

    // MARK: Labels

    func testA1LabelOnAComponentPartFillsFactsAndIsSolved() throws {
        let d = try doc(stage(#"{"labels": [{"id": "lSun", "at": {"part": "stage.sun", "offset": [0, 0, 14]}, "text": "Sun: {stage.sun.teeth} teeth"}]}"#))
        let l = try XCTUnwrap(d.annotations.label("lSun"))
        let expected = rest(d).world["stage.sun"]!.apply(MGVec3(0, 0, 14))
        let got = l.at.world(rest(d))
        XCTAssertEqual(got.x, expected.x, accuracy: 1e-9); XCTAssertEqual(got.y, expected.y, accuracy: 1e-9); XCTAssertEqual(got.z, expected.z, accuracy: 1e-9)
        XCTAssertEqual(l.text, "Sun: 24 teeth")
        XCTAssertEqual(l.template, "Sun: {stage.sun.teeth} teeth")
        XCTAssertEqual(l.facts, ["stage.sun.teeth"])
        XCTAssertEqual(claim(d, "lSun")?.tier, .solved)
        XCTAssertEqual(d.describe("lSun")?["kind"], .string("label"))
        // An anchor name resolves to its part.
        let viaAnchor = try doc(stage(#"{"labels": [{"id": "lIn", "at": "stage.input", "text": "Input"}]}"#))
        XCTAssertEqual(viaAnchor.annotations.labels[0].at.part, "stage.sun")
        XCTAssertNil(claim(viaAnchor, "lIn"), "a label that shows no fact makes no claim")
    }

    func testA22LabelTypedDigitsNeedUnchecked() throws {
        XCTAssertEqual(reason(gears(#"{"labels": [{"id": "l1", "at": "p", "text": "Gear 2"}]}"#)), "text.number.label.l1")
        let d = try doc(gears(#"{"labels": [{"id": "l1", "at": "p", "text": "Gear 2", "unchecked": "the author's name for it"}]}"#))
        XCTAssertEqual(d.annotations.labels[0].tier, .described)
        XCTAssertEqual(claim(d, "l1")?.badge, "Not checked")
    }

    func testA23AbsIsRefusedInAnnotationText() {
        XCTAssertEqual(reason(gears(#"{"labels": [{"id": "l1", "at": "w", "text": "{w.speed|abs} turns"}]}"#)), "text.sign.w.speed")
        XCTAssertEqual(reason(gears(#"{"arrows": [{"id": "a1", "meaning": "pointer", "from": {"world": [0, 0, 60]}, "to": "w", "text": "{w.speed|abs}"}]}"#)), "text.sign.w.speed")
    }

    func testA26EveryNumberScalarIsRefusedByN1() {
        for (k, s) in ["½ turn", "mm²", "Gear \u{FF15}", "Tally \u{1246F}"].enumerated() {
            XCTAssertEqual(reason(gears(#"{"labels": [{"id": "l\#(k)", "at": "p", "text": "\#(s)"}]}"#)), "text.number.label.l\(k)", s)
        }
        XCTAssertEqual(reason(gears(#"{"arrows": [{"id": "a1", "meaning": "flow", "from": {"world": [0, -60, 0]}, "to": {"world": [0, 60, 0]}, "text": "Air ½"}]}"#)),
                       "text.number.arrow.a1")
    }

    // MARK: Arrows

    /// A linear slide (1 mm per input radian along +X) and a turning disc, for arrows on linear chains.
    static let linearParts = #"{"id": "base", "shape": {"box": {"size": [4, 4, 4]}}}, {"id": "s", "at": [10, 0, 0], "shape": {"box": {"size": [4, 4, 4]}}, "joint": {"prismatic": [1, 0, 0]}, "drive": {"input": 1}}, {"id": "disc", "at": [0, 40, 0], "shape": {"shaft": {"radius": 8, "length": 2}}, "joint": {"revolute": [0, 0, 1]}, "drive": {"input": 1}}"#
    func linear(_ annotations: String, steps: String = #"[{"say": "Linear."}]"#) -> String {
        #"{"v": 2, "kind": "assembly", "parts": [\#(Self.linearParts)], "annotations": \#(annotations), "steps": \#(steps)}"#
    }

    func testA2MotionArrowLengthShowsAFact() throws {
        let d = try doc(linear(#"{"arrows": [{"id": "aS", "meaning": "motion", "from": {"part": "s", "point": "centre"}, "length": {"fact": "s.travel", "scale": 2}}]}"#))
        let travel = try XCTUnwrap(d.fact("s.travel"))
        XCTAssertEqual(travel.value, 2 * .pi, accuracy: 1e-9)
        let r = try XCTUnwrap(d.annotations.arrow("aS"))
        XCTAssertEqual(try XCTUnwrap(r.length), 2 * travel.value, accuracy: 1e-9)
        let prims = MGSolidAnnotations.primitives(d, "aS", params: d.defaults)
        XCTAssertEqual((prims[1].end - prims[0].start).length, 2 * travel.value, accuracy: 1e-9)
        XCTAssertEqual(r.tier, travel.tier)
        XCTAssertTrue(r.scaled)
        XCTAssertFalse(d.legend.notes.contains("Arrow lengths are not to scale"), "the only arrow shows a fact length")
        XCTAssertEqual(reason(linear(#"{"arrows": [{"id": "aS", "meaning": "motion", "from": "s", "length": {"fact": "nope.travel", "scale": 2}}]}"#)),
                       "arrow.length.fact.aS")
    }


    func testA3TypedForceArrowIsDescribedAndArrowsAreNotToScale() throws {
        let d = try doc(gears(#"{"arrows": [{"id": "aPush", "meaning": "force", "from": {"world": [0, -40, 0]}, "to": "p", "text": "Push"}]}"#))
        let c = try XCTUnwrap(claim(d, "aPush"))
        XCTAssertEqual(c.tier, .described)
        XCTAssertEqual(c.badge, "Not checked")
        XCTAssertTrue(d.legend.notes.contains("Arrow lengths are not to scale"))
        XCTAssertEqual(d.legend.text, "Solved 2 (animation ratios) · Not checked 1")
        // A pointer makes no claim and needs no note.
        let pointer = try doc(gears(#"{"arrows": [{"id": "aLook", "meaning": "pointer", "from": {"world": [60, 0, 90]}, "to": "w", "text": "Wheel"}]}"#))
        XCTAssertNil(claim(pointer, "aLook"))
        XCTAssertEqual(pointer.legend.notes, [])
    }

    func testA10TurnArrowSenseComesFromTheEngine() throws {
        let d = try doc(gears(#"{"arrows": [{"id": "aw", "meaning": "motion", "style": "turn", "on": "w"}]}"#))
        XCTAssertEqual(d.fact("w.speed")?.value ?? 0, -0.5, accuracy: 1e-12)
        let r = try XCTUnwrap(d.annotations.arrow("aw"))
        XCTAssertEqual(r.turnSign, -1, "clockwise as seen from the +Z tip")
        XCTAssertEqual(r.tier, .solved)
        // The drawn arc turns clockwise about +Z around the wheel centre.
        let prims = MGSolidAnnotations.primitives(d, "aw", params: d.defaults)
        let c = MGVec3(45, 0, prims[0].start.z)
        XCTAssertLessThan((prims[0].start - c).cross(prims[0].end - c).z, 0)
        XCTAssertEqual(prims.count, MGSolidAnnotations.arcChords + 1)
        XCTAssertEqual(try doc(gears(#"{"arrows": [{"id": "aw", "meaning": "motion", "style": "turn", "on": "w", "sense": "cw"}]}"#)).annotations.arrows[0].sense, "cw")
    }

    func testA11WrongStatedSenseIsRefused() {
        XCTAssertEqual(reason(gears(#"{"arrows": [{"id": "aw", "meaning": "motion", "style": "turn", "on": "w", "sense": "ccw"}]}"#)), "arrow.sense.aw")
        XCTAssertEqual(reason(gears(#"{"arrows": [{"id": "aw", "meaning": "motion", "style": "turn", "on": "w", "sense": "left"}]}"#)), "arrow.sense.form.aw")
    }

    func testA12TurnArrowNeedsATurningRevolutePart() {
        let idle = #", {"id": "idle", "at": [0, 80, 0], "shape": {"shaft": {"radius": 5, "length": 5}}, "joint": {"revolute": [0, 0, 1]}}"#
        XCTAssertEqual(reason(gears(#"{"arrows": [{"id": "a1", "meaning": "motion", "style": "turn", "on": "idle"}]}"#, extraParts: idle)), "arrow.still.a1")
        XCTAssertEqual(reason(slider(#"{"arrows": [{"id": "a1", "meaning": "motion", "style": "turn", "on": "piston"}]}"#)), "arrow.turn.joint.a1")
        XCTAssertEqual(reason(slider(#"{"arrows": [{"id": "a1", "meaning": "motion", "style": "turn", "on": "frame"}]}"#)), "arrow.turn.joint.a1")
        // A crank rod swings back and forth: its chain is not linear.
        XCTAssertEqual(reason(slider(#"{"arrows": [{"id": "a1", "meaning": "motion", "style": "turn", "on": "rod"}]}"#)), "annotation.motion.nonlinear.a1")
        XCTAssertNoThrow(try doc(slider(#"{"arrows": [{"id": "a1", "meaning": "motion", "style": "turn", "on": "crank"}]}"#)))
    }


    /// A13 under the linear-motion rule (third review): a crank-slider chain is refused, also at a dead centre; a linear
    /// chain gives the exact velocity at every pose.
    func testA13MotionArrowsNeedALinearChain() throws {
        XCTAssertEqual(reason(slider(#"{"arrows": [{"id": "aRod", "meaning": "motion", "from": {"part": "piston", "point": "centre"}}]}"#)),
                       "annotation.motion.nonlinear.aRod")
        let d = try doc(linear(#"{"arrows": [{"id": "aS", "meaning": "motion", "from": "s"}, {"id": "aD", "meaning": "motion", "from": {"part": "disc", "offset": [8, 0, 0]}}]}"#))
        XCTAssertEqual(d.annotations.arrow("aS")?.direction?.x ?? 0, 1, accuracy: 1e-12)
        XCTAssertEqual(d.annotations.arrow("aD")?.direction?.y ?? 0, 1, accuracy: 1e-12, "a rim point at +X on a disc turning about +Z moves +Y")
        for u in [0.0, 1, 2.5, 5] {
            let prims = MGSolidAnnotations.primitives(d, "aS", params: MGPoseParameters(input: u))
            XCTAssertEqual((prims[1].end - prims[0].start).normalized.x, 1, accuracy: 1e-12)
        }
    }


    func testA14StatedDirectionIsChecked() {
        XCTAssertEqual(reason(linear(#"{"arrows": [{"id": "aS", "meaning": "motion", "from": "s", "expect": [-1, 0, 0]}]}"#)), "arrow.expect.aS")
        XCTAssertNil(reason(linear(#"{"arrows": [{"id": "aS", "meaning": "motion", "from": "s", "expect": [1, 0.2, 0]}]}"#)))
        XCTAssertEqual(reason(linear(#"{"arrows": [{"id": "aS", "meaning": "motion", "from": {"world": [0, 0, 0]}}]}"#)), "arrow.from.aS")
        XCTAssertEqual(reason(linear(#"{"arrows": [{"id": "aS", "meaning": "motion", "from": "base"}]}"#)), "arrow.still.aS")
    }


    func testA15GravityForceIsCheckedAgainstMinusZ() throws {
        let up = #"{"arrows": [{"id": "aG", "meaning": "force", "cause": "gravity", "from": "p", "to": {"part": "p", "offset": [0, 0, 30]}}]}"#
        XCTAssertEqual(reason(gears(up)), "arrow.gravity.aG")
        let down = try doc(gears(#"{"arrows": [{"id": "aG", "meaning": "force", "cause": "gravity", "from": "p", "to": {"part": "p", "offset": [0, 0, -30]}, "text": "Weight"}]}"#))
        XCTAssertEqual(claim(down, "aG")?.tier, .solved)
        XCTAssertEqual(reason(gears(#"{"arrows": [{"id": "aG", "meaning": "force", "cause": "wind", "from": "p", "to": "w"}]}"#)), "arrow.cause.aG")
        XCTAssertEqual(reason(gears(#"{"arrows": [{"id": "aG", "meaning": "force", "from": "p", "to": {"part": "p", "offset": [0, 0, 0.1]}}]}"#)), "arrow.length.aG")
    }

    func testArrowKeysFollowTheMeaning() {
        XCTAssertEqual(reason(gears(#"{"arrows": [{"id": "a1", "meaning": "flow", "from": "p", "to": "w", "cause": "gravity"}]}"#)), "arrow.key.cause.a1")
        XCTAssertEqual(reason(gears(#"{"arrows": [{"id": "a1", "meaning": "motion", "style": "turn", "on": "w", "from": "p"}]}"#)), "arrow.key.from.a1")
        XCTAssertEqual(reason(gears(#"{"arrows": [{"id": "a1", "meaning": "force", "from": "p"}]}"#)), "arrow.missing.to")
        XCTAssertEqual(reason(gears(#"{"arrows": [{"id": "a1", "meaning": "push", "from": "p", "to": "w"}]}"#)), "arrow.meaning.a1")
        XCTAssertEqual(reason(gears(#"{"arrows": [{"id": "a1", "meaning": "motion", "style": "spiral", "on": "w"}]}"#)), "arrow.style.a1")
        XCTAssertEqual(reason(gears(#"{"arrows": [{"id": "a1", "meaning": "flow", "from": "p", "to": "w", "unchecked": "why"}]}"#)), "arrow.unchecked.text.a1")
        XCTAssertEqual(reason(gears(#"{"arrows": [{"id": "a1", "meaning": "flow", "from": "p", "to": "w", "text": "Air", "unchecked": ""}]}"#)), "arrow.unchecked.a1")
        XCTAssertEqual(reason(gears(#"{"arrows": [{"meaning": "flow", "from": "p", "to": "w"}]}"#)), "arrow.missing.id")
        XCTAssertEqual(reason(gears(#"{"arrows": [{"id": "a1", "meaning": "flow", "from": "p", "to": "w", "size": 3}]}"#)), "arrow.unknown.size")
    }

    // MARK: Dimensions

    /// A slide moving along X with the input (1 mm per input radian), 10 mm from a fixed base at input 0.
    func slide(_ dimension: String, input: Double = 0.5) -> String {
        #"{"v": 2, "kind": "assembly", "params": {"input": \#(input)}, "parts": [{"id": "base", "shape": {"box": {"size": [4, 4, 4]}}}, {"id": "s", "at": [10, 0, 0], "shape": {"box": {"size": [4, 4, 4]}}, "joint": {"prismatic": [1, 0, 0]}, "drive": {"input": 1}}], "annotations": {"dimensions": [\#(dimension)]}, "steps": [{"say": "The gap is {dim.gap}."}]}"#
    }

    func testA5DimensionAtTheDefaultInputAndOverOneTurn() throws {
        let plain = try doc(slide(#"{"id": "gap", "a": "base", "b": "s"}"#))
        XCTAssertEqual(plain.fact("dim.gap")?.value ?? 0, 10.5, accuracy: 1e-9)
        XCTAssertEqual(plain.fact("dim.gap")?.unit, "mm")
        XCTAssertEqual(plain.fact("dim.gap")?.source, "dimension")
        XCTAssertEqual(plain.steps[0].say, "The gap is 10.5 mm.")
        let over = try doc(slide(#"{"id": "gap", "a": "base", "b": "s", "over": "input"}"#))
        // Outside reference: the slide moves 1 mm per input radian, so one turn covers 2π mm.
        XCTAssertEqual(over.fact("dim.gap")?.value ?? 0, 2 * .pi, accuracy: 1e-9)
        var lo = Double.infinity, hi = -Double.infinity
        for k in 0...720 {
            let w = over.assembly.pose(MGPoseParameters(input: 2 * .pi * Double(k) / 720)).world
            let g = (w["s"]!.translation - w["base"]!.translation).length
            lo = min(lo, g); hi = max(hi, g)
        }
        XCTAssertEqual(over.fact("dim.gap")?.value ?? 0, hi - lo, accuracy: 1e-12)
        XCTAssertEqual(over.fact("dim.gap")?.tier, .solved)
        XCTAssertEqual(reason(slide(#"{"id": "gap", "a": "base", "b": {"world": [50, 0, 0]}, "over": "input"}"#)), "dimension.over.gap")
        XCTAssertEqual(reason(slide(#"{"id": "gap", "a": "base", "b": "s", "over": "time"}"#)), "dimension.over.form.gap")
    }

    func testA6StrokeOfTheSliderCrankIsMeasured() throws {
        let d = try doc(slider(#"{"dimensions": [{"id": "stroke", "a": {"part": "piston", "point": "centre"}, "b": {"world": [0, 0, 0]}, "along": "x", "over": "input"}]}"#,
                               steps: #"[{"say": "Its stroke is {dim.stroke}."}]"#))
        XCTAssertEqual(d.steps[0].say, "Its stroke is 36 mm.")
        XCTAssertEqual(d.steps[0].tier, .solved)
        XCTAssertEqual(d.fact("dim.stroke")?.value ?? 0, 36, accuracy: 1e-6)
        XCTAssertEqual(d.annotations.dimensions[0].text, "36 mm")
        XCTAssertEqual(claim(d, "stroke")?.tier, .solved)
    }

    func testA7RightAngle() throws {
        let text = #"{"v": 2, "kind": "assembly", "parts": [{"id": "pivot", "shape": {"shaft": {"radius": 4, "length": 4}}}, {"id": "arm", "rot": [0, 0, 1, 90], "shape": {"box": {"size": [80, 6, 4], "at": [40, 0, 0]}}}], "annotations": {"dimensions": [{"id": "tilt", "kind": "angle", "a": {"world": [100, 0, 0]}, "vertex": "pivot", "b": {"part": "arm", "offset": [80, 0, 0]}}]}, "steps": [{"say": "A right angle: {dim.tilt}."}]}"#
        let d = try doc(text)
        XCTAssertEqual(d.fact("dim.tilt")?.value ?? 0, 90, accuracy: 1e-9)
        XCTAssertEqual(d.fact("dim.tilt")?.unit, "°")
        XCTAssertEqual(d.annotations.dimensions[0].text, "90°")
        XCTAssertEqual(d.steps[0].say, "A right angle: 90°.")
        XCTAssertEqual(MGSolidAnnotations.primitives(d, "tilt", params: d.defaults).count, MGSolidAnnotations.arcChords + 2)
        XCTAssertEqual(reason(text.replacingOccurrences(of: #""vertex": "pivot", "#, with: "")), "dimension.vertex.tilt")
        XCTAssertEqual(reason(text.replacingOccurrences(of: #""kind": "angle", "#, with: "")), "dimension.vertex.tilt")
        XCTAssertEqual(reason(text.replacingOccurrences(of: #""kind": "angle""#, with: #""kind": "arc""#)), "dimension.kind.tilt")
        XCTAssertEqual(reason(text.replacingOccurrences(of: #""kind": "angle""#, with: #""kind": "angle", "along": "x""#)), "dimension.along.tilt")
    }

    func testA8CoincidentAnchorsAreRefused() {
        XCTAssertEqual(reason(gears(#"{"dimensions": [{"id": "gap", "a": "p", "b": "p"}]}"#)), "dimension.zero.gap")
        XCTAssertEqual(reason(gears(#"{"dimensions": [{"id": "tilt", "kind": "angle", "a": "p", "vertex": "p", "b": "w"}]}"#)), "dimension.zero.tilt")
    }

    func testA9DimensionTextMustShowItsOwnFact() throws {
        XCTAssertEqual(reason(gears(#"{"dimensions": [{"id": "gap", "a": "p", "b": "w", "text": "Centre distance"}]}"#)), "dimension.text.gap")
        XCTAssertEqual(reason(gears(#"{"dimensions": [{"id": "gap", "a": "p", "b": "w", "text": "Gap {dim.gap} 2"}]}"#)), "text.number.dimension.gap")
        let d = try doc(gears(#"{"dimensions": [{"id": "gap", "a": "p", "b": "w"}]}"#, steps: #"[{"say": "The centres are {dim.gap} apart."}]"#))
        XCTAssertEqual(d.annotations.dimensions[0].text, "45 mm")
        XCTAssertEqual(d.steps[0].say, "The centres are 45 mm apart.")
        // A fact name `dim.<id>` that already exists (a part named `dim`) is refused instead of shadowed.
        let dimPart = #", {"id": "dim", "at": [0, 90, 0], "shape": {"gear": {"teeth": 15, "module": 2, "width": 8}}}"#
        XCTAssertEqual(reason(gears(#"{"dimensions": [{"id": "teeth", "a": "p", "b": "w"}]}"#, extraParts: dimPart)), "dimension.fact.teeth")
    }

    // MARK: Anchors, limits, visibility

    func testA16AnchorsMustNameOnePart() {
        XCTAssertEqual(reason(stage(#"{"labels": [{"id": "l1", "at": "stage.planet", "text": "Planets"}]}"#)), "anchor.ambiguous.stage.planet")
        XCTAssertEqual(reason(stage(#"{"labels": [{"id": "l1", "at": "stage", "text": "Stage"}]}"#)), "anchor.ambiguous.stage")
        XCTAssertEqual(reason(stage(#"{"labels": [{"id": "l1", "at": "nope", "text": "Nothing"}]}"#)), "anchor.ref.nope")
        XCTAssertNil(reason(stage(#"{"labels": [{"id": "l1", "at": "stage.planet2", "text": "One planet"}]}"#)))
        // `{"part": "p"}` alone is the part's centre (it was `anchor.form` before the back-preset release).
        XCTAssertNil(reason(gears(#"{"labels": [{"id": "l1", "at": {"part": "p"}, "text": "P"}]}"#)))
        XCTAssertEqual(reason(gears(#"{"labels": [{"id": "l1", "at": {"part": "p", "point": "centre", "offset": [0, 0, 1]}, "text": "P"}]}"#)), "anchor.form")
        XCTAssertEqual(reason(gears(#"{"labels": [{"id": "l1", "at": {"part": "p", "offset": [0, 0, 5000]}, "text": "P"}]}"#)), "anchor.offset")
        XCTAssertEqual(reason(gears(#"{"labels": [{"id": "l1", "at": {"part": "p", "point": "middle"}, "text": "P"}]}"#)), "anchor.point")
        XCTAssertEqual(reason(gears(#"{"labels": [{"id": "l1", "at": {"world": [0, 0]}, "text": "P"}]}"#)), "anchor.world")
        // Annotation ids join the document's one namespace.
        XCTAssertEqual(reason(gears(#"{"labels": [{"id": "w", "at": "p", "text": "P"}]}"#)), "id.duplicate.w")
        XCTAssertEqual(reason(gears(#"{"labels": [{"id": "x", "at": "p", "text": "P"}], "arrows": [{"id": "x", "meaning": "pointer", "from": "p", "to": "w"}]}"#)), "id.duplicate.x")
        XCTAssertEqual(reason(stage(#"{"labels": [{"id": "stage", "at": "stage.sun", "text": "Sun"}]}"#)), "id.duplicate.stage")
        XCTAssertEqual(reason(gears(#"{"labels": [{"id": "bad id", "at": "p", "text": "P"}]}"#)), "label.id")
    }

    func testA17AnnotationsNeedVersionTwo() {
        XCTAssertEqual(reason(gears(#"{"labels": []}"#, v: 1)), "assembly.unknown.annotations")
        let v1 = #"{"v": 1, "kind": "assembly", "parts": [\#(Self.pair)], "constraints": [{"gearMesh": {"a": "p", "b": "w"}}], "steps": [{"say": "Gears.", "annotate": []}]}"#
        XCTAssertEqual(reason(v1), "step.unknown.annotate")
    }

    func testA4CountLimits() {
        func labels(_ n: Int) -> String { (0..<n).map { #"{"id": "l\#($0)", "at": "p", "text": "Label"}"# }.joined(separator: ",") }
        func arrows(_ n: Int) -> String { (0..<n).map { #"{"id": "a\#($0)", "meaning": "pointer", "from": "p", "to": "w"}"# }.joined(separator: ",") }
        func dims(_ n: Int) -> String { (0..<n).map { #"{"id": "d\#($0)", "a": "p", "b": "w"}"# }.joined(separator: ",") }
        let steps = #"[{"say": "Shown.", "annotate": []}]"#
        XCTAssertEqual(reason(gears(#"{"labels": [\#(labels(33))]}"#, steps: steps)), "labels.count")
        XCTAssertEqual(reason(gears(#"{"arrows": [\#(arrows(33))]}"#, steps: steps)), "arrows.count")
        XCTAssertEqual(reason(gears(#"{"dimensions": [\#(dims(17))]}"#, steps: steps)), "dimensions.count")
        // At the limits the document is accepted (each annotation unused: a warning).
        XCTAssertNil(reason(gears(#"{"labels": [\#(labels(32))], "arrows": [\#(arrows(32))], "dimensions": [\#(dims(16))]}"#, steps: steps)))
        XCTAssertEqual(reason(gears(#"{"labels": {}}"#)), "labels.count")
        XCTAssertEqual(reason(gears(#"{"notes": []}"#)), "annotations.unknown.notes")
        XCTAssertEqual(reason(gears(#"[]"#)), "annotations.object")
    }

    func testA18AllVisibleNeedsTwelveOrFewer() {
        let thirteen = (0..<13).map { #"{"id": "l\#($0)", "at": "p", "text": "Label"}"# }.joined(separator: ",")
        XCTAssertEqual(reason(gears(#"{"labels": [\#(thirteen)]}"#)), "annotations.visible")
        let twelve = (0..<12).map { #"{"id": "l\#($0)", "at": "p", "text": "Label"}"# }.joined(separator: ",")
        XCTAssertNil(reason(gears(#"{"labels": [\#(twelve)]}"#)))
    }

    func testA19AStepShowsAtMostTwelve() throws {
        let labels = (0..<13).map { #"{"id": "l\#($0)", "at": "p", "text": "Label"}"# }.joined(separator: ",")
        let ids = (0..<13).map { #""l\#($0)""# }
        XCTAssertEqual(reason(gears(#"{"labels": [\#(labels)]}"#, steps: #"[{"say": "Many.", "annotate": [\#(ids.joined(separator: ","))]}]"#)),
                       "step.annotate.count")
        XCTAssertEqual(reason(gears(#"{"labels": [\#(labels)]}"#, steps: #"[{"say": "One.", "annotate": ["nope"]}]"#)), "step.annotate.ref.nope")
        XCTAssertEqual(reason(gears(#"{"labels": [\#(labels)]}"#, steps: #"[{"say": "One.", "annotate": "l1"}]"#)), "step.annotate")
        // Twelve of thirteen in one step, the last in another: accepted; the plain view shows none.
        let d = try doc(gears(#"{"labels": [\#(labels)]}"#, steps: #"[{"say": "Many.", "annotate": [\#(ids.prefix(12).joined(separator: ","))]}, {"say": "Last.", "annotate": ["l12"]}]"#))
        XCTAssertEqual(d.view(step: 0).annotations.count, 12)
        XCTAssertEqual(d.view(step: 1).annotations, ["l12"])
        XCTAssertEqual(d.view(step: nil).annotations, [])
        XCTAssertEqual(d.warnings, [])
    }

    func testA20UnusedAnnotationWarnsAndStrictRefuses() throws {
        let text = gears(#"{"labels": [{"id": "lp", "at": "p", "text": "Pinion"}, {"id": "lx", "at": "w", "text": "Wheel"}]}"#,
                         steps: #"[{"say": "The pinion.", "annotate": ["lp"]}, {"say": "Nothing labelled."}]"#)
        let d = try doc(text)
        XCTAssertEqual(d.warnings.map(\.reason), ["annotation.unused.lx"])
        XCTAssertEqual(d.view(step: 1).annotations, [], "a step without annotate shows none")
        XCTAssertEqual(reason(text, profile: .strict), "annotation.unused.lx")
    }

    func testA21AnchorInTheRemovedHalfWarnsButIsAccepted() throws {
        let text = #"{"v": 2, "kind": "assembly", "parts": [{"id": "casing", "shape": {"box": {"size": [20, 20, 20]}}}], "annotations": {"labels": [{"id": "lab", "at": {"part": "casing", "offset": [0, -5, 0]}, "text": "Front wall"}]}, "steps": [{"say": "Cut.", "section": {"normal": [0, -1, 0], "parts": ["casing"]}, "annotate": ["lab"]}]}"#
        let d = try doc(text)
        XCTAssertEqual(d.warnings.map(\.reason), ["annotation.cut.lab"])
        XCTAssertNil(reason(text, profile: .strict))
        // In the kept half: no warning.
        XCTAssertEqual(try doc(text.replacingOccurrences(of: "[0, -5, 0]", with: "[0, 5, 0]")).warnings, [])
    }

    func testA24ArrowsJoinTheMeshBudgetBeforeAnyMeshIsBuilt() throws {
        // Parts whose exact estimate sits just under the limit, with less room left than one turn arrow needs: closed
        // revolves of 256 points (copied with `repeat`), then one revolve sized to land in that window.
        func revolve(_ n: Int) -> String {
            let pts = (0..<n).map { k -> String in
                let t = 2 * Double.pi * Double(k) / Double(n)
                return "[" + String(format: "%.2f", 50 + 10 * cos(t)) + ", " + String(format: "%.2f", 10 * sin(t)) + "]"
            }
            return #"{"revolvedProfile": {"points": [\#(pts.joined(separator: ", "))], "closed": true}}"#
        }
        func estimate(_ n: Int) throws -> Int {
            try MGSolidParser.shape(try XCTUnwrap(MGJSON(any: try JSONSerialization.jsonObject(with: Data(revolve(n).utf8))))).meshEstimate.triangles
        }
        let arrow = MGSolidAnnotations.counts((MGSolidAnnotations.arcChords, 1)).triangles
        XCTAssertEqual(arrow, MGSolidAnnotations.arcChords * 32 + 16)
        let big = try estimate(256), perPoint = try estimate(4) - (try estimate(3))
        let target = MGSolidLimits.triangles - arrow / 2
        var bigs = target / big
        var parts: [String] = []
        while bigs > 0 {
            let k = parts.count
            if bigs >= 12 {
                let shapes = min(8, bigs / 12)
                parts.append(#"{"id": "r\#(k)", "shape": [\#(Array(repeating: revolve(256), count: shapes).joined(separator: ","))], "repeat": {"count": 12}}"#)
                bigs -= 12 * shapes
            } else if bigs >= 2 {
                parts.append(#"{"id": "r\#(k)", "shape": \#(revolve(256)), "repeat": {"count": \#(bigs)}}"#)
                bigs = 0
            } else {
                parts.append(#"{"id": "r\#(k)", "shape": \#(revolve(256))}"#)
                bigs = 0
            }
        }
        let used = (target / big) * big
        let points = 3 + (target - used - (try estimate(3))) / perPoint
        let total = used + (try estimate(points))
        XCTAssertGreaterThan(total, MGSolidLimits.triangles - arrow)
        XCTAssertLessThanOrEqual(total, MGSolidLimits.triangles)
        parts.append(#"{"id": "fill", "shape": \#(revolve(points))}"#)
        let arrowJSON = #"{"arrows": [{"id": "aw", "meaning": "motion", "style": "turn", "on": "fill"}]}"#
        let text = #"{"v": 2, "kind": "assembly", "parts": [\#(parts.joined(separator: ","))], "annotations": \#(arrowJSON), "steps": [{"say": "Big."}]}"#
        XCTAssertLessThan(text.utf8.count, MGSolidLimits.bytes)
        let t0 = Date()
        XCTAssertEqual(reason(text), "assembly.budget")
        XCTAssertLessThan(Date().timeIntervalSince(t0), 5, "refused from the estimate, before any mesh is built")
    }

    func testA25HostileInputIsBoundedAndNeverTraps() throws {
        // Built in code: NaN offsets, huge strings and a million entries are refused by the size check.
        let nan: MGJSON = .object(["v": .number(2), "kind": .string("assembly"),
                                   "parts": .array([.object(["id": .string("p"), "shape": .object(["box": .object(["size": .array([.number(4), .number(4), .number(4)])])])])]),
                                   "annotations": .object(["labels": .array([.object(["id": .string("l"), "text": .string("L"),
                                                                                      "at": .object(["part": .string("p"), "offset": .array([.number(.nan), .number(0), .number(0)])])])])])])
        XCTAssertEqual(MGSolidParser.document(json: nan).failureReason, "assembly.bytes")
        let huge: MGJSON = .object(["v": .number(2), "kind": .string("assembly"), "parts": .array([]),
                                    "annotations": .object(["labels": .array([.object(["id": .string("l"), "at": .string("p"), "text": .string(String(repeating: "x", count: 1 << 20))])])])])
        XCTAssertEqual(MGSolidParser.document(json: huge).failureReason, "assembly.bytes")
        let many: MGJSON = .object(["v": .number(2), "kind": .string("assembly"), "parts": .array([]),
                                    "annotations": .object(["arrows": .array(Array(repeating: .object(["id": .string("a")]), count: 1_000_000))])])
        XCTAssertEqual(MGSolidParser.document(json: many).failureReason, "assembly.bytes")
        // Under the size limit, a long text is refused by its own reason.
        XCTAssertEqual(reason(gears(#"{"labels": [{"id": "l1", "at": "p", "text": "\#(String(repeating: "x", count: 61))"}]}"#)), "label.text.l1")
        XCTAssertEqual(reason(gears(#"{"labels": [{"id": "l1", "at": "p", "text": "<b>x</b>"}]}"#)), "label.text.l1")
        XCTAssertEqual(reason(gears(#"{"labels": [{"id": "l1", "at": "p", "text": "P", "unchecked": ""}]}"#)), "label.unchecked.l1")
        // Public layout and drawing types never trap on hostile numbers.
        let item = MGAnnotationLayout.Item(id: "x", kind: .label, text: "X", attach: MGVec2(.nan, .infinity), line: MGVec2(.nan, 1), dot: true, occluded: nil)
        XCTAssertNil(MGAnnotationLayout.place(.init(items: Array(repeating: item, count: 1_000_000), width: 100, height: 100)))
        XCTAssertNil(MGAnnotationLayout.place(.init(items: [item], width: .nan, height: 100)))
        XCTAssertNil(MGAnnotationLayout.place(.init(items: [item], width: 1e300, height: 100)))
        let off = try XCTUnwrap(MGAnnotationLayout.place(.init(items: [item], width: 100, height: 100, centre: MGVec2(.nan, .nan))))
        XCTAssertEqual(off[0].callout, 0)
        XCTAssertTrue(off[0].offView)
        XCTAssertNil(MGAnnotationProjection(camera: MGSolidCamera(target: MGVec3(.nan, 0, 0), yaw: .nan, pitch: 0, distance: 1), width: 10, height: 10).project(.zero))
        XCTAssertEqual(MGAnnotationPrimitive(shape: .cone, start: MGVec3(.nan, 0, 0), end: .zero, radius: .infinity, hidden: false).renderMesh.indices.count,
                       3 * MGSolidAnnotations.coneCounts.triangles)
        XCTAssertGreaterThanOrEqual(MGSolidOverlay.fit(String(repeating: "W", count: 10_000), width: .nan, fontSize: .infinity).size, MGSolidOverlay.minimumFont)
    }

    // MARK: Poses (review of PR #31: B1, S1, S2, S3)

    func winch() throws -> String {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Examples/Solid3D/Sources/MartySolid3D/Models/annotated-winch.json")
        return String(decoding: try Data(contentsOf: url), as: UTF8.self)
    }
    /// The winch with its steps replaced and extra annotations.
    func winch(steps: String, arrows: String = "", dimensions: String = "") throws -> String {
        var t = try winch()
        let s0 = try XCTUnwrap(t.range(of: #""steps": ["#)), end = try XCTUnwrap(t.range(of: "]}", options: .backwards))
        t.replaceSubrange(s0.lowerBound..<end.upperBound, with: #""steps": \#(steps)}"#)
        if !arrows.isEmpty { t = t.replacingOccurrences(of: #""arrows": ["#, with: #""arrows": [\#(arrows), "#) }
        if !dimensions.isEmpty { t = t.replacingOccurrences(of: #""dimensions": ["#, with: #""dimensions": [\#(dimensions), "#) }
        return t
    }
    let allShown = #""annotate": ["lPinion", "lWheel", "aPinion", "aWheel", "aWeight", "aLift", "centres"]"#

    /// B1: a claim checked at the default pose must also hold over every pose a step that shows it plays.
    func testClaimsMustHoldOverTheStepSpinRange() throws {
        // The rope-side arrow rides the drum: with a spin it leaves the rope side and stops pointing up.
        XCTAssertEqual(reason(try winch(steps: #"[{"say": "Wind.", "spin": 1, \#(allShown)}]"#)), "annotation.pose.aLift")
        XCTAssertEqual(reason(try winch(steps: #"[{"say": "Wind.", "spin": 1.5, \#(allShown)}]"#)), "annotation.pose.aLift")
        // The same step without the spin, or without the arrow, holds.
        XCTAssertNil(reason(try winch(steps: #"[{"say": "Still.", \#(allShown)}]"#)))
        let noLift = #""annotate": ["lPinion", "lWheel", "aPinion", "aWheel", "aWeight", "centres"]"#
        XCTAssertNil(reason(try winch(steps: #"[{"say": "Wind.", "spin": 3, \#(noLift)}, {"say": "Rope.", "annotate": ["aLift"]}]"#)))
        // A gravity arrow on the turning drum.
        let drumG = #"{"id": "aDrumG", "meaning": "force", "cause": "gravity", "from": {"part": "wheel", "offset": [20, 0, -23]}, "to": {"part": "wheel", "offset": [20, 30, -23]}}"#
        XCTAssertNil(reason(try winch(steps: #"[{"say": "Still.", "annotate": ["aDrumG"]}, {"say": "Rest.", \#(allShown)}]"#, arrows: drumG)))
        XCTAssertEqual(reason(try winch(steps: #"[{"say": "Wind.", "spin": 1, "annotate": ["aDrumG"]}, {"say": "Rest.", \#(allShown)}]"#, arrows: drumG)),
                       "annotation.pose.aDrumG")
        // A dimension to a point off the drum axis changes as the drum turns; one on the axes does not.
        let gap = #"{"id": "gap", "a": {"part": "pinion", "offset": [0, 0, -46]}, "b": {"part": "wheel", "offset": [16, 0, -46]}, "text": "Gap {dim.gap}"}"#
        XCTAssertEqual(reason(try winch(steps: #"[{"say": "Wind.", "spin": 1, "annotate": ["gap", "centres"]}, {"say": "Rest.", \#(allShown)}]"#, dimensions: gap)),
                       "annotation.pose.gap")
        XCTAssertNil(reason(try winch(steps: #"[{"say": "Wind.", "spin": 1, "annotate": ["centres", "aWheel", "aPinion", "lWheel"]}, {"say": "Rest.", \#(allShown)}]"#)))
    }

    /// B1 (probe p7): an exploded step moves dimension anchors apart.
    func testExplodedStepMustKeepItsDimension() throws {
        var t = try winch(steps: #"[{"say": "Apart.", "explode": 1, "annotate": ["centres"]}, {"say": "Rest.", \#(allShown)}]"#)
        t = t.replacingOccurrences(of: #""expect": {"axisWorld": [0, 1, 0]}},"#, with: #""expect": {"axisWorld": [0, 1, 0]}, "explode": [40, 0, 0]},"#)
        XCTAssertEqual(t.components(separatedBy: #""explode": [40, 0, 0]"#).count, 3, "both gears explode")
        // Only the drum explodes: the centres move apart.
        let one = t.replacingOccurrences(of: #""joint": {"revolute": [0, 0, 1]}, "drive": {"input": 1}, "expect": {"axisWorld": [0, 1, 0]}, "explode": [40, 0, 0]}"#,
                                         with: #""joint": {"revolute": [0, 0, 1]}, "drive": {"input": 1}, "expect": {"axisWorld": [0, 1, 0]}}"#)
        XCTAssertEqual(reason(one), "annotation.pose.centres")
        // Both explode together: the distance holds.
        XCTAssertNil(reason(t))
    }

    /// S1: a negative spin plays backwards; arrows draw the shown motion and a stated sense must match it.
    func testNegativeSpinReversesTheShownMotion() throws {
        XCTAssertEqual(reason(try winch(steps: #"[{"say": "Back.", "spin": -1, "annotate": ["aPinion"]}, {"say": "Rest.", \#(allShown)}]"#)),
                       "annotation.pose.aPinion")
        let text = gears(#"{"arrows": [{"id": "aw", "meaning": "motion", "style": "turn", "on": "w"}]}"#, steps: #"[{"say": "Back.", "spin": -1}]"#)
        let d = try doc(text)
        let view = d.view(step: 0)
        XCTAssertEqual(view.motionSense, -1)
        XCTAssertEqual(d.checkedAnnotations(view, params: MGPoseParameters(input: -1)), ["aw"], "inside the backwards spin range")
        XCTAssertNil(d.checkedAnnotations(view, params: MGPoseParameters(input: 1)), "outside it")
        let prims = MGSolidAnnotations.primitives(d, "aw", params: d.defaults, sense: view.motionSense)
        let c = MGVec3(45, 0, prims[0].start.z)
        XCTAssertGreaterThan((prims[0].start - c).cross(prims[0].end - c).z, 0, "played backwards, the wheel turns counter-clockwise")
        let snap = MGSolidSnapshot.make(d, step: 0, params: d.defaults)
        XCTAssertGreaterThan(snap.annotations?.arrows.first?.direction[1] ?? 0, 0, "turns counter-clockwise about kernel +Z (world +Y)")
        // A line arrow played backwards points the other way.
        let s = try doc(linear(#"{"arrows": [{"id": "aS", "meaning": "motion", "from": "s"}]}"#, steps: #"[{"say": "Back.", "spin": -1}]"#))
        let back = MGSolidAnnotations.primitives(s, "aS", params: MGPoseParameters(input: -1), sense: -1)
        XCTAssertEqual((back[1].end - back[0].start).normalized.x, -1, accuracy: 1e-12)
    }

    /// S2: one meaning per reason for `over` dimensions that do not change; `over` needs a motion with an exact range.
    func testOverRangesAreExactOrRefused() {
        XCTAssertEqual(reason(slide(#"{"id": "gap", "a": "base", "b": "s", "along": "y", "over": "input"}"#)), "dimension.over.still.gap")
        let turning = #"{"dimensions": [{"id": "same", "a": {"part": "w", "offset": [10, 0, 0]}, "b": {"world": [0, 0, 0]}, "over": "input"}]}"#
        XCTAssertEqual(reason(gears(turning)), "dimension.over.motion.same")
        let angle = #"{"dimensions": [{"id": "ang", "kind": "angle", "a": {"part": "w", "offset": [10, 0, 0]}, "vertex": "w", "b": {"part": "w", "offset": [0, 10, 0]}, "over": "input"}]}"#
        XCTAssertEqual(reason(gears(angle)), "dimension.over.motion.ang")
    }

    /// Review 2, R1: text that shows a `dim.<id>` fact must hold in its view, even when the dimension is hidden.
    func testTextThatShowsAMovingDimensionIsRefused() throws {
        func doc(_ text: String, _ steps: String, extra: String = "") -> String {
            #"{"v": 2, "kind": "assembly", "params": {"input": 0}, "parts": [{"id": "p", "shape": {"shaft": {"radius": 1, "length": 2}}, "joint": {"revolute": [0, 0, 1]}, "drive": {"input": 1}}\#(extra)], "annotations": {"dimensions": [{"id": "gap", "a": {"world": [10, 0, 0]}, "b": {"part": "p", "offset": [20, 0, 0]}, "text": "Gap {dim.gap}"}], \#(text)}, "steps": \#(steps)}"#
        }
        let label = #""labels": [{"id": "l", "at": "p", "text": "Gap {dim.gap}"}]"#
        let pointer = #""arrows": [{"id": "ptr", "meaning": "pointer", "from": {"world": [0, 0, 30]}, "to": "p", "text": "Gap {dim.gap}"}]"#
        XCTAssertEqual(reason(doc(label, #"[{"say": "Turn.", "spin": 0.5, "annotate": ["l"]}, {"say": "Measure.", "annotate": ["gap"]}]"#)), "annotation.pose.l")
        XCTAssertEqual(reason(doc(pointer, #"[{"say": "Turn.", "spin": 0.5, "annotate": ["ptr"]}, {"say": "Measure.", "annotate": ["gap"]}]"#)), "annotation.pose.ptr")
        XCTAssertEqual(reason(doc(label, #"[{"say": "Apart.", "explode": 1, "annotate": ["l"]}, {"say": "Measure.", "annotate": ["gap"]}]"#,
                                  extra: #", {"id": "q", "shape": {"box": {"size": [2, 2, 2]}}}"#).replacingOccurrences(of: #""drive": {"input": 1}}"#, with: #""drive": {"input": 1}, "explode": [0, 0, 30]}"#)),
                       "annotation.pose.l")
        XCTAssertEqual(reason(doc(label, #"[{"say": "Gap {dim.gap} turns.", "spin": 0.5, "annotate": []}, {"say": "Measure.", "annotate": ["gap", "l"]}]"#)),
                       "text.pose.step.1")
        // Still steps keep the claim.
        XCTAssertNil(reason(doc(label, #"[{"say": "Still.", "annotate": ["l"]}, {"say": "Measure.", "annotate": ["gap"]}]"#)))
        // Patch a still document into a turning step: refused; the document stays.
        let base = try self.doc(doc(label, #"[{"say": "Still.", "annotate": ["l"]}, {"say": "Measure.", "annotate": ["gap"]}]"#))
        let before = base
        let patch = try XCTUnwrap(MGJSON(any: ["steps": [["say": "Turn.", "spin": 0.5, "annotate": ["l"]], ["say": "Measure.", "annotate": ["gap"]]]] as [String: Any]))
        XCTAssertEqual(MGSolidParser.applying(patch, to: base).failureReason, "annotation.pose.l")
        XCTAssertEqual(base, before)
        // A patch that moves the anchor recomputes the value everywhere it shows (no stale text).
        let move = try XCTUnwrap(MGJSON(any: ["parts": ["p": ["at": [5, 0, 0]]]] as [String: Any]))
        guard case .success(let moved) = MGSolidParser.applying(move, to: base) else { return XCTFail("move") }
        XCTAssertEqual(moved.annotations.label("l")?.text, "Gap 15 mm")
        XCTAssertEqual(moved.annotations.dimension("gap")?.text, "Gap 15 mm")
        XCTAssertEqual(moved.describe("gap")?["value"], .number(15))
        guard case .array(let entries)? = MGSolidReport.make(moved).json["annotations"] else { return XCTFail("report") }
        XCTAssertEqual(entries.first { $0["id"] == .string("l") }?["text"], .string("Gap 15 mm"))
    }

    /// Review 2, R2: aliasing at high rates cannot pass any more: the rules are structural.
    func testHighRatesCannotHideMotion() {
        func one(_ annotations: String, rate: Int = 720, axis: String = "[0, 0, 1]") -> String {
            #"{"v": 2, "kind": "assembly", "parts": [{"id": "p", "shape": {"shaft": {"radius": 1, "length": 2}}, "joint": {"revolute": \#(axis)}, "drive": {"input": \#(rate)}}], "annotations": \#(annotations), "steps": [{"say": "Motion.", "spin": 1}]}"#
        }
        XCTAssertEqual(reason(one(#"{"dimensions": [{"id": "gap", "a": {"world": [10, 0, 0]}, "b": {"part": "p", "offset": [20, 0, 0]}, "text": "Gap {dim.gap}"}]}"#)), "annotation.pose.gap")
        XCTAssertEqual(reason(one(#"{"arrows": [{"id": "g", "meaning": "force", "cause": "gravity", "from": "p", "to": {"part": "p", "offset": [0, 0, -10]}}]}"#, axis: "[0, 1, 0]")),
                       "annotation.pose.g")
        XCTAssertEqual(reason(one(#"{"arrows": [{"id": "m", "meaning": "motion", "from": {"part": "p", "offset": [20, 0, 0]}, "expect": [0, 1, 0]}]}"#)), "annotation.pose.m")
        // The same rules at rate 1, and a turn arrow instead (its sense is exactly constant).
        XCTAssertEqual(reason(one(#"{"arrows": [{"id": "m", "meaning": "motion", "from": {"part": "p", "offset": [20, 0, 0]}}]}"#, rate: 1)), "annotation.pose.m")
        XCTAssertNil(reason(one(#"{"arrows": [{"id": "t", "meaning": "motion", "style": "turn", "on": "p", "sense": "ccw"}]}"#)))
        // A point on the turning axis stays put: a dimension to it is constant.
        XCTAssertNil(reason(one(#"{"dimensions": [{"id": "gap", "a": {"world": [10, 0, 0]}, "b": {"part": "p", "offset": [0, 0, 5]}}]}"#)))
    }

    /// Third review (C1–C3): every crank chain is refused for direction-bearing annotations, whatever the step: a
    /// follow of a slider, a prismatic joint on a crank rod, a dead centre at a step's end, a turn under a crank rod.
    func testCrankChainsAreRefused() {
        let followSlider = #", {"id": "f", "at": [0, 60, 0], "shape": {"box": {"size": [4, 4, 4]}}, "joint": {"prismatic": [1, 0, 0]}, "drive": {"follow": {"source": "piston", "ratio": 1}}}"#
        func crank(_ extra: String, _ annotations: String, input: Double = 0.5, spin: Double = 1) -> String {
            #"{"v": 2, "kind": "assembly", "params": {"input": \#(input)}, "parts": [\#(Self.slider)\#(extra)], "annotations": \#(annotations), "steps": [{"say": "Motion.", "spin": \#(spin)}]}"#
        }
        XCTAssertEqual(reason(crank(followSlider, #"{"arrows": [{"id": "m", "meaning": "motion", "from": "f", "expect": [-1, 0, 0]}]}"#)), "annotation.motion.nonlinear.m")
        let rodSlider = #", {"id": "q", "at": [0, 60, 0], "shape": {"box": {"size": [4, 4, 4]}}, "joint": {"prismatic": [1, 0, 0]}, "drive": {"crankRod": {"crank": "crank", "radius": 18, "rod": 62}}}"#
        XCTAssertEqual(reason(crank(rodSlider, #"{"arrows": [{"id": "m", "meaning": "motion", "from": "q"}]}"#)), "annotation.motion.nonlinear.m")
        XCTAssertEqual(reason(crank("", #"{"arrows": [{"id": "m", "meaning": "motion", "from": "piston", "expect": [-1, 0, 0]}]}"#, input: 0, spin: 0.5)),
                       "annotation.motion.nonlinear.m")
        let child = #", {"id": "c", "parent": "rod", "shape": {"shaft": {"radius": 2, "length": 2}}, "joint": {"revolute": [0, 0, 1]}, "drive": {"input": 0.1}}"#
        XCTAssertEqual(reason(crank(child, #"{"arrows": [{"id": "t", "meaning": "motion", "style": "turn", "on": "c", "sense": "ccw"}]}"#)), "annotation.motion.nonlinear.t")
        // A dimension in a moving step on a crank chain; the same dimension in a still step stays.
        let gap = #"{"dimensions": [{"id": "gap", "a": {"part": "piston", "offset": [0, 0, 0]}, "b": {"part": "piston", "offset": [0, 10, 0]}}]}"#
        XCTAssertEqual(reason(crank("", gap)), "annotation.motion.nonlinear.gap")
        XCTAssertNil(reason(crank("", gap, spin: 0)))
    }

    /// A constant-ratio follow of a linear joint is linear; a planet on a turning carrier has one world rate; a turn
    /// under a non-parallel turning parent has none.
    func testLinearChainsAndWorldTurnSense() throws {
        let follow = #", {"id": "f", "at": [0, 0, 20], "shape": {"box": {"size": [4, 4, 4]}}, "joint": {"prismatic": [0, 1, 0]}, "drive": {"follow": {"source": "s", "ratio": -2}}}"#
        let t = #"{"v": 2, "kind": "assembly", "parts": [\#(Self.linearParts)\#(follow)], "annotations": {"arrows": [{"id": "m", "meaning": "motion", "from": "f", "expect": [0, -1, 0]}]}, "steps": [{"say": "Moves.", "spin": 2}]}"#
        XCTAssertNil(reason(t))
        let planets = try doc(stage(#"{"arrows": [{"id": "tp", "meaning": "motion", "style": "turn", "on": "stage.planet1", "sense": "cw"}, {"id": "tc", "meaning": "motion", "style": "turn", "on": "stage.carrier", "sense": "ccw"}]}"#,
                                    steps: #"[{"say": "Turn.", "spin": 1}]"#))
        XCTAssertEqual(planets.fact("stage.planet1.worldSpeed")?.value ?? 0, -2.0 / 3, accuracy: 1e-12)
        XCTAssertEqual(planets.annotations.arrow("tp")?.turnSign, -1)
        let tilted = #"{"v": 2, "kind": "assembly", "parts": [{"id": "arm", "shape": {"box": {"size": [40, 4, 4]}}, "joint": {"revolute": [1, 0, 0]}, "drive": {"input": 1}}, {"id": "w", "parent": "arm", "shape": {"shaft": {"radius": 5, "length": 2}}, "joint": {"revolute": [0, 0, 1]}, "drive": {"input": 1}}], "annotations": {"arrows": [{"id": "t", "meaning": "motion", "style": "turn", "on": "w"}]}, "steps": [{"say": "Turn."}]}"#
        XCTAssertEqual(reason(tilted), "arrow.turn.steady.t")
    }

    /// Review 2, R4: a dimension along one axis draws that component, parallel to the axis.
    func testAlongDimensionDrawsTheComponent() throws {
        let d = try doc(#"{"v": 2, "kind": "assembly", "parts": [{"id": "p", "shape": {"box": {"size": [2, 2, 2]}}}], "annotations": {"dimensions": [{"id": "dx", "a": {"world": [0, 0, 0]}, "b": {"world": [3, 4, 0]}, "along": "x"}]}}"#)
        XCTAssertEqual(d.fact("dim.dx")?.value ?? 0, 3, accuracy: 1e-12)
        let line = MGSolidAnnotations.primitives(d, "dx", params: d.defaults)[2]
        let v = line.end - line.start
        XCTAssertEqual(v.length, 3, accuracy: 1e-12)
        XCTAssertEqual(v.normalized.x, 1, accuracy: 1e-12)
        XCTAssertEqual(MGSolidAnnotations.primitives(d, "dx", params: d.defaults)[1].start.x, 3, accuracy: 1e-12, "the second extension line starts at b")
    }

    /// The title may show a dimension only when it holds in every view.
    func testTitleWithAMovingDimension() {
        let t = #"{"v": 2, "kind": "assembly", "title": "Gap {dim.gap}", "parts": [{"id": "p", "shape": {"shaft": {"radius": 1, "length": 2}}, "joint": {"revolute": [0, 0, 1]}, "drive": {"input": 1}}], "annotations": {"dimensions": [{"id": "gap", "a": {"world": [10, 0, 0]}, "b": {"part": "p", "offset": [20, 0, 0]}}]}, "steps": [{"say": "Turn.", "spin": 0.5, "annotate": []}, {"say": "Measure.", "annotate": ["gap"]}]}"#
        XCTAssertEqual(reason(t), "text.pose.title")
        XCTAssertNil(reason(t.replacingOccurrences(of: #""spin": 0.5, "#, with: "")))
    }

    /// Fourth review (D1): a compiled document is read-only to hosts. Every stored property of the compiled types has an
    /// internal setter, so no host can change motion sources, meshes, steps, facts or defaults after the checks ran.
    func testCompiledTypesAreReadOnlyToHosts() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/MartyGraphics/Solid")
        func body(_ file: String, _ type: String) throws -> String {
            let text = try String(contentsOf: root.appendingPathComponent(file), encoding: .utf8)
            let start = try XCTUnwrap(text.range(of: "public struct \(type):"))
            let end = text.range(of: "\n}\n", range: start.upperBound..<text.endIndex)?.lowerBound ?? text.endIndex
            return String(text[start.lowerBound..<end])
        }
        // Fifth review (E1): views too, so a host cannot swap in other cut geometry or another annotation list.
        for (file, type) in [("MGSolidParser.swift", "MGSolidDocument"), ("MGSolidParser.swift", "MGSolidStep"), ("MGSolidParser.swift", "MGSolidGear"),
                             ("MGSolidFacts.swift", "MGSolidFact"), ("MGSolidView.swift", "MGSolidStepSection"), ("MGSolidView.swift", "MGSolidView")] {
            let stored = try body(file, type).split(separator: "\n").filter { $0.hasPrefix("    public var ") && !$0.contains("{") }
            XCTAssertEqual(stored, [], "\(type) has a public setter")
        }
        let view = try body("MGSolidView.swift", "MGSolidView")
        for name in ["parts", "section", "annotations", "motionSense", "step", "fingerprint"] {
            XCTAssertTrue(view.contains("public internal(set) var \(name)"), name)
        }
    }

    /// Fourth review (D2): a document with annotations keeps its default input within 10,000 turns.
    func testDefaultInputIsBounded() {
        let far = gears(#"{"labels": [{"id": "l", "at": "p", "text": "Pinion"}]}"#).replacingOccurrences(of: #""v": 2, "kind": "assembly","#, with: #""v": 2, "kind": "assembly", "params": {"input": 1000000},"#)
        XCTAssertEqual(reason(far), "annotations.input")
        XCTAssertNil(reason(far.replacingOccurrences(of: "1000000", with: "62000")))
        XCTAssertNil(reason(gears("{}").replacingOccurrences(of: #""v": 2, "kind": "assembly","#, with: #""v": 2, "kind": "assembly", "params": {"input": 1000000},"#)),
                     "a document without annotations keeps the old range")
    }

    func testRefusedPoseLeavesTheDocumentUnchanged() throws {
        let d = try doc(try winch())
        let before = d
        let patch = try XCTUnwrap(MGJSON(any: ["steps": [["say": "Wind.", "spin": 1, "annotate": ["aLift"]]]] as [String: Any]))
        XCTAssertEqual(MGSolidParser.applying(patch, to: d).failureReason, "annotation.pose.aLift")
        XCTAssertEqual(d, before)
    }

    // MARK: Compatibility, patches, determinism

    func testRefusedPatchLeavesTheDocumentUnchanged() throws {
        let d = try doc(gears(#"{"labels": [{"id": "lw", "at": "w", "text": "Wheel: {w.teeth} teeth"}]}"#))
        let before = d
        let patch = try XCTUnwrap(MGJSON(any: ["parts": ["w": ["shape": ["gear": ["teeth": 31, "module": 2, "width": 8]]]]] as [String: Any]))
        XCTAssertEqual(MGSolidParser.applying(patch, to: d).failureReason, "constraint.gearMesh.distance")
        XCTAssertEqual(d, before)
        // A patch keeps the annotations and refills their text.
        let ok = try XCTUnwrap(MGJSON(any: ["parts": ["w": ["material": "brass"]]] as [String: Any]))
        guard case .success(let patched) = MGSolidParser.applying(ok, to: d) else { return XCTFail() }
        XCTAssertEqual(patched.annotations, d.annotations)
        XCTAssertEqual(MGSolidParser.applying(try XCTUnwrap(MGJSON(any: ["annotations": [:]] as [String: Any])), to: d).failureReason,
                       "patch.unknown.annotations")
    }

    func testSeveralErrorsGiveTheFirstInAuthoredOrder() {
        let text = gears(#"{"labels": [{"id": "l1", "at": "nope", "text": "A 1"}], "arrows": [{"id": "a1", "meaning": "push", "from": "p", "to": "w"}], "dimensions": [{"id": "d1", "a": "p", "b": "p"}]}"#)
        for _ in 0..<5 { XCTAssertEqual(reason(text), "anchor.ref.nope") }
        XCTAssertEqual(reason(gears(#"{"labels": [{"id": "l1", "at": "p", "text": "A 1"}], "dimensions": [{"id": "d1", "a": "p", "b": "p"}]}"#)), "dimension.zero.d1",
                       "dimensions are measured before any text is filled")
    }

    func testDocumentsWithoutAnnotationsAreUnchanged() throws {
        let d = try doc(gears("{}"))
        XCTAssertTrue(d.annotations.isEmpty)
        XCTAssertEqual(d.legend.notes, [])
        XCTAssertEqual(d.view(step: 0).annotations, [])
        XCTAssertFalse(d.claims.contains { $0.kind == .annotation })
        XCTAssertEqual(d.annotationReport, .array([]))
    }

    func testMeshEstimateIsExact() throws {
        let d = try doc(gears(#"{"arrows": [{"id": "aw", "meaning": "motion", "style": "turn", "on": "w"}, {"id": "ap", "meaning": "pointer", "from": {"world": [0, -60, 30]}, "to": "p"}], "dimensions": [{"id": "g1", "a": "p", "b": "w"}, {"id": "g2", "a": "p", "b": "w", "along": "x"}, {"id": "g3", "kind": "angle", "a": "w", "vertex": "p", "b": {"world": [0, 40, 0]}}]}"#))
        var triangles = 0, vertices = 0
        for id in d.annotations.ids {
            for p in MGSolidAnnotations.primitives(d, id, params: d.defaults) {
                var shown = p; shown.hidden = false
                let m = shown.renderMesh
                triangles += m.indices.count / 3; vertices += m.positions.count
                XCTAssertEqual(m.normals.count, m.positions.count)
            }
        }
        XCTAssertEqual(triangles, d.annotations.meshEstimate.triangles)
        XCTAssertEqual(vertices, d.annotations.meshEstimate.vertices)
    }
}

extension Result where Failure == MGSolidIssue {
    var failureReason: String? { if case .failure(let e) = self { return e.reason }; return nil }
}
