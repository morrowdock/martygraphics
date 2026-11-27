// SPDX-License-Identifier: Apache-2.0
// Parity against the Swift-rendered references in docs/assets/native (provenance.json there): the frames of
// scripts/parity-cases.mjs (seven stills, every frame of the three Showcase GIFs, the seven 500×270 overview boards).
// The Swift capture wraps each board in a SwiftUI card; the board is located from the background colour alone,
// cropped, and compared with this renderer's output by `MGPixels.measureFrame` and judged by `verdict`
// (web/pixels.js), the same metric and rule the contact sheet uses. The negative controls must fail; the script exits
// 1 if one passes. Nothing here claims pixel parity.
//
//   node scripts/parity-native.mjs [--out DIR] [--shadow K] [--calibrate]

import fs from "node:fs";
import path from "node:path";
import { TOLERANCE } from "../web/pixels.js";
import { ORIGIN, PACKAGE_ROOT, openRenderer } from "./browser.mjs";
import { negativeControls, parityCases, sceneText } from "./parity-cases.mjs";

const args = process.argv.slice(2);
const flag = (name) => args.includes(name);
const option = (name, fallback) => {
  const i = args.indexOf(name);
  return i >= 0 && i + 1 < args.length ? args[i + 1] : fallback;
};
const OUT = path.resolve(option("--out", path.join(PACKAGE_ROOT, "out", "parity")));

/** Measures each case in the page. `c.text` overrides the Showcase scene text (negative controls). */
async function run(session, list, shadow, write) {
  const results = [];
  for (const c of list) {
    const r = await session.page.evaluate(({ req }) => window.MGPixels.measureFrame(window.MGWeb.MG, req), {
      req: { origin: ORIGIN, scene: c.text ?? sceneText(c.scene), packs: ["graphs"], step: c.step, time: c.time, size: c.size,
        reference: { file: c.reference, frame: c.frame, boardIndex: c.boardIndex }, shadowBlurPerRadius: shadow, images: write },
    });
    if (r.error) throw new Error(`${c.id}: ${r.error}`);
    const { text, ...meta } = c;
    results.push({ ...meta, board: r.board, pass: r.verdict.pass, failures: r.verdict.failures, metrics: r.metrics });
    if (write) {
      const base = c.id.replace(/[#.:]/g, "_");
      for (const kind of ["native", "ours", "diff"]) {
        fs.writeFileSync(path.join(OUT, `${base}-${kind}.png`), Buffer.from(r.images[kind].split(",")[1], "base64"));
      }
    }
  }
  return results;
}

const finite = (xs) => xs.filter((x) => x !== null && x !== undefined);

const session = await openRenderer();
let exitCode = 0;
try {
  fs.mkdirSync(OUT, { recursive: true });
  if (flag("--calibrate")) {
    // Every PNG board: the seven stills and the seven 500×270 overview boards (14), keyed by frame id.
    const boards = parityCases().filter((c) => c.reference.endsWith(".png"));
    const rows = [];
    for (const k of [0, 0.5, 0.75, 1, 1.25, 1.5, 2, 2.5]) {
      const res = await run(session, boards, k, false);
      const mae = res.reduce((s, r) => s + r.metrics.meanAbsError, 0) / res.length;
      rows.push({ shadowBlurPerRadius: k, boards: res.length, meanAbsError: +mae.toFixed(4), perFrame: Object.fromEntries(res.map((r) => [r.id, r.metrics.meanAbsError])) });
    }
    console.log(JSON.stringify(rows, null, 1));
    fs.writeFileSync(path.join(OUT, "shadow-calibration.json"), JSON.stringify(rows, null, 1) + "\n");
  } else {
    const shadow = option("--shadow", undefined) === undefined ? undefined : Number(option("--shadow"));
    const results = await run(session, parityCases(), shadow, true);
    const controls = await run(session, negativeControls(), shadow, true);
    const summary = {
      cases: results.length,
      passed: results.filter((r) => r.pass).length,
      negativeControls: controls.length,
      negativeControlsFailed: controls.filter((r) => !r.pass).length,
      byReference: Object.fromEntries([...new Set(results.map((r) => r.reference))].map((ref) => {
        const rs = results.filter((r) => r.reference === ref);
        const min = (f) => (finite(rs.map(f)).length ? Math.min(...finite(rs.map(f))) : null);
        const max = (f) => (finite(rs.map(f)).length ? Math.max(...finite(rs.map(f))) : null);
        return [ref, {
          frames: rs.length, passed: rs.filter((r) => r.pass).length,
          worstMeanAbsError: max((r) => r.metrics.meanAbsError),
          worstRecallWithin2px: min((r) => r.metrics.foreground.recallWithin2px),
          worstPrecisionWithin2px: min((r) => r.metrics.foreground.precisionWithin2px),
          judgedTiles: rs.reduce((n, r) => n + r.metrics.tiles.tiles, 0),
          worstTilesWithin1px: min((r) => r.metrics.tiles.within1px),
          worstTilesWithin2px: min((r) => r.metrics.tiles.within2px),
          worstTileScore: min((r) => r.metrics.tiles.minScore),
          largestTileShiftPx: max((r) => r.metrics.tiles.maxShift),
          focusRingTiles: rs.reduce((n, r) => n + r.metrics.tiles.focusRingTiles, 0),
          worstFocusRingWithin2px: min((r) => r.metrics.tiles.focusRingWithin2px),
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
      negativeControls: controls,
    };
    fs.writeFileSync(path.join(OUT, "report.json"), JSON.stringify(report, null, 1) + "\n");
    console.log(JSON.stringify(summary, null, 1));
    for (const r of results.filter((x) => !x.pass)) console.log("FAIL", r.id, r.failures.join("; "));
    for (const r of controls) console.log(r.pass ? "CONTROL PASSED (metric too weak)" : "control failed as required", r.id, r.failures.join("; "));
    if (controls.some((r) => r.pass)) exitCode = 1;
  }
} finally {
  await session.close();
}
process.exitCode = exitCode;
