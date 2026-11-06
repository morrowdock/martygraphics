// SPDX-License-Identifier: Apache-2.0
import XCTest
import SceneKit
@testable import MartyGraphics

/// Fail-closed behaviour of the solid assembly format on invalid or hostile input: motion composition, mesh budget,
/// gear geometry, renderer bookkeeping and decoders.
final class SolidHardeningTests: XCTestCase {
    func compile(_ s: String) -> Result<MGSolidDocument, MGSolidIssue> { MGSolidParser.document(data: Data(s.utf8)) }
    func reason(_ s: String) -> String? {
        if case .failure(let e) = compile(s) { return e.reason }
        return nil
    }
    func doc(_ parts: String, _ constraints: String = "") -> String {
        "{\"v\": 1, \"kind\": \"assembly\", \"parts\": [\(parts)], \"constraints\": [\(constraints)]}"
    }
    func gear(_ z: Int, _ extra: String = "") -> String { "{\"gear\": {\"teeth\": \(z), \"module\": 2, \"width\": 8\(extra)}}" }
    let spin = "\"joint\": {\"revolute\": [0, 0, 1]}"

    // MARK: Parent rotation

    /// A pinion keyed to a driven shaft (no joint of its own) turns with the shaft; the wheel it drives must turn too.
    func testGearOnRotatingShaftComposesItsParentRotation() throws {
        let d = try compile(doc("""
            {"id": "shaft", "shape": {"shaft": {"radius": 3, "length": 30, "z0": -10}}, \(spin), "drive": {"input": 1}},
            {"id": "pinion", "parent": "shaft", "shape": \(gear(12, ", \"bore\": 3"))},
            {"id": "wheel", "at": [48, 0, 0], "shape": \(gear(36, ", \"bore\": 5")), \(spin)}
            """, "{\"gearMesh\": {\"a\": \"pinion\", \"b\": \"wheel\"}}")).get()
        XCTAssertEqual(d.ratios["wheel"]!, -12.0 / 36.0, accuracy: 1e-12)   // was 0: the pinion was treated as fixed
        for s in [0.4, 3.1] { for r in d.assembly.gearResiduals(MGPoseParameters(input: s)) { XCTAssertEqual(r, 0, accuracy: 1e-9) } }
        let report = MGSolidChecks.gearMeshes(d, samples: 48)
        XCTAssertLessThan(report.maxPenetration, 1e-6)
        XCTAssertLessThan(report.minClearance, 0.3)
    }

    func testUnsupportedMovingParentsAreRefused() {
        let wheel = "{\"id\": \"wheel\", \"at\": [68, 0, 0], \"shape\": \(gear(36)), \(spin)}"
        let mesh = "{\"gearMesh\": {\"a\": \"pinion\", \"b\": \"wheel\"}}"
        // An arm turns about the origin and carries the pinion off its axis, with no carrier named.
        let arm = "{\"id\": \"arm\", \"shape\": {\"box\": {\"size\": [60, 8, 4]}}, \(spin), \"drive\": {\"input\": 1}}"
        XCTAssertEqual(reason(doc("\(arm), {\"id\": \"pinion\", \"parent\": \"arm\", \"at\": [20, 0, 0], \"shape\": \(gear(12))}, \(wheel)", mesh)),
                       "constraint.gearMesh.parentRotates")
        // Same with the pinion on its own joint (a planet without its carrier).
        XCTAssertEqual(reason(doc("\(arm), {\"id\": \"pinion\", \"parent\": \"arm\", \"at\": [20, 0, 0], \"shape\": \(gear(12)), \(spin)}, \(wheel)", mesh)),
                       "constraint.gearMesh.parentRotates")
        // A slide moves the pinion's centre.
        let slide = "{\"id\": \"slide\", \"shape\": {\"box\": {\"size\": [8, 8, 4]}}, \"joint\": {\"prismatic\": [1, 0, 0]}, \"drive\": {\"input\": 5}}"
        XCTAssertEqual(reason(doc("\(slide), {\"id\": \"pinion\", \"parent\": \"slide\", \"at\": [20, 0, 0], \"shape\": \(gear(12))}, \(wheel)", mesh)),
                       "constraint.gearMesh.parentMoves")
        // A coaxial parent driven by `follow` is outside the linear solve.
        let motor = "{\"id\": \"motor\", \"at\": [0, -80, 0], \"shape\": {\"shaft\": {\"radius\": 3, \"length\": 10}}, \(spin), \"drive\": {\"input\": 1}}"
        let shaft = "{\"id\": \"shaft\", \"at\": [20, 0, 0], \"shape\": {\"shaft\": {\"radius\": 3, \"length\": 10}}, \(spin), \"drive\": {\"follow\": {\"source\": \"motor\", \"ratio\": 2}}}"
        XCTAssertEqual(reason(doc("\(motor), \(shaft), {\"id\": \"pinion\", \"parent\": \"shaft\", \"shape\": \(gear(12))}, \(wheel)", mesh)),
                       "constraint.gearMesh.parentDrive")
    }

