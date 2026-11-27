// SPDX-License-Identifier: Apache-2.0
// Snapshot tests of this renderer's own output (headless Chromium). Every frame of test/render-cases.mjs is drawn at
// its board size (760×440 pt, or 500×270 for the overview frames), scale 1, reduced 4× with a box filter and compared
// with test/snapshots/<frame>.png: at most 0.5% of thumbnail pixels may differ by more than 16 in any channel
// (anti-aliasing and font hinting noise).
// UPDATE_SNAPSHOTS=1 rewrites the snapshots. Snapshots were made on Windows with Playwright's Chromium; fonts differ
// on other systems, so a new platform may need its own snapshots (see README).

import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { after, before, test } from "node:test";
import { ORIGIN, openRenderer } from "../scripts/browser.mjs";
import { PACKAGE_ROOT } from "./corpus.mjs";
import { renderCases } from "./render-cases.mjs";

const SNAPSHOTS = path.join(PACKAGE_ROOT, "test", "snapshots");
const UPDATE = process.env.UPDATE_SNAPSHOTS === "1";
const slug = (s) => s.replace(/[^A-Za-z0-9_.-]+/g, "_");
let session;

before(async () => {
  session = await openRenderer();
  fs.mkdirSync(SNAPSHOTS, { recursive: true });
});
after(async () => {
  await session?.close();
});

const { frames, refused } = renderCases();

test("render cases cover every 2D kind and every Showcase step", () => {
  assert.ok(frames.length >= 70, `${frames.length} frames`);
  assert.ok(frames.some((f) => f.name === "regression/allKinds@step0"));
  assert.deepEqual(refused.map((r) => r.name).sort(), [
    "demo/dot_3d", "fixtures/explainer-mixed.statements", "fixtures/highlight-cycle", "fixtures/rotation.lesson",
    "fixtures/rotation.statements", "fixtures/shortest-path+null.patch", "fixtures/unknown-key",
  ]);
});

for (const f of frames) {
  test(`snapshot ${f.name}`, async () => {
    const file = path.join(SNAPSHOTS, `${slug(f.name)}.png`);
    const exists = fs.existsSync(file);
    const r = await session.page.evaluate(async ({ origin, f, snapshot, update }) => {
      const PX = window.MGPixels;
      const canvas = document.createElement("canvas");
      const [w, h] = f.size;
      const res = window.MGWeb.MG.render(canvas, { scene: f.scene, patches: f.patches, packs: f.packs, step: f.step, time: f.time, width: w, height: h, scale: 1 });
      if (!res.ok) return { error: res.reason };
      const thumb = PX.downscale(canvas.getContext("2d").getImageData(0, 0, w, h), 4);
      if (update || !snapshot) return { png: PX.toPNGDataURL(thumb) };
      const want = (await PX.decodeFrames(`${origin}/${snapshot}`))[0];
      return { changed: PX.changedShare(want, thumb, 16) };
    }, {
      origin: ORIGIN,
      f: { scene: f.source.scene.toString("utf8"), patches: (f.source.patches ?? []).map((p) => p.toString("utf8")), packs: f.source.packs ?? [], step: f.step, time: f.time, size: f.size ?? [760, 440] },
      snapshot: exists ? `tools/web-renderer/test/snapshots/${slug(f.name)}.png` : null,
      update: UPDATE,
    });
    assert.ok(!r.error, r.error);
    if (r.png) {
      if (!UPDATE) assert.fail(`missing snapshot ${path.relative(PACKAGE_ROOT, file)} (run with UPDATE_SNAPSHOTS=1)`);
      fs.writeFileSync(file, Buffer.from(r.png.split(",")[1], "base64"));
      return;
    }
    assert.ok(r.changed <= 0.005, `${(r.changed * 100).toFixed(2)}% of thumbnail pixels changed by more than 16`);
  });
}

test("no page errors while rendering", () => {
  assert.deepEqual(session.errors, []);
});
