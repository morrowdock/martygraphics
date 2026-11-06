// SPDX-License-Identifier: Apache-2.0
import Foundation

/// Opt-in graph-algorithm pack. It is NOT built in: hosts call `try MGPacks.register(MGGraphPack.pack)` once per process
/// (a second call throws `duplicatePack`), so the default registry, grammar document and existing scenes are unchanged.
/// Until it is registered, scenes naming `shortest_path` are rejected with `template.unknown`.
///
/// `shortest_path` takes a small weighted graph as record-list parameters and computes Dijkstra's algorithm locally.
/// Every distance, settle order, relaxation, tie and final path shown on the board comes from this code, not from the
/// scene author; a `params` patch ("what if this link cost 9?") recomputes the whole walkthrough or is refused whole.
///
/// Edge ids are semantic, not positional. An undirected link between nodes i < j is `e<i>_<j>` whatever the endpoint
/// order in its record; a directed arc from tail t to head h is `d<t>_<h>`. Reordering edge records therefore keeps every
/// id, `over`/`hide` entry and step reference on the same link. Reversing an arc or toggling `directed` changes the id, so
/// persisted `over`/`hide` entries naming the old link are refused (`over.ref`/`hide.ref`), never moved to another link.
///
/// Bounds (rejected, never clamped; PROPOSED, not accepted): 2–8 nodes, 1–16 edges, integer weights 0–99 (Dijkstra needs
/// non-negative weights), no self-loops and at most one edge per node pair even when directed (so anti-parallel arcs
/// such as a→b 3 and b→a 7 are not expressible). Optional node positions: none (automatic circle) or exactly one per
/// node, at least 1.2 world units apart, with every edge at least 0.6 from every node that is not one of its endpoints
/// (an edge drawn through a node would read as two links). 2D only. The walkthrough is one intro step, one step per
/// settled node and one summary step (at most 10 of the 48 template steps).
///
/// Not accepted visually: dense automatic layouts. With an even node count every diameter chord has the same midpoint,
/// so weight labels can coincide; pass `at` positions for dense graphs. Colour still carries edge state (no
/// accessibility acceptance).
public enum MGGraphPack {
    public static let maxNodes = 8, maxEdges = 16
    /// Minimum centre distance between authored node positions, in world units.
    static let minNodeGap = 1.2
    /// Minimum distance between an edge segment and any node centre that is not one of its endpoints (node radius 0.45
    /// plus a 0.15 margin).
    static let nodeRadius = 0.45, edgeClearance = 0.6
    /// Absorbs decimal representation in the geometry checks: positions exactly 1.2 apart are accepted whatever their
    /// binary rounding (for example 10.3 and 11.5).
    static let tolerance = 1e-9

    public static let shortestPath = MGTemplate(
        name: "shortest_path",
        summary: "Dijkstra shortest paths on a small weighted graph; settle order, relaxations, ties and final path computed locally",
        params: [
            .init(name: "n", unit: "", range: 2...Double(maxNodes), integer: true),
            .records("edges", count: 1...maxEdges, fields: [.init("a", 0...Double(maxNodes - 1), integer: true),
                                                             .init("b", 0...Double(maxNodes - 1), integer: true),
                                                             .init("w", 0...99, integer: true)]),
            .init(name: "source", unit: "", range: 0...Double(maxNodes - 1), defaultValue: 0, integer: true),
            .init(name: "target", unit: "", range: 0...Double(maxNodes - 1), defaultValue: .infinity, integer: true),
            .init(name: "directed", unit: "", range: 0...1, defaultValue: 0, integer: true),
            .records("at", count: 0...maxNodes, fields: [.init("x", 0.5...11.5), .init("y", 2...7.5)]),
        ],
        reject: { p in
            if case .failure(let problem) = graph(p) { return problem.reason }
            return nil
        },
        make: { p, is3D in
            guard !is3D, case .success(let g) = graph(p) else { return nil }
            return build(g)
        })

    public static let pack = MGPack(
        id: "graphs", title: "Graphs: algorithms", summary: "weighted shortest paths computed locally",
        templates: [shortestPath],
        fixtures: [.init(id: "router_latency", title: "Router latency paths", json: routerLatencyFixture)],
        fewShots: [MGFewShot(ask: "Which route has the lowest total latency from router 0 to router 5?", fixture: "router_latency")])