    /// Compound gear: Y rides on X. Constraints list Y's mesh first and X has an authored phase, so X's phase knob
    /// turns after Y was phased; Y must be compensated and every pair must still interleave.
    func testCompoundGearKeepsPhaseAndRatio() throws {
        let d = try compile(doc("""
            {"id": "x", "shape": \(gear(40, ", \"bore\": 5")), \(spin), "drive": {"input": 1}, "phase": 7},
            {"id": "y", "parent": "x", "shape": \(gear(15, ", \"z0\": 10"))},
            {"id": "a", "at": [60, 0, 0], "shape": \(gear(20)), \(spin)},
            {"id": "b", "at": [0, 60, 0], "shape": \(gear(45, ", \"z0\": 10")), \(spin)}
            """, "{\"gearMesh\": {\"a\": \"y\", \"b\": \"b\"}}, {\"gearMesh\": {\"a\": \"x\", \"b\": \"a\"}}")).get()
        XCTAssertEqual(d.ratios["a"]!, -2, accuracy: 1e-12)
        XCTAssertEqual(d.ratios["b"]!, -15.0 / 45.0, accuracy: 1e-12)
        let report = MGSolidChecks.gearMeshes(d, samples: 60)
        XCTAssertLessThan(report.maxPenetration, 1e-6)
        XCTAssertLessThan(report.minClearance, 0.3)
    }

    /// Residuals follow each joint's axis direction, and a wrong ratio cannot report zero.
    func testResidualsRespectAxisDirectionAndCatchWrongRatios() throws {
        let d = try compile(doc("""
            {"id": "a", "shape": \(gear(20)), \(spin), "drive": {"input": 1}},
            {"id": "b", "at": [50, 0, 0], "shape": \(gear(30)), "joint": {"revolute": [0, 0, -1]}}
            """, "{\"gearMesh\": {\"a\": \"a\", \"b\": \"b\"}}")).get()
        XCTAssertEqual(d.ratios["b"]!, 2.0 / 3.0, accuracy: 1e-12)   // about -Z, so the opposite turn is positive
        for r in d.assembly.gearResiduals(MGPoseParameters(input: 1.3)) { XCTAssertEqual(r, 0, accuracy: 1e-9) }
        XCTAssertLessThan(MGSolidChecks.gearMeshes(d, samples: 36).maxPenetration, 1e-6)
        var wrong = d.assembly
        let k = wrong.parts.firstIndex { $0.id == "b" }!
        guard case .input(_, let offset)? = wrong.parts[k].drive else { return XCTFail("b must be input driven") }
        wrong.parts[k].drive = .input(scale: -2.0 / 3.0, offset: offset)
        XCTAssertGreaterThan(abs(wrong.gearResiduals(MGPoseParameters(input: 1.3))[0]), 1)
    }

