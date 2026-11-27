// SPDX-License-Identifier: Apache-2.0
import XCTest
@testable import MartyGraphics

/// Text alternatives: the `alt` keys of a scene and its steps, the VoiceOver value the native board reads, and the
/// engine-written board description (`MGDescribe`).
final class AltTextTests: XCTestCase {
    private func scene(_ json: String) throws -> MGScene { try MGParser.scene(data: Data(json.utf8)).get() }
    private func graphs() throws -> MGScene { try XCTUnwrap(MGFixtures.all.first { $0.id == "graphs" }?.scene) }

    func testAltTextParsesOnTheSceneAndOnSteps() throws {
        let s = try graphs()
        XCTAssertEqual(s.alt, "A sine curve with the area from 0 to 3.14 shaded, beside a vector field that turns counterclockwise.")
        XCTAssertEqual(s.steps.map { $0.alt != nil }, [true, true, false])
        XCTAssertNil(try scene(MGRegression.items(MGRegression.dot)).alt)
        // Placeholders and the plain-text rules are those of `say`; the limit is the narration limit.
        XCTAssertNil(MGRegression.reason(#"{"v":1,"alt":"# + "\"" + String(repeating: "a", count: MGLimits.say) + "\"" + #","items":[{"id":"dot","k":"body","at":[3,4]}]}"#))
        XCTAssertEqual(MGRegression.reason(#"{"v":1,"alt":"a {b} c","items":[{"id":"dot","k":"body","at":[3,4]}]}"#), "alt.placeholder.b")
        XCTAssertEqual(MGRegression.reason(MGRegression.withDot(#""steps":[{"say":"x","alt":"<i>x</i>"}]"#)), "step.alt")
        XCTAssertEqual(MGRegression.reason(MGRegression.withDot(#""steps":[{"say":"x","alts":"y"}]"#)), "step.unknown.alts")
    }

    func testTheVoiceOverValueReadsNarrationThenAltText() throws {
        let s = try graphs()
        XCTAssertEqual(MGDescribe.accessibilityValue(s, step: 0), s.steps[0].say + " " + (s.steps[0].alt ?? ""))
        // A step without its own text falls back to the scene's.
        XCTAssertEqual(MGDescribe.accessibilityValue(s, step: 2), s.steps[2].say + " " + (s.alt ?? ""))
        // Without alt text and without the opt-in the value is the narration alone, as before.
        let plain = try scene(MGRegression.withDot(#""steps":[{"say":"Look at the dot."}]"#))
        XCTAssertEqual(MGDescribe.accessibilityValue(plain, step: 0), "Look at the dot.")
        XCTAssertEqual(MGDescribe.accessibilityValue(plain, step: 0, describing: true), "Look at the dot. A box.")
        let stepless = try scene(MGRegression.items(MGRegression.dot))
        XCTAssertEqual(MGDescribe.accessibilityValue(stepless, step: 0), "")
        XCTAssertEqual(MGDescribe.accessibilityValue(stepless, step: 0, describing: true), "A box.")
    }

    func testTheEngineDescribesWhatIsDrawn() throws {
        let s = try graphs()
        XCTAssertEqual(MGDescribe.board(s, step: 0),
                       "A graph of y = a*sin(x) labelled “y = a sin x” for x from -3.2 to 3.2 and y from -1.6 to 1.6 with a = 1, "
                       + "shaded from x = 0 to 3.14, marking the point (1.57, 1); a vector field (-y, x) labelled “v = (-y, x)” "
                       + "of 8 by 7 arrows for x from -2 to 2 and y from -2 to 2.")
        // The numbers follow the step's edits.
        XCTAssertTrue(MGDescribe.board(s, step: 1).contains("with a = 1.5, shaded from x = 0 to 3.14, marking the point (1.57, 1.5)"))
        // Concealed items are never described (practice values stay hidden from a screen reader too).
        XCTAssertFalse(MGDescribe.board(s, step: 0, hiding: ["flow"]).contains("vector field"))
        XCTAssertEqual(MGDescribe.board(s, step: 0, hiding: ["wave", "flow"]), "The board is empty.")
    }

    func testDescriptionsOfTheExistingKinds() throws {
        let json = #"""
        {"v":1,"items":[
         {"id":"a","k":"node","at":[3,4],"text":"A"},
         {"id":"b","k":"node","at":[8,4],"text":"B"},
         {"id":"ab","k":"edge","a":"a","b":"b","dir":true,"label":"next"},
         {"id":"note","k":"text","at":[6,7],"text":"Hi"},
         {"id":"t","k":"table","at":[6,2],"cells":[["k","v"],["a",1]],"header":true,"label":"T"},
         {"id":"arr","k":"array","at":[6,5.5],"vals":[3,1,2],"ptrs":[{"i":0,"label":"L"}],"marked":[2]}
        ]}
        """#
        XCTAssertEqual(MGDescribe.board(try scene(json)),
                       "The node “A”; the node “B”; an arrow from “A” to “B” labelled “next”; the text “Hi”; "
                       + "a table of 2 rows and 2 columns labelled “T”: k, v; a, 1; an array of 3 cells: 3, 1, 2, with L at cell 0, marked cells 2.")
        let all = try scene(MGRegression.allKinds)
        let phrases = all.items.map { MGDescribe.item($0, in: all.items) }
        XCTAssertEqual(phrases.count, all.items.count)
        XCTAssertTrue(phrases.allSatisfy { !$0.isEmpty && !$0.contains("missing") }, phrases.joined(separator: " | "))
    }

    func testTemplateStepsKeepAndCheckTheirAltText() throws {
        func template(_ alt: String) -> MGTemplate {
            MGTemplate(name: "demo_alt", summary: "alt text", params: [], make: { _, _ in
                MGTemplateBuild(title: "Alt", items: [MGMake.body("b", MGPoint(3, 3))], steps: [MGStep(say: "One.", alt: alt)])
            })
        }
        let json = MGJSON.object(["v": .number(1), "template": .string("demo_alt"), "params": .object([:])])
        XCTAssertEqual(try MGParser.scene(json: json, extraTemplates: [template("A box.")]).get().steps.first?.alt, "A box.")
        guard case .failure(let e) = MGParser.scene(json: json, extraTemplates: [template("<b>box</b>")]) else {
            return XCTFail("template alt text is checked")
        }
        XCTAssertEqual(e.reason, "template.alt")
    }

    func testThePatchStepsOperationCarriesAltTextAndLessonsKeepTheSceneText() throws {
        let s = try graphs()
        let patch = try MGPatch.parse(data: Data(#"{"v":1,"rev":0,"ops":[{"op":"steps","steps":[{"say":"New.","alt":"A new text alternative."}]}]}"#.utf8)).get()
        let next = try s.applying(patch).get()
        XCTAssertEqual(next.steps.first?.alt, "A new text alternative.")
        XCTAssertEqual(next.alt, s.alt)
        let bad = try MGPatch.parse(data: Data(#"{"v":1,"ops":[{"op":"steps","steps":[{"say":"New.","alt":"see ftp://x"}]}]}"#.utf8)).get()
        guard case .failure(let e) = s.applying(bad) else { return XCTFail("a patch cannot bring in unchecked alt text") }
        XCTAssertEqual(e.reason, "step.alt")
        // A lesson drops the scene's own walkthrough but keeps its text alternative.
        let lesson = MGLessonEngine.lessonScene(s)
        XCTAssertTrue(lesson.steps.isEmpty)
        XCTAssertEqual(lesson.alt, s.alt)
    }
}
