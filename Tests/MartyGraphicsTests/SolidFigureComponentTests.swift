// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import MartyGraphics

/// The `mannequin` and `centrifugalCompressor` built-ins: geometry, joints, anchors, parameters, checks, exact mesh
/// counts and strict checks over every parameter corner.
final class SolidFigureComponentTests: XCTestCase {
    let lib = MGSolidLibrary.builtIn

    func compile(_ s: String) -> Result<MGSolidDocument, MGSolidIssue> { MGSolidParser.document(data: Data(s.utf8)) }
    func use(_ id: String, _ with: [String: Double] = [:], extra: String = "") -> String {
        let w = with.keys.sorted().map { "\"\($0)\": \(with[$0]!)" }.joined(separator: ", ")
        return #"{"v": 2, "kind": "assembly", "parts": [{"id": "a", "use": "\#(id)", "with": {\#(w)}}\#(extra)], "steps": [{"say": "One step."}]}"#
    }
    /// World (kernel, Z up) bounds of one part at the default pose.
    func bounds(_ d: MGSolidDocument, _ id: String) -> MGBounds {
        let t = d.assembly.pose(d.defaults).world[id] ?? .identity
        var b = MGBounds.empty
        for p in d.assembly.part(id)!.mesh.positions { b.include(t.apply(p)) }
        return b
    }
    func triangles(_ d: MGSolidDocument) -> Int { d.assembly.parts.reduce(0) { $0 + $1.mesh.triangleCount } }
    func estimate(_ d: MGSolidDocument) -> Int {
        d.assembly.parts.reduce(0) { sum, p in sum + (d.shapes[p.id] ?? []).reduce(0) { $0 + $1.meshEstimate.triangles } }
    }

    func testCatalogEntries() throws {
        guard case .array(let entries)? = lib.catalog()["components"] else { return XCTFail("catalog") }
        let m = try XCTUnwrap(entries.first { $0["id"] == .string("mannequin") })
        XCTAssertEqual(m["anchors"], .object(["back": .string("body"), "head": .string("skull"), "leftShoulder": .string("upperArmL"),
                                              "rightShoulder": .string("upperArmR"), "leftHand": .string("handL"), "rightHand": .string("handR"),
                                              "leftFoot": .string("footL"), "rightFoot": .string("footR")]))
        XCTAssertEqual(m["params"]?["leftShoulder"]?["default"], .number(10))
        let c = try XCTUnwrap(entries.first { $0["id"] == .string("centrifugalCompressor") })
        XCTAssertEqual(c["anchors"], .object(["input": .string("impeller"), "frame": .string("diffuser")]))
        XCTAssertEqual(c["params"]?["vanes"]?["integer"], .bool(true))
    }

    // MARK: mannequin

    func testMannequinStandsOnTheFloorFacingMinusY() throws {
        let d = try compile(use("mannequin")).get()
        XCTAssertEqual(d.assembly.parts.map(\.id), ["a.body", "a.skull", "a.upperArmL", "a.lowerArmL", "a.handL", "a.upperArmR", "a.lowerArmR",
                                                    "a.handR", "a.legL", "a.footL", "a.legR", "a.footR"])
        XCTAssertEqual(triangles(d), 26_048)
        XCTAssertEqual(estimate(d), triangles(d))
        var all = MGBounds.empty
        for p in d.assembly.parts { all = all.union(bounds(d, p.id)) }
        XCTAssertEqual(all.min.z, 0, accuracy: 0.5)                 // soles on the floor
        XCTAssertEqual(all.max.z, 1763, accuracy: 0.5)              // top of the head
        XCTAssertLessThan(bounds(d, "a.footL").min.y, -200)        // toes point to -Y
        XCTAssertLessThan(bounds(d, "a.skull").min.y, -100)        // the nose is on the -Y side
        XCTAssertGreaterThan(bounds(d, "a.handL").center.x, 0)     // left side is +X
        XCTAssertLessThan(bounds(d, "a.handR").center.x, 0)
        // Anchor frames: the back anchor sits on the upper back, the feet at the soles, the shoulders at the joints.
        let w = d.assembly.pose(d.defaults).world
        XCTAssertEqual(w["a.body"]?.translation, MGVec3(0, 125, 1340))
        XCTAssertEqual(w["a.footL"]?.translation, MGVec3(95, 0, 0))
        XCTAssertEqual(w["a.upperArmL"]?.translation, MGVec3(205, 0, 1430))
        XCTAssertEqual(w["a.upperArmR"]?.translation, MGVec3(-205, 0, 1430))
        XCTAssertEqual(d.aliases["a.leftHand"], "a.handL")
        XCTAssertEqual(d.aliases["a.back"], "a.body")
    }

