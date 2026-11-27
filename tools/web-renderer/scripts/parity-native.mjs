// SPDX-License-Identifier: Apache-2.0
// Parity against the Swift-rendered references in docs/assets/native (provenance.json there): the seven Showcase
// stills (last step, time 1 s) and every frame of the three Showcase GIFs (two-pointers: one frame per step;
// shortest-path: one per step; motion: step 0 at t = frame/8 s). The Swift capture wraps each 760×440 board in a
// SwiftUI card; the board is located from the background colour alone, cropped, and compared with this renderer's
// 760×440 output using tolerant pixel and structure metrics (web/pixels.js). Nothing here claims pixel parity.
//
//   node scripts/parity-native.mjs [--out DIR] [--shadow K] [--calibrate]

import fs from "node:fs";
import path from "node:path";
import { ORIGIN, PACKAGE_ROOT, REPO_ROOT, openRenderer } from "./browser.mjs";

const args = process.argv.slice(2);
const flag = (name) => args.includes(name);
const option = (name, fallback) => {
  const i = args.indexOf(name);
  return i >= 0 && i + 1 < args.length ? args[i + 1] : fallback;
};
const OUT = path.resolve(option("--out", path.join(PACKAGE_ROOT, "out", "parity")));
const SHOWCASE = path.join(REPO_ROOT, "Examples", "Showcase", "Sources", "MartyShowcase", "Scenes");
const SCENES = ["tree", "two-pointers", "handoff", "function", "counts", "motion", "shortest-path"];

/**
 * Pass thresholds (README "Parity"). A first per-colour centroid criterion was dropped after the first run: colours
 * shared by text, dashes and shapes moved their centroids by font and dash differences, not by geometry. Per-colour
 * counts stay in the report as information; local geometry is judged by tile alignment instead.
 */
export const TOLERANCE = {
  meanAbsError: 6,
  recallWithin2px: 0.95,
  precisionWithin2px: 0.95,
  tilesWithin2px: 0.9,
};

function cases() {
  const out = [];
  for (const id of SCENES) out.push({ id: `${id}.png`, scene: id, reference: `${id}.png`, frame: 0, step: "last", time: 1 });
  for (let f = 0; f < 4; f++) out.push({ id: `two-pointers.gif#${f}`, scene: "two-pointers", reference: "two-pointers.gif", frame: f, step: f, time: 0 });
  for (let f = 0; f < 8; f++) out.push({ id: `shortest-path.gif#${f}`, scene: "shortest-path", reference: "shortest-path.gif", frame: f, step: f, time: 0 });
  for (let f = 0; f < 32; f++) out.push({ id: `motion.gif#${f}`, scene: "motion", reference: "motion.gif", frame: f, step: 0, time: f / 8 });
  // overview.png: the same seven scenes on 500×270 boards (a second viewport scale), last step at t = 1 s.
  SCENES.forEach((id, k) => out.push({ id: `overview.png#${id}`, scene: id, reference: "overview.png", frame: 0, step: "last", time: 1, size: [500, 270], boardIndex: k }));
  return out;
}

export function verdict(m) {
  const t = TOLERANCE;
  const pass = m.meanAbsError <= t.meanAbsError && m.foreground.recallWithin2px >= t.recallWithin2px &&
    m.foreground.precisionWithin2px >= t.precisionWithin2px && m.tiles.within2px >= t.tilesWithin2px;
  return { pass };
}

