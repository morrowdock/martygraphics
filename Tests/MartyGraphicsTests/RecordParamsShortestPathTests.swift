// SPDX-License-Identifier: Apache-2.0
import XCTest
@testable import MartyGraphics

/// Record-list template parameters and the opt-in `shortest_path` template. Graph results are checked against
/// independent oracles written here (Bellman–Ford distances; route counts by enumerating node sequences), not against the
/// template's own Dijkstra code. Exact narration goldens were derived from a line-by-line Python transcription of the
/// template; they still need a compiled Swift run.
final class RecordParamsShortestPathTests: XCTestCase {
    override func tearDown() { MGPacks.resetRegistered() }

    // MARK: helpers

    static let routerEdges = "[0,1,4],[0,2,1],[2,1,2],[1,3,5],[2,3,8],[2,4,10],[3,4,2],[3,5,6],[4,5,3]"
    /// The same nine links reversed, with every other record's endpoints swapped.
    static let routerEdgesShuffled = "[4,5,3],[5,3,6],[3,4,2],[4,2,10],[2,3,8],[3,1,5],[2,1,2],[2,0,1],[0,1,4]"
    static let routerAt = "[1.5,5],[4.5,7],[4.5,3],[7.5,7],[7.5,3],[10.5,5]"

    func parse(_ json: String) -> Result<MGScene, MGError> {
        MGParser.scene(data: Data(json.utf8), extraTemplates: MGGraphPack.pack.templates)
    }
    func reason(_ json: String) -> String? { if case .failure(let e) = parse(json) { return e.reason }; return nil }
    func scene(n: Int, edges: [[Int]], source: Int = 0, target: Int? = nil, directed: Bool = false, extra: String = "") throws -> MGScene {
        let e = edges.map { "[\($0[0]),\($0[1]),\($0[2])]" }.joined(separator: ",")
        let t = target.map { ",\"target\":\($0)" } ?? ""
        return try parse(#"{"v":1,"template":"shortest_path","params":{"n":\#(n),"edges":[\#(e)],"source":\#(source)\#(t),"directed":\#(directed ? 1 : 0)}\#(extra)}"#).get()
    }
    func patch(_ params: String, rev: Int? = nil) throws -> MGPatch {
        let r = rev.map { #""rev":\#($0),"# } ?? ""
        return try MGPatch.parse(data: Data(#"{"v":1,\#(r)"ops":[{"op":"params","params":\#(params)}]}"#.utf8)).get()
    }
    /// Final board after every cumulative step edit.
    func last(_ s: MGScene) -> [String: MGItem] {
        Dictionary(uniqueKeysWithValues: MGTimeline.items(s, step: s.steps.count - 1).map { ($0.id, $0) })
    }
    /// Semantic edge id: undirected `e<min>_<max>`, directed `d<tail>_<head>`.
    func eid(_ e: [Int], _ directed: Bool) -> String { directed ? "d\(e[0])_\(e[1])" : "e\(min(e[0], e[1]))_\(max(e[0], e[1]))" }
    /// Independent oracle: Bellman–Ford relaxation over every edge, n−1 rounds.
    func oracle(n: Int, edges: [[Int]], source: Int, directed: Bool) -> [Int?] {
        var d = [Int?](repeating: nil, count: n); d[source] = 0
        for _ in 0..<n {
            for e in edges {
                let arcs = directed ? [(e[0], e[1])] : [(e[0], e[1]), (e[1], e[0])]
                for (u, v) in arcs { if let du = d[u], d[v].map({ du + e[2] < $0 }) ?? true { d[v] = du + e[2] } }
            }
        }
        return d
    }
    /// Independent route count: every ordered sequence of distinct intermediate nodes, checked link by link.
    func oracleRoutes(n: Int, edges: [[Int]], source: Int, target: Int, directed: Bool, cost: Int) -> Int {
        var w = [[Int?]](repeating: [Int?](repeating: nil, count: n), count: n)
        for e in edges { w[e[0]][e[1]] = e[2]; if !directed { w[e[1]][e[0]] = e[2] } }
        var count = 0
        func extend(_ seq: [Int], _ rest: [Int]) {
            let nodes = [source] + seq + [target]
            var total = 0, linked = true
            for (x, y) in zip(nodes, nodes.dropFirst()) { if let c = w[x][y] { total += c } else { linked = false; break } }
            if linked && total == cost { count += 1 }
            for (i, m) in rest.enumerated() { var r = rest; r.remove(at: i); extend(seq + [m], r) }
        }
        extend([], (0..<n).filter { $0 != source && $0 != target })
        return count
    }

    // MARK: record-list parameters (core API)

    static let recordTemplate = MGTemplate(
        name: "demo_records", summary: "record params",
        params: [.records("pts", count: 1...3, fields: [.init("i", 0...9, integer: true), .init("x", -1...1)]),
                 .records("opt", count: 0...2, fields: [.init("v", 0...5)]),
                 .init(name: "k", unit: "", range: 1...3, integer: true)],
        check: { p in p["k"] != 2 || (p.records["pts"] ?? []).count < 3 },
        reject: { p in p["k"] == 3 && (p.records["opt"] ?? []).isEmpty ? "opt.needed" : nil },
        make: { p, _ in
            let pts = p.records["pts"] ?? []
            let items = pts.enumerated().map { k, r in MGMake.body("b\(k)", MGPoint(2 + r[0], 4 + r[1])) }
            return MGTemplateBuild(title: "Records \(pts.count) \((p.records["opt"] ?? []).count)", items: items)
        })

    func recordReason(_ params: String) -> String? {
        if case .failure(let e) = MGParser.scene(data: Data(#"{"v":1,"template":"demo_records","params":\#(params)}"#.utf8), extraTemplates: [Self.recordTemplate]) { return e.reason }
        return nil
    }

    func testRecordParamsValidateArityRangeIntegralityAndCount() throws {
        let ok = try MGParser.scene(data: Data(#"{"v":1,"template":"demo_records","params":{"pts":[[1,0.5],[3,-1]],"k":1}}"#.utf8), extraTemplates: [Self.recordTemplate]).get()
        XCTAssertEqual(ok.items.map(\.pts.first), [MGPoint(3, 4.5), MGPoint(5, 3)])
        XCTAssertEqual(ok.title, "Records 2 0")                                         // optional record list absent = empty
        XCTAssertNil(recordReason(#"{"pts":[[1,0]],"opt":[[2],[3]],"k":1}"#))
        XCTAssertNil(recordReason(#"{"pts":[[1,0]],"opt":[],"k":1}"#))                    // an empty list is the explicit "none"
        XCTAssertEqual(recordReason(#"{"pts":[[1,0,0]],"k":1}"#), "template.pts.arity")
        XCTAssertEqual(recordReason(#"{"pts":[1,0],"k":1}"#), "template.pts.arity")       // flat list is not a record list
        XCTAssertEqual(recordReason(#"{"pts":[[1.5,0]],"k":1}"#), "template.pts.i.integer")
        XCTAssertEqual(recordReason(#"{"pts":[[1,2]],"k":1}"#), "template.pts.x")         // out of range: rejected, not clamped
        XCTAssertEqual(recordReason(#"{"pts":[[1,"0"]],"k":1}"#), "template.pts.x")
        XCTAssertEqual(recordReason(#"{"pts":[[1,true]],"k":1}"#), "template.pts.x")      // JSON booleans are not numbers
        XCTAssertEqual(recordReason(#"{"pts":[],"k":1}"#), "template.pts.count")
        XCTAssertEqual(recordReason(#"{"pts":[[1,0],[1,0],[1,0],[1,0]],"k":1}"#), "template.pts.count")
        XCTAssertEqual(recordReason(#"{"k":1}"#), "template.pts.missing")
        XCTAssertEqual(recordReason(#"{"pts":{"i":1},"k":1}"#), "template.pts")
        XCTAssertEqual(recordReason(#"{"pts":null,"k":1}"#), "template.pts")              // null is not "absent"
        XCTAssertEqual(recordReason(#"{"pts":[[1,0]],"opt":null,"k":1}"#), "template.opt") // not even for an optional list
        XCTAssertEqual(recordReason(#"{"pts":[[1,0]],"opt":[[9]],"k":1}"#), "template.opt.v")
        // Scalar and number-list parameters keep their exact previous behaviour and reasons.
        XCTAssertEqual(recordReason(#"{"pts":[[1,0]],"k":1.5}"#), "template.k.integer")
        XCTAssertEqual(recordReason(#"{"pts":[[1,0]]}"#), "template.k.missing")
        // A specific `reject` reason runs before the generic `check`.
        XCTAssertEqual(recordReason(#"{"pts":[[1,0]],"k":3}"#), "template.opt.needed")
        XCTAssertNil(recordReason(#"{"pts":[[1,0]],"opt":[[1]],"k":3}"#))
        XCTAssertEqual(recordReason(#"{"pts":[[1,0],[1,0],[1,0]],"k":2}"#), "template.check")
        XCTAssertEqual(Self.recordTemplate.doc, "demo_records{pts:[1–3 × (i 0–9 int, x -1–1)], opt:[0–2 × (v 0–5)], k 1–3}: record params")
        XCTAssertTrue(Self.recordTemplate.params[0].isRecordList)
        XCTAssertFalse(Self.recordTemplate.params[2].isRecordList)
    }

    func testRecordFieldBoundariesAreInclusiveAndNeverClamped() {
        XCTAssertNil(recordReason(#"{"pts":[[0,-1],[9,1]],"k":1}"#))
        XCTAssertEqual(recordReason(#"{"pts":[[1,1.0000001]],"k":1}"#), "template.pts.x")
        XCTAssertEqual(recordReason(#"{"pts":[[1,-1.0000001]],"k":1}"#), "template.pts.x")
        XCTAssertEqual(recordReason(#"{"pts":[[9.0000001,0]],"k":1}"#), "template.pts.i")        // range before integrality
        XCTAssertEqual(recordReason(#"{"pts":[[2.0000001,0]],"k":1}"#), "template.pts.i.integer")
        XCTAssertEqual(recordReason(#"{"pts":[[-0.0000001,0]],"k":1}"#), "template.pts.i")
    }

    func testRejectionSuffixesAreSanitised() {
        XCTAssertEqual(MGTemplate.rejection("edges.loop"), "template.edges.loop")
        XCTAssertEqual(MGTemplate.rejection("at.gap2_x"), "template.at.gap2_x")
        XCTAssertEqual(MGTemplate.rejection(String(repeating: "a", count: 48)), "template." + String(repeating: "a", count: 48))
        for bad in ["", "Edges", "edges..loop", ".edges", "edges.", "2edges", "edges loop", "edges.<b>", "édges", String(repeating: "a", count: 49)] {
            XCTAssertEqual(MGTemplate.rejection(bad), "template.check", bad)
        }
    }

    func testRecordDeclarationsAreValidatedAtRegistrationAndLazily() {
        func t(_ specs: [MGParamSpec]) -> MGTemplate {
            MGTemplate(name: "demo_bad_rec", summary: "", params: specs, make: { _, _ in MGTemplateBuild(title: "x", items: [MGMake.body("b", MGPoint(1, 1))]) })
        }
        func pack(_ specs: [MGParamSpec]) -> MGPack {
            MGPack(id: "demo_rec", title: "x", summary: "x", templates: [t(specs)],
                   fixtures: [.init(id: "demo_rec_f", title: "x", json: #"{"v":1,"template":"demo_bad_rec","params":{"r":[[1]]}}"#)])
        }
        func lazyReason(_ spec: MGParamSpec) -> String? {
            if case .failure(let e) = MGParser.scene(data: Data(#"{"v":1,"template":"demo_bad_rec","params":{"r":[[1]]}}"#.utf8), extraTemplates: [t([spec])]) { return e.reason }
            return nil
        }
        let a = MGParamField("a", 0...1)
        let good = MGParamSpec.records("r", count: 1...MGLimits.records, fields: [a])
        XCTAssertNil(lazyReason(good))
        XCTAssertEqual(MGPacks.validate(pack([good])), [])
        XCTAssertNil(lazyReason(.records("r", count: 0...2, fields: [MGParamField("f1", 0...1)])))

        var noCount = MGParamSpec(name: "r", unit: "", range: 0...1); noCount.fields = [a]
        let cases: [(MGParamSpec, String)] = [
            (.records("r", count: 1...(MGLimits.records + 1), fields: [a]), "r: count must lie within 0…32"),
            (.records("r", count: -1...2, fields: [a]), "r: count must lie within 0…32"),
            (.records("r", count: 1...2, fields: []), "r: needs 1…6 fields"),
            (.records("r", count: 1...2, fields: (0...MGLimits.recordFields).map { MGParamField("f\($0)", 0...1) }), "r: needs 1…6 fields"),
            (.records("r", count: 1...2, fields: [a, a]), "r: field 'a' is declared twice"),
            (.records("r", count: 1...2, fields: [.init("count", 0...1)]), "r: field 'count' is a reserved reason suffix"),
            (.records("r", count: 1...2, fields: [.init("integer", 0...1)]), "r: field 'integer' is a reserved reason suffix"),
            (.records("r", count: 1...2, fields: [.init("A", 0...1)]), "r: field 'A' must be 1–16 lowercase ASCII letters, digits or _, starting with a letter"),
            (.records("r", count: 1...2, fields: [.init("x.y", 0...1)]), "r: field 'x.y' must be 1–16 lowercase ASCII letters, digits or _, starting with a letter"),
            (.records("r", count: 1...2, fields: [.init("a", -Double.infinity...1)]), "r: field 'a' needs a finite range"),
            (noCount, "r: a record list needs a count"),
        ]
        for (spec, why) in cases {
            XCTAssertEqual(lazyReason(spec), "template.r.spec", why)
            XCTAssertEqual(MGPacks.validate(pack([spec])).first, .badParamSpec("demo_bad_rec", why))
            XCTAssertThrowsError(try MGPacks.register(pack([spec]))) { XCTAssertEqual($0 as? MGPackError, .badParamSpec("demo_bad_rec", why)) }
            XCTAssertNil(MGPacks.all.first { $0.id == "demo_rec" }, "nothing registered on failure")
        }
        XCTAssertEqual(MGPacks.validate(pack([.records("r", count: 1...2, fields: [])])),
                       [.badParamSpec("demo_bad_rec", "r: needs 1…6 fields"), .fixtureInvalid("demo_rec_f", "template.r.spec"), .templateWithoutFixture("demo_bad_rec")])
        // A parameter name used twice is caught at registration (lazy parsing cannot see it).
        XCTAssertEqual(MGPacks.validate(pack([good, .init(name: "r", unit: "", range: 0...1, defaultValue: 0)])).first,
                       .badParamSpec("demo_bad_rec", "r: parameter name declared twice"))
        XCTAssertEqual(MGPackError.badParamSpec("demo_bad_rec", "r: needs 1…6 fields").description, "template 'demo_bad_rec' parameter r: needs 1…6 fields")
        // Scalar and number-list declarations keep their existing (lazy) behaviour.
        XCTAssertEqual(t([.init(name: "Q", unit: "", range: 0...1, defaultValue: 0), .init(name: "count", unit: "", range: 0...1, count: 1...2)]).declarationProblems, [])
    }

    func testGrammarExposesRecordShapesOnlyForRegisteredRecordTemplates() throws {
        let before = MGGrammar.document()
        let templatesBefore = try XCTUnwrap(before["templates"] as? [[String: Any]])
        XCTAssertEqual(Set(templatesBefore.flatMap(\.keys)), ["name", "parameters"])          // default document unchanged
        XCTAssertEqual(Set(try XCTUnwrap(before["limits"] as? [String: Int]).keys), ["sceneBytes", "patchBytes", "items", "steps", "templateSteps"])
        try MGPacks.register(MGGraphPack.pack)
        let after = MGGrammar.document()
        XCTAssertTrue(JSONSerialization.isValidJSONObject(after))
        let entry = try XCTUnwrap((after["templates"] as? [[String: Any]])?.first { $0["name"] as? String == "shortest_path" })
        XCTAssertEqual(entry["parameters"] as? [String], ["n", "edges", "source", "target", "directed", "at"])
        let records = try XCTUnwrap(entry["records"] as? [[String: Any]])
        XCTAssertEqual(records.map { $0["name"] as? String }, ["edges", "at"])
        XCTAssertEqual(records.map { $0["count"] as? [Int] }, [[1, 16], [0, 8]])
        let edgeFields = try XCTUnwrap(records[0]["fields"] as? [[String: Any]])
        XCTAssertEqual(edgeFields.map { $0["name"] as? String }, ["a", "b", "w"])
        XCTAssertEqual(edgeFields.map { $0["range"] as? [Double] }, [[0, 7], [0, 7], [0, 99]])
        XCTAssertEqual(edgeFields.map { $0["integer"] as? Bool }, [true, true, true])
        let atFields = try XCTUnwrap(records[1]["fields"] as? [[String: Any]])
        XCTAssertEqual(atFields.map { $0["name"] as? String }, ["x", "y"])
        XCTAssertEqual(atFields.map { $0["range"] as? [Double] }, [[0.5, 11.5], [2, 7.5]])
        XCTAssertEqual(atFields.map { $0["integer"] as? Bool }, [false, false])
        // Built-in templates still have no record key; global limits are unchanged by registration.
        XCTAssertTrue((after["templates"] as? [[String: Any]])?.filter { $0["name"] as? String != "shortest_path" }.allSatisfy { $0["records"] == nil } ?? false)
        XCTAssertEqual(Set(try XCTUnwrap(after["limits"] as? [String: Int]).keys), ["sceneBytes", "patchBytes", "items", "steps", "templateSteps"])
    }

    // MARK: shortest_path: golden fixture

    func testRouterFixtureGoldenWalkthrough() throws {
        let s = try parse(MGGraphPack.routerLatencyFixture).get()
        XCTAssertEqual(s.title, "Router latency (ms)")
        XCTAssertEqual(s.items.map(\.id), ["e0_1", "e0_2", "e1_2", "e1_3", "e2_3", "e2_4", "e3_4", "e3_5", "e4_5",
                                           "n0", "n1", "n2", "n3", "n4", "n5", "dist"])
        XCTAssertEqual(s.steps.count, 8)                                   // intro + 6 settles + summary
        let order = (1...6).map { k in MGTimeline.items(s, step: k).first { $0.id == "dist" }!.pointers.first! }
        XCTAssertEqual(order, [0, 2, 1, 3, 4, 5].map { MGPointer(index: Double($0), label: "u") })
        XCTAssertEqual(s.steps[2].say, "Settle 2 at 1, the closest unsettled node. 2→1: 1+2=3 beats 4. 2→3: 1+8=9 beats ∞. 2→4: 1+10=11 beats ∞.")
        XCTAssertEqual(s.steps.last?.say, "The shortest path 0→2→1→3→4→5 costs 13.")
        let board = last(s)
        XCTAssertEqual(board["dist"]?.list, ["0", "3", "1", "8", "10", "13"])
        XCTAssertEqual(board["dist"]?.marked, [0, 1, 2, 3, 4, 5])
        XCTAssertEqual(board["dist"]?.pointers, [MGPointer(index: 5, label: "t")])   // target, not "being settled"
        let colours = ["e0_1", "e0_2", "e1_2", "e1_3", "e2_3", "e2_4", "e3_4", "e3_5", "e4_5"].map { board[$0]!.color }
        XCTAssertEqual(colours, [.muted, .yellow, .yellow, .yellow, .muted, .muted, .yellow, .muted, .yellow])
        XCTAssertEqual(board["e1_2"]?.ref, "n1"); XCTAssertEqual(board["e1_2"]?.ref2, "n2")   // record [2,1,2], canonical ends
        XCTAssertEqual(s.values["cost"]?.value, 13)
        XCTAssertEqual(s.values["routes"]?.value, 1)
        XCTAssertEqual(oracle(n: 6, edges: [[0,1,4],[0,2,1],[2,1,2],[1,3,5],[2,3,8],[2,4,10],[3,4,2],[3,5,6],[4,5,3]], source: 0, directed: false),
                       [0, 3, 1, 8, 10, 13])
        XCTAssertEqual(try parse(MGGraphPack.routerLatencyFixture).get(), s)    // deterministic
    }

    func testAuthoredTextCanQuoteComputedValues() throws {
        let s = try parse(#"{"v":1,"template":"shortest_path","params":{"n":3,"edges":[[0,1,2],[1,2,2],[0,2,4]],"target":2},"title":"Cost {cost} via {routes} routes"}"#).get()
        XCTAssertEqual(s.title, "Cost 4 via 2 routes")
        XCTAssertEqual(reason(#"{"v":1,"template":"shortest_path","params":{"n":3,"edges":[[0,1,2]]},"title":"Cost {cost}"}"#), "title.placeholder.cost")
        XCTAssertEqual(reason(#"{"v":1,"template":"shortest_path","params":{"n":3,"edges":[[0,1,2]]},"title":"{routes} routes"}"#), "title.placeholder.routes")
    }

    // MARK: shortest_path: semantic edge ids

    func testEdgeIdsAreSemanticAndRecordOrderDoesNotMatter() throws {
        let a = try parse(#"{"v":1,"template":"shortest_path","params":{"n":6,"target":5,"edges":[\#(Self.routerEdges)],"at":[\#(Self.routerAt)]}}"#).get()
        let b = try parse(#"{"v":1,"template":"shortest_path","params":{"n":6,"target":5,"edges":[\#(Self.routerEdgesShuffled)],"at":[\#(Self.routerAt)]}}"#).get()
        XCTAssertEqual(a.items, b.items)
        XCTAssertEqual(a.steps, b.steps)
        XCTAssertEqual(a.values, b.values)
        // Directed arcs keep their direction in the id; the item order is still by unordered pair.
        let d = try parse(#"{"v":1,"template":"shortest_path","params":{"n":6,"target":5,"directed":1,"edges":[\#(Self.routerEdges)],"at":[\#(Self.routerAt)]}}"#).get()
        XCTAssertEqual(d.items.filter { $0.kind == .edge }.map(\.id), ["d0_1", "d0_2", "d2_1", "d1_3", "d2_3", "d2_4", "d3_4", "d3_5", "d4_5"])
        XCTAssertEqual(d.items.first { $0.id == "d2_1" }?.ref, "n2")
        XCTAssertTrue(d.items.filter { $0.kind == .edge }.allSatisfy { $0.has("dir") })
        XCTAssertEqual(d.steps.last?.say, "The shortest path 0→2→1→3→4→5 costs 13.")
    }

    func testOverAndHideFollowTheLinkAndAreRefusedWhenItsIdentityChanges() throws {
        try MGPacks.register(MGGraphPack.pack)
        // `over` on link 3–4 survives a reordered what-if and is refused (never moved) when the link disappears.
        let s = try MGParser.scene(data: Data(#"{"v":1,"template":"shortest_path","params":{"n":6,"target":5,"edges":[\#(Self.routerEdges)],"at":[\#(Self.routerAt)]},"over":[{"id":"e3_4","key":"label","value":"slow"}]}"#.utf8)).get()
        XCTAssertEqual(s.items.first { $0.id == "e3_4" }?.label, "slow")
        let reordered = try s.applying(patch(#"{"edges":[\#(Self.routerEdgesShuffled)]}"#, rev: 0)).get()
        let link = try XCTUnwrap(reordered.items.first { $0.id == "e3_4" })
        XCTAssertEqual([link.label, link.ref, link.ref2], ["slow", "n3", "n4"])
        XCTAssertEqual(reordered.items.filter { $0.label == "slow" }.count, 1)
        XCTAssertEqual(reordered.applying(try patch(#"{"edges":[[0,1,4],[0,2,1],[2,1,2],[1,3,5],[2,3,8],[2,4,10],[3,5,6],[4,5,3]]}"#)).failureReason, "over.ref")

        // `hide` of a link the walkthrough never edits follows it across a reorder, and is refused when the link goes.
        let h = try MGParser.scene(data: Data(#"{"v":1,"template":"shortest_path","params":{"n":3,"edges":[[0,1,1],[0,2,1],[1,2,5]]},"hide":["e1_2"]}"#.utf8)).get()
        XCTAssertNil(h.items.first { $0.id == "e1_2" })
        let hr = try h.applying(patch(#"{"edges":[[2,1,5],[2,0,1],[1,0,1]]}"#)).get()
        XCTAssertNil(hr.items.first { $0.id == "e1_2" })
        XCTAssertEqual(hr.items.filter { $0.kind == .edge }.map(\.id), ["e0_1", "e0_2"])
        XCTAssertEqual(h.applying(try patch(#"{"edges":[[0,1,1],[0,2,1]]}"#)).failureReason, "hide.ref")

        // Directed: reversing the arc or toggling `directed` is a different link, so the reference is refused.
        let d = try MGParser.scene(data: Data(#"{"v":1,"template":"shortest_path","params":{"n":3,"directed":1,"edges":[[0,1,1],[1,2,1]]},"over":[{"id":"d1_2","key":"label","value":"one-way"}]}"#.utf8)).get()
        XCTAssertEqual(try d.applying(patch(#"{"edges":[[1,2,1],[0,1,1]]}"#)).get().items.first { $0.id == "d1_2" }?.label, "one-way")
        XCTAssertEqual(d.applying(try patch(#"{"edges":[[0,1,1],[2,1,1]]}"#)).failureReason, "over.ref")
        XCTAssertEqual(d.applying(try patch(#"{"directed":0}"#)).failureReason, "over.ref")
        XCTAssertEqual(d.revision, 0)
    }

    // MARK: shortest_path: ties, source = target, oracle property check

    func testSettledDirectedTiesAreDisclosedWithoutCountingCyclicWalks() throws {
        let edges = [[0, 1, 0], [0, 2, 0], [2, 1, 0]]
        let tree = try scene(n: 3, edges: edges, directed: true)
        XCTAssertTrue(tree.steps.last!.say.contains("Multiple shortest simple paths exist"))
        let targeted = try scene(n: 3, edges: edges, target: 1, directed: true)
        XCTAssertEqual(targeted.values["routes"]?.value, 2)
        XCTAssertTrue(targeted.steps.last!.say.contains("2 routes tie at 0"))
        let cycle = try scene(n: 3, edges: [[0, 1, 0], [1, 2, 0], [2, 0, 0]], directed: true)
        XCTAssertFalse(cycle.steps.last!.say.contains("Multiple shortest simple paths exist"))
    }

    func testEqualCostTiesAreNarratedAndCounted() throws {
        // Flagship what-if: 0→2→1→3→5 and 0→2→4→5 both cost 14.
        let w = try parse(#"{"v":1,"template":"shortest_path","params":{"n":6,"target":5,"edges":[[0,1,4],[0,2,1],[2,1,2],[1,3,5],[2,3,8],[2,4,10],[3,4,9],[3,5,6],[4,5,3]],"at":[\#(Self.routerAt)]}}"#).get()
        XCTAssertEqual(w.steps[5].say, "Settle 4 at 11, the closest unsettled node. 4→5: 11+3=14 ties 14, earlier route kept.")
        XCTAssertEqual(w.steps.last?.say, "A shortest path 0→2→1→3→5 costs 14. 2 routes tie at 14; the one found first is shown.")
        XCTAssertEqual(w.values["routes"]?.value, 2)
        XCTAssertEqual(last(w)["e4_5"]?.color, .muted)                       // the tied link is not drawn as the path
        // Tree-only walkthrough: the zero-weight tie is narrated and the summary says the tree is one of several.
        let t = try scene(n: 4, edges: [[0, 2, 5], [0, 1, 5], [1, 3, 0], [2, 3, 0]])
        let settles = (1...4).map { Int(MGTimeline.items(t, step: $0).first { $0.id == "dist" }!.pointers[0].index) }
        XCTAssertEqual(settles, [0, 1, 2, 3])                                 // equal distances settle lowest index first
        XCTAssertEqual(t.steps[3].say, "Settle 2 at 5, the closest unsettled node. 2→3: 5+0=5 ties 5, earlier route kept.")
        XCTAssertEqual(t.steps.last?.say, "Done: green edges form a shortest-path tree from 0. Multiple shortest simple paths exist; the tree found first is shown.")
        XCTAssertEqual(last(t)["dist"]?.list, ["0", "5", "5", "5"])
        XCTAssertEqual(last(t)["e1_3"]?.color, .good)
        XCTAssertEqual(last(t)["e2_3"]?.color, .muted)
        // A tie-heavy step falls back to counts within the narration bound (the only reachable fallback in these bounds).
        let f = try scene(n: 8, edges: [[0, 1, 10], [0, 2, 99], [0, 3, 99], [0, 4, 99], [1, 2, 89], [1, 3, 89], [1, 4, 89], [1, 5, 89], [1, 6, 89], [1, 7, 89]])
        XCTAssertEqual(f.steps[2].say, "Settle 1 at 10, the closest unsettled node. 3 improved (orange), 3 tied (earlier route kept).")
        XCTAssertTrue(f.steps.allSatisfy { $0.say.unicodeScalars.count <= MGLimits.say })
    }

    func testSourceEqualToTargetIsExplained() throws {
        let s = try scene(n: 3, edges: [[0, 1, 2], [1, 2, 2]], source: 1, target: 1)
        XCTAssertEqual(s.steps.last?.say, "Target 1 is the source itself, so the path is just node 1 and costs 0.")
        XCTAssertEqual(s.values["cost"]?.value, 0)
        XCTAssertEqual(s.values["routes"]?.value, 1)
        XCTAssertEqual(last(s)["dist"]?.pointers, [MGPointer(index: 1, label: "t")])
        XCTAssertEqual(last(s)["dist"]?.list, ["2", "0", "2"])
        XCTAssertTrue(["e0_1", "e1_2"].allSatisfy { last(s)[$0]?.color == .good })   // the tree is still shown, no path drawn
    }

    func testRandomGraphsMatchIndependentOracles() throws {
        var seed: UInt64 = 0x5EED_2026_1105
        func next(_ bound: Int) -> Int { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Int((seed >> 33) % UInt64(bound)) }
        var checked = 0, unreachableSeen = 0, reachableTargets = 0, tiedTargets = 0, sourceIsTarget = 0, narratedTies = 0
        for _ in 0..<400 {
            let n = 2 + next(7), directed = next(2) == 1, small = next(2) == 0
            var pairs = Set<[Int]>(), edges: [[Int]] = []
            for _ in 0..<(1 + next(MGGraphPack.maxEdges)) {
                let a = next(n), b = next(n); guard a != b, pairs.insert([min(a, b), max(a, b)]).inserted else { continue }
                edges.append([a, b, small ? next(4) : next(100)])
            }
            guard !edges.isEmpty else { continue }
            let source = next(n), target = next(3) == 0 ? nil : next(n)
            let s = try scene(n: n, edges: edges, source: source, target: target, directed: directed)
            let expected = oracle(n: n, edges: edges, source: source, directed: directed)
            let board = last(s)
            XCTAssertEqual(board["dist"]?.list, expected.map { $0.map(String.init) ?? "∞" }, "\(edges)")
            // Record order never matters.
            let reversed = try scene(n: n, edges: Array(edges.reversed()), source: source, target: target, directed: directed)
            XCTAssertEqual(reversed.items, s.items); XCTAssertEqual(reversed.steps, s.steps); XCTAssertEqual(reversed.values, s.values)
            // Settle order is non-decreasing in distance and settles exactly the reachable nodes.
            let settles = (1..<(s.steps.count - 1)).map { Int(MGTimeline.items(s, step: $0).first { $0.id == "dist" }!.pointers[0].index) }
            XCTAssertEqual(Set(settles), Set((0..<n).filter { expected[$0] != nil }))
            XCTAssertEqual(settles.count, Set(settles).count)
            XCTAssertEqual(settles.map { expected[$0]! }, settles.map { expected[$0]! }.sorted())
            for i in 0..<n { XCTAssertEqual(board["n\(i)"]?.color, expected[i] == nil ? .muted : .good) }
            if let t = target, t == source {
                sourceIsTarget += 1
                XCTAssertEqual(s.values["cost"]?.value, 0)
            } else if let t = target, let cost = expected[t] {
                reachableTargets += 1
                // Yellow edges form one source→target path whose weights sum to the oracle distance.
                let path = edges.filter { board[eid($0, directed)]?.color == .yellow }
                XCTAssertEqual(path.map { $0[2] }.reduce(0, +), cost)
                var at = source, used = Set<Int>()
                while at != t, let k = path.indices.first(where: { !used.contains($0) && (path[$0][0] == at || (!directed && path[$0][1] == at)) }) {
                    used.insert(k); at = path[k][0] == at ? path[k][1] : path[k][0]
                }
                XCTAssertEqual(at, t); XCTAssertEqual(used.count, path.count)
                XCTAssertEqual(s.values["cost"]?.value, Double(cost))
                let routes = oracleRoutes(n: n, edges: edges, source: source, target: t, directed: directed, cost: cost)
                XCTAssertEqual(s.values["routes"]?.value, Double(routes), "\(edges)")
                XCTAssertTrue(s.steps.last!.say.hasPrefix(routes == 1 ? "The shortest path " : "A shortest path "))
                if routes > 1 { tiedTargets += 1; XCTAssertTrue(s.steps.last!.say.contains("\(routes) routes tie at \(cost)")) }
            } else if let t = target {
                XCTAssertEqual(s.steps.last?.say, "Node \(t) is unreachable from \(source): no path exists.")
                XCTAssertNil(s.values["cost"])
            }
            if s.steps.contains(where: { $0.say.contains(" ties ") }) { narratedTies += 1 }
            if expected.contains(where: { $0 == nil }) { unreachableSeen += 1 }
            XCTAssertLessThanOrEqual(s.steps.count, n + 2)
            XCTAssertTrue(s.steps.allSatisfy { $0.say.unicodeScalars.count < MGLimits.say })   // summary truncation never needed
            checked += 1
        }
        // Exact counts replayed from the same generator in the Python transcription (probes/lcg_property.out).
        XCTAssertEqual(checked, 389); XCTAssertEqual(unreachableSeen, 226); XCTAssertEqual(reachableTargets, 106)
        XCTAssertEqual(tiedTargets, 5); XCTAssertEqual(sourceIsTarget, 62); XCTAssertEqual(narratedTies, 21)
    }

    func testDirectedEdgesOnlyRelaxForward() throws {
        let s = try scene(n: 3, edges: [[1, 0, 1], [0, 2, 4]], target: 1, directed: true)
        XCTAssertEqual(last(s)["dist"]?.list, ["0", "∞", "4"])
        XCTAssertEqual(s.items.filter { $0.kind == .edge }.map(\.id), ["d1_0", "d0_2"])
        XCTAssertTrue(s.items.first { $0.id == "d1_0" }!.has("dir"))
        XCTAssertEqual(s.steps.last?.say, "Node 1 is unreachable from 0: no path exists.")
        XCTAssertEqual(last(s)["n1"]?.color, .muted)
    }

    // MARK: shortest_path: bounds and rejection

    func testInvalidGraphsGiveSpecificReasonsAndAreRejectedWhole() {
        let base = #"{"v":1,"template":"shortest_path","params":"#
        let cases: [(String, String)] = [
            (#"{"n":3,"edges":[[0,1,-1]]}"#, "template.edges.w"),                       // negative weight
            (#"{"n":3,"edges":[[0,1,100]]}"#, "template.edges.w"),
            (#"{"n":3,"edges":[[0,1,2.5]]}"#, "template.edges.w.integer"),
            (#"{"n":3,"edges":[[0,1]]}"#, "template.edges.arity"),
            (#"{"n":3}"#, "template.edges.missing"),
            (#"{"n":3,"edges":[]}"#, "template.edges.count"),
            (#"{"n":3,"edges":[[0,3,1]]}"#, "template.edges.node"),                     // index ≥ n
            (#"{"n":3,"edges":[[1,1,1]]}"#, "template.edges.loop"),
            (#"{"n":3,"edges":[[0,1,1],[1,0,2]]}"#, "template.edges.duplicate"),
            (#"{"n":3,"edges":[[0,1,1],[1,0,2]],"directed":1}"#, "template.edges.duplicate"),   // no anti-parallel arcs
            (#"{"n":3,"edges":[[0,1,1]],"source":5}"#, "template.source.range"),
            (#"{"n":3,"edges":[[0,1,1]],"target":1.5}"#, "template.target.integer"),
            (#"{"n":3,"edges":[[0,1,1]],"target":4}"#, "template.target.range"),
            (#"{"n":3,"edges":[[0,1,1]],"target":null}"#, "template.target"),
            (#"{"n":3,"edges":[[0,1,1]],"directed":true}"#, "template.directed"),          // 0/1 number, not a JSON boolean
            (#"{"n":3,"edges":[[0,1,1]],"directed":0.5}"#, "template.directed.integer"),
            (#"{"n":9,"edges":[[0,1,1]]}"#, "template.n"),
            (#"{"n":3,"edges":[[0,1,1]],"at":[[1,3],[5,3]]}"#, "template.at.count"),
            (#"{"n":2,"edges":[[0,1,1]],"at":[[1,3],[1.5,3]]}"#, "template.at.gap"),
            (#"{"n":2,"edges":[[0,1,1]],"at":[[1,1],[5,3]]}"#, "template.at.y"),            // would cover the array
            (#"{"n":2,"edges":[[0,1,1]],"colour":1}"#, "template.params.unknown"),
        ]
        for (params, expected) in cases { XCTAssertEqual(reason(base + params + "}"), expected, params) }
        XCTAssertEqual(reason(#"{"v":1,"dim":"3d","template":"shortest_path","params":{"n":2,"edges":[[0,1,1]]}}"#), "template.build")
        let tooMany = (0..<17).map { k in "[\(k % 8),\((k / 8 + k % 8 + 1) % 8),1]" }.joined(separator: ",")
        XCTAssertEqual(reason(base + #"{"n":8,"edges":[\#(tooMany)]}}"#), "template.edges.count")
    }

    func testGeometryAndNumericBoundariesAreRepresentationTolerant() {
        let two = #"{"v":1,"template":"shortest_path","params":{"n":2,"edges":[[0,1,1]],"at":"#
        XCTAssertNil(reason(two + #"[[0.5,5],[1.7,5]]}}"#))                 // exactly 1.2 apart
        XCTAssertNil(reason(two + #"[[10.3,5],[11.5,5]]}}"#))               // 1.2 apart; binary difference is just below 1.2
        XCTAssertEqual(reason(two + #"[[1,5],[2.19,5]]}}"#), "template.at.gap")
        XCTAssertNil(reason(two + #"[[0.5,2],[11.5,7.5]]}}"#))              // inclusive field bounds
        XCTAssertEqual(reason(two + #"[[0.5,2],[11.5000001,7.5]]}}"#), "template.at.x")
        XCTAssertEqual(reason(two + #"[[0.4999999,2],[11.5,7.5]]}}"#), "template.at.x")
        XCTAssertEqual(reason(two + #"[[0.5,1.9999999],[11.5,7.5]]}}"#), "template.at.y")
        XCTAssertEqual(reason(two + #"[[0.5,2],[11.5,7.5000001]]}}"#), "template.at.y")
        let base = #"{"v":1,"template":"shortest_path","params":"#
        XCTAssertNil(reason(base + #"{"n":8,"edges":[[0,7,99],[1,2,0]],"source":7,"target":0}}"#))
        XCTAssertEqual(reason(base + #"{"n":8.0000001,"edges":[[0,1,1]]}}"#), "template.n")
        XCTAssertEqual(reason(base + #"{"n":3,"edges":[[0,1,99.0000001]]}}"#), "template.edges.w")
        XCTAssertEqual(reason(base + #"{"n":3,"edges":[[0,1,1.0000001]]}}"#), "template.edges.w.integer")
        XCTAssertEqual(reason(base + #"{"n":3,"edges":[[0,1,-0.0000001]]}}"#), "template.edges.w")
        XCTAssertEqual(reason(base + #"{"n":3,"edges":[[0,1,1]],"target":2.0000001}}"#), "template.target.integer")
    }

    func testEdgesMayNotPassThroughOtherNodes() {
        let three = #"{"v":1,"template":"shortest_path","params":{"n":3,"#
        XCTAssertEqual(reason(three + #""edges":[[0,2,1]],"at":[[1.5,5],[4.5,5],[7.5,5]]}}"#), "template.at.crossing")   // 0–2 reads as 0–1–2
        XCTAssertNil(reason(three + #""edges":[[0,1,1],[1,2,1]],"at":[[1.5,5],[4.5,5],[7.5,5]]}}"#))
        XCTAssertNil(reason(three + #""edges":[[0,2,1]],"at":[[1.5,5],[4.5,5.6],[7.5,5]]}}"#))            // exactly 0.6 clear
        XCTAssertEqual(reason(three + #""edges":[[0,2,1]],"at":[[1.5,5],[4.5,5.59],[7.5,5]]}}"#), "template.at.crossing")
        XCTAssertNil(reason(three + #""edges":[[0,1,1]],"at":[[1.5,5],[4.5,5],[5.7,5]]}}"#))              // beyond the segment's end
        // The automatic circle always clears: every single link on every node count parses.
        for n in 2...MGGraphPack.maxNodes { for a in 0..<n { for b in (a + 1)..<n {
            XCTAssertNil(reason(#"{"v":1,"template":"shortest_path","params":{"n":\#(n),"edges":[[\#(a),\#(b),1]]}}"#), "\(n): \(a)-\(b)")
        } } }
    }

    func testLargestGraphStaysInsideExistingSceneBounds() throws {
        // 8 nodes, 16 distinct pairs, maximal weights and 3-digit distances; four routes tie at 197.
        var edges: [[Int]] = []
        for k in 0..<8 { edges.append([k, (k + 1) % 8, 99]) }
        for k in 0..<8 { edges.append([k, (k + 3) % 8, 98]) }
        let s = try scene(n: 8, edges: edges, target: 4)
        XCTAssertEqual(s.items.count, 8 + 16 + 1)
        XCTAssertEqual(s.steps.count, 10)
        XCTAssertEqual(s.steps.last?.say, "A shortest path 0→3→4 costs 197. 4 routes tie at 197; the one found first is shown.")
        XCTAssertEqual(s.values["routes"]?.value, 4)
        XCTAssertEqual(oracleRoutes(n: 8, edges: edges, source: 0, target: 4, directed: false, cost: 197), 4)
        XCTAssertLessThanOrEqual(s.source.canonicalData.count, MGLimits.sceneBytes)
        XCTAssertTrue(s.steps.allSatisfy { $0.say.unicodeScalars.count <= MGLimits.say })
        // All 10 template extras still fit (25 + 10 ≤ 40 resolved); the existing extras bound is unchanged.
        func extras(_ k: Int) -> String { (0..<k).map { #"{"id":"x\#($0)","k":"text","at":[1,1],"text":"t"}"# }.joined(separator: ",") }
        let params = s.source["params"]!.canonicalString
        XCTAssertNil(reason(#"{"v":1,"template":"shortest_path","params":\#(params),"items":[\#(extras(10))]}"#))
        XCTAssertEqual(reason(#"{"v":1,"template":"shortest_path","params":\#(params),"items":[\#(extras(11))]}"#), "items.count")
        let edits = s.steps.reduce(0) { $0 + $1.edits.count }
        print("MG-METRIC largest-graph steps=\(s.steps.count) cumulativeEdits=\(edits) maxStepEdits=\(s.steps.map(\.edits.count).max() ?? 0) canonicalBytes=\(s.source.canonicalData.count)")
        XCTAssertEqual(edits, 53)                                  // indicative only; frame cost is unmeasured
        XCTAssertLessThanOrEqual(edits, 120, "edit replay per frame stays bounded")
    }

    // MARK: registration, patches, streaming

    func testOptInRegistrationLeavesDefaultsUntilRegistered() throws {
        XCTAssertNil(MGTemplates.library["shortest_path"])
        XCTAssertEqual(MGParser.scene(data: Data(MGGraphPack.routerLatencyFixture.utf8)).failureReason, "template.unknown")
        XCTAssertEqual((MGGrammar.document()["templates"] as? [[String: Any]])?.count, MGTemplates.all.count)
        XCTAssertEqual(MGPacks.validate(MGGraphPack.pack), [])
        try MGPacks.register(MGGraphPack.pack)
        XCTAssertNotNil(MGTemplates.library["shortest_path"])
        XCTAssertEqual(MGPacks.pack(ofTemplate: "shortest_path")?.id, "graphs")
        // Registration is once per process; a second call is refused and changes nothing.
        XCTAssertThrowsError(try MGPacks.register(MGGraphPack.pack)) { XCTAssertEqual($0 as? MGPackError, .duplicatePack("graphs")) }
        XCTAssertEqual(MGPacks.all.filter { $0.id == "graphs" }.count, 1)
    }

    func testWhatIfPatchRecomputesOrIsRefusedWhole() throws {
        try MGPacks.register(MGGraphPack.pack)
        let s = try MGParser.scene(data: Data(MGGraphPack.routerLatencyFixture.utf8)).get()
        // What if link 3–4 degrades from 2 ms to 9 ms?
        let slower = try patch(#"{"edges":[[0,1,4],[0,2,1],[2,1,2],[1,3,5],[2,3,8],[2,4,10],[3,4,9],[3,5,6],[4,5,3]]}"#, rev: 0)
        let next = try s.applying(slower).get()
        XCTAssertEqual(next.revision, 1)
        XCTAssertEqual(next.steps.last?.say, "A shortest path 0→2→1→3→5 costs 14. 2 routes tie at 14; the one found first is shown.")
        XCTAssertEqual(last(next)["dist"]?.list, ["0", "3", "1", "8", "11", "14"])
        XCTAssertEqual(next.title, "Router latency (ms)")
        // An invalid what-if (negative latency, stale revision) changes nothing.
        XCTAssertEqual(s.applying(try patch(#"{"edges":[[0,1,-4]]}"#)).failureReason, "template.edges.w")
        XCTAssertEqual(next.applying(slower).failureReason, "patch.stale")
        XCTAssertEqual(last(s)["dist"]?.list, ["0", "3", "1", "8", "10", "13"])
    }

    func testParamsPatchMergesShallowlyReplacesListsWholeAndRejectsNull() throws {
        try MGPacks.register(MGGraphPack.pack)
        let s = try MGParser.scene(data: Data(MGGraphPack.routerLatencyFixture.utf8)).get()
        // A record list is replaced whole: sending one edge leaves one edge, not nine with one changed.
        let one = try s.applying(patch(#"{"edges":[[0,5,7]]}"#)).get()
        XCTAssertEqual(one.items.filter { $0.kind == .edge }.map(\.id), ["e0_5"])
        XCTAssertEqual(one.values["cost"]?.value, 7)
        // Keys that are not sent keep their previous values (shallow merge): target, at and the title stay.
        XCTAssertEqual(one.items.first { $0.id == "n5" }?.pts.first, MGPoint(10.5, 5))
        XCTAssertEqual(one.title, "Router latency (ms)")
        // null is not a deletion: it is rejected and the old scene stays.
        XCTAssertEqual(s.applying(try patch(#"{"at":null}"#)).failureReason, "template.at")
        XCTAssertEqual(s.applying(try patch(#"{"target":null}"#)).failureReason, "template.target")
        // An optional record list is cleared with an empty list (automatic layout). A scalar such as `target` cannot be
        // removed by a patch once set; send a fresh scene instead.
        let auto = try s.applying(patch(#"{"at":[]}"#)).get()
        let n0 = try XCTUnwrap(auto.items.first { $0.id == "n0" }?.pts.first)
        XCTAssertEqual(n0.x, 6, accuracy: 1e-9); XCTAssertEqual(n0.y, 7.4, accuracy: 1e-9)
        XCTAssertEqual(auto.values["cost"]?.value, 13)
        XCTAssertEqual(auto.source["params"]?["target"], .number(5))
    }

    func testCostPlaceholderMakesADisconnectingWhatIfRefusedWhole() throws {
        try MGPacks.register(MGGraphPack.pack)
        let cut = try patch(#"{"edges":[[0,1,4],[0,2,1],[2,1,2],[1,3,5],[2,3,8],[2,4,10],[3,4,2]]}"#, rev: 0)
        let quoted = MGGraphPack.routerLatencyFixture.replacingOccurrences(of: #""title":"Router latency (ms)""#, with: #""title":"Best {cost} ms over {routes} route(s)""#)
        let s = try MGParser.scene(data: Data(quoted.utf8)).get()
        XCTAssertEqual(s.title, "Best 13 ms over 1 route(s)")
        // {cost}/{routes} exist only while the target is reachable, so this what-if is refused and the scene stays.
        XCTAssertEqual(s.applying(cut).failureReason, "title.placeholder.cost")
        // Without them the same what-if is accepted and narrated.
        let plain = try MGParser.scene(data: Data(MGGraphPack.routerLatencyFixture.utf8)).get()
        let next = try plain.applying(cut).get()
        XCTAssertEqual(next.steps.last?.say, "Node 5 is unreachable from 0: no path exists.")
        XCTAssertNil(next.values["cost"]); XCTAssertNil(next.values["routes"])
        XCTAssertEqual(last(next)["n5"]?.color, .muted)
    }

    func testProtocolDocumentationFixturesForRecordParameters() throws {
        func fixture(_ name: String) throws -> Data {
            let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            return try Data(contentsOf: root.appendingPathComponent("docs/fixtures/v1/" + name))
        }
        XCTAssertEqual(MGParser.scene(data: try fixture("shortest-path.scene.json")).failureReason, "template.unknown")
        try MGPacks.register(MGGraphPack.pack)
        let s = try MGParser.scene(data: fixture("shortest-path.scene.json")).get()
        XCTAssertEqual(s.steps[2].say, "Settle 1 at 2, the closest unsettled node. 1→2: 2+2=4 ties 4, earlier route kept.")
        XCTAssertEqual(s.steps.last?.say, "A shortest path 0→2 costs 4. 2 routes tie at 4; the one found first is shown.")
        let edges = try s.applying(MGPatch.parse(data: fixture("shortest-path-edges.patch.json")).get()).get()
        XCTAssertEqual(edges.steps.last?.say, "The shortest path 0→1→2 costs 3.")
        XCTAssertEqual(edges.revision, 1)
        XCTAssertEqual(s.applying(try MGPatch.parse(data: fixture("shortest-path-null.patch.json")).get()).failureReason, "template.target")
    }

    func testStreamingPreviewsOnlyOnceParamsCloseAndMatchesStrictParse() throws {
        try MGPacks.register(MGGraphPack.pack)
        let text = MGGraphPack.routerLatencyFixture
        var stream = MGStreamParser(), previews: [MGScene] = []
        var i = text.startIndex
        while i < text.endIndex {
            let j = text.index(i, offsetBy: 11, limitedBy: text.endIndex) ?? text.endIndex
            if let p = stream.feed(String(text[i..<j])) { previews.append(p) }
            i = j
        }
        XCTAssertFalse(previews.isEmpty)
        XCTAssertTrue(previews.allSatisfy { $0.template == "shortest_path" && $0.items.count == 6 + 9 + 1 })
        XCTAssertEqual(try stream.finish().get(), try MGParser.scene(data: Data(text.utf8)).get())
        var cut = MGStreamParser()
        XCTAssertNil(cut.feed(String(text.prefix(80))))                           // edges still open: nothing provisional
    }
}

private extension Result where Failure == MGError {
    var failureReason: String? { if case .failure(let e) = self { return e.reason }; return nil }
}
