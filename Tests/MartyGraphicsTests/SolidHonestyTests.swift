// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import MartyGraphics

/// Assembly v2 honesty layer (open-vocabulary phase 1, row 1): the version gate, facts and placeholders, rule N1,
/// claim checks, truth tiers and the legend, idle joints, frame lints, `expect` claims, the read-back and the strict
/// profile. Ids refer to PHASE1-ACCEPTANCE.md (V, H).
final class SolidHonestyTests: XCTestCase {
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
    func model(_ name: String) throws -> Data {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try Data(contentsOf: root.appendingPathComponent("Examples/Solid3D/Sources/MartySolid3D/Models/\(name).json"))
    }

    /// PR #18 planetary stage (sun 24, planet 18, 3 planets) with one v2 step.
    func stage(_ step: String) -> String {
        #"{"v": 2, "kind": "assembly", "parts": [{"id": "stage", "use": "planetaryStage", "with": {"sunTeeth": 24, "planetTeeth": 18, "planets": 3}}], "steps": [\#(step)]}"#
    }
    let sliderSteps = [
        #"{"say": "A slider-crank turns spinning motion into back-and-forth motion."}"#,
        #"{"say": "Input: the crank turns. Its pin travels in a circle of radius 18 mm.", "highlight": ["engine.crank"], "spin": 1}"#,
    ]
    func slider(_ v: Int, _ steps: [String]) -> String {
        #"{"v": \#(v), "kind": "assembly", "parts": [{"id": "engine", "use": "sliderCrank", "with": {"radius": 18, "rod": 62, "piston": 14}}], "steps": [\#(steps.joined(separator: ","))]}"#
    }

    // MARK: V. Compatibility

