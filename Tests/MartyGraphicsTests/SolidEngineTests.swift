// SPDX-License-Identifier: Apache-2.0
import XCTest
@testable import MartyGraphics

/// Solid geometry kernel, kinematic assembly, assembly JSON and snapshot export.
final class SolidKernelTests: XCTestCase {
    func assertClosed(_ m: MGMesh, _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        let r = m.edgeReport
        XCTAssertTrue(r.isClosed, "\(what): \(r)", file: file, line: line)
        XCTAssertEqual(r.degenerateTriangles, 0, "\(what) degenerate", file: file, line: line)
        XCTAssertGreaterThan(m.signedVolume, 0, "\(what) must wind outward", file: file, line: line)
    }

    func testBoxExtrusionIsClosedWithExactVolumeAndBounds() {
        let m = MGMesh.extrude(MGProfile(outer: MGProfile.roundedRectLoop(width: 4, height: 2, cornerRadius: 0)), from: 0, to: 3)
        assertClosed(m, "box")
        XCTAssertEqual(m.signedVolume, 24, accuracy: 1e-9)
        XCTAssertEqual(m.bounds.min, MGVec3(-2, -1, 0)); XCTAssertEqual(m.bounds.max, MGVec3(2, 1, 3))
        XCTAssertEqual(m.outwardFraction(), 1, accuracy: 1e-12)
    }

    func testClockwiseInputIsNormalisedAndHolesAreSubtracted() {
        let outer = MGProfile.roundedRectLoop(width: 10, height: 10, cornerRadius: 0).reversed()
        let p = MGProfile(outer: Array(outer), holes: [MGProfile.roundedRectLoop(width: 2, height: 2, cornerRadius: 0)])
        XCTAssertGreaterThan(MGProfile.signedArea(p.outer), 0)
        XCTAssertLessThan(MGProfile.signedArea(p.holes[0]), 0)
        let m = MGMesh.extrude(p, to: 1)
        assertClosed(m, "square with hole")
        XCTAssertEqual(m.signedVolume, 96, accuracy: 1e-9)
    }

    func testPlateWithSeveralHolesUsesEarClippingAndStaysClosed() {
        let holes = (0..<6).map { MGProfile.circleLoop(radius: 2, segments: 20, center: .polar(14, Double($0) * .pi / 3)) }
        let p = MGProfile(outer: MGProfile.circleLoop(radius: 20, segments: 96), holes: holes + [MGProfile.circleLoop(radius: 5, segments: 32)])
        let m = MGMesh.extrude(p, from: -1, to: 2, chamfer: 0.4)
        assertClosed(m, "plate")
        XCTAssertEqual(m.bounds.max.z, 2, accuracy: 1e-12)
        // Volume is below the prism of the net area (chamfers remove material) but close to it.
        let prism = p.area * 3
        XCTAssertLessThan(m.signedVolume, prism)
        XCTAssertGreaterThan(m.signedVolume, prism * 0.95)
    }

    func testChamferedBoxHexAndCylindersAreClosed() {
        let box = MGMesh.chamferedBox(size: MGVec3(4, 3, 2), chamfer: 0.3)
        assertClosed(box, "chamfered box")
        XCTAssertEqual(box.bounds.size.x, 4, accuracy: 1e-9); XCTAssertEqual(box.bounds.size.z, 2, accuracy: 1e-9)
        assertClosed(.hexPrism(acrossFlats: 7, from: 0, to: 4, chamfer: 0.5), "hex")
        let cyl = MGMesh.cylinder(radius: 2, from: 0, to: 5, segments: 256)
        assertClosed(cyl, "cylinder")
        XCTAssertEqual(cyl.signedVolume, Double.pi * 4 * 5, accuracy: 0.01 * Double.pi * 20)
        let tube = MGMesh.tube(inner: 1, outer: 2, from: 0, to: 3, chamfer: 0.2)
        assertClosed(tube, "tube")
        XCTAssertEqual(tube.bounds.min.z, 0, accuracy: 1e-12)
    }

