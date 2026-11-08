// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import MartyGraphics

/// The annotation visibility limit keeps its single-token reasons and adds repair fields (`visibility`): the first
/// annotation over the limit, the count, the limit, the cause and the step or beat at fault. In an explainer the limit
/// applies per beat. Other refusals keep their exact report keys.
final class AnnotationVisibilityDetailTests: XCTestCase {
    /// `n` labels on one box (`l1` … `ln`), then `arrows` pointer arrows (`a1` …).
    static func annotations(labels n: Int, arrows: Int = 0) -> String {
        let labels = (0..<n).map { #"{"id":"l\#($0 + 1)","at":"b","text":"Box"}"# }
        let arrowList = (0..<arrows).map { #"{"id":"a\#($0 + 1)","meaning":"pointer","from":{"world":[0,0,60]},"to":"b","text":"Look"}"# }
        var o: [String] = []
        if !labels.isEmpty { o.append(#""labels":[\#(labels.joined(separator: ","))]"#) }
        if !arrowList.isEmpty { o.append(#""arrows":[\#(arrowList.joined(separator: ","))]"#) }
        return "{" + o.joined(separator: ",") + "}"
    }
    static func solid(labels n: Int, arrows: Int = 0) -> String {
        #"{"v":2,"parts":[{"id":"b","shape":{"box":{"size":[20,20,20]}}}],"annotations":\#(annotations(labels: n, arrows: arrows))}"#
    }
    static func assembly(labels n: Int, arrows: Int = 0, steps: String? = nil) -> String {
        let base = #"{"v":2,"kind":"assembly","parts":[{"id":"b","shape":{"box":{"size":[20,20,20]}}}],"annotations":\#(annotations(labels: n, arrows: arrows))"#
        return base + (steps.map { #","steps":\#($0)}"# } ?? "}")
    }

    func report(_ s: String) -> MGJSON { MGSolidReport.check(data: Data(s.utf8), profile: .strict, engine: nil).json }

    func testAssemblyWithoutStepsNamesTheThirteenthAnnotation() {
        let r = report(Self.assembly(labels: 13))
        XCTAssertEqual(r["reason"], .string("annotations.visible"))
        XCTAssertEqual(r["part"], .string("l13"))
        XCTAssertEqual(r["visibility"], .object(["annotation": .string("l13"), "cause": .string("nosteps"), "count": .number(13),
                                                 "limit": .number(12)]))
        // Authored order is labels, then arrows: with 10 labels and 4 arrows the 13th is the third arrow.
        let mixed = report(Self.assembly(labels: 10, arrows: 4))
        XCTAssertEqual(mixed["visibility"]?["annotation"], .string("a3"))
        XCTAssertEqual(mixed["visibility"]?["count"], .number(14))
        // Twelve is fine.
        XCTAssertEqual(report(Self.assembly(labels: 12))["ok"], .bool(true))
    }

    func testStepsWithoutAnnotateAreTheOtherCause() {
        let r = report(Self.assembly(labels: 13, steps: #"[{"say":"One."},{"say":"Two."}]"#))
        XCTAssertEqual(r["reason"], .string("annotations.visible"))
        XCTAssertEqual(r["visibility"]?["cause"], .string("unannotated"))
        // One step with `annotate` makes the document stepped: accepted (the others show none).
        let stepped = report(Self.assembly(labels: 13, steps: #"[{"say":"One.","annotate":["l1","l2","l3","l4","l5","l6","l7","l8","l9","l10","l11","l12"]},{"say":"Two.","annotate":["l13"]}]"#))
        XCTAssertNil(stepped["visibility"])
        XCTAssertEqual(stepped["reason"], .null)
    }

    /// Refusals other than the visibility limit keep their exact keys.
    func testOtherRefusalsKeepTheirKeys() {
        let r = MGSolidReport.check(data: Data(#"{"v":2,"kind":"assembly","parts":[]}"#.utf8), engine: nil).json
        XCTAssertNotEqual(r["reason"], .string("annotations.visible"))
        XCTAssertEqual(Set(r.objectValue?.keys.map { $0 } ?? []), ["ok", "reason", "part", "strict", "file"])
        let ref = report(Self.assembly(labels: 2, steps: #"[{"say":"One.","annotate":["zz"]}]"#))
        XCTAssertEqual(ref["reason"], .string("step.annotate.ref.zz"))
        XCTAssertNil(ref["visibility"])
    }

    /// One step's own list over the limit: `step.annotate.count`, with the step (1-based) in the detail.
    func testOneStepOverTheLimitNamesTheStep() {
        let list = (1...13).map { #""l\#($0)""# }.joined(separator: ",")
        let r = report(Self.assembly(labels: 13, steps: #"[{"say":"One.","annotate":["l1"]},{"say":"Two.","annotate":[\#(list)]}]"#))
        XCTAssertEqual(r["reason"], .string("step.annotate.count"))
        XCTAssertEqual(r["part"], .string("l13"))
        XCTAssertEqual(r["visibility"], .object(["annotation": .string("l13"), "cause": .string("step"), "count": .number(13),
                                                 "limit": .number(12), "step": .number(2)]))
    }

    /// The same first refusal and detail in every run (labels and arrows are walked in authored order).
    func testDetailIsDeterministic() {
        let first = report(Self.assembly(labels: 9, arrows: 6))
        for _ in 0..<5 { XCTAssertEqual(report(Self.assembly(labels: 9, arrows: 6)), first) }
        XCTAssertEqual(first["visibility"]?["annotation"], .string("a4"))
    }

    static func labelList(_ r: ClosedRange<Int>) -> String { r.map { #""l\#($0)""# }.joined(separator: ",") }

    /// In an explainer the limit applies to each beat's own list: 13 or more annotations spread over beats are accepted.
    /// The plain view and a beat without `annotate` show none; each beat shows exactly its list.
    func testExplainerAnnotationsOverTwelveSpreadOverBeatsAreAccepted() throws {
        let beats = #"[{"say":"One.","view":{"annotate":[\#(Self.labelList(1...7))]}},{"say":"Two.","view":{"annotate":[\#(Self.labelList(8...13))]}},{"say":"Three."},{"say":"Four.","view":{"annotate":[\#(Self.labelList(10...20))]}}]"#
        let doc = XFix.doc(solid: Self.solid(labels: 20), beats: beats)
        XCTAssertNil(XFix.refusal(doc))
        let s = try XFix.load(doc)
        let d = try XCTUnwrap(s.solid)
        XCTAssertEqual(d.annotations.ids.count, 20)
        XCTAssertTrue(d.annotations.stepped)
        XCTAssertEqual(d.visibleAnnotations(step: nil), [])
        XCTAssertEqual(s.solidStep(forBeat: 2), nil)                       // beat 3 has no view: the plain view, no annotations
        XCTAssertEqual(d.visibleAnnotations(step: s.solidStep(forBeat: 0)), (1...7).map { "l\($0)" })
        XCTAssertEqual(d.visibleAnnotations(step: s.solidStep(forBeat: 1)), (8...13).map { "l\($0)" })
        XCTAssertEqual(d.visibleAnnotations(step: s.solidStep(forBeat: 3)), (10...20).map { "l\($0)" })
        // A beat with a view but no `annotate` shows none either.
        let noList = XFix.doc(solid: Self.solid(labels: 13), beats: #"[{"say":"One.","view":{"annotate":[\#(Self.labelList(1...12))]}},{"say":"Two.","view":{"orbit":30}}]"#)
        let t = try XFix.load(noList)
        XCTAssertEqual(t.solid?.visibleAnnotations(step: t.solidStep(forBeat: 1)), [])
        // The strict report accepts it when every annotation is shown by some beat, and refuses an unused one as before.
        let ok = MGExplainerReport.check(data: Data(XFix.doc(solid: Self.solid(labels: 13), beats: #"[{"say":"One.","view":{"annotate":[\#(Self.labelList(1...12))]}},{"say":"Two.","view":{"annotate":["l13"]}}]"#).utf8), profile: .strict, engine: nil)
        XCTAssertNil(ok.reason, "\(ok.json)")
        let unused = MGExplainerReport.check(data: Data(noList.utf8), profile: .strict, engine: nil)
        XCTAssertEqual(unused.reason, "annotation.unused.l13")
    }

    /// At most 12 annotations keep the earlier rule, so existing documents do not change: without any `annotate`,
    /// every beat shows all of them.
    func testExplainerWithTwelveOrFewerKeepsTheEarlierRule() throws {
        let s = try XFix.load(XFix.doc(solid: Self.solid(labels: 12), beats: #"[{"say":"One."},{"say":"Two.","view":{"orbit":30}}]"#))
        let d = try XCTUnwrap(s.solid)
        XCTAssertFalse(d.annotations.stepped)
        XCTAssertEqual(d.visibleAnnotations(step: nil).count, 12)
        XCTAssertEqual(d.visibleAnnotations(step: s.solidStep(forBeat: 1)).count, 12)
    }

    /// One beat that lists 13 is refused (`view.annotate.count`); the report names the beat, the 13th id, the count
    /// and the limit.
    func testOneBeatWithThirteenIsRefusedWithTheBeat() {
        let beats = #"[{"say":"One.","view":{"annotate":["l1"]}},{"say":"Two."},{"say":"Three.","view":{"annotate":[\#(Self.labelList(1...13))]}}]"#
        let doc = XFix.doc(solid: Self.solid(labels: 14), beats: beats)
        let issue = XFix.refusal(doc)
        XCTAssertEqual(issue?.reason, "view.annotate.count")
        XCTAssertEqual(issue?.view, .beat)
        XCTAssertEqual(issue?.beat, 2)
        XCTAssertEqual(issue?.id, "l13")
        XCTAssertEqual(issue?.detail, "beat")
        XCTAssertEqual(issue?.visibility, MGAnnotationVisibilityDetail(annotation: "l13", count: 13, limit: 12, cause: .beat, index: 2))
        let r = MGExplainerReport.check(data: Data(doc.utf8), profile: .strict, engine: nil).json
        XCTAssertEqual(r["reason"], .string("view.annotate.count"))
        XCTAssertEqual(r["location"]?["beat"], .number(2))
        XCTAssertEqual(r["visibility"], .object(["annotation": .string("l13"), "cause": .string("beat"), "count": .number(13),
                                                 "limit": .number(12), "beat": .number(3)]))
        // Other explainer refusals have no `visibility`.
        let other = MGExplainerReport.check(data: Data(XFix.doc(solid: XFix.gears, beats: #"[{"say":"Hi.","view":{"annotate":["zz"]}}]"#).utf8),
                                            engine: nil).json
        XCTAssertEqual(other["reason"], .string("view.annotate.ref.zz"))
        XCTAssertNil(other["visibility"])
    }

    /// Author ids are capped at 64 scalars in the detail (they are already tokens of the format's id rule).
    func testDetailIdIsBounded() {
        let v = MGAnnotationVisibilityDetail(annotation: String(repeating: "x", count: 500), count: 13, limit: 12, cause: .noSteps)
        XCTAssertEqual(v.annotation.unicodeScalars.count, 64)
        XCTAssertEqual(MGSolidIssue(visibility: v).reason, "annotations.visible")
        XCTAssertEqual(MGSolidIssue(visibility: v).part, v.annotation)
    }
}
