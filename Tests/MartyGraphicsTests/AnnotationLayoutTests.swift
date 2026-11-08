// SPDX-License-Identifier: Apache-2.0
import Foundation
import SceneKit
import SwiftUI
import XCTest
@testable import MartyGraphics

/// Annotation placement, occlusion, snapshot `/2` fields and renderers (open vocabulary 3a). Test names carry the
/// acceptance ids P1–P15 of the PR 3 spec (§11 P).
final class AnnotationLayoutTests: XCTestCase {
    func doc(_ text: String, file: StaticString = #filePath, line: UInt = #line) throws -> MGSolidDocument {
        switch MGSolidParser.document(data: Data(text.utf8)) {
        case .success(let d): return d
        case .failure(let e): XCTFail("refused: \(e)", file: file, line: line); throw e
        }
    }
    func model(_ name: String) throws -> MGSolidDocument {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Examples/Solid3D/Sources/MartySolid3D/Models/\(name).json")
        return try doc(String(decoding: try Data(contentsOf: url), as: UTF8.self))
    }
    var seed: UInt64 = 0x9E3779B97F4A7C15
    func rnd() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 11) / Double(1 << 53) }

    /// A small box with `n` labels around it (or all on one anchor).
    func labelled(_ n: Int, sameAnchor: Bool = false, steps: String = #"[{"say": "Labels."}]"#) -> String {
        let labels = (0..<n).map { k -> String in
            let t = 2 * Double.pi * Double(k) / Double(n)
            let at = sameAnchor ? #""core""# : #"{"part": "core", "offset": [\#(10 * cos(t)), \#(10 * sin(t)), \#(k % 2 == 0 ? 5 : -5)]}"#
            return #"{"id": "l\#(k)", "at": \#(at), "text": "Label number word \#(["one", "two", "six", "ten"][k % 4])"}"#
        }
        return #"{"v": 2, "kind": "assembly", "parts": [{"id": "core", "shape": {"box": {"size": [20, 20, 10]}}}], "annotations": {"labels": [\#(labels.joined(separator: ","))]}, "steps": \#(steps)}"#
    }

    /// Hard rules on a finished frame: boxes inside the safe frame, outside the legend corner, apart from each other and
    /// from every label dot; callout rows apart from placed boxes; nothing dropped.
    func assertRules(_ f: MGAnnotationFrame, caption: Bool, title: Bool = false, ids: [String], file: StaticString = #filePath, line: UInt = #line) {
        let w = f.width, h = f.height
        func px(_ b: [Double]) -> MGAnnotationRect { MGAnnotationRect(x: b[0] * w, y: b[1] * h, width: b[2] * w, height: b[3] * h) }
        XCTAssertEqual(f.placement.map(\.id).sorted(), ids.sorted(), "none dropped", file: file, line: line)
        let safe = MGAnnotationLayout.safeFrame(width: w, height: h, caption: caption, title: title)
        let legend = MGAnnotationLayout.legendRect(width: w, height: h)
        let placed = f.placement.filter { $0.callout == nil }
        let dots = f.placement.filter { $0.kind == "label" }.compactMap { $0.anchor.map { MGVec2($0[0] * w, $0[1] * h) } }
        for (i, p) in placed.enumerated() {
            let b = px(p.box)
            let grown = MGAnnotationRect(x: safe.x - 1e-6, y: safe.y - 1e-6, width: safe.width + 2e-6, height: safe.height + 2e-6)
            XCTAssertTrue(grown.contains(b), "\(p.id) inside the safe frame", file: file, line: line)
            XCTAssertFalse(b.intersects(legend), "\(p.id) clear of the legend", file: file, line: line)
            for q in placed[(i + 1)...] { XCTAssertFalse(b.intersects(px(q.box), gap: 3.999), "\(p.id) overlaps \(q.id)", file: file, line: line) }
            for d in dots { XCTAssertGreaterThanOrEqual((b.nearest(d) - d).length, 6 - 1e-6, "\(p.id) covers a dot", file: file, line: line) }
            for c in f.placement where c.callout != nil { XCTAssertFalse(b.intersects(px(c.box)), "\(p.id) overlaps callout \(c.id)", file: file, line: line) }
        }
        let callouts = f.placement.compactMap(\.callout)
        XCTAssertEqual(callouts, Array(0..<callouts.count), "callout rows numbered in order", file: file, line: line)
    }

    // MARK: P1 projection

    func testP1CoreProjectionMatchesTheRenderer() throws {
        let d = try model("annotated-winch")
        let r = MGSolidRenderer(assembly: d.assembly)
        let cameras = [MGSolidCamera(target: .zero, yaw: 32, pitch: 28, distance: 400),
                       MGSolidCamera(target: MGVec3(10, 20, -5), yaw: -120, pitch: 60, distance: 250, fieldOfView: 45),
                       MGSolidCamera(target: MGVec3(0, 50, 0), yaw: 200, pitch: -10, distance: 900, fieldOfView: 20)]
        var compared = 0
        for c in cameras {
            r.setCamera(c)
            let proj = MGAnnotationProjection(camera: c, width: 1280, height: 800)
            for _ in 0..<50 {
                let p = MGVec3(rnd() * 300 - 150, rnd() * 300 - 150, rnd() * 300 - 150)
                let a = r.project(p, width: 1280, height: 800), b = proj.project(p)
                XCTAssertEqual(a == nil, b == nil)
                if let a, let b { XCTAssertLessThan(hypot(Double(a.x) - b.x, Double(a.y) - b.y), 0.5); compared += 1 }
            }
        }
        XCTAssertGreaterThan(compared, 100)
    }

    // MARK: P2–P4 placement

    func testP2TwelveLabelsAroundASmallModel() throws {
        let d = try doc(labelled(12))
        let view = d.view(step: 0)
        for (w, h) in [(1024.0, 768.0), (1366.0, 1024.0)] {
            let cam = MGSolidAnnotations.defaultCamera(d, params: d.defaults, aspect: w / h)
            let f = MGSolidAnnotations.frame(document: d, view: view, params: d.defaults, camera: cam, width: w, height: h, caption: true)
            assertRules(f, caption: true, ids: d.annotations.ids)
            XCTAssertGreaterThan(f.placement.filter { $0.callout == nil }.count, 0)
        }
    }

    func testP3TwelveLabelsOnOneAnchor() throws {
        let d = try doc(labelled(12, sameAnchor: true))
        let cam = MGSolidAnnotations.defaultCamera(d, params: d.defaults, aspect: 1024.0 / 768)
        let f = MGSolidAnnotations.frame(document: d, view: d.view(step: 0), params: d.defaults, camera: cam, width: 1024, height: 768, caption: true)
        assertRules(f, caption: true, ids: d.annotations.ids)
        XCTAssertEqual(f.placement.map(\.id), d.annotations.ids, "authored order")
        let firstCallout = try XCTUnwrap(f.placement.firstIndex { $0.callout != nil }, "some labels cannot be placed on one anchor")
        XCTAssertGreaterThan(firstCallout, 0)
        XCTAssertTrue(f.placement[firstCallout...].allSatisfy { $0.callout != nil }, "valid placements first, then callout entries")
        XCTAssertEqual(MGSolidAnnotations.frame(document: d, view: d.view(step: 0), params: d.defaults, camera: cam, width: 1024, height: 768, caption: true), f)
    }

    func testP4PlacementIsDeterministic() throws {
        let d = try model("annotated-winch")
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        for step in d.steps.indices {
            let cam = MGSolidAnnotations.defaultCamera(d, params: d.defaults)
            let a = try enc.encode(MGSolidAnnotations.frame(document: d, view: d.view(step: step), params: d.defaults, camera: cam, aspect: 1.6, caption: true))
            let b = try enc.encode(MGSolidAnnotations.frame(document: try model("annotated-winch"), view: d.view(step: step), params: d.defaults, camera: cam,
                                                            aspect: 1.6, caption: true))
            XCTAssertEqual(a, b)
        }
        // The fresh-process half of P4 is in MartySolidCLITests (the check report's `placements`).
    }

    // MARK: P5–P7 occlusion

    func casing(_ extra: String = "") -> String {
        #"{"v": 2, "kind": "assembly", "parts": [{"id": "casing", "shape": {"box": {"size": [40, 40, 40]}}}], "annotations": {"labels": [{"id": "l", "at": {"world": [0, -2, 0]}, "text": "Inside"}]}, "steps": [{"say": "Closed.", "annotate": ["l"]}, {"say": "Ghost.", "ghost": ["casing"], "annotate": ["l"]}, {"say": "Cut.", "section": {"normal": [0, -1, 0], "parts": ["casing"]}, "annotate": ["l"]}]}"#
    }
    func occluded(_ d: MGSolidDocument, step: Int, budget: Int = MGSolidAnnotationLimits.occlusionTests) -> Bool?? {
        let cam = MGSolidAnnotations.defaultCamera(d, params: d.defaults)
        return MGSolidAnnotations.frame(document: d, view: d.view(step: step), params: d.defaults, camera: cam, width: 1280, height: 800,
                                        caption: true, occlusionBudget: budget).placement.first?.occluded
    }

    func testP5AnchorBehindACasingAndThroughAGhost() throws {
        let d = try doc(casing())
        XCTAssertEqual(occluded(d, step: 0), .some(true))
        XCTAssertEqual(occluded(d, step: 1), .some(false))
    }

    func testP6CutCasingTestsTheCutMesh() throws {
        XCTAssertEqual(occluded(try doc(casing()), step: 2), .some(false))
    }

    func testP7OverBudgetIsUnknown() throws {
        let d = try doc(casing())
        XCTAssertEqual(occluded(d, step: 0, budget: 1), .some(nil))
        let cam = MGSolidAnnotations.defaultCamera(d, params: d.defaults)
        let n = d.assembly.parts[0].mesh.triangleCount
        XCTAssertEqual(MGSolidAnnotations.occlusion(document: d, view: d.view(step: 0), params: d.defaults, camera: cam, budget: n - 1).map(\.occluded), [nil])
        XCTAssertEqual(MGSolidAnnotations.occlusion(document: d, view: d.view(step: 0), params: d.defaults, camera: cam, budget: n).map(\.occluded), [true])
    }

    // MARK: P8 hysteresis

    func testP8OrbitKeepsLabelsUntilTheirPlaceBecomesInvalid() throws {
        let d = try doc(labelled(6))
        let view = d.view(step: 0)
        let base = MGSolidAnnotations.defaultCamera(d, params: d.defaults)
        var previous: MGAnnotationFrame?
        var kept = 0, moved = 0
        for k in 0..<72 {
            var cam = base
            cam.yaw = base.yaw + 5 * Double(k)
            let input = MGSolidAnnotations.layoutInput(document: d, view: view, params: d.defaults, camera: cam, width: 1024, height: 768,
                                                       previous: previous, highlight: [], caption: true, title: false, stage: MGSolidStage.zUpToYUp,
                                                       occlusionBudget: MGSolidAnnotationLimits.occlusionTests)
            var trace: [String: String] = [:]
            let placement = try XCTUnwrap(MGAnnotationLayout.place(input, trace: &trace))
            let frame = MGSolidAnnotations.frame(document: d, view: view, params: d.defaults, camera: cam, width: 1024, height: 768,
                                                 previous: previous, caption: true)
            XCTAssertEqual(frame.placement, placement)
            assertRules(frame, caption: true, ids: d.annotations.ids)
            for p in placement {
                guard let old = previous?.placement.first(where: { $0.id == p.id })?.candidate else { continue }
                if p.candidate == old { XCTAssertEqual(trace[p.id], "kept"); kept += 1 }
                else { XCTAssertEqual(trace[p.id], "invalid", "\(p.id) moved at frame \(k) while its place was valid"); moved += 1 }
            }
            previous = frame
        }
        XCTAssertGreaterThan(kept, moved)
    }

    // MARK: P9–P13 snapshot

    /// The winch with one step that shows 2 labels, 2 arrows and 1 dimension.
    func winchStep() throws -> MGSolidDocument {
        let d = try model("annotated-winch")
        let patch = try XCTUnwrap(MGJSON(any: ["steps": [["say": "All of it.", "highlight": ["wheel"],
                                                          "annotate": ["lPinion", "lWheel", "aWheel", "aWeight", "centres"]]]] as [String: Any]))
        guard case .success(let p) = MGSolidParser.applying(patch, to: d) else { XCTFail("patch"); throw MGSolidIssue("patch") }
        return p
    }
    func withoutAnnotations(_ d: MGSolidDocument) throws -> MGSolidDocument {
        guard case .object(var o) = d.source else { throw MGSolidIssue("source") }
        o.removeValue(forKey: "annotations")
        o["steps"] = .array([.object(["say": .string("All of it."), "highlight": .array([.string("wheel")])])])
        guard case .success(let plain) = MGSolidParser.document(json: .object(o)) else { throw MGSolidIssue("plain") }
        return plain
    }

    func testP9SnapshotCarriesAnnotationsAfterThePartTriangles() throws {
        let d = try winchStep()
        let params = d.defaults
        let snap = MGSolidSnapshot.make(d, step: 0, params: params, highlight: d.steps[0].highlight)
        // The gate: a pose this still step does not show exports no annotations.
        XCTAssertNil(MGSolidSnapshot.make(d, step: 0, params: MGPoseParameters(input: 0.3), highlight: []).annotations)
        let plain = MGSolidSnapshot.make(try withoutAnnotations(d), step: 0, params: params)
        XCTAssertEqual(snap.parts, plain.parts, "part ranges unchanged")
        XCTAssertEqual(snap.camera, plain.camera, "annotation geometry does not change the framing")
        XCTAssertEqual(snap.boundsMin, plain.boundsMin)
        let a = try XCTUnwrap(snap.annotations)
        XCTAssertEqual(a.arrows.map(\.id), ["aWheel", "aWeight"])
        XCTAssertEqual(a.dimensions.map(\.id), ["centres"])
        XCTAssertEqual(a.labels.map(\.id), ["lPinion", "lWheel"])
        XCTAssertEqual(a.labels.map(\.text), ["Pinion: 14 teeth", "Drum gear: 42 teeth"])
        XCTAssertEqual(a.dimensions[0].value, 56, accuracy: 1e-9)
        XCTAssertEqual(a.placement.map(\.id), ["lPinion", "lWheel", "aWeight", "centres"], "labels, then arrow texts, then dimension texts")
        XCTAssertEqual(snap.highlight, ["wheel"])
        let partsEnd = plain.indices.count / 3
        XCTAssertEqual(a.arrows[0].firstTriangle, partsEnd)
        XCTAssertEqual(a.arrows[0].triangleCount, MGSolidAnnotations.arcChords * 32 + 16)
        XCTAssertEqual(a.dimensions[0].firstTriangle + a.dimensions[0].triangleCount, snap.indices.count / 3)
        XCTAssertEqual(a.arrows[0].direction.count, 3)
        let data = try snap.jsonData()
        let back = try JSONDecoder().decode(MGSolidSnapshot.self, from: data)
        XCTAssertEqual(back, snap)
        XCTAssertEqual(try back.jsonData(), data, "re-encode is byte-identical")
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains(#""occluded":"#), "placements write every field")
    }

    func testP10SnapshotWithoutAnnotationsIsUnchanged() throws {
        for name in ["idler-gearbox", "horizontal-reduction"] {
            let d = try model(name)
            for step in [nil] + d.steps.indices.map({ Optional($0) }) {
                let snap = MGSolidSnapshot.make(d, step: step, params: MGPoseParameters(input: 0.4, explode: 0.3))
                let reference = MGSolidSnapshot.build(d.assembly, view: d.view(step: step), params: MGPoseParameters(input: 0.4, explode: 0.3),
                                                      camera: nil, aspect: 16.0 / 10, lighting: .studio, stage: MGSolidStage.zUpToYUp)
                XCTAssertEqual(try snap.jsonData(), try reference.jsonData(), name)
                let keys = try XCTUnwrap(try JSONSerialization.jsonObject(with: snap.jsonData()) as? [String: Any]).keys
                XCTAssertFalse(keys.contains("annotations")); XCTAssertFalse(keys.contains("highlight"))
            }
        }
    }

    func testP11CorruptAnnotationFieldsFailToDecode() throws {
        let d = try winchStep()
        let data = try MGSolidSnapshot.make(d, step: 0, params: d.defaults, highlight: ["wheel"]).jsonData()
        func decodes(_ edit: (inout [String: Any]) -> Void) throws -> Bool {
            var o = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            edit(&o)
            return (try? JSONDecoder().decode(MGSolidSnapshot.self, from: JSONSerialization.data(withJSONObject: o))) != nil
        }
        func annotations(_ o: inout [String: Any], _ f: (inout [String: Any]) -> Void) {
            var a = o["annotations"] as! [String: Any]; f(&a); o["annotations"] = a
        }
        XCTAssertTrue(try decodes { _ in })
        XCTAssertFalse(try decodes { o in annotations(&o) { a in var r = a["arrows"] as! [[String: Any]]; r[0]["triangleCount"] = 1_000_000_000; a["arrows"] = r } })
        XCTAssertFalse(try decodes { o in annotations(&o) { a in var r = a["arrows"] as! [[String: Any]]; r[0]["firstTriangle"] = 0; a["arrows"] = r } })
        XCTAssertFalse(try decodes { o in annotations(&o) { a in var r = a["arrows"] as! [[String: Any]]; r[0]["direction"] = [0, 2, 0]; a["arrows"] = r } })
        XCTAssertFalse(try decodes { o in annotations(&o) { a in var r = a["arrows"] as! [[String: Any]]; r[0]["colorRole"] = "pink"; a["arrows"] = r } })
        XCTAssertFalse(try decodes { o in annotations(&o) { a in var r = a["dimensions"] as! [[String: Any]]; r[0]["points"] = [[0, 0, 0]]; a["dimensions"] = r } })
        XCTAssertFalse(try decodes { o in annotations(&o) { a in var r = a["placement"] as! [[String: Any]]; r[0]["id"] = "nobody"; a["placement"] = r } })
        XCTAssertFalse(try decodes { o in annotations(&o) { a in var r = a["labels"] as! [[String: Any]]; r[0]["id"] = "aWheel"; a["labels"] = r } })
        XCTAssertFalse(try decodes { o in o["highlight"] = ["nothing"] })
    }

    func testP12SnapshotV1WithAnnotationsFailsToDecode() throws {
        let d = try winchStep()
        let data = try MGSolidSnapshot.make(d, step: 0, params: d.defaults).jsonData()
        var o = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        // Strip every v2 part field so only `annotations` marks the file as v2.
        o["format"] = MGSolidSnapshot.formatV1
        o["parts"] = (o["parts"] as! [[String: Any]]).map { var p = $0; p.removeValue(forKey: "opacity"); return p }
        o["materials"] = (o["materials"] as! [[String: Any]]).map { var m = $0; m.removeValue(forKey: "emission"); return m }
        XCTAssertNil(try? JSONDecoder().decode(MGSolidSnapshot.self, from: JSONSerialization.data(withJSONObject: o)))
        o.removeValue(forKey: "annotations")
        XCTAssertNotNil(try? JSONDecoder().decode(MGSolidSnapshot.self, from: JSONSerialization.data(withJSONObject: o)))
        o["highlight"] = ["wheel"]
        XCTAssertNil(try? JSONDecoder().decode(MGSolidSnapshot.self, from: JSONSerialization.data(withJSONObject: o)))
    }

    func testP13FrameRecordEqualsSnapshotPlacement() throws {
        let d = try winchStep()
        let params = d.defaults
        let snap = MGSolidSnapshot.make(d, step: 0, params: params, highlight: d.steps[0].highlight)
        let frame = MGSolidAnnotations.frame(document: d, view: d.view(step: 0), params: params, camera: snap.camera, aspect: snap.aspect,
                                             highlight: d.steps[0].highlight, caption: true)
        XCTAssertEqual(frame.placement, snap.annotations?.placement)
        XCTAssertEqual(frame.anchors.map(\.id), d.steps[0].annotate)
        XCTAssertEqual(frame.height, MGAnnotationLayout.referenceHeight)
    }

    // MARK: P14, P15 renderers

    @MainActor func testP14OverlayTextFitsItsBox() throws {
        // At the limit (60 scalars) the text draws on two lines, each fitted in the box.
        let long = "ABCDEFGHIJKLMNOPQRSTUVWXYZ WWWWWWWWWWWWW abcdefghijklmnopqrs"
        XCTAssertEqual(long.unicodeScalars.count, MGSolidAnnotationLimits.text)
        XCTAssertEqual(MGAnnotationLayout.lines(long).count, 2)
        let text = #"{"v": 2, "kind": "assembly", "parts": [{"id": "core", "shape": {"box": {"size": [20, 20, 10]}}}], "annotations": {"labels": [{"id": "l1", "at": "core", "text": "\#(long)"}, {"id": "l2", "at": {"part": "core", "offset": [10, 0, 0]}, "text": "MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM"}]}, "steps": [{"say": "Long."}]}"#
        let d = try doc(text)
        for (w, h) in [(1024.0, 768.0), (640.0, 400.0)] {
            let f = MGSolidAnnotations.frame(document: d, view: d.view(step: 0), params: d.defaults,
                                             camera: MGSolidAnnotations.defaultCamera(d, params: d.defaults, aspect: w / h), width: w, height: h, caption: true)
            for p in f.placement {
                let boxWidth = p.box[2] * w
                let shown = p.callout.map { "\($0 + 1). " + p.text } ?? p.text
                for line in MGAnnotationLayout.lines(shown) {
                    let fit = MGSolidOverlay.fit(line, width: boxWidth - 12, fontSize: f.fontSize)
                    XCTAssertLessThanOrEqual(fit.width, boxWidth - 12 + 1e-9, "\(p.id) at \(w)x\(h)")
                    XCTAssertEqual(MGSolidOverlay.textWidth(line, fontSize: fit.size), fit.width, accuracy: 1e-9)
                }
            }
            let renderer = ImageRenderer(content: MGSolidOverlayView(frame: f, document: d).frame(width: w, height: h))
            let image = try XCTUnwrap(renderer.cgImage)
            XCTAssertEqual(image.width, Int(w))
            // The CoreGraphics drawer (marty-solid render) draws the same records without trapping.
            let ctx = try XCTUnwrap(CGContext(data: nil, width: Int(w), height: Int(h), bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            MGSolidOverlay.draw(f, document: d, legend: true, in: ctx, width: Int(w), height: Int(h))
            XCTAssertNotNil(ctx.makeImage())
        }
    }

    func testP15SceneKitSpinMovesNodesWithoutRebuildingGeometry() throws {
        // A linear slide (its motion arrow) and a turning disc (its turn arrow): linear chains, as the rules require.
        let text = #"{"v": 2, "kind": "assembly", "parts": [\#(SolidAnnotationTests.linearParts), {"id": "crank", "at": [0, -40, 0], "shape": {"shaft": {"radius": 6, "length": 4}}, "joint": {"revolute": [0, 0, 1]}, "drive": {"input": 1}}], "annotations": {"arrows": [{"id": "aRod", "meaning": "motion", "from": {"part": "s", "point": "centre"}}, {"id": "aCrank", "meaning": "motion", "style": "turn", "on": "crank"}]}, "steps": [{"say": "Spin.", "spin": 1}]}"#
        let d = try doc(text)
        let r = MGSolidRenderer(document: d)
        r.show(document: d, view: d.view(step: 0))
        func nodes(_ id: String) -> [SCNNode] { r.scene.rootNode.childNodes(passingTest: { n, _ in n.name == "annotation.\(id)" }) }
        let rod = nodes("aRod"), crank = nodes("aCrank")
        XCTAssertEqual(rod.count, 2)
        XCTAssertEqual(crank.count, MGSolidAnnotations.arcChords + 1)
        let geometries = (rod + crank).map { ObjectIdentifier($0.geometry!) }
        var starts: [Double] = []
        for k in 0...24 {
            // Inside the step exactly: k / 24 × (spin × 2π), the last equal to the step end.
            let params = MGPoseParameters(input: Double(k) / 24 * 2 * .pi)
            r.apply(params)
            XCTAssertEqual((rod + crank).map { ObjectIdentifier($0.geometry!) }, geometries, "no geometry rebuild")
            let prims = MGSolidAnnotations.primitives(d, "aRod", params: params)
            let m = rod[0].simdTransform
            XCTAssertEqual(Double(m.columns.3.x), prims[0].start.x, accuracy: 1e-3, "the shaft follows the pose")
            XCTAssertGreaterThan(m.columns.2.x, 0, "the slide moves +X at every pose")
            starts.append(Double(m.columns.3.x))
            // The turn arc rides the crank's parent frame (the world): it does not spin with the crank.
            let still = MGSolidRenderer.pieceMatrix(MGSolidAnnotations.primitives(d, "aCrank", params: MGPoseParameters())[0])
            for c in 0..<4 { for e in 0..<4 { XCTAssertEqual(crank[0].simdTransform[c][e], still[c][e], accuracy: 1e-3) } }
        }
        XCTAssertEqual(starts.last! - starts.first!, 2 * .pi, accuracy: 1e-3, "the arrow rides the slide one turn's travel")
        r.show(MGSolidView(d.assembly))
        XCTAssertTrue((rod + crank).allSatisfy(\.isHidden), "a view without annotations hides them")
        XCTAssertTrue((rod + crank).allSatisfy { !$0.castsShadow })
        r.highlightAnnotations(["aRod"])
        XCTAssertEqual(Double(rod[0].geometry?.firstMaterial?.emission.intensity ?? 0), 1.6, accuracy: 1e-6)
        XCTAssertEqual(Double(crank[0].geometry?.firstMaterial?.emission.intensity ?? 0), 0.6, accuracy: 1e-6)
    }

    // MARK: The one gate (review 2, R3, R5, R6)

    /// A host view or pose that the engine did not check shows no annotations in any output path.
    func testUncheckedViewsAndPosesShowNothingAnywhere() throws {
        let d = try doc(#"{"v": 2, "kind": "assembly", "parts": [{"id": "p", "shape": {"shaft": {"radius": 1, "length": 2}}, "joint": {"revolute": [0, 0, 1]}, "drive": {"input": 1}}], "annotations": {"dimensions": [{"id": "gap", "a": {"world": [10, 0, 0]}, "b": {"part": "p", "offset": [20, 0, 0]}}], "arrows": [{"id": "g", "meaning": "force", "cause": "gravity", "from": "p", "to": {"part": "p", "offset": [0, 0, -10]}}]}, "steps": [{"say": "Still."}]}"#)
        let cam = MGSolidAnnotations.defaultCamera(d, params: d.defaults)
        let good = d.view(step: nil)
        XCTAssertEqual(d.checkedAnnotations(good, params: d.defaults), ["g", "gap"], "authored order: arrows, then dimensions")
        var host = MGSolidView(d.assembly)
        host.annotations = ["gap", "g"]
        let away = MGPoseParameters(input: .pi)
        for (view, params) in [(host, d.defaults), (good, away), (good, MGPoseParameters(input: 0, explode: 0.5))] {
            XCTAssertNil(d.checkedAnnotations(view, params: params))
            let f = MGSolidAnnotations.frame(document: d, view: view, params: params, camera: cam, width: 1280, height: 800)
            XCTAssertEqual(f.refusal, .unchecked); XCTAssertEqual(f.placement, []); XCTAssertEqual(f.anchors.count, 0)
        }
        XCTAssertNil(MGSolidSnapshot.make(d, step: nil, params: away).annotations)
        XCTAssertNotNil(MGSolidSnapshot.make(d, step: nil, params: d.defaults).annotations)
        let r = MGSolidRenderer(document: d)
        func shown() -> Int { r.scene.rootNode.childNodes(passingTest: { n, _ in n.name?.hasPrefix("annotation.") == true && !n.isHidden }).count }
        r.show(document: d, view: good); r.apply(d.defaults)
        XCTAssertGreaterThan(shown(), 0)
        r.annotationsHidden = true
        XCTAssertEqual(shown(), 0, "the renderer switch hides pieces")
        r.annotationsHidden = false
        XCTAssertGreaterThan(shown(), 0)
        r.apply(away)
        XCTAssertEqual(shown(), 0, "a pose outside the view hides every piece")
        r.show(document: d, view: host); r.apply(d.defaults)
        XCTAssertEqual(shown(), 0, "a host-built view hides every piece")
        r.show(good)
        XCTAssertEqual(shown(), 0, "show(_:) without the document shows no annotations")
        // A view lists exactly what its step shows (a host hides annotations with the renderer switch instead).
        var fewer = good; fewer.annotations = ["g"]
        XCTAssertNil(d.checkedAnnotations(fewer, params: d.defaults))
        var more = d.view(step: 0); more.annotations += ["nobody"]
        XCTAssertNil(d.checkedAnnotations(more, params: d.defaults))
        // Third review (C4): a view is bound to its document's fingerprint and its step's playback sense.
        var flipped = good; flipped.motionSense = -1
        XCTAssertNil(d.checkedAnnotations(flipped, params: d.defaults), "a changed playback sense")
        var twice = good; twice.annotations = ["g", "g"]
        XCTAssertNil(d.checkedAnnotations(twice, params: d.defaults), "an id listed twice")
        let other = try doc(#"{"v": 2, "kind": "assembly", "parts": [{"id": "p", "shape": {"shaft": {"radius": 1, "length": 2}}, "joint": {"revolute": [0, 0, 1]}, "drive": {"input": 1}}], "annotations": {"dimensions": [{"id": "gap", "a": {"world": [12, 0, 0]}, "b": {"part": "p", "offset": [20, 0, 0]}}], "arrows": [{"id": "g", "meaning": "force", "cause": "gravity", "from": "p", "to": {"part": "p", "offset": [0, 0, -10]}}]}, "steps": [{"say": "Still."}]}"#)
        XCTAssertNil(d.checkedAnnotations(other.view(step: nil), params: d.defaults), "a view of another document")
        XCTAssertNotNil(other.checkedAnnotations(other.view(step: nil), params: other.defaults))
        // Fourth review (D2): exact poses only. A still step accepts exactly the default input, not the next Double.
        XCTAssertNil(d.checkedAnnotations(good, params: MGPoseParameters(input: d.defaults.input.nextUp)))
        XCTAssertNil(d.checkedAnnotations(good, params: MGPoseParameters(input: d.defaults.input, explode: 1e-300)))
        // R5: a bad view size has its own refusal.
        XCTAssertEqual(MGSolidAnnotations.frame(document: d, view: good, params: d.defaults, camera: cam, width: 0, height: 700).refusal, .viewSize)
    }

    /// Fifth review (E2): the renderer draws annotations only against the assembly of the document they belong to.
    func testRendererDrawsAnnotationsOnlyForItsOwnDocument() throws {
        let text = #"{"v": 2, "kind": "assembly", "parts": [{"id": "s", "shape": {"box": {"size": [4, 4, 4]}}, "joint": {"prismatic": [1, 0, 0]}, "drive": {"input": 1}}], "annotations": {"arrows": [{"id": "m", "meaning": "motion", "from": "s", "expect": [1, 0, 0]}]}, "steps": [{"say": "Moves.", "spin": 1}]}"#
        let d = try doc(text)
        func shown(_ r: MGSolidRenderer) -> Int { r.scene.rootNode.childNodes(passingTest: { n, _ in n.name?.hasPrefix("annotation.") == true && !n.isHidden }).count }
        var displayed = d.assembly
        displayed.parts[0].drive = .input(scale: -1, offset: 0)
        let foreign = MGSolidRenderer(assembly: displayed)
        foreign.show(document: d, view: d.view(step: 0)); foreign.apply(MGPoseParameters(input: 1))
        XCTAssertEqual(shown(foreign), 0, "an assembly given on its own never shows a document's annotations")
        let r = MGSolidRenderer(document: d)
        r.show(document: d, view: d.view(step: 0)); r.apply(MGPoseParameters(input: 1))
        XCTAssertEqual(shown(r), 2)
        r.setAssembly(displayed)
        r.show(document: d, view: d.view(step: 0)); r.apply(MGPoseParameters(input: 1))
        XCTAssertEqual(shown(r), 0, "after setAssembly the old document's annotations do not come back")
        let other = try doc(text.replacingOccurrences(of: #""say": "Moves.""#, with: #""say": "Slides.""#))
        r.setDocument(other)
        r.show(document: d, view: d.view(step: 0)); r.apply(MGPoseParameters(input: 1))
        XCTAssertEqual(shown(r), 0, "a document the renderer was not loaded with")
        r.show(document: other, view: other.view(step: 0)); r.apply(MGPoseParameters(input: 1))
        XCTAssertEqual(shown(r), 2)
    }

    /// Sixth review (F1): loading a document and showing its view poses the parts before the annotations attach, with no
    /// `apply` in between, so the part and its checked dimension agree.
    func testShowAfterLoadingPosesThePartsFirst() throws {
        func text(_ x: Int) -> String {
            #"{"v": 2, "kind": "assembly", "parts": [{"id": "p", "at": [\#(x), 0, 0], "shape": {"box": {"size": [10, 10, 10]}}}], "annotations": {"dimensions": [{"id": "gap", "a": {"world": [0, 0, 0]}, "b": {"part": "p", "point": "centre"}, "text": "Centre {dim.gap}"}]}, "steps": [{"say": "Measure."}]}"#
        }
        let previous = try doc(text(10)), next = try doc(text(110))
        XCTAssertEqual(next.fact("dim.gap")?.value ?? 0, 110, accuracy: 1e-12)
        func check(_ r: MGSolidRenderer, file: StaticString = #filePath, line: UInt = #line) {
            let part = r.scene.rootNode.childNode(withName: "p", recursively: true)!
            let pieces = r.scene.rootNode.childNodes(passingTest: { n, _ in n.name == "annotation.gap" })
            XCTAssertEqual(Double(part.simdTransform.columns.3.x), 110, accuracy: 1e-3, "the part sits where the document puts it", file: file, line: line)
            XCTAssertFalse(pieces[0].isHidden, file: file, line: line)
            // The dimension line runs from the origin to the part's centre.
            let lineEnd = pieces[0].simdTransform.columns.3 + pieces[0].simdTransform.columns.2
            XCTAssertEqual(Double(lineEnd.x), Double(part.simdTransform.columns.3.x), accuracy: 1e-3, file: file, line: line)
            let image = r.render(width: 320, height: 200)
            if image == nil { print("F1: no Metal device; the node check above still ran") }
        }
        let r = MGSolidRenderer(document: previous)
        r.show(document: previous, view: previous.view(step: 0))
        r.apply(previous.defaults)
        r.setDocument(next)
        r.show(document: next, view: next.view(step: 0))   // no apply
        check(r)
        let fresh = MGSolidRenderer(document: next)
        fresh.show(document: next, view: next.view(step: 0))   // no apply
        check(fresh)
    }

    /// R6: `marty-solid render` draws annotations on hero.png and the step stills only, never on exploded.png or a loop
    /// frame, whatever their pose.
    func testRenderPlanShowsAnnotationsOnHeroAndStepsOnly() throws {
        let d = try model("annotated-winch")
        let plan = MGSolidRenderPlan(d, sourceName: "w.json", source: MGSolidSource(data: Data("{}".utf8)))
        XCTAssertEqual(plan.stills.filter(\.showsAnnotations).map(\.file), ["hero.png"] + d.steps.indices.map { "step-\($0 + 1).png" })
        XCTAssertTrue(plan.loop.allSatisfy { !$0.showsAnnotations })
    }

    // MARK: Shipped example

    /// Review of PR #31, B1: every step of the example, sampled over its whole spin range at its explode value, keeps
    /// each shown claim: the dimension line length equals its text, the gravity arrow points down, the rope-side arrow
    /// points up, and turn arcs keep the engine's sense.
    func testEveryStepRangeOfTheExampleKeepsItsClaims() throws {
        let d = try model("annotated-winch")
        for i in d.steps.indices {
            let view = d.view(step: i)
            // The engine proves this without sampling; the test samples the range densely as an outside check.
            let (u0, spin, explode) = MGSolidAnnotationEngine.domain(d, step: i)
            let n = spin == 0 ? 0 : Int((abs(spin) * 1440).rounded(.up))
            let u1 = u0 + spin * 2 * .pi
            let inputs = (0...n).map { k in k == n ? u1 : u0 + 2 * .pi * spin * Double(k) / Double(n) }.filter { $0 >= min(u0, u1) && $0 <= max(u0, u1) }
            for u in inputs {
                XCTAssertEqual(d.checkedAnnotations(view, params: MGPoseParameters(input: u, explode: explode)), view.annotations)
                let params = MGPoseParameters(input: u, explode: explode)
                for id in view.annotations {
                    let prims = MGSolidAnnotations.primitives(d, id, params: params, sense: view.motionSense)
                    if let dim = d.annotations.dimension(id) {
                        XCTAssertEqual((prims[0].end - prims[0].start).length, dim.value, accuracy: 0.01, "step \(i + 1) \(id) at \(u)")
                    }
                    if id == "aWeight" { XCTAssertLessThan(MGSolidAnnotationEngine.angle(prims[1].end - prims[0].start, MGVec3(0, 0, -1)), 1e-6) }
                    if id == "aLift" { XCTAssertLessThan(MGSolidAnnotationEngine.angle(prims[1].end - prims[0].start, MGVec3(0, 0, 1)), 30) }
                }
            }
        }
        XCTAssertEqual(d.steps.last?.spin, 0, "the rope-side arrow shows in a still step")
    }

    /// The annotated winch: every step's texts are placed (no callouts) without collisions at the CLI render size and
    /// camera, and it passes the strict profile with no warnings.
    func testAnnotatedWinchExample() throws {
        let d = try model("annotated-winch")
        guard case .success = MGSolidParser.document(json: d.source, profile: .strict) else { return XCTFail("strict") }
        XCTAssertEqual(d.warnings, [])
        XCTAssertEqual(d.legend.text, "Solved 12")
        XCTAssertEqual(d.legend.notes, ["Arrow lengths are not to scale"])
        XCTAssertEqual(d.steps.map(\.say)[1], "The drum gear has 42 teeth, so it turns 1/3 of a turn, the other way.")
        XCTAssertEqual(d.steps.map(\.say)[2], "The gear centres are 56 mm apart: half the sum of the tooth counts, times the module.")
        // Up, within the few degrees the drum's tooth phase turns it at input 0.
        XCTAssertEqual(d.annotations.arrow("aLift")?.direction.map { $0.z } ?? 0, 1, accuracy: 0.01)
        XCTAssertEqual(d.annotations.arrows.compactMap(\.turnSign), [1, -1])
        let r = MGSolidRenderer(assembly: d.assembly)
        for (i, step) in d.steps.enumerated() {
            let params = MGPoseParameters(input: d.defaults.input + step.spin * 2 * .pi, explode: step.explode ?? d.defaults.explode)
            let preset = MGSolidCamera.presets[step.camera ?? "hero"]!
            r.apply(params)
            r.frame(params, explodeRange: [0, params.explode], yaw: preset.yaw + step.orbit, pitch: preset.pitch, aspect: 1.6, margin: 0.8)
            let f = MGSolidAnnotations.frame(document: d, view: d.view(step: i), params: params, camera: r.camera, width: 1280, height: 800,
                                             highlight: step.highlight, caption: true, title: true)
            let texts = (step.annotate ?? []).filter { d.annotations.kind($0) != "arrow" || d.annotations.arrow($0)?.text != nil }
            assertRules(f, caption: true, title: true, ids: texts)
            XCTAssertTrue(f.placement.allSatisfy { $0.callout == nil }, "step \(i + 1): every text placed")
        }
    }
}