    func testOpenRevolveWithPolesIsClosedEvenWhenDrawnClockwise() {
        let profile = [MGVec2(0, 4), MGVec2(3, 4), MGVec2(3, 0), MGVec2(0, 0)]  // clockwise in (r, z)
        let m = MGMesh.revolve(profile, segments: 64, closed: false)
        assertClosed(m, "revolve")
        XCTAssertEqual(m.outwardFraction(about: MGVec3(0, 0, 2)), 1, accuracy: 1e-12)
    }

    func testSpurGearDimensionsToothCountAndClosedMesh() {
        let g = MGSpurGear(teeth: 24, module: 2)
        XCTAssertEqual(g.pitchRadius, 24, accuracy: 1e-12)              // m z / 2
        XCTAssertEqual(g.baseRadius, 24 * cos(20 * Double.pi / 180), accuracy: 1e-12)
        XCTAssertEqual(g.tipRadius, 26, accuracy: 1e-12); XCTAssertEqual(g.rootRadius, 21.5, accuracy: 1e-12)
        let outline = g.outline()
        XCTAssertTrue(MGProfile.isPolarMonotonic(outline))
        XCTAssertGreaterThan(MGProfile.signedArea(outline), 0)
        // Tooth count = number of separate runs of points on the tip circle.
        var runs = 0, wasTip = false
        for p in outline + [outline[0]] {
            let tip = abs(p.length - g.tipRadius) < 1e-6
            if tip && !wasTip { runs += 1 }
            wasTip = tip
        }
        if abs(outline[0].length - g.tipRadius) < 1e-6 && abs(outline[outline.count - 1].length - g.tipRadius) < 1e-6 { runs -= 1 }
        XCTAssertEqual(runs, 24)
        // Radii stay within root and tip; the tooth has a positive tip land.
        for p in outline { XCTAssertGreaterThan(p.length, g.rootRadius - 1e-9); XCTAssertLessThan(p.length, g.tipRadius + 1e-9) }
        XCTAssertGreaterThan(g.halfThicknessAngle(at: g.tipRadius), 0)
        let mesh = MGMesh.extrude(g.profile(bore: 6, keyway: (width: 3, depth: 1.6)), to: 14, chamfer: 0.5)
        assertClosed(mesh, "gear")
        XCTAssertEqual(mesh.bounds.max.x, g.tipRadius, accuracy: 0.01)
        XCTAssertGreaterThan(mesh.outwardFraction(about: MGVec3(0, 0, 7)), 0.5)
    }

    func testRingGearCarrierAndBladeAreClosed() {
        let ring = MGRingGear(teeth: 60, module: 2, outerRadius: 69)
        XCTAssertEqual(ring.pitchRadius, 60, accuracy: 1e-12)
        XCTAssertTrue(MGProfile.isPolarMonotonic(ring.outline()))
        assertClosed(.extrude(ring.profile(), to: 15, chamfer: 0.5), "ring gear")
        let spider = MGSolidModels.spiderOutline(armRadius: 42, hubRadius: 15, bossRadius: 9.5, armHalfWidth: 6.5, blend: 5, samples: 360)
        assertClosed(.extrude(MGProfile(outer: spider), to: 6, chamfer: 0.8), "carrier")
        assertClosed(.blade(span: 80, chord: 20, thickness: 0.12, twist: 0.5, root: 10, tipChord: 12), "blade")
        assertClosed(.blade(span: 80, chord: 20, thickness: 0.10, twist: -0.6, root: 10, camber: 0.04, camberPosition: 0.4), "cambered blade")
    }

