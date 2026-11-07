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
        XCTAssertEqual(Array(ids.prefix(4)), ["p", "w", "lp", "gap"], "annotation claims follow the motion claims")
        XCTAssertEqual(s.claims.first { $0.id == "gap" }?.kind, .annotation)
        XCTAssertEqual(s.describe("gap")?["kind"], .string("dimension"))
        _ = s.lineEnded(0)
        XCTAssertEqual(s.presented.solid?.annotations, ["lp"])
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
