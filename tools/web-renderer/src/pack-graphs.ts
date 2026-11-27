// SPDX-License-Identifier: Apache-2.0
// The opt-in graph pack (Sources/MartyGraphics/MGGraphPack.swift): `shortest_path`, Dijkstra on a small weighted
// graph computed locally. Not built in: a caller enables it with the `graphs` pack, as Showcase registers it and as
// the Python preflight's `--pack graphs` does. Until then `shortest_path` is `template.unknown`.

import { type JSONValue, newObject } from "./json.js";
import { MGLimits } from "./limits.js";
import { type MGColorRole, type MGEdit, type MGItem, type MGPoint, type MGStep, type MGValue, P, add, newItem, polar, sub, length } from "./model.js";
import { makeKind } from "./templates-core.js";
import { type Params, type Template, param, registerPack } from "./templates.js";
import { scalarCount, scalarPrefix } from "./unicode.js";

const maxNodes = 8;
const maxEdges = 16;
const minNodeGap = 1.2;
const nodeRadius = 0.45;
const edgeClearance = 0.6;
const tolerance = 1e-9;

interface Edge { a: number; b: number; w: number }
interface Graph {
  n: number;
  source: number;
  target: number | null;
  directed: boolean;
  edges: Edge[];
  at: MGPoint[];
}

const edgeId = (g: Graph, k: number) => (g.directed ? `d${g.edges[k].a}_${g.edges[k].b}` : `e${g.edges[k].a}_${g.edges[k].b}`);

function distance(p: MGPoint, a: MGPoint, b: MGPoint): number {
  const dx = b.x - a.x;
  const dy = b.y - a.y;
  const len2 = dx * dx + dy * dy;
  const s = len2 > 0 ? Math.max(0, Math.min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2)) : 0;
  const cx = a.x + s * dx - p.x;
  const cy = a.y + s * dy - p.y;
  return Math.sqrt(cx * cx + cy * cy);
}

function graph(p: Params): Graph | { reason: string } {
  const n = Math.trunc(param(p, "n"));
  const source = Math.trunc(param(p, "source"));
  const directed = param(p, "directed") === 1;
  if (n < 2 || n > maxNodes) return { reason: "n" };
  if (source < 0 || source >= n) return { reason: "source.range" };
  let target: number | null = null;
  const t = param(p, "target");
  if (Number.isFinite(t)) {
    if (Math.round(t) !== t) return { reason: "target.integer" };
    if (t < 0 || t >= n) return { reason: "target.range" };
    target = t;
  }
  const edges: Edge[] = [];
  const pairs = new Set<string>();
  for (const r of p.records["edges"] ?? []) {
    if (r.length !== 3) return { reason: "edges.arity" };
    const a = Math.trunc(r[0]);
    const b = Math.trunc(r[1]);
    if (!(a < n && b < n)) return { reason: "edges.node" };
    if (a === b) return { reason: "edges.loop" };
    const key = `${Math.min(a, b)},${Math.max(a, b)}`;
    if (pairs.has(key)) return { reason: "edges.duplicate" };
    pairs.add(key);
    edges.push(directed ? { a, b, w: Math.trunc(r[2]) } : { a: Math.min(a, b), b: Math.max(a, b), w: Math.trunc(r[2]) });
  }
  if (edges.length === 0) return { reason: "edges.count" };
  edges.sort((x, y) => {
    const x0 = Math.min(x.a, x.b), x1 = Math.max(x.a, x.b), y0 = Math.min(y.a, y.b), y1 = Math.max(y.a, y.b);
    return x0 !== y0 ? x0 - y0 : x1 - y1;
  });
  const given = (p.records["at"] ?? []).map((r) => P(r[0], r[1]));
  let at: MGPoint[];
  if (given.length === 0) {
    at = Array.from({ length: n }, (_, i) => add(P(6, 4.9), polar(90 - (360 * i) / n, 2.5)));
  } else {
    if (given.length !== n) return { reason: "at.count" };
    for (let i = 0; i < n; i++) for (let j = i + 1; j < n; j++) if (length(sub(given[i], given[j])) < minNodeGap - tolerance) return { reason: "at.gap" };
    at = given;
  }
  for (const e of edges) {
    for (let i = 0; i < n; i++) {
      if (i !== e.a && i !== e.b && distance(at[i], at[e.a], at[e.b]) < edgeClearance - tolerance) return { reason: "at.crossing" };
    }
  }
  return { n, source, target, directed, edges, at };
}

function neighbours(g: Graph, u: number): Array<{ edge: number; to: number; w: number }> {
  const out: Array<{ edge: number; to: number; w: number }> = [];
  g.edges.forEach((e, k) => {
    if (e.a === u) out.push({ edge: k, to: e.b, w: e.w });
    else if (!g.directed && e.b === u) out.push({ edge: k, to: e.a, w: e.w });
  });
  return out.sort((x, y) => x.to - y.to);
}

