// SPDX-License-Identifier: Apache-2.0
// Computed values against Swift: number formatting, the strict JSON front door, step playback (ported
// TimelineRegressionTests), template narration (the captions printed in the Swift captures under docs/assets/native,
// and the strings pinned by RecordParamsShortestPathTests), patches and revisions (ProtocolFixtureTests), and the
// wire round trip of every kind (ParserRegressionTests.testEveryKindRoundTripsThroughItsWireForm).

import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { test } from "node:test";
import { REPO_ROOT, regressionFixtures } from "./corpus.mjs";
import { MG } from "./helpers.mjs";

const enc = (s) => Buffer.from(s, "utf8");
const scene = (json, packs = []) => MG.parseSceneBytes(enc(json), { packs });
const reason = (fn) => {
  try {
    fn();
    return null;
  } catch (e) {
    if (e?.reason) return e.reason;
    throw e;
  }
};
const showcase = (name) => fs.readFileSync(path.join(REPO_ROOT, "Examples", "Showcase", "Sources", "MartyShowcase", "Scenes", name));
const fixture = (name) => fs.readFileSync(path.join(REPO_ROOT, "docs", "fixtures", "v1", name));
const R = regressionFixtures();
const patchBytes = (params, rev) => enc(`{"v":1,${rev === undefined ? "" : `"rev":${rev},`}"ops":[{"op":"params","params":${params}}]}`);
const applyParams = (s, params, rev) => MG.applyPatch(s, MG.parsePatchBytes(patchBytes(params, rev)));
const lastBoard = (s) => new Map(MG.itemsAtStep(s, s.steps.length - 1).map((i) => [i.id, i]));

// MARK: number formatting (MGPhysics.format)

test("format: about three significant figures, printf rounding with ties to even", () => {
  const cases = [
    [0, "0"], [1, "1"], [2.5, "2.5"], [0.125, "0.12"], [0.375, "0.38"], [0.005, "0.01"], [-0.001, "0"], [-0, "0"],
    [12.25, "12.2"], [12.35, "12.3"], [99.95, "100"], [100.5, "100"], [101.5, "102"], [-2.5, "-2.5"], [1234.5, "1234"],
    [3.14159, "3.14"], [10, "10"], [999999, "999999"], [1e-9, "0"],
  ];
  for (const [v, s] of cases) assert.equal(MG.format(v, ""), s, `format(${v})`);
  assert.equal(MG.format(45, "°"), "45°");
  assert.equal(MG.format(30, "items"), "30 items");
  assert.equal(MG.format(NaN, ""), "—");
  assert.equal(MG.formatFixed(0.125, 2), "0.12");
  assert.equal(MG.formatFixed(-0.0001, 2), "-0.00");
});

// MARK: JSON front door

test("json: UTF-8 only, no NUL, nesting 64, strict grammar, unique keys, finite numbers", () => {
  const body = '"items":[{"id":"dot","k":"body","at":[3,4]}]';
  const ok = `{"v":1,${body}}`;
  assert.equal(reason(() => scene(ok)), null);
  assert.equal(reason(() => MG.parseSceneBytes(Buffer.concat([Buffer.from([0xef, 0xbb, 0xbf]), enc(ok)]))), "json"); // BOM
  assert.equal(reason(() => scene(`{"v":1,"v":1,${body}}`)), "json"); // duplicate key
  assert.equal(reason(() => scene(`{"v":1,${body},"title":"a\u0000"}`)), "json"); // NUL byte
  assert.equal(reason(() => scene(`{"v":1,${body},"title":"\\ud800"}`)), "json"); // lone surrogate escape
  assert.equal(reason(() => scene(`{"v":1e400,${body}}`)), "json"); // MGJSON(any:) refuses a non-finite number
  assert.equal(reason(() => scene(`{"v":1,${body},}`)), "json");
  assert.equal(reason(() => scene("5")), "json");
  assert.equal(reason(() => scene("[" .repeat(64) + "]".repeat(64))), "scene.object");
  assert.equal(reason(() => scene("[".repeat(65) + "]".repeat(65))), "scene.depth");
  assert.equal(reason(() => scene(`{"v":1,${body},"x":"[[[[${"[".repeat(80)}"}`)), "scene.unknown.x"); // brackets in strings do not nest
  assert.equal(reason(() => scene(`{"v":1.0,${body}}`)), null);
});