    func testV1ExamplesKeepTheirMeaningAndTextStaysLiteral() throws {
        for name in ["planetary", "slider-crank", "propeller", "planetary-components", "slider-crank-component"] {
            guard case .success(let d) = MGSolidParser.document(data: try model(name)) else { return XCTFail(name) }
            XCTAssertEqual(d.version, 1, name)
            XCTAssertEqual(d.warnings, [], name)
            for s in d.steps { XCTAssertEqual(s.say, s.template); XCTAssertTrue(s.checks.isEmpty); XCTAssertNil(s.unchecked) }
            // Parsing twice gives the same document; the strict profile accepts every shipped v1 example.
            XCTAssertEqual(MGSolidParser.document(data: try model(name)), .success(d), name)
            XCTAssertEqual(MGSolidParser.document(data: try model(name), profile: .strict), .success(d), name)
        }
        // v1 never fills placeholders: braces and digits stay literal text.
        let v1 = try doc(#"{"v": 1, "kind": "assembly", "parts": [{"id": "a", "shape": {"box": {"size": [4, 4, 4]}}}], "steps": [{"say": "Gear {x} has 12 teeth."}]}"#)
        XCTAssertEqual(v1.steps[0].say, "Gear {x} has 12 teeth.")
        XCTAssertEqual(v1.steps[0].tier, .described)
    }

    func testNewKeysNeedVersionTwo() {
        let box = #""shape": {"box": {"size": [4, 4, 4]}}"#
        let cases: [(part: String, step: String, v1: String)] = [
            (#"{"id": "a", \#(box), "offAxis": true}"#, #"{"say": "Hi."}"#, "part.unknown.offAxis"),
            (#"{"id": "a", \#(box), "expect": {"upWorld": [0, 0, 1]}}"#, #"{"say": "Hi."}"#, "part.unknown.expect"),
            (#"{"id": "a", \#(box)}"#, #"{"say": "Hi.", "unchecked": "prose"}"#, "step.unknown.unchecked"),
            (#"{"id": "a", \#(box)}"#, #"{"say": "Hi.", "check": [{"value": "a.teeth", "eq": 1}]}"#, "step.unknown.check"),
        ]
        for c in cases {
            let body = #""kind": "assembly", "parts": [\#(c.part)], "steps": [\#(c.step)]}"#
            XCTAssertEqual(reason(#"{"v": 1, \#(body)"#), c.v1)                       // V2
            if c.step.contains(#""check""#) { XCTAssertEqual(reason(#"{"v": 2, \#(body)"#), "check.fact.a.teeth") }
            else { XCTAssertNil(reason(#"{"v": 2, \#(body)"#), c.v1) }                 // V3
        }
        XCTAssertEqual(reason(#"{"v": 3, "kind": "assembly", "parts": [{"id": "a", \#(box)}]}"#), "assembly.version")
        // A key no version knows yet stays refused in v2 too.
        XCTAssertEqual(reason(#"{"v": 2, "kind": "assembly", "parts": [{"id": "a", \#(box), "tracks": []}]}"#), "part.unknown.tracks")
    }

    /// V6: the solid core stays Foundation-only; only the SceneKit renderer and the annotation overlay (SwiftUI,
    /// CoreGraphics) import more.
    func testSolidCoreImportsOnlyFoundation() throws {
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/MartyGraphics/Solid")
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".swift") }.sorted()
        XCTAssertTrue(files.contains("MGSolidFacts.swift") && files.contains("MGSolidTiers.swift") && files.contains("MGSolidFrames.swift"))
        XCTAssertTrue(files.contains("MGSolidSection.swift") && files.contains("MGSolidView.swift"))
        XCTAssertTrue(files.contains("MGSolidAnnotations.swift") && files.contains("MGAnnotationLayout.swift"))
        for f in files where !["MGSolidRenderer.swift", "MGSolidOverlayView.swift"].contains(f) {
            let text = try String(contentsOf: dir.appendingPathComponent(f), encoding: .utf8)
            let imports = text.split(separator: "\n").filter { $0.hasPrefix("import ") || $0.hasPrefix("@testable import ") }
            XCTAssertEqual(imports, ["import Foundation"], f)
        }
    }

    // MARK: H. Facts, placeholders, N1, checks

    func testPlaceholdersFillFromEngineFactsWithModifiers() throws {
        let d = try doc(stage(#"{"say": "The carrier turns {stage.output.speed|frac} of a turn."}"#))       // H1
        XCTAssertEqual(d.steps[0].say, "The carrier turns 2/7 of a turn.")
        XCTAssertEqual(d.steps[0].template, "The carrier turns {stage.output.speed|frac} of a turn.")
        XCTAssertEqual(d.steps[0].facts, ["stage.carrier.speed"])
        XCTAssertEqual(d.steps[0].tier, .solved)
        XCTAssertEqual(d.fact("stage.output.speed")?.tier, .solved)
        XCTAssertEqual(d.fact("stage.output.speed")?.source, "gearMesh")
        XCTAssertEqual(d.fact("stage.output.speed")!.value, 24.0 / 84, accuracy: 1e-12)
        let h2 = try doc(stage(#"{"say": "{stage.output.speed} or {stage.output.speed|inv}; {stage.output.speed|pct}, {stage.output.speed|deg}."}"#))
        XCTAssertEqual(h2.steps[0].say, "0.29 or 3.5; 28.6%, 103°.")                                       // H2
        let more = try doc(stage(#"{"say": "Sun {stage.sun.teeth}, planets {count.stage.planet} of {stage.planet.teeth}, ring {stage.ring.teeth}, module {stage.sun.module}, ratio {stage.ratio|frac}, planet {stage.planet.speed|abs|frac}.", "check": [{"value": "stage.planet.speed", "lt": 0}]}"#))
        XCTAssertEqual(more.steps[0].say, "Sun 24, planets 3 of 18, ring 60, module 2 mm, ratio 2/7, planet 20/21.")
        XCTAssertEqual(more.fact("count.stage.planet")?.source, "repeat")
    }

    func testFractionsAndModifierRefusals() {
        XCTAssertEqual(MGSolidFacts.fraction(24.0 / 84), "2/7")
        XCTAssertEqual(MGSolidFacts.fraction(-1.0 / 3), "-1/3")
        XCTAssertEqual(MGSolidFacts.fraction(0.375), "3/8")
        XCTAssertEqual(MGSolidFacts.fraction(1.0 / 30), "1/30")
        XCTAssertEqual(MGSolidFacts.fraction(3), "3")
        XCTAssertEqual(MGSolidFacts.fraction(0), "0")
        XCTAssertNil(MGSolidFacts.fraction(.pi))
        XCTAssertNil(MGSolidFacts.fraction(1.0 / 100_003))
        let cases: [(String, String)] = [
            ("{stage.sun.module|inv}", "text.modifier.inv.stage.sun.module"),           // inv needs a pure number
            ("{stage.output.speed|frac|abs}", "text.modifier.abs.stage.output.speed"),  // nothing after frac, pct or deg
            ("{stage.output.speed|half}", "text.modifier.half"),
            ("{stage.output.speed|abs|abs|abs|abs}", "text.placeholder"),
            ("{}", "text.placeholder"), ("{a b}", "text.placeholder"), ("{a", "text.brace"), ("a } b", "text.brace"), ("{a{b}}", "text.brace"),
        ]
        for (text, expected) in cases { XCTAssertEqual(reason(stage(#"{"say": "\#(text)"}"#)), expected, text) }
        XCTAssertEqual(reason(stage(#"{"say": "{stage.ring.speed|frac}"}"#)), "text.placeholder.stage.ring.speed")   // the ring has no joint
    }

    func testTravelFactReplacesTypedStroke() throws {
        // H3 (with `<part>.travel`; the `dimension` form arrives with annotations): measured over one input turn.
        let d = try doc(slider(2, [#"{"say": "Its stroke is {engine.piston.travel}; the crank radius is {engine.piston.crankRadius}."}"#,
                                   #"{"say": "Same through the anchor: {engine.output.travel}."}"#]))
        XCTAssertEqual(d.steps[0].say, "Its stroke is 36 mm; the crank radius is 18 mm.")
        XCTAssertEqual(d.steps[1].say, "Same through the anchor: 36 mm.")
        XCTAssertEqual(d.fact("engine.piston.travel")!.value, 36, accuracy: 0.01)
        XCTAssertEqual(d.fact("engine.piston.travel")?.tier, .solved)
        XCTAssertEqual(d.steps[0].tier, .solved)
    }

    func testRuleN1AndUnchecked() throws {
        XCTAssertEqual(reason(slider(2, sliderSteps)), "text.number.step.2")                              // H4
        XCTAssertNil(reason(slider(1, sliderSteps)))                                                       // v1 unchanged
        let marked = sliderSteps[1].replacingOccurrences(of: #", "spin": 1}"#, with: #", "spin": 1, "unchecked": "author's numbers"}"#)
        let d = try doc(slider(2, [sliderSteps[0], marked]))                                               // H5
        XCTAssertEqual(d.steps[1].tier, .described)
        XCTAssertNil(d.steps[0].tier)   // prose with no engine number: no tier, no check mark
        let claim = d.claims.first { $0.id == "step.2" }
        XCTAssertEqual(claim?.badge, "Not checked")
        XCTAssertEqual(claim?.why, "Marked unchecked: author's numbers")
        // Number characters beyond ASCII digits count too; titles and names may hold digits.
        XCTAssertEqual(reason(stage(#"{"say": "About ½ a turn."}"#)), "text.number.step.1")
        XCTAssertNil(reason(#"{"v": 2, "kind": "assembly", "title": "V8 engine, NACA 2412", "parts": [{"id": "a", "name": "Part 7", "shape": {"box": {"size": [4, 4, 4]}}}]}"#))
        XCTAssertEqual(reason(stage(#"{"say": "Hi.", "unchecked": ""}"#)), "step.unchecked")
        XCTAssertEqual(reason(stage(#"{"say": "The ring has {stage.nothing}."}"#)), "text.placeholder.stage.nothing")   // H6
        // The title fills too and carries a tier.
        let t = try doc(#"{"v": 2, "kind": "assembly", "title": "A {stage.sun.teeth}-tooth sun", "parts": [{"id": "stage", "use": "planetaryStage"}]}"#)
        XCTAssertEqual(t.title, "A 24-tooth sun")
        XCTAssertEqual(t.titleTier, .solved)
    }

    func testClaimChecks() throws {
        func check(_ c: String) -> String? { reason(stage(#"{"say": "The carrier turns slowly.", "check": [\#(c)]}"#)) }
        XCTAssertEqual(check(#"{"value": "stage.output.speed", "eq": 0.3, "tol": 0.001}"#), "check.failed.stage.output.speed")   // H7
        XCTAssertNil(check(#"{"value": "stage.output.speed", "eq": 0.2857, "tol": 0.001}"#))
        XCTAssertNil(check(#"{"value": "stage.output.speed", "eq": 0.286}"#))         // what the learner sees: "0.29"
        XCTAssertEqual(check(#"{"value": "stage.output.speed", "eq": 0.28}"#), "check.failed.stage.output.speed")
        XCTAssertNil(check(#"{"value": "stage.output.speed", "lt": 1}"#))
        XCTAssertEqual(check(#"{"value": "stage.output.speed", "gt": 1}"#), "check.failed.stage.output.speed")
        XCTAssertEqual(check(#"{"value": "stage.nope", "eq": 1}"#), "check.fact.stage.nope")
        XCTAssertEqual(check(#"{"value": "stage.output.speed"}"#), "check.comparison")
        XCTAssertEqual(check(#"{"value": "stage.output.speed", "lt": 1, "tol": 0.1}"#), "check.tol")
        XCTAssertEqual(check(#"{"value": "a b", "eq": 1}"#), "check.value")
        XCTAssertEqual(check(#"{"eq": 1}"#), "step.check.missing.value")
        XCTAssertEqual(reason(stage(#"{"say": "Hi.", "check": []}"#)), "step.check")
        // A passing check is its own claim; it does not give prose a tier.
        let d = try doc(stage(#"{"say": "The carrier turns slower than the sun.", "check": [{"value": "stage.output.speed", "lt": 1}]}"#))
        XCTAssertNil(d.steps[0].tier)
        XCTAssertEqual(d.steps[0].checks, [MGSolidClaimCheck(value: "stage.output.speed", comparison: .lt, target: 1, tolerance: nil)])
        let claim = d.claims.first { $0.kind == .check }
        XCTAssertEqual(claim?.id, "step.1.check.1")
        XCTAssertEqual(claim?.badge, "Checked")
        XCTAssertEqual(claim?.why, "Checked: stage.output.speed < 1")
    }

    func testTierKeyIsRefused() {
        XCTAssertEqual(reason(#"{"v": 2, "kind": "assembly", "parts": [{"id": "a", "shape": {"box": {"size": [4, 4, 4]}}, "tier": "solved"}]}"#), "tier.key")   // H8
        XCTAssertEqual(reason(stage(#"{"say": "Hi.", "check": [{"value": "x", "eq": 1, "tier": "solved"}]}"#)), "tier.key")
        XCTAssertEqual(reason(#"{"v": 1, "kind": "assembly", "parts": [{"id": "a", "shape": {"box": {"size": [4, 4, 4]}}, "tier": "solved"}]}"#), "part.unknown.tier")
    }

    func testPatchedStepsFollowTheRules() throws {
        let d = try doc(stage(#"{"say": "Turns {stage.output.speed|frac}."}"#))
        XCTAssertEqual(MGSolidParser.applying(.object(["steps": .array([.object(["say": .string("Turns 2/7.")])])]), to: d).map(\.title),
                       .failure(MGSolidIssue("text.number.step.1")))
        guard case .success(let p) = MGSolidParser.applying(.object(["parts": .object(["stage": .object(["with": .object(["sunTeeth": .number(30), "planetTeeth": .number(15)])])])]), to: d) else { return XCTFail() }
        XCTAssertEqual(p.steps[0].say, "Turns 1/3.")   // 30 / (30 + 60)
    }

    // MARK: Tiers and legend

    func testTierCalculusAndLegend() throws {
        // H20: the lowest placeholder tier wins; Built captions show "Schematic".
        let solved = MGSolidFact(value: 1, unit: "", tier: .solved, source: "input")
        let built = MGSolidFact(value: 2, unit: "", tier: .built, source: "track")
        XCTAssertEqual(MGSolidTiers.text(facts: [solved, built], unchecked: false), .built)
        XCTAssertEqual(MGSolidTiers.text(facts: [solved], unchecked: true), .described)
        XCTAssertNil(MGSolidTiers.text(facts: [], unchecked: false))
        XCTAssertEqual(MGSolidTier.built.badge(.caption), "Schematic")
        XCTAssertEqual(MGSolidTier.built.badge(.motion), "Schematic motion")
        XCTAssertEqual(MGSolidTier.solved.badge(.caption), "Numbers solved")
        XCTAssertEqual(MGSolidTier.solved.badge(.motion), "Solved")
        XCTAssertLessThan(MGSolidTier.described, MGSolidTier.built)
        // Hand count on the v2 worked example: pinion and wheel motion, three filled captions, one unchecked caption.
        let d = try doc(String(decoding: try model("horizontal-reduction"), as: UTF8.self))
        let legend = d.legend
        XCTAssertEqual(legend.claims.map(\.id), ["pinion", "wheel", "step.2", "step.3", "step.3.check.1", "step.3.check.2", "step.4", "step.4.check.1", "step.5"])
        XCTAssertEqual([legend.solved, legend.built, legend.described], [8, 0, 1])
        XCTAssertEqual(legend.text, "Solved 8 (2 animation ratios) · Not checked 1")
        XCTAssertNil(legend.note)
        XCTAssertEqual(legend.shapes, "Shapes as authored")
        XCTAssertEqual(Array(d.steps.map(\.say)[1...3]), ["The pinion has 15 teeth; the wheel has 40.",
                                                  "Each pinion turn moves the wheel 3/8 of a turn, the other way.",
                                                  "So the output collar turns 2.67 times slower than the input."])
        // Motion claims count each authored part once; a child that only rides on its parent makes none.
        let p = try doc(stage(#"{"say": "Hi."}"#))
        XCTAssertEqual(p.claims.map(\.id), ["stage.sun", "stage.carrier", "stage.planet"])
        XCTAssertNil(p.motionTier("stage.ring"))
        XCTAssertEqual(p.motionTier("stage.planet2"), .solved)
        XCTAssertEqual(p.motionTier("stage.output"), .solved)
        // v1 captions with numbers are Not checked.
        guard case .success(let v1) = MGSolidParser.document(data: try model("slider-crank")) else { return XCTFail() }
        XCTAssertEqual(v1.legend.text, "Solved 3 (animation ratios) · Not checked 3")
    }

    func testDescribe() throws {
        let d = try doc(stage(#"{"say": "Hi."}"#))
        guard case .object(let o)? = d.describe("stage.output") else { return XCTFail() }
        XCTAssertEqual(o["id"], .string("stage.carrier"))
        XCTAssertEqual(o["motion"], .string("Solved by gearMesh (0.29 turns per input turn)"))
        XCTAssertEqual(o["tier"], .string("solved"))
        guard case .object(let facts)? = o["facts"], case .array(let nc)? = o["notChecked"] else { return XCTFail() }
        XCTAssertEqual(facts.keys.sorted(), ["stage.carrier.speed", "stage.carrier.worldSpeed"])
        XCTAssertTrue(nc.contains(.string("3D tooth contact")))
        guard case .object(let planet)? = d.describe("stage.planet"), case .object(let pf)? = planet["facts"] else { return XCTFail() }
        XCTAssertTrue(pf.keys.contains("count.stage.planet") && pf.keys.contains("stage.planet.teeth"))
        guard case .object(let ring)? = d.describe("stage.ring") else { return XCTFail() }
        XCTAssertEqual(ring["motion"], .string("Static"))
        XCTAssertEqual(ring["tier"], .null)
        XCTAssertNil(d.describe("stage.nothing"))
    }

    // MARK: Idle joints and frames

    let box = #"{"box": {"size": [40, 8, 4]}}"#
    func one(_ v: Int, _ parts: [String], steps: String = "") -> String {
        #"{"v": \#(v), "kind": "assembly", "parts": [\#(parts.joined(separator: ","))]\#(steps)}"#
    }

    func testIdleJointWarnsAndStrictRefuses() throws {
        let idle = #"{"id": "disc", "shape": {"shaft": {"radius": 20, "length": 5}}, "joint": {"revolute": [0, 0, 1]}}"#
        for v in [1, 2] {
            let d = try doc(one(v, [idle]))                                                                    // H9
            XCTAssertEqual(d.warnings, [MGSolidIssue("joint.idle.disc", part: "disc")])
            XCTAssertEqual(reason(one(v, [idle]), profile: .strict), "joint.idle.disc")
            XCTAssertTrue(d.readBack[0].contains("with no drive: never moves (joint.idle)"), d.readBack[0])
            guard case .object(let o)? = d.describe("disc") else { return XCTFail() }
            XCTAssertEqual(o["motion"], .string("Idle: the joint has no drive or constraint, so it never moves"))
        }
        let driven = idle.replacingOccurrences(of: "[0, 0, 1]}}", with: #"[0, 0, 1]}, "drive": {"input": 1}}"#)
        XCTAssertEqual(try doc(one(2, [driven])).warnings, [])
        // Held on purpose: a drive of 0 or a `fixed` constraint is not idle. A repeated idle part warns once.
        XCTAssertEqual(try doc(one(2, [driven.replacingOccurrences(of: #""input": 1"#, with: #""input": 0"#)])).warnings, [])
        let repeated = idle.replacingOccurrences(of: #""id": "disc","#, with: #""id": "disc", "at": [60, 0, 0], "repeat": {"count": 3},"#)
        XCTAssertEqual(try doc(one(2, [repeated])).warnings.map(\.reason), ["joint.idle.disc"])
    }

    func testAbsoluteChildOffset() throws {
        let hub = #"{"id": "hub", "at": [50, 0, 0], "shape": {"shaft": {"radius": 10, "length": 20}}}"#
        let bad = #"{"id": "blade", "parent": "hub", "at": [50, 0, 0], "shape": \#(box)}"#
        let d = try doc(one(2, [hub, bad]))                                                                    // H14
        XCTAssertEqual(d.warnings, [MGSolidIssue("frame.child.absolute.blade", part: "blade")])
        // A heuristic: a warning in every profile, never a strict refusal (it can flag correct layouts).
        XCTAssertNil(reason(one(2, [hub, bad]), profile: .strict))
        XCTAssertNil(reason(one(1, [hub, bad]), profile: .strict))
        let good = bad.replacingOccurrences(of: #""at": [50, 0, 0]"#, with: #""at": [0, 0, 0]"#)
        XCTAssertEqual(try doc(one(2, [hub, good])).warnings, [])
        // The parent's world position counts too (a grandparent moved it).
        let base = #"{"id": "base", "at": [0, 30, 0], "shape": \#(box)}"#
        let mid = #"{"id": "mid", "parent": "base", "at": [20, 0, 0], "shape": \#(box)}"#
        let leaf = #"{"id": "leaf", "parent": "mid", "at": [20, 30, 0], "shape": \#(box)}"#
        XCTAssertEqual(try doc(one(2, [base, mid, leaf])).warnings.map(\.reason), ["frame.child.absolute.leaf"])
    }

    func testFarChildStaysAWarning() throws {
        let parent = #"{"id": "frame", "shape": {"box": {"size": [40, 40, 40]}}}"#
        let far = #"{"id": "lamp", "parent": "frame", "at": [2000, 0, 0], "shape": {"box": {"size": [10, 10, 10]}}}"#
        XCTAssertEqual(try doc(one(2, [parent, far])).warnings, [MGSolidIssue("frame.child.far.lamp", part: "lamp")])   // H15
        XCTAssertNil(reason(one(2, [parent, far]), profile: .strict))
        let near = far.replacingOccurrences(of: "2000", with: "60")
        XCTAssertEqual(try doc(one(2, [parent, near])).warnings, [])
    }

    func testTurnAxisMustPassThroughItsPart() throws {
        let disc = #"{"id": "disc", "shape": {"shaft": {"radius": 15, "length": 6, "at": [80, 0, 0]}}, "joint": {"revolute": [0, 0, 1]}, "drive": {"input": 1}}"#
        XCTAssertEqual(try doc(one(2, [disc])).warnings, [MGSolidIssue("frame.axis.off.disc", part: "disc")])   // H16
        XCTAssertEqual(reason(one(2, [disc]), profile: .strict), "frame.axis.off.disc")
        let marked = disc.replacingOccurrences(of: #""drive""#, with: #""offAxis": true, "drive""#)
        XCTAssertEqual(try doc(one(2, [marked])).warnings, [])
        // A crank pin inside a crank part: the bounds include the hub on the axis.
        let crank = #"{"id": "crank", "shape": [{"shaft": {"radius": 6, "length": 16, "z0": -10}}, {"box": {"size": [30, 12, 6], "at": [9, 0, -3]}}, {"shaft": {"radius": 4, "length": 10, "at": [18, 0, 0]}}], "joint": {"revolute": [0, 0, 1]}, "drive": {"input": 1}}"#
        XCTAssertEqual(try doc(one(2, [crank])).warnings, [])
        // A link hinged at its end is on axis.
        let link = #"{"id": "link", "shape": {"box": {"size": [62, 8, 4], "at": [-31, 0, 5]}}, "joint": {"revolute": [0, 0, 1]}, "drive": {"input": 1}}"#
        XCTAssertEqual(try doc(one(2, [link])).warnings, [])
    }

    func testWarningsComeInPartOrder() throws {
        let a = #"{"id": "a", "shape": {"shaft": {"radius": 5, "length": 5, "at": [90, 0, 0]}}, "joint": {"revolute": [0, 0, 1]}}"#
        let b = #"{"id": "b", "parent": "a", "at": [3000, 0, 0], "shape": \#(box)}"#
        let warnings = try doc(one(2, [a, b])).warnings.map(\.reason)
        XCTAssertEqual(warnings, ["joint.idle.a", "frame.axis.off.a", "frame.child.far.b"])
        for _ in 0..<5 { XCTAssertEqual(try doc(one(2, [a, b])).warnings.map(\.reason), warnings) }
    }

    // MARK: Orientation claims and read-back

    let tower = #"{"id": "tower", "name": "Tower", "shape": {"shaft": {"radius": 4, "length": 90}}, "expect": {"upWorld": [0, 0, 1]}}"#
    func rotor(rot: String) -> String {
        #"{"id": "rotor", "parent": "tower", "at": [0, 0, 92]\#(rot), "shape": {"shaft": {"radius": 5, "length": 20, "z0": -10}}, "joint": {"revolute": [0, 0, 1]}, "drive": {"input": 1}, "expect": {"axisWorld": [1, 0, 0]}}"#
    }
    let blade = #"{"id": "blade", "parent": "rotor", "at": [0, 30, 0], "shape": {"box": {"size": [4, 60, 2]}}}"#

    func testExpectOrientationClaims() throws {
        XCTAssertEqual(reason(one(2, [tower, rotor(rot: ""), blade])), "expect.axis.rotor")                  // H17
        let turned = one(2, [tower, rotor(rot: #", "rot": [0, 1, 0, 90]"#), blade])
        XCTAssertNil(reason(turned))
        XCTAssertEqual(reason(one(2, [tower, rotor(rot: #", "rot": [0, 1, 0, -90]"#), blade])), "expect.axis.rotor")   // sign matters
        let tipped = tower.replacingOccurrences(of: #""name": "Tower","#, with: #""name": "Tower", "rot": [1, 0, 0, 90],"#)
        XCTAssertEqual(reason(one(2, [tipped])), "expect.up.tower")
        XCTAssertEqual(reason(one(2, [#"{"id": "a", "shape": \#(box), "expect": {"axisWorld": [1, 0, 0]}}"#])), "expect.axis.a")
        XCTAssertEqual(reason(one(2, [#"{"id": "a", "shape": \#(box), "expect": {}}"#])), "part.expect")
        XCTAssertEqual(reason(one(2, [#"{"id": "a", "shape": \#(box), "expect": {"axis": [1, 0, 0]}}"#])), "part.expect.unknown.axis")
        XCTAssertEqual(reason(one(2, [#"{"id": "a", "shape": \#(box), "expect": {"upWorld": [0, 0, 0]}}"#])), "part.expect.upWorld")
    }

    func testReadBackGoldenText() throws {
        let d = try doc(one(2, [tower, rotor(rot: #", "rot": [0, 1, 0, 90]"#), blade]))                     // H18
        XCTAssertEqual(d.warnings, [])
        XCTAssertEqual(d.readBack, [
            "tower: world centre (0, 0, 45) mm, size 8 x 8 x 90 mm; static; root (at [0, 0, 0] in the world frame); local +Z points +Z",
            "rotor: world centre (0, 0, 92) mm, size 20 x 10 x 10 mm; turns about a horizontal axis (+X) through (0, 0, 92); 1 turn per input turn (Solved, input); child of tower (at [0, 0, 92] in the tower frame); local +Z points +X",
            "blade: world centre (0, 30, 92) mm, size 2 x 60 x 4 mm; fixed to its parent, moves with rotor; child of rotor (at [0, 30, 0] in the rotor frame); its origin is 30 mm from the rotor axis; local +Z points +X",
        ])
        XCTAssertEqual(MGSolidFrames.axisWords(MGVec3(0, 0, -1)), "a vertical axis (-Z)")
        XCTAssertEqual(MGSolidFrames.axisWords(MGVec3(1, 1, 0)), "a horizontal axis along (0.71, 0.71, 0)")
        XCTAssertEqual(MGSolidFrames.axisWords(MGVec3(0.5, 0, 0.5 * 3.0.squareRoot())), "an axis tilted 30° from vertical, along (0.5, 0, 0.87)")
    }

    func testWorkedV2ExamplePassesStrict() throws {
        let data = try model("horizontal-reduction")
        guard case .success(let d) = MGSolidParser.document(data: data, profile: .strict) else { return XCTFail() }
        XCTAssertEqual(d.version, 2)
        XCTAssertEqual(d.warnings, [])
        XCTAssertEqual(d.fact("wheel.speed")!.value, -0.375, accuracy: 1e-12)
        XCTAssertTrue(d.readBack.contains { $0.hasPrefix("pinion:") && $0.contains("turns about a horizontal axis (+X)") })
        XCTAssertTrue(d.readBack.contains { $0.hasPrefix("collar:") && $0.contains("child of wheel (at [0, 0, 26] in the wheel frame)") })
    }
}

/// Regressions from the independent review of PR #21 (one test per finding, fixtures from the review).
final class SolidHonestyReviewTests: XCTestCase {
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
    func stage(_ step: String, title: String = "") -> String {
        #"{"v": 2, "kind": "assembly", \#(title)"parts": [{"id": "stage", "use": "planetaryStage", "with": {"sunTeeth": 24, "planetTeeth": 18, "planets": 3}}], "steps": [\#(step)]}"#
    }

    /// B1: a typed number in a title makes it Described, even beside a placeholder.
    func testB1TitleWithTypedNumberIsDescribed() throws {
        let d = try doc(stage(#"{"say": "Hi."}"#, title: #""title": "A 3:1 reduction with a {stage.sun.teeth}-tooth sun", "#))
        XCTAssertEqual(d.title, "A 3:1 reduction with a 24-tooth sun")
        XCTAssertEqual(d.titleTier, .described)
        let claim = d.claims.first { $0.kind == .title }
        XCTAssertEqual(claim?.badge, "Not checked")
        XCTAssertEqual(claim?.why, "Title has typed numbers")
        XCTAssertEqual(try doc(stage(#"{"say": "Hi."}"#, title: #""title": "A {stage.sun.teeth}-tooth sun", "#)).titleTier, .solved)
        // The same rule in v1, where titles are never filled.
        let v1 = try doc(#"{"v": 1, "kind": "assembly", "title": "Reducer, 12.25:1", "parts": [{"id": "a", "shape": {"box": {"size": [4, 4, 4]}}}]}"#)
        XCTAssertEqual(v1.titleTier, .described)
    }

    /// B2: children that touch their parent as placed are correct, even when `at` equals the parent's `at`.
    func testB2EqualStepsAreNotDoubleOffsets() throws {
        let fixtures = [
            #"{"v": 2, "kind": "assembly", "parts": [{"id": "base", "shape": {"shaft": {"radius": 15, "length": 40}}}, {"id": "upper", "parent": "base", "at": [0, 0, 40], "shape": [{"shaft": {"radius": 5, "length": 10, "z0": -5, "rot": [1, 0, 0, 90]}}, {"box": {"size": [8, 8, 40], "at": [0, 0, 20]}}], "joint": {"revolute": [0, 1, 0]}, "drive": {"input": 0.1}}, {"id": "fore", "parent": "upper", "at": [0, 0, 40], "shape": [{"shaft": {"radius": 4, "length": 10, "z0": -5, "rot": [1, 0, 0, 90]}}, {"box": {"size": [6, 6, 40], "at": [0, 0, 20]}}], "joint": {"revolute": [0, 1, 0]}, "drive": {"input": -0.2}}]}"#,
            #"{"v": 2, "kind": "assembly", "parts": [{"id": "link1", "at": [50, 0, 0], "shape": {"box": {"size": [50, 8, 4], "at": [25, 0, 0]}}}, {"id": "link2", "parent": "link1", "at": [50, 0, 0], "shape": {"box": {"size": [50, 8, 4], "at": [25, 0, 0]}}}, {"id": "link3", "parent": "link2", "at": [50, 0, 0], "shape": {"box": {"size": [50, 8, 4], "at": [25, 0, 0]}}}]}"#,
            #"{"v": 2, "kind": "assembly", "parts": [{"id": "p1", "at": [0, 0, 10], "shape": {"box": {"size": [40, 40, 10]}}}, {"id": "p2", "parent": "p1", "at": [0, 0, 10], "shape": {"box": {"size": [40, 40, 10]}}}]}"#,
        ]
        // A child of a parent at the world origin that only rotates (the shipped turbofan's spinner on its shaft).
        let spinner = #"{"v": 2, "kind": "assembly", "parts": [{"id": "shaft", "rot": [0, 1, 0, 90], "shape": {"tube": {"inner": 28, "outer": 45, "length": 1000, "z0": 150}}, "joint": {"revolute": [0, 0, 1]}, "drive": {"input": 1}}, {"id": "spinner", "parent": "shaft", "shape": {"revolvedProfile": {"points": [[0, -320], [262, -10], [0, -10]]}}}]}"#
        for f in fixtures + [spinner] {
            XCTAssertEqual(try doc(f).warnings, [], f)
            XCTAssertNil(reason(f, profile: .strict), f)
        }
    }

    /// S2: the double offset is found by geometry, not only by exact matches.
    func testS2DoubleOffsetFoundByGeometry() {
        let cases: [(String, String)] = [
            (#"{"v": 2, "kind": "assembly", "parts": [{"id": "hub", "at": [50, 0, 0], "shape": {"shaft": {"radius": 10, "length": 20}}}, {"id": "blade", "parent": "hub", "at": [50, 30, 0], "shape": {"box": {"size": [40, 8, 4]}}}]}"#, "frame.child.absolute.blade"),
            (#"{"v": 2, "kind": "assembly", "parts": [{"id": "hub", "at": [50, 0, 0], "rot": [0, 0, 1, 90], "shape": {"shaft": {"radius": 10, "length": 20}}}, {"id": "blade", "parent": "hub", "at": [70, 0, 0], "shape": {"box": {"size": [40, 8, 4]}}}]}"#, "frame.child.absolute.blade"),
            (#"{"v": 2, "kind": "assembly", "parts": [{"id": "tower", "shape": {"shaft": {"radius": 4, "length": 90}}}, {"id": "nacelle", "parent": "tower", "at": [0, 0, 92], "shape": {"box": {"size": [30, 12, 12]}}}, {"id": "rotor", "parent": "nacelle", "at": [16, 0, 92], "rot": [0, 1, 0, 90], "shape": {"shaft": {"radius": 5, "length": 8}}, "joint": {"revolute": [0, 0, 1]}, "drive": {"input": 1}}]}"#, "frame.child.absolute.rotor"),
        ]
        for (f, r) in cases {
            XCTAssertTrue(try doc(f).warnings.map(\.reason).contains(r), f)
            XCTAssertNil(reason(f, profile: .strict), f)   // warning only
        }
    }

    /// S1: author behaviour is Built: a `follow` ratio, an `input` scale other than ±1, and what they feed.
    func testS1AuthorRatesAreBuilt() throws {
        let follow = try doc(#"{"v": 2, "kind": "assembly", "parts": [{"id": "a", "shape": {"shaft": {"radius": 10, "length": 4}}, "joint": {"revolute": [0, 0, 1]}, "drive": {"input": 1}}, {"id": "b", "at": [60, 0, 0], "shape": {"shaft": {"radius": 20, "length": 4}}, "joint": {"revolute": [0, 0, 1]}, "drive": {"follow": {"source": "a", "ratio": 0.37}}}], "steps": [{"say": "The belt makes the big pulley turn {b.speed|frac} of a turn."}]}"#)
        XCTAssertEqual(follow.fact("b.speed")?.tier, .built)
        XCTAssertEqual(follow.fact("a.speed")?.tier, .solved)
        XCTAssertEqual(follow.steps[0].tier, .built)
        XCTAssertEqual(follow.motionTier("b"), .built)
        XCTAssertEqual(follow.legend.text, "Solved 1 (animation ratio) · Schematic 2")
        XCTAssertEqual(follow.legend.note, "Some motion is schematic")
        XCTAssertEqual(follow.claims.first { $0.id == "b" }?.badge, "Schematic motion")
        let scaled = try doc(#"{"v": 2, "kind": "assembly", "parts": [{"id": "d", "shape": {"shaft": {"radius": 10, "length": 4}}, "joint": {"revolute": [0, 0, 1]}, "drive": {"input": 0.333}}], "steps": [{"say": "It turns {d.speed|frac} of a turn."}]}"#)
        XCTAssertEqual(scaled.steps[0].tier, .built)
        // A gear mesh fed by an author speed carries it; the reference speed (±1) stays Solved.
        func pair(_ scale: Double) throws -> MGSolidDocument {
            try doc(#"{"v": 2, "kind": "assembly", "parts": [{"id": "p", "use": "spurPair", "set": {"pinion": {"drive": {"input": \#(scale)}}}}]}"#)
        }
        XCTAssertEqual(try pair(2).fact("p.wheel.speed")?.tier, .built)
        XCTAssertEqual(try pair(-1).fact("p.wheel.speed")?.tier, .solved)
        XCTAssertEqual(try pair(1).fact("p.ratio")?.tier, .solved)
        // The shipped turbofan's HP spool runs at an authored 3 x N1.
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        guard case .success(let fan) = MGSolidParser.document(data: try Data(contentsOf: root.appendingPathComponent("Examples/Turbofan/Sources/TurbofanKit/Models/turbofan.json"))) else { return XCTFail() }
        XCTAssertEqual(fan.legend.text, "Solved 1 (animation ratio) · Schematic 1 · Not checked 1")
    }

    /// S3: a check does not make prose Solved; it is its own claim with its expression.
    func testS3CheckOnUnrelatedFactLeavesProseUntiered() throws {
        let d = try doc(stage(#"{"say": "The carrier turns faster than the sun.", "check": [{"value": "stage.sun.teeth", "gt": 0}]}"#))
        XCTAssertNil(d.steps[0].tier)
        XCTAssertEqual(d.claims.map(\.why).last, "Checked: stage.sun.teeth > 0")
    }

    /// S4: a non-zero value never shows as "0", and `eq 0` without `tol` needs exactly 0.
    func testS4RoundingToZero() {
        let dial = { (step: String) in #"{"v": 2, "kind": "assembly", "parts": [{"id": "dial", "shape": {"shaft": {"radius": 10, "length": 4}}, "joint": {"revolute": [0, 0, 1]}, "drive": {"input": 0.004}}], "steps": [\#(step)]}"# }
        XCTAssertEqual(reason(dial(#"{"say": "The dial turns {dial.speed} turns per input turn."}"#)), "text.rounding.dial.speed")
        XCTAssertEqual(reason(dial(#"{"say": "Slow: {dial.speed|pct} of a turn."}"#)), nil)   // 0.4% is honest
        XCTAssertNil(reason(dial(#"{"say": "The dial turns {dial.speed|frac} of a turn."}"#)))
        XCTAssertEqual(reason(dial(#"{"say": "It hardly turns.", "check": [{"value": "dial.speed", "eq": 0}]}"#)), "check.failed.dial.speed")
        XCTAssertNil(reason(dial(#"{"say": "It turns slowly.", "check": [{"value": "dial.speed", "eq": 0, "tol": 0.01}]}"#)))
    }

    /// S5: world speed beside the parent-relative speed; `abs` needs a check that proves the sign.
    func testS5WorldSpeedAndSign() throws {
        XCTAssertEqual(reason(stage(#"{"say": "Each planet spins {stage.planet.speed|abs|frac} of a turn per sun turn."}"#)), "text.sign.stage.planet.speed")
        XCTAssertEqual(reason(stage(#"{"say": "The planets spin the same way as the sun at {stage.planet.speed|abs|frac} of a turn."}"#)), "text.sign.stage.planet.speed")
        XCTAssertEqual(reason(stage(#"{"say": "{stage.planet.speed|abs|frac}", "check": [{"value": "stage.planet.speed", "lt": 1}]}"#)), "text.sign.stage.planet.speed")
        XCTAssertNil(reason(stage(#"{"say": "{stage.planet.speed|abs|frac}, the other way", "check": [{"value": "stage.planet.speed", "lt": 0}]}"#)))
        XCTAssertEqual(reason(stage(#"{"say": "Hi."}"#, title: #""title": "Planet {stage.planet.speed|abs}", "#)), "text.sign.stage.planet.speed")
        let d = try doc(stage(#"{"say": "Seen from the ground a planet turns {stage.planet.worldSpeed|frac} of a turn."}"#))
        XCTAssertEqual(d.steps[0].say, "Seen from the ground a planet turns -2/3 of a turn.")   // 2/7 - 20/21
        guard case .object(let o)? = d.describe("stage.planet") else { return XCTFail() }
        XCTAssertEqual(o["motion"], .string("Solved by gearMesh (-0.95 turns per input turn relative to stage.carrier; -0.67 in the world frame)"))
    }

    /// S6: a digit inside a grapheme cluster that starts with a prepended letter still counts.
    func testS6PrependedDigitsAreNumbers() {
        XCTAssertEqual(reason(stage(#"{"say": "The sun has ൎ5 teeth."}"#)), "text.number.step.1")
        XCTAssertEqual(reason(stage(#"{"say": "The sun has 𑇂7 teeth."}"#)), "text.number.step.1")
    }

    /// S7: one meaning per reason: an unknown key in a check and an unknown fact differ.
    func testS7CheckReasonsHaveOneMeaning() {
        XCTAssertEqual(reason(stage(#"{"say": "Hi.", "check": [{"value": "stage.output.speed", "eq": 0.2857, "tolerance": 0.001}]}"#)), "step.check.unknown.tolerance")
        XCTAssertEqual(reason(stage(#"{"say": "Hi.", "check": [{"value": "stage.speed", "eq": 1}]}"#)), "check.fact.stage.speed")
    }

    /// S8: the document records which fact filled each placeholder (N1 does not catch the wrong fact).
    func testS8StepRecordsItsFacts() throws {
        let d = try doc(stage(#"{"say": "The carrier turns {count.stage.planet} times slower than the sun."}"#))
        XCTAssertEqual(d.steps[0].facts, ["count.stage.planet"])
        // Number words are prose: N1 covers number characters only.
        XCTAssertNil(try doc(stage(#"{"say": "The carrier turns two sevenths of a turn."}"#)).steps[0].tier)
    }

    /// NITs: `deg`/`pct` only on speeds and ratios (N1); a top-level `tier` (N2); strict patches (N3); a dotted
    /// modifier (N7).
    func testReviewNits() throws {
        XCTAssertEqual(reason(stage(#"{"say": "{stage.sun.teeth|deg}"}"#)), "text.modifier.deg.stage.sun.teeth")
        XCTAssertEqual(reason(stage(#"{"say": "{stage.sun.teeth|pct}"}"#)), "text.modifier.pct.stage.sun.teeth")
        XCTAssertEqual(reason(#"{"v": 2, "kind": "assembly", "tier": "solved", "parts": [{"id": "a", "shape": {"box": {"size": [4, 4, 4]}}}]}"#), "tier.key")
        XCTAssertEqual(reason(stage(#"{"say": "{stage.sun.teeth|inv.y}"}"#)), "text.placeholder")
        // A patch that removes the only drive leaves an idle joint: the strict profile refuses the patched result.
        let d = try doc(#"{"v": 2, "kind": "assembly", "parts": [{"id": "disc", "shape": {"shaft": {"radius": 20, "length": 5}}, "joint": {"revolute": [0, 0, 1]}, "drive": {"input": 1}}]}"#)
        let patch: MGJSON = .object(["parts": .object(["disc": .object(["drive": .null])])])
        XCTAssertEqual(try MGSolidParser.applying(patch, to: d).get().warnings.map(\.reason), ["joint.idle.disc"])
        XCTAssertEqual(MGSolidParser.applying(patch, to: d, profile: .strict).map(\.title), .failure(MGSolidIssue("joint.idle.disc", part: "disc")))
    }
}

/// Regressions from the second independent review of PR #21 (R1–R7, one test per finding).
final class SolidHonestyReview2Tests: XCTestCase {
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
    /// Three engine-solved 15:150 stages: the output turns -1/1000 per input turn (Solved).
    func train(_ steps: String = "") -> String {
        let w = #""with": {"pinionTeeth": 15, "wheelTeeth": 150, "module": 0.5, "width": 2}"#
        func stage(_ n: Int, _ x: Double, _ z: Int) -> String {
            #"{"id": "s\#(n)", "use": "spurPair", "at": [\#(x), 0, \#(z)], \#(w), "set": {"pinion": {"parent": "s\#(n - 1).output", "at": [0, 0, 8], "joint": null, "drive": null}}}"#
        }
        return #"{"v": 2, "kind": "assembly", "parts": [{"id": "s1", "use": "spurPair", \#(w)}, \#(stage(2, 41.25, 8)), \#(stage(3, 82.5, 16))]\#(steps)}"#
    }

    /// R1: child-frame heuristics never refuse; correct spaced, supported, repeated, component and near-origin
    /// layouts pass strict. Strict still refuses idle joints and an axis that misses its own jointed part.
    func testR1ChildFrameLintsAreWarningsOnly() throws {
        let plate = #""shape": {"box": {"size": [10, 10, 2]}}"#
        let fixtures = [
            #"{"v": 2, "kind": "assembly", "parts": [{"id": "lower", "at": [0, 0, 10], \#(plate)}, {"id": "upper", "parent": "lower", "at": [0, 0, 10], \#(plate)}]}"#,
            #"{"v":2,"kind":"assembly","parts":[{"id":"lower","at":[0,0,10],"shape":{"box":{"size":[10,10,2]}}},{"id":"postNW","parent":"lower","at":[-3,3,1],"shape":{"shaft":{"radius":0.5,"length":8}}},{"id":"postNE","parent":"lower","at":[3,3,1],"shape":{"shaft":{"radius":0.5,"length":8}}},{"id":"postSW","parent":"lower","at":[-3,-3,1],"shape":{"shaft":{"radius":0.5,"length":8}}},{"id":"postSE","parent":"lower","at":[3,-3,1],"shape":{"shaft":{"radius":0.5,"length":8}}},{"id":"upper","parent":"lower","at":[0,0,10],"shape":{"box":{"size":[10,10,2]}}}]}"#,
            #"{"v": 2, "kind": "assembly", "parts": [{"id": "lower", "at": [0, 0, 10], \#(plate)}, {"id": "bearing", "use": "shaftWithBearing", "parent": "lower", "at": [0, 0, 10]}]}"#,
            #"{"v": 2, "kind": "assembly", "parts": [{"id": "carrier", "at": [1, 0, 0], "shape": {"box": {"size": [2, 2, 2]}}, "joint": {"revolute": [0, 0, 1]}, "drive": {"input": 1}}, {"id": "satellite", "parent": "carrier", "at": [3, 0, 0], "shape": {"box": {"size": [1, 1, 1]}}}]}"#,
        ]
        for f in fixtures { XCTAssertNil(reason(f, profile: .strict), f) }
        // The spaced plates still get the warning, so the report shows the suspicion beside the read-back.
        XCTAssertEqual(try doc(fixtures[0]).warnings.map(\.reason), ["frame.child.absolute.upper"])
        // Open vocabulary 3a adds `annotation.unused.` (certain from the document: no step shows it) and the anchor
        // checks add `annotation.anchor.off.` (an anchor off its part, in the part's own frame); still no frame heuristic.
        XCTAssertEqual(MGSolidProfile.strictPrefixes, ["joint.idle.", "frame.axis.off.", "annotation.unused.", "annotation.anchor.off."])
        XCTAssertEqual(reason(#"{"v": 2, "kind": "assembly", "parts": [{"id": "disc", "shape": {"shaft": {"radius": 20, "length": 5}}, "joint": {"revolute": [0, 0, 1]}}]}"#, profile: .strict), "joint.idle.disc")
        XCTAssertEqual(reason(#"{"v": 2, "kind": "assembly", "parts": [{"id": "sat", "shape": {"shaft": {"radius": 5, "length": 4, "at": [80, 0, 0]}}, "joint": {"revolute": [0, 0, 1]}, "drive": {"input": 1}}]}"#, profile: .strict), "frame.axis.off.sat")
    }

    /// R2: an equality never proves a sign; `abs` needs a strict inequality on the same fact.
    func testR2EqualityDoesNotProveSign() {
        XCTAssertEqual(reason(train(#", "steps": [{"say": "Forward {s3.output.speed|abs|frac}.", "check": [{"value": "s3.output.speed", "eq": 0.001}]}]"#)), "text.sign.s3.wheel.speed")
        XCTAssertEqual(reason(train(#", "steps": [{"say": "Back {s3.output.speed|abs|frac}.", "check": [{"value": "s3.output.speed", "eq": -0.001, "tol": 0.0001}]}]"#)), "text.sign.s3.wheel.speed")
        XCTAssertNil(reason(train(#", "steps": [{"say": "Back {s3.output.speed|abs|frac}.", "check": [{"value": "s3.output.speed", "lt": 0}]}]"#)))
        XCTAssertEqual(reason(train(#", "steps": [{"say": "Forward {s3.output.speed|abs|frac}.", "check": [{"value": "s3.output.speed", "gt": 0}]}]"#)), "check.failed.s3.output.speed")
        XCTAssertEqual(reason(train(#", "steps": [{"say": "{s3.output.speed|abs|frac}", "check": [{"value": "s3.output.speed", "lt": 0.5}]}]"#)), "text.sign.s3.wheel.speed")
    }

    /// R3: no non-zero fact shows "0": not in the facts table, the read-back or `describe`.
    func testR3NonZeroFactsNeverShowZero() throws {
        let d = try doc(train())
        XCTAssertEqual(d.fact("s3.output.speed")?.text, "-0.001")
        XCTAssertEqual(d.fact("s3.output.speed")?.tier, .solved)
        XCTAssertTrue(d.readBack.contains { $0.hasPrefix("s3.wheel:") && $0.contains("-0.001 turns per input turn") }, d.readBack.joined(separator: "\n"))
        guard case .object(let o)? = d.describe("s3.output") else { return XCTFail() }
        XCTAssertEqual(o["motion"], .string("Solved by gearMesh (-0.001 turns per input turn)"))
        XCTAssertEqual(MGSolidFacts.display(0.0033, unit: ""), "0.0033")
        XCTAssertEqual(MGSolidFacts.display(-4e-12, unit: "mm"), "-4.00e-12 mm")
        XCTAssertEqual(MGSolidFacts.display(0.29, unit: ""), "0.29")
        XCTAssertEqual(MGSolidFacts.display(0, unit: ""), "0")
    }

    /// R4: check text and report data keep the exact target, comparator and tolerance.
    func testR4CheckTextIsExact() throws {
        let d = try doc(#"{"v": 2, "kind": "assembly", "parts": [{"id": "dial", "shape": {"box": {"size": [10, 10, 2]}}, "joint": {"revolute": [0, 0, 1]}, "drive": {"input": 1}}], "steps": [{"say": "{dial.speed}", "check": [{"value": "dial.speed", "gt": 0.004}, {"value": "dial.speed", "eq": 1, "tol": 1e-09}, {"value": "dial.speed", "eq": 1.004}]}]}"#)
        XCTAssertEqual(d.steps[0].checks.map(\.text), ["dial.speed > 0.004", "dial.speed = 1 ± 1e-09", "dial.speed shows as 1 (target 1.004)"])
        XCTAssertEqual(d.claims.filter { $0.kind == .check }.map(\.why), ["Checked: dial.speed > 0.004", "Checked: dial.speed = 1 ± 1e-09", "Checked: dial.speed shows as 1 (target 1.004)"])
        XCTAssertEqual(MGSolidFacts.exact(2.0 / 7), "0.2857142857142857")
    }

    /// R5: a failed claim and a missing fact have disjoint reasons, even for a part named `fact`.
    func testR5CheckReasonsAreDisjoint() {
        let part = #"{"id": "fact", "shape": {"box": {"size": [2, 2, 2]}}, "joint": {"revolute": [0, 0, 1]}, "drive": {"input": 1}}"#
        XCTAssertEqual(reason(#"{"v": 2, "kind": "assembly", "parts": [\#(part)], "steps": [{"say": "Hi.", "check": [{"value": "fact.speed", "eq": 0}]}]}"#), "check.failed.fact.speed")
        XCTAssertEqual(reason(#"{"v": 2, "kind": "assembly", "parts": [\#(part)], "steps": [{"say": "Hi.", "check": [{"value": "speed", "eq": 0}]}]}"#), "check.fact.speed")
    }

    /// R6: copies with opposite tiny rates do not share one repeat fact; equal rates still do.
    func testR6OppositeTinyRatesDoNotMerge() throws {
        func rotors(_ rate: String, _ steps: String = "") -> String {
            #"{"v":2,"kind":"assembly","parts":[{"id":"parent","shape":{"box":{"size":[4,4,4]}},"joint":{"revolute":[0,0,1]},"drive":{"input":\#(rate)}},{"id":"rotor","parent":"parent","shape":{"shaft":{"radius":1,"length":2}},"joint":{"revolute":[0,0,1]},"drive":{"input":0},"repeat":{"count":2,"axis":[1,0,0]}}]\#(steps)}"#
        }
        for rate in ["1e-10", "1"] {
            let d = try doc(rotors(rate))
            XCTAssertEqual(d.fact("rotor1.worldSpeed")!.value, -d.fact("rotor2.worldSpeed")!.value, rate)
            XCTAssertNil(d.facts["rotor.worldSpeed"], rate)
            XCTAssertNotNil(d.facts["rotor.speed"], rate)   // both copies hold still relative to the parent
        }
        XCTAssertEqual(reason(rotors("1e-10", #", "steps": [{"say": "Inverse rate {rotor.worldSpeed|inv}."}]"#)), "text.placeholder.rotor.worldSpeed")
    }

    /// R7: Unicode 18 numeric scalars count for N1 and for typed numbers in titles, whatever the runtime's data.
    func testR7Unicode18NumericScalars() throws {
        for scalar in ["\u{1246F}", "\u{32403}"] {
            let caption = #"{"v": 2, "kind": "assembly", "parts": [{"id": "g", "shape": {"gear": {"teeth": 24, "module": 1, "width": 4}}}], "steps": [{"say": "Count \#(scalar) and {g.teeth}."}]}"#
            XCTAssertEqual(reason(caption), "text.number.step.1", scalar)
            let title = try doc(#"{"v": 2, "kind": "assembly", "title": "Count \#(scalar) and {g.teeth}", "parts": [{"id": "g", "shape": {"gear": {"teeth": 24, "module": 1, "width": 4}}}]}"#)
            XCTAssertEqual(title.titleTier, .described, scalar)
        }
        // The pinned table: 2,348 scalars in 239 sorted, disjoint, non-adjacent ranges; every listed scalar is a number.
        let r = MGSolidNumericScalars.ranges
        XCTAssertEqual(MGSolidNumericScalars.version, "18.0.0")
        XCTAssertEqual(r.count, 239)
        XCTAssertEqual(r.reduce(0) { $0 + Int($1.upperBound - $1.lowerBound) + 1 }, 2348)
        for i in 1..<r.count { XCTAssertGreaterThan(r[i].lowerBound, r[i - 1].upperBound + 1) }
        for range in r { for v in range { if let s = Unicode.Scalar(v) { XCTAssertTrue(MGSolidFacts.isNumber(Character(s)), String(v, radix: 16)) } } }
        XCTAssertFalse(MGSolidFacts.isNumber("a"))
        XCTAssertFalse(MGSolidFacts.isNumber(" "))
    }
}

/// Regression from the third independent review of PR #21 (R8): modifier arithmetic that overflows or underflows is
/// refused at the step where it happens, so `inv|inv` can never turn infinity back into a false "0".
final class SolidHonestyReview3Tests: XCTestCase {
    func reason(_ text: String) -> String? {
        if case .failure(let e) = MGSolidParser.document(data: Data(text.utf8), profile: .strict) { return e.reason }
        return nil
    }
    func dial(_ rate: String, say: String? = nil, title: String? = nil, check: String = #"{"value": "dial.speed", "gt": 0}"#) -> String {
        let t = title.map { #""title": "\#($0)", "# } ?? ""
        let s = say.map { #", "steps": [{"say": "\#($0)", "check": [\#(check)]}]"# } ?? ""
        return #"{"v": 2, "kind": "assembly", \#(t)"parts": [{"id": "dial", "shape": {"box": {"size": [2, 2, 2]}}, "joint": {"revolute": [0, 0, 1]}, "drive": {"input": \#(rate)}}]\#(s)}"#
    }

    func testR8ModifierOverflowIsRefused() throws {
        XCTAssertEqual(reason(dial("1e-309", say: "Rate {dial.speed|inv|inv}.")), "text.range.dial.speed")
        XCTAssertEqual(reason(dial("-1e-309", say: "Rate {dial.speed|inv|inv}.", check: #"{"value": "dial.speed", "lt": 0}"#)), "text.range.dial.speed")
        XCTAssertEqual(reason(dial("-1e-309", say: "Rate {dial.speed|abs|inv|inv}.", check: #"{"value": "dial.speed", "lt": 0}"#)), "text.range.dial.speed")
        XCTAssertEqual(reason(dial("1e-309", title: "Rate {dial.speed|inv|inv}")), "text.range.dial.speed")
        XCTAssertEqual(reason(dial("1e-309", say: "Rate {dial.speed|inv}.")), "text.range.dial.speed")          // not "—"
        XCTAssertEqual(reason(dial("1e-307", say: "Rate {dial.speed|inv|pct}.")), "text.range.dial.speed")      // finite, then x 100
        XCTAssertEqual(reason(dial("1e-307", say: "Rate {dial.speed|inv|deg}.")), "text.range.dial.speed")
        XCTAssertEqual(reason(dial("1e-309", say: "Rate {dial.speed|frac}.")), "text.rounding.dial.speed")      // "0" from a non-zero fact
        XCTAssertEqual(reason(dial("1e-300", say: "Rate {dial.speed|inv|inv}.")), "text.rounding.dial.speed")   // in range, shows "0"
        // inv|inv on 1e308 (no document can author it; drive scales are at most 1000): 1e-308 is subnormal.
        let huge = ["x": MGSolidFact(value: 1e308, unit: "", tier: .solved, source: "input")]
        XCTAssertThrowsError(try MGSolidFacts.placeholder("x|inv|inv", huge, [:])) { XCTAssertEqual(($0 as? MGSolidIssue)?.reason, "text.range.x") }
        XCTAssertThrowsError(try MGSolidFacts.placeholder("x|pct", huge, [:])) { XCTAssertEqual(($0 as? MGSolidIssue)?.reason, "text.modifier.pct.x") }   // not a speed
        let speed = ["x.speed": MGSolidFact(value: 1e308, unit: "", tier: .solved, source: "input")]
        XCTAssertThrowsError(try MGSolidFacts.placeholder("x.speed|pct", speed, [:])) { XCTAssertEqual(($0 as? MGSolidIssue)?.reason, "text.range.x.speed") }
        XCTAssertThrowsError(try MGSolidFacts.placeholder("x.speed|deg", speed, [:])) { XCTAssertEqual(($0 as? MGSolidIssue)?.reason, "text.range.x.speed") }
        // Finite controls.
        let d = try MGSolidParser.document(data: Data(dial("0.25", say: "Rate {dial.speed|inv|inv}, {dial.speed|inv}, {dial.speed|pct}.").utf8)).get()
        XCTAssertEqual(d.steps[0].say, "Rate 0.25, 4, 25%.")
    }
}
