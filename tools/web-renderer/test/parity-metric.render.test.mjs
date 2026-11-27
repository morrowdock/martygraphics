// SPDX-License-Identifier: Apache-2.0
// The parity metric itself (web/pixels.js measureFrame and verdict, shared by scripts/parity-native.mjs and
// scripts/contact-sheet.mjs): unchanged Showcase scenes pass against their Swift captures, the negative controls of
// scripts/parity-cases.mjs (a small item removed, a label changed) fail, and missing evidence (no judged tiles, an
// empty mask) is a failure rather than 100%. Also: a shadow-calibration override applies to one render only.

import assert from "node:assert/strict";
import { after, before, test } from "node:test";
import { ORIGIN, openRenderer } from "../scripts/browser.mjs";
import { negativeControls, sceneText } from "../scripts/parity-cases.mjs";
import { TOLERANCE, verdict } from "../web/pixels.js";

let session;
before(async () => {
  session = await openRenderer();
});
after(async () => {
  await session?.close();
});

const measure = (c, text) => session.page.evaluate(({ req }) => window.MGPixels.measureFrame(window.MGWeb.MG, req), {
  req: { origin: ORIGIN, scene: text, packs: ["graphs"], step: c.step, time: c.time, size: c.size, reference: { file: c.reference, frame: c.frame, boardIndex: c.boardIndex } },
});

for (const c of negativeControls()) {
  test(`unchanged ${c.scene} passes against ${c.reference}`, async () => {
    const r = await measure(c, sceneText(c.scene));
    assert.ok(!r.error, r.error);
    assert.deepEqual(r.verdict, { pass: true, failures: [] });
  });
  test(`negative control fails: ${c.scene} with ${c.what}`, async () => {
    const r = await measure(c, c.text);
    assert.ok(!r.error, r.error);
    assert.equal(r.verdict.pass, false, `${c.id} passed the metric`);
    assert.ok(r.metrics.tiles.unmatched.length > 0, "the changed tile is reported as unmatched");
  });
}

const metrics = (over = {}) => ({
  meanAbsError: 1, foreground: { recallWithin2px: 1, precisionWithin2px: 1 },
  tiles: { tiles: 10, within2px: 1, unmatched: [] }, ...over,
});

test("verdict: complete metrics within tolerance pass; each missing value fails", () => {
  assert.deepEqual(verdict(metrics()), { pass: true, failures: [] });
  assert.deepEqual(verdict(metrics({ tiles: { tiles: 0, within2px: null, unmatched: [] } })).failures, ["no judged tiles"]);
  assert.deepEqual(verdict(metrics({ foreground: { recallWithin2px: null, precisionWithin2px: 1 } })).failures, ["reference has no drawn content"]);
  assert.deepEqual(verdict(metrics({ foreground: { recallWithin2px: 1, precisionWithin2px: null } })).failures, ["nothing drawn"]);
  assert.equal(verdict(metrics({ meanAbsError: Number.NaN })).pass, false);
  const low = { x: 32, y: 64, score: TOLERANCE.minTileScore - 0.01 };
  assert.equal(verdict(metrics({ tiles: { tiles: 10, within2px: 0.9, unmatched: [low] } })).pass, false);
});

test("two empty boards have no judged tiles and no content, so they fail instead of scoring 100%", async () => {
  const r = await session.page.evaluate(() => {
    const PX = window.MGPixels;
    // The bare board gradient (MGTheme.board top #111A33 to bottom #0A0F1F), with nothing drawn on it.
    const img = new ImageData(760, 440);
    for (let y = 0; y < 440; y++) {
      const t = y / 439;
      for (let x = 0; x < 760; x++) {
        const i = (y * 760 + x) * 4;
        img.data[i] = 17 + (10 - 17) * t;
        img.data[i + 1] = 26 + (15 - 26) * t;
        img.data[i + 2] = 51 + (31 - 51) * t;
        img.data[i + 3] = 255;
      }
    }
    const m = PX.compare(img, img);
    return { tiles: m.tiles.tiles, within2px: m.tiles.within2px, recall: m.foreground.recallWithin2px, verdict: PX.verdict(m) };
  });
  assert.equal(r.tiles, 0);
  assert.equal(r.within2px, null);
  assert.equal(r.recall, null);
  assert.equal(r.verdict.pass, false);
  assert.ok(r.verdict.failures.includes("no judged tiles"));
});

test("a shadow-calibration override applies to its own render only, drawn or refused", async () => {
  const handoff = sceneText("handoff");
  const r = await session.page.evaluate(({ scene }) => {
    const draw = (extra) => window.MGWeb.render({ scene, step: "last", time: 1, width: 760, height: 440, scale: 1, ...extra });
    const base = draw({}).png;
    const overridden = draw({ shadowBlurPerRadius: 0 }).png;
    const afterOverride = draw({}).png;
    const refused = window.MGWeb.render({ scene: '{"v":1,"items":[],"nope":1}', width: 760, height: 440, shadowBlurPerRadius: 0 });
    const afterRefusal = draw({}).png;
    return { overrideChanged: overridden !== base, sameAfterOverride: afterOverride === base, refused: refused.ok === false, sameAfterRefusal: afterRefusal === base };
  }, { scene: handoff });
  assert.deepEqual(r, { overrideChanged: true, sameAfterOverride: true, refused: true, sameAfterRefusal: true });
});