function routes(g: Graph, target: number, cost: number): number {
  let count = 0;
  const onPath = new Array<boolean>(g.n).fill(false);
  const walk = (u: number, sum: number) => {
    if (u === target) {
      if (sum === cost) count += 1;
      return;
    }
    onPath[u] = true;
    for (const { to, w } of neighbours(g, u)) if (!onPath[to] && sum + w <= cost) walk(to, sum + w);
    onPath[u] = false;
  };
  walk(g.source, 0);
  return count;
}

const symbol = (d: number | null) => (d === null ? "∞" : String(d));

interface Pointer { node: number; label: string }
interface Board {
  node: MGColorRole[];
  edge: MGColorRole[];
  dist: Array<number | null>;
  settled: number[];
  pointer: Pointer | null;
}

const cloneBoard = (b: Board): Board => ({
  node: [...b.node], edge: [...b.edge], dist: [...b.dist], settled: [...b.settled], pointer: b.pointer ? { ...b.pointer } : null,
});

function edits(a: Board, b: Board, g: Graph): MGEdit[] {
  const out: MGEdit[] = [];
  b.node.forEach((c, i) => { if (a.node[i] !== c) out.push({ id: `n${i}`, key: "color", value: c }); });
  b.edge.forEach((c, k) => { if (a.edge[k] !== c) out.push({ id: edgeId(g, k), key: "color", value: c }); });
  if (a.dist.map(symbol).join("|") !== b.dist.map(symbol).join("|")) out.push({ id: "dist", key: "vals", value: b.dist.map(symbol) });
  if (a.settled.join(",") !== b.settled.join(",")) out.push({ id: "dist", key: "marked", value: [...b.settled].sort((x, y) => x - y) });
  const samePointer = (a.pointer === null && b.pointer === null) ||
    (a.pointer !== null && b.pointer !== null && a.pointer.node === b.pointer.node && a.pointer.label === b.pointer.label);
  if (!samePointer) {
    const value: JSONValue = b.pointer ? [newObject([["i", b.pointer.node], ["label", b.pointer.label]])] : [];
    out.push({ id: "dist", key: "ptrs", value });
  }
  return out;
}

