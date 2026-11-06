// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import MartyGraphics

/// Regressions from the independent review of the component library (one reference namespace, authored ids, repeat
/// copies, resolved id length, refusal order, step limits) and the blade pitch convention.
final class SolidComponentNamespaceTests: XCTestCase {
    func compile(_ s: String, _ library: MGSolidLibrary = .builtIn) -> Result<MGSolidDocument, MGSolidIssue> {
        MGSolidParser.document(data: Data(s.utf8), library: library)
    }
    func reason(_ s: String, _ library: MGSolidLibrary = .builtIn) -> String? {
        if case .failure(let e) = compile(s, library) { return e.reason }
        return nil
    }
    func register(_ s: String, into library: MGSolidLibrary = .builtIn) -> Result<MGSolidLibrary, MGSolidIssue> {
        var l = library
        switch l.register(Data(s.utf8)) {
        case .success: return .success(l)
        case .failure(let e): return .failure(e)
        }
    }
    func registerReason(_ s: String, into library: MGSolidLibrary = .builtIn) -> String? {
        if case .failure(let e) = register(s, into: library) { return e.reason }
        return nil
    }
    static let box = #"{"box":{"size":[4,4,4]}}"#
    func component(_ id: String, _ parts: String, _ extra: String = "") -> String {
        #"{"v":1,"kind":"component","id":"\#(id)","title":"T","about":"Review fixture.","parts":[\#(parts)]\#(extra)}"#
    }

    // MARK: B1: one reference namespace