    func testRigidTransformInverseAndComposition() {
        let t = MGTransform.translation(MGVec3(3, -2, 5)) * .rotation(axis: MGVec3(1, 2, 3), angle: 0.7)
        let p = MGVec3(0.3, 4, -1)
        let back = t.inverse.apply(t.apply(p))
        XCTAssertEqual((back - p).length, 0, accuracy: 1e-12)
        XCTAssertEqual(((t * t.inverse).apply(p) - p).length, 0, accuracy: 1e-12)
        XCTAssertEqual((MGTransform.rotation(axis: .unitZ, angle: .pi / 2).apply(.unitX) - .unitY).length, 0, accuracy: 1e-12)
    }

    func testRenderMeshSplitsOnlySharpEdges() {
        let box = MGMesh.extrude(MGProfile(outer: MGProfile.roundedRectLoop(width: 2, height: 2, cornerRadius: 0)), to: 2)
        XCTAssertEqual(box.renderMesh(creaseAngle: 0.6).positions.count, 24)   // 6 faces x 4 corners
        XCTAssertEqual(box.renderMesh(creaseAngle: .pi).positions.count, 8)
        let cyl = MGMesh.cylinder(radius: 1, to: 1, segments: 64).renderMesh(creaseAngle: 0.6)
        for n in cyl.normals { XCTAssertEqual(n.length, 1, accuracy: 1e-9) }
        XCTAssertEqual(cyl.positions.count, 64 * 2 + 64 * 2 + 2)   // smooth wall, separate cap rings, two poles
    }
}

final class SolidKinematicsTests: XCTestCase {
    /// Largest penetration (mm) of B's outline into A over sampled points, and the smallest radial gap.
    /// `a` is a spur gear (material inside its outline) or a ring (material outside its toothed bore).
    static func contact(_ a: [MGVec2], _ fa: MGTransform, ring: Bool, _ b: [MGVec2], _ fb: MGTransform) -> (penetration: Double, gap: Double) {
        let pa = MGProfile.PolarBoundary(loopCCW: a), pb = MGProfile.PolarBoundary(loopCCW: b)
        var pen = -Double.infinity, gap = Double.infinity
        let ia = fa.inverse, ib = fb.inverse
        let ra = a.map(\.length), rb = b.map(\.length)
        let (aMin, aMax) = (ra.min()!, ra.max()!), (bMin, bMax) = (rb.min()!, rb.max()!)
        for p in b {
            let l = ia.apply(fb.apply(MGVec3(p.x, p.y, 0)))
            let r = (l.x * l.x + l.y * l.y).squareRoot()
            guard r > aMin - 0.5, r < aMax + 0.5 else { continue }
            let d = ring ? r - pa.radius(at: atan2(l.y, l.x)) : pa.radius(at: atan2(l.y, l.x)) - r
            pen = max(pen, d); gap = min(gap, -d)
        }
        for p in a {
            let l = ib.apply(fa.apply(MGVec3(p.x, p.y, 0)))
            let r = (l.x * l.x + l.y * l.y).squareRoot()
            guard r > bMin - 0.5, r < bMax + 0.5 else { continue }
            let d = pb.radius(at: atan2(l.y, l.x)) - r
            pen = max(pen, d); gap = min(gap, -d)
        }
        return (pen, gap)
    }

    func testPlanetaryRatioAndResiduals() throws {
        let model = try MGSolidModels.planetary()
        XCTAssertEqual(model.assembly.validate(), [])
        XCTAssertEqual(model.ring.teeth, model.sun.teeth + 2 * model.planet.teeth)
        XCTAssertEqual(model.carrierRatio, 24.0 / 84.0, accuracy: 1e-15)    // Zs / (Zs + Zr) = 2/7
        for s in [0.0, 0.7, 2 * Double.pi, -5.3, 40] {
            let pose = model.assembly.pose(MGPoseParameters(input: s))
            XCTAssertEqual(pose.values[MGPlanetaryModel.carrierID]!, s * 2 / 7, accuracy: 1e-12)
            // Planet spin relative to the carrier: -(Zs/Zp)(s - c).
            XCTAssertEqual(pose.values["planet1"]! - model.planetPhases[0], -(24.0 / 18.0) * (s - s * 2 / 7), accuracy: 1e-12)
            for r in model.assembly.gearResiduals(MGPoseParameters(input: s)) { XCTAssertEqual(r, 0, accuracy: 1e-9) }
        }
        // Purity: same parameters, same pose.
        XCTAssertEqual(model.assembly.pose(MGPoseParameters(input: 1.25, explode: 0.4)), model.assembly.pose(MGPoseParameters(input: 1.25, explode: 0.4)))
        XCTAssertThrowsError(try MGSolidModels.planetary(sunTeeth: 24, planetTeeth: 18, ringTeeth: 62))
        XCTAssertThrowsError(try MGSolidModels.planetary(sunTeeth: 20, planetTeeth: 18, ringTeeth: 56, planets: 3))
    }

