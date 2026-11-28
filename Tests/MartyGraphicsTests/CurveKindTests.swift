// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import MartyGraphics

/// The additive 2D kind `curve` (docs/PROTOCOL.md, "Parametric and polar curves"): engine sampling against closed forms
/// (circle, ellipse, cardioid, roses), the aspect-correct frame, gaps and poles, refusals and their bounds, motion,
/// step edits and blends, the wire form, the expression budget and the text alternative. Foundation only, so it also
/// runs off Apple platforms.
final class CurveKindTests: XCTestCase {
    private func scene(_ json: String) throws -> MGScene { try MGParser.scene(data: Data(json.utf8)).get() }
    private func curve(_ keys: String, frame: String = #""at":[1,1],"w":4,"h":4"#) throws -> MGItem {
        try XCTUnwrap(try scene(#"{"v":1,"items":[{"id":"c","k":"curve","# + frame + "," + keys + "}]}").items.first)
    }
    private func reason(_ json: String) -> String? {
        if case .failure(let e) = MGParser.scene(data: Data(json.utf8)) { return e.reason }
        return nil
    }
    private func reason(item keys: String) -> String? {
        reason(#"{"v":1,"items":[{"id":"c","k":"curve","at":[1,1],"w":4,"h":4,"# + keys + "}]}")
    }
    private func fixture(_ id: String) throws -> MGScene { try XCTUnwrap(MGFixtures.all.first { $0.id == id }?.scene) }

    /// θ of sample `i` of a curve without gaps (every sample is a grid value).
    private func theta(_ c: MGItem, _ i: Int) -> Double { MGGraph.gridT(i, c.n("th0"), c.n("th1")) }

    // MARK: closed forms

    func testACircleIsSampledOnItsClosedForm() throws {
        let c = try curve(#""xr":[-1.5,1.5],"yr":[-1.5,1.5],"x":"cos(theta)","y":"sin(theta)""#)
        XCTAssertEqual(c.kind, .curve)
        XCTAssertEqual(c.pts.count, 1 + MGLimits.curveIntervals + 1)
        XCTAssertEqual(c.marked, [])
        XCTAssertFalse(c.has("polar"))
        XCTAssertEqual(c.color, .accent)
        for (i, p) in c.pts.dropFirst().enumerated() {
            XCTAssertEqual(MGGraph.length(p.x, p.y), 1, accuracy: 1e-12, "on the unit circle at sample \(i)")
            XCTAssertEqual(p.x, cos(theta(c, i)), accuracy: 1e-12)
            XCTAssertEqual(p.y, sin(theta(c, i)), accuracy: 1e-12)
        }
        // θ runs from exactly 0 to exactly 2π, so the circle closes.
        XCTAssertEqual(c.pts[1], MGPoint(1, 0))
        XCTAssertEqual(c.pts.last!.x, 1, accuracy: 1e-15)
        XCTAssertEqual(c.pts.last!.y, 0, accuracy: 1e-15)
        XCTAssertTrue(MGGraph.isClosed(c))
        XCTAssertEqual([c.n("th0"), c.n("th1")], [0, 2 * Double.pi], "the default theta range")
    }

    func testAnEllipseKeepsItsShapeInAnAspectCorrectFrame() throws {
        // A 4 × 4 frame for x in ±2.2 and y in ±1.2: the y range widens to ±2.2 so the ellipse is not stretched.
        let c = try curve(#""xr":[-2.2,2.2],"yr":[-1.2,1.2],"x":"2*cos(theta)","y":"sin(theta)","mark":0.7"#)
        XCTAssertEqual([c.n("x0"), c.n("x1"), c.n("y0"), c.n("y1")], [-2.2, 2.2, -2.2, 2.2])
        XCTAssertEqual([c.n("rx0"), c.n("rx1"), c.n("ry0"), c.n("ry1")], [-2.2, 2.2, -1.2, 1.2], "the given ranges are kept")
        for p in c.pts.dropFirst() { XCTAssertEqual(p.x * p.x / 4 + p.y * p.y, 1, accuracy: 1e-12) }
        XCTAssertEqual(try XCTUnwrap(c.num["mx"]), 2 * cos(0.7), accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(c.num["my"]), sin(0.7), accuracy: 1e-12)
        // A frame of the same proportions as the ranges is left as given.
        let fitted = try curve(#""xr":[-2,2],"yr":[-1,1],"x":"2*cos(theta)","y":"sin(theta)""#, frame: #""at":[1,1],"w":4,"h":2"#)
        XCTAssertEqual([fitted.n("x0"), fitted.n("x1"), fitted.n("y0"), fitted.n("y1")], [-2, 2, -1, 1])
        // One data unit is as long across as up.
        for item in [c, fitted] {
            let across = item.n("w") / (item.n("x1") - item.n("x0")), up = item.n("h") / (item.n("y1") - item.n("y0"))
            XCTAssertEqual(across, up, accuracy: 1e-12)
        }
        // A tall frame widens x instead.
        let tall = MGGraph.curveWindow((-1, 1), (-1, 1), w: 2, h: 4)
        XCTAssertEqual([tall.x0, tall.x1, tall.y0, tall.y1], [-1, 1, -2, 2])
        let wide = MGGraph.curveWindow((0, 1), (-1, 1), w: 4, h: 2)
        XCTAssertEqual([wide.x0, wide.x1, wide.y0, wide.y1], [-1.5, 2.5, -1, 1])
    }

    func testACardioidMatchesItsClosedForm() throws {
        let c = try curve(#""xr":[-0.6,2.2],"yr":[-1.4,1.4],"r":"1 + cos(theta)""#)
        XCTAssertTrue(c.has("polar"))
        XCTAssertEqual(c.pts.count - 1, 257)
        for (i, p) in c.pts.dropFirst().enumerated() {
            let t = theta(c, i), k = cos(t)
            // x = cos θ + cos² θ, y = sin θ (1 + cos θ); and the implicit form (x² + y² − x)² = x² + y².
            XCTAssertEqual(p.x, k + k * k, accuracy: 1e-12)
            XCTAssertEqual(p.y, sin(t) * (1 + k), accuracy: 1e-12)
            let rr = p.x * p.x + p.y * p.y
            XCTAssertEqual((rr - p.x) * (rr - p.x), rr, accuracy: 1e-12)
        }
        XCTAssertEqual(c.pts[1], MGPoint(2, 0))
        XCTAssertEqual(MGGraph.length(c.pts[129].x, c.pts[129].y), 0, accuracy: 1e-15, "the cusp at θ = π")
        XCTAssertTrue(MGGraph.isClosed(c))
    }

    func testRosesHaveTheirPetalsAndClose() throws {
        // r = cos 3θ over [0, π]: three petals, traced once; cos 3θ = 4 cos³ θ − 3 cos θ.
        let three = try curve(#""xr":[-1.1,1.1],"yr":[-1.1,1.1],"r":"cos(3*theta)","theta":[0,3.141592653589793]"#)
        var tips = 0
        for (i, p) in three.pts.dropFirst().enumerated() {
            let t = theta(three, i), k = cos(t), r = 4 * k * k * k - 3 * k
            XCTAssertEqual(p.x, r * k, accuracy: 1e-12)
            XCTAssertEqual(p.y, r * sin(t), accuracy: 1e-12)
            if MGGraph.length(p.x, p.y) > 0.9999 { tips += 1 }
        }
        XCTAssertEqual(tips, 3 + 1, "the tips at θ = 0, π/3, 2π/3 and the start again at θ = π")
        XCTAssertTrue(MGGraph.isClosed(three))
        // r = cos 2θ over [0, 2π]: four petals; cos 2θ = cos² θ − sin² θ.
        let four = try curve(#""xr":[-1.1,1.1],"yr":[-1.1,1.1],"r":"cos(2*theta)""#)
        var through = 0
        for (i, p) in four.pts.dropFirst().enumerated() {
            let t = theta(four, i), r = cos(t) * cos(t) - sin(t) * sin(t)
            XCTAssertEqual(p.x, r * cos(t), accuracy: 1e-12)
            XCTAssertEqual(p.y, r * sin(t), accuracy: 1e-12)
            if MGGraph.length(p.x, p.y) < 1e-12 { through += 1 }
        }
        XCTAssertEqual(through, 4, "the curve passes through the origin between petals")
        XCTAssertTrue(MGGraph.isClosed(four))
        // Parameters as in `func`: a·cos(bθ) with b = 5 is a five-petal rose.
        let five = try curve(#""xr":[-1.2,1.2],"yr":[-1.2,1.2],"r":"a*cos(b*theta)","a":1,"b":5"#)
        for (i, p) in five.pts.dropFirst().enumerated() {
            XCTAssertEqual(MGGraph.length(p.x, p.y), abs(cos(5 * theta(five, i))), accuracy: 1e-12)
        }
    }

    // MARK: gaps and poles

    func testPolesBreakTheCurveAndNoChordCrossesTheView() throws {
        // r = 1/cos θ is the line x = 1, with poles at θ = π/2 and 3π/2.
        let line = try curve(#""xr":[-3,3],"yr":[-3,3],"r":"1/cos(theta)""#)
        XCTAssertEqual(line.marked, [65, 193])
        let window = MGGraph.Window(line), samples = Array(line.pts.dropFirst())
        for p in samples where MGGraph.length(p.x, p.y) < 1e6 { XCTAssertEqual(p.x, 1, accuracy: 1e-9) }
        for r in MGGraph.pieces(samples.count, starts: line.marked) {
            for (a, b) in zip(samples[r], samples[r].dropFirst()) where !window.contains(a) && !window.contains(b) {
                XCTAssertFalse(window.crosses(a, b), "a chord between two far points crosses the view")
            }
        }
        // A hyperbola r = 1/(1 − 2 cos θ) jumps between its branches at θ = ±π/3.
        let hyperbola = try curve(#""xr":[-3,3],"yr":[-3,3],"r":"1/(1 - 2*cos(theta))""#)
        XCTAssertEqual(hyperbola.marked, [43, 214])
        // Points far outside the view are kept within ±10¹² in their own direction.
        let far = MGGraph.clampPoint(MGPoint(4e15, -1e15))
        XCTAssertEqual(far.x, 1e12)
        XCTAssertEqual(far.y, -0.25e12)
        XCTAssertEqual(MGGraph.clampPoint(MGPoint(3, 4)), MGPoint(3, 4))
    }

    func testGapsAreSplitAndAHoleStaysOpen() throws {
        // √(cos 2θ) has no value where cos 2θ < 0: a lemniscate drawn in three pieces (the right lobe is split at θ = 0).
        let lemniscate = try curve(#""xr":[-1.2,1.2],"yr":[-0.8,0.8],"r":"sqrt(cos(2*theta))""#)
        XCTAssertEqual(lemniscate.pts.count - 1, 131)
        XCTAssertEqual(lemniscate.marked, [33, 98])
        for p in lemniscate.pts.dropFirst() {
            let rr = p.x * p.x + p.y * p.y
            XCTAssertEqual(rr * rr, p.x * p.x - p.y * p.y, accuracy: 1e-12, "(x² + y²)² = x² − y²")
        }
        // r = 1/θ has no value at θ = 0, a grid value: the piece ends one probe before it and the next starts one after.
        let spiral = try curve(#""xr":[-2,2],"yr":[-2,2],"r":"1/theta","theta":[-3,3]"#)
        XCTAssertEqual(spiral.marked, [129])
        XCTAssertEqual(spiral.pts.count - 1, 258)
    }

    func testClippingKeepsOnlyTheVisibleRuns() {
        let window = MGGraph.Window(x0: 0, x1: 1, y0: 0, y1: 1)
        let runs = MGGraph.clipped([MGPoint(-1, 0.5), MGPoint(0.5, 0.5), MGPoint(0.5, 2), MGPoint(0.75, 0.25)], to: window)
        XCTAssertEqual(runs, [[MGPoint(0, 0.5), MGPoint(0.5, 0.5), MGPoint(0.5, 1)],
                              [MGPoint(0.5 + 0.25 / 1.75, 1), MGPoint(0.75, 0.25)]])
        XCTAssertEqual(MGGraph.clipped([MGPoint(2, 2), MGPoint(3, 3)], to: window), [])
        XCTAssertEqual(MGGraph.clipped([MGPoint(0.2, 0.2), MGPoint(0.4, 0.4), MGPoint(0.6, 0.2)], to: window),
                       [[MGPoint(0.2, 0.2), MGPoint(0.4, 0.4), MGPoint(0.6, 0.2)]], "inside, the polyline is unchanged")
        XCTAssertEqual(MGGraph.clipped([MGPoint(.nan, 0.5), MGPoint(0.5, 0.5), MGPoint(0.6, 0.6)], to: window),
                       [[MGPoint(0.5, 0.5), MGPoint(0.6, 0.6)]], "a point that is not finite (built in code) is skipped")
        XCTAssertTrue(window.crosses(MGPoint(-1, -1), MGPoint(2, 2)))
        XCTAssertTrue(window.crosses(MGPoint(-1, 0), MGPoint(1, 2)), "touching a corner counts")
        XCTAssertFalse(window.crosses(MGPoint(-1, 1.5), MGPoint(1, 3.5)))
    }

    func testOnlyASegmentOfNonzeroLengthInsideTheWindowIsVisible() {
        let window = MGGraph.Window(x0: 0, x1: 1, y0: 0, y1: 1)
        func draws(_ pts: [MGPoint], _ starts: [Int] = []) -> Bool { MGGraph.drawsSegment(pts, starts: starts, in: window) }
        XCTAssertTrue(draws([MGPoint(0.2, 0.2), MGPoint(0.4, 0.4)]))
        XCTAssertTrue(draws([MGPoint(-1, 0.5), MGPoint(2, 0.5)]), "a chord across the window, both ends outside")
        XCTAssertFalse(draws([MGPoint(0.5, 0.5)]), "one point")
        XCTAssertFalse(draws([MGPoint(0.5, 0.5), MGPoint(2, 2), MGPoint(0.3, 0.3)], [1, 2]), "one-point pieces")
        XCTAssertFalse(draws([MGPoint(0.5, 0.5), MGPoint(0.5, 0.5), MGPoint(0.5, 0.5)]), "a curve that stays at one point")
        XCTAssertFalse(draws([MGPoint(2, 0.5), MGPoint(1, 0.5), MGPoint(2, 0.6)]), "touching an edge")
        XCTAssertFalse(draws([MGPoint(-1, 0), MGPoint(1, 2)]), "touching a corner")
        XCTAssertTrue(draws([MGPoint(1, 0.2), MGPoint(1, 0.4)]), "along an edge")
        // At parse time: each of these has a point inside the window but draws nothing there.
        for keys in [#""r":"0""#, #""x":"0.5","y":"0.5""#, #""x":"sqrt(-abs(theta - 32))","y":"0","theta":[0,64]"#,
                     #""x":"2 + cos(theta)","y":"sin(theta)""#] {
            XCTAssertEqual(reason(item: #""xr":[-1,1],"yr":[-1,1],"# + keys), "curve.empty", keys)
        }
    }

    // MARK: refusals and limits

    func testTheBoundsAreTheDocumentedOnes() {
        XCTAssertEqual(MGLimits.curveIntervals, 256)
        XCTAssertEqual(MGLimits.curveBreaks, 16)
        XCTAssertEqual(MGLimits.curveWeight, 2)
        XCTAssertEqual(MGLimits.curveEnd, 1000)
        XCTAssertEqual(MGLimits.curveSpan, 0.001...100)
        XCTAssertEqual(MGLimits.curveTolerance, 0.01)
        // The span bound is what 256 steps can draw: the chord of a unit circle in a window of ±1.05 (the circle fills
        // the frame) at 100 rad / 256 per step is within the tolerance (the parse below shows it), at 0.4 rad it is not.
        let step = MGLimits.curveSpan.upperBound / Double(MGLimits.curveIntervals)
        XCTAssertLessThan((1 - cos(step / 2)) / 2.1, MGLimits.curveTolerance)
        XCTAssertGreaterThan((1 - cos(0.42 / 2)) / 2.1, MGLimits.curveTolerance)
        // A gap probe stays well above the spacing of doubles at the largest end.
        XCTAssertGreaterThan(MGLimits.curveSpan.lowerBound / Double(MGLimits.curveIntervals) / 1024, 1e4 * MGLimits.curveEnd.ulp)
        // Three moving parametric curves fill the budget of six moving graphs.
        XCTAssertEqual(MGLimits.exprItems / MGLimits.curveWeight, 3)
    }

    func testRefusalsNameTheKeyToRepair() {
        let cases: [(String, String)] = [
            (#""xr":[-2,2],"yr":[-2,2]"#, "curve.form"),
            (#""xr":[-2,2],"yr":[-2,2],"x":"cos(theta)","y":"sin(theta)","r":"1""#, "curve.form"),
            (#""xr":[-2,2],"yr":[-2,2],"y":"sin(theta)""#, "curve.form"),
            (#""xr":[-2,2],"yr":[-2,2],"x":"cos(x)","y":"sin(theta)""#, "curve.x.var.x"),
            (#""xr":[-2,2],"yr":[-2,2],"r":"1 + t""#, "curve.r.var.t"),
            (#""xr":[-2,2],"yr":[-2,2],"r":"cos(θ)""#, "curve.r"),
            (#""xr":[-2,2],"yr":[-2,2],"r":"cos(thetaa)""#, "curve.r.name"),
            (#""xr":[-2,2],"yr":[-2,2],"r":"1","period":2"#, "curve.period"),
            (#""xr":[-2,2],"yr":[-2,2],"r":"1","theta":[0,100.5]"#, "curve.theta"),
            (#""xr":[-2,2],"yr":[-2,2],"r":"1","theta":[0,0.0009]"#, "curve.theta"),
            (#""xr":[-2,2],"yr":[-2,2],"r":"1","theta":[-1001,0]"#, "curve.theta"),
            (#""xr":[-2,2],"yr":[-2,2],"r":"1","theta":[1,0]"#, "curve.theta"),
            (#""xr":[-2,2],"yr":[-2,2],"r":"1","mark":-0.1"#, "curve.mark"),
            (#""xr":[-2,2],"yr":[-2,2],"x":"3*cos(theta)","y":"sin(theta)","mark":0"#, "curve.mark"),
            (#""xr":[-2,2],"yr":[-2,2],"r":"cos(90*theta)""#, "curve.detail"),
            (#""xr":[-1.2,1.2],"yr":[-1.2,1.2],"r":"1/cos(10*theta)""#, "curve.breaks"),
            (#""xr":[-1,1],"yr":[-1,1],"x":"5 + cos(theta)","y":"sin(theta)""#, "curve.empty"),
            (#""xr":[-1.5,1.5],"yr":[-1.5,1.5],"x":"cos(theta - t)","y":"sin(theta - t)","period":4"#, "curve.loop"),
            (#""xr":[-2,2],"yr":[-2,2],"r":"1","shade":[0,1]"#, "item.curve.unknown.shade"),
            (#""xr":[-2,2],"r":"1""#, "item.curve.missing")
        ]
        for (keys, want) in cases { XCTAssertEqual(reason(item: keys), want, keys) }
        // The span bounds are inclusive.
        XCTAssertNil(reason(item: #""xr":[-100,100],"yr":[-100,100],"r":"theta","theta":[0,100]"#))
        XCTAssertNil(reason(item: #""xr":[-2,2],"yr":[-2,2],"r":"1","theta":[0,0.001]"#))
        XCTAssertNil(reason(item: #""xr":[-1.05,1.05],"yr":[-1.05,1.05],"x":"cos(theta)","y":"sin(theta)","theta":[0,100]"#))
        XCTAssertEqual(reason(item: #""xr":[-1.05,1.05],"yr":[-1.05,1.05],"x":"cos(1.2*theta)","y":"sin(1.2*theta)","theta":[0,100]"#), "curve.detail")
        // `theta` is a curve variable only.
        XCTAssertEqual(reason(#"{"v":1,"items":[{"id":"f","k":"func","at":[1,1],"w":6,"h":4,"xr":[-3,3],"yr":[-2,2],"y":"sin(theta)"}]}"#), "func.y.var.theta")
        XCTAssertEqual(reason(#"{"v":1,"items":[{"id":"v","k":"field","at":[1,1],"w":6,"h":4,"xr":[-2,2],"yr":[-2,2],"dx":"theta","dy":"1"}]}"#), "field.dx.var.theta")
    }

    func testACurveCountsTwiceTowardTheExpressionBudget() throws {
        let one = #"{"id":"cID","k":"curve","at":[1,1],"w":3,"h":3,"xr":[-1.5,1.5],"yr":[-1.5,1.5],"x":"a*cos(theta + 2*pi*t/4)","y":"sin(b*theta + 2*pi*t/4)","a":1,"b":2,"period":4,"mark":1}"#
        let three = (1...3).map { one.replacingOccurrences(of: "cID", with: "c\($0)") }.joined(separator: ",")
        let start = Date()
        let s = try scene(#"{"v":1,"items":["# + three + "]}")
        let seconds = Date().timeIntervalSince(start)
        XCTAssertEqual(s.items.count, 3)
        // Pending Mac measurement: record this line in the receipt. The bound is deliberately generous.
        print("MGCURVE three moving parametric curves parsed in \(seconds) s")
        XCTAssertLessThan(seconds, 2)
        let func1 = #"{"id":"f","k":"func","at":[1,1],"w":2,"h":2,"xr":[-1,1],"yr":[-1,1],"y":"x"}"#
        XCTAssertEqual(reason(#"{"v":1,"items":["# + three + "," + func1 + "]}"), "items.expr")
        XCTAssertEqual(reason(#"{"v":1,"items":["# + three + "," + one.replacingOccurrences(of: "cID", with: "c4") + "]}"), "items.expr")
        let two = (1...2).map { one.replacingOccurrences(of: "cID", with: "c\($0)") }.joined(separator: ",")
        let funcs = (1...2).map { func1.replacingOccurrences(of: #""f""#, with: "\"f\($0)\"") }.joined(separator: ",")
        XCTAssertEqual(try scene(#"{"v":1,"items":["# + two + "," + funcs + "]}").items.count, 4, "2 × 2 + 2 = 6")
        // The weights the count reads before any item is evaluated: a wire entry, a template item and one edit.
        let none: Set<String> = []
        let curveEntry: MGJSON = .object(["id": .string("c"), "k": .string("curve")])
        let funcEntry: MGJSON = .object(["id": .string("f"), "k": .string("func")])
        let bodyEntry: MGJSON = .object(["id": .string("b"), "k": .string("body")])
        XCTAssertEqual(MGLimits.curveWeight, 2)
        XCTAssertEqual(MGParser.exprWeight(curveEntry, readouts: none), MGLimits.curveWeight)
        XCTAssertEqual(MGParser.exprWeight(funcEntry, readouts: none), 1)
        XCTAssertEqual(MGParser.exprWeight(bodyEntry, readouts: none), 0)
        let curveItem = MGItem(id: "c", kind: .curve, color: .accent)
        XCTAssertEqual(MGParser.exprWeight(curveItem, readouts: none), MGLimits.curveWeight)
        let curves: Set<String> = ["c"]
        XCTAssertEqual(MGParser.editWeight("c", key: "a", readouts: none, curves: curves), MGLimits.curveWeight)
        XCTAssertEqual(MGParser.editWeight("c", key: "color", readouts: none, curves: curves), MGLimits.curveWeight,
                       "any edit checks the whole curve again")
        XCTAssertEqual(MGParser.editWeight("f", key: "a", readouts: none, curves: curves), 1)
    }

    func testEachEditOfACurveCountsTwiceTowardTheExpressionBudget() throws {
        let still = #"{"id":"c","k":"curve","at":[1,1],"w":4,"h":4,"xr":[-5,5],"yr":[-5,5],"r":"a","a":1}"#
        func withEdits(_ count: Int) -> String {
            var edits: [String] = []
            for k in 0..<count { edits.append(#"{"id":"c","key":"a","value":\#(k + 2)}"#) }
            let list = edits.joined(separator: ",")
            return #"{"v":1,"items":[\#(still)],"steps":[{"say":"one"},{"say":"two","do":[\#(list)]}]}"#
        }
        let raw = try JSONSerialization.jsonObject(with: Data(withEdits(2).utf8))
        let json = try XCTUnwrap(MGJSON(any: raw))
        let o = try XCTUnwrap(json.objectValue)
        let curves = MGParser.curveGraphs(o, templateItems: [])
        XCTAssertEqual(curves, ["c"])
        let none: Set<String> = []
        let counted = MGParser.graphEdits(o, templateGraphs: [], templateSteps: []) {
            MGParser.editWeight($0, key: $1, readouts: none, curves: curves)
        }
        XCTAssertEqual(counted, 4, "two edits of a curve weigh 2 each")
        // One curve (2) and two edits of it (2 × 2) fill the six graph checks; a third edit is one too many.
        let full = try scene(withEdits(2))
        XCTAssertEqual(full.items.count, 1)
        XCTAssertEqual(reason(withEdits(3)), "items.expr")
        // A func in its place weighs 1 per edit, so the same three edits fit.
        let asFunc = withEdits(3).replacingOccurrences(of: #""k":"curve""#, with: #""k":"func""#)
            .replacingOccurrences(of: #""r":"a""#, with: #""y":"a*x/5""#)
        XCTAssertNil(reason(asFunc))
    }

    // MARK: motion, steps and the wire

    func testAMovingCurveIsResampledAtItsLoopTime() throws {
        let s = try scene(#"{"v":1,"items":[{"id":"c","k":"curve","at":[1,1],"w":4,"h":4,"xr":[-1.5,1.5],"yr":[-1.5,1.5],"x":"cos(theta + 2*pi*t/4)","y":"sin(theta + 2*pi*t/4)","period":4,"mark":0}]}"#)
        XCTAssertTrue(s.animates)
        XCTAssertEqual(MGTimeline.cycle(s), 4)
        XCTAssertEqual(MGTimeline.frame(s, items: s.items, time: 0), s.items, "t = 0 is the parsed curve")
        let c = try XCTUnwrap(s.items.first)
        XCTAssertEqual(try XCTUnwrap(c.num["mx"]), 1, accuracy: 1e-12)
        let one = try XCTUnwrap(MGTimeline.frame(s, items: s.items, time: 1).first)
        // A quarter period later the marked point (θ = 0) has turned a quarter turn.
        XCTAssertEqual(try XCTUnwrap(one.num["mx"]), 0, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(one.num["my"]), 1, accuracy: 1e-12)
        for (i, p) in one.pts.dropFirst().enumerated() {
            XCTAssertEqual(p.x, cos(theta(c, i) + Double.pi / 2), accuracy: 1e-12)
        }
        XCTAssertEqual(MGTimeline.frame(s, items: s.items, time: 0.5), MGTimeline.frame(s, items: s.items, time: 4.5))
        XCTAssertNotEqual(MGTimeline.frame(s, items: s.items, time: 0.5), MGTimeline.frame(s, items: s.items, time: 1.5))
        // A marked point that leaves the window between checked instants is dropped, never kept from t = 0.
        let leaving = try scene(#"{"v":1,"items":[{"id":"c","k":"curve","at":[1,1],"w":4,"h":4,"xr":[-1.5,1.5],"yr":[-1.5,1.5],"x":"cos(theta) + 3*sin(pi*t)","y":"sin(theta)","period":4,"mark":0}]}"#)
        let l = try XCTUnwrap(leaving.items.first)
        XCTAssertNotNil(l.num["mx"])
        XCTAssertNil(MGGraph.animatedCurve(l, at: 0.5).num["mx"], "outside the window at t = 0.5")
        // A still curve is never resampled.
        let still = try scene(#"{"v":1,"items":[{"id":"c","k":"curve","at":[1,1],"w":4,"h":4,"xr":[-1.5,1.5],"yr":[-1.5,1.5],"r":"1"}]}"#)
        XCTAssertFalse(still.animates)
        XCTAssertNil(MGTimeline.cycle(still))
        XCTAssertEqual(MGTimeline.frame(still, items: still.items, time: 3), still.items)
    }

    func testStepEditsResampleAndTheBlendMorphsTheCurve() throws {
        let s = try fixture("curves")
        let before = try XCTUnwrap(MGTimeline.items(s, step: 0).first { $0.id == "circle" })
        let after = try XCTUnwrap(MGTimeline.items(s, step: 1).first { $0.id == "circle" })
        XCTAssertEqual(before.pts.count, after.pts.count)
        for (p, q) in zip(before.pts.dropFirst(), after.pts.dropFirst()) {
            XCTAssertEqual(q.x, 0.6 * p.x, accuracy: 1e-12)
            XCTAssertEqual(q.y, 0.6 * p.y, accuracy: 1e-12)
        }
        XCTAssertEqual(try XCTUnwrap(after.num["mx"]), 0.6 * cos(1.0472), accuracy: 1e-12)
        let mid = try XCTUnwrap(MGTimeline.blend(from: [before], to: [after], t: 0.5).first)
        for (p, q) in zip(before.pts.dropFirst(), mid.pts.dropFirst()) { XCTAssertEqual(q.x, 0.8 * p.x, accuracy: 1e-12) }
        // Patches get the same checks: the limacon patch applies, a broken expression does not.
        let limacon = try XCTUnwrap(MGFixtures.patches.first { $0.id == "curves_limacon" })
        let patched = try s.applying(MGPatch.parse(data: Data(limacon.json.utf8)).get()).get()
        XCTAssertEqual(patched.item("heart")?.list.last, "0.5 + cos(theta)")
        let broken = try MGPatch.parse(data: Data(#"{"v":1,"ops":[{"op":"set","id":"heart","key":"r","value":"cos(theta"}]}"#.utf8)).get()
        guard case .failure(let e) = s.applying(broken) else { return XCTFail("a broken expression must not apply") }
        XCTAssertEqual(e.reason, "curve.r.syntax")
        let second = try MGPatch.parse(data: Data(#"{"v":1,"ops":[{"op":"set","id":"heart","key":"x","value":"cos(theta)"}]}"#.utf8)).get()
        guard case .failure(let f) = s.applying(second) else { return XCTFail("a second form must not apply") }
        XCTAssertEqual(f.reason, "curve.form")
    }

    func testTheWireFormRoundTripsWithTheGivenRanges() throws {
        let s = try fixture("curves")
        let ctx = MGContext(width: s.width, height: s.height, is3D: false, values: [:])
        for item in s.items {
            XCTAssertEqual(try MGParser.item(.object(item.wire()), ctx), item, item.id)
            XCTAssertNil(item.wire()["pts"], item.id)
        }
        let heart = try XCTUnwrap(s.item("heart"))
        XCTAssertEqual(heart.wire()["r"], .string("1 + cos(theta)"))
        XCTAssertNil(heart.wire()["x"])
        XCTAssertEqual(heart.wire()["yr"], .array([.number(-1.4), .number(1.4)]))
        XCTAssertEqual(heart.wire()["theta"], .array([.number(0), .number(2 * Double.pi)]))
        let rebuilt: [String: Any] = ["v": 1, "items": s.items.map { MGJSON.object($0.wire()).any }]
        XCTAssertEqual(try MGParser.scene(object: rebuilt).get().items, s.items)
        // Streaming previews end in the strict parse.
        for seed in UInt64(1)...3 {
            var parser = MGStreamParser()
            for chunk in MGRegression.chunks(try XCTUnwrap(MGFixtures.all.first { $0.id == "curves" }?.json), seed: seed) { _ = parser.feed(chunk) }
            XCTAssertEqual(try parser.finish().get(), s, "seed \(seed)")
        }
    }

    // MARK: text alternative, layout, 3D and items built in code

    func testTheDescriptionNamesTheFormTheRangesAndTheMarkedPoint() throws {
        let s = try fixture("curves")
        let circle = try XCTUnwrap(s.item("circle")), heart = try XCTUnwrap(s.item("heart"))
        XCTAssertEqual(MGDescribe.item(circle, in: s.items),
                       "a closed parametric curve x = a*cos(theta), y = a*sin(theta) labelled “x = a cos(theta), y = a sin(theta)” "
                       + "for theta from 0 to 6.28, x from -1.25 to 1.25 and y from -1.25 to 1.25 with a = 1, "
                       + "marking the point (0.5, 0.87) at theta = 1.05")
        XCTAssertEqual(MGDescribe.item(heart, in: s.items),
                       "a closed polar curve r = 1 + cos(theta) labelled “r = 1 + cos(theta)” for theta from 0 to 6.28, "
                       + "x from -0.6 to 2.2 and y from -1.4 to 1.4")
        XCTAssertEqual(MGDescribe.board(s, step: 1),
                       "A closed parametric curve x = a*cos(theta), y = a*sin(theta) labelled “x = a cos(theta), y = a sin(theta)” "
                       + "for theta from 0 to 6.28, x from -1.25 to 1.25 and y from -1.25 to 1.25 with a = 0.6, "
                       + "marking the point (0.3, 0.52) at theta = 1.05; a closed polar curve r = 1 + cos(theta) labelled "
                       + "“r = 1 + cos(theta)” for theta from 0 to 6.28, x from -0.6 to 2.2 and y from -1.4 to 1.4.")
        // The author's text wins (step 2 has no `alt`, so the scene's is read); the engine's description is the fallback.
        XCTAssertTrue(MGDescribe.accessibilityValue(s, step: 2, describing: true)
            .hasPrefix("A polar curve: r = 1 + cos(theta) is a cardioid. A circle of radius 1"))
        let line = try curve(#""xr":[-3,3],"yr":[-3,3],"r":"1/cos(theta)","theta":[-3,3]"#)
        XCTAssertEqual(MGDescribe.item(line, in: [line]),
                       "a polar curve r = 1/cos(theta) for theta from -3 to 3, x from -3 to 3 and y from -3 to 3, in 3 pieces")
        let moving = try curve(#""xr":[-1.5,1.5],"yr":[-1.5,1.5],"x":"cos(theta + 2*pi*t/4)","y":"sin(theta + 2*pi*t/4)","period":4"#)
        XCTAssertTrue(MGDescribe.item(moving, in: [moving]).hasSuffix(", moving and repeating every 4 s"))
    }

    func testLayoutBoundsAreTheFrameAndCurvesAreTwoDimensionalOnly() throws {
        XCTAssertFalse(MGKind.in3D.contains(.curve))
        XCTAssertEqual(MGKind(rawValue: "curve"), .curve)
        let s = try fixture("curves")
        let vp = MGViewport(size: CGSize(width: 600, height: 400), width: s.width, height: s.height, camera: nil)
        let item = try XCTUnwrap(s.item("circle"))
        let box = try XCTUnwrap(MGLayout.bounds(item, in: s.items, vp))
        XCTAssertEqual(box.width, vp.length(item.n("w")), accuracy: 0.01)
        XCTAssertEqual(box.height, vp.length(item.n("h")), accuracy: 0.01)
        let toDepth = try MGPatch.parse(data: Data(#"{"v":1,"ops":[{"op":"dim","dim":"3d"}]}"#.utf8)).get()
        guard case .failure(let e) = s.applying(toDepth) else { return XCTFail("a curve must not enter 3D") }
        XCTAssertEqual(e.reason, "3d.kind.curve")
    }

    func testItemsBuiltInCodeAreRefusedOrLeftAloneNeverTrapped() throws {
        let ctx = MGContext(width: 12, height: 8, is3D: false, values: [:])
        var bad = MGItem(id: "x", kind: .curve, color: .accent)
        bad.pts = [MGPoint(1, 1)]
        bad.num = ["w": .nan, "h": 4, "x0": 0, "x1": .infinity, "y0": 0, "y1": 1, "th0": 5, "th1": 1]
        bad.marked = [9999, -3]
        XCTAssertThrowsError(try MGParser.item(.object(bad.wire()), ctx))
        XCTAssertFalse(MGDescribe.item(bad, in: [bad]).isEmpty)
        XCTAssertFalse(MGGraph.isClosed(bad))
        XCTAssertEqual(MGGraph.animatedCurve(bad, at: 1), bad, "no expressions: left as it is")
        var odd = try XCTUnwrap(try fixture("curves").item("heart"))
        odd.list[2] = "cos(("
        odd.num["period"] = 2
        XCTAssertEqual(MGGraph.animatedCurve(odd, at: 1), odd)
        XCTAssertEqual(MGGraph.curvePoint([], .init()).x.isNaN, true)
    }

    // MARK: main's board: the layered board, audio graphs, sliders and readouts

    /// G's layered board (`MGCanvasLayers`): a moving curve is sampled again at every tick, like a moving `func`, so it
    /// stays in the live layer and is never cached in the base.
    func testAMovingCurveIsLiveOnTheLayeredBoard() throws {
        let zone = #"{"id":"zone","k":"region","pts":[[1,1],[5,1],[5,4],[1,4]]}"#
        let spin = #"{"id":"spin","k":"curve","at":[1,1],"w":4,"h":4,"xr":[-1.5,1.5],"yr":[-1.5,1.5],"x":"cos(theta + 2*pi*t/4)","y":"sin(theta + 2*pi*t/4)","period":4}"#
        let still = #"{"id":"still","k":"curve","at":[6,1],"w":4,"h":4,"xr":[-1.5,1.5],"yr":[-1.5,1.5],"r":"1"}"#
        let s = try scene(#"{"v":1,"items":[\#(zone),\#(spin),\#(still)]}"#)
        XCTAssertTrue(s.animates)
        let items = MGTimeline.frame(s, items: s.items, time: 0.5)
        let live = MGCanvasLayers.live(s, items: items)
        XCTAssertEqual(live, ["spin"], "the curve with a period is sampled again each tick; the still curve is static")
        let base = MGCanvasLayers.base(items, live: live)
        XCTAssertFalse(base.contains("spin"))
        let curveRank = MGCanvasRenderer.layer[.curve]
        let funcRank = MGCanvasRenderer.layer[.function]
        XCTAssertEqual(curveRank, funcRank, "a curve draws in the graphs' layer")
        // A still curve on a board without motion: nothing is live.
        let calm = try scene(#"{"v":1,"items":[\#(zone),\#(still)]}"#)
        XCTAssertFalse(calm.animates)
        XCTAssertEqual(MGCanvasLayers.live(calm, items: calm.items), [])
    }

    /// Audio graphs play y as x rises, so a curve (not a function of x) is never charted: a board with curves alone has
    /// no audio graph, and a chart's summary says how many curves the board draws beside it.
    func testACurveIsNeverChartedAndTheAudioGraphSummarySaysSo() throws {
        let wave = #"{"id":"f","k":"func","at":[1,1],"w":5,"h":4,"xr":[-3,3],"yr":[-1.5,1.5],"y":"sin(x)"}"#
        let circle = #"{"id":"c","k":"curve","at":[7,1],"w":4,"h":4,"xr":[-1.5,1.5],"yr":[-1.5,1.5],"r":"1"}"#
        let rose = #"{"id":"r","k":"curve","at":[7,5],"w":2,"h":2,"xr":[-1.2,1.2],"yr":[-1.2,1.2],"r":"cos(3*theta)"}"#
        let one = try scene(#"{"v":1,"items":[\#(wave),\#(circle)]}"#)
        let chart = try XCTUnwrap(MGAudioGraph.chart(one))
        let ids: [String] = chart.series.map(\.id)
        XCTAssertEqual(ids, ["f"], "only the func is charted")
        let items = MGTimeline.items(one, step: 0)
        let f = try XCTUnwrap(items.first { $0.id == "f" })
        let phrase = MGDescribe.item(f, in: items)
        let described = MGDescribe.capitalized(phrase) + "."
        XCTAssertEqual(chart.summary, "\(described) One curve on the board is not in this audio graph.")
        let two = try scene(#"{"v":1,"items":[\#(wave),\#(circle),\#(rose)]}"#)
        let both = try XCTUnwrap(MGAudioGraph.chart(two)).summary
        XCTAssertEqual(both, "\(described) 2 curves on the board are not in this audio graph.")
        // Concealed curves are not on the board.
        let concealed = try XCTUnwrap(MGAudioGraph.chart(two, hiding: ["c", "r"])).summary
        XCTAssertEqual(concealed, described)
        // Curves alone: no audio graph; the board's description names each curve.
        let curves = try scene(#"{"v":1,"items":[\#(circle),\#(rose)]}"#)
        XCTAssertNil(MGAudioGraph.chart(curves))
        XCTAssertNil(MGAudioGraph.chart(try fixture("curves")))
        let board = MGDescribe.board(stepItems: MGTimeline.items(curves, step: 0), hiding: [])
        XCTAssertTrue(board.contains("polar curve r = 1"), board)
        XCTAssertTrue(board.contains("polar curve r = cos(3*theta)"), board)
        // A curve first shown at step 1 is counted from step 1.
        let later = try scene(#"{"v":1,"items":[\#(wave),\#(circle)],"steps":[{"say":"A wave.","show":["f"]},{"say":"A circle.","show":["c"]}]}"#)
        let first = try XCTUnwrap(MGAudioGraph.chart(later, step: 0)).summary
        let second = try XCTUnwrap(MGAudioGraph.chart(later, step: 1)).summary
        XCTAssertEqual(first, described)
        XCTAssertEqual(second, "\(described) One curve on the board is not in this audio graph.")
    }

    /// Sliders drive `func` items only. A curve that sets the slider's parameter, or a step edit that sets it on a
    /// curve, is refused; a curve that does not read it stays as parsed while the slider moves.
    func testASliderNeverDrivesACurve() throws {
        let slider = #"{"param":"a","min":0,"max":2,"step":0.5,"default":1,"label":"Slope a"}"#
        let line = #"{"id":"f","k":"func","at":[1,1],"w":10,"h":6,"xr":[-3,3],"yr":[-4,4],"y":"a*x","a":1}"#
        let circle = #"{"id":"c","k":"curve","at":[1,1],"w":4,"h":4,"xr":[-2,2],"yr":[-2,2],"r":"a","a":1}"#
        let still = #"{"id":"c","k":"curve","at":[1,1],"w":4,"h":4,"xr":[-2,2],"yr":[-2,2],"r":"1"}"#
        XCTAssertEqual(reason(#"{"v":1,"items":[\#(line),\#(circle)],"sliders":[\#(slider)]}"#), "slider.curve")
        XCTAssertEqual(reason(#"{"v":1,"items":[\#(circle)],"sliders":[\#(slider)]}"#), "slider.curve", "not slider.unbound")
        let steps = #"[{"say":"One."},{"say":"Two.","do":[{"id":"c","key":"a","value":1}]}]"#
        XCTAssertEqual(reason(#"{"v":1,"items":[\#(line),\#(still)],"steps":\#(steps),"sliders":[\#(slider)]}"#), "slider.edit")
        let s = try scene(#"{"v":1,"items":[\#(line),\#(still)],"sliders":[\#(slider)]}"#)
        let driven: [String] = s.sliders.flatMap(\.items)
        XCTAssertEqual(driven, ["f"])
        var state = MGSliderState(scene: s)
        XCTAssertTrue(state.set("a", nearest: 2))
        let before = try XCTUnwrap(s.items.first { $0.id == "c" })
        let after = try XCTUnwrap(state.items.first { $0.id == "c" })
        XCTAssertEqual(after, before, "the curve is not driven")
        let moved = try XCTUnwrap(state.items.first { $0.id == "f" })
        XCTAssertEqual(moved.num["a"], 2)
        let hint = try XCTUnwrap(MGRepairHint.text(for: "slider.curve"))
        XCTAssertTrue(hint.hasPrefix("sliders drive func graphs only"), hint)
    }

    /// Readouts are `func` numbers: a curve that lists them, or a step edit that gives it them, is refused
    /// (`curve.readouts`), and a text cannot name a curve's readout. A curve's own texts can name a `func`'s readouts,
    /// and a `func` with readouts beside curves weighs as readouts say.
    func testACurveHasNoReadoutsButItsTextsCanNameAFuncs() throws {
        let still = #""id":"c","k":"curve","at":[1,1],"w":4,"h":4,"xr":[-2,2],"yr":[-2,2],"r":"1","mark":1"#
        XCTAssertEqual(reason(#"{"v":1,"items":[{\#(still),"readouts":["value"]}]}"#), "curve.readouts")
        XCTAssertEqual(reason(#"{"v":1,"items":[{\#(still),"readouts":["value"],"shade":[0,1]}]}"#), "curve.readouts",
                       "before the closed-key check")
        let steps = #"[{"say":"One."},{"say":"Two.","do":[{"id":"c","key":"readouts","value":["value"]}]}]"#
        XCTAssertEqual(reason(#"{"v":1,"items":[{\#(still)}],"steps":\#(steps)}"#), "curve.readouts")
        let named = #"{"id":"t","k":"text","at":[8,6],"text":"r = {c.value}"}"#
        XCTAssertEqual(reason(#"{"v":1,"items":[{\#(still)},\#(named)]}"#), "text.text.placeholder.readout")
        let hint = try XCTUnwrap(MGRepairHint.text(for: "curve.readouts"))
        XCTAssertTrue(hint.hasPrefix("readouts are func numbers"), hint)
        // A curve's label names a func's readout, filled from the engine's value.
        let sine = #"{"id":"f","k":"func","at":[6,1],"w":5,"h":4,"xr":[-3,3],"yr":[-1.5,1.5],"y":"sin(x)","mark":1,"readouts":["value"]}"#
        let labelled = #"{\#(still),"label":"sin 1 = {f.value}"}"#
        let s = try scene(#"{"v":1,"items":[\#(sine),\#(labelled)]}"#)
        let c = try XCTUnwrap(s.item("c"))
        XCTAssertEqual(c.label, "sin 1 = 0.84")
        // A func with readouts (2) and two curves (2 each) fill the six graph checks; one more func is refused.
        let more = #"{"id":"c2","k":"curve","at":[1,4],"w":3,"h":3,"xr":[-2,2],"yr":[-2,2],"r":"1"}"#
        let full = #"{"v":1,"items":[\#(sine),\#(labelled),\#(more)]}"#
        XCTAssertEqual(try scene(full).items.count, 3)
        let plain = #"{"id":"g","k":"func","at":[6,5],"w":3,"h":2,"xr":[-1,1],"yr":[-1,1],"y":"x"}"#
        XCTAssertEqual(reason(#"{"v":1,"items":[\#(sine),\#(labelled),\#(more),\#(plain)]}"#), "items.expr")
    }
}
