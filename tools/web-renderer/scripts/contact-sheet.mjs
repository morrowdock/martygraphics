// SPDX-License-Identifier: Apache-2.0
// Side-by-side contact sheets for human review.
//   parity.html / parity.png   — every frame that has a Swift capture: Swift board | web board | |difference| ×4,
//                                with the metric and verdict of the parity report (web/pixels.js measureFrame, verdict)
//   gallery.html / gallery.png — every other fixture frame (all steps), plus the inputs that are refused, with reasons
// Full-size frames are written next to the sheets.
//
//   node scripts/contact-sheet.mjs [--out DIR]

import fs from "node:fs";
import path from "node:path";
import { ORIGIN, PACKAGE_ROOT, openRenderer } from "./browser.mjs";
import { renderCases } from "../test/render-cases.mjs";
import { TOLERANCE } from "../web/pixels.js";

const args = process.argv.slice(2);
const outIndex = args.indexOf("--out");
const OUT = path.resolve(outIndex >= 0 ? args[outIndex + 1] : path.join(PACKAGE_ROOT, "out", "contact-sheet"));
const FRAMES = path.join(OUT, "frames");
fs.rmSync(OUT, { recursive: true, force: true });
fs.mkdirSync(FRAMES, { recursive: true });

const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);
const slug = (s) => s.replace(/[^A-Za-z0-9_.-]+/g, "_");
const fmt = (v) => (v === null || v === undefined ? "none" : String(v));
/** "34 of 36 (94.44%), lowest match score 0.91" — a share of tiles with its count, or "no tiles". */
const tileLine = (share, n, minScore) => (n ? `${Math.round(share * n)} of ${n} (${(share * 100).toFixed(2)}%), lowest match score ${fmt(minScore)}` : "no tiles");
const write = (name, dataURL) => {
  fs.writeFileSync(path.join(FRAMES, name), Buffer.from(dataURL.slice(dataURL.indexOf(",") + 1), "base64"));
  return `frames/${name}`;
};