    /// Original synthetic example: six routers, link latencies in milliseconds. The direct-looking routes are not the
    /// cheapest; the computed answer is 0→2→1→3→4→5 at 13, and it is the only route at that cost.
    public static let routerLatencyFixture =
        #"{"v":1,"template":"shortest_path","params":{"n":6,"source":0,"target":5,"#
        + #""edges":[[0,1,4],[0,2,1],[2,1,2],[1,3,5],[2,3,8],[2,4,10],[3,4,2],[3,5,6],[4,5,3]],"#
        + #""at":[[1.5,5],[4.5,7],[4.5,3],[7.5,7],[7.5,3],[10.5,5]]},"title":"Router latency (ms)"}"#

    // MARK: validated graph

    /// Undirected edges are stored with `a < b`; directed edges keep tail `a` and head `b`.
    struct Edge: Equatable { let a: Int, b: Int, w: Int }
    struct Graph: Equatable {
        let n: Int, source: Int, target: Int?, directed: Bool
        /// Sorted by unordered endpoint pair, so record order never changes ids, item order, narration or results.
        let edges: [Edge]
        let at: [MGPoint]
        func id(_ k: Int) -> String { let e = edges[k]; return directed ? "d\(e.a)_\(e.b)" : "e\(e.a)_\(e.b)" }
    }

    /// A specific cross-parameter rejection, reported as `template.<reason>`.
    struct Problem: Error, Equatable { let reason: String }

    /// Cross-parameter rules with a specific reason for each rejection.
    static func graph(_ p: MGParams) -> Result<Graph, Problem> {
        let n = Int(p["n"]), source = Int(p["source"]), directed = p["directed"] == 1
        guard (2...maxNodes).contains(n) else { return .failure(.init(reason: "n")) }
        guard (0..<n).contains(source) else { return .failure(.init(reason: "source.range")) }
        var target: Int?
        let t = p["target"]
        if t.isFinite {
            guard t.rounded() == t else { return .failure(.init(reason: "target.integer")) }
            guard (0..<n).contains(Int(t)) else { return .failure(.init(reason: "target.range")) }
            target = Int(t)
        }
        var edges: [Edge] = [], pairs = Set<[Int]>()
        for r in p.records["edges"] ?? [] {
            guard r.count == 3 else { return .failure(.init(reason: "edges.arity")) }
            let a = Int(r[0]), b = Int(r[1])
            guard a < n, b < n else { return .failure(.init(reason: "edges.node")) }
            guard a != b else { return .failure(.init(reason: "edges.loop")) }
            // One edge per unordered pair, even when directed: two anti-parallel arrows would draw on one line.
            guard pairs.insert([min(a, b), max(a, b)]).inserted else { return .failure(.init(reason: "edges.duplicate")) }
            edges.append(directed ? Edge(a: a, b: b, w: Int(r[2])) : Edge(a: min(a, b), b: max(a, b), w: Int(r[2])))
        }
        guard !edges.isEmpty else { return .failure(.init(reason: "edges.count")) }
        edges.sort { (min($0.a, $0.b), max($0.a, $0.b)) < (min($1.a, $1.b), max($1.a, $1.b)) }

        let given = (p.records["at"] ?? []).map { MGPoint($0[0], $0[1]) }
        let at: [MGPoint]
        if given.isEmpty {
            // Clockwise from the top on a circle above the distance array.
            at = (0..<n).map { MGPoint(6, 4.9) + MGPoint.polar(90 - 360 * Double($0) / Double(n), 2.5) }
        } else {
            guard given.count == n else { return .failure(.init(reason: "at.count")) }
            for i in 0..<n { for j in (i + 1)..<n where (given[i] - given[j]).length < minNodeGap - tolerance {
                return .failure(.init(reason: "at.gap"))
            } }
            at = given
        }
        // Applied to automatic layouts too (they always pass: the closest node to any chord is at least 0.73 away).
        for e in edges {
            for i in 0..<n where i != e.a && i != e.b && distance(at[i], at[e.a], at[e.b]) < edgeClearance - tolerance {
                return .failure(.init(reason: "at.crossing"))
            }
        }
        return .success(Graph(n: n, source: source, target: target, directed: directed, edges: edges, at: at))
    }

