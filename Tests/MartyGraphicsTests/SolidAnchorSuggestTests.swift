// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import MartyGraphics

/// Anchor suggestions (docs/SOLID-3D.md, "Anchor suggestions"): for an off or hidden label or pointer the check report
/// gives `suggest`, an anchor that passes both anchor rules in every view that shows it, or `suggest: null` with
/// `noSuggest` (why, and what to do instead), plus a one-line `repair`. Synthetic boxes, and copies of the round-2f
/// refused documents (docs/fixtures/round-2f).
final class SolidAnchorSuggestTests: XCTestCase {
    /// A closed 200 mm shell box with a 40 mm core box inside it, and a 40 mm box beside them.
    static let parts = #"{"id": "shell", "shape": {"box": {"size": [200, 200, 200]}}}, {"id": "core", "shape": {"box": {"size": [40, 40, 40]}}}, {"id": "side", "at": [400, 0, 0], "shape": {"box": {"size": [40, 40, 40]}}}"#
    static let cut = #""section": {"normal": [0, -1, 0], "offset": 0, "parts": ["shell"]}"#

    func text(_ annotations: String, steps: String = #"[{"say": "Boxes."}]"#) -> String {
        #"{"v": 2, "kind": "assembly", "parts": [\#(Self.parts)], "annotations": \#(annotations), "steps": \#(steps)}"#
    }
    func report(_ t: String) -> MGSolidReport { MGSolidReport.check(data: Data(t.utf8), profile: .strict, engine: nil) }
    func issues(_ json: MGJSON) -> [[String: MGJSON]] {
        guard case .array(let a)? = json["anchorIssues"] else { return [] }
        return a.compactMap { if case .object(let o) = $0 { return o }; return nil }
    }
    static func object(_ s: String) -> [String: MGJSON] {
        guard let o = try? JSONSerialization.jsonObject(with: Data(s.utf8)), case .object(let m)? = MGJSON(any: o) else { return [:] }
        return m
    }
    static func text(_ v: MGJSON) -> String { v.canonicalString }

    /// Replaces the anchor (`at` or `to`) of every annotation with a suggestion in a copy of the document text.
    static func applying(_ suggestions: [String: MGJSON], to source: String) -> String {
        var doc = object(source)
        let explainer = doc["kind"] == .string("explainer")
        var host: [String: MGJSON] = explainer ? (doc["solid"]?.objectValue ?? [:]) : doc
        guard case .object(var ann)? = host["annotations"] else { return source }
        for (key, anchor) in [("labels", "at"), ("arrows", "to")] {
            guard case .array(let list)? = ann[key] else { continue }
            ann[key] = .array(list.map { e in
                guard case .object(var o) = e, case .string(let id)? = o["id"], let s = suggestions[id] else { return e }
                o[anchor] = s
                return .object(o)
            })
        }
        host["annotations"] = .object(ann)
        if explainer { doc["solid"] = .object(host) } else { doc = host }
        return text(.object(doc))
    }

    func suggestions(_ json: MGJSON) -> [String: MGJSON] {
        var out: [String: MGJSON] = [:]
        for i in issues(json) { if case .string(let id)? = i["id"], let s = i["suggest"], s != .null { out[id] = s } }
        return out
    }

    // MARK: Synthetic