    // MARK: Budget

    func testHostileMeshBudgetIsRefusedBeforeBuilding() {
        // 256-point closed revolve (96 segments), 8 shapes per part, repeated 12 times: about 4.7 M triangles.
        let pts = (0..<256).map { k -> String in
            let a = 2 * Double.pi * Double(k) / 256
            return "[\(Int((1500 + 1000 * cos(a)).rounded())), \(Int((1000 * sin(a)).rounded()))]"
        }.joined(separator: ",")
        let shape = "{\"revolvedProfile\": {\"closed\": true, \"points\": [\(pts)]}}"
        let json = doc("{\"id\": \"cup\", \"shape\": [\(Array(repeating: shape, count: 8).joined(separator: ","))], \"repeat\": {\"count\": 12}}")
        XCTAssertLessThan(json.utf8.count, MGSolidLimits.bytes)
        let t0 = Date()
        XCTAssertEqual(reason(json), "assembly.budget")
        XCTAssertLessThan(Date().timeIntervalSince(t0), 5, "the budget must refuse before meshes are built")
        // One copy of the part is well inside the budget.
        let one = try? compile(doc("{\"id\": \"cup\", \"shape\": [\(shape)]}")).get()
        XCTAssertEqual(one?.assembly.part("cup")?.mesh.triangleCount, 2 * 96 * 256)
    }

