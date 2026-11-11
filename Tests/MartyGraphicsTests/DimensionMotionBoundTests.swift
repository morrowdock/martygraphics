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
        XCTAssertTrue(m.repair.hasPrefix(#"Set "spin": 0 in step 1. Or replace its anchors with {"a": {"world": ["#), m.repair)
        try assertActionsParse(m.repair)
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
        guard case .object(let f)? = m.fixed, let a = f["a"] else { return XCTFail("fixed") }
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

    // MARK: Review of #54: every executable repair validates and stays whole

    static let farConstant = #"{"annotations":{"dimensions":[{"a":{"offset":[-1.8e-06,0,0],"part":"t8"},"b":{"world":[50,-100,0]},"id":"gap"}]},"kind":"assembly","parts":[{"id":"body","shape":{"box":{"size":[20,20,20]}}},{"at":[0,-100,0],"drive":{"input":0.5},"id":"t1","joint":{"revolute":[0,0,1]},"offAxis":true,"parent":"carrier","shape":{"box":{"at":[1.8e-06,0,0],"size":[0.05,0.05,0.05]}}},{"at":[3.6e-06,0,0],"drive":{"input":-0.5},"id":"t2","joint":{"revolute":[0,0,1]},"offAxis":true,"parent":"t1","shape":{"box":{"at":[-1.8e-06,0,0],"size":[0.05,0.05,0.05]}}},{"at":[-3.6e-06,0,0],"drive":{"input":0.5},"id":"t3","joint":{"revolute":[0,0,1]},"offAxis":true,"parent":"t2","shape":{"box":{"at":[1.8e-06,0,0],"size":[0.05,0.05,0.05]}}},{"at":[3.6e-06,0,0],"drive":{"input":-0.5},"id":"t4","joint":{"revolute":[0,0,1]},"offAxis":true,"parent":"t3","shape":{"box":{"at":[-1.8e-06,0,0],"size":[0.05,0.05,0.05]}}},{"at":[-3.6e-06,0,0],"drive":{"input":0.5},"id":"t5","joint":{"revolute":[0,0,1]},"offAxis":true,"parent":"t4","shape":{"box":{"at":[1.8e-06,0,0],"size":[0.05,0.05,0.05]}}},{"at":[3.6e-06,0,0],"drive":{"input":-0.5},"id":"t6","joint":{"revolute":[0,0,1]},"offAxis":true,"parent":"t5","shape":{"box":{"at":[-1.8e-06,0,0],"size":[0.05,0.05,0.05]}}},{"at":[-3.6e-06,0,0],"drive":{"input":0.5},"id":"t7","joint":{"revolute":[0,0,1]},"offAxis":true,"parent":"t6","shape":{"box":{"at":[1.8e-06,0,0],"size":[0.05,0.05,0.05]}}},{"at":[3.6e-06,0,0],"drive":{"input":-0.5},"id":"t8","joint":{"revolute":[0,0,1]},"offAxis":true,"parent":"t7","shape":{"box":{"at":[-1.8e-06,0,0],"size":[0.05,0.05,0.05]}}},{"at":[10,-100,0],"drive":{"input":0.01},"id":"s","joint":{"prismatic":[1,0,0]},"shape":{"box":{"size":[2,2,2]}}},{"at":[4000,0,0],"id":"distant","shape":{"box":{"size":[0.05,0.05,0.05]}}},{"at":[4000,0,0],"id":"carrier","shape":{"box":{"size":[2,2,2]}}}],"steps":[{"annotate":["gap"],"camera":"front","say":"The gap is {dim.gap}.","spin":1}],"v":2}"#
    static let farOver = #"{"annotations":{"dimensions":[{"a":"s","b":{"offset":[-1.8e-06,0,0],"part":"t8"},"id":"gap","over":"input"}]},"kind":"assembly","parts":[{"id":"body","shape":{"box":{"size":[20,20,20]}}},{"at":[0,-100,0],"drive":{"input":0.5},"id":"t1","joint":{"revolute":[0,0,1]},"offAxis":true,"parent":"carrier","shape":{"box":{"at":[1.8e-06,0,0],"size":[0.05,0.05,0.05]}}},{"at":[3.6e-06,0,0],"drive":{"input":-0.5},"id":"t2","joint":{"revolute":[0,0,1]},"offAxis":true,"parent":"t1","shape":{"box":{"at":[-1.8e-06,0,0],"size":[0.05,0.05,0.05]}}},{"at":[-3.6e-06,0,0],"drive":{"input":0.5},"id":"t3","joint":{"revolute":[0,0,1]},"offAxis":true,"parent":"t2","shape":{"box":{"at":[1.8e-06,0,0],"size":[0.05,0.05,0.05]}}},{"at":[3.6e-06,0,0],"drive":{"input":-0.5},"id":"t4","joint":{"revolute":[0,0,1]},"offAxis":true,"parent":"t3","shape":{"box":{"at":[-1.8e-06,0,0],"size":[0.05,0.05,0.05]}}},{"at":[-3.6e-06,0,0],"drive":{"input":0.5},"id":"t5","joint":{"revolute":[0,0,1]},"offAxis":true,"parent":"t4","shape":{"box":{"at":[1.8e-06,0,0],"size":[0.05,0.05,0.05]}}},{"at":[3.6e-06,0,0],"drive":{"input":-0.5},"id":"t6","joint":{"revolute":[0,0,1]},"offAxis":true,"parent":"t5","shape":{"box":{"at":[-1.8e-06,0,0],"size":[0.05,0.05,0.05]}}},{"at":[-3.6e-06,0,0],"drive":{"input":0.5},"id":"t7","joint":{"revolute":[0,0,1]},"offAxis":true,"parent":"t6","shape":{"box":{"at":[1.8e-06,0,0],"size":[0.05,0.05,0.05]}}},{"at":[3.6e-06,0,0],"drive":{"input":-0.5},"id":"t8","joint":{"revolute":[0,0,1]},"offAxis":true,"parent":"t7","shape":{"box":{"at":[-1.8e-06,0,0],"size":[0.05,0.05,0.05]}}},{"at":[10,-100,0],"drive":{"input":0.01},"id":"s","joint":{"prismatic":[1,0,0]},"shape":{"box":{"size":[2,2,2]}}},{"at":[4000,0,0],"id":"distant","shape":{"box":{"size":[0.05,0.05,0.05]}}},{"at":[4000,0,0],"id":"carrier","shape":{"box":{"size":[2,2,2]}}}],"steps":[{"annotate":["gap"],"camera":"front","say":"The gap is {dim.gap}.","spin":0}],"v":2}"#
    static let longIds = #"{"annotations":{"dimensions":[{"a":{"offset":[-1.8e-06,0,0],"part":"pppppppppppppppppppppppp"},"b":{"offset":[1.8e-06,0,0],"part":"other"},"id":"dddddddddddddddddddddddd","kind":"angle","vertex":{"world":[50,-100.1234567890123,1.2345678901234567]}}]},"kind":"assembly","parts":[{"id":"body","shape":{"box":{"size":[20,20,20]}}},{"at":[0,-100.1234567890123,1.2345678901234567],"drive":{"input":0.5},"id":"jjjjjjjjjjjjjjjjjjjjjjjj","joint":{"revolute":[0,0,1]},"offAxis":true,"shape":{"box":{"at":[1.8e-06,0,0],"size":[0.05,0.05,0.05]}}},{"at":[3.6e-06,0,0],"drive":{"input":-0.5},"id":"t2","joint":{"revolute":[0,0,1]},"offAxis":true,"parent":"jjjjjjjjjjjjjjjjjjjjjjjj","shape":{"box":{"at":[-1.8e-06,0,0],"size":[0.05,0.05,0.05]}}},{"at":[-3.6e-06,0,0],"drive":{"input":0.5},"id":"t3","joint":{"revolute":[0,0,1]},"offAxis":true,"parent":"t2","shape":{"box":{"at":[1.8e-06,0,0],"size":[0.05,0.05,0.05]}}},{"at":[3.6e-06,0,0],"drive":{"input":-0.5},"id":"t4","joint":{"revolute":[0,0,1]},"offAxis":true,"parent":"t3","shape":{"box":{"at":[-1.8e-06,0,0],"size":[0.05,0.05,0.05]}}},{"at":[-3.6e-06,0,0],"drive":{"input":0.5},"id":"t5","joint":{"revolute":[0,0,1]},"offAxis":true,"parent":"t4","shape":{"box":{"at":[1.8e-06,0,0],"size":[0.05,0.05,0.05]}}},{"at":[3.6e-06,0,0],"drive":{"input":-0.5},"id":"t6","joint":{"revolute":[0,0,1]},"offAxis":true,"parent":"t5","shape":{"box":{"at":[-1.8e-06,0,0],"size":[0.05,0.05,0.05]}}},{"at":[-3.6e-06,0,0],"drive":{"input":0.5},"id":"t7","joint":{"revolute":[0,0,1]},"offAxis":true,"parent":"t6","shape":{"box":{"at":[1.8e-06,0,0],"size":[0.05,0.05,0.05]}}},{"at":[3.6e-06,0,0],"drive":{"input":-0.5},"id":"pppppppppppppppppppppppp","joint":{"revolute":[0,0,1]},"offAxis":true,"parent":"t7","shape":{"box":{"at":[-1.8e-06,0,0],"size":[0.05,0.05,0.05]}}},{"at":[10,-100,0],"drive":{"input":0.01},"id":"s","joint":{"prismatic":[1,0,0]},"shape":{"box":{"size":[2,2,2]}}},{"at":[4000,0,0],"id":"distant","shape":{"box":{"size":[0.05,0.05,0.05]}}},{"at":[0,-100.1234567890123,51.23456789012345],"drive":{"input":0.5},"id":"other","joint":{"revolute":[0,0,1]},"shape":{"box":{"size":[2,2,2]}}}],"steps":[{"annotate":["dddddddddddddddddddddddd"],"say":"An angle.","spin":1}],"v":2}"#
    static let minimumArm = #"{"annotations":{"dimensions":[{"a":{"offset":[-1.8e-14,0,0],"part":"t8"},"b":{"world":[-0.009999999999983,-100,-0.02]},"id":"gap","kind":"angle","vertex":{"world":[-0.009999999999983,-100,0]}}]},"kind":"assembly","parts":[{"id":"body","shape":{"box":{"size":[20,20,20]}}},{"at":[0,-100,0],"drive":{"input":0.5},"id":"t1","joint":{"revolute":[0,0,1]},"offAxis":true,"shape":{"box":{"at":[1.8e-14,0,0],"size":[0.05,0.05,0.05]}}},{"at":[3.6e-14,0,0],"drive":{"input":-0.5},"id":"t2","joint":{"revolute":[0,0,1]},"offAxis":true,"parent":"t1","shape":{"box":{"at":[-1.8e-14,0,0],"size":[0.05,0.05,0.05]}}},{"at":[-3.6e-14,0,0],"drive":{"input":0.5},"id":"t3","joint":{"revolute":[0,0,1]},"offAxis":true,"parent":"t2","shape":{"box":{"at":[1.8e-14,0,0],"size":[0.05,0.05,0.05]}}},{"at":[3.6e-14,0,0],"drive":{"input":-0.5},"id":"t4","joint":{"revolute":[0,0,1]},"offAxis":true,"parent":"t3","shape":{"box":{"at":[-1.8e-14,0,0],"size":[0.05,0.05,0.05]}}},{"at":[-3.6e-14,0,0],"drive":{"input":0.5},"id":"t5","joint":{"revolute":[0,0,1]},"offAxis":true,"parent":"t4","shape":{"box":{"at":[1.8e-14,0,0],"size":[0.05,0.05,0.05]}}},{"at":[3.6e-14,0,0],"drive":{"input":-0.5},"id":"t6","joint":{"revolute":[0,0,1]},"offAxis":true,"parent":"t5","shape":{"box":{"at":[-1.8e-14,0,0],"size":[0.05,0.05,0.05]}}},{"at":[-3.6e-14,0,0],"drive":{"input":0.5},"id":"t7","joint":{"revolute":[0,0,1]},"offAxis":true,"parent":"t6","shape":{"box":{"at":[1.8e-14,0,0],"size":[0.05,0.05,0.05]}}},{"at":[3.6e-14,0,0],"drive":{"input":-0.5},"id":"t8","joint":{"revolute":[0,0,1]},"offAxis":true,"parent":"t7","shape":{"box":{"at":[-1.8e-14,0,0],"size":[0.05,0.05,0.05]}}},{"at":[10,-100,0],"drive":{"input":0.01},"id":"s","joint":{"prismatic":[1,0,0]},"shape":{"box":{"size":[2,2,2]}}},{"at":[4000,0,0],"id":"distant","shape":{"box":{"size":[0.05,0.05,0.05]}}}],"steps":[{"annotate":["gap"],"camera":"front","say":"The gap is {dim.gap}.","spin":1}],"v":2}"#

    /// Each action of a repair line is whole: it starts with `Set "spin": 0 in step <n>.` (when `spin` is given), and a
    /// replacement after "anchors with " or "fixed points: " is complete JSON up to its closing brace.
    func assertActionsParse(_ line: String, spin: Bool = true, file: StaticString = #filePath, l: UInt = #line) throws {
        XCTAssertLessThanOrEqual(line.unicodeScalars.count, MGAnnotationAnchorIssue.repairScalars, file: file, line: l)
        if spin { XCTAssertNotNil(line.range(of: #"^Set "spin": 0 in step \d+\."#, options: .regularExpression), line, file: file, line: l) }
        for lead in ["anchors with ", "fixed points: "] {
            guard let r = line.range(of: lead), line[r.upperBound...].hasPrefix("{") else { continue }
            var depth = 0, end = r.upperBound
            for i in line[r.upperBound...].indices {
                if line[i] == "{" { depth += 1 } else if line[i] == "}" { depth -= 1; if depth == 0 { end = line.index(after: i); break } }
            }
            XCTAssertEqual(depth, 0, "the JSON is cut: \(line)", file: file, line: l)
            let fragment = String(line[r.upperBound..<end])
            XCTAssertNotNil(try? JSONSerialization.jsonObject(with: Data(fragment.utf8)), fragment, file: file, line: l)
        }
    }

    /// `source` with dimension `id`'s anchors replaced by `fixed`, compiled.
    func applying(_ t: String, _ fixed: MGJSON, id: String = "gap") throws -> MGSolidReport {
        let json = try XCTUnwrap(MGJSON(any: try JSONSerialization.jsonObject(with: Data(t.utf8))))
        return MGSolidReport.check(data: MGRepairCheck.replacingDimension(json, id, fixed).canonicalData,
                                   profile: .strict, engine: nil)
    }

    /// The review's nested chain: the eight joints under a still `carrier` at x = 4000. The end's world point is x =
    /// 4000.0000018, outside the ±4000 mm a world anchor allows (`anchor.world`), so a world-point repair cannot apply.
    /// Now the copy is compiled first: the world points are refused, and the repair is the end's offset on `carrier`
    /// (it validates; applied, strict passes). The constant case keeps `"spin": 0` first.
    func testAnUnrepresentableWorldRepairFallsBackToAStillPart() throws {
        for (t, over) in [(Self.farConstant, false), (Self.farOver, true)] {
            let e = try XCTUnwrap(refusal(t))
            XCTAssertEqual(e.reason, over ? "dimension.over.motion.gap" : "annotation.pose.gap")
            let m = try XCTUnwrap(e.dimensionMotion)
            guard case .object(let f)? = m.fixed, case .object(let end)? = f[over ? "b" : "a"] else { return XCTFail("fixed \(String(describing: m.fixed))") }
            XCTAssertEqual(end["part"], .string("carrier"))
            XCTAssertNil(m.fixedNote)
            XCTAssertFalse(m.repair.contains("4000.0000018"), m.repair)
            try assertActionsParse(m.repair, spin: !over)
            XCTAssertEqual(m.repair.hasPrefix("Replace its anchors with "), over, m.repair)
            let r = try applying(t, try XCTUnwrap(m.fixed))
            XCTAssertTrue(r.ok, r.reason ?? "")
        }
    }

    /// The same chain with no still part above it (`t1` at the root, x = 4000): no replacement validates. The structured
    /// `fixed` is null and `fixedNote` says why; the constant line keeps `"spin": 0` alone; the `over` line has no
    /// action and says to hold the end on a still part.
    func testNoValidRepairIsDropped() throws {
        for (t, over) in [(Self.farConstant, false), (Self.farOver, true)] {
            let root = t.replacingOccurrences(of: #""parent":"carrier","#, with: "").replacingOccurrences(of: #""at":[0,-100,0],"drive""#, with: #""at":[4000,-100,0],"drive""#)
            XCTAssertNotEqual(root, t)
            let m = try XCTUnwrap(refusal(root)?.dimensionMotion)
            XCTAssertNil(m.fixed)
            XCTAssertEqual(m.fixedNote, "world points are refused (`anchor.world`)")
            XCTAssertFalse(m.repair.contains("{"), m.repair)
            XCTAssertTrue(m.repair.contains("No fixed anchor: world points are refused"), m.repair)
            try assertActionsParse(m.repair, spin: !over)
            if over { XCTAssertTrue(m.repair.contains("Hold that end on a part that does not move."), m.repair) }
            guard case .object(let detail)? = strict(root).json["dimensionMotion"] else { return XCTFail("detail") }
            XCTAssertEqual(detail["fixed"], .null)
        }
    }

    /// The #53 gravity repair has the same check: an end at x = 4000.0000018 cannot be a world point, so `fixed` is null
    /// with `fixedNote`, and the line keeps `"spin": 0`.
    func testAnUnrepresentableGravityRepairIsDropped() throws {
        let t = Self.farConstant.replacingOccurrences(of: #""annotations":{"dimensions":[{"a":{"offset":[-1.8e-06,0,0],"part":"t8"},"b":{"world":[50,-100,0]},"id":"gap"}]}"#,
                                                     with: #""annotations":{"arrows":[{"id":"w","meaning":"force","cause":"gravity","from":{"world":[4000,-100,100]},"to":{"part":"t8","offset":[-1.8e-06,0,0]}}]}"#)
            .replacingOccurrences(of: #""annotate":["gap"]"#, with: #""annotate":["w"]"#).replacingOccurrences(of: "The gap is {dim.gap}.", with: "Weight points down.")
        XCTAssertNotEqual(t, Self.farConstant)
        let e = try XCTUnwrap(refusal(t))
        XCTAssertEqual(e.reason, "annotation.pose.w")
        let c = try XCTUnwrap(e.centreOfMass)
        XCTAssertFalse(c.fixedVerified)
        XCTAssertEqual(c.fixedNote, "they are refused (`anchor.world`)")
        XCTAssertFalse(c.repair.contains("4000.0000018"), c.repair)
        try assertActionsParse(c.repair)
        guard case .object(let detail)? = strict(t).json["centreOfMass"] else { return XCTFail("detail") }
        XCTAssertEqual(detail["fixed"], .null)
    }

    /// The review's angle with 24-character ids and full-precision coordinates: the old line was cut inside its JSON and
    /// lost `"spin": 0`. Now `"spin": 0` comes first, the replacement is whole or named as `fixed`, and only the
    /// explanation is cut. Every action in the line parses, and the structured replacement passes strict when applied.
    func testALongAngleRepairKeepsEveryActionWhole() throws {
        let m = try XCTUnwrap(refusal(Self.longIds)?.dimensionMotion)
        XCTAssertEqual(m.unit, "°")
        try assertActionsParse(m.repair)
        XCTAssertTrue(m.repair.contains("replace its anchors with {") || m.repair.contains("(see fixed)"), m.repair)
        let r = try applying(Self.longIds, try XCTUnwrap(m.fixed), id: "dddddddddddddddddddddddd")
        XCTAssertTrue(r.ok, r.reason ?? "")
    }

    /// The review's minimum-arm angle: its arm is 0.010000000000001 mm and its end moves by up to about 1.2e-10 mm, so the
    /// arm can fall below the 0.01 mm a measured angle needs (sampled: 0.009999999999857 mm; 19 250 of 20 001 samples had
    /// no value). Before: strict passed. Now the arm bound requires the arm to stay at least 0.01 mm long: refused.
    func testAnAngleArmThatCanFallBelowTheMinimumIsRefused() throws {
        let e = try XCTUnwrap(refusal(Self.minimumArm), "an arm that can leave the measurable range was accepted")
        XCTAssertEqual(e.reason, "annotation.pose.gap")
        XCTAssertEqual(e.dimensionMotion?.change, 180)
    }
}

extension DimensionMotionBoundTests {
    /// The #53 gravity line with 24-character ids and full-precision coordinates: `"spin": 0` first, the fixed points
    /// whole (or named as `fixed`), only the explanation cut.
    func testALongGravityRepairKeepsEveryActionWhole() throws {
        let id = String(repeating: "r", count: 24), arrow = String(repeating: "w", count: 24)
        let t = #"{"v": 2, "kind": "assembly", "parts": [{"id": "\#(id)", "shape": {"box": {"size": [20, 20, 20], "at": [100.12345678901234, 0, 0]}}, "joint": {"revolute": [0, 0, 1]}, "drive": {"input": 1}, "offAxis": true}], "annotations": {"arrows": [{"id": "\#(arrow)", "meaning": "force", "cause": "gravity", "from": {"point": "centreOfMass", "offset": [0, -100.12345678901234, 0]}, "to": {"world": [100.12345678901234, -100.12345678901234, -100.12345678901234]}}]}, "steps": [{"say": "Weight points down.", "camera": "front", "spin": 0.25, "annotate": ["\#(arrow)"]}]}"#
        let c = try XCTUnwrap(refusal(t)?.centreOfMass)
        XCTAssertTrue(c.fixedVerified)
        try assertActionsParse(c.repair)
        XCTAssertTrue(c.repair.contains("fixed points: {") || c.repair.contains("(see fixed)"), c.repair)
    }
}
