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

    func testA2MotionArrowLengthShowsAFact() throws {
        let d = try doc(slider(#"{"arrows": [{"id": "aRod", "meaning": "motion", "from": {"part": "piston", "point": "centre"}, "length": {"fact": "piston.travel", "scale": 2}}]}"#))
        let travel = try XCTUnwrap(d.fact("piston.travel"))
        XCTAssertEqual(travel.value, 36, accuracy: 1e-9)
        let r = try XCTUnwrap(d.annotations.arrow("aRod"))
        XCTAssertEqual(try XCTUnwrap(r.length), 2 * travel.value, accuracy: 1e-9)
        let prims = MGSolidAnnotations.primitives(d, "aRod", params: d.defaults)
        XCTAssertEqual((prims[1].end - prims[0].start).length, 2 * travel.value, accuracy: 1e-9)
        XCTAssertEqual(r.tier, travel.tier)
        XCTAssertTrue(r.scaled)
        XCTAssertFalse(d.legend.notes.contains("Arrow lengths are not to scale"), "the only arrow shows a fact length")
        XCTAssertEqual(reason(slider(#"{"arrows": [{"id": "aRod", "meaning": "motion", "from": "piston", "length": {"fact": "nope.travel", "scale": 2}}]}"#)),
                       "arrow.length.fact.aRod")
    }

    func testA3TypedForceArrowIsDescribedAndArrowsAreNotToScale() throws {
        let d = try doc(gears(#"{"arrows": [{"id": "aPush", "meaning": "force", "from": {"world": [0, -40, 0]}, "to": "p", "text": "Push"}]}"#))
        let c = try XCTUnwrap(claim(d, "aPush"))
        XCTAssertEqual(c.tier, .described)
        XCTAssertEqual(c.badge, "Not checked")
        XCTAssertTrue(d.legend.notes.contains("Arrow lengths are not to scale"))
        XCTAssertEqual(d.legend.text, "Solved 2 · Not checked 1")
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
        // A crank rod swings back and forth, so no single turn sense holds for a whole view.
        XCTAssertEqual(reason(slider(#"{"arrows": [{"id": "a1", "meaning": "motion", "style": "turn", "on": "rod"}]}"#)), "arrow.turn.steady.a1")
        XCTAssertNoThrow(try doc(slider(#"{"arrows": [{"id": "a1", "meaning": "motion", "style": "turn", "on": "crank"}]}"#)))
    }

    func testA13MotionArrowAtDeadCentreLooksAhead() throws {
        let d = try doc(slider(#"{"arrows": [{"id": "aRod", "meaning": "motion", "from": {"part": "piston", "point": "centre"}}]}"#))
        let r = try XCTUnwrap(d.annotations.arrow("aRod"))
        let dir = try XCTUnwrap(r.direction)
        // From top dead centre (input 0, piston at its largest x) the piston first moves toward -X.
        XCTAssertEqual(dir.x, -1, accuracy: 1e-6)
        XCTAssertEqual(r.tier, .solved)
        // While a view plays, the arrow follows the velocity and never hides at a dead centre.
        let quarter = MGSolidAnnotations.primitives(d, "aRod", params: MGPoseParameters(input: .pi / 2))
        XCTAssertFalse(quarter[1].hidden)
        XCTAssertEqual((quarter[1].end - quarter[0].start).normalized.x, -1, accuracy: 1e-6)
        let back = MGSolidAnnotations.primitives(d, "aRod", params: MGPoseParameters(input: 3 * .pi / 2))
        XCTAssertEqual((back[1].end - back[0].start).normalized.x, 1, accuracy: 1e-6)
    }

    func testA14StatedDirectionIsChecked() {
        XCTAssertEqual(reason(slider(#"{"arrows": [{"id": "aRod", "meaning": "motion", "from": {"part": "piston", "point": "centre"}, "expect": [1, 0, 0]}]}"#)),
                       "arrow.expect.aRod")
        XCTAssertNil(reason(slider(#"{"arrows": [{"id": "aRod", "meaning": "motion", "from": {"part": "piston", "point": "centre"}, "expect": [-1, 0.2, 0]}]}"#)))
        XCTAssertEqual(reason(slider(#"{"arrows": [{"id": "aRod", "meaning": "motion", "from": {"world": [0, 0, 0]}}]}"#)), "arrow.from.aRod")
        XCTAssertEqual(reason(slider(#"{"arrows": [{"id": "aRod", "meaning": "motion", "from": "frame"}]}"#)), "arrow.still.aRod")
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
        XCTAssertEqual(reason(gears(#"{"labels": [{"id": "l1", "at": {"part": "p"}, "text": "P"}]}"#)), "anchor.form")
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
        XCTAssertEqual(reason(gears(#"{"labels": [{"id": "l1", "at": "p", "text": "\#(String(repeating: "x", count: 41))"}]}"#)), "label.text.l1")
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
        let prims = MGSolidAnnotations.primitives(d, "aw", params: d.defaults, sense: view.motionSense)
        let c = MGVec3(45, 0, prims[0].start.z)
        XCTAssertGreaterThan((prims[0].start - c).cross(prims[0].end - c).z, 0, "played backwards, the wheel turns counter-clockwise")
        let snap = MGSolidSnapshot.make(d, step: 0, params: d.defaults)
        XCTAssertGreaterThan(snap.annotations?.arrows.first?.direction[1] ?? 0, 0, "turns counter-clockwise about kernel +Z (world +Y)")
        // A line arrow played backwards points the other way.
        let s = try doc(slider(#"{"arrows": [{"id": "aRod", "meaning": "motion", "from": {"part": "piston", "point": "centre"}}]}"#,
                               steps: #"[{"say": "Back.", "spin": -1}]"#))
        let back = MGSolidAnnotations.primitives(s, "aRod", params: MGPoseParameters(input: .pi / 2), sense: -1)
        XCTAssertEqual((back[1].end - back[0].start).normalized.x, 1, accuracy: 1e-6)
    }

    /// S2: one meaning per reason for `over` dimensions that do not change.
    func testOverWithNoChangeHasItsOwnReason() {
        let still = #"{"dimensions": [{"id": "same", "a": {"part": "w", "offset": [10, 0, 0]}, "b": {"part": "w", "offset": [-10, 0, 0]}, "over": "input"}]}"#
        XCTAssertEqual(reason(gears(still)), "dimension.over.still.same")
        let angle = #"{"dimensions": [{"id": "ang", "kind": "angle", "a": {"part": "w", "offset": [10, 0, 0]}, "vertex": "w", "b": {"part": "w", "offset": [0, 10, 0]}, "over": "input"}]}"#
        XCTAssertEqual(reason(gears(angle)), "dimension.over.still.ang")
    }

    /// S3: a host view with more than 12 annotations is refused visibly, never laid out with texts missing.
    func testFrameRefusesTooManyAnnotations() throws {
        let labels = (0..<13).map { #"{"id": "l\#($0)", "at": "p", "text": "Label"}"# }.joined(separator: ",")
        let d = try doc(gears(#"{"labels": [\#(labels)]}"#, steps: #"[{"say": "Some.", "annotate": ["l0"]}, {"say": "Rest.", "annotate": ["l1", "l2", "l3", "l4", "l5", "l6", "l7", "l8", "l9", "l10", "l11", "l12"]}]"#))
        var view = d.view(step: 0)
        let cam = MGSolidAnnotations.defaultCamera(d, params: d.defaults)
        XCTAssertNil(MGSolidAnnotations.frame(document: d, view: view, params: d.defaults, camera: cam, aspect: 1.6).refusal)
        view.annotations = d.annotations.ids
        let f = MGSolidAnnotations.frame(document: d, view: view, params: d.defaults, camera: cam, aspect: 1.6)
        XCTAssertEqual(f.refusal, "annotations.visible")
        XCTAssertEqual(f.placement, [])
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