    func testAnOffPartLabelGetsAnAnchorOnItsPartThatPasses() throws {
        let t = text(#"{"labels": [{"id": "l1", "at": {"part": "side", "offset": [0, 0, 200]}, "text": "Side box"}]}"#)
        let r = report(t)
        XCTAssertEqual(r.reason, "annotation.anchor.off.l1")
        guard case .object(let a)? = r.json["anchor"], case .object(let s)? = a["suggest"] else { return XCTFail("no suggest") }
        XCTAssertEqual(s["part"], .string("side"))
        guard case .array(let off)? = s["offset"], off.count == 3 else { return XCTFail("offset") }
        XCTAssertEqual(a["noSuggest"], .null)
        // The authored dot is 200 mm above the centre: the nearest visible point is on the top face.
        if case .number(let z) = off[2] { XCTAssertEqual(z, 20, accuracy: 0.1) } else { XCTFail("z") }
        let fixed = Self.applying(suggestions(r.json), to: t)
        XCTAssertTrue(report(fixed).ok, "\(report(fixed).reason ?? "")")
        // No fix text proposes the part's centre (an inner part's centre is often hidden).
        guard case .string(let fix)? = a["fix"], case .string(let repair)? = a["repair"] else { return XCTFail("fix") }
        XCTAssertFalse(fix.contains("centre"), fix)
        XCTAssertTrue(repair.hasPrefix("Label l1 is 180.0 mm off side"), repair)
        XCTAssertTrue(repair.contains(#"Use anchor {"part": "side", "offset": ["#), repair)
        XCTAssertEqual(r.json["repair"], a["repair"])
    }

    func testAPartFullyInsideAnotherHasNoSuggestionAndSaysWhy() throws {
        let t = text(#"{"labels": [{"id": "l1", "at": {"part": "core", "point": "centre"}, "text": "Core"}]}"#)
        let r = report(t)
        XCTAssertEqual(r.reason, "annotation.anchor.hidden.l1")
        guard case .object(let a)? = r.json["anchor"], case .object(let n)? = a["noSuggest"] else { return XCTFail("no noSuggest") }
        XCTAssertEqual(a["suggest"], .null)
        XCTAssertEqual(n["cause"], .string("part fully hidden in step 1"))
        XCTAssertEqual(n["code"], .string("occluded"))
        XCTAssertEqual(n["step"], .number(1))
        XCTAssertEqual(n["by"], .string("shell"))
        guard case .array(let alt)? = n["alternatives"] else { return XCTFail("alternatives") }
        XCTAssertEqual(alt, [.string("Leave l1 out of step 1's annotate list."), .string("Ghost `shell` in step 1."), .string("Change step 1's camera.")])
        guard case .string(let repair)? = a["repair"] else { return XCTFail("repair") }
        XCTAssertEqual(repair, "Label l1 (step 1) is hidden behind shell. No visible point: part fully hidden in step 1. "
                       + "Leave l1 out of step 1's annotate list, ghost `shell` in step 1, or change step 1's camera.")
        // Ghosting the shell (one of the alternatives) makes the authored anchor pass.
        let ghosted = text(#"{"labels": [{"id": "l1", "at": {"part": "core", "point": "centre"}, "text": "Core"}]}"#,
                           steps: #"[{"say": "Boxes.", "ghost": ["shell"]}]"#)
        XCTAssertTrue(report(ghosted).ok)
    }

    func testThroughACutTheInnerPartGetsAVisibleAnchor() throws {
        // The core's centre is behind its own front face from the camera only when the shell is cut; anchored on the
        // side box's centre seen through nothing, it is fine. Here the dot is placed off the core, behind it.
        let t = text(#"{"labels": [{"id": "l1", "at": {"part": "core", "offset": [0, 90, 0]}, "text": "Core"}]}"#,
                     steps: "[{\"say\": \"Cut open.\", \(Self.cut)}]")
        let r = report(t)
        XCTAssertFalse(r.ok)
        let s = suggestions(r.json)
        XCTAssertNotNil(s["l1"])
        XCTAssertTrue(report(Self.applying(s, to: t)).ok)
    }

    func testOnACutPartTheSuggestionLiesOnTheCutFace() throws {
        // The dot is 50 mm outside the shell's back face (+Y, the kept side): off its part. The view cuts the shell,
        // so the suggestion is on the cut face (y = 0 in the shell's frame).
        let t = text(#"{"labels": [{"id": "l1", "at": {"part": "shell", "offset": [60, 150, 60]}, "text": "Shell"}]}"#,
                     steps: "[{\"say\": \"Cut open.\", \(Self.cut)}]")
        let r = report(t)
        XCTAssertEqual(r.reason, "annotation.anchor.off.l1")
        let d = try XCTUnwrap(MGSolidParser.document(data: Data(t.utf8)).successValue)
        var rep = MGAnnotationAnchorReport()
        rep.issues = d.offPartAnchors
        rep.suggest(d, views: d.stepAnchorViews())
        let sug = try XCTUnwrap(rep.issues.first?.suggestion)
        XCTAssertTrue(sug.onCut)
        let off = try XCTUnwrap(sug.offset)
        XCTAssertGreaterThan(off.y, 0, "on the kept side of the cut face")
        XCTAssertLessThanOrEqual(off.y, MGAnnotationAnchorRules.inset + 0.001, "within inset mm of the cut face")
        XCTAssertTrue(report(Self.applying(suggestions(r.json), to: t)).ok)
    }

    func testAHiddenPartSaysWhichStepHidesIt() throws {
        // A view built in code (the compile refuses a step that hides a part its annotation names).
        let t = text(#"{"labels": [{"id": "l1", "at": {"part": "side", "point": "centre"}, "text": "Side"}]}"#)
        let d = try XCTUnwrap(MGSolidParser.document(data: Data(t.utf8)).successValue)
        var v = d.view(step: 0)
        v.parts["side"]?.hidden = true
        let cam = MGSolidCamera(target: MGVec3(400, 0, 0), yaw: 32, pitch: 28, distance: 600)
        let view = MGAnnotationAnchorView(view: v, params: d.defaults, camera: cam, width: 1280, height: 800, step: 0, beat: nil)
        var rep = d.anchorIssues(view)
        XCTAssertEqual(rep.issues.map(\.cause), [.hidden])
        rep.suggest(d, views: [view])
        let sug = try XCTUnwrap(rep.issues.first?.suggestion)
        XCTAssertNil(sug.offset)
        XCTAssertEqual(sug.cause, .hidden)
        XCTAssertEqual(sug.causeText, "part hidden in step 1")
        XCTAssertEqual(sug.alternatives(id: "l1").first, "Leave l1 out of step 1's annotate list.")
        XCTAssertTrue(rep.issues[0].repair.contains("No visible point: part hidden in step 1."), rep.issues[0].repair)
    }

    func testSuggestionsAreDeterministicAndBounded() throws {
        let t = text(#"{"labels": [{"id": "l1", "at": {"part": "side", "offset": [0, 0, 200]}, "text": "Side"}, {"id": "l2", "at": {"part": "core", "point": "centre"}, "text": "Core"}], "arrows": [{"id": "p1", "meaning": "pointer", "from": {"world": [600, -300, 300]}, "to": {"part": "side", "offset": [0, -300, 0]}, "text": "Here"}]}"#)
        let a = report(t).text, b = report(t).text
        XCTAssertEqual(a, b)
        let r = report(t)
        for i in issues(r.json) {
            guard case .string(let repair)? = i["repair"] else { return XCTFail("repair") }
            XCTAssertLessThanOrEqual(repair.unicodeScalars.count, MGAnnotationAnchorIssue.repairScalars)
            XCTAssertFalse(repair.contains("\n"))
        }
        let pointer = issues(r.json).first { $0["id"] == .string("p1") }
        if case .string(let repair)? = pointer?["repair"] { XCTAssertTrue(repair.contains("Use tip (`to`) {"), repair) } else { XCTFail("pointer") }
        XCTAssertTrue(report(Self.applying(suggestions(r.json), to: t)).issuesFree(except: ["l2"]))
    }

    func testRepairTextIsCutToItsLimit() {
        let long = String(repeating: "word ", count: 200)
        let cut = MGAnnotationAnchorIssue.bounded(long, 50)
        XCTAssertEqual(cut.unicodeScalars.count, 50)
        XCTAssertTrue(cut.hasSuffix("…"))
        XCTAssertEqual(MGAnnotationAnchorIssue.number(-0.0004), "0")
        XCTAssertEqual(MGAnnotationAnchorIssue.number(148.25), "148.25")
        XCTAssertEqual(MGAnnotationAnchorIssue.number(-30), "-30")
    }

    // MARK: Round 2f

    static var fixtures: URL { XFix.root.appendingPathComponent("docs/fixtures/round-2f") }
    static let names = ["opus-1-try-2", "opus-1-try-3", "opus-1-try-4", "opus-2-try-4", "sonnet-2-try-4"]

    /// For each round-2f refused document: every `suggest` the strict check gives, applied to a copy, clears every
    /// anchor issue of that annotation; every annotation without one names a part fully hidden in a beat (dense
    /// re-sampling finds no visible point either). The expected counts are this engine's results.
    func testRound2fSuggestionsClearTheirAnchorIssues() throws {
        // (suggested, of which cleared, annotations with suggest null)
        let expected: [String: (Int, Int, Int)] = ["opus-1-try-2": (7, 7, 5), "opus-1-try-3": (1, 1, 4), "opus-1-try-4": (1, 1, 1),
                                                   "opus-2-try-4": (8, 8, 3), "sonnet-2-try-4": (9, 9, 1)]
        for name in Self.names {
            let source = try String(contentsOf: Self.fixtures.appendingPathComponent("\(name).explainer.json"), encoding: .utf8)
            let before = MGExplainerReport.check(data: Data(source.utf8), profile: .strict, engine: nil)
            XCTAssertFalse(before.ok, name)
            XCTAssertTrue(before.reason?.hasPrefix("annotation.anchor.") ?? false, name)
            let all = issues(before.json)
            let offOrHidden = all.filter { if case .string(let r)? = $0["reason"] { return !r.hasPrefix("annotation.anchor.untested.") }; return false }
            var none = Set<String>()
            for i in offOrHidden {
                guard case .string(let id)? = i["id"] else { continue }
                // Each such issue has a suggestion or says why not; never both, never neither.
                XCTAssertTrue((i["suggest"] != .null) != (i["noSuggest"] != .null), "\(name) \(id)")
                if i["suggest"] == .null {
                    none.insert(id)
                    guard case .object(let n)? = i["noSuggest"], case .string(let cause)? = n["cause"] else { XCTFail("\(name) \(id): noSuggest"); continue }
                    XCTAssertTrue(cause.hasPrefix("part fully hidden in beat "), "\(name) \(id): \(cause)")
                }
            }
            let s = suggestions(before.json)
            let after = MGExplainerReport.check(data: Data(Self.applying(s, to: source).utf8), profile: .strict, engine: nil, suggest: false)
            let left = Set(issues(after.json).compactMap { i -> String? in if case .string(let id)? = i["id"] { return id }; return nil })
            let cleared = s.keys.filter { !left.contains($0) }
            XCTAssertEqual(cleared.count, s.count, "\(name): applying suggest leaves \(s.keys.filter { left.contains($0) }.sorted())")
            XCTAssertEqual(left, none, "\(name): only the annotations without a suggestion keep issues")
            if let e = expected[name] { XCTAssertEqual([s.count, cleared.count, none.count], [e.0, e.1, e.2], name) }
        }
    }

    /// A suggestion is null only when the search finds no visible point: 4 times the samples find none either. (A denser
    /// first search found one for `lDiff` here; the second, denser pass now finds it too.)
    func testRound2fNullSuggestionsHoldWithDenseSampling() throws {
        let source = try String(contentsOf: Self.fixtures.appendingPathComponent("opus-1-try-3.explainer.json"), encoding: .utf8)
        let doc = try XCTUnwrap(MGExplainer.parse(data: Data(source.utf8)).successValue)
        let framed = MGExplainerFrame.beatAnchorViews(doc)
        let d = try XCTUnwrap(framed.solid)
        var rep = MGAnnotationAnchorReport()
        for v in framed.views { rep.append(d.anchorIssues(v)) }
        let plain = d.anchorSuggestions(for: rep.issues, views: framed.views)
        let nulls = plain.keys.filter { plain[$0]?.offset == nil }.sorted()
        XCTAssertEqual(nulls, ["lComb", "lExample", "lImp", "lTurb"])
        XCTAssertNotNil(plain["lDiff"]?.offset)
        let dense = d.anchorSuggestions(for: rep.issues.filter { nulls.contains($0.id) }, views: framed.views, scale: 4)
        for id in nulls {
            XCTAssertNil(dense[id]?.offset, "\(id): a visible point exists")
            XCTAssertEqual(dense[id]?.cause, .occluded, id)
        }
    }
}

private extension MGSolidReport {
    /// True when no anchor issue remains other than those of `ids`.
    func issuesFree(except ids: Set<String>) -> Bool {
        guard case .array(let a)? = json["anchorIssues"] else { return true }
        return a.allSatisfy { if case .string(let id)? = $0["id"] { return ids.contains(id) }; return false }
    }
}

private extension Result {
    var successValue: Success? { if case .success(let v) = self { return v }; return nil }
}
