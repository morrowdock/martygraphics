// SPDX-License-Identifier: Apache-2.0
import Foundation
import SceneKit
import XCTest
@testable import MartyGraphics

/// Per-step `pose`, per-step `hide`/`show`, component instance ids in step part lists, `explode` on an instance, motion
/// arrows sized to the step focus, two-line annotation text, hero framing and the story pose blend
/// (docs/SOLID-3D.md, "Step pose" and "Step visibility").
final class StepPoseVisibilityTests: ExplainerTestCase {
    /// A mannequin with one engine on each hand and a plume on the left engine's exhaust. `steps` is the steps array.
    static func suit(_ steps: String, plume: Bool = true, annotations: String? = nil, extraParts: String = "") -> String {
        let p = plume ? #", {"id": "plume", "parent": "engL.exhaust", "shape": {"shaft": {"radius": 20, "length": 150}}, "material": "aluminum", "opacity": 0.3}"# : ""
        let a = annotations.map { #", "annotations": \#($0)"# } ?? ""
        return #"{"v": 2, "kind": "assembly", "title": "Suit", "parts": [{"id": "pilot", "use": "mannequin"}, {"id": "engL", "use": "microTurbojet", "with": {"diameter": 70, "length": 200}, "parent": "pilot.leftHand", "at": [63, 0, -60], "rot": [1, 0, 0, 180]}, {"id": "engR", "use": "microTurbojet", "with": {"diameter": 70, "length": 200}, "parent": "pilot.rightHand", "at": [-63, 0, -60], "rot": [1, 0, 0, 180]}\#(p)\#(extraParts)], "steps": \#(steps)\#(a)}"#
    }
    static func doc(_ s: String) throws -> MGSolidDocument { try MGSolidParser.document(data: Data(s.utf8)).get() }
    static func reason(_ s: String) -> String? { MGSolidParser.document(data: Data(s.utf8)).failureReason }
    static func issue(_ s: String) -> MGSolidIssue? { if case .failure(let e) = MGSolidParser.document(data: Data(s.utf8)) { return e }; return nil }

    // MARK: Pose

    func testInstancePoseAppliesToItsStepOnly() throws {
        let d = try Self.doc(Self.suit(#"[{"say": "Hover."}, {"say": "Steer.", "pose": {"pilot": {"with": {"leftShoulder": 40}}}}, {"say": "Again."}]"#))
        XCTAssertTrue(d.steps[0].pose.isEmpty); XCTAssertTrue(d.steps[2].pose.isEmpty)
        XCTAssertEqual(d.steps[1].pose.keys.sorted(), ["pilot.upperArmL"])
        // The posed placement is the authored one with the shoulder at 40 degrees, exactly.
        let ref = try Self.doc(Self.suit(#"[{"say": "x"}]"#).replacingOccurrences(of: #""use": "mannequin"}"#, with: #""use": "mannequin", "with": {"leftShoulder": 40}}"#))
        XCTAssertEqual(d.steps[1].pose["pilot.upperArmL"], ref.assembly.part("pilot.upperArmL")?.placement)
        // The step still, its pose parameters and the view all carry the pose; the plain view and other steps do not.
        let shot = try XCTUnwrap(MGSolidShot.step(d, 1))
        XCTAssertEqual(shot.params.placements, d.steps[1].pose)
        XCTAssertEqual(MGSolidShot.step(d, 0)?.params.placements, [:])
        let posed = d.pose(shot.params).world, rest = d.pose(d.defaults).world
        XCTAssertNotEqual(posed["engL.casing"], rest["engL.casing"])
        XCTAssertEqual(posed["engR.casing"], rest["engR.casing"])
        XCTAssertEqual(posed["engL.casing"], ref.pose(ref.defaults).world["engL.casing"])
        // Facts are the same facts (the pose moves no mechanism).
        XCTAssertEqual(d.facts["engL.shaft.speed"]?.value, 1)
        // Read-back: every moved part, the posed root named with its posed placement, the others moving with their parent.
        let rb = try XCTUnwrap(d.poseReadBack.first)
        XCTAssertEqual(rb.step, 2)
        XCTAssertTrue(rb.lines.contains { $0.hasPrefix("pilot.upperArmL:") && $0.contains("posed placement") })
        XCTAssertTrue(rb.lines.contains { $0.hasPrefix("engL.casing:") })
        XCTAssertFalse(rb.lines.contains { $0.hasPrefix("engR.") || $0.hasPrefix("pilot.upperArmR") })
        let report = MGSolidReport.make(d).json
        guard case .array(let views)? = report["stepViews"] else { return XCTFail("stepViews") }
        XCTAssertEqual(views.count, 3)
        XCTAssertEqual(views[1]["posed"], .array([.string("pilot.upperArmL")]))
        XCTAssertEqual(views[0]["posed"], .array([]))
        // Reports without poses keep their exact keys.
        XCTAssertNil(MGSolidReport.make(try Self.doc(Self.suit(#"[{"say": "x"}]"#))).json["stepViews"])
    }

    func testPartAnchorAndInnerPartPosesAgree() throws {
        let viaWith = try Self.doc(Self.suit(#"[{"say": "a", "pose": {"pilot": {"with": {"leftShoulder": 40}}}}]"#))
        let viaAnchor = try Self.doc(Self.suit(#"[{"say": "a", "pose": {"pilot.leftShoulder": {"rot": [0, -1, 0, 40]}}}]"#))
        let viaPart = try Self.doc(Self.suit(#"[{"say": "a", "pose": {"pilot.upperArmL": {"rot": [0, -1, 0, 40]}}}]"#))
        XCTAssertEqual(viaAnchor.steps[0].pose, viaWith.steps[0].pose)
        XCTAssertEqual(viaPart.steps[0].pose, viaWith.steps[0].pose)
        // An authored part takes `rot` (it replaces the part's own `rot`).
        let arm = #"{"v": 2, "kind": "assembly", "parts": [{"id": "base", "shape": {"box": {"size": [40, 40, 10]}}}, {"id": "arm", "parent": "base", "at": [0, 0, 5], "shape": {"box": {"size": [10, 10, 60]}}}], "steps": [{"say": "Up."}, {"say": "Tilt.", "pose": {"arm": {"rot": [1, 0, 0, 30]}}}]}"#
        let d = try Self.doc(arm)
        XCTAssertEqual(d.steps[1].pose["arm"], MGTransform.translation(MGVec3(0, 0, 5)) * .rotation(axis: .unitX, angle: .pi / 6))
        XCTAssertNil(d.steps[1].pose["base"])
    }

    func testPoseRefusals() {
        func r(_ pose: String) -> String? { Self.reason(Self.suit(#"[{"say": "a", "pose": \#(pose)}]"#)) }
        XCTAssertEqual(r("[]"), "step.pose")
        XCTAssertEqual(r("{}"), "step.pose")
        let many = (1...17).map { #""p\#($0)": {"rot": [0, 0, 1, 1]}"# }.joined(separator: ",")
        XCTAssertEqual(r("{\(many)}"), "step.pose")
        XCTAssertEqual(r(#"{"pilot": 3}"#), "step.pose.key")
        XCTAssertEqual(r(#"{"pilot": {}}"#), "step.pose.key")
        XCTAssertEqual(r(#"{"pilot": {"at": [0, 0, 1]}}"#), "step.pose.key")
        XCTAssertEqual(r(#"{"pilot": {"rot": [0, 0, 1, 10]}}"#), "step.pose.key")            // an instance takes `with`
        XCTAssertEqual(r(#"{"plume": {"with": {"x": 1}}}"#), "step.pose.key")               // a part takes `rot`
        XCTAssertEqual(r(#"{"plume": {"rot": [0, 0, 0, 10]}}"#), "step.pose.key")
        XCTAssertEqual(r(#"{"plume": {"rot": [0, 0, 1, 400]}}"#), "step.pose.key")
        XCTAssertEqual(r(#"{"plume": {"rot": [0, 0, 1]}}"#), "step.pose.key")
        XCTAssertEqual(r(#"{"nothing": {"rot": [0, 0, 1, 10]}}"#), "step.pose.ref")
        XCTAssertEqual(r(#"{"pilot.nothing": {"rot": [0, 0, 1, 10]}}"#), "step.pose.ref")
        XCTAssertEqual(r(#"{"pilot.leftShoulder": {"rot": [0, 1, 0, 9]}, "pilot.upperArmL": {"rot": [0, 1, 0, 9]}}"#), "step.pose.ref")
        XCTAssertEqual(r(#"{"pilot": {"with": 3}}"#), "step.pose.with")
        XCTAssertEqual(r(#"{"pilot": {"with": {"leftShoulder": 400}}}"#), "step.pose.with")
        XCTAssertEqual(r(#"{"pilot": {"with": {"noSuchJoint": 4}}}"#), "step.pose.with")
        // A parameter that changes a shape is not a pose.
        XCTAssertEqual(r(#"{"engL": {"with": {"diameter": 90}}}"#), "step.pose.with")
        // v1 has no pose.
        XCTAssertEqual(Self.reason(#"{"v": 1, "kind": "assembly", "parts": [{"id": "a", "shape": {"box": {"size": [1, 1, 1]}}}], "steps": [{"say": "a", "pose": {"a": {"rot": [0, 0, 1, 5]}}}]}"#), "step.unknown.pose")
        // The id is named in the refusal.
        XCTAssertEqual(Self.issue(Self.suit(#"[{"say": "a", "pose": {"zz": {"rot": [0, 0, 1, 5]}}}]"#))?.part, "zz")
    }

    func testPoseOfASolvedMechanismIsRefused() throws {
        // Gear pair members and their carrier frame.
        let gears = #"{"v": 2, "kind": "assembly", "parts": [{"id": "frame", "shape": {"box": {"size": [120, 60, 4]}}, "at": [20, 0, -6]}, {"id": "p", "parent": "frame", "at": [-20, 0, 6], "shape": {"gear": {"teeth": 15, "module": 2, "width": 8}}, "joint": {"revolute": [0, 0, 1]}, "drive": {"input": 1}}, {"id": "w", "parent": "frame", "at": [25, 0, 6], "shape": {"gear": {"teeth": 30, "module": 2, "width": 8}}, "joint": {"revolute": [0, 0, 1]}}], "constraints": [{"gearMesh": {"a": "p", "b": "w"}}], "steps": [{"say": "a", "pose": POSE}]}"#
        for pose in [#"{"w": {"rot": [0, 0, 1, 10]}}"#, #"{"p": {"rot": [1, 0, 0, 10]}}"#, #"{"frame": {"rot": [0, 0, 1, 10]}}"#] {
            let i = Self.issue(gears.replacingOccurrences(of: "POSE", with: pose))
            XCTAssertEqual(i?.reason, "step.pose.solved", pose)
        }
        // A crank mechanism.
        guard case .object(var crank) = try XFix.model("slider-crank") else { return XCTFail("model") }
        crank["v"] = .number(2)
        crank["steps"] = XFix.json(#"[{"say": "a", "pose": {"crank": {"rot": [0, 0, 1, 20]}}}]"#)
        XCTAssertEqual(MGSolidParser.document(json: .object(crank)).failureReason, "step.pose.solved")
        // A pose that changes an engine fact: a child turning on a turning parent loses its parallel axis, so its
        // world speed would change.
        let nested = #"{"v": 2, "kind": "assembly", "parts": [{"id": "disc", "shape": {"shaft": {"radius": 30, "length": 4}}, "joint": {"revolute": [0, 0, 1]}, "drive": {"input": 1}}, {"id": "top", "parent": "disc", "at": [15, 0, 4], "shape": {"shaft": {"radius": 5, "length": 4}}, "joint": {"revolute": [0, 0, 1]}, "drive": {"input": 1}}], "steps": [{"say": "a", "pose": {"top": {"rot": [1, 0, 0, 30]}}}]}"#
        XCTAssertNotNil(try Self.doc(nested.replacingOccurrences(of: #", "pose": {"top": {"rot": [1, 0, 0, 30]}}"#, with: "")).facts["top.worldSpeed"])
        XCTAssertEqual(Self.reason(nested), "step.pose.solved")
    }

    func testPosedStepIsRecheckedAtItsPose() throws {
        // A gravity arrow riding the arm: down at rest, sideways at a 90 degree pose.
        func arm(_ deg: Int) -> String {
            #"{"v": 2, "kind": "assembly", "parts": [{"id": "base", "shape": {"box": {"size": [40, 40, 10]}}}, {"id": "arm", "parent": "base", "at": [0, 0, 5], "shape": {"box": {"size": [10, 10, 60]}}}], "annotations": {"arrows": [{"id": "g", "meaning": "force", "cause": "gravity", "from": {"part": "arm", "offset": [0, 0, 30]}, "to": {"part": "arm", "offset": [0, 0, -30]}}]}, "steps": [{"say": "Rest."}, {"say": "Tilt.", "pose": {"arm": {"rot": [1, 0, 0, \#(deg)]}}}]}"#
        }
        XCTAssertNoThrow(try Self.doc(arm(5)))
        XCTAssertEqual(Self.reason(arm(90)), "annotation.pose.g")
        // Frame lints run at each pose too: a child mesh pushed far from its parent only at the pose warns.
        let far = #"{"v": 2, "kind": "assembly", "parts": [{"id": "base", "shape": {"box": {"size": [20, 20, 10]}}}, {"id": "tip", "parent": "base", "shape": {"revolvedProfile": {"points": [[0, -2], [2, -2], [2, 2], [0, 2]], "at": [0, 38, 0]}}}], "steps": [{"say": "a"}, {"say": "b", "pose": {"tip": {"rot": [1, 0, 0, 90]}}}]}"#
        let d = try Self.doc(far)
        XCTAssertFalse(try Self.doc(far.replacingOccurrences(of: #", "pose": {"tip": {"rot": [1, 0, 0, 90]}}"#, with: "")).warnings.contains { $0.reason == "frame.child.far.tip" })
        XCTAssertTrue(d.warnings.contains { $0.reason == "frame.child.far.tip" })
    }

    func testAnnotationsDrawOnlyAtTheStepPose() throws {
        let d = try Self.doc(Self.suit(#"[{"say": "a", "annotate": ["l"]}, {"say": "b", "annotate": ["l"], "pose": {"pilot": {"with": {"leftShoulder": 50}}}}]"#,
                                       annotations: #"{"labels": [{"id": "l", "at": "engL.casing", "text": "Engine"}]}"#))
        let v1 = d.view(step: 1)
        XCTAssertEqual(d.checkedAnnotations(v1, params: d.poseParameters(step: 1)), ["l"])
        // Step 2's view at the authored placements, or at a pose between the two steps, is not one the engine checked.
        XCTAssertNil(d.checkedAnnotations(v1, params: d.poseParameters(step: 0)))
        let between = MGPoseParameters(input: d.defaults.input, explode: 0,
                                       placements: MGStoryPlan.placements(d.assembly, from: [:], to: d.steps[1].pose, 0.5))
        XCTAssertNil(d.checkedAnnotations(v1, params: between))
        XCTAssertNil(d.checkedAnnotations(d.view(step: 0), params: d.poseParameters(step: 1)))
        // The snapshot of the posed step lists the moved parts and exports the label at its posed anchor.
        let snap = MGSolidSnapshot.make(d, step: 1, params: d.poseParameters(step: 1))
        XCTAssertEqual(snap.posed, ["pilot.upperArmL"])
        XCTAssertEqual(snap.annotations?.labels.map(\.id), ["l"])
        XCTAssertNil(MGSolidSnapshot.make(d, step: 0, params: d.poseParameters(step: 0)).posed)
        let data = try snap.jsonData()
        XCTAssertEqual(try MGSolidSnapshot.decode(data: data), snap)
    }

    func testPoseIsDeterministicAndPatchRefusalChangesNothing() throws {
        let text = Self.suit(#"[{"say": "a"}, {"say": "b", "pose": {"pilot": {"with": {"rightShoulder": 60, "leftShoulder": 30}}, "pilot.lowerArmL": {"rot": [-1, 0, 0, 50]}}}]"#)
        let a = try Self.doc(text), b = try Self.doc(text)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.checkedFingerprint, b.checkedFingerprint)
        XCTAssertEqual(a.steps[1].pose.keys.sorted(), ["pilot.lowerArmL", "pilot.upperArmL", "pilot.upperArmR"])
        // Several bad entries: the first in sorted key order is reported, every time.
        let bad = Self.suit(#"[{"say": "a", "pose": {"zz": {"rot": [0, 0, 1, 5]}, "aa": {"rot": [0, 0, 1, 5]}}}]"#)
        XCTAssertEqual(Self.issue(bad)?.part, "aa")
        // A refused patch leaves the document as it was (documents are values; the patch returns a refusal).
        let before = a
        let r = MGSolidParser.applying(XFix.json(#"{"steps": [{"say": "x", "pose": {"pilot": {"with": {"leftShoulder": 999}}}}]}"#), to: a)
        XCTAssertEqual(r.failureReason, "step.pose.with")
        XCTAssertEqual(a, before)
        // A pose by patch is accepted and recompiles.
        let ok = try MGSolidParser.applying(XFix.json(#"{"steps": [{"say": "x", "pose": {"pilot": {"with": {"leftShoulder": 90}}}}]}"#), to: a).get()
        XCTAssertEqual(ok.steps[0].pose.keys.sorted(), ["pilot.upperArmL"])
    }

    // MARK: Hide and show

    func testShowOnlyPartAppearsOnlyInItsSteps() throws {
        let d = try Self.doc(Self.suit(#"[{"say": "a"}, {"say": "b", "show": ["plume"]}, {"say": "c", "hide": ["engR"]}]"#))
        XCTAssertEqual(d.showOnly, ["plume"])
        XCTAssertTrue(d.view(step: nil).part("plume").hidden)
        XCTAssertTrue(d.view(step: 0).part("plume").hidden)
        XCTAssertFalse(d.view(step: 1).part("plume").hidden)
        XCTAssertTrue(d.view(step: 2).part("plume").hidden)
        // An instance id hides every part of the instance.
        XCTAssertEqual(d.steps[2].hide.count, 11)
        XCTAssertTrue(d.view(step: 2).part("engR.casing").hidden)
        XCTAssertEqual(d.view(step: 2).hiddenParts.count, 12)
        // Hidden parts are left out of framing: the hero and a whole-model step frame as if the parts were absent.
        let without = try Self.doc(Self.suit(#"[{"say": "a"}, {"say": "b"}, {"say": "c"}]"#, plume: false))
        let plan = MGSolidRenderPlan(d, sourceName: "x", source: MGSolidSource(data: Data()), loop: false)
        let plan0 = MGSolidRenderPlan(without, sourceName: "x", source: MGSolidSource(data: Data()), loop: false)
        let c = plan.cameras(d, width: 1280, height: 800), c0 = plan0.cameras(without, width: 1280, height: 800)
        XCTAssertEqual(c.stills[0], c0.stills[0])   // hero.png
        XCTAssertEqual(c.stills[2], c0.stills[2])   // step 1
        XCTAssertNotEqual(c.stills[3], c0.stills[3]) // step 2 shows the plume
        // The snapshot keeps every part range (part order) and gives hidden parts no triangles.
        let snap = MGSolidSnapshot.make(d, step: 2, params: d.poseParameters(step: 2))
        XCTAssertEqual(snap.parts.count, d.assembly.parts.count)
        XCTAssertEqual(snap.hidden?.count, 12)
        for p in snap.parts where snap.hidden!.contains(p.id) { XCTAssertEqual(p.triangleCount, 0, p.id) }
        XCTAssertEqual(try MGSolidSnapshot.decode(data: snap.jsonData()), snap)
        XCTAssertNil(MGSolidSnapshot.make(d, step: 1, params: d.poseParameters(step: 1)).hidden)
        // The report lists each step's hidden parts and the show-only parts.
        let report = MGSolidReport.make(d).json
        XCTAssertEqual(report["showOnly"], .array([.string("plume")]))
    }

    func testSnapshotHiddenFieldIsValidated() throws {
        let d = try Self.doc(Self.suit(#"[{"say": "a", "hide": ["plume"]}]"#))
        let snap = MGSolidSnapshot.make(d, step: 0, params: d.poseParameters(step: 0))
        var o = try XCTUnwrap(JSONSerialization.jsonObject(with: snap.jsonData()) as? [String: Any])
        XCTAssertEqual(o["hidden"] as? [String], ["plume"])
        func decodes(_ o: [String: Any]) -> Bool { (try? MGSolidSnapshot.decode(data: JSONSerialization.data(withJSONObject: o))) != nil }
        XCTAssertTrue(decodes(o))
        o["hidden"] = ["plume", "plume"]; XCTAssertFalse(decodes(o))
        o["hidden"] = ["nothing"]; XCTAssertFalse(decodes(o))
        o["hidden"] = ["engL.casing"]; XCTAssertFalse(decodes(o))   // a hidden part has no triangles
        o["hidden"] = ["plume"]; o["highlight"] = ["plume"]; XCTAssertFalse(decodes(o))
        o.removeValue(forKey: "highlight"); o["format"] = MGSolidSnapshot.formatV1
        XCTAssertFalse(decodes(o))
    }

    func testHideShowRefusals() {
        func r(_ steps: String, annotations: String? = nil) -> String? { Self.reason(Self.suit(steps, annotations: annotations)) }
        XCTAssertEqual(r(#"[{"say": "a", "hide": []}]"#), "step.hide")
        XCTAssertEqual(r(#"[{"say": "a", "show": "plume"}]"#), "step.show")
        let many = Array(repeating: #""plume""#, count: 17).joined(separator: ",")
        XCTAssertEqual(r(#"[{"say": "a", "hide": [\#(many)]}]"#), "step.hide")
        XCTAssertEqual(r(#"[{"say": "a", "hide": ["nothing"]}]"#), "ref.unknown.nothing")
        XCTAssertEqual(r(#"[{"say": "a", "hide": ["plume"], "show": ["plume"]}]"#), "step.hide.both")
        XCTAssertEqual(r(#"[{"say": "a", "hide": ["engL"], "highlight": ["engL.casing"]}]"#), "step.hide.use")
        // A show-only part is hidden in the other steps, so they may not focus it.
        XCTAssertEqual(r(#"[{"say": "a", "show": ["plume"]}, {"say": "b", "focus": ["plume"]}]"#), "step.hide.use")
        // Hidden parts make no claim: no shown annotation on them, no fact of theirs in the caption or a check.
        let label = #"{"labels": [{"id": "l", "at": "engR.casing", "text": "Engine"}]}"#
        XCTAssertEqual(r(#"[{"say": "a", "hide": ["engR"], "annotate": ["l"]}]"#, annotations: label), "step.hide.claim")
        XCTAssertNil(r(#"[{"say": "a", "hide": ["engL"], "annotate": ["l"]}]"#, annotations: label))
        XCTAssertEqual(r(#"[{"say": "Turns {engR.shaft.speed} per turn.", "hide": ["engR"]}]"#), "step.hide.fact")
        XCTAssertEqual(r(#"[{"say": "Turns.", "hide": ["engR"], "check": [{"value": "engR.shaft.speed", "eq": 1}]}]"#), "step.hide.fact")
        XCTAssertNil(r(#"[{"say": "Turns {engL.shaft.speed} per turn.", "hide": ["engR"]}]"#))
        // The plain view shows every annotation when no step uses `annotate`; one on a show-only part is refused.
        let onPlume = #"{"labels": [{"id": "l", "at": "plume", "text": "Plume"}]}"#
        XCTAssertEqual(r(#"[{"say": "a", "show": ["plume"]}]"#, annotations: onPlume), "step.show.claim")
        XCTAssertNil(r(#"[{"say": "a", "show": ["plume"], "annotate": ["l"]}]"#, annotations: onPlume))
        XCTAssertEqual(Self.reason(#"{"v": 1, "kind": "assembly", "parts": [{"id": "a", "shape": {"box": {"size": [1, 1, 1]}}}], "steps": [{"say": "a", "hide": ["a"]}]}"#), "step.unknown.hide")
    }

    // MARK: Instance ids in step lists, instance explode

    func testInstanceIdIsOneEntryInEveryStepList() throws {
        let five = #"{"v": 2, "kind": "assembly", "parts": [\#((1...5).map { #"{"id": "e\#($0)", "use": "microTurbojet", "at": [\#($0 * 200), 0, 0]}"# }.joined(separator: ","))], "steps": [{"say": "All.", "highlight": ["e1", "e2", "e3", "e4", "e5"], "ghost": ["e1"], "focus": ["e2", "e3"]}, {"say": "Hide.", "hide": ["e5"]}]}"#
        let d = try Self.doc(five)
        XCTAssertEqual(d.steps[0].highlight.count, 55)
        XCTAssertEqual(d.steps[0].ghost.count, 11)
        XCTAssertEqual(d.steps[0].focus.count, 22)
        XCTAssertEqual(d.steps[1].hide.count, 11)
        // The 16-entry limit counts authored entries (an instance id is one); 17 is refused.
        let ids = (1...17).map { _ in #""e1""# }.joined(separator: ",")
        XCTAssertEqual(Self.reason(five.replacingOccurrences(of: #""ghost": ["e1"]"#, with: #""ghost": [\#(ids)]"#)), "step.ghost")
        XCTAssertEqual(Self.reason(five.replacingOccurrences(of: #""ghost": ["e1"]"#, with: #""section": {"normal": [1, 0, 0], "parts": [\#(ids)]}"#)),
                       "step.section.parts")
        // A section of an instance cuts every part of it.
        var lib = MGSolidLibrary.builtIn
        _ = try lib.register(Data(#"{"v": 1, "kind": "component", "id": "pair", "title": "T", "about": "Two blocks.", "params": {}, "parts": [{"id": "a", "shape": {"box": {"size": [40, 20, 20]}}}, {"id": "b", "at": [0, 30, 0], "shape": {"box": {"size": [40, 20, 20]}}}]}"#.utf8)).get()
        let pair = #"{"v": 2, "kind": "assembly", "parts": [{"id": "x", "use": "pair"}, {"id": "y", "use": "pair", "at": [0, 0, 60]}], "steps": [{"say": "Cut.", "section": {"normal": [1, 0, 0], "parts": ["x", "y.a"]}}]}"#
        let cut = try MGSolidParser.document(data: Data(pair.utf8), library: lib).get()
        XCTAssertEqual(cut.steps[0].section?.parts, ["x.a", "x.b", "y.a"])
        XCTAssertEqual(cut.steps[0].section?.cuts.count, 3)
    }

    func testInstanceExplodeMovesEveryPart() throws {
        let text = #"{"v": 2, "kind": "assembly", "params": {"explode": 1}, "parts": [{"id": "e", "use": "microTurbojet", "explode": [0, 0, 120]}, {"id": "c", "use": "centrifugalCompressor", "at": [400, 0, 0], "explode": [50, 0, 0]}]}"#
        let d = try Self.doc(text)
        for id in ["e.casing", "e.shaft", "e.nozzle"] { XCTAssertEqual(d.assembly.part(id)?.explode, MGVec3(0, 0, 120), id) }
        // The compressor's roots add the instance offset to their own; inner parts ride on their roots.
        XCTAssertEqual(d.assembly.part("c.impeller")?.explode, MGVec3(50, 0, 0))
        XCTAssertEqual(d.assembly.part("c.diffuser")?.explode, MGVec3(50, 0, 25))
        XCTAssertEqual(d.assembly.part("c.vane1")?.explode, .zero)
        XCTAssertEqual(Self.reason(text.replacingOccurrences(of: "[0, 0, 120]", with: "[0, 0]")), "component.use.explode")
        XCTAssertEqual(Self.reason(text.replacingOccurrences(of: #""v": 2"#, with: #""v": 1"#).replacingOccurrences(of: #", "params": {"explode": 1}"#, with: "")),
                       "component.use.unknown.explode")
    }

    // MARK: Motion arrow size

    func testMotionArrowsTakeTheStepFocusSize() throws {
        let text = #"{"v": 2, "kind": "assembly", "parts": [{"id": "frame", "shape": {"box": {"size": [2000, 400, 40]}}, "at": [0, 0, -40]}, {"id": "shaft", "shape": {"shaft": {"radius": 4, "length": 60}}, "joint": {"revolute": [0, 0, 1]}, "drive": {"input": 1}}, {"id": "hub", "parent": "shaft", "shape": {"shaft": {"radius": 30, "length": 10, "z0": 25}}}], "annotations": {"arrows": [{"id": "t", "meaning": "motion", "style": "turn", "on": "shaft"}]}, "steps": [{"say": "Whole."}, {"say": "Close.", "focus": ["shaft", "hub"]}]}"#
        let d = try Self.doc(text)
        let model = d.annotations.diagonal
        XCTAssertEqual(d.motionArrowDiagonal(step: nil), model)
        XCTAssertEqual(d.motionArrowDiagonal(step: 0), model)
        let close = d.motionArrowDiagonal(step: 1)
        XCTAssertLessThan(close, 0.1 * model)
        let wide = MGSolidAnnotations.primitives(d, "t", params: d.defaults, step: 0)
        let near = MGSolidAnnotations.primitives(d, "t", params: d.defaults, step: 1)
        XCTAssertEqual(wide.count, near.count)
        XCTAssertEqual(wide[0].radius, model * MGSolidAnnotationLimits.shaftRadius, accuracy: 1e-9)
        XCTAssertEqual(near[0].radius, close * MGSolidAnnotationLimits.shaftRadius, accuracy: 1e-9)
        // The arc keeps clear of the part (1.15 x its widest radius) and stays near it.
        let arm = d.annotations.arrow("t")!
        let radius = (near[0].start - MGVec3(0, 0, near[0].start.z)).length
        XCTAssertEqual(radius, max(arm.arcClearance, 8 * near[0].radius), accuracy: 1e-6)
        XCTAssertLessThan(radius, 60)
    }

    // MARK: Two-line text

    func testLinesBreakNearTheMiddle() {
        XCTAssertEqual(MGAnnotationLayout.lines(String(repeating: "a", count: 40)).count, 1)
        let t = "Back: equipment plus about one third of pilot weight"
        let l = MGAnnotationLayout.lines(t)
        XCTAssertEqual(l, ["Back: equipment plus about", "one third of pilot weight"])
        XCTAssertTrue(l.allSatisfy { $0.unicodeScalars.count <= MGAnnotationLayout.lineScalars })
        XCTAssertEqual(MGAnnotationLayout.lines(t), l)
        // No space: a cut at the middle character boundary.
        XCTAssertEqual(MGAnnotationLayout.lines(String(repeating: "x", count: 50)), [String(repeating: "x", count: 25), String(repeating: "x", count: 25)])
        // Box: one row per line, the longest line sets the width; a one-line text keeps its earlier box.
        let f = 18.0
        let one = MGAnnotationLayout.boxSize("Short", fontSize: f), two = MGAnnotationLayout.boxSize(t, fontSize: f)
        XCTAssertEqual(one.width, 0.58 * f * 5 + 12, accuracy: 1e-9); XCTAssertEqual(one.height, 1.3 * f + 8, accuracy: 1e-9)
        XCTAssertEqual(two.width, 0.58 * f * 26 + 12, accuracy: 1e-9); XCTAssertEqual(two.height, 2.6 * f + 8, accuracy: 1e-9)
        let full = String(repeating: "word ", count: 12).trimmingCharacters(in: .whitespaces)
        XCTAssertEqual(full.unicodeScalars.count, 59)
        XCTAssertLessThanOrEqual(MGAnnotationLayout.boxSize(full, fontSize: f).width, 0.58 * f * 40 + 12)
    }

    /// Five 60-scalar labels at the readability-guarantee sizes: every box inside the view, no overlap, bounded size, the
    /// same layout twice.
    @MainActor func testSixtyScalarLabelsLayOutAtGuaranteedSizes() throws {
        let texts = ["Alpha", "Bravo", "Charlie", "Delta", "Echo"].map { "Label \($0) with a long reported figure and its source" }
        XCTAssertTrue(texts.allSatisfy { $0.unicodeScalars.count <= MGSolidAnnotationLimits.text })
        let labels = texts.enumerated().map { #"{"id": "l\#($0.offset)", "at": {"part": "core", "offset": [\#($0.offset * 40 - 80), 0, \#($0.offset * 30)]}, "text": "\#($0.element)"}"# }
        let text = #"{"v": 2, "kind": "assembly", "parts": [{"id": "core", "shape": {"box": {"size": [200, 60, 160]}}}], "annotations": {"labels": [\#(labels.joined(separator: ","))]}, "steps": [{"say": "Labels."}]}"#
        let d = try Self.doc(text)
        for (w, h) in [(1280.0, 720.0), (1280, 800), (1440, 720), (1280, 1280), (1280, 2560), (1920, 1080), (3840, 2160), (1600, 3200)] {
            let cam = MGSolidAnnotations.defaultCamera(d, params: d.defaults, aspect: w / h)
            let f = MGSolidAnnotations.frame(document: d, view: d.view(step: 0), params: d.defaults, camera: cam, width: w, height: h, caption: true)
            XCTAssertEqual(f.placement.count, 5)
            let fs = MGAnnotationLayout.fontSize(height: h)
            let boxes = f.placement.map { MGAnnotationRect(x: $0.box[0] * w, y: $0.box[1] * h, width: $0.box[2] * w, height: $0.box[3] * h) }
            for (p, b) in zip(f.placement, boxes) {
                XCTAssertTrue(b.x >= 0 && b.y >= 0 && b.maxX <= w + 1e-6 && b.maxY <= h + 1e-6, "\(p.id) at \(w)x\(h)")
                XCTAssertLessThanOrEqual(b.height, 2.6 * fs + 8 + 1e-6)
                if p.callout == nil { XCTAssertLessThanOrEqual(b.width, 0.58 * fs * 40 + 12 + 1e-6) }
                for line in MGAnnotationLayout.lines(p.callout.map { "\($0 + 1). " + p.text } ?? p.text) {
                    XCTAssertLessThanOrEqual(MGSolidOverlay.fit(line, width: b.width - 12, fontSize: fs).width, b.width - 12 + 1e-9)
                }
            }
            for i in boxes.indices { for j in boxes.indices where i < j { XCTAssertFalse(boxes[i].intersects(boxes[j]), "\(w)x\(h) \(i) \(j)") } }
            let again = MGSolidAnnotations.frame(document: d, view: d.view(step: 0), params: d.defaults, camera: cam, width: w, height: h, caption: true)
            XCTAssertEqual(again, f)
        }
    }

    // MARK: Hero framing

    func testHeroKeepsTheTitleBandFree() throws {
        // A tall figure: the earlier whole-model framing reached into the title band.
        let d = try Self.doc(Self.suit(#"[{"say": "a"}]"#, plume: false))
        let plan = MGSolidRenderPlan(d, sourceName: "x", source: MGSolidSource(data: Data()), loop: false)
        for (w, h) in [(1280.0, 800.0), (1280, 720), (1280, 1280), (1280, 2560)] {
            let hero = plan.stills[0]
            XCTAssertEqual(hero.file, "hero.png")
            let cam = MGSolidFraming.camera(d, shot: hero, aspect: w / h, titleBand: MGSolidRenderPlan.bands(width: w, height: h).title, captionBand: 0)
            let pts = MGSolidFraming.Samples(d.assembly, ids: nil).world(d.assembly, hero.params, stage: MGSolidStage.zUpToYUp)
            let window = MGSolidFraming.Window(titleBand: MGSolidRenderPlan.bands(width: w, height: h).title, captionBand: 0)
            XCTAssertTrue(MGSolidFraming.contains(pts, camera: cam, aspect: w / h, window: window), "\(w)x\(h)")
        }
    }

    // MARK: Story blend

    func testTransformBlendAndStoryPlacements() throws {
        let a = MGTransform.translation(MGVec3(10, 0, 0)) * .rotation(axis: .unitZ, angle: 0.2)
        let b = MGTransform.translation(MGVec3(30, 0, 0)) * .rotation(axis: .unitZ, angle: 1.0)
        XCTAssertEqual(MGTransform.blend(a, b, 0), a)
        XCTAssertEqual(MGTransform.blend(a, b, 1), b)
        let m = MGTransform.blend(a, b, 0.5)
        XCTAssertEqual(m.translation.x, 20, accuracy: 1e-12)
        XCTAssertEqual(atan2(m.c0.y, m.c0.x), 0.6, accuracy: 1e-12)
        XCTAssertEqual(MGTransform.blend(a, b, .nan), b)
        let d = try Self.doc(Self.suit(#"[{"say": "a"}, {"say": "b", "pose": {"pilot": {"with": {"leftShoulder": 60}}}}]"#))
        let to = d.steps[1].pose
        XCTAssertEqual(MGStoryPlan.placements(d.assembly, from: [:], to: to, 1), to)
        XCTAssertEqual(MGStoryPlan.placements(d.assembly, from: [:], to: to, 0)["pilot.upperArmL"], d.assembly.part("pilot.upperArmL")?.placement)
        XCTAssertEqual(MGStoryPlan.placements(d.assembly, from: to, to: to, 0.3), to)
        XCTAssertEqual(MGStoryPlan.placements(d.assembly, from: [:], to: [:], 0.3), [:])
    }

    // MARK: Renderer

    func testRendererHidesPartsAndPosesNodes() throws {
        let d = try Self.doc(Self.suit(#"[{"say": "a"}, {"say": "b", "show": ["plume"], "pose": {"pilot": {"with": {"leftShoulder": 60}}}}]"#))
        let r = MGSolidRenderer(document: d)
        func node(_ id: String) -> SCNNode? { r.scene.rootNode.childNode(withName: id, recursively: true) }
        r.show(document: d, view: d.view(step: 0)); r.apply(d.poseParameters(step: 0))
        XCTAssertEqual(node("plume")?.isHidden, true)
        let rest = try XCTUnwrap(node("engL.casing")).simdWorldTransform
        r.show(document: d, view: d.view(step: 1)); r.apply(d.poseParameters(step: 1))
        XCTAssertEqual(node("plume")?.isHidden, false)
        XCTAssertNotEqual(try XCTUnwrap(node("engL.casing")).simdWorldTransform, rest)
        // Framing bounds leave hidden parts out.
        let all = r.worldBounds(d.defaults), shown = r.worldBounds(d.defaults, hidden: ["plume"])
        XCTAssertNotEqual(all, shown)
        XCTAssertEqual(shown, MGSolidRenderer(document: try Self.doc(Self.suit(#"[{"say": "a"}]"#, plume: false))).worldBounds(d.defaults))
    }

    // MARK: Explainer views

    func testExplainerViewPoseHideAndShow() throws {
        let solid = Self.suit("[]").replacingOccurrences(of: #", "steps": []"#, with: "").replacingOccurrences(of: #", "title": "Suit""#, with: "")
        let beats = #"[{"say": "Hover."}, {"say": "Steer.", "view": {"pose": {"pilot": {"with": {"leftShoulder": 45}}}, "show": ["plume"]}}, {"say": "Hide.", "view": {"hide": ["engR"]}}]"#
        let s = try XFix.load(XFix.doc(title: "Suit", solid: solid, beats: beats))
        let d = try XCTUnwrap(s.solid)
        let step = try XCTUnwrap(s.solidStep(forBeat: 1))
        XCTAssertEqual(d.steps[step].pose.keys.sorted(), ["pilot.upperArmL"])
        XCTAssertFalse(d.view(step: step).part("plume").hidden)
        XCTAssertTrue(d.view(step: s.solidStep(forBeat: 2)).part("plume").hidden)
        XCTAssertTrue(d.view(step: s.solidStep(forBeat: 2)).part("engR.casing").hidden)
        // The beat view's pose parameters carry the pose.
        var v = MGExplainerBeatView(); v.step = d.steps[step]
        XCTAssertEqual(MGExplainerFrame.pose(d, view: v).placements, d.steps[step].pose)
        // Snapshot and restore keep the posed view.
        let restored = try MGExplainerSession.restore(s.snapshot(), pacing: .immediate, clock: MGManualClock()).get()
        XCTAssertEqual(restored.solid?.steps.map(\.pose), d.steps.map(\.pose))
        XCTAssertEqual(restored.solid?.showOnly, ["plume"])
        // Refusals carry the view names.
        func refusal(_ view: String, say: String = "B.") -> String? {
            XFix.refusal(XFix.doc(title: "Suit", solid: solid, beats: #"[{"say": "\#(say)", "view": \#(view)}]"#))?.reason
        }
        XCTAssertEqual(refusal(#"{"pose": {"pilot": {"with": {"leftShoulder": 999}}}}"#), "view.pose.with")
        XCTAssertEqual(refusal(#"{"pose": {"nothing": {"rot": [0, 0, 1, 4]}}}"#), "view.pose.ref")
        XCTAssertEqual(refusal(#"{"pose": {"pilot": {"rot": [0, 0, 1, 4]}}}"#), "view.pose.key")
        XCTAssertEqual(refusal(#"{"hide": []}"#), "view.hide")
        XCTAssertEqual(refusal(#"{"hide": ["plume"], "show": ["plume"]}"#), "view.hide.both")
        XCTAssertEqual(refusal(#"{"hide": ["engR"], "focus": ["engR.casing"]}"#), "view.hide.use")
        // A beat caption may not show a fact of a part its view hides.
        XCTAssertEqual(refusal(#"{"hide": ["engR"]}"#, say: "Turns {engR.shaft.speed}."), "view.hide.fact")
        XCTAssertNil(refusal(#"{"hide": ["engR"]}"#, say: "Turns {engL.shaft.speed}."))
    }

    func testRefusedExplainerViewLeavesTheSessionUnchanged() throws {
        let solid = Self.suit("[]").replacingOccurrences(of: #", "steps": []"#, with: "").replacingOccurrences(of: #", "title": "Suit""#, with: "")
        var s = MGExplainerSession(pacing: .immediate, clock: MGManualClock())
        var events = s.feed(XFix.header() + "\n" + #"{"solid": \#(solid)}"# + "\n" + #"{"say": "Hover."}"# + "\n" + #"{"view": {"pose": {"pilot": {"with": {"leftShoulder": 30}}}}}"# + "\n")
        XCTAssertEqual(XFix.reasons(events), [])
        let before = s.solid
        events = s.feed(#"{"say": "Steer."}"# + "\n" + #"{"view": {"pose": {"engL": {"with": {"diameter": 90}}}}}"# + "\n")
        XCTAssertEqual(XFix.reasons(events), ["view.pose.with"])
        XCTAssertEqual(s.solid, before)
    }
}

/// The PR #39 review probe, one test per scenario: facts at the pose, facts of hidden parts, presented-only motion
/// claims, the title-free pose compile, oversized graphemes, refusal state, snapshot structure, the winch golden, story
/// bounds and determinism.
final class StepPoseReviewTests: ExplainerTestCase {
    static let arm = #"[{"id":"arm","shape":{"box":{"size":[10,10,60]}}}]"#
    static let gap = #"{"dimensions":[{"id":"gap","a":{"part":"arm","offset":[0,0,30]},"b":{"world":[0,0,60]}}]}"#
    static let moving = #"[{"id":"base","shape":{"box":{"size":[20,20,10]}}},{"id":"shaft","at":[50,0,0],"shape":{"shaft":{"radius":5,"length":20}},"joint":{"revolute":[0,0,1]},"drive":{"input":1}}]"#
    static func dimDoc(rot: String, step2: String) -> String {
        #"{"v":2,"kind":"assembly","parts":\#(arm),"annotations":\#(gap),"steps":[{"say":"Base.","annotate":["gap"]},{"say":"Tilt.","annotate":[],"pose":{"arm":{"rot":\#(rot)}}\#(step2)}]}"#
    }
    func issue(_ s: String) -> MGSolidIssue? {
        if case .failure(let e) = MGSolidParser.document(data: Data(s.utf8), profile: .strict) { return e }; return nil
    }
    func doc(_ s: String) throws -> MGSolidDocument { try MGSolidParser.document(data: Data(s.utf8), profile: .strict).get() }
    func session(_ source: String) throws -> MGExplainerSession {
        var s = MGExplainerSession(pacing: .immediate, clock: MGManualClock())
        _ = try s.load(try MGExplainer.parse(data: Data(source.utf8)).get()).get()
        return s
    }

    // MARK: 1. Facts at the pose

    func testPosedDimensionCheckIsRefused() throws {
        // POSED_DIM_CHECK: the arm tilts 90 degrees, so the gap is 67.08 there, not 30.
        let i = issue(Self.dimDoc(rot: "[1,0,0,90]", step2: #","check":[{"value":"dim.gap","eq":30}]"#))
        XCTAssertEqual(i?.reason, "step.pose.fact"); XCTAssertEqual(i?.part, "dim.gap")
        // The same fact in the caption or the title, with the dimension hidden in that step.
        XCTAssertEqual(issue(Self.dimDoc(rot: "[1,0,0,90]", step2: "").replacingOccurrences(of: #""say":"Tilt.""#, with: #""say":"Gap {dim.gap}.""#))?.reason, "step.pose.fact")
        XCTAssertEqual(issue(Self.dimDoc(rot: "[1,0,0,90]", step2: "").replacingOccurrences(of: #""kind":"assembly","#, with: #""kind":"assembly","title":"Gap {dim.gap}","#))?.reason, "step.pose.fact")
        // In annotation text a step shows.
        let label = Self.dimDoc(rot: "[1,0,0,90]", step2: "").replacingOccurrences(of: #""annotations":{"#, with: #""annotations":{"labels":[{"id":"l","at":"arm","text":"Gap {dim.gap}"}],"#)
            .replacingOccurrences(of: #""annotate":[],"#, with: #""annotate":["l"],"#)
        XCTAssertEqual(issue(label)?.reason, "step.pose.fact")
        // A pose that keeps the gap (a turn about the arm's own axis) keeps the check.
        let kept = try doc(Self.dimDoc(rot: "[0,0,1,90]", step2: #","check":[{"value":"dim.gap","eq":30}]"#))
        XCTAssertEqual(kept.steps[1].checks.count, 1)
        XCTAssertNil(kept.factNotHolding(step: 1, names: ["dim.gap"]))
    }

    func testExplainerPosedDimensionCheckIsRefusedInEveryOrder() throws {
        let solid = #"{"v":2,"parts":\#(Self.arm),"annotations":\#(Self.gap)}"#
        // EXPLAINER_DIM_CHECK: a whole document.
        let docText = #"{"v":1,"kind":"explainer","solid":\#(solid),"beats":[{"say":"Base.","view":{"annotate":["gap"]}},{"say":"Tilt.","view":{"annotate":[],"pose":{"arm":{"rot":[1,0,0,90]}}},"check":[{"value":"dim.gap","eq":30}]}]}"#
        let r = XFix.refusal(docText)
        XCTAssertEqual(r?.reason, "view.pose.fact"); XCTAssertEqual(r?.id, "dim.gap")
        // A stream: the view after the check, and the check after the view.
        let head = [XFix.header(), #"{"solid":\#(solid)}"#, #"{"say":"Base."}"#, #"{"view":{"annotate":["gap"]}}"#, #"{"say":"Tilt."}"#]
        let (_, a) = XFix.stream(head + [#"{"check":{"value":"dim.gap","eq":30}}"#, #"{"view":{"annotate":[],"pose":{"arm":{"rot":[1,0,0,90]}}}}"#])
        XCTAssertEqual(XFix.reasons(a), ["view.pose.fact"])
        let (_, b) = XFix.stream(head + [#"{"view":{"annotate":[],"pose":{"arm":{"rot":[1,0,0,90]}}}}"#, #"{"check":{"value":"dim.gap","eq":30}}"#])
        XCTAssertEqual(XFix.reasons(b), ["view.pose.fact"])
        // EXPLAINER_DIM_CHECK_RESTORE: a snapshot whose view was changed to the tilting pose is refused on restore.
        let ok = try session(docText.replacingOccurrences(of: "[1,0,0,90]", with: "[0,0,1,90]"))
        guard case .object(var saved) = ok.snapshot(), case .array(var beats)? = saved["beats"], case .object(var beat) = beats[1] else { return XCTFail("snapshot") }
        beat["view"] = .string(#"{"annotate":[],"pose":{"arm":{"rot":[1,0,0,90]}}}"#)
        beats[1] = .object(beat); saved["beats"] = .array(beats)
        guard case .failure(let e) = MGExplainerSession.restore(.object(saved), pacing: .immediate) else { return XCTFail("restored") }
        XCTAssertEqual(e.reason, "view.pose.fact")
    }

    func testHostBoardChangeAtAPoseIsRefusedAndChangesNothing() throws {
        // HOST_POSE_REFUSAL: board text that would show the gap while a beat tilts the arm.
        let board = #"{"v":1,"items":[{"id":"label","k":"text","at":[1,1],"text":"Safe."}]}"#
        let text = #"{"v":1,"kind":"explainer","board":\#(board),"solid":{"v":2,"parts":\#(Self.arm),"annotations":\#(Self.gap)},"beats":[{"say":"Base.","view":{"annotate":["gap"]}},{"say":"Tilt.","view":{"annotate":[],"pose":{"arm":{"rot":[1,0,0,90]}}}}]}"#
        var s = try session(text)
        let state = s.state, solid = s.solid, presented = s.presented, legend = s.legend
        let r = s.apply([XFix.json(#"{"op":"set","id":"label","key":"text","value":"Gap {dim.gap}"}"#)])
        guard case .failure(let e) = r else { return XCTFail("accepted") }
        XCTAssertEqual(e.reason, "view.pose.fact"); XCTAssertEqual(e.id, "dim.gap")
        XCTAssertEqual(s.state, state); XCTAssertEqual(s.solid, solid); XCTAssertEqual(s.presented, presented); XCTAssertEqual(s.legend, legend)
    }

    // MARK: Re-check: the whole motion domain, and fact ids

    static let motorArm = #"[{"id":"arm","shape":{"box":{"size":[10,10,60]}},"joint":{"revolute":[1,0,0]},"drive":{"input":1}}]"#

    func testPosedSpinningCheckIsRefused() {
        // POSE_SPIN_CHECK: the arm turns about its own X axis during the step, so the gap is 30 only at the start.
        let posed = #"{"v":2,"kind":"assembly","parts":\#(Self.motorArm),"annotations":\#(Self.gap),"steps":[{"say":"Base.","annotate":["gap"]},{"say":"Turn.","annotate":[],"pose":{"arm":{"rot":[0,0,1,90]}},"spin":0.25,"check":[{"value":"dim.gap","eq":30}]}]}"#
        XCTAssertEqual(issue(posed)?.reason, "step.pose.fact"); XCTAssertEqual(issue(posed)?.part, "dim.gap")
        // The same check in a spinning step without a pose follows the same rule.
        XCTAssertEqual(issue(posed.replacingOccurrences(of: #""pose":{"arm":{"rot":[0,0,1,90]}},"#, with: ""))?.reason, "step.pose.fact")
        // Without the spin the check holds at the pose (a turn about Z keeps the gap).
        XCTAssertNoThrow(try doc(posed.replacingOccurrences(of: #","spin":0.25"#, with: "")))
    }

    func testExplainerPosedSpinningCheckIsRefusedInEveryPath() throws {
        let solid = #"{"v":2,"parts":\#(Self.motorArm),"annotations":\#(Self.gap)}"#
        let view = #"{"annotate":[],"pose":{"arm":{"rot":[0,0,1,90]}},"spin":0.25}"#
        let text = #"{"v":1,"kind":"explainer","solid":\#(solid),"beats":[{"say":"Base.","view":{"annotate":["gap"]}},{"say":"Turn.","view":\#(view),"check":[{"value":"dim.gap","eq":30}]}]}"#
        let r = XFix.refusal(text)
        XCTAssertEqual(r?.reason, "view.pose.fact"); XCTAssertEqual(r?.id, "dim.gap")
        // STREAM_POSE_SPIN_CHECK: the check first, then the spinning view; and the other order.
        let head = [XFix.header(), #"{"solid":\#(solid)}"#, #"{"say":"Base."}"#, #"{"view":{"annotate":["gap"]}}"#, #"{"say":"Turn."}"#]
        let (_, a) = XFix.stream(head + [#"{"check":{"value":"dim.gap","eq":30}}"#, #"{"view":\#(view)}"#])
        XCTAssertEqual(XFix.reasons(a), ["view.pose.fact"]); XCTAssertEqual(XFix.refusals(a).first?.id, "dim.gap")
        let (_, b) = XFix.stream(head + [#"{"view":\#(view)}"#, #"{"check":{"value":"dim.gap","eq":30}}"#])
        XCTAssertEqual(XFix.reasons(b), ["view.pose.fact"])
        // Restore: a saved still view changed to the spinning one is refused, naming the fact.
        let ok = try session(text.replacingOccurrences(of: #","spin":0.25"#, with: ""))
        guard case .object(var saved) = ok.snapshot(), case .array(var beats)? = saved["beats"], case .object(var beat) = beats[1] else { return XCTFail("snapshot") }
        beat["view"] = .string(view)
        beats[1] = .object(beat); saved["beats"] = .array(beats)
        guard case .failure(let e) = MGExplainerSession.restore(.object(saved), pacing: .immediate) else { return XCTFail("restored") }
        XCTAssertEqual(e.reason, "view.pose.fact"); XCTAssertEqual(e.id, "dim.gap")
    }

    func testHostEditAndRestoreRefusalsNameTheFact() throws {
        // HOST_HIDE: board text with a fact of a part a beat hides.
        let board = #"{"v":1,"items":[{"id":"label","k":"text","at":[1,1],"text":"Safe."}]}"#
        var s = try session(#"{"v":1,"kind":"explainer","board":\#(board),"solid":{"v":2,"parts":\#(Self.moving)},"beats":[{"say":"A."},{"say":"B.","view":{"hide":["shaft"]}}]}"#)
        let before = s.claims
        guard case .failure(let e) = s.apply([XFix.json(#"{"op":"set","id":"label","key":"text","value":"Speed {shaft.speed}"}"#)]) else { return XCTFail("accepted") }
        XCTAssertEqual(e.reason, "view.hide.fact"); XCTAssertEqual(e.id, "shaft.speed"); XCTAssertEqual(s.claims, before)
        // RESTORE_FACT_ID: a title that shows the gap, and a saved view changed to a tilting pose.
        let solid = #"{"v":2,"parts":\#(Self.arm),"annotations":\#(Self.gap)}"#
        let ok = try session(#"{"v":1,"kind":"explainer","title":"Gap {dim.gap}","solid":\#(solid),"beats":[{"say":"Base.","view":{"annotate":["gap"]}},{"say":"Tilt.","view":{"annotate":[],"pose":{"arm":{"rot":[0,0,1,90]}}}}]}"#)
        guard case .object(var saved) = ok.snapshot(), case .array(var beats)? = saved["beats"], case .object(var beat) = beats[1] else { return XCTFail("snapshot") }
        beat["view"] = .string(#"{"annotate":[],"pose":{"arm":{"rot":[1,0,0,90]}}}"#)
        beats[1] = .object(beat); saved["beats"] = .array(beats)
        guard case .failure(let r) = MGExplainerSession.restore(.object(saved), pacing: .immediate) else { return XCTFail("restored") }
        XCTAssertEqual(r.reason, "view.pose.fact"); XCTAssertEqual(r.id, "dim.gap")
    }

    // MARK: 2. Facts of hidden parts

    func testHiddenPartFactsAreRefusedEverywhere() {
        // HIDDEN_LABEL: a visible label that shows the hidden shaft's speed.
        let label = #"{"v":2,"kind":"assembly","parts":\#(Self.moving),"annotations":{"labels":[{"id":"l","at":"base","text":"Hidden speed {shaft.speed}"}]},"steps":[{"say":"Hidden.","hide":["shaft"],"annotate":["l"]}]}"#
        XCTAssertEqual(issue(label)?.reason, "step.hide.fact"); XCTAssertEqual(issue(label)?.part, "shaft.speed")
        // HIDDEN_TITLE: the title shows in every frame; a part any step hides may not appear in it.
        let title = #"{"v":2,"kind":"assembly","title":"Hidden speed {shaft.speed}","parts":\#(Self.moving),"steps":[{"say":"Shown."},{"say":"Hidden.","hide":["shaft"]}]}"#
        XCTAssertEqual(issue(title)?.reason, "step.hide.fact")
        XCTAssertNoThrow(try doc(title.replacingOccurrences(of: #","hide":["shaft"]"#, with: "")))
        // Explainer: board text and the title against every view, a beat's annotation text against its own.
        let solid = #"{"v":2,"parts":\#(Self.moving),"annotations":{"labels":[{"id":"l","at":"base","text":"Speed {shaft.speed}"}]}}"#
        let board = #"{"v":1,"items":[{"id":"t","k":"text","at":[1,1],"text":"Speed {shaft.speed}"}]}"#
        XCTAssertEqual(XFix.refusal(XFix.doc(board: board, solid: #"{"v":2,"parts":\#(Self.moving)}"#, beats: #"[{"say":"A."},{"say":"B.","view":{"hide":["shaft"]}}]"#))?.reason, "view.hide.fact")
        XCTAssertEqual(XFix.refusal(XFix.doc(title: "Speed {shaft.speed}", solid: #"{"v":2,"parts":\#(Self.moving)}"#, beats: #"[{"say":"A."},{"say":"B.","view":{"hide":["shaft"]}}]"#))?.reason, "view.hide.fact")
        XCTAssertEqual(XFix.refusal(XFix.doc(solid: solid, beats: #"[{"say":"A.","view":{"hide":["shaft"],"annotate":["l"]}}]"#))?.reason, "view.hide.fact")
    }

    // MARK: 3. Presented-only motion claims

    func testExplainerMotionCountsOnlyWhenDisplayed() throws {
        // HIDDEN_EXPLAINER_LEGEND: the only beat hides the shaft, so its motion never showed.
        let hidden = #"{"v":1,"kind":"explainer","solid":{"v":2,"parts":\#(Self.moving)},"beats":[{"say":"Hidden.","view":{"hide":["shaft"]}}]}"#
        let s = try session(hidden)
        XCTAssertFalse(s.claims.contains { $0.kind == .motion })
        XCTAssertEqual(s.snapshot()["shownMotion"], .array([]))
        // HIDDEN_EXPLAINER_RESTORE.
        let restored = try MGExplainerSession.restore(s.snapshot(), pacing: .immediate).get()
        XCTAssertFalse(restored.claims.contains { $0.kind == .motion })
        // A later beat that shows the shaft counts it, and it stays counted (frozen).
        let both = try session(hidden.replacingOccurrences(of: #"{"say":"Hidden.","view":{"hide":["shaft"]}}"#,
                                                         with: #"{"say":"Shown."},{"say":"Hidden.","view":{"hide":["shaft"]}}"#))
        XCTAssertEqual(both.claims.filter { $0.kind == .motion }.map(\.id), ["shaft"])
        XCTAssertEqual(both.snapshot()["shownMotion"], .array([.object(["id": .string("shaft"), "tier": .string("solved")])]))
        // Without any hidden part, motion counts as before and the snapshot has no record.
        let plain = try session(hidden.replacingOccurrences(of: #","view":{"hide":["shaft"]}"#, with: ""))
        XCTAssertEqual(plain.claims.filter { $0.kind == .motion }.map(\.id), ["shaft"])
        XCTAssertNil(plain.snapshot()["shownMotion"])
    }

    func testShownMotionRecordIsCheckedOnRestore() throws {
        let text = #"{"v":1,"kind":"explainer","solid":{"v":2,"parts":\#(Self.moving)},"beats":[{"say":"Shown."},{"say":"Hidden.","view":{"hide":["shaft"]}}]}"#
        let s = try session(text)
        func restore(_ v: MGJSON?, _ snap: MGExplainerSession) -> String? {
            guard case .object(var o) = snap.snapshot() else { return "x" }
            o["shownMotion"] = v
            if case .failure(let e) = MGExplainerSession.restore(.object(o), pacing: .immediate) { return e.reason }
            return nil
        }
        XCTAssertNil(restore(s.snapshot()["shownMotion"], s))
        XCTAssertEqual(restore(.array([]), s), "snapshot.shown")                                         // misses the shaft
        XCTAssertEqual(restore(.array([.object(["id": .string("base"), "tier": .string("solved")])]), s), "snapshot.shown")
        XCTAssertEqual(restore(.array([.object(["id": .string("shaft"), "tier": .string("built")])]), s), "snapshot.shown")
        let twice = MGJSON.object(["id": .string("shaft"), "tier": .string("solved")])
        XCTAssertEqual(restore(.array([twice, twice]), s), "snapshot.shown")
        XCTAssertEqual(restore(.array(Array(repeating: twice, count: MGShownMotion.maxCount + 1)), s), "snapshot.shown")
        XCTAssertNil(restore(nil, s))                                                                     // rebuilt
        // A session whose views hide nothing may not carry the record.
        let plain = try session(text.replacingOccurrences(of: #","view":{"hide":["shaft"]}"#, with: ""))
        XCTAssertEqual(restore(.array([]), plain), "snapshot.shown")
    }

    func testAssemblyPartHiddenInEveryViewMakesNoMotionClaim() throws {
        // The hero (plain view) hides only show-only parts, and a show-only part shows in its own steps; so a part every
        // step hides is still seen in hero.png and keeps its claim.
        let everyStep = try doc(#"{"v":2,"kind":"assembly","parts":\#(Self.moving),"steps":[{"say":"A.","hide":["shaft"]},{"say":"B.","hide":["shaft"]}]}"#)
        XCTAssertTrue(everyStep.neverShownParts.isEmpty)
        XCTAssertEqual(everyStep.claims.filter { $0.kind == .motion }.map(\.id), ["shaft"])
        // A part hidden in the plain view and in every step makes no claim (an explainer solid's views can do this).
        var d = everyStep
        d.showOnly = ["shaft"]
        XCTAssertEqual(d.neverShownParts, ["shaft"])
        XCTAssertFalse(d.claims.contains { $0.kind == .motion })
    }

    // MARK: 4. The title stays out of the pose compile

    func testUnrelatedPoseKeepsAnAnnotationTitle() throws {
        // POSE_DIM_TITLE: the gap runs between two world points, so the pose does not change it.
        let d = try doc(#"{"v":2,"kind":"assembly","title":"Gap {dim.gap}","parts":\#(Self.arm),"annotations":{"dimensions":[{"id":"gap","a":{"world":[0,0,0]},"b":{"world":[0,0,60]}}]},"steps":[{"say":"Tilt.","pose":{"arm":{"rot":[1,0,0,90]}}}]}"#)
        XCTAssertEqual(d.title, "Gap 60 mm")
        XCTAssertEqual(d.steps[0].pose.keys.sorted(), ["arm"])
    }

    // MARK: 5. Graphemes and the box bound

    func testGraphemeLimitAndBoxBound() throws {
        func labelDoc(_ t: String) -> String {
            let e = String(data: try! JSONEncoder().encode(t), encoding: .utf8)!
            return #"{"v":2,"kind":"assembly","parts":\#(Self.arm),"annotations":{"labels":[{"id":"l","at":"arm","text":\#(e)}]}}"#
        }
        let cjk = String(repeating: "漢", count: 60), emoji = String(repeating: "😀", count: 60)
        let combining = "a" + String(repeating: "\u{0301}", count: 59)
        XCTAssertNoThrow(try doc(labelDoc(cjk)))
        XCTAssertNoThrow(try doc(labelDoc(emoji)))
        XCTAssertEqual(issue(labelDoc(combining))?.reason, "text.grapheme")
        XCTAssertEqual(issue(labelDoc(combining))?.part, "l")
        XCTAssertNoThrow(try doc(labelDoc("e" + String(repeating: "\u{0301}", count: 7))))   // 8 scalars: allowed
        XCTAssertEqual(issue(labelDoc("e" + String(repeating: "\u{0301}", count: 8)))?.reason, "text.grapheme")
        let f = 16.0, maxWidth = 0.58 * f * Double(MGAnnotationLayout.lineScalars) + 12
        for t in [cjk, emoji, combining, String(repeating: "x", count: 100), String(repeating: "word ", count: 30)] {
            let lines = MGAnnotationLayout.lines(t)
            XCTAssertLessThanOrEqual(lines.count, 2)
            XCTAssertTrue(lines.allSatisfy { $0.unicodeScalars.count <= MGAnnotationLayout.lineScalars }, "\(lines)")
            let box = MGAnnotationLayout.boxSize(t, fontSize: f)
            XCTAssertLessThanOrEqual(box.width, maxWidth + 1e-9)
            XCTAssertLessThanOrEqual(box.height, 2.6 * f + 8 + 1e-9)
            for line in lines { XCTAssertLessThanOrEqual(MGSolidOverlay.fit(line, width: box.width - 12, fontSize: f).width, box.width - 12 + 1e-9) }
        }
        XCTAssertEqual(MGAnnotationLayout.lines(cjk).map { $0.unicodeScalars.count }, [30, 30])
        XCTAssertTrue(MGAnnotationLayout.lines(combining)[0].hasSuffix("…"))
        XCTAssertTrue(MGAnnotationLayout.lines(String(repeating: "x", count: 100)).allSatisfy { $0.hasSuffix("…") })
    }

    // MARK: Refusal state, snapshots, golden, bounds, determinism

    func testRefusedStreamedPoseChangesNothing() {
        // REFUSAL_STATE.
        var s = MGExplainerSession(pacing: .immediate, clock: MGManualClock())
        _ = s.feed(XFix.header() + "\n" + #"{"solid":{"v":2,"parts":\#(Self.moving)}}"# + "\n" + #"{"say":"First."}"# + "\n"
                   + #"{"view":{"pose":{"base":{"rot":[1,0,0,30]}}}}"# + "\n" + #"{"say":"Invalid."}"# + "\n")
        let solid = s.solid, view = s.presented, legend = s.legend
        let events = s.feed(#"{"view":{"pose":{"shaft":{"with":{"bad":4}}}}}"# + "\n")
        XCTAssertEqual(XFix.reasons(events), ["view.pose.key"])
        XCTAssertEqual(XFix.refusals(events).first?.id, "shaft")
        XCTAssertEqual(s.solid, solid); XCTAssertEqual(s.presented, view); XCTAssertEqual(s.legend, legend)
    }

    func testSnapshotTamperAndPosedStructure() throws {
        // SNAPSHOT_TAMPER: a saved view with a bad rot is refused on restore.
        let s = try session(#"{"v":1,"kind":"explainer","solid":{"v":2,"parts":\#(Self.moving)},"beats":[{"say":"Hidden.","view":{"hide":["shaft"]}}]}"#)
        guard case .object(var saved) = s.snapshot(), case .array(var beats)? = saved["beats"], case .object(var beat) = beats[0] else { return XCTFail("snapshot") }
        beat["view"] = .string(#"{"pose":{"base":{"rot":[1,0,0,400]}}}"#)
        beats[0] = .object(beat); saved["beats"] = .array(beats)
        guard case .failure(let e) = MGExplainerSession.restore(.object(saved), pacing: .immediate) else { return XCTFail("restored") }
        XCTAssertEqual(e.reason, "step.pose.key")
        // SNAPSHOT_POSED_STRUCTURE.
        let d = try doc(Self.dimDoc(rot: "[0,0,1,90]", step2: ""))
        let snap = MGSolidSnapshot.make(d, step: 1, params: d.poseParameters(step: 1))
        var o = try XCTUnwrap(JSONSerialization.jsonObject(with: snap.jsonData()) as? [String: Any])
        func decodes() -> Bool { (try? MGSolidSnapshot.decode(data: JSONSerialization.data(withJSONObject: o))) != nil }
        o["posed"] = ["arm"]; XCTAssertTrue(decodes())
        o["posed"] = ["arm", "arm"]; XCTAssertFalse(decodes())
        o["posed"] = ["unknown"]; XCTAssertFalse(decodes())
    }

    func testWinchGoldenAndShorterLiftArrow() throws {
        // WINCH_GOLDEN: the golden check output has the new placements; the drawn lift arrow is shorter than its
        // model-size length.
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let d = try MGSolidParser.document(data: Data(contentsOf: root.appendingPathComponent("Examples/Solid3D/Sources/MartySolid3D/Models/annotated-winch.json")), profile: .strict).get()
        let golden = XFix.json(try String(contentsOf: root.appendingPathComponent("Examples/Solid3D/Tests/MartySolidCLITests/Golden/models-annotated-winch.strict.json"), encoding: .utf8))
        XCTAssertEqual(d.annotationPlacements, golden["placements"])
        let arrow = try XCTUnwrap(d.annotations.arrow("aLift"))
        let pieces = MGSolidAnnotations.primitives(d, "aLift", params: d.poseParameters(step: 4), step: 4)
        let drawn = (pieces[1].end - pieces[0].start).length
        XCTAssertEqual(try XCTUnwrap(arrow.length), 40.0127, accuracy: 1e-3)
        XCTAssertEqual(drawn, 21.9253, accuracy: 1e-3)
    }

    func testStoryFrameBound() throws {
        // STORY_BOUNDS: sixteen short beats fit; sixteen 9-second beats at 30 fps (4,320 frames) are refused.
        XCTAssertEqual(try MGStoryPlan(captions: Array(repeating: "Short.", count: 16), spins: Array(repeating: 0, count: 16)).frameCount, 1440)
        XCTAssertThrowsError(try MGStoryPlan(captions: Array(repeating: String(repeating: "a", count: 240), count: 16), spins: Array(repeating: 0, count: 16))) {
            XCTAssertEqual(($0 as? MGSolidIssue)?.reason, "story.frames")
        }
    }

    func testBlendAndPosedCameraAreDeterministic() throws {
        // DETERMINISM.
        let d = try doc(#"{"v":2,"kind":"assembly","parts":\#(Self.arm),"steps":[{"say":"Tilt.","pose":{"arm":{"rot":[1,0,0,90]}}}]}"#)
        let blend = MGStoryPlan.placements(d.assembly, from: [:], to: d.steps[0].pose, 0.5)
        XCTAssertEqual(blend, MGStoryPlan.placements(d.assembly, from: [:], to: d.steps[0].pose, 0.5))
        let half = try XCTUnwrap(blend["arm"])
        XCTAssertEqual(half.c1.y, 0.5.squareRoot(), accuracy: 1e-12); XCTAssertEqual(half.c1.z, 0.5.squareRoot(), accuracy: 1e-12)
        let shot = try XCTUnwrap(MGSolidShot.step(d, 0))
        let a = MGSolidFraming.camera(d, shot: shot, aspect: 1.6, titleBand: 0.14, captionBand: 0.15)
        XCTAssertEqual(a, MGSolidFraming.camera(d, shot: shot, aspect: 1.6, titleBand: 0.14, captionBand: 0.15))
        XCTAssertEqual(a, MGSolidFraming.camera(try doc(#"{"v":2,"kind":"assembly","parts":\#(Self.arm),"steps":[{"say":"Tilt.","pose":{"arm":{"rot":[1,0,0,90]}}}]}"#),
                                                shot: shot, aspect: 1.6, titleBand: 0.14, captionBand: 0.15))
    }
}
