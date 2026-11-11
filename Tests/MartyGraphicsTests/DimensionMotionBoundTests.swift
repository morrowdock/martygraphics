// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import MartyGraphics

/// Dimension claims in a moving step get the proven motion bound of #53 (docs/SOLID-3D.md, "Poses: every claim holds at
/// every pose its view can show"). Before, an anchor that was world-fixed within the epsilon of each axis counted as not
/// moving, though such offsets add up along a chain: an eight-joint chain whose axes lie 0.0000018 mm around one point
/// moved a dimension's end 0.0000288 mm, 7.18 × the dimension tolerance, and both the constant claim and an `over` range
/// passed strict as Solved. Synthetic boxes and neutral names.
final class DimensionMotionBoundTests: XCTestCase {
    /// The eight-joint chain `t1`…`t8` (alternating rates ±0.5, axes ±0.0000036 mm apart, each box 0.0000018 mm off its
    /// joint's axis), a slider `s` (0.01 mm per input radian) and a distant box that makes the diagonal about 4000 mm.
    func chainText(_ dim: String, spin: Double = 1) -> String {
        var parts = [#"{"id": "body", "shape": {"box": {"size": [20, 20, 20]}}}"#]
        for k in 1...8 {
            let sign = k % 2 == 1 ? 1.0 : -1.0
            let at = k == 1 ? "[0, -100, 0]" : "[\(-3.6e-06 * sign), 0, 0]"
            let parent = k == 1 ? "" : #", "parent": "t\#(k - 1)""#
            parts.append(#"{"id": "t\#(k)", "shape": {"box": {"size": [0.05, 0.05, 0.05], "at": [\#(1.8e-06 * sign), 0, 0]}}, "at": \#(at), "joint": {"revolute": [0, 0, 1]}, "drive": {"input": \#(0.5 * sign)}, "offAxis": true\#(parent)}"#)
        }
        parts.append(#"{"id": "s", "shape": {"box": {"size": [2, 2, 2]}}, "at": [10, -100, 0], "joint": {"prismatic": [1, 0, 0]}, "drive": {"input": 0.01}}"#)
        parts.append(#"{"id": "distant", "shape": {"box": {"size": [0.05, 0.05, 0.05]}}, "at": [4000, 0, 0]}"#)
        return #"{"v": 2, "kind": "assembly", "parts": [\#(parts.joined(separator: ", "))], "annotations": {"dimensions": [\#(dim)]}, "steps": [{"say": "The gap is {dim.gap}.", "camera": "front", "spin": \#(spin), "annotate": ["gap"]}]}"#
    }
    static let end = #"{"part": "t8", "offset": [-1.8e-06, 0, 0]}"#
    static let constant = #"{"id": "gap", "a": \#(end), "b": {"world": [50, -100, 0]}}"#
    static let range = #"{"id": "gap", "a": "s", "b": \#(end), "over": "input"}"#

    func refusal(_ t: String) -> MGSolidIssue? {
        if case .failure(let e) = MGSolidParser.document(data: Data(t.utf8)) { return e }
        return nil
    }
    func strict(_ t: String) -> MGSolidReport { MGSolidReport.check(data: Data(t.utf8), profile: .strict, engine: nil) }

    /// The value of `d` sampled densely over one input turn (the drift proof; the rule itself samples nothing).
    func sampled(_ d: MGSolidDimension, _ doc: MGSolidDocument, count: Int = 20_000) -> (lo: Double, hi: Double) {
        var lo = Double.infinity, hi = -Double.infinity
        for i in 0...count {
            let pose = doc.assembly.pose(MGPoseParameters(input: Double(i) / Double(count) * 2 * .pi, explode: 0))
            let v = MGSolidAnnotationEngine.dimensionValue(d, pose)!
            lo = min(lo, v); hi = max(hi, v)
        }
        return (lo, hi)
    }

    func testAConstantDimensionOnANearAxisChainIsRefused() throws {
        // The drift is real: the same assembly with a still step compiles; sampled over the spin, the value leaves the
        // fact by more than the tolerance.
        let still = try MGSolidParser.document(data: Data(chainText(Self.constant, spin: 0).utf8)).get()
        let d = try XCTUnwrap(still.annotations.dimension("gap"))
        let tol = 1e-9 * max(1, d.value, still.annotations.diagonal)
        let s = sampled(d, still)
        let drift = max(s.hi - d.value, d.value - s.lo)
        XCTAssertGreaterThan(drift, 7 * tol, "drift \(drift), tolerance \(tol)")
        // Before: accepted as Solved. Now: refused, with the bound.
        let t = chainText(Self.constant)
        let e = try XCTUnwrap(refusal(t), "a dimension whose value drifts past its tolerance was accepted")
        XCTAssertEqual(e.reason, "annotation.pose.gap")
        let m = try XCTUnwrap(e.dimensionMotion)
        XCTAssertEqual(m.dimension, "gap"); XCTAssertEqual(m.step, 0); XCTAssertFalse(m.over)
        XCTAssertGreaterThan(m.boundA, 0); XCTAssertEqual(m.boundB, 0); XCTAssertNil(m.boundVertex)
        XCTAssertEqual(m.change, m.boundA + m.boundB)
        XCTAssertGreaterThanOrEqual(m.change, drift, "the bound covers the sampled drift")
        XCTAssertGreaterThan(m.change, m.tolerance)
        XCTAssertEqual(m.anchor, "a"); XCTAssertEqual(m.part, "t8"); XCTAssertTrue(m.joint.hasPrefix("t"), m.joint)
        XCTAssertNotNil(m.distance)
        XCTAssertTrue(m.repair.contains("\"spin\": 0 in step 1"), m.repair)
        XCTAssertTrue(m.repair.contains("{\"a\": {\"world\": ["), m.repair)
        let rep = strict(t)
        XCTAssertFalse(rep.ok); XCTAssertEqual(rep.reason, "annotation.pose.gap")
        guard case .object(let detail)? = rep.json["dimensionMotion"], case .string(let line)? = rep.json["repair"] else { return XCTFail("dimensionMotion") }
        XCTAssertEqual(detail["part"], .string("t8")); XCTAssertEqual(line, m.repair)
        // The same claim in the caption only: `text.pose.step.1`, with the same detail.
        let caption = t.replacingOccurrences(of: #""annotate": ["gap"]"#, with: #""annotate": []"#)
        let c = try XCTUnwrap(refusal(caption))
        XCTAssertEqual(c.reason, "text.pose.step.1"); XCTAssertEqual(c.dimensionMotion, m)
    }

    func testTheWorldFixedControlTheStillStepAndTheRepairPass() throws {
        // The same end as a world point: nothing moves.
        let posed = try MGSolidParser.document(data: Data(chainText(Self.constant, spin: 0).utf8)).get()
        let x = try XCTUnwrap(posed.annotations.dimension("gap")).a.world(posed.assembly.pose(MGPoseParameters(input: 0, explode: 0)))
        let world = #"{"id": "gap", "a": {"world": [\#(x.x), \#(x.y), \#(x.z)]}, "b": {"world": [50, -100, 0]}}"#
        XCTAssertTrue(strict(chainText(world)).ok, strict(chainText(world)).reason ?? "")
        // A still step shows one pose.
        XCTAssertTrue(strict(chainText(Self.constant, spin: 0)).ok, strict(chainText(Self.constant, spin: 0)).reason ?? "")
        // The fixed-point repair, applied at full precision, passes strict.
        let m = try XCTUnwrap(refusal(chainText(Self.constant))?.dimensionMotion)
        guard case .object(let f) = m.fixed, let a = f["a"] else { return XCTFail("fixed") }
        guard case .object(var src) = try MGSolidParser.document(data: Data(chainText(Self.constant, spin: 0).utf8)).get().source,
              case .object(var ann)? = src["annotations"], case .array(var dims)? = ann["dimensions"], case .object(var gap) = dims[0],
              case .array(var steps)? = src["steps"], case .object(var step) = steps[0] else { return XCTFail("source") }
        gap["a"] = a; dims[0] = .object(gap); ann["dimensions"] = .array(dims); src["annotations"] = .object(ann)
        step["spin"] = .number(1); steps[0] = .object(step); src["steps"] = .array(steps)
        guard case .success(let fixed) = MGSolidParser.document(json: .object(src)) else { return XCTFail("the applied repair does not compile") }
        let r = MGSolidReport.make(fixed, profile: .strict, engine: nil)
        XCTAssertTrue(r.ok, r.reason ?? "")
    }

    /// Two anchors on the same part ride the same moving joints: their distance is exactly constant (no bound needed).
    func testTwoAnchorsOnOneChainKeepTheirDistanceExactly() throws {
        let t = chainText(#"{"id": "gap", "a": \#(Self.end), "b": {"part": "t8", "offset": [-1.8e-06, 0, -0.5]}}"#)
        let rep = strict(t)
        XCTAssertTrue(rep.ok, rep.reason ?? "")
        // `along` on a turning chain is still refused (a turn changes world components).
        let along = chainText(#"{"id": "gap", "a": \#(Self.end), "b": {"part": "t8", "offset": [0.5, 0, 0]}, "along": "x"}"#)
        XCTAssertEqual(refusal(along)?.reason, "annotation.pose.gap")
        XCTAssertNil(refusal(along)?.dimensionMotion)
    }

    /// An angle at a world vertex between a world point and the chain's end: each arm can turn by `asin(e / L)`.
    func testAnAngleOnANearAxisChainIsBounded() throws {
        let t = chainText(#"{"id": "gap", "kind": "angle", "vertex": {"world": [0, -100, -50]}, "a": \#(Self.end), "b": {"world": [50, -100, -50]}}"#)
        let e = try XCTUnwrap(refusal(t), "an angle whose arm turns past its tolerance was accepted")
        XCTAssertEqual(e.reason, "annotation.pose.gap")
        let m = try XCTUnwrap(e.dimensionMotion)
        XCTAssertEqual(m.unit, "°"); XCTAssertEqual(m.boundVertex, 0); XCTAssertEqual(m.boundB, 0)
        XCTAssertEqual(m.change, asin(m.boundA / 50) * 180 / .pi, accuracy: 1e-12)
    }

    func testAnOverRangeHeldByANearAxisChainIsRefused() throws {
        // The range is off: the same dimension without `over` compiles in a still step; its sampled range over the turn
        // differs from the closed-form range by more than the tolerance.
        let plain = try MGSolidParser.document(data: Data(chainText(#"{"id": "gap", "a": "s", "b": \#(Self.end)}"#, spin: 0).utf8)).get()
        let d = try XCTUnwrap(plain.annotations.dimension("gap"))
        let r = try MGSolidAnnotationMotion.rangeBound(d, plain, explode: 0)
        let tol = 1e-9 * max(1, r.value, plain.annotations.diagonal)
        let s = sampled(d, plain)
        let off = abs(s.hi - s.lo - r.value)
        XCTAssertGreaterThan(off, 7 * tol, "range error \(off), tolerance \(tol)")
        XCTAssertGreaterThanOrEqual(r.bound, off, "the bound covers the sampled error")
        // Before: the range was a Solved fact. Now: `dimension.over.motion.gap` at compile, with the bound.
        let e = try XCTUnwrap(refusal(chainText(Self.range, spin: 0)), "an over range off by more than its tolerance was accepted")
        XCTAssertEqual(e.reason, "dimension.over.motion.gap")
        let m = try XCTUnwrap(e.dimensionMotion)
        XCTAssertTrue(m.over); XCTAssertNil(m.step)
        XCTAssertEqual(m.boundA, 0, "the slider's motion is exact"); XCTAssertGreaterThan(m.boundB, 0)
        XCTAssertEqual(m.change, 2 * m.boundB)
        XCTAssertEqual(m.anchor, "b"); XCTAssertEqual(m.part, "t8")
        XCTAssertTrue(m.repair.contains("{\"b\": {\"world\": ["), m.repair)
        XCTAssertFalse(m.repair.contains("spin"), m.repair)
        let rep = strict(chainText(Self.range, spin: 0))
        XCTAssertEqual(rep.reason, "dimension.over.motion.gap")
        XCTAssertNotNil(rep.json["dimensionMotion"])
        // The world-point control: the range is exact and passes strict.
        let x = d.b.world(plain.assembly.pose(MGPoseParameters(input: 0, explode: 0)))
        let world = chainText(#"{"id": "gap", "a": "s", "b": {"world": [\#(x.x), \#(x.y), \#(x.z)]}, "over": "input"}"#, spin: 0)
        XCTAssertTrue(strict(world).ok, strict(world).reason ?? "")
    }
}
