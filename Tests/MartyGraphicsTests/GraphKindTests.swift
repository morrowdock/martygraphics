// SPDX-License-Identifier: Apache-2.0
import XCTest
import SwiftUI
import ImageIO
@testable import MartyGraphics

/// The additive 2D kinds `func` (an engine-sampled function graph) and `field` (an engine-evaluated vector field):
/// sampling, step edits and blends, motion, patches, streaming, layout, 3D, items built in code, the parse budget and
/// rendering (pixels at the positions the engine computed).
final class GraphKindTests: XCTestCase {
    private func scene(_ json: String) throws -> MGScene { try MGParser.scene(data: Data(json.utf8)).get() }
    private func fixture(_ id: String) throws -> MGScene { try XCTUnwrap(MGFixtures.all.first { $0.id == id }?.scene) }
    private func reason(_ json: String) -> String? {
        if case .failure(let e) = MGParser.scene(data: Data(json.utf8)) { return e.reason }
        return nil
    }

    static let sine = #"{"v":1,"items":[{"id":"f","k":"func","at":[1,1],"w":10,"h":6,"xr":[-3.2,3.2],"yr":[-1.6,1.6],"y":"sin(x)"}]}"#

    func testSamplesSpanTheRangeExactlyAndFollowTheFunction() throws {
        let f = try XCTUnwrap(try scene(Self.sine).items.first)
        XCTAssertEqual(f.kind, .function)
        XCTAssertEqual(f.pts.count, 1 + MGLimits.funcIntervals + 1)
        XCTAssertEqual(f.pts[1].x, -3.2)
        XCTAssertEqual(f.pts.last?.x, 3.2)
        for p in f.pts.dropFirst() { XCTAssertEqual(p.y, sin(p.x)) }
        XCTAssertEqual(f.marked, [])
        XCTAssertEqual(f.text, "sin(x)")
        XCTAssertEqual(f.color, .accent)
    }

    func testDefaultsAndRoundTripsInASmallWorld() throws {
        let json = #"{"v":1,"world":{"w":2,"h":2},"items":[{"id":"f","k":"func","at":[0.2,0.2],"w":1.5,"h":1.5,"xr":[0,1],"yr":[0,1],"y":"x^2"},{"id":"v","k":"field","at":[0.2,0.2],"w":1.5,"h":1.5,"xr":[-1,1],"yr":[-1,1],"dx":"1","dy":"x"}]}"#
        let s = try scene(json)
        let ctx = MGContext(width: s.width, height: s.height, is3D: false, values: [:])
        for item in s.items { XCTAssertEqual(try MGParser.item(.object(item.wire()), ctx), item, item.id) }
        XCTAssertEqual(s.item("v")?.n("cols"), 12)
        XCTAssertEqual(s.item("v")?.n("rows"), 12)
        XCTAssertEqual(s.item("v")?.color, .teal)
        let rebuilt: [String: Any] = ["v": 1, "world": ["w": 2, "h": 2], "items": s.items.map { MGJSON.object($0.wire()).any }]
        XCTAssertEqual(try MGParser.scene(object: rebuilt).get().items, s.items)
    }

    func testStepEditsResampleAndTheBlendMorphsTheCurve() throws {
        let s = try fixture("graphs")
        let before = try XCTUnwrap(MGTimeline.items(s, step: 0).first { $0.id == "wave" })
        let after = try XCTUnwrap(MGTimeline.items(s, step: 1).first { $0.id == "wave" })
        XCTAssertEqual(before.pts.count, after.pts.count)
        for (p, q) in zip(before.pts.dropFirst(), after.pts.dropFirst()) {
            XCTAssertEqual(q.x, p.x)
            XCTAssertEqual(q.y, 1.5 * p.y, accuracy: 1e-12)
        }
        XCTAssertEqual(try XCTUnwrap(after.num["my"]), 1.5 * sin(1.5708), accuracy: 1e-12)
        // Equal sample counts, so a step change morphs the curve point by point instead of cutting.
        let mid = try XCTUnwrap(MGTimeline.blend(from: [before], to: [after], t: 0.5).first)
        for (p, q) in zip(before.pts.dropFirst(), mid.pts.dropFirst()) { XCTAssertEqual(q.y, 1.25 * p.y, accuracy: 1e-12) }
        XCTAssertEqual(mid.num["a"], 1.25)
    }