    /// The budget counts exactly what `mesh()` builds, for every primitive.
    func testMeshEstimateMatchesBuiltMeshes() throws {
        let kitchen = doc("""
            {"id": "g1", "shape": \(gear(24, ", \"bore\": 6, \"keyway\": [3, 1.6]"))},
            {"id": "g2", "at": [100, 0, 0], "shape": \(gear(9, ", \"pressureAngle\": 25"))},
            {"id": "r", "at": [0, 200, 0], "shape": {"ringGear": {"teeth": 50, "module": 2, "width": 10, "outer": 60}}},
            {"id": "s", "shape": [{"shaft": {"radius": 3, "length": 10}}, {"shaft": {"radius": 30, "length": 10, "chamfer": 1}},
                                  {"tube": {"inner": 4, "outer": 6, "length": 9}}, {"tube": {"inner": 4, "outer": 9, "length": 9, "chamfer": 0.5}},
                                  {"box": {"size": [4, 5, 6]}}, {"box": {"size": [4, 5, 6], "chamfer": 0.5}},
                                  {"hex": {"acrossFlats": 7, "length": 4}}, {"hex": {"acrossFlats": 7, "length": 4, "chamfer": 0.5}}]},
            {"id": "p", "shape": [{"plate": {"radius": 40, "thickness": 4, "chamfer": 0.5, "holes": [[0, 0, 5], [20, 0, 2], [-20, 0, 12]]}},
                                  {"carrier": {"arms": 3, "radius": 42, "hub": 15, "boss": 9.5, "armWidth": 13, "thickness": 6, "chamfer": 0.9}},
                                  {"extrudedProfile": {"points": [[0, 0], [40, 0], [40, 30], [0, 30]], "depth": 5, "chamfer": 0.5,
                                                       "holes": [[[5, 5], [10, 5], [10, 10], [5, 10]], [[20, 5], [30, 5], [25, 20]]]}},
                                  {"revolvedProfile": {"points": [[0, 0], [10, 0], [10, 5], [0, 5]]}},
                                  {"revolvedProfile": {"closed": true, "points": [[20, 0], [24, 0], [24, 5], [20, 5]]}},
                                  {"blade": {"span": 60, "chord": 14, "twist": -18, "root": 8, "camber": 0.04}}]},
            {"id": "t", "shape": [{"bladeRow": {"count": 24, "span": 80, "chord": 40, "root": 200}},
                                  {"bladeRow": {"count": 9, "span": 30, "chord": 12, "root": 60, "z": 50, "stagger": -35, "twist": 10,
                                                "camber": -0.06, "thickness": 0.2, "sections": 3, "chordSamples": 7}},
                                  {"revolvedProfile": {"closed": true, "sweep": 210, "start": -30, "points": [[20, 0], [24, 0], [24, 5], [20, 5]]}},
                                  {"revolvedProfile": {"closed": true, "sweep": 270, "start": 270, "points": [[30, 0], [36, 2], [33, 9]]}},
                                  {"revolvedProfile": {"sweep": 90, "points": [[0, 0], [10, 0], [12, 4], [10, 8], [0, 8]]}},
                                  {"revolvedProfile": {"closed": true, "sweep": 1, "points": [[40, 0], [44, 0], [44, 5], [40, 5]]}},
                                  {"revolvedProfile": {"closed": true, "sweep": 359.5, "points": [[50, 0], [54, 0], [54, 5]]}},
                                  {"revolvedProfile": {"closed": true, "sweep": 360, "points": [[60, 0], [64, 0], [64, 5]]}}]},
            {"id": "u", "shape": [{"revolvedProfile": {"closed": true, "sweep": 359.99999999, "points": [[70, 0], [74, 0], [74, 5]]}},
                                  {"revolvedProfile": {"sweep": 359.99999999, "start": 45, "points": [[0, 0], [10, 0], [10, 8], [0, 8]]}},
                                  {"revolvedProfile": {"closed": true, "sweep": 359.9999, "points": [[80, 0], [84, 0], [84, 5]]}}]}
            """)
        let turbofan = SolidAssemblyFormatTests.planetaryURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Turbofan/Sources/TurbofanKit/Models/turbofan.json")
        for json in [kitchen, String(decoding: try Data(contentsOf: SolidAssemblyFormatTests.planetaryURL), as: UTF8.self),
                     String(decoding: try Data(contentsOf: turbofan), as: UTF8.self)] {
            let d = try compile(json).get()
            for p in d.assembly.parts { for s in d.shapes[p.id]! {
                let m = s.mesh(), e = s.meshEstimate
                XCTAssertEqual(e.vertices, m.positions.count, "\(p.id) \(s.kind) vertices")
                XCTAssertEqual(e.triangles, m.triangleCount, "\(p.id) \(s.kind) triangles")
            } }
        }
        let planetary = try compile(String(decoding: try Data(contentsOf: SolidAssemblyFormatTests.planetaryURL), as: UTF8.self)).get()
        let total = planetary.assembly.parts.reduce(0) { $0 + $1.mesh.triangleCount }
        XCTAssertLessThan(Double(total) / Double(MGSolidLimits.triangles), 0.1)
    }

    // MARK: Gear geometry

    func testGearToothBoreKeywayAndChamferLimitsComeFromTheRealOutline() {
        func r(_ fields: String) -> String? { reason(doc("{\"id\": \"g\", \"shape\": {\"gear\": {\"module\": 2, \"width\": 10, \(fields)}}}")) }
        // Negative tip thickness: 8 teeth, 25 degrees, maximum backlash.
        XCTAssertEqual(r("\"teeth\": 8, \"pressureAngle\": 25, \"backlash\": 0.3"), "part.gear.tip")
        // Positive but narrow tips: a chamfer of 0.445 m (allowed by the old 0.45 m rule) folds the inset tip.
        XCTAssertEqual(r("\"teeth\": 8, \"pressureAngle\": 25, \"chamfer\": 0.89"), "part.gear.chamfer")
        XCTAssertNil(r("\"teeth\": 8, \"pressureAngle\": 25, \"chamfer\": 0.1"))
        // Bore close to the root: fine without a chamfer, but the chamfered bore and root caps would cross.
        XCTAssertNil(r("\"teeth\": 24, \"bore\": 20.4, \"chamfer\": 0"))
        XCTAssertEqual(r("\"teeth\": 24, \"bore\": 20.4, \"chamfer\": 0.6"), "part.gear.chamfer")
        // Keyway corners outside the root circle (the old depth-only rule let this through).
        XCTAssertEqual(r("\"teeth\": 24, \"bore\": 20, \"keyway\": [19, 0.5], \"chamfer\": 0"), "part.gear.keyway")
        // Deep keyway whose chamfer inset crosses the root inset.
        XCTAssertNil(r("\"teeth\": 24, \"bore\": 6, \"keyway\": [3, 14], \"chamfer\": 0"))
        XCTAssertEqual(r("\"teeth\": 24, \"bore\": 6, \"keyway\": [3, 14], \"chamfer\": 0.8"), "part.gear.chamfer")
    }