    func testPlanetaryGearsMeshWithoutInterpenetration() throws {
        let model = try MGSolidModels.planetary()
        let sun = model.sun.outline(), planet = model.planet.outline(), ring = model.ring.outline(phase: model.ringPhase)
        var worst = -Double.infinity, closest = Double.infinity
        let pitch = 2 * Double.pi / 24
        let samples = (0..<72).map { Double($0) / 72 * 3 * pitch } + [1.0, 2.5, 7.77, 31.4]
        for s in samples {
            let pose = model.assembly.pose(MGPoseParameters(input: s))
            for i in 0..<3 {
                let fp = pose.world[MGPlanetaryModel.planetID(i)]!
                let a = Self.contact(sun, pose.world["sun"]!, ring: false, planet, fp)
                let b = Self.contact(ring, pose.world["ring"]!, ring: true, planet, fp)
                worst = max(worst, a.penetration, b.penetration); closest = min(closest, a.gap, b.gap)
            }
        }
        XCTAssertLessThan(worst, 1e-6, "teeth interpenetrate")
        XCTAssertLessThan(closest, 0.25, "teeth must stay engaged (backlash-sized gap)")
        // Negative control: a planet shifted by half a tooth collides.
        let pose = model.assembly.pose(MGPoseParameters(input: 0.3))
        let shifted = pose.world["planet1"]! * .rotation(axis: .unitZ, angle: Double.pi / 18)
        XCTAssertGreaterThan(Self.contact(sun, pose.world["sun"]!, ring: false, planet, shifted).penetration, 0.5)
        // Wrong ratio collides too.
        var wrong = model.assembly
        let k = wrong.parts.firstIndex { $0.id == "planet1" }!
        wrong.parts[k].drive = .gear(driver: "sun", ratio: -1.2, carrier: "carrier", offset: model.planetPhases[0])
        var hit = 0.0
        for s in stride(from: 0.0, to: 1.0, by: 0.05) {
            let p = wrong.pose(MGPoseParameters(input: s))
            hit = max(hit, Self.contact(sun, p.world["sun"]!, ring: false, planet, p.world["planet1"]!).penetration)
        }
        XCTAssertGreaterThan(hit, 0.5)
    }

    func testExplodeIsStaggeredAndReversible() throws {
        let a = try MGSolidModels.planetary().assembly
        let p0 = a.pose(MGPoseParameters(input: 0.5, explode: 0)), p1 = a.pose(MGPoseParameters(input: 0.5, explode: 1))
        XCTAssertEqual(p1.world["carrier"]!.translation.z - p0.world["carrier"]!.translation.z, 50, accuracy: 1e-9)
        XCTAssertEqual(p1.world["planet1"]!.translation.z - p0.world["planet1"]!.translation.z, 22, accuracy: 1e-9)  // 50 - 28
        XCTAssertEqual(MGAssembly.explodeAmount(0.1, window: 0.35...1), 0)
        XCTAssertEqual(MGAssembly.explodeAmount(0.5, window: 0...1), 0.5, accuracy: 1e-12)
        // Explode does not change joint values.
        XCTAssertEqual(p0.values, p1.values)
    }