    /// An anchor named like a repeat copy used to redirect `fixed` to another part while the real copy kept turning.
    func testAnchorCannotShadowARepeatCopy() throws {
        let driven = #"{"id":"pin","shape":\#(Self.box),"repeat":{"count":2},"joint":{"revolute":[0,0,1]},"drive":{"input":1}},{"id":"other","shape":\#(Self.box)}"#
        XCTAssertEqual(registerReason(component("aliasDriven", driven, #","anchors":{"pin1":"other"}"#)), "component.anchor.pin1")
        // Control: with a free anchor name the fixed copy really is the driven copy, so the conflict is reported.
        let l = try register(component("aliasSafe", driven, #","anchors":{"output":"other"}"#)).get()
        XCTAssertEqual(reason(#"{"v":1,"kind":"assembly","parts":[{"id":"a","use":"aliasSafe"}],"constraints":[{"fixed":"a.pin1"}]}"#, l),
                       "constraint.conflict")
        XCTAssertEqual(try compile(#"{"v":1,"kind":"assembly","parts":[{"id":"a","use":"aliasSafe"}],"constraints":[{"fixed":"a.output"}]}"#, l)
            .get().ratios["a.pin1"], 1)
    }

    func testInstanceIdCannotShadowARepeatCopy() throws {
        let plain = #"{"id":"p","repeat":{"count":2},"shape":\#(Self.box)}"#
        XCTAssertEqual(reason(#"{"v":1,"kind":"assembly","parts":[\#(plain),{"id":"p1","use":"propeller"}],"steps":[{"say":"First plain copy","highlight":["p1"]}]}"#),
                       "id.duplicate.p1")
        XCTAssertEqual(reason(#"{"v":1,"kind":"assembly","parts":[\#(plain),{"id":"p1","use":"propeller"},{"id":"child","parent":"p1","shape":\#(Self.box)}]}"#),
                       "id.duplicate.p1")
        // The same inside a definition, refused at registration.
        XCTAssertEqual(registerReason(component("groupCollision", #"\#(plain),{"id":"p1","use":"propeller"}"#)), "id.duplicate.p1")
        // A `set` that changes a repeat count is checked again: the new copies `pin1`, `pin2` meet the part `pin2`.
        let l = try register(component("pair", #"{"id":"pin","shape":\#(Self.box)},{"id":"pin2","shape":\#(Self.box)}"#)).get()
        XCTAssertEqual(reason(#"{"v":1,"kind":"assembly","parts":[{"id":"s","use":"pair","set":{"pin":{"repeat":{"count":2}}}}]}"#, l),
                       "id.duplicate.s.pin2")
        // A parameter that changes a repeat count is checked at every expansion.
        let counted = component("counted", #"{"id":"pin","shape":\#(Self.box),"repeat":{"count":{"param":"n"}}},{"id":"pin3","shape":\#(Self.box)}"#,
                                #","params":{"n":{"default":2,"min":2,"max":4,"integer":true}}"#)
        let l2 = try register(counted).get()
        XCTAssertNoThrow(try compile(#"{"v":1,"kind":"assembly","parts":[{"id":"c","use":"counted"}]}"#, l2).get())
        XCTAssertEqual(reason(#"{"v":1,"kind":"assembly","parts":[{"id":"c","use":"counted","with":{"n":3}}]}"#, l2), "id.duplicate.pin3")
    }

    // MARK: S1: authored ids

    func testAuthoredIdsStayIdentifiersBesideComponents() {
        let cases = ["bad.. id.xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx", "x. bad", "x y", "x!", "p.hub", "p.blade1",
                     String(repeating: "a", count: 25)]
        for id in cases {
            let one = #"{"v":1,"kind":"assembly","parts":[{"id":"p","use":"propeller"},{"id":"\#(id)","shape":\#(Self.box)}]}"#
            XCTAssertEqual(reason(one), "part.id", id)
            let twice = #"{"v":1,"kind":"assembly","parts":[{"id":"p","use":"propeller"},{"id":"\#(id)","shape":\#(Self.box)},{"id":"\#(id)","shape":\#(Self.box)}]}"#
            XCTAssertEqual(reason(twice), "part.id", id)
            // Without a component the same ids give the same reason.
            XCTAssertEqual(reason(#"{"v":1,"kind":"assembly","parts":[{"id":"\#(id)","shape":\#(Self.box)}]}"#), "part.id", id)
        }
        // A plain duplicate beside a component keeps its single-token reason.
        XCTAssertEqual(reason(#"{"v":1,"kind":"assembly","parts":[{"id":"p","use":"propeller"},{"id":"c","shape":\#(Self.box)},{"id":"c","shape":\#(Self.box)}]}"#),
                       "id.duplicate.c")
    }

    // MARK: S2: references to repeat copies

    func testRepeatCopiesCanBeReferenced() throws {
        // An outer part on one propeller blade.
        let d = try compile(#"{"v":1,"kind":"assembly","parts":[{"id":"p","use":"propeller"},{"id":"tip","parent":"p.blade1","shape":\#(Self.box)}]}"#).get()
        XCTAssertEqual(d.assembly.part("tip")?.parent, "p.blade1")
        let w = d.pose(MGPoseParameters(input: 0.7)).world
        XCTAssertEqual((w["tip"]!.translation - w["p.blade1"]!.translation).length, 0, accuracy: 1e-9)
        // Inside a definition: a parent and an anchor on one copy.
        let l = try register(component("repeated", #"{"id":"pin","repeat":{"count":2},"shape":\#(Self.box)},{"id":"tip","parent":"pin1","shape":\#(Self.box)}"#,
                                       #","anchors":{"out":"pin2"}"#)).get()
        let r = try compile(#"{"v":1,"kind":"assembly","parts":[{"id":"r","use":"repeated"}],"steps":[{"say":"Out","highlight":["r.out"]}]}"#, l).get()
        XCTAssertEqual(r.assembly.part("r.tip")?.parent, "r.pin1")
        XCTAssertEqual(r.steps[0].highlight, ["r.pin2"])
        // `set` and patches edit a repeated part through its base id (every copy), and say so for one copy.
        XCTAssertEqual(reason(#"{"v":1,"kind":"assembly","parts":[{"id":"p","use":"propeller","set":{"blade1":{"material":"brass"}}}]}"#),
                       "component.set.repeat.blade1")
        let base = try compile(#"{"v":1,"kind":"assembly","parts":[{"id":"p","use":"propeller"}]}"#).get()
        guard case .failure(let e) = MGSolidParser.applying(.object(["parts": .object(["p.blade1": .object(["material": .string("brass")])])]), to: base) else {
            return XCTFail("per-copy patch accepted")
        }
        XCTAssertEqual(e.reason, "component.set.repeat.blade1")
        let brass = try MGSolidParser.applying(.object(["parts": .object(["p.blade": .object(["material": .string("brass")])])]), to: base).get()
        XCTAssertEqual(brass.assembly.parts.filter { $0.id.hasPrefix("p.blade") }.map(\.material), [.brass, .brass, .brass])
    }

    // MARK: S3: resolved id length

    func testResolvedIdLengthIncludesTheRepeatSuffix() throws {
        let leaf = component("longLeaf", #"{"id":"xxxxxxxxxxxxxxxxxxxxxx","repeat":{"count":{"param":"n"}},"shape":\#(Self.box)}"#,
                             #","params":{"n":{"default":2,"min":2,"max":12,"integer":true}}"#)
        let short = component("short", #"{"id":"nnnnnnnnnnnnnnnnnn","use":"longLeaf","with":{"n":{"param":"n"}}}"#,
                              #","params":{"n":{"default":2,"min":2,"max":12,"integer":true}}"#)
        let l = try register(short, into: try register(leaf).get()).get()
        func use(_ id: String, _ n: Int) -> String { #"{"v":1,"kind":"assembly","parts":[{"id":"\#(id)","use":"short","with":{"n":\#(n)}}]}"# }
        let id21 = String(repeating: "y", count: 21), id22 = String(repeating: "y", count: 22)
        // 21 + 1 + 18 + 1 + 22 = 63 characters before the suffix: copies 1…9 are exactly 64.
        let ok = try compile(use(id21, 9), l).get()
        XCTAssertEqual(ok.assembly.parts.map(\.id.count).max(), 64)
        for n in [10, 12] { XCTAssertEqual(reason(use(id21, n), l), "component.id.length") }
        // The reviewed case: a 64-character wire id whose copies would be 65 and 66 characters.
        for n in [9, 12] { XCTAssertEqual(reason(use(id22, n), l), "component.id.length") }
    }

    // MARK: S4: refusal order

    /// Several invalid anchor or check names always report the first in sorted order. With eight names, a
    /// hash-ordered loop would pick another one in most processes.
    func testInvalidNamesReportTheSortedFirst() {
        let names = ["bad one", "bad two", "bad 3", "bad four", "bad five", "bad six", "bad 7", "bad eight"]
        for order in [names, names.reversed(), names.shuffled(), names.shuffled()] {
            let anchors = order.map { #""\#($0)":"c""# }.joined(separator: ",")
            XCTAssertEqual(registerReason(component("badAnchors", #"{"id":"c","shape":\#(Self.box)}"#, #","anchors":{\#(anchors)}"#)),
                           "component.anchor.bad_3")
            let checks = order.map { #""\#($0)":{"lt":[1,2]}"# }.joined(separator: ",")
            XCTAssertEqual(registerReason(component("badChecks", #"{"id":"c","shape":\#(Self.box)}"#, #","checks":{\#(checks)}"#)),
                           "component.check.name.bad_3")
        }
    }

    // MARK: N1: step limits

    func testAuthoredStepLimitDoesNotDependOnComponents() {
        let many = Array(repeating: #""c""#, count: 17).joined(separator: ",")
        let alone = #"{"v":1,"kind":"assembly","parts":[{"id":"c","shape":\#(Self.box)}],"steps":[{"say":"Test","highlight":[\#(many)]}]}"#
        let mixed = #"{"v":1,"kind":"assembly","parts":[{"id":"c","shape":\#(Self.box)},{"id":"p","use":"propeller"}],"steps":[{"say":"Test","focus":[\#(many)]}]}"#
        XCTAssertEqual(reason(alone), "step.highlight")
        XCTAssertEqual(reason(mixed), "step.focus")
        // Groups still expand and merge duplicates within the limit.
        let grouped = #"{"v":1,"kind":"assembly","parts":[{"id":"p","use":"propeller"}],"steps":[{"say":"Test","highlight":["p","p","p.hub"]}]}"#
        XCTAssertEqual(try compile(grouped).get().steps[0].highlight, ["p.hub", "p.blade1", "p.blade2", "p.blade3"])
    }

    /// The expression node budget is reachable through registration within 16 KiB.
    func testExpressionNodeBudgetThroughRegistration() throws {
        let leaf = #"{"add":[1,1,1,1,1,1,1,1]}"#
        let mid = #"{"add":[\#(Array(repeating: leaf, count: 8).joined(separator: ","))]}"#
        let big = #"{"add":[\#(Array(repeating: mid, count: 8).joined(separator: ","))]}"#   // 585 nodes, value 512
        let shapes = (0..<4).map { _ in #"{"box":{"size":[\#(big),\#(big)]}}"# }.joined(separator: ",")
        let def = component("wide", #"{"id":"c","shape":[\#(shapes)]}"#)
        XCTAssertLessThan(def.utf8.count, MGSolidComponentLimits.bytes)
        XCTAssertEqual(registerReason(def.replacingOccurrences(of: "\"size\":[", with: "\"size\":[1,")), "component.expr.size")
    }

    // MARK: Blade pitch

    func testBladePitchSetsTheRootAngle() throws {
        // A flat (uncambered) blade: the trailing edge of the root section sits at the pitch angle about +X.
        for degrees in [-40.0, 0, 25] {
            let m = MGMesh.blade(span: 50, chord: 20, thickness: 0.1, twist: 0, root: 0, pitch: degrees * .pi / 180)
            let rootSection = m.positions.filter { abs($0.x) < 1e-9 }
            let te = try XCTUnwrap(rootSection.max { MGVec2($0.y, $0.z).length < MGVec2($1.y, $1.z).length })
            XCTAssertEqual(atan2(te.z, te.y) * 180 / .pi, degrees, accuracy: 0.5)
        }
        // Mesh size does not depend on pitch.
        XCTAssertEqual(MGMesh.blade(span: 50, chord: 20, thickness: 0.1, twist: 0.3, pitch: 0.5).triangleCount,
                       MGMesh.blade(span: 50, chord: 20, thickness: 0.1, twist: 0.3).triangleCount)
        func blade(_ fields: String) -> String {
            #"{"v":1,"kind":"assembly","parts":[{"id":"b","shape":{"blade":{"span":50,"chord":20,\#(fields)}}}]}"#
        }
        XCTAssertEqual(reason(blade(#""pitch":81"#)), "part.blade.pitch")
        XCTAssertEqual(reason(blade(#""pitch":-60,"twist":-30"#)), "part.blade.twist")
        XCTAssertNil(reason(blade(#""pitch":-40,"twist":28"#)))
    }

    /// The propeller example and component move leading edge first, steep at the hub and flatter at the tip, and their
    /// blade angle pushes air toward -Z (thrust +Z, toward the camber side).
    func testPropellersMoveLeadingEdgeFirstWithRealisticPitch() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Examples/Solid3D/Sources/MartySolid3D/Models/propeller.json")
        let example = try MGSolidParser.document(data: Data(contentsOf: url)).get()
        let component = try MGSolidLibrary.builtIn.instantiate("propeller").get()
        for (doc, blade) in [(example, "blade1"), (component, "propeller.blade1")] {
            let f = try XCTUnwrap(doc.shapes[blade]?.first?.fields)
            guard case .number(let span)? = f["span"], case .number(let chord)? = f["chord"], case .number(let root)? = f["root"],
                  case .number(let pitch)? = f["pitch"], case .number(let twist)? = f["twist"] else { return XCTFail("blade fields") }
            XCTAssertGreaterThan(abs(pitch), abs(pitch + twist), "steeper at the hub than at the tip")
            for t in [0.0, 0.5, 1.0] {
                // Leading and trailing edge of the section at span fraction t, in the blade frame (see MGMesh.blade).
                let a = (pitch + twist * t) * .pi / 180, x = root + span * t
                let c = chord + ((f["tipChord"].flatMap { if case .number(let v) = $0 { return v }; return nil } ?? chord) - chord) * t
                let le = MGVec3(x, -0.25 * c * cos(a), -0.25 * c * sin(a)), te = MGVec3(x, 0.75 * c * cos(a), 0.75 * c * sin(a))
                let w0 = doc.pose(MGPoseParameters(input: 0)).world[blade]!, w1 = doc.pose(MGPoseParameters(input: 1e-4)).world[blade]!
                let velocity = w1.apply(le) - w0.apply(le), chordDir = w0.apply(le) - w0.apply(te)
                XCTAssertGreaterThan(velocity.dot(chordDir), 0, "leading edge first at t = \(t)")
                // Leading edge above the trailing edge: the blade turns the flow toward -Z.
                XCTAssertGreaterThan(w0.apply(le).z, w0.apply(te).z)
            }
        }
    }
}