    /// Every gear the parser accepts has cap loops that triangulate into non-overlapping triangles covering exactly the
    /// inset region, across tooth counts, pressure angles, backlash, bores and chamfers (authored and default).
    func testAcceptedGearsHaveSimpleNonCrossingCaps() throws {
        var accepted = 0, refused: [String: Int] = [:]
        for z in [8, 9, 10, 12, 17, 24, 40, 80, 200] { for pa in [14.5, 20, 25] { for bl in [0, 0.06, 0.3] {
            for chamfer in [nil, 0.1, 0.3, 0.5] as [Double?] { for boreFraction in [0, 0.6] {
                let g = MGSpurGear(teeth: z, module: 2)
                var body: [String: MGJSON] = ["teeth": .number(Double(z)), "module": .number(2), "width": .number(10),
                                              "pressureAngle": .number(pa), "backlash": .number(bl)]
                if boreFraction > 0 { body["bore"] = .number((g.rootRadius * boreFraction).rounded()) }
                if let c = chamfer { body["chamfer"] = .number(c * 2) }
                do {
                    let spec = try MGSolidParser.shape(.object(["gear": .object(body)]))
                    accepted += 1
                    let gear = spec.spurGear!
                    let profile = gear.profile(bore: spec.n("bore"))
                    let c = spec.n("chamfer", -1)
                    XCTAssertGreaterThanOrEqual(c, 0, "the parser records the chamfer it validated")
                    let loops = [profile.outer] + profile.holes
                    let caps = loops.map { c > 0 ? MGProfile.inset($0, by: c) : $0 }
                    guard caps.count > 1 else {
                        // Without a bore the cap is one loop; star-shaped about the axis means simple.
                        XCTAssertTrue(MGProfile.isPolarMonotonic(caps[0]), "z\(z) pa\(pa) bl\(bl) c\(c)")
                        continue
                    }
                    var pts: [MGVec2] = [], idx: [[Int]] = []
                    for l in caps { idx.append(Array(pts.count..<(pts.count + l.count))); pts += l }
                    let tris = MGTriangulator.triangulate(points: pts, outer: idx[0], holes: Array(idx.dropFirst()))
                    var sum = 0.0, negative = 0
                    for (a, b, cc) in tris {
                        let area = (pts[b] - pts[a]).cross(pts[cc] - pts[a]) / 2
                        if area < -1e-9 { negative += 1 }
                        sum += abs(area)
                    }
                    let region = caps.reduce(0) { $0 + MGProfile.signedArea($1) }
                    XCTAssertEqual(negative, 0, "z\(z) pa\(pa) bl\(bl) c\(c)")
                    XCTAssertEqual(sum, region, accuracy: 1e-6 * region, "z\(z) pa\(pa) bl\(bl) c\(c)")
                } catch let e as MGSolidIssue {
                    refused[e.reason, default: 0] += 1
                    XCTAssertTrue(["part.gear.tip", "part.gear.chamfer", "part.gear.profile", "part.gear.bore"].contains(e.reason), e.reason)
                    // Defaults never cause a refusal on their own: an omitted chamfer falls back to a valid one.
                    if chamfer == nil { XCTAssertNotEqual(e.reason, "part.gear.chamfer") }
                }
            } }
        } } }
        XCTAssertGreaterThan(accepted, 300)
        XCTAssertGreaterThan(refused["part.gear.tip"] ?? 0, 0)
        XCTAssertGreaterThan(refused["part.gear.chamfer"] ?? 0, 0)
    }