    func testAMovingGraphIsResampledAtItsLoopTime() throws {
        let s = try fixture("wave")
        XCTAssertTrue(s.animates)
        XCTAssertEqual(MGTimeline.cycle(s), 4)
        XCTAssertEqual(MGTimeline.restTime(s, loops: 2), 8)
        XCTAssertEqual(MGTimeline.frame(s, items: s.items, time: 0), s.items, "t = 0 is the parsed graph")
        let one = try XCTUnwrap(MGTimeline.frame(s, items: s.items, time: 1).first)
        for p in one.pts.dropFirst() { XCTAssertEqual(p.y, sin(p.x - 2 * Double.pi * 1 / 4), accuracy: 1e-12) }
        XCTAssertEqual(MGTimeline.frame(s, items: s.items, time: 0.5), MGTimeline.frame(s, items: s.items, time: 4.5))
        XCTAssertNotEqual(MGTimeline.frame(s, items: s.items, time: 0.5), MGTimeline.frame(s, items: s.items, time: 1.5))
        // A still graph is never resampled, and nothing moves without a period.
        let still = try scene(Self.sine)
        XCTAssertFalse(still.animates)
        XCTAssertNil(MGTimeline.cycle(still))
        XCTAssertEqual(MGTimeline.frame(still, items: still.items, time: 3), still.items)
    }

