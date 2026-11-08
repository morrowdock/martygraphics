// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import MartyGraphics

/// 3D annotations (open-vocabulary PR 3a) inside explainers: one namespace, one legend, `annotate` views, the pose
/// rule for shown text, the report and the one gate in the host.
final class ExplainerAnnotationTests: ExplainerTestCase {
    static func gears(_ annotations: String) -> String { String(XFix.gears.dropLast()) + #","annotations":\#(annotations)}"# }
    static let annotated = gears(#"{"labels":[{"id":"lp","at":"p","text":"Small: {p.teeth} teeth"}],"dimensions":[{"id":"gap","a":"p","b":"w"}]}"#)
    static var mixed: String {
        XFix.doc(board: XFix.table(cells: #"[["gear","teeth"],["small","{p.teeth}"],["big","{w.teeth}"]]"#), solid: annotated,
                 beats: #"[{"say":"The centres are {dim.gap} apart.","view":{"annotate":["gap"]},"highlight":["gap","t.r1"]},{"say":"The small gear has {p.teeth} teeth.","view":{"annotate":["lp"],"spin":1}}]"#)
    }

    // A mixed explainer with a label and a dimension: ids, claims, captions, highlight, describe and the report.
    func testMixedExplainerWithALabelAndADimension() throws {
        var s = MGExplainerSession(pacing: .speech, clock: MGManualClock())
        _ = try s.load(MGExplainer.parse(data: Data(Self.mixed.utf8)).get()).get()
        XCTAssertEqual(s.caption, "The centres are 45 mm apart.")
        XCTAssertEqual(s.ids.solid.suffix(2), ["lp", "gap"], "annotation ids join the namespace after the parts and anchors")
        XCTAssertEqual(s.presented.annotations, ["gap"])
        XCTAssertEqual(s.presented.tableRows, ["t": [1]])
        XCTAssertEqual(s.presented.solid?.annotations, ["gap"], "the beat's `annotate` list")
        XCTAssertEqual(s.solid?.checkedAnnotations(try XCTUnwrap(s.presented.solid), params: s.solid!.defaults), ["gap"])
        let ids = s.claims.map(\.id)
        // The beats choose their labels, so an annotation claims once a presented beat displayed it: beat 1 shows `gap`.
        XCTAssertEqual(Array(ids.prefix(3)), ["p", "w", "gap"], "annotation claims follow the motion claims")
        XCTAssertFalse(ids.contains("lp"), "beat 2's label is not displayed yet")
        XCTAssertEqual(s.claims.first { $0.id == "gap" }?.kind, .annotation)
        XCTAssertEqual(s.describe("gap")?["kind"], .string("dimension"))
        _ = s.lineEnded(0)
        XCTAssertEqual(s.presented.solid?.annotations, ["lp"])
        XCTAssertEqual(Array(s.claims.map(\.id).prefix(4)), ["p", "w", "lp", "gap"], "both displayed now, in authored order")
        let r = MGExplainerReport.check(data: Data(Self.mixed.utf8), profile: .strict, engine: nil)
        XCTAssertTrue(r.ok, r.reason ?? "")
        XCTAssertEqual(r.json["ids"]?["annotations"], .array([.string("lp"), .string("gap")]))
        XCTAssertEqual(r.json["annotations"]?.arrayValue?.count, 2)
        XCTAssertEqual(r.json["beats"]?.arrayValue?.first?["highlight"]?["annotations"], .array([.string("gap")]))
    }

    // #31's rules apply unchanged: `annotate` references, the strict unused-annotation warning, and the pose rule for a
    // caption that shows a dimension fact its spinning view does not keep constant.
    func testAssemblyRulesApplyInsideExplainers() {
        let doc = { (beats: String) in XFix.doc(solid: Self.annotated, beats: beats) }
        XCTAssertEqual(XFix.refusal(doc(#"[{"say":"Hi.","view":{"annotate":["nope"]}}]"#))?.reason, "view.annotate.ref.nope")
        XCTAssertEqual(MGExplainerReport.check(data: Data(doc(#"[{"say":"Hi.","view":{"annotate":["gap"]}}]"#).utf8), profile: .strict, engine: nil).reason,
                       "annotation.unused.lp")
        // An anchor off the turning axis: the distance changes while the beat spins, so its caption may not show it.
        let moving = Self.gears(#"{"dimensions":[{"id":"far","a":"p","b":{"part":"w","offset":[20,0,0]}}]}"#)
        // (The dimension itself shows only in the still beat; a shown moving dimension is the assembly's own
        // `annotation.pose.<id>`.)
        let views = #"{"say":"Look.","view":{"annotate":["far"]}}"#
        XCTAssertEqual(XFix.refusal(XFix.doc(solid: moving, beats: #"[\#(views),{"say":"Now {dim.far}.","view":{"spin":1,"annotate":[]}}]"#))?.reason,
                       "text.pose.beat.2")
        XCTAssertNil(XFix.refusal(XFix.doc(solid: moving, beats: #"[\#(views),{"say":"Now {dim.far}.","view":{"annotate":[]}}]"#)),
                     "a still view shows the pose it measured")
        XCTAssertEqual(XFix.refusal(XFix.doc(board: XFix.table(cells: #"[["{dim.far}"]]"#), solid: moving,
                                             beats: #"[\#(views),{"say":"Turn.","view":{"spin":1,"annotate":[]}}]"#))?.reason, "text.pose.board")
        XCTAssertEqual(XFix.refusal(XFix.doc(solid: moving, beats: #"[{"say":"Look.","view":{"spin":1}}]"#))?.reason, "annotation.pose.far")
    }

    // The host draws annotations only through the one gate: its renderer is loaded from the compiled solid, and the
    // overlay record comes from the frame function at the pose shown.
    @MainActor func testHostUsesTheOneGate() throws {
        let clock = MGManualClock()
        let c = MGExplainerController(pacing: .speech, clock: clock)
        c.begin()
        XCTAssertTrue(c.load(try MGExplainer.parse(data: Data(Self.mixed.utf8)).get()))
        c.setSolidSize(CGSize(width: 800, height: 500))
        let f = try XCTUnwrap(c.annotationFrame)
        XCTAssertNil(f.refusal)
        XCTAssertEqual(f.placement.map(\.id), ["gap"])
        c.lineEnded(0)
        clock.advance(by: .seconds(2)); c.next()
        XCTAssertEqual(c.annotationFrame?.placement.map(\.id), ["lp"], "the second beat's label, at a pose its spin shows")
        XCTAssertNil(c.annotationFrame?.refusal)
    }
}

/// The fifth check: host changes keep the pose rule for 3D dimension facts in board text, and one call with two
/// documents speaks only the shown document's line.
final class ExplainerHostPoseTests: ExplainerTestCase {
    /// A gear pair with a still dimension `gap` (both anchors on turning axes: it holds in every pose) and a moving
    /// one `far` (an anchor off the wheel's axis). Beat 1 shows `far` while still; beat 2 spins and shows none.
    static var doc: String {
        let solid = ExplainerAnnotationTests.gears(#"{"dimensions":[{"id":"gap","a":"p","b":"w"},{"id":"far","a":"p","b":{"part":"w","offset":[20,0,0]}}]}"#)
        let board = #"{"v":1,"template":"rotate2d","params":{"pts":[[2,1],[4,1],[2,3]],"angle":0},"items":[{"id":"ready","k":"text","at":[1,7],"text":"Ready"}]}"#
        return XFix.doc(board: board, solid: solid,
                        beats: #"[{"say":"Look.","view":{"annotate":["far","gap"]}},{"say":"Turn.","view":{"spin":1,"annotate":[]}}]"#)
    }

    func spinning() throws -> MGExplainerSession {
        var s = MGExplainerSession(pacing: .speech, clock: MGManualClock())
        _ = try s.load(MGExplainer.parse(data: Data(Self.doc.utf8)).get()).get()
        _ = s.lineEnded(0)
        XCTAssertEqual(s.presented.step?.spin, 1)
        return s
    }

    // F1: `add`, `set` on an authored item, `set` on a template item (an `over`) and a batch: refused, nothing changes.
    func testHostChangesKeepThePoseRule() throws {
        let refused = [#"{"op":"add","item":{"id":"distance","k":"text","at":[2,3],"text":"Distance {dim.far}."}}"#,
                       #"{"op":"set","id":"ready","key":"text","value":"Distance {dim.far}."}"#,
                       #"{"op":"set","id":"ltheta","key":"text","value":"Far {dim.far}"}"#]
        for c in refused {
            var s = try spinning()
            let state = s.state, claims = s.claims, legend = s.legend, motion = s.motionRemaining, serial = s.lesson.lastChange?.serial
            XCTAssertEqual(s.apply([XFix.json(c)]).failureIssue?.reason, "text.pose.board", c)
            XCTAssertEqual(s.state, state, c); XCTAssertEqual(s.claims, claims, c); XCTAssertEqual(s.legend, legend, c)
            XCTAssertEqual(s.motionRemaining, motion, c); XCTAssertEqual(s.lesson.lastChange?.serial, serial, c)
        }
        // A batch whose second command brings the moving fact in: the whole batch is refused.
        var s = try spinning()
        let state = s.state
        XCTAssertEqual(s.apply([XFix.json(#"{"op":"set","id":"ready","key":"text","value":"Set"}"#), XFix.json(refused[0])]).failureIssue?.reason,
                       "text.pose.board")
        XCTAssertEqual(s.state, state)
        // The control case: a dimension that holds in every pose may show during the spin.
        var ok = try spinning()
        XCTAssertNotNil(try? ok.apply([XFix.json(#"{"op":"add","item":{"id":"g","k":"text","at":[2,3],"text":"Gap {dim.gap}."}}"#)]).get())
        XCTAssertEqual(ok.state?.scene.item("g")?.text, "Gap 45 mm.")
        XCTAssertEqual(ok.claims.first { $0.id == "item.g" }?.tier, .solved)
    }

    // F2: one call with two complete documents speaks only the line of the document the board shows.
    @MainActor func testTwoDocumentsInOneCallSpeakOnlyTheShownOne() throws {
        func stream(_ angle: Int) -> String {
            [XFix.header(), #"{"board":{"v":1,"template":"rotate2d","params":{"pts":[[2,1],[4,1],[2,3]],"angle":\#(angle)}}}"#,
             #"{"say":"Angle {theta}."}"#, #"{"end":true}"#].joined(separator: "\n") + "\n"
        }
        for pacing in [MGPacing.speech, .immediate] {
            let c = MGExplainerController(pacing: pacing, clock: MGManualClock())
            c.begin()
            var spoken: [(String, Double?)] = []
            c.onEvent = { [weak c] e in if case .lineDue(_, let t, _) = e { spoken.append((t, c?.board.scene?.values["theta"]?.value)) } }
            c.feed(stream(90) + stream(180))
            XCTAssertEqual(spoken.map(\.0), ["Angle 180°."], "\(pacing)")
            XCTAssertEqual(spoken.first?.1, 180, "\(pacing)")
            XCTAssertEqual(c.session.caption, "Angle 180°.")
        }
    }
}