    func testRingGearUsesItsPressureAngleAndRefusesInterferingPairs() {
        func ring(_ z: Int, _ pa: Double) -> String? {
            reason(doc("{\"id\": \"r\", \"shape\": {\"ringGear\": {\"teeth\": \(z), \"module\": 2, \"width\": 10, \"outer\": \(Double(z) + 8), \"pressureAngle\": \(pa)}}}"))
        }
        // Tip circle inside the base circle at 14.5 degrees (fine at the default 20).
        XCTAssertEqual(ring(40, 14.5), "part.ringGear.teeth")
        XCTAssertNil(ring(40, 20))
        // And the other way round: 30 teeth only work with the larger pressure angle.
        XCTAssertEqual(ring(30, 20), "part.ringGear.teeth")
        XCTAssertNil(ring(30, 25))
        func pair(_ zr: Int, _ zp: Int, planetAngle: Double = 20) -> String? {
            reason(doc("""
                {"id": "r", "shape": {"ringGear": {"teeth": \(zr), "module": 2, "width": 10, "outer": \(Double(zr) + 8)}}, \(spin)},
                {"id": "p", "at": [\(Double(zr - zp)), 0, 0], "shape": {"gear": {"teeth": \(zp), "module": 2, "width": 8, "pressureAngle": \(planetAngle)}},
                \(spin), "drive": {"input": 1}}
                """, "{\"gearMesh\": {\"a\": \"r\", \"b\": \"p\"}}"))
        }
        XCTAssertNil(pair(60, 18))
        XCTAssertEqual(pair(40, 36), "constraint.gearMesh.interference")   // too small a tooth difference: tips clash
        XCTAssertEqual(pair(40, 8), "constraint.gearMesh.interference")    // involute interference of a small planet
        XCTAssertEqual(pair(60, 18, planetAngle: 25), "constraint.gearMesh.pressureAngle")
    }

    func testExternalPairsWhoseTeethOverlapAreRefused() {
        func spur(_ za: Int, _ zb: Int, _ pa: Double) -> String? {
            reason(doc("""
                {"id": "a", "shape": {"gear": {"teeth": \(za), "module": 2, "width": 8, "pressureAngle": \(pa)}}, \(spin), "drive": {"input": 1}},
                {"id": "b", "at": [\(Double(za + zb)), 0, 0], "shape": {"gear": {"teeth": \(zb), "module": 2, "width": 8, "pressureAngle": \(pa)}}, \(spin)}
                """, "{\"gearMesh\": {\"a\": \"a\", \"b\": \"b\"}}"))
        }
        XCTAssertNil(spur(12, 36, 20))                                         // a normal pair still compiles
        XCTAssertEqual(spur(10, 36, 14.5), "constraint.gearMesh.interference")  // undercut pinion at a low pressure angle
        XCTAssertEqual(spur(8, 80, 20), "constraint.gearMesh.interference")     // tiny pinion against a large wheel
    }

    // MARK: Reasons

    func testMissingKeysAreNamedInTheReason() throws {
        // A model that writes crankRadius/rodLength instead of radius/rod must learn which keys are missing.
        let crank = "{\"id\": \"crank\", \"shape\": \(gear(12)), \(spin), \"drive\": {\"input\": 1}}"
        let piston = "{\"id\": \"piston\", \"shape\": {\"box\": {\"size\": [10, 10, 10]}}, \"joint\": {\"prismatic\": [1, 0, 0]}, "
            + "\"drive\": {\"crankSlider\": {\"crank\": \"crank\", \"crankRadius\": 18, \"rodLength\": 62}}}"
        XCTAssertEqual(reason(doc("\(crank), \(piston)")), "part.drive.crankSlider.missing.radius,rod")
        XCTAssertEqual(reason(doc("{\"id\": \"b\", \"shape\": {\"shaft\": {\"radius\": 4}}}")), "part.shaft.missing.length")
    }

