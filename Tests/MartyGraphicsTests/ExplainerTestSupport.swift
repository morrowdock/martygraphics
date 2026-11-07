// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import MartyGraphics

/// Shared fixtures for the explainer tests (spec PR 3b, tests X, N, T, S, B, D). Beats are 0-based in the API and
/// 1-based in reasons.
enum XFix {
    static var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }
    static func example(_ name: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent("Examples/Explainers/\(name).explainer.json"), encoding: .utf8)
    }
    static func model(_ name: String) throws -> MGJSON {
        json(try String(contentsOf: root.appendingPathComponent("Examples/Solid3D/Sources/MartySolid3D/Models/\(name).json"), encoding: .utf8))
    }

    /// Two meshing gears: `p` (15 teeth, driven) and `w` (30 teeth) 45 mm apart. `w.speed` = −1/2.
    static let gears = #"{"v":2,"parts":[{"id":"p","shape":{"gear":{"teeth":15,"module":2,"width":8}},"joint":{"revolute":[0,0,1]},"drive":{"input":1}},{"id":"w","at":[45,0,0],"shape":{"gear":{"teeth":30,"module":2,"width":8}},"joint":{"revolute":[0,0,1]}}],"constraints":[{"gearMesh":{"a":"p","b":"w"}}]}"#
    /// The same with the driven gear named `wheel`.
    static let wheelGears = gears.replacingOccurrences(of: #""w""#, with: #""wheel""#)
    /// A 2D table `t` with 5 rows (header + 4) and typed numbers.
    static func table(_ id: String = "t", cells: String = #"[["Planet","km"],["Mercury",4879],["Venus",12104],["Earth",12756],["Mars",6792]]"#) -> String {
        #"{"v":1,"items":[{"id":"\#(id)","k":"table","at":[6,4],"header":true,"cells":\#(cells)}]}"#
    }
    static let rotate = #"{"v":1,"template":"rotate2d","params":{"pts":[[2,1],[4,1],[2,3]],"angle":0}}"#

    static func json(_ s: String) -> MGJSON { MGJSON(any: try! JSONSerialization.jsonObject(with: Data(s.utf8)))! }

    /// A document from its parts.
    static func doc(title: String? = nil, notes: String? = nil, board: String? = nil, solid: String? = nil, beats: String,
                    extra: String = "") -> String {
        var parts = [#""v":1"#, #""kind":"explainer""#]
        if let title { parts.append(#""title":"\#(title)""#) }
        if let notes { parts.append(#""notes":\#(notes)"#) }
        if let board { parts.append(#""board":\#(board)"#) }
        if let solid { parts.append(#""solid":\#(solid)"#) }
        parts.append(#""beats":\#(beats)"#)
        if !extra.isEmpty { parts.append(extra) }
        return "{" + parts.joined(separator: ",") + "}"
    }

    /// Parse + load; the first refusal, or nil when accepted.
    static func refusal(_ s: String, library: MGSolidLibrary = .builtIn) -> MGExplainerIssue? {
        switch MGExplainer.parse(data: Data(s.utf8)) {
        case .failure(let i): return i
        case .success(let d):
            var session = MGExplainerSession(pacing: .immediate, clock: MGManualClock(), library: library)
            if case .failure(let i) = session.load(d) { return i }
            return nil
        }
    }

    static func load(_ s: String, pacing: MGPacing = .immediate, clock: MGManualClock = MGManualClock(),
                     file: StaticString = #filePath, line: UInt = #line) throws -> MGExplainerSession {
        let d: MGExplainer
        switch MGExplainer.parse(data: Data(s.utf8)) {
        case .failure(let i): XCTFail("parse: \(i)", file: file, line: line); throw i
        case .success(let x): d = x
        }
        var session = MGExplainerSession(pacing: pacing, clock: clock)
        if case .failure(let i) = session.load(d) { XCTFail("load: \(i)", file: file, line: line); throw i }
        if pacing == .immediate { session.finishNow() }
        return session
    }

    /// Feeds statements one per line (plus `endStream()` unless `end` is false).
    static func stream(_ lines: [String], pacing: MGPacing = .immediate, clock: MGManualClock = MGManualClock(), end: Bool = true) -> (MGExplainerSession, [MGExplainerEvent]) {
        var s = MGExplainerSession(pacing: pacing, clock: clock)
        var events: [MGExplainerEvent] = []
        for l in lines { events += s.feed(l + "\n") }
        if end { events += s.endStream() }
        return (s, events)
    }

    static func refusals(_ events: [MGExplainerEvent]) -> [MGExplainerIssue] {
        events.compactMap { if case .refused(let i) = $0 { return i } else { return nil } }
    }
    static func reasons(_ events: [MGExplainerEvent]) -> [String] { refusals(events).map(\.reason) }
    static func lineDue(_ events: [MGExplainerEvent]) -> [String] {
        events.compactMap { if case .lineDue(_, let t, _) = $0 { return t } else { return nil } }
    }
    static func header(_ extra: String = "") -> String { #"{"explainer":{"v":1\#(extra)}}"# }
}

/// Registers the opt-in geometry pack (`rotate2d`) per test and drops it afterwards.
class ExplainerTestCase: XCTestCase {
    override func setUp() { super.setUp(); try? MGPacks.register(MGGeometryPack.pack) }
    override func tearDown() { MGPacks.resetRegistered(); super.tearDown() }
}