test("json: canonical byte count is the compact sorted-key UTF-8 length", () => {
  const sorted = (v) => (Array.isArray(v) ? v.map(sorted) : v && typeof v === "object"
    ? Object.fromEntries(Object.keys(v).sort().map((k) => [k, sorted(v[k])])) : v);
  for (const text of ['{"b":[1,2.5,-0.125],"a":"x\\ny","c":{"z":null,"y":true,"x":false}}', '{"k":"é∞ \\"q\\"","n":[0.5,12,-3.75]}']) {
    const v = MG.parseJSONText(text);
    assert.equal(MG.canonicalByteCount(v), Buffer.byteLength(JSON.stringify(sorted(v))), text);
  }
  // Exponents are spelled as Python's repr and Swift's description spell them (at least two digits).
  assert.equal(MG.canonicalByteCount(MG.parseJSONText('{"n":1e-7}')), '{"n":1e-07}'.length);
  assert.equal(MG.spellNumber(0.1), "0.1");
  assert.equal(MG.spellNumber(1e-7), "1e-07");
  assert.equal(MG.spellNumber(0.00001), "1e-05");
  assert.equal(MG.spellNumber(0.0001), "0.0001");
  assert.equal(MG.spellNumber(1e21), "1000000000000000000000");
  assert.equal(MG.spellNumber(-0), "0");
  assert.equal(MG.canonicalByteCount(MG.parseJSONText('{"a":[1,"é"]}')), Buffer.byteLength('{"a":[1,"é"]}'));
});

// MARK: step playback (TimelineRegressionTests)

test("timeline: step gating, anchor hiding and cumulative edits", () => {
  const s = scene(R.timeline);
  assert.deepEqual(Object.fromEntries(MG.firstShown(s)), { ball: 1, nb: 2, mark: 2 });
  const ids = (k) => MG.itemsAtStep(s, k).map((i) => i.id);
  assert.deepEqual(ids(0), ["na", "arr"]);
  assert.deepEqual(ids(1), ["ball", "push", "na", "arr"]);
  assert.deepEqual(ids(2), ["ball", "push", "na", "nb", "ab", "mark", "arr"]);
  const arr = (k) => MG.itemsAtStep(s, k).find((i) => i.id === "arr");
  assert.deepEqual(arr(0).pointers.map((p) => p.index), [0]);
  assert.deepEqual(arr(1).pointers.map((p) => p.index), [1]);
  assert.deepEqual(arr(1).marked, []);
  assert.deepEqual(arr(2).pointers.map((p) => p.index), [1]);
  assert.deepEqual(arr(2).marked, [1]);
  assert.deepEqual(MG.itemsAtStep(s, -5), MG.itemsAtStep(s, 0));
  assert.deepEqual(MG.itemsAtStep(s, 99), MG.itemsAtStep(s, 2));
});

test("timeline: a scene without steps shows everything at any step", () => {
  const s = scene(R.allKinds);
  assert.equal(s.steps.length, 0);
  for (const k of [-1, 0, 3]) assert.deepEqual(MG.itemsAtStep(s, k), s.items);
});