    func testMannequinArmAnglesAreHeldJoints() throws {
        let d = try compile(use("mannequin", ["leftShoulder": 90, "rightShoulder": 90, "leftElbow": 90, "rightElbow": 0])).get()
        let w = d.assembly.pose(d.defaults).world
        // Left arm straight out to +X at shoulder height; the forearm bent 90 degrees forward (to -Y).
        let elbowL = try XCTUnwrap(w["a.lowerArmL"]).translation, wristL = try XCTUnwrap(w["a.handL"]).translation
        XCTAssertEqual(elbowL.x, 505, accuracy: 1e-9); XCTAssertEqual(elbowL.z, 1430, accuracy: 1e-9)
        XCTAssertEqual(wristL.y, -268, accuracy: 1e-9); XCTAssertEqual(wristL.x, 505, accuracy: 1e-9)
        // Right arm out to -X, straight.
        XCTAssertEqual(try XCTUnwrap(w["a.handR"]).translation.x, -773, accuracy: 1e-9)
        // The joints are revolute and held: no input turn or explode moves them.
        for id in ["a.upperArmL", "a.lowerArmL", "a.upperArmR", "a.lowerArmR"] {
            guard case .revolute? = d.assembly.part(id)?.joint else { return XCTFail(id) }
            let a = d.assembly.pose(MGPoseParameters(input: 0, explode: 0)).world[id]!
            let b = d.assembly.pose(MGPoseParameters(input: 5, explode: 1)).world[id]!
            XCTAssertEqual(a, b, id)
        }
        XCTAssertEqual(d.motionSources["a.upperArmL"], "input")
    }

    /// Every corner of the parameter ranges passes the strict profile with no warning (no idle joint, no axis off its
    /// part, no far or absolute child).
    func testMannequinCornersPassStrict() throws {
        for ls in [4.0, 170] { for rs in [4.0, 170] { for le in [0.0, 150] { for re in [0.0, 150] {
            let r = MGSolidReport.check(data: Data(use("mannequin", ["leftShoulder": ls, "rightShoulder": rs, "leftElbow": le, "rightElbow": re]).utf8),
                                        profile: .strict)
            XCTAssertNil(r.reason, "\(ls) \(rs) \(le) \(re)")
            XCTAssertEqual(r.json["warnings"], .array([]), "\(ls) \(rs) \(le) \(re)")
        } } } }
        if case .failure(let e) = compile(use("mannequin", ["leftShoulder": 2])) { XCTAssertEqual(e.reason, "component.param.range.leftShoulder") }
        else { XCTFail("range") }
    }

    /// Parts attach to the anchors: an engine on the right hand moves with the arm angle.
    func testPartsAttachToMannequinAnchors() throws {
        let engine = #", {"id": "jet", "parent": "a.rightHand", "at": [0, -60, 120], "shape": {"shaft": {"radius": 40, "length": 250, "z0": -150}}}"#
        let down = try compile(use("mannequin", ["rightShoulder": 10], extra: engine)).get()
        let out = try compile(use("mannequin", ["rightShoulder": 80], extra: engine)).get()
        let a = down.assembly.pose(down.defaults).world["jet"]!.translation, b = out.assembly.pose(out.defaults).world["jet"]!.translation
        XCTAssertLessThan(b.x, a.x - 300)
        XCTAssertGreaterThan(b.z, a.z + 300)
    }

    // MARK: centrifugalCompressor

