// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import MartyGraphics

/// Backward compatibility (spec PR 3b, tests B1–B7): plain scenes, lessons and assemblies are unchanged.
final class ExplainerCompatTests: ExplainerTestCase {
    var fixtures: [URL] {
        let dir = XFix.root.appendingPathComponent("docs/fixtures/v1")
        return ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasSuffix(".scene.json") }.sorted { $0.path < $1.path }
    }

    // B1: without the environment the parser gives byte-identical results and reasons for every scene fixture, and an
    // environment without 3D facts changes nothing for scenes without dotted placeholders.
    func testB1ParserWithoutEnvironmentIsUnchanged() throws {
        XCTAssertGreaterThan(fixtures.count, 3)
        for url in fixtures {
            let json = XFix.json(try String(contentsOf: url, encoding: .utf8))
            let plain = MGParser.scene(json: json)
            XCTAssertEqual(plain, MGParser.scene(json: json, extraTemplates: [], env: nil), url.lastPathComponent)
            if case .success(let a) = plain, case .success(let b) = MGParser.scene(json: json, extraTemplates: [], env: MGParseEnvironment()) {
                XCTAssertEqual(a.items, b.items, url.lastPathComponent)
            }
        }
        // A plain parser refuses an explainer with its existing reason; so does the solid parser.
        let doc = XFix.json(try XFix.example("gears-mixed"))
        XCTAssertEqual(MGParser.scene(json: doc).failureIssue?.reason, "scene.unknown.beats,board,kind,solid")
        XCTAssertTrue(MGSolidParser.document(json: doc).failureIssue?.reason.hasPrefix("assembly.") ?? false)
        // A dotted placeholder outside an explainer keeps its old reason.
        let dotted = XFix.json(#"{"v":1,"items":[{"id":"l","k":"text","at":[1,1],"text":"{p.teeth}"}]}"#)
        XCTAssertEqual(MGParser.scene(json: dotted).failureIssue?.reason, "text.text.placeholder")
    }

    // B2: a lesson session is unchanged: no explainer environment, the D3 rule on, its event history as before.
    func testB2LessonsUnchanged() throws {
        var s = MGLessonSession()
        _ = s.load(try LessonFixture.lesson())
        XCTAssertNil(s.env)
        XCTAssertFalse(s.boardless)
        XCTAssertTrue(s.closeRefusals.isEmpty)
        var t = MGLessonSession()
        let ev = t.feed(try LessonFixture.stream())
        XCTAssertEqual(LessonFixture.beatEvents(ev).map(\.name), LessonFixture.beatEvents(s.events).map(\.name))
        var u = MGLessonSession()
        XCTAssertEqual(LessonFixture.refusals(u.feed(#"{"scene":{"v":1,"items":[{"id":"l","k":"text","at":[1,1],"text":"1.5 m"}]}}"# + "\n")).map(\.reason), ["text.literal"])
    }

    // B3: assembly v1 documents keep their meaning; v2-only keys stay refused in v1.
    func testB3AssemblyV1() throws {
        for name in ["planetary", "planetary-components", "propeller", "slider-crank", "slider-crank-component"] {
            XCTAssertNoThrow(try MGSolidParser.document(json: try XFix.model(name)).get(), name)
        }
        XCTAssertEqual(XFix.refusal(XFix.doc(solid: #"{"v":1,"kind":"assembly","parts":[{"id":"a","shape":{"box":{"size":[1,1,1]}}}]}"#, beats: #"[{"say":"Hi."}]"#))?.reason,
                       "explainer.solid.version")
    }

    // B4: the embedded solid compiles to the same facts, claims and legend as the assembly on its own.
    func testB4EmbeddedSolidUnchanged() throws {
        var assembly = try XFix.model("horizontal-reduction").objectValue!
        assembly.removeValue(forKey: "steps"); assembly.removeValue(forKey: "title")
        let alone = try MGSolidParser.document(json: .object(assembly)).get()
        let s = try XFix.load(XFix.doc(solid: MGJSON.object(assembly).canonicalString, beats: #"[{"say":"Hi."}]"#))
        XCTAssertEqual(s.solid?.facts, alone.facts)
        XCTAssertEqual(s.solid?.claims, alone.claims)
        XCTAssertEqual(s.solid?.readBack, alone.readBack)
        XCTAssertEqual(MGSolidRenderPlan.snapshot(try XCTUnwrap(s.solid)).encodedForTest, MGSolidRenderPlan.snapshot(alone).encodedForTest)
    }

    // B5: the rotation lesson as an explainer gives the same final 2D state.
    func testB5LessonToExplainer() throws {
        var lesson = MGLessonSession()
        _ = lesson.load(try LessonFixture.lesson())
        _ = lesson.finishNow()
        let doc = XFix.json(try String(contentsOf: XFix.root.appendingPathComponent("docs/fixtures/v1/rotation.lesson.json"), encoding: .utf8))
        let converted = try XCTUnwrap(MGExplainer.fromLesson(doc))
        let s = try XFix.load(converted.canonicalString)
        XCTAssertEqual(s.state?.scene.source, lesson.state?.scene.source)
        XCTAssertEqual(s.state?.scene.items, lesson.state?.scene.items)
        XCTAssertEqual(s.state?.controls, lesson.state?.controls)
        XCTAssertEqual(s.captions.keys.sorted().map { s.captions[$0]! }, LessonFixture.lineDue(lesson.events))
    }

    // B6: an assembly with steps as an explainer shows the same view in every beat (cuts, ghosts, explode, camera).
    func testB6AssemblyToExplainerViews() throws {
        let assembly = try XFix.model("idler-gearbox")
        let doc = try MGSolidParser.document(json: assembly).get()
        let converted = try XCTUnwrap(MGExplainer.fromAssembly(assembly))
        var s = MGExplainerSession(pacing: .speech, clock: MGManualClock())
        _ = s.load(try MGExplainer.parse(json: converted).get())
        for (i, step) in doc.steps.enumerated() {
            XCTAssertEqual(s.presented.beat, i)
            XCTAssertEqual(s.presented.solid, doc.view(step: i), "beat \(i)")
            XCTAssertEqual(s.presented.step?.explode, step.explode)
            XCTAssertEqual(s.presented.step?.camera ?? nil, step.camera)
            XCTAssertEqual(s.presented.step?.spin ?? 0, step.spin)
            XCTAssertEqual(s.presented.solidHighlight, step.highlight)
            _ = s.lineEnded(i)
        }
    }

    // B7: snapshot /1 decoding is untouched by this PR (no annotation fields exist yet).
    func testB7SnapshotV1() throws {
        let doc = try MGSolidParser.document(json: try XFix.model("planetary")).get()
        let data = try MGSolidRenderPlan.snapshot(doc).jsonData()
        XCTAssertNoThrow(try MGSolidSnapshot.decode(data: data))
    }
}

extension MGSolidSnapshot {
    var encodedForTest: Data? { try? jsonData() }
}