    func testSliderCrankClosesTheLoop() throws {
        let m = try MGSolidModels.sliderCrank()
        XCTAssertEqual(m.assembly.validate(), [])
        for t in stride(from: 0.0, to: 2 * Double.pi, by: 0.2) {
            let pose = m.assembly.pose(MGPoseParameters(input: t))
            let crankPin = pose.world["crank"]!.apply(MGVec3(m.crankRadius, 0, 0))
            let bigEnd = pose.world["rod"]!.apply(MGVec3(-m.rodLength, 0, 0))
            XCTAssertEqual((crankPin - bigEnd).length, 0, accuracy: 1e-9, "rod must reach the crank pin at \(t)")
            XCTAssertEqual(pose.world["piston"]!.translation.y, 0, accuracy: 1e-12)
        }
        XCTAssertEqual(m.assembly.pose(MGPoseParameters(input: 0)).values["piston"]!, m.crankRadius + m.rodLength, accuracy: 1e-12)
        XCTAssertEqual(m.assembly.pose(MGPoseParameters(input: .pi)).values["piston"]!, m.rodLength - m.crankRadius, accuracy: 1e-12)
    }

    func testAssemblyValidationFindsCycles() {
        let a = MGAssembly(name: "bad", parts: [
            MGPart(id: "a", name: "a", mesh: MGMesh(), material: .brass, parent: "b", joint: .revolute(axis: .unitZ), drive: .follow(source: "b", ratio: 1, offset: 0)),
            MGPart(id: "b", name: "b", mesh: MGMesh(), material: .brass, parent: "a", joint: .revolute(axis: .unitZ), drive: .follow(source: "a", ratio: 1, offset: 0)),
        ])
        XCTAssertEqual(Set(a.validate()), ["parent cycle", "drive cycle"])
    }
}

