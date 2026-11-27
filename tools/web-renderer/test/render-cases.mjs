// SPDX-License-Identifier: Apache-2.0
// Every frame the snapshot tests and the contact sheet render: each fixture and Showcase scene at every step, the
// built-in demos and regression scenes, and the patch fixtures applied to their scenes. Inputs that are refused, or
// that are not 2D scenes, are listed with the reason instead.

import fs from "node:fs";
import path from "node:path";
import { REPO_ROOT, mgFixtureDemos, regressionFixtures } from "./corpus.mjs";
import { MG } from "./helpers.mjs";

const fx = (n) => fs.readFileSync(path.join(REPO_ROOT, "docs", "fixtures", "v1", n));
const sc = (n) => fs.readFileSync(path.join(REPO_ROOT, "Examples", "Showcase", "Sources", "MartyShowcase", "Scenes", n));
const branch = (n) => fs.readFileSync(path.join(REPO_ROOT, "tools", "web-renderer", "test", "corpus", "schema-branch", n));

/**
 * Native Swift captures (docs/assets/native): stills are the last step at t = 1 s; GIF frames per provenance;
 * overview.png holds the same seven scenes on 500×270 boards (index = card order).
 */
const REFERENCES = {
  "showcase/tree": { still: "tree.png", overview: 0 },
  "showcase/two-pointers": { still: "two-pointers.png", overview: 1, gif: "two-pointers.gif", gifFrame: (step) => step },
  "showcase/handoff": { still: "handoff.png", overview: 2 },
  "showcase/function": { still: "function.png", overview: 3 },
  "showcase/counts": { still: "counts.png", overview: 4 },
  "showcase/motion": { still: "motion.png", overview: 5, gif: "motion.gif", gifFrame: () => 0, gifPerSecond: 8 },
  "showcase/shortest-path": { still: "shortest-path.png", overview: 6, gif: "shortest-path.gif", gifFrame: (step) => step },
};

export function renderSources() {
  const demos = Object.fromEntries(mgFixtureDemos().map((d) => [d.id, Buffer.from(d.json, "utf8")]));
  const reg = regressionFixtures();
  const sources = [
    ...["tree", "two-pointers", "handoff", "function", "counts", "motion", "shortest-path"].map((n) => ({ name: `showcase/${n}`, scene: sc(`${n}.json`), packs: ["graphs"] })),
    { name: "fixtures/scene", scene: fx("scene.json") },
    { name: "fixtures/scene+title.patch", scene: fx("scene.json"), patches: [fx("title.patch.json")] },
    { name: "fixtures/table-region-code", scene: fx("table-region-code.scene.json") },
    { name: "fixtures/shortest-path", scene: fx("shortest-path.scene.json"), packs: ["graphs"] },
    { name: "fixtures/shortest-path+edges.patch", scene: fx("shortest-path.scene.json"), packs: ["graphs"], patches: [fx("shortest-path-edges.patch.json")] },
    { name: "fixtures/shortest-path+null.patch", scene: fx("shortest-path.scene.json"), packs: ["graphs"], patches: [fx("shortest-path-null.patch.json")] },
    { name: "fixtures/highlight-cycle", scene: fx("highlight-cycle.scene.json") },
    { name: "fixtures/unknown-key", scene: fx("unknown-key.scene.json") },
    { name: "fixtures/rotation.lesson", scene: fx("rotation.lesson.json"), note: "lesson protocol (MGLesson), not a scene" },
    { name: "fixtures/rotation.statements", scene: fx("rotation.statements.ndjson"), note: "statement stream (NDJSON), not a scene" },
    { name: "fixtures/explainer-mixed.statements", scene: fx("explainer-mixed.statements.ndjson"), note: "explainer statement stream (3D solid + board), not a scene" },
    { name: "schema-branch/math-label", scene: branch("math-label.scene.json") },
    { name: "schema-branch/studio-draft", scene: branch("studio-draft.json") },
    ...["moving_dot", "graph", "tree", "pointers", "dot_3d", "cells"].map((id) => ({ name: `demo/${id}`, scene: demos[id] })),
    ...["allKinds", "timeline", "glide", "edgeFirst", "tricky", "patchBase", "twoPointers", "singleNodeTree"].map((k) => ({ name: `regression/${k}`, scene: Buffer.from(reg[k], "utf8") })),
  ];
  return sources;
}

/** Frames to render, plus refused sources with their reasons. */
export function renderCases() {
  const frames = [];
  const refused = [];
  for (const src of renderSources()) {
    let scene;
    try {
      scene = MG.loadScene(src.scene, src.patches ?? [], { packs: src.packs ?? [] });
    } catch (e) {
      refused.push({ name: src.name, reason: e.reason ?? String(e), note: src.note });
      continue;
    }
    if (scene.is3D) {
      refused.push({ name: src.name, reason: "render.3d.unsupported", note: "valid 3D scene; this prototype draws 2D only" });
      continue;
    }
    const steps = scene.steps.length ? scene.steps.map((_, i) => i) : [0];
    const ref = REFERENCES[src.name];
    for (const step of steps) {
      frames.push({
        name: `${src.name}@step${step}`, source: src, step, time: 0, title: scene.title, say: scene.steps[step]?.say ?? "",
        reference: ref?.gif ? { file: ref.gif, frame: ref.gifFrame(step), time: 0 } : undefined,
      });
    }
    if (ref?.still) {
      const last = steps[steps.length - 1];
      frames.push({ name: `${src.name}@last-t1`, source: src, step: last, time: 1, title: scene.title, say: scene.steps[last]?.say ?? "", reference: { file: ref.still, frame: 0, time: 1 } });
      frames.push({ name: `${src.name}@last-t1-500x270`, source: src, step: last, time: 1, size: [500, 270], title: scene.title, say: scene.steps[last]?.say ?? "", reference: { file: "overview.png", frame: 0, time: 1, boardIndex: ref.overview } });
    }
    if (src.name === "showcase/motion" || src.name === "demo/moving_dot") {
      for (const t of [0.5, 1.5, 2.5]) {
        const reference = ref?.gifPerSecond ? { file: ref.gif, frame: t * ref.gifPerSecond, time: t } : undefined;
        frames.push({ name: `${src.name}@t${t}`, source: src, step: 0, time: t, title: scene.title, say: scene.steps[0]?.say ?? "", reference });
      }
    }
  }
  return { frames, refused };
}