    func testReasonsAreStableTokensInADeterministicOrder() throws {
        let sun = "{\"id\": \"sun\", \"shape\": \(gear(24)), \(spin), \"drive\": {\"input\": 1}}"
        let cases: [(String, String)] = [
            (doc("\(sun), {\"id\": \"f\", \"shape\": \(gear(12)), \(spin), \"drive\": {\"follow\": {\"source\": \"ghost\", \"ratio\": 1}}}"), "ref.unknown.ghost"),
            (doc("\(sun), {\"id\": \"f\", \"shape\": \(gear(12)), \(spin), \"drive\": {\"follow\": {\"source\": 3, \"ratio\": 1}}}"), "part.drive.follow.source"),
            (doc("\(sun), {\"id\": \"f\", \"shape\": \(gear(12)), \"joint\": {\"prismatic\": [1, 0, 0]}, \"drive\": {\"crankSlider\": {\"crank\": \"nope\", \"radius\": 5, \"rod\": 20}}}"), "ref.unknown.nope"),
            (doc("\(sun), {\"id\": \"f\", \"shape\": \(gear(12)), \"bad key\": 1}"), "part.unknown.bad_key"),
            (doc(sun, "{\"gear mesh\": {}}"), "constraint.unknown.gear_mesh"),
            (doc("{\"id\": \"q\", \"shape\": {\"teapot \\\"x\\\"\": {}}}"), "part.shape.unknown.teapot__x_"),
            (doc("{\"id\": \"a\", \"parent\": \"b\", \"shape\": \(gear(12))}, {\"id\": \"b\", \"parent\": \"a\", \"shape\": \(gear(12))}"), "part.parent.cycle"),
            (doc("""
                {"id": "a", "shape": \(gear(12)), \(spin), "drive": {"follow": {"source": "b", "ratio": 1}}},
                {"id": "b", "at": [80, 0, 0], "shape": \(gear(12)), \(spin), "drive": {"follow": {"source": "a", "ratio": 1}}}
                """), "part.drive.cycle"),
        ]
        for (json, expected) in cases {
            XCTAssertEqual(reason(json), expected)
            for _ in 0..<3 { XCTAssertEqual(reason(json), reason(json)) }
        }
        // No reason anywhere carries spaces or JSON debug text.
        for (json, _) in cases { XCTAssertFalse(reason(json)!.contains(where: { $0 == " " || $0 == "\"" || $0 == "(" })) }
        // Patches report the first bad part id in sorted order.
        let base = try MGSolidParser.document(json: SolidAssemblyFormatTests.planetaryJSON()).get()
        let patch: MGJSON = .object(["parts": .object(["zz": .object(["material": .string("brass")]), "aa top": .object(["material": .string("brass")])])])
        guard case .failure(let issue) = MGSolidParser.applying(patch, to: base) else { return XCTFail("patch must fail") }
        XCTAssertEqual(issue.reason, "ref.unknown.aa_top")
    }

    // MARK: Renderer

