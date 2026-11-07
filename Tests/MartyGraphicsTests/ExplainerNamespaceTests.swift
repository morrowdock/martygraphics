// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import MartyGraphics

/// One stable-id namespace across 2D items, 2D controls and 3D parts (spec PR 3b, tests N1–N13).
final class ExplainerNamespaceTests: ExplainerTestCase {
    static func board(_ id: String) -> String { #"{"v":1,"items":[{"id":"\#(id)","k":"text","at":[1,1],"text":"A label"}]}"# }
    static func solid(_ id: String) -> String { #"{"v":2,"parts":[{"id":"\#(id)","shape":{"box":{"size":[4,4,4]}}}]}"# }
    static let stage = #"{"v":2,"parts":[{"id":"stage","use":"spurPair"}]}"#
    static let planets = #"{"v":2,"parts":[{"id":"planet","at":[20,0,0],"shape":{"box":{"size":[4,4,4]}},"repeat":{"count":3}}]}"#

    /// Both statement orders: the second view statement is refused, and it changes nothing.
    func assertCollision(board: String, solid: String, _ reason: String, file: StaticString = #filePath, line: UInt = #line) {
        let (a, ea) = XFix.stream([XFix.header(), #"{"board":\#(board)}"#, #"{"solid":\#(solid)}"#], end: false)
        XCTAssertEqual(XFix.refusals(ea).map(\.reason), [reason], file: file, line: line)
        XCTAssertEqual(XFix.refusals(ea).first?.statement, 2, file: file, line: line)
        XCTAssertNil(a.solid, "the refused solid changed nothing", file: file, line: line)
        XCTAssertTrue(a.ids.solid.isEmpty, file: file, line: line)
        let (b, eb) = XFix.stream([XFix.header(), #"{"solid":\#(solid)}"#, #"{"board":\#(board)}"#], end: false)
        XCTAssertEqual(XFix.refusals(eb).map(\.reason), [reason], file: file, line: line)
        XCTAssertNil(b.board, file: file, line: line)
        XCTAssertNil(b.state, "the refused board changed nothing", file: file, line: line)
        XCTAssertEqual(XFix.refusal(XFix.doc(board: board, solid: solid, beats: #"[{"say":"Hi."}]"#))?.reason, reason, file: file, line: line)
    }

    // N1–N3: a 2D item against a 3D part, a component instance and a `repeat` copy.
    func testN1PartCollision() { assertCollision(board: Self.board("gear"), solid: Self.solid("gear"), "explainer.id.duplicate.gear") }
    func testN2InstanceCollision() { assertCollision(board: Self.board("stage"), solid: Self.stage, "explainer.id.duplicate.stage") }
    func testN3CopyCollision() {
        assertCollision(board: Self.board("planet2"), solid: Self.planets, "explainer.id.duplicate.planet2")
        assertCollision(board: Self.board("planet"), solid: Self.planets, "explainer.id.duplicate.planet")   // the repeat base id
    }

    // N4: an anchor's last segment is not a name of its own.
    func testN4AnchorNames() {
        XCTAssertNil(XFix.refusal(XFix.doc(board: Self.board("output"), solid: Self.stage, beats: #"[{"say":"Hi.","highlight":["output","stage.output"]}]"#)))
    }

    // N5 (SEAM, PR 3a): annotation ids join the namespace once `annotations` merges. Until then the key is an unknown
    // v2 key inside the solid, refused with the assembly's own reason.
    func testN5AnnotationsSeam() {
        let solid = String(Self.solid("box").dropLast()) + #","annotations":{"labels":[{"id":"lab","at":"box","text":"Box"}]}}"#
        XCTAssertEqual(XFix.refusal(XFix.doc(board: Self.board("lab"), solid: solid, beats: #"[{"say":"Hi."}]"#))?.reason, "assembly.unknown.annotations")
    }

    // N6: an `add` op that introduces a 3D id is refused; the state is unchanged.
    func testN6AddIntroducesThreeDID() {
        var s = MGExplainerSession(pacing: .immediate, clock: MGManualClock())
        _ = s.feed([XFix.header(), #"{"board":\#(Self.board("lbl"))}"#, #"{"solid":\#(XFix.wheelGears)}"#, #"{"say":"One."}"#].joined(separator: "\n") + "\n")
        let projected = s.lesson.projected
        let ev = s.feed(#"{"op":"add","item":{"id":"wheel","k":"text","at":[2,2],"text":"W"}}"# + "\n")
        XCTAssertEqual(XFix.reasons(ev), ["explainer.id.duplicate.wheel"])
        XCTAssertEqual(s.lesson.projected, projected)
        // A template build that produces a 3D id is caught by the lesson guard too (params paths, keyframes).
        var direct = s
        XCTAssertEqual(direct.apply([XFix.json(#"{"op":"add","item":{"id":"wheel","k":"text","at":[2,2],"text":"W"}}"#)]).failureIssue?.reason,
                       "explainer.id.duplicate.wheel")
    }

    // N7: a control id may not equal a 2D item id (stricter than a lesson).
    func testN7ControlCollision() {
        let (_, ev) = XFix.stream([XFix.header(), #"{"board":\#(XFix.rotate)}"#,
                                   #"{"op":"bind","control":{"id":"shape","k":"slider","param":"angle","min":0,"max":90,"step":5,"label":"Angle"}}"#])
        XCTAssertEqual(XFix.reasons(ev), ["explainer.id.duplicate.shape"])
        // The same control in a plain lesson is accepted (controls have their own namespace there).
        var lesson = MGLessonSession()
        let lev = lesson.feed(#"{"scene":\#(XFix.rotate)}"# + "\n" + #"{"op":"bind","control":{"id":"shape","k":"slider","param":"angle","min":0,"max":90,"step":5,"label":"Angle"}}"# + "\n")
        XCTAssertTrue(LessonFixture.refusals(lev).isEmpty)
    }

    // N8: three collisions at once give the same first reason every time (ordered lists, never set order).
    func testN8DeterministicFirstCollision() {
        let board = #"{"v":1,"items":[{"id":"cc","k":"text","at":[1,1],"text":"c"},{"id":"aa","k":"text","at":[2,1],"text":"a"},{"id":"bb","k":"text","at":[3,1],"text":"b"}]}"#
        let solid = #"{"v":2,"parts":[{"id":"bb","shape":{"box":{"size":[1,1,1]}}},{"id":"aa","shape":{"box":{"size":[1,1,1]}}},{"id":"cc","shape":{"box":{"size":[1,1,1]}}}]}"#
        for _ in 0..<20 {
            // The arriving view's canonical order decides: the solid's part order, or the board's item order.
            XCTAssertEqual(XFix.refusal(XFix.doc(board: board, solid: solid, beats: #"[{"say":"Hi."}]"#))?.reason, "explainer.id.duplicate.bb")
            let (_, e) = XFix.stream([XFix.header(), #"{"solid":\#(solid)}"#, #"{"board":\#(board)}"#], end: false)
            XCTAssertEqual(XFix.reasons(e), ["explainer.id.duplicate.cc"])
        }
    }

    // N9: a 2D command naming a 3D id.
    func testN9SetOnThreeDID() {
        let (_, ev) = XFix.stream([XFix.header(), #"{"board":\#(Self.board("lbl"))}"#, #"{"solid":\#(XFix.wheelGears)}"#, #"{"say":"One."}"#,
                                   #"{"op":"set","id":"wheel","key":"text","value":"x"}"#, #"{"op":"remove","id":"p"}"#])
        XCTAssertEqual(XFix.reasons(ev), ["explainer.id.view.wheel", "explainer.id.view.p"])
    }

    // N10: note keys name 2D ids only; a note that never matches is a warning that strict refuses.
    func testN10NoteKeys() {
        XCTAssertEqual(XFix.refusal(XFix.doc(notes: #"{"wheel":{"basis":"b"}}"#, board: Self.board("lbl"), solid: XFix.wheelGears,
                                             beats: #"[{"say":"Hi."}]"#))?.reason, "notes.view.wheel")
        let doc = XFix.doc(notes: #"{"ghost":{"basis":"b"}}"#, board: Self.board("lbl"), beats: #"[{"say":"Hi."}]"#)
        let normal = MGExplainerReport.check(data: Data(doc.utf8), engine: nil)
        XCTAssertTrue(normal.ok)
        XCTAssertEqual(normal.json["warnings"]?.arrayValue?.first?["reason"], .string("notes.unused.ghost"))
        let strict = MGExplainerReport.check(data: Data(doc.utf8), profile: .strict, engine: nil)
        XCTAssertFalse(strict.ok)
        XCTAssertEqual(strict.reason, "notes.unused.ghost")
        XCTAssertNotNil(strict.json["beats"], "the full report is printed")
        // A note for an id that an `add` op introduces in a later beat is used.
        let added = XFix.doc(notes: #"{"late":{"unchecked":"rough"}}"#, board: Self.board("lbl"),
                             beats: #"[{"say":"Hi."},{"say":"Now.","ops":[{"op":"add","item":{"id":"late","k":"text","at":[3,3],"text":"about 7"}}]}]"#)
        XCTAssertTrue(MGExplainerReport.check(data: Data(added.utf8), profile: .strict, engine: nil).ok)
    }

    // N11: collisions are checked after `hide`.
    func testN11CollisionAfterHide() {
        let board = #"{"v":1,"template":"rotate2d","params":{"pts":[[2,1],[4,1],[2,3]],"angle":0},"hide":["xaxis"]}"#
        XCTAssertNil(XFix.refusal(XFix.doc(board: board, solid: Self.solid("xaxis"), beats: #"[{"say":"Hi."}]"#)))
        XCTAssertEqual(XFix.refusal(XFix.doc(board: XFix.rotate, solid: Self.solid("xaxis"), beats: #"[{"say":"Hi."}]"#))?.reason,
                       "explainer.id.duplicate.xaxis")
    }

    // N12: a removed 2D id comes back only with the same kind (the lesson rule).
    func testN12RemovedIDKind() {
        let (_, ev) = XFix.stream([XFix.header(), #"{"board":\#(Self.board("lbl"))}"#, #"{"say":"One."}"#,
                                   #"{"op":"add","item":{"id":"m","k":"text","at":[2,2],"text":"m"}}"#, #"{"say":"Two."}"#,
                                   #"{"op":"remove","id":"m"}"#, #"{"say":"Three."}"#,
                                   #"{"op":"add","item":{"id":"m","k":"region","pts":[[1,1],[2,1],[2,2]]}}"#])
        XCTAssertEqual(XFix.reasons(ev), ["lesson.id.kind.m"])
    }

    // N13: an author string inside an explainer-owned reason is one bounded segment.
    func testN13ReasonSanitising() {
        let ugly = "a b.c" + String(repeating: "x", count: 200)
        let (_, ev) = XFix.stream([XFix.header(), #"{"board":\#(Self.board("lbl"))}"#, #"{"say":"One."}"#, #"{"highlight":["\#(ugly)"]}"#])
        let r = XFix.reasons(ev).first ?? ""
        XCTAssertTrue(r.hasPrefix("beat.highlight.ref."))
        let seg = String(r.dropFirst("beat.highlight.ref.".count))
        XCTAssertEqual(seg, "a_b_c" + String(repeating: "x", count: 27))
        XCTAssertLessThanOrEqual(seg.count, 32)
        XCTAssertLessThanOrEqual(r.count, 96)
        XCTAssertTrue(r.unicodeScalars.allSatisfy { $0.isASCII && (CharacterSet.alphanumerics.contains($0) || "_.,".unicodeScalars.contains($0)) })
    }
}

extension MGJSON {
    var arrayValue: [MGJSON]? { if case .array(let a) = self { return a }; return nil }
}