test("timeline: frames are pure, clamp negative time and carry attached vectors", () => {
  const demos = Object.fromEntries((mgDemos()).map((d) => [d.id, d.json]));
  const dot = scene(demos.moving_dot);
  assert.deepEqual(MG.frame(dot, dot.items, -3), MG.frame(dot, dot.items, 0));
  const mid = MG.frame(dot, dot.items, 1).find((i) => i.id === "dot");
  assert.deepEqual(mid.pts, [{ x: 5, y: 4, z: 0 }]);
  const glide = scene(R.glide);
  const tail = (t) => MG.frame(glide, glide.items, t).find((i) => i.id === "f").pts;
  assert.deepEqual(tail(0), [{ x: 2, y: 4, z: 0 }]);
  assert.deepEqual(tail(2), [{ x: 6, y: 4, z: 0 }]);
  assert.deepEqual(tail(4), [{ x: 2, y: 4, z: 0 }]);
  assert.equal(MG.cycle(dot), 4);
  for (const id of ["graph", "tree", "pointers"]) assert.equal(MG.cycle(scene(demos[id])), null, id);
});

test("timeline: spring settles exactly", () => {
  assert.equal(MG.spring(0), 0);
  assert.equal(MG.spring(1.2), 1);
  assert.equal(MG.spring(10), 1);
  assert.ok(MG.spring(0.4) > 1);
});