    /// Distance from `p` to the segment `a`–`b` (2D).
    static func distance(_ p: MGPoint, _ a: MGPoint, _ b: MGPoint) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y, len2 = dx * dx + dy * dy
        let s = len2 > 0 ? max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2)) : 0
        let cx = a.x + s * dx - p.x, cy = a.y + s * dy - p.y
        return (cx * cx + cy * cy).squareRoot()
    }

    // MARK: Dijkstra

    /// Outgoing edges of `u` (both directions when undirected), by neighbour index.
    static func neighbours(_ g: Graph, _ u: Int) -> [(edge: Int, to: Int, w: Int)] {
        var out: [(edge: Int, to: Int, w: Int)] = []
        for (k, e) in g.edges.enumerated() {
            if e.a == u { out.append((k, e.b, e.w)) } else if !g.directed, e.b == u { out.append((k, e.a, e.w)) }
        }
        return out.sorted { $0.to < $1.to }
    }

    /// Number of distinct simple source→target paths whose total weight equals `cost` (exact; at most 1,957 for 8 nodes).
    static func routes(_ g: Graph, to target: Int, cost: Int) -> Int {
        var count = 0, onPath = [Bool](repeating: false, count: g.n)
        func walk(_ u: Int, _ sum: Int) {
            if u == target { if sum == cost { count += 1 }; return }
            onPath[u] = true
            for (_, v, w) in neighbours(g, u) where !onPath[v] && sum + w <= cost { walk(v, sum + w) }
            onPath[u] = false
        }
        walk(g.source, 0)
        return count
    }

    static func symbol(_ d: Int?) -> String { d.map(String.init) ?? "∞" }

    /// The array pointer: `u` marks the node being settled, `t` the target in the summary.
    struct Pointer: Equatable { let node: Int, label: String }

    /// Snapshot of every edited key; successive snapshots are diffed into step edits.
    struct Board: Equatable {
        var node: [MGColorRole], edge: [MGColorRole]
        var dist: [Int?], settled: [Int], pointer: Pointer?
    }

    static func edits(from a: Board, to b: Board, _ g: Graph) -> [MGEdit] {
        var out: [MGEdit] = []
        for i in b.node.indices where a.node[i] != b.node[i] { out.append(.init(id: "n\(i)", key: "color", value: .string(b.node[i].rawValue))) }
        for k in b.edge.indices where a.edge[k] != b.edge[k] { out.append(.init(id: g.id(k), key: "color", value: .string(b.edge[k].rawValue))) }
        if a.dist != b.dist { out.append(.init(id: "dist", key: "vals", value: .array(b.dist.map { .string(symbol($0)) }))) }
        if a.settled != b.settled { out.append(.init(id: "dist", key: "marked", value: .array(b.settled.sorted().map { .number(Double($0)) }))) }
        if a.pointer != b.pointer {
            out.append(.init(id: "dist", key: "ptrs", value: .array(b.pointer.map { [.object(["i": .number(Double($0.node)), "label": .string($0.label)])] } ?? [])))
        }
        return out
    }

    static func build(_ g: Graph) -> MGTemplateBuild {
        var dist = [Int?](repeating: nil, count: g.n), prev = [Int?](repeating: nil, count: g.n)
        var settled: [Int] = []
        dist[g.source] = 0
        var board = Board(node: .init(repeating: .blue, count: g.n), edge: .init(repeating: .muted, count: g.edges.count),
                          dist: dist, settled: [], pointer: nil)
        board.node[g.source] = .warn

        var items: [MGItem] = []
        for (k, e) in g.edges.enumerated() {
            var it = MGItem(id: g.id(k), kind: .edge, color: .muted); it.ref = "n\(e.a)"; it.ref2 = "n\(e.b)"; it.label = String(e.w)
            if g.directed { it.flags.insert("dir") }
            items.append(it)
        }
        for i in 0..<g.n {
            var it = MGMake.kind("n\(i)", .node, [g.at[i]], ["r": nodeRadius], color: board.node[i]); it.text = String(i); items.append(it)
        }
        var array = MGMake.kind("dist", .array, [MGPoint(6, 0.9)], ["cell": 0.85], color: .blue, label: "dist")
        array.list = dist.map(symbol)
        items.append(array)

        var steps = [MGStep(say: "Dijkstra from \(g.source)\(g.directed ? " on directed edges" : ""). Weights are non-negative, so the closest unsettled node's distance is final.",
                            focus: "n\(g.source)")]
        while settled.count < g.n {
            // Closest unsettled reachable node; ties go to the lowest index (deterministic).
            guard let u = (0..<g.n).filter({ !settled.contains($0) && dist[$0] != nil }).min(by: { (dist[$0]!, $0) < (dist[$1]!, $1) }) else { break }
            let du = dist[u]!
            settled.append(u)
            var next = board
            next.node[u] = .good; next.settled = settled; next.pointer = Pointer(node: u, label: "u")
            if let e = prev[u] { next.edge[e] = .good }
            var notes: [String] = [], improved = 0, tied = 0
            for (k, v, w) in neighbours(g, u) where !settled.contains(v) {
                let alt = du + w
                if let old = dist[v], alt >= old {
                    // An equal-cost route is disclosed but not taken: the route found first stays.
                    if alt == old { tied += 1; notes.append("\(u)→\(v): \(du)+\(w)=\(alt) ties \(old), earlier route kept.") }
                    continue
                }
                improved += 1
                notes.append("\(u)→\(v): \(du)+\(w)=\(alt) beats \(symbol(dist[v])).")
                if let old = prev[v] { next.edge[old] = .muted }
                dist[v] = alt; prev[v] = k
                next.edge[k] = .warn; next.node[v] = .warn
            }
            next.dist = dist
            let head = "Settle \(u) at \(du), the closest unsettled node."
            var say = notes.isEmpty ? "\(head) No neighbour improves." : "\(head) " + notes.joined(separator: " ")
            if say.unicodeScalars.count > MGLimits.say {
                say = "\(head) \(improved) improved (orange)" + (tied > 0 ? ", \(tied) tied (earlier route kept)." : ".")
            }
            steps.append(MGStep(say: say, focus: "n\(u)", edits: edits(from: board, to: next, g)))
            board = next
        }

        // Summary step.
        var final = board
        final.pointer = nil
        let unreachable = (0..<g.n).filter { dist[$0] == nil }
        for i in unreachable { final.node[i] = .muted }
        var values: [String: MGValue] = ["n": .init(value: Double(g.n), unit: ""), "m": .init(value: Double(g.edges.count), unit: ""),
                                         "reached": .init(value: Double(settled.count), unit: "")]
        var say: String
        var focus: String?
        if let t = g.target {
            if t == g.source {
                values["cost"] = .init(value: 0, unit: ""); values["routes"] = .init(value: 1, unit: "")
                say = "Target \(t) is the source itself, so the path is just node \(t) and costs 0."
                final.pointer = Pointer(node: t, label: "t"); focus = "n\(t)"
            } else if let cost = dist[t] {
                var path = [t], at = t
                while let e = prev[at] { let edge = g.edges[e]; at = edge.a == at ? edge.b : edge.a; path.append(at); final.edge[e] = .yellow }
                path.reverse()
                let count = routes(g, to: t, cost: cost)
                values["cost"] = .init(value: Double(cost), unit: ""); values["routes"] = .init(value: Double(count), unit: "")
                let route = path.map(String.init).joined(separator: "→")
                say = count == 1 ? "The shortest path \(route) costs \(cost)."
                    : "A shortest path \(route) costs \(cost). \(count) routes tie at \(cost); the one found first is shown."
                final.pointer = Pointer(node: t, label: "t"); focus = "n\(t)"
            } else {
                say = "Node \(t) is unreachable from \(g.source): no path exists."
                focus = "n\(t)"
            }
        } else {
            say = "Done: green edges form a shortest-path tree from \(g.source)."
            let hasAlternative = (0..<g.n).contains { target in
                guard target != g.source, let cost = dist[target] else { return false }
                return routes(g, to: target, cost: cost) > 1
            }
            if hasAlternative { say += " Multiple shortest simple paths exist; the tree found first is shown." }
        }
        if !unreachable.isEmpty, g.target.map({ dist[$0] != nil }) ?? true {
            say += " Unreachable: \(unreachable.map(String.init).joined(separator: ", "))."
        }
        steps.append(MGStep(say: String(String.UnicodeScalarView(say.unicodeScalars.prefix(MGLimits.say))), focus: focus, edits: edits(from: board, to: final, g)))
        return MGTemplateBuild(title: "Shortest paths from \(g.source)", items: items, steps: steps, values: values)
    }
}