const { frames, refused } = renderCases();
const session = await openRenderer({ width: 1400, height: 900 });
const rows = [];
try {
  for (const f of frames) {
    const r = await session.page.evaluate(async ({ origin, f, scene, patches, packs }) => {
      const [w, h] = f.size ?? [760, 440];
      if (f.reference) {
        // The parity report's metric and verdict (web/pixels.js measureFrame), including the focus-ring exclusion.
        const m = await window.MGPixels.measureFrame(window.MGWeb.MG, { origin, scene, patches, packs, step: f.step, time: f.time, size: [w, h],
          reference: { file: f.reference.file, frame: f.reference.frame, boardIndex: f.reference.boardIndex }, images: true });
        if (m.error) return { error: m.error };
        return { web: m.images.ours, native: m.images.native, diff: m.images.diff, metrics: m.metrics, verdict: m.verdict };
      }
      const canvas = document.createElement("canvas");
      const res = window.MGWeb.MG.render(canvas, { scene, patches, packs, step: f.step, time: f.time, width: w, height: h, scale: 1 });
      if (!res.ok) return { error: res.reason };
      return { web: canvas.toDataURL("image/png") };
    }, { origin: ORIGIN, f: { step: f.step, time: f.time, reference: f.reference, size: f.size }, scene: f.source.scene.toString("utf8"),
      patches: (f.source.patches ?? []).map((p) => p.toString("utf8")), packs: f.source.packs ?? [] });
    if (r.error) throw new Error(`${f.name}: ${r.error}`);
    const base = slug(f.name);
    rows.push({ ...f, web: write(`${base}-web.png`, r.web), native: r.native && write(`${base}-swift.png`, r.native), diff: r.diff && write(`${base}-diff.png`, r.diff), metrics: r.metrics, verdict: r.verdict });
  }

  const ua = await session.page.evaluate(() => navigator.userAgent);
  const style = `
    body { margin: 0; padding: 24px; background: #05070d; color: #e6e9f2; font: 13px/1.45 "Segoe UI", -apple-system, sans-serif; }
    h1 { font-size: 20px; margin: 0 0 4px; } h2 { font-size: 15px; margin: 22px 0 8px; color: #9fb4ff; }
    p.meta { color: #8e96ad; margin: 0 0 14px; max-width: 1180px; }
    .row { display: grid; grid-template-columns: 380px 380px 380px; gap: 10px; margin: 0 0 6px; }
    .cap { color: #c9cfdf; margin: 12px 0 4px; } .cap b { color: #fff; } .cap span { color: #8e96ad; }
    img { width: 380px; display: block; border-radius: 6px; }
    .lab { color: #8e96ad; font-size: 11px; margin-top: 2px; }
    .grid { display: grid; grid-template-columns: repeat(3, 380px); gap: 14px 10px; }
    table { border-collapse: collapse; margin-top: 6px; } td { padding: 3px 10px 3px 0; color: #c9cfdf; vertical-align: top; }
    code { color: #ffd479; } .pass { color: #69f0ae; } .fail { color: #ffb74d; }`;
  const head = (title, intro) => `<!doctype html><html><head><meta charset="utf-8"><title>${esc(title)}</title><style>${style}</style></head><body>
<h1>${esc(title)}</h1><p class="meta">${intro}<br>Web renderer: MartyGraphics web prototype (tools/web-renderer), 760×440 pt boards (500×270 for overview.png), scale 1, ${esc(ua)}.<br>Generated ${new Date().toISOString()}.</p>`;

  const withRef = rows.filter((r) => r.native);
  const parity = head("MartyGraphics 2D: Swift captures vs web prototype",
    "Left: board cropped from the Swift capture in docs/assets/native (SwiftUI ImageRenderer, MGCanvasRenderer, scale 1; GIF frames are 256-colour). " +
    "Middle: this prototype, same scene, step and time. Right: |difference| ×4. Metrics and verdict are those of the parity report (web/pixels.js measureFrame and verdict): mean absolute RGB error (0–255); drawn-content recall and precision within 2 px; " +
    `judged edge tiles aligned within 2 px with a match score of at least ${TOLERANCE.minTileScore}; and, reported apart and not judged, the tiles on the dashed focus ring. ` +
    "Fonts differ (SF Pro in Swift, the browser's system font here); dashed rings differ in dash phase. This is a review aid, not a pixel-parity claim.") +
    withRef.map((r) => `<div class="cap"><b>${esc(r.name)}</b> <span class="${r.verdict.pass ? "pass" : "fail"}">${r.verdict.pass ? "within tolerance" : "outside tolerance"}</span> <span>${(r.size ?? [760, 440]).join("×")} pt · t = ${r.time} s · ${esc(r.reference.file)}${r.reference.file.endsWith(".gif") ? ` frame ${r.reference.frame}` : ""}${r.reference.boardIndex !== undefined ? ` board ${r.reference.boardIndex}` : ""}</span><br>
<span>MAE ${fmt(r.metrics.meanAbsError)} · recall ${fmt(r.metrics.foreground.recallWithin2px)} · precision ${fmt(r.metrics.foreground.precisionWithin2px)} · judged tiles aligned ≤2 px: ${tileLine(r.metrics.tiles.within2px, r.metrics.tiles.tiles, r.metrics.tiles.minScore)} · excluded focus-ring tiles ≤2 px: ${tileLine(r.metrics.tiles.focusRingWithin2px, r.metrics.tiles.focusRingTiles, r.metrics.tiles.focusRingMinScore)}</span>${r.verdict.pass ? "" : `<br><span class="fail">${esc(r.verdict.failures.join("; "))}</span>`}</div>
<div class="row"><div><img src="${r.native}"><div class="lab">Swift (native capture)</div></div><div><img src="${r.web}"><div class="lab">Web prototype</div></div><div><img src="${r.diff}"><div class="lab">|difference| ×4</div></div></div>`).join("\n") + "</body></html>";
  fs.writeFileSync(path.join(OUT, "parity.html"), parity);

  const others = rows.filter((r) => !r.native);
  const gallery = head("MartyGraphics 2D fixtures in the web prototype",
    "Every docs/fixtures/v1 scene (including patches applied to their scenes), the Showcase scenes at every step, the built-in MGFixtures demos, the RegressionFixtures scenes (allKinds draws all 19 kinds) and the schema-branch scenes. No Swift capture exists for these frames.") +
    `<div class="grid">${others.map((r) => `<div><img src="${r.web}"><div class="lab"><b>${esc(r.name)}</b>${r.time ? ` · t = ${r.time} s` : ""}${r.say ? ` · ${esc(r.say.length > 90 ? r.say.slice(0, 89) + "…" : r.say)}` : ""}</div></div>`).join("\n")}</div>` +
    `<h2>Inputs that are not drawn</h2><table>${refused.map((r) => `<tr><td><b>${esc(r.name)}</b></td><td><code>${esc(r.reason)}</code></td><td>${esc(r.note ?? "refused by the scene parser, as in Swift")}</td></tr>`).join("")}</table></body></html>`;
  fs.writeFileSync(path.join(OUT, "gallery.html"), gallery);

  for (const sheet of ["parity", "gallery"]) {
    await session.page.goto(`${ORIGIN}/${path.relative(path.resolve(PACKAGE_ROOT, "..", ".."), path.join(OUT, `${sheet}.html`)).split(path.sep).join("/")}`);
    await session.page.waitForLoadState("load");
    await session.page.screenshot({ path: path.join(OUT, `${sheet}.png`), fullPage: true });
  }
  console.log(JSON.stringify({ out: OUT, framesWithSwiftReference: withRef.length, withinTolerance: withRef.filter((r) => r.verdict.pass).length,
    outsideTolerance: withRef.filter((r) => !r.verdict.pass).map((r) => r.name), framesWithoutReference: others.length, refused: refused.length }));
} finally {
  await session.close();
}