    /// `1/x` and `x/x` where 0 falls exactly on the midpoint of interval 127: both grid values beside it are finite (and,
    /// for `1/x`, inside the y range, so no pole bisection runs), so only the midpoint shows the gap. The piece splits
    /// there, at parse time and in every animated frame, and no shade can cover the gap (tools/mg_expr.py: the same).
    func testANonFiniteMidpointBetweenTwoSamplesSplitsThePiece() throws {
        for (y, yr) in [("1/x", "[-300,300]"), ("x/x", "[0,2]")] {
            let json = #"{"v":1,"items":[{"id":"f","k":"func","at":[1,1],"w":6,"h":4,"xr":[-0.99609375,1.00390625],"yr":\#(yr),"y":"\#(y)"}]}"#
            let f = try XCTUnwrap(try scene(json).items.first, y)
            XCTAssertEqual(MGGraph.gridX(127, -0.99609375, 1.00390625) + MGGraph.gridX(128, -0.99609375, 1.00390625), 0, y)
            XCTAssertEqual(f.marked, [129], y)
            XCTAssertEqual(f.pts.count - 1, 259, y)
            let samples = Array(f.pts.dropFirst())
            let pieces = MGGraph.pieces(samples.count, starts: f.marked)
            XCTAssertEqual(pieces.count, 2, y)
            for r in pieces {
                let xs = samples[r].map(\.x)
                XCTAssertTrue(xs.allSatisfy { $0 < 0 } || xs.allSatisfy { $0 > 0 }, "\(y): a piece crosses x = 0")
            }
            XCTAssertNil(MGGraph.drawnValue(samples, starts: f.marked, at: 0), y)
            // No shade across the gap: a shaded interval over it is refused, and no band spans it.
            let shaded = #"{"v":1,"items":[{"id":"f","k":"func","at":[1,1],"w":6,"h":4,"xr":[-0.99609375,1.00390625],"yr":\#(yr),"y":"\#(y)","shade":[-0.5,0.5]}]}"#
            XCTAssertEqual(reason(shaded), "func.shade", y)
            let bands = MGGraph.shadeBands(samples, starts: f.marked, -0.5, 0.5, y0: f.n("y0"), y1: f.n("y1"))
            XCTAssertEqual(bands.count, 2, y)
            for band in bands {
                let xs = band.map(\.x)
                XCTAssertTrue(xs.allSatisfy { $0 <= 0 } || xs.allSatisfy { $0 >= 0 }, "\(y): a band crosses x = 0")
            }
        }
        // The same rule in animated frames.
        let moving = try scene(#"{"v":1,"items":[{"id":"f","k":"func","at":[1,1],"w":6,"h":4,"xr":[-0.99609375,1.00390625],"yr":[-300,300],"y":"1/x + sin(pi*t/2)","period":4}]}"#)
        let g = try XCTUnwrap(moving.items.first)
        XCTAssertEqual(g.marked, [129])
        for tau in [0.5, 1.5, 2.5] {
            let frame = MGGraph.animated(g, at: tau)
            XCTAssertEqual(frame.marked, [129], "t = \(tau)")
            XCTAssertNil(MGGraph.drawnValue(Array(frame.pts.dropFirst()), starts: frame.marked, at: 0), "t = \(tau)")
        }
        XCTAssertEqual(MGTimeline.frame(moving, items: moving.items, time: 5.5).first?.marked, [129])
    }

    /// An animated marker shows the value at the current instant or nothing: it never keeps the parsed (t = 0) value
    /// where the current mark is undefined or outside the y range.
    func testAnAnimatedMarkerIsDroppedWhenItsCurrentValueIsInvalid() throws {
        // ln(x + sin(πt)) at x = 0.5: defined at the checked instants t = 0, 1, 2, 3; undefined at t = 1.5.
        let undefined = try scene(#"{"v":1,"items":[{"id":"f","k":"func","at":[1,1],"w":6,"h":4,"xr":[0.1,2],"yr":[-3,1],"y":"ln(x + sin(pi*t))","period":4,"mark":0.5}]}"#)
        let f = try XCTUnwrap(undefined.items.first)
        XCTAssertEqual(try XCTUnwrap(f.num["my"]), Foundation.log(0.5), accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(MGGraph.animated(f, at: 0.5).num["my"]), Foundation.log(1.5), accuracy: 1e-12)
        XCTAssertNil(MGGraph.animated(f, at: 1.5).num["my"], "undefined at t = 1.5")
        XCTAssertNil(MGTimeline.frame(undefined, items: undefined.items, time: 5.5).first?.num["my"], "t = 5.5 is t = 1.5")
        // x + 3 sin(πt) at x = 0: inside the y range at the checked instants, above it at t = 0.5, below it at t = 1.5.
        let outside = try scene(#"{"v":1,"items":[{"id":"f","k":"func","at":[1,1],"w":6,"h":4,"xr":[-0.5,0.5],"yr":[-1,1],"y":"x + 3*sin(pi*t)","period":4,"mark":0}]}"#)
        let g = try XCTUnwrap(outside.items.first)
        XCTAssertEqual(try XCTUnwrap(g.num["my"]), 0, accuracy: 1e-12)
        XCTAssertNil(MGGraph.animated(g, at: 0.5).num["my"], "above the y range at t = 0.5")
        XCTAssertNil(MGGraph.animated(g, at: 1.5).num["my"], "below the y range at t = 1.5")
        XCTAssertEqual(try XCTUnwrap(MGGraph.animated(g, at: 1).num["my"]), 3 * sin(Double.pi), accuracy: 1e-12)
    }

    func testPatchesAndStepEditsGetTheSameChecks() throws {
        let s = try fixture("graphs")
        let cosine = try MGPatch.parse(data: Data(#"{"v":1,"rev":0,"ops":[{"op":"set","id":"wave","key":"y","value":"a*cos(x)"}]}"#.utf8)).get()
        let wave = try XCTUnwrap(try s.applying(cosine).get().item("wave"))
        XCTAssertEqual(wave.text, "a*cos(x)")
        XCTAssertEqual(wave.pts[1].y, cos(-3.2))
        let broken = try MGPatch.parse(data: Data(#"{"v":1,"ops":[{"op":"set","id":"wave","key":"y","value":"cosh(x"}]}"#.utf8)).get()
        guard case .failure(let e) = s.applying(broken) else { return XCTFail("a broken expression must not apply") }
        XCTAssertEqual(e.reason, "func.y.syntax")
        let grid = try MGPatch.parse(data: Data(#"{"v":1,"ops":[{"op":"set","id":"flow","key":"n","value":[4,4]}]}"#.utf8)).get()
        XCTAssertEqual(try s.applying(grid).get().item("flow")?.pts.count, 1 + 16)
        // A step edit is re-checked like a patch: an edit that would make the graph unfaithful refuses the scene.
        let json = #"{"v":1,"items":[{"id":"f","k":"func","at":[1,1],"w":6,"h":4,"xr":[-3,3],"yr":[-2,2],"y":"sin(x)"}],"steps":[{"say":"One."},{"say":"Two.","do":[{"id":"f","key":"y","value":"sin(90*x)"}]}]}"#
        XCTAssertEqual(reason(json), "func.detail")
    }

    func testStreamingPreviewsMatchTheStrictParse() throws {
        for id in ["graphs", "wave"] {
            let json = try XCTUnwrap(MGFixtures.all.first { $0.id == id }?.json)
            for seed in UInt64(1)...3 {
                var parser = MGStreamParser()
                for chunk in MGRegression.chunks(json, seed: seed) { _ = parser.feed(chunk) }
                XCTAssertEqual(try parser.finish().get(), try fixture(id), "\(id) seed \(seed)")
            }
        }
    }

    func testLayoutBoundsAreTheFrame() throws {
        let s = try fixture("graphs")
        let vp = MGViewport(size: CGSize(width: 600, height: 400), width: s.width, height: s.height, camera: nil)
        for id in ["wave", "flow"] {
            let item = try XCTUnwrap(s.item(id))
            let box = try XCTUnwrap(MGLayout.bounds(item, in: s.items, vp))
            XCTAssertEqual(box.minX, vp.point(item.pts[0]).x, accuracy: 0.01)
            XCTAssertEqual(box.maxY, vp.point(item.pts[0]).y, accuracy: 0.01)
            XCTAssertEqual(box.width, vp.length(item.n("w")), accuracy: 0.01)
            XCTAssertEqual(box.height, vp.length(item.n("h")), accuracy: 0.01)
        }
    }

    func testTheNewKindsAreTwoDimensionalOnly() throws {
        XCTAssertFalse(MGKind.in3D.contains(.function))
        XCTAssertFalse(MGKind.in3D.contains(.field))
        XCTAssertEqual(MGKind(rawValue: "func"), .function)
        XCTAssertEqual(MGKind.function.rawValue, "func")
        let toDepth = try MGPatch.parse(data: Data(#"{"v":1,"ops":[{"op":"dim","dim":"3d"}]}"#.utf8)).get()
        guard case .failure(let e) = try scene(Self.sine).applying(toDepth) else { return XCTFail("a graph must not enter 3D") }
        XCTAssertEqual(e.reason, "3d.kind.func")
    }

    func testItemsBuiltInCodeAreRefusedOrSkippedNeverTrapped() throws {
        let ctx = MGContext(width: 12, height: 8, is3D: false, values: [:])
        for kind in [MGKind.function, .field] {
            var bad = MGItem(id: "x", kind: kind, color: .accent)
            bad.pts = [MGPoint(1, 1)]
            bad.num = ["w": .nan, "h": 4, "x0": 0, "x1": .infinity, "y0": 0, "y1": 1, "cols": 1e300, "rows": -1]
            XCTAssertThrowsError(try MGParser.item(.object(bad.wire()), ctx), kind.rawValue)
            XCTAssertFalse(MGDescribe.item(bad, in: [bad]).isEmpty)
        }
        XCTAssertEqual(MGGraph.pieces(3, starts: [5, -1, 2, 2]), [0..<2, 2..<3])
        XCTAssertEqual(MGGraph.pieces(0, starts: [1]), [])
        XCTAssertNil(MGGraph.drawnValue([], starts: [], at: 0))
        // A moving graph built in code with an expression that does not compile is left as it is.
        var odd = try XCTUnwrap(try fixture("wave").items.first)
        odd.text = "sin(("
        XCTAssertEqual(MGGraph.animated(odd, at: 1), odd)
    }

    func testSixMovingGraphsParseWithinAGenerousBudget() throws {
        let one = #"{"id":"fID","k":"func","at":[1,1],"w":4,"h":3,"xr":[-6.2832,6.2832],"yr":[-1.5,1.5],"y":"a*sin(x - 2*pi*t/4)*cos(b*x)","a":1,"b":0.5,"period":4,"shade":[0,1],"mark":1}"#
        let items = (1...MGLimits.exprItems).map { one.replacingOccurrences(of: "fID", with: "f\($0)") }.joined(separator: ",")
        let start = Date()
        let s = try scene(#"{"v":1,"items":["# + items + "]}")
        let seconds = Date().timeIntervalSince(start)
        XCTAssertEqual(s.items.count, MGLimits.exprItems)
        // Pending Mac measurement: record this line in the receipt. The bound is deliberately generous.
        print("MGVNEXT six moving graphs parsed in \(seconds) s")
        XCTAssertLessThan(seconds, 2)
        let seventh = one.replacingOccurrences(of: "fID", with: "f7")
        XCTAssertEqual(reason(#"{"v":1,"items":["# + items + "," + seventh + "]}"), "items.expr")
    }

    // MARK: rendering

    private static let size = CGSize(width: 600, height: 400)

    @MainActor private func render(_ scene: MGScene, items: [MGItem]? = nil, appear: [String: Double] = [:],
                                   size: CGSize = GraphKindTests.size) throws -> (CGImage, MGViewport) {
        let vp = MGViewport(size: size, width: scene.width, height: scene.height, camera: nil)
        let input = MGRenderInput(scene: scene, items: items ?? scene.items, viewport: vp, appear: appear, focus: nil, time: 0)
        let renderer = ImageRenderer(content: Canvas { context, _ in MGCanvasRenderer.draw(input, in: context) }
            .frame(width: size.width, height: size.height))
        renderer.scale = 1
        return (try XCTUnwrap(renderer.cgImage), vp)
    }

    /// Review stills of the new kinds (docs/proposals/ROADMAP-VNEXT.md, "Mac verification"), written only when
    /// `MG_VNEXT_RENDER_DIR` names a directory; skipped otherwise. Prints one SHA-256 per still for the receipt. The
    /// pixels are for a person to review, not a byte-exact golden (anti-aliasing can differ between machines).
    @MainActor func testRenderReviewStills() throws {
        guard let dir = ProcessInfo.processInfo.environment["MG_VNEXT_RENDER_DIR"], !dir.isEmpty else {
            throw XCTSkip("set MG_VNEXT_RENDER_DIR to write the review stills")
        }
        let out = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        var boards: [(name: String, scene: MGScene, items: [MGItem])] = []
        let graphs = try fixture("graphs")
        for step in graphs.steps.indices { boards.append(("graphs-step\(step + 1)", graphs, MGTimeline.items(graphs, step: step))) }
        let wave = try fixture("wave")
        for t in [0, 1, 2, 3] { boards.append(("wave-t\(t)", wave, MGTimeline.frame(wave, items: wave.items, time: Double(t)))) }
        let frame = #""at":[1,1],"w":10,"h":6"#
        let cases: [(String, String)] = [
            ("tangent-poles", #"{"v":1,"items":[{"id":"f","k":"func","#  + frame + #","xr":[-6.2832,6.2832],"yr":[-4,4],"y":"tan(x)","label":"tan x"}]}"#),
            ("reciprocal-pole", #"{"v":1,"items":[{"id":"f","k":"func","# + frame + #","xr":[-2,3],"yr":[-5,5],"y":"1/x","shade":[0.5,2],"label":"1/x"}]}"#),
            ("removable-hole", #"{"v":1,"items":[{"id":"f","k":"func","# + frame + #","xr":[-10,10],"yr":[-0.5,1.2],"y":"sin(x)/x","mark":0.001}]}"#),
            ("log-asymptote", #"{"v":1,"items":[{"id":"f","k":"func","# + frame + #","xr":[0,3],"yr":[-3,2],"y":"ln(x)","mark":1}]}"#),
            ("root-start", #"{"v":1,"items":[{"id":"f","k":"func","# + frame + #","xr":[0,4],"yr":[0,2.2],"y":"sqrt(x)","shade":[1,4]}]}"#),
            ("field-arrows", #"{"v":1,"items":[{"id":"v","k":"field","# + frame + #","xr":[-2,2],"yr":[-2,2],"dx":"-y","dy":"x","label":"(-y, x)"}]}"#),
            ("field-unit", #"{"v":1,"items":[{"id":"v","k":"field","# + frame + #","xr":[-1.5,1.5],"yr":[-1.5,1.5],"dx":"x/(x^2+y^2)","dy":"y/(x^2+y^2)","style":"unit","n":[9,9]}]}"#),
            ("field-slope", #"{"v":1,"items":[{"id":"v","k":"field","# + frame + #","xr":[-3,3],"yr":[-2,2],"dx":"1","dy":"x - y","style":"slope","label":"dy/dx = x - y"}]}"#),
            ("curve-ellipse-widened", #"{"v":1,"items":[{"id":"c","k":"curve",\#(frame),"xr":[-2.2,2.2],"yr":[-1.2,1.2],"x":"2*cos(theta)","y":"sin(theta)","mark":0.7,"label":"(2 cos t, sin t)"}]}"#),
            ("curve-rose", #"{"v":1,"items":[{"id":"c","k":"curve",\#(frame),"xr":[-1.1,1.1],"yr":[-1.1,1.1],"r":"cos(3*theta)","theta":[0,3.141592653589793],"label":"r = cos 3t"}]}"#),
            ("curve-line-poles", #"{"v":1,"items":[{"id":"c","k":"curve",\#(frame),"xr":[-3,3],"yr":[-3,3],"r":"1/cos(theta)","label":"r = 1/cos t"}]}"#),
            ("curve-lemniscate-gaps", #"{"v":1,"items":[{"id":"c","k":"curve",\#(frame),"xr":[-1.2,1.2],"yr":[-0.8,0.8],"r":"sqrt(cos(2*theta))"}]}"#),
            ("curve-cycloid", #"{"v":1,"items":[{"id":"c","k":"curve","at":[0.5,2],"w":11,"h":2.4,"xr":[0,12.6],"yr":[0,2.2],"x":"theta - sin(theta)","y":"1 - cos(theta)","theta":[0,12.566370614359172]}]}"#)
        ]
        for (name, json) in cases { let s = try scene(json); boards.append((name, s, s.items)) }
        let curves = try fixture("curves")
        for step in curves.steps.indices { boards.append(("curves-step\(step + 1)", curves, MGTimeline.items(curves, step: step))) }
        for board in boards {
            let (image, _) = try render(board.scene, items: board.items, size: CGSize(width: 960, height: 640))
            let url = out.appendingPathComponent(board.name + ".png")
            guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
                return XCTFail("cannot write \(board.name)")
            }
            CGImageDestinationAddImage(destination, image, nil)
            XCTAssertTrue(CGImageDestinationFinalize(destination), board.name)
            let png = try Data(contentsOf: url)
            print("MGVNEXT still \(board.name).png sha256 \(MGSHA256.hex(png))")
        }
    }

    /// Brightness (the largest of R, G and B, 0…255) of one pixel, at a top-left-origin point of the rendered board.
    static func brightness(_ image: CGImage, _ p: CGPoint) -> Int {
        guard let one = image.cropping(to: CGRect(x: Int(p.x.rounded(.down)), y: Int(p.y.rounded(.down)), width: 1, height: 1)) else { return -1 }
        var pixel = [UInt8](repeating: 0, count: 4)
        let drawn = pixel.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(one, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        return drawn ? Int(max(pixel[0], pixel[1], pixel[2])) : -1
    }

    /// The brightest pixel within `radius` of `p` (strokes are anti-aliased and a few pixels wide).
    static func brightest(_ image: CGImage, near p: CGPoint, radius: Int = 3) -> Int {
        var best = -1
        for dy in -radius...radius {
            for dx in -radius...radius { best = max(best, brightness(image, CGPoint(x: p.x + CGFloat(dx), y: p.y + CGFloat(dy)))) }
        }
        return best
    }

    /// Where the renderer puts data point (x, y) of a `func` or `field` item: its frame and ranges, mapped as
    /// `MGCanvasRenderer.graphFrame` does.
    static func screen(_ item: MGItem, _ vp: MGViewport, x: Double, y: Double) -> CGPoint {
        let frame = CGRect(origin: vp.point(item.pts[0] + MGPoint(0, item.n("h"))),
                           size: CGSize(width: vp.length(item.n("w")), height: vp.length(item.n("h"))))
        return CGPoint(x: frame.minX + frame.width * CGFloat((x - item.n("x0")) / (item.n("x1") - item.n("x0"))),
                       y: frame.maxY - frame.height * CGFloat((y - item.n("y0")) / (item.n("y1") - item.n("y0"))))
    }

    @MainActor func testTheCurveIsDrawnWhereTheEngineSampledIt() throws {
        let s = try scene(#"{"v":1,"items":[{"id":"f","k":"func","at":[1,1],"w":10,"h":6,"xr":[-1,1],"yr":[-1,1],"y":"x"}]}"#)
        let f = try XCTUnwrap(s.items.first)
        let (image, vp) = try render(s)
        for x in [-0.75, -0.3, 0.3, 0.75] {
            XCTAssertGreaterThan(Self.brightest(image, near: Self.screen(f, vp, x: x, y: x)), 190, "on the curve at x = \(x)")
            XCTAssertLessThan(Self.brightness(image, Self.screen(f, vp, x: x, y: -x)), 140, "off the curve at x = \(x)")
        }
        // Draw-on reveals the graph from the left: at progress 0 nothing of the curve is drawn.
        let (hidden, _) = try render(s, appear: ["f": 0])
        XCTAssertLessThan(Self.brightest(hidden, near: Self.screen(f, vp, x: 0.75, y: 0.75)), 140)
    }

    @MainActor func testTheShadedBandAndTheMarkedPointAreDrawn() throws {
        let s = try scene(#"{"v":1,"items":[{"id":"f","k":"func","at":[1,1],"w":10,"h":6,"xr":[-1,1],"yr":[-1,1],"y":"x^2","shade":[0,0.8],"mark":-0.6}]}"#)
        let f = try XCTUnwrap(s.items.first)
        XCTAssertEqual(try XCTUnwrap(f.num["my"]), 0.36, accuracy: 1e-12)
        let (image, vp) = try render(s)
        let inside = Self.brightness(image, Self.screen(f, vp, x: 0.6, y: 0.15))
        let outside = Self.brightness(image, Self.screen(f, vp, x: -0.6, y: 0.15))
        XCTAssertGreaterThan(inside, outside + 20, "the area under the curve from 0 to 0.8 is shaded")
        XCTAssertGreaterThan(Self.brightness(image, Self.screen(f, vp, x: -0.6, y: 0.36)), 220, "the marked point")
    }

    @MainActor func testFieldArrowsSitAtTheirCellCentresAndMissingCellsStayEmpty() throws {
        let uniform = try scene(#"{"v":1,"items":[{"id":"v","k":"field","at":[1,1],"w":10,"h":6,"xr":[-2,2],"yr":[-1,1],"dx":"1","dy":"0","n":[4,2]}]}"#)
        let v = try XCTUnwrap(uniform.items.first)
        let (image, vp) = try render(uniform)
        for x in [-1.5, -0.5, 0.5, 1.5] {
            for y in [-0.5, 0.5] {
                XCTAssertGreaterThan(Self.brightest(image, near: Self.screen(v, vp, x: x, y: y), radius: 2), 150, "arrow at (\(x), \(y))")
                XCTAssertLessThan(Self.brightness(image, Self.screen(v, vp, x: x, y: y + 0.25)), 120, "between arrows at (\(x), \(y))")
            }
        }
        let singular = try scene(#"{"v":1,"items":[{"id":"g","k":"field","at":[1,1],"w":10,"h":6,"xr":[0.5,3.5],"yr":[0.5,3.5],"dx":"1/(x-2)","dy":"0","n":[3,3]}]}"#)
        let g = try XCTUnwrap(singular.items.first)
        XCTAssertEqual(g.marked, [1, 4, 7])
        let (hole, gvp) = try render(singular)
        XCTAssertLessThan(Self.brightness(hole, Self.screen(g, gvp, x: 2, y: 2)), 110, "no arrow where the field has no value")
        XCTAssertGreaterThan(Self.brightest(hole, near: Self.screen(g, gvp, x: 1, y: 2), radius: 2), 150, "the arrow beside it")
    }

    /// A circle is drawn round where the engine sampled it (the frame is aspect-correct), with nothing at its centre,
    /// and its marked point is drawn at the engine's coordinates; draw-on traces it from θ = 0.
    @MainActor func testACurveIsDrawnWhereTheEngineSampledIt() throws {
        let s = try scene(#"{"v":1,"items":[{"id":"c","k":"curve","at":[1,1],"w":10,"h":6,"xr":[-1.25,1.25],"yr":[-1.25,1.25],"x":"cos(theta)","y":"sin(theta)","mark":2.5}]}"#)
        let c = try XCTUnwrap(s.items.first)
        // The 10 × 6 frame widens x, so one data unit is as long across as up on the screen too.
        let (image, vp) = try render(s)
        let centre: CGPoint = Self.screen(c, vp, x: 0, y: 0)
        let right: CGPoint = Self.screen(c, vp, x: 1, y: 0)
        let top: CGPoint = Self.screen(c, vp, x: 0, y: 1)
        let across: CGFloat = right.x - centre.x
        let up: CGFloat = centre.y - top.y
        XCTAssertEqual(across, up, accuracy: 0.5, "a circle is round")
        let angles: StrideTo<Double> = stride(from: 0.3, to: 6.2, by: 0.7)
        for angle in angles {
            let x: Double = cos(angle)
            let y: Double = sin(angle)
            let point: CGPoint = Self.screen(c, vp, x: x, y: y)
            let lit: Int = Self.brightest(image, near: point)
            XCTAssertGreaterThan(lit, 190, "on the circle at \(angle)")
        }
        let inside: CGPoint = Self.screen(c, vp, x: 0.4, y: -0.3)
        let insideLit: Int = Self.brightness(image, inside)
        XCTAssertLessThan(insideLit, 140, "inside the circle")
        let markX: Double = cos(2.5)
        let markY: Double = sin(2.5)
        let mark: CGPoint = Self.screen(c, vp, x: markX, y: markY)
        let markLit: Int = Self.brightness(image, mark)
        XCTAssertGreaterThan(markLit, 220, "the marked point")
        let (hidden, _) = try render(s, appear: ["c": 0])
        let laterX: Double = cos(3.5)
        let laterY: Double = sin(3.5)
        let later: CGPoint = Self.screen(c, vp, x: laterX, y: laterY)
        let laterLit: Int = Self.brightest(hidden, near: later)
        XCTAssertLessThan(laterLit, 140, "not yet traced")
        // The line r = 1/cos θ is drawn at x = 1 only: no chord through the view at its poles.
        let line = try scene(#"{"v":1,"items":[{"id":"l","k":"curve","at":[1,1],"w":10,"h":6,"xr":[-3,3],"yr":[-3,3],"r":"1/cos(theta)"}]}"#)
        let l = try XCTUnwrap(line.items.first)
        let (lineImage, lvp) = try render(line)
        let onLine: CGPoint = Self.screen(l, lvp, x: 1, y: 2)
        let lineLit: Int = Self.brightest(lineImage, near: onLine)
        XCTAssertGreaterThan(lineLit, 190)
        let offLine: CGPoint = Self.screen(l, lvp, x: -1.5, y: 0.5)
        let chordLit: Int = Self.brightness(lineImage, offLine)
        XCTAssertLessThan(chordLit, 140, "no chord across the view")
    }

    @MainActor func testUncheckedItemsDrawNothingInsteadOfTrapping() throws {
        let s = try scene(Self.sine)
        var f = try XCTUnwrap(s.items.first)
        f.num["x1"] = .nan
        f.marked = [9999, -3]
        var v = MGItem(id: "v", kind: .field, color: .teal)
        v.pts = [MGPoint(1, 1)]
        v.num = ["w": 4, "h": 4, "x0": 0, "x1": 1, "y0": 0, "y1": 1, "cols": 3.5, "rows": 2]
        var c = MGItem(id: "c", kind: .curve, color: .accent)
        c.pts = [MGPoint(1, 1), MGPoint(.nan, 2), MGPoint(1e300, -1e300), MGPoint(0.5, 0.5)]
        c.num = ["w": 4, "h": 4, "x0": 0, "x1": 1, "y0": 0, "y1": 1, "mx": .infinity, "my": 0]
        c.marked = [7, -1]
        let (image, _) = try render(s, items: [f, v, c])
        XCTAssertEqual(image.width, Int(Self.size.width))
    }
}