function build(g: Graph) {
  const dist: Array<number | null> = new Array(g.n).fill(null);
  const prev: Array<number | null> = new Array(g.n).fill(null);
  const settled: number[] = [];
  dist[g.source] = 0;
  let board: Board = { node: new Array(g.n).fill("blue"), edge: new Array(g.edges.length).fill("muted"), dist: [...dist], settled: [], pointer: null };
  board.node[g.source] = "warn";

  const items: MGItem[] = [];
  g.edges.forEach((e, k) => {
    const it = newItem(edgeId(g, k), "edge", "muted");
    it.ref = `n${e.a}`;
    it.ref2 = `n${e.b}`;
    it.label = String(e.w);
    if (g.directed) it.flags.add("dir");
    items.push(it);
  });
  for (let i = 0; i < g.n; i++) {
    const it = makeKind(`n${i}`, "node", [g.at[i]], { r: nodeRadius }, board.node[i]);
    it.text = String(i);
    items.push(it);
  }
  const array = makeKind("dist", "array", [P(6, 0.9)], { cell: 0.85 }, "blue", "dist");
  array.list = dist.map(symbol);
  items.push(array);

  const steps: MGStep[] = [{
    say: `Dijkstra from ${g.source}${g.directed ? " on directed edges" : ""}. Weights are non-negative, so the closest unsettled node's distance is final.`,
    show: [], focus: `n${g.source}`, edits: [],
  }];
  while (settled.length < g.n) {
    const candidates = Array.from({ length: g.n }, (_, i) => i).filter((i) => !settled.includes(i) && dist[i] !== null);
    if (candidates.length === 0) break;
    const u = candidates.reduce((best, i) => (dist[i]! < dist[best]! || (dist[i] === dist[best] && i < best) ? i : best));
    const du = dist[u]!;
    settled.push(u);
    const next = cloneBoard(board);
    next.node[u] = "good";
    next.settled = [...settled];
    next.pointer = { node: u, label: "u" };
    const pu = prev[u];
    if (pu !== null) next.edge[pu] = "good";
    const notes: string[] = [];
    let improved = 0;
    let tied = 0;
    for (const { edge: k, to: v, w } of neighbours(g, u)) {
      if (settled.includes(v)) continue;
      const alt = du + w;
      const old = dist[v];
      if (old !== null && alt >= old) {
        if (alt === old) {
          tied += 1;
          notes.push(`${u}→${v}: ${du}+${w}=${alt} ties ${old}, earlier route kept.`);
        }
        continue;
      }
      improved += 1;
      notes.push(`${u}→${v}: ${du}+${w}=${alt} beats ${symbol(dist[v])}.`);
      const po = prev[v];
      if (po !== null) next.edge[po] = "muted";
      dist[v] = alt;
      prev[v] = k;
      next.edge[k] = "warn";
      next.node[v] = "warn";
    }
    next.dist = [...dist];
    const head = `Settle ${u} at ${du}, the closest unsettled node.`;
    let sayText = notes.length === 0 ? `${head} No neighbour improves.` : `${head} ` + notes.join(" ");
    if (scalarCount(sayText) > MGLimits.say) {
      sayText = `${head} ${improved} improved (orange)` + (tied > 0 ? `, ${tied} tied (earlier route kept).` : ".");
    }
    steps.push({ say: sayText, show: [], focus: `n${u}`, edits: edits(board, next, g) });
    board = next;
  }

  const final = cloneBoard(board);
  final.pointer = null;
  const unreachable = Array.from({ length: g.n }, (_, i) => i).filter((i) => dist[i] === null);
  for (const i of unreachable) final.node[i] = "muted";
  const values: Record<string, MGValue> = {
    n: { value: g.n, unit: "" }, m: { value: g.edges.length, unit: "" }, reached: { value: settled.length, unit: "" },
  };
  let sayText: string;
  let focus: string | undefined;
  if (g.target !== null) {
    const t = g.target;
    const cost = dist[t];
    if (t === g.source) {
      values["cost"] = { value: 0, unit: "" };
      values["routes"] = { value: 1, unit: "" };
      sayText = `Target ${t} is the source itself, so the path is just node ${t} and costs 0.`;
      final.pointer = { node: t, label: "t" };
      focus = `n${t}`;
    } else if (cost !== null) {
      const path = [t];
      let at = t;
      for (let e = prev[at]; e !== null; e = prev[at]) {
        const edge = g.edges[e];
        at = edge.a === at ? edge.b : edge.a;
        path.push(at);
        final.edge[e] = "yellow";
      }
      path.reverse();
      const count = routes(g, t, cost);
      values["cost"] = { value: cost, unit: "" };
      values["routes"] = { value: count, unit: "" };
      const route = path.map(String).join("→");
      sayText = count === 1 ? `The shortest path ${route} costs ${cost}.`
        : `A shortest path ${route} costs ${cost}. ${count} routes tie at ${cost}; the one found first is shown.`;
      final.pointer = { node: t, label: "t" };
      focus = `n${t}`;
    } else {
      sayText = `Node ${t} is unreachable from ${g.source}: no path exists.`;
      focus = `n${t}`;
    }
  } else {
    sayText = `Done: green edges form a shortest-path tree from ${g.source}.`;
    const hasAlternative = Array.from({ length: g.n }, (_, i) => i).some((target) => {
      const cost = dist[target];
      if (target === g.source || cost === null) return false;
      return routes(g, target, cost) > 1;
    });
    if (hasAlternative) sayText += " Multiple shortest simple paths exist; the tree found first is shown.";
  }
  if (unreachable.length > 0 && (g.target === null || dist[g.target] !== null)) {
    sayText += ` Unreachable: ${unreachable.map(String).join(", ")}.`;
  }
  steps.push({ say: scalarPrefix(sayText, MGLimits.say), show: [], focus, edits: edits(board, final, g) });
  return { title: `Shortest paths from ${g.source}`, width: 12, height: 8, items, steps, values };
}

export const shortestPath: Template = {
  name: "shortest_path",
  summary: "Dijkstra shortest paths on a small weighted graph; settle order, relaxations, ties and final path computed locally",
  params: [
    { name: "n", unit: "", range: [2, maxNodes], integer: true },
    { name: "edges", unit: "", range: [0, 0], count: [1, maxEdges], fields: [
      { name: "a", range: [0, maxNodes - 1], integer: true },
      { name: "b", range: [0, maxNodes - 1], integer: true },
      { name: "w", range: [0, 99], integer: true },
    ] },
    { name: "source", unit: "", range: [0, maxNodes - 1], defaultValue: 0, integer: true },
    { name: "target", unit: "", range: [0, maxNodes - 1], defaultValue: Infinity, integer: true },
    { name: "directed", unit: "", range: [0, 1], defaultValue: 0, integer: true },
    { name: "at", unit: "", range: [0, 0], count: [0, maxNodes], fields: [
      { name: "x", range: [0.5, 11.5], integer: false },
      { name: "y", range: [2, 7.5], integer: false },
    ] },
  ],
  reject: (p) => {
    const g = graph(p);
    return "reason" in g ? g.reason : null;
  },
  make: (p, is3D) => {
    if (is3D) return null;
    const g = graph(p);
    if ("reason" in g) return null;
    return build(g);
  },
};

registerPack("graphs", [shortestPath]);
