// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import MartyGraphics

/// `MGTranscript` (docs/EXPLAINER.md, "Transcript"): the words of a checked document per beat, in the course transcript
/// format. The CLI tests hold the golden files of the shipped explainers; these pin the pieces they do not show.
final class ExplainerTranscriptTests: XCTestCase {
    static let fruit = #"""
    {"v":1,"kind":"explainer","title":"Fruit colours","notes":{"t":{"unchecked":"Example values"}},
     "board":{"v":1,"items":[{"id":"t","k":"table","at":[6,4],"cells":[["apple","red"],["lime","green"]]}]},
     "beats":[{"say":"An apple is red.","highlight":["t"]},
              {"say":"Most bags hold about 6 apples.","unchecked":"Example count"}]}
    """#

    func object(_ text: String) throws -> NSDictionary {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? NSDictionary)
    }

    /// A caption's `unchecked` reason is `captionNote`; a table without `header` has an empty header and every row as
    /// data; a table's `unchecked` note is `note` (a `basis` note would be `source`); a board-only beat shows no
    /// annotation.
    func testCaptionNoteAndATableWithoutHeader() throws {
        let t = MGTranscript.make(data: Data(Self.fruit.utf8), file: "fruit.json")
        XCTAssertTrue(t.ok, t.text)
        XCTAssertEqual(t.exitCode, 0)
        let want = #"""
        {"format":"morrowdock-explainer-transcript","version":1,"explainer":"fruit.json","title":"Fruit colours",
         "about":"Every caption, every on-screen label and arrow text, and the table rows, as plain text. Generated from the explainer JSON; the words are the document's own.",
         "beats":[
          {"beat":1,"caption":"An apple is red.","onScreen":[],"highlight":["t"],
           "tables":{"t":{"header":[],"rows":[["apple","red"],["lime","green"]],"note":"Example values"}}},
          {"beat":2,"caption":"Most bags hold about 6 apples.","captionNote":"Example count","onScreen":[],"highlight":[],
           "tables":{"t":{"header":[],"rows":[["apple","red"],["lime","green"]],"note":"Example values"}}}]}
        """#
        XCTAssertEqual(try object(t.text), try object(want))
        // The same bytes every time.
        XCTAssertEqual(MGTranscript.make(data: Data(Self.fruit.utf8), file: "fruit.json").text, t.text)
    }

    /// A refused document gives no transcript: `json` is the document's check report with the same profile.
    func testARefusedDocumentGivesItsCheckReport() throws {
        let typed = Data(#"{"v":1,"kind":"explainer","title":"T","board":{"v":1,"items":[]},"beats":[{"say":"It weighs 5 kg."}]}"#.utf8)
        let t = MGTranscript.make(data: typed, file: "typed.json")
        XCTAssertFalse(t.ok)
        XCTAssertEqual(t.exitCode, 1)
        XCTAssertEqual(t.json, MGExplainerReport.check(data: typed).json)
        let idle = Data(#"{"v":2,"kind":"assembly","parts":[{"id":"disc","shape":{"shaft":{"radius":20,"length":5}},"joint":{"revolute":[0,0,1]}}],"steps":[{"say":"A disc on a joint."}]}"#.utf8)
        XCTAssertTrue(MGTranscript.make(data: idle, file: "idle.json").ok)
        let strict = MGTranscript.make(data: idle, file: "idle.json", profile: .strict)
        XCTAssertFalse(strict.ok)
        XCTAssertEqual(strict.json, MGSolidReport.check(data: idle, profile: .strict).json)
    }

    /// An assembly's steps are the beats: the filled caption, the step's highlight, no tables.
    func testAnAssemblyStepIsABeat() throws {
        let idle = Data(#"{"v":2,"kind":"assembly","title":"Disc","parts":[{"id":"disc","shape":{"shaft":{"radius":20,"length":5}},"joint":{"revolute":[0,0,1]},"drive":{"input":1}}],"steps":[{"say":"A disc on a joint.","highlight":["disc"]},{"say":"It turns.","spin":1}]}"#.utf8)
        let t = MGTranscript.make(data: idle, file: "disc.json")
        XCTAssertTrue(t.ok, t.text)
        let beats = try XCTUnwrap(try object(t.text)["beats"] as? [NSDictionary])
        XCTAssertEqual(beats.count, 2)
        XCTAssertEqual(beats[0]["caption"] as? String, "A disc on a joint.")
        XCTAssertEqual(beats[0]["highlight"] as? [String], ["disc"])
        XCTAssertEqual(beats[1]["beat"] as? Int, 2)
        XCTAssertEqual(beats[1]["tables"] as? NSDictionary, NSDictionary())
        XCTAssertNil(beats[1]["captionNote"])
    }
}