    func testCompressorPartsCountsAndBudget() throws {
        let d = try compile(use("centrifugalCompressor")).get()
        XCTAssertEqual(d.assembly.parts.count, 1 + 7 + 7 + 1 + 12)
        XCTAssertEqual(triangles(d), 5_996)
        XCTAssertEqual(estimate(d), triangles(d))
        let big = try compile(use("centrifugalCompressor", ["vanes": 12, "diffuserVanes": 12, "diameter": 1000, "bore": 70])).get()
        XCTAssertEqual(big.assembly.parts.count, 1 + 12 + 12 + 1 + 12)
        XCTAssertEqual(estimate(big), triangles(big))
        XCTAssertLessThan(triangles(big), 10_000)
        for p in big.assembly.parts { XCTAssertTrue(p.mesh.edgeReport.isClosed, p.id) }
    }

    func testCompressorGeometry() throws {
        let dia = 200.0
        let d = try compile(use("centrifugalCompressor", ["diameter": dia, "vanes": 8])).get()
        // The impeller turns with the input; vanes and splitters ride on it.
        XCTAssertEqual(d.motionSources["a.impeller"], "input")
        XCTAssertEqual(d.assembly.part("a.vane1")?.parent, "a.impeller")
        // Tip at the diameter, diffuser vanes outside the tip.
        var imp = MGBounds.empty
        for id in ["a.impeller"] + (1...8).map({ "a.vane\($0)" }) { imp = imp.union(bounds(d, id)) }
        XCTAssertEqual(imp.max.x, dia / 2, accuracy: 0.5)
        let dv = d.assembly.part("a.diffuserVane1")!.mesh.positions.map { MGVec2($0.x, $0.y).length }
        XCTAssertGreaterThan(dv.min()!, 0.54 * dia)
        // Backswept: along a main vane the outer end lags the inner end against the +θ turn.
        let vane = d.assembly.part("a.vane1")!.mesh.positions
        func angle(_ p: MGVec3) -> Double { atan2(p.y, p.x) }
        let inner = vane.filter { MGVec2($0.x, $0.y).length < 0.2 * dia }.map(angle), outer = vane.filter { MGVec2($0.x, $0.y).length > 0.45 * dia }.map(angle)
        XCTAssertLessThan(outer.max()!, inner.min()! - 0.2)
        // Splitters sit half a vane pitch ahead of the main vanes.
        let w = d.assembly.pose(d.defaults).world
        let s1 = w["a.splitter1"]!.c0, v1 = w["a.vane1"]!.c0
        XCTAssertEqual(atan2(s1.y, s1.x) - atan2(v1.y, v1.x), .pi / 8, accuracy: 1e-9)
    }

    func testCompressorChecksAndCornersPassStrict() throws {
        guard case .failure(let e) = compile(use("centrifugalCompressor", ["diameter": 100, "bore": 7.5])) else { return XCTFail("bore") }
        XCTAssertEqual(e.reason, "component.check.bore")
        guard case .failure(let v) = compile(use("centrifugalCompressor", ["vanes": 13])) else { return XCTFail("vanes") }
        XCTAssertEqual(v.reason, "component.param.range.vanes")
        guard case .failure(let i) = compile(use("centrifugalCompressor", ["vanes": 7.5])) else { return XCTFail("integer") }
        XCTAssertEqual(i.reason, "component.param.integer.vanes")
        // The real range endpoints: bore 70 is refused at diameter 30 (70 ≥ 0.075 × 30) by the check, on purpose.
        var accepted = 0, refused: [String] = []
        for dia in [30.0, 1000] { for vanes in [4.0, 12] { for dvs in [6.0, 12] { for bore in [0.5, 70] {
            let r = MGSolidReport.check(data: Data(use("centrifugalCompressor", ["diameter": dia, "vanes": vanes, "diffuserVanes": dvs, "bore": bore]).utf8),
                                        profile: .strict)
            if let reason = r.reason {
                refused.append(reason)
                XCTAssertTrue(dia == 30 && bore == 70, "\(dia) \(vanes) \(dvs) \(bore): \(reason)")
            } else {
                accepted += 1
                XCTAssertEqual(r.json["warnings"], .array([]), "\(dia) \(vanes) \(dvs) \(bore)")
            }
        } } } }
        XCTAssertEqual(accepted, 12)
        XCTAssertEqual(refused, Array(repeating: "component.check.bore", count: 4))
    }
}