function mgDemos() {
  const src = fs.readFileSync(path.join(REPO_ROOT, "Sources", "MartyGraphics", "MGFixtures.swift"), "utf8");
  return [...src.matchAll(/\.init\(id: "([a-z_0-9]+)", title: "[^"]*", json: #"(.*?)"#\)/g)].map((m) => ({ id: m[1], json: m[2] }));
}

// MARK: narration and step counts printed in the Swift captures (docs/assets/native, last step of each card)

test("templates and steps: the last-step caption and step count of every Showcase capture", () => {
  const captions = {
    "tree.json": [4, "8 = 8. Found it in 3 comparisons."],
    "two-pointers.json": [4, "5 + 9 = 14. Found the pair."],
    "handoff.json": [3, "A worker takes the message from the queue."],
    "function.json": [1, "Seven supplied points sketch y = x squared. The engine draws the data; it does not solve the function."],
    "counts.json": [1, "Beta is the largest of these invented counts: 30 items. No real user or business data is shown."],
    "motion.json": [1, "The marker travels from A to B in two seconds, then returns. This is a geometric animation, not a physics simulation."],
    "shortest-path.json": [8, "The shortest path 0→2→1→3→4→5 costs 13."],
  };
  for (const [name, [count, say]] of Object.entries(captions)) {
    const s = MG.parseSceneBytes(showcase(name), { packs: ["graphs"] });
    assert.equal(s.steps.length, count, name);
    assert.equal(s.steps.at(-1).say, say, name);
  }
});

// MARK: graph pack (RecordParamsShortestPathTests, ProtocolFixtureTests)

const routerLatency = '{"v":1,"template":"shortest_path","params":{"n":6,"source":0,"target":5,' +
  '"edges":[[0,1,4],[0,2,1],[2,1,2],[1,3,5],[2,3,8],[2,4,10],[3,4,2],[3,5,6],[4,5,3]],' +
  '"at":[[1.5,5],[4.5,7],[4.5,3],[7.5,7],[7.5,3],[10.5,5]]},"title":"Router latency (ms)"}';

test("graph pack: documentation fixtures narrate and patch as the Swift tests pin", () => {
  assert.equal(reason(() => MG.parseSceneBytes(fixture("shortest-path.scene.json"))), "template.unknown");
  const s = MG.parseSceneBytes(fixture("shortest-path.scene.json"), { packs: ["graphs"] });
  assert.equal(s.steps[2].say, "Settle 1 at 2, the closest unsettled node. 1→2: 2+2=4 ties 4, earlier route kept.");
  assert.equal(s.steps.at(-1).say, "A shortest path 0→2 costs 4. 2 routes tie at 4; the one found first is shown.");
  const edges = MG.applyPatch(s, MG.parsePatchBytes(fixture("shortest-path-edges.patch.json")));
  assert.equal(edges.steps.at(-1).say, "The shortest path 0→1→2 costs 3.");
  assert.equal(edges.revision, 1);
  assert.equal(reason(() => MG.applyPatch(s, MG.parsePatchBytes(fixture("shortest-path-null.patch.json")))), "template.target");
});

test("graph pack: what-if patches recompute the walkthrough or are refused whole", () => {
  const s = scene(routerLatency, ["graphs"]);
  const slower = '{"edges":[[0,1,4],[0,2,1],[2,1,2],[1,3,5],[2,3,8],[2,4,10],[3,4,9],[3,5,6],[4,5,3]]}';
  const next = applyParams(s, slower, 0);
  assert.equal(next.revision, 1);
  assert.equal(next.steps.at(-1).say, "A shortest path 0→2→1→3→5 costs 14. 2 routes tie at 14; the one found first is shown.");
  assert.deepEqual(lastBoard(next).get("dist").list, ["0", "3", "1", "8", "11", "14"]);
  assert.equal(next.title, "Router latency (ms)");
  assert.equal(reason(() => applyParams(s, '{"edges":[[0,1,-4]]}')), "template.edges.w");
  assert.equal(reason(() => applyParams(next, slower, 0)), "patch.stale");
  assert.deepEqual(lastBoard(s).get("dist").list, ["0", "3", "1", "8", "10", "13"]);

  const one = applyParams(s, '{"edges":[[0,5,7]]}');
  assert.deepEqual(one.items.filter((i) => i.kind === "edge").map((i) => i.id), ["e0_5"]);
  assert.equal(one.values.cost.value, 7);
  assert.deepEqual(one.items.find((i) => i.id === "n5").pts[0], { x: 10.5, y: 5, z: 0 });
  assert.equal(reason(() => applyParams(s, '{"at":null}')), "template.at");
  assert.equal(reason(() => applyParams(s, '{"target":null}')), "template.target");
  const auto = applyParams(s, '{"at":[]}');
  const n0 = auto.items.find((i) => i.id === "n0").pts[0];
  assert.ok(Math.abs(n0.x - 6) < 1e-9 && Math.abs(n0.y - 7.4) < 1e-9);
  assert.equal(auto.values.cost.value, 13);
  assert.equal(auto.source.params.target, 5);

  const cut = '{"edges":[[0,1,4],[0,2,1],[2,1,2],[1,3,5],[2,3,8],[2,4,10],[3,4,2]]}';
  const quoted = scene(routerLatency.replace('"title":"Router latency (ms)"', '"title":"Best {cost} ms over {routes} route(s)"'), ["graphs"]);
  assert.equal(quoted.title, "Best 13 ms over 1 route(s)");
  assert.equal(reason(() => applyParams(quoted, cut, 0)), "title.placeholder.cost");
  const plain = applyParams(s, cut, 0);
  assert.equal(plain.steps.at(-1).say, "Node 5 is unreachable from 0: no path exists.");
  assert.equal(plain.values.cost, undefined);
  assert.equal(plain.values.routes, undefined);
  assert.equal(lastBoard(plain).get("n5").color, "muted");
});

test("graph pack: final distances match an independent Bellman-Ford oracle on 60 seeded random graphs", () => {
  let seed = 20261126;
  const rand = (n) => {
    seed = (Math.imul(seed, 1103515245) + 12345) >>> 0;
    return seed % n;
  };
  let checked = 0;
  for (let k = 0; k < 60; k++) {
    const n = 2 + rand(7);
    const directed = rand(3) === 0;
    const pairs = new Set();
    const edges = [];
    for (let e = 0; e < 1 + rand(Math.min(16, (n * (n - 1)) / 2)); e++) {
      const a = rand(n), b = rand(n);
      if (a === b || pairs.has(`${Math.min(a, b)},${Math.max(a, b)}`)) continue;
      pairs.add(`${Math.min(a, b)},${Math.max(a, b)}`);
      edges.push([a, b, rand(10)]);
    }
    if (!edges.length) continue;
    const s = scene(`{"v":1,"template":"shortest_path","params":{"n":${n},"edges":${JSON.stringify(edges)},"directed":${directed ? 1 : 0}}}`, ["graphs"]);
    const d = new Array(n).fill(null);
    d[0] = 0;
    for (let round = 0; round < n; round++) {
      for (const [a, b, w] of edges) {
        for (const [u, v] of directed ? [[a, b]] : [[a, b], [b, a]]) if (d[u] !== null && (d[v] === null || d[u] + w < d[v])) d[v] = d[u] + w;
      }
    }
    assert.deepEqual(lastBoard(s).get("dist").list, d.map((x) => (x === null ? "∞" : String(x))), JSON.stringify({ n, edges, directed }));
    checked++;
  }
  assert.ok(checked >= 40);
});

// MARK: patches (ProtocolFixtureTests, TemplateExtensionTests)

test("patches: the title fixture advances the revision once and is stale after", () => {
  const s = MG.parseSceneBytes(fixture("scene.json"));
  const p = MG.parsePatchBytes(fixture("title.patch.json"));
  const updated = MG.applyPatch(s, p);
  assert.equal(updated.title, "Synthetic dot");
  assert.equal(updated.revision, 1);
  assert.equal(s.revision, 0);
  assert.equal(reason(() => MG.applyPatch(updated, p)), "patch.stale");
});

test("patches: every MGFixtures.patches entry applies to its fixture", () => {
  const src = fs.readFileSync(path.join(REPO_ROOT, "Sources", "MartyGraphics", "MGFixtures.swift"), "utf8");
  const patches = [...src.matchAll(/\.init\(id: "([a-z_0-9]+)", scene: "([a-z_0-9]+)", ask: "[^"]*",\s*json: #"(.*?)"#\)/g)];
  assert.equal(patches.length, 6);
  const demos = Object.fromEntries(mgDemos().map((d) => [d.id, d.json]));
  for (const [, id, base, json] of patches) {
    const next = MG.applyPatch(scene(demos[base]), MG.parsePatchBytes(enc(json)));
    assert.equal(next.revision, 1, id);
  }
});

test("the table-region-code fixture equals the built-in `cells` demo", () => {
  const s = MG.parseSceneBytes(fixture("table-region-code.scene.json"));
  assert.deepEqual(s.items.map((i) => i.kind), ["region", "table", "text", "text"]);
  assert.equal(s.items.find((i) => i.id === "line2").text, "    i += 1");
  const demos = Object.fromEntries(mgDemos().map((d) => [d.id, d.json]));
  assert.deepEqual(scene(demos.cells).items, s.items);
});

// MARK: wire round trip

test("every kind round-trips through its wire form, in 2D and 3D", () => {
  for (const json of [R.allKinds, R.allKinds3D]) {
    const s = scene(json);
    const ctx = { width: s.width, height: s.height, is3D: s.is3D, values: s.values };
    for (const item of s.items) assert.deepEqual(MG.item(MG.wire(item), ctx), item, item.id);
  }
  assert.deepEqual(new Set(scene(R.allKinds).items.map((i) => i.kind)), new Set(MG.KINDS));
  assert.equal(MG.KINDS.length, 19);
  assert.equal(MG.COLOR_ROLES.length, 22);
});

// MARK: render request scope

test("a refused render request does not change the shadow calibration of later renders", async () => {
  const { pathToFileURL } = await import("node:url");
  const browser = await import(pathToFileURL(path.join(REPO_ROOT, "tools", "web-renderer", "dist", "browser.js")).href);
  const gfx = await import(pathToFileURL(path.join(REPO_ROOT, "tools", "web-renderer", "dist", "gfx.js")).href);
  const before = gfx.SHADOW_BLUR_PER_RADIUS;
  assert.equal(before, 2);
  const refused = browser.render({}, { scene: fixture("unknown-key.scene.json").toString("utf8"), width: 760, height: 440, shadowBlurPerRadius: 0.25 });
  assert.equal(refused.ok, false);
  assert.equal(gfx.SHADOW_BLUR_PER_RADIUS, before);
});