async function run(session, list, shadow, write) {
  const results = [];
  for (const c of list) {
    const scene = fs.readFileSync(path.join(SHOWCASE, `${c.scene}.json`), "utf8");
    const r = await session.page.evaluate(async ({ origin, c, scene, shadow, write }) => {
      const PX = window.MGPixels;
      window.__refs ??= {};
      window.__refs[c.reference] ??= await PX.decodeFrames(`${origin}/docs/assets/native/${c.reference}`);
      const ref = window.__refs[c.reference][c.frame];
      const [w, h] = c.size ?? [760, 440];
      const board = c.boardIndex === undefined ? PX.findBoard(ref, w, h) : PX.findBoards(ref, w, h, [56 + w / 2, 616 + w / 2])[c.boardIndex];
      if (!board) return { error: "board not found" };
      const native = PX.crop(ref, board.x, board.y, w, h);
      const canvas = document.createElement("canvas");
      const res = window.MGWeb.MG.render(canvas, { scene, packs: ["graphs"], step: c.step, time: c.time, width: w, height: h, scale: 1, shadowBlurPerRadius: shadow });
      if (!res.ok) return { error: res.reason };
      const ours = canvas.getContext("2d").getImageData(0, 0, w, h);
      // The focus ring's box (bounds of the focus item, grown by 8 pt), so its dash-phase tiles are reported apart.
      const MG = window.MGWeb.MG;
      const prepared = MG.prepareFrame(MG.loadScene(new TextEncoder().encode(scene), [], { packs: ["graphs"] }), { step: c.step, time: c.time, width: w, height: h });
      const target = prepared.input.items.find((i) => i.id === prepared.input.focus);
      const fr = target ? MG.bounds(target, prepared.input.items, prepared.input.viewport) : null;
      const ring = fr ? { x: fr.x - 8, y: fr.y - 8, w: fr.w + 16, h: fr.h + 16 } : null;
      const metrics = PX.compare(native, ours, ring);
      const images = write ? { native: PX.toPNGDataURL(native), ours: canvas.toDataURL("image/png"), diff: PX.toPNGDataURL(PX.diffImage(native, ours)) } : null;
      return { board, metrics, images };
    }, { origin: ORIGIN, c, scene, shadow, write });
    if (r.error) throw new Error(`${c.id}: ${r.error}`);
    const v = verdict(r.metrics);
    results.push({ ...c, board: r.board, ...v, metrics: r.metrics });
    if (write) {
      const base = c.id.replace(/[#.]/g, "_").replace(/-/g, "-");
      for (const kind of ["native", "ours", "diff"]) {
        fs.writeFileSync(path.join(OUT, `${base}-${kind}.png`), Buffer.from(r.images[kind].split(",")[1], "base64"));
      }
    }
  }
  return results;
}

const session = await openRenderer();
try {
  fs.mkdirSync(OUT, { recursive: true });
  if (flag("--calibrate")) {
    const stills = cases().filter((c) => c.reference.endsWith(".png"));
    const rows = [];
    for (const k of [0, 0.5, 0.75, 1, 1.25, 1.5, 2, 2.5]) {
      const res = await run(session, stills, k, false);
      const mae = res.reduce((s, r) => s + r.metrics.meanAbsError, 0) / res.length;
      rows.push({ shadowBlurPerRadius: k, meanAbsError: +mae.toFixed(4), perScene: Object.fromEntries(res.map((r) => [r.scene, r.metrics.meanAbsError])) });
    }
    console.log(JSON.stringify(rows, null, 1));
    fs.writeFileSync(path.join(OUT, "shadow-calibration.json"), JSON.stringify(rows, null, 1) + "\n");
  } else {
    const shadow = option("--shadow", undefined) === undefined ? undefined : Number(option("--shadow"));
    const results = await run(session, cases(), shadow, true);
    const summary = {
      cases: results.length,
      passed: results.filter((r) => r.pass).length,
      byReference: Object.fromEntries([...new Set(results.map((r) => r.reference))].map((ref) => {
        const rs = results.filter((r) => r.reference === ref);
        return [ref, {
          frames: rs.length, passed: rs.filter((r) => r.pass).length,
          worstMeanAbsError: Math.max(...rs.map((r) => r.metrics.meanAbsError)),
          worstRecallWithin2px: Math.min(...rs.map((r) => r.metrics.foreground.recallWithin2px)),
          worstPrecisionWithin2px: Math.min(...rs.map((r) => r.metrics.foreground.precisionWithin2px)),
          worstTilesWithin1px: Math.min(...rs.map((r) => r.metrics.tiles.within1px)),
          worstTilesWithin2px: Math.min(...rs.map((r) => r.metrics.tiles.within2px)),
          largestTileShiftPx: Math.max(...rs.map((r) => r.metrics.tiles.maxShift)),
          focusRingTiles: rs.reduce((n, r) => n + r.metrics.tiles.focusRingTiles, 0),
          worstFocusRingWithin2px: Math.min(...rs.map((r) => r.metrics.tiles.focusRingWithin2px)),
        }];
      })),
    };
    const report = {
      generated: new Date().toISOString(),
      references: "docs/assets/native (Swift MGCanvasRenderer via SwiftUI ImageRenderer, scale 1; see provenance.json)",
      tolerance: TOLERANCE,
      browser: await session.page.evaluate(() => navigator.userAgent),
      summary,
      results,
    };
    fs.writeFileSync(path.join(OUT, "report.json"), JSON.stringify(report, null, 1) + "\n");
    console.log(JSON.stringify(summary, null, 1));
    for (const r of results.filter((x) => !x.pass)) console.log("FAIL", r.id, JSON.stringify(r.metrics));
  }
} finally {
  await session.close();
}