final class SolidAssemblyFormatTests: XCTestCase {
    static var planetaryURL: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Examples/Solid3D/Sources/MartySolid3D/Models/planetary.json")
    }
    static func planetaryJSON() throws -> MGJSON {
        let data = try Data(contentsOf: planetaryURL)
        return MGJSON(any: try JSONSerialization.jsonObject(with: data))!
    }
    func parse(_ j: MGJSON) -> Result<MGSolidDocument, MGSolidIssue> { MGSolidParser.document(json: j) }

    /// Edit the example JSON through a closure over its parts list.
    func edited(_ change: (inout [String: MGJSON], inout [MGJSON]) -> Void) throws -> MGJSON {
        guard case .object(var top) = try Self.planetaryJSON(), case .array(var parts)? = top["parts"] else { throw MGSolidIssue("fixture") }
        change(&top, &parts)
        top["parts"] = .array(parts)
        return .object(top)
    }
    func setPart(_ parts: inout [MGJSON], _ id: String, _ key: String, _ value: MGJSON?) {
        let k = parts.firstIndex { $0["id"] == .string(id) }!
        guard case .object(var o) = parts[k] else { return }
        o[key] = value
        parts[k] = .object(o)
    }
    func reason(_ r: Result<MGSolidDocument, MGSolidIssue>) -> String? {
        if case .failure(let e) = r { return e.reason }
        return nil
    }

    func testExampleJSONCompilesWithSolvedRatiosAndMeshes() throws {
        let doc = try parse(Self.planetaryJSON()).get()
        XCTAssertEqual(doc.assembly.parts.count, 1 + 6 + 1 + 1 + 1 + 1 + 1 + 3 + 3)
        XCTAssertEqual(doc.ratios["sun"]!, 1, accuracy: 1e-12)
        XCTAssertEqual(doc.ratios["carrier"]!, 2.0 / 7.0, accuracy: 1e-12)
        XCTAssertEqual(doc.ratios["planet2"]!, -(24.0 / 18.0) * (5.0 / 7.0), accuracy: 1e-12)
        XCTAssertEqual(doc.steps.count, 5)
        XCTAssertEqual(doc.steps[2].highlight, ["planet1", "planet2", "planet3"])
        for part in doc.assembly.parts {
            XCTAssertTrue(part.mesh.edgeReport.edges > 0, part.id)
            for shape in doc.shapes[part.id]! { XCTAssertTrue(shape.mesh().edgeReport.isClosed, "\(part.id) \(shape.kind)") }
        }
        for r in doc.assembly.gearResiduals(MGPoseParameters(input: 2.2)) { XCTAssertEqual(r, 0, accuracy: 1e-9) }
    }

    func testExampleJSONGearsDoNotInterpenetrate() throws {
        let doc = try parse(Self.planetaryJSON()).get()
        func outline(_ id: String) -> [MGVec2] { doc.gears[id]!.spur?.outline() ?? doc.gears[id]!.ring!.outline() }
        var worst = -Double.infinity, closest = Double.infinity
        for s in (0..<60).map({ Double($0) * 0.0131 }) + [3.3, 12.0] {
            let pose = doc.pose(MGPoseParameters(input: s))
            func frame(_ id: String) -> MGTransform { pose.world[id]! * doc.gears[id]!.local }
            for i in 1...3 {
                let a = SolidKinematicsTests.contact(outline("sun"), frame("sun"), ring: false, outline("planet\(i)"), frame("planet\(i)"))
                let b = SolidKinematicsTests.contact(outline("ring"), frame("ring"), ring: true, outline("planet\(i)"), frame("planet\(i)"))
                worst = max(worst, a.penetration, b.penetration); closest = min(closest, a.gap, b.gap)
            }
        }
        XCTAssertLessThan(worst, 1e-6)
        XCTAssertLessThan(closest, 0.25)
    }

    func testRefusalsNameTheRule() throws {
        let teeth = try edited { _, parts in
            setPart(&parts, "sun", "shape", .object(["gear": .object(["teeth": .number(7), "module": .number(2), "width": .number(14)])]))
        }
        XCTAssertEqual(reason(parse(teeth)), "part.gear.teeth")
        if case .failure(let e) = parse(teeth) { XCTAssertEqual(e.part, "sun") }

        let module = try edited { _, parts in
            setPart(&parts, "sun", "shape", .object(["gear": .object(["teeth": .number(24), "module": .number(2.5), "width": .number(14)])]))
        }
        XCTAssertEqual(reason(parse(module)), "constraint.gearMesh.module")

        let distance = try edited { _, parts in
            setPart(&parts, "planet", "at", .array([.number(43), .number(0), .number(0)]))
        }
        XCTAssertEqual(reason(parse(distance)), "constraint.gearMesh.distance")

        let axis = try edited { _, parts in setPart(&parts, "sun", "joint", .object(["revolute": .array([.number(0), .number(0), .number(0)])])) }
        XCTAssertEqual(reason(parse(axis)), "joint.axis")

        let ref = try edited { _, parts in setPart(&parts, "pin", "parent", .string("nowhere")) }
        XCTAssertEqual(reason(parse(ref)), "ref.unknown.nowhere")

        let key = try edited { _, parts in setPart(&parts, "ring", "colour", .string("red")) }
        XCTAssertEqual(reason(parse(key)), "part.unknown.colour")

        let material = try edited { _, parts in setPart(&parts, "ring", "material", .string("unobtainium")) }
        XCTAssertEqual(reason(parse(material)), "part.material")

        // Ring free to turn and nothing holding the carrier: the output is not determined.
        let free = try edited { _, parts in setPart(&parts, "ring", "joint", .object(["revolute": .array([.number(0), .number(0), .number(1)])])) }
        XCTAssertEqual(reason(parse(free)), "constraint.underdetermined")

        // Ring and carrier both fixed while the sun is driven: contradiction.
        let conflict = try edited { top, _ in
            guard case .array(var c)? = top["constraints"] else { return }
            c.append(.object(["fixed": .string("carrier")])); top["constraints"] = .array(c)
        }
        XCTAssertEqual(reason(parse(conflict)), "constraint.conflict")

        // Five equally spaced planets cannot all mesh when (Zs + Zr) / 5 is not whole.
        let five = try edited { _, parts in
            for id in ["planet", "pin"] { setPart(&parts, id, "repeat", .object(["count": .number(5)])) }
        }
        XCTAssertEqual(reason(parse(five)), "constraint.gearMesh.phase")

        let tooMany = try edited { _, parts in parts += (0..<50).map { .object(["id": .string("x\($0)"), "shape": .object(["shaft": .object(["radius": .number(1), "length": .number(1)])])]) } }
        XCTAssertEqual(reason(parse(tooMany)), "parts.count")

        let dup = try edited { _, parts in parts.append(.object(["id": .string("sun"), "shape": .object(["shaft": .object(["radius": .number(1), "length": .number(1)])])])) }
        XCTAssertEqual(reason(parse(dup)), "id.duplicate.sun")

        let crossing = try edited { _, parts in
            parts.append(.object(["id": .string("bow"), "shape": .object(["extrudedProfile": .object([
                "points": .array([[0, 0], [10, 10], [10, 0], [0, 10]].map { .array($0.map { .number(Double($0)) }) }), "depth": .number(2)])])]))
        }
        XCTAssertEqual(reason(parse(crossing)), "part.extrudedProfile.points")

        XCTAssertEqual(reason(MGSolidParser.document(data: Data("{".utf8))), "json")
        XCTAssertEqual(reason(parse(.object(["v": .number(3), "kind": .string("assembly"), "parts": .array([])]))), "assembly.version")
        // Assembly v2 exists (a strict superset of v1); an empty v2 document fails on its parts.
        XCTAssertEqual(reason(parse(.object(["v": .number(2), "kind": .string("assembly"), "parts": .array([])]))), "parts.count")
    }

    func testPatchesKeepIdentityAndReuseUnchangedMeshes() throws {
        let doc = try parse(Self.planetaryJSON()).get()
        let params = try MGSolidParser.applying(.object(["params": .object(["explode": .number(0.5), "input": .number(1)])]), to: doc).get()
        XCTAssertEqual(params.defaults, MGPoseParameters(input: 1, explode: 0.5))
        XCTAssertEqual(params.assembly.parts.map(\.id), doc.assembly.parts.map(\.id))
        XCTAssertEqual(params.assembly, doc.assembly)

        let recolour = try MGSolidParser.applying(.object(["parts": .object(["sun": .object(["material": .string("plastic.orange")])])]), to: doc).get()
        XCTAssertEqual(recolour.assembly.part("sun")!.material, .plastic(.orange))
        XCTAssertEqual(recolour.assembly.part("ring")!.mesh, doc.assembly.part("ring")!.mesh)

        // What if the carrier is held and the ring turns? Same ids, new ratios.
        let swap = try MGSolidParser.applying(.object([
            "parts": .object(["ring": .object(["joint": .object(["revolute": .array([.number(0), .number(0), .number(1)])])]),
                              "carrier": .object(["joint": .null])]),
        ]), to: doc).get()
        XCTAssertEqual(swap.assembly.parts.map(\.id), doc.assembly.parts.map(\.id))
        XCTAssertEqual(swap.ratios["ring"]!, -24.0 / 60.0, accuracy: 1e-12)   // star arrangement: ring turns backward
        XCTAssertNil(swap.ratios["carrier"])

        XCTAssertEqual(reason(MGSolidParser.applying(.object(["parts": .object(["ghost": .object(["material": .string("brass")])])]), to: doc)), "ref.unknown.ghost")
        XCTAssertEqual(reason(MGSolidParser.applying(.object(["bogus": .number(1)]), to: doc)), "patch.unknown.bogus")
    }

    func testMeshCheckReportsEngagementWithoutOverlap() throws {
        let doc = try parse(Self.planetaryJSON()).get()
        let report = MGSolidChecks.gearMeshes(doc, samples: 48)
        XCTAssertEqual(report.pairs, 6)
        XCTAssertLessThan(report.maxPenetration, 1e-6)
        XCTAssertGreaterThan(report.minClearance, 0)
        XCTAssertLessThan(report.minClearance, 0.3)
    }

    /// A small drone-style rotor pair: repeated cambered blades, opposite spin directions, and a casing revolve.
    func testRotorsWithRepeatedBladesAndOppositeSpin() throws {
        func blade() -> MGJSON { .object(["blade": .object(["span": .number(60), "chord": .number(14), "twist": .number(-18),
                                                              "root": .number(8), "camber": .number(0.04), "tipChord": .number(8)])]) }
        func num(_ v: [Double]) -> MGJSON { .array(v.map { .number($0) }) }
        let json: MGJSON = .object([
            "v": .number(1), "kind": .string("assembly"), "title": .string("Twin rotors"),
            "parts": .array([
                .object(["id": .string("hubA"), "shape": .object(["shaft": .object(["radius": .number(8), "length": .number(10)])]),
                         "joint": .object(["revolute": num([0, 0, 1])]), "drive": .object(["input": .number(1)]), "material": .string("plastic.blue")]),
                .object(["id": .string("bladeA"), "parent": .string("hubA"), "at": num([0, 0, 5]), "shape": blade(),
                         "repeat": .object(["count": .number(3)]), "material": .string("plastic.white")]),
                .object(["id": .string("hubB"), "at": num([200, 0, 0]), "shape": .object(["shaft": .object(["radius": .number(8), "length": .number(10)])]),
                         "joint": .object(["revolute": num([0, 0, 1])]), "drive": .object(["input": .number(-1)])]),
                .object(["id": .string("duct"), "at": num([200, 0, 0]), "material": .string("glass"),
                         "shape": .object(["revolvedProfile": .object(["closed": .bool(true),
                                                                       "points": .array([[72, -4], [76, -4], [78, 12], [72, 14]].map { num($0) })])])]),
            ]),
        ])
        let doc = try parse(json).get()
        XCTAssertEqual(doc.assembly.parts.map(\.id), ["hubA", "bladeA1", "bladeA2", "bladeA3", "hubB", "duct"])
        let pose = doc.pose(MGPoseParameters(input: 0.5))
        XCTAssertEqual(pose.values["hubA"]!, 0.5, accuracy: 1e-12)
        XCTAssertEqual(pose.values["hubB"]!, -0.5, accuracy: 1e-12)
        for p in doc.assembly.parts { XCTAssertTrue(p.mesh.edgeReport.isClosed, p.id) }
        // Blade 2 sits 120 degrees around the hub.
        let tip2 = pose.world["bladeA2"]!.apply(MGVec3(68, 0, 0)) - pose.world["hubA"]!.translation
        XCTAssertEqual(atan2(tip2.y, tip2.x), 0.5 + 2 * .pi / 3, accuracy: 1e-9)
    }

    func testSnapshotIsSelfConsistent() throws {
        let doc = try parse(Self.planetaryJSON()).get()
        let snap = MGSolidSnapshot.make(doc.assembly, params: MGPoseParameters(input: 0.4, explode: 0.3))
        XCTAssertEqual(snap.positions.count, snap.normals.count)
        XCTAssertEqual(snap.triangleMaterials.count, snap.triangleCount)
        XCTAssertEqual(snap.parts.count, doc.assembly.parts.count)
        XCTAssertEqual(snap.parts.last!.firstTriangle + snap.parts.last!.triangleCount, snap.triangleCount)
        XCTAssertTrue(snap.indices.allSatisfy { Int($0) < snap.vertexCount })
        XCTAssertTrue(snap.materials.contains { $0.id == "brass" && $0.parameters.metallic == 1 })
        // Y-up: the carrier sits above the base.
        XCTAssertGreaterThan(snap.boundsMax[1], 50)
        let decoded = try MGSolidSnapshot.decode(data: snap.jsonData())
        XCTAssertEqual(decoded, snap)
    }
}
