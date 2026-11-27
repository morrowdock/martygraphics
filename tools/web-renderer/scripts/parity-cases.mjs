// SPDX-License-Identifier: Apache-2.0
// The frames compared against the Swift captures in docs/assets/native (provenance.json there), and the negative
// controls: deliberately wrong renders of the same scenes that the metric (web/pixels.js `verdict`) must fail.
// Shared by scripts/parity-native.mjs and test/parity-metric.render.test.mjs.

import fs from "node:fs";
import path from "node:path";
import { REPO_ROOT } from "./browser.mjs";

export const SHOWCASE = path.join(REPO_ROOT, "Examples", "Showcase", "Sources", "MartyShowcase", "Scenes");
export const SCENES = ["tree", "two-pointers", "handoff", "function", "counts", "motion", "shortest-path"];

export const sceneText = (id) => fs.readFileSync(path.join(SHOWCASE, `${id}.json`), "utf8");

/**
 * The seven Showcase stills (last step, t = 1 s), every frame of the three Showcase GIFs (two-pointers and
 * shortest-path: one frame per step; motion: step 0 at t = frame/8 s) and the seven 500×270 boards of overview.png.
 * `id` is unique per frame.
 */
export function parityCases() {
  const out = [];
  for (const id of SCENES) out.push({ id: `${id}.png`, scene: id, reference: `${id}.png`, frame: 0, step: "last", time: 1 });
  for (let f = 0; f < 4; f++) out.push({ id: `two-pointers.gif#${f}`, scene: "two-pointers", reference: "two-pointers.gif", frame: f, step: f, time: 0 });
  for (let f = 0; f < 8; f++) out.push({ id: `shortest-path.gif#${f}`, scene: "shortest-path", reference: "shortest-path.gif", frame: f, step: f, time: 0 });
  for (let f = 0; f < 32; f++) out.push({ id: `motion.gif#${f}`, scene: "motion", reference: "motion.gif", frame: f, step: 0, time: f / 8 });
  // overview.png: the same seven scenes on 500×270 boards (a second viewport scale), last step at t = 1 s.
  SCENES.forEach((id, k) => out.push({ id: `overview.png#${id}`, scene: id, reference: "overview.png", frame: 0, step: "last", time: 1, size: [500, 270], boardIndex: k }));
  return out;
}

const edit = (id, change) => {
  const scene = JSON.parse(sceneText(id));
  change(scene);
  return JSON.stringify(scene);
};

/**
 * Negative controls: each renders a changed scene against the unchanged Swift capture and must FAIL the verdict.
 * They are ordinary, valid scenes (no malformed input): one drops a small item, one changes a label's text.
 */
export function negativeControls() {
  return [
    {
      id: "control:motion.png-without-B", what: "the small \"B\" text item removed", scene: "motion", reference: "motion.png", frame: 0, step: "last", time: 1,
      text: edit("motion", (s) => { s.items = s.items.filter((i) => i.id !== "end"); }),
    },
    {
      id: "control:handoff.png-label-Queue-to-Store", what: "the node label \"Queue\" changed to \"Store\"", scene: "handoff", reference: "handoff.png", frame: 0, step: "last", time: 1,
      text: edit("handoff", (s) => { s.items.find((i) => i.id === "queue").text = "Store"; }),
    },
  ];
}