    /// A patch that only changes a part's material updates the bookkeeping, and a section cut on one part never
    /// edits the cached material other parts share.
    func testRendererMaterialBookkeepingAndPrivateSectionMaterials() {
        let mesh = MGMesh.cylinder(radius: 2, to: 2, segments: 16)
        let a = MGAssembly(name: "m", parts: [
            MGPart(id: "a", name: "a", mesh: mesh, material: .brass),
            MGPart(id: "b", name: "b", mesh: mesh, material: .brass, placement: .translation(MGVec3(10, 0, 0))),
            MGPart(id: "c", name: "c", mesh: mesh, material: .bronze, placement: .translation(MGVec3(20, 0, 0))),
        ])
        let r = MGSolidRenderer(assembly: a)
        func material(_ id: String) -> SCNMaterial { r.scene.rootNode.childNode(withName: id, recursively: true)!.geometry!.firstMaterial! }
        XCTAssertTrue(material("a") === material("b"))
        var next = a
        next.parts[1].material = .bronze
        r.setAssembly(next)
        XCTAssertEqual(r.partMaterials["b"], .bronze)
        XCTAssertTrue(material("b") === material("c"), "b now shares the bronze material")
        var options = MGStudioOptions()
        options.section = (normal: MGVec3(1, 0, 0), offset: 12)
        options.sectionParts = ["b"]
        r.options = options
        XCTAssertNotNil(material("b").shaderModifiers)
        XCTAssertFalse(material("b") === material("c"))
        XCTAssertNil(material("c").shaderModifiers, "the shared bronze material must not be cut")
        XCTAssertNil(material("a").shaderModifiers)
        r.highlight(["c"])
        XCTAssertNotNil(material("b").shaderModifiers)
        XCTAssertNil(material("c").shaderModifiers)
    }

    // MARK: Snapshot and decoders

    func testEmptySnapshotEncodesFiniteJSON() throws {
        let snap = MGSolidSnapshot.make(MGAssembly(name: "empty", parts: []), params: MGPoseParameters())
        let data = try snap.jsonData()
        XCTAssertEqual(try JSONDecoder().decode(MGSolidSnapshot.self, from: data), snap)
        XCTAssertEqual(snap.boundsMin, [0, 0, 0])
        XCTAssertTrue(snap.camera.distance.isFinite && snap.camera.target.allSatisfy(\.isFinite))
    }

    func testDecodersRefuseShortSlotsInsteadOfCrashing() throws {
        let doc = try MGSolidParser.document(json: SolidAssemblyFormatTests.planetaryJSON()).get()
        let snap = MGSolidSnapshot.make(doc.assembly, params: MGPoseParameters())
        let good = try JSONSerialization.jsonObject(with: snap.jsonData()) as! [String: Any]
        func decodes(_ edit: (inout [String: Any]) -> Void) -> Bool {
            var o = good
            edit(&o)
            let data = try! JSONSerialization.data(withJSONObject: o)
            return (try? JSONDecoder().decode(MGSolidSnapshot.self, from: data)) != nil
        }
        XCTAssertTrue(decodes { _ in })
        XCTAssertFalse(decodes { o in var c = o["camera"] as! [String: Any]; c["target"] = [1, 2]; o["camera"] = c })
        XCTAssertFalse(decodes { o in
            var m = o["materials"] as! [[String: Any]]; var p = m[0]["parameters"] as! [String: Any]
            p["baseColor"] = [0.5]; m[0]["parameters"] = p; o["materials"] = m
        })
        XCTAssertFalse(decodes { o in
            var l = o["lighting"] as! [String: Any]; var e = l["environment"] as! [String: Any]
            e["softboxes"] = [[1, 2, 3]]; l["environment"] = e; o["lighting"] = l
        })
        XCTAssertFalse(decodes { o in var l = o["lighting"] as! [String: Any]; l["background"] = []; o["lighting"] = l })
        XCTAssertFalse(decodes { o in o["boundsMax"] = [1, 2] })
        XCTAssertFalse(decodes { o in var i = o["indices"] as! [Int]; i[0] = 1_000_000_000; o["indices"] = i })
        XCTAssertFalse(decodes { o in o["triangleMaterials"] = [0] })
        XCTAssertFalse(decodes { o in o["format"] = "other/9" })
        XCTAssertNil(try? JSONDecoder().decode(MGSolidCamera.self, from: Data("{\"target\":[],\"yaw\":0,\"pitch\":0,\"distance\":1,\"fieldOfView\":30}".utf8)))
    }
}
